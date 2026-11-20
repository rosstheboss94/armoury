[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding($false)
function Copy-Expected([string]$Source, [string]$Target) {
    if ((Test-Path -LiteralPath $Target) -and (Get-FileHash -LiteralPath $Source).Hash -eq (Get-FileHash -LiteralPath $Target).Hash) { return }
    if ($Check) { throw "Factory copy differs: $Target" }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target)) | Out-Null
    [IO.File]::Copy($Source, $Target, $true)
}
foreach ($guide in Get-ChildItem -LiteralPath (Join-Path $repo 'skills/openai/factory/references/roles') -Filter '*.md') {
    $role = $guide.BaseName
    $source = Join-Path $repo "skills/openai/factory-$role/SKILL.md"
    $text = [IO.File]::ReadAllText($source)
    $header = [regex]::Match($text, '(?s)\A---\r?\n.*?\r?\n---\r?\n').Value
    if (-not $header) { throw "Missing role metadata: $role" }
    $temporary = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($temporary, $header + "`n" + [IO.File]::ReadAllText($guide.FullName), $utf8)
        Copy-Expected $temporary $source
    } finally { [IO.File]::Delete($temporary) }
    Copy-Expected $source (Join-Path $repo "skills/claude/factory-$role/SKILL.md")
}
$core = Join-Path $repo 'skills/openai/factory'
foreach ($source in Get-ChildItem -LiteralPath $core -Recurse -File) {
    $relative = $source.FullName.Substring($core.Length + 1).Replace('\','/')
    if ($relative -like 'agents/*' -or $relative -like '*/__pycache__/*') { continue }
    Copy-Expected $source.FullName (Join-Path $repo "skills/claude/factory/$relative")
}
Write-Output 'Factory model copies match.'
