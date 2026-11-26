#!/usr/bin/env bash
# Produce build/ios/ipa/Zangetsu-<version>.ipa on macOS.
#
#   scripts/ios-export.sh          # unsigned archive, for Sideloadly/AltStore
#   scripts/ios-export.sh --sign   # codesigned, needs the APPLE_* variables
#
# iOS builds only run on macOS with Xcode; this exists so CI and a local Mac
# use the same steps.
set -euo pipefail

SIGN=0
[ "${1:-}" = "--sign" ] && SIGN=1

VERSION=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1 | tr '+' '-')
OUT=build/ios/ipa
NAME="Zangetsu-${VERSION}.ipa"

if [ "$SIGN" = 0 ]; then
    flutter build ios --release --no-codesign
    rm -rf "$OUT"
    mkdir -p "$OUT/Payload"
    cp -R build/ios/iphoneos/Runner.app "$OUT/Payload/"
    (cd "$OUT" && zip -qry "$NAME" Payload && rm -rf Payload)
    echo "wrote $OUT/$NAME (unsigned)"
    exit 0
fi

: "${APPLE_CERT_P12_BASE64:?missing APPLE_CERT_P12_BASE64}"
: "${APPLE_CERT_PASSWORD:?missing APPLE_CERT_PASSWORD}"
: "${APPLE_PROVISIONING_PROFILE_BASE64:?missing APPLE_PROVISIONING_PROFILE_BASE64}"
: "${APPLE_TEAM_ID:?missing APPLE_TEAM_ID}"
BUNDLE_ID=${APPLE_BUNDLE_ID:-$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \(.*\);/\1/p' ios/Runner.xcodeproj/project.pbxproj | head -1)}
METHOD=${APPLE_EXPORT_METHOD:-ad-hoc}
KEYCHAIN=build.keychain
KEYCHAIN_PASSWORD=$(openssl rand -hex 16)

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security default-keychain -s "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
printf '%s' "$APPLE_CERT_P12_BASE64" | base64 -d > /tmp/cert.p12
security import /tmp/cert.p12 -k "$KEYCHAIN" -P "$APPLE_CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
rm -f /tmp/cert.p12

PROFILES="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILES"
printf '%s' "$APPLE_PROVISIONING_PROFILE_BASE64" | base64 -d > "$PROFILES/zangetsu.mobileprovision"
PROFILE_NAME=$(security cms -D -i "$PROFILES/zangetsu.mobileprovision" | plutil -extract Name raw -)

cat > /tmp/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>${METHOD}</string>
    <key>teamID</key><string>${APPLE_TEAM_ID}</string>
    <key>signingStyle</key><string>manual</string>
    <key>provisioningProfiles</key>
    <dict><key>${BUNDLE_ID}</key><string>${PROFILE_NAME}</string></dict>
</dict>
</plist>
PLIST

flutter build ipa --release --export-options-plist /tmp/ExportOptions.plist
echo "wrote $OUT/$NAME"
