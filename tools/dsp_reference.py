# Numpy mirror of PianoCore YIN / onset / tracker logic for tuning parameters on any OS.
# Run: python3 tools/dsp_reference.py   (needs numpy)
import numpy as np, math
def midi_val(f,a4=440.0): return 69+12*math.log2(f/a4)

class YIN:
    def __init__(s,sr,N=2048,fmin=120,fmax=900,thr=0.15):
        s.sr,s.N,s.thr=sr,N,thr
        s.tmin=max(2,int(math.floor(sr/fmax))); s.tmax=int(math.ceil(sr/fmin))+1
        s.W=N-s.tmax-1
    def est(s,x):
        x=np.asarray(x[-s.N:],dtype=np.float64); x=x-x.mean()
        rms=math.sqrt((x*x).mean())
        if rms<=1e-7: return None
        lvl=20*math.log10(rms)
        W=s.W; d=np.zeros(s.tmax+1)
        sq=np.concatenate([[0],np.cumsum(x*x)])
        e0=sq[W]
        for t in range(1,s.tmax+1):
            d[t]=max(0,e0+(sq[t+W]-sq[t])-2*np.dot(x[:W],x[t:t+W]))
        c=np.ones(s.tmax+1); run=0
        for t in range(1,s.tmax+1):
            run+=d[t]; c[t]=d[t]*t/run if run>0 else 1
        ch=-1;t=s.tmin
        while t<s.tmax:
            if c[t]<s.thr:
                while t+1<s.tmax and c[t+1]<c[t]: t+=1
                ch=t;break
            t+=1
        if ch<0: ch=s.tmin+int(np.argmin(c[s.tmin:s.tmax]))
        r=float(ch)
        if 1<ch<s.tmax:
            s0,s1,s2=c[ch-1],c[ch],c[ch+1]; den=s0-2*s1+s2
            if abs(den)>1e-12:
                sh=0.5*(s0-s2)/den
                if abs(sh)<=1: r+=sh
        return (s.sr/r, min(1,max(0,1-c[ch])), lvl)

class Onset:
    def __init__(s,hopdur,minLevel=-58,above=12,rise=6,look=3,belowPeak=1,hopsBelow=3,drop=4,minInter=0.08,floorRise=3):
        s.__dict__.update(locals()); del s.__dict__['s']
        s.floor=-90; s.armed=True; s.hist=[]; s.peak=-200; s.hb=0; s.last=-1e9; s.id=1; s.cal=None
    def proc(s,l,t):
        rm=min(s.hist) if s.hist else -200
        fl=max(s.floor, s.cal if s.cal is not None else -200)
        if not s.armed:
            if l>s.peak: s.peak=l; s.hb=0
            elif l<s.peak-s.belowPeak: s.hb+=1
            else: s.hb=0
            if s.hb>=s.hopsBelow or l<=s.peak-s.drop or l<fl+s.above*0.5: s.armed=True
        on=None
        if s.armed and l>=s.minLevel and l>=fl+s.above and l-rm>=s.rise and t-s.last>=s.minInter:
            on=(s.id,t,l); s.id+=1; s.armed=False; s.peak=l; s.hb=0; s.last=t
        if l<s.floor: s.floor+=(l-s.floor)*0.5
        elif on is None and s.armed and l<fl+s.above: s.floor+=min(l-s.floor, s.floorRise*s.hopdur)
        s.hist.append(l); s.hist=s.hist[-s.look:]
        return on

class Tracker:
    def __init__(s,minConf=0.8,stable=3,stab=30,tol=40,skip=2,maxWin=0.2,minLevel=-60,fmin=120,fmax=900,a4=440):
        s.__dict__.update(locals()); del s.__dict__['s']; s.p=None
    def proc(s,t,est,on):
        out=[]
        if on:
            if s.p: out.append(('rej',s.p['on'][0],'superseded'))
            s.p=dict(on=on,dl=on[1]+s.maxWin,skip=s.skip,streak=[],fail='no pitch')
        p=s.p
        if not p: return out
        if t>p['dl']: out.append(('rej',p['on'][0],p['fail'])); s.p=None; return out
        if p['skip']>0: p['skip']-=1; return out
        if est is None: p['streak']=[]; p['fail']='none'; return out
        f,c,l=est
        if l<s.minLevel: p['streak']=[];p['fail']='quiet';return out
        if c<s.minConf: p['streak']=[];p['fail']='lowconf %.2f'%c;return out
        if f<s.fmin*0.97 or f>s.fmax*1.03: p['streak']=[];p['fail']='range';return out
        m=midi_val(f,s.a4); p['streak'].append((m,f,c)); p['streak']=p['streak'][-s.stable:]
        if len(p['streak'])<s.stable: return out
        v=[q[0] for q in p['streak']]
        if (max(v)-min(v))*100>s.stab: p['fail']='unstable';return out
        med=sorted(p['streak'])[len(v)//2]; mi=int(round(med[0])); ce=(med[0]-mi)*100
        s.p=None
        if abs(ce)>s.tol: out.append(('rej',p['on'][0],'cents %.0f'%ce))
        else: out.append(('acc',p['on'][0],mi,ce,t-p['on'][1],np.mean([q[2] for q in p['streak']])))
        return out

def run(sig,sr,N=2048,H=512):
    y=YIN(sr,N); o=Onset(H/sr); tr=Tracker()
    win=np.zeros(N); res=[]; ons=[]; ests=[]
    for k in range(len(sig)//H):
        hop=sig[k*H:(k+1)*H]; win=np.concatenate([win[H:],hop])
        lvl=20*math.log10(max(math.sqrt((hop.astype(np.float64)**2).mean()),1e-9))
        t=(k+1)*H/sr
        on=o.proc(lvl,t)
        e=y.est(win) if (k+1)*H>=N else None
        if on: ons.append(on)
        ests.append(e)
        res+=tr.proc(t,e,on)
    return ons,res,ests

class LCG:
    def __init__(s,seed=12345): s.x=seed
    def next(s):
        s.x=(s.x*6364136223846793005+1442695040888963407)%(1<<64)
        return ((s.x>>33)/float(1<<31))*2-1
def noise(n,amp,seed=1):
    g=LCG(seed); return np.array([g.next()*amp for _ in range(n)],dtype=np.float32)

def piano(f,dur,sr,amp=0.3,decay=2.5,B=0.0004,nh=8,start=0.0,total=None):
    total=total or dur; n=int(total*sr); t=np.arange(n)/sr; out=np.zeros(n)
    tt=t-start; m=tt>=0; tt=np.where(m,tt,0)
    env=np.where(tt<0.004,tt/0.004,1.0)*np.exp(-decay*tt)*m*(tt<dur)
    for h in range(1,nh+1):
        fh=h*f*math.sqrt(1+B*h*h)
        if fh>sr/2.2: break
        out+= (1.0/h**1.1)*np.sin(2*np.pi*fh*tt)*np.exp(-0.6*(h-1)*tt)
    return (amp*out*env/1.8).astype(np.float32)

def report(name,sig,sr):
    ons,res,ests=run(sig,sr)
    print(f"{name:34s} sr={sr} onsets={len(ons)} results={[(r[0],r[1],r[2] if r[0]=='acc' else r[2], round(r[3],1) if r[0]=='acc' else '', round(r[4]*1000) if r[0]=='acc' else '') for r in res]}")
    return ons,res,ests

for sr in (44100,48000):
    base=lambda d: noise(int(d*sr),0.0005,seed=7)
    for name,f,exp in [('C3',130.81,48),('C4',261.63,60),('E4',329.63,64),('G4',392.0,67),('A4',440.0,69),('C5',523.25,72)]:
        s=base(1.5); s+=piano(f,1.2,sr,start=0.3,total=1.5); report(f"piano {name} exp {exp}",s,sr)
    s=base(1.5); s+=piano(261.63,1.2,sr,amp=0.02,start=0.3,total=1.5); report("soft C4 amp .02",s,sr)
    s=base(1.5); s+=piano(261.63,1.2,sr,amp=0.006,start=0.3,total=1.5); report("very soft C4 amp .006",s,sr)
    s=base(3.0); s+=piano(329.63,2.7,sr,decay=1.2,start=0.3,total=3.0); report("single decaying E4",s,sr)
    s=base(2.0); s+=piano(329.63,1.7,sr,start=0.3,total=2.0)+piano(329.63,1.0,sr,start=0.8,total=2.0); report("E4 pair 0.5s apart",s,sr)
    s=base(2.0); s+=piano(329.63,1.7,sr,decay=0.8,start=0.3,total=2.0)+piano(329.63,1.0,sr,amp=0.3,decay=0.8,start=0.7,total=2.0); report("E4 pair 0.4s slow decay",s,sr)
    s=np.zeros(int(1.5*sr),dtype=np.float32); report("silence",s,sr)
    s=noise(int(1.5*sr),0.05,seed=3); report("steady noise .05",s,sr)
    s=base(1.5); s[int(0.5*sr):]+=noise(int(1.0*sr),0.05,seed=9); report("noise burst",s,sr)
    # clean sine accuracy
    for f in (130.81,261.63,329.63,523.25):
        t=np.arange(2048)/sr; x=(0.3*np.sin(2*np.pi*f*t)).astype(np.float32)
        e=YIN(sr).est(x); print(f"  sine {f}: est {e[0]:.2f} ({(midi_val(e[0])-midi_val(f))*100:+.2f}c) conf {e[1]:.3f}")
