param([string]$ScriptPath, [string]$ArgumentsFile)
$ErrorActionPreference = 'Stop'
$decoded = [IO.File]::ReadAllText($ArgumentsFile) | ConvertFrom-Json
[string[]]$forwarded = @($decoded | ForEach-Object { [string]$_ })
& $ScriptPath @forwarded
if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
