
param(
    [string]$Model = "qwen2.5-coder:32b"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$scriptsDirectory = $PSScriptRoot
$mocksDirectory = Join-Path $root "tests\mocks"
$specDirectory = Join-Path $root "specs"

$validator = Join-Path $scriptsDirectory "validate-spec.ps1"
$reviewer = Join-Path $scriptsDirectory "review-spec.ps1"
$specify = Join-Path $scriptsDirectory "specify.ps1"

foreach ($path in @($validator, $reviewer, $specify)) {
    if (-not (Test-Path $path)) {
        throw "Required script not found: $path"
    }
}

$validSpec = Join-Path $root "tests\fixtures\minimal-valid-spec.md"
$invalidSpec = Join-Path $root "tests\fixtures\semantic-invalid-spec.md"

$task = "Create a specification for a simple user registration feature with email and password."

$script:passed = 0
$script:failed = 0

function Invoke-HarnessScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script,

        [string[]]$Arguments = @()
    )

    $output = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $Script `
        @Arguments 2>&1

    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        Write-Host $line
    }

    return [int]$exitCode
}

function Invoke-ExpectedResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$ExpectedExitCode,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "=== TEST: $Name ===" -ForegroundColor Cyan
    Write-Host "Expected exit code: $ExpectedExitCode"

    try {
        $result = & $Action
        $actualExitCode = [int]$result[-1]
    }
    catch {
        Write-Host "Execution error: $($_.Exception.Message)" -ForegroundColor Red
        $actualExitCode = -1
    }

    if ($actualExitCode -eq $ExpectedExitCode) {
        Write-Host "Actual exit code  : $actualExitCode" -ForegroundColor Green
        Write-Host "RESULT            : PASS" -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host "Actual exit code  : $actualExitCode" -ForegroundColor Red
        Write-Host "RESULT            : FAIL" -ForegroundColor Red
        $script:failed++
    }
}

function Assert-FileExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-Host ""
    Write-Host "=== ARTIFACT TEST: $Name ===" -ForegroundColor Cyan
    Write-Host "Path: $Path"

    if (Test-Path $Path -PathType Leaf) {
        Write-Host "RESULT: PASS" -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host "RESULT: FAIL" -ForegroundColor Red
        $script:failed++
    }
}

function Get-MockPath {
    param([string]$Name)

    $path = Join-Path $mocksDirectory $Name

    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Required mock not found: $path"
    }

    return $path
}

function Invoke-MockWorkflow {
    param(
        [string]$Name,
        [string]$Runner = "runner-success.ps1",
        [string]$Validator = "validator-success.ps1",
        [string]$Reviewer = "reviewer-pass.ps1",
        [string]$Reviser = "reviser-success.ps1"
    )

    return Invoke-HarnessScript `
        -Script $specify `
        -Arguments @(
            "-Task", "Deterministic test task",
            "-Name", $Name,
            "-RunnerScript", (Get-MockPath $Runner),
            "-ValidatorScript", (Get-MockPath $Validator),
            "-ReviewerScript", (Get-MockPath $Reviewer),
            "-ReviserScript", (Get-MockPath $Reviser)
        )
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "        SPECIFICATION TEST SUITE" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# TEST: Invalid specification names are rejected.

Invoke-ExpectedResult `
    -Name "Invalid specification name returns 2" `
    -ExpectedExitCode 2 `
    -Action {
        Invoke-HarnessScript `
            -Script $specify `
            -Arguments @(
                "-Task", "Test invalid name handling",
                "-Name", "../outside"
            )
    }
    
# TEST 1: Structural validation passes.

Invoke-ExpectedResult `
    -Name "Valid specification - structural validation" `
    -ExpectedExitCode 0 `
    -Action {
        Invoke-HarnessScript -Script $validator -Arguments @(
            "-SpecFile", $validSpec
        )
    }

# TEST 3: Semantic-invalid fixture passes structural validation.

Invoke-ExpectedResult `
    -Name "Semantically invalid specification - structural validation" `
    -ExpectedExitCode 0 `
    -Action {
        Invoke-HarnessScript -Script $validator -Arguments @(
            "-SpecFile", $invalidSpec
        )
    }

# TEST 5: Deterministic workflow passes without revision.

Invoke-ExpectedResult `
    -Name "Mock workflow - direct PASS" `
    -ExpectedExitCode 0 `
    -Action {
        Invoke-MockWorkflow -Name "test-mock-direct-pass"
    }

# TEST 6: FAIL -> revision -> PASS.

Invoke-ExpectedResult `
    -Name "Mock workflow - revision then PASS" `
    -ExpectedExitCode 0 `
    -Action {
        Remove-Item (Join-Path $env:TEMP "ai-dev-harness-reviewer-state.txt") `
            -Force -ErrorAction SilentlyContinue

        Invoke-MockWorkflow `
            -Name "test-mock-revision-pass" `
            -Reviewer "reviewer-pass-after-revision.ps1"
    }

# TEST 7: Runner error maps to execution error.

Invoke-ExpectedResult `
    -Name "Mock workflow - runner error returns 2" `
    -ExpectedExitCode 2 `
    -Action {
        Invoke-MockWorkflow `
            -Name "test-mock-runner-error" `
            -Runner "runner-error.ps1"
    }
# TEST: Reviewer exits 0 but produces no report.

Invoke-ExpectedResult `
    -Name "Mock workflow - missing review report returns 2" `
    -ExpectedExitCode 2 `
    -Action {
        Invoke-MockWorkflow `
            -Name "test-mock-no-review-output" `
            -Reviewer "reviewer-no-output.ps1"
    }

# TEST: Reviser exits 0 but produces an empty specification.

Invoke-ExpectedResult `
    -Name "Mock workflow - empty revised specification returns 2" `
    -ExpectedExitCode 2 `
    -Action {
        Invoke-MockWorkflow `
            -Name "test-mock-empty-revised-spec" `
            -Reviewer "reviewer-fail.ps1" `
            -Reviser "reviser-empty.ps1"
    }

# TEST 8: Runner exits 0 but creates an empty specification.

Invoke-ExpectedResult `
    -Name "Mock workflow - empty specification returns 2" `
    -ExpectedExitCode 2 `
    -Action {
        Invoke-MockWorkflow `
            -Name "test-mock-empty-spec" `
            -Runner "runner-empty.ps1"
    }

# TEST 9: Runner exits 0 but does not create a specification.

Invoke-ExpectedResult `
    -Name "Mock workflow - missing specification returns 2" `
    -ExpectedExitCode 2 `
    -Action {
        Invoke-MockWorkflow `
            -Name "test-mock-no-output" `
            -Runner "runner-no-output.ps1"
    }
    
# TEST 8: Initial validator error maps to execution error.

Invoke-ExpectedResult `
    -Name "Mock workflow - validator error returns 2" `
    -ExpectedExitCode 2 `
    -Action {
        Invoke-MockWorkflow `
            -Name "test-mock-validator-error" `
            -Validator "validator-error.ps1"
    }

# TEST 9: Reviewer execution error maps to execution error.

Invoke-ExpectedResult `
    -Name "Mock workflow - reviewer error returns 2" `
    -ExpectedExitCode 2 `
    -Action {
        Invoke-MockWorkflow `
            -Name "test-mock-reviewer-error" `
            -Reviewer "reviewer-error.ps1"
    }

# TEST 10: Persistent semantic rejection reaches the revision limit.

Invoke-ExpectedResult `
    -Name "Mock workflow - maximum revisions returns 1" `
    -ExpectedExitCode 1 `
    -Action {
        Invoke-MockWorkflow `
            -Name "test-mock-max-revisions" `
            -Reviewer "reviewer-fail.ps1"
    }

# TEST 11: Verify deterministic workflow artifacts.

Assert-FileExists `
    -Name "Direct-pass specification" `
    -Path (Join-Path $specDirectory "test-mock-direct-pass.md")

Assert-FileExists `
    -Name "Direct-pass review" `
    -Path (Join-Path $specDirectory "test-mock-direct-pass.review.md")

Assert-FileExists `
    -Name "Revised specification" `
    -Path (Join-Path $specDirectory "test-mock-revision-pass.revised-v1.md")

Assert-FileExists `
    -Name "Final revision review" `
    -Path (Join-Path $specDirectory "test-mock-revision-pass.revised-v1.review.md")

# SUMMARY

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "              TEST SUMMARY" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Passed: $script:passed"
Write-Host "Failed: $script:failed"
Write-Host ""

if ($script:failed -eq 0) {
    Write-Host "STATUS: PASS" -ForegroundColor Green
    exit 0
}

Write-Host "STATUS: FAIL" -ForegroundColor Red
exit 1
