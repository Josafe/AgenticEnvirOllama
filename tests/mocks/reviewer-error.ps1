param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $true)]
    [string]$SpecFile,

    [string]$Model,

    [string]$OutputFile
)

Write-Host ""
Write-Host "=== MOCK REVIEWER ===" -ForegroundColor DarkCyan
Write-Host "Simulated reviewer execution error."

exit 2