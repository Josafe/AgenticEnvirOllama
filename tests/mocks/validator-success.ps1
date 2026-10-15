param(
    [Parameter(Mandatory = $true)]
    [string]$SpecFile
)

Write-Host ""
Write-Host "=== MOCK VALIDATOR ===" -ForegroundColor DarkCyan
Write-Host "Spec: $SpecFile"
Write-Host "STATUS: PASS"

exit 0