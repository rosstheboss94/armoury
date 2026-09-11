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

function Select-Model {
    while ($true) {
        Write-Host ''
        Write-Host 'Select a model:'
        Write-Host '  1. openai'
        Write-Host '  2. claude'
        $choice = Read-Host 'Model number'

        switch ($choice.Trim()) {
            '1' { return 'openai' }
            '2' { return 'claude' }
            default { Write-Warning 'Choose 1 or 2.' }
        }
    }
}

function Get-SkillDirectories {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)

    $directories = @(Get-ChildItem -LiteralPath $SourceRoot -Directory -Force -ErrorAction Stop | Sort-Object Name)
    if ($directories.Count -eq 0) {
        throw "No skills found in: $SourceRoot"
    }

    foreach ($directory in $directories) {
        if (-not (Test-Path -LiteralPath (Join-Path $directory.FullName 'SKILL.md') -PathType Leaf)) {
            throw "Skill is missing SKILL.md: $($directory.FullName)"
        }
    }

    return $directories
}

function Get-CollectionDefinitions {
    param(
        [Parameter(Mandatory = $true)][string]$CollectionRoot,
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo[]]$SkillDirectories
    )

    if (-not (Test-Path -LiteralPath $CollectionRoot -PathType Container)) {
        throw "Collection directory does not exist: $CollectionRoot"
    }

    $skillNames = @($SkillDirectories.Name)
    $collections = @()
    $collectionDirectories = @(Get-ChildItem -LiteralPath $CollectionRoot -Directory -Force -ErrorAction Stop | Sort-Object Name)

    foreach ($collectionDirectory in $collectionDirectories) {
        $manifestPath = Join-Path $collectionDirectory.FullName 'collection.yaml'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Collection is missing collection.yaml: $($collectionDirectory.FullName)"
        }

        $name = $null
        $description = $null
        $members = @()
        $inSkills = $false

        foreach ($line in Get-Content -LiteralPath $manifestPath -ErrorAction Stop) {
            if ($line -match '^name:\s*(.+?)\s*$') {
                $name = $Matches[1].Trim().Trim('"').Trim("'")
                $inSkills = $false
            }
            elseif ($line -match '^description:\s*(.+?)\s*$') {
                $description = $Matches[1].Trim().Trim('"').Trim("'")
                $inSkills = $false
            }
            elseif ($line -match '^skills:\s*$') {
                $inSkills = $true
            }
            elseif ($inSkills -and $line -match '^\s+-\s+([a-z0-9][a-z0-9-]*)\s*$') {
                $members += $Matches[1]
            }
            elseif ($inSkills -and $line -match '^\S') {
                $inSkills = $false
            }
        }

        if (-not $name) {
            throw "Collection manifest is missing a name: $manifestPath"
        }
        if ($name -cne $collectionDirectory.Name) {
            throw "Collection name '$name' must match its directory '$($collectionDirectory.Name)'."
        }
        if (-not $description) {
            throw "Collection manifest is missing a description: $manifestPath"
        }
        if ($members.Count -eq 0) {
            throw "Collection has no skills: $name"
        }
        if (@($members | Sort-Object -Unique).Count -ne $members.Count) {
            throw "Collection contains duplicate skills: $name"
        }

        foreach ($member in $members) {
            if (-not ($skillNames -contains $member)) {
                throw "Collection '$name' references unknown $Model skill: $member"
            }
        }

        $collections += [pscustomobject]@{
            Name = $name
            Description = $description
            Skills = @($members)
        }
    }

    if ($collections.Count -eq 0) {
        throw "No collections found in: $CollectionRoot"
    }

    $collectedNames = @($collections | ForEach-Object { $_.Skills } | Sort-Object -Unique)
    $uncollected = @($skillNames | Where-Object { $_ -notin $collectedNames })
    if ($uncollected.Count -gt 0) {
        throw "Active skills missing from collections: $($uncollected -join ', ')"
    }

    return $collections
}

function Resolve-SkillSelection {
    param(
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo[]]$SkillDirectories,
        [Parameter(Mandatory = $true)][object[]]$Collections,
        [string[]]$Requested
    )

    $tokens = @()
    if ($Requested) {
        $tokens = @($Requested | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    else {
        Write-Host ''
        Write-Host 'Select skills or collections. Enter All or comma-separated numbers.'
        Write-Host '  0. All'
        for ($index = 0; $index -lt $SkillDirectories.Count; $index++) {
            Write-Host ('  {0}. {1}' -f ($index + 1), $SkillDirectories[$index].Name)
        }
        for ($index = 0; $index -lt $Collections.Count; $index++) {
            $number = $SkillDirectories.Count + $index + 1
            Write-Host ('  {0}. collection:{1} - {2}' -f $number, $Collections[$index].Name, $Collections[$index].Description)
        }
        $tokens = @((Read-Host 'Selection') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    if ($tokens.Count -eq 0) {
        throw 'At least one skill must be selected.'
    }

    if ($tokens -contains '0' -or ($tokens | Where-Object { $_ -ieq 'all' })) {
        return @($SkillDirectories)
    }

    $selected = @()
    foreach ($token in $tokens) {
        $candidateNames = @()
        $number = 0
        if ([int]::TryParse($token, [ref]$number)) {
            $maximum = $SkillDirectories.Count + $Collections.Count
            if ($number -lt 1 -or $number -gt $maximum) {
                throw "Selection number is out of range: $token"
            }
            if ($number -le $SkillDirectories.Count) {
                $candidateNames = @($SkillDirectories[$number - 1].Name)
            }
            else {
                $collectionIndex = $number - $SkillDirectories.Count - 1
                $candidateNames = @($Collections[$collectionIndex].Skills)
            }
        }
        elseif ($token -match '^collection:(.+)$') {
            $collectionName = $Matches[1].Trim()
            $collection = $Collections | Where-Object { $_.Name -ieq $collectionName } | Select-Object -First 1
            if (-not $collection) {
                throw "Unknown collection: $collectionName"
            }
            $candidateNames = @($collection.Skills)
        }
        else {
            $candidate = $SkillDirectories | Where-Object { $_.Name -ieq $token } | Select-Object -First 1
            if (-not $candidate) {
                throw "Unknown skill: $token"
            }
            $candidateNames = @($candidate.Name)
        }

        foreach ($candidateName in $candidateNames) {
            $candidate = $SkillDirectories | Where-Object { $_.Name -ieq $candidateName } | Select-Object -First 1
            if (-not ($selected.Name -contains $candidate.Name)) {
                $selected += $candidate
            }
        }
    }

    return $selected
}

function Resolve-Project {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        $project = Get-Item -LiteralPath $RequestedPath -ErrorAction Stop
        if (-not $project.PSIsContainer) {
            throw "Project path is not a directory: $RequestedPath"
        }
        return $project
    }

    while ($true) {
        $path = Read-Host 'Project root'
        if (-not $path) {
            Write-Warning 'Project root is required.'
            continue
        }

        try {
            $project = Get-Item -LiteralPath $path -ErrorAction Stop
            if (-not $project.PSIsContainer) {
                Write-Warning 'That path is not a directory.'
                continue
            }
            return $project
        }
        catch {
            Write-Warning "Project directory does not exist: $path"
        }
    }
}

$interactive = -not ($PSBoundParameters.ContainsKey('Model') -and
    $PSBoundParameters.ContainsKey('Skills') -and
    $PSBoundParameters.ContainsKey('ProjectPath'))

if (-not $Model) {
    $Model = Select-Model
}
$Model = $Model.ToLowerInvariant()

$scriptDirectory = $PSScriptRoot
$repositoryRoot = Split-Path -Parent $scriptDirectory
$sourceRoot = Join-Path $repositoryRoot "skills\$Model"
$collectionRoot = Join-Path $repositoryRoot 'collections'
$skillDirectories = @(Get-SkillDirectories -SourceRoot $sourceRoot)
$collections = @(Get-CollectionDefinitions -CollectionRoot $collectionRoot -SkillDirectories $skillDirectories)
$selectedSkills = @(Resolve-SkillSelection -SkillDirectories $skillDirectories -Collections $collections -Requested $Skills)
$project = Resolve-Project -RequestedPath $ProjectPath

if ($Model -eq 'openai') {
    $destinationRoot = Join-Path $project.FullName '.agents\skills'
}
else {
    $destinationRoot = Join-Path $project.FullName '.claude\skills'
}

Write-Host ''
Write-Host 'Install summary:'
Write-Host "  Model: $Model"
Write-Host "  Project: $($project.FullName)"
Write-Host "  Skills: $($selectedSkills.Name -join ', ')"

if ($interactive) {
    $confirmation = Read-Host 'Copy these skills? [Y/n]'
    if ($confirmation -match '^(n|no)$') {
        Write-Output 'Cancelled.'
        return
    }
}

New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
foreach ($skillDirectory in $selectedSkills) {
    $targetDirectory = Join-Path $destinationRoot $skillDirectory.Name
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    Get-ChildItem -LiteralPath $skillDirectory.FullName -Force |
        Copy-Item -Destination $targetDirectory -Recurse -Force
    Write-Output "Installed $($skillDirectory.Name) -> $targetDirectory"
}
