-- The $1 tier follows the continent, not the rail.
--
-- Korapay's live account collects six currencies (18 countries); the rest of
-- Africa is collected by Flutterwave in USD. Those payers were being quoted the
-- $6.99 overseas price purely because their currency is not on the Korapay
-- account. They now pay $1 too: local currency where Korapay has it, USD 1.00
-- through Flutterwave where it does not.
--
-- Trade-off, accepted: on the USD rails any percent promo drops the charge
-- below Flutterwave's one-dollar floor, so codes are refused there. The overseas
-- tier exists precisely so codes stay payable; the African USD rails cannot
-- have both at a $1 list price.

create or replace function public.is_african_country(p_country text)
returns boolean
language sql
immutable
as $$
  select upper(coalesce(p_country, '')) = any (array[
    'DZ', 'AO', 'BJ', 'BW', 'BF', 'BI', 'CV', 'CM', 'CF',
    'TD', 'KM', 'CG', 'CD', 'CI', 'DJ', 'EG', 'GQ', 'ER',
    'SZ', 'ET', 'GA', 'GM', 'GH', 'GN', 'GW', 'KE', 'LS',
    'LR', 'LY', 'MG', 'MW', 'ML', 'MR', 'MU', 'MA', 'MZ',
    'NA', 'NE', 'NG', 'RW', 'ST', 'SN', 'SC', 'SL', 'SO',
    'ZA', 'SS', 'SD', 'TZ', 'TG', 'TN', 'UG', 'ZM', 'ZW'
  ]);
$$;

grant execute on function public.is_african_country(text) to anon, authenticated;

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
           when public.is_african_country(
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

drop function if exists public.is_korapay_rail_country(text);
