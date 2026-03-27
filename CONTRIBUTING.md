# Contributing to ProjectSwitcher

Thanks for your interest in contributing. This guide covers everything you need to get started.

## Prerequisites

- macOS 15.7 or later (Apple Silicon)
- Xcode (full install, not just command-line tools)
- [Homebrew](https://brew.sh/)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [xcbeautify](https://github.com/cpisciotta/xcbeautify): `brew install xcbeautify`

## Architecture

ProjectSwitcher is structured as six non-test build targets:

| Target | Type | Role |
|--------|------|------|
| `ProjectSwitcher` | Application | Menu bar UI, switcher panel, onboarding, hotkey registration |
| `ProjectSwitcherDev` | Application | Development app identity variant (`ProjectSwitcher Dev`) for side-by-side local installs |
| `ProjectSwitcherCore` | Static framework | All business logic: config parsing, Doctor checks, project activation, layout engine, window management |
| `ProjectSwitcherAppKit` | Static framework | System-level implementations (Accessibility APIs, NSScreen, CGDisplay) behind Core-defined protocols |
| `ProjectSwitcherCLICore` | Static framework | Shared CLI command parsing and execution logic |
| `ProjectSwitcherCLI` | Tool | `pswitcher` CLI entrypoint |

**Key design principles:**

- **Core owns business logic.** The app is a thin presentation layer. Core never imports AppKit.
- **Protocol-based dependency injection.** System interactions (AeroSpace CLI, window positioning, screen detection) are defined as protocols in Core with concrete implementations in AppKit. Tests use stub implementations.
- **`Result<T, PsCoreError>` pattern.** Errors are typed and carry category, message, detail, command, and exit code.
- **Fail loudly.** No silent fallbacks for missing or invalid configuration. Unknown config keys are hard failures.

## Getting Started

```sh
# Validate Xcode toolchain (one-time)
make setup

# Generate Xcode project from project.yml
make regen

# Build (Debug, no code signing)
make build

# Build development app variant (Debug, no code signing)
make build-dev

# Run all tests (coverage collected automatically)
make test

# Run tests with coverage gate (90% minimum)
make coverage
```

The Xcode project (`ProjectSwitcher.xcodeproj`) is generated from `project.yml` using XcodeGen. If you add or rename source files, regenerate the project with `make regen`.

## Dev and Release App Variants

- `ProjectSwitcher` (release identity): `PRODUCT_NAME=ProjectSwitcher`, bundle ID `com.projectswitcher.ProjectSwitcher`
- `ProjectSwitcherDev` (dev identity): `PRODUCT_NAME=ProjectSwitcher Dev`, bundle ID `com.projectswitcher.ProjectSwitcher.dev`
- Build commands:
  - `make build` for release identity debug builds.
  - `make build-dev` for dev identity debug builds.
- macOS permissions:
  - Accessibility and Automation entries appear separately for `ProjectSwitcher` and `ProjectSwitcher Dev`.
  - `UserDefaults.standard` and login-item registration are bundle-ID scoped, so each app identity has separate preference/login-item state.
- Shared data paths (by design):
  - Both variants use `~/.config/project-switcher/` and `~/.local/state/project-switcher/` for config and state.

## Testing

Tests live in `ProjectSwitcherAppTests/`, `ProjectSwitcherCoreTests/`, and `ProjectSwitcherCLITests/`. Coverage is enforced at 90% minimum on `ProjectSwitcherCore` and `ProjectSwitcherCLICore`. The `ProjectSwitcherAppKit` target is excluded from the coverage gate because it requires a live window server.

```sh
# Run all tests (coverage collected automatically)
make test

# Run tests with coverage gate + per-file summary
make coverage

# Re-check coverage from existing results
scripts/coverage_gate.sh build/TestResults/Test-ProjectSwitcher.xcresult
```

**Test conventions:**

- Use `@testable import ProjectSwitcherCore` for Core tests.
- Tests must not launch real executables (`code`, `al`, `aerospace`). Use stub/mock implementations.
- Thread-safe test doubles are required for concurrent code paths (use `NSLock`).
- New test files require `make regen` before Xcode discovers them.

## Adding New Files

1. Create the file in the appropriate source directory.
2. Add the file path to `project.yml` if it's in a new directory not already covered by the `sources` glob.
3. Run `make regen`.
4. Verify with `make build`.

## Code Style

- Swift with strict typing. No force-unwrapping in production code.
- Public functions include docstrings describing arguments and return values.
- Follow existing patterns in the codebase. When in doubt, look at how similar code is structured.

## Git Hooks

Install the pre-commit hook (runs targeted tests for staged files before commit):

```sh
make hooks
```

## Pull Requests

1. Fork the repository and create a feature branch.
2. Make your changes with tests.
3. Ensure `make coverage` passes (build + tests + coverage gate).
4. Open a pull request against `main`.
5. Describe what changed and why.

## Reporting Issues

Open a GitHub issue with:

- What you expected to happen.
- What actually happened.
- Output of `pswitcher doctor` (if relevant).
- macOS version and ProjectSwitcher version (`pswitcher --version`).

## Internal Documentation

These files are maintained for development context and are not user-facing:

- `docs/CORE_API.md` -- public API reference for ProjectSwitcherCore
- `docs/using_aerospace.md` -- AeroSpace CLI usage patterns
- `docs/agent-layer/` -- roadmap, decisions, issues, backlog, commands
