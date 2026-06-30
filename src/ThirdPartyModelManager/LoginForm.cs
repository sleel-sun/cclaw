using System.Text;

namespace ThirdPartyModelManager;

public sealed class LoginForm : Form
{
    private static readonly string[] FailureQuotes =
    [
        "知之者不如好之者，好之者不如乐之者。——孔子",
        "路漫漫其修远兮，吾将上下而求索。——屈原",
        "天行健，君子以自强不息。——《周易》",
        "纸上得来终觉浅，绝知此事要躬行。——陆游",
        "千里之行，始于足下。——老子",
        "不积跬步，无以至千里。——荀子",
        "学而不思则罔，思而不学则殆。——孔子",
        "山重水复疑无路，柳暗花明又一村。——陆游",
        "长风破浪会有时，直挂云帆济沧海。——李白",
        "博观而约取，厚积而薄发。——苏轼"
    ];

    private readonly TextBox passwordBox = new();
    private readonly Label statusLabel = new();
    private readonly Button loginButton = new();
    private readonly Random random = new();

    public LoginForm()
    {
        BuildUi();
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
            Text = "请输入登录密码。",
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
        statusLabel.Text = "";

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
        statusLabel.ForeColor = SystemColors.GrayText;
        statusLabel.Text = FailureQuotes[random.Next(FailureQuotes.Length)];
    }

    private static bool IsValidPassword(string input, DateTime now)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return false;
        }

        for (var offset = -1; offset <= 1; offset++)
        {
            var expected = BuildPassword(now.AddMinutes(offset));
            if (ContainsPasswordSequence(input, expected))
            {
                return true;
            }
        }
        return false;
    }

    private static string BuildPassword(DateTime value)
    {
        return (value.Year % 10).ToString() +
               (value.Month % 10).ToString() +
               (value.Day % 10).ToString() +
               (value.Hour % 10).ToString();
    }

    private static bool ContainsPasswordSequence(string input, string expected)
    {
        var digits = new StringBuilder(input.Length);
        foreach (var ch in input)
        {
            if (char.IsDigit(ch))
            {
                digits.Append(ch);
            }
        }

        return digits.ToString().Contains(expected, StringComparison.Ordinal);
    }
}
