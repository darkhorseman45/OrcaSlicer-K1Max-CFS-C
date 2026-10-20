# K1 Max CFS-C Community Setup (Windows 10/11 PowerShell 5.1)
# Installs bundled portable OrcaSlicer, and optionally deploys reversible user-space Fluidd services.
# No firmware, printer.cfg or CFS box.cfg edits. No baked-in network addresses or credentials.
param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$orcaArchive = Join-Path $root 'Windows\OrcaSlicer-2.4.2-K1Max-CFS-C-Windows.zip'
$printerArchive = Join-Path $root 'Windows\PrinterPayload.zip'
$dest = Join-Path $env:LOCALAPPDATA 'Programs\K1Max-CFS-C-OrcaSlicer'
$fluiddUrl = 'https://github.com/fluidd-core/fluidd/releases/download/v1.37.7/fluidd.zip'
$fluiddBundled = Join-Path $root 'Windows\fluidd-v1.37.7.zip'
$newLauncherBinary = Join-Path $root 'Windows\K1Max-CFS-C-Launcher.exe'
$fluiddHash = 'e45889071dae4e79f22e38bfb28cad0ce0c89e134c09d174cd447c4c93bd9556'

function Assert-Prerequisites {
    if (!(Test-Path $orcaArchive)) { throw "Missing bundled modified OrcaSlicer: $orcaArchive" }
    if (!(Test-Path $printerArchive)) { throw "Missing printer payload: $printerArchive" }
    if (!(Test-Path $newLauncherBinary)) { throw "Missing rebuilt configurable launcher: $newLauncherBinary" }
    if (!([Environment]::OSVersion.Platform -eq 'Win32NT')) { throw 'Requires Windows.' }
    if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'Requires Windows PowerShell 5.1.' }
}
function Quote-Arg([string]$s) { '"' + ($s.Replace('\','\\').Replace('"','\"')) + '"' }
function Invoke-Plink([string]$plink,[string]$ip,[string]$pw,[string]$fingerprint,[string]$command,[byte[]]$inputBytes=$null) {
    $args = '-ssh -batch -noagent -l root -P 22 -pw ' + (Quote-Arg $pw)
    if ($fingerprint) { $args += ' -hostkey ' + (Quote-Arg $fingerprint) }
    $args += ' ' + $ip + ' ' + (Quote-Arg $command)
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName=$plink; $start.Arguments=$args; $start.UseShellExecute=$false
    $start.RedirectStandardError=$true; $start.RedirectStandardOutput=$true
    $start.RedirectStandardInput=$true; $start.CreateNoWindow=$true
    $p = [System.Diagnostics.Process]::Start($start)
    try {
        $errTask=$p.StandardError.ReadToEndAsync()
        $outTask=$p.StandardOutput.ReadToEndAsync()
        if ($null -ne $inputBytes) { $p.StandardInput.BaseStream.Write($inputBytes,0,$inputBytes.Length) }
        $p.StandardInput.Close()
        if (!$p.WaitForExit(120000)) { $p.Kill(); throw 'SSH command timed out (120s).' }
        [System.Threading.Tasks.Task]::WaitAll(@($errTask,$outTask))
        return @{ Code=$p.ExitCode; Error=$errTask.Result; Output=$outTask.Result }
    } finally { $p.Dispose() }
}
function Log([string]$message) {
    $logBox.AppendText("$message`r`n")
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}
function Check-IP([string]$hostIP) {
    $addr = $null
    if (![System.Net.IPAddress]::TryParse($hostIP,[ref]$addr)) { throw 'Enter a valid printer IPv4 address.' }
    if ($addr.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { throw 'IPv4 only.' }
}
function Download-Fluidd([string]$target) {
    if (Test-Path -LiteralPath $fluiddBundled) {
        Log 'Using bundled Fluidd v1.37.7 (offline)...'
        Copy-Item -LiteralPath $fluiddBundled -Destination $target -Force
    } else {
        Log 'Downloading the pinned Fluidd v1.37.7 UI from GitHub...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $fluiddUrl -OutFile $target
    }
    $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    if ($got -ne $fluiddHash) { throw "Fluidd SHA256 checksum mismatch. Download aborted. Actual hash: $got" }
    Log 'Fluidd UI SHA256 checksum verified.'
}
function Install-Orca {
    Log 'Installing the bundled modified OrcaSlicer 2.4.2 portable build...'
    if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    Expand-Archive -LiteralPath $orcaArchive -DestinationPath $dest -Force
    $exe = Join-Path $dest 'orca-slicer.exe'
    $launcher=Join-Path $dest 'K1Max-CFS-C-Launcher.exe'
    $plink=Join-Path $dest 'plink.exe'
    foreach($p in @($exe,$launcher,$plink)) { if (!(Test-Path $p)) { throw "Incomplete bundled OrcaSlicer build: $p" } }
    # Replace the older embedded-defaults launcher supplied in the historical
    # Orca build with the standalone, rebuilt, per-owner-configurable version.
    # No C# compiler or Visual Studio is required on an end user's PC.
    Copy-Item -LiteralPath $newLauncherBinary -Destination $launcher -Force
    Log 'Installed the rebuilt configurable launcher (no embedded IP/password).'
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'OrcaSlicer K1Max CFS-C.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath=$launcher; $shortcut.WorkingDirectory=$dest
    $shortcut.Description='Modified OrcaSlicer 2.4.2 for K1 Max CFS-C'
    $shortcut.Save()
    Log "OrcaSlicer installed in: $dest"
    Log 'Desktop launcher shortcut created.'
}
function Install-Printer([string]$ip,[string]$pw) {
    if (!$modelCheck.Checked) { throw 'Confirm this printer is a Creality K1 Max with the native CFS-C system.' }
    if (!$idle.Checked) { throw 'Confirm the printer is idle before a printer-side install.' }
    Check-IP $ip
    if (!$pw) { throw 'The printer root SSH password is required.' }
    $plink = Join-Path $dest 'plink.exe'
    if (!(Test-Path $plink)) { throw 'Install bundled OrcaSlicer first (plink.exe missing).' }
    Log "Checking root SSH access to ${ip}:22..."
    $probe=Invoke-Plink $plink $ip $pw '' 'echo K1MAX-SSH-READY'
    $key=''
    if ($probe.Code -ne 0 -and $probe.Error -match 'SHA256:[A-Za-z0-9+/=]+') {
        $key = $Matches[0]
        $msg = "The printer reports SSH fingerprint:`n$key`n`nVerify this matches YOUR printer (out-of-band), particularly if its host key has changed. Trust this identity for this installation?"
        $answer=[System.Windows.Forms.MessageBox]::Show($msg,'Confirm printer SSH key',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($answer -ne 'Yes') { throw 'SSH host key was not approved; printer installation canceled.' }
        $probe=Invoke-Plink $plink $ip $pw $key 'echo K1MAX-SSH-READY'
    }
    if ($probe.Code -ne 0 -or $probe.Output -notmatch 'K1MAX-SSH-READY') { throw "SSH connection failed: $($probe.Error)" }
    Log 'Printer root SSH authentication successful.'
    $tmp = Join-Path $env:TEMP ('K1Max-CFSC-'+[Guid]::NewGuid().ToString('N'))
    New-Item -Path $tmp -ItemType Directory | Out-Null
    try {
        $fluiddZip=Join-Path $tmp 'fluidd.zip'
        Download-Fluidd $fluiddZip
        $payload=Join-Path $tmp 'payload'
        New-Item -Path $payload -ItemType Directory | Out-Null
        Expand-Archive -LiteralPath $printerArchive -DestinationPath $payload -Force
        $ui = Join-Path $payload 'ui'
        New-Item -Path $ui -ItemType Directory | Out-Null
        Expand-Archive -LiteralPath $fluiddZip -DestinationPath $ui -Force
        if (!(Test-Path (Join-Path $ui 'index.html'))) { throw 'Fluidd UI package did not contain index.html.' }
        $allZip=Join-Path $tmp 'printer-full.zip'
        Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $allZip -CompressionLevel Optimal
        $result=Invoke-Plink $plink $ip $pw $key 'mkdir -p /usr/data/k1max-cfs-c && cat > /usr/data/k1max-cfs-c/setup-payload.zip' ([IO.File]::ReadAllBytes($allZip))
        if ($result.Code -ne 0) { throw "Printer package transfer failed: $($result.Error)" }
        Log 'Printer payload uploaded.'
        $extract = 'python3 -c "import zipfile;zipfile.ZipFile(''/usr/data/k1max-cfs-c/setup-payload.zip'').extractall(''/usr/data/k1max-cfs-c'')"'
        $result=Invoke-Plink $plink $ip $pw $key $extract
        if ($result.Code -ne 0) { throw "Could not unpack printer payload: $($result.Error)" }
        Log 'Running pre-installation checks on the printer...'
        $check=Invoke-Plink $plink $ip $pw $key 'sh /usr/data/k1max-cfs-c/install.sh --check'
        Log ($check.Output.Trim()); if ($check.Code -ne 0) { throw "Printer preflight failed: $($check.Error)" }
        $cmd="K1MAX_INSTALL_CONFIRM=IDLE K1MAX_PRINTER_IP=$ip sh /usr/data/k1max-cfs-c/install.sh --install"
        $done=Invoke-Plink $plink $ip $pw $key $cmd
        Log ($done.Output.Trim()); if ($done.Code -ne 0) { throw "Printer install failed: $($done.Error)" }
        Log "Printer installed. Open Fluidd: http://${ip}:4408"
        Log 'Optional form_tip.json is NOT installed automatically. Read Docs/INSTALLATION.md first.'
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Assert-Prerequisites
if ($VerifyOnly) { Write-Host 'Setup prerequisites: OK'; exit 0 }
$form=New-Object System.Windows.Forms.Form
$form.Text='K1 Max CFS-C - Community Installer'; $form.Width=720; $form.Height=580
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false
$label = New-Object System.Windows.Forms.Label
$label.Text='K1 Max CFS-C | OrcaSlicer + Fluidd + Camera'; $label.AutoSize=$true
$label.Left=18; $label.Top=16; $label.Font=New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
$form.Controls.Add($label)
$desc = New-Object System.Windows.Forms.Label
$desc.Text='Installs modified OrcaSlicer locally. Optionally install user-space printer services (root SSH, nginx, Python, and internet required).'
$desc.SetBounds(18,48,660,44); $form.Controls.Add($desc)
$ipLabel=New-Object System.Windows.Forms.Label
$ipLabel.Text='Printer IPv4 address:'; $ipLabel.SetBounds(18,101,155,24); $form.Controls.Add($ipLabel)
$ipText=New-Object System.Windows.Forms.TextBox
$ipText.SetBounds(175,98,230,27); $form.Controls.Add($ipText)
$passLabel=New-Object System.Windows.Forms.Label
$passLabel.Text='Root SSH password:'; $passLabel.SetBounds(18,138,150,24); $form.Controls.Add($passLabel)
$passText=New-Object System.Windows.Forms.TextBox
$passText.SetBounds(175,135,230,27); $passText.UseSystemPasswordChar=$true; $form.Controls.Add($passText)
$printerCheck=New-Object System.Windows.Forms.CheckBox
$printerCheck.Text='Also install printer-side Fluidd, webcam, and database compatibility bridge'; $printerCheck.SetBounds(18,177,650,26)
$printerCheck.Checked=$true; $form.Controls.Add($printerCheck)
$modelCheck=New-Object System.Windows.Forms.CheckBox
$modelCheck.Text='I confirm this is a Creality K1 Max with native CFS-C (NOT standard CFS)'
$modelCheck.SetBounds(18,211,665,26)
$form.Controls.Add($modelCheck)
$idle=New-Object System.Windows.Forms.CheckBox
$idle.Text='I confirm my printer is idle, with no print or filament change underway'; $idle.SetBounds(18,238,660,26)
$form.Controls.Add($idle)
$install=New-Object System.Windows.Forms.Button
$install.Text='Install'; $install.SetBounds(18,276,115,35); $form.Controls.Add($install)
$logBox=New-Object System.Windows.Forms.TextBox
$logBox.SetBounds(18,327,665,170); $logBox.Multiline=$true; $logBox.ScrollBars='Vertical'; $logBox.ReadOnly=$true
$logBox.Font=New-Object System.Drawing.Font('Consolas',9); $form.Controls.Add($logBox)
Log 'Ready. The install can be run for OrcaSlicer only, or with optional printer services.'
$install.Add_Click({
    $install.Enabled=$false
    $form.UseWaitCursor=$true
    try {
        Install-Orca
        if ($printerCheck.Checked) { Install-Printer $ipText.Text.Trim() $passText.Text }
        Log 'SETUP COMPLETE. Import OrcaSlicer profiles as described in Docs/INSTALLATION.md.'
        [System.Windows.Forms.MessageBox]::Show('Installation complete. Read Docs/INSTALLATION.md for the Orca profile selection and optional form_tip.json.', 'K1 Max CFS-C') | Out-Null
    } catch { Log ('ERROR: '+ $_.Exception.Message); [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Installation stopped',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null }
    finally { $form.UseWaitCursor=$false; $install.Enabled=$true }
})
[void]$form.ShowDialog()