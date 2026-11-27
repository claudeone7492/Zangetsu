-- Price the paywall by the country the charge is actually routed from.
--
-- The app used to send its device locale region, which is the phone's language
-- setting, not its location: an English (US) Android in Lagos reports "US", so
-- a Nigerian saw the $6.99 overseas price while the checkout would have charged
-- ₦1,356. The edge already decides the rail from the geo header on the request
-- (`cf-ipcountry`), so the quote must read the same header; the client hint is
-- only a fallback for when the edge cannot see the caller's address.
--
-- The tier is the rail: Korapay's local African currencies are $1, everything
-- Flutterwave collects is the overseas price.

create or replace function public.request_country()
returns text
language sql
stable
as $$
  select c
  from (
    select upper(btrim(coalesce(
             current_setting('request.headers', true)::jsonb ->> 'cf-ipcountry',
             current_setting('request.headers', true)::jsonb ->> 'x-country-code',
             current_setting('request.headers', true)::jsonb ->> 'x-vercel-ip-country',
             current_setting('request.headers', true)::jsonb ->> 'x-geo-country'
           ))) as c
  ) s
  where c ~ '^[A-Z]{2}$' and c <> 'XX';
$$;

grant execute on function public.request_country() to anon, authenticated;

-- Countries whose rail is Korapay, i.e. the $1 tier. Mirrors
-- KORA_COUNTRY_CURRENCIES in supabase/functions/_shared/payment_routing.ts;
-- `charge_currency.test.ts` fails if the two lists drift apart.
create or replace function public.is_korapay_rail_country(p_country text)
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

drop function if exists public.is_african_rail_country(text);

create or replace function public.list_plans(p_country text default null)
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
           when public.is_korapay_rail_country(
             coalesce(public.request_country(), p_country)
           ) then p.price_usd_cents
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

drop function if exists public._geo_probe();
