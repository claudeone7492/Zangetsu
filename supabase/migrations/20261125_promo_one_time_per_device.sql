-- =============================================================================
-- Zangetsu subscription — a promo code is a one-time, per-device discount.
--
-- A device may redeem a given code once. The redemption row is kept forever,
-- so the same device cannot use the code again after its month expires. The
-- code only discounts the first month; renewals are charged at the normal
-- price. `access_until` records the one-month window for support and admin
-- reporting.
-- =============================================================================

alter table public.promo_redemptions
  add column if not exists access_until timestamptz;

update public.promo_redemptions
set access_until = created_at + interval '30 days'
where access_until is null;

-- Resolve a code for this device. A code that this device already redeemed is
-- returned with `already_used = true` (and no discount is applied by the
-- client), so the paywall can show a clear "expired for this device" notice.
-- `usable` reports expiry / exhaustion / inactive state without revealing the
-- catalogue for an unknown code.
drop function if exists public.resolve_promo(text, text);
drop function if exists public.resolve_promo(text, text, text);

create function public.resolve_promo(
  p_code        text,
  p_plan        text default null,
  p_fingerprint text default null
) returns table (
  code         text,
  percent_off  int,
  kind         text,
  label        text,
  already_used boolean,
  usable       boolean
)
language sql security definer set search_path = public as $$
  select
    p.code,
    coalesce(p.percent_off, 0),
    p.kind,
    p.label,
    (
      p_fingerprint is not null
      and p_fingerprint <> ''
      and exists (
        select 1
        from public.promo_redemptions pr
        where pr.promo_id = p.id
          and pr.fingerprint = p_fingerprint
      )
    ) as already_used,
    (
      p.active
      and (p.expires_at is null or p.expires_at > now())
      and (p.max_uses is null or p.used_count < p.max_uses)
    ) as usable
  from public.promo_codes p
  where upper(p.code) = upper(trim(p_code))
    and (p.valid_for is null or p.valid_for = 'stream')
  limit 1;
$$;

revoke execute on function public.resolve_promo(text, text, text) from public;
grant execute on function public.resolve_promo(text, text, text)
  to anon, authenticated;

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
     amount_before, amount_after, access_until)
  values
    (v_promo.id, p_fingerprint, v_session, p_plan,
     coalesce(v_promo.percent_off, 0), p_before, p_after,
     now() + interval '30 days')
  on conflict (promo_id, fingerprint) do nothing;

  get diagnostics v_inserted = row_count;

  -- A duplicate is not a second redemption: return null so callers can tell
  -- the device it has already used this code.
  if v_inserted = 0 then return null; end if;

  update promo_codes
     set used_count = used_count + 1
   where id = v_promo.id;

  return coalesce(v_promo.percent_off, 0);
end $$;

-- Redemption is a server-side operation. Clients can resolve a code, but only
-- the edge functions may consume it.
revoke execute on function public.redeem_promo(text, text, text, int, int)
  from public, anon, authenticated;
grant execute on function public.redeem_promo(text, text, text, int, int)
  to service_role;

notify pgrst, 'reload schema';
