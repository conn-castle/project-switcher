# Releasing ProjectSwitcher

This document covers how to create a new release. Releases are built, signed, notarized, and published automatically by CI when a version tag is pushed.

## Prerequisites

The GitHub repository must have a `release` environment configured with the following secrets. If your local `human_setup.md` runbook is unavailable, use the table below as the source of truth.

The release workflow requires **Xcode 26+** and fails early when an older Xcode is selected. This keeps release artifacts aligned with the current CI/local toolchain baseline.

### Secrets (in `release` environment)

| Secret | Description |
|--------|-------------|
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID |
| `APPLE_API_PRIVATE_KEY_B64` | Base64-encoded `.p8` API key |
| `DEVELOPER_ID_APP_P12_B64` | Base64-encoded Developer ID Application `.p12` |
| `DEVELOPER_ID_APP_P12_PASSWORD` | Password for the Application `.p12` |
| `DEVELOPER_ID_INSTALLER_P12_B64` | Base64-encoded Developer ID Installer `.p12` |
| `DEVELOPER_ID_INSTALLER_P12_PASSWORD` | Password for the Installer `.p12` |
| `KEYCHAIN_PASSWORD` | Random password for CI temporary keychain |
| `DEVELOPER_ID_APP_IDENTITY` | Full identity string (e.g., `Developer ID Application: Name (TEAMID)`) |
| `DEVELOPER_ID_INSTALLER_IDENTITY` | Full identity string (e.g., `Developer ID Installer: Name (TEAMID)`) |

The CLI package destination is repository-controlled by `release/cli-install-path`; GitHub environment variables cannot override it. The macOS deployment target is set in `project.yml` and must not be overridden in CI. The tag prefix `v` is hardcoded in the workflow trigger.

## Creating a Release

### 1. Bump the version

Update `MARKETING_VERSION` in `project.yml`:

```yaml
MARKETING_VERSION: "0.2.0"
```

Regenerate the Xcode project and verify:

```sh
make regen
make build
make coverage
```

### 2. Update the changelog

Add a new section to `CHANGELOG.md` with the version and date:

```markdown
## [0.2.0] - 2026-03-01

### Added
- ...

### Fixed
- ...
```

### 3. Commit, tag, and push

```sh
git add project.yml ProjectSwitcher.xcodeproj CHANGELOG.md
git commit -m "Bump version to 0.2.0"
git tag v0.2.0
git push origin main v0.2.0
```

The tag push triggers the release workflow.

### 4. Monitor the workflow

The release workflow (`.github/workflows/release.yml`) runs on `macos-26` and:

1. Selects the latest stable Xcode toolchain available on the runner.
2. Validates the selected Xcode major version is `26+`.
3. Validates the tag version matches `MARKETING_VERSION` in `project.yml`.
4. Installs build dependencies (xcbeautify, xcodegen, create-dmg).
5. Generates the Xcode project.
6. Runs build and tests (full test suite with coverage gate).
7. Imports signing certificates into a temporary keychain.
8. Archives the app and codesigns with Developer ID identity (hardened runtime + entitlements).
9. Codesigns the CLI binary with hardened runtime.
10. Creates distribution artifacts:
   - `ProjectSwitcher-v<version>-macos-arm64.dmg` (app)
   - `pswitcher-v<version>-macos-arm64.pkg` (CLI installer, signed with Installer cert)
   - `pswitcher-v<version>-macos-arm64.tar.gz` (CLI binary)
11. Notarizes the DMG and PKG with Apple.
12. Validates all artifacts (mounts DMG, verifies signatures, checks notarization).
   - Confirms the PKG payload installs the CLI at the path in `release/cli-install-path`.
13. Generates `SHA256SUMS`.
14. Creates a GitHub Release with all artifacts attached.

### 5. Verify the release

After the workflow completes:

```sh
# Download and verify the DMG
spctl --assess --verbose=4 --type execute /path/to/ProjectSwitcher.app

# Verify the PKG
pkgutil --check-signature /path/to/pswitcher-v0.2.0-macos-arm64.pkg

# Verify the tarball CLI
xattr -d com.apple.quarantine /path/to/pswitcher
./pswitcher --version
```

## CI Scripts

These scripts are called by the release workflow and are not intended for local use:

| Script | Purpose |
|--------|---------|
| `scripts/ci_setup_signing.sh` | Import certificates into temporary keychain |
| `scripts/ci_archive.sh` | Archive, codesign app and CLI with Developer ID |
| `scripts/ci_package.sh` | Create DMG, PKG, and tarball |
| `scripts/ci_notarize.sh` | Notarize and staple a single artifact |
| `scripts/ci_release_validate.sh` | Validate all artifact signatures and notarization |

## Troubleshooting

**Tag version mismatch:** The workflow validates that the tag version (e.g., `v0.2.0` -> `0.2.0`) matches `MARKETING_VERSION` in `project.yml`. If they don't match, the workflow fails immediately.

**Notarization fails:** Check the Apple Developer portal for notarization logs. Common issues: missing entitlements, unsigned nested binaries, or expired certificates.

**`codesign` cannot find identity:** Verify the `.p12` password is correct and the identity string in `DEVELOPER_ID_APP_IDENTITY` matches the certificate exactly (including team ID in parentheses).
