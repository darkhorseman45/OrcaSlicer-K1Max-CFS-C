# K1 Max CFS-C — OrcaSlicer + Fluidd community installer

**Community release candidate | 2026-10-20.** User-space toolkit for **rooted Creality K1 Max equipped with native CFS-C**. Original working configuration provided by project owner and adapted into a portable, reversible installer.

**No firmware replacement. No CFS-C disabling. No KAMP installation.** The printer's stock NEXUSP interface and Creality toolchange functionality remain untouched.

## Download and install

Use the **complete ZIP release**, not GitHub's automatic "Source code" archive; it includes the compiled Windows OrcaSlicer binaries. Extract all files, read `Docs/INSTALLATION.md`, and launch `Windows/Setup.cmd` on Windows 10/11. A new printer must have root SSH access, nginx, Python 3.8+ and ffmpeg available for the optional Fluidd/camera services. The release contains the complete modified OrcaSlicer 2.4.2, launcher, profiles, G-code, user-level printer services, optional `form_tip.json`, rollback and guide.

**Connection ports:** Creality NEXUSP printing 7125; Fluidd with webcam adapter 4408; camera `/stream` on 8080; local-only bridge 7126. The `server.database.list` shim handles the specific unsupported NEXUSP RPC that previously caused Fluidd's `Method unimplemented` popup. Normal printer errors are **not** suppressed.

The owner's original preset calls `NATIVE_ADAPTIVE_MESH` (a machine-specific installed macro). Other owners should import the stock-startup alternative unless their macro is confirmed. The CFS-C `form_tip.json` profile is **manual and optional** because filament behavior varies with machine and firmware.

## Repository structure

- `FluiddLauncher/FluiddLauncher.cs`: IP/password-configurable Windows launcher; stored credentials encrypted for the local Windows user.
- `.github/workflows/build-fluidd-launcher-only.yml`: builds the launcher without embedding a specific LAN IP or password.
- `.github/workflows/build-k1max-cfs-c.yml`: builds the modified OrcaSlicer v2.4.2 portable Windows binary.
- `.github/workflows/prepare-fluidd-ui.yml`: downloads and checksum-verifies the pinned Fluidd UI.
- `Windows/Setup.ps1` and `Windows/Setup.cmd`: guided installer.
- `Printer/`: reversible bridge, webcam, nginx, installation/rollback, and optional tip forming profile.
- `OrcaSlicer/`: printer G-code and importable preset bundle examples (included in full release ZIP).
- `Docs/INSTALLATION.md`: complete installation, preflight, importing, optional CFS-C settings, testing and recovery.

## Builds and limitations

The modified OrcaSlicer app is built using the official OrcaSlicer `v2.4.2` tag with a targeted CrealityPrint.cpp patch. Its compiled build is distributed in the **release ZIP/Actions artifacts**, not stored in Git history. Fluidd is upstream open-source software and remains separately licensed; follow `LICENSE.txt` in the bundled OrcaSlicer distribution and Fluidd upstream licenses.

**No universal guarantee:** The scripts are based on one working K1 Max CFS-C environment. They have not been field-verified on every Creality firmware, and the release should be treated as a candidate until tested on a second printer. The printer installer rejects an unrelated existing nginx/Fluidd configuration rather than clobbering it.