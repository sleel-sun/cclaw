using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace ThirdPartyModelManager;

public partial class Form1 : Form
{
    private readonly TextBox providerBox = new();
    private readonly TextBox baseUrlBox = new();
    private readonly TextBox apiKeyBox = new();
    private readonly ComboBox apiBox = new();
    private readonly NumericUpDown contextWindowBox = new();
    private readonly NumericUpDown maxTokensBox = new();
    private readonly ComboBox savedProfilesBox = new();
    private readonly CheckedListBox modelList = new();
    private readonly TextBox manualModelsBox = new();
    private readonly TextBox logBox = new();
    private readonly Button fetchButton = new();
    private readonly Button saveProfileButton = new();
    private readonly Button deleteProfileButton = new();
    private readonly Button applyButton = new();
    private readonly Button applyAllButton = new();
    private readonly Button watcherButton = new();
    private readonly Button selectAllButton = new();
    private bool loadingProfile;

    private readonly string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    public Form1()
    {
        InitializeComponent();
        BuildUi();
    }

    private string AssistDir => Path.Combine(userProfile, ".cclaw-assist");
    private string ToolsDir => Path.Combine(AssistDir, "tools");
    private string ConfigPath => Path.Combine(AssistDir, "cclaw-assist.json");
    private string AgentDir => Path.Combine(AssistDir, "agents", "main", "agent");
    private string ProfilesPath => Path.Combine(ToolsDir, "third-party-provider-profiles.json");
    private string ProviderScript => Path.Combine(AssistDir, "plugins", "third-party-models", "scripts", "apply-cclaw-provider.ps1");
    private string WatcherScript => Path.Combine(ToolsDir, "watch-cclaw-model-overlay.ps1");
    private string OpenClawCmd => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "CClaw", "bin", "openclaw.cmd");

    private void BuildUi()
    {
        Text = "CClaw 第三方模型管理器";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(900, 700);
        Size = new Size(980, 760);

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            Padding = new Padding(12)
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 202));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 55));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 88));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 45));
        Controls.Add(root);

        root.Controls.Add(BuildProviderPanel(), 0, 0);
        root.Controls.Add(BuildModelsPanel(), 0, 1);
        root.Controls.Add(BuildActionsPanel(), 0, 2);
        root.Controls.Add(BuildLogPanel(), 0, 3);

        providerBox.Text = "grok";
        baseUrlBox.Text = "https://cloudmanager.cn/v1";
        apiBox.Items.AddRange(new object[] { "openai-completions", "anthropic-messages" });
        apiBox.SelectedIndex = 0;
        contextWindowBox.Maximum = 2000000;
        contextWindowBox.Minimum = 1000;
        contextWindowBox.Value = 128000;
        contextWindowBox.Increment = 1000;
        maxTokensBox.Maximum = 200000;
        maxTokensBox.Minimum = 1;
        maxTokensBox.Value = 8192;
        maxTokensBox.Increment = 512;
        savedProfilesBox.DropDownStyle = ComboBoxStyle.DropDownList;

        fetchButton.Click += async (_, _) => await FetchModelsAsync();
        saveProfileButton.Click += (_, _) => SaveCurrentProfile();
        deleteProfileButton.Click += (_, _) => DeleteSelectedProfile();
        applyButton.Click += async (_, _) => await ApplyAsync();
        applyAllButton.Click += async (_, _) => await ApplyAllProfilesAsync();
        watcherButton.Click += (_, _) => StartWatcher();
        selectAllButton.Click += (_, _) => SetAllModelsChecked(true);
        savedProfilesBox.SelectedIndexChanged += (_, _) => LoadSelectedProfile();

        LoadProfilesIntoCombo();
    }

    private Control BuildProviderPanel()
    {
        var group = new GroupBox { Text = "供应商配置", Dock = DockStyle.Fill };
        var grid = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 4,
            RowCount = 5,
            Padding = new Padding(10)
        };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 96));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 96));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        group.Controls.Add(grid);

        AddLabeledControl(grid, "供应商 ID", providerBox, 0, 0);
        AddLabeledControl(grid, "Base URL", baseUrlBox, 2, 0);
        AddLabeledControl(grid, "API Key", apiKeyBox, 0, 1);
        apiKeyBox.UseSystemPasswordChar = true;
        AddLabeledControl(grid, "接口类型", apiBox, 2, 1);
        AddLabeledControl(grid, "上下文", contextWindowBox, 0, 2);
        AddLabeledControl(grid, "Max Tokens", maxTokensBox, 2, 2);
        AddLabeledControl(grid, "配置列表", savedProfilesBox, 0, 3);
        grid.SetColumnSpan(savedProfilesBox, 3);

        var hint = new Label
        {
            Text = "OpenAI 兼容供应商会请求 Base URL + /models；可保存多组供应商配置后批量写入。",
            Dock = DockStyle.Fill,
            AutoSize = false,
            ForeColor = SystemColors.GrayText,
            TextAlign = ContentAlignment.MiddleLeft
        };
        grid.Controls.Add(hint, 0, 4);
        grid.SetColumnSpan(hint, 4);

        return group;
    }

    private Control BuildModelsPanel()
    {
        var split = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Vertical,
            SplitterDistance = 560
        };

        var modelsGroup = new GroupBox { Text = "自动获取的模型", Dock = DockStyle.Fill };
        modelList.Dock = DockStyle.Fill;
        modelList.CheckOnClick = true;
        modelsGroup.Controls.Add(modelList);
        split.Panel1.Controls.Add(modelsGroup);

        var manualGroup = new GroupBox { Text = "手工模型 ID（每行一个，或逗号分隔）", Dock = DockStyle.Fill };
        manualModelsBox.Dock = DockStyle.Fill;
        manualModelsBox.Multiline = true;
        manualModelsBox.ScrollBars = ScrollBars.Vertical;
        manualGroup.Controls.Add(manualModelsBox);
        split.Panel2.Controls.Add(manualGroup);

        return split;
    }

    private Control BuildActionsPanel()
    {
        var panel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            Padding = new Padding(0, 16, 0, 0),
            WrapContents = true
        };

        fetchButton.Text = "获取供应商模型";
        fetchButton.Width = 150;
        selectAllButton.Text = "全选";
        selectAllButton.Width = 80;
        saveProfileButton.Text = "保存供应商";
        saveProfileButton.Width = 120;
        deleteProfileButton.Text = "删除供应商";
        deleteProfileButton.Width = 120;
        applyButton.Text = "写入配置";
        applyButton.Width = 130;
        applyAllButton.Text = "写入全部";
        applyAllButton.Width = 110;
        watcherButton.Text = "启动自动补回";
        watcherButton.Width = 150;

        panel.Controls.Add(fetchButton);
        panel.Controls.Add(selectAllButton);
        panel.Controls.Add(saveProfileButton);
        panel.Controls.Add(deleteProfileButton);
        panel.Controls.Add(applyButton);
        panel.Controls.Add(applyAllButton);
        panel.Controls.Add(watcherButton);
        return panel;
    }

    private Control BuildLogPanel()
    {
        var group = new GroupBox { Text = "执行日志", Dock = DockStyle.Fill };
        logBox.Dock = DockStyle.Fill;
        logBox.Multiline = true;
        logBox.ScrollBars = ScrollBars.Vertical;
        logBox.ReadOnly = true;
        logBox.Font = new Font("Consolas", 9);
        group.Controls.Add(logBox);
        return group;
    }

    private static void AddLabeledControl(TableLayoutPanel grid, string labelText, Control control, int labelCol, int row)
    {
        var label = new Label
        {
            Text = labelText,
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleLeft
        };
        control.Dock = DockStyle.Fill;
        grid.Controls.Add(label, labelCol, row);
        grid.Controls.Add(control, labelCol + 1, row);
    }

    private async Task FetchModelsAsync()
    {
        var baseUrl = baseUrlBox.Text.Trim().TrimEnd('/');
        var apiKey = apiKeyBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            MessageBox.Show("请填写 Base URL。", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        await RunUiTaskAsync(fetchButton, async () =>
        {
            Log($"GET {baseUrl}/models");
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            using var request = new HttpRequestMessage(HttpMethod.Get, $"{baseUrl}/models");
            if (!string.IsNullOrWhiteSpace(apiKey))
            {
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", apiKey);
            }

            using var response = await client.SendAsync(request);
            var body = await response.Content.ReadAsStringAsync();
            Log($"HTTP {(int)response.StatusCode} {response.ReasonPhrase}");
            if (!response.IsSuccessStatusCode)
            {
                Log(TrimForLog(body));
                throw new InvalidOperationException("模型接口返回失败，可改用手工输入模型 ID。");
            }

            var ids = ParseModelIds(body).OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
            if (ids.Count == 0)
            {
                throw new InvalidOperationException("响应中没有识别到模型 ID，可改用手工输入。");
            }

            modelList.Items.Clear();
            foreach (var id in ids)
            {
                modelList.Items.Add(id, true);
            }
            Log($"已加载 {ids.Count} 个模型。");
        });
    }

    private async Task ApplyAsync()
    {
        var profile = BuildCurrentProfile(showWarnings: true);
        if (profile == null)
        {
            return;
        }
        if (!File.Exists(ProviderScript))
        {
            MessageBox.Show($"找不到脚本：{ProviderScript}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        await RunUiTaskAsync(applyButton, async () =>
        {
            await ApplyProviderProfileAsync(profile);
            VerifyAppliedConfig(profile.ProviderId, profile.ModelIds);
            Log("磁盘配置已写入并校验通过。当前客户端可能仍有缓存；界面未刷新时请重启 CClaw，或点击“启动自动补回”。");
        });
    }

    private async Task ApplyAllProfilesAsync()
    {
        var profiles = LoadProviderProfiles();
        if (profiles.Count == 0)
        {
            MessageBox.Show("请先保存至少一组供应商配置。", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (!File.Exists(ProviderScript))
        {
            MessageBox.Show($"找不到脚本：{ProviderScript}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        await RunUiTaskAsync(applyAllButton, async () =>
        {
            foreach (var profile in profiles)
            {
                await ApplyProviderProfileAsync(profile);
                VerifyAppliedConfig(profile.ProviderId, profile.ModelIds);
            }
            Log($"已写入全部供应商配置：{profiles.Count} 组。");
        });
    }

    private async Task ApplyProviderProfileAsync(ProviderProfile profile)
    {
        Directory.CreateDirectory(ToolsDir);
        var batchPath = Path.Combine(ToolsDir, $"cclaw-provider-{profile.ProviderId}.batch.json");
        Log($"写入供应商 {profile.ProviderId}，模型数 {profile.ModelIds.Count}");

        var args = new List<string>
        {
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", ProviderScript,
            "-ProviderId", profile.ProviderId,
            "-BaseUrl", profile.BaseUrl,
            "-Api", profile.Api,
            "-InputTypes", "text",
            "-ContextWindow", profile.ContextWindow.ToString(),
            "-MaxTokens", profile.MaxTokens.ToString(),
            "-ConfigPath", ConfigPath,
            "-AgentDir", AgentDir,
            "-OverlayBatchPath", batchPath
        };

        if (!string.IsNullOrWhiteSpace(profile.ApiKey))
        {
            args.Add("-ApiKey");
            args.Add(profile.ApiKey);
        }
        else
        {
            args.Add("-AllowMissingApiKey");
        }

        args.Add("-ModelIds");
        args.Add(string.Join(",", profile.ModelIds));

        await RunProcessAsync("powershell.exe", args);
    }

    private ProviderProfile? BuildCurrentProfile(bool showWarnings)
    {
        var provider = NormalizeProviderId(providerBox.Text);
        var baseUrl = baseUrlBox.Text.Trim();
        var models = GetSelectedModels();

        if (string.IsNullOrWhiteSpace(provider))
        {
            if (showWarnings)
            {
                MessageBox.Show("请填写有效供应商 ID。", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            return null;
        }
        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            if (showWarnings)
            {
                MessageBox.Show("请填写 Base URL。", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            return null;
        }
        if (models.Count == 0)
        {
            if (showWarnings)
            {
                MessageBox.Show("请至少选择或手工输入一个模型 ID。", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            return null;
        }

        return new ProviderProfile
        {
            ProviderId = provider,
            BaseUrl = baseUrl,
            ApiKey = apiKeyBox.Text.Trim(),
            Api = string.IsNullOrWhiteSpace(apiBox.Text) ? "openai-completions" : apiBox.Text.Trim(),
            ContextWindow = (int)contextWindowBox.Value,
            MaxTokens = (int)maxTokensBox.Value,
            ModelIds = models
        };
    }

    private void SaveCurrentProfile()
    {
        var profile = BuildCurrentProfile(showWarnings: true);
        if (profile == null)
        {
            return;
        }

        var profiles = LoadProviderProfiles();
        var existing = profiles.FindIndex(x => string.Equals(x.ProviderId, profile.ProviderId, StringComparison.OrdinalIgnoreCase));
        if (existing >= 0 && string.IsNullOrWhiteSpace(profile.ApiKey))
        {
            profile.ApiKey = profiles[existing].ApiKey;
        }
        if (existing >= 0)
        {
            profiles[existing] = profile;
        }
        else
        {
            profiles.Add(profile);
        }

        SaveProviderProfiles(profiles);
        LoadProfilesIntoCombo(profile.ProviderId);
        Log($"已保存供应商配置：{profile.ProviderId}，模型数 {profile.ModelIds.Count}。");
    }

    private void DeleteSelectedProfile()
    {
        if (savedProfilesBox.SelectedItem is not ProviderProfileListItem item)
        {
            MessageBox.Show("请先选择一组已保存的供应商配置。", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var profiles = LoadProviderProfiles();
        profiles.RemoveAll(x => string.Equals(x.ProviderId, item.Profile.ProviderId, StringComparison.OrdinalIgnoreCase));
        SaveProviderProfiles(profiles);
        LoadProfilesIntoCombo();
        Log($"已删除供应商配置：{item.Profile.ProviderId}。");
    }

    private void LoadSelectedProfile()
    {
        if (loadingProfile || savedProfilesBox.SelectedItem is not ProviderProfileListItem item)
        {
            return;
        }

        var profile = item.Profile;
        providerBox.Text = profile.ProviderId;
        baseUrlBox.Text = profile.BaseUrl;
        apiKeyBox.Text = profile.ApiKey;
        SelectApi(profile.Api);
        contextWindowBox.Value = Math.Clamp(profile.ContextWindow, (int)contextWindowBox.Minimum, (int)contextWindowBox.Maximum);
        maxTokensBox.Value = Math.Clamp(profile.MaxTokens, (int)maxTokensBox.Minimum, (int)maxTokensBox.Maximum);
        modelList.Items.Clear();
        manualModelsBox.Text = string.Join(Environment.NewLine, profile.ModelIds);
        Log($"已加载供应商配置：{profile.ProviderId}。");
    }

    private void LoadProfilesIntoCombo(string? selectedProvider = null)
    {
        loadingProfile = true;
        try
        {
            savedProfilesBox.Items.Clear();
            var profiles = LoadProviderProfiles()
                .OrderBy(x => x.ProviderId, StringComparer.OrdinalIgnoreCase)
                .ToList();
            foreach (var profile in profiles)
            {
                savedProfilesBox.Items.Add(new ProviderProfileListItem(profile));
            }

            if (!string.IsNullOrWhiteSpace(selectedProvider))
            {
                for (var i = 0; i < savedProfilesBox.Items.Count; i++)
                {
                    if (savedProfilesBox.Items[i] is ProviderProfileListItem item &&
                        string.Equals(item.Profile.ProviderId, selectedProvider, StringComparison.OrdinalIgnoreCase))
                    {
                        savedProfilesBox.SelectedIndex = i;
                        break;
                    }
                }
            }
            else if (savedProfilesBox.Items.Count > 0)
            {
                savedProfilesBox.SelectedIndex = 0;
            }
        }
        finally
        {
            loadingProfile = false;
        }

        if (savedProfilesBox.SelectedIndex >= 0)
        {
            LoadSelectedProfile();
        }
    }

    private List<ProviderProfile> LoadProviderProfiles()
    {
        if (!File.Exists(ProfilesPath))
        {
            return new List<ProviderProfile>();
        }

        try
        {
            var profiles = JsonSerializer.Deserialize<List<ProviderProfile>>(
                File.ReadAllText(ProfilesPath, Encoding.UTF8),
                ProviderProfileJsonOptions);
            return profiles?
                .Where(x => !string.IsNullOrWhiteSpace(x.ProviderId) &&
                            !string.IsNullOrWhiteSpace(x.BaseUrl) &&
                            x.ModelIds.Count > 0)
                .ToList() ?? new List<ProviderProfile>();
        }
        catch (Exception ex)
        {
            Log($"读取供应商配置列表失败：{ex.Message}");
            return new List<ProviderProfile>();
        }
    }

    private void SaveProviderProfiles(List<ProviderProfile> profiles)
    {
        Directory.CreateDirectory(ToolsDir);
        var ordered = profiles
            .GroupBy(x => x.ProviderId, StringComparer.OrdinalIgnoreCase)
            .Select(x => x.Last())
            .OrderBy(x => x.ProviderId, StringComparer.OrdinalIgnoreCase)
            .ToList();
        var json = JsonSerializer.Serialize(ordered, ProviderProfileJsonOptions);
        File.WriteAllText(ProfilesPath, json + Environment.NewLine, Encoding.UTF8);
    }

    private void SelectApi(string value)
    {
        var api = string.IsNullOrWhiteSpace(value) ? "openai-completions" : value.Trim();
        if (!apiBox.Items.Contains(api))
        {
            apiBox.Items.Add(api);
        }
        apiBox.SelectedItem = api;
    }

    private void StartWatcher()
    {
        var provider = NormalizeProviderId(providerBox.Text);
        if (string.IsNullOrWhiteSpace(provider))
        {
            MessageBox.Show("请先填写供应商 ID。", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (!File.Exists(WatcherScript))
        {
            MessageBox.Show($"找不到脚本：{WatcherScript}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        var batchPath = Path.Combine(ToolsDir, $"cclaw-provider-{provider}.batch.json");
        if (!File.Exists(batchPath))
        {
            MessageBox.Show("请先写入配置，生成 overlay batch 文件。", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var psi = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        foreach (var arg in new[]
        {
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", WatcherScript,
            "-Apply",
            "-RequireClientRunning",
            "-BatchFile", batchPath,
            "-IntervalSeconds", "10",
            "-PostApplyPauseSeconds", "25"
        })
        {
            psi.ArgumentList.Add(arg);
        }
        Process.Start(psi);
        Log("已启动隐藏 watcher，客户端覆盖配置后会自动补回。");
    }

    private async Task MergeConfigAsync(string batchPath)
    {
        if (!File.Exists(OpenClawCmd))
        {
            Log($"未找到 openclaw.cmd，跳过运行态合并：{OpenClawCmd}");
            return;
        }

        var args = new List<string> { "config", "set", "--batch-file", batchPath, "--merge" };
        var env = new Dictionary<string, string>
        {
            ["OPENCLAW_STATE_DIR"] = AssistDir,
            ["OPENCLAW_CONFIG_PATH"] = ConfigPath,
            ["OPENCLAW_AGENT_DIR"] = AgentDir
        };

        try
        {
            await RunProcessAsync(OpenClawCmd, args, env);
        }
        catch (Exception ex)
        {
            Log($"运行态合并失败：{ex.Message}");
            Log("如果看到 EPERM，请以管理员身份重新运行本工具。");
        }
    }

    private void VerifyAppliedConfig(string provider, IReadOnlyCollection<string> expectedModels)
    {
        if (!File.Exists(ConfigPath))
        {
            throw new InvalidOperationException($"配置文件不存在：{ConfigPath}");
        }

        using var doc = JsonDocument.Parse(File.ReadAllText(ConfigPath));
        var root = doc.RootElement;
        var missing = new List<string>();

        if (!TryGetProperty(root, "models", out var modelsRoot) ||
            !TryGetProperty(modelsRoot, "providers", out var providersRoot) ||
            !TryGetProperty(providersRoot, provider, out var providerRoot) ||
            !TryGetProperty(providerRoot, "models", out var providerModels) ||
            providerModels.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidOperationException($"写入后未找到供应商配置：{provider}");
        }

        var providerModelsById = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in providerModels.EnumerateArray())
        {
            if (TryGetProperty(item, "id", out var id) && id.ValueKind == JsonValueKind.String)
            {
                var value = id.GetString();
                if (!string.IsNullOrWhiteSpace(value))
                {
                    providerModelsById[value] = item;
                }
            }
        }

        foreach (var model in expectedModels)
        {
            if (!providerModelsById.ContainsKey(model))
            {
                missing.Add(model);
            }
        }

        if (missing.Count > 0)
        {
            throw new InvalidOperationException("供应商配置缺少模型：" + string.Join(", ", missing.Take(10)));
        }

        foreach (var model in expectedModels)
        {
            if (!ModelHasToolCompat(providerModelsById[model]))
            {
                missing.Add(model);
            }
        }

        if (missing.Count > 0)
        {
            throw new InvalidOperationException("供应商配置缺少工具兼容字段：" + string.Join(", ", missing.Take(10)));
        }

        if (!TryGetProperty(root, "agents", out var agentsRoot) ||
            !TryGetProperty(agentsRoot, "defaults", out var defaultsRoot) ||
            !TryGetProperty(defaultsRoot, "models", out var pickerModels))
        {
            throw new InvalidOperationException("写入后未找到模型选择器配置：agents.defaults.models");
        }

        missing.Clear();
        foreach (var model in expectedModels)
        {
            if (!TryGetProperty(pickerModels, $"{provider}/{model}", out _))
            {
                missing.Add(model);
            }
        }

        if (missing.Count > 0)
        {
            throw new InvalidOperationException("模型选择器缺少模型：" + string.Join(", ", missing.Take(10)));
        }

        Log($"校验通过：供应商模型 {expectedModels.Count} 个，选择器模型 {expectedModels.Count} 个。");
    }

    private static bool ModelHasToolCompat(JsonElement model)
    {
        if (!TryGetProperty(model, "compat", out var compat) || compat.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        if (!TryGetProperty(compat, "supportsTools", out var supportsTools) ||
            supportsTools.ValueKind != JsonValueKind.True)
        {
            return false;
        }

        foreach (var name in new[]
        {
            "supportsStore",
            "supportsDeveloperRole",
            "supportsReasoningEffort",
            "supportsUsageInStreaming",
            "supportsStrictMode",
            "requiresStringContent",
            "requiresToolResultName",
            "requiresAssistantAfterToolResult",
            "requiresThinkingAsText",
            "requiresMistralToolIds",
            "requiresOpenAiAnthropicToolPayload"
        })
        {
            if (!TryGetProperty(compat, name, out var field) || field.ValueKind != JsonValueKind.False)
            {
                return false;
            }
        }

        if (!TryGetProperty(compat, "unsupportedToolSchemaKeywords", out var unsupportedKeywords) ||
            unsupportedKeywords.ValueKind != JsonValueKind.Array ||
            unsupportedKeywords.GetArrayLength() == 0)
        {
            return false;
        }

        return TryGetProperty(compat, "maxTokensField", out var maxTokensField) &&
               maxTokensField.ValueKind == JsonValueKind.String &&
               maxTokensField.GetString() == "max_tokens";
    }

    private static bool TryGetProperty(JsonElement element, string name, out JsonElement value)
    {
        value = default;
        return element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out value);
    }

    private List<string> GetSelectedModels()
    {
        var values = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in modelList.CheckedItems)
        {
            AddModelId(values, item?.ToString());
        }
        foreach (var part in manualModelsBox.Text.Split(new[] { '\r', '\n', ',' }, StringSplitOptions.RemoveEmptyEntries))
        {
            AddModelId(values, part);
        }
        return values.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
    }

    private static void AddModelId(HashSet<string> values, string? raw)
    {
        var value = raw?.Trim();
        if (!string.IsNullOrWhiteSpace(value))
        {
            values.Add(value);
        }
    }

    private static List<string> ParseModelIds(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var result = new List<string>();
        if (doc.RootElement.ValueKind == JsonValueKind.Object &&
            doc.RootElement.TryGetProperty("data", out var data) &&
            data.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in data.EnumerateArray())
            {
                if (item.ValueKind == JsonValueKind.Object &&
                    item.TryGetProperty("id", out var id) &&
                    id.ValueKind == JsonValueKind.String)
                {
                    var value = id.GetString();
                    if (!string.IsNullOrWhiteSpace(value))
                    {
                        result.Add(value);
                    }
                }
            }
        }
        else if (doc.RootElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in doc.RootElement.EnumerateArray())
            {
                if (item.ValueKind == JsonValueKind.String)
                {
                    var value = item.GetString();
                    if (!string.IsNullOrWhiteSpace(value))
                    {
                        result.Add(value);
                    }
                }
                else if (item.ValueKind == JsonValueKind.Object &&
                         item.TryGetProperty("id", out var id) &&
                         id.ValueKind == JsonValueKind.String)
                {
                    var value = id.GetString();
                    if (!string.IsNullOrWhiteSpace(value))
                    {
                        result.Add(value);
                    }
                }
            }
        }
        return result.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    private static string NormalizeProviderId(string value)
    {
        var normalized = Regex.Replace(value.Trim().ToLowerInvariant(), "[^a-z0-9_.-]+", "-").Trim('-');
        return normalized;
    }

    private void SetAllModelsChecked(bool isChecked)
    {
        for (var i = 0; i < modelList.Items.Count; i++)
        {
            modelList.SetItemChecked(i, isChecked);
        }
    }

    private async Task RunUiTaskAsync(Control source, Func<Task> action)
    {
        source.Enabled = false;
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            Log($"ERROR: {ex.Message}");
            MessageBox.Show(ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            source.Enabled = true;
        }
    }

    private async Task RunProcessAsync(string fileName, IReadOnlyList<string> args, Dictionary<string, string>? env = null)
    {
        var psi = new ProcessStartInfo(fileName)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var arg in args)
        {
            psi.ArgumentList.Add(arg);
        }
        if (env != null)
        {
            foreach (var item in env)
            {
                psi.Environment[item.Key] = item.Value;
            }
        }

        Log($"> {Path.GetFileName(fileName)} {string.Join(" ", args.Select(EscapeForLog))}");
        using var process = Process.Start(psi) ?? throw new InvalidOperationException($"无法启动进程：{fileName}");
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var stdout = await stdoutTask;
        var stderr = await stderrTask;
        if (!string.IsNullOrWhiteSpace(stdout))
        {
            Log(TrimForLog(stdout));
        }
        if (!string.IsNullOrWhiteSpace(stderr))
        {
            Log(TrimForLog(stderr));
        }
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"{Path.GetFileName(fileName)} 退出码 {process.ExitCode}");
        }
    }

    private static string EscapeForLog(string arg)
    {
        if (arg.Contains(" ", StringComparison.Ordinal) || arg.Contains('\\', StringComparison.Ordinal))
        {
            return "\"" + arg.Replace("\"", "\\\"", StringComparison.Ordinal) + "\"";
        }
        return arg;
    }

    private static string TrimForLog(string value)
    {
        var text = value.Trim();
        return text.Length <= 4000 ? text : text[..4000] + Environment.NewLine + "...<truncated>";
    }

    private void Log(string message)
    {
        if (InvokeRequired)
        {
            BeginInvoke(new Action<string>(Log), message);
            return;
        }
        logBox.AppendText($"[{DateTime.Now:HH:mm:ss}] {message}{Environment.NewLine}");
    }

    private static readonly JsonSerializerOptions ProviderProfileJsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private sealed class ProviderProfile
    {
        public string ProviderId { get; set; } = "";
        public string BaseUrl { get; set; } = "";
        public string ApiKey { get; set; } = "";
        public string Api { get; set; } = "openai-completions";
        public int ContextWindow { get; set; } = 128000;
        public int MaxTokens { get; set; } = 8192;
        public List<string> ModelIds { get; set; } = new();
    }

    private sealed class ProviderProfileListItem(ProviderProfile profile)
    {
        public ProviderProfile Profile { get; } = profile;

        public override string ToString()
        {
            return $"{Profile.ProviderId}  |  {Profile.BaseUrl}  |  {Profile.ModelIds.Count} models";
        }
    }
}
