#!/bin/sh
# Optional filament-tip profile replacement; requires explicit, existing target.
set -eu
SRC=/usr/data/k1max-cfs-c/optional/form_tip.json
case "${1:-}" in
  --list)
    echo 'Possible existing form_tip.json files:'
    find /usr/data -name form_tip.json -type f 2>/dev/null || true
    exit 0;;
  --install)
    TARGET=${2:-};;
  *) echo 'Usage: sh apply-form-tip.sh --list | --install /absolute/path/to/existing/form_tip.json'; exit 2;;
esac
[ "$(id -u)" = 0 ] || { echo 'ERROR: root SSH required'; exit 1; }
[ "${K1MAX_INSTALL_CONFIRM:-}" = IDLE ] || { echo 'ERROR: confirm printer is idle with K1MAX_INSTALL_CONFIRM=IDLE'; exit 1; }
case "$TARGET" in /*/form_tip.json) ;; *) echo 'ERROR: provide full path to an existing form_tip.json'; exit 1;; esac
[ -f "$TARGET" ] && [ ! -L "$TARGET" ] || { echo 'ERROR: target missing or symlink'; exit 1; }
[ -f "$SRC" ] || { echo 'ERROR: packaged source not installed'; exit 1; }
/usr/bin/python3 - "$SRC" "$TARGET" <<'PY'
import sys,json
for f in sys.argv[1:]:
    with open(f) as h: d=json.load(h)
    if not isinstance(d,dict) or 'version' not in d: raise SystemExit('Invalid form_tip.json: '+f)
print('Validated both form_tip.json files')
PY
BACKUP="${TARGET}.k1max-cfsc-backup-$(date +%Y%m%d-%H%M%S)-$$"
cp -p "$TARGET" "$BACKUP"
cp "$SRC" "${TARGET}.k1max-cfsc-stage-$$"
chmod --reference="$TARGET" "${TARGET}.k1max-cfsc-stage-$$" 2>/dev/null || true
mv "${TARGET}.k1max-cfsc-stage-$$" "$TARGET"
echo "Optional form_tip.json installed; original preserved at $BACKUP"
echo 'Reboot only if required by your existing CFS-C configuration workflow, with printer idle.'