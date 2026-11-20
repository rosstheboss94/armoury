[CmdletBinding()]
param([string]$Bash = '', [switch]$EncodingOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$encoding = New-Object Text.UTF8Encoding($false, $true)
$shell = (Get-Process -Id $PID).Path
if (-not $Bash) { $Bash = (Get-Command bash -CommandType Application | Select-Object -First 1).Source }
$git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
$env:FACTORY_ADD_GIT_DIR = Split-Path -Parent $git
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('factory-add-tests.' + [guid]::NewGuid().ToString('N'))
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
    # Native fixtures and helpers emit UTF-8 even when Run-Check inherits an OEM console.
    $info.StandardOutputEncoding = $script:encoding; $info.StandardErrorEncoding = $script:encoding
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try { $null = $process.Start() } catch { throw "Cannot start fixture program $Program. $($_.Exception.Message)" }
    $output = $process.StandardOutput.ReadToEndAsync(); $errorText = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return @{ Code=$process.ExitCode; Out=$output.Result; Err=$errorText.Result }
}
function Case([string]$Name, [string]$Idea = 'Add saved searches', [string]$Title = 'Add saved searches', [string]$Mode = 'success', [string]$Label = 'factory', [int]$Posts = 1, [bool]$Success = $true, [string]$InputKind = 'file', [int]$ConsoleCodePage = 0) {
    @{ Name=$Name; Idea=$Idea; Title=$Title; Mode=$Mode; Label=$Label; Posts=$Posts; Success=$Success; InputKind=$InputKind; ConsoleCodePage=$ConsoleCodePage }
}
$emoji = [char]::ConvertFromUtf32(128512)
$accent = [string][char]0xe9
$nbsp = [string][char]0xa0
$literal = '--title="literal" $(touch command-marker); `touch command-marker` & | > < \ backslash'
$cases = @(
    (Case 'ordinary'),
    (Case 'initialized'),
    (Case 'claude parity'),
    (Case 'multiline LF' "`n  Add`t$accent searches  `n`n$literal`n--leading-hyphens`n`n" "Add $accent searches"),
    (Case 'multiline CRLF' "`r`n`r`n  Add saved searches  `r`n$literal`r`n`r`n"),
    (Case 'literal title' $literal $literal),
    (Case 'emoji cutoff excluded' (('a' * 118) + $emoji + ' tail') ('a' * 118)),
    (Case 'emoji cutoff included' (('a' * 116) + $emoji + ' tail') (('a' * 116) + $emoji)),
    (Case 'long body' ("Add saved searches`n" + ('Body paragraph. ' * 6000) + "`n`n")),
    (Case 'unicode whitespace trim' ($nbsp + "`n" + $nbsp + 'Add saved searches' + $nbsp + "`n")),
    (Case 'controls and escapes' ("Add saved searches`n" + [char]1 + [char]8 + [char]11 + [char]12 + [char]31 + ' " \ ')),
    (Case 'custom literal label' 'Add saved searches' 'Add saved searches' 'success' ('triage / ' + $accent + ' " & #?')),
    (Case 'enterprise host' 'Add saved searches' 'Add saved searches' 'enterprise'),
    (Case 'empty' '' '' 'success' 'factory' 0 $false),
    (Case 'unicode blank' ($nbsp + "`t`r`n" + [char]0x3000) '' 'success' 'factory' 0 $false),
    (Case 'missing file' '' '' 'success' 'factory' 0 $false 'missing'),
    (Case 'absent path' '' '' 'success' 'factory' 0 $false 'no-path'),
    (Case 'directory' '' '' 'success' 'factory' 0 $false 'directory'),
    (Case 'unreadable file' 'locked' '' 'success' 'factory' 0 $false 'locked'),
    (Case 'invalid UTF8' '' '' 'success' 'factory' 0 $false 'invalid'),
    (Case 'UTF8 BOM' '' '' 'success' 'factory' 0 $false 'bom'),
    (Case 'NUL' "hello$([char]0)world" '' 'success' 'factory' 0 $false),
    (Case 'empty label' 'idea' 'idea' 'success' '' 0 $false),
    (Case 'blank label' 'idea' 'idea' 'success' $nbsp 0 $false),
    (Case 'comma label' 'idea' 'idea' 'success' 'one,two' 0 $false),
    (Case 'newline label' 'idea' 'idea' 'success' "one`ntwo" 0 $false)
)
foreach ($mode in @('missing-gh','missing-git','invalid-git','repo-fail','invalid-repo','auth-fail','missing-label','label-fail','post-reject','ambiguous','malformed','invalid-url','missing-returned-label')) {
    $posts = if ($mode -in @('post-reject','ambiguous','malformed','invalid-url','missing-returned-label')) { 1 } else { 0 }
    $cases += Case $mode 'Add saved searches' 'Add saved searches' $mode 'factory' $posts $false
}
try {
    Write-Output ('Offline issue fixtures. PowerShell ' + $PSVersionTable.PSVersion.ToString() + '. No live GitHub calls.')
    $engines = if ($EncodingOnly) { @() } else { @('powershell','bash') }
    if ($EncodingOnly -and $env:OS -ne 'Windows_NT') { throw 'Redirected encoding regressions require Windows PowerShell 5.1.' }
    if ($env:OS -eq 'Windows_NT') {
        Assert ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1) 'Executable fixtures require actual Windows PowerShell 5.1.'
        $compiled = Join-Path $temporary 'gh.exe'
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/add-native.cs'))) -OutputAssembly $compiled -OutputType ConsoleApplication
        foreach ($variant in @('openai','claude')) {
            $probe = Join-Path $temporary "$variant quote probe"
            [IO.Directory]::CreateDirectory($probe) | Out-Null
            $result = Run $shell @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'invoke-add-native-probe.ps1'),'-Helper',(Join-Path $repo "skills/$variant/factory/scripts/add-issue.ps1"),'-Executable',$compiled,'-Records',$probe,'-Temporary',$probe)
            Assert ($result.Code -eq 0) "$variant native quote probe failed: $($result.Out) $($result.Err)"
            Write-Output "$variant $($result.Out.TrimEnd())"
        }
        $engines += 'native'
    }
    foreach ($engine in $engines) {
        $engineCases = @(if (-not $EncodingOnly) { $cases })
        if ($engine -eq 'native') {
            foreach ($variant in @('openai','claude')) {
                foreach ($codePage in @(437,1252)) {
                    foreach ($mode in @('post-reject','ambiguous')) {
                        $engineCases += Case "$variant redirected $codePage $mode" -Mode $mode -Success $false -ConsoleCodePage $codePage
                    }
                }
            }
        }
        foreach ($case in $engineCases) {
            $work = Join-Path $temporary ([guid]::NewGuid().ToString('N'))
            $project = Join-Path $work 'project with spaces'; $bin = Join-Path $work 'bin with spaces'; $records = Join-Path $work 'records'; $tempFiles = Join-Path $work 'temp with spaces'
            foreach ($path in @($project,$bin,$records,$tempFiles)) { [IO.Directory]::CreateDirectory($path) | Out-Null }
            if ($case.Mode -ne 'invalid-git') {
                $init = Run $git @('init','-q',$project)
                Assert ($init.Code -eq 0) 'Cannot initialize offline Git project.'
            }
            $original = Join-Path $project 'keep.txt'; Write-Utf8 $original 'preexisting file'
            $preserved = @{}
            if ($case.Name -eq 'initialized') {
                foreach ($name in @('factory/config.json','factory/checks.ps1','factory/checks.sh','factory/jobs/fixture/job.state','factory/jobs/fixture/round-1/build.md','factory/dashboard.html','.gitignore')) {
                    $path = Join-Path $project $name
                    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
                    Write-Utf8 $path "Existing offline fixture $name"
                    $preserved[$path] = (Get-FileHash -LiteralPath $path).Hash
                }
            }
            $gitBefore = Run $git @('-C',$project,'status','--porcelain')
            $input = Join-Path $work 'idea.txt'
            Write-Utf8 $input $case.Idea
            switch ($case.InputKind) {
                missing { [IO.File]::Delete($input) }
                directory { [IO.File]::Delete($input); [IO.Directory]::CreateDirectory($input) | Out-Null }
                invalid { [IO.File]::WriteAllBytes($input, [byte[]]@(0xed,0xa0,0x80)) }
                bom { [IO.File]::WriteAllBytes($input, [byte[]]@(239,187,191,65)) }
            }
            $before = if ([IO.File]::Exists($input)) { (Get-FileHash -LiteralPath $input).Hash } else { '' }
            if ($case.InputKind -eq 'no-path') { $input = ''; $before = '' }
            Write-Utf8 (Join-Path $records 'mode') $case.Mode
            Write-Utf8 (Join-Path $records 'label') $case.Label
            $hostname = if ($case.Mode -eq 'enterprise') { 'git.example.invalid' } else { 'github.com' }
            Write-Utf8 (Join-Path $records 'host') $hostname
            Write-Utf8 (Join-Path $records 'context') "fixture/project`nhttps://$hostname/fixture/project`n"
            Write-Utf8 (Join-Path $records 'result') "42`nhttps://$hostname/fixture/project/issues/42`n$($case.Label)`n"
            # Isolate config and credentials. Fixtures have no forwarding path.
            $env:GH_CONFIG_DIR = Join-Path $work 'gh-config'; $env:GH_TOKEN = 'offline-fixture'; $env:GITHUB_TOKEN = 'offline-fixture'
            $env:GH_ENTERPRISE_TOKEN = 'offline-fixture'; $env:GITHUB_ENTERPRISE_TOKEN = 'offline-fixture'
            $env:GH_DEBUG = 'api'
            $env:TEMP = $tempFiles; $env:TMP = $tempFiles; $env:TMPDIR = Unix-Path $tempFiles
            $env:FACTORY_ADD_FIXTURE = if ($engine -eq 'bash') { Unix-Path $records } else { $records }
            $missing = if ($case.Mode -eq 'missing-gh') { 'gh' } elseif ($case.Mode -eq 'missing-git') { 'git' } else { 'none' }
            $variant = if ($case.Name -like 'claude*') { 'claude' } else { 'openai' }
            $defaultLabel = if ($case.Name -eq 'ordinary') { 'yes' } else { 'no' }
            if ($missing -ne 'gh') {
                $fixture = if ($engine -eq 'bash') { 'add-gh' } else { 'add-gh.ps1' }
                $target = if ($engine -eq 'bash') { 'gh' } else { 'gh.ps1' }
                [IO.File]::Copy((Join-Path $PSScriptRoot "fixtures/$fixture"), (Join-Path $bin $target))
                if ($engine -eq 'native') {
                    [IO.File]::Delete((Join-Path $bin $target))
                    [IO.File]::Copy($compiled, (Join-Path $bin 'gh.exe'))
                }
            }
            if ($engine -eq 'bash') {
                if ($missing -eq 'git') { Write-Utf8 (Join-Path $bin 'git') "#!/usr/bin/env bash`nprintf 'Git is unavailable in this fixture.\n' >&2`nexit 127`n" }
                $entry = Unix-Path (Join-Path $repo "skills/$variant/factory/scripts/factory.sh")
                $program = $Bash
                $arguments = @((Unix-Path (Join-Path $PSScriptRoot 'invoke-add-fixture.sh')), $entry, (Unix-Path $project), (Unix-Path $input), $case.Label, (Unix-Path $bin), $missing, $defaultLabel)
                # Executable mode is not retained by Windows file copies.
                $chmod = Run $Bash @('-c','chmod +x -- "$1"/*', 'fixture', (Unix-Path $bin))
                if ($missing -eq 'gh') { $null = $chmod } else { Assert ($chmod.Code -eq 0) 'Cannot prepare Bash fixture.' }
            } else {
                $program = $shell
                $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'invoke-add-fixture.ps1'),'-Entry',(Join-Path $repo "skills/$variant/factory/scripts/factory.ps1"),'-Project',$project,'-InputFile',$input,'-Label',$case.Label,'-Bin',$bin,'-Missing',$missing,'-DefaultLabel',$defaultLabel)
                if ($engine -eq 'native') { $arguments += @('-Fixture','gh.exe','-ConsoleCodePage',[string]$case.ConsoleCodePage) }
            }
            $handle = $null
            try {
                if ($case.InputKind -eq 'locked') { $handle = [IO.File]::Open($input, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None) }
                $result = Run $program $arguments
            } finally { if ($handle) { $handle.Dispose() } }
            $prefix = "$engine / $($case.Name)"
            Assert (($result.Code -eq 0) -eq $case.Success) "$prefix exit=$($result.Code) stdout=$($result.Out) stderr=$($result.Err)"
            if ($case.Success) {
                Assert ($result.Out -ceq "https://$hostname/fixture/project/issues/42`n" -or $result.Out -ceq "https://$hostname/fixture/project/issues/42`r`n") "$prefix success output is not URL-only: $($result.Out)"
            } else {
                Assert ($result.Out -eq '') "$prefix failure polluted stdout: $($result.Out)"
                Assert ($result.Err.Length -gt 0) "$prefix has no actionable diagnostic."
                if ($case.Posts -eq 1) { Assert ($result.Err -match 'Do not blindly retry' -and $result.Err -match 'closed issues') "$prefix lacks recovery guidance." }
                if ($case.Mode -eq 'missing-returned-label') { Assert ($result.Err -match 'https://github.com/fixture/project/issues/42' -and $result.Err -match 'Correct this existing issue') "$prefix lost the created issue URL." }
            }
            $calls = @(Get-ChildItem -LiteralPath $records -Directory -Filter 'call.*')
            if ($engine -eq 'native') {
                foreach ($call in $calls) {
                    $reader = New-Object IO.BinaryReader([IO.File]::OpenRead((Join-Path $call.FullName 'argv')), $encoding)
                    try {
                        $count = $reader.ReadInt32()
                        $actual = @(for ($i=0; $i -lt $count; $i++) { $reader.ReadString() })
                        if ($actual[0] -eq 'repo') { $expected = @('repo','view','--json','nameWithOwner,url','--template','{{.nameWithOwner}}{{"\n"}}{{.url}}{{"\n"}}') }
                        elseif ($actual[4] -eq 'GET') { $expected = @('api','--hostname',$hostname,'-X','GET',('repos/fixture/project/labels/' + [uri]::EscapeDataString($case.Label)),'--template','{{.name}}') }
                        else {
                            $payloadPath = [IO.File]::ReadAllText((Join-Path $call.FullName 'payload-path'))
                            Assert ($payloadPath.StartsWith($tempFiles + [IO.Path]::DirectorySeparatorChar) -and $payloadPath -match '[\\/]factory-add\.[0-9a-f]{32}[\\/]payload.json$') "$prefix unexpected complete payload path."
                            $expected = @('api','--hostname',$hostname,'-X','POST','repos/fixture/project/issues','--input',$payloadPath,'--template','{{printf "%v\n%s\n" .number .html_url}}{{range .labels}}{{printf "%s\n" .name}}{{end}}')
                        }
                        Assert ($count -eq $expected.Count) "$prefix argument count differs."
                        for ($i=0; $i -lt $count; $i++) { Assert ($actual[$i] -ceq $expected[$i]) "$prefix complete argument $i differs." }
                    } finally { $reader.Dispose() }
                }
                if ($case.Mode -in @('post-reject','ambiguous')) {
                    Assert ($result.Err.Contains("Submission diagnostic: caf$accent.")) "$prefix lost UTF-8 stderr."
                    Assert (-not $result.Err.Contains(('x' * 100))) "$prefix mixed stdout into diagnostics."
                }
            }
            $posts = @($calls | Where-Object { [IO.File]::Exists((Join-Path $_.FullName 'payload.json')) })
            Assert ($posts.Count -eq $case.Posts) "$prefix creation count $($posts.Count), expected $($case.Posts)."
            foreach ($post in $posts) {
                $payload = [IO.File]::ReadAllText((Join-Path $post.FullName 'payload.json'), $encoding) | ConvertFrom-Json
                Assert ($payload.title -ceq $case.Title) "$prefix title differs."
                Assert ($payload.body -ceq $case.Idea) "$prefix complete body differs."
                Assert (@($payload.labels).Count -eq 1 -and $payload.labels[0] -ceq $case.Label) "$prefix label differs."
                $payloadPath = [IO.File]::ReadAllText((Join-Path $post.FullName 'payload-path')).TrimEnd("`r", "`n")
                if ($engine -eq 'bash' -and $env:OS -eq 'Windows_NT' -and $payloadPath -match '^/([a-z])/(.*)$') { $payloadPath = $Matches[1] + ':/' + $Matches[2] }
                Assert (-not [IO.File]::Exists($payloadPath)) "$prefix temporary payload leaked."
            }
            if ($case.Success) {
                Assert ($calls.Count -eq 3) "$prefix did not make exactly two reads and one creation."
                $lookup = @($calls | ForEach-Object { [IO.File]::ReadAllLines((Join-Path $_.FullName 'arguments')) } | Where-Object { $_ -like 'repos/fixture/project/labels/*' })
                Assert ($lookup.Count -eq 1 -and [uri]::UnescapeDataString($lookup[0].Substring('repos/fixture/project/labels/'.Length)) -ceq $case.Label) "$prefix lookup label differs."
            }
            Assert (@(Get-ChildItem -LiteralPath $tempFiles -Force).Count -eq 0) "$prefix temporary files leaked."
            Assert ([IO.File]::ReadAllText($original) -eq 'preexisting file') "$prefix overwrote a user file."
            if ($case.Name -eq 'initialized') {
                foreach ($path in $preserved.Keys) { Assert ((Get-FileHash -LiteralPath $path).Hash -eq $preserved[$path]) "$prefix changed existing factory files." }
                Assert (@(Get-ChildItem -LiteralPath (Join-Path $project 'factory') -File -Recurse).Count -eq 6) "$prefix created runtime records."
            } else {
                Assert (-not [IO.Directory]::Exists((Join-Path $project 'factory'))) "$prefix initialized factory state."
                Assert (-not [IO.File]::Exists((Join-Path $project '.gitignore'))) "$prefix changed ignore rules."
            }
            $gitAfter = Run $git @('-C',$project,'status','--porcelain')
            Assert ($gitAfter.Out -ceq $gitBefore.Out) "$prefix changed Git state."
            Assert (-not [IO.File]::Exists((Join-Path $project 'command-marker'))) "$prefix evaluated idea text."
            Assert (-not [IO.File]::Exists((Join-Path $repo 'command-marker'))) "$prefix evaluated idea text in the caller directory."
            if ($before) { Assert ((Get-FileHash -LiteralPath $input).Hash -eq $before) "$prefix changed its input file." }
            if ($case.ConsoleCodePage) { Write-Output "PASS $prefix UTF-8 stderr, exit=$($result.Code), creation requests=$($posts.Count)." }
            if ($case.Name -in @('ordinary','missing-label','ambiguous')) {
                Write-Output "$prefix : exit=$($result.Code), creation requests=$($posts.Count)"
                if ($case.Success) { Write-Output $result.Out.TrimEnd() }
                else { Write-Output ([regex]::Replace($result.Err.TrimEnd(), 'y{100,}', '[70000 diagnostic bytes]')) }
            }
        }
        if ($EncodingOnly) { Write-Output "Verified $($engineCases.Count) redirected native UTF-8 diagnostic cases with exact arguments, payloads, exit status, recovery, cleanup, and no setup." }
        else { Write-Output "Verified $engine exact content, UTF-8 cutoff, literal input, labels, host, failures, one POST, cleanup, and no setup across $($engineCases.Count) offline cases." }
    }
} finally {
    # The only recursive deletion is the directory this test exclusively created.
    $resolved = [IO.Path]::GetFullPath($temporary)
    if ($resolved -notmatch '[\\/]factory-add-tests\.[0-9a-f]{32}$') { throw 'Unexpected fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
