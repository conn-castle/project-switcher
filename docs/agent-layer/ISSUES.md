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

- Issue 2026-03-09 testgap: Missing unit tests for new extraction/refactor surfaces
    Priority: Medium. Area: tests
    Description: Several refactored or newly extracted methods lack direct unit test coverage: `retryTransientWindowOp` (retry+fallback logic), `AeroSpaceCircuitBreaker.beginRecovery` 60s stuck-recovery timeout, `listAllWindows` infrastructure error propagation (circuitBreakerOpen/timeout), `ProjectError.userFacingMessage`, `performBackgroundBreakerRecovery` readiness polling, `restoreNonProjectFocusFromStack` multi-candidate loop, `PsAeroSpace.focusWindow` tree-node error retry path, `closeProject` post-close `reloadConfig` call verification, and `captureWindowPositions` skip-on-no-IDE-windows guard.
    Next step: Add focused unit tests for `retryTransientWindowOp` covering immediate success, transient retry, fallback invocation, and permanent failure paths.
