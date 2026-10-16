[CmdletBinding()]
param(
    [ValidateSet('cn', 'ov')]
    [string]$Region,
    [string]$ToolDirectory = 'E:\Tools\TripoAI\cli-0.7.0',
    [string]$ProfileDirectory = 'E:\Tools\TripoAI\profile'
)

# Run manually in a terminal: the official CLI masks the pasted key and saves
# it in the same private profile directory used by the Codex MCP entry.
$ErrorActionPreference = 'Stop'
$nodeExecutable = (Get-Command node.exe -ErrorAction Stop).Source
$cliPath = Join-Path $ToolDirectory 'node_modules\tripo-cli\dist\cli.js'
if (-not (Test-Path -LiteralPath $cliPath -PathType Leaf)) {
    throw "Tripo CLI is not installed at $cliPath"
}

$previousProfile = [Environment]::GetEnvironmentVariable('TRIPO_HOME', 'Process')
$previousAnalytics = [Environment]::GetEnvironmentVariable('TRIPO_ANALYTICS_ENABLED', 'Process')
try {
    $env:TRIPO_HOME = $ProfileDirectory
    $env:TRIPO_ANALYTICS_ENABLED = '0'
    $loginArguments = @($cliPath, 'login', '--paste')
    if ($Region) {
        $loginArguments += @('--region', $Region)
    }
    & $nodeExecutable @loginArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Tripo login exited with code $LASTEXITCODE"
    }
}
finally {
    [Environment]::SetEnvironmentVariable('TRIPO_HOME', $previousProfile, 'Process')
    [Environment]::SetEnvironmentVariable('TRIPO_ANALYTICS_ENABLED', $previousAnalytics, 'Process')
}
