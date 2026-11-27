import numpy as np, sys
from scipy.spatial import cKDTree
from render import *
t=np.load('t.npy');n=np.load('n.npy');v=t.reshape(-1,3)
d=np.load('adj.npz'); U=d['uniq']; tree=cKDTree(U)
c=(v.min(0)+v.max(0))/2; c[2]=0
def views(attr_fn, yaws=(0,90,180,270), elev=0, size=(360,820), sc=7.8):
    out=[]
    L=np.array([-0.4,-0.5,0.75]);L/=np.linalg.norm(L)
    for yaw in yaws:
        m,nb,z,p=render(t,n,yaw,elev,size,sc,c)
        s=np.clip((nb*L).sum(2),0,1)*0.75+0.25
        img=np.zeros(m.shape+(3,))
        idx=np.where(m)
        _,vi=tree.query(p[idx]+c, k=1)
        img[idx]=attr_fn(vi)
        out.append((np.clip(img*s[...,None],0,1)*255).astype(np.uint8))
    return np.hstack(out)
if __name__=='__main__':
    r=np.load('vdata.npz')['rough']
    def f(vi):
        x=np.clip(r[vi]/0.08,0,1)[:,None]
        return np.array([0.9,0.9,0.9])*(1-x)+np.array([1,0.2,0.1])*x
    Image.fromarray(views(f)).save('rough.png')
