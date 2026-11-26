#!/usr/bin/env python3
# resumen3.py VRAMMED3.CSV -> tiempo real de cada rutina y fallos por ritmo. araubi, MIT.
import sys, collections
CUADRO = 313 * 228.0          # T de un cuadro PAL (cambiar a 262*228 en NTSC)
REPS = dict(NUL=1, BWL=128 * 8, WME=128 * 8, DLY=760)
cal = collections.defaultdict(lambda: collections.defaultdict(list))
med = collections.defaultdict(dict)
txt = open(sys.argv[1], 'rb').read().split(b'\x1a')[0].decode('latin1')
for l in txt.splitlines():
    f = l.strip().split(',')
    if f[0] == 'H': print('Cabecera:', l)
    if f[0] == 'C' and len(f) >= 5:
        cal[int(f[1], 16)][f[2]] = [int(x, 16) for x in f[3:5]]
    if f[0] == 'M' and len(f) >= 24:
        pos = [tuple(int(y, 16) for y in x.split(':')) for x in f[3:19]]
        med[int(f[1], 16)][f[2]] = (pos, [int(x, 16) for x in f[19:24]])
per = collections.defaultdict(list)
import statistics
FRM = statistics.median(x for c in cal for x in cal[c]['FRM'])
fix = lambda v: v - FRM * round(v / FRM - 0.5) if v > FRM * 1.02 else v   # flag F perdido: cuadros de mas
for c in sorted(cal):
    nul = statistics.median(map(fix, cal[c]['NUL']))
    for n, v in cal[c].items():
        if n in ('FRM', 'NUL'): continue
        for x in v:
            per[n].append((c, (nul - fix(x)) * CUADRO / FRM / REPS.get(n, 1024)))
print('Regla: %.1f vueltas por cuadro' % FRM)
print('rutina  T medios  (min..max)   primer ciclo -> ultimo ciclo')
for n, v in per.items():
    t = [x for _, x in v]
    print('%-6s %7.2f  (%.2f..%.2f)   %.2f -> %.2f' % (n, statistics.median(t), min(t), max(t), statistics.median(t[:10]), statistics.median(t[-10:])))
print()
print('ritmo  T real  ciclos  fallos/ciclo: A  S  B  E  O   arranques con fallo/16')
names = []
for c in med:
    for n in med[c]:
        if n not in names: names.append(n)
for n in names:
    tot = [0] * 5; runs = 0; k = 0
    for c in med:
        if n in med[c]:
            pos, t = med[c][n]; k += 1
            tot = [a + b for a, b in zip(tot, t)]
            runs += sum(1 for p in pos if p[1])
    t = [x for _, x in per.get(n, [])]
    pr = statistics.median(t) if t else 0
    print('%-5s %6.2f  %4d   %s   %.1f' % (n, pr, k, ' '.join('%7.1f' % (x / k) for x in tot), runs / k))
if len(sys.argv) > 2:
    print('\nPor ciclo (A+S+B+E+O):')
    for c in sorted(med):
        print('%02X ' % c + ' '.join('%s:%d' % (n, sum(med[c][n][1])) for n in names if n in med[c]))
