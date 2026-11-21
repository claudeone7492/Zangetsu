-- =============================================================================
-- Zangetsu admin console — show who shares a plan with whom
-- Target: Sophie project (ref lmjeickcvynwqsvustwq)
--
-- device_seats made sharing real, but admin_devices still resolved each
-- device's own subscription, so a seat read as an inactive device with no plan
-- and support could not see who was riding on whom. Two columns are added:
--
--   seat_owner — the fingerprint this device is linked to (null when it pays)
--   seats      — devices on the plan this device is on, itself included
--
-- A seat's plan and status now resolve through its owner, so the row tells the
-- truth: a guest on a live Standard plan reads Standard/active, not inactive.
--
-- The OUT columns change, so the function is rebuilt under a new name and then
-- swapped in — the old one is only dropped once the new body compiles.
-- =============================================================================

create or replace function public.admin_devices_v2(p_passcode text)
returns table (
  fingerprint text,
  platform text,
  plan text,
  promo text,
  percent_off int,
  paid_cents int,
  status text,
  renews_at timestamptz,
  watch int,
  last_seen_at timestamptz,
  seat_owner text,
  seats int
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
         d.last_seen_at,
         seat.owner_fingerprint,
         1 + (
            select count(*)::int from device_seats ds
            where ds.owner_fingerprint = coalesce(seat.owner_fingerprint, d.fingerprint)
          )
  from devices d
  left join device_seats seat on seat.fingerprint = d.fingerprint
  left join lateral (
    select s2.* from subscriptions s2
    join devices ed on ed.fingerprint = coalesce(seat.owner_fingerprint, d.fingerprint)
    where s2.subscriber_session_id = ed.session_id
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

drop function if exists public.admin_devices(text);
alter function public.admin_devices_v2(text) rename to admin_devices;

grant execute on function public.admin_devices(text) to anon, authenticated;
