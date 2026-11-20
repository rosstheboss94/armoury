$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$bash = Get-Command bash -ErrorAction SilentlyContinue
$gitBash = if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Git/bin/bash.exe' } else { $null }
if ($gitBash -and (Test-Path -LiteralPath $gitBash)) { $bashPath = $gitBash }
elseif ($bash) { $bashPath = $bash.Source }
else { throw 'Factory checks require Bash 4 or newer and PowerShell.' }
& $bashPath (Join-Path $PSScriptRoot 'check-factory.sh')
exit $LASTEXITCODE
