# Commands

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
Canonical, repeatable **development workflow** commands for this repository (setup, build, run, test, coverage, lint/format, typecheck, migrations, scripts). This file is not for application/CLI usage documentation.

## Format
- Prefer commands that are stable and will be used repeatedly. Avoid one-off debugging commands.
- Organize commands using headings that fit the repo. Create headings as needed.
- If the repo is a monorepo, group commands per workspace/package/service and specify the working directory.
- When commands change, update this file and remove stale entries.
- Insert entries (and any needed headings) below `<!-- ENTRIES START -->`.

### Entry template
````text
- <Short purpose>
```bash
<command>
```
Run from: <repo root or path>
Prerequisites: <only if critical>
Notes: <optional constraints or tips>
````

<!-- ENTRIES START -->

## Verify

Run the doctor verification suite (checks config, dependencies, permissions, and app state):

```bash
pswitcher doctor
```

Run from repo root (or anywhere if installed).

## Generate

Regenerate `ProjectSwitcher.xcodeproj` from `project.yml` (XcodeGen):

```bash
make regen
```

Run from repo root. Prerequisites: `xcodegen` installed (for example via `brew install xcodegen`).

Reference (underlying script): `scripts/regenerate_xcodeproj.sh`

## Setup

Validate Xcode toolchain selection and first-launch state (run once after clone):

```bash
make setup
```

Run from repo root. Prerequisites: full Xcode installed and selected via `xcode-select`.
If this fails due to first-launch state, run the printed fix commands (for example `sudo xcodebuild -runFirstLaunch`).

Reference (underlying script): `scripts/dev_bootstrap.sh`

## Build

Build the app + CLI (Debug), without code signing:

```bash
make build
```

Run from repo root. Prerequisites: `xcbeautify` installed (`brew install xcbeautify`).

Reference (underlying script): `scripts/build.sh`. Runs `scripts/dev_bootstrap.sh` and then uses `xcodebuild` with a repo-owned DerivedData path under `build/DerivedData`.

## Build (Dev app identity)

Build the development app variant (Debug), without code signing:

```bash
make build-dev
```

Run from repo root. Prerequisites: `xcbeautify` installed (`brew install xcbeautify`).
Notes: Produces `build/DerivedData/Build/Products/Debug/ProjectSwitcher Dev.app` with a distinct bundle identifier so dev and release can be installed side-by-side.

Reference (underlying script): `scripts/build_dev.sh`

## Clean

Clean build artifacts (DerivedData + build output). Logs are outside the repo and must be removed manually as instructed by the script:

```bash
make clean
```

Run from repo root. Notes: The script prints the exact `rm -rf` command to delete logs under `~/.local/state/project-switcher/logs`.

Reference (underlying script): `scripts/clean.sh`

## Test

Run all unit tests (Debug) with coverage collection:

```bash
make test
```

Run from repo root. Prerequisites: `xcbeautify` installed (`brew install xcbeautify`).
Notes: Always collects coverage data (zero overhead). Test execution is serialized (`-parallel-testing-enabled NO`). Does not enforce the coverage gate — use `make coverage` for the full quality gate.

Reference (underlying script): `scripts/test.sh`

## Test (selective targets)

Run a single test bundle:

```bash
make test-app    # ProjectSwitcherAppTests only
make test-core   # ProjectSwitcherCoreTests only
make test-cli    # ProjectSwitcherCLITests only
```

Run a single test method:

```bash
make test-one TARGET=ProjectSwitcherAppTests TEST=SwitcherWorkspaceRetryCoordinatorTests/testScheduleRetryTriggersOnRetrySucceededWhenWorkspaceStateSucceeds
```

Run from repo root. Notes: Uses `-only-testing:` xcodebuild flag. `--test` requires `--target`. `make test-one` requires both `TARGET` and `TEST`. All selective runs collect coverage.

## Test with Coverage Gate

Run unit tests with coverage collection and enforce the 90% coverage gate:

```bash
make coverage
```

Run from repo root. Prerequisites: `xcbeautify` installed (`brew install xcbeautify`).
Notes: This is the quality gate used by CI. Prints per-file coverage sorted by % ascending (lowest first). The pre-commit hook runs selective tests (without the gate) based on staged files.

Reference (underlying script): `scripts/test.sh --gate`

## Re-check Coverage Gate

Re-check the coverage gate from an existing test result bundle:

```bash
scripts/coverage_gate.sh build/TestResults/Test-ProjectSwitcher.xcresult
```

Run from repo root. Notes: the `.xcresult` bundle is produced by `make coverage`.

## Coverage Gate Integration Test

Run integration tests for `coverage_gate.swift` (verifies per-file output, sorting, pass/fail logic):

```bash
make test-coverage-gate
```

Run from repo root. Notes: fast — pipes JSON fixtures to `coverage_gate.swift`, no xcodebuild.

Reference (underlying script): `scripts/test_coverage_gate.sh`

## Release Preflight

Validate release-readiness (version format, Info.plist variables, entitlements, CI scripts, workflow config):

```bash
make preflight
```

Run from repo root. Notes: runs automatically in CI on every push/PR. Also useful locally before tagging a release.

Reference (underlying script): `scripts/ci_preflight.sh`

## Release (CI only)

The release workflow (`.github/workflows/release.yml`) runs on tag push (`v*`). These scripts are called by CI and are not intended for local use:

- `scripts/ci_preflight.sh` — validate release configuration (also runs in CI workflow)
- `scripts/ci_setup_signing.sh` — import certs into temp keychain
- `scripts/ci_archive.sh` — archive + codesign app and CLI with Developer ID
- `scripts/ci_package.sh` — create DMG, PKG, tarball
- `scripts/ci_notarize.sh <artifact>` — notarize + staple a single artifact
- `scripts/ci_release_validate.sh` — validate all artifacts post-notarization

To create a release:

```bash
git tag vX.Y.Z && git push origin main vX.Y.Z
```

Run from repo root. Prerequisites: GitHub `release` environment with secrets (`APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_PRIVATE_KEY_B64`, `DEVELOPER_ID_APP_P12_B64`, `DEVELOPER_ID_APP_P12_PASSWORD`, `DEVELOPER_ID_INSTALLER_P12_B64`, `DEVELOPER_ID_INSTALLER_P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `DEVELOPER_ID_APP_IDENTITY`, `DEVELOPER_ID_INSTALLER_IDENTITY`) and variables (`CLI_INSTALL_PATH`).

## Git hooks

Install repo-managed git hooks (pre-commit runs targeted tests based on staged files):

```bash
make hooks
```

Run from repo root. Notes: sets local git config `core.hooksPath` to `.githooks`. The pre-commit hook maps staged file paths to test targets (e.g., `ProjectSwitcherApp/*` → ProjectSwitcherAppTests) and only runs the affected targets. Infrastructure file changes (`project.yml`, `Makefile`, `scripts/*`) trigger all tests. Non-source changes skip tests entirely. No coverage gate — CI enforces that.

Reference (underlying script): `scripts/install_git_hooks.sh`
