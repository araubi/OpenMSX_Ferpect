openMSX 22.0 con estos cambios (ver [README_FERPECT.md](README_FERPECT.md)):

1. **Cintas TSX con los pulsos exactos**: ya no se muestrean a 58,9 kHz. Cargan cintas a 2400 baudios que antes fallaban (Congo Bongo, Rambo III, revistas de Edigamma…) y gastan unas 4 veces menos memoria.
2. **Aviso al escribir R#9/R#18 de la VDP durante un comando** (`VDP.reg_write_during_command_callback`).
3. **Aviso de escritura demasiado rápida al YM2413** (`too_fast_opll_access_callback`, issue #935 de openMSX).
4. **MSX1: escritura en la VRAM medida en un Sony HB-20P real**: se pierden bytes con 23 T o menos entre escrituras, y no con 24 T o más (antes, hasta 26 T). Arregla el mapa de War in Middle Earth.
5. **Turbo R: R800 medido en un FS-A1ST real**: en modo DRAM la BIOS ya va a velocidad de RAM (era un fallo), y los cartuchos van con 3 ciclos de espera alineados al bus de 3,5 MHz (antes 2). Todas las medidas quedan a menos de un 2,5 % del aparato.

Los avisos están desactivados por defecto. Zip para Windows de 64 bits: se descomprime, se ponen las ROM de sistema en `share/systemroms` y se ejecuta `openmsx.exe`.

Licencia GPL v2, como openMSX. No es una versión oficial de openMSX.
