#!/usr/bin/env bash
# Build the Windows and Linux versions (single self-contained executables) and zip them.
# Output: build/BNBClashes-windows.zip, build/BNBClashes-linux.zip
# Needs the Godot 4.3 export templates (windows_*_x86_64.exe, linux_*.x86_64).
set -euo pipefail
cd "$(dirname "$0")"
GD="$HOME/Applications/godot/Godot_v4.3-stable_linux.x86_64"
mkdir -p build/windows build/linux && touch build/.gdignore
"$GD" --headless --path . --import >/dev/null 2>&1 || true
"$GD" --headless --path . --export-release "Windows Desktop" build/windows/BNBClashes.exe
"$GD" --headless --path . --export-release "Linux" build/linux/BNBClashes.x86_64
(cd build/windows && rm -f ../BNBClashes-windows.zip && zip -q ../BNBClashes-windows.zip BNBClashes.exe *.dll)
(cd build/linux && chmod +x BNBClashes.x86_64 && rm -f ../BNBClashes-linux.zip && zip -q ../BNBClashes-linux.zip BNBClashes.x86_64 *.so)
ls -la build/*.zip
