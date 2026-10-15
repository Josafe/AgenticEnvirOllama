param(
    [string]$Agent,
    [string]$Task,
    [string]$Model = "qwen2.5-coder:32b",
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Agent)) {
throw "Agent is required. Example: -Agent spec"
}

if ([string]::IsNullOrWhiteSpace($Task)) {
throw "Task is required. Example: -Task 'Create a specification...'"
}

if ($Agent -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') {
    throw "Invalid agent name: $Agent"
}

if ([string]::IsNullOrWhiteSpace($Model)) {
    throw "Model is required."
}

$root = Split-Path -Parent $PSScriptRoot

$agentFile = Join-Path $root ".ai\agents"
$agentFile = Join-Path $agentFile "$Agent.md"

$rulesFile = Join-Path $root ".ai\rules"
$rulesFile = Join-Path $rulesFile "agent-contract.md"

$instructionsFile = Join-Path $root "AGENTS.md"


if (-not (Test-Path $agentFile)) {
throw "Agent not found: $agentFile"
}

if (-not (Test-Path $rulesFile)) {
throw "Agent contract not found: $rulesFile"
}

if (-not (Test-Path $instructionsFile)) {
throw "AGENTS.md not found: $instructionsFile"
}

Write-Host ""
Write-Host "=== AI Development Harness ===" -ForegroundColor Cyan
Write-Host "Agent : $Agent"
Write-Host "Model : $Model"
Write-Host ""

try {
    $ollamaTags = Invoke-RestMethod `
        -Uri "http://localhost:11434/api/tags" `
        -Method Get `
        -ErrorAction Stop
}
catch {
    throw "Ollama is not reachable at http://localhost:11434. Make sure Ollama is running."
}

$availableModels = @(
    $ollamaTags.models | ForEach-Object { $_.name }
)

if ($availableModels -notcontains $Model) {
    Write-Host "Model not found: $Model" -ForegroundColor Red
    Write-Host "Available models:" -ForegroundColor Yellow

    foreach ($availableModel in $availableModels) {
        Write-Host "  - $availableModel"
    }

    throw "The requested Ollama model is not installed."
}

$agentInstructions = Get-Content $agentFile -Raw
$agentContract = Get-Content $rulesFile -Raw
$projectInstructions = Get-Content $instructionsFile -Raw

$systemPrompt = @"
You are an AI agent operating inside the AI Development Harness.

PROJECT INSTRUCTIONS:
$projectInstructions

AGENT CONTRACT:
$agentContract

AGENT ROLE:
$agentInstructions

Follow all instructions above.

Do not invent requirements.
Do not claim verification that was not performed.
Stay within your assigned role.
"@

$body = @{
model  = $Model
system = $systemPrompt
prompt = $Task
stream = $false
} | ConvertTo-Json -Depth 10

Write-Host "Sending task to Ollama..." -ForegroundColor Yellow
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
    Write-Host "Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red

    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errorBody = $reader.ReadToEnd()
        Write-Host $errorBody -ForegroundColor Yellow
    }

    Write-Host "=== END OLLAMA ERROR ===" -ForegroundColor Red
    throw "Agent execution failed."
}

Write-Host "=== Agent Result ===" -ForegroundColor Green
Write-Host ""

if ([string]::IsNullOrWhiteSpace($response.response)) {
    throw "Agent returned an empty response."
}

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    $outputDirectory = Split-Path -Parent $OutputFile

    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        if (-not (Test-Path $outputDirectory)) {
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        }
    }

    [System.IO.File]::WriteAllText(
        $OutputFile,
        $response.response,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "Output : $OutputFile" -ForegroundColor DarkGray
}

$response.response

exit 0