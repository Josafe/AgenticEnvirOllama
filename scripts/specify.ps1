param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [string]$Model = "qwen2.5-coder:32b",

    [string]$RunnerScript,
    [string]$ValidatorScript,
    [string]$ReviewerScript,
    [string]$ReviserScript
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*$') {
    Write-Host ""
    Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
    Write-Host "Invalid specification name: $Name" -ForegroundColor Red
    Write-Host "Use only letters, numbers, dots, underscores and hyphens."
    Write-Host "The name must start with a letter or number."
    exit 2
}

$specDirectory = Join-Path $root "specs"
$specFile = Join-Path $specDirectory "$Name.md"
$reviewFile = Join-Path $specDirectory "$Name.review.md"

$runner = if ($RunnerScript) {
    $RunnerScript
}
else {
    Join-Path $PSScriptRoot "run-agent.ps1"
}

$validator = if ($ValidatorScript) {
    $ValidatorScript
}
else {
    Join-Path $PSScriptRoot "validate-spec.ps1"
}

$reviewer = if ($ReviewerScript) {
    $ReviewerScript
}
else {
    Join-Path $PSScriptRoot "review-spec.ps1"
}

$reviser = if ($ReviserScript) {
    $ReviserScript
}
else {
    Join-Path $PSScriptRoot "revise-spec.ps1"
}

$maxRevisions = 3

if (-not (Test-Path $runner)) {
    throw "Agent runner not found: $runner"
}

if (-not (Test-Path $validator)) {
    throw "Specification validator not found: $validator"
}

if (-not (Test-Path $reviewer)) {
    throw "Specification reviewer not found: $reviewer"
}

if (-not (Test-Path $reviser)) {
    throw "Specification reviser not found: $reviser"
}

if (-not (Test-Path $specDirectory)) {
    New-Item -ItemType Directory -Path $specDirectory -Force | Out-Null
}

Write-Host ""
Write-Host "=== Specification Workflow ===" -ForegroundColor Cyan
Write-Host "Name  : $Name"
Write-Host "Model : $Model"
Write-Host ""

# ------------------------------------------------------------
# Step 1 - Generate specification
# ------------------------------------------------------------

Write-Host "Step 1 - Generating specification..." -ForegroundColor Yellow
Write-Host ""

Remove-Item $specFile -Force -ErrorAction SilentlyContinue
& $runner `
    -Agent "spec" `
    -Task $Task `
    -Model $Model `
    -OutputFile $specFile

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
    Write-Host "Specification agent failed." -ForegroundColor Red
    exit 2
}


if (
    -not (Test-Path $specFile -PathType Leaf) -or
    (Get-Item $specFile).Length -eq 0
) {
    Write-Host ""
    Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
    Write-Host "Specification file is missing or empty: $specFile" -ForegroundColor Red
    exit 2
}


# ------------------------------------------------------------
# Step 2 - Initial structural validation
# ------------------------------------------------------------

Write-Host ""
Write-Host "Step 2 - Validating specification structure..." -ForegroundColor Yellow
Write-Host ""

& $validator `
    -SpecFile $specFile

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
    Write-Host "Generated specification failed structural validation." -ForegroundColor Red
    Write-Host "File: $specFile"
    exit 2
}

# ------------------------------------------------------------
# Step 3+ - Review / revision loop
# ------------------------------------------------------------

$currentSpecFile = $specFile

for ($revision = 0; $revision -le $maxRevisions; $revision++) {

    $reviewIteration = $revision + 1

    if ($revision -eq 0) {
        $currentReviewFile = $reviewFile
    }
    else {
        $currentReviewFile = Join-Path `
            $specDirectory `
            "$Name.revised-v$revision.review.md"
    }

    Write-Host ""
    Write-Host "Review iteration $reviewIteration" -ForegroundColor Cyan
    Write-Host "Specification: $currentSpecFile"
    Write-Host ""

    # --------------------------------------------------------
    # Semantic review
    # --------------------------------------------------------

    Write-Host "Reviewing specification semantics..." -ForegroundColor Yellow
    Write-Host ""

    Remove-Item $currentReviewFile -Force -ErrorAction SilentlyContinue
    & $reviewer `
        -Task $Task `
        -SpecFile $currentSpecFile `
        -Model $Model `
        -OutputFile $currentReviewFile

    $reviewExitCode = $LASTEXITCODE

    # Validate reviewer exit code contract.

    if ($reviewExitCode -notin @(0, 1, 2)) {
        Write-Host ""
        Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
        Write-Host "Unexpected reviewer exit code: $reviewExitCode" -ForegroundColor Red
        exit 2
    }

    # Exit code 2 is an execution error and is handled below.
    # PASS/FAIL results must have a non-empty review artifact.

    if ($reviewExitCode -ne 2) {
        if (
            -not (Test-Path $currentReviewFile -PathType Leaf) -or
            (Get-Item $currentReviewFile).Length -eq 0
        ) {
            Write-Host ""
            Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
            Write-Host "Reviewer report is missing or empty: $currentReviewFile" -ForegroundColor Red
            exit 2
        }
    }


    if ($reviewExitCode -eq 0) {

        Write-Host ""
        Write-Host "=== Specification Workflow Complete ===" -ForegroundColor Green
        Write-Host ""
        Write-Host "Specification: $currentSpecFile"
        Write-Host "Validation   : PASS"
        Write-Host "Review       : PASS"
        Write-Host "Review File  : $currentReviewFile"
        Write-Host "Revisions    : $revision"
        Write-Host ""

        exit 0
    }

    if ($reviewExitCode -eq 2) {
        Write-Host ""
        Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
        Write-Host "Specification reviewer encountered an execution error." -ForegroundColor Red
        Write-Host "Specification: $currentSpecFile"
        Write-Host "Review       : $currentReviewFile"
        exit 2
    }
    # --------------------------------------------------------
    # Reviewer failed
    # --------------------------------------------------------

    if ($revision -eq $maxRevisions) {
        Write-Host ""
        Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
        Write-Host "Maximum revision attempts reached ($maxRevisions)." -ForegroundColor Red
        Write-Host ""
        Write-Host "Specification: $currentSpecFile"
        Write-Host "Review       : $currentReviewFile"
        Write-Host ""

        exit 1
    }

    # --------------------------------------------------------
    # Revision
    # --------------------------------------------------------

    $nextRevision = $revision + 1

    $nextSpecFile = Join-Path `
        $specDirectory `
        "$Name.revised-v$nextRevision.md"

    Write-Host ""
    Write-Host "Semantic review failed." -ForegroundColor Red
    Write-Host "Starting revision $nextRevision/$maxRevisions..." -ForegroundColor Yellow
    Write-Host ""

    Remove-Item $nextSpecFile -Force -ErrorAction SilentlyContinue
    & $reviser `
        -Task $Task `
        -SpecFile $currentSpecFile `
        -ReviewFile $currentReviewFile `
        -Model $Model `
        -OutputFile $nextSpecFile

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
        Write-Host "Specification reviser failed." -ForegroundColor Red
        Write-Host "Review: $currentReviewFile"
        exit 2
    }

    if (
        -not (Test-Path $nextSpecFile -PathType Leaf) -or
        (Get-Item $nextSpecFile).Length -eq 0
    ) {
        Write-Host ""
        Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
        Write-Host "Revised specification is missing or empty." -ForegroundColor Red
        Write-Host "Expected: $nextSpecFile"
        exit 2
    }

    # --------------------------------------------------------
    # Structural validation of revised specification
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Validating revised specification structure..." -ForegroundColor Yellow
    Write-Host ""

    & $validator `
        -SpecFile $nextSpecFile

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "=== Specification Workflow Failed ===" -ForegroundColor Red
        Write-Host "Revised specification failed structural validation." -ForegroundColor Red
        Write-Host "File: $nextSpecFile"
        exit 2
    }

    $currentSpecFile = $nextSpecFile
}

exit 1