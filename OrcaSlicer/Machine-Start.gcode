; K1 Max CFS-C - Native Adaptive Mesh

START_PRINT EXTRUDER_TEMP=[nozzle_temperature_initial_layer] BED_TEMP=[bed_temperature_initial_layer_single]

; Cool nozzle to prevent filament dripping during probing
M109 S140

RESPOND MSG="BEFORE NATIVE MESH"

NATIVE_ADAPTIVE_MESH

RESPOND MSG="AFTER NATIVE MESH"

; Restore printing temperature and wait
M109 S[nozzle_temperature_initial_layer]

; Select correct CFS-C filament
T[initial_no_support_extruder]

M204 S2000
G1 Z3 F600
M83
G92 E0
G1 Z1 F600