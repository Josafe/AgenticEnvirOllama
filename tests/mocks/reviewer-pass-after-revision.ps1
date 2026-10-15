param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $true)]
    [string]$SpecFile,

    [string]$Model,

    [string]$OutputFile
)

$stateFile = Join-Path $env:TEMP "ai-dev-harness-reviewer-state.txt"

if (-not (Test-Path $stateFile)) {

    Set-Content -Path $stateFile -Value "FAILED"

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
}

Remove-Item $stateFile -Force

$review = @"
# Specification Review

## Status

PASS

## Summary

Mock reviewer approved the revised specification.

## Findings

None.

## Unsupported Requirements

None.

## Missing Open Questions

None.

## Final Decision

PASS
"@

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutputFile, $review, $utf8NoBom)
}

Write-Host ""
Write-Host "=== MOCK REVIEWER ===" -ForegroundColor DarkCyan
Write-Host "Review Status: PASS"

exit 0