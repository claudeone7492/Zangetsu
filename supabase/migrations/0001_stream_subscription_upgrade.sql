-- =============================================================================
-- Zangetsu subscription + device-identity upgrade
-- Target: Sophie project (ref lmjeickcvynwqsvustwq)
--
-- Additive only. Nothing existing is dropped or renamed. Existing tables that
-- already model this domain (user_profiles, subscription_plans, subscriptions,
-- promo_codes, payments, entitlements) are extended in place:
--
--   * identity becomes a DEVICE FINGERPRINT (no sign-in). user_profiles
--     already keys on session_id (uuid) — we add fingerprint columns to it.
--   * promo_codes currently only stores a flat discount_amount for a
--     'vip_unlock' product. We add percent_off / kind / active / label so the
--     tiered (10..100%) catalogue and per-device redemptions can be tracked.
--   * a device registry + redemption ledger are added so the admin console can
--     show every device, which code it used, its subscription and usage.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. user_profiles — device identity
-- ---------------------------------------------------------------------------
alter table public.user_profiles
  add column if not exists device_fingerprint text,
  add column if not exists platform           text,
  add column if not exists app_version        text,
  add column if not exists device_model       text,
  add column if not exists first_seen_at      timestamptz not null default now();

-- One fingerprint == one device. Partial index so the many legacy rows with a
-- null fingerprint (pre-upgrade accounts) don't collide.
create unique index if not exists user_profiles_fingerprint_key
  on public.user_profiles (device_fingerprint)
  where device_fingerprint is not null;

-- ---------------------------------------------------------------------------
-- 2. subscription_plans — cheap African-friendly USD price points
-- ---------------------------------------------------------------------------
-- Prices are USD but set to African purchasing-power levels, not US/UK list.
-- Existing rows (vip_monthly 999, etc.) are left untouched; we upsert only the
-- three streaming tiers the app now sells.
insert into public.subscription_plans
  (key, product_type, entitlement, label, price_usd_cents, period_days,
   trial_days, grace_days, features, active, sort_order)
values
  ('stream_basic',    'subscription_stream', 'stream_hd',
   'Basic (with ads)', 199,  30, 0, 3, '["1 device","720p","Ads"]'::jsonb,   true, 10),
  ('stream_standard', 'subscription_stream', 'stream_fhd',
   'Standard',         349,  30, 7, 3, '["2 devices","1080p","Downloads"]'::jsonb, true, 11),
  ('stream_premium',  'subscription_stream', 'stream_uhd',
   'Premium',          599,  30, 7, 3, '["4 devices","4K + HDR","Spatial audio"]'::jsonb, true, 12)
on conflict (key) do update set
  label           = excluded.label,
  price_usd_cents = excluded.price_usd_cents,
  period_days     = excluded.period_days,
  trial_days      = excluded.trial_days,
  grace_days      = excluded.grace_days,
  features        = excluded.features,
  active          = excluded.active,
  sort_order      = excluded.sort_order;

-- ---------------------------------------------------------------------------
-- 3. promo_codes — tiered percentage discounts + lifecycle flags
-- ---------------------------------------------------------------------------
alter table public.promo_codes
  add column if not exists percent_off int,
  add column if not exists kind        text not null default 'percent',
  add column if not exists label       text,
  add column if not exists active      boolean not null default true,
  add column if not exists created_at  timestamptz not null default now(),
  add column if not exists updated_at  timestamptz not null default now();

-- Legacy rows used a flat discount_amount for 'vip_unlock'; keep that column
-- but stop requiring it for the new percentage-based codes.
alter table public.promo_codes alter column discount_amount drop not null;
alter table public.promo_codes alter column valid_for       drop not null;

do $$ begin
  alter table public.promo_codes
    add constraint promo_codes_percent_off_check
    check (percent_off is null or (percent_off >= 0 and percent_off <= 100));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.promo_codes
    add constraint promo_codes_kind_check
    check (kind in ('free','percent'));
exception when duplicate_object then null; end $$;

-- Seed the 48-code catalogue, 6 per tier. Codes are hidden from end users and
-- only surfaced in the in-app admin console.
insert into public.promo_codes (code, percent_off, kind, label, valid_for, max_uses, active)
values
  -- 100% off — free access
  ('$EDGES',100,'free','Free access','stream',null,true),
  ('BOSSSLINGZS',100,'free','Free access','stream',null,true),
  ('NETFLIX$100',100,'free','Free access','stream',100,true),
  ('PRIME#100',100,'free','Free access','stream',null,true),
  ('DISNEY_100',100,'free','Free access','stream',null,true),
  ('HBOMAX100!',100,'free','Free access','stream',null,true),
  -- 85% off
  ('NETFLIX85!',85,'percent',null,'stream',null,true),
  ('STARZ_85',85,'percent',null,'stream',200,true),
  ('HULU#85*',85,'percent',null,'stream',null,true),
  ('SHOWMAX85',85,'percent',null,'stream',null,true),
  ('PRIME85!',85,'percent',null,'stream',null,true),
  ('DISNEY85#',85,'percent',null,'stream',null,true),
  -- 75% off
  ('STREMIO75!',75,'percent',null,'stream',200,true),
  ('KODI_75',75,'percent',null,'stream',null,true),
  ('JELLYFIN#75',75,'percent',null,'stream',null,true),
  ('PLEX75*',75,'percent',null,'stream',null,true),
  ('EMBY_75',75,'percent',null,'stream',null,true),
  ('MUBI75!',75,'percent',null,'stream',null,true),
  -- 65% off
  ('SHOWMAX65!',65,'percent',null,'stream',null,true),
  ('IQIYI_65',65,'percent',null,'stream',null,true),
  ('ZEE5#65',65,'percent',null,'stream',null,true),
  ('VIKI65!',65,'percent',null,'stream',null,true),
  ('WETV_65',65,'percent',null,'stream',null,true),
  ('CRUNCHY65#',65,'percent',null,'stream',null,true),
  -- 50% off
  ('DISNEY+50',50,'percent',null,'stream',null,true),
  ('APPLE50!',50,'percent',null,'stream',null,true),
  ('MAX_50',50,'percent',null,'stream',null,true),
  ('HBO#50',50,'percent',null,'stream',null,true),
  ('PARAMOUNT50!',50,'percent',null,'stream',100,true),
  ('PEACOCK#50',50,'percent',null,'stream',null,true),
  -- 35% off
  ('CRUNCHY35!',35,'percent',null,'stream',null,true),
  ('VIKI_35',35,'percent',null,'stream',null,true),
  ('WETV#35',35,'percent',null,'stream',null,true),
  ('TUBI35!',35,'percent',null,'stream',null,true),
  ('ROKU_35',35,'percent',null,'stream',null,true),
  ('PLUTO35#',35,'percent',null,'stream',null,true),
  -- 25% off
  ('PRIME25!',25,'percent',null,'stream',null,true),
  ('ROKU_25',25,'percent',null,'stream',500,true),
  ('SLING#25',25,'percent',null,'stream',null,true),
  ('MUBI25*',25,'percent',null,'stream',null,true),
  ('PEACOCK25!',25,'percent',null,'stream',null,true),
  ('VUDU#25',25,'percent',null,'stream',null,true),
  -- 10% off
  ('HULU#10',10,'percent',null,'stream',null,true),
  ('PEACOCK10!',10,'percent',null,'stream',null,true),
  ('TUBI_10',10,'percent',null,'stream',null,true),
  ('PLEX10*',10,'percent',null,'stream',null,true),
  ('VUDU#10',10,'percent',null,'stream',100,true),
  ('ROKU10!',10,'percent',null,'stream',null,true)
on conflict (code) do update set
  percent_off = excluded.percent_off,
  kind        = excluded.kind,
  label       = excluded.label,
  valid_for   = excluded.valid_for,
  max_uses    = excluded.max_uses,
  active      = excluded.active,
  updated_at  = now();

-- ---------------------------------------------------------------------------
-- 4. devices — registry the admin console lists
-- ---------------------------------------------------------------------------
create table if not exists public.devices (
  fingerprint   text primary key,
  session_id    uuid references public.user_profiles(session_id) on delete set null,
  platform      text,
  device_model  text,
  app_version   text,
  is_admin      boolean not null default false,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now()
);

create index if not exists devices_last_seen_idx on public.devices (last_seen_at desc);

-- ---------------------------------------------------------------------------
-- 5. promo_redemptions — which device used which code, and what it saved
-- ---------------------------------------------------------------------------
create table if not exists public.promo_redemptions (
  id            uuid primary key default gen_random_uuid(),
  promo_id      uuid not null references public.promo_codes(id) on delete cascade,
  fingerprint   text not null,
  session_id    uuid,
  plan_key      text,
  percent_off   int  not null default 0,
  amount_before int,
  amount_after  int,
  currency      text not null default 'USD',
  created_at    timestamptz not null default now()
);

create index if not exists promo_redemptions_promo_idx on public.promo_redemptions (promo_id);
create index if not exists promo_redemptions_fp_idx    on public.promo_redemptions (fingerprint);

-- ---------------------------------------------------------------------------
-- 6. device_watch_stats — usage rollup per device/profile
-- ---------------------------------------------------------------------------
create table if not exists public.device_watch_stats (
  fingerprint  text primary key references public.devices(fingerprint) on delete cascade,
  profiles     int not null default 1,
  titles       int not null default 0,
  minutes      int not null default 0,
  updated_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 7. admins — in-app admin gate
-- ---------------------------------------------------------------------------
create table if not exists public.admins (
  id            uuid primary key default gen_random_uuid(),
  label         text,
  passcode_hash text not null,
  role          text not null default 'owner',
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  last_login_at timestamptz
);

-- ---------------------------------------------------------------------------
-- 8. app_config — admin-managed defaults
-- ---------------------------------------------------------------------------
alter table public.app_config
  add column if not exists stream_launch_discount_pct int not null default 15,
  add column if not exists display_currency text not null default 'USD';

-- ---------------------------------------------------------------------------
-- 9. RLS: service-role only for the admin surfaces
-- ---------------------------------------------------------------------------
alter table public.devices            enable row level security;
alter table public.promo_redemptions  enable row level security;
alter table public.device_watch_stats enable row level security;
alter table public.admins             enable row level security;

do $$ begin
  create policy admin_all_devices on public.devices
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy admin_all_redemptions on public.promo_redemptions
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy admin_all_watch on public.device_watch_stats
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy admin_all_admins on public.admins
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;
