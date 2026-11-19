#!/usr/bin/env bash
# Check that every System Settings pane the panel links to exists on this Mac.
# A click on a card opens `x-apple.systempreferences:<identifier>`. System Settings ignores an
# identifier it does not know, so a pane Apple renamed would fail without a word. The identifiers
# are read from the `SettingsPane` enum, and each must be registered by a settings extension:
# as its bundle identifier, or as a pane it hosts.
#
#   .github/scripts/check-settings-panes.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
source_file="$root/Sources/GlanceBar/AppDelegate.swift"
extensions="/System/Library/ExtensionKit/Extensions"

panes="$(awk '/^enum SettingsPane/ { inside = 1 } inside && /^}/ { inside = 0 } inside' "$source_file" \
  | grep -o '"com\.apple\.[^"]*"' | tr -d '"')"
[[ -n "$panes" ]] || { echo "No pane identifiers found in $source_file" >&2; exit 2; }
[[ -d "$extensions" ]] || { echo "No settings extensions at $extensions" >&2; exit 2; }

registered="$(for plist in "$extensions"/*.appex/Contents/Info.plist; do plutil -p "$plist"; done)"

missing=0
for pane in $panes; do
  if grep -qF "\"$pane\"" <<<"$registered"; then
    echo "ok       $pane"
  else
    echo "missing  $pane"
    missing=1
  fi
done
if [[ "$missing" != 0 ]]; then
  echo "A pane the panel links to is not registered on macOS $(sw_vers -productVersion)." >&2
  exit 1
fi
