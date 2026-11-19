#!/usr/bin/env bash
# Rebuild the Zangetsu build toolchain on the PERSISTENT volume after a sandbox
# restart. A restart wipes /opt and $HOME (Flutter, pub cache, Gradle cache),
# so everything the build needs is installed under /workspace/toolchain and
# reused across restarts. Idempotent: anything already present is skipped.
set -uo pipefail

ROOT=/workspace/toolchain
FLUTTER_VERSION=3.44.9
NDK_VERSION=28.2.13676358
CMDTOOLS_URL=https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
JDK_URL="https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"

mkdir -p "$ROOT"

# --- Flutter ---------------------------------------------------------------
if [ ! -x "$ROOT/flutter/bin/flutter" ]; then
  echo "==> Installing Flutter $FLUTTER_VERSION"
  curl -sL -o "$ROOT/flutter.tar.xz" "$FLUTTER_URL" &&
    tar xf "$ROOT/flutter.tar.xz" -C "$ROOT" && rm -f "$ROOT/flutter.tar.xz"
else
  echo "==> Flutter present"
fi
git config --global --add safe.directory "$ROOT/flutter" 2>/dev/null || true

# --- JDK 17 ----------------------------------------------------------------
if [ ! -x "$ROOT/jdk/bin/java" ]; then
  echo "==> Installing Temurin JDK 17"
  mkdir -p "$ROOT/jdk"
  curl -sL -o "$ROOT/jdk.tar.gz" "$JDK_URL" &&
    tar xzf "$ROOT/jdk.tar.gz" -C "$ROOT/jdk" --strip-components=1 && rm -f "$ROOT/jdk.tar.gz"
else
  echo "==> JDK present"
fi
export JAVA_HOME="$ROOT/jdk"
export PATH="$JAVA_HOME/bin:$ROOT/flutter/bin:$PATH"

# --- Android SDK -----------------------------------------------------------
SDK="$ROOT/android-sdk"
if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "==> Installing Android cmdline-tools"
  mkdir -p "$SDK"
  curl -sL -o "$ROOT/cmdtools.zip" "$CMDTOOLS_URL" &&
    (cd "$SDK" && python3 -c "import zipfile;zipfile.ZipFile('$ROOT/cmdtools.zip').extractall('.')") &&
    rm -f "$ROOT/cmdtools.zip"
  mkdir -p "$SDK/cmdline-tools"
  mv "$SDK/cmdline-tools/cmdline-tools" "$SDK/cmdline-tools/latest" 2>/dev/null || true
  chmod +x "$SDK/cmdline-tools/latest/bin/"*
else
  echo "==> Android cmdline-tools present"
fi

if [ ! -d "$SDK/platforms/android-36" ]; then
  echo "==> Accepting licenses + installing SDK packages"
  yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" --licenses >/dev/null 2>&1
  "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" \
    "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;$NDK_VERSION"
else
  echo "==> Android SDK packages present"
fi

echo
echo "Environment ready. Export for build shells:"
echo "  export JAVA_HOME=$ROOT/jdk ANDROID_HOME=$SDK ANDROID_SDK_ROOT=$SDK"
echo "  export PATH=\"$ROOT/jdk/bin:$ROOT/flutter/bin:\$PATH\""

# --- Persistent caches -----------------------------------------------------
# Keep pub's cache and Gradle's home on the persistent volume too, so restarts
# do not re-download dependencies. Point the shell at them with scripts/env.sh.
mkdir -p "$ROOT/pub-cache" "$ROOT/gradle"
echo
echo "Persistent caches: PUB_CACHE=$ROOT/pub-cache GRADLE_USER_HOME=$ROOT/gradle"
echo "For a fully prepared shell, use:  source scripts/env.sh"

