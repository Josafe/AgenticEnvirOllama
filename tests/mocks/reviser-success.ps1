param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $true)]
    [string]$SpecFile,

    [Parameter(Mandatory = $true)]
    [string]$ReviewFile,

    [string]$Model,

    [string]$OutputFile
)

$spec = @"
# Specification

## Goal

Revised test specification.

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

Write-Host ""
Write-Host "=== MOCK REVISER ===" -ForegroundColor DarkCyan
Write-Host "Revision generated: $OutputFile"

exit 0