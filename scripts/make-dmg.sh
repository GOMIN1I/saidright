#!/bin/zsh
# Packages build/Saywell.app into dist/Saywell-<version>.dmg. Build and sign the app first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
APP="${SAYWELL_APP:-$ROOT/build/Saywell.app}"
[[ -d "$APP" ]] || { echo "Build the app first: scripts/build-app.sh" >&2; exit 1; }
codesign --verify --strict "$APP"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$ROOT/dist"
LABEL="${SAYWELL_DMG_LABEL--dev-preview-unnotarized}"
DMG="${SAYWELL_DMG:-$ROOT/dist/Saywell-$VERSION$LABEL.dmg}"
rm -f "$DMG"
hdiutil create -volname "Saywell $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1
rm -rf "$STAGE"
echo "Created $DMG ($(du -h "$DMG" | cut -f1)). Notarize before publishing; see docs/RELEASE.md."
