#!/usr/bin/env bash
# Registers the Zangetsu admin console login from environment secrets.
#
#   JUMP_EMAIL=... JUMP_PASSWORD=... SUPABASE_ACCESS_TOKEN=... \
#     ./supabase/register-admin.sh
#
# The password is hashed in Postgres; it is never written to this repository or
# printed by the script. Existing owner rows are updated in place so rotating
# the credential is just another run.
set -euo pipefail

REF="${SUPABASE_PROJECT_REF:-lmjeickcvynwqsvustwq}"
TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
EMAIL="${JUMP_EMAIL:-}"
PASSWORD="${JUMP_PASSWORD:-}"

[ -n "$TOKEN" ] || { echo "SUPABASE_ACCESS_TOKEN is not set" >&2; exit 1; }
[ -n "$EMAIL" ] || { echo "JUMP_EMAIL is not set" >&2; exit 1; }
[ -n "$PASSWORD" ] || { echo "JUMP_PASSWORD is not set" >&2; exit 1; }

python3 - "$REF" "$TOKEN" "$EMAIL" "$PASSWORD" <<'PY'
import json
import sys
import urllib.error
import urllib.request

ref, token, email, password = sys.argv[1:5]


def quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


sql = f"""
update public.admins
   set email = lower({quote(email)}),
       label = {quote(email)},
       passcode_hash = extensions.crypt({quote(password)}, extensions.gen_salt('bf')),
       active = true
 where role = 'owner';

insert into public.admins (label, email, passcode_hash, role)
select {quote(email)}, lower({quote(email)}),
       extensions.crypt({quote(password)}, extensions.gen_salt('bf')), 'owner'
where not exists (select 1 from public.admins where active);
"""

request = urllib.request.Request(
    f"https://api.supabase.com/v1/projects/{ref}/database/query",
    data=json.dumps({"query": sql}).encode(),
    headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    },
    method="POST",
)

try:
    with urllib.request.urlopen(request, timeout=60) as response:
        if response.status not in (200, 201):
            raise SystemExit(f"admin registration failed: HTTP {response.status}")
except urllib.error.HTTPError as error:
    detail = error.read().decode(errors="replace")[:500]
    raise SystemExit(f"admin registration failed: HTTP {error.code} {detail}")

print("admin login registered")
PY
