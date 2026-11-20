[CmdletBinding()]
param([string]$Bash, [ValidateSet('openai','claude')][string]$Model = 'openai')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$shell = (Get-Process -Id $PID).Path
if (-not $Bash) {
    $gitBash = if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Git/bin/bash.exe' } else { $null }
    $Bash = if ($gitBash -and (Test-Path -LiteralPath $gitBash)) { $gitBash } else { (Get-Command bash -CommandType Application | Select-Object -First 1).Source }
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('factory-regressions.' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporary) | Out-Null
$oldPath = $env:PATH
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Write-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $script:utf8) }
function Quote([string]$Value) { '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"' }
function Unix-Path([string]$Path) {
    $value = $Path.Replace('\','/')
    if ($value -match '^([A-Za-z]):/(.*)$') { return '/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2] }
    return $value
}
function Run([string]$Program, [string[]]$Arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Program; $info.Arguments = ($Arguments | ForEach-Object { Quote $_ }) -join ' '
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $script:utf8; $info.StandardErrorEncoding = $script:utf8
    $process = New-Object Diagnostics.Process; $process.StartInfo = $info
    try {
        $process.Start() | Out-Null
        $output = $process.StandardOutput.ReadToEndAsync(); $errors = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return @{ Code=$process.ExitCode; Out=$output.Result; Err=$errors.Result }
    } finally { $process.Dispose() }
}
function Good($Result) {
    Assert ($Result.Code -eq 0) ("Command failed with $($Result.Code): $($Result.Out) $($Result.Err)")
    return $Result.Out.Trim()
}
function Native([string]$Action, [string[]]$Options = @()) {
    if ($script:engine -eq 'powershell') {
        return Run $script:shell (@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',"$repo/skills/$Model/factory/scripts/factory.ps1",$Action,'-ProjectPath',$script:project) + $Options)
    }
    $arguments = @()
    for ($i=0; $i -lt $Options.Count; $i+=2) {
        $option = switch ($Options[$i]) {
            -Base {'--base'} -File {'--file'} -Job {'--job'} -Next {'--next'}
            -Role {'--role'} -Executable {'--executable'} -Prompt {'--prompt'}
            default { throw "Unmapped option $($Options[$i])" }
        }
        $value = $Options[$i+1]
        if ($Options[$i] -in @('-File','-Prompt','-Executable')) { $value = Unix-Path $value }
        $arguments += @($option,$value)
    }
    return Run $Bash (@((Unix-Path "$repo/skills/$Model/factory/scripts/factory.sh"),'--project',(Unix-Path $script:project),$Action) + $arguments)
}
function Parse-Json([string]$Json) {
    # PowerShell 5.1 accepts raw controls in JSON strings, but browser JSON.parse rejects them.
    foreach ($literal in [regex]::Matches($Json, '"(?:[^"\\]|\\.)*"')) {
        Assert (-not [regex]::IsMatch($literal.Value, '[\x00-\x1f]')) 'JSON string contains an unescaped control character.'
    }
    return $Json | ConvertFrom-Json
}
function Status { return Parse-Json (Good (Native status @('-Job',$script:job))) }
function Board {
    $html = [IO.File]::ReadAllText((Join-Path $script:project 'factory/dashboard.html'))
    $data = [regex]::Match($html, '(?s)<script id="factory-data" type="application/json">(.*?)</script>').Groups[1].Value
    Assert ($data -ne '') 'Dashboard JSON was not found.'
    Assert (-not $data.Contains('<script>')) 'Dashboard data contains unescaped markup.'
    return Parse-Json $data
}
function Same-Bytes([byte[]]$Actual, [byte[]]$Expected, [string]$Message) {
    Assert ([Convert]::ToBase64String($Actual) -ceq [Convert]::ToBase64String($Expected)) $Message
}
try {
    foreach ($engine in @('powershell','bash')) {
        $project = Join-Path $temporary "$engine project"; $mock = Join-Path $temporary "$engine bin"
        $remote = Join-Path $temporary "$engine remote.git"
        [IO.Directory]::CreateDirectory($project) | Out-Null; [IO.Directory]::CreateDirectory($mock) | Out-Null
        $env:FACTORY_NATIVE_CAPTURE = $mock; $env:FACTORY_FAKE_GH = $mock
        $env:GH_CONFIG_DIR = Join-Path $mock 'github-config'; $env:GH_TOKEN = 'offline-fixture'; $env:GITHUB_TOKEN = 'offline-fixture'
        if ($engine -eq 'powershell' -and $env:OS -eq 'Windows_NT') {
            # Compile a real .exe so PowerShell script argument binding cannot hide the regression.
            $source = [IO.File]::ReadAllText((Join-Path $repo 'tests/fixtures/native-capture.cs'))
            Add-Type -TypeDefinition $source -OutputAssembly (Join-Path $mock 'gh.exe') -OutputType ConsoleApplication
            Copy-Item -LiteralPath (Join-Path $mock 'gh.exe') -Destination (Join-Path $mock 'agent.exe')
            $agent = Join-Path $mock 'agent.exe'
        } else {
            Copy-Item -LiteralPath (Join-Path $repo 'tests/fixtures/gh.ps1') -Destination (Join-Path $mock 'gh.ps1')
            Copy-Item -LiteralPath (Join-Path $repo 'tests/fixtures/agent.ps1') -Destination (Join-Path $mock 'agent.ps1')
            $agent = Join-Path $mock 'agent.ps1'
        }
        Copy-Item -LiteralPath (Join-Path $repo 'tests/fixtures/gh') -Destination (Join-Path $mock 'gh')
        $env:PATH = $mock + [IO.Path]::PathSeparator + $oldPath
        $resolved = Good (Run $shell @('-NoProfile','-NonInteractive','-Command','(Get-Command gh -CommandType Application,ExternalScript | Select-Object -First 1).Source'))
        Assert ((Split-Path -Parent $resolved) -eq $mock) "Uncontrolled GitHub CLI resolved: $resolved"
        $bashResolved = Good (Run $Bash @('-c','selected=$(command -v gh) || exit; if command -v cygpath >/dev/null; then cygpath -w "$selected"; else printf "%s\n" "$selected"; fi'))
        Assert ([IO.Path]::GetFullPath($bashResolved) -eq [IO.Path]::GetFullPath((Join-Path $mock 'gh'))) "Uncontrolled Bash GitHub CLI resolved: $bashResolved"
        Good (Run $Bash @('-c','chmod +x -- "$1"','fixture',(Unix-Path (Join-Path $mock 'gh')))) | Out-Null
        Good (Run git @('init','--bare',$remote)) | Out-Null; Good (Run git @('init','-b','main',$project)) | Out-Null
        Good (Run git @('-C',$project,'config','user.name','Factory fixture')) | Out-Null
        Good (Run git @('-C',$project,'config','user.email','fixture@example.invalid')) | Out-Null
        Good (Run git @('-C',$project,'config','commit.gpgsign','false')) | Out-Null
        Good (Run git @('-C',$project,'config','core.autocrlf','false')) | Out-Null
        Good (Run git @('-C',$project,'config','core.quotePath','true')) | Out-Null
        $trackedName = 'caf' + [char]0xe9 + '[tracked].txt'
        Write-Utf8 (Join-Path $project $trackedName) "before`n"
        Write-Utf8 (Join-Path $project 'app.txt') "before`n"
        Good (Run git @('-C',$project,'--literal-pathspecs','add','--','app.txt',$trackedName)) | Out-Null
        Good (Run git @('-C',$project,'commit','-m','Initial')) | Out-Null
        Good (Run git @('-C',$project,'remote','add','origin',$remote)) | Out-Null
        Good (Run git @('-C',$project,'push','-u','origin','main')) | Out-Null
        Good (Native init @('-Base','main')) | Out-Null
        Write-Utf8 (Join-Path $project 'factory/checks.ps1') 'exit 0'
        Write-Utf8 (Join-Path $project 'factory/checks.sh') "exit 0`n"
        $controls = -join (0..31 | ForEach-Object { [char]$_ })
        $unicode = [string][char]0x4e2d + [char]0x6587 + [char]::ConvertFromUtf32(128512)
        $hostileTitle = 'Review idea"" --repo example/other --head user:branch --base evil --title "final ' + $unicode + '\'
        $placeholders = '__FACTORY_STYLE__ __FACTORY_DATA__ __FACTORY_SCRIPT__'
        $request = $hostileTitle + "`r`n" + $controls + "`n<script>literal</script>`nquotes `" \ `n$placeholders`n`n"
        $inputFile = Join-Path $temporary 'request.md'; Write-Utf8 $inputFile $request
        $job = Good (Native create @('-Base','main','-File',$inputFile))
        $folder = Join-Path $project "factory/jobs/$job"
        $summary = Status; $board = Board
        $actualRequest = $summary.artifacts.'request.md'
        $mismatch = 0
        while ($mismatch -lt [Math]::Min($actualRequest.Length, $request.Length) -and $actualRequest[$mismatch] -ceq $request[$mismatch]) { $mismatch++ }
        Assert ($actualRequest -ceq $request) "$engine summary mismatch at character $mismatch, lengths $($actualRequest.Length) and $($request.Length)."
        Assert ($board.artifacts.'request.md' -ceq $request) "$engine dashboard JSON did not round trip the complete request."
        $blocker = "Need an answer $unicode`n$controls`n`n"
        $blockerInput = Join-Path $temporary 'blocker.md'; Write-Utf8 $blockerInput $blocker
        Good (Native advance @('-Job',$job,'-Next','needs-human','-File',$blockerInput)) | Out-Null
        Assert ((Status).blocker -ceq $blocker) "$engine active blocker lost content."
        Assert ((Board).blocker -ceq $blocker) "$engine board lost active blocker."
        Good (Native feedback @('-Job',$job,'-Next','build','-File',$inputFile)) | Out-Null
        $summary = Status; $board = Board
        Assert ($summary.stage -eq 'build' -and $null -eq $summary.blocker -and $null -eq $board.blocker) "$engine resumed work still has an active blocker."
        $history = @(Get-ChildItem -LiteralPath $folder -Filter 'blocker-resolved-*.md')
        Assert ($history.Count -eq 1) "$engine did not retain resolved blocker history."
        Assert ([IO.File]::ReadAllText($history[0].FullName) -ceq $blocker) "$engine changed blocker history."
        Assert (@(Get-ChildItem -LiteralPath $folder -Filter 'feedback-*.md').Count -eq 1) "$engine did not save feedback."
        # Synthetic delivery evidence stays inside this temporary project. No real job records are used.
        Good (Native prepare @('-Job',$job)) | Out-Null
        $worktree = Join-Path $project ".worktrees/$job"
        $commit = Good (Run git @('-C',$worktree,'rev-parse','HEAD')); $env:FACTORY_NATIVE_COMMIT = $commit
        $prompt = "ROLE: builder`r`nFull prompt $unicode`n$controls`n`n"
        $promptFile = Join-Path $temporary 'prompt.md'; Write-Utf8 $promptFile $prompt
        if ($engine -eq 'powershell') {
            Good (Native dispatch @('-Job',$job,'-Role','builder','-Executable',$agent,'-Prompt',$promptFile)) | Out-Null
            Same-Bytes ([IO.File]::ReadAllBytes((Join-Path $mock 'stdin.bin'))) ($utf8.GetBytes($prompt)) 'Child stdin bytes differ from the complete UTF-8 prompt.'
            Assert ($utf8.GetString([IO.File]::ReadAllBytes((Join-Path $mock 'stdin.bin'))) -ceq $prompt) 'Child Unicode prompt content differs.'
        }
        # Exercise the public build transition with default Git filename quoting enabled.
        $round = Join-Path $folder 'round-1'; [IO.Directory]::CreateDirectory($round) | Out-Null
        $builderReport = "VERDICT: READY`nCOMMIT: $commit`n$placeholders`n"
        Write-Utf8 (Join-Path $round 'builder.md') $builderReport
        Write-Utf8 (Join-Path $round 'builder.exit') '0'
        $untrackedName = $unicode + '[new].txt'
        $contents = @{}; $contents[$trackedName] = "modified $unicode`n"; $contents[$untrackedName] = "untracked $unicode`n"
        if ($env:OS -ne 'Windows_NT') {
            # Windows filesystems reject quotes and newlines in filenames.
            $contents["quoted`"$unicode.txt"] = "quoted`n"
            $contents["line`nbreak $unicode.txt"] = "newline`n"
        }
        foreach ($name in $contents.Keys) { Write-Utf8 (Join-Path $worktree $name) $contents[$name] }
        Good (Native advance @('-Job',$job,'-Next','gate')) | Out-Null
        Assert ((Good (Run git @('-C',$worktree,'status','--porcelain'))) -eq '') "$engine build left unstaged paths."
        foreach ($name in $contents.Keys) {
            $stored = Run git @('-C',$worktree,'show',("HEAD:" + $name))
            Assert ($stored.Code -eq 0 -and $stored.Out -ceq $contents[$name]) "$engine committed filename or content differs."
        }
        $commit = Good (Run git @('-C',$worktree,'rev-parse','HEAD')); $env:FACTORY_NATIVE_COMMIT = $commit
        $expectedReport = $builderReport.Replace(($builderReport -split "`n")[1], "COMMIT: $commit")
        Assert ((Board).artifacts.'round-1/builder.md' -ceq $expectedReport) "$engine dashboard changed literal placeholders in the saved report."
        Write-Output "PASS $Model/$engine literal dashboard placeholders and modified/untracked Unicode build paths."
        if ($env:OS -eq 'Windows_NT') { Write-Output 'SKIP quote/newline filenames: Windows filesystem rejects these names.' }
        $statePath = Join-Path $folder 'job.state'; $state = [IO.File]::ReadAllText($statePath)
        $state = [regex]::Replace($state,'(?m)^stage\t[^\r\n]*','stage' + "`tdeliver")
        $state = [regex]::Replace($state,'(?m)^review_commit\t[^\r\n]*','review_commit' + "`t$commit")
        Write-Utf8 $statePath $state
        $round = Join-Path $folder 'round-1'; [IO.Directory]::CreateDirectory($round) | Out-Null
        Write-Utf8 (Join-Path $folder 'spec-writer.md') "VERDICT: READY`nCOMMIT: $commit`nOffline fixture."
        foreach ($role in @('review-code','approver')) {
            $verdict = if ($role -eq 'approver') { 'APPROVE' } else { 'PASS' }
            Write-Utf8 (Join-Path $round "$role.md") "VERDICT: $verdict`nCOMMIT: $commit`nOffline fixture."
            Write-Utf8 (Join-Path $round "$role.exit") '0'
        }
        if ($engine -eq 'powershell' -and $env:OS -eq 'Windows_NT') {
            $env:FACTORY_NATIVE_FAIL = '1'
            $failed = Native deliver @('-Job',$job)
            Assert ($failed.Code -ne 0 -and $failed.Err.Contains('exited 23') -and $failed.Err.Contains('fixture stdout diagnostic') -and $failed.Err.Contains('fixture stderr diagnostic')) 'Native exit code or diagnostics were lost.'
            Assert (-not (Test-Path -LiteralPath (Join-Path $mock 'created'))) 'Failed preflight created a PR.'
            $env:FACTORY_NATIVE_FAIL = $null
        }
        Good (Native deliver @('-Job',$job)) | Out-Null
        $summary = Status; $board = Board
        Assert ($summary.stage -eq 'ready' -and $null -eq $summary.blocker -and $null -eq $board.blocker) "$engine ready summary still has an active blocker."
        Assert ($summary.artifacts.($history[0].Name) -ceq $blocker -and $board.artifacts.($history[0].Name) -ceq $blocker) "$engine ready history lost the resolved blocker."
        if ($engine -eq 'powershell' -and $env:OS -eq 'Windows_NT') {
            $reader = New-Object IO.BinaryReader([IO.File]::OpenRead((Join-Path $mock 'create.argv')), $utf8)
            try { $count = $reader.ReadInt32(); $actual = @(for ($i=0; $i -lt $count; $i++) { $reader.ReadString() }) } finally { $reader.Dispose() }
            $expected = @('pr','create','--draft','--base','main','--head',"factory/$job",'--title',$hostileTitle,'--body-file',(Join-Path $folder 'pr-body.md'))
            Assert ($count -eq $expected.Count) "Native title injected extra options. Expected $($expected.Count) arguments, got $count."
            for ($i=0; $i -lt $count; $i++) { Assert ($actual[$i] -ceq $expected[$i]) "Native argument $i differs." }
            Assert (Test-Path -LiteralPath (Join-Path $mock 'ready')) 'Native delivery did not mark the fixture PR ready.'
        }
        Write-Output "PASS $engine summary/dashboard control round trips and needs-human -> feedback -> build -> ready history."
    }
    Write-Output "PASS native delivery argument capture, diagnostics, exit handling, and complete Unicode stdin on PowerShell $($PSVersionTable.PSVersion)."
} finally {
    $env:PATH = $oldPath
    $env:FACTORY_NATIVE_CAPTURE = $null; $env:FACTORY_NATIVE_COMMIT = $null; $env:FACTORY_NATIVE_FAIL = $null; $env:FACTORY_FAKE_GH = $null
    # The generated directory is an absolute child of the system temporary directory.
    $resolved = [IO.Path]::GetFullPath($temporary)
    Assert ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'factory-regressions.*') 'Refusing cleanup outside the fixture directory.'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
