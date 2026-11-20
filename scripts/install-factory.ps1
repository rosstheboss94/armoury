[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('openai', 'claude')]
    [string]$Model,
    [ValidateSet('user', 'project')]
    [string]$Scope,
    [Alias('Project')]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,
    [ValidateNotNullOrEmpty()]
    [string]$SkillsPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-FactoryTarget {
    param([string]$Target, [string]$InstallRoot)
    $candidate = $Target
    while ($candidate -ne $InstallRoot) {
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        if ($null -ne $item) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing a linked installation path: $candidate"
            }
            if ($candidate -ne $Target -and -not $item.PSIsContainer) {
                throw "Installation directory is a file: $candidate"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($candidate)
        if (-not $parent -or $parent -eq $candidate) {
            throw "Installation path escapes its target directory: $Target"
        }
        $candidate = $parent
    }
}

try {
    $Model = $Model.ToLowerInvariant()
    if ($Scope) { $Scope = $Scope.ToLowerInvariant() }
    if (-not $Scope) {
        $Scope = if ($PSBoundParameters.ContainsKey('ProjectPath')) { 'project' } else { 'user' }
    }
    if ($Scope -eq 'user' -and $PSBoundParameters.ContainsKey('ProjectPath')) {
        throw 'Use -ProjectPath only with project scope.'
    }
    if ($Scope -eq 'user') {
        $factoryHome = if ($env:OS -eq 'Windows_NT') { $env:USERPROFILE } else { $env:HOME }
        if (-not $factoryHome) {
            $factoryHome = [Environment]::GetFolderPath('UserProfile')
        }
        if (-not $factoryHome) { throw 'Cannot determine the user home directory.' }
        $factoryInstallRoot = [IO.Path]::GetFullPath($factoryHome)
    } else {
        $factoryInstallRoot = if ($ProjectPath) {
            $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProjectPath)
        } else {
            (Get-Location).ProviderPath
        }
    }
    if (-not (Test-Path -LiteralPath $factoryInstallRoot -PathType Container)) {
        throw "The target directory does not exist: $factoryInstallRoot"
    }
    $factoryInstallRoot = [IO.Path]::GetFullPath($factoryInstallRoot)
    if ($factoryInstallRoot.Length -gt [IO.Path]::GetPathRoot($factoryInstallRoot).Length) {
        $factoryInstallRoot = $factoryInstallRoot.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    }
    $factoryRepo = Split-Path -Parent $PSScriptRoot
    $factoryVendor = if ($Model -eq 'openai') { '.agents' } else { '.claude' }
    $factoryDestination = Join-Path (Join-Path $factoryInstallRoot $factoryVendor) 'skills'
    if ($SkillsPath) {
        if ($PSBoundParameters.ContainsKey('Scope') -or $PSBoundParameters.ContainsKey('ProjectPath')) {
            throw 'Use -SkillsPath without -Scope or -ProjectPath.'
        }
        $factoryDestination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SkillsPath)
        $destinationItem = Get-Item -LiteralPath $factoryDestination -Force
        if (-not $destinationItem.PSIsContainer -or ($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Use -SkillsPath with an existing physical skills directory, not a link.'
        }
        $factoryInstallRoot = $destinationItem.FullName.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
        $factoryDestination = $factoryInstallRoot
    }
    $factoryCollection = Join-Path $factoryRepo 'collections/factory/collection.yaml'
    $factoryMembers = @(foreach ($line in Get-Content -LiteralPath $factoryCollection) {
        if ($line -match '^\s*-\s+([a-z0-9][a-z0-9-]*)\s*$') { $Matches[1] }
    })
    if ($factoryMembers.Count -eq 0) { throw 'The factory collection has no members.' }
    $factoryCopies = New-Object 'System.Collections.Generic.List[object]'
    foreach ($name in $factoryMembers) {
        $source = Join-Path (Join-Path (Join-Path $factoryRepo 'skills') $Model) $name
        if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md') -PathType Leaf)) {
            throw "Collection member is missing: $name"
        }
        foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -Force) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing a linked package path: $($file.FullName)"
            }
            if ($file.PSIsContainer -or $file.Extension -eq '.pyc') { continue }
            $relative = $file.FullName.Substring($source.Length + 1)
            if (($relative -split '[\\/]') -contains '__pycache__') { continue }
            $target = Join-Path (Join-Path $factoryDestination $name) $relative
            Assert-FactoryTarget -Target $target -InstallRoot $factoryInstallRoot
            if (Test-Path -LiteralPath $target) {
                if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                    throw "Existing file differs: $target"
                }
                $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                $targetHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
                if ($sourceHash -ne $targetHash) { throw "Existing file differs: $target" }
            } else {
                $factoryCopies.Add([PSCustomObject]@{ Source = $file.FullName; Target = $target })
            }
        }
    }
    # Check every destination before copying the first file.
    foreach ($copy in $factoryCopies) {
        Assert-FactoryTarget -Target $copy.Target -InstallRoot $factoryInstallRoot
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($copy.Target)) | Out-Null
        [IO.File]::Copy($copy.Source, $copy.Target, $false)
    }
    Write-Output "Installed $($factoryCopies.Count) files in $factoryDestination"
    if ($Scope -eq 'user') {
        Write-Output 'Open an agent in a project root and invoke $factory in Codex or /factory in Claude or Grok.'
        Write-Output 'The skill handles first-use setup. Settings and jobs stay in that project.'
    }
} catch {
    [Console]::Error.WriteLine("install-factory: $($_.Exception.Message)")
    exit 1
}
