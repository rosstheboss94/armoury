[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('add','init','create','status','queue','prepare','dispatch','accept','gate','advance','feedback','deliver','dashboard','skills')]
    [string]$Action,
    [Alias('Project')][string]$ProjectPath = '.',
    [string]$Job,
    [ValidateSet('codex','claude','grok')][string]$Runner = 'codex',
    [string]$Model = '', [string]$Reasoning = '', [string]$Executable = '',
    [string]$Base = '', [string]$Next = '', [string]$Role = '',
    [string]$File = '', [string]$Prompt = '', [string]$Label = 'factory',
    [ValidateRange(1,100)][int]$Limit = 3,
    [ValidateRange(1,100)][int]$Concurrency = 3,
    [ValidateRange(1,86400)][int]$TimeoutSeconds = 1800
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$package = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding($false)
$previousOutputEncoding = [Console]::OutputEncoding
$locks = New-Object 'System.Collections.Generic.List[string]'

function Native([string]$Program, [string[]]$Arguments, [string]$Directory, [switch]$AllowFailure, [switch]$RawOutput) {
    Push-Location -LiteralPath $Directory
    try {
        $ErrorActionPreference = 'Continue'
        $resolvedProgram = (Get-Command $Program -CommandType Application,ExternalScript -ErrorAction Stop | Select-Object -First 1).Source
        if ([IO.Path]::GetExtension($resolvedProgram) -eq '.ps1') {
            $text = (& $resolvedProgram @Arguments 2>&1 | Out-String).TrimEnd()
            $code = $LASTEXITCODE
        } else {
            # Encode each argument explicitly. Windows PowerShell's native binder can split quoted titles.
            $info = New-Object Diagnostics.ProcessStartInfo
            $info.FileName = $resolvedProgram
            $info.Arguments = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
            $info.WorkingDirectory = $Directory; $info.UseShellExecute = $false; $info.CreateNoWindow = $true
            $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
            $info.StandardOutputEncoding = $script:utf8; $info.StandardErrorEncoding = $script:utf8
            $process = New-Object Diagnostics.Process; $process.StartInfo = $info
            try {
                $process.Start() | Out-Null
                $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync()
                $process.WaitForExit()
                $text = if ($RawOutput) { $outTask.Result } else { ($outTask.Result + $errTask.Result).TrimEnd() }
                $code = $process.ExitCode
            } finally { $process.Dispose() }
        }
        if ($code -ne 0 -and -not $AllowFailure) { throw "$Program exited $code. $text" }
        return @{ Text = $text; Code = $code }
    } finally { Pop-Location }
}
function Invoke-FactoryGit([string[]]$Arguments, [string]$Directory = $script:project) { (Native 'git' $Arguments $Directory).Text }
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $script:utf8) }
function Lock-Directory([string]$Path) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $acquired = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        try { New-Item -ItemType Directory -Path $Path -ErrorAction Stop | Out-Null; $acquired = $true; break }
        catch { Start-Sleep -Milliseconds 50 }
    }
    if (-not $acquired) { throw "Another operation owns $Path. Inspect its owner before recovery." }
    $script:locks.Add($Path)
    Write-Text (Join-Path $Path 'owner') "shell=powershell`npid=$PID`n"
}
function Load-Job {
    if ($script:Job -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') { throw 'Invalid job identifier.' }
    $script:folder = Join-Path $script:jobs $script:Job
    foreach ($path in @($script:jobs, $script:folder)) {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Job path is linked outside its project.' }
    }
    $script:state = [ordered]@{}
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $script:folder 'job.state'))) {
        $pair = $line -split "`t", 2
        if ($pair.Count -ne 2 -or $pair[0] -notmatch '^[a-z_]+$') { throw 'Invalid state record.' }
        $script:state[$pair[0]] = $pair[1]
    }
    if ($script:state.id -ne $script:Job -or $script:state.worktree -ne ".worktrees/$($script:Job)") { throw 'Job belongs to a different project.' }
    $script:worktree = Join-Path $script:project $script:state.worktree
    $script:roundFolder = Join-Path $script:folder "round-$($script:state.round)"
}
function Summary {
    $value = [ordered]@{}
    foreach ($key in $script:state.Keys) { $value[$key] = $script:state[$key] }
    $blocker = Join-Path $script:folder 'blocker.md'
    $value.blocker = if ($script:state.stage -in @('needs-human','needs-info') -and (Test-Path -LiteralPath $blocker)) { [IO.File]::ReadAllText($blocker) } else { $null }
    $value.artifacts = [ordered]@{}
    foreach ($report in Get-ChildItem -LiteralPath $script:folder -Filter '*.md' -Recurse) {
        $relative = $report.FullName.Substring($script:folder.Length + 1).Replace('\','/')
        if (($relative -split '/').Count -gt 2 -or ($report.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        $value.artifacts[$relative] = [IO.File]::ReadAllText($report.FullName)
    }
    return $value
}
function Atomic-Text([string]$Path, [string]$Text) {
    $temporary = "$Path.$([guid]::NewGuid().ToString('N'))"
    Write-Text $temporary $Text
    try {
        for ($attempt = 0; ; $attempt++) {
            try {
                if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
                else { [IO.File]::Move($temporary, $Path) }
                break
            } catch { if ($attempt -ge 39) { throw }; Start-Sleep -Milliseconds 50 }
        }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Dashboard {
    $savedJob = $script:Job
    $rows = New-Object 'System.Collections.Generic.List[object]'
    if (Test-Path -LiteralPath $script:jobs) {
        foreach ($directory in Get-ChildItem -LiteralPath $script:jobs -Directory) {
            if (-not (Test-Path -LiteralPath (Join-Path $directory.FullName 'job.state'))) { continue }
            $script:Job = $directory.Name; Load-Job; $rows.Add((Summary))
        }
    }
    $data = ConvertTo-Json -InputObject @($rows.ToArray()) -Depth 12 -Compress
    $data = $data.Replace('<','\u003c')
    $html = [IO.File]::ReadAllText((Join-Path $script:package 'assets/dashboard.html'))
    $values = @{
        '__FACTORY_STYLE__' = [IO.File]::ReadAllText((Join-Path $script:package 'assets/dashboard.css'))
        '__FACTORY_DATA__' = $data
        '__FACTORY_SCRIPT__' = [IO.File]::ReadAllText((Join-Path $script:package 'assets/dashboard.js'))
    }
    # Match only the template. Inserted reports and assets remain literal data.
    $html = [regex]::Replace($html, '__FACTORY_(STYLE|DATA|SCRIPT)__', [Text.RegularExpressions.MatchEvaluator]{ param($match) $values[$match.Value] })
    Atomic-Text (Join-Path $script:factory 'dashboard.html') $html
    $script:Job = $savedJob
    if ($savedJob) { Load-Job }
}
function Get-StopStage {
    $found = ''
    $path = Join-Path $script:folder 'history.tsv'
    if (-not (Test-Path -LiteralPath $path)) { throw 'This stop has no recorded entry.' }
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $parts = $line -split "`t"
        if ($parts.Count -ge 3 -and $parts[2] -eq 'needs-human' -and $parts[1] -ne 'needs-human') { $found = $parts[1] }
    }
    if (-not $found) { throw 'This stop has no recorded entry.' }
    return $found
}
function Test-BudgetBlocker {
    $path = Join-Path $script:folder 'blocker.md'
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $text = [IO.File]::ReadAllText($path).TrimEnd("`r", "`n")
    return $text -eq 'Build round budget exhausted. Create a successor job.'
}
function Save-Job {
    $lines = foreach ($key in $script:state.Keys) {
        if ([string]$script:state[$key] -match "[`t`r`n]") { throw 'State values cannot contain tabs or newlines.' }
        "$key`t$($script:state[$key])"
    }
    Atomic-Text (Join-Path $script:folder 'job.state') (($lines -join "`n") + "`n")
    Atomic-Text (Join-Path $script:folder 'job.json') ((Summary) | ConvertTo-Json -Depth 12)
    Dashboard
}
function Head-Commit { Invoke-FactoryGit @('rev-parse','HEAD') $script:worktree }
function Report-Path {
    if ($script:Role -in @('intake','spec-writer')) { return Join-Path $script:folder "$($script:Role).md" }
    return Join-Path $script:roundFolder "$($script:Role).md"
}
function Proof([string]$Path, [string]$Verdict, [string]$Commit = '') {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $exitPath = Join-Path $script:roundFolder ([IO.Path]::GetFileNameWithoutExtension($Path) + '.exit')
    if (-not (Test-Path -LiteralPath $exitPath) -or [IO.File]::ReadAllText($exitPath).Trim() -ne '0') { return $false }
    $lines = [IO.File]::ReadAllLines($Path)
    return $lines.Count -ge 2 -and $lines[0] -eq "VERDICT: $Verdict" -and (-not $Commit -or $lines[1] -eq "COMMIT: $Commit")
}
function Prepare {
    if (Test-Path -LiteralPath $script:worktree) {
        if ((Invoke-FactoryGit @('branch','--show-current') $script:worktree) -ne $script:state.branch) { throw 'The worktree is on an unexpected branch.' }
        return
    }
    Lock-Directory (Join-Path $script:factory '.workspace.lock')
    Invoke-FactoryGit @('fetch','origin',$script:state.base) | Out-Null
    $script:state.base_commit = Invoke-FactoryGit @('rev-parse',"origin/$($script:state.base)")
    [IO.Directory]::CreateDirectory((Join-Path $script:project '.worktrees')) | Out-Null
    $exists = Native 'git' @('show-ref','--verify','--quiet',"refs/heads/$($script:state.branch)") $script:project -AllowFailure
    if ($exists.Code -eq 0) { Invoke-FactoryGit @('worktree','add',$script:worktree,$script:state.branch) | Out-Null }
    else { Invoke-FactoryGit @('worktree','add','-b',$script:state.branch,$script:worktree,$script:state.base_commit) | Out-Null }
}
function Quote-Argument([string]$Value) {
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
function Stop-OwnedProcess($Process) {
    if ($Process.HasExited) { return }
    if ($env:OS -eq 'Windows_NT') { & taskkill /PID $Process.Id /T /F 2>&1 | Out-Null }
    else { try { $Process.Kill($true) } catch { $Process.Kill() } }
    $Process.WaitForExit()
}
function Run-Check {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Process -Id $PID).Path
    $info.Arguments = (@('-NoProfile','-NonInteractive','-File',(Join-Path $script:folder 'checks.ps1')) | ForEach-Object { Quote-Argument $_ }) -join ' '
    $info.WorkingDirectory = $script:worktree; $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process; $process.StartInfo = $info; $process.Start() | Out-Null
    $marker = Join-Path (Join-Path $script:folder '.state.lock') 'child'; Write-Text $marker ([string]$process.Id)
    $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($script:TimeoutSeconds * 1000)) { Stop-OwnedProcess $process; $code = 124 }
    else { $code = $process.ExitCode }
    Write-Text (Join-Path $script:roundFolder 'checks.log') ($outTask.Result + $errTask.Result)
    [IO.File]::Delete($marker)
    return $code
}

try {
    [Console]::OutputEncoding = $utf8
    if ($Action -eq 'add' -and -not (Get-Command git -CommandType Application,ExternalScript -ErrorAction SilentlyContinue)) { throw 'Install Git and run add from a Git project.' }
    $project = (Native 'git' @('rev-parse','--show-toplevel') $ProjectPath).Text
    $project = [IO.Path]::GetFullPath($project)
    $factory = Join-Path $project 'factory'; $jobs = Join-Path $factory 'jobs'
    if ($Role -and $Role -notin @('intake','spec-writer','builder','review-code','review-security','review-ux','review-ui','approver')) { throw 'Unknown role.' }
    switch ($Action) {
        add {
            & (Join-Path $PSScriptRoot 'add-issue.ps1') -ProjectPath $project -File $File -Label $Label
            exit $LASTEXITCODE
        }
        init {
            [IO.Directory]::CreateDirectory($factory) | Out-Null; Lock-Directory (Join-Path $factory '.config.lock')
            $configPath = Join-Path $factory 'config.json'
            if (-not (Test-Path -LiteralPath $configPath)) {
                if (-not $Base) { $Base = (Native 'git' @('symbolic-ref','--short','refs/remotes/origin/HEAD') $project -AllowFailure).Text -replace '^origin/','' }
                if (-not $Base) { $Base = (Native 'gh' @('repo','view','--json','defaultBranchRef','--template','{{.defaultBranchRef.name}}') $project).Text }
                Invoke-FactoryGit @('check-ref-format',"refs/heads/$Base") | Out-Null
                $config = [ordered]@{ version=2; base_branch=$Base; concurrency=3; max_rounds=3; default=@{runner=$Runner; model=$null; timeout_seconds=1800}; roles=@{}; skills=@{roots=@(); include=@(); exclude=@()} }
                Write-Text $configPath ($config | ConvertTo-Json -Depth 8)
            }
            $ignore = Join-Path $project '.gitignore'
            $text = if (Test-Path -LiteralPath $ignore) { [IO.File]::ReadAllText($ignore) } else { '' }
            foreach ($line in @('/factory/jobs/','/factory/.*.lock/','/factory/dashboard.html','/factory/dashboard-data.*','/factory/dashboard.*','/.worktrees/')) {
                if (($text -split '\r?\n') -notcontains $line) { $text += "`n$line`n" }
            }
            Write-Text $ignore $text; Write-Output $configPath
        }
        queue { (Native 'gh' @('api','-X','GET','--paginate','--slurp','repos/{owner}/{repo}/issues','-f','state=open','-f','per_page=100','-f',"labels=$Label") $project).Text }
        skills {
            foreach ($root in @($project, [Environment]::GetFolderPath('UserProfile'))) {
                foreach ($vendor in @('.agents','.claude','.grok')) {
                    $rootPath = Join-Path (Join-Path $root $vendor) 'skills'
                    if (Test-Path -LiteralPath $rootPath) { Get-ChildItem -LiteralPath $rootPath -Directory | ForEach-Object { $entry = Join-Path $_.FullName 'SKILL.md'; if (Test-Path -LiteralPath $entry) { Write-Output $entry } } }
                }
            }
        }
        create {
            if (-not (Test-Path -LiteralPath $File) -or -not (Test-Path -LiteralPath (Join-Path $factory 'config.json')) -or -not (Test-Path -LiteralPath (Join-Path $factory 'checks.ps1'))) { throw 'Initialize the project and configure checks.ps1 before creating jobs.' }
            Lock-Directory (Join-Path $factory '.queue.lock')
            $busy = 0
            if (Test-Path -LiteralPath $jobs) {
                foreach ($existing in Get-ChildItem -LiteralPath $jobs -Directory) {
                    $path = Join-Path $existing.FullName 'job.state'
                    if (-not (Test-Path -LiteralPath $path)) { continue }
                    $stage = ([IO.File]::ReadAllLines($path) | Where-Object { $_ -match '^stage\t' }) -replace '^stage\t',''
                    if ($stage -notin @('ready','merged','rejected','needs-info','needs-human')) { $busy++ }
                }
            }
            if ($busy -ge $Concurrency) { throw 'Concurrency limit reached.' }
            if (-not $Base) { throw 'Pass the base branch from project config.' }
            $Job = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,10)
            $folder = Join-Path $jobs $Job; [IO.Directory]::CreateDirectory($folder) | Out-Null
            $state = [ordered]@{id=$Job;stage='intake';round=0;limit=$Limit;runner=$Runner;base=$Base;branch="factory/$Job";base_commit='';worktree=".worktrees/$Job";reviewers='review-code';review_commit='';pr_url=''}
            Copy-Item -LiteralPath $File -Destination (Join-Path $folder 'request.md')
            Copy-Item -LiteralPath (Join-Path $factory 'config.json') -Destination (Join-Path $folder 'config.json')
            foreach ($name in @('checks.ps1','checks.sh')) { $source = Join-Path $factory $name; if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $folder $name) } }
            Save-Job; Write-Output $Job
        }
        status {
            if ($Job) { Load-Job; [IO.File]::ReadAllText((Join-Path $folder 'job.json')) }
            elseif (Test-Path -LiteralPath $jobs) { Get-ChildItem -LiteralPath $jobs -Directory | ForEach-Object { $path = Join-Path $_.FullName 'job.json'; if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } } }
        }
        dashboard { [IO.Directory]::CreateDirectory($factory) | Out-Null; Dashboard; Write-Output (Join-Path $factory 'dashboard.html') }
        default {
            Load-Job
            $lockName = if ($Action -eq 'dispatch') { ".dispatch-$Role.lock" } else { '.state.lock' }
            Lock-Directory (Join-Path $folder $lockName)
            switch ($Action) {
                prepare { Prepare; Save-Job }
                dispatch {
                    if ($state.stage -eq 'needs-human') {
                        if (Test-BudgetBlocker) { throw 'Build round budget exhausted. Create a successor job.' }
                        $entered = Get-StopStage
                        $matches = $false
                        switch ($entered) {
                            'spec' { $matches = $Role -eq 'spec-writer' }
                            'build' { $matches = $Role -eq 'builder' }
                            'approve' { $matches = $Role -eq 'approver' }
                            'review' { $matches = ($state.reviewers -split ' ') -contains $Role }
                        }
                        if (-not $matches) { throw 'Role does not match the stopped stage.' }
                        if (-not (Test-Path -LiteralPath $Prompt)) { throw 'Dispatch needs a current role and prepared prompt file.' }
                        $recorded = @()
                        if ($state.Contains('retry') -and $state['retry']) { $recorded = @(([string]$state['retry']) -split ' ' | Where-Object { $_ }) }
                        if ($recorded -contains $Role) { throw 'This role was already dispatched for this stop.' }
                        $state['retry'] = (($recorded + $Role) -join ' ')
                        Save-Job
                    } else {
                        $valid = "$($state.stage):$Role" -in @('intake:intake','spec:spec-writer','build:builder','approve:approver')
                        if ($state.stage -eq 'review' -and (($state.reviewers -split ' ') -contains $Role)) { $valid = $true }
                        if (-not $valid -or -not (Test-Path -LiteralPath $Prompt)) { throw 'Dispatch needs a current role and prepared prompt file.' }
                    }
                    if (-not $Executable) { $Executable = $Runner }
                    $resolved = (Get-Command $Executable -ErrorAction Stop | Select-Object -First 1).Source
                    $output = Join-Path $folder ('attempts/' + [guid]::NewGuid().ToString('N'))
                    [IO.Directory]::CreateDirectory($output) | Out-Null
                    Copy-Item -LiteralPath $Prompt -Destination (Join-Path $output 'prompt.md')
                    $cwd = if (Test-Path -LiteralPath $worktree) { $worktree } else { $project }
                    $writable = $Role -eq 'builder'
                    switch ($Runner) {
                        codex { $sandbox = if ($writable) {'workspace-write'} else {'read-only'}; $arguments = @('-a','never','exec','--json','--sandbox',$sandbox,'--cd',$cwd); if ($Reasoning) { $arguments += @('-c',"model_reasoning_effort=`"$Reasoning`"") } }
                        claude { $mode = if ($writable) {'auto'} else {'dontAsk'}; $tools = if ($writable) {'Read,Grep,Glob,Edit,Write,Bash'} else {'Read,Grep,Glob'}; $arguments = @('-p','--output-format','json','--permission-mode',$mode,'--tools',$tools); if ($Reasoning) { $arguments += @('--effort',$Reasoning) } }
                        grok { $mode = if ($writable) {'auto'} else {'dontAsk'}; $arguments = @('--prompt-file',(Join-Path $output 'prompt.md'),'--output-format','json','--cwd',$cwd,'--permission-mode',$mode,'--no-subagents'); if (-not $writable) { $arguments += @('--tools','read_file,grep,list_dir','--deny','MCPTool') }; if ($Reasoning) { $arguments += @('--reasoning-effort',$Reasoning) } }
                    }
                    if ($Model) { $arguments += @('--model',$Model) }; if ($Runner -eq 'codex') { $arguments += '-' }
                    $before = (Invoke-FactoryGit @('rev-parse','HEAD') $cwd) + (Invoke-FactoryGit @('status','--porcelain') $cwd) + (Invoke-FactoryGit @('diff') $cwd) + (Invoke-FactoryGit @('diff','--cached') $cwd)
                    if ([IO.Path]::GetExtension($resolved) -eq '.ps1') {
                        $argumentFile = Join-Path $output 'arguments.json'
                        Write-Text $argumentFile (ConvertTo-Json -InputObject @($arguments) -Compress)
                        $arguments = @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'invoke-script.ps1'),'-ScriptPath',$resolved,'-ArgumentsFile',$argumentFile)
                        $resolved = (Get-Process -Id $PID).Path
                    }
                    $info = New-Object Diagnostics.ProcessStartInfo
                    $info.FileName = $resolved; $info.Arguments = (($arguments | ForEach-Object { Quote-Argument $_ }) -join ' ')
                    Write-Text (Join-Path $output 'command.txt') ($resolved + "`n" + $info.Arguments)
                    $info.WorkingDirectory = $cwd; $info.UseShellExecute = $false; $info.CreateNoWindow = $true
                    $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
                    [IO.Directory]::CreateDirectory($roundFolder) | Out-Null
                    Write-Text (Join-Path $roundFolder "$Role.exit") 'PENDING'
                    $process = New-Object Diagnostics.Process; $process.StartInfo = $info; $process.Start() | Out-Null
                    Write-Text (Join-Path (Join-Path $folder $lockName) 'child') ([string]$process.Id)
                    $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync()
                    $clock = [Diagnostics.Stopwatch]::StartNew()
                    $code = 0
                    if ($Runner -ne 'grok') {
                        try {
                            # Write UTF-8 bytes without relying on the console code page or a StreamWriter default.
                            $promptBytes = $utf8.GetBytes([IO.File]::ReadAllText($Prompt))
                            $inputTask = $process.StandardInput.BaseStream.WriteAsync($promptBytes, 0, $promptBytes.Length)
                            if (-not $inputTask.Wait($TimeoutSeconds * 1000)) { $code = 124; Stop-OwnedProcess $process }
                        } catch { Stop-OwnedProcess $process; $code = 1 }
                    }
                    try { $process.StandardInput.Close() } catch { }
                    $remaining = [Math]::Max(1, $TimeoutSeconds * 1000 - [int]$clock.ElapsedMilliseconds)
                    if ($code -eq 0 -and -not $process.WaitForExit($remaining)) { Stop-OwnedProcess $process; $code = 124 }
                    elseif ($code -eq 0) { $code = $process.ExitCode }
                    Write-Text (Join-Path $output 'stdout.log') $outTask.Result; Write-Text (Join-Path $output 'stderr.log') $errTask.Result
                    $after = (Invoke-FactoryGit @('rev-parse','HEAD') $cwd) + (Invoke-FactoryGit @('status','--porcelain') $cwd) + (Invoke-FactoryGit @('diff') $cwd) + (Invoke-FactoryGit @('diff','--cached') $cwd)
                    if (-not $writable -and $before -ne $after) { $code = 1; [IO.File]::AppendAllText((Join-Path $output 'stderr.log'), 'Read-only role changed the checkout.') }
                    [IO.File]::Delete((Join-Path (Join-Path $folder $lockName) 'child'))
                    [IO.Directory]::CreateDirectory($roundFolder) | Out-Null
                    Write-Text (Join-Path $roundFolder "$Role.exit") ([string]$code)
                    Write-Text (Join-Path $output 'exit.code') ([string]$code)
                    Write-Text (Join-Path $roundFolder "$Role.commit") (Invoke-FactoryGit @('rev-parse','HEAD') $cwd)
                    Write-Text (Join-Path $roundFolder "$Role.model") "$Role`t$Runner`t$Model`n"
                    Write-Text (Join-Path $output 'model.tsv') "$Role`t$Runner`t$Model`n"
                    Write-Output $output
                    if ($code -ne 0) { throw "Runner failed or timed out, exit $code. Inspect $output" }
                }
                accept {
                    $exitPath = Join-Path $roundFolder "$Role.exit"
                    if (-not (Test-Path -LiteralPath $File) -or -not (Test-Path -LiteralPath $exitPath) -or [IO.File]::ReadAllText($exitPath).Trim() -ne '0') { throw 'A successful dispatch and a report file are required.' }
                    $expectedCommit = if (Test-Path -LiteralPath $worktree) { Head-Commit } else { Invoke-FactoryGit @('rev-parse','HEAD') }
                    if ([IO.File]::ReadAllText((Join-Path $roundFolder "$Role.commit")).Trim() -ne $expectedCommit) { throw 'The dispatched commit changed before acceptance.' }
                    $lines = [IO.File]::ReadAllLines($File); $verdict = $lines[0]
                    $allowed = switch ($Role) { intake {@('ACCEPT','NEEDS_INFO','REJECT')} {$_ -in @('builder','spec-writer')} {@('READY','BLOCKED')} approver {@('APPROVE','ESCALATE')} default {@('PASS','CHANGES','BLOCKED')} }
                    if ($verdict -notin @($allowed | ForEach-Object { "VERDICT: $_" })) { throw 'Invalid role verdict.' }
                    $commit = if (Test-Path -LiteralPath $worktree) { Head-Commit } else { Invoke-FactoryGit @('rev-parse','HEAD') }
                    $target = Report-Path; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
                    if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination "$target.before-$([guid]::NewGuid().ToString('N'))" }
                    $body = if ($lines.Count -gt 1) { $lines[1..($lines.Count-1)] -join "`n" } else { '' }
                    Atomic-Text $target "$verdict`nCOMMIT: $commit`n$body`n"; Save-Job
                }
                gate {
                    if ($state.stage -ne 'gate' -or (Invoke-FactoryGit @('status','--porcelain') $worktree)) { throw 'Checks require the clean gate-stage worktree.' }
                    $commit = Head-Commit; $code = Run-Check
                    if ((Invoke-FactoryGit @('status','--porcelain') $worktree) -or (Head-Commit) -ne $commit) { $code = 1 }
                    $paths = Invoke-FactoryGit @('diff','--name-only',$state.base_commit,'HEAD') $worktree
                    if ($paths -match '(?m)^(factory/(config\.json|checks\.)|\.(agents|claude|grok)/skills/factory[^/]*/)') { $code = 1 }
                    $verdict = if ($code -eq 0) { 'PASS' } else { 'FAIL' }
                    Write-Text (Join-Path $roundFolder 'checks.md') "GATE: $verdict`nCOMMIT: $commit`n`nCheck exit: $code. See checks.log.`n"
                    if ($verdict -eq 'PASS') {
                        $state.review_commit = $commit; $state.reviewers = 'review-code'
                        $areas = [IO.File]::ReadAllText((Join-Path $folder 'intake.md')) + "`n" + $paths
                        if ($areas -match 'security|auth|payment|webhook|permission|secret|token|session') { $state.reviewers += ' review-security' }
                        if ($areas -match 'AREAS:.*ui|\.(tsx|jsx|vue|svelte|html|css|scss)') { $state.reviewers += ' review-ux review-ui' }
                    }
                    Save-Job; Write-Output "GATE: $verdict"
                }
                advance {
                    $from = $state.stage
                    $logical = $from
                    if ($from -eq 'needs-human' -and $Next -ne 'needs-human') {
                        $logical = Get-StopStage
                        $state['retry'] = ''
                    }
                    if ($Next -eq 'needs-human') { if (Test-Path -LiteralPath $File) { Copy-Item -LiteralPath $File -Destination (Join-Path $folder 'blocker.md') -Force } }
                    else {
                        switch ("${logical}:$Next") {
                            'intake:spec' { if (-not (Proof (Join-Path $folder 'intake.md') 'ACCEPT')) { throw 'Intake has not accepted this job.' }; Prepare }
                            'intake:needs-info' { if (-not (Proof (Join-Path $folder 'intake.md') 'NEEDS_INFO')) { throw 'Intake has not requested information.' } }
                            'intake:rejected' { if (-not (Proof (Join-Path $folder 'intake.md') 'REJECT')) { throw 'Intake has not rejected this job.' } }
                            'spec:build' { if (-not (Proof (Join-Path $folder 'spec-writer.md') 'READY')) { throw 'Specification is not ready.' }; $state.round = 1 }
                            'build:gate' {
                                if (-not (Proof (Join-Path $roundFolder 'builder.md') 'READY')) { throw 'Builder is not ready.' }
                                $changed = Native 'git' @('diff','--name-only','-z','--no-renames','HEAD') $worktree -RawOutput
                                $untracked = Native 'git' @('ls-files','--others','--exclude-standard','-z') $worktree -RawOutput
                                $paths = @(($changed.Text + $untracked.Text) -split "`0" | Where-Object { $_.Length -gt 0 })
                                if ($paths.Count) { Invoke-FactoryGit (@('--literal-pathspecs','add','--') + $paths) $worktree | Out-Null }
                                if ((Invoke-FactoryGit @('diff','--cached','--name-only') $worktree)) { Invoke-FactoryGit @('commit','-m',"Factory $Job round $($state.round)") $worktree | Out-Null }
                                if ((Invoke-FactoryGit @('status','--porcelain') $worktree)) { throw 'Build left uncommitted files.' }
                                $report = Join-Path $roundFolder 'builder.md'; $text = [IO.File]::ReadAllText($report) -replace '(?m)^COMMIT:.*',("COMMIT: " + (Head-Commit)); Write-Text $report $text
                            }
                            'gate:review' { $text = [IO.File]::ReadAllText((Join-Path $roundFolder 'checks.md')); if ($text -notmatch '^GATE: PASS' -or $state.review_commit -ne (Head-Commit)) { throw 'Current checks have not passed.' } }
                            'review:approve' { if ($state.review_commit -ne (Head-Commit)) { throw 'Reviewed commit changed.' }; foreach ($required in ($state.reviewers -split ' ')) { if (-not (Proof (Join-Path $roundFolder "$required.md") 'PASS' (Head-Commit))) { throw "Missing current PASS from $required" } } }
                            'approve:deliver' { if ($state.review_commit -ne (Head-Commit) -or -not (Proof (Join-Path $roundFolder 'approver.md') 'APPROVE' (Head-Commit))) { throw 'Current approval is missing.' } }
                            {$_ -in @('gate:build','review:build')} { if ([int]$state.round -ge [int]$state.limit) { $Next = 'needs-human'; Write-Text (Join-Path $folder 'blocker.md') 'Build round budget exhausted. Create a successor job.' } else { $state.round = [int]$state.round + 1 } }
                            default { throw "Illegal transition: $from -> $Next" }
                        }
                    }
                    [IO.File]::AppendAllText((Join-Path $folder 'history.tsv'), "$([DateTime]::UtcNow.ToString('o'))`t$from`t$Next`n", $utf8)
                    $state.stage = $Next; Save-Job
                }
                feedback {
                    if (-not (Test-Path -LiteralPath $File)) { throw 'Feedback file is required.' }
                    if ($state.stage -eq 'needs-info') { $Next = 'intake' }
                    elseif ($state.stage -in @('needs-human','ready')) { if (-not $Next) { $Next = 'build' } }
                    else { throw 'The job is not waiting for feedback.' }
                    if ($Next -notin @('intake','spec','build','gate','review','approve','deliver')) { throw 'Invalid recovery stage.' }
                    if ($Next -eq 'build') { if ([int]$state.round -ge [int]$state.limit) { throw 'Build budget is exhausted.' }; $state.round = [int]$state.round + 1 }
                    Copy-Item -LiteralPath $File -Destination (Join-Path $folder "feedback-$([guid]::NewGuid().ToString('N')).md")
                    $blocker = Join-Path $folder 'blocker.md'
                    if (Test-Path -LiteralPath $blocker) { Move-Item -LiteralPath $blocker -Destination (Join-Path $folder "blocker-resolved-$([guid]::NewGuid().ToString('N')).md") }
                    $state['retry'] = ''
                    $state.stage = $Next; Save-Job
                }
                deliver {
                    if ($state.stage -ne 'deliver' -or (Invoke-FactoryGit @('status','--porcelain') $worktree) -or (Head-Commit) -ne $state.review_commit) { throw 'Delivery requires the clean reviewed commit.' }
                    foreach ($required in @($state.reviewers -split ' ') + @('approver')) { $verdict = if ($required -eq 'approver') {'APPROVE'} else {'PASS'}; if (-not (Proof (Join-Path $roundFolder "$required.md") $verdict (Head-Commit))) { throw 'Required review or approval is missing.' } }
                    Invoke-FactoryGit @('push','-u','origin',$state.branch) $worktree | Out-Null
                    $arguments = @('pr','list','--state','all','--head',$state.branch,'--json','number,url,state,isDraft,headRefOid')
                    $prData = (Native 'gh' $arguments $project).Text | ConvertFrom-Json
                    $prs = @($prData | ForEach-Object { $_ })
                    if ($prs.Count -eq 0) {
                        $body = Join-Path $folder 'pr-body.md'; if (-not (Test-Path -LiteralPath $body)) { Copy-Item -LiteralPath (Join-Path $folder 'spec-writer.md') -Destination $body }
                        $title = [IO.File]::ReadAllLines((Join-Path $folder 'request.md'))[0]
                        Native 'gh' @('pr','create','--draft','--base',$state.base,'--head',$state.branch,'--title',$title,'--body-file',$body) $project | Out-Null
                        $prData = (Native 'gh' $arguments $project).Text | ConvertFrom-Json
                        $prs = @($prData | ForEach-Object { $_ })
                    }
                    if ($prs.Count -ne 1 -or $prs[0].state -ne 'OPEN' -or $prs[0].headRefOid -ne $state.review_commit) { throw 'PR state or head differs from the reviewed branch.' }
                    if ($prs[0].isDraft) { Native 'gh' @('pr','ready',[string]$prs[0].number) $project | Out-Null }
                    $state.pr_url = $prs[0].url; $state.stage = 'ready'; Save-Job
                }
            }
        }
    }
} catch {
    [Console]::Error.WriteLine("factory: $($_.Exception.Message)"); exit 1
} finally {
    [Console]::OutputEncoding = $previousOutputEncoding
    foreach ($path in $locks) {
        $owner = Join-Path $path 'owner'; if ([IO.File]::Exists($owner)) { [IO.File]::Delete($owner) }
        try { [IO.Directory]::Delete($path) } catch { }
    }
}
