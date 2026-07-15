# Issues

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
Deferred defects, maintainability refactors, technical debt, risks, and engineering concerns. Add an entry only when you are not fixing it now.

## Format
- Insert new entries immediately below `<!-- ENTRIES START -->` (most recent first).
- Keep each entry **3–5 lines**.
- Line 1 starts with `- Issue YYYY-MM-DD <id>:` and a short title.
- Lines 2–5 are indented by **4 spaces** and use `Key: Value`.
- Keep **exactly one blank line** between entries.
- Prevent duplicates: search the file and merge/rewrite instead of adding near-duplicates.
- When fixed, remove the entry from this file.

### Entry template
```text
- Issue YYYY-MM-DD short-slug: Short title
    Priority: Critical | High | Medium | Low. Area: <area>
    Description: <observed problem or risk>
    Next step: <smallest concrete next action>
    Notes: <optional dependencies/constraints>
```

## Open issues

<!-- ENTRIES START -->

- Issue 2026-07-15 aerospace-update-visibility: Existing AeroSpace installs have no update or version-mismatch diagnostic
    Priority: Medium. Area: AeroSpace lifecycle
    Description: Fresh installs use the current official Homebrew tap, but Doctor neither detects an outdated cask nor warns when the CLI and running app server versions differ after an upgrade.
    Next step: Add an explicit Doctor update action and client/server mismatch finding; do not silently auto-upgrade the public-beta dependency.

- Issue 2026-07-15 chrome-duplicate-token: Multiple exact-token Chrome windows are selected arbitrarily
    Priority: Medium. Area: Chrome activation
    Description: When more than one Chrome window has the same exact `PS:<projectId>` token, AeroSpace enumeration order decides which window activation moves, while positioning can affect every match.
    Next step: Prefer the window already in the target workspace and surface unresolved ambiguity instead of choosing an arbitrary duplicate.

- Issue 2026-07-15 chrome-empty-capture: Empty Chrome capture can delete a valid tab snapshot
    Priority: Medium. Area: Chrome tab persistence
    Description: AppleScript returns the same empty output for a missing project window and for a found window whose tabs temporarily have no readable URL, so close can delete the canonical snapshot without proving absence.
    Next step: Return a structured capture outcome that distinguishes `windowNotFound` from captured URLs and preserve snapshots for indeterminate/empty reads.

- Issue 2026-07-15 aerospace-focus-retry: Stable-focus loops retry permanent AeroSpace errors until timeout
    Priority: Medium. Area: AeroSpace focus
    Description: Focus stabilization discards `focusWindow` errors and retries stale IDs for the full polling budget; individual commands can also make the nominal deadline overrun substantially.
    Next step: Classify permanent versus transient focus failures, stop on permanent errors, and bound command attempts as well as wall-clock polling.

- Issue 2026-07-15 ax-frame-write-detail: Chrome frame-write failures omit Accessibility error detail
    Priority: Medium. Area: window positioning
    Description: Partial Chrome positioning logs identify the failed window and operation but not the underlying AX error code, preventing an evidence-backed fix for repeated size-write failures.
    Next step: Preserve and log the AX error code from position/size writes, then diagnose from a new occurrence before changing retry behavior.

- Issue 2026-03-09 testgap: Missing unit tests for new extraction/refactor surfaces
    Priority: Medium. Area: tests
    Description: Several refactored or newly extracted methods lack direct unit test coverage: `retryTransientWindowOp` (retry+fallback logic), `AeroSpaceCircuitBreaker.beginRecovery` 60s stuck-recovery timeout, `listAllWindows` infrastructure error propagation (circuitBreakerOpen/timeout), `ProjectError.userFacingMessage`, `performBackgroundBreakerRecovery` readiness polling, `restoreNonProjectFocusFromStack` multi-candidate loop, `PsAeroSpace.focusWindow` tree-node error retry path, `closeProject` post-close `reloadConfig` call verification, and `captureWindowPositions` skip-on-no-IDE-windows guard.
    Next step: Add focused unit tests for `retryTransientWindowOp` covering immediate success, transient retry, fallback invocation, and permanent failure paths.
