# K1 Max CFS-C Community Installer — installation and recovery guide

**Release candidate — Windows 10/11, rooted Creality K1 Max with the native CFS-C accessory.**

This package contains a patched OrcaSlicer 2.4.2 portable build, Windows launcher, the complete original user-tested OrcaSlicer profile, webcam/NEXUSP compatibility bridge, Fluidd UI installer, and an *optional* CFS-C `form_tip.json` profile. It does **not** install, flash, replace, or modify printer firmware. It does not touch printer.cfg, box.cfg, native CFS-C calibration, or the existing print start/end macros.

## 1. Before you begin

1. Confirm the printer is **a K1 Max with CFS-C**, not a standard CFS or a different Creality model. **Do not install this package on an unsupported model.**
2. Confirm the printer has the original Creality NEXUSP API reachable on TCP 7125, root SSH access on TCP 22, Python 3.8+, nginx and ffmpeg available, and a compatible USB camera at `/dev/video0` for camera streaming. Root access must be enabled separately using supported user-level access methods; this package does not root the printer.
3. Make sure the printer is **idle**. No running print, tool/filament changes, or calibration. Export existing profiles and copy all printer-side custom configuration files to a safe PC location before installation.
4. Know the printer's **own LAN IPv4 address** and SSH password. Never copy someone else's IP address or SSH secrets from examples. Do not expose TCP 22/4408/8080 to the internet.
5. Close existing OrcaSlicer instances. Open the ZIP on a Windows 10/11 computer with PowerShell 5.1+ and at least 1 GB free space. Leave the full extracted folder together.
6. If you already have a third-party Fluidd/nginx setup, the automatic printer installer will **refuse to overwrite it**. Use a manual migration and retain your previous files.

## 2. Run the Windows installer

1. Extract **all** contents of `K1Max-CFSC-Complete-Release.zip` to a folder on your PC. Do not run Setup from inside Windows Explorer's ZIP preview.
2. Double-click **`Windows/Setup.cmd`**. You may also run `Windows/Setup.ps1` in Windows PowerShell. The script runs with a process-only execution-policy bypass; it does not alter your system-wide policy.
3. In the setup window, enter **your** printer's IPv4 address (for example, `192.168.1.100`) and root SSH password. There is no built-in printer IP address or SSH password in the rebuilt launcher. The setup package includes this precompiled launcher; Visual Studio is not needed.
4. The checkbox to install printer-side Fluidd, camera and NEXUSP bridge is optional. If the printer meets all requirements and is idle, leave it enabled and acknowledge the idle-printer check. For OrcaSlicer-only installation, uncheck the printer-side option.
5. Click **Install**. OrcaSlicer is installed into `%LOCALAPPDATA%\Programs\K1Max-CFS-C-OrcaSlicer`; a Desktop launcher shortcut is created. If the printer-side installation is selected, the script checks SSH identity, verifies the bundled Fluidd release by SHA-256, uploads the payload, verifies Python/nginx and NEXUSP, backs up existing installer-owned files, then starts the user-space services.
6. **SSH host key:** Plink may report the printer fingerprint the first time it connects or after a host key changes. Verify the fingerprint actually belongs to *your* printer before approving it. Do not approve an unexpected fingerprint without checking.
7. If printer preflight fails, read the error. Existing Creality firmware and CFS-C files are untouched. No firmware image is ever installed.

The Windows launcher starts OrcaSlicer and can start the printer's existing `/usr/data/fluidd/start-fluidd.sh` over SSH. If the launcher asks for credentials, enter your own printer's details. Do not share launcher settings containing credentials.

## 3. Import OrcaSlicer settings correctly

The package has two complete profiles under `OrcaSlicer/`:

- **`Original-Working-Profile-Big-Sexy.orca_printer`** — user's original export, exact machine G-code, PLA-Silk filament preset and 0.20 mm process preset. Provided for reference; the `NATIVE_ADAPTIVE_MESH` command is **not** guaranteed to exist on other printers.
- **`K1Max-CFS-C-Community.orca_printer`** — an independently named copy of the same tuned settings. Do not use it for your first test unless the printer has the required macros.
- **`K1Max-CFS-C-Stock-Startup.orca_printer`** — alternative profile that uses the standard Creality `START_PRINT` startup without calling custom `NATIVE_ADAPTIVE_MESH`. Prefer this for first tests on a new rooted CFS-C printer where custom macro availability is unknown. It must still be inspected for matching machine/firmware parameters.

In OrcaSlicer use **File → Import → Import Presets** (menu wording can differ by Orca version), select a `.orca_printer` file, and choose the printer/filament/process presets to import. Confirm the machine profile, printer model, nozzle size, and your process/filament settings. If the import menu expects a preset bundle, use OrcaSlicer's **Import Configs** / **Import Config Bundle** option appropriate for that version.

Go to **Printer settings → Machine G-code**, compare the start, end, before-layer-change, pause, and filament-change fields against the individual `.gcode` files in this package. The original exported `change_filament_gcode` field is **empty** — the printer's native tool selection is in the start G-code. Do not add invented change sequences. The user's tested native adaptive-mesh routine calls **`NATIVE_ADAPTIVE_MESH`**. Check in Fluidd's console that it exists (`HELP` or `printer.objects` lookup) **before** choosing that profile. If the command is absent, use the stock-startup alternative; never install KAMP or replace firmware just to satisfy this package.

Creality print-host settings: keep the **CrealityPrint** host type selected in OrcaSlicer as your setup requires. The printer's native Creality API remains on **7125**; port **4408** hosts the custom Fluidd interface and its WebSocket compatibility route, not a replacement for native print delivery.

## 4. Ports and first-run checks

| Port | Purpose | Expected test |
| --- | --- | --- |
| **22** | SSH (root user-level remote startup) | Windows installer verifies SSH login |
| **7125** | Creality's native NEXUSP printer API | Native printer/Orca print delivery is unchanged |
| **4408** | User-space Fluidd web UI and WebSocket proxy | Open `http://PRINTER-IP:4408` in a browser |
| **7126** | **Localhost-only** NEXUSP compatibility bridge | Internal; not for browser use |
| **8080** | LAN-only camera MJPEG and snapshot server | `http://PRINTER-IP:8080/stream` / `snapshot` |

When Fluidd opens, select the connection/profile that uses **4408** for Fluidd. It will proxy normal printer requests to Creality NEXUSP at 7125, provide persistent webcam listing, and handle only the unsupported `server.database.list` startup query without a red compatibility error. Camera configuration should persist after **F5** and a launcher restart.

Check that temperatures report correctly and the webcam streams. Then conduct a small supervised **single-filament** print before attempting multicolor work. Test CFS-C filament changes only after basic printing has been verified.

## 5. Optional — apply the tested `form_tip.json`

This is **NOT installed automatically**. It changes CFS-C filament-tip behavior, so compatibility must be assessed for each firmware version, material, extruder and filament path. It is not equivalent to a universal factory setting.

With the printer idle, copy the printer payload in the setup step or use the already uploaded `/usr/data/k1max-cfs-c/` folder. Log in with SSH and locate an **existing** original file:

```sh
sh /usr/data/k1max-cfs-c/apply-form-tip.sh --list
```

Read its actual path and back it up externally. Then, with the printer **idle**, and only if this profile is appropriate:

```sh
K1MAX_INSTALL_CONFIRM=IDLE sh /usr/data/k1max-cfs-c/apply-form-tip.sh --install /exact/path/to/form_tip.json
```

The script validates JSON, preserves the original beside the target with a unique `.k1max-cfsc-backup-...` suffix, and swaps only the named existing file. **Use the actual file path reported by `--list`**, not an example. Restoring means copying the saved original over the edited file while idle. Some setups need a normal restart to load changes; do not restart during a print. Because there are many material-specific sequences in this profile, first test tip forming on the chosen filament under supervision.

## 6. Printer backup and rollback

The installer stores copies of the previous installer-managed configuration at `/usr/data/k1max-cfs-c-backups/TIMESTAMP/`. Its success message identifies the exact rollback folder. **Write down that path.** From PuTTY (idle printer):

```sh
sh /usr/data/k1max-cfs-c/rollback.sh /usr/data/k1max-cfs-c-backups/EXACT_TIMESTAMP
```

The rollback restores the files backed up by this installer. It will not attempt firmware downgrades or edit CFS-C configuration. If Fluidd was installed over a pre-existing custom setup, manual reconciliation may be required; do not run the automatic installer on a non-installer-managed Fluidd installation.

OrcaSlicer Windows rollback: close OrcaSlicer and remove `%LOCALAPPDATA%\Programs\K1Max-CFS-C-OrcaSlicer` or return to your previous separate Orca install. Your Windows OrcaSlicer user profiles are stored separately from the portable program; back them up before profile changes.

## 7. Troubleshooting

- **`Method unimplemented`**: Only `server.database.list` is translated by the 4408 bridge. Verify Fluidd is using the 4408 connection, not a direct 7125 WebSocket. Do not suppress unrelated errors.
- **Camera missing after refresh**: Confirm `http://PRINTER-IP:8080/snapshot` works; verify `webcam_bridge.py` and nginx startup, and select the 4408 Fluidd connection.
- **SSH fingerprint warning**: Do not blindly accept. Verify you are connecting to the right printer and compare its host fingerprint.
- **Installer stops due to existing Fluidd**: A safety check detected an unrelated nginx/startup file. Your files were preserved; inspect/migrate manually.
- **`Unknown command: NATIVE_ADAPTIVE_MESH`**: Your K1 Max lacks the custom macro used by the tuned profile. Use the stock-startup profile. Do not modify firmware for this.
- **Printing works but camera not available**: Check for `/dev/video0`, `ffmpeg`, and camera compatibility. Printer delivery is intentionally independent of the camera.
- **No native CFS-C support in Orca**: Ensure the supplied modified OrcaSlicer 2.4.2 binary is launched instead of a different installed version.

## 8. Important limitations

- **Release candidate:** Verified against the originating owner's K1 Max CFS-C environment and source-level checks. It has **not** been field-tested across all Creality firmware versions or on another printer; do not claim universal support.
- Root SSH and custom user-space services are required for the Fluidd camera bridge. The Windows OrcaSlicer install alone doesn't require root.
- Some Creality installations use different camera devices, nginx paths, SSH settings, or NEXUSP interfaces. Preflight will stop if basic prerequisites are missing.
- The supplied original profile has a custom native-mesh macro. No firmware/Creality scripts are modified or added by this package.
- Keep original backups. Test upgrades on an idle machine and never expose these HTTP/SSH ports publicly.