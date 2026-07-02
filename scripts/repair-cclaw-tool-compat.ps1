param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$env:USERPROFILE\.cclaw-assist\cclaw-assist.json",

    [Parameter(Mandatory = $false)]
    [string]$AgentDir = "$env:USERPROFILE\.cclaw-assist\agents\main\agent",

    [Parameter(Mandatory = $false)]
    [string]$ToolsDir = "$env:USERPROFILE\.cclaw-assist\tools"
)

$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item -LiteralPath $Path -Destination "$Path.bak.tool-compat.$stamp" -Force
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
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

function New-ToolCompat {
    return [pscustomobject]@{
        supportsTools                       = $true
        supportsStore                       = $false
        supportsDeveloperRole               = $false
        supportsReasoningEffort             = $false
        supportsUsageInStreaming            = $false
        supportsStrictMode                  = $false
        requiresStringContent               = $false
        requiresToolResultName              = $false
        requiresAssistantAfterToolResult    = $false
        requiresThinkingAsText              = $false
        requiresMistralToolIds              = $false
        requiresOpenAiAnthropicToolPayload  = $false
        unsupportedToolSchemaKeywords       = @("minLength", "maxLength", "minItems", "maxItems", "minContains", "maxContains")
        maxTokensField                      = "max_tokens"
    }
}

function Merge-ToolCompat {
    param([object]$Model)
    $compat = Get-ObjectProperty -Object $Model -Name "compat"
    if ($null -eq $compat -or $compat -isnot [pscustomobject]) {
        $compat = [pscustomobject]@{}
        Set-ObjectProperty -Object $Model -Name "compat" -Value $compat
    }
    $defaults = New-ToolCompat
    foreach ($prop in $defaults.PSObject.Properties) {
        Set-ObjectProperty -Object $compat -Name $prop.Name -Value $prop.Value
    }
}

function Repair-Providers {
    param([object]$Providers)
    $changed = 0
    if ($null -eq $Providers) {
        return 0
    }
    foreach ($providerProp in @($Providers.PSObject.Properties)) {
        $provider = $providerProp.Value
        $providerApi = [string](Get-ObjectProperty -Object $provider -Name "api")
        $models = @(Get-ObjectProperty -Object $provider -Name "models")
        foreach ($model in $models) {
            if ($null -eq $model) {
                continue
            }
            $modelApi = [string](Get-ObjectProperty -Object $model -Name "api")
            if ($modelApi -eq "openai-completions" -or ($modelApi -eq "" -and $providerApi -eq "openai-completions")) {
                Merge-ToolCompat -Model $model
                $changed += 1
            }
        }
    }
    return $changed
}

function Repair-ConfigFile {
    param([string]$Path)
    $json = Read-JsonFile -Path $Path
    if ($null -eq $json) {
        return 0
    }
    $providers = Get-ObjectProperty -Object (Get-ObjectProperty -Object $json -Name "models") -Name "providers"
    $changed = Repair-Providers -Providers $providers
    if ($changed -gt 0) {
        Write-JsonFile -Path $Path -Value $json
    }
    return $changed
}

function Repair-ModelsFile {
    param([string]$Path)
    $json = Read-JsonFile -Path $Path
    if ($null -eq $json) {
        return 0
    }
    $changed = Repair-Providers -Providers (Get-ObjectProperty -Object $json -Name "providers")
    if ($changed -gt 0) {
        Write-JsonFile -Path $Path -Value $json
    }
    return $changed
}

function Repair-OverlayFile {
    param([string]$Path)
    $json = Read-JsonFile -Path $Path
    if ($null -eq $json) {
        return 0
    }
    $changed = 0
    foreach ($operation in @($json)) {
        $pathValue = [string](Get-ObjectProperty -Object $operation -Name "path")
        if ($pathValue -ne "models.providers") {
            continue
        }
        $changed += Repair-Providers -Providers (Get-ObjectProperty -Object $operation -Name "value")
    }
    if ($changed -gt 0) {
        Write-JsonFile -Path $Path -Value $json
    }
    return $changed
}

$configChanged = Repair-ConfigFile -Path $ConfigPath
$modelsChanged = Repair-ModelsFile -Path (Join-Path $AgentDir "models.json")
$overlayChanged = 0
if (Test-Path -LiteralPath $ToolsDir) {
    foreach ($file in Get-ChildItem -LiteralPath $ToolsDir -Filter "*.batch.json" -File) {
        $overlayChanged += Repair-OverlayFile -Path $file.FullName
    }
}

Write-Output "tool-compat: config models=$configChanged, agent models=$modelsChanged, overlay models=$overlayChanged"
