# openMSX FERPECT v0.22c

Versión 0.22c, hecha a partir de **openMSX 22.0** (código de [openMSX/openMSX](https://github.com/openMSX/openMSX), commit `b34dbbd`) con cambios pensados para quien carga cintas TSX, para quien juega en MSX1 o turbo R y para quien programa para MSX. Sirve para probarlos antes de proponerlos al proyecto original.

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

### 4. MSX1: escritura en la VRAM medida en un aparato real

openMSX supone que la VDP de un MSX1 (TMS9918/9928/9929) necesita al menos 27 T-states entre dos escrituras en la VRAM con la imagen encendida. Si van más seguidas, pierde bytes. El propio código de openMSX reconoce que ese valor es una suposición, que ya tuvieron que retocar por Chase HQ.

Un ejemplo es War in Middle Earth: dibuja el mapa escribiendo un byte cada 25 T. En openMSX se pierden bytes y el mapa sale revuelto, pero en un Sony HB-20P de verdad se ve bien.

Para comprobarlo se hizo una ROM de prueba (`ferpect/prueba_vram/vramtest.asm`). Escribe 1024 bytes en SCREEN 2 con la imagen encendida, separando las escrituras de 17 a 32 T, y lo repite en 4 momentos distintos de la imagen. En el HB-20P (Toshiba T6950A, PAL):
- con 23 T o menos se pierden muchos bytes;
- con 24 T o más no se pierde prácticamente ninguno (como mucho 1 de 1024). (Ese «1» de 26 T era un fallo de la propia prueba: su fila de 26 T usaba `ADD A,1 / RET C` y solo escribía 256 bytes.)

FERPECT espera ahora 4 ciclos de la VDP en vez de 7 antes de buscar el hueco de acceso. Con eso da el mismo límite que el aparato: pierde bytes con 23 T o menos y ninguno con 24 T o más. Así, War in Middle Earth se ve bien con el ajuste normal (`too_fast_vram_access real`).

**Chips de Texas (v0.22e).** La misma ROM en un Toshiba HX-10D, que lleva un TMS9918A de Texas, pierde bytes también con 24 T y 25 T (en algunas pasadas, y muchos) y ninguno desde 26 T. El HB-20P lleva un Toshiba T6950A. FERPECT da ahora a los chips de Texas 9 ciclos más de retraso: pierden con 24 T y 25 T. Los Toshiba siguen como el HB-20P.

**Cómo falla, y por qué cambia de un día a otro (v0.22i).** Con `ferpect/prueba_vram/vramtest4.asm`, que llena la VRAM con EEh, escribe 00, 01, 02… y enseña los bytes del primer fallo, el HB-20P da siempre lo mismo: `2B 2C 2E EE 2F 30`. Cuando una escritura llega antes de que la VDP haya hecho la anterior, la anterior se hace con el dato nuevo y la nueva no se hace, pero el puntero avanza por las dos. Queda un byte equivocado y otro sin escribir, y el resto en su sitio. openMSX, en cambio, corría todos los bytes siguientes una posición, y por eso el mapa de War in Middle Earth salía revuelto en vez de con algún punto suelto como en el aparato.

Ese mismo HB-20P, el 21-11 y después de apagarlo y encenderlo cuatro veces, pierde siempre parecido: con 24 T unos 40 fallos de cada 1024 escrituras, con 25 T de 5 a 12, con el patrón de War in Middle Earth de 5 a 10, y ninguno con 26 T (en el HB-20P la VDP y el Z80 tienen relojes independientes, así que su fase va girando). La prueba del 19-11, sin fallos a 24-25 T, fue la excepción. FERPECT v0.22j da esas cifras: los Toshiba ven la petición 9 ciclos de VDP después, como los de Texas (la v0.22i elegía una fase al azar al arrancar; se ha quitado). Los chips de Texas mantienen su forma de fallar hasta medirlos con la misma ROM.

La regla para programar no cambia: deja al menos 29 T entre escrituras con la imagen encendida, porque no todos los MSX1 tienen por qué ser iguales que el HB-20P.

### 5. Turbo R: velocidad del R800 medida en un FS-A1ST real

Con dos ROM de prueba (`ferpect/prueba_turbor/`) que miden con el temporizador del turbo R (E6h) cuánto tardan 2048 operaciones de cada tipo, en un Panasonic FS-A1ST. Se repitió con dos cartuchos distintos, con expansor y sin él, y salió lo mismo.
- Con el Z80, la VDP, la RAM, el PSG y el OPLL, openMSX ya coincidía (diferencias de un 1 %).
- **Modo R800 DRAM:** leer la BIOS va igual de rápido que la RAM, pero openMSX la seguía leyendo a velocidad de ROM. Era un fallo: al pasar a modo DRAM no se actualizaba la página que ya estaba seleccionada. Arreglado.
- **Cartuchos con el R800:** en el aparato van más lentos que en openMSX. El código ejecutado desde un cartucho iba hasta un 34 % más rápido de la cuenta. FERPECT pone ahora 3 ciclos de espera en las ranuras externas (antes 2) y alinea cada acceso con el bus de 3,5 MHz, como ya se hacía con la E/S. Así todas las medidas quedan a menos de un 2,5 % del aparato.

### 6. V9990: el WAIT del GFX9000, emulado

Medido con tres ROM de prueba (`ferpect/prueba_v9990/`) en el mismo FS-A1ST con un GFX9000:
- Escribir la paleta o los registros no frena nunca. Con la pantalla apagada, el Z80 tampoco espera al acceder a la VRAM.
- Un acceso suelto a la VRAM no espera nunca, caiga donde caiga en la línea (`v9test3.asm`).
- Los accesos seguidos sí esperan con la imagen encendida (`v9test2.asm`). Con el Z80, separados de 17 a 32 T, se pierden hasta 2,3 T por acceso en P1 y hasta 0,5 T en B1. Con 40 T o más no se pierde nada.
- Con el R800 (OTIR e INIR, `v9test.asm`), escribir la VRAM va entre un 5 % y un 55 % más lento, y leerla, hasta el doble.

FERPECT lo emula así: el V9990 guarda un acceso de la CPU y lo completa más tarde. Si la CPU vuelve a acceder antes de que el anterior se haya completado, espera. En las líneas visibles, la VRAM está ocupada al principio de cada línea: unos 36 T del Z80 en P1 y 22 T en B1. El acceso se completa después, más un tiempo de servicio en P1. Con eso, las medidas del Z80 quedan cerca del aparato y el R800 pasa de no esperar nada a esperar más o menos lo que espera en el aparato. P2 y los demás modos B no se han medido: usan los valores de P1 y B1.

### 7. MSX1: carrera del flag F medida en un Toshiba HX-21 (v0.22f)

Si un programa espera el cuadro leyendo S#0 en bucle y la lectura cae justo cuando el VDP pone a 1 el flag F, la lectura lo borra sin que el Z80 lo vea y se pierde ese cuadro. openMSX ya lo emula en V9938 y V9958 (medido por su equipo), pero suponía que los VDP de MSX1 eran iguales que el V9938. Con la ROM `ferpect/prueba_flag/flagtest.asm` (1000 esperas con bucles de 39 a 134 T), un Toshiba HX-21 (TMS9928A) pierde unas 0,42 veces lo que suponía openMSX: la ventana dura unos 1,9 T, no 4,7. FERPECT usa ahora esa ventana en todos los VDP de MSX1 y da lo mismo que el aparato (por ejemplo, con IN cada 39 T: 50 cuadros perdidos de 1000 en el HX-21, 48 en FERPECT, 113 en openMSX 22). El FS-A1ST (V9958) ya daba lo mismo que openMSX. **v0.22g/h:** el Sony HB-20P (Toshiba T6950A) y el Toshiba HX-10D (TMS9918A) pierden la mitad que el HX-21 (ventana de 1 T): el HX-10D, 22 de 1000 con IN cada 39 T y 6 con IN cada 134 T (FERPECT: 19 y 6). FERPECT usa la ventana ancha (1,9 T) en los TMS9928A y TMS9929A, y la estrecha (1 T) en los demás VDP de MSX1. Dato curioso sin explicar: en el HB-20P el bucle da 1684 vueltas por cuadro y en openMSX 1806, como si cada vuelta tardase un 7 % más en el aparato.

**Regla:** no esperar el cuadro leyendo S#0 en bucle; usar la interrupción y una marca en RAM.

Los dos avisos están **desactivados por defecto** y no cambian la emulación. Para quitarlos, basta con dejar el ajuste vacío (`set too_fast_opll_access_callback ""`).

## Descarga

En [Releases](../../releases) están los paquetes (desde la v0.22j):
- **Windows** de 64 bits (`windows-x86_64.zip`): se descomprime y se ejecuta `openmsx.exe`.
- **Linux** de 64 bits (`linux-x86_64.zip`): se descomprime y se ejecuta `bin/openmsx`.
- **macOS** (`mac-arm64.dmg` para Apple Silicon, `mac-x86_64.dmg` para Intel): desde la v0.22l la aplicación va firmada «ad hoc» (sin certificado de Apple). Ya no sale «está dañado», pero la primera vez macOS avisa de que no puede comprobarla: en macOS 15 o posterior, Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente»; en versiones anteriores, clic derecho → Abrir. También vale quitarle la cuarentena en Terminal con `xattr -cr /Applications/openMSX.app`. Quitar el aviso del todo exige una cuenta de desarrollador de Apple (99 $ al año) para firmar y notarizar.

Las ROM de sistema se ponen en `share/systemroms`, igual que en openMSX. Todo lo compila GitHub Actions (`.github/workflows/ferpect.yml`) con las mismas recetas que las versiones de prueba oficiales.

## Licencia y créditos

- openMSX es © el openMSX Team, con licencia **GPL v2** (`doc/GPL.txt`). Esta versión, con sus cambios, tiene la misma licencia.
- Cambios de araubi, desarrollados con Claude (Anthropic).
- Datos técnicos: Grauw (MSX Assembly Page), HRA! (Takayuki Hara) y la documentación de Yamaha que ellos citan.
- No es una versión oficial de openMSX. Los fallos de estos cambios no son responsabilidad del equipo de openMSX.
