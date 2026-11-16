-- =============================================================================
-- Zangetsu subscription — app-facing RPCs (Sophie project)
--
-- The tables added in 0001 are service-role only (RLS on, no anon policies),
-- so the device cannot read the promo table or the device registry directly.
-- Everything the app needs goes through SECURITY DEFINER functions below,
-- which keeps the promo catalogue unenumerable and the registry write-only.
--
-- Also adds first-time-device trial support for the "Activate free trial"
-- button.
-- =============================================================================

-- Trial bookkeeping on the device registry.
alter table public.devices
  add column if not exists trial_used_at timestamptz;

-- ---------------------------------------------------------------------------
-- register_device: idempotent device upsert, reports first-time status.
-- Returns is_new = true only the first time this fingerprint is ever seen,
-- which is exactly what gates the "Activate free trial" button.
-- ---------------------------------------------------------------------------
create or replace function public.register_device(
  p_fingerprint text,
  p_platform    text default null,
  p_model       text default null,
  p_version     text default null
) returns table (is_new boolean, trial_used boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_existed boolean;
begin
  if p_fingerprint is null or length(p_fingerprint) < 8 then
    raise exception 'invalid fingerprint';
  end if;

  select exists(select 1 from devices d where d.fingerprint = p_fingerprint)
    into v_existed;

  insert into devices (fingerprint, platform, device_model, app_version)
  values (p_fingerprint, p_platform, p_model, p_version)
  on conflict (fingerprint) do update set
    platform     = coalesce(excluded.platform, devices.platform),
    device_model = coalesce(excluded.device_model, devices.device_model),
    app_version  = coalesce(excluded.app_version, devices.app_version),
    last_seen_at = now();

  return query
    select not v_existed, (d.trial_used_at is not null)
    from devices d where d.fingerprint = p_fingerprint;
end $$;

-- ---------------------------------------------------------------------------
-- resolve_promo: validate a typed code without revealing the catalogue.
-- Returns null when the code is unknown, inactive, expired or exhausted.
-- ---------------------------------------------------------------------------
create or replace function public.resolve_promo(
  p_code text,
  p_plan text default null
) returns table (code text, percent_off int, kind text, label text)
language sql security definer set search_path = public as $$
  select p.code, coalesce(p.percent_off, 0), p.kind, p.label
  from promo_codes p
  where upper(p.code) = upper(trim(p_code))
    and p.active
    and (p.expires_at is null or p.expires_at > now())
    and (p.max_uses is null or p.used_count < p.max_uses)
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- start_trial: grant a 7-day trial once per device. Returns the new
-- subscription row id, or null when the device already used its trial.
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

  select trial_used_at into v_used from devices where fingerprint = p_fingerprint;
  if v_used is not null then return null; end if;

  select session_id into v_session from devices where fingerprint = p_fingerprint;

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
-- Admin reads — gated by the in-app passcode (hash stored in public.admins).
-- No service-role key ever ships on the device.
-- ---------------------------------------------------------------------------
create or replace function public.admin_check(p_passcode text)
returns boolean
language sql security definer set search_path = public as $$
  select exists(
    select 1 from admins
    where active and passcode_hash = encode(extensions.digest(p_passcode, 'sha256'), 'hex')
  );
$$;

create or replace function public.admin_devices(p_passcode text)
returns table (
  fingerprint text, platform text, plan text, promo text, percent_off int,
  paid_cents int, status text, renews_at timestamptz, watch int, last_seen_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_passcode) then raise exception 'unauthorized'; end if;

  return query
  select d.fingerprint,
         d.platform,
         pl.label,
         r.code,
         coalesce(r.percent_off, 0),
         coalesce(pl.price_usd_cents, 0),
         coalesce(s.status, 'inactive'),
         s.current_period_end,
         coalesce(w.titles, 0),
         d.last_seen_at
  from devices d
  left join lateral (
    select s2.* from subscriptions s2
    where s2.subscriber_session_id = d.session_id
    order by s2.started_at desc limit 1
  ) s on true
  left join subscription_plans pl on pl.key = s.plan_key
  left join lateral (
    select pc.code, pr.percent_off
    from promo_redemptions pr
    join promo_codes pc on pc.id = pr.promo_id
    where pr.fingerprint = d.fingerprint
    order by pr.created_at desc limit 1
  ) r on true
  left join device_watch_stats w on w.fingerprint = d.fingerprint
  order by d.last_seen_at desc;
end $$;
