#!/usr/bin/env bash
# Build the Android APK (debug-signed, arm64). Output: build/android/BNBClashes.apk
# Needs: JDK 17, Android SDK (build-tools 34) and Godot 4.3 Android export templates.
# Their paths live in Godot's editor settings (export/android/java_sdk_path, android_sdk_path).
set -euo pipefail
cd "$(dirname "$0")"
GD="$HOME/Applications/godot/Godot_v4.7.2-stable_linux.x86_64"
mkdir -p build/android && touch build/.gdignore
"$GD" --headless --path . --import >/dev/null 2>&1 || true
"$GD" --headless --path . --export-debug "Android" build/android/BNBClashes.apk
echo "APK: $(pwd)/build/android/BNBClashes.apk"
echo "Install on a phone with USB debugging:  ~/Android/Sdk/platform-tools/adb install -r build/android/BNBClashes.apk"
