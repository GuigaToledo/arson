import numpy as np, scipy.sparse as sp
from scipy.sparse.csgraph import connected_components
d=np.load('adj.npz'); F=d['F']; U=d['uniq']; V=np.load('vdata.npz'); vn=V['vn']; rough=V['rough']
P=sp.load_npz('P.npz')
x,y,z=U[:,0],U[:,1],U[:,2]
e=np.concatenate([F[:,[0,1]],F[:,[1,2]],F[:,[2,0]]])
def flood(pred, seed):
    m=pred[e[:,0]]&pred[e[:,1]]
    g=sp.coo_matrix((np.ones(m.sum()),(e[m,0],e[m,1])),shape=(len(U),len(U)))
    n,lab=connected_components(g,directed=False)
    return lab==lab[seed]
def near(px,pz,front=True,tol=0.6):
    i=np.where((np.abs(z-pz)<tol)&(np.abs(x-px)<tol))[0]
    return i[np.argmin(y[i])] if front else i[np.argmax(y[i])]
xc=-1.0; dx=np.abs(x-xc); front=vn[:,1]<0
lower=np.where(front, 43.0+1.05*dx, 41.5+0.45*dx)
vneck=np.minimum(77.0, 69.0+1.6*dx)
upper=np.where(front, np.where(dx<6.5, vneck, 64.0), np.where(dx<6.0, 68.0, 64.0))
roupa=flood((z>lower)&(z<upper), near(0,61))
sorv=flood((x>1.8)&(z>79.0)&(z<90)&(y<-1.0), near(6,85))
A=(P>0).astype(np.float32)
def dil(m,k):
    m=m.astype(np.float32)
    for i in range(k): m=np.minimum(1,m+A@m)
    return m>0
h0=(rough>0.024)&(z>56)
cab=~dil(~dil(h0,9),9)
face=(z>79)&(z<92.0)&(y<-3.0)&(np.abs(x)<5.5)
chest=((z<80)&(y<-3.5)&(x>-6.5))|((z<79)&(x>6)&(y<2.5))
cab|=((z>92)&(np.abs(x)<6.0))|(z>96.5)
cab&=~chest&(z>56)&~face&~roupa&~sorv
L=np.zeros(len(U),np.uint8); L[roupa]=1; L[cab]=2; L[sorv]=3
print(roupa.sum(),cab.sum(),sorv.sum())

conc=np.load('conc.npy')
hs=np.where((z>44)&(z<47)&(x<-11.5))[0]; hseed=hs[0]
arm=flood((x<-5.8)&(z<72)&(conc<0), hseed).astype(float)
for k in range(4): arm=np.maximum(arm,(P@arm>0).astype(float))
arm=(arm>0)&(x<-5.8)&(z>42)
L[arm&(L==1)]=0
np.save('L.npy',L); np.save('arm.npy',arm)
