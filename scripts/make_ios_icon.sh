#!/bin/zsh
# Regenerates DeskiOS/Resources/Assets.xcassets/AppIcon.appiconset (one 1024 px icon, Brass on the dark plate) from
# the app's mark — the same art and colours as the Mac icon (scripts/make_app_icon.swift --ios).
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
cp scripts/make_app_icon.swift "$TMP/main.swift"
swiftc -D APPICON_TOOL -o "$TMP/make_app_icon" "$TMP/main.swift" \
  ThubanDesk/Views/Components/AppArt.swift ThubanDesk/Views/Components/AppArtSource.swift
OUT=DeskiOS/Resources/Assets.xcassets/AppIcon.appiconset
mkdir -p "$OUT"
find "$OUT" -name "*.png" -delete
"$TMP/make_app_icon" "$OUT" --ios
rm -rf "$TMP"
