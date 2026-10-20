using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

// K1 Max CFS-C userspace launcher. No hard-coded IP, password or trust bypass.
// Windows .NET Framework 4.7+, System.Windows.Forms, Drawing, Security.
internal sealed class FluiddLauncher : Form
{
    readonly TextBox address = new TextBox();
    readonly TextBox password = new TextBox();
    readonly CheckBox automatic = new CheckBox();
    readonly Label status = new Label();
    readonly string settingsPath = Path.Combine(Environment.GetFolderPath(
        Environment.SpecialFolder.ApplicationData), "K1MaxCfsC", "fluidd-launcher.txt");
    bool opened;

    public FluiddLauncher()
    {
        Text = "K1 Max CFS-C - OrcaSlicer and Fluidd";
        ClientSize = new Size(490, 300);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Controls.Add(new Label { Text = "Printer IPv4 address:", Location = new Point(15, 24), AutoSize = true });
        address.SetBounds(170, 20, 285, 24);
        Controls.Add(address);
        Controls.Add(new Label { Text = "Printer root SSH password:", Location = new Point(15, 62), AutoSize = true });
        password.SetBounds(170, 58, 285, 24);
        password.UseSystemPasswordChar = true;
        Controls.Add(password);
        automatic.Text = "Start Fluidd when OrcaSlicer opens";
        automatic.SetBounds(15, 100, 460, 25);
        automatic.Checked = true;
        Controls.Add(automatic);
        var save = new Button { Text = "Save Settings", Location = new Point(15, 146), Size = new Size(105, 32) };
        var start = new Button { Text = "Start Fluidd", Location = new Point(125, 146), Size = new Size(104, 32) };
        var open = new Button { Text = "Open OrcaSlicer", Location = new Point(235, 146), Size = new Size(120, 32) };
        var web = new Button { Text = "Open Fluidd", Location = new Point(360, 146), Size = new Size(113, 32) };
        Controls.AddRange(new Control[] { save, start, open, web });
        status.SetBounds(15, 196, 460, 76);
        status.Text = "Enter your printer address and SSH password. Save to this Windows account.";
        Controls.Add(status);
        save.Click += (s, e) => SaveSettings(true);
        start.Click += (s, e) => StartFluidd();
        open.Click += (s, e) => OpenOrca();
        web.Click += (s, e) => OpenWeb();
        LoadSettings();
        Shown += (s, e) => {
            if (opened) return;
            opened = true;
            OpenOrca();
            if (automatic.Checked && password.Text.Length > 0 && ValidAddress()) StartFluidd();
        };
    }

    bool ValidAddress()
    {
        IPAddress ip;
        if (!IPAddress.TryParse(address.Text.Trim(), out ip) ||
            ip.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork)
        {
            MessageBox.Show("Enter the printer's IPv4 address (for example, 192.168.1.100).", "Printer address");
            return false;
        }
        return true;
    }

    static string Arg(string text)
    {
        return "\"" + text.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }

    void LoadSettings()
    {
        try
        {
            if (!File.Exists(settingsPath)) return;
            var a = File.ReadAllLines(settingsPath);
            if (a.Length > 0) address.Text = a[0].Trim();
            if (a.Length > 1) automatic.Checked = a[1].Trim() == "1";
            if (a.Length > 2 && a[2].Length > 0)
            {
                var bytes = ProtectedData.Unprotect(Convert.FromBase64String(a[2]), null,
                    DataProtectionScope.CurrentUser);
                password.Text = Encoding.UTF8.GetString(bytes);
            }
        }
        catch (Exception e) { status.Text = "Settings read failed: " + e.Message; }
    }

    void SaveSettings(bool notify)
    {
        if (!ValidAddress()) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(settingsPath));
            var encrypted = ProtectedData.Protect(Encoding.UTF8.GetBytes(password.Text), null,
                DataProtectionScope.CurrentUser);
            File.WriteAllLines(settingsPath, new[] {address.Text.Trim(),
                automatic.Checked ? "1" : "0", Convert.ToBase64String(encrypted)});
            if (notify) status.Text = "Settings saved securely for this Windows user.";
        }
        catch (Exception e) { status.Text = "Settings save failed: " + e.Message; }
    }

    void OpenOrca()
    {
        string exe = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "orca-slicer.exe");
        if (!File.Exists(exe)) { status.Text = "orca-slicer.exe missing beside launcher."; return; }
        try { Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true,
            WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory }); }
        catch (Exception e) { status.Text = "Cannot start OrcaSlicer: " + e.Message; }
    }

    void OpenWeb()
    {
        if (!ValidAddress()) return;
        Process.Start("http://" + address.Text.Trim() + ":4408");
    }

    sealed class Reply
    {
        public bool TimedOut;
        public int Code;
        public string Error;
    }

    static Reply RunPlink(string exe, string host, string pass, string fingerprint)
    {
        using (var p = new Process())
        {
            string args = "-ssh -batch -noagent -pw " + Arg(pass) + " -l root -P 22 ";
            if (!string.IsNullOrEmpty(fingerprint)) args += "-hostkey " + Arg(fingerprint) + " ";
            args += host + " /usr/data/fluidd/start-fluidd.sh";
            p.StartInfo = new ProcessStartInfo {
                FileName = exe, Arguments = args, CreateNoWindow = true,
                UseShellExecute = false, RedirectStandardError = true,
                RedirectStandardOutput = true
            };
            p.Start();
            Task<string> stderr = p.StandardError.ReadToEndAsync();
            Task<string> stdout = p.StandardOutput.ReadToEndAsync();
            if (!p.WaitForExit(30000))
            {
                try { p.Kill(); } catch { }
                try { p.WaitForExit(3000); } catch { }
                return new Reply { TimedOut = true, Code = -1, Error = "SSH timed out" };
            }
            Task.WaitAll(stderr, stdout);
            return new Reply { Code = p.ExitCode, Error = stderr.Result + "\n" + stdout.Result };
        }
    }

    void StartFluidd()
    {
        if (!ValidAddress()) return;
        if (password.Text.Length == 0) { status.Text = "Enter SSH password first."; return; }
        SaveSettings(false);
        string host = address.Text.Trim();
        string pass = password.Text;
        string plink = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "plink.exe");
        if (!File.Exists(plink)) { status.Text = "plink.exe missing beside launcher."; return; }
        status.Text = "Connecting to printer and starting Fluidd...";
        Task.Run(() =>
        {
            string message;
            try
            {
                var reply = RunPlink(plink, host, pass, null);
                if (reply.Code != 0 && reply.Error.IndexOf("host key", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    var m = Regex.Match(reply.Error, @"SHA256:[A-Za-z0-9+/=]+");
                    if (m.Success)
                    {
                        var fp = m.Value;
                        DialogResult approval = DialogResult.No;
                        if (!IsDisposed && IsHandleCreated)
                        {
                            Invoke(new Action(() => approval = MessageBox.Show(this,
                                "Printer SSH fingerprint: " + fp + "\n\n" +
                                "Verify it belongs to your printer before continuing. " +
                                "Trust this fingerprint for this connection?",
                                "Confirm printer SSH identity", MessageBoxButtons.YesNo,
                                MessageBoxIcon.Warning)));
                        }
                        if (approval == DialogResult.Yes) reply = RunPlink(plink, host, pass, fp);
                    }
                }
                message = reply.TimedOut ? "Printer SSH connection timed out" :
                          reply.Code == 0 ? "Fluidd startup completed. Open http://" + host + ":4408" :
                          "SSH failed: " + reply.Error.Trim().Substring(0, Math.Min(180, reply.Error.Trim().Length));
            }
            catch (Exception e) { message = "SSH startup failed: " + e.Message; }
            if (!IsDisposed && IsHandleCreated) BeginInvoke(new Action(() => status.Text = message));
        });
    }

    [STAThread]
    static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new FluiddLauncher());
    }
}