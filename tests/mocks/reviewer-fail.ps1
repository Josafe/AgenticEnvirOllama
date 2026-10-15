param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $true)]
    [string]$SpecFile,

    [string]$Model,

    [string]$OutputFile
)

$review = @"
# Specification Review

## Status

FAIL

## Summary

Mock reviewer rejected the specification.

## Findings

### FINDING-001

**Severity:** BLOCKING
**Category:** INVENTED_REQUIREMENT
**Location:** Test
**Problem:** Mock blocking finding.
**Recommendation:** Revise the specification.

## Unsupported Requirements

- Mock unsupported requirement.

## Missing Open Questions

None.

## Final Decision

FAIL
"@

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutputFile, $review, $utf8NoBom)
}

Write-Host ""
Write-Host "=== MOCK REVIEWER ===" -ForegroundColor DarkCyan
Write-Host "Review Status: FAIL"

exit 1