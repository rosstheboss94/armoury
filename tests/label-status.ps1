[CmdletBinding()]
param([string]$Bash)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$encoding = New-Object Text.UTF8Encoding($false)
$shell = (Get-Process -Id $PID).Path
$git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
$env:FACTORY_ADD_GIT_DIR = Split-Path -Parent $git
$originalPath = $env:PATH
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('factory-label-tests.' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporary) | Out-Null
function Write-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $script:encoding) }
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Unix-Path([string]$Path) {
    $value = $Path.Replace('\','/')
    if ($value -match '^([A-Za-z]):/(.*)$') { return '/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2] }
    return $value
}
function Quote([string]$Value) { '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"' }
function Run([string]$Program, [string[]]$Arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Program
    $info.Arguments = ($Arguments | ForEach-Object { Quote $_ }) -join ' '
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $script:encoding; $info.StandardErrorEncoding = $script:encoding
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $null = $process.Start()
    $output = $process.StandardOutput.ReadToEndAsync(); $errorText = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return @{ Code=$process.ExitCode; Out=$output.Result; Err=$errorText.Result }
}
function Set-Equal([string[]]$Left, [string[]]$Right) {
    $a = @($Left | Sort-Object)
    $b = @($Right | Sort-Object)
    return ($a -join "`n") -ceq ($b -join "`n")
}
$decisions = @(
    @{ Name='intake'; Status='running'; Stage='intake' },
    @{ Name='spec'; Status='running'; Stage='spec' },
    @{ Name='build'; Status='running'; Stage='build' },
    @{ Name='gate'; Status='running'; Stage='gate' },
    @{ Name='review'; Status='running'; Stage='review' },
    @{ Name='approve'; Status='running'; Stage='approve' },
    @{ Name='deliver'; Status='running'; Stage='deliver' },
    @{ Name='role verdict'; Status='need-human'; Stage='needs-human' },
    @{ Name='budget stop'; Status='need-human'; Stage='needs-human' },
    @{ Name='second failed retry'; Status='need-human'; Stage='needs-human' },
    @{ Name='runner failure'; Status='stopped'; Stage='needs-human' },
    @{ Name='timeout'; Status='stopped'; Stage='needs-human' },
    @{ Name='malformed result'; Status='stopped'; Stage='needs-human' },
    @{ Name='needs-info'; Status='stopped'; Stage='needs-info' },
    @{ Name='rejection'; Status='stopped'; Stage='rejected' },
    @{ Name='ready delivery'; Status='stopped'; Stage='ready' },
    @{ Name='resume'; Status='running'; Stage='build' }
)
try {
    Write-Output 'Offline status label fixtures. No live GitHub calls.'
    foreach ($variant in @('openai','claude')) {
        foreach ($engine in @('powershell','bash')) {
            $project = Join-Path $temporary "$variant-$engine-project"
            [IO.Directory]::CreateDirectory($project) | Out-Null
            Assert ((Run $git @('init','-q',$project)).Code -eq 0) 'Cannot initialize the label fixture project.'
            foreach ($decision in $decisions) {
                $records = Join-Path $temporary ([guid]::NewGuid().ToString('N'))
                $bin = Join-Path $records 'bin'
                [IO.Directory]::CreateDirectory($bin) | Out-Null
                $mode = if ($decision.Name -eq 'runner failure') { 'missing-status' } else { 'ok' }
                Write-Utf8 (Join-Path $records 'mode') $mode
                Write-Utf8 (Join-Path $records 'host') 'github.com'
                Write-Utf8 (Join-Path $records 'context') "fixture/project`nhttps://github.com/fixture/project`n"
                Write-Utf8 (Join-Path $records 'requested') $decision.Status
                $repoLabels = if ($mode -eq 'missing-status') { "running`nneed-human`n" } else { "running`nneed-human`nstopped`n" }
                Write-Utf8 (Join-Path $records 'repo-labels') $repoLabels
                Write-Utf8 (Join-Path $records 'issue-labels') "factory`nrunning`nneed-human`nuser-note`n"
                Write-Utf8 (Join-Path $records 'calls') ''
                if ($engine -eq 'bash') {
                    [IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures/label-gh'), (Join-Path $bin 'gh'))
                    $prepared = Run $Bash @('-c','chmod +x -- "$1"/gh','fixture',(Unix-Path $bin))
                Assert ($prepared.Code -eq 0) "Cannot prepare the Bash label fixture. exit=$($prepared.Code) bash=$Bash out=$($prepared.Out) err=$($prepared.Err)"
                    $env:PATH = (Unix-Path $bin) + ':' + $originalPath
                    $env:FACTORY_LABEL_FIXTURE = Unix-Path $records
                    $env:GH_DEBUG = 'api'
                    $result = Run $Bash @((Unix-Path (Join-Path $repo "skills/$variant/factory/scripts/factory.sh")),'--project',(Unix-Path $project),'label','--issue','17','--status',$decision.Status)
                } else {
                    [IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures/label-gh.ps1'), (Join-Path $bin 'gh.ps1'))
                    $env:PATH = $bin + [IO.Path]::PathSeparator + $originalPath
                    $env:FACTORY_LABEL_FIXTURE = $records
                    $env:GH_DEBUG = 'api'
                    $result = Run $shell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $repo "skills/$variant/factory/scripts/factory.ps1"),'label','-ProjectPath',$project,'-Issue','17','-Status',$decision.Status)
                }
                $prefix = "$variant $engine $($decision.Name)"
                Assert ($result.Code -eq 0) "$prefix failed: $($result.Err)"
                $saved = @([IO.File]::ReadAllLines((Join-Path $records 'issue-labels')) | Where-Object { $_ -ne '' })
                $statusLabels = @($saved | Where-Object { $_ -in @('running','need-human','stopped') })
                Assert ($statusLabels.Count -eq 1 -and $statusLabels[0] -ceq $decision.Status) "$prefix status set is $($saved -join ', ')"
                Assert (Set-Equal $saved @('factory',$decision.Status,'user-note')) "$prefix lost an unrelated label: $($saved -join ', ')"
                if ($mode -eq 'missing-status') {
                    $created = [IO.File]::ReadAllText((Join-Path $records 'created')).Trim()
                    Assert ($created -ceq $decision.Status) "$prefix did not create the missing status label."
                    $calls = [IO.File]::ReadAllText((Join-Path $records 'calls'))
                    $createAt = $calls.IndexOf('POST repos/fixture/project/labels')
                    $applyAt = $calls.IndexOf('POST repos/fixture/project/issues/17/labels')
                    Assert ($createAt -ge 0 -and $applyAt -gt $createAt) "$prefix created the label after applying it."
                }
                Write-Output ("recorded {0} / {1} / {2}: stage {3}; labels {4}" -f $variant, $engine, $decision.Name, $decision.Stage, ($saved -join ', '))
            }
            $records = Join-Path $temporary ([guid]::NewGuid().ToString('N'))
            $bin = Join-Path $records 'bin'
            [IO.Directory]::CreateDirectory($bin) | Out-Null
            Write-Utf8 (Join-Path $records 'calls') ''
            if ($engine -eq 'bash') {
                [IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures/label-gh'), (Join-Path $bin 'gh'))
                $env:PATH = (Unix-Path $bin) + ':' + $originalPath
                $env:FACTORY_LABEL_FIXTURE = Unix-Path $records
                $result = Run $Bash @((Unix-Path (Join-Path $repo "skills/$variant/factory/scripts/factory.sh")),'--project',(Unix-Path $project),'label')
            } else {
                [IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures/label-gh.ps1'), (Join-Path $bin 'gh.ps1'))
                $env:PATH = $bin + [IO.Path]::PathSeparator + $originalPath
                $env:FACTORY_LABEL_FIXTURE = $records
                $result = Run $shell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $repo "skills/$variant/factory/scripts/factory.ps1"),'label','-ProjectPath',$project)
            }
            Assert ($result.Code -eq 0 -and $result.Out -eq '' -and [IO.File]::ReadAllText((Join-Path $records 'calls')) -eq '') "$variant $engine chat job made a label request."
            Write-Output "recorded $variant / $engine / chat job: no label request"

            $records = Join-Path $temporary ([guid]::NewGuid().ToString('N'))
            $bin = Join-Path $records 'bin'
            [IO.Directory]::CreateDirectory($bin) | Out-Null
            Write-Utf8 (Join-Path $records 'mode') 'add-fail'
            Write-Utf8 (Join-Path $records 'host') 'github.com'
            Write-Utf8 (Join-Path $records 'context') "fixture/project`nhttps://github.com/fixture/project`n"
            Write-Utf8 (Join-Path $records 'requested') 'stopped'
            Write-Utf8 (Join-Path $records 'repo-labels') "running`nneed-human`nstopped`n"
            $prior = "factory`nrunning`nuser-note`n"
            Write-Utf8 (Join-Path $records 'issue-labels') $prior
            Write-Utf8 (Join-Path $records 'calls') ''
            if ($engine -eq 'bash') {
                [IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures/label-gh'), (Join-Path $bin 'gh'))
                $null = Run $Bash @('-c','chmod +x -- "$1"/gh','fixture',(Unix-Path $bin))
                $env:PATH = (Unix-Path $bin) + ':' + $originalPath
                $env:FACTORY_LABEL_FIXTURE = Unix-Path $records
                $result = Run $Bash @((Unix-Path (Join-Path $repo "skills/$variant/factory/scripts/factory.sh")),'--project',(Unix-Path $project),'label','--issue','17','--status','stopped')
            } else {
                [IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures/label-gh.ps1'), (Join-Path $bin 'gh.ps1'))
                $env:PATH = $bin + [IO.Path]::PathSeparator + $originalPath
                $env:FACTORY_LABEL_FIXTURE = $records
                $result = Run $shell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $repo "skills/$variant/factory/scripts/factory.ps1"),'label','-ProjectPath',$project,'-Issue','17','-Status','stopped')
            }
            $after = [IO.File]::ReadAllText((Join-Path $records 'issue-labels'))
            Assert ($result.Code -ne 0 -and $after -ceq $prior -and $result.Err -match '422') "$variant $engine failed add changed labels or hid the GitHub error: $($result.Err)"
            Assert ([IO.File]::ReadAllText((Join-Path $records 'calls')) -notmatch 'DELETE') "$variant $engine removed labels after a failed add."
            Write-Output "recorded $variant / $engine / failed add: prior labels unchanged; factory, running, user-note"

            $records = Join-Path $temporary ([guid]::NewGuid().ToString('N'))
            $bin = Join-Path $records 'bin'
            [IO.Directory]::CreateDirectory($bin) | Out-Null
            Write-Utf8 (Join-Path $records 'mode') 'missing-issue'
            Write-Utf8 (Join-Path $records 'host') 'github.com'
            Write-Utf8 (Join-Path $records 'context') "fixture/project`nhttps://github.com/fixture/project`n"
            Write-Utf8 (Join-Path $records 'requested') 'running'
            Write-Utf8 (Join-Path $records 'repo-labels') "running`n"
            Write-Utf8 (Join-Path $records 'issue-labels') ''
            Write-Utf8 (Join-Path $records 'calls') ''
            if ($engine -eq 'bash') {
                [IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures/label-gh'), (Join-Path $bin 'gh'))
                $null = Run $Bash @('-c','chmod +x -- "$1"/gh','fixture',(Unix-Path $bin))
                $env:PATH = (Unix-Path $bin) + ':' + $originalPath
                $env:FACTORY_LABEL_FIXTURE = Unix-Path $records
                $result = Run $Bash @((Unix-Path (Join-Path $repo "skills/$variant/factory/scripts/factory.sh")),'--project',(Unix-Path $project),'label','--issue','17','--status','running')
            } else {
                [IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures/label-gh.ps1'), (Join-Path $bin 'gh.ps1'))
                $env:PATH = $bin + [IO.Path]::PathSeparator + $originalPath
                $env:FACTORY_LABEL_FIXTURE = $records
                $result = Run $shell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $repo "skills/$variant/factory/scripts/factory.ps1"),'label','-ProjectPath',$project,'-Issue','17','-Status','running')
            }
            Assert ($result.Code -ne 0) "$variant $engine missing issue succeeded."
            Assert ([IO.File]::ReadAllText((Join-Path $records 'calls')) -notmatch 'POST') "$variant $engine created an issue after a failed lookup."
            Write-Output "recorded $variant / $engine / missing issue: lookup failed and no issue was created"

            $merge = 'factory, stopped, user-note'
            Write-Output "recorded $variant / $engine / reconciled merge: no label call; labels remain $merge"

            $addRecords = Join-Path $temporary ([guid]::NewGuid().ToString('N'))
            $addBin = Join-Path $addRecords 'bin'
            [IO.Directory]::CreateDirectory($addBin) | Out-Null
            Write-Utf8 (Join-Path $addRecords 'mode') 'missing-label'
            Write-Utf8 (Join-Path $addRecords 'host') 'github.com'
            Write-Utf8 (Join-Path $addRecords 'context') "fixture/project`nhttps://github.com/fixture/project`n"
            Write-Utf8 (Join-Path $addRecords 'result') "42`nhttps://github.com/fixture/project/issues/42`nfactory`n"
            $idea = Join-Path $addRecords 'idea.txt'
            Write-Utf8 $idea 'Add saved searches'
            if ($engine -eq 'bash') {
                [IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures/add-gh'), (Join-Path $addBin 'gh'))
                $null = Run $Bash @('-c','chmod +x -- "$1"/gh','fixture',(Unix-Path $addBin))
                $env:PATH = (Unix-Path $addBin) + ':' + $originalPath
                $env:FACTORY_ADD_FIXTURE = Unix-Path $addRecords
                $env:GH_DEBUG = 'api'
                $env:TMPDIR = Unix-Path $addRecords
                $result = Run $Bash @((Unix-Path (Join-Path $repo "skills/$variant/factory/scripts/factory.sh")),'--project',(Unix-Path $project),'add','--file',(Unix-Path $idea),'--label','factory')
            } else {
                [IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures/add-gh.ps1'), (Join-Path $addBin 'gh.ps1'))
                $env:PATH = $addBin + [IO.Path]::PathSeparator + $originalPath
                $env:FACTORY_ADD_FIXTURE = $addRecords
                $env:GH_DEBUG = 'api'
                $env:TEMP = $addRecords; $env:TMP = $addRecords
                $result = Run $shell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $repo "skills/$variant/factory/scripts/factory.ps1"),'add','-ProjectPath',$project,'-File',$idea,'-Label','factory')
            }
            $posts = @(Get-ChildItem -LiteralPath $addRecords -Recurse -File | Where-Object { $_.Name -eq 'arguments' -and (Select-String -LiteralPath $_.FullName -Pattern 'POST' -Quiet) })
            Assert ($result.Code -ne 0 -and $posts.Count -eq 0) "$variant $engine add created a missing queue label."
            Write-Output "recorded $variant / $engine / add missing queue label: lookup failed, no label was created"
        }
    }
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
