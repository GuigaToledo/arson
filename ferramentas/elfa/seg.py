import numpy as np
from collections import Counter
t=np.load('t.npy')
v=t.reshape(-1,3); key=np.round(v,4)
uniq,inv=np.unique(key,axis=0,return_inverse=True); F=inv.ravel().reshape(-1,3)
print('verts',len(uniq),'faces',len(F))
fn=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]); fn/=np.linalg.norm(fn,axis=1,keepdims=True)+1e-12
E=np.concatenate([F[:,[0,1]],F[:,[1,2]],F[:,[2,0]]]); fi=np.tile(np.arange(len(F)),3)
E.sort(1); k=E[:,0].astype(np.int64)*len(uniq)+E[:,1]
o=np.argsort(k); ks=k[o]; fs=fi[o]
same=ks[1:]==ks[:-1]
a=fs[:-1][same]; b=fs[1:][same]
cnt=Counter(ks.tolist()); print('edge share hist',Counter(cnt.values()).most_common(5))
dots=(fn[a]*fn[b]).sum(1)
ang=np.degrees(np.arccos(np.clip(dots,-1,1)))
print('angle pct',np.percentile(ang,[50,90,99,99.9]))
np.savez('adj.npz',a=a,b=b,ang=ang,F=F,uniq=uniq)
