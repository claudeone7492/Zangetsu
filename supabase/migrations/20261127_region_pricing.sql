-- Two price tiers.
--
-- Local African rails charge $1; everywhere else charges the overseas tier.
-- The overseas price is not a business decision alone: Flutterwave refuses any
-- charge below one major unit, so a promo code against a $1 list price (85% off
-- leaves $0.15) could never start a checkout. $6.99 is the lowest round price
-- where the deepest code (85% off, leaving $1.05) still clears that floor.
--
-- `price_usd_cents` keeps its meaning (the local-rail price) so nothing that
-- already reads it changes; `price_intl_usd_cents` is the second tier.

alter table public.subscription_plans
  add column if not exists price_intl_usd_cents integer not null default 699;

update public.subscription_plans
   set price_intl_usd_cents = 699
 where price_intl_usd_cents is null or price_intl_usd_cents <= 0;

-- Keep the country list in step with KORA_COUNTRY_CURRENCIES in
-- supabase/functions/_shared/payment_routing.ts.
create or replace function public.is_african_rail_country(p_country text)
returns boolean
language sql
immutable
as $$
  select upper(coalesce(p_country, '')) = any (array[
    'NG', 'GH', 'KE', 'ZA',
    'BJ', 'BF', 'CI', 'GW', 'ML', 'NE', 'SN', 'TG',
    'CM', 'CF', 'TD', 'CG', 'GA', 'GQ'
  ]);
$$;

-- The plan list now quotes the price for the caller's country. Returning the
-- overseas price when no country is known is the safe default: a client is
-- never shown a price lower than the one it will be charged.
drop function if exists public.list_plans();

create function public.list_plans(p_country text default null)
returns table(
  key text,
  label text,
  price_usd_cents integer,
  price_intl_usd_cents integer,
  period_days integer,
  trial_days integer,
  features jsonb,
  sort_order integer
)
language sql
security definer
set search_path to 'public'
as $$
  select p.key,
         p.label,
         case
           when public.is_african_rail_country(p_country) then p.price_usd_cents
           else p.price_intl_usd_cents
         end as price_usd_cents,
         p.price_intl_usd_cents,
         p.period_days,
         p.trial_days,
         p.features,
         p.sort_order
  from subscription_plans p
  where p.active and p.key like 'stream_%'
  order by p.sort_order;
$$;

grant execute on function public.list_plans(text) to anon, authenticated;
