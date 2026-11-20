param([string]$Entry, [string]$Project, [string]$InputFile, [AllowEmptyString()][string]$Label, [string]$Bin, [string]$Missing, [string]$DefaultLabel, [ValidateSet('gh.ps1','gh.exe')][string]$Fixture = 'gh.ps1', [int]$ConsoleCodePage = 0)
$ErrorActionPreference = 'Stop'
if ($ConsoleCodePage) { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding($ConsoleCodePage) }
# Restrict discovery in the child shell. No installed gh can be a fallback.
$env:PATH = if ($Missing -eq 'git') { $Bin } else { $Bin + [IO.Path]::PathSeparator + $env:FACTORY_ADD_GIT_DIR }
$gh = Get-Command gh -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
if ($Missing -eq 'gh') { if ($gh) { throw 'Missing-tool fixture found a GitHub executable.' } }
elseif (-not $gh -or $gh.Source -ne (Join-Path $Bin $Fixture)) { throw 'Controlled GitHub fixture is not active.' }
if ($DefaultLabel -eq 'yes') { & $Entry add -ProjectPath $Project -File $InputFile }
else { & $Entry add -ProjectPath $Project -File $InputFile -Label $Label }
exit $LASTEXITCODE
