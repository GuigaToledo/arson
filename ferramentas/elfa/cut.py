import numpy as np, scipy.sparse as sp
from scipy.sparse.csgraph import connected_components
d=np.load('adj.npz'); F=d['F']; U=d['uniq']; vn=np.load('vdata.npz')['vn']
P=sp.load_npz('P.npz')
sn=vn.copy()
for i in range(3): sn=P@sn
sn/=np.linalg.norm(sn,axis=1,keepdims=True)
fr=1-(vn*sn).sum(1)
# curvature sign (concave crease vs convex): use laplacian dot normal
lap=(P@U)-U; conc=(lap*vn).sum(1)
np.save('fr.npy',fr); np.save('conc.npy',conc)
print(np.percentile(fr,[50,80,90,95,98]))
