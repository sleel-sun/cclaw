# cclaw

CClaw third-party model management tools for Windows.

## Features

- Windows GUI for adding third-party model providers.
- Fetches OpenAI-compatible model lists from `Base URL + /models`.
- Supports selecting fetched models or entering model IDs manually.
- Writes provider config into CClaw's `cclaw-assist.json` and agent `models.json`.
- Marks third-party OpenAI-compatible models with tool-call compatibility metadata by default.
- Saves multiple provider profiles and can write all saved providers in one pass.
- Generates overlay batch files for later recovery.
- Starts a hidden watcher to restore model config if the CClaw client rewrites config on restart.
- Includes Grok helper scripts and a Grok composer hotfix.

## Release

Download or copy:

```text
release/ThirdPartyModelManager.zip
```

Extract and run:

```text
ThirdPartyModelManager.exe
```

The executable is published as a self-contained Windows x64 app.

## Login

The GUI shows only a generic login prompt. It does not display the password rule.

Password validation uses the current computer time:

```text
last digit of year + last digit of month + last digit of day + last digit of hour
```

Example:

```text
2026-07-01 13:45 => 6713
```

The input may contain other digits or text. Login succeeds as long as the required sequence appears continuously in the digits extracted from the input.

Examples that pass when the target sequence is `6713`:

```text
6713
000671399
abc6-7-1-3xyz
```

The validator accepts the current minute, previous minute, and next minute to avoid edge cases when the hour changes during input.

## Usage

1. Open `ThirdPartyModelManager.exe`.
2. Log in.
3. Enter `Provider ID`, `Base URL`, and `API Key`.
4. Click `获取供应商模型` to load models from the provider.
5. Select models or enter model IDs manually.
6. Click `保存供应商` to save the current provider profile.
7. Repeat steps 3-6 for each different provider, URL, key, and model list.
8. Click `写入配置` for the current provider, or `写入全部` for all saved provider profiles.
9. Click `启动自动补回` if the CClaw client resets `cclaw-assist.json` after restart.

For OpenAI-compatible providers, `Base URL` usually ends with `/v1`.

Saved provider profiles are stored at:

```text
%USERPROFILE%\.cclaw-assist\tools\third-party-provider-profiles.json
```

This file can contain API keys. Keep it local and do not commit or share it.

The generic provider script defaults to a tool/MCP-call friendly compatibility profile:

- `supportsTools=true`
- `supportsStore=false`
- `supportsDeveloperRole=false`
- `supportsReasoningEffort=false`
- `supportsUsageInStreaming=false`
- `supportsStrictMode=false`
- `requiresStringContent=false`
- `requiresToolResultName=false`
- `requiresAssistantAfterToolResult=false`
- `requiresThinkingAsText=false`
- `requiresMistralToolIds=false`
- `requiresOpenAiAnthropicToolPayload=false`
- `unsupportedToolSchemaKeywords=minLength,maxLength,minItems,maxItems,minContains,maxContains`
- `maxTokensField=max_tokens`

These defaults avoid OpenAI-only request fields that many proxy or third-party endpoints mishandle, keep CClaw exposing tools and MCP tools to the model, and simplify tool parameter schemas for broad provider compatibility.

## Scripts

- `scripts/apply-cclaw-provider.ps1`
  Generic provider/model registration script.

- `scripts/apply-cclaw-grok.ps1`
  Grok provider helper.

- `scripts/watch-cclaw-model-overlay.ps1`
  Periodically checks and reapplies provider overlay config.

- `scripts/apply-grok-composer-2.5-hotfix.ps1`
  Command-line hotfix for adding `grok-composer-2.5`.

## Build

Requires .NET SDK with Windows Desktop support.

```powershell
dotnet build .\src\ThirdPartyModelManager\ThirdPartyModelManager.csproj -c Release
dotnet publish .\src\ThirdPartyModelManager\ThirdPartyModelManager.csproj `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:PublishSingleFile=true `
  -p:PublishReadyToRun=false `
  -o .\release\ThirdPartyModelManager
```

## Notes

- Do not commit `cclaw-assist.json`, auth files, logs, PEM files, provider profile files, or batch files containing API keys.
- If GitHub push fails with SSH key permission errors, add the public key to the GitHub account or repository with write access.
