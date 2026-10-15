param(
    [string]$Task,
    [string]$SpecFile,
    [string]$ReviewFile,
    [string]$Model,
    [string]$OutputFile
)

# Simulate a successful reviser that produces an empty specification.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputFile, "", $utf8NoBom)

exit 0