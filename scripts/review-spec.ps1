param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $true)]
    [string]$SpecFile,

    [string]$Model = "qwen2.5-coder:32b",

    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

$agentFile = Join-Path $root ".ai\agents\spec-reviewer.md"
$contractFile = Join-Path $root ".ai\rules\agent-contract.md"
$instructionsFile = Join-Path $root "AGENTS.md"

if (-not (Test-Path $SpecFile)) {
    Write-Host "Specification file not found: $SpecFile" -ForegroundColor Red
    exit 2
}

if (-not (Test-Path $agentFile)) {
    Write-Host "Specification reviewer agent not found: $agentFile" -ForegroundColor Red
    exit 2
}

if (-not (Test-Path $contractFile)) {
    Write-Host "Agent contract not found: $contractFile" -ForegroundColor Red
    exit 2
}

if (-not (Test-Path $instructionsFile)) {
    Write-Host "AGENTS.md not found: $instructionsFile" -ForegroundColor Red
    exit 2
}

try {
    $specContent = Get-Content $SpecFile -Raw
    $agentInstructions = Get-Content $agentFile -Raw
    $agentContract = Get-Content $contractFile -Raw
    $projectInstructions = Get-Content $instructionsFile -Raw
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

try {
    $null = Invoke-RestMethod `
        -Uri "http://localhost:11434/api/tags" `
        -Method Get `
        -ErrorAction Stop
}
catch {
    Write-Host ""
    Write-Host "=== OLLAMA CONNECTION ERROR ===" -ForegroundColor Red
    Write-Host "Ollama is not reachable at http://localhost:11434." -ForegroundColor Red
    Write-Host "Make sure Ollama is running." -ForegroundColor Red
    exit 2
}

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

$body = @{
    model  = $Model
    system = $systemPrompt
    prompt = "Review the specification according to your assigned role."
    stream = $false
} | ConvertTo-Json -Depth 10

Write-Host "Sending specification to reviewer..." -ForegroundColor Yellow
Write-Host ""

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $bodyBytes = $utf8NoBom.GetBytes($body)

    $response = Invoke-RestMethod `
        -Uri "http://localhost:11434/api/generate" `
        -Method Post `
        -ContentType "application/json; charset=utf-8" `
        -Body $bodyBytes
}
catch {
    Write-Host ""
    Write-Host "=== OLLAMA ERROR ===" -ForegroundColor Red

    if ($_.Exception.Response) {
        Write-Host "Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red

        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $errorBody = $reader.ReadToEnd()

            if (-not [string]::IsNullOrWhiteSpace($errorBody)) {
                Write-Host $errorBody -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "Unable to read Ollama error response." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }

    Write-Host "=== END OLLAMA ERROR ===" -ForegroundColor Red

    exit 2
}

$review = $response.response

if ([string]::IsNullOrWhiteSpace($review)) {
    Write-Host ""
    Write-Host "=== REVIEWER OUTPUT ERROR ===" -ForegroundColor Red
    Write-Host "Reviewer returned an empty response." -ForegroundColor Red
    exit 2
}

$statusMatch = [regex]::Match(
    $review,
    '(?im)^##\s+Status\s*\r?\n\s*(PASS|FAIL)\s*$'
)

if (-not $statusMatch.Success) {
    Write-Host ""
    Write-Host "=== REVIEW VALIDATION ERROR ===" -ForegroundColor Red
    Write-Host "Reviewer did not return a valid Status section." -ForegroundColor Red
    Write-Host ""
    Write-Host "Expected:"
    Write-Host ""
    Write-Host "## Status"
    Write-Host "PASS or FAIL"
    Write-Host ""

    exit 2
}

$status = $statusMatch.Groups[1].Value.ToUpperInvariant()

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($OutputFile, $review, $utf8NoBom)
    }
    catch {
        Write-Host ""
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

if ($status -eq "FAIL") {
    exit 1
}

exit 0