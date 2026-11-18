#!/usr/bin/env bash
# Download the latest released "Glance Bar.app", check it and install it. No Swift toolchain needed.
#
#   curl -fsSL https://raw.githubusercontent.com/RobinVivant/glance-bar/main/scripts/get.sh | bash
#
# GLANCE_BAR_DIR      where the app goes (default: ~/Applications)
# GLANCE_BAR_VERSION  the release to install, such as 1.0.0 (default: the latest)
# GLANCE_BAR_NO_OPEN  set to 1 to install without quitting a running copy or opening the new one
set -euo pipefail

repo="https://github.com/RobinVivant/glance-bar"
work=""  # the download folder; global, so the exit trap can still read it after main returns
trap '[[ -z "$work" ]] || rm -rf "$work"' EXIT

fail() {
  echo "Glance Bar install: $1" >&2
  exit 1
}

# The whole script runs from this function, so a download that stops halfway runs nothing.
main() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "this app runs on macOS only."
  [[ "$(uname -m)" == "arm64" ]] || fail "the app runs on Apple silicon only."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [[ "$major" -ge 15 ]] || fail "macOS 15 or later is required (this Mac runs $(sw_vers -productVersion))."

  local version="${GLANCE_BAR_VERSION:-}"
  if [[ -z "$version" ]]; then
    # The "latest" page redirects to the newest tag; this needs no API call and no rate limit.
    local latest
    latest="$(curl -fsSI -o /dev/null -w '%{redirect_url}' "$repo/releases/latest")"
    version="${latest##*/v}"
    [[ "$latest" == */releases/tag/v* && -n "$version" ]] || fail "could not find the latest release at $repo/releases."
  fi

  local zip="Glance-Bar-$version-arm64.zip"
  local dir="${GLANCE_BAR_DIR:-$HOME/Applications}"
  local dest="$dir/Glance Bar.app"
  work="$(mktemp -d)"

  echo "Downloading Glance Bar $version"
  curl -fsSL -o "$work/$zip" "$repo/releases/download/v$version/$zip" ||
    fail "could not download $zip from release v$version."
  curl -fsSL -o "$work/$zip.sha256" "$repo/releases/download/v$version/$zip.sha256" ||
    fail "could not download the checksum of release v$version."
  (cd "$work" && shasum -a 256 -c "$zip.sha256" >/dev/null) || fail "the download does not match its checksum."

  ditto -x -k "$work/$zip" "$work"
  codesign --verify --strict "$work/Glance Bar.app" || fail "the app's signature is not valid."

  if [[ "${GLANCE_BAR_NO_OPEN:-}" != "1" ]] && pgrep -xq GlanceBar; then
    osascript -e 'tell application id "local.glance-bar" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do
      pgrep -xq GlanceBar || break
      sleep 1
    done
    pkill -x GlanceBar 2>/dev/null || true
  fi

  mkdir -p "$dir"
  rm -rf "$dest"
  ditto "$work/Glance Bar.app" "$dest"
  echo "Installed $dest"
  if [[ "${GLANCE_BAR_NO_OPEN:-}" != "1" ]]; then
    open "$dest"
  fi
}

main "$@"
