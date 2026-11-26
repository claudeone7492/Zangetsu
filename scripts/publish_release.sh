#!/usr/bin/env bash
# Publish a signed APK as a GitHub release, refusing to publish a build whose
# signer is not the one users already have installed. zangetsu.online reads
# `releases/latest`, so publishing is all it takes for the site to follow.
#
#   scripts/publish_release.sh --repo Spyou/Zangetsu --tag v2.3.7 \
#       --apk build/app/outputs/flutter-apk/app-release.apk \
#       --asset-name Zangetsu.apk --notes notes.md
#
# Add --dry-run to print the API calls without making them.
set -uo pipefail

PRODUCTION_CERT=13bed97f2409b69a0aa44361b30c3756edf52315aea73eb3ad13ec03c3cf9662
REPO= TAG= APK= ASSET_NAME= NOTES= EXPECT=$PRODUCTION_CERT DRY_RUN=0

die() { printf '%s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO=$2; shift 2 ;;
        --tag) TAG=$2; shift 2 ;;
        --apk) APK=$2; shift 2 ;;
        --asset-name) ASSET_NAME=$2; shift 2 ;;
        --notes) NOTES=$2; shift 2 ;;
        --expect) EXPECT=$2; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -n "$REPO" ] && [ -n "$TAG" ] && [ -n "$APK" ] || die "usage: $0 --repo owner/name --tag vX --apk file.apk [--asset-name name.apk] [--notes file] [--expect sha256] [--dry-run]"
[ -f "$APK" ] || die "no such APK: $APK"
[ -n "$ASSET_NAME" ] || ASSET_NAME=$(basename "$APK")
[ -n "$NOTES" ] && [ -f "$NOTES" ] || NOTES=/dev/null

find_apksigner() {
    if command -v apksigner >/dev/null 2>&1; then command -v apksigner; return; fi
    local sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
    [ -n "$sdk" ] || return 1
    ls -d "$sdk"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1
}

APKSIGNER=$(find_apksigner) || die "apksigner not found; set ANDROID_HOME or put it on PATH"
CERT=$("$APKSIGNER" verify --print-certs "$APK" 2>/dev/null \
    | awk '/SHA-256 digest/ {print $NF; exit}')
[ -n "$CERT" ] || die "could not read the signing certificate of $APK"

CERT=$(printf '%s' "$CERT" | tr 'A-F' 'a-f')
EXPECT=$(printf '%s' "$EXPECT" | tr -d ':' | tr 'A-F' 'a-f')
if [ "$CERT" != "$EXPECT" ]; then
    die "$(printf 'refusing to publish: %s is signed by %s, not %s.\nUsers on the published build cannot upgrade across a different key, so this\nwould force an uninstall. Re-sign with the production keystore first\n(android/key.properties -> storeFile/storePassword/keyAlias/keyPassword).' \
        "$APK" "$CERT" "$EXPECT")"
fi

NAME=${TAG#v}
BODY=$(cat "$NOTES")

if [ "$DRY_RUN" = 1 ]; then
    printf 'dry run: would publish %s to %s as %s\n' "$APK" "$REPO" "$TAG"
    printf '  POST /repos/%s/releases  {"tag_name":"%s","name":"%s"}\n' "$REPO" "$TAG" "$NAME"
    printf '  POST https://uploads.github.com/repos/%s/releases/<id>/assets?name=%s\n' \
        "$REPO" "$ASSET_NAME"
    exit 0
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN must hold a token with write access to $REPO}"
api() {
    local method=$1 url=$2 data=${3:-}
    if [ -n "$data" ]; then
        curl -sS -X "$method" -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "Content-Type: application/json" -d "$data" "$url"
    else
        curl -sS -X "$method" -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" "$url"
    fi
}

json() { python3 -c "import json,sys; d=json.load(sys.stdin); print(d$1)" 2>/dev/null; }

release_id=$(api GET "https://api.github.com/repos/$REPO/releases/tags/$TAG" | json "['id']")
if [ -z "$release_id" ]; then
    payload=$(python3 -c 'import json,sys; print(json.dumps({"tag_name":sys.argv[1],"name":sys.argv[2],"body":sys.argv[3]}))' \
        "$TAG" "$NAME" "$BODY")
    release_id=$(api POST "https://api.github.com/repos/$REPO/releases" "$payload" | json "['id']")
    [ -n "$release_id" ] || die "could not create the release on $REPO"
    printf 'created release %s on %s\n' "$TAG" "$REPO"
fi

curl -sS -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/vnd.android.package-archive" \
    --data-binary "@$APK" \
    "https://uploads.github.com/repos/$REPO/releases/$release_id/assets?name=$ASSET_NAME" \
    | json "['browser_download_url']"
