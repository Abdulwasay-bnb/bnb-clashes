#!/usr/bin/env bash
# Play BNB Clashes (Godot 4.3). Pass --editor to open the project in the Godot editor instead.
GD="$HOME/Applications/godot/Godot_v4.3-stable_linux.x86_64"
unset DRI_PRIME   # this laptop has a single GPU
cd "$(dirname "$0")"
if [ "$1" = "--editor" ]; then exec "$GD" --editor --path .; else exec "$GD" --path .; fi
