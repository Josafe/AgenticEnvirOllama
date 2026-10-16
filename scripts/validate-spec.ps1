param(
    [Parameter(Mandatory = $true)]
    [string]$SpecFile
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $SpecFile)) {
    throw "Specification file not found: $SpecFile"
}

$content = Get-Content $SpecFile -Raw

if ([string]::IsNullOrWhiteSpace($content)) {
    throw "Specification file is empty."
}

Write-Host ""
Write-Host "=== Specification Validator ===" -ForegroundColor Cyan
Write-Host "File: $SpecFile"
Write-Host ""

$requiredSections = @(
    "# Specification",
    "## Goal",
    "## Context",
    "## Functional Requirements",
    "## Non-Functional Requirements",
    "## Acceptance Criteria",
    "## Edge Cases",
    "## Dependencies",
    "## Open Questions",
    "## Assumptions"
)

# 1. Required sections (anchored to the whole line)
$missingSections = @()

foreach ($section in $requiredSections) {
    $pattern = '(?m)^' + [regex]::Escape($section) + '\s*$'
    if ($content -notmatch $pattern) {
        $missingSections += $section
    }
}

if ($missingSections.Count -gt 0) {
    Write-Host "STATUS: FAIL" -ForegroundColor Red
    Write-Host ""
    Write-Host "Missing required sections:" -ForegroundColor Yellow
    foreach ($section in $missingSections) { Write-Host "- $section" }
    exit 1
}

# 2. Insufficient input: Functional Requirements is exactly "None"
$frMatch = [regex]::Match(
    $content,
    '(?ms)^## Functional Requirements\s*\r?\n(.*?)(?=^## )'
)
$fr = ($frMatch.Groups[1].Value -replace '```text|```', '').Trim()

if ($fr -eq 'None') {
    Write-Host "STATUS: INSUFFICIENT INPUT" -ForegroundColor Yellow
    Write-Host "The task did not contain enough information. See Open Questions."
    exit 3
}

# 3. Content checks
$validationErrors = @()

if ($content -notmatch '(?m)^### FR-\d+') {
    $validationErrors += "No functional requirements found."
}
if ($content -notmatch '(?m)^### AC-\d+') {
    $validationErrors += "No acceptance criteria found."
}
if ($content -notmatch '(?im)^\*\*Source:\*\*') {
    $validationErrors += "No requirement source annotations found."
}

$allowedSources = @("USER", "PROJECT", "FACT", "ASSUMPTION")

$sourceMatches = [regex]::Matches(
    $content,
    '(?im)^\*\*Source:\*\*\s*(.+?)\s*$'
)

foreach ($match in $sourceMatches) {
    $source = $match.Groups[1].Value.Trim()
    if ($allowedSources -notcontains $source) {
        $validationErrors += "Invalid requirement source: '$source'. Allowed values: USER, PROJECT, FACT, ASSUMPTION."
    }
}

if ($validationErrors.Count -gt 0) {
    Write-Host "STATUS: FAIL" -ForegroundColor Red
    Write-Host ""
    Write-Host "Validation errors:" -ForegroundColor Yellow
    foreach ($validationError in $validationErrors) {
        Write-Host "- $validationError"
    }
    exit 1
}

Write-Host "STATUS: PASS" -ForegroundColor Green
Write-Host ""
Write-Host "All required specification checks passed."
exit 0