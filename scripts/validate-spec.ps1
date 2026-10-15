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

$missingSections = @()

foreach ($section in $requiredSections) {
    if ($content -notmatch [regex]::Escape($section)) {
        $missingSections += $section
    }
}

Write-Host ""
Write-Host "=== Specification Validator ===" -ForegroundColor Cyan
Write-Host "File: $SpecFile"
Write-Host ""

if ($missingSections.Count -gt 0) {
    Write-Host "STATUS: FAIL" -ForegroundColor Red
    Write-Host ""
    Write-Host "Missing required sections:" -ForegroundColor Yellow

    foreach ($section in $missingSections) {
        Write-Host "- $section"
    }

    exit 1
}

$validationErrors = @()

# At least one functional requirement
if ($content -notmatch '(?m)^### FR-\d+') {
    $validationErrors += "No functional requirements found."
}

# At least one acceptance criterion
if ($content -notmatch '(?m)^### AC-\d+') {
    $validationErrors += "No acceptance criteria found."
}

# At least one source annotation
if ($content -notmatch '(?im)^\*\*Source:\*\*') {
    $validationErrors += "No requirement source annotations found."
}

# Validate source values
$allowedSources = @(
    "USER",
    "PROJECT",
    "FACT",
    "ASSUMPTION"
)

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

    foreach ($error in $validationErrors) {
        Write-Host "- $error"
    }

    exit 1
}

Write-Host "STATUS: PASS" -ForegroundColor Green
Write-Host ""
Write-Host "All required specification checks passed."

exit 0
