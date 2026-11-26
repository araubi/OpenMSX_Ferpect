# tipos5.py (araubi, MIT): clasifica las perdidas de un CSV de VRAMMED5 por pasada.
# S = byte perdido y lo siguiente corrido; A = byte perdido y otro sin escribir;
# K = direccion saltada sin perder dato. Uso: python3 tipos5.py VRAMMED5.CSV [ciclo]
import sys
def load(f):
    R={}
    for l in open(f,errors='replace'):
        p=l.strip().split(',')
        if p[0]=='D' and len(p)>4 and len(p[4])>=2048:
            R[(int(p[1]),p[2],int(p[3]))]=bytes.fromhex(p[4][:2048])
    return R
def events(d):
    """sequence of tokens in address order: ('D',idx) data, ('H',) hole, ('W',v) weird. stops after idx 1023"""
    last=-1; seq=[]
    for a,v in enumerate(d):
        if last>=1023: break
        c=None
        for dd in range(last+1,min(last+10,1024)):
            if (dd&255)==v: c=dd;break
        if c is None:
            seq.append(('H',) if v==0xEE else ('W',v)); continue
        seq.append(('D',c)); last=c
    return seq,last
def classify(seq):
    S=A=K=W=0; ev=[]   # ev: (write index, type)
    last=-1; pendloss=0
    for i,t in enumerate(seq):
        if t[0]=='D':
            n=t[1]-last-1
            # look ahead: hole right after?
            nxt=seq[i+1][0] if i+1<len(seq) else None
            for j in range(n):
                if nxt=='H' and j==n-1: A+=1; ev.append((last+1+j,'A'))
                else: S+=1; ev.append((last+1+j,'S'))
            if nxt=='H' and n>0: seq[i+1]=('h',)
            last=t[1]
        elif t[0]=='H': K+=1; ev.append((last,'K'))
        elif t[0]=='W': W+=1; ev.append((last,'W'))
    return S,A,K,W,ev
if __name__=='__main__':
    R=load(sys.argv[1])
    cyc=int(sys.argv[2]) if len(sys.argv)>2 else 0
    for k in sorted(R,key=lambda k:(k[1],k[2])):
        if k[0]!=cyc: continue
        seq,last=events(R[k]); S,A,K,W,ev=classify(seq)
        if S+A+K+W: print('%s arr%d: S%4d A%4d K%3d W%3d  fin %4d'%(k[1],k[2],S,A,K,W,last))
