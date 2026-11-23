# Zangetsu — subscription + admin design spec

Previews (app theming: `bg #0B0B0F`, `surface #16161C`, `accent #FF4D57`, frosted):

- `paywall_preview.html` — the subscription card users see.
- `admin_preview.html` — the in-app admin console (tabular).

## 0. Identity: device fingerprint, no sign-in

- Sign-in is removed. On first launch the app derives a **device fingerprint**
  (stable, hashed) and that is the account.
- Only the hash leaves the device; raw hardware ids stay local.
- Admin "login" is an in-app gate (stored passcode hash), not a server account.

## 1. Storage: the Sophie Supabase project

Backend is the **Sophie project** (ref `lmjeickcvynwqsvustwq`) — the closest
existing project; it already models this domain, so the migration is
**additive**, not a rebuild. Applied via
`supabase/migrations/0001_stream_subscription_upgrade.sql`.

Reused as-is: `user_profiles` (identity key), `subscription_plans`,
`subscriptions` (has `korapay_reference`), `payments` (has `promo_code_used`),
`entitlements`, `bandwidth_sharing` (matches the Proxies.sx work in this repo).

Upgraded / added:

| Object | Change |
|---|---|
| `user_profiles` | + `device_fingerprint`, `platform`, `app_version`, `device_model`, `first_seen_at`; unique index on fingerprint |
| `subscription_plans` | + 3 streaming tiers (`stream_basic/standard/premium`) |
| `promo_codes` | + `percent_off`, `kind`, `label`, `active`, timestamps; seeded 48 codes |
| `devices` (new) | fingerprint · session · platform · model · app version · admin flag · seen |
| `promo_redemptions` (new) | which device used which code, % off, amount before/after |
| `device_watch_stats` (new) | profiles · titles · minutes per device |
| `admins` (new) | in-app admin gate (passcode hash, role) |
| `app_config` | + `stream_launch_discount_pct` (0), `display_currency` (USD) |

## 2. Pricing — affordable to African rails, in USD

USD, but priced to African purchasing power (not US/UK list). List price, then
15% launch offer:

| Tier           | List  | App price (15% off) | Devices | Quality           |
|----------------|-------|---------------------|---------|-------------------|
| Basic (ads)    | $2.34 | **$1.99**/mo        | 1       | 720p              |
| Standard       | $4.11 | **$3.49**/mo        | 2       | 1080p + downloads |
| Premium        | $7.05 | **$5.99**/mo        | 4       | 4K + HDR + spatial|

7-day trial on Standard & Premium. Cancel anytime.

## 3. Promo codes — hidden from users

Users never see a code list; they may type one, the DB resolves it and records
the redemption against the fingerprint. The admin console is the only place
codes are visible. **6 codes per tier** (48), names = platforms + number +
special char:

- **100%** `$EDGES`, `BOSSSLINGZS`, `NETFLIX$100`, `PRIME#100`, `DISNEY_100`, `HBOMAX100!`
- **85%**  `NETFLIX85!`, `STARZ_85`, `HULU#85*`, `SHOWMAX85`, `PRIME85!`, `DISNEY85#`
- **75%**  `STREMIO75!`, `KODI_75`, `JELLYFIN#75`, `PLEX75*`, `EMBY_75`, `MUBI75!`
- **65%**  `SHOWMAX65!`, `IQIYI_65`, `ZEE5#65`, `VIKI65!`, `WETV_65`, `CRUNCHY65#`
- **50%**  `DISNEY+50`, `APPLE50!`, `MAX_50`, `HBO#50`, `PARAMOUNT50!`, `PEACOCK#50`
- **35%**  `CRUNCHY35!`, `VIKI_35`, `WETV#35`, `TUBI35!`, `ROKU_35`, `PLUTO35#`
- **25%**  `PRIME25!`, `ROKU_25`, `SLING#25`, `MUBI25*`, `PEACOCK25!`, `VUDU#25`
- **10%**  `HULU#10`, `PEACOCK10!`, `TUBI_10`, `PLEX10*`, `VUDU#10`, `ROKU10!`

Stacking: promo % applies on top of the 15% price. 100% → $0, no payment call.

## 4. Admin console (in-app, tabular)

- **Devices & Users** — fingerprint · platform · plan · promo used · % off ·
  paid/mo · status · renews · watch · last seen.
- **Promo Codes** — code · % off · redeemed-by · max uses · expires ·
  enable/disable · edit expiry.
- **Subscriptions** — plan · subscribers · list · app price · revenue · churn.
- **Profiles** — profile · device fingerprint · kind · titles · mins · last seen.

Admin can add/edit codes, change expiry, toggle active — all in-app.

## 5. Payment (KoraPay, in-app)

Embedded WebView checkout (add `flutter_inappwebview`; none today). Never
`url_launcher` to a browser. Callback intercepted in-app, verified, then unlock.
