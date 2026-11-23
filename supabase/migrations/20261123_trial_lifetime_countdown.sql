-- =============================================================================
-- Trial lifetime + countdown
--
-- 1. The free trial is recorded in an append-only claim ledger as well as on
--    the device row. Deleting or rebuilding a device row cannot hand the same
--    fingerprint a second trial.
-- 2. Subscriptions carry is_trial so the app can show a countdown for a trial
--    and never for a paid plan.
-- 3. identify_device/device_entitlement return the trial flag and the server
--    clock, so the countdown is based on server time and not a device clock
--    that can be moved backwards.
--
-- The device fingerprint is the identity. It survives an uninstall on Android
-- (ANDROID_ID) and iOS (Keychain), so reinstalling lands back on the same
-- claim row.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Trial claim ledger. RLS on, no policies: only SECURITY DEFINER functions
--    below may read or write it.
-- ---------------------------------------------------------------------------
create table if not exists public.trial_claims (
  fingerprint text primary key,
  claimed_at  timestamptz not null default now()
);

alter table public.trial_claims enable row level security;

insert into public.trial_claims (fingerprint, claimed_at)
select fingerprint, trial_used_at
from public.devices
where trial_used_at is not null
on conflict (fingerprint) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Mark trial subscriptions. Existing trial rows are the ones written at
--    the same moment as the device's trial_used_at stamp.
-- ---------------------------------------------------------------------------
alter table public.subscriptions
  add column if not exists is_trial boolean not null default false;

update public.subscriptions s
set is_trial = true
from public.devices d
where d.session_id = s.subscriber_session_id
  and d.trial_used_at is not null
  and s.auto_renew = false
  and s.started_at between d.trial_used_at - interval '5 minutes'
                       and d.trial_used_at + interval '5 minutes'
  and s.is_trial = false;

-- ---------------------------------------------------------------------------
-- 3. device_entitlement — seat-aware, blocked-aware, and trial-aware.
--
-- A seat is entitled exactly as long as its owner. A seat's own trial claim is
-- never consumed by joining a plan. is_trial follows the subscription being
-- used, so a seat on a trial owner sees the owner's remaining trial time.
-- ---------------------------------------------------------------------------
drop function if exists public.device_entitlement(text);

create function public.device_entitlement(p_fingerprint text)
returns table (
  entitled boolean,
  show_paywall boolean,
  trial_available boolean,
  trial_used boolean,
  status text,
  plan_key text,
  period_end timestamptz,
  days_left int,
  is_trial boolean,
  server_now timestamptz
)
language plpgsql security definer set search_path = public as $$
declare
  v_owner text;
  v_effective text;
  v_session uuid;
  v_trial_used timestamptz;
  v_claimed timestamptz;
  v_blocked_self boolean := false;
  v_blocked_owner boolean := false;
  v_sub subscriptions%rowtype;
  v_plan subscription_plans%rowtype;
  v_grace int := 3;
  v_entitled boolean := false;
  v_status text := 'none';
  v_is_trial boolean := false;
begin
  if p_fingerprint is null or length(p_fingerprint) < 8 then
    raise exception 'invalid fingerprint';
  end if;

  select s.owner_fingerprint into v_owner
  from public.device_seats s where s.fingerprint = p_fingerprint;

  v_effective := coalesce(v_owner, p_fingerprint);

  select d.session_id, d.blocked
    into v_session, v_blocked_self
  from public.devices d where d.fingerprint = p_fingerprint;

  if v_effective <> p_fingerprint then
    select d.blocked into v_blocked_owner
    from public.devices d where d.fingerprint = v_effective;
  end if;

  select d.trial_used_at into v_trial_used
  from public.devices d where d.fingerprint = p_fingerprint;

  select tc.claimed_at into v_claimed
  from public.trial_claims tc where tc.fingerprint = p_fingerprint;

  if coalesce(v_blocked_self, false) or coalesce(v_blocked_owner, false) then
    return query select false, true, false, true, 'blocked', null, null, 0,
                        false, now();
    return;
  end if;

  if v_session is null and v_effective <> p_fingerprint then
    select d.session_id into v_session
    from public.devices d where d.fingerprint = v_effective;
  end if;

  if v_session is not null then
    select * into v_sub from public.subscriptions s
    where s.subscriber_session_id = v_session
    order by s.started_at desc limit 1;

    if found then
      select * into v_plan
      from public.subscription_plans where key = v_sub.plan_key;
      v_grace := coalesce(v_plan.grace_days, 3);
      v_status := v_sub.status;
      v_is_trial := coalesce(v_sub.is_trial, false);

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
    ((v_trial_used is null and v_claimed is null) and not v_entitled),
    (v_trial_used is not null or v_claimed is not null),
    v_status,
    v_sub.plan_key,
    v_sub.current_period_end,
    case
      when v_entitled and v_sub.current_period_end is not null
        then greatest(0, ceil(extract(epoch from (v_sub.current_period_end - now())) / 86400)::int)
      else 0
    end,
    v_is_trial,
    now();
end $$;

grant execute on function public.device_entitlement(text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. identify_device — add is_trial + server_now to the one-call identity.
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
  days_left   int,
  is_trial    boolean,
  server_now  timestamptz
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
  from public.user_profiles up where up.device_fingerprint = p_fingerprint;

  v_existed := v_session is not null;

  if not v_existed then
    v_session := gen_random_uuid();
    insert into public.user_profiles (session_id, device_fingerprint, platform,
                                      app_version, device_model, display_name)
    values (v_session, p_fingerprint, p_platform, p_version, p_model, 'Guest');
  else
    update public.user_profiles set
      platform     = coalesce(p_platform, platform),
      app_version  = coalesce(p_version,  app_version),
      device_model = coalesce(p_model,    device_model),
      last_seen_at = now()
    where user_profiles.session_id = v_session;
  end if;

  insert into public.devices (fingerprint, session_id, platform, device_model, app_version)
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
         e.days_left,
         e.is_trial,
         e.server_now
  from public.device_entitlement(p_fingerprint) e;
end $$;

grant execute on function public.identify_device(text, text, text, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. start_trial — claim once per fingerprint, forever.
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
  v_claimed  timestamptz;
  v_blocked  boolean := false;
  v_existing subscriptions%rowtype;
begin
  if p_fingerprint is null or length(p_fingerprint) < 8 then
    raise exception 'invalid fingerprint';
  end if;

  select * into v_plan
  from subscription_plans
  where key = p_plan and active;
  if not found then raise exception 'unknown plan %', p_plan; end if;
  if v_plan.trial_days <= 0 then
    raise exception 'plan % has no trial', p_plan;
  end if;

  insert into devices (fingerprint)
  values (p_fingerprint)
  on conflict (fingerprint) do nothing;

  select session_id, trial_used_at, blocked
    into v_session, v_used, v_blocked
  from devices
  where fingerprint = p_fingerprint
  for update;

  select claimed_at into v_claimed
  from trial_claims
  where fingerprint = p_fingerprint;

  if v_blocked then raise exception 'device blocked'; end if;
  if v_used is not null or v_claimed is not null then return null; end if;

  if v_session is null then
    select session_id into v_session
    from user_profiles
    where device_fingerprint = p_fingerprint;

    if v_session is null then
      v_session := gen_random_uuid();
      insert into user_profiles (session_id, device_fingerprint, display_name)
      values (v_session, p_fingerprint, 'Guest');
    end if;

    update devices
       set session_id = v_session
     where fingerprint = p_fingerprint;
  end if;

  select * into v_existing
  from subscriptions
  where subscriber_session_id = v_session
  order by started_at desc
  limit 1;

  if found
     and v_existing.status in ('active', 'grace')
     and now() <= v_existing.current_period_end then
    return null;
  end if;

  insert into trial_claims (fingerprint, claimed_at)
  values (p_fingerprint, now())
  on conflict (fingerprint) do nothing;

  insert into subscriptions
    (subscriber_session_id, plan_key, entitlement, status,
     current_period_start, current_period_end, auto_renew, is_trial)
  values
    (v_session, p_plan, v_plan.entitlement, 'active',
     now(), now() + make_interval(days => v_plan.trial_days), false, true)
  on conflict (subscriber_session_id, plan_key) do update
    set status = 'active',
        auto_renew = false,
        is_trial = true,
        current_period_start = now(),
        current_period_end = excluded.current_period_end,
        cancelled_at = null,
        expired_at = null,
        updated_at = now()
  returning id into v_sub_id;

  update devices
     set trial_used_at = now()
   where fingerprint = p_fingerprint;

  return v_sub_id;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Admin trial refresh is a trial too.
-- ---------------------------------------------------------------------------
create or replace function public.admin_refresh_trial(
  p_passcode    text,
  p_fingerprint text,
  p_days        int default 14
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_session uuid;
  v_plan    subscription_plans%rowtype;
  v_end     timestamptz;
  v_sub_id  uuid;
begin
  if not admin_check(p_passcode) then
    raise exception 'unauthorized';
  end if;
  if p_days is null or p_days < 1 or p_days > 365 then
    return jsonb_build_object('ok', false, 'error', 'invalid_days');
  end if;

  select session_id into v_session
  from devices
  where fingerprint = p_fingerprint;

  if v_session is null then
    return jsonb_build_object('ok', false, 'error', 'unknown_device');
  end if;

  select * into v_plan
  from subscription_plans
  where key = 'stream_standard' and active;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_plan');
  end if;

  v_end := now() + make_interval(days => p_days);

  insert into trial_claims (fingerprint, claimed_at)
  values (p_fingerprint, now())
  on conflict (fingerprint) do nothing;

  insert into subscriptions
    (subscriber_session_id, plan_key, entitlement, status,
     current_period_start, current_period_end, auto_renew, is_trial)
  values
    (v_session, 'stream_standard', v_plan.entitlement, 'active',
     now(), v_end, false, true)
  on conflict (subscriber_session_id, plan_key) do update
    set status = 'active',
        auto_renew = false,
        is_trial = true,
        current_period_start = now(),
        current_period_end = greatest(
          subscriptions.current_period_end,
          excluded.current_period_end
        ),
        cancelled_at = null,
        expired_at = null,
        updated_at = now()
  returning id, current_period_end into v_sub_id, v_end;

  update devices
     set trial_used_at = coalesce(trial_used_at, now())
   where fingerprint = p_fingerprint;

  return jsonb_build_object(
    'ok', true,
    'subscription_id', v_sub_id,
    'period_end', v_end,
    'days', p_days
  );
end $$;

grant execute on function public.admin_refresh_trial(text, text, int)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Paid grants never carry the trial countdown.
-- ---------------------------------------------------------------------------
create or replace function public.admin_grant_subscription(
  p_passcode    text,
  p_fingerprint text,
  p_days        int default 30,
  p_plan_key    text default 'stream_standard',
  p_note        text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_session uuid;
  v_plan subscription_plans%rowtype;
  v_end timestamptz;
  v_sub_id uuid;
  v_blocked boolean;
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  if p_days is null or p_days < 1 or p_days > 3650 then
    return jsonb_build_object('ok', false, 'error', 'invalid_days');
  end if;

  select session_id, blocked into v_session, v_blocked
  from public.devices where fingerprint = p_fingerprint;
  if v_session is null then
    return jsonb_build_object('ok', false, 'error', 'unknown_device');
  end if;
  if v_blocked then
    return jsonb_build_object('ok', false, 'error', 'device_blocked');
  end if;

  select * into v_plan from public.subscription_plans where key = p_plan_key;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_plan');
  end if;
  if not v_plan.active then
    return jsonb_build_object('ok', false, 'error', 'inactive_plan');
  end if;

  v_end := now() + make_interval(days => p_days);
  insert into public.subscriptions
    (subscriber_session_id, plan_key, entitlement, status,
     current_period_start, current_period_end, auto_renew, is_trial)
  values
    (v_session, p_plan_key, v_plan.entitlement, 'active',
     now(), v_end, false, false)
  on conflict (subscriber_session_id, plan_key) do update
    set status = 'active',
        auto_renew = false,
        is_trial = false,
        current_period_start = now(),
        current_period_end = greatest(
          subscriptions.current_period_end,
          excluded.current_period_end
        ),
        cancelled_at = null,
        expired_at = null,
        updated_at = now()
  returning id, current_period_end into v_sub_id, v_end;

  perform public.admin_log(
    p_passcode, 'subscription.grant', p_fingerprint,
    jsonb_build_object('plan', p_plan_key, 'days', p_days, 'note', p_note,
                       'period_end', v_end)
  );

  return jsonb_build_object('ok', true, 'subscription_id', v_sub_id,
                            'period_end', v_end, 'days', p_days);
end $$;

-- ---------------------------------------------------------------------------
-- 8. A completed payment always turns the subscription into a paid one.
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
    korapay_reference, started_at, cancelled_at, expired_at, updated_at,
    is_trial
  ) values (
    p_session, p_plan_key, plan.entitlement, 'active', true,
    now(), period_end, period_end + make_interval(days => plan.grace_days),
    p_reference, now(), null, null, now(), false
  )
  on conflict (subscriber_session_id, plan_key) do update
    set status = 'active',
        auto_renew = true,
        is_trial = false,
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

-- activate_stream_subscription is service-role only; keep that boundary.
revoke execute on function public.activate_stream_subscription(uuid, text, text)
  from anon, authenticated;
grant execute on function public.activate_stream_subscription(uuid, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 9. The generic activation path is a paid activation too. Without this, a
--    plan that was once a trial would keep is_trial=true after a renewal and
--    the app would show a countdown to a paying subscriber.
-- ---------------------------------------------------------------------------
create or replace function public.start_subscription_period(
  p_subscriber uuid,
  p_plan_key   text,
  p_reference  text
) returns subscriptions
language plpgsql
as $function$
declare
    plan subscription_plans;
    sub subscriptions;
    period_end timestamptz;
    trial_end timestamptz;
begin
    select * into plan from subscription_plans where key = p_plan_key;
    if plan is null then
        raise exception 'unknown_plan:%', p_plan_key;
    end if;

    if plan.trial_days > 0 then
        trial_end := now() + make_interval(days => plan.trial_days);
        period_end := trial_end + make_interval(days => plan.period_days);
    else
        period_end := now() + make_interval(days => plan.period_days);
    end if;

    insert into subscriptions (
        subscriber_session_id, plan_key, entitlement, status, auto_renew,
        current_period_start, current_period_end, grace_until,
        korapay_reference, started_at, cancelled_at, expired_at, updated_at,
        is_trial
    ) values (
        p_subscriber, p_plan_key, plan.entitlement, 'active', true,
        now(), period_end, period_end + make_interval(days => plan.grace_days),
        p_reference, now(), null, null, now(), false
    )
    on conflict (subscriber_session_id, plan_key) do update
        set status = 'active',
            auto_renew = true,
            is_trial = false,
            current_period_start = now(),
            current_period_end = excluded.current_period_end,
            grace_until = excluded.grace_until,
            korapay_reference = excluded.korapay_reference,
            cancelled_at = null,
            expired_at = null,
            updated_at = now()
    returning * into sub;

    insert into entitlements (
        subscriber_session_id, entitlement, active, source, subscription_id, expires_at, updated_at
    ) values (
        p_subscriber, plan.entitlement, true, 'subscription', sub.id, sub.current_period_end, now()
    )
    on conflict (subscriber_session_id, entitlement) do update
        set active = true,
            source = 'subscription',
            subscription_id = excluded.subscription_id,
            expires_at = excluded.expires_at,
            updated_at = now();

    return sub;
end;
$function$;
