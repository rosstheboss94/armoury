[CmdletBinding()]
param([string]$ProjectPath, [string]$File, [AllowEmptyString()][string]$Label = 'factory')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$temporary = $null
$ownedTemporary = $false
$submitted = $false
$recovery = ''
function Quote-Argument([string]$Value) {
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
function Gh([string[]]$Arguments) {
    # Idea text never enters native arguments, including on Windows PowerShell 5.1.
    $diagnostics = Join-Path $script:temporary 'stderr'
    $previousDebug = $env:GH_DEBUG
    $previousEncoding = [Console]::OutputEncoding
    try {
        # API debug logs can contain request headers and the complete idea.
        $env:GH_DEBUG = ''
        # Windows PowerShell 5.1 otherwise decodes native UTF-8 output as OEM text.
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        if ([IO.Path]::GetExtension($script:ghCommand.Source) -eq '.ps1') {
            $output = & $script:ghCommand.Source @Arguments 2> $diagnostics
            $code = $LASTEXITCODE
            $detail = [IO.File]::ReadAllText($diagnostics).Trim()
            $output = $output -join "`n"
        } else {
            # Encode the executable boundary explicitly, including Go-template quotes.
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
                $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
                $process.WaitForExit()
                $output = $stdout.Result; $detail = $stderr.Result.Trim(); $code = $process.ExitCode
            } finally { $process.Dispose() }
        }
    } finally { $env:GH_DEBUG = $previousDebug; [Console]::OutputEncoding = $previousEncoding }
    if ($code -ne 0) {
        throw "GitHub CLI failed. Check authentication, repository access, and the diagnostic: $detail"
    }
    return $output
}
try {
    if (-not $File -or -not [IO.File]::Exists($File)) { throw 'Pass -File with a readable UTF-8 idea file, not a directory.' }
    $bytes = [IO.File]::ReadAllBytes($File)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { throw 'Use UTF-8 without a BOM.' }
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    $idea = $encoding.GetString($bytes)
    if ($idea.IndexOf([char]0) -ge 0) { throw 'NUL bytes are not supported in an idea.' }
    # Unicode White_Space, shared explicitly with the Bash implementation.
    $whitespace = '[\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]'
    $title = ''
    foreach ($line in ($idea -split "`n")) {
        $candidate = [regex]::Replace([regex]::Replace($line, "^$whitespace+", ''), "$whitespace+$", '').Replace("`t", ' ')
        if ($candidate.Length -eq 0) { continue }
        $length = 0; $count = 0
        for ($index = 0; $index -lt $candidate.Length; $index += $length) {
            $length = if ([char]::IsHighSurrogate($candidate[$index])) { 2 } else { 1 }
            $character = $candidate.Substring($index, $length)
            $size = $encoding.GetByteCount($character)
            if ($count + $size -gt 120) { break }
            $title += $character; $count += $size
        }
        break
    }
    if (-not $title) { throw 'The idea must contain non-whitespace text.' }
    if ([regex]::IsMatch($Label, "^$whitespace*$") -or $Label.IndexOfAny([char[]]",`r`n") -ge 0) {
        throw 'Choose one nonblank label without commas or line breaks.'
    }
    # New-Item refuses collisions. Only files in this owned directory are removed.
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('factory-add.' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporary -ErrorAction Stop | Out-Null
    $ownedTemporary = $true
    if ($env:OS -ne 'Windows_NT') {
        & chmod 700 -- $temporary
        if ($LASTEXITCODE -ne 0) { throw 'Cannot make the temporary directory private.' }
    }
    Push-Location -LiteralPath $ProjectPath
    try {
        $ghCommand = Get-Command gh -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $ghCommand) { throw 'Install GitHub CLI and authenticate with gh auth login.' }
        $context = Gh @('repo','view','--json','nameWithOwner,url','--template','{{.nameWithOwner}}{{"\n"}}{{.url}}{{"\n"}}')
        $parts = @($context.TrimEnd("`r", "`n") -split '\r?\n')
        if ($parts.Count -ne 2 -or $parts[0] -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Cannot resolve the GitHub repository. Check gh repo view and the project remotes.' }
        $repository = $parts[0]
        if ($parts[1] -cnotmatch ('^https://([A-Za-z0-9][A-Za-z0-9.-]*(?::[0-9]+)?)/' + [regex]::Escape($repository) + '$')) { throw 'GitHub returned an invalid repository URL.' }
        $hostname = $Matches[1]
        $recovery = "Inspect recent issues in https://$hostname/$repository/issues, including closed issues, and compare title and body before retrying. A repeated invocation creates a new issue."
        $endpoint = "repos/$repository"
        try { $null = Gh @('api','--hostname',$hostname,'-X','GET',"$endpoint/labels/$([uri]::EscapeDataString($Label))",'--template','{{.name}}') }
        catch { throw "Label lookup failed. Create the label in $repository or select an existing label. $($_.Exception.Message)" }
        $payload = Join-Path $temporary 'payload.json'
        $json = ConvertTo-Json -InputObject ([ordered]@{ title=$title; body=$idea; labels=@($Label) }) -Depth 4 -Compress
        $stream = [IO.File]::Open($payload, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $data = $encoding.GetBytes($json); $stream.Write($data, 0, $data.Length) } finally { $stream.Dispose() }
        $submitted = $true
        $result = Gh @('api','--hostname',$hostname,'-X','POST',"$endpoint/issues",'--input',$payload,'--template','{{printf "%v\n%s\n" .number .html_url}}{{range .labels}}{{printf "%s\n" .name}}{{end}}')
        $resultLines = @($result -split '\r?\n')
        if ($resultLines.Count -lt 2 -or $resultLines[0] -notmatch '^[1-9][0-9]*$' -or $resultLines[1] -cne "https://$hostname/$repository/issues/$($resultLines[0])") { throw 'GitHub returned an invalid issue result.' }
        if ($resultLines.Count -lt 3 -or -not (@($resultLines | Select-Object -Skip 2) -ccontains $Label)) {
            throw "Created issue $($resultLines[1]) lacks the requested label. Correct this existing issue before running the queue."
        }
        [Console]::Out.WriteLine($resultLines[1])
    } finally { Pop-Location }
    exit 0
} catch {
    [Console]::Error.WriteLine("factory add: $($_.Exception.Message)")
    if ($submitted) { [Console]::Error.WriteLine("Creation may have occurred. Do not blindly retry. $recovery") }
    exit 1
} finally {
    if ($ownedTemporary -and [IO.Directory]::Exists($temporary)) {
        foreach ($name in @('payload.json','stderr')) { [IO.File]::Delete((Join-Path $temporary $name)) }
        [IO.Directory]::Delete($temporary)
    }
}
