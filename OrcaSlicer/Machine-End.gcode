; --- K1 Max CFS-C End G-code for Orca Slicer ---

M400 ; Clear buffer / Wait for all current moves to finish

G92 E0 ; Reset extrusion distance

G1 E-1.5 F1200 ; Small safety retraction to clear nozzle pressure

; Safely park the toolhead away from the printed object

G91 ; Relative positioning

G1 Z10 F600 ; Drop the bed by 10mm
G90 ; Absolute positioning

G1 X10 Y240 F12000 ; Park toolhead to the rear-left safely out of the way


; Hand off to the firmware shutdown routines

END_PRINT ; Triggers Creality's native macro to turn off heaters, bed, and fans


M84 ; Disable stepper motors