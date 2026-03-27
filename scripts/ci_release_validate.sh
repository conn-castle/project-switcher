#!/usr/bin/env bash
set -euo pipefail

# Validate all release artifacts are properly signed, notarized, and stapled.
#
# Required environment variables:
#   VERSION     — e.g. "0.1.0"
#   RUNNER_TEMP

staging_path="$RUNNER_TEMP/staging"
artifacts_path="$RUNNER_TEMP/artifacts"

dmg="$artifacts_path/ProjectSwitcher-v${VERSION}-macos-arm64.dmg"
pkg="$artifacts_path/pswitcher-v${VERSION}-macos-arm64.pkg"
cli="$staging_path/pswitcher"

echo "=== Validating staged app bundle ==="
codesign --verify --deep --strict --verbose=2 "$staging_path/ProjectSwitcher.app"
spctl --assess --verbose=4 --type execute "$staging_path/ProjectSwitcher.app"

echo ""
echo "=== Validating CLI binary ==="
codesign --verify --deep --strict --verbose=2 "$cli"

echo ""
echo "=== Validating DMG signature ==="
codesign --verify --deep --strict "$dmg"

echo ""
echo "=== Validating DMG payload ==="
dmg_mount="$RUNNER_TEMP/dmg-verify"
mkdir -p "$dmg_mount"
hdiutil attach "$dmg" -mountpoint "$dmg_mount" -nobrowse -readonly -noverify
trap 'hdiutil detach "$dmg_mount" 2>/dev/null || true' EXIT

if [[ ! -d "$dmg_mount/ProjectSwitcher.app" ]]; then
  echo "error: ProjectSwitcher.app not found in DMG root" >&2
  echo "DMG contents:"
  ls -la "$dmg_mount/" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$dmg_mount/ProjectSwitcher.app"
spctl --assess --verbose=4 --type execute "$dmg_mount/ProjectSwitcher.app"

hdiutil detach "$dmg_mount" 2>/dev/null || true
trap - EXIT

echo ""
echo "=== Validating PKG ==="
pkgutil --check-signature "$pkg"
spctl --assess --verbose=4 --type install "$pkg"

echo ""
echo "ci_release_validate: OK — all artifacts verified"
