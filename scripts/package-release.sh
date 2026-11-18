#!/usr/bin/env bash
# Build "Glance Bar.app" and zip it for a GitHub release.
# Writes build/Glance-Bar-<version>-arm64.zip and its .sha256 file, and prints the zip's path.
# With a tag as the argument (v1.2.3), fails unless it matches the version in Resources/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -gt 1 ]]; then
  echo "Usage: scripts/package-release.sh [tag]" >&2
  exit 2
fi

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
if [[ $# -eq 1 && "$1" != "v$version" ]]; then
  echo "Tag $1 does not match version $version in Resources/Info.plist" >&2
  exit 1
fi

scripts/build-app.sh >&2
app="build/Glance Bar.app"
codesign --verify --strict "$app"

zip="build/Glance-Bar-$version-arm64.zip"
rm -f "$zip" "$zip.sha256"
# Without extended attributes: the signature lives in the bundle's files, and the attributes
# would only add the build machine's provenance marks as __MACOSX entries.
ditto -c -k --norsrc --noextattr --keepParent "$app" "$zip"
(cd build && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
echo "$zip"
