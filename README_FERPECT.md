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

Ese mismo HB-20P, el 21-11 y después de apagarlo y encenderlo cuatro veces, pierde siempre parecido: con 24 T unos 40 fallos de cada 1024 escrituras, con 25 T de 5 a 12, con el patrón de War in Middle Earth de 5 a 10, y ninguno con 26 T (en el HB-20P la VDP y el Z80 tienen relojes independientes, así que su fase va girando). La prueba del 19-11, sin fallos a 24-25 T, fue la excepción. FERPECT v0.22j da esas cifras: los Toshiba ven la petición 9 ciclos de VDP después, como los de Texas (la v0.22i elegía una fase al azar al arrancar; se ha quitado). Los chips de Texas, medidos con la misma ROM en un Toshiba HX-21 (TMS9928A, 21-11), tampoco corren los bytes: unas veces fallan igual que el Toshiba (un byte erróneo y otro sin escribir) y otras, cuando la escritura llega justo después de la anterior, solo dejan un byte erróneo con el valor del siguiente. FERPECT v0.22m lo emula así (ventana de 18 ciclos de VDP): 24 T 162/99 fallos (real 108/97), 25 T 76/67 (89/78), WME 59/58 (69/64) y ninguno a 26 y 27 T.

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

### 8. Yamanooto: el registro BFFEh como en un SCC+ real (v0.22n)

En el SCC+ de Konami (SCC-I), el registro de modo (BFFEh) puede poner bancos en «RAM»: el bit 4 los pone todos, y los bits 0, 1 y 2+5 los bancos 0, 1 y 2. Un banco en RAM no cambia aunque se escriba en su registro. openMSX ya lo emula en el cartucho SCC+, pero en el Yamanooto solo miraba el bit 5 (registros del SCC+), así que allí todo funcionaba.

El SD Snatcher en castellano para Yamanooto escribe 3Fh en BFFEh después de cada acceso al SCC+. En un FS-A1ST real con Yamanooto se queda sin música, sin la imagen de Moscú y colgado en el prólogo («Los misteriosos bioroides…»). En openMSX 22 iba bien. FERPECT respeta ahora esos bits en el Yamanooto y falla igual que el aparato. Con un parche de un byte en la ROM (3Fh → 20h) funciona en FERPECT; falta probarlo en el aparato.

Los dos avisos están **desactivados por defecto** y no cambian la emulación. Para quitarlos, basta con dejar el ajuste vacío (`set too_fast_opll_access_callback ""`).

### 9. MSX1 Toshiba (T6950A): escrituras muy seguidas, medidas con calibración (v0.22o)

Las medidas anteriores del HB-20P se hacían con rutinas «de N ciclos» contados a mano. `ferpect/prueba_vram/VRAMMED3.ASM` y `VRAMMED4.ASM` (programas de MSX-DOS; la idea de hacerlo todo en un programa que escribe a fichero es de un colaborador) **miden el ritmo real de cada rutina contra el propio VDP**: cuentan las vueltas de un bucle entre dos borrados verticales, con y sin la rutina. En el emulador dan la cuenta teórica con ±0,02 T.

Lo que salió:
- Con el DOS arrancado desde una PicoVerse 2350, el programa corre desde la RAM del cartucho y cada lectura de memoria tarda más: un NOP 5,68 T, LD A,(HL) 10,5 T, OUTI 21,9 T. Las rutinas «de 20 T» eran de 25,6 T. Cualquier medida de tiempos hecha así no vale para el MSX solo.
- Desde la RAM interna (VRAMMED4) las instrucciones tardan lo teórico, salvo un factor 0,991: en este HB-20P (PAL) el Z80 y el VDP van con cristales distintos, y la relación es justo la de las subportadoras NTSC/PAL (3,579545 / 3,546895).
- Nada cambia en media hora encendido (55 ciclos iguales).
- Fallos por 16 pasadas de 1024 escrituras, aparato / FERPECT v0.22o: 22 T: 121 del tipo conocido y 385 corridos / 153 y 423; 23 T: 533 y 144 / 517 y 91; 24 T: 339 / 383; 25 T: 68 / 86; 26 T o más: 0 / 0. A 21 T o menos todo queda corrido en los dos.

El cambio: en los chips Toshiba, si una escritura llega menos de 128 a 140 ciclos del VDP (21,3 a 23,3 T) después de la anterior y esta sigue pendiente, la nueva se pierde entera (dato e incremento del puntero). El límite exacto depende de la posición en el cuadro, para que la emulación siga siendo determinista.

**Regla:** la de siempre, 29 T o más entre escrituras a la VRAM con la imagen encendida. Y para medir tiempos en un MSX real, calibrar antes contra el VDP y no fiarse de cartuchos que sirven la memoria con un microcontrolador.

### 10. MSX1 Toshiba (T6950A): los huecos de acceso del chip, sacados del volcado (v0.22p)

`ferpect/prueba_vram/VRAMMED5.ASM` hace 1024 escrituras seguidas a 17, 18, ... 24 T (y con las dos rutinas rápidas de Bestial Warrior), empezando en 8 puntos del cuadro, y guarda en un CSV lo que se lee después. `tipos5.py` y `resumen5.py` lo resumen. Con el volcado de un Sony HB-20P:

- Las pérdidas no dependen del calor ni del azar: se repiten cada 20,84 ciclos del Z80 y, a mayor escala, cada 229,23, que es lo que dura una línea del VDP en ese aparato (64 µs; openMSX supone 228). El Z80 y el VDP llevan cristales distintos.
- En las líneas con imagen (SCREEN 2) el chip atiende al Z80 en 12 momentos por línea: 9 seguidos cada 20,6 T y 3 más a 8,9, 18,5 y 11,9 T; hasta el primero de la línea siguiente pasan 25,4 T. En el borde de arriba y de abajo y en el retrazado no se pierde nada ni a 17 T.
- Un byte se pierde de dos maneras. Si la escritura siguiente llega antes del hueco, sustituye a la que esperaba y todo lo que sigue queda corrido una posición. Si llega de 2,1 a 4,5 T después de un hueco que se hizo esperar 16,3 T o más, cambia el byte recién escrito; y si la espera pasó de 19,2 T queda además una dirección sin escribir.

FERPECT usa esa tabla para los Toshiba, esas dos reglas y, en el HB-20P, la relación de relojes medida (`z80_freq_for_vdp_line` en la configuración de la máquina). Bytes perdidos por pasada de 1024 dentro de la imagen, corridos + con byte sin escribir, aparato / FERPECT:

| Ritmo | HB-20P | FERPECT v0.22p |
|---|---|---|
| 17 T | 156 + 12 | 167 + 0 |
| 18 T | 120 + 12 | 124 + 0 |
| 19 T | 111 + 8 | 107 + 0 |
| 20 T | 84 + 3 | 87 + 0 |
| 21 T | 85 + 10 | 80 + 0 |
| 22 T | 53 + 29 | 54 + 26 |
| 23 T | 36 + 57 | 41 + 45 |
| 24 T | 2 + 38 | 19 + 33 |
| Carga de Bestial Warrior | 90 + 6 | 76 + 0 |
| Juego de Bestial Warrior | 76 + 12 | 73 + 0 |

A 26 T o más no se pierde nada en ninguno de los dos; a 25 T FERPECT pierde algo menos que el aparato. Las dos rutinas de Bestial Warrior no se usaron para ajustar: sirven de comprobación. Queda sin modelar que, a ritmos rápidos, 1 de cada 10 pérdidas del aparato deja además un byte sin escribir. La posición de los huecos dentro de la línea no se puede medir así (solo sus distancias); se ha tomado la de los Texas.

### 11. Yamanooto: lo que faltaba de su referencia de hardware (v0.22q)

openMSX emula el Yamanooto de 2023-2024. Con la «Yamanooto Hardware Reference» del 5-12-2025 y la lista de chips de su autor, FERPECT añade:

- **ASCII8 y ASCII16**: bit 2 de CFGR (7FFDh), solo o junto con K4. Ese bit era antes ROMDIS, que ya no existe.
- **OFFR** (7FFEh): al escribirlo se borran los dos bits SUBOFF de CFGR.
- **LOFF** (bit 5 de ENAR): el desplazamiento cuenta en pasos de 2 MB, para chips de más de 8 MB.
- **MSTEN / MOFFR** (bit 2 de ENAR): desplazamiento maestro, de solo escritura, que se suma al normal.
- **SD por SPI** (bit 1 de ENAR): SPICON en 7FFEh (listo, tarjeta presente, CS y destino) y SDAT en 7FFCh. La imagen de la tarjeta se inserta con `hda`.
- **Flash según el tamaño de la ROM**: hasta 8 MB el S29GL064N; para 16, 32, 64 y 128 MB los S29GL128P, 256P, 512P y 01GP (sectores de 128 KB, identificación 01h 7Eh 21h/22h/23h/28h 01h). También se puede fijar con `<flash>` en la configuración.

Dos cosas no vienen en la referencia y están supuestas: que el desplazamiento maestro usa el mismo paso que OFFR, y que escribir en 7FFCh-7FFFh no cambia bancos en los modos ASCII. Probado con una imagen de 32 MB (cada modo y cada desplazamiento) y con los primeros comandos de una SD; falta software real que lo use.

### 12. V9968 (la VDP del MSX2++), con el código de buppu3 (v0.22r)

FERPECT lleva ahora la emulación del **V9968** que **buppu3** tiene en su rama `msx2pp` de openMSX (https://github.com/buppu3/openMSX, commit `aea339b`): registros nuevos (R#20 y R#21, que hay que desbloquear escribiendo 0 en el puerto 9Ch/8Ch), VRAM de 256 KB, modo rápido de comandos (HS), comandos nuevos, 16 sprites por línea, sprites modo 3, paleta ampliada, interrupción de fin de comando y los modos de pantalla añadidos. Todo el mérito de esa emulación es suyo.

- Máquina de ejemplo: `Panasonic_FS-A1ST_V9968` (un turbo R con V9968). En cualquier otra: `<version>V9968</version>` dentro de `<VDP id="VDP">`.
- Cartucho: extensión `HRA_V9968` (puertos 88h-8Ch).
- Al arrancar, la BIOS deja R#21 = 3Bh y el chip se comporta como un V9958.

Qué no es igual que en su versión: buppu3 cuadruplica el reloj del VDP y tiene tablas de huecos propias para el V9968. FERPECT mantiene el reloj de openMSX y sus tablas medidas en aparatos reales (V9938/V9958 y los MSX1), así que la **temporización del V9968 es aproximada**: en la prueba (un programa en BASIC, tiempo en la variable TIME) con modo rápido tarda 64 en su versión y 65 en FERPECT, y sin modo rápido 275 y 290 (un 5 % más lento). El contenido de la VRAM y la imagen salen iguales en las pruebas hechas (BASIC con LINE, PAINT, COPY y sprites, con HS, 16 sprites, paleta ampliada y sprites modo 3). El depurador (visores de sprites, mapa de bits y registros) aún no conoce lo nuevo del V9968.

Comprobado que no cambia nada de lo anterior: la prueba `VRAMMED5` del HB-20P y una prueba de comandos en el HB-F900 dan byte a byte lo mismo que en v0.22q.

### 13. MSX1 Toshiba (T6950A): direcciones saltadas a ritmos rápidos (v0.22s)

Con escrituras cada 17-21 T el HB-20P deja, además de bytes perdidos, alguna dirección **sin escribir**; hasta la v0.22r FERPECT no dejaba ninguna. Del volcado de `VRAMMED5` salen dos reglas:

- Si la escritura que pisa a la que estaba esperando llega **menos de 2 T antes del hueco**, el chip la vuelve a ver después del acceso y hace un acceso «vacío» (solo avanza el puntero) en el hueco siguiente, salvo que antes llegue otra escritura. Con huecos cada 20,6 T siempre llega antes, así que solo se nota al final de la línea, donde hay dos huecos a 8,9 T.
- Si la escritura llega **menos de 0,8 T después** de un acceso que se hizo esperar casi un hueco entero (19,8 T o más), el puntero avanza una vez de más: una dirección saltada y ningún dato perdido.

| Por pasada de 1024 (HB-20P / FERPECT) | 17 T | 18 T | 19 T | 20 T | 21 T | Rutina del juego |
|---|---|---|---|---|---|---|
| Perdido + sin escribir | 13 / 14 | 12 / 10 | 7 / 7 | 4 / 2 | 8 / 1 | 8 / 4 |
| Solo saltada | 0 / 0 | 0 / 0 | 1 / 0 | 5 / 7 | 14 / 14 | 7 / 5 |

En **Bestial Warrior** son las rayitas de otro color que aparecen en la pared al entrar en cada pantalla, cada vez en un sitio (ahí queda el color de la pantalla anterior). Queda corto a 20-21 T en el primer tipo y se pasa un poco a 22-24 T.

Esta versión arregla también la carga de estados guardados de versiones anteriores a la v0.22r.

### 14. Sony HB-20P: contenido de la RAM al encender (v0.22t)

`ferpect/prueba_ram/MEMINI.COM` vuelca a disco la RAM tal como la deja el encendido (la del DOS y, sin escribir en ellos, el resto de slots). En un HB-20P real, en frío: **128 bytes a 00h y 128 a FFh**, repetido, sin ninguna desviación de 0000h a BFFFh (la página 3 ya la ha usado la BIOS). FERPECT arranca ahora así; antes toda a FFh. Los programas que leen memoria sin inicializar se comportan como en el aparato.

### 15. MSX1 Toshiba (T6950A): la dirección saltada espera a un hueco libre (v0.22u)

Visto al comparar el Obliterator (ráfagas de 8 escrituras a 17 T) en el HB-20P y en FERPECT. La dirección que el chip se salta (segunda regla del apartado 13) no se salta en el momento: el acceso «vacío» se hace en el primer hueco que las escrituras dejan libre. En ráfagas eso es casi siempre al terminar la ráfaga. Direcciones saltadas tras cada una de las 8 escrituras, rutina de carga de Bestial Warrior en `VRAMMED5`, aparato / FERPECT: 0, 0, 3, 2, 5, 4, 7, 32 / 0, 0, 0, 2, 2, 5, 8, 45. Pendiente: en ráfagas el aparato pierde más la primera escritura y menos la segunda que FERPECT.

### 16. MSX1 Toshiba (T6950A): margen antes del hueco (v0.22v)

En ráfagas el HB-20P pierde bytes encadenados cada dos escrituras. El chip necesita que la escritura llegue unos 2,2 ciclos de Z80 antes del hueco; si no, espera al siguiente. Los huecos muy seguidos del final de la línea no lo piden. Con esa regla y las anteriores reajustadas, las cuentas de `VRAMMED5` cuadran mejor a casi todos los ritmos (17, 20 y 24 T casi exactas) y por primera vez en la forma de las ráfagas (`ferpect/prueba_vram/rafagas5.py`). El detalle está en las notas de la versión, punto 21.

### 17. Proporción de imagen PAL (v0.22w, v0.22x)

Un televisor PAL enseña unas 288 líneas de imagen y uno NTSC unas 240. openMSX dibuja siempre 240 líneas y las estira a toda la altura de la ventana, lo que está bien para una máquina a 60 Hz pero deja la imagen de una máquina a 50 Hz más alta de lo que era: en el televisor el área de juego de un MSX europeo se ve más alargada.

El ajuste nuevo `pal_aspect` (activado por defecto) lo corrige: cuando el VDP está a 50 Hz, las 240 líneas dibujadas ocupan 240/288 de la altura y arriba y abajo se añaden 24 líneas que repiten la segunda y la penúltima línea dibujada, que son de borde (desde la v0.22x; la primera y la última traían basura en algún equipo). El área de 256x192 pasa de 1,52:1 a 1,83:1 (con `horizontal_stretch` 280).

- Ajuste `pal_overscan` (v0.22x; 5 por defecto, de 0 a 15): porcentaje de la imagen que se recorta por cada uno de los cuatro lados cuando `pal_aspect` está activo, como el sobrebarrido de un televisor. Con 5 quedan a la vista unas 259 líneas de las 288 y el área de juego se ve un 11 % más grande con la misma forma. `set pal_overscan 0` enseña la imagen entera.
- A 60 Hz no cambia nada. Un MSX2 europeo que arranque a 60 Hz se ve como antes hasta que el programa ponga 50 Hz.
- No se aplica con `display_deform 3d`.
- La pistola de luz tiene en cuenta la corrección.
- `set pal_aspect off` deja la imagen como en openMSX.

## Descarga

En [Releases](../../releases) están los paquetes (desde la v0.22j):
- **Windows** de 64 bits (`windows-x86_64.zip`): se descomprime y se ejecuta `openmsx.exe`.
- **Linux** de 64 bits (`linux-x86_64.zip`): se descomprime y se ejecuta `bin/openmsx`.
- **macOS** (`mac-arm64.dmg` para Apple Silicon, `mac-x86_64.dmg` para Intel): desde la v0.22l la aplicación va firmada «ad hoc» (sin certificado de Apple). Ya no sale «está dañado», pero la primera vez macOS avisa de que no puede comprobarla: en macOS 15 o posterior, Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente»; en versiones anteriores, clic derecho → Abrir. También vale quitarle la cuarentena en Terminal con `xattr -cr /Applications/openMSX.app`. Quitar el aviso del todo exige una cuenta de desarrollador de Apple (99 $ al año) para firmar y notarizar.

Las ROM de sistema se ponen en `share/systemroms`, igual que en openMSX. Todo lo compila GitHub Actions (`.github/workflows/ferpect.yml`) con las mismas recetas que las versiones de prueba oficiales.

## Licencia y créditos

- openMSX es © el openMSX Team, con licencia **GPL v2** (`doc/GPL.txt`). Esta versión, con sus cambios, tiene la misma licencia.
- Cambios de araubi, desarrollados con Claude (Anthropic).
- Emulación del V9968: **buppu3** (rama `msx2pp` de https://github.com/buppu3/openMSX), adaptada aquí al reloj y a las tablas de FERPECT.
- Datos técnicos: Grauw (MSX Assembly Page), HRA! (Takayuki Hara) y la documentación de Yamaha que ellos citan.
- No es una versión oficial de openMSX. Los fallos de estos cambios no son responsabilidad del equipo de openMSX.
