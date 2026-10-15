param(
    [string]$Agent,
    [string]$Task,
    [string]$Model,
    [string]$OutputFile
)

$spec = @"
# Specification

## Goal

Test specification.

## Context

None

## Functional Requirements

### FR-001

**Source:** USER

A user can perform the requested action.

## Non-Functional Requirements

None

## Acceptance Criteria

### AC-001

**Source:** USER

A user can complete the requested action.

## Edge Cases

None

## Dependencies

None

## Open Questions

None

## Assumptions

None
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputFile, $spec, $utf8NoBom)

exit 0