param([string]$Bash = '', [string]$TestScript = (Join-Path $PSScriptRoot 'add-issue.ps1'))
$ErrorActionPreference = 'Stop'
# Match Run-Check's redirected PowerShell process, including implicit outer decoding.
# Force OEM encoding in the child so a UTF-8 desktop console cannot hide the defect.
$command = "[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(437); & '" + $TestScript.Replace("'", "''") + "' -EncodingOnly"
if ($Bash) { $command += " -Bash '" + $Bash.Replace("'", "''") + "'" }
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = (Get-Process -Id $PID).Path
$info.Arguments = '-NoProfile -NonInteractive -Command "' + $command.Replace('"', '\"') + '"'
$info.UseShellExecute = $false; $info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
$process = New-Object Diagnostics.Process
$process.StartInfo = $info
try {
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    [Console]::Out.Write($stdout.Result)
    [Console]::Error.Write($stderr.Result)
    if ($process.ExitCode -ne 0) { throw "Redirected OEM issue regression failed with exit $($process.ExitCode)." }
    Write-Output 'PASS redirected Run-Check equivalent with OEM parent, UTF-8 streams, both models, and 8 rejected or uncertain submissions.'
} finally { $process.Dispose() }
