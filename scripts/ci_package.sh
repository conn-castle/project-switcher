#!/usr/bin/env bash
set -euo pipefail

# Package staged artifacts into DMG, PKG, and tarball for distribution.
#
# Required environment variables:
#   DEVELOPER_ID_APP_IDENTITY       — for DMG codesigning
#   DEVELOPER_ID_INSTALLER_IDENTITY — for PKG signing
#   VERSION                         — e.g. "0.1.0"
#   CLI_INSTALL_PATH                — e.g. "/usr/local/bin/pswitcher"
#   RUNNER_TEMP

staging_path="$RUNNER_TEMP/staging"
artifacts_path="$RUNNER_TEMP/artifacts"

mkdir -p "$artifacts_path"

# --- Validate inputs ---
if [[ ! -d "$staging_path/ProjectSwitcher.app" ]]; then
  echo "error: staged app not found at $staging_path/ProjectSwitcher.app" >&2
  exit 1
fi
if [[ ! -x "$staging_path/pswitcher" ]]; then
  echo "error: staged CLI binary not found at $staging_path/pswitcher" >&2
  exit 1
fi
if [[ -z "${CLI_INSTALL_PATH:-}" ]]; then
  echo "error: CLI_INSTALL_PATH is not set or empty" >&2
  exit 1
fi
if [[ "$CLI_INSTALL_PATH" != /* ]]; then
  echo "error: CLI_INSTALL_PATH must be an absolute path, got: $CLI_INSTALL_PATH" >&2
  exit 1
fi
if ! command -v create-dmg &>/dev/null; then
  echo "error: create-dmg not found" >&2
  echo "Fix: brew install create-dmg" >&2
  exit 1
fi

# --- DMG ---
dmg_name="ProjectSwitcher-v${VERSION}-macos-arm64.dmg"
echo "Creating DMG: $dmg_name"

# create-dmg expects a source directory; it copies the directory's contents into the DMG.
# Stage the .app inside a temp directory so the DMG root contains ProjectSwitcher.app.
dmg_source="$RUNNER_TEMP/dmg-source"
rm -rf "$dmg_source"
mkdir -p "$dmg_source"
cp -R "$staging_path/ProjectSwitcher.app" "$dmg_source/ProjectSwitcher.app"

# create-dmg returns exit code 2 when it successfully creates the DMG but
# cannot set a custom icon (common in headless CI). Accept 0 and 2 as success
# when the output file exists.
dmg_exit=0
create-dmg \
  --volname "ProjectSwitcher" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "ProjectSwitcher.app" 150 190 \
  --app-drop-link 450 190 \
  --no-internet-enable \
  "$artifacts_path/$dmg_name" \
  "$dmg_source" \
  || dmg_exit=$?

if [[ $dmg_exit -ne 0 && $dmg_exit -ne 2 ]]; then
  echo "error: create-dmg failed with exit code $dmg_exit" >&2
  exit 1
fi
if [[ ! -f "$artifacts_path/$dmg_name" ]]; then
  echo "error: create-dmg exited $dmg_exit but DMG was not created" >&2
  exit 1
fi
if [[ $dmg_exit -eq 2 ]]; then
  echo "warning: create-dmg exited 2 (icon not set); DMG created successfully"
fi
rm -rf "$dmg_source"

echo "Codesigning DMG..."
codesign --force --timestamp \
  --sign "$DEVELOPER_ID_APP_IDENTITY" \
  "$artifacts_path/$dmg_name"

# --- PKG ---
pkg_name="pswitcher-v${VERSION}-macos-arm64.pkg"
echo "Creating PKG: $pkg_name"

# Determine install directory and binary name from CLI_INSTALL_PATH
install_dir=$(dirname "$CLI_INSTALL_PATH")
install_bin=$(basename "$CLI_INSTALL_PATH")

# Setup pkg root directory structure
pkg_root="$RUNNER_TEMP/pkg-root"
rm -rf "$pkg_root"
mkdir -p "$pkg_root/$install_dir"
cp "$staging_path/pswitcher" "$pkg_root/$install_dir/$install_bin"

# Create unsigned component package
unsigned_pkg="$RUNNER_TEMP/pswitcher-unsigned.pkg"
pkgbuild \
  --root "$pkg_root" \
  --identifier "com.projectswitcher.cli" \
  --version "$VERSION" \
  --install-location "/" \
  "$unsigned_pkg"

# Sign with installer identity
productsign \
  --sign "$DEVELOPER_ID_INSTALLER_IDENTITY" \
  --timestamp \
  "$unsigned_pkg" \
  "$artifacts_path/$pkg_name"

rm -f "$unsigned_pkg"

# --- Tarball ---
tarball_name="pswitcher-v${VERSION}-macos-arm64.tar.gz"
echo "Creating tarball: $tarball_name"
tar -czf "$artifacts_path/$tarball_name" -C "$staging_path" pswitcher

echo "ci_package: OK"
echo "DMG: $artifacts_path/$dmg_name"
echo "PKG: $artifacts_path/$pkg_name"
echo "Tarball: $artifacts_path/$tarball_name"
