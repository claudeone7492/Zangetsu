-- =============================================================================
-- Zangetsu subscription — $2 paywall, 14-day per-device trial hardening,
-- admin email login and admin trial refresh.
-- Target: Sophie project (ref lmjeickcvynwqsvustwq)
--
-- Closes three gaps:
--
--   1. start_trial could be called before identify_device. With no device row
--      it inserted a subscription under a random session and its
--      `update devices ...` matched zero rows, so the trial flag was never
--      set and the call could be repeated. It now creates/locks the device row
--      first and refuses while an active entitlement exists.
--   2. Admins could only sign in with a passcode. `admins.email` +
--      `admin_login` add the email/password login the console now uses.
--   3. There was no supported way to refresh a device's trial. The only reset
--      was direct SQL. `admin_refresh_trial` grants a fresh period and stamps
--      the device so it cannot self-serve another trial.
--
-- The paywall is one product (`stream_standard`). Its list price is now 200c
-- ($2.00) and the launch discount is cleared, so the card quotes $2.00 rather
-- than a discounted figure.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. One product, $2, 14-day trial, no launch discount.
-- ---------------------------------------------------------------------------
update public.subscription_plans
   set price_usd_cents = 200,
       trial_days = 14
 where key = 'stream_standard';

update public.subscription_plans
   set trial_days = 14
 where key = 'stream_premium';

update public.app_config
   set stream_launch_discount_pct = 0
 where true;

-- ---------------------------------------------------------------------------
-- 2. Admin identity: email + password.
-- ---------------------------------------------------------------------------
alter table public.admins
  add column if not exists email text;

create unique index if not exists admins_email_active_key
  on public.admins (lower(email))
  where email is not null and active;

-- Verify an email/password pair. Password hashing stays the same SHA-256 the
-- passcode gate already used, so an existing admin row keeps working.
create or replace function public.admin_login(
  p_email    text,
  p_password text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_ok boolean;
begin
  if p_email is null or length(trim(p_email)) < 3 then return false; end if;
  if p_password is null or length(p_password) < 6 then return false; end if;

  update public.admins
     set last_login_at = now()
   where active
     and lower(email) = lower(trim(p_email))
     and passcode_hash =
         encode(extensions.digest(p_password, 'sha256'), 'hex')
  returning true into v_ok;

  return coalesce(v_ok, false);
end $$;

-- First-run registration. Refuses once any active admin exists, so it cannot
-- be used from a device to overwrite the owner.
create or replace function public.admin_register(
  p_email    text,
  p_password text
) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_email is null or length(trim(p_email)) < 3 then
    raise exception 'email too short';
  end if;
  if p_password is null or length(p_password) < 6 then
    raise exception 'password too short';
  end if;
  if exists (select 1 from public.admins where active) then
    return false;
  end if;

  insert into public.admins (label, email, passcode_hash, role)
  values (
    trim(p_email),
    lower(trim(p_email)),
    encode(extensions.digest(p_password, 'sha256'), 'hex'),
    'owner'
  );
  return true;
end $$;

grant execute on function public.admin_login(text, text)    to anon, authenticated;
grant execute on function public.admin_register(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. start_trial — one trial per device, enforced under a row lock.
--
-- The device row is created if the caller skipped identify_device, the row is
-- locked while the flag is checked, and the claim is written in the same
-- transaction. A device with a live subscription is refused rather than
-- overwriting it.
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

  select session_id, trial_used_at
    into v_session, v_used
  from devices
  where fingerprint = p_fingerprint
  for update;

  if v_used is not null then return null; end if;

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

  insert into subscriptions
    (subscriber_session_id, plan_key, entitlement, status,
     current_period_start, current_period_end, auto_renew)
  values
    (v_session, p_plan, v_plan.entitlement, 'active',
     now(), now() + make_interval(days => v_plan.trial_days), false)
  on conflict (subscriber_session_id, plan_key) do update
    set status = 'active',
        auto_renew = false,
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
-- 4. Admin trial refresh — the only supported way to extend a lapsed device.
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

  insert into subscriptions
    (subscriber_session_id, plan_key, entitlement, status,
     current_period_start, current_period_end, auto_renew)
  values
    (v_session, 'stream_standard', v_plan.entitlement, 'active',
     now(), v_end, false)
  on conflict (subscriber_session_id, plan_key) do update
    set status = 'active',
        auto_renew = false,
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
