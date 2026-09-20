[CmdletBinding()]
param(
    [string]$RepositoryUrl = 'https://github.com/IAmUnbounded/save-token-jev-clean.git',
    [string]$InstallPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-CodexHome {
    $processValue = $env:CODEX_HOME
    $userValue = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'User')
    $machineValue = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Machine')
    $configuredValue = if (-not [string]::IsNullOrWhiteSpace($userValue)) { $userValue } else { $machineValue }
    if (-not [string]::IsNullOrWhiteSpace($processValue) -and
        -not [string]::IsNullOrWhiteSpace($configuredValue) -and
        ([IO.Path]::GetFullPath($processValue) -ne [IO.Path]::GetFullPath($configuredValue))) {
        throw 'Process CODEX_HOME differs from the persisted CODEX_HOME. Restart from the intended environment before installing.'
    }
    $selected = if (-not [string]::IsNullOrWhiteSpace($processValue)) {
        $processValue
    } elseif (-not [string]::IsNullOrWhiteSpace($userValue)) {
        $userValue
    } elseif (-not [string]::IsNullOrWhiteSpace($machineValue)) {
        $machineValue
    } else {
        Join-Path $env:USERPROFILE '.codex'
    }
    return [IO.Path]::GetFullPath($selected)
}

function Resolve-WorkingNpm {
    $candidates = New-Object System.Collections.Generic.List[string]
    $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($npmCommand) { $candidates.Add($npmCommand.Source) }
    $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($nodeCommand) { $candidates.Add((Join-Path (Split-Path $nodeCommand.Source -Parent) 'npm.cmd')) }
    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'nodejs\npm.cmd')) }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        & $candidate --version *> $null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    throw 'A working npm.cmd was not found.'
}

function Invoke-Checked([string]$Executable, [string[]]$Arguments, [string]$Label) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

function Test-SaveTokenPackage([string]$Path) {
    $packagePath = Join-Path $Path 'package.json'
    if (-not (Test-Path -LiteralPath $packagePath)) { return $false }
    try {
        return ((Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json).name -eq 'save-token-jev')
    } catch {
        return $false
    }
}

function Copy-IfPresent([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Source) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    }
}

$codexHome = Resolve-CodexHome
$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop)) {
    throw 'Windows did not return the current user Desktop path.'
}

$openRouterKey = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', 'User')
if ([string]::IsNullOrWhiteSpace($openRouterKey)) {
    throw 'OPENROUTER_API_KEY is missing from Windows user environment. Run Set-OpenRouterKey.ps1 interactively first.'
}

$node = Get-Command node.exe -ErrorAction Stop
$nodeVersion = (& $node.Source --version).Trim()
if ($nodeVersion -notmatch '^v(?<major>\d+)' -or [int]$Matches.major -lt 20) {
    throw "Node.js 20 or newer is required; found $nodeVersion."
}
$npm = Resolve-WorkingNpm
$git = Get-Command git.exe -ErrorAction Stop

$preferredExisting = Join-Path $codexHome 'plugins\local\save-token-jev'
$desktopTarget = Join-Path $desktop 'save-token-jev'
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    if (Test-SaveTokenPackage $preferredExisting) {
        $InstallPath = $preferredExisting
    } elseif (Test-SaveTokenPackage $desktopTarget) {
        $InstallPath = $desktopTarget
    } else {
        $InstallPath = $desktopTarget
    }
}
$target = [IO.Path]::GetFullPath($InstallPath)

if (Test-Path -LiteralPath $target) {
    $hasItems = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction Stop).Count -gt 0
    if ($hasItems -and -not (Test-SaveTokenPackage $target)) {
        throw "Target directory exists and is not a recognized save-token-jev installation: $target"
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $codexHome "backups\save-token-jev-$stamp"
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

Copy-IfPresent (Join-Path $codexHome 'hooks.json') $backupRoot
[IO.File]::WriteAllLines((Join-Path $backupRoot 'environment-variable-names.txt'), @(
    'OPENROUTER_API_KEY (value intentionally not backed up)',
    'TYPESAFE_API_KEY (value intentionally not backed up)',
    'JEV_BASE_URL',
    'JEV_MODEL',
    'SAVE_TOKEN_JEV_KEEP_THRESHOLD',
    'SAVE_TOKEN_JEV_PRESERVE_RECENT',
    'SAVE_TOKEN_JEV_MIN_REDUCTION',
    'SAVE_TOKEN_JEV_DASHBOARD_PORT'
))

if (Test-SaveTokenPackage $target) {
    $pluginBackup = Join-Path $backupRoot 'plugin'
    New-Item -ItemType Directory -Force -Path $pluginBackup | Out-Null
    foreach ($relative in @('package.json', 'package-lock.json', 'hooks', 'src', 'tests', '.codex-plugin', 'dist')) {
        Copy-IfPresent (Join-Path $target $relative) $pluginBackup
    }
}

$staging = Join-Path ([IO.Path]::GetTempPath()) ("save-token-jev-stage-" + [Guid]::NewGuid().ToString('N'))
try {
    Invoke-Checked $git.Source @('clone', '--depth', '1', $RepositoryUrl, $staging) 'git clone'

    $sourcePath = Join-Path $staging 'src\integrations\codex.ts'
    $source = [IO.File]::ReadAllText($sourcePath)
    $guard = 'await rm(path, { force: true });'
    if (-not $source.Contains($guard)) {
        $oldImport = "import { appendFile, mkdir, readFile, rename, writeFile } from 'node:fs/promises';"
        $newImport = "import { appendFile, mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';"
        if (-not $source.Contains($oldImport)) {
            throw 'Upstream Codex integration import changed; stale-sidecar guard could not be applied safely.'
        }
        $source = $source.Replace($oldImport, $newImport)
        $anchor = "  if (input.hook_event_name === 'PreCompact') {"
        if (-not $source.Contains($anchor)) {
            throw 'Upstream PreCompact implementation changed; stale-sidecar guard could not be applied safely.'
        }
        $source = $source.Replace($anchor, "$anchor`r`n    $guard")
        [IO.File]::WriteAllText($sourcePath, $source, (New-Object Text.UTF8Encoding($false)))
    }

    Push-Location $staging
    try {
        Invoke-Checked $npm @('install') 'npm install'
        Invoke-Checked $npm @('run', 'typecheck') 'npm run typecheck'
        Invoke-Checked $npm @('test') 'npm test'
        Invoke-Checked $npm @('run', 'build') 'npm run build'
    } finally {
        Pop-Location
    }

    foreach ($required in @('hooks\hooks.json', 'dist\cli.js', 'dist\integrations\codex.js')) {
        if (-not (Test-Path -LiteralPath (Join-Path $staging $required))) {
            throw "Build output is missing: $required"
        }
    }

    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Get-ChildItem -LiteralPath $staging -Force |
        Where-Object { $_.Name -notin @('.git', 'node_modules', '.env') } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force }

    $commit = (& $git.Source -C $staging rev-parse HEAD).Trim()
    $manifest = [ordered]@{
        repository = $RepositoryUrl
        commit = $commit
        installedAt = (Get-Date).ToUniversalTime().ToString('o')
        staleSidecarGuard = $true
    } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $target '.save-token-jev-install.json'), $manifest, (New-Object Text.UTF8Encoding($false)))
} finally {
    if (Test-Path -LiteralPath $staging) {
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $stagingFull = [IO.Path]::GetFullPath($staging)
        $expectedPrefix = $tempRoot + [IO.Path]::DirectorySeparatorChar + 'save-token-jev-stage-'
        if (-not $stagingFull.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unexpected staging path: $stagingFull"
        }
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}

[Environment]::SetEnvironmentVariable('TYPESAFE_API_KEY', $openRouterKey, 'User')
$settings = [ordered]@{
    JEV_BASE_URL = 'https://openrouter.ai/api/alpha/decisions'
    JEV_MODEL = '~typesafe/jev-latest'
    SAVE_TOKEN_JEV_KEEP_THRESHOLD = '0.5'
    SAVE_TOKEN_JEV_PRESERVE_RECENT = '6'
    SAVE_TOKEN_JEV_MIN_REDUCTION = '0.15'
    SAVE_TOKEN_JEV_DASHBOARD_PORT = '43127'
}
foreach ($entry in $settings.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'User')
    Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value
}
$env:TYPESAFE_API_KEY = $openRouterKey

$hooksPath = Join-Path $codexHome 'hooks.json'
if (Test-Path -LiteralPath $hooksPath) {
    $hooksConfig = Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
    $hooksConfig = [pscustomobject]@{}
}
if (-not $hooksConfig.PSObject.Properties['hooks']) {
    $hooksConfig | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
}

$template = Get-Content -LiteralPath (Join-Path $target 'hooks\hooks.json') -Raw | ConvertFrom-Json
$commandRoot = $target.Replace('\', '/')
foreach ($eventName in @('PreCompact', 'SessionStart')) {
    $desiredJson = (@($template.hooks.$eventName)[0] | ConvertTo-Json -Depth 30).Replace('${PLUGIN_ROOT}', $commandRoot)
    $desired = $desiredJson | ConvertFrom-Json
    $desiredCommand = [string](@($desired.hooks)[0].command)
    $existing = if ($hooksConfig.hooks.PSObject.Properties[$eventName]) { @($hooksConfig.hooks.$eventName) } else { @() }
    $kept = @($existing | Where-Object {
        $commands = @($_.hooks | ForEach-Object { [string]$_.command })
        -not (($commands -contains $desiredCommand) -or ($commands -match 'save-token-jev.*dist[\\/]+cli\.js.*hook codex'))
    })
    $merged = @($kept + $desired)
    if ($hooksConfig.hooks.PSObject.Properties[$eventName]) {
        $hooksConfig.hooks.$eventName = $merged
    } else {
        $hooksConfig.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue $merged
    }
}

$json = $hooksConfig | ConvertTo-Json -Depth 50
[IO.File]::WriteAllText($hooksPath, $json, (New-Object Text.UTF8Encoding($false)))
$null = Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json
if ((Get-Content -LiteralPath $hooksPath -Raw).Contains('${PLUGIN_ROOT}')) {
    throw 'hooks.json still contains a PLUGIN_ROOT placeholder.'
}

$regressionScript = Join-Path $PSScriptRoot 'verify-stale-sidecar.mjs'
Invoke-Checked $node.Source @($regressionScript, $target) 'stale-sidecar regression test'

$doctorOutput = (& $node.Source (Join-Path $target 'dist\cli.js') doctor 2>&1 | Out-String)
$doctorExit = $LASTEXITCODE
if ($doctorOutput.Contains($openRouterKey)) {
    throw 'The doctor command unexpectedly exposed the API key.'
}
if ($doctorExit -ne 0) {
    throw "save-token-jev doctor failed with exit code $doctorExit."
}

[pscustomobject]@{
    Configured = $true
    CodexHome = $codexHome
    Desktop = $desktop
    InstallPath = $target
    HooksPath = $hooksPath
    BackupPath = $backupRoot
    NodeVersion = $nodeVersion
    OpenRouterKeyPresent = $true
    TypesafeKeyMatches = $true
    StaleSidecarRegressionPassed = $true
    TrustStatus = 'Manual review required in Codex CLI /hooks'
    RealCompactVerified = $false
} | Format-List
