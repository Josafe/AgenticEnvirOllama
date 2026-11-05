function Write-HarnessModelTelemetry {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Agent,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][datetime]$StartedAt,
        [Parameter(Mandatory = $true)][string]$Status,
        $Response = $null,
        [string]$ErrorMessage = ""
    )

    try {
        $logDir = Join-Path $Root "logs"

        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force |
                Out-Null
        }

        $endedAt = [datetime]::UtcNow
        $durationMs = [math]::Round(
            ($endedAt - $StartedAt.ToUniversalTime()).TotalMilliseconds, 0
        )

        $runId = if (-not [string]::IsNullOrWhiteSpace($env:AI_HARNESS_RUN_ID)) {
            $env:AI_HARNESS_RUN_ID
        }
        else {
            [guid]::NewGuid().ToString()
        }
        $record = [pscustomobject][ordered]@{
            timestamp_utc           = $endedAt.ToString("o")
            run_id                  = $runId
            agent                   = $Agent
            model                   = $Model
            status                  = $Status
            started_at_utc          = $StartedAt.ToUniversalTime().ToString("o")
            duration_ms             = $durationMs
            total_duration_ns       = $Response.total_duration
            load_duration_ns        = $Response.load_duration
            prompt_eval_count       = $Response.prompt_eval_count
            prompt_eval_duration_ns = $Response.prompt_eval_duration
            eval_count              = $Response.eval_count
            eval_duration_ns        = $Response.eval_duration
            error                   = $ErrorMessage
        }

        $jsonlPath = Join-Path $logDir "model-calls.jsonl"
        $csvPath = Join-Path $logDir "model-calls.csv"

        $record |
            ConvertTo-Json -Depth 5 -Compress |
            Add-Content -Path $jsonlPath -Encoding UTF8

        if (Test-Path $csvPath) {
            $csvLines = @($record | ConvertTo-Csv -NoTypeInformation)
            if ($csvLines.Count -gt 1) {
                $csvLines | Select-Object -Skip 1 |
                    Add-Content -Path $csvPath -Encoding UTF8
            }
        }
        else {
            $record | Export-Csv -Path $csvPath `
                -NoTypeInformation -Encoding UTF8
        }
    }
    catch {
        Write-Warning "Telemetry logging failed: $($_.Exception.Message)"
    }
}