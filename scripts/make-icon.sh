#!/bin/zsh
# Renders the app icon from the SwiftUI source (Sources/Saidright/UI/Branding.swift, AppIconArt)
# so the bundle icon, Dock variants and in-app previews share one geometry.
#   scripts/make-icon.sh        → Resources/AppIcon.icns and assets/brand/*.png
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$ROOT" --product Saidright >/dev/null
BIN="$(swift build --package-path "$ROOT" --show-bin-path)/Saidright"
TMP="$(mktemp -d)"
for variant in standard light mono; do
  "$BIN" --render-icon "$TMP/$variant.iconset" "$variant"
  cp "$TMP/$variant.iconset/icon_512x512@2x.png" "$ROOT/assets/brand/app-icon-$variant-1024.png"
done
iconutil -c icns "$TMP/standard.iconset" -o "$ROOT/Resources/AppIcon.icns"
# Layers for the Icon Composer icon (Resources/AppIcon.icon, compiled by build-app.sh).
"$BIN" --render-icon-layers "$ROOT/Resources/AppIcon.icon/Assets"
cp "$TMP/standard.iconset/icon_512x512@2x.png" "$ROOT/assets/brand/app-icon-1024.png"
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns and assets/brand/app-icon-*.png"
