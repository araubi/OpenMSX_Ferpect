# openMSX con el V9968 (rama msx2pp de buppu3)

Compilación sin cambios de la rama `msx2pp` de **buppu3** (https://github.com/buppu3/openMSX, commit `aea339b`, 4-10-2026), que añade al openMSX el **V9968**, la VDP prevista para el MSX2++. Todo el mérito es de buppu3. No lleva las mejoras de openMSX FERPECT.

Cómo usarlo (según su README):
- Máquina de ejemplo: `Panasonic_FS-A1ST_V9968` (un turbo R con V9968).
- En cualquier máquina: en su XML, dentro de `<VDP id="VDP">`, poner `<version>V9968</version>`. La VRAM es siempre de 256 KB. `<timing>` 0 = temporización lenta propia del V9968, 1 = la del V9958 (el bit HS de R#20 influye).
- Cartucho: extensión `HRA_V9968` (puerto 88h). Sin doble pantalla: la fuente de vídeo se cambia en Settings → Video → Misc.

Paquetes: Windows (zip, `openmsx.exe`), Linux (zip, `bin/openmsx`) y macOS (dmg, sin firmar: la primera vez, clic derecho → Abrir). Las ROM de sistema van en `share/systemroms`.

Licencia: GPL, como openMSX (ver GPL.txt).
