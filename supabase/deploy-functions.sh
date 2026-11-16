#!/usr/bin/env bash
# Deploys the Sophie edge functions that back the Zangetsu paywall.
#
# The Management API takes a single bundled file per function, so each entry
# point is bundled with esbuild first (bundling resolves the ../_shared imports).
#
#   SUPABASE_ACCESS_TOKEN=... ./supabase/deploy-functions.sh [slug ...]
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
  SLUGS=(stream-subscribe korapay-webhook)
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
