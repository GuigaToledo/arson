import numpy as np
from scipy.sparse import coo_matrix, diags
d=np.load('adj.npz'); F=d['F']; U=d['uniq']
t=np.load('t.npy')
fn=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]); ar=np.linalg.norm(fn,axis=1); fn/=ar[:,None]+1e-12
nv=len(U)
# vertex normals
vn=np.zeros((nv,3))
for k in range(3): np.add.at(vn,F[:,k],fn*ar[:,None])
vn/=np.linalg.norm(vn,axis=1,keepdims=True)+1e-12
# vertex adjacency
r=np.concatenate([F[:,0],F[:,1],F[:,2],F[:,1],F[:,2],F[:,0]]); c=np.concatenate([F[:,1],F[:,2],F[:,0],F[:,0],F[:,1],F[:,2]])
A=coo_matrix((np.ones(len(r)),(r,c)),shape=(nv,nv)).tocsr(); A.data[:]=1
deg=np.asarray(A.sum(1)).ravel(); Dinv=diags(1/deg)
P=Dinv@A
# smoothed normals over ~k rings, roughness = 1 - dot(n, smooth n)
sn=vn.copy()
for i in range(6): sn=P@sn
sn/=np.linalg.norm(sn,axis=1,keepdims=True)+1e-12
rough=1-(vn*sn).sum(1)
for i in range(10): rough=P@rough
np.savez('vdata.npz',vn=vn,rough=rough)
import scipy.sparse as sp; sp.save_npz('P.npz',P.tocsr())
print(np.percentile(rough,[10,50,75,90,95,99]))
