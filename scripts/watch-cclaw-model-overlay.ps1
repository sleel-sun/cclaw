param(
    [Parameter(Mandatory = $false)]
    [string]$BatchFile = "$env:USERPROFILE\.cclaw-assist\tools\cclaw-provider-grok.batch.json",

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$env:USERPROFILE\.cclaw-assist\cclaw-assist.json",

    [Parameter(Mandatory = $false)]
    [string]$AgentDir = "$env:USERPROFILE\.cclaw-assist\agents\main\agent",

    [Parameter(Mandatory = $false)]
    [string]$OpenClawCmd = "$env:LOCALAPPDATA\CClaw\bin\openclaw.cmd",

    [Parameter(Mandatory = $false)]
    [string]$GatewayUrl = "ws://127.0.0.1:18789",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:USERPROFILE\.cclaw-assist\tools\model-overlay-watch.log",

    [Parameter(Mandatory = $false)]
    [int]$IntervalSeconds = 10,

    [Parameter(Mandatory = $false)]
    [int]$PostApplyPauseSeconds = 25,

    [Parameter(Mandatory = $false)]
    [switch]$RunOnce,

    [Parameter(Mandatory = $false)]
    [switch]$Apply,

    [Parameter(Mandatory = $false)]
    [switch]$RequireClientRunning
)

$ErrorActionPreference = "Stop"
$script:LastStatus = $null

function Write-OverlayLog {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    try {
        $logDir = Split-Path -Parent $LogPath
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch {
        Write-Output $line
    }
}

function Write-Status {
    param([string]$Message)
    if ($script:LastStatus -ne $Message) {
        $script:LastStatus = $Message
        Write-OverlayLog $Message
    }
}

function ConvertTo-CompactJson {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Redact-Text {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $redacted = $Text -replace '("apiKey"\s*:\s*")[^"]+(")', '$1***$2'
    $redacted = $redacted -replace '(Authorization:\s*Bearer\s+)[^\s"]+', '$1***'
    if ($redacted.Length -gt 1600) {
        return $redacted.Substring(0, 1600) + "...<truncated>"
    }
    return $redacted
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-JsonProperty {
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

function Get-JsonPathValue {
    param(
        [object]$Object,
        [string]$Path
    )

    $current = $Object
    foreach ($part in ($Path -split '\.')) {
        $current = Get-JsonProperty -Object $current -Name $part
        if ($null -eq $current) {
            return $null
        }
    }
    return $current
}

function Ensure-JsonObjectProperty {
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

function Set-JsonPathValue {
    param(
        [object]$Object,
        [string]$Path,
        [object]$Value
    )

    $parts = @($Path -split '\.')
    if ($parts.Count -eq 0) {
        return
    }

    $current = $Object
    for ($i = 0; $i -lt ($parts.Count - 1); $i++) {
        $current = Ensure-JsonObjectProperty -Object $current -Name $parts[$i]
    }

    $last = $parts[$parts.Count - 1]
    $prop = $current.PSObject.Properties[$last]
    if ($null -eq $prop) {
        $current | Add-Member -MemberType NoteProperty -Name $last -Value $Value
    } else {
        $prop.Value = $Value
    }
}

function Test-JsonSubset {
    param(
        [object]$Expected,
        [object]$Actual
    )

    if ($null -eq $Expected) {
        return $true
    }
    if ($null -eq $Actual) {
        return $false
    }

    if ($Expected -is [System.Array]) {
        if (-not ($Actual -is [System.Array])) {
            return $false
        }
        foreach ($expectedItem in $Expected) {
            $matched = $false
            foreach ($actualItem in $Actual) {
                if (Test-JsonSubset -Expected $expectedItem -Actual $actualItem) {
                    $matched = $true
                    break
                }
            }
            if (-not $matched) {
                return $false
            }
        }
        return $true
    }

    if (($Expected -is [string]) -or ($Expected -is [System.ValueType])) {
        return $Expected -eq $Actual
    }

    $expectedProps = @($Expected.PSObject.Properties | Where-Object {
            $_.MemberType -eq "NoteProperty" -or $_.MemberType -eq "Property"
        })

    if ($expectedProps.Count -eq 0) {
        return (ConvertTo-CompactJson $Expected) -eq (ConvertTo-CompactJson $Actual)
    }

    foreach ($prop in $expectedProps) {
        $actualValue = Get-JsonProperty -Object $Actual -Name $prop.Name
        if (-not (Test-JsonSubset -Expected $prop.Value -Actual $actualValue)) {
            return $false
        }
    }

    return $true
}

function Get-JsonNoteProperties {
    param([object]$Object)

    if ($null -eq $Object) {
        return @()
    }

    return @($Object.PSObject.Properties | Where-Object {
            $_.MemberType -eq "NoteProperty" -or $_.MemberType -eq "Property"
        })
}

function Test-ProviderOverlayPresent {
    param(
        [object]$ExpectedProviders,
        [object]$ActualProviders
    )

    foreach ($providerProp in (Get-JsonNoteProperties -Object $ExpectedProviders)) {
        $providerName = $providerProp.Name
        $expectedProvider = $providerProp.Value
        $actualProvider = Get-JsonProperty -Object $ActualProviders -Name $providerName
        if ($null -eq $actualProvider) {
            return $false
        }

        foreach ($field in (Get-JsonNoteProperties -Object $expectedProvider)) {
            if ($field.Name -eq "models") {
                $actualModels = @(Get-JsonProperty -Object $actualProvider -Name "models")
                foreach ($expectedModel in @($field.Value)) {
                    $expectedModelId = [string](Get-JsonProperty -Object $expectedModel -Name "id")
                    if ([string]::IsNullOrWhiteSpace($expectedModelId)) {
                        continue
                    }

                    $matched = $false
                    foreach ($actualModel in $actualModels) {
                        $actualModelId = [string](Get-JsonProperty -Object $actualModel -Name "id")
                        if ($actualModelId -eq $expectedModelId) {
                            $matched = $true
                            break
                        }
                    }

                    if (-not $matched) {
                        return $false
                    }
                }
                continue
            }

            $actualValue = Get-JsonProperty -Object $actualProvider -Name $field.Name
            if ($null -eq $actualValue) {
                return $false
            }

            if (($field.Value -is [string]) -or ($field.Value -is [System.ValueType])) {
                if ($actualValue -ne $field.Value) {
                    return $false
                }
                continue
            }

            if (-not (Test-JsonSubset -Expected $field.Value -Actual $actualValue)) {
                return $false
            }
        }
    }

    return $true
}

function Test-PickerOverlayPresent {
    param(
        [object]$ExpectedModels,
        [object]$ActualModels
    )

    foreach ($modelProp in (Get-JsonNoteProperties -Object $ExpectedModels)) {
        $actualEntry = Get-JsonProperty -Object $ActualModels -Name $modelProp.Name
        if ($null -eq $actualEntry) {
            return $false
        }

        $expectedAlias = Get-JsonProperty -Object $modelProp.Value -Name "alias"
        if (-not [string]::IsNullOrWhiteSpace([string]$expectedAlias)) {
            $actualAlias = Get-JsonProperty -Object $actualEntry -Name "alias"
            if ($actualAlias -ne $expectedAlias) {
                return $false
            }
        }
    }

    return $true
}

function Read-OverlayOperations {
    $ops = Read-JsonFile -Path $BatchFile
    if ($null -eq $ops) {
        throw "Overlay batch file missing: $BatchFile"
    }
    return @($ops)
}

function Convert-BatchToPatch {
    param([object[]]$Operations)

    $patch = [pscustomobject]@{}
    foreach ($op in $Operations) {
        $path = [string](Get-JsonProperty -Object $op -Name "path")
        $value = Get-JsonProperty -Object $op -Name "value"
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }
        Set-JsonPathValue -Object $patch -Path $path -Value $value
    }
    return $patch
}

function Test-OverlayPresent {
    param([object[]]$Operations)

    $config = Read-JsonFile -Path $ConfigPath
    if ($null -eq $config) {
        return $false
    }

    foreach ($op in $Operations) {
        $path = [string](Get-JsonProperty -Object $op -Name "path")
        $value = Get-JsonProperty -Object $op -Name "value"
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $actual = Get-JsonPathValue -Object $config -Path $path
        if ($path -eq "models.providers") {
            if (-not (Test-ProviderOverlayPresent -ExpectedProviders $value -ActualProviders $actual)) {
                return $false
            }
            continue
        }

        if ($path -eq "agents.defaults.models") {
            if (-not (Test-PickerOverlayPresent -ExpectedModels $value -ActualModels $actual)) {
                return $false
            }
            continue
        }

        if (-not (Test-JsonSubset -Expected $value -Actual $actual)) {
            return $false
        }
    }

    return $true
}

function Get-CClawInstallRoot {
    return (Join-Path $env:LOCALAPPDATA "CClaw")
}

function Test-CClawClientRunning {
    $installRoot = Get-CClawInstallRoot
    $processes = @(Get-Process -Name "cclaw", "node" -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        try {
            if ($process.Path -and $process.Path.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        } catch {
            continue
        }
    }
    return $false
}

function Get-GatewayToken {
    try {
        $config = Read-JsonFile -Path $ConfigPath
        $gateway = Get-JsonProperty -Object $config -Name "gateway"
        $auth = Get-JsonProperty -Object $gateway -Name "auth"
        $token = Get-JsonProperty -Object $auth -Name "token"
        if ($token) {
            return [string]$token
        }
    } catch {
        return $null
    }
    return $null
}

function Find-JsonPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Array]) {
        foreach ($item in $Object) {
            $found = Find-JsonPropertyValue -Object $item -Name $Name
            if ($null -ne $found) {
                return $found
            }
        }
        return $null
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) {
        return $prop.Value
    }

    foreach ($child in $Object.PSObject.Properties) {
        if ($null -eq $child.Value -or $child.Value -is [string] -or $child.Value -is [System.ValueType]) {
            continue
        }
        $found = Find-JsonPropertyValue -Object $child.Value -Name $Name
        if ($null -ne $found) {
            return $found
        }
    }

    return $null
}

function Invoke-OpenClaw {
    param([string[]]$Arguments)

    $previousStateDir = $env:OPENCLAW_STATE_DIR
    $previousConfigPath = $env:OPENCLAW_CONFIG_PATH
    $previousAgentDir = $env:OPENCLAW_AGENT_DIR
    $previousErrorActionPreference = $ErrorActionPreference

    try {
        $env:OPENCLAW_STATE_DIR = (Split-Path -Parent $ConfigPath)
        $env:OPENCLAW_CONFIG_PATH = $ConfigPath
        $env:OPENCLAW_AGENT_DIR = $AgentDir

        $ErrorActionPreference = "Continue"
        try {
            $output = & $OpenClawCmd @Arguments 2>&1
            $exitCode = $LASTEXITCODE
            if ($null -eq $exitCode) {
                $exitCode = 0
            }
        } catch {
            $output = @($_.Exception.Message)
            $exitCode = 1
        }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output   = (($output | Out-String).Trim())
        }
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        $env:OPENCLAW_STATE_DIR = $previousStateDir
        $env:OPENCLAW_CONFIG_PATH = $previousConfigPath
        $env:OPENCLAW_AGENT_DIR = $previousAgentDir
    }
}

function Invoke-GatewayPatch {
    param([object]$Patch)

    $token = Get-GatewayToken
    $getArgs = @("gateway", "call", "config.get", "--params", "{}", "--json", "--timeout", "5000", "--url", $GatewayUrl)
    if ($token) {
        $getArgs += @("--token", $token)
    }

    $getResult = Invoke-OpenClaw -Arguments $getArgs
    if ($getResult.ExitCode -ne 0) {
        Write-OverlayLog ("config.get failed; fallback to config set: " + (Redact-Text $getResult.Output))
        return $false
    }

    try {
        $getJson = $getResult.Output | ConvertFrom-Json
        $baseHash = Find-JsonPropertyValue -Object $getJson -Name "hash"
    } catch {
        Write-OverlayLog ("config.get JSON parse failed; fallback to config set: " + $_.Exception.Message)
        return $false
    }

    if ([string]::IsNullOrWhiteSpace([string]$baseHash)) {
        Write-OverlayLog "config.get did not return a base hash; fallback to config set"
        return $false
    }

    $params = [pscustomobject]@{
        raw            = (ConvertTo-CompactJson $Patch)
        baseHash       = [string]$baseHash
        note           = "Reapply CClaw custom model overlay"
        restartDelayMs = 0
    }

    $patchArgs = @(
        "gateway", "call", "config.patch",
        "--params", (ConvertTo-CompactJson $params),
        "--json",
        "--timeout", "15000",
        "--url", $GatewayUrl
    )
    if ($token) {
        $patchArgs += @("--token", $token)
    }

    $patchResult = Invoke-OpenClaw -Arguments $patchArgs
    if ($patchResult.ExitCode -eq 0) {
        Write-OverlayLog "config.patch applied overlay through running gateway"
        return $true
    }

    Start-Sleep -Seconds 3
    try {
        $operations = Read-OverlayOperations
        if (Test-OverlayPresent -Operations $operations) {
            Write-OverlayLog "config.patch connection closed after applying overlay"
            return $true
        }
    } catch {
        Write-OverlayLog ("post-patch verification failed: " + $_.Exception.Message)
    }

    Write-OverlayLog ("config.patch failed; fallback to config set: " + (Redact-Text $patchResult.Output))
    return $false
}

function Invoke-ConfigSetMerge {
    $result = Invoke-OpenClaw -Arguments @("config", "set", "--batch-file", $BatchFile, "--merge")
    if ($result.ExitCode -eq 0) {
        Write-OverlayLog "config set --merge applied overlay to disk"
        return $true
    }

    Write-OverlayLog ("config set --merge failed: " + (Redact-Text $result.Output))
    return $false
}

function Invoke-OverlayCheck {
    if (-not (Test-Path -LiteralPath $OpenClawCmd)) {
        Write-Status "waiting: openclaw command not found at $OpenClawCmd"
        return
    }
    if (-not (Test-Path -LiteralPath $BatchFile)) {
        Write-Status "waiting: overlay batch file not found at $BatchFile"
        return
    }
    if ($RequireClientRunning -and -not (Test-CClawClientRunning)) {
        Write-Status "waiting: CClaw client is not running"
        return
    }

    $operations = Read-OverlayOperations
    if (Test-OverlayPresent -Operations $operations) {
        Write-Status "ok: custom model overlay is present"
        return
    }

    if (-not $Apply) {
        Write-Status "disabled: custom model overlay is absent; auto-apply is off (pass -Apply to write config)"
        return
    }

    Write-OverlayLog "missing: custom model overlay is absent; applying"
    $patch = Convert-BatchToPatch -Operations $operations
    $applied = Invoke-GatewayPatch -Patch $patch
    if (-not $applied) {
        $applied = Invoke-ConfigSetMerge
    }

    if ($applied) {
        $script:LastStatus = $null
        Start-Sleep -Seconds $PostApplyPauseSeconds
    }
}

Write-OverlayLog "watcher started; batch=$BatchFile"

do {
    try {
        Invoke-OverlayCheck
    } catch {
        Write-OverlayLog ("error: " + $_.Exception.Message)
    }

    if (-not $RunOnce) {
        Start-Sleep -Seconds $IntervalSeconds
    }
} while (-not $RunOnce)
