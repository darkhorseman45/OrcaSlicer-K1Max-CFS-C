# K1 Max CFS-C — START HERE

This is a **release candidate** for a ROOTED **Creality K1 Max with CFS-C**. It includes the modified OrcaSlicer v2.4.2 portable application, an Orca/Fluidd launcher, Fluidd webcam and NEXUSP compatibility services, the original tested machine profiles, and an optional CFS-C `form_tip.json`.

1. Read **`Docs/INSTALLATION.md`** before changing the printer.
2. Extract the full release ZIP on Windows 10/11.
3. Run **`Windows/Setup.cmd`**.
4. Enter **your own** printer IP and root SSH password and confirm the printer is idle.
5. The installer checks prerequisites and makes backups. If it detects an existing unrelated Fluidd setup, it stops safely rather than replacing it.
6. Import one of the `.orca_printer` preset bundles from `OrcaSlicer/`. For unknown custom-macro configurations, start with `K1Max-CFS-C-Stock-Startup.orca_printer`.
7. Visit `http://YOUR-PRINTER-IP:4408`; normal Creality NEXUSP stays on 7125.
8. `form_tip.json` is **optional**; it is never applied automatically.

**No firmware flashing, replacements, or CFS-C disabling.** Not tested on standard CFS or other printer models.