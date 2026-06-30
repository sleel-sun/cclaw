using System.Security.Cryptography;
using System.Text;

namespace ThirdPartyModelManager;

public sealed class LoginForm : Form
{
    private readonly TextBox passwordBox = new();
    private readonly Label statusLabel = new();
    private readonly Button loginButton = new();
    private readonly System.Windows.Forms.Timer clockTimer = new();

    public LoginForm()
    {
        BuildUi();
        clockTimer.Interval = 1000;
        clockTimer.Tick += (_, _) => UpdateStatus();
        clockTimer.Start();
        UpdateStatus();
    }

    private void BuildUi()
    {
        Text = "登录验证";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(420, 210);

        var title = new Label
        {
            Text = "CClaw 第三方模型管理器",
            Font = new Font(Font.FontFamily, 13, FontStyle.Bold),
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleLeft,
            Location = new Point(24, 20),
            Size = new Size(360, 28)
        };

        var hint = new Label
        {
            Text = "请输入按当前电脑时间生成的动态密码。",
            AutoSize = false,
            ForeColor = SystemColors.GrayText,
            Location = new Point(24, 56),
            Size = new Size(360, 24)
        };

        var passwordLabel = new Label
        {
            Text = "密码",
            Location = new Point(24, 94),
            Size = new Size(64, 26),
            TextAlign = ContentAlignment.MiddleLeft
        };

        passwordBox.Location = new Point(88, 92);
        passwordBox.Size = new Size(210, 26);
        passwordBox.UseSystemPasswordChar = true;
        passwordBox.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.SuppressKeyPress = true;
                TryLogin();
            }
        };

        loginButton.Text = "登录";
        loginButton.Location = new Point(314, 91);
        loginButton.Size = new Size(76, 28);
        loginButton.Click += (_, _) => TryLogin();

        statusLabel.Location = new Point(24, 140);
        statusLabel.Size = new Size(366, 42);
        statusLabel.ForeColor = SystemColors.GrayText;

        Controls.Add(title);
        Controls.Add(hint);
        Controls.Add(passwordLabel);
        Controls.Add(passwordBox);
        Controls.Add(loginButton);
        Controls.Add(statusLabel);
    }

    private void TryLogin()
    {
        if (IsValidPassword(passwordBox.Text.Trim(), DateTime.Now))
        {
            DialogResult = DialogResult.OK;
            Close();
            return;
        }

        passwordBox.SelectAll();
        statusLabel.ForeColor = Color.Firebrick;
        statusLabel.Text = "密码错误。请确认电脑时间正确，并使用当前分钟的动态密码。";
    }

    private void UpdateStatus()
    {
        if (statusLabel.ForeColor == Color.Firebrick)
        {
            return;
        }

        statusLabel.Text = $"当前电脑时间：{DateTime.Now:yyyy-MM-dd HH:mm:ss}\r\n密码格式：yyyyMMddHHmm";
    }

    private static bool IsValidPassword(string input, DateTime now)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return false;
        }

        var inputHash = Hash(input);
        for (var offset = -1; offset <= 1; offset++)
        {
            var expected = now.AddMinutes(offset).ToString("yyyyMMddHHmm");
            if (CryptographicOperations.FixedTimeEquals(inputHash, Hash(expected)))
            {
                return true;
            }
        }
        return false;
    }

    private static byte[] Hash(string value)
    {
        return SHA256.HashData(Encoding.UTF8.GetBytes(value));
    }
}
