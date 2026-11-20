# Offline fixture. Never forwards a command to GitHub CLI.
$ErrorActionPreference = 'Stop'
if (-not $env:FACTORY_ADD_FIXTURE -or -not [IO.Directory]::Exists($env:FACTORY_ADD_FIXTURE)) { exit 90 }
if ($env:GH_DEBUG) { throw 'API debug logging must be disabled for issue requests.' }
if ([Console]::OutputEncoding.CodePage -ne 65001) { throw 'Native GitHub output must decode as UTF-8.' }
$folder = $env:FACTORY_ADD_FIXTURE
$record = Join-Path $folder ('call.' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($record) | Out-Null
[IO.File]::WriteAllLines((Join-Path $record 'arguments'), [string[]]$args)
$mode = [IO.File]::ReadAllText((Join-Path $folder 'mode'))
$template = '{{printf "%v\n%s\n" .number .html_url}}{{range .labels}}{{printf "%s\n" .name}}{{end}}'
if ($args.Count -eq 6 -and ($args[0..4] -join '|') -ceq 'repo|view|--json|nameWithOwner,url|--template' -and $args[5] -ceq '{{.nameWithOwner}}{{"\n"}}{{.url}}{{"\n"}}') {
    switch ($mode) {
        repo-fail { [Console]::Error.WriteLine('No GitHub repository context.'); exit 1 }
        auth-fail { [Console]::Error.WriteLine('Authentication required.'); exit 1 }
        invalid-repo { "fixture/project`nhttp://github.com/fixture/project" }
        default { Write-Output ([IO.File]::ReadAllText((Join-Path $folder 'context'))) }
    }
} elseif ($args.Count -ge 8 -and $args[0] -ceq 'api' -and $args[1] -ceq '--hostname' -and $args[2] -ceq [IO.File]::ReadAllText((Join-Path $folder 'host')) -and $args[3] -ceq '-X') {
    if ($args.Count -eq 8 -and $args[4] -ceq 'GET' -and $args[5].StartsWith('repos/fixture/project/labels/') -and $args[6] -ceq '--template' -and $args[7] -ceq '{{.name}}') {
        if ($mode -in @('missing-label','label-fail')) { [Console]::Error.WriteLine('Label lookup rejected.'); exit 1 }
        'fixture label'
    } elseif ($args.Count -eq 10 -and $args[4] -ceq 'POST' -and $args[5] -ceq 'repos/fixture/project/issues' -and $args[6] -ceq '--input' -and $args[8] -ceq '--template' -and $args[9] -ceq $template) {
        [IO.File]::WriteAllText((Join-Path $record 'payload-path'), $args[7])
        [IO.File]::Copy($args[7], (Join-Path $record 'payload.json'))
        switch ($mode) {
            post-reject { [Console]::Error.WriteLine('HTTP 422 validation failed.'); exit 1 }
            ambiguous { [Console]::Error.WriteLine('Connection closed after submission.'); exit 1 }
            malformed { 'invalid response' }
            invalid-url { "42`nhttps://attacker.invalid/issues/42`nfactory" }
            missing-returned-label { "42`nhttps://github.com/fixture/project/issues/42" }
            default { Write-Output ([IO.File]::ReadAllText((Join-Path $folder 'result'))) }
        }
    } else { throw 'Unexpected offline GitHub fixture API call.' }
} else { throw 'Unexpected offline GitHub fixture call.' }
exit 0
