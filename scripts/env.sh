#!/usr/bin/env bash
# Source this before any Flutter/Dart/Gradle command:
#
#   source scripts/env.sh
#
# A sandbox restart wipes $HOME, /tmp and /opt (they sit on the overlay root
# filesystem). Only /workspace is a persistent volume. Everything a build
# needs — the toolchain *and* the package/Gradle caches — therefore lives under
# /workspace so a restart no longer forces a cold re-download.
#
# `restore-env.sh` installs the toolchain; this file only points the shell at it.

ROOT=/workspace/toolchain

export JAVA_HOME="$ROOT/jdk"
export ANDROID_HOME="$ROOT/android-sdk"
export ANDROID_SDK_ROOT="$ROOT/android-sdk"

# Keep pub's cache and Gradle's home on the persistent volume. Without these,
# `flutter pub get` and `flutter build apk` re-download hundreds of MB into
# $HOME on every restart.
export PUB_CACHE="$ROOT/pub-cache"
export GRADLE_USER_HOME="$ROOT/gradle"

export PATH="$JAVA_HOME/bin:$ROOT/flutter/bin:$PATH"
