#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

scripts/dev_bootstrap.sh

if [[ ! -d "ProjectSwitcher.xcodeproj" ]]; then
  echo "error: ProjectSwitcher.xcodeproj is missing" >&2
  echo "Fix: scripts/regenerate_xcodeproj.sh" >&2
  exit 1
fi

derived_data_path="build/DerivedData"
mkdir -p "$(dirname -- "$derived_data_path")"

if ! command -v xcbeautify &>/dev/null; then
  echo "error: xcbeautify not found" >&2
  echo "Fix: brew install xcbeautify" >&2
  exit 1
fi

echo "Resolving SwiftPM packages (if any)..."
xcodebuild \
  -project ProjectSwitcher.xcodeproj \
  -scheme ProjectSwitcher \
  -derivedDataPath "$derived_data_path" \
  -resolvePackageDependencies \
  2>&1 | xcbeautify

echo "Building (Debug)..."
xcodebuild \
  -project ProjectSwitcher.xcodeproj \
  -scheme ProjectSwitcher \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | xcbeautify

app_path="$derived_data_path/Build/Products/Debug/ProjectSwitcher.app"
alt_app_path="$derived_data_path/Build/Products/Debug/ProjectSwitcherApp.app"
cli_path="$derived_data_path/Build/Products/Debug/pswitcher"

if [[ ! -d "$app_path" ]]; then
  echo "error: Expected app bundle not found at: $app_path" >&2
  if [[ -d "$alt_app_path" ]]; then
    echo "error: Found app bundle at: $alt_app_path (expected ProjectSwitcher.app)" >&2
    echo "Fix: Ensure the ProjectSwitcher target sets PRODUCT_NAME=ProjectSwitcher in project.yml, then regenerate ProjectSwitcher.xcodeproj" >&2
  else
    echo "Fix: Ensure the ProjectSwitcher scheme builds ProjectSwitcher as an app product" >&2
  fi
  exit 1
fi

if [[ ! -x "$cli_path" ]]; then
  echo "error: Expected CLI binary not found at: $cli_path" >&2
  echo "Fix: Ensure the ProjectSwitcher scheme builds pswitcher" >&2
  exit 1
fi

echo "build: OK"
echo "App: $app_path"
echo "CLI: $cli_path"
