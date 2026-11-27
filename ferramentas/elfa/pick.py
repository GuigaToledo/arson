import numpy as np
from scipy.spatial import cKDTree
from render import *
t=np.load('t.npy');n=np.load('n.npy');v=t.reshape(-1,3)
U=np.load('adj.npz')['uniq']; tree=cKDTree(U)
c=(v.min(0)+v.max(0))/2; c[2]=0
_cache={}
def pick(yaw,px,py):
    if yaw not in _cache: _cache[yaw]=render(t,n,yaw,0,(500,1000),10.5,c)
    m,nb,z,p=_cache[yaw]
    if not m[py,px]:
        raise ValueError(f'fora do corpo {yaw} {px} {py}')
    return int(tree.query(p[py,px]+c)[1])
