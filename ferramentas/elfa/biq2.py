import numpy as np, scipy.sparse as sp, sys
from scipy.sparse.csgraph import dijkstra
d=np.load('adj.npz'); F=d['F']; U=d['uniq']
fr=np.load('fr.npy'); L=np.load('L.npy')
x,y,z=U[:,0],U[:,1],U[:,2]
K=float(sys.argv[1]) if len(sys.argv)>1 else 60
e=np.concatenate([F[:,[0,1]],F[:,[1,2]],F[:,[2,0]]])
ln=np.linalg.norm(U[e[:,0]]-U[e[:,1]],axis=1)
w=ln*(1+K*np.clip(np.maximum(fr[e[:,0]],fr[e[:,1]])/0.02,0,4)**2)
G=sp.coo_matrix((w,(e[:,0],e[:,1])),shape=(len(U),len(U))).tocsr()
def seed(px,pz,front=True):
    i=np.where((np.abs(z-pz)<0.5)&(np.abs(x-px)<0.6))[0]
    return int(i[np.argmin(y[i])] if front else i[np.argmax(y[i])])
from pick import pick
# (yaw, x, y) em imagens 500x1000 (y já com o deslocamento +60 da figura de conferência)
BQ=[(0,255,330),(0,250,315),(0,215,135),(0,300,145),(0,225,150),(0,295,130),(180,250,325),(180,240,300),(180,270,300)]
PL=[(0,270,260),(0,240,240),(0,300,250),(0,185,390),(0,290,420),(0,262,165),(0,240,100),(0,200,300),(0,320,290),(0,190,250),(0,330,240),
    (180,200,380),(180,340,360),(180,240,260),(180,250,220),(180,200,330),(180,330,330),(180,250,150),(180,200,200),(180,300,200),
    (90,230,330),(90,260,250),(270,280,330),(270,250,250),
    (0,215,262),(0,195,95),(0,268,135),(0,285,128),(180,250,265),(180,200,272),(180,300,262),(180,190,285),(90,285,255),(90,295,245)]
def pk(L_):
    out=[]
    for q in L_:
        try: out.append(pick(*q))
        except ValueError as er: print(er)
    return out
biq=pk(BQ); pele=pk(PL)
pele+=list(np.where(((z<36)|(z>83))&(L==0))[0][::50])
src=np.array(biq+pele); cls=np.array([1]*len(biq)+[0]*len(pele))
dist,pred,sources=dijkstra(G,directed=False,indices=src,min_only=True,return_predecessors=True)
lab=np.zeros(len(U),int)
ok=sources>=0
m={s:c for s,c in zip(src,cls)}
lab[ok]=np.array([m[s] for s in sources[ok]])
B=(lab==1)&(L!=2)&(L!=3)
np.save('biq.npy',B); print('biquini verts',B.sum())
