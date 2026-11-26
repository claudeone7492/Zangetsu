#!/usr/bin/env bash
# Restore the release signing key into a fresh sandbox.
#
# The keystore and its passwords live in the GitLab project's CI/CD settings
# (project exploit7492/Zangetsu). GitHub holds the same values as Actions
# secrets, but those are write-only, so GitLab is the copy you can read back.
#
#   GITLAB_TOKEN=... scripts/restore-signing-key.sh
#
# Writes $KEYSTORE_PATH (default /workspace/keys/zangetsu-release.jks) and
# android/key.properties, then checks the certificate really is the one the
# published APKs are signed with.
set -uo pipefail

PROJECT=${GITLAB_PROJECT:-exploit7492/Zangetsu}
GITLAB=${GITLAB_HOST:-https://gitlab.com}
KEYSTORE=${KEYSTORE_PATH:-/workspace/keys/zangetsu-release.jks}
KEYPROPS=${KEY_PROPERTIES_PATH:-android/key.properties}
PRODUCTION_CERT=805c450aedab52b2c93b8f68f12a8a9070cfd2439b3c43f12e570a76b800b344

die() { printf '%s\n' "$*" >&2; exit 1; }
: "${GITLAB_TOKEN:?set GITLAB_TOKEN to a token with maintainer access to $PROJECT}"

enc=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$PROJECT")
api() { curl -sS --fail-with-body --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$@"; }
var() {
    api "$GITLAB/api/v4/projects/$enc/variables/$1" |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])'
}

mkdir -p "$(dirname "$KEYSTORE")"
chmod 700 "$(dirname "$KEYSTORE")" 2>/dev/null || true

# Keystore: the base64 variable is the primary copy, the secure file is the
# fallback for projects where the variable was rotated away.
if b64=$(var ANDROID_KEYSTORE_BASE64 2>/dev/null) && [ -n "$b64" ]; then
    printf '%s' "$b64" | base64 -d > "$KEYSTORE"
else
    printf 'ANDROID_KEYSTORE_BASE64 missing, trying the secure file\n' >&2
    sid=$(api "$GITLAB/api/v4/projects/$enc/secure_files" |
        python3 -c 'import json,sys
for f in json.load(sys.stdin):
    if f["name"] == "zangetsu-release.jks": print(f["id"]); break')
    [ -n "$sid" ] || die "no keystore in CI variables or secure files on $PROJECT"
    api "$GITLAB/api/v4/projects/$enc/secure_files/$sid/download" > "$KEYSTORE"
fi
chmod 600 "$KEYSTORE"
[ -s "$KEYSTORE" ] || die "restored keystore is empty"

store_pass=$(var ANDROID_KEYSTORE_PASSWORD)
key_pass=$(var ANDROID_KEY_PASSWORD)
alias_name=$(var ANDROID_KEY_ALIAS)
printf 'storePassword=%s\nkeyPassword=%s\nkeyAlias=%s\nstoreFile=%s\n' \
    "$store_pass" "$key_pass" "$alias_name" "$KEYSTORE" > "$KEYPROPS"
chmod 600 "$KEYPROPS"

find_java() {
    command -v keytool >/dev/null 2>&1 && { command -v keytool; return; }
    local jdk=${JAVA_HOME:-/workspace/toolchain/jdk}
    [ -x "$jdk/bin/keytool" ] && printf '%s\n' "$jdk/bin/keytool"
}
KEYTOOL=$(find_java) || die "keytool not found; run scripts/restore-env.sh first"
cert=$("$KEYTOOL" -list -v -keystore "$KEYSTORE" -storepass "$store_pass" \
    -alias "$alias_name" 2>/dev/null |
    awk '/SHA256:/ {print $2; exit}' | tr -d ':' | tr 'A-F' 'a-f')
[ -n "$cert" ] || die "could not read the certificate out of $KEYSTORE"
[ "$cert" = "$PRODUCTION_CERT" ] ||
    die "restored key is $cert, not the production $PRODUCTION_CERT"

printf 'restored %s\n  cert %s\n  properties %s\n' "$KEYSTORE" "$cert" "$KEYPROPS"
