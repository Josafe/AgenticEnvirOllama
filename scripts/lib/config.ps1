function Get-HarnessConfig {
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    if (-not (Test-Path $ConfigPath -PathType Leaf)) {
        return [pscustomobject]@{}
    }

    try {
        return Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON in config file: $ConfigPath. $($_.Exception.Message)"
    }
}

function Get-ConfigValue {
    param($Object, [string]$Name, $Default)

    if ($null -ne $Object -and $Object.PSObject.Properties[$Name] -and
        $null -ne $Object.$Name) {
        return $Object.$Name
    }
    return $Default
}

function Resolve-HarnessModel {
    param(
        [Parameter(Mandatory = $true)][string]$Agent,
        [bool]$ModelWasProvided,
        [string]$ExplicitModel,
        $Config
    )

    # 1. Parámetro explícito (aunque venga vacío: se valida, no se sustituye)
    if ($ModelWasProvided) { return $ExplicitModel }

    # 2. Variable de entorno
    if (-not [string]::IsNullOrWhiteSpace($env:AI_HARNESS_MODEL)) {
        return $env:AI_HARNESS_MODEL
    }

    # 3. Modelo específico del agente
    $agentModels = Get-ConfigValue $Config "agentModels" $null
    if ($agentModels -and $agentModels.PSObject.Properties[$Agent]) {
        return $agentModels.$Agent
    }

    # 4. Modelo por defecto
    $default = Get-ConfigValue $Config "defaultModel" $null
    if ($default) { return $default }

    throw "No model configured. Use -Model, set AI_HARNESS_MODEL, or define defaultModel in .ai\config.json."
}
function Invoke-HarnessGenerate {
    param(
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$System,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)]$Config
    )

    $ollamaUrl     = (Get-ConfigValue $Config "ollamaUrl" "http://localhost:11434").TrimEnd('/')
    $timeoutSec    = [int](Get-ConfigValue $Config "timeoutSec" 600)
    $stripThinking = [bool](Get-ConfigValue $Config "stripThinking" $true)
    $options       = Get-ConfigValue $Config "options" $null

    $payload = @{ model = $Model; system = $System; prompt = $Prompt; stream = $false }
    if ($options) { $payload.options = $options }

    $json  = $payload | ConvertTo-Json -Depth 10
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)

    try {
        $response = Invoke-RestMethod `
            -Uri "$ollamaUrl/api/generate" `
            -Method Post `
            -ContentType "application/json; charset=utf-8" `
            -Body $bytes `
            -TimeoutSec $timeoutSec
    }
    catch {
        throw "Ollama request failed: $($_.Exception.Message)"
    }

    $text = "$($response.response)"
    if ($stripThinking) {
        $text = [regex]::Replace($text, '(?s)<think>.*?</think>\s*', '')
    }
    return $text.Trim()
}