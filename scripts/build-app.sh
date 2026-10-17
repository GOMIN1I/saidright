#!/bin/zsh
# Builds build/Saidright.app from source.
#
#   scripts/build-app.sh                 release build, signed with an Apple Development
#                                        identity if one exists, otherwise ad hoc
#   SAIDRIGHT_SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#   SAIDRIGHT_CONFIGURATION=debug scripts/build-app.sh
#
#   SAIDRIGHT_SIGN_IDENTITY=- SAIDRIGHT_BUILD_DIR=build/public scripts/build-app.sh
#                                        ad hoc build for public downloads (no personal
#                                        certificate or team id inside the app)
#
# Ad hoc signatures change on every build, and macOS then forgets Microphone, Input
# Monitoring and Accessibility grants. A stable identity keeps them across rebuilds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${SAIDRIGHT_CONFIGURATION:-release}"
VERSION="$(cat "$ROOT/VERSION")"
BUILD_NUMBER="${SAIDRIGHT_BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
# SAIDRIGHT_BUILD_DIR builds elsewhere (e.g. a public ad hoc build) without replacing build/Saidright.app.
OUT="${SAIDRIGHT_BUILD_DIR:-$ROOT/build}"
APP="$OUT/Saidright.app"
# The bundle id lives only in Resources/Info.plist (change it with scripts/set-bundle-id.sh).
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$ROOT/Resources/Info.plist")"

swift build -c "$CONFIG" --package-path "$ROOT" --product Saidright
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/Saidright"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Saidright"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
cp "$ROOT/Resources/recognizer.py" "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
# macOS 26+: Icon Composer icon with automatic dark and tinted appearances (Assets.car).
# The .icns stays as the icon for older systems and for Finder previews.
if xcrun --find actool >/dev/null 2>&1; then
  ICONTMP="$(mktemp -d)"
  if xcrun actool --compile "$ICONTMP" --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
       --output-partial-info-plist "$ICONTMP/partial.plist" "$ROOT/Resources/AppIcon.icon" >/dev/null 2>&1; then
    cp "$ICONTMP/Assets.car" "$APP/Contents/Resources/Assets.car"
  else
    echo "warning: actool could not compile Resources/AppIcon.icon; using AppIcon.icns only" >&2
  fi
  rm -rf "$ICONTMP"
fi
cp "$ROOT/Runtime/requirements.lock" "$APP/Contents/Resources/requirements.lock"
cp "$ROOT/Runtime/requirements-parakeet.lock" "$APP/Contents/Resources/requirements-parakeet.lock"
for lproj in "$ROOT"/Resources/Localization/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done
xattr -cr "$APP" 2>/dev/null || true

IDENTITY="${SAIDRIGHT_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -nE 's/^[[:space:]]+[0-9]+\) ([A-F0-9]{40}) "(Developer ID Application|Apple Development):.*/\1/p' | head -1)"
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
  echo "warning: no signing identity found; signing ad hoc. Permissions will need to be granted again after each rebuild." >&2
fi
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" \
  --identifier "$BUNDLE_ID" --entitlements "$ROOT/Resources/entitlements.plist" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($BUNDLE_ID $VERSION, build $BUILD_NUMBER, $CONFIG, identity ${IDENTITY:0:12})"
