-- =============================================================================
-- Zangetsu subscription — identity entry point + admin management (Sophie)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- identify_device: the single call the app makes on launch.
-- Upserts the device identity (user_profiles + devices) and returns the
-- session id plus current subscription, so the client never touches tables.
-- ---------------------------------------------------------------------------
create or replace function public.identify_device(
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
  period_end  timestamptz
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
         (d.trial_used_at is not null),
         s.plan_key,
         coalesce(s.status, 'inactive'),
         s.current_period_end
  from devices d
  left join lateral (
    select s2.plan_key, s2.status, s2.current_period_end
    from subscriptions s2
    where s2.subscriber_session_id = v_session
    order by s2.started_at desc limit 1
  ) s on true
  where d.fingerprint = p_fingerprint;
end $$;

-- ---------------------------------------------------------------------------
-- redeem_promo: record a redemption against the device and bump the counter.
-- Returns the percent off, or null when the code is not usable.
-- ---------------------------------------------------------------------------
create or replace function public.redeem_promo(
  p_code        text,
  p_fingerprint text,
  p_plan        text default null,
  p_before      int  default null,
  p_after       int  default null
) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_promo promo_codes%rowtype;
  v_session uuid;
begin
  select * into v_promo from promo_codes p
  where upper(p.code) = upper(trim(p_code))
    and p.active
    and (p.expires_at is null or p.expires_at > now())
    and (p.max_uses is null or p.used_count < p.max_uses)
  limit 1;

  if not found then return null; end if;

  select session_id into v_session from devices where fingerprint = p_fingerprint;

  insert into promo_redemptions
    (promo_id, fingerprint, session_id, plan_key, percent_off,
     amount_before, amount_after)
  values
    (v_promo.id, p_fingerprint, v_session, p_plan,
     coalesce(v_promo.percent_off, 0), p_before, p_after);

  update promo_codes set used_count = used_count + 1 where id = v_promo.id;

  return coalesce(v_promo.percent_off, 0);
end $$;

-- ---------------------------------------------------------------------------
-- Admin — first-run setup, then management. All gated by admin_check.
-- ---------------------------------------------------------------------------

-- Creates the first admin passcode. No-op once an active admin exists, so it
-- cannot be used to overwrite the owner from a device.
create or replace function public.admin_setup(p_passcode text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if length(p_passcode) < 6 then raise exception 'passcode too short'; end if;
  if exists(select 1 from admins where active) then return false; end if;
  insert into admins (label, passcode_hash, role)
  values ('owner', encode(extensions.digest(p_passcode, 'sha256'), 'hex'), 'owner');
  return true;
end $$;

-- Does an admin passcode exist yet? Drives the "create passcode" vs "sign in".
create or replace function public.admin_configured()
returns boolean
language sql security definer set search_path = public as $$
  select exists(select 1 from admins where active);
$$;

create or replace function public.admin_promos(p_passcode text)
returns table (
  code text, percent_off int, kind text, active boolean,
  max_uses int, used_count int, expires_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  return query
    select p.code, coalesce(p.percent_off, 0), p.kind, p.active,
           p.max_uses, p.used_count, p.expires_at
    from promo_codes p order by p.percent_off desc nulls last, p.code;
end $$;

-- Upsert a promo. Percent/kind/expiry/active are editable from the console.
create or replace function public.admin_set_promo(
  p_passcode    text,
  p_code        text,
  p_percent_off int,
  p_active      boolean default true,
  p_expires_at  timestamptz default null,
  p_max_uses    int default null
) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  insert into promo_codes (code, percent_off, kind, active, expires_at, max_uses, valid_for)
  values (trim(p_code), p_percent_off,
          case when p_percent_off >= 100 then 'free' else 'percent' end,
          p_active, p_expires_at, p_max_uses, 'stream')
  on conflict (code) do update set
    percent_off = excluded.percent_off,
    kind        = excluded.kind,
    active      = excluded.active,
    expires_at  = excluded.expires_at,
    max_uses    = excluded.max_uses,
    updated_at  = now();
  return true;
end $$;

create or replace function public.admin_subscriptions(p_passcode text)
returns table (
  plan text, subscribers bigint, price_usd_cents int, revenue_cents bigint
)
language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  return query
    select pl.label,
           count(s.id),
           pl.price_usd_cents,
           coalesce(sum(pl.price_usd_cents) filter (where s.status = 'active'), 0)
    from subscription_plans pl
    left join subscriptions s on s.plan_key = pl.key
    where pl.active and pl.key like 'stream_%'
    group by pl.label, pl.price_usd_cents, pl.sort_order
    order by pl.sort_order;
end $$;

-- Mark the calling device as an admin device (audit trail in the registry).
create or replace function public.admin_claim(p_passcode text, p_fingerprint text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  update devices set is_admin = true where fingerprint = p_fingerprint;
  return true;
end $$;
