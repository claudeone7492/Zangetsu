-- =============================================================================
-- Zangetsu subscription — close the remaining server-side bypasses.
--
-- Found while auditing every anon-executable function:
--
--   * activate_stream_subscription was SECURITY DEFINER and callable by anon.
--     Any client could pass a session id and plan key and grant itself a paid
--     period without a charge. Only the Korapay webhook / stream-subscribe edge
--     functions call it, and they use the service-role client.
--   * get_subscription_session exposed the same session ids to anon. It is an
--     edge-function helper too.
--   * admin_check was a direct passcode oracle. It stays internal to the admin
--     RPCs, which now rate-limit wrong attempts.
--   * redeem_promo accepted unlimited redemptions of one code by one device,
--     so a single device could exhaust a promo's max_uses.
--
-- The trial itself is locked in 20261122_trial_hardening_admin_login.sql.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Paid activation and session lookup are service-role only.
-- ---------------------------------------------------------------------------
revoke execute on function public.activate_stream_subscription(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.activate_stream_subscription(uuid, text, text)
  to service_role;

revoke execute on function public.get_subscription_session(text)
  from public, anon, authenticated;
grant execute on function public.get_subscription_session(text)
  to service_role;

-- The legacy passcode setup/check pair is not called by the app any more; the
-- admin RPCs below still reach admin_check as the function owner.
revoke execute on function public.admin_check(text)
  from public, anon, authenticated;
revoke execute on function public.admin_setup(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Rate-limit admin passcode attempts. One global counter is deliberate:
--    the key is not attacker-controlled, so it cannot be used to fill a table,
--    and five failures lock the console for 15 minutes.
-- ---------------------------------------------------------------------------
create table if not exists public.admin_auth_state (
  id          boolean primary key default true check (id),
  attempts    int not null default 0,
  locked_until timestamptz,
  updated_at  timestamptz not null default now()
);

insert into public.admin_auth_state (id) values (true)
on conflict (id) do nothing;

alter table public.admin_auth_state enable row level security;
revoke all on public.admin_auth_state from anon, authenticated;

create or replace function public.admin_check(p_passcode text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_hash     text;
  v_attempts int;
  v_locked   timestamptz;
begin
  if p_passcode is null or length(p_passcode) < 6 then return false; end if;

  select attempts, locked_until into v_attempts, v_locked
  from public.admin_auth_state where id;

  if v_locked is not null and v_locked > now() then return false; end if;

  v_hash := encode(extensions.digest(p_passcode, 'sha256'), 'hex');

  if exists (
    select 1 from public.admins
    where active and passcode_hash = v_hash
  ) then
    update public.admin_auth_state
       set attempts = 0, locked_until = null, updated_at = now()
     where id;
    return true;
  end if;

  update public.admin_auth_state
     set attempts = attempts + 1,
         locked_until = case
           when attempts + 1 >= 5 then now() + interval '15 minutes'
           else locked_until
         end,
         updated_at = now()
   where id;

  return false;
end $$;

-- Email/password login gets the same five-strike lockout, tracked on the admin
-- row so one account cannot lock out another.
alter table public.admins
  add column if not exists failed_attempts int not null default 0,
  add column if not exists locked_until    timestamptz;

create or replace function public.admin_login(
  p_email    text,
  p_password text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_admin admins%rowtype;
  v_ok    boolean;
begin
  if p_email is null or length(trim(p_email)) < 3 then return false; end if;
  if p_password is null or length(p_password) < 6 then return false; end if;

  select * into v_admin
  from public.admins
  where active and lower(email) = lower(trim(p_email));

  if not found then return false; end if;
  if v_admin.locked_until is not null and v_admin.locked_until > now() then
    return false;
  end if;

  v_ok := v_admin.passcode_hash =
    encode(extensions.digest(p_password, 'sha256'), 'hex');

  if v_ok then
    update public.admins
       set failed_attempts = 0,
           locked_until = null,
           last_login_at = now()
     where id = v_admin.id;
    return true;
  end if;

  update public.admins
     set failed_attempts = failed_attempts + 1,
         locked_until = case
           when failed_attempts + 1 >= 5 then now() + interval '15 minutes'
           else locked_until
         end
   where id = v_admin.id;

  return false;
end $$;

grant execute on function public.admin_login(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. One redemption per device per promo, counted once.
-- ---------------------------------------------------------------------------
create unique index if not exists promo_redemptions_promo_fp_key
  on public.promo_redemptions (promo_id, fingerprint);

create or replace function public.redeem_promo(
  p_code        text,
  p_fingerprint text,
  p_plan        text default null,
  p_before      int  default null,
  p_after       int  default null
) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_promo    promo_codes%rowtype;
  v_session  uuid;
  v_inserted int;
begin
  select * into v_promo from promo_codes p
  where upper(p.code) = upper(trim(p_code))
    and p.active
    and (p.expires_at is null or p.expires_at > now())
    and (p.max_uses is null or p.used_count < p.max_uses)
  limit 1;

  if not found then return null; end if;

  select session_id into v_session
  from devices where fingerprint = p_fingerprint;

  insert into promo_redemptions
    (promo_id, fingerprint, session_id, plan_key, percent_off,
     amount_before, amount_after)
  values
    (v_promo.id, p_fingerprint, v_session, p_plan,
     coalesce(v_promo.percent_off, 0), p_before, p_after)
  on conflict (promo_id, fingerprint) do nothing;

  get diagnostics v_inserted = row_count;

  if v_inserted > 0 then
    update promo_codes
       set used_count = used_count + 1
     where id = v_promo.id;
  end if;

  return coalesce(v_promo.percent_off, 0);
end $$;

grant execute on function public.redeem_promo(text, text, text, int, int)
  to anon, authenticated;
