#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/coverage_gate.sh <path-to-xcresult>" >&2
  exit 2
fi

xcresult_path="$1"

if [[ ! -d "$xcresult_path" ]]; then
  echo "error: xcresult bundle not found at: $xcresult_path" >&2
  exit 2
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun not found (install Xcode and select it via xcode-select)" >&2
  exit 2
fi

# Single source of truth for the coverage policy:
# - The UI app (ProjectSwitcher.app) is presentation code; coverage gating focuses on non-UI targets.
# - ProjectSwitcherAppKit contains system-level code (AX APIs, NSScreen, CGDisplay) that requires
#   a live window server and connected displays — not exercisable in CI unit tests.
min_percent="90"
targets=(
  "ProjectSwitcherCore.framework"
  "ProjectSwitcherCLICore.framework"
)

swift_args=(
  "$repo_root/scripts/coverage_gate.swift"
  "--minPercent"
  "$min_percent"
)
for t in "${targets[@]}"; do
  swift_args+=("--target" "$t")
done

echo "Checking coverage gate (min ${min_percent}%)..."
for t in "${targets[@]}"; do
  echo "  - $t"
done

xcrun xccov view --report --json "$xcresult_path" | xcrun swift "${swift_args[@]}"

echo "coverage_gate: OK"
