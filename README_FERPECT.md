# openMSX FERPECT

Versión de **openMSX 22.0** (código de [openMSX/openMSX](https://github.com/openMSX/openMSX), commit `b34dbbd`) con tres cambios pensados para quien carga cintas TSX y para quien programa para MSX. Sirve para probarlos antes de proponerlos al proyecto original.

Todo lo demás es openMSX tal cual: mismas máquinas, mismas ROM de sistema (`share/systemroms`), mismos ajustes.

## Cambios

### 1. Cintas TSX: pulsos con su duración exacta

openMSX convertía cada TSX en una onda muestreada a 58 900 Hz, de modo que cada pulso podía alargarse o acortarse hasta 17 µs. A 1200 baudios eso no importa, pero a 2400 baudios (pulsos de unos 100 µs) muchas cintas ni siquiera pasan la detección de cabecera de la BIOS.

Ahora la cinta se guarda como una lista de tramos con su duración exacta en T-states (3,5 MHz, la unidad del formato TZX), y el MSX lee el nivel justo en el instante en que lo pide. El sonido de la cinta se sigue generando a 58 900 Hz. Además ocupa mucha menos memoria: una cinta de revista de 41 minutos pasa de unos 145 MB a unos 33 MB.

Pruebas hechas:
- Congo Bongo (Sega, 2400 baudios) y una cinta de revista de Edigamma no llegaban a «Found:» y ahora cargan.
- Con 37 TSX de una colección de cintas en un Sony HB-20P, en 6 minutos de emulación, 25 terminan igual que con openMSX 22.0 y en 7 solo cambia el momento de la demo. Las 5 restantes van mejor: Rambo III (que antes no cargaba), Asquad, Score 3020, Shit! y Livingstone... I Presume.
- Ninguna cinta probada carga peor.

Si una TSX sigue sin cargar, puede que el fallo esté en la propia TSX. Por ejemplo, un cargador que necesite un hueco entre bytes que el bloque 4B no conserva (2 bits de parada en vez de 3). Eso no se arregla en el emulador.

### 2. Aviso al escribir R#9 o R#18 de la VDP durante un comando

En un V9938/V9958 real, escribir R#9 o R#18 mientras se ejecuta un comando de la VDP (CE = 1) lo estropea. openMSX no lo emula porque el efecto exacto no se conoce. Ahora puede avisar:

```
set VDP.reg_write_during_command_callback regwriteduringcommandcallback
```

Muestra el registro, el valor y el PC. Fuentes:
- Nota del editor en la transcripción del *V9938 Technical Data Book* de Grauw ([map.grauw.nl](https://map.grauw.nl/resources/video/v9938/v9938.xhtml)).
- *MSX Documents*, de HRA! (Takayuki Hara) ([hra1129/msx_documents](https://github.com/hra1129/msx_documents)).

### 3. Aviso de escritura demasiado rápida al YM2413 (MSX-MUSIC / FM-PAC)

El YM2413 necesita 12 ciclos (a 3,58 MHz) después de escribir la dirección y 84 después de escribir el dato. En un turbo R en modo R800, o con código Z80 muy apretado, es fácil ir más deprisa. En el aparato real esas escrituras se pierden, pero en openMSX la música suena bien. Es la propuesta del [issue #935](https://github.com/openMSX/openMSX/issues/935) de openMSX, con las medidas de Grauw. Para activarlo:

```
set too_fast_opll_access_callback toofastopllaccesscallback
```

Avisa por la consola de errores con el puerto (0 = dirección, 1 = dato) y el nombre del aparato. Usa el tiempo emulado, así que no depende de la velocidad ni del procesador elegidos.

Los dos avisos están **desactivados por defecto** y no cambian la emulación. Para quitarlos, basta con dejar el ajuste vacío (`set too_fast_opll_access_callback ""`).

## Descarga

En [Releases](../../releases) está el zip para Windows de 64 bits. Se descomprime y se ejecuta `openmsx.exe`. Las ROM de sistema se ponen en `share/systemroms`, igual que en openMSX.

El zip lo compila GitHub Actions (`.github/workflows/ferpect.yml`) con MinGW-w64, igual que las versiones de prueba oficiales.

## Licencia y créditos

- openMSX es © el openMSX Team, con licencia **GPL v2** (`doc/GPL.txt`). Esta versión, con sus cambios, tiene la misma licencia.
- Cambios de araubi, desarrollados con Claude (Anthropic).
- Datos técnicos: Grauw (MSX Assembly Page), HRA! (Takayuki Hara) y la documentación de Yamaha que ellos citan.
- No es una versión oficial de openMSX. Los fallos de estos cambios no son responsabilidad del equipo de openMSX.
