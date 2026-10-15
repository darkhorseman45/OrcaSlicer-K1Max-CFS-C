GitHub repository update: keep these relative file paths exactly:
.github/workflows/build-k1max-cfs-c.yml
FluiddLauncher/FluiddLauncher.cs

The workflow still builds official OrcaSlicer v2.4.2 with the original CFS-C patch.
It ALSO creates K1Max-CFS-C-Launcher.exe inside the portable artifact, with bundled plink.exe.
Use K1Max-CFS-C-Launcher.exe rather than orca-slicer.exe to open Orca and run Fluidd startup.
The launcher displays editable printer IP, an auto-start checkbox and Start Fluidd Now.
Default IP: 192.168.68.74; default SSH password: creality_2023.
Its saved settings live under Windows AppData\\Roaming\\K1MaxCfsC\\fluidd-launcher.txt.

NOTE: This is a companion Windows EXE shipped in the OrcaSlicer folder; it does not add a menu
inside OrcaSlicer itself. This is a low-risk first implementation that preserves the CFS-C patch.
Plink's -batch mode assumes the SSH host key was already accepted on the PC; your existing
working bat setup does this. A new PC without that cached key may show a host-key error.
This version has NOT been built on GitHub Actions or run on a Windows PC yet.
WARNING: The public-known Creality SSH password is embedded in the launcher and visible to anyone.
