-- =============================================================================
-- Zangetsu subscription — launch price for the single paywall tier
--
-- The paywall collapses the catalogue to one card ("Premium subscription"),
-- which is `stream_standard` (see SubscriptionCubit._singlePremiumPlan). Its
-- seeded price was 349c; the launch price is 200c ($2). Kept in a migration
-- rather than edited in place so a fresh project seeds the same price the
-- running one sells.
--
-- The other tiers are untouched: `stream_basic`/`stream_premium` are not
-- shown, and the pre-existing vip_*/creator_*/premium_* rows belong to the
-- wider Sophie catalogue.
-- =============================================================================

update public.subscription_plans
   set price_usd_cents = 200
 where key = 'stream_standard';
