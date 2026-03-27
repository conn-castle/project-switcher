#!/usr/bin/env bash
set -euo pipefail

# Archive the app, codesign for Developer ID distribution, and codesign the CLI binary.
#
# Uses direct codesign instead of xcodebuild -exportArchive to avoid
# IDEDistribution issues on CI runners (missing intermediate CAs, etc.).
# The archive step already signs the app with the Developer ID identity;
# we re-sign explicitly to ensure hardened runtime, entitlements, and
# timestamp are correct.
#
# Required environment variables:
#   DEVELOPER_ID_APP_IDENTITY  — e.g. "Developer ID Application: Name (TEAMID)"
#   VERSION                    — e.g. "0.1.0"
#   RUNNER_TEMP

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v xcbeautify &>/dev/null; then
  echo "error: xcbeautify not found" >&2
  echo "Fix: brew install xcbeautify" >&2
  exit 1
fi

archive_path="$RUNNER_TEMP/ProjectSwitcher.xcarchive"
staging_path="$RUNNER_TEMP/staging"
derived_data_path="build/DerivedData"

# Extract team ID from identity string: "Developer ID Application: Name (TEAMID)" → "TEAMID"
team_id=$(echo "$DEVELOPER_ID_APP_IDENTITY" | sed 's/.*(\(.*\))/\1/')
if [[ -z "$team_id" || "$team_id" == "$DEVELOPER_ID_APP_IDENTITY" ]]; then
  echo "error: could not extract team ID from DEVELOPER_ID_APP_IDENTITY" >&2
  exit 1
fi
echo "Team ID: $team_id"

# --- Archive ---
echo "Archiving (Release)..."
xcodebuild archive \
  -project ProjectSwitcher.xcodeproj \
  -scheme ProjectSwitcher \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_data_path" \
  DEVELOPMENT_TEAM="$team_id" \
  2>&1 | xcbeautify

# --- Extract app from archive ---
# The archive stores the app in Products/Applications/
app_source="$archive_path/Products/Applications/ProjectSwitcher.app"
if [[ ! -d "$app_source" ]]; then
  echo "error: app not found at expected archive location" >&2
  echo "Archive Products contents:"
  find "$archive_path/Products" -maxdepth 3 -type d 2>/dev/null || true
  exit 1
fi

# --- Stage artifacts ---
mkdir -p "$staging_path"
cp -R "$app_source" "$staging_path/ProjectSwitcher.app"

# --- Re-sign app with Developer ID + hardened runtime + entitlements ---
# The archive already signed the app, but we re-sign explicitly to ensure
# the correct identity, hardened runtime, entitlements, and secure timestamp.
echo "Codesigning app with Developer ID (hardened runtime)..."
codesign --force --options runtime --timestamp \
  --entitlements "$repo_root/release/ProjectSwitcher.entitlements" \
  --sign "$DEVELOPER_ID_APP_IDENTITY" \
  "$staging_path/ProjectSwitcher.app"
codesign --verify --deep --strict "$staging_path/ProjectSwitcher.app"
echo "App signature verified"

# --- Find and codesign CLI binary ---
cli_candidates=(
  "$archive_path/Products/usr/local/bin/pswitcher"
  "$archive_path/Products/usr/bin/pswitcher"
)
cli_source=""
for candidate in "${cli_candidates[@]}"; do
  if [[ -x "$candidate" ]]; then
    cli_source="$candidate"
    break
  fi
done

if [[ -z "$cli_source" ]]; then
  echo "error: CLI binary 'pswitcher' not found in archive" >&2
  echo "Searching archive Products directory..."
  find "$archive_path/Products" -name "pswitcher" -type f 2>/dev/null || true
  exit 1
fi

echo "Found CLI binary at: $cli_source"
cp "$cli_source" "$staging_path/pswitcher"

echo "Codesigning CLI binary with hardened runtime..."
codesign --force --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APP_IDENTITY" \
  "$staging_path/pswitcher"
codesign --verify --deep --strict "$staging_path/pswitcher"

echo "ci_archive: OK"
echo "App: $staging_path/ProjectSwitcher.app"
echo "CLI: $staging_path/pswitcher"
