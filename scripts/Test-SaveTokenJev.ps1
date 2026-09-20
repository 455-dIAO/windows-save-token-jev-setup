[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$processHome = $env:CODEX_HOME
$userHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'User')
$machineHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Machine')
$codexHome = if (-not [string]::IsNullOrWhiteSpace($processHome)) {
    $processHome
} elseif (-not [string]::IsNullOrWhiteSpace($userHome)) {
    $userHome
} elseif (-not [string]::IsNullOrWhiteSpace($machineHome)) {
    $machineHome
} else {
    Join-Path $env:USERPROFILE '.codex'
}
$codexHome = [IO.Path]::GetFullPath($codexHome)
$hooksPath = Join-Path $codexHome 'hooks.json'
if (-not (Test-Path -LiteralPath $hooksPath)) { throw "Missing hooks.json: $hooksPath" }

$config = Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json
$hookMatches = @()
foreach ($eventName in @('PreCompact', 'SessionStart')) {
    foreach ($entry in @($config.hooks.$eventName)) {
        foreach ($hook in @($entry.hooks)) {
            if ([string]$hook.command -match 'node\s+"(?<cli>[^"]+dist[\\/]cli\.js)"\s+hook\s+codex') {
                $hookMatches += [pscustomobject]@{ Event=$eventName; Entry=$entry; Hook=$hook; Cli=$Matches.cli }
            }
        }
    }
}
if (@($hookMatches | Where-Object Event -eq 'PreCompact').Count -ne 1) { throw 'Expected exactly one save-token-jev PreCompact Hook.' }
if (@($hookMatches | Where-Object Event -eq 'SessionStart').Count -ne 1) { throw 'Expected exactly one save-token-jev SessionStart Hook.' }

$pre = @($hookMatches | Where-Object Event -eq 'PreCompact')[0]
$start = @($hookMatches | Where-Object Event -eq 'SessionStart')[0]
$pluginRoot = Split-Path (Split-Path $pre.Cli -Parent) -Parent
if (-not (Test-Path -LiteralPath $pre.Cli)) { throw "Missing CLI: $($pre.Cli)" }
if ($pre.Entry.matcher -ne 'manual|auto' -or [int]$pre.Hook.timeout -ne 120) { throw 'PreCompact matcher or timeout is incorrect.' }
if ($start.Entry.matcher -ne 'compact' -or [int]$start.Hook.timeout -ne 10 -or [int]$start.Hook.additionalContextLimit -ne 200000) {
    throw 'SessionStart matcher, timeout, or context limit is incorrect.'
}

$openRouter = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', 'User')
$typesafe = [Environment]::GetEnvironmentVariable('TYPESAFE_API_KEY', 'User')
$keyPresent = -not [string]::IsNullOrWhiteSpace($openRouter)
$keysMatch = $keyPresent -and ($openRouter -ceq $typesafe)
if (-not $keysMatch) { throw 'OPENROUTER_API_KEY and TYPESAFE_API_KEY are missing or do not match.' }

$expected = [ordered]@{
    JEV_BASE_URL = 'https://openrouter.ai/api/alpha/decisions'
    JEV_MODEL = '~typesafe/jev-latest'
    SAVE_TOKEN_JEV_KEEP_THRESHOLD = '0.5'
    SAVE_TOKEN_JEV_PRESERVE_RECENT = '6'
    SAVE_TOKEN_JEV_MIN_REDUCTION = '0.15'
    SAVE_TOKEN_JEV_DASHBOARD_PORT = '43127'
}
$environmentMatches = $true
foreach ($entry in $expected.GetEnumerator()) {
    if ([Environment]::GetEnvironmentVariable($entry.Key, 'User') -cne $entry.Value) {
        $environmentMatches = $false
    }
}
if (-not $environmentMatches) { throw 'One or more save-token-jev user environment settings are incorrect.' }

$node = (Get-Command node.exe -ErrorAction Stop).Source
$regression = Join-Path $PSScriptRoot 'verify-stale-sidecar.mjs'
& $node $regression $pluginRoot
if ($LASTEXITCODE -ne 0) { throw 'Stale-sidecar regression test failed.' }

[pscustomobject]@{
    JsonValid = $true
    CodexHome = $codexHome
    PluginRoot = $pluginRoot
    PreCompactConfigured = $true
    SessionStartConfigured = $true
    EnvironmentConfigured = $true
    KeysPresentAndMatch = $true
    StaleSidecarRegressionPassed = $true
    TrustStatus = 'Cannot be proven from JSON; inspect interactively with /hooks'
    RealCompactVerified = $false
} | Format-List
