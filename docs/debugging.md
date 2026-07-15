# Debugging ProjectSwitcher from local logs

This document defines the repeatable, read-only procedure for finding and
reporting ProjectSwitcher issues from local logs. It does not contain a
specific audit's findings.

## Required sources

Inspect only these ProjectSwitcher sources unless the investigation scope is
explicitly expanded:

| Source | Purpose |
| --- | --- |
| ~/.local/state/project-switcher/logs/project-switcher.log and rotations | Current application log location. |
| macOS unified log subsystem com.projectswitcher | System-integrated logging. |
| ProjectSwitcher-named diagnostic and crash reports only | Crash evidence; exclude other applications' reports. |

The application logs are JSON Lines. Their timestamp values are UTC and can
include milliseconds. The unified-log command accepts local-time boundaries.

## Procedure

### 1. Define the audit window explicitly

Set both endpoints before searching. Do not use an implicit rolling window if
the result will be retained or compared later.

```zsh
# Replace both placeholders with the intended local dates and times.
START_LOCAL='YYYY-MM-DD HH:MM:SS'
END_LOCAL='YYYY-MM-DD HH:MM:SS'
START_EPOCH=$(/bin/date -j -f '%Y-%m-%d %H:%M:%S' "$START_LOCAL" +%s)
END_EPOCH=$(/bin/date -j -f '%Y-%m-%d %H:%M:%S' "$END_LOCAL" +%s)
```

Record the local timezone used for the audit.

### 2. Collect the application log files

Run in zsh. The (N) qualifier avoids a failure when a location or rotation
does not exist. Exclude lock files because they are not JSON logs.

```zsh
log_files=(
  "$HOME"/.local/state/project-switcher/logs/project-switcher.log(N)
  "$HOME"/.local/state/project-switcher/logs/project-switcher.log.*(N)
)
log_files=("${(@)log_files:#*.lock}")
print -l -- $log_files
```

### 3. Check coverage before concluding that no event occurred

```zsh
for file in $log_files; do
  first=$(sed -n '1p' "$file" | jq -r '.timestamp // "unparseable"')
  last=$(tail -n 1 "$file" | jq -r '.timestamp // "unparseable"')
  print -r -- "$file\t$first\t$last"
done
```

Confirm that the retained-file ranges cover the complete audit window. An
empty interval or a retention gap is a coverage limitation, not evidence that
the application had no issue.

### 4. Extract warning, error, and explicit failure-state records

Normalize fractional seconds before fromdateiso8601; the installed jq
implementation does not parse them directly.

```zsh
jq -c --argjson start "$START_EPOCH" --argjson end "$END_EPOCH" '
  (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) as $timestamp_epoch
  | select($timestamp_epoch >= $start and $timestamp_epoch <= $end)
  | select(
      .level == "warn" or .level == "error" or
      ((.event // "") | test("failed|failure|error|timeout|unresponsive|crash"; "i"))
    )
' $log_files
```

Do not rely on severity alone: ProjectSwitcher records some failure-state
events at info level.

### 5. Group repeated records without losing evidence

Keep the count, first/last timestamp, messages, project IDs, and workspaces
for each event type before writing a findings list.

```zsh
jq -s --argjson start "$START_EPOCH" --argjson end "$END_EPOCH" '
  map(
    (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) as $timestamp_epoch
    | select($timestamp_epoch >= $start and $timestamp_epoch <= $end)
    | select(
        .level == "warn" or .level == "error" or
        ((.event // "") | test("failed|failure|error|timeout|unresponsive|crash"; "i"))
      )
  )
  | sort_by(.event)
  | group_by(.event)[]
  | {
      event: .[0].event,
      occurrences: length,
      first: (map(.timestamp) | min),
      last: (map(.timestamp) | max),
      levels: (map(.level) | unique),
      messages: (map(.message // empty) | unique),
      project_ids: (map(.context.project_id? // empty) | unique | map(select(. != ""))),
      workspaces: (map(.context.workspace? // empty) | unique | map(select(. != "")))
    }
' $log_files
```

Group duplicate symptoms into one issue only when the event, message, and
context establish the same condition. Preserve separate user-visible failure
results even when they arise from the same incident.

### 6. Examine Doctor warnings and their supporting detail

First list Doctor reports with warnings:

```zsh
jq -r --argjson start "$START_EPOCH" --argjson end "$END_EPOCH" '
  (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) as $timestamp_epoch
  | select(
      $timestamp_epoch >= $start and $timestamp_epoch <= $end and
      .event == "doctor.refresh.completed" and
      ((.context.warn_count // "0" | tostring) != "0")
    )
  | [.timestamp, .context.warn_count, .context.warn_findings] | @tsv
' $log_files
```

Then print each warning with its immediate detail line:

```zsh
jq -r --argjson start "$START_EPOCH" --argjson end "$END_EPOCH" '
  (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) as $timestamp_epoch
  | select(
      $timestamp_epoch >= $start and $timestamp_epoch <= $end and
      .event == "doctor.refresh.completed" and
      ((.context.warn_count // "0" | tostring) != "0")
    )
  | "REPORT " + .timestamp + "\n" + .context.rendered_report
' $log_files | awk '
  /^REPORT / { report=$0; next }
  /^WARN  / { warning=$0; need_detail=1; next }
  need_detail && /^Detail: / { print report; print warning; print; need_detail=0 }
'
```

Treat an SSH timeout as evidence that the remote check could not be completed,
not as proof that the remote path or setting is absent. A No such file or
directory detail is evidence for the requested path at that timestamp only.

### 7. Query the macOS unified log

Use /usr/bin/log; interactive zsh can resolve log to a shell function.

```zsh
/usr/bin/log show \
  --style syslog \
  --timezone local \
  --start "$START_LOCAL" \
  --end "$END_LOCAL" \
  --predicate 'subsystem == "com.projectswitcher"' \
  --info --debug --no-pager
```

Record an empty result as “no retained records returned.” It does not prove
that the application did not run or did not encounter a problem.

### 8. Find only ProjectSwitcher crash and diagnostic reports

```zsh
find \
  "$HOME/Library/Logs/DiagnosticReports" \
  "$HOME/Library/Logs/CrashReporter" \
  /Library/Logs/DiagnosticReports \
  -type f -iname '*ProjectSwitcher*' -print 2>/dev/null | sort
```

Inspect each matching report's timestamp before placing it in the audit
window. Do not include reports for other applications.

## Writing an evidence-backed finding

For each issue, record:

- The source file or subsystem.
- Exact UTC timestamp(s), event name, severity, message, and relevant context.
- The occurrence count and the first/last occurrence if it repeated.
- The directly logged user-visible result, if present.
- Coverage gaps and empty-source results.

Separate observations from conclusions. For example, a failed SSH read proves
that the check could not read the remote file; it does not prove why it failed
or what the remote file contains. Keep proposed causes and fixes out of an
evidence-only inventory.
