param(
    [string]$Agent = "spec",

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Task,

    [string[]]$Models = @(
        "qwen2.5-coder:7b",
        "qwen2.5-coder:32b",
        "deepseek-r1:32b"
    ),

    [ValidateRange(1, 20)]
    [int]$Repetitions = 3,

    [string]$OutputDirectory = "",

    [switch]$SkipWarmUp
)

function Get-Median {
    param(
        [double[]]$Values
    )

    if (-not $Values -or $Values.Count -eq 0) {
        return $null
    }

    $sorted = @($Values | Sort-Object)
    $count = $sorted.Count
    $middle = [math]::Floor($count / 2)

    if ($count % 2 -eq 0) {
        return [math]::Round(
            ($sorted[$middle - 1] + $sorted[$middle]) / 2,
            2
        )
    }

    return [math]::Round($sorted[$middle], 2)
}

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $PSScriptRoot "run-agent.ps1"
$telemetryFile = Join-Path $root "logs\model-calls.jsonl"
$powerShellExe = Join-Path $PSHOME "powershell.exe"

if (-not (Test-Path $runner -PathType Leaf)) {
    throw "Runner not found: $runner"
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root "logs\benchmarks"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force |
    Out-Null

$resultsDirectory = Join-Path $OutputDirectory "responses"
New-Item -ItemType Directory -Path $resultsDirectory -Force |
    Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$runsCsv = Join-Path $OutputDirectory "benchmark-runs-$timestamp.csv"
$summaryCsv = Join-Path $OutputDirectory "benchmark-summary-$timestamp.csv"

$results = @()
$totalRuns = $Models.Count * $Repetitions
$currentRun = 0

$previousRunId = $env:AI_HARNESS_RUN_ID

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "       AI HARNESS MODEL BENCHMARK" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Agent       : $Agent"
Write-Host "Models      : $($Models.Count)"
Write-Host "Repetitions : $Repetitions"
Write-Host "Total runs  : $totalRuns"
Write-Host "Warm-up     : $(if ($SkipWarmUp) { 'Disabled' } else { 'Enabled' })"
Write-Host ""

try {
    if (-not $SkipWarmUp) {
        foreach ($model in $Models) {
            $warmupRunId = [guid]::NewGuid().ToString()
            $warmupOutputFile = Join-Path $resultsDirectory "$warmupRunId-warmup.txt"

            Write-Host ""
            Write-Host "WARM-UP | $model" -ForegroundColor Cyan

            $env:AI_HARNESS_RUN_ID = $warmupRunId

            try {
                $warmupOutput = @(
                    & $powerShellExe `
                        -NoProfile `
                        -ExecutionPolicy Bypass `
                        -File $runner `
                        -Agent $Agent `
                        -Model $model `
                        -Task $Task `
                        -OutputFile $warmupOutputFile 2>&1 |
                        ForEach-Object { $_.ToString() }
                )

                $warmupExitCode = $LASTEXITCODE

                if ($warmupExitCode -eq 0) {
                    Write-Host "WARM-UP SUCCESS | $model" -ForegroundColor Green
                }
                else {
                    Write-Warning "Warm-up failed for $model. Measured runs will continue."
                    $warmupOutput | ForEach-Object { Write-Host $_ -ForegroundColor DarkYellow }
                }
            }
            catch {
                Write-Warning "Warm-up error for $model`: $($_.Exception.Message)"
            }
        }
    }
    foreach ($model in $Models) {
        for ($iteration = 1; $iteration -le $Repetitions; $iteration++) {

            $currentRun++

            $runId = [guid]::NewGuid().ToString()
            $outputFile = Join-Path $resultsDirectory "$runId.txt"

            Write-Host ""
            Write-Host "[$currentRun/$totalRuns] $model - Run $iteration/$Repetitions" `
                -ForegroundColor Yellow

            $env:AI_HARNESS_RUN_ID = $runId

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $exitCode = -1
            $executionError = ""

            try {
                $childOutput = @(
                    & $powerShellExe `
                        -NoProfile `
                        -ExecutionPolicy Bypass `
                        -File $runner `
                        -Agent $Agent `
                        -Model $model `
                        -Task $Task `
                        -OutputFile $outputFile 2>&1 |
                        ForEach-Object { $_.ToString() }
                )

                $exitCode = $LASTEXITCODE

                if ($exitCode -ne 0) {
                    $executionError = $childOutput -join "`n"
                }
            }
            catch {
                $executionError = $_.Exception.Message
            }
            finally {
                $stopwatch.Stop()
            }

            # Recuperar el registre exacte de telemetria
            $telemetry = $null

            if (Test-Path $telemetryFile) {
                try {
                    $telemetry = Get-Content $telemetryFile -Encoding UTF8 |
                        ForEach-Object {
                            try {
                                $_ | ConvertFrom-Json
                            }
                            catch {
                                $null
                            }
                        } |
                        Where-Object { $_.run_id -eq $runId } |
                        Select-Object -First 1
                }
                catch {
                    Write-Warning "Could not read telemetry: $($_.Exception.Message)"
                }
            }

            $status = if ($exitCode -eq 0 -and $telemetry) {
                "success"
            }
            else {
                "error"
            }

            if (-not $telemetry -and
                [string]::IsNullOrWhiteSpace($executionError)) {
                $executionError = "No telemetry record found for run $runId"
            }

            $promptTokens = if ($telemetry) {
                [double]$telemetry.prompt_eval_count
            } else { 0 }

            $outputTokens = if ($telemetry) {
                [double]$telemetry.eval_count
            } else { 0 }

            $promptSeconds = if ($telemetry -and
                [double]$telemetry.prompt_eval_duration_ns -gt 0) {
                [double]$telemetry.prompt_eval_duration_ns / 1000000000
            } else { 0 }

            $generationSeconds = if ($telemetry -and
                [double]$telemetry.eval_duration_ns -gt 0) {
                [double]$telemetry.eval_duration_ns / 1000000000
            } else { 0 }

            $promptTokensPerSecond = if ($promptSeconds -gt 0) {
                [math]::Round($promptTokens / $promptSeconds, 2)
            } else { 0 }

            $generationTokensPerSecond = if ($generationSeconds -gt 0) {
                [math]::Round($outputTokens / $generationSeconds, 2)
            } else { 0 }

            $row = [pscustomobject][ordered]@{
                run_id                   = $runId
                model                    = $model
                agent                    = $Agent
                iteration                = $iteration
                status                   = $status
                exit_code                = $exitCode
                process_duration_ms      = $stopwatch.ElapsedMilliseconds
                model_duration_ms        = if ($telemetry) { $telemetry.duration_ms } else { $null }
                load_duration_ns         = if ($telemetry) { $telemetry.load_duration_ns } else { $null }
                load_duration_ms         = if ($telemetry) {
                    [math]::Round(([double]$telemetry.load_duration_ns / 1000000), 2)
                } else { $null }
                prompt_eval_count        = $promptTokens
                prompt_eval_duration_ns  = if ($telemetry) { $telemetry.prompt_eval_duration_ns } else { $null }
                prompt_eval_duration_ms  = if ($telemetry) {
                    [math]::Round(([double]$telemetry.prompt_eval_duration_ns / 1000000), 2)
                } else { $null }                
                prompt_tokens_per_second = $promptTokensPerSecond
                eval_count               = $outputTokens
                eval_duration_ns         = if ($telemetry) { $telemetry.eval_duration_ns } else { $null }
                eval_duration_ms         = if ($telemetry) {
                    [math]::Round(([double]$telemetry.eval_duration_ns / 1000000), 2)
                } else { $null }                
                generation_tokens_second = $generationTokensPerSecond
                error                    = if ($telemetry -and $telemetry.error) {
                    $telemetry.error
                } else {
                    $executionError
                }
                response_file            = if (Test-Path $outputFile) { $outputFile } else { "" }
            }

            $results += $row

            if ($status -eq "success") {
                Write-Host "SUCCESS | $($row.process_duration_ms) ms | $outputTokens tokens | $generationTokensPerSecond tok/s" `
                    -ForegroundColor Green
            }
            else {
                Write-Host "ERROR | $($row.error)" -ForegroundColor Red            }
        }
    }
}
finally {
    $env:AI_HARNESS_RUN_ID = $previousRunId
}

# Exportar resultats individuals
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $runsCsv -NoTypeInformation -Encoding UTF8
}

# Calcular resum per model
$summary = foreach ($group in ($results | Group-Object model)) {

    $successful = @(
        $group.Group | Where-Object { $_.status -eq "success" }
    )

    if ($successful.Count -gt 0) {

        # Extreure els valors numèrics de les execucions correctes
        $processTimes = @($successful | ForEach-Object { [double]$_.process_duration_ms })
        $modelTimes = @($successful | ForEach-Object { [double]$_.model_duration_ms })
        $loadTimes = @($successful | ForEach-Object { [double]$_.load_duration_ms })
        $promptTimes = @($successful | ForEach-Object { [double]$_.prompt_eval_duration_ms })
        $generationTimes = @($successful | ForEach-Object { [double]$_.eval_duration_ms })
        $promptSpeeds = @($successful | ForEach-Object { [double]$_.prompt_tokens_per_second })
        $generationSpeeds = @($successful | ForEach-Object { [double]$_.generation_tokens_second })
        $promptTokens = @($successful | ForEach-Object { [double]$_.prompt_eval_count })
        $outputTokens = @($successful | ForEach-Object { [double]$_.eval_count })

        [pscustomobject][ordered]@{
            model                           = $group.Name
            total_runs                      = $group.Count
            successful_runs                 = $successful.Count
            failed_runs                     = $group.Count - $successful.Count

            avg_process_duration_ms         = [math]::Round(($processTimes | Measure-Object -Average).Average, 2)
            median_process_duration_ms      = Get-Median -Values $processTimes

            avg_model_duration_ms           = [math]::Round(($modelTimes | Measure-Object -Average).Average, 2)
            median_model_duration_ms        = Get-Median -Values $modelTimes

            avg_load_duration_ms            = [math]::Round(($loadTimes | Measure-Object -Average).Average, 2)
            median_load_duration_ms         = Get-Median -Values $loadTimes

            avg_prompt_eval_duration_ms     = [math]::Round(($promptTimes | Measure-Object -Average).Average, 2)
            median_prompt_eval_duration_ms  = Get-Median -Values $promptTimes

            avg_eval_duration_ms            = [math]::Round(($generationTimes | Measure-Object -Average).Average, 2)
            median_eval_duration_ms         = Get-Median -Values $generationTimes

            avg_prompt_tokens               = [math]::Round(($promptTokens | Measure-Object -Average).Average, 2)
            avg_output_tokens               = [math]::Round(($outputTokens | Measure-Object -Average).Average, 2)

            avg_prompt_tokens_per_sec       = [math]::Round(($promptSpeeds | Measure-Object -Average).Average, 2)
            median_prompt_tokens_per_sec    = Get-Median -Values $promptSpeeds

            avg_generation_tokens_sec       = [math]::Round(($generationSpeeds | Measure-Object -Average).Average, 2)
            median_generation_tokens_sec    = Get-Median -Values $generationSpeeds
        }
    }
    else {
        [pscustomobject][ordered]@{
            model                           = $group.Name
            total_runs                      = $group.Count
            successful_runs                 = 0
            failed_runs                     = $group.Count

            avg_process_duration_ms         = $null
            median_process_duration_ms      = $null
            avg_model_duration_ms           = $null
            median_model_duration_ms        = $null
            avg_load_duration_ms            = $null
            median_load_duration_ms         = $null
            avg_prompt_eval_duration_ms     = $null
            median_prompt_eval_duration_ms  = $null
            avg_eval_duration_ms            = $null
            median_eval_duration_ms         = $null
            avg_prompt_tokens               = $null
            avg_output_tokens               = $null
            avg_prompt_tokens_per_sec       = $null
            median_prompt_tokens_per_sec    = $null
            avg_generation_tokens_sec       = $null
            median_generation_tokens_sec    = $null
        }
    }
}

if (@($summary).Count -gt 0) {
    $summary | Export-Csv -Path $summaryCsv -NoTypeInformation -Encoding UTF8
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "             BENCHMARK SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$summary | Format-Table -AutoSize

Write-Host ""
Write-Host "Individual results : $runsCsv"
Write-Host "Model summary      : $summaryCsv"
Write-Host "Response files     : $resultsDirectory"
Write-Host ""

if (@($results | Where-Object { $_.status -eq "error" }).Count -gt 0) {
    Write-Warning "Some benchmark runs failed. Check the CSV for details."
}
else {
    Write-Host "All benchmark runs completed successfully." -ForegroundColor Green
}
