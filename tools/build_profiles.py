#!/usr/bin/env python3
"""Rebuild the three OrcaSlicer .orca_printer preset bundles from source JSON.

Usage: python tools/build_profiles.py
No external dependencies. Reproduces all original printer/process/filament settings;
the original vendor export is also shipped byte-for-byte in the release ZIP.
"""
from __future__ import annotations
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Source' / 'presets'
OUT = ROOT / 'OrcaSlicer'
ORIGINAL = json.loads((SOURCE / 'printer' / 'Big Sexy.json').read_text(encoding='utf-8'))
BASE_BUNDLE = json.loads((SOURCE / 'bundle_structure.json').read_text(encoding='utf-8'))

profiles = [
    ('Original-Working-Profile-Big-Sexy.orca_printer', 'Big Sexy', 'Big Sexy', None),
    ('K1Max-CFS-C-Community.orca_printer', 'K1 Max CFS-C Community', 'K1 Max CFS-C Community', None),
    ('K1Max-CFS-C-Stock-Startup.orca_printer', 'K1 Max CFS-C Stock Startup', 'K1 Max CFS-C Stock Startup',
     '; K1 Max CFS-C - stock START_PRINT profile (no custom adaptive mesh macro)\n'
     'START_PRINT EXTRUDER_TEMP=[nozzle_temperature_initial_layer] BED_TEMP=[bed_temperature_initial_layer_single]\n'
     '; Do not add NATIVE_ADAPTIVE_MESH unless it is installed and verified\n'
     'T[initial_no_support_extruder]\n'
     'M204 S2000\nG1 Z3 F600\nM83\nG92 E0\nG1 Z1 F600\n'),
]


def write_profile(filename: str, name: str, profile_id: str, override_start: str | None) -> None:
    profile = dict(ORIGINAL)
    profile['name'] = name if name != 'K1 Max CFS-C Stock Startup' else 'K1 Max CFS-C Community'
    profile['printer_settings_id'] = profile_id
    if override_start is not None:
        profile['machine_start_gcode'] = override_start
    printer_path = f'printer/{profile_id}.json'
    structure = dict(BASE_BUNDLE)
    structure['printer_config'] = [printer_path]
    structure['printer_preset_name'] = name
    structure['bundle_id'] = '_' + name.replace(' ', ' ') + '_20261020'
    dest = OUT / filename
    dest.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(dest, 'w', ZIP_DEFLATED) as archive:
        archive.writestr(printer_path, json.dumps(profile, ensure_ascii=False, indent=2) + '\n')
        for subdir in ['filament', 'process']:
            for entry in structure[f'{subdir}_config']:
                archive.write(SOURCE / entry, entry)
        archive.writestr('bundle_structure.json', json.dumps(structure, ensure_ascii=False, indent=2) + '\n')
    print('Built', dest.relative_to(ROOT))


if __name__ == '__main__':
    for args in profiles:
        write_profile(*args)