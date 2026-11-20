$ErrorActionPreference = 'Stop'
$folder = $env:FACTORY_FAKE_GH
switch ($args[0] + ':' + $args[1]) {
    'pr:list' {
        if (-not (Test-Path -LiteralPath (Join-Path $folder 'pr'))) { Write-Output '[]'; exit 0 }
        $index = [Array]::IndexOf($args, '--head')
        $commit = (& git rev-parse $args[$index+1]).Trim()
        Write-Output ('[{"number":1,"url":"https://github.com/example/project/pull/1","state":"OPEN","isDraft":true,"headRefOid":"' + $commit + '"}]')
    }
    'pr:create' { [IO.File]::WriteAllText((Join-Path $folder 'pr'), 'created'); Write-Output 'https://github.com/example/project/pull/1' }
    'pr:ready' { [IO.File]::WriteAllText((Join-Path $folder 'ready'), 'ready') }
    default { throw 'Unexpected mocked GitHub call.' }
}
exit 0
