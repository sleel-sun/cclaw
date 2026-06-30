param(
    [Parameter(Mandatory = $false)]
    [string]$BaseUrl = "https://cloudmanager.cn/v1",

    [Parameter(Mandatory = $false)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [string]$UserProfilePath = $env:USERPROFILE,

    [Parameter(Mandatory = $false)]
    [switch]$StartWatcher
)

$ErrorActionPreference = "Stop"

$assistDir = Join-Path $UserProfilePath ".cclaw-assist"
$providerScript = Join-Path $assistDir "plugins\third-party-models\scripts\apply-cclaw-provider.ps1"
$watcherScript = Join-Path $assistDir "tools\watch-cclaw-model-overlay.ps1"
$providerBatch = Join-Path $assistDir "tools\cclaw-provider-grok.batch.json"
$legacyBatch = Join-Path $assistDir "tools\cclaw-grok-config.batch.json"
$configPath = Join-Path $assistDir "cclaw-assist.json"
$agentDir = Join-Path $assistDir "agents\main\agent"

if (-not (Test-Path -LiteralPath $providerScript)) {
    throw "Missing provider script: $providerScript"
}

$modelIds = @(
    "grok-build-console",
    "grok-4.20-multi-agent-xhigh",
    "grok-composer-2.5"
)

$providerArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $providerScript,
    "-ProviderId", "grok",
    "-BaseUrl", $BaseUrl,
    "-ModelIds", ($modelIds -join ",")
) + @(
    "-Api", "openai-completions",
    "-InputTypes", "text",
    "-ContextWindow", "128000",
    "-MaxTokens", "8192",
    "-ConfigPath", $configPath,
    "-AgentDir", $agentDir,
    "-OverlayBatchPath", $providerBatch
)

if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    $providerArgs += @("-ApiKey", $ApiKey)
}

& powershell @providerArgs
if ($LASTEXITCODE -ne 0) {
    throw "apply-cclaw-provider.ps1 failed with exit code $LASTEXITCODE"
}

if (Test-Path -LiteralPath $providerBatch) {
    Copy-Item -LiteralPath $providerBatch -Destination $legacyBatch -Force
}

if (Test-Path -LiteralPath $watcherScript) {
    $text = Get-Content -LiteralPath $watcherScript -Raw
    $text = $text -replace [regex]::Escape('$env:USERPROFILE\.cclaw-assist\tools\cclaw-grok-config.batch.json'), '$env:USERPROFILE\.cclaw-assist\tools\cclaw-provider-grok.batch.json'
    Set-Content -LiteralPath $watcherScript -Value $text -Encoding UTF8
}

$openClawCmd = Join-Path $env:LOCALAPPDATA "CClaw\bin\openclaw.cmd"
if (Test-Path -LiteralPath $openClawCmd) {
    $previousStateDir = $env:OPENCLAW_STATE_DIR
    $previousConfigPath = $env:OPENCLAW_CONFIG_PATH
    $previousAgentDir = $env:OPENCLAW_AGENT_DIR
    try {
        $env:OPENCLAW_STATE_DIR = $assistDir
        $env:OPENCLAW_CONFIG_PATH = $configPath
        $env:OPENCLAW_AGENT_DIR = $agentDir
        & $openClawCmd config set --batch-file $providerBatch --merge
    } finally {
        $env:OPENCLAW_STATE_DIR = $previousStateDir
        $env:OPENCLAW_CONFIG_PATH = $previousConfigPath
        $env:OPENCLAW_AGENT_DIR = $previousAgentDir
    }
}

if ($StartWatcher -and (Test-Path -LiteralPath $watcherScript)) {
    Start-Process -FilePath powershell.exe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $watcherScript,
        "-Apply",
        "-RequireClientRunning",
        "-BatchFile", $providerBatch,
        "-IntervalSeconds", "10",
        "-PostApplyPauseSeconds", "25"
    ) -WindowStyle Hidden
}

Write-Output "Grok composer hotfix applied. Models: $($modelIds -join ', ')"
