[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('openai', 'claude', IgnoreCase = $true)]
    [string]$Model,
    [Parameter(Position = 1)]
    [string[]]$Skills,
    [Parameter(Position = 2)]
    [string]$ProjectPath
)
$ErrorActionPreference = 'Stop'
$factoryArguments = @((Join-Path $PSScriptRoot 'install-factory.py'))
if ($Model) { $factoryArguments += @('--model', $Model.ToLowerInvariant()) }
if ($Skills) { $factoryArguments += @('--skills', ($Skills -join ',')) }
if ($ProjectPath) { $factoryArguments += @('--project', $ProjectPath) }
& python @factoryArguments
exit $LASTEXITCODE
