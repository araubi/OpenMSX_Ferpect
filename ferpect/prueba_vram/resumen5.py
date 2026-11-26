#!/usr/bin/env python3
# resumen5.py (araubi, MIT): resume el CSV de VRAMMED5.
# Uso: python3 resumen5.py VRAMMED5.CSV [-v]
# Se escribe el byte (direccion AND 255) en 1024 direcciones seguidas y se lee despues.
# Por cada pasada: bytes bien, bytes desplazados (dato de k posiciones mas adelante),
# bytes con otro valor, y en que posiciones cambia el desplazamiento (= escritura perdida).
import sys
v='-v' in sys.argv
f=[a for a in sys.argv[1:] if a!='-v'][0]
for l in open(f,errors='replace'):
    p=l.strip().split(',')
    if p[0]!='D' or len(p)<5 or len(p[4])<2048: continue
    d=bytes.fromhex(p[4][:2048])
    ok=des=otro=0; k=0; saltos=[]; raros=[]
    for a,b in enumerate(d):
        j=(b-a)&255
        if j==k:
            if k==0: ok+=1
            else: des+=1
        elif 0<j-k<=8 or (j<k and k-j<=2):
            saltos.append((a,j-k)); k=j
            if k==0: ok+=1
            else: des+=1
        else:
            otro+=1; raros.append((a,b))
    print('%s %s arr %s: bien %4d  desplazados %4d  otros %4d  perdidas %3d (despl. final %d)'%(
        p[1],p[2],p[3],ok,des,otro,sum(s for _,s in saltos if s>0),k))
    if v:
        print('   saltos (pos:+n):',' '.join('%d:%+d'%s for s in saltos))
        print('   otros (pos=valor):',' '.join('%d=%02X'%r for r in raros[:60]))
