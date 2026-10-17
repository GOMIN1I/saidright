#!/bin/zsh
# Sets the app's bundle identifier in one place (Resources/Info.plist; build-app.sh reads it).
#   scripts/set-bundle-id.sh <github-user>        → io.github.<user>.saidright
#   scripts/set-bundle-id.sh --id com.example.saidright
# After a change macOS treats the app as new: grant Microphone, Input Monitoring and
# Accessibility again once, and allow Keychain access when asked (the saved key is kept).
# Data in ~/Library/Application Support/Saidright is not affected.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
if [[ "${1:-}" == "--id" ]]; then
  ID="${2:?usage: set-bundle-id.sh --id <reverse.dns.id>}"
else
  USER_NAME="${1:?usage: set-bundle-id.sh <github-user>}"
  # GitHub user names: letters, digits, single hyphens. Bundle ids are case-insensitive.
  [[ "$USER_NAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]] || { echo "not a GitHub user name: $USER_NAME" >&2; exit 1; }
  ID="io.github.${USER_NAME:l}.saidright"
fi
[[ "$ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { echo "not a valid bundle id: $ID" >&2; exit 1; }
OLD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$PLIST")"
/usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $ID" "$PLIST"
echo "Bundle id: $OLD → $ID"
