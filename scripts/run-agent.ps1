param(
    [string]$Agent,
    [string]$Task,
    [string]$Model,
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

# Cualquier error termina con mensaje limpio y exit code 1 explícito
trap {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

. (Join-Path $PSScriptRoot "lib\config.ps1")

# ---------- 1. Validación de entrada (sin tocar config ni Ollama) ----------

if ([string]::IsNullOrWhiteSpace($Agent)) {
    throw "Agent is required. Example: -Agent spec"
}

if ([string]::IsNullOrWhiteSpace($Task)) {
    throw "Task is required. Example: -Task 'Create a specification...'"
}

if ($Agent -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') {
    throw "Invalid agent name: $Agent"
}

# ---------- 2. Ficheros del proyecto ----------

$root             = Split-Path -Parent $PSScriptRoot
$agentFile        = Join-Path $root ".ai\agents\$Agent.md"
$rulesFile        = Join-Path $root ".ai\rules\agent-contract.md"
$instructionsFile = Join-Path $root "AGENTS.md"
$configFile       = Join-Path $root ".ai\config.json"

if (-not (Test-Path $agentFile -PathType Leaf)) {
    throw "Agent not found: $agentFile"
}
if (-not (Test-Path $rulesFile -PathType Leaf)) {
    throw "Agent contract not found: $rulesFile"
}
if (-not (Test-Path $instructionsFile -PathType Leaf)) {
    throw "AGENTS.md not found: $instructionsFile"
}

# ---------- 3. Configuración y modelo ----------

$config = Get-HarnessConfig -ConfigPath $configFile

$Model = Resolve-HarnessModel `
    -Agent $Agent `
    -ModelWasProvided $PSBoundParameters.ContainsKey('Model') `
    -ExplicitModel $Model `
    -Config $config

$Model = "$Model".Trim()

if ([string]::IsNullOrWhiteSpace($Model)) {
    throw "Model name cannot be empty."
}

$ollamaUrl     = (Get-ConfigValue $config "ollamaUrl" "http://localhost:11434").TrimEnd('/')
$timeoutSec    = [int](Get-ConfigValue $config "timeoutSec" 600)
$stripThinking = [bool](Get-ConfigValue $config "stripThinking" $true)
$options       = Get-ConfigValue $config "options" $null

Write-Host ""
Write-Host "=== AI Development Harness ===" -ForegroundColor Cyan
Write-Host "Agent : $Agent"
Write-Host "Model : $Model"
Write-Host "Server: $ollamaUrl"
Write-Host ""

# ---------- 4. Comprobar Ollama y el modelo ----------

try {
    $ollamaTags = Invoke-RestMethod -Uri "$ollamaUrl/api/tags" -Method Get -TimeoutSec 15
}
catch {
    throw "Ollama is not reachable at $ollamaUrl. Make sure Ollama is running."
}

$availableModels = @($ollamaTags.models | ForEach-Object { $_.name })

if ($availableModels -notcontains $Model) {
    Write-Host "Model not found: $Model" -ForegroundColor Red
    Write-Host "Available models:" -ForegroundColor Yellow
    foreach ($m in $availableModels) { Write-Host "  - $m" }
    throw "The requested Ollama model is not installed. Try: ollama pull $Model"
}

# ---------- 5. Construir prompt ----------

$agentInstructions   = Get-Content $agentFile -Raw -Encoding UTF8
$agentContract       = Get-Content $rulesFile -Raw -Encoding UTF8
$projectInstructions = Get-Content $instructionsFile -Raw -Encoding UTF8

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

$payload = @{
    model  = $Model
    system = $systemPrompt
    prompt = $Task
    stream = $false
}
if ($options) { $payload.options = $options }

$body      = $payload | ConvertTo-Json -Depth 10
$bodyBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($body)

# ---------- 6. Llamada a Ollama ----------

Write-Host "Sending task to Ollama..." -ForegroundColor Yellow
Write-Host ""

try {
    $response = Invoke-RestMethod `
        -Uri "$ollamaUrl/api/generate" `
        -Method Post `
        -ContentType "application/json; charset=utf-8" `
        -Body $bodyBytes `
        -TimeoutSec $timeoutSec
}
catch {
    Write-Host "=== OLLAMA ERROR ===" -ForegroundColor Red

    if ($_.Exception.Response) {
        Write-Host "Status: $([int]$_.Exception.Response.StatusCode)" -ForegroundColor Red
        try {
            $reader = New-Object System.IO.StreamReader(
                $_.Exception.Response.GetResponseStream())
            Write-Host $reader.ReadToEnd() -ForegroundColor Yellow
        }
        catch { }
    }
    else {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }

    Write-Host "=== END OLLAMA ERROR ===" -ForegroundColor Red
    throw "Agent execution failed."
}

# ---------- 7. Resultado ----------

$result = "$($response.response)"

if ($stripThinking) {
    $result = [regex]::Replace($result, '(?s)<think>.*?</think>\s*', '')
}

$result = $result.Trim()

if ([string]::IsNullOrWhiteSpace($result)) {
    throw "Agent returned an empty response."
}

Write-Host "=== Agent Result ===" -ForegroundColor Green
Write-Host ""

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    $outputDirectory = Split-Path -Parent $OutputFile

    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and
        -not (Test-Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $OutputFile, $result, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host "Output : $OutputFile" -ForegroundColor DarkGray
}

$result
exit 0