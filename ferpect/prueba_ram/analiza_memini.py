#!/usr/bin/env python3
"""Analiza los volcados de MEMINI.COM (MEMINI.BIN y MEMSLOT.BIN).

  python analiza_memini.py MEMINI.BIN [otro MEMINI.BIN ...] [--slots MEMSLOT.BIN]
                           [--ram salida.bin] [--xml]

Con un volcado: cabecera, estadistica, periodo que mejor explica la RAM y
zonas que no siguen el patron (lo que tocaron la BIOS, el DOS y el programa).
Con varios (arranques en frio distintos): ademas, cuantos bytes y bits
cambian de un arranque a otro. --xml escribe el <initialContent> propuesto.
"""
import sys, base64, zlib, collections

MAGIC = b"MEMINI-COM-MAGIC"

def slot(b):
    return f"{b & 3}-{(b >> 2) & 3}" if b & 0x80 else f"{b & 3}"

def lee(nombre):
    d = open(nombre, "rb").read()
    if d[:6] != b"MEMINI" and d[:6] != b"MEMSNI":
        if d[:3] != b"MEM":
            sys.exit(f"{nombre}: no es un volcado de MEMINI")
    h = dict(a8=d[8], ff=d[9], exp=d[10:14], ram=d[14:18], drv=d[18:26],
             tpa=d[26] | d[27] << 8, sp=d[28] | d[29] << 8, ver=d[30],
             dosa=d[31], dosb=d[32], segs=d[33] | d[34] << 8)
    p, trozos, rep = 64, [], 0
    def cab(q):
        return (q == len(d) or (q + 8 <= len(d) and d[q] == 0x43 and d[q+1] <= 2
                and d[q+4] <= 3 and d[q+5:q+8] == b"\0\0\0"))
    while p < len(d):
        if not cab(p):
            sys.exit(f"{nombre}: trozo mal formado en {p}")
        tipo, seg, hi, marca = d[p+1:p+5]
        p += 8
        datos = None
        if marca == 0:
            if cab(p + 4096):
                datos = d[p:p+4096]; p += 4096
            else:
                # Copia en modo texto: cada CR LF se quedo en LF. Se busca la
                # cabecera siguiente y se reponen los CR que faltan.
                for falta in range(1, 400):
                    if cab(p + 4096 - falta):
                        break
                else:
                    sys.exit(f"{nombre}: archivo cortado o danado en {p}")
                b = bytearray(d[p:p+4096-falta]); p += 4096 - falta
                lf = [i for i, v in enumerate(b) if v == 10 and (i == 0 or b[i-1] != 13)]
                for i in reversed(lf[:falta]):
                    b.insert(i, 13)
                b += bytes(4096 - len(b))
                datos = bytes(b[:4096]); rep += 1
        trozos.append((tipo, seg, hi, marca, datos))
    if rep:
        print(f"AVISO {nombre}: copiado en modo texto (CR LF -> LF); {rep} trozos reparados a ojo."
              " Los trozos sin CR LF (la RAM limpia) no se ven afectados.")
    return h, trozos

def imagen(h, trozos):
    """RAM del DOS reconstruida y lista de zonas sucias conocidas."""
    if h["segs"] == 0:
        img = bytearray(65536)
        for tipo, seg, hi, marca, datos in trozos:
            if tipo == 0:
                img[hi << 8:(hi << 8) + 4096] = datos
        pag = {0: 0, 1: 0x4000, 2: 0x8000, 3: 0xC000}
    else:
        n = max(seg for tipo, seg, *_ in trozos if tipo == 1) + 1
        img = bytearray(n * 16384)
        pre = None
        for tipo, seg, hi, marca, datos in trozos:
            if tipo == 1:
                o = seg * 16384 + (hi << 8)
                img[o:o + 4096] = datos
            elif tipo == 0:
                pre = datos
        s0 = [s for s in range(n) if img[s*16384+0x103:s*16384+0x113] == MAGIC]
        pag = {}
        if s0:
            pag[0] = s0[0] * 16384
            if pre:
                img[pag[0] + 0x2000:pag[0] + 0x3000] = pre
        pag[3] = 0                     # el segmento 0 es la pagina 3
    sucio = []
    if 0 in pag:
        sucio.append((pag[0], pag[0] + 0x800, "pagina 0: vectores del DOS y MEMINI.COM"))
    if 3 in pag:
        sucio.append((pag[3] + (h["tpa"] & 0x3FFF if h["tpa"] >= 0xC000 else 0),
                      pag[3] + 0x4000, "pagina 3: DOS, zona de trabajo de la BIOS y pila"))
    return img, sucio

def periodo(img, sucio):
    """Devuelve (aciertos, periodo, patron) del periodo potencia de 2 mas corto
    que explica la RAM limpia casi tan bien como el mejor."""
    limpio = bytearray(b"\1" * len(img))
    for a, b, _ in sucio:
        limpio[a:b] = bytes(b - a)
    total = sum(limpio)
    res = []
    p = 1
    while p <= 16384:
        ok, pat = 0, bytearray(p)
        for r in range(p):
            c = collections.Counter(img[i] for i in range(r, len(img), p) if limpio[i])
            if c:
                v, k = c.most_common(1)[0]
                pat[r] = v; ok += k
        res.append((ok / total, p, bytes(pat)))
        p *= 2
    mejor = max(r[0] for r in res)
    for r in res:
        if r[0] >= mejor - 0.002:
            return r, res, limpio

def zonas(img, pat, limpio):
    p, out, ini = len(pat), [], None
    for i in range(0, len(img), 256):
        mal = sum(1 for j in range(i, i + 256) if img[j] != pat[j % p])
        if mal:
            out.append((i, mal))
    return out

def informe(nombre, quiere_xml, salida_ram):
    h, trozos = lee(nombre)
    print(f"== {nombre}")
    print(f"  MSX version {h['ver']} (0=MSX1 1=MSX2 2=2+ 3=turbo R), DOS: A={h['dosa']} B={h['dosb']}"
          f" ({'DOS 2/Nextor' if h['dosa'] == 0 and h['dosb'] >= 2 else 'DOS 1'})")
    print(f"  RAM del DOS por pagina: {' '.join(slot(b) for b in h['ram'])}; "
          f"slots expandidos: {' '.join(str(b >> 7) for b in h['exp'])}")
    print(f"  ROM de disco: {' '.join(slot(h['drv'][i+1]) for i in range(0, 8, 2) if h['drv'][i]) or 'ninguna'}")
    print(f"  TPA hasta {h['tpa']:04X}h, mapper: {h['segs']} segmentos ({h['segs']*16} KB)" if h["segs"]
          else f"  TPA hasta {h['tpa']:04X}h, RAM sin mapper (64 KB)")
    img, sucio = imagen(h, trozos)
    if salida_ram:
        open(salida_ram, "wb").write(img)
    c = collections.Counter(img)
    print("  bytes mas frecuentes: " + ", ".join(f"{v:02X}h {100*k/len(img):.1f} %" for v, k in c.most_common(6)))
    (ok, p, pat), res, limpio = periodo(img, sucio)
    print("  periodo -> % de la RAM limpia explicada: " +
          " ".join(f"{q}:{100*o:.1f}" for o, q, _ in res))
    print(f"  mejor periodo: {p} bytes, explica el {100*ok:.2f} %")
    if p <= 64:
        print("  patron: " + pat.hex().upper())
    z = [(i, m) for i, m in zonas(img, pat, limpio)]
    fuera = [(i, m) for i, m in z if limpio[i]]
    print(f"  paginas de 256 bytes que no siguen el patron fuera de las zonas sucias: {len(fuera)}")
    for i, m in fuera[:40]:
        print(f"    {i:06X}h: {m} bytes distintos")
    if len(fuera) > 40:
        print(f"    ... y {len(fuera) - 40} mas")
    if quiere_xml:
        xml = base64.b64encode(zlib.compress(pat, 9)).decode()
        print(f'  <initialContent encoding="gz-base64">{xml}</initialContent>')
    return img, limpio

def slots(nombre):
    h, trozos = lee(nombre)
    print(f"== {nombre} (resto de slots, solo lectura)")
    txt = {1: "todo FFh", 2: "RAM del DOS", 3: "no leido (ROM de disco)"}
    porslot = collections.OrderedDict()
    for tipo, seg, hi, marca, datos in trozos:
        porslot.setdefault((seg, hi >> 6), []).append((hi, marca, datos))
    for (s, pg), l in porslot.items():
        marcas = {m for _, m, _ in l}
        if marcas == {0} or 0 in marcas:
            dat = b"".join(d if d else b"\xff" * 4096 for _, m, d in l)
            c = collections.Counter(dat)
            print(f"  slot {slot(s)} pagina {pg}: datos, " +
                  ", ".join(f"{v:02X}h {100*k/len(dat):.0f} %" for v, k in c.most_common(3)))
        else:
            print(f"  slot {slot(s)} pagina {pg}: {txt[marcas.pop()]}")

def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    xml = "--xml" in a
    a = [x for x in a if x != "--xml"]
    ram = sl = None
    if "--ram" in a:
        i = a.index("--ram"); ram = a[i + 1]; del a[i:i + 2]
    if "--slots" in a:
        i = a.index("--slots"); sl = a[i + 1]; del a[i:i + 2]
    imgs = [informe(n, xml, ram) for n in a]
    if len(imgs) > 1 and len({len(i) for i, _ in imgs}) == 1:
        limpio = imgs[0][1]
        n = sum(limpio)
        dif = sum(1 for j in range(len(limpio)) if limpio[j] and len({i[j] for i, _ in imgs}) > 1)
        bits = sum(bin(imgs[0][0][j] ^ i[j]).count("1") for i, _ in imgs[1:]
                   for j in range(len(limpio)) if limpio[j])
        print(f"== Entre los {len(imgs)} volcados: {dif} de {n} bytes limpios cambian "
              f"({100*dif/n:.2f} %); {bits} bits distintos respecto al primero")
    if sl:
        slots(sl)

main()
