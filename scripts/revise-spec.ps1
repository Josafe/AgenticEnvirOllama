param(
    [Parameter(Mandatory = $true)][string]$Task,
    [Parameter(Mandatory = $true)][string]$SpecFile,
    [Parameter(Mandatory = $true)][string]$ReviewFile,
    [string]$Model,
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

$agentFile        = Join-Path $root ".ai\agents\spec-reviser.md"
$contractFile     = Join-Path $root ".ai\rules\agent-contract.md"
$instructionsFile = Join-Path $root "AGENTS.md"
$configFile       = Join-Path $root ".ai\config.json"

foreach ($required in @(
    @{ Path = $SpecFile;         Label = "Specification file" },
    @{ Path = $ReviewFile;       Label = "Review file" },
    @{ Path = $agentFile;        Label = "Specification reviser agent" },
    @{ Path = $contractFile;     Label = "Agent contract" },
    @{ Path = $instructionsFile; Label = "AGENTS.md" }
)) {
    if (-not (Test-Path $required.Path -PathType Leaf)) {
        throw "$($required.Label) not found: $($required.Path)"
    }
}

. (Join-Path $PSScriptRoot "lib\config.ps1")

$config = Get-HarnessConfig -ConfigPath $configFile

$Model = Resolve-HarnessModel `
    -Agent "spec-reviser" `
    -ModelWasProvided $PSBoundParameters.ContainsKey('Model') `
    -ExplicitModel $Model `
    -Config $config

$Model = "$Model".Trim()
if ([string]::IsNullOrWhiteSpace($Model)) {
    throw "Model name cannot be empty."
}

$specContent         = Get-Content $SpecFile -Raw -Encoding UTF8
$reviewContent       = Get-Content $ReviewFile -Raw -Encoding UTF8
$agentInstructions   = Get-Content $agentFile -Raw -Encoding UTF8
$agentContract       = Get-Content $contractFile -Raw -Encoding UTF8
$projectInstructions = Get-Content $instructionsFile -Raw -Encoding UTF8

if ([string]::IsNullOrWhiteSpace($specContent))   { throw "Specification file is empty." }
if ([string]::IsNullOrWhiteSpace($reviewContent)) { throw "Review file is empty." }

Write-Host ""
Write-Host "=== Specification Reviser ===" -ForegroundColor Cyan
Write-Host "Model : $Model"
Write-Host "Spec  : $SpecFile"
Write-Host "Review: $ReviewFile"
Write-Host ""

$systemPrompt = @"
You are the Specification Reviser Agent operating inside the AI Development Harness.

PROJECT INSTRUCTIONS:
$projectInstructions

AGENT CONTRACT:
$agentContract

AGENT ROLE:
$agentInstructions

ORIGINAL USER REQUEST:
$Task

CURRENT SPECIFICATION:
$specContent

SPECIFICATION REVIEW:
$reviewContent

Revise the specification according to the reviewer findings.

This is a MINIMAL REVISION, not a rewrite. Your task is ONLY to remove or
correct unsupported content identified by the reviewer. It is NOT to make the
specification more complete.

Rules, in order:

1. Start from the CURRENT SPECIFICATION.
2. Preserve every requirement directly supported by the ORIGINAL USER REQUEST.
3. Remove or correct every unsupported item identified by the REVIEW.
4. Do not replace removed items with new ones.
5. Do not invent requirements, edge cases, open questions, assumptions,
   dependencies, security or validation rules, UI behavior, error handling,
   implementation details, architecture decisions, or facts about the
   existing system. Use only context supported by the supplied input.
6. If removing unsupported content leaves no acceptance criterion, write one
   acceptance criterion that restates the complete behavior requested by the
   user, using only the user's own words. Do not add behavior.
7. Every requirement must have a Source of USER, PROJECT, FACT or ASSUMPTION.

The output MUST contain exactly these headings, in this order:

# Specification
## Goal
## Context
## Functional Requirements
## Non-Functional Requirements
## Acceptance Criteria
## Edge Cases
## Dependencies
## Open Questions
## Assumptions

If a section has no supported content, write exactly: None

Before answering, verify that all 10 headings are present, that at least one
FR-XXX and one AC-XXX exist, and that nothing new was introduced.

Return ONLY the complete revised specification.
"@

Write-Host "Sending specification to reviser..." -ForegroundColor Yellow
Write-Host ""

$revision = Invoke-HarnessGenerate `
    -Model $Model `
    -System $systemPrompt `
    -Prompt "Revise the specification according to the original request and review findings." `
    -Config $config

if ([string]::IsNullOrWhiteSpace($revision)) {
    throw "Reviser returned an empty response."
}

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    [System.IO.File]::WriteAllText(
        $OutputFile, $revision, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host "=== Revised Specification ===" -ForegroundColor Green
Write-Host ""

$revision
exit 0