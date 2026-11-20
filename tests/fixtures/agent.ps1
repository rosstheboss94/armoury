$ErrorActionPreference = 'Stop'
if ($env:FACTORY_FAKE_SLEEP -and $env:FACTORY_FAKE_SLEEP -ne '0') { Start-Sleep -Seconds ([int]$env:FACTORY_FAKE_SLEEP) }
if ($env:FACTORY_FAKE_EDIT -eq '1') { [IO.File]::WriteAllText((Join-Path (Get-Location).Path 'app.txt'), "done`n") }
$inputBytes = New-Object IO.MemoryStream
[Console]::OpenStandardInput().CopyTo($inputBytes)
if ($env:FACTORY_NATIVE_CAPTURE) { [IO.File]::WriteAllBytes((Join-Path $env:FACTORY_NATIVE_CAPTURE 'stdin.bin'), $inputBytes.ToArray()) }
$promptText = (New-Object Text.UTF8Encoding($false, $true)).GetString($inputBytes.ToArray())
$inputBytes.Dispose()
$promptIndex = [Array]::IndexOf($args, '--prompt-file')
if ($promptIndex -ge 0) { $promptText = [IO.File]::ReadAllText($args[$promptIndex+1]) }
foreach ($argument in $args) { [Console]::Error.WriteLine($argument) }
$role = [regex]::Match($promptText, '(?m)^ROLE: ([\w-]+)').Groups[1].Value
$verdict = switch ($role) { intake {'ACCEPT'} {$_ -in @('spec-writer','builder')} {'READY'} approver {'APPROVE'} default {'PASS'} }
$body = @{verdict=$verdict;summary='Fixture';report='Offline evidence';skills_used=@();risk='low';areas=@('code')} | ConvertTo-Json -Compress
if ($promptIndex -ge 0) { @{text=$body;stopReason='end_turn';sessionId='offline'} | ConvertTo-Json -Compress }
elseif ($args -contains 'exec') {
    @{type='thread.started';thread_id='offline'} | ConvertTo-Json -Compress
    @{type='item.completed';item=@{type='agent_message';text=$body}} | ConvertTo-Json -Depth 5 -Compress
    @{type='turn.completed';usage=@{input_tokens=1;output_tokens=1}} | ConvertTo-Json -Depth 4 -Compress
} else { @{result=$body;is_error=$false;session_id='offline'} | ConvertTo-Json -Compress }
exit 0
