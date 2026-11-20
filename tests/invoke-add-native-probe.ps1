param([string]$Helper, [string]$Executable, [string]$Records, [string]$Temporary)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$encoding = New-Object Text.UTF8Encoding($false, $true)
$temporary = $Temporary
$ghCommand = Get-Command $Executable -CommandType Application
$env:FACTORY_ADD_FIXTURE = $Records
$env:GH_DEBUG = 'api'
$previousDebug = $env:GH_DEBUG
$previousEncoding = [Console]::OutputEncoding
# Load the production functions without running the issue operation.
$tokens = $null; $errors = $null
$tree = [Management.Automation.Language.Parser]::ParseFile($Helper, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Cannot parse production issue helper.' }
foreach ($name in @('Quote-Argument','Gh')) {
    $definition = $tree.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false) | Where-Object Name -eq $name
    . ([scriptblock]::Create($definition.Extent.Text))
}
$arguments = @('', 'ordinary', 'space in value', '"quoted"', '\', '\\', 'trailing space \', '\"', '\\"', '" --hostname attacker.invalid', [string][char]0xe9, '{{.nameWithOwner}}{{"\n"}}{{.url}}{{"\n"}}')
[IO.File]::WriteAllText((Join-Path $Records 'mode'), 'quote-probe', $encoding)
$writer = New-Object IO.BinaryWriter([IO.File]::Create((Join-Path $Records 'expected.argv')), $encoding)
try { $writer.Write([int]$arguments.Count); foreach ($argument in $arguments) { $writer.Write([string]$argument) } } finally { $writer.Dispose() }
$response = Gh $arguments
if ($response -cne 'exact executable arguments') { throw 'Executable stdout and stderr were mixed.' }
if ($env:GH_DEBUG -cne $previousDebug -or [Console]::OutputEncoding.CodePage -ne $previousEncoding.CodePage) { throw 'GitHub environment or encoding was not restored.' }
$failed = $false
try { $null = Gh @('unexpected argument') } catch { $failed = $true }
if (-not $failed -or $env:GH_DEBUG -cne $previousDebug -or [Console]::OutputEncoding.CodePage -ne $previousEncoding.CodePage) { throw 'Failure did not restore GitHub environment and encoding.' }
# The same executable rejects the predecessor native binder on Windows PowerShell 5.1.
$env:GH_DEBUG = ''
$ErrorActionPreference = 'Continue'
$null = & $Executable @arguments 2> (Join-Path $Temporary 'legacy-stderr')
$legacyCode = $LASTEXITCODE
if ($legacyCode -ne 92) { throw "Expected predecessor binder corruption, got exit $legacyCode." }
[Console]::Out.WriteLine('PASS exact empty, Unicode, quote, backslash and trailing-backslash arguments; prior binder rejected with exit 92; environment restored.')
