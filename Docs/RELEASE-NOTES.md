# Community release candidate — 2026-10-20

- Bundled user's successfully built OrcaSlicer 2.4.2 with K1 Max CFS-C routing fix.
- Included a separately rebuilt configurable launcher that requires each owner to enter their own IP address and SSH password, and encrypted local setting storage.
- Bundled installer for user-space Fluidd, Python camera capture, local WebSocket bridge and 4408 nginx routing.
- Included the **specific** `server.database.list` workaround that removed the red `Method unimplemented` Fluidd startup message on the originating unit. Does not fake unrelated printer RPC results.
- Included complete user's exported Orca printer/filament/process presets, individual G-code sections, and separate stock-startup alternative.
- Included an optional, validated `form_tip.json` with file-specific backup.
- Printer-side rollback and preflight checks; no firmware modifications.

**Status:** Packaging/source validation completed; not tested on a second K1 Max CFS-C. It is a release candidate, not a claim of universal hardware compatibility.