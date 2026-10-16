param(
    [Parameter(Mandatory = $true)][string]$Task,
    [Parameter(Mandatory = $true)][string]$SpecFile,
    [string]$Model,
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

$agentFile        = Join-Path $root ".ai\agents\spec-reviewer.md"
$contractFile     = Join-Path $root ".ai\rules\agent-contract.md"
$instructionsFile = Join-Path $root "AGENTS.md"
$configFile       = Join-Path $root ".ai\config.json"

foreach ($required in @(
    @{ Path = $SpecFile;         Label = "Specification file" },
    @{ Path = $agentFile;        Label = "Specification reviewer agent" },
    @{ Path = $contractFile;     Label = "Agent contract" },
    @{ Path = $instructionsFile; Label = "AGENTS.md" }
)) {
    if (-not (Test-Path $required.Path -PathType Leaf)) {
        Write-Host "$($required.Label) not found: $($required.Path)" -ForegroundColor Red
        exit 2
    }
}

try {
    . (Join-Path $PSScriptRoot "lib\config.ps1")

    $config = Get-HarnessConfig -ConfigPath $configFile

    $Model = Resolve-HarnessModel `
        -Agent "spec-reviewer" `
        -ModelWasProvided $PSBoundParameters.ContainsKey('Model') `
        -ExplicitModel $Model `
        -Config $config

    $Model = "$Model".Trim()
    if ([string]::IsNullOrWhiteSpace($Model)) {
        throw "Model name cannot be empty."
    }

    $specContent         = Get-Content $SpecFile -Raw -Encoding UTF8
    $agentInstructions   = Get-Content $agentFile -Raw -Encoding UTF8
    $agentContract       = Get-Content $contractFile -Raw -Encoding UTF8
    $projectInstructions = Get-Content $instructionsFile -Raw -Encoding UTF8
}
catch {
    Write-Host ""
    Write-Host "=== REVIEWER INPUT ERROR ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 2
}

if ([string]::IsNullOrWhiteSpace($specContent)) {
    Write-Host "Specification file is empty." -ForegroundColor Red
    exit 2
}

Write-Host ""
Write-Host "=== Specification Reviewer ===" -ForegroundColor Cyan
Write-Host "Model : $Model"
Write-Host "Spec  : $SpecFile"
Write-Host ""

$systemPrompt = @"
You are the Specification Reviewer Agent operating inside the AI Development Harness.

PROJECT INSTRUCTIONS:
$projectInstructions

AGENT CONTRACT:
$agentContract

AGENT ROLE:
$agentInstructions

IMPORTANT REVIEW INPUT:

ORIGINAL USER REQUEST:
$Task

GENERATED SPECIFICATION:
$specContent

Review the generated specification against the original user request.

Do not modify the specification.

Do not implement code.

Do not invent additional requirements.

Identify unsupported or misclassified requirements.

Pay particular attention to requirements incorrectly marked as Source: USER.

Follow the reviewer output format exactly.

Do not claim PASS without actually reviewing the specification.
"@

Write-Host "Sending specification to reviewer..." -ForegroundColor Yellow
Write-Host ""

try {
    $review = Invoke-HarnessGenerate `
        -Model $Model `
        -System $systemPrompt `
        -Prompt "Review the specification according to your assigned role." `
        -Config $config
}
catch {
    Write-Host "=== OLLAMA ERROR ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    exit 2
}

if ([string]::IsNullOrWhiteSpace($review)) {
    Write-Host "=== REVIEWER OUTPUT ERROR ===" -ForegroundColor Red
    Write-Host "Reviewer returned an empty response." -ForegroundColor Red
    exit 2
}

$statusMatch = [regex]::Match(
    $review,
    '(?im)^##\s+Status\s*\r?\n\s*(PASS|FAIL)\s*$'
)

if (-not $statusMatch.Success) {
    Write-Host "=== REVIEW VALIDATION ERROR ===" -ForegroundColor Red
    Write-Host "Reviewer did not return a valid Status section." -ForegroundColor Red
    Write-Host ""
    Write-Host "Expected:"
    Write-Host ""
    Write-Host "## Status"
    Write-Host "PASS or FAIL"
    exit 2
}

$status = $statusMatch.Groups[1].Value.ToUpperInvariant()

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    try {
        [System.IO.File]::WriteAllText(
            $OutputFile, $review, (New-Object System.Text.UTF8Encoding($false)))
    }
    catch {
        Write-Host "=== REVIEW OUTPUT ERROR ===" -ForegroundColor Red
        Write-Host "Could not write review file: $OutputFile" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        exit 2
    }
}

Write-Host ""
Write-Host "Review Status: $status" -ForegroundColor $(if ($status -eq "PASS") { "Green" } else { "Red" })
Write-Host ""

$review

if ($status -eq "FAIL") { exit 1 }
exit 0