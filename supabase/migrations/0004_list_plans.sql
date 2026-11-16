-- Public, read-only plan catalogue. subscription_plans has RLS on with no
-- anon policy, so the paywall reads it through this function instead.
create or replace function public.list_plans()
returns table (
  key text, label text, price_usd_cents int, period_days int,
  trial_days int, features jsonb, sort_order int
)
language sql security definer set search_path = public as $$
  select p.key, p.label, p.price_usd_cents, p.period_days,
         p.trial_days, p.features, p.sort_order
  from subscription_plans p
  where p.active and p.key like 'stream_%'
  order by p.sort_order;
$$;
