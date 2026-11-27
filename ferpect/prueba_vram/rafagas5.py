# rafagas5.py (araubi, MIT): en las rutinas a rafagas de 8 escrituras de VRAMMED5 (BWL),
# cuenta que escrituras de cada rafaga se pierden juntas (0S 2S = la 1.a y la 3.a) y
# cuantas veces empieza la perdida en la 1.a por posicion de arranque.
# Uso: python3 rafagas5.py VRAMMED5.CSV [otro.csv ...]
import sys
import tipos5 as t
from collections import Counter
for f in sys.argv[1:]:
    R=t.load(f)
    for name in ('BWL',):
        c=Counter(); per=Counter()
        for k in sorted(R):
            if k[1]!=name: continue
            seq,last=t.events(R[k]); S,A,K,W,ev=t.classify(seq)
            g={}
            for i,ty in ev: g.setdefault(i//8,[]).append('%d%s'%(i%8,ty))
            for gi in range(128): c[' '.join(g.get(gi,[]))]+=1
            per[k[2]]+=sum(1 for i,ty in ev if i%8==0 and ty in 'SA')
        print(f[-12:],name,dict(per)); 
        for p,n in c.most_common(22): print('   %5d  %s'%(n,p or '-'))
