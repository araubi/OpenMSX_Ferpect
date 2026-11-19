openMSX 22.0 con tres cambios (ver [README_FERPECT.md](README_FERPECT.md)):

1. **Cintas TSX con los pulsos exactos**: ya no se muestrean a 58,9 kHz. Cargan cintas a 2400 baudios que antes fallaban (Congo Bongo, Rambo III, revistas de Edigamma…) y gastan unas 4 veces menos memoria.
2. **Aviso al escribir R#9/R#18 de la VDP durante un comando** (`VDP.reg_write_during_command_callback`).
3. **Aviso de escritura demasiado rápida al YM2413** (`too_fast_opll_access_callback`, issue #935 de openMSX).

Los avisos están desactivados por defecto. Zip para Windows de 64 bits: se descomprime, se ponen las ROM de sistema en `share/systemroms` y se ejecuta `openmsx.exe`.

Licencia GPL v2, como openMSX. No es una versión oficial de openMSX.
