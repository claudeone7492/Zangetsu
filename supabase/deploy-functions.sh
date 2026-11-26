#!/usr/bin/env bash
# Deploys the Sophie edge functions that back the Zangetsu paywall.
#
# The Management API takes a single bundled file per function, so each entry
# point is bundled with esbuild first (bundling resolves the ../_shared imports).
#
#   SUPABASE_ACCESS_TOKEN=... ./supabase/deploy-functions.sh [slug ...]
#
# Runtime secrets the paywall reads (set with `supabase secrets set` or the
# dashboard):
#
#   KORAPAY_MODE=live                 KORAPAY_LIVE_SECRET_KEY
#   KORAPAY_LIVE_PUBLIC_KEY           KORAPAY_MERCHANT_EMAIL
#   FLUTTERWAVE_MODE=live             FLUTTERWAVE_LIVE_SECRET_KEY
#   FLUTTERWAVE_WEBHOOK_SECRET        (dashboard "secret hash")
#   PAYMENT_RETURN_BASE_URL           (optional callback base override)
#   PAYMENT_RETURN_ALLOWED_HOSTS      (optional; default
#                                      zangetsu.online,edgesenterprise.com)
#   KORA_ACTIVE_CURRENCIES            (optional comma list, see routing)
#
# The already-registered `FLUTTERWAVE_SECRETE_KEY` name is accepted as a live
# alias, so the existing secret works unchanged. Hosted checkout needs only the
# secret key; the public/encryption keys are not read because card data stays on
# Flutterwave's page.
#
# No Flutterwave webhook is required. After the browser returns, the app polls
# `stream-subscribe` with {"action":"verify"}, and the function asks
# Flutterwave's verify-by-reference endpoint with the secret key before it
# credits the charge. Configuring the dashboard webhook at
# https://<project>.supabase.co/functions/v1/flutterwave-webhook is optional;
# if it is used, its "secret hash" must equal FLUTTERWAVE_WEBHOOK_SECRET.
#
# Both gateways get the callback the app sends in `returnUrl`
# (https://edgesenterprise.com/payment/return on current builds). That page
# lives on a separate, globally reachable domain because the main site is
# blocked in some regions. Older builds send nothing and keep the legacy
# zangetsu.online URL, so deploying this function before the app cannot strand
# them. The hint is pinned to PAYMENT_RETURN_ALLOWED_HOSTS so it cannot become
# an open redirect; PAYMENT_RETURN_BASE_URL overrides it without an app release.
#
# Deploy `payment-return/index.html` at that path (for the Next.js site:
# `public/payment/return.html` plus a `/payment/return` rewrite, or any static
# host). The app's WebView intercepts the URL before the page loads, so the
# document is only the external-browser fallback.
set -euo pipefail

REF="${SUPABASE_PROJECT_REF:-lmjeickcvynwqsvustwq}"
TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
[ -n "$TOKEN" ] || { echo "SUPABASE_ACCESS_TOKEN is not set" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FN_DIR="$ROOT/supabase/functions"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

SLUGS=("$@")
if [ ${#SLUGS[@]} -eq 0 ]; then
  SLUGS=(stream-subscribe korapay-webhook flutterwave-webhook)
fi

for slug in "${SLUGS[@]}"; do
  entry="$FN_DIR/$slug/index.ts"
  [ -f "$entry" ] || { echo "missing entry point: $entry" >&2; exit 1; }

  npx --yes esbuild "$entry" --bundle --format=esm --platform=neutral \
    --target=deno1.46 --external:jsr:* --external:npm:* \
    --outfile="$OUT/$slug.js" >/dev/null

  payload="$(python3 - "$slug" "$OUT/$slug.js" <<'PY'
import json, sys
slug, path = sys.argv[1], sys.argv[2]
body = open(path).read()
print(json.dumps({"slug": slug, "name": slug, "verify_jwt": False, "body": body}))
PY
)"

  code="$(curl -sS -m 120 -o "$OUT/$slug.resp" -w '%{http_code}' \
    -X POST "https://api.supabase.com/v1/projects/$REF/functions" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$payload")"

  if [ "$code" = "409" ] || grep -qi "duplicat" "$OUT/$slug.resp"; then
    # Already exists: PATCH replaces the body in place.
    code="$(curl -sS -m 120 -o "$OUT/$slug.resp" -w '%{http_code}' \
      -X PATCH "https://api.supabase.com/v1/projects/$REF/functions/$slug" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "$payload")"
  fi

  echo "$slug -> $code $(head -c 200 "$OUT/$slug.resp")"
done
