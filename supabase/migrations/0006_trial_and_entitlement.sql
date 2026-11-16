-- =============================================================================
-- Zangetsu subscription — 14-day trial + device entitlement gate (Sophie)
--
-- Reuses the subscription rails the Sophie project already runs (the
-- subscription-subscribe / korapay-webhook edge functions and the
-- start_subscription_period / refresh_subscription_state / active_entitlements
-- RPCs). This migration only fills two gaps the app needs:
--
--   1. The trial is 14 days, granted once per device. start_trial checked the
--      device's trial flag but never set it, so a device could claim the trial
--      repeatedly. It now records the claim.
--   2. There was no single "may this device watch, or should we show the
--      paywall?" answer. device_entitlement computes it server-side.
--
-- A device that used its trial and never paid stays unentitled forever
-- (trial_used_at is permanent), which is the "paywall kicks in after 14 days"
-- rule. Grace is only applied to auto-renewing (paid) subs, so the trial ends
-- exactly on day 14 rather than day 17.
-- =============================================================================

-- Free trial is 14 days on the paid tiers.
update subscription_plans
   set trial_days = 14
 where key in ('stream_standard', 'stream_premium');

-- ---------------------------------------------------------------------------
-- device_entitlement: the single source of truth for "may this device watch?".
--
--   entitled        — an active/trial/grace subscription that has not lapsed
--   show_paywall    — no entitlement, so the app must surface the paywall
--   trial_available — a first-time device that has never used its trial
-- ---------------------------------------------------------------------------
create or replace function public.device_entitlement(p_fingerprint text)
returns table (
  entitled boolean,
  show_paywall boolean,
  trial_available boolean,
  trial_used boolean,
  status text,
  plan_key text,
  period_end timestamptz,
  days_left int
)
language plpgsql security definer set search_path = public as $$
declare
  v_session uuid;
  v_trial_used timestamptz;
  v_sub subscriptions%rowtype;
  v_plan subscription_plans%rowtype;
  v_grace int := 3;
  v_entitled boolean := false;
  v_status text := 'none';
begin
  if p_fingerprint is null or length(p_fingerprint) < 8 then
    raise exception 'invalid fingerprint';
  end if;

  select session_id, trial_used_at into v_session, v_trial_used
  from devices where fingerprint = p_fingerprint;

  if v_session is not null then
    select * into v_sub from subscriptions s
    where s.subscriber_session_id = v_session
    order by s.started_at desc limit 1;

    if found then
      select * into v_plan from subscription_plans where key = v_sub.plan_key;
      v_grace := coalesce(v_plan.grace_days, 3);
      v_status := v_sub.status;

      -- 'trial' is just an active subscription with auto_renew off. Entitlement
      -- is time-based. Grace applies only to auto-renewing (paid) subs, where a
      -- renewal can fail transiently — a trial gets none, so it ends on day 14.
      v_entitled := v_sub.status in ('active', 'trial', 'grace')
        and now() <= (
          v_sub.current_period_end
          + case when v_sub.auto_renew
                 then make_interval(days => v_grace)
                 else interval '0' end
        );
    end if;
  end if;

  return query select
    v_entitled,
    (not v_entitled),
    (v_trial_used is null and not v_entitled),
    (v_trial_used is not null),
    v_status,
    v_sub.plan_key,
    v_sub.current_period_end,
    case
      when v_entitled and v_sub.current_period_end is not null
        then greatest(0, ceil(extract(epoch from (v_sub.current_period_end - now())) / 86400)::int)
      else 0
    end;
end $$;

-- ---------------------------------------------------------------------------
-- start_trial: grant the one-time trial and record the claim.
-- The previous body returned a subscription id but never wrote trial_used_at,
-- so "once per device" was not actually enforced.
-- ---------------------------------------------------------------------------
create or replace function public.start_trial(
  p_fingerprint text,
  p_plan        text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_plan     subscription_plans%rowtype;
  v_session  uuid;
  v_sub_id   uuid;
  v_used     timestamptz;
begin
  select * into v_plan from subscription_plans where key = p_plan and active;
  if not found then raise exception 'unknown plan %', p_plan; end if;
  if v_plan.trial_days <= 0 then raise exception 'plan % has no trial', p_plan; end if;

  select session_id, trial_used_at into v_session, v_used
  from devices where fingerprint = p_fingerprint;
  if v_used is not null then return null; end if;

  insert into subscriptions
    (subscriber_session_id, plan_key, entitlement, status,
     current_period_start, current_period_end, auto_renew)
  values
    (coalesce(v_session, gen_random_uuid()), p_plan, v_plan.entitlement, 'active',
     now(), now() + make_interval(days => v_plan.trial_days), false)
  returning id into v_sub_id;

  update devices set trial_used_at = now() where fingerprint = p_fingerprint;

  return v_sub_id;
end $$;

-- ---------------------------------------------------------------------------
-- identify_device — extended with entitlement so the app needs one call.
-- Dropped first: the OUT columns changed, which CREATE OR REPLACE rejects.
-- ---------------------------------------------------------------------------
drop function if exists public.identify_device(text, text, text, text);

create function public.identify_device(
  p_fingerprint text,
  p_platform    text default null,
  p_model       text default null,
  p_version     text default null
) returns table (
  session_id  uuid,
  is_new      boolean,
  trial_used  boolean,
  plan_key    text,
  status      text,
  period_end  timestamptz,
  entitled    boolean,
  show_paywall boolean,
  trial_available boolean,
  days_left   int
)
language plpgsql security definer set search_path = public as $$
declare
  v_session uuid;
  v_existed boolean;
begin
  if p_fingerprint is null or length(p_fingerprint) < 8 then
    raise exception 'invalid fingerprint';
  end if;

  select up.session_id into v_session
  from user_profiles up where up.device_fingerprint = p_fingerprint;

  v_existed := v_session is not null;

  if not v_existed then
    v_session := gen_random_uuid();
    insert into user_profiles (session_id, device_fingerprint, platform,
                               app_version, device_model, display_name)
    values (v_session, p_fingerprint, p_platform, p_version, p_model, 'Guest');
  else
    update user_profiles set
      platform     = coalesce(p_platform, platform),
      app_version  = coalesce(p_version,  app_version),
      device_model = coalesce(p_model,    device_model),
      last_seen_at = now()
    where user_profiles.session_id = v_session;
  end if;

  insert into devices (fingerprint, session_id, platform, device_model, app_version)
  values (p_fingerprint, v_session, p_platform, p_model, p_version)
  on conflict (fingerprint) do update set
    session_id   = excluded.session_id,
    platform     = coalesce(excluded.platform, devices.platform),
    device_model = coalesce(excluded.device_model, devices.device_model),
    app_version  = coalesce(excluded.app_version, devices.app_version),
    last_seen_at = now();

  return query
  select v_session,
         not v_existed,
         e.trial_used,
         e.plan_key,
         e.status,
         e.period_end,
         e.entitled,
         e.show_paywall,
         e.trial_available,
         e.days_left
  from device_entitlement(p_fingerprint) e;
end $$;

-- ---------------------------------------------------------------------------
-- activate_stream_subscription: starts (or restarts) a PAID stream period.
--
-- Called by the korapay-webhook once a charge settles. This is deliberately
-- not start_subscription_period: that one adds the plan's trial days, which
-- would hand a paying subscriber another free fortnight. A paid period is
-- exactly period_days and renews automatically.
-- ---------------------------------------------------------------------------
create or replace function public.activate_stream_subscription(
  p_session   uuid,
  p_plan_key  text,
  p_reference text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  plan subscription_plans%rowtype;
  sub  subscriptions%rowtype;
  period_end timestamptz;
begin
  select * into plan from subscription_plans where key = p_plan_key;
  if not found then raise exception 'unknown plan %', p_plan_key; end if;

  period_end := now() + make_interval(days => plan.period_days);

  insert into subscriptions (
    subscriber_session_id, plan_key, entitlement, status, auto_renew,
    current_period_start, current_period_end, grace_until,
    korapay_reference, started_at, cancelled_at, expired_at, updated_at
  ) values (
    p_session, p_plan_key, plan.entitlement, 'active', true,
    now(), period_end, period_end + make_interval(days => plan.grace_days),
    p_reference, now(), null, null, now()
  )
  on conflict (subscriber_session_id, plan_key) do update
    set status = 'active',
        auto_renew = true,
        current_period_start = now(),
        current_period_end = excluded.current_period_end,
        grace_until = excluded.grace_until,
        korapay_reference = excluded.korapay_reference,
        cancelled_at = null,
        expired_at = null,
        updated_at = now()
  returning * into sub;

  insert into entitlements (
    subscriber_session_id, entitlement, active, source, subscription_id,
    expires_at, updated_at
  ) values (
    p_session, plan.entitlement, true, 'subscription', sub.id,
    sub.current_period_end, now()
  )
  on conflict (subscriber_session_id, entitlement) do update
    set active = true,
        source = 'subscription',
        subscription_id = excluded.subscription_id,
        expires_at = excluded.expires_at,
        updated_at = now();

  return jsonb_build_object(
    'ok', true, 'subscription_id', sub.id, 'plan_key', p_plan_key,
    'period_end', sub.current_period_end);
end $$;

-- ---------------------------------------------------------------------------
-- get_subscription_session: resolves a fingerprint to its device session.
-- Used by the stream-subscribe edge function, which only has the fingerprint.
-- ---------------------------------------------------------------------------
create or replace function public.get_subscription_session(p_fingerprint text)
returns uuid
language sql security definer set search_path = public as $$
  select session_id from devices where fingerprint = p_fingerprint;
$$;

-- ---------------------------------------------------------------------------
-- payments.product_type must allow the stream product. Without this the paid
-- checkout cannot record its charge (the free-promo path never inserts one).
-- ---------------------------------------------------------------------------
alter table public.payments drop constraint if exists payments_product_type_check;
alter table public.payments add constraint payments_product_type_check
  check (product_type = any (array[
    'vip_unlock', 'private_session', 'contact_reveal', 'group_session', 'tip',
    'connection_fee', 'contact_unlock',
    'subscription_vip', 'subscription_creator', 'subscription_premium',
    'subscription_stream'
  ]));
