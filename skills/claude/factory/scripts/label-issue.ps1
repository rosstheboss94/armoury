[CmdletBinding()]
param([string]$ProjectPath, [AllowEmptyString()][string]$Issue = '', [AllowEmptyString()][string]$Status = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $Issue) { exit 0 }
if ($Issue -notmatch '^[1-9][0-9]*$') { [Console]::Error.WriteLine('factory label: Pass the issue number saved on this job.'); exit 1 }
if ($Status -notin @('running','need-human','stopped')) { [Console]::Error.WriteLine('factory label: Status must be running, need-human, or stopped.'); exit 1 }
$encoding = New-Object Text.UTF8Encoding($false)
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('factory-label.' + [guid]::NewGuid().ToString('N'))
$pushed = $false
function Quote-Argument([string]$Value) {
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
function Invoke-Gh([string[]]$Arguments) {
    $diagnostics = Join-Path $script:temporary 'stderr'
    $stdoutPath = Join-Path $script:temporary 'stdout'
    $previousDebug = $env:GH_DEBUG
    $previousEncoding = [Console]::OutputEncoding
    try {
        $env:GH_DEBUG = ''
        [Console]::OutputEncoding = $script:encoding
        if ([IO.Path]::GetExtension($script:ghCommand.Source) -eq '.ps1') {
            $captured = & $script:ghCommand.Source @Arguments 2> $diagnostics
            $code = $LASTEXITCODE
            [IO.File]::WriteAllText($stdoutPath, (($captured | ForEach-Object { "$_" }) -join "`n"), $script:encoding)
        } else {
            $info = New-Object Diagnostics.ProcessStartInfo
            $info.FileName = $script:ghCommand.Source
            $info.Arguments = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
            $info.WorkingDirectory = (Get-Location).ProviderPath
            $info.UseShellExecute = $false; $info.CreateNoWindow = $true
            $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
            $info.StandardOutputEncoding = $script:encoding; $info.StandardErrorEncoding = $script:encoding
            $process = New-Object Diagnostics.Process
            $process.StartInfo = $info
            try {
                $null = $process.Start()
                $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync()
                $process.WaitForExit()
                [IO.File]::WriteAllText($stdoutPath, $outTask.Result, $script:encoding)
                [IO.File]::WriteAllText($diagnostics, $errTask.Result, $script:encoding)
                $code = $process.ExitCode
            } finally { $process.Dispose() }
        }
    } finally { $env:GH_DEBUG = $previousDebug; [Console]::OutputEncoding = $previousEncoding }
    $output = if ([IO.File]::Exists($stdoutPath)) { [IO.File]::ReadAllText($stdoutPath, $script:encoding) } else { '' }
    $detail = ''
    if ([IO.File]::Exists($diagnostics)) {
        $bytes = [IO.File]::ReadAllBytes($diagnostics)
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) { $detail = [Text.Encoding]::Unicode.GetString($bytes).Trim() }
        else { $detail = $script:encoding.GetString($bytes).Trim() }
    }
    return @{ Code = $code; Output = $output; Detail = $detail }
}
try {
    [IO.Directory]::CreateDirectory($temporary) | Out-Null
    Push-Location -LiteralPath $ProjectPath
    $pushed = $true
    $ghCommand = Get-Command gh -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ghCommand) { throw 'Install GitHub CLI and authenticate with gh auth login.' }
    $context = Invoke-Gh @('repo','view','--json','nameWithOwner,url','--template','{{.nameWithOwner}}{{"\n"}}{{.url}}{{"\n"}}')
    if ($context.Code -ne 0) { throw "Cannot resolve the repository. Check gh auth login, gh repo view, and project remotes. $($context.Detail)" }
    $parts = @($context.Output.TrimEnd("`r","`n") -split '\r?\n')
    if ($parts.Count -ne 2 -or $parts[0] -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Cannot resolve the GitHub repository. Check gh repo view and the project remotes.' }
    $repository = $parts[0]
    if ($parts[1] -cnotmatch ('^https://([A-Za-z0-9][A-Za-z0-9.-]*(?::[0-9]+)?)/' + [regex]::Escape($repository) + '$')) { throw 'GitHub returned an invalid repository URL.' }
    $hostname = $Matches[1]
    $endpoint = "repos/$repository"
    function Read-IssueLabels {
        $read = Invoke-Gh @('api','--hostname',$hostname,'-X','GET',"$endpoint/issues/$Issue/labels",'--template','{{range .}}{{printf "%s\n" .name}}{{end}}')
        if ($read.Code -ne 0) { throw "GitHub label lookup failed. No issue was created. $($read.Detail)" }
        return @($read.Output -split '\r?\n' | Where-Object { $_ -ne '' })
    }
    $current = @(Read-IssueLabels)
    $encoded = [uri]::EscapeDataString($Status)
    $exists = Invoke-Gh @('api','--hostname',$hostname,'-X','GET',"$endpoint/labels/$encoded",'--template','{{.name}}')
    if ($exists.Code -ne 0) {
        if ($exists.Detail -notmatch '404|Not Found') { throw "GitHub label lookup failed. Existing issue labels were left unchanged. $($exists.Detail)" }
        $createPath = Join-Path $temporary 'create.json'
        [IO.File]::WriteAllText($createPath, ('{"name":"' + $Status + '","color":"ededed"}'), $encoding)
        $created = Invoke-Gh @('api','--hostname',$hostname,'-X','POST',"$endpoint/labels",'--input',$createPath)
        if ($created.Code -ne 0) { throw "GitHub could not create the status label. Existing issue labels were left unchanged. $($created.Detail)" }
    }
    $addPath = Join-Path $temporary 'add.json'
    [IO.File]::WriteAllText($addPath, ('{"labels":["' + $Status + '"]}'), $encoding)
    $added = Invoke-Gh @('api','--hostname',$hostname,'-X','POST',"$endpoint/issues/$Issue/labels",'--input',$addPath)
    if ($added.Code -ne 0) { throw "GitHub rejected the status label. Existing issue labels were left unchanged. $($added.Detail)" }
    foreach ($other in @('running','need-human','stopped')) {
        if ($other -eq $Status -or $current -cnotcontains $other) { continue }
        $removed = Invoke-Gh @('api','--hostname',$hostname,'-X','DELETE',"$endpoint/issues/$Issue/labels/$([uri]::EscapeDataString($other))")
        if ($removed.Code -ne 0) { throw "GitHub could not remove the previous status label. $($removed.Detail)" }
    }
    $final = @(Read-IssueLabels)
    foreach ($name in $final) { [Console]::Out.WriteLine($name) }
    exit 0
} catch {
    [Console]::Error.WriteLine("factory label: $($_.Exception.Message)")
    exit 1
} finally {
    if ($pushed) { Pop-Location }
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
}
