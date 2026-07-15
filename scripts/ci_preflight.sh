#!/usr/bin/env bash
# ci_preflight.sh — Validates release-readiness on every CI run.
# Catches configuration and packaging issues before a release tag is pushed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
errors=0
runner_label=""

# ── Policy constants ──────────────────────────────────────────────────
# Update these when changing runner, Xcode, or signing requirements.
POLICY_RUNNER_LABEL="macos-26"            # GitHub Actions runner label for release builds
POLICY_XCODE_MAJOR_FLOOR=26              # Minimum Xcode major version enforced in workflow
POLICY_XCODE_CHANNEL="latest-stable"     # setup-xcode version channel
POLICY_SETUP_XCODE_REF="maxim-lobanov/setup-xcode@60606e260d2fc5762a71e64e74b2174e8ea3c8bd"
POLICY_CODE_SIGN_STYLE="Manual"          # Release code signing style in project.yml
POLICY_ENVIRONMENT="release"             # GitHub Actions environment name
POLICY_TAG_PATTERN='v\*'                 # Tag glob that triggers release workflow (escaped for grep)
POLICY_INTERMEDIATE_CERT="DeveloperIDG2CA.cer"  # Apple Developer ID G2 intermediate cert

# ── Helpers ───────────────────────────────────────────────────────────

fail() {
  echo "FAIL: $1" >&2
  errors=$((errors + 1))
}

# Match a YAML key-value pattern in a file, tolerant of whitespace and
# quote variations.  Strips leading/trailing whitespace from each line,
# collapses internal whitespace, and removes surrounding single/double quotes
# from values before testing the pattern.
yaml_grep() {
  local file="$1" pattern="$2"
  sed -E 's/[[:space:]]+#.*$//' "$file" \
    | sed '/^[[:space:]]*#/d' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]\{1,\}/ /g' \
    | sed "s/['\"]//g" \
    | grep -qE "$pattern"
}

echo "=== Release preflight checks ==="

# 1. MARKETING_VERSION in project.yml must be valid semver
version=$(grep 'MARKETING_VERSION' "$REPO_ROOT/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
if [[ -z "$version" ]]; then
  fail "MARKETING_VERSION not found in project.yml"
elif [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "MARKETING_VERSION '$version' is not valid semver (expected X.Y.Z)"
else
  echo "PASS: MARKETING_VERSION=$version"
fi

# 2. CURRENT_PROJECT_VERSION in project.yml must be a positive integer
build_version=$(grep 'CURRENT_PROJECT_VERSION' "$REPO_ROOT/project.yml" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '[:space:]')
if [[ -z "$build_version" ]]; then
  fail "CURRENT_PROJECT_VERSION not found in project.yml"
elif [[ ! "$build_version" =~ ^[1-9][0-9]*$ ]]; then
  fail "CURRENT_PROJECT_VERSION '$build_version' is not a positive integer"
else
  echo "PASS: CURRENT_PROJECT_VERSION=$build_version"
fi

# 3. Info.plist uses build-setting variables (not hardcoded)
plist="$REPO_ROOT/ProjectSwitcherApp/Info.plist"
if [[ ! -f "$plist" ]]; then
  fail "Info.plist not found at $plist"
else
  if grep -q '<string>$(MARKETING_VERSION)</string>' "$plist"; then
    echo "PASS: Info.plist CFBundleShortVersionString uses \$(MARKETING_VERSION)"
  else
    fail "Info.plist CFBundleShortVersionString is not \$(MARKETING_VERSION) — version will be wrong in built app"
  fi
  if grep -q '<string>$(CURRENT_PROJECT_VERSION)</string>' "$plist"; then
    echo "PASS: Info.plist CFBundleVersion uses \$(CURRENT_PROJECT_VERSION)"
  else
    fail "Info.plist CFBundleVersion is not \$(CURRENT_PROJECT_VERSION) — build number will be wrong in built app"
  fi
fi

# 4. Entitlements file exists
entitlements="$REPO_ROOT/release/ProjectSwitcher.entitlements"
if [[ -f "$entitlements" ]]; then
  echo "PASS: Entitlements file exists"
else
  fail "Entitlements file missing at release/ProjectSwitcher.entitlements"
fi

# 5. CI scripts exist and are executable
ci_scripts=(
  ci_setup_signing.sh
  ci_archive.sh
  ci_package.sh
  ci_notarize.sh
  ci_release_validate.sh
)
for script in "${ci_scripts[@]}"; do
  path="$REPO_ROOT/scripts/$script"
  if [[ ! -f "$path" ]]; then
    fail "CI script missing: scripts/$script"
  elif [[ ! -x "$path" ]]; then
    fail "CI script not executable: scripts/$script"
  else
    echo "PASS: scripts/$script"
  fi
done

# 6. Release workflow exists and references the release environment
workflow="$REPO_ROOT/.github/workflows/release.yml"
if [[ ! -f "$workflow" ]]; then
  fail "Release workflow missing at .github/workflows/release.yml"
else
  if yaml_grep "$workflow" "environment: *${POLICY_ENVIRONMENT}"; then
    echo "PASS: Release workflow uses '$POLICY_ENVIRONMENT' environment"
  else
    fail "Release workflow does not reference '$POLICY_ENVIRONMENT' environment"
  fi
  # Verify tag trigger pattern (tolerates single/double quotes and bracket syntax)
  if yaml_grep "$workflow" "tags:.*${POLICY_TAG_PATTERN}"; then
    echo "PASS: Release workflow triggers on v* tags"
  else
    fail "Release workflow does not trigger on v* tags"
  fi

  # Extract runner label (normalize whitespace, strip quotes)
  runner_label=$(sed -E 's/[[:space:]]+#.*$//' "$workflow" \
    | sed '/^[[:space:]]*#/d' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]\{1,\}/ /g' \
    | sed "s/['\"]//g" \
    | grep -E '^runs-on:' | head -1 | sed -E 's/^runs-on: *//')
  if [[ "$runner_label" == "$POLICY_RUNNER_LABEL" ]]; then
    echo "PASS: Release workflow runs on $POLICY_RUNNER_LABEL"
  else
    fail "Release workflow runner is '$runner_label' (expected $POLICY_RUNNER_LABEL)"
  fi

  if yaml_grep "$workflow" "uses: *${POLICY_SETUP_XCODE_REF}"; then
    echo "PASS: Release workflow pins setup-xcode to immutable ref"
  else
    fail "Release workflow missing pinned setup-xcode ref ($POLICY_SETUP_XCODE_REF)"
  fi

  if yaml_grep "$workflow" "xcode-version: *${POLICY_XCODE_CHANNEL}"; then
    echo "PASS: Release workflow uses $POLICY_XCODE_CHANNEL Xcode channel"
  else
    fail "Release workflow does not use xcode-version: $POLICY_XCODE_CHANNEL"
  fi

  if grep -q "\-lt ${POLICY_XCODE_MAJOR_FLOOR}" "$workflow"; then
    echo "PASS: Release workflow enforces Xcode major >= $POLICY_XCODE_MAJOR_FLOOR"
  else
    fail "Release workflow does not enforce Xcode major >= $POLICY_XCODE_MAJOR_FLOOR"
  fi
fi

# 7. project.yml has Release code signing configured for app and CLI
if grep -A2 'CODE_SIGN_STYLE:' "$REPO_ROOT/project.yml" | grep -q "$POLICY_CODE_SIGN_STYLE"; then
  echo "PASS: Release code signing configured ($POLICY_CODE_SIGN_STYLE)"
else
  fail "project.yml missing Release code signing configuration (CODE_SIGN_STYLE: $POLICY_CODE_SIGN_STYLE)"
fi

# 8. ci_archive.sh passes DEVELOPMENT_TEAM to xcodebuild archive
archive_script="$REPO_ROOT/scripts/ci_archive.sh"
if [[ -f "$archive_script" ]]; then
  if grep -q 'DEVELOPMENT_TEAM=' "$archive_script"; then
    echo "PASS: ci_archive.sh passes DEVELOPMENT_TEAM to xcodebuild"
  else
    fail "ci_archive.sh does not pass DEVELOPMENT_TEAM to xcodebuild — archive will fail with 'requires a development team'"
  fi
  # ci_archive.sh must codesign with hardened runtime and entitlements
  if grep -q 'options runtime' "$archive_script" && grep -q 'entitlements' "$archive_script"; then
    echo "PASS: ci_archive.sh codesigns with hardened runtime and entitlements"
  else
    fail "ci_archive.sh missing hardened runtime or entitlements in codesign — notarization will fail"
  fi
fi

# 9. Release workflow does not override MACOSX_DEPLOYMENT_TARGET
# The deployment target is set in project.yml (single source of truth).
# Overriding via env var causes failures when the runner SDK is older than the target.
if [[ -f "$workflow" ]]; then
  if grep -q 'MACOS_DEPLOYMENT_TARGET\|MACOSX_DEPLOYMENT_TARGET' "$workflow"; then
    fail "Release workflow overrides deployment target — remove it; project.yml is the single source of truth"
  else
    echo "PASS: Release workflow does not override deployment target"
  fi
fi

# 10. project.yml deployment target is within release runner SDK major range
if [[ -z "$runner_label" ]]; then
  echo "SKIP: Deployment target runner-major check skipped because release runner label is unavailable"
else
  deploy_target=$(grep 'macOS:' "$REPO_ROOT/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
  if [[ -n "$deploy_target" ]]; then
    deploy_major=$(echo "$deploy_target" | cut -d. -f1)
    if [[ "$runner_label" =~ ^macos-([0-9]+)$ ]]; then
      runner_major="${BASH_REMATCH[1]}"
      if [[ "$deploy_major" -gt "$runner_major" ]]; then
        fail "project.yml deployment target $deploy_target exceeds release runner SDK major ($runner_label) — archive will fail"
      else
        echo "PASS: Deployment target $deploy_target (major $deploy_major) is within release runner SDK major ($runner_label)"
      fi
    elif [[ "$runner_label" == "macos-latest" ]]; then
      echo "PASS: Release runner is macos-latest; deployment target $deploy_target accepted without strict major check"
    else
      fail "Unable to infer release runner SDK major from runs-on label '$runner_label'"
    fi
  else
    fail "Could not read deployment target from project.yml"
  fi
fi

# 11. ci_setup_signing.sh preserves existing keychain search list
signing_script="$REPO_ROOT/scripts/ci_setup_signing.sh"
if [[ -f "$signing_script" ]]; then
  # The script must NOT replace the keychain list (removing login.keychain-db breaks
  # IDEDistribution). It must preserve existing keychains when adding the release keychain.
  if grep -q 'list-keychains -d user -s.*\$' "$signing_script" && grep -q 'existing_keychains\|list-keychains.*-d user' "$signing_script"; then
    echo "PASS: ci_setup_signing.sh preserves existing keychain search list"
  else
    fail "ci_setup_signing.sh may replace the keychain search list — exportArchive will fail with empty distribution methods"
  fi
  # The .p12 only has the leaf cert. IDEDistribution needs the Apple intermediate CA
  # to validate the chain for developer-id distribution. Without it: "Unknown Distribution Error".
  if grep -q "$POLICY_INTERMEDIATE_CERT" "$signing_script"; then
    echo "PASS: ci_setup_signing.sh downloads Apple Developer ID G2 intermediate certificate"
  else
    fail "ci_setup_signing.sh missing Apple Developer ID G2 intermediate cert download ($POLICY_INTERMEDIATE_CERT) — exportArchive will fail"
  fi
fi

# 12. ci_setup_signing.sh must not delete the API key needed by notarization
# The signing setup script runs in its own step. An EXIT trap that removes the
# entire signing directory also deletes AuthKey.p8, which ci_notarize.sh reads
# from $RUNNER_TEMP/signing/AuthKey.p8 in a later step.
if [[ -f "$signing_script" ]]; then
  if grep -qE "trap\b.*rm\b.*signing" "$signing_script"; then
    fail "ci_setup_signing.sh has an EXIT trap that removes the signing directory — this deletes AuthKey.p8 before notarization can use it"
  else
    echo "PASS: ci_setup_signing.sh does not trap-remove the signing directory"
  fi
fi

# 13. Identity.swift buildVersion matches MARKETING_VERSION
identity_swift="$REPO_ROOT/ProjectSwitcherCore/Identity.swift"
if [[ -f "$identity_swift" ]]; then
  swift_version=$(grep 'static let buildVersion' "$identity_swift" | head -1 | sed 's/.*= *"\([^"]*\)".*/\1/')
  if [[ -z "$swift_version" ]]; then
    fail "Could not read buildVersion from Identity.swift"
  elif [[ "$swift_version" != "$version" ]]; then
    fail "Identity.swift buildVersion '$swift_version' does not match MARKETING_VERSION '$version' — CLI will report wrong version"
  else
    echo "PASS: Identity.swift buildVersion matches MARKETING_VERSION ($version)"
  fi
else
  fail "Identity.swift not found at $identity_swift"
fi

# 14. CLI install path is repository-owned and canonical
cli_install_path_file="$REPO_ROOT/release/cli-install-path"
if [[ ! -f "$cli_install_path_file" ]]; then
  fail "CLI install path file missing at release/cli-install-path"
else
  cli_install_path=$(<"$cli_install_path_file")
  if [[ "$cli_install_path" != /* ]]; then
    fail "CLI install path '$cli_install_path' is not absolute"
  elif [[ "$(basename "$cli_install_path")" != "pswitcher" ]]; then
    fail "CLI install path '$cli_install_path' does not use the canonical pswitcher binary name"
  else
    echo "PASS: CLI install path is repository-owned and canonical ($cli_install_path)"
  fi
fi

if [[ -f "$workflow" ]]; then
  if grep -q 'vars\.CLI_INSTALL_PATH\|CLI_INSTALL_PATH:' "$workflow"; then
    fail "Release workflow overrides the repository-owned CLI install path"
  else
    echo "PASS: Release workflow does not override the CLI install path"
  fi
fi

echo ""
if [[ $errors -gt 0 ]]; then
  echo "=== $errors preflight check(s) FAILED ==="
  exit 1
else
  echo "=== All preflight checks passed ==="
fi
