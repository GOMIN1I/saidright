#!/bin/zsh
# Packages build/Saidright.app into dist/Saidright-<version>.dmg. Build and sign the app first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
APP="${SAIDRIGHT_APP:-$ROOT/build/Saidright.app}"
[[ -d "$APP" ]] || { echo "Build the app first: scripts/build-app.sh" >&2; exit 1; }
codesign --verify --strict "$APP"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$ROOT/dist"
LABEL="${SAIDRIGHT_DMG_LABEL--dev-preview-unnotarized}"
DMG="${SAIDRIGHT_DMG:-$ROOT/dist/Saidright-$VERSION$LABEL.dmg}"
rm -f "$DMG"
hdiutil create -volname "Saidright $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1
rm -rf "$STAGE"
echo "Created $DMG ($(du -h "$DMG" | cut -f1)). Notarize before publishing; see docs/RELEASE.md."
