#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Parse flags
run_gate=false
target=""
test_filter=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  case "${args[$i]}" in
    --gate)
      run_gate=true
      ;;
    --target)
      i=$((i + 1))
      if [[ $i -ge ${#args[@]} ]]; then
        echo "error: --target requires an argument" >&2
        exit 2
      fi
      target="${args[$i]}"
      if [[ "$target" == --* ]]; then
        echo "error: --target requires a non-option argument" >&2
        exit 2
      fi
      ;;
    --test)
      i=$((i + 1))
      if [[ $i -ge ${#args[@]} ]]; then
        echo "error: --test requires an argument" >&2
        exit 2
      fi
      test_filter="${args[$i]}"
      if [[ "$test_filter" == --* ]]; then
        echo "error: --test requires a non-option argument" >&2
        exit 2
      fi
      ;;
    *)
      echo "error: unrecognized argument: ${args[$i]}" >&2
      echo "usage: scripts/test.sh [--gate] [--target <BundleName>] [--test <Class/method>]" >&2
      exit 2
      ;;
  esac
  i=$((i + 1))
done

# --test requires --target
if [[ -n "$test_filter" && -z "$target" ]]; then
  echo "error: --test requires --target" >&2
  exit 2
fi

# Build -only-testing flag if target is specified
only_testing_args=()
if [[ -n "$target" ]]; then
  if [[ -n "$test_filter" ]]; then
    only_testing_args+=("-only-testing:${target}/${test_filter}")
  else
    only_testing_args+=("-only-testing:${target}")
  fi
fi

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

# Structured failure diagnostics using xcresulttool JSON output.
print_test_failures() {
  local bundle="$1"
  if [[ ! -e "$bundle" ]]; then
    return
  fi
  if ! command -v python3 &>/dev/null; then
    echo "  (install python3 for structured failure output)" >&2
    return
  fi
  local json
  json="$(xcrun xcresulttool get test-results tests --path "$bundle" --compact 2>/dev/null)" || return 0
  python3 -c '
import json, sys
data = json.load(sys.stdin)
def walk(node):
    if node.get("nodeType") == "Test Case" and node.get("result") == "Failed":
        name = node.get("name", "<unknown>")
        msgs = []
        for child in node.get("children", []):
            if child.get("nodeType") == "Failure Message":
                msgs.append(child.get("name", ""))
        if msgs:
            print(f"  FAIL: {name}")
            for m in msgs:
                print(f"        {m}")
        else:
            print(f"  FAIL: {name}")
    for child in node.get("children", []):
        walk(child)
for node in data.get("testNodes", []):
    walk(node)
' <<< "$json"
}

# Build target description for log messages
test_desc="unit tests"
if [[ -n "$target" ]]; then
  test_desc="$target"
  if [[ -n "$test_filter" ]]; then
    test_desc="$target/$test_filter"
  fi
fi

result_bundle_path="build/TestResults/Test-ProjectSwitcher.xcresult"
mkdir -p "$(dirname -- "$result_bundle_path")"
if [[ -e "$result_bundle_path" ]]; then
  if [[ "$result_bundle_path" != build/TestResults/*.xcresult ]]; then
    echo "error: refusing to delete unexpected result bundle path: $result_bundle_path" >&2
    exit 1
  fi
  rm -rf "$result_bundle_path"
fi

echo "Running $test_desc (Debug)..."
set +e
xcodebuild \
  -project ProjectSwitcher.xcodeproj \
  -scheme ProjectSwitcher \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  -resultBundlePath "$result_bundle_path" \
  -enableCodeCoverage YES \
  -parallel-testing-enabled NO \
  ${only_testing_args[@]+"${only_testing_args[@]}"} \
  test \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | xcbeautify
xcodebuild_exit=${PIPESTATUS[0]}
set -e

if [[ "$xcodebuild_exit" -ne 0 ]]; then
  echo ""
  echo "xcodebuild exited $xcodebuild_exit — checking for test failures..."
  print_test_failures "$result_bundle_path"
  exit "$xcodebuild_exit"
fi

if "$run_gate"; then
  scripts/coverage_gate.sh "$result_bundle_path"
fi

echo "test: OK"
