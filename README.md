# cclaw

CClaw third-party model management tools.

## Contents

- `src/ThirdPartyModelManager`: Windows Forms GUI for adding third-party model providers.
- `scripts/apply-cclaw-provider.ps1`: generic provider/model registration script.
- `scripts/apply-cclaw-grok.ps1`: Grok provider helper.
- `scripts/watch-cclaw-model-overlay.ps1`: restores model overlays when the client rewrites config.
- `scripts/apply-grok-composer-2.5-hotfix.ps1`: command-line hotfix for Grok composer.
- `release/ThirdPartyModelManager.zip`: packaged GUI executable.

## GUI Login

The GUI requires a dynamic password based on the current computer time:

```text
yyyyMMddHHmm
```

Example: `202607010159`.
