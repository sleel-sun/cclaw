param(
    [Parameter(Mandatory = $false)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [switch]$PromptForApiKey,

    [Parameter(Mandatory = $false)]
    [string]$BaseUrl = "https://cloudmanager.cn/v1",

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$env:USERPROFILE\.cclaw-assist\cclaw-assist.json",

    [Parameter(Mandatory = $false)]
    [string]$AgentDir = "$env:USERPROFILE\.cclaw-assist\agents\main\agent",

    [Parameter(Mandatory = $false)]
    [string]$OverlayBatchPath = "$env:USERPROFILE\.cclaw-assist\tools\cclaw-grok-config.batch.json",

    [Parameter(Mandatory = $false)]
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    if (Test-Path -LiteralPath $Path) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        Copy-Item -LiteralPath $Path -Destination "$Path.bak.third-party-models.$stamp" -Force
    }
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Ensure-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name
    )
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        $value = [pscustomobject]@{}
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $value
        return $value
    }
    return $prop.Value
}

function Set-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    } else {
        $prop.Value = $Value
    }
}

function Get-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name
    )
    if ($null -eq $Object) {
        return $null
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $null
    }
    return $prop.Value
}

function Convert-SecureStringToPlainText {
    param([securestring]$Value)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Read-ApiKeyFromPrompt {
    $secure = Read-Host -Prompt "Enter Grok API key" -AsSecureString
    $plain = Convert-SecureStringToPlainText -Value $secure
    if ([string]::IsNullOrWhiteSpace($plain)) {
        throw "API key cannot be empty."
    }
    return $plain.Trim()
}

function New-GrokProvider {
    param(
        [string]$Key,
        [string]$Url
    )
    return [pscustomobject]@{
        baseUrl        = $Url
        api            = "openai-completions"
        apiKey         = $Key
        timeoutSeconds = 300
        models         = @(
            [pscustomobject]@{
                id            = "grok-build-console"
                name          = "grok-build-console"
                api           = "openai-completions"
                reasoning     = $false
                input         = @("text")
                cost          = [pscustomobject]@{
                    input      = 0
                    output     = 0
                    cacheRead  = 0
                    cacheWrite = 0
                }
                contextWindow = 200000
                maxTokens     = 8192
            },
            [pscustomobject]@{
                id            = "grok-4.20-multi-agent-xhigh"
                name          = "grok-4.20-multi-agent-xhigh"
                api           = "openai-completions"
                reasoning     = $false
                input         = @("text")
                cost          = [pscustomobject]@{
                    input      = 0
                    output     = 0
                    cacheRead  = 0
                    cacheWrite = 0
                }
                contextWindow = 200000
                maxTokens     = 8192
            },
            [pscustomobject]@{
                id            = "grok-composer-2.5"
                name          = "grok-composer-2.5"
                api           = "openai-completions"
                reasoning     = $false
                input         = @("text")
                cost          = [pscustomobject]@{
                    input      = 0
                    output     = 0
                    cacheRead  = 0
                    cacheWrite = 0
                }
                contextWindow = 200000
                maxTokens     = 8192
            }
        )
    }
}

function Resolve-GrokApiKey {
    param(
        [string]$ExplicitKey,
        [object]$Config,
        [object]$AuthProfiles,
        [switch]$ForcePrompt
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitKey)) {
        return $ExplicitKey.Trim()
    }
    if ($ForcePrompt) {
        return Read-ApiKeyFromPrompt
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GROK_API_KEY)) {
        return $env:GROK_API_KEY.Trim()
    }

    $configProviders = Get-ObjectProperty -Object (Get-ObjectProperty -Object $Config -Name "models") -Name "providers"
    $configGrok = Get-ObjectProperty -Object $configProviders -Name "grok"
    $configKey = Get-ObjectProperty -Object $configGrok -Name "apiKey"
    if (-not [string]::IsNullOrWhiteSpace([string]$configKey)) {
        return [string]$configKey
    }

    $profiles = Get-ObjectProperty -Object $AuthProfiles -Name "profiles"
    $manual = Get-ObjectProperty -Object $profiles -Name "grok:manual"
    $authKey = Get-ObjectProperty -Object $manual -Name "key"
    if (-not [string]::IsNullOrWhiteSpace([string]$authKey)) {
        return [string]$authKey
    }

    Write-Output "No Grok API key was found in -ApiKey, GROK_API_KEY, config, or auth profile."
    return Read-ApiKeyFromPrompt
}

function Verify-GrokAccess {
    param(
        [string]$Key,
        [string]$Url
    )
    $node = Join-Path $env:LOCALAPPDATA "CClaw\bin\node.exe"
    if (-not (Test-Path -LiteralPath $node)) {
        Write-Warning "CClaw Node runtime not found; skipped remote verification."
        return
    }

    $previousHttpProxy = $env:HTTP_PROXY
    $previousHttpsProxy = $env:HTTPS_PROXY
    $previousAllProxy = $env:ALL_PROXY
    try {
        $env:HTTP_PROXY = ""
        $env:HTTPS_PROXY = ""
        $env:ALL_PROXY = ""
        $code = @"
const key = process.env.GROK_API_KEY;
const baseUrl = process.env.GROK_BASE_URL || 'https://cloudmanager.cn/v1';
fetch(baseUrl.replace(/\/$/, '') + '/chat/completions', {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    model: 'grok-build-console',
    messages: [{ role: 'user', content: 'Reply with exactly OK' }],
    max_tokens: 8,
    stream: false
  })
}).then(async (response) => {
  const text = await response.text();
  console.log('status=' + response.status);
  console.log(text.slice(0, 800));
  process.exit(response.ok ? 0 : 1);
}).catch((error) => {
  console.error(error && error.message ? error.message : String(error));
  process.exit(1);
});
"@
        $env:GROK_API_KEY = $Key
        $env:GROK_BASE_URL = $Url
        & $node -e $code
        if ($LASTEXITCODE -ne 0) {
            throw "Grok verification failed."
        }
    } finally {
        $env:HTTP_PROXY = $previousHttpProxy
        $env:HTTPS_PROXY = $previousHttpsProxy
        $env:ALL_PROXY = $previousAllProxy
        Remove-Item Env:GROK_API_KEY -ErrorAction SilentlyContinue
        Remove-Item Env:GROK_BASE_URL -ErrorAction SilentlyContinue
    }
}

$authProfilesPath = Join-Path $AgentDir "auth-profiles.json"
$authStatePath = Join-Path $AgentDir "auth-state.json"
$modelsPath = Join-Path $AgentDir "models.json"

$config = Read-JsonFile -Path $ConfigPath
if ($null -eq $config) {
    $config = [pscustomobject]@{}
}
$authProfiles = Read-JsonFile -Path $authProfilesPath
if ($null -eq $authProfiles) {
    $authProfiles = [pscustomobject]@{ version = 1; profiles = [pscustomobject]@{} }
}

$resolvedKey = Resolve-GrokApiKey -ExplicitKey $ApiKey -Config $config -AuthProfiles $authProfiles -ForcePrompt:$PromptForApiKey
$provider = New-GrokProvider -Key $resolvedKey -Url $BaseUrl

$models = Ensure-ObjectProperty -Object $config -Name "models"
Set-ObjectProperty -Object $models -Name "mode" -Value "merge"
$providers = Ensure-ObjectProperty -Object $models -Name "providers"
Set-ObjectProperty -Object $providers -Name "grok" -Value $provider

$agents = Ensure-ObjectProperty -Object $config -Name "agents"
$defaults = Ensure-ObjectProperty -Object $agents -Name "defaults"
$pickerModels = Ensure-ObjectProperty -Object $defaults -Name "models"
Set-ObjectProperty -Object $pickerModels -Name "grok/grok-build-console" -Value ([pscustomobject]@{ alias = "grok-build-console" })
Set-ObjectProperty -Object $pickerModels -Name "grok/grok-4.20-multi-agent-xhigh" -Value ([pscustomobject]@{ alias = "grok-4.20-multi-agent-xhigh" })
Set-ObjectProperty -Object $pickerModels -Name "grok/grok-composer-2.5" -Value ([pscustomobject]@{ alias = "grok-composer-2.5" })

$meta = Ensure-ObjectProperty -Object $config -Name "meta"
Set-ObjectProperty -Object $meta -Name "lastTouchedAt" -Value ((Get-Date).ToUniversalTime().ToString("o"))

$profiles = Ensure-ObjectProperty -Object $authProfiles -Name "profiles"
Set-ObjectProperty -Object $profiles -Name "grok:manual" -Value ([pscustomobject]@{
        type     = "api_key"
        provider = "grok"
        key      = $resolvedKey
    })

$agentModels = Read-JsonFile -Path $modelsPath
if ($null -eq $agentModels) {
    $agentModels = [pscustomobject]@{ providers = [pscustomobject]@{} }
}
$agentProviders = Ensure-ObjectProperty -Object $agentModels -Name "providers"
Set-ObjectProperty -Object $agentProviders -Name "grok" -Value $provider

$authState = Read-JsonFile -Path $authStatePath
if ($null -eq $authState) {
    $authState = [pscustomobject]@{ version = 1; usageStats = [pscustomobject]@{} }
}
Set-ObjectProperty -Object $authState -Name "usageStats" -Value ([pscustomobject]@{})

$overlay = @(
    [pscustomobject]@{
        path  = "models.providers"
        value = [pscustomobject]@{
            grok = $provider
        }
    },
    [pscustomobject]@{
        path  = "agents.defaults.models"
        value = [pscustomobject]@{
            "grok/grok-build-console"             = [pscustomobject]@{ alias = "grok-build-console" }
            "grok/grok-4.20-multi-agent-xhigh"    = [pscustomobject]@{ alias = "grok-4.20-multi-agent-xhigh" }
            "grok/grok-composer-2.5"              = [pscustomobject]@{ alias = "grok-composer-2.5" }
        }
    }
)

Write-JsonFile -Path $ConfigPath -Value $config
Write-JsonFile -Path $authProfilesPath -Value $authProfiles
Write-JsonFile -Path $modelsPath -Value $agentModels
Write-JsonFile -Path $authStatePath -Value $authState
Write-JsonFile -Path $OverlayBatchPath -Value $overlay

if (-not $SkipVerify) {
    Verify-GrokAccess -Key $resolvedKey -Url $BaseUrl
}

Write-Output "third-party-models: Grok provider configuration applied."
