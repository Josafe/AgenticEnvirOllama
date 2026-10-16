
$ErrorActionPreference = "Stop"

$runner = Join-Path $PSScriptRoot "run-agent.ps1"

if (-not (Test-Path $runner -PathType Leaf)) {
    throw "Runner not found: $runner"
}

$script:passed = 0
$script:failed = 0

function Invoke-RunnerTest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Arguments,

        [int]$ExpectedExitCode = 1
    )

    Write-Host ""
    Write-Host "=== TEST: $Name ===" -ForegroundColor Cyan

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        $output = & powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $runner `
            @Arguments 2>&1 | ForEach-Object { $_.ToString() }

        $actualExitCode = $LASTEXITCODE

        foreach ($line in $output) {
            Write-Host $line
        }
    }
    catch {
        Write-Host "Test execution error: $($_.Exception.Message)" `
            -ForegroundColor Red
        $actualExitCode = -1
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($actualExitCode -eq $ExpectedExitCode) {
        Write-Host "Expected: $ExpectedExitCode | Actual: $actualExitCode" `
            -ForegroundColor Green
        Write-Host "RESULT: PASS" -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host "Expected: $ExpectedExitCode | Actual: $actualExitCode" `
            -ForegroundColor Red
        Write-Host "RESULT: FAIL" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "           RUNNER TEST SUITE" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

Invoke-RunnerTest `
    -Name "Missing agent is rejected" `
    -Arguments @("-Task", "Test task")

Invoke-RunnerTest `
    -Name "Missing task is rejected" `
    -Arguments @("-Agent", "spec")

Invoke-RunnerTest `
    -Name "Invalid agent name is rejected" `
    -Arguments @(
        "-Agent", "../outside",
        "-Task", "Test task"
    )

Invoke-RunnerTest `
    -Name "Unknown agent is rejected before contacting Ollama" `
    -Arguments @(
        "-Agent", "agent-does-not-exist",
        "-Task", "Test task"
    )

Invoke-RunnerTest `
    -Name "Empty model name is rejected" `
    -Arguments @(
        "-Agent", "spec",
        "-Task", "Test task",
        "-Model", '""'
    )

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "              TEST SUMMARY" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Passed: $script:passed"
Write-Host "Failed: $script:failed"

if ($script:failed -eq 0) {
    Write-Host "STATUS: PASS" -ForegroundColor Green
    exit 0
}

Write-Host "STATUS: FAIL" -ForegroundColor Red
exit 1
