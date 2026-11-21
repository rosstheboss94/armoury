$ErrorActionPreference = 'Stop'
if (-not $env:FACTORY_LABEL_FIXTURE -or -not (Test-Path -LiteralPath $env:FACTORY_LABEL_FIXTURE)) { exit 90 }
if ($env:GH_DEBUG) { [Console]::Error.WriteLine('API debug logging must be disabled.'); exit 90 }
$dir = $env:FACTORY_LABEL_FIXTURE
Add-Content -LiteralPath (Join-Path $dir 'calls') -Value ($args -join ' ') -Encoding utf8
$mode = [IO.File]::ReadAllText((Join-Path $dir 'mode')).Trim()
$hostName = [IO.File]::ReadAllText((Join-Path $dir 'host')).Trim()
$endpoint = [string](@($args | Where-Object { $_ -like 'repos/*' } | Select-Object -First 1) | Select-Object -First 1)
function Fail([string]$Message) { Write-Error $Message -ErrorAction Continue; exit 1 }
function Read-Names([string]$File) {
    if (-not (Test-Path -LiteralPath $File)) { return @() }
    return @([IO.File]::ReadAllLines($File) | Where-Object { $_ -ne '' })
}
function Write-Names([string]$File, [string[]]$Names) {
    $text = if ($Names.Count) { ($Names -join "`n") + "`n" } else { '' }
    [IO.File]::WriteAllText($File, $text)
}
if ($args[0] -eq 'repo' -and $args[1] -eq 'view') {
    Write-Output ([IO.File]::ReadAllText((Join-Path $dir 'context')))
    exit 0
}
if ($args[0] -ne 'api' -or $args[1] -ne '--hostname' -or $args[2] -ne $hostName -or $args[3] -ne '-X' -or -not $endpoint) { Fail 'Unexpected offline GitHub fixture call.' }
$method = $args[4]
$issueFile = Join-Path $dir 'issue-labels'
$repoFile = Join-Path $dir 'repo-labels'
if ($method -eq 'GET' -and $endpoint -match '^repos/fixture/project/issues/[^/]+/labels$') {
    if ($mode -eq 'missing-issue') { Fail 'HTTP 404 Not Found' }
    Write-Output ([IO.File]::ReadAllText($issueFile))
} elseif ($method -eq 'GET' -and $endpoint -match '^repos/fixture/project/labels/(.+)$') {
    $name = [uri]::UnescapeDataString($Matches[1])
    $requested = [IO.File]::ReadAllText((Join-Path $dir 'requested')).Trim()
    $known = @(Read-Names $repoFile)
    if (($mode -eq 'missing-status' -and $name -eq $requested) -or ($known -cnotcontains $name)) { Fail 'HTTP 404 Not Found' }
    Write-Output $name
} elseif ($method -eq 'POST' -and $endpoint -eq 'repos/fixture/project/labels') {
    $index = [array]::IndexOf($args, '--input')
    $payload = [IO.File]::ReadAllText($args[$index + 1])
    if ($payload -notmatch '"name":"([^"]+)"') { Fail 'Label payload has no name.' }
    $name = $Matches[1]
    if ($payload -notmatch '"color":"([0-9a-fA-F]{6})"') { Fail 'Label payload has no color.' }
    $color = $Matches[1].ToLowerInvariant()
    $known = @(Read-Names $repoFile)
    if ($known -cnotcontains $name) { $known += $name }
    Write-Names $repoFile $known
    [IO.File]::WriteAllText((Join-Path $dir 'created'), "$name $color`n")
    Write-Output $name
} elseif ($method -eq 'POST' -and $endpoint -match '^repos/fixture/project/issues/[^/]+/labels$') {
    if ($mode -eq 'add-fail') { Fail 'HTTP 422 validation failed.' }
    $index = [array]::IndexOf($args, '--input')
    $payload = [IO.File]::ReadAllText($args[$index + 1])
    if ($payload -notmatch '"labels":\["([^"]+)"\]') { Fail 'Issue label payload has no name.' }
    $name = $Matches[1]
    $known = @(Read-Names $issueFile)
    if ($known -cnotcontains $name) { $known += $name }
    Write-Names $issueFile $known
    Write-Output $name
} elseif ($method -eq 'DELETE' -and $endpoint -match '^repos/fixture/project/issues/[^/]+/labels/(.+)$') {
    if ($mode -eq 'delete-fail') { Fail 'HTTP 500 could not delete label.' }
    $name = [uri]::UnescapeDataString($Matches[1])
    $known = @(Read-Names $issueFile | Where-Object { $_ -cne $name })
    Write-Names $issueFile $known
} else { Fail 'Unexpected offline GitHub fixture call.' }
exit 0
