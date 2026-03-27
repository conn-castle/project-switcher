#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required to generate ProjectSwitcher.xcodeproj" >&2
  echo "Fix: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec project.yml --project-root "$repo_root" --project "$repo_root"
echo "Generated ProjectSwitcher.xcodeproj"

