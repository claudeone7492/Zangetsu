-- Remove the free trial product entirely and drop the subscription price to
-- $0.75/month. Run after the trial countdown migration.

-- 1. One price, no trial period, for every plan.
update subscription_plans
set price_usd_cents = 75,
    trial_days = 0;

-- 2. Active trials end now. A device that was on a trial must subscribe to
--    keep watching, exactly like a device that never had one.
update subscriptions
set current_period_end = now(),
    status = 'expired',
    updated_at = now()
where is_trial
  and status in ('active', 'trialing')
  and current_period_end > now();

-- 3. Remove the trial RPCs so no client, old or new, can mint free access.
drop function if exists public.start_trial(text, text);
drop function if exists public.admin_refresh_trial(text, text, int);
