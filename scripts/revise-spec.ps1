param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $true)]
    [string]$SpecFile,

    [Parameter(Mandatory = $true)]
    [string]$ReviewFile,

    [string]$Model = "qwen2.5-coder:32b",

    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

$agentFile = Join-Path $root ".ai\agents\spec-reviser.md"
$contractFile = Join-Path $root ".ai\rules\agent-contract.md"
$instructionsFile = Join-Path $root "AGENTS.md"

if (-not (Test-Path $SpecFile)) {
    throw "Specification file not found: $SpecFile"
}

if (-not (Test-Path $ReviewFile)) {
    throw "Review file not found: $ReviewFile"
}

if (-not (Test-Path $agentFile)) {
    throw "Specification reviser agent not found: $agentFile"
}

if (-not (Test-Path $contractFile)) {
    throw "Agent contract not found: $contractFile"
}

if (-not (Test-Path $instructionsFile)) {
    throw "AGENTS.md not found: $instructionsFile"
}

$specContent = Get-Content $SpecFile -Raw
$reviewContent = Get-Content $ReviewFile -Raw
$agentInstructions = Get-Content $agentFile -Raw
$agentContract = Get-Content $contractFile -Raw
$projectInstructions = Get-Content $instructionsFile -Raw

if ([string]::IsNullOrWhiteSpace($specContent)) {
    throw "Specification file is empty."
}

if ([string]::IsNullOrWhiteSpace($reviewContent)) {
    throw "Review file is empty."
}

Write-Host ""
Write-Host "=== Specification Reviser ===" -ForegroundColor Cyan
Write-Host "Model : $Model"
Write-Host "Spec  : $SpecFile"
Write-Host "Review: $ReviewFile"
Write-Host ""

try {
    $null = Invoke-RestMethod `
        -Uri "http://localhost:11434/api/tags" `
        -Method Get `
        -ErrorAction Stop
}
catch {
    throw "Ollama is not reachable at http://localhost:11434. Make sure Ollama is running."
}

$systemPrompt = @"
You are the Specification Reviser Agent operating inside the AI Development Harness.

PROJECT INSTRUCTIONS:
$projectInstructions

AGENT CONTRACT:
$agentContract

AGENT ROLE:
$agentInstructions

ORIGINAL USER REQUEST:
$Task

CURRENT SPECIFICATION:
$specContent

SPECIFICATION REVIEW:
$reviewContent

Revise the specification according to the reviewer findings.

IMPORTANT: Perform a MINIMAL REVISION, not a rewrite.

Your task is NOT to make the specification more complete.
Your task is ONLY to remove or correct unsupported content identified by the reviewer.

Follow these rules in this exact order:

1. Start from the CURRENT SPECIFICATION.
2. Preserve every requirement that is directly supported by the ORIGINAL USER REQUEST.
3. Remove every unsupported requirement identified by the REVIEW.
4. Do NOT replace removed requirements with new requirements.
5. Do NOT invent edge cases.
6. Do NOT invent open questions.
7. Do NOT invent assumptions.
8. Do NOT invent technical dependencies.
9. Do NOT invent security requirements.
10. Do NOT invent validation rules.
11. Do NOT invent UI behavior.
12. Do NOT invent error handling.
13. Do NOT invent implementation details.
14. Do NOT invent facts about the existing system.
15. Do NOT add architecture decisions.

CRITICAL ACCEPTANCE CRITERIA RULE:

The final specification MUST contain at least one acceptance criterion because the specification format requires acceptance criteria.

The acceptance criterion must verify the COMPLETE behavior explicitly requested by the user.

Do not reduce a requested feature to an intermediate input step.

For this exact request:

"Create a specification for a simple user registration feature with email and password."

the correct minimal acceptance criterion is:

### AC-001

**Source:** USER

A user can register using an email address and a password.

This does NOT introduce additional behavior. "Register" is the core behavior explicitly requested by the original request.

Do NOT add:

- Confirmation messages
- Email validation
- Password validation
- Password length
- Error messages
- Security requirements
- Storage requirements
- Database requirements
- UI behavior

unless the original user request explicitly requires those decisions.

CRITICAL CONTEXT RULE:

Do not invent facts about the existing system.

For this exact request, do not state that the system currently does or does not have registration functionality unless that fact was explicitly provided.

Use only context directly supported by the supplied input.

FINAL SELF-CHECK BEFORE OUTPUT:

Before returning the specification, verify all of the following:

STRUCTURAL REQUIREMENT:

The final output MUST contain ALL of these section headings, exactly:

# Specification
## Goal
## Context
## Functional Requirements
## Non-Functional Requirements
## Acceptance Criteria
## Edge Cases
## Dependencies
## Open Questions
## Assumptions

Never omit any of these sections.

If a section has no supported content, write exactly:

None

For example:

## Non-Functional Requirements

None

## Edge Cases

None

## Dependencies

None

## Open Questions

None

## Assumptions

None

FINAL SELF-CHECK:

Before returning the specification, verify:

- All 10 required section headings are present.
- At least one FR-XXX exists.
- At least one AC-XXX exists.
- Every requirement has a valid Source.
- No unsupported requirement from the review remains.
- No new requirement was introduced.
- No invented edge case remains.
- No invented open question remains.
- No invented assumption remains.
- No invented technical dependency remains.
- No invented project fact remains.
- The specification remains faithful to the original request.

The required section order is:

# Specification
## Goal
## Context
## Functional Requirements
## Non-Functional Requirements
## Acceptance Criteria
## Edge Cases
## Dependencies
## Open Questions
## Assumptions

Return ONLY the complete revised specification.
"@

$body = @{
    model  = $Model
    system = $systemPrompt
    prompt = "Revise the specification according to the original request and review findings."
    stream = $false
} | ConvertTo-Json -Depth 10

Write-Host "Sending specification to reviser..." -ForegroundColor Yellow
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
                Write-Host "Response body:" -ForegroundColor Yellow
                Write-Host $errorBody -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "Could not read Ollama error response." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "No HTTP response was available." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Exception:" -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow

    Write-Host "=== END OLLAMA ERROR ===" -ForegroundColor Red

    throw "Specification revision failed."
}

$revision = $response.response

if ([string]::IsNullOrWhiteSpace($revision)) {
    throw "Reviser returned an empty response."
}

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutputFile, $revision, $utf8NoBom)
}

Write-Host ""
Write-Host "=== Revised Specification ===" -ForegroundColor Green
Write-Host ""

$revision

exit 0