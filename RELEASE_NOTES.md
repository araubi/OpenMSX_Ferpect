openMSX 22.0 con estos cambios (ver [README_FERPECT.md](README_FERPECT.md)):

1. **Cintas TSX con los pulsos exactos**: ya no se muestrean a 58,9 kHz. Cargan cintas a 2400 baudios que antes fallaban (Congo Bongo, Rambo III, revistas de Edigamma…) y gastan unas 4 veces menos memoria.
2. **Aviso al escribir R#9/R#18 de la VDP durante un comando** (`VDP.reg_write_during_command_callback`).
3. **Aviso de escritura demasiado rápida al YM2413** (`too_fast_opll_access_callback`, issue #935 de openMSX).
4. **MSX1: escritura en la VRAM medida en un Sony HB-20P real**: se pierden bytes con 23 T o menos entre escrituras, y no con 24 T o más (antes, hasta 26 T). Arregla el mapa de War in Middle Earth. **v0.22e:** en las máquinas con chip de Texas (TMS9918A/9928A/9929A), medido en un Toshiba HX-10D, se pierden también con 24 y 25 T; las de chip Toshiba (T6950, como el HB-20P) siguen igual.
5. **Turbo R: R800 medido en un FS-A1ST real**: en modo DRAM la BIOS ya va a velocidad de RAM (era un fallo), y los cartuchos van con 3 ciclos de espera alineados al bus de 3,5 MHz (antes 2). Todas las medidas quedan a menos de un 2,5 % del aparato.
6. **V9990 (GFX9000): WAIT emulado**, medido en un FS-A1ST con un GFX9000. Un acceso suelto a la VRAM no espera, pero los accesos seguidos con la imagen encendida sí: en P1 más que en B1, y con el R800 bastante (escribir la VRAM hasta un 55 % más lento, leerla hasta el doble). Antes, openMSX no frenaba nunca.
7. **MSX1: carrera del flag F medida en un Toshiba HX-21** (v0.22f): al esperar el cuadro leyendo S#0 en bucle, los VDP de MSX1 pierden menos cuadros que el V9938 (ventana de unos 1,9 T en vez de 4,7). FERPECT da ahora lo mismo que el aparato. **v0.22h:** el TMS9918A (HX-10D) y el Toshiba T6950A (HB-20P) pierden la mitad que el TMS9928A (ventana de 1 T); el TMS9928A/9929A mantiene la de 1,9 T.
8. **MSX1 (chips Toshiba): cómo se pierde un byte en la VRAM, medido en el HB-20P** (v0.22i). Si una escritura llega demasiado pronto, la VDP hace la anterior con el dato nuevo y el puntero avanza igual: queda un byte mal y otro sin escribir, pero el resto en su sitio (openMSX corría todo lo que venía detrás). Y la fase entre el Z80 y la VDP se elige al azar en cada arranque, como en el aparato, que unos días pierde bytes con 24-25 T y otros no (`VDP.msx1_phase` para fijarla). War in Middle Earth sale ahora como en el HB-20P: limpio o con algún punto suelto junto al cursor.

Los avisos están desactivados por defecto. Zip para Windows de 64 bits: se descomprime, se ponen las ROM de sistema en `share/systemroms` y se ejecuta `openmsx.exe`.

Licencia GPL v2, como openMSX. No es una versión oficial de openMSX.
