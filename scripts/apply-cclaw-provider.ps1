param(
    [Parameter(Mandatory = $true)]
    [string]$ProviderId,

    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,

    [Parameter(Mandatory = $false)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [switch]$PromptForApiKey,

    [Parameter(Mandatory = $true)]
    [string[]]$ModelIds,

    [Parameter(Mandatory = $false)]
    [string[]]$ModelNames,

    [Parameter(Mandatory = $false)]
    [string]$Api = "openai-completions",

    [Parameter(Mandatory = $false)]
    [string[]]$InputTypes = @("text"),

    [Parameter(Mandatory = $false)]
    [int]$ContextWindow = 128000,

    [Parameter(Mandatory = $false)]
    [int]$MaxTokens = 8192,

    [Parameter(Mandatory = $false)]
    [bool]$ToolOptimizedCompat = $true,

    [Parameter(Mandatory = $false)]
    [bool]$SupportsTools = $true,

    [Parameter(Mandatory = $false)]
    [bool]$SupportsStore = $false,

    [Parameter(Mandatory = $false)]
    [bool]$SupportsDeveloperRole = $false,

    [Parameter(Mandatory = $false)]
    [bool]$SupportsReasoningEffort = $false,

    [Parameter(Mandatory = $false)]
    [bool]$SupportsUsageInStreaming = $false,

    [Parameter(Mandatory = $false)]
    [bool]$SupportsStrictMode = $false,

    [Parameter(Mandatory = $false)]
    [bool]$RequiresStringContent = $false,

    [Parameter(Mandatory = $false)]
    [bool]$RequiresToolResultName = $false,

    [Parameter(Mandatory = $false)]
    [bool]$RequiresAssistantAfterToolResult = $false,

    [Parameter(Mandatory = $false)]
    [bool]$RequiresThinkingAsText = $false,

    [Parameter(Mandatory = $false)]
    [bool]$RequiresMistralToolIds = $false,

    [Parameter(Mandatory = $false)]
    [bool]$RequiresOpenAiAnthropicToolPayload = $false,

    [Parameter(Mandatory = $false)]
    [ValidateSet("max_tokens", "max_completion_tokens")]
    [string]$MaxTokensField = "max_tokens",

    [Parameter(Mandatory = $false)]
    [string[]]$UnsupportedToolSchemaKeywords = @("minLength", "maxLength", "minItems", "maxItems", "minContains", "maxContains"),

    [Parameter(Mandatory = $false)]
    [string]$HeadersJson,

    [Parameter(Mandatory = $false)]
    [string]$AuthEnvVar,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$env:USERPROFILE\.cclaw-assist\cclaw-assist.json",

    [Parameter(Mandatory = $false)]
    [string]$AgentDir = "$env:USERPROFILE\.cclaw-assist\agents\main\agent",

    [Parameter(Mandatory = $false)]
    [string]$OverlayBatchPath,

    [Parameter(Mandatory = $false)]
    [switch]$AllowMissingApiKey,

    [Parameter(Mandatory = $false)]
    [switch]$Verify
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

function Normalize-ProviderId {
    param([string]$Value)
    $normalized = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9_.-]+', '-'
    $normalized = $normalized.Trim('-')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "ProviderId is invalid."
    }
    return $normalized
}

function Get-ProviderEnvName {
    param([string]$Value)
    return (($Value.ToUpperInvariant() -replace '[^A-Z0-9]+', '_').Trim('_') + "_API_KEY")
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
    param([string]$Provider)
    $secure = Read-Host -Prompt "Enter API key for provider '$Provider'" -AsSecureString
    $plain = Convert-SecureStringToPlainText -Value $secure
    if ([string]::IsNullOrWhiteSpace($plain)) {
        throw "API key cannot be empty."
    }
    return $plain.Trim()
}

function Expand-StringList {
    param([string[]]$Values)
    $result = @()
    foreach ($value in @($Values)) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }
        foreach ($part in ($value -split ',')) {
            $trimmed = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $result += $trimmed
            }
        }
    }
    return @($result)
}

function Resolve-ApiKey {
    param(
        [string]$ExplicitKey,
        [string]$Provider,
        [string]$EnvVar,
        [object]$Config,
        [object]$AuthProfiles,
        [switch]$ForcePrompt,
        [switch]$AllowMissing
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitKey)) {
        return $ExplicitKey.Trim()
    }
    if ($ForcePrompt) {
        return Read-ApiKeyFromPrompt -Provider $Provider
    }

    $candidateEnvVars = @()
    if (-not [string]::IsNullOrWhiteSpace($EnvVar)) {
        $candidateEnvVars += $EnvVar.Trim()
    }
    $candidateEnvVars += (Get-ProviderEnvName -Value $Provider)

    foreach ($name in $candidateEnvVars) {
        $value = [Environment]::GetEnvironmentVariable($name, "Process")
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = [Environment]::GetEnvironmentVariable($name, "User")
        }
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = [Environment]::GetEnvironmentVariable($name, "Machine")
        }
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    }

    $configProviders = Get-ObjectProperty -Object (Get-ObjectProperty -Object $Config -Name "models") -Name "providers"
    $configProvider = Get-ObjectProperty -Object $configProviders -Name $Provider
    $configKey = Get-ObjectProperty -Object $configProvider -Name "apiKey"
    if (-not [string]::IsNullOrWhiteSpace([string]$configKey)) {
        return [string]$configKey
    }

    $profiles = Get-ObjectProperty -Object $AuthProfiles -Name "profiles"
    $manual = Get-ObjectProperty -Object $profiles -Name "$Provider`:manual"
    $authKey = Get-ObjectProperty -Object $manual -Name "key"
    if (-not [string]::IsNullOrWhiteSpace([string]$authKey)) {
        return [string]$authKey
    }

    if ($AllowMissing) {
        return $null
    }

    Write-Output "No API key was found in -ApiKey, environment variables, config, or auth profile."
    return Read-ApiKeyFromPrompt -Provider $Provider
}

function Parse-Headers {
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) {
        return $null
    }
    $parsed = $Json | ConvertFrom-Json
    if ($null -eq $parsed) {
        return $null
    }
    return $parsed
}

function New-ProviderModel {
    param(
        [string]$Id,
        [string]$Name,
        [string]$ModelApi,
        [string[]]$Inputs,
        [int]$Window,
        [int]$Tokens,
        [object]$Compat
    )
    $model = [pscustomobject]@{
        id            = $Id
        name          = $Name
        api           = $ModelApi
        reasoning     = $false
        input         = @($Inputs)
        cost          = [pscustomobject]@{
            input      = 0
            output     = 0
            cacheRead  = 0
            cacheWrite = 0
        }
        contextWindow = $Window
        maxTokens     = $Tokens
    }
    if ($null -ne $Compat) {
        Set-ObjectProperty -Object $model -Name "compat" -Value $Compat
    }
    return $model
}

function New-ToolOptimizedCompat {
    param(
        [bool]$Tools,
        [bool]$Store,
        [bool]$DeveloperRole,
        [bool]$ReasoningEffort,
        [bool]$UsageInStreaming,
        [bool]$StrictMode,
        [string]$TokensField,
        [bool]$StringContent,
        [bool]$ToolResultName,
        [bool]$AssistantAfterToolResult,
        [bool]$ThinkingAsText,
        [bool]$MistralToolIds,
        [bool]$OpenAiAnthropicToolPayload,
        [string[]]$UnsupportedSchemaKeywords
    )
    return [pscustomobject]@{
        supportsTools                       = $Tools
        supportsStore                       = $Store
        supportsDeveloperRole               = $DeveloperRole
        supportsReasoningEffort             = $ReasoningEffort
        supportsUsageInStreaming            = $UsageInStreaming
        supportsStrictMode                  = $StrictMode
        requiresStringContent               = $StringContent
        requiresToolResultName              = $ToolResultName
        requiresAssistantAfterToolResult    = $AssistantAfterToolResult
        requiresThinkingAsText              = $ThinkingAsText
        requiresMistralToolIds              = $MistralToolIds
        requiresOpenAiAnthropicToolPayload  = $OpenAiAnthropicToolPayload
        unsupportedToolSchemaKeywords       = @($UnsupportedSchemaKeywords | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
        maxTokensField                      = $TokensField
    }
}

function New-ProviderConfig {
    param(
        [string]$Url,
        [string]$ProviderApi,
        [string]$Key,
        [object]$Headers,
        [object[]]$Models
    )
    $provider = [pscustomobject]@{
        baseUrl        = $Url.TrimEnd('/')
        api            = $ProviderApi
        timeoutSeconds = 300
        models         = @($Models)
    }
    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        Set-ObjectProperty -Object $provider -Name "apiKey" -Value $Key
    }
    if ($null -ne $Headers) {
        Set-ObjectProperty -Object $provider -Name "headers" -Value $Headers
    }
    return $provider
}

function Verify-ProviderAccess {
    param(
        [string]$Url,
        [string]$Key,
        [string]$Model
    )
    if ([string]::IsNullOrWhiteSpace($Key)) {
        throw "Verification requires an API key."
    }

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
        $env:CUSTOM_PROVIDER_API_KEY = $Key
        $env:CUSTOM_PROVIDER_BASE_URL = $Url
        $env:CUSTOM_PROVIDER_MODEL = $Model
        $code = @"
const key = process.env.CUSTOM_PROVIDER_API_KEY;
const baseUrl = process.env.CUSTOM_PROVIDER_BASE_URL;
const model = process.env.CUSTOM_PROVIDER_MODEL;
fetch(baseUrl.replace(/\/$/, '') + '/chat/completions', {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    model,
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
        & $node -e $code
        if ($LASTEXITCODE -ne 0) {
            throw "Provider verification failed."
        }
    } finally {
        $env:HTTP_PROXY = $previousHttpProxy
        $env:HTTPS_PROXY = $previousHttpsProxy
        $env:ALL_PROXY = $previousAllProxy
        Remove-Item Env:CUSTOM_PROVIDER_API_KEY -ErrorAction SilentlyContinue
        Remove-Item Env:CUSTOM_PROVIDER_BASE_URL -ErrorAction SilentlyContinue
        Remove-Item Env:CUSTOM_PROVIDER_MODEL -ErrorAction SilentlyContinue
    }
}

$provider = Normalize-ProviderId -Value $ProviderId
$modelIds = Expand-StringList -Values $ModelIds
$modelNames = Expand-StringList -Values $ModelNames
$inputTypes = Expand-StringList -Values $InputTypes
if ($inputTypes.Count -eq 0) {
    $inputTypes = @("text")
}
if ($modelIds.Count -eq 0) {
    throw "At least one model ID is required."
}

if ([string]::IsNullOrWhiteSpace($OverlayBatchPath)) {
    $safeProvider = $provider -replace '[^a-z0-9_.-]+', '-'
    $OverlayBatchPath = "$env:USERPROFILE\.cclaw-assist\tools\cclaw-provider-$safeProvider.batch.json"
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

$resolvedKey = Resolve-ApiKey -ExplicitKey $ApiKey -Provider $provider -EnvVar $AuthEnvVar -Config $config -AuthProfiles $authProfiles -ForcePrompt:$PromptForApiKey -AllowMissing:$AllowMissingApiKey
$headers = Parse-Headers -Json $HeadersJson
$compat = $null
if ($ToolOptimizedCompat) {
    $compat = New-ToolOptimizedCompat `
        -Tools $SupportsTools `
        -Store $SupportsStore `
        -DeveloperRole $SupportsDeveloperRole `
        -ReasoningEffort $SupportsReasoningEffort `
        -UsageInStreaming $SupportsUsageInStreaming `
        -StrictMode $SupportsStrictMode `
        -TokensField $MaxTokensField `
        -StringContent $RequiresStringContent `
        -ToolResultName $RequiresToolResultName `
        -AssistantAfterToolResult $RequiresAssistantAfterToolResult `
        -ThinkingAsText $RequiresThinkingAsText `
        -MistralToolIds $RequiresMistralToolIds `
        -OpenAiAnthropicToolPayload $RequiresOpenAiAnthropicToolPayload `
        -UnsupportedSchemaKeywords $UnsupportedToolSchemaKeywords
}

$modelsList = @()
for ($i = 0; $i -lt $modelIds.Count; $i++) {
    $name = $modelIds[$i]
    if ($modelNames -and $modelNames.Count -gt $i -and -not [string]::IsNullOrWhiteSpace($modelNames[$i])) {
        $name = $modelNames[$i]
    }
    $modelsList += New-ProviderModel -Id $modelIds[$i] -Name $name -ModelApi $Api -Inputs $inputTypes -Window $ContextWindow -Tokens $MaxTokens -Compat $compat
}

$providerConfig = New-ProviderConfig -Url $BaseUrl -ProviderApi $Api -Key $resolvedKey -Headers $headers -Models $modelsList

$configModels = Ensure-ObjectProperty -Object $config -Name "models"
Set-ObjectProperty -Object $configModels -Name "mode" -Value "merge"
$configProviders = Ensure-ObjectProperty -Object $configModels -Name "providers"
Set-ObjectProperty -Object $configProviders -Name $provider -Value $providerConfig

$agents = Ensure-ObjectProperty -Object $config -Name "agents"
$defaults = Ensure-ObjectProperty -Object $agents -Name "defaults"
$pickerModels = Ensure-ObjectProperty -Object $defaults -Name "models"
$pickerValue = [pscustomobject]@{}
$desiredModelRefs = @($modelIds | ForEach-Object { "$provider/$_" })
foreach ($prop in @($pickerModels.PSObject.Properties)) {
    if ($prop.Name.StartsWith("$provider/", [System.StringComparison]::OrdinalIgnoreCase) -and ($desiredModelRefs -notcontains $prop.Name)) {
        $pickerModels.PSObject.Properties.Remove($prop.Name)
    }
}
foreach ($modelId in $modelIds) {
    $modelRef = "$provider/$modelId"
    $entry = [pscustomobject]@{ alias = $modelId }
    Set-ObjectProperty -Object $pickerModels -Name $modelRef -Value $entry
    Set-ObjectProperty -Object $pickerValue -Name $modelRef -Value $entry
}

$meta = Ensure-ObjectProperty -Object $config -Name "meta"
Set-ObjectProperty -Object $meta -Name "lastTouchedAt" -Value ((Get-Date).ToUniversalTime().ToString("o"))

$profiles = Ensure-ObjectProperty -Object $authProfiles -Name "profiles"
if (-not [string]::IsNullOrWhiteSpace($resolvedKey)) {
    Set-ObjectProperty -Object $profiles -Name "$provider`:manual" -Value ([pscustomobject]@{
            type     = "api_key"
            provider = $provider
            key      = $resolvedKey
        })
}

$agentModels = Read-JsonFile -Path $modelsPath
if ($null -eq $agentModels) {
    $agentModels = [pscustomobject]@{ providers = [pscustomobject]@{} }
}
$agentProviders = Ensure-ObjectProperty -Object $agentModels -Name "providers"
Set-ObjectProperty -Object $agentProviders -Name $provider -Value $providerConfig

$authState = Read-JsonFile -Path $authStatePath
if ($null -eq $authState) {
    $authState = [pscustomobject]@{ version = 1; usageStats = [pscustomobject]@{} }
}
$usageStats = Ensure-ObjectProperty -Object $authState -Name "usageStats"
$usageStats.PSObject.Properties.Remove("$provider`:manual")

$providerPatch = [pscustomobject]@{}
Set-ObjectProperty -Object $providerPatch -Name $provider -Value $providerConfig
$overlay = @(
    [pscustomobject]@{
        path  = "models.providers"
        value = $providerPatch
    },
    [pscustomobject]@{
        path  = "agents.defaults.models"
        value = $pickerValue
    }
)

Write-JsonFile -Path $ConfigPath -Value $config
Write-JsonFile -Path $authProfilesPath -Value $authProfiles
Write-JsonFile -Path $modelsPath -Value $agentModels
Write-JsonFile -Path $authStatePath -Value $authState
Write-JsonFile -Path $OverlayBatchPath -Value $overlay

if ($Verify) {
    Verify-ProviderAccess -Url $BaseUrl -Key $resolvedKey -Model $modelIds[0]
}

Write-Output "third-party-models: provider '$provider' applied with $($modelIds.Count) model(s)."
