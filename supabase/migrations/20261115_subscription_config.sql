-- Public, read-only paywall display config.
--
-- app_config has RLS on with no anon policy, so the paywall cannot read the
-- launch discount directly. This exposes only the two fields the card needs,
-- never the rest of the admin row (fees, XP thresholds, ...). Always returns
-- exactly one row so the client never has to handle an empty result.
create or replace function public.subscription_config()
returns table (launch_discount_pct int, display_currency text)
language sql security definer set search_path = public as $$
  select
    coalesce((select stream_launch_discount_pct from public.app_config limit 1), 0),
    coalesce((select nullif(display_currency, '') from public.app_config limit 1), 'USD');
$$;

grant execute on function public.subscription_config() to anon, authenticated;
