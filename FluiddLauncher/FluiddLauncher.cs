using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Threading.Tasks;
using System.Windows.Forms;

internal sealed class FluiddLauncher : Form
{
    private readonly TextBox address = new TextBox();
    private readonly CheckBox automatic = new CheckBox();
    private readonly Label status = new Label();
    private readonly string settingsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "K1MaxCfsC", "fluidd-launcher.txt");
    private bool launched = false;

    public FluiddLauncher()
    {
        Text = "OrcaSlicer K1 Max CFS-C - Fluidd";
        ClientSize = new Size(445, 222);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        var title = new Label { Text = "K1 Max Fluidd startup", Font = new Font(Font.FontFamily, 11f, FontStyle.Bold), AutoSize = true, Location = new Point(17, 15) };
        var caption = new Label { Text = "Printer IP address:", AutoSize = true, Location = new Point(18, 56) };
        address.Location = new Point(145, 51);
        address.Width = 270;
        address.Text = "192.168.68.74";
        automatic.Text = "Start Fluidd automatically when OrcaSlicer opens";
        automatic.Location = new Point(18, 92);
        automatic.Width = 405;
        automatic.Checked = true;
        var save = new Button { Text = "Save Settings", Location = new Point(17, 132), Width = 115 };
        var start = new Button { Text = "Start Fluidd Now", Location = new Point(142, 132), Width = 133 };
        var open = new Button { Text = "Open OrcaSlicer", Location = new Point(285, 132), Width = 138 };
        status.Location = new Point(17, 174);
        status.Size = new Size(407, 40);
        status.Text = "Ready";
        Controls.AddRange(new Control[] { title, caption, address, automatic, save, start, open, status });
        LoadSettings();
        save.Click += (s, e) => SaveSettings(true);
        start.Click += (s, e) => StartFluidd();
        open.Click += (s, e) => OpenOrca();
        Shown += (s, e) => { if (!launched) { launched = true; OpenOrca(); if (automatic.Checked) StartFluidd(); } };
    }

    private bool ValidAddress()
    {
        string host = address.Text.Trim();
        IPAddress parsed;
        if (host.Length == 0 || !IPAddress.TryParse(host, out parsed) || parsed.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork)
        {
            MessageBox.Show("Enter a valid IPv4 printer address, for example 192.168.68.74.", "Printer IP", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }
        return true;
    }

    private void LoadSettings()
    {
        try
        {
            if (!File.Exists(settingsPath)) return;
            var lines = File.ReadAllLines(settingsPath);
            if (lines.Length > 0) address.Text = lines[0].Trim();
            if (lines.Length > 1) automatic.Checked = lines[1].Trim() == "1";
        }
        catch (Exception ex) { status.Text = "Settings load error: " + ex.Message; }
    }

    private void SaveSettings(bool notify)
    {
        if (!ValidAddress()) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(settingsPath));
            File.WriteAllLines(settingsPath, new[] { address.Text.Trim(), automatic.Checked ? "1" : "0" });
            if (notify) status.Text = "Settings saved";
        }
        catch (Exception ex) { status.Text = "Settings save error: " + ex.Message; }
    }

    private void OpenOrca()
    {
        var exe = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "orca-slicer.exe");
        if (!File.Exists(exe)) { status.Text = "orca-slicer.exe not found beside launcher"; return; }
        try
        {
            Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory, UseShellExecute = true });
        }
        catch (Exception ex) { status.Text = "OrcaSlicer launch failed: " + ex.Message; }
    }

    private void StartFluidd()
    {
        if (!ValidAddress()) return;
        SaveSettings(false);
        string host = address.Text.Trim();
        string plink = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "plink.exe");
        if (!File.Exists(plink)) { status.Text = "Missing plink.exe from portable folder"; return; }
        status.Text = "Starting Fluidd at " + host + " ...";
        Task.Run(() =>
        {
            string result;
            try
            {
                using (var p = new Process())
                {
                    p.StartInfo = new ProcessStartInfo
                    {
                        FileName = plink,
                        Arguments = "-ssh -batch -noagent -pw creality_2023 -l root -P 22 -connect-timeout 5 " + host + " /usr/data/fluidd/start-fluidd.sh",
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        RedirectStandardError = true,
                        RedirectStandardOutput = true
                    };
                    p.Start();
                    if (!p.WaitForExit(15000)) { try { p.Kill(); } catch { } result = "SSH startup timed out"; }
                    else
                    {
                        var error = p.StandardError.ReadToEnd().Trim();
                        result = p.ExitCode == 0 ? "Fluidd startup command completed" : "SSH failed: " + (error.Length > 150 ? error.Substring(0, 150) : error);
                    }
                }
            }
            catch (Exception ex) { result = "Fluidd startup error: " + ex.Message; }
            if (!IsDisposed && IsHandleCreated) BeginInvoke(new Action(() => status.Text = result));
        });
    }

    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new FluiddLauncher());
    }
}
