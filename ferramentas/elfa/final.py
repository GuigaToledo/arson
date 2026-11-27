"""Elfa NPC: cores por região, roupa medieval curta (couro), adaga presa na coxa por fita,
oclusão ambiente por vértice e render isométrico nas 8 direções no formato dos sprites do Arson."""
import numpy as np, scipy.sparse as sp, json, os, sys
from numba import njit
from PIL import Image
from render import raster

t = np.load('t.npy')
d = np.load('adj.npz'); F = d['F']; U = d['uniq']
L = np.load('L.npy'); vn = np.load('vdata.npz')['vn']
P = sp.load_npz('P.npz'); A = (P > 0).astype(np.float32)
x, y, z = U[:, 0], U[:, 1], U[:, 2]
nv = len(U)

def srgb(h):
    h = h.lstrip('#'); return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])

# ---------- cores por vértice ----------
PELE = srgb('dcae90'); CAB = srgb('c49a58'); COURO = srgb('4a2a1a'); BORDA = srgb('8a5a34')
CORDAO = srgb('c9a66b'); CINTO = srgb('2e1a10'); FIVELA = srgb('c8a050')
SORVETE = srgb('f2b8c6'); CASQUINHA = srgb('c98c4a')
col = np.tile(PELE, (nv, 1)); spec = np.full(nv, 0.25)
roupa = L == 1; cab = L == 2; sorv = L == 3
col[cab] = CAB; spec[cab] = 0.45
# cabelo: variação suave de tom (mechas)
rng = np.random.default_rng(3)
noise = rng.normal(0, 1, nv)
for k in range(6): noise = P @ noise
nz = noise[cab] / (noise[cab].std() + 1e-9)
col[cab] *= np.clip(1 + 0.12 * nz, 0.75, 1.25)[:, None]
# biquíni rosa: só a peça esculpida no modelo (bordas achadas na malha, biq2.py); o resto é pele
bq = np.load('biq.npy').astype(float)
for k in range(4): bq = P @ bq
biq = (bq > 0.5) & ~cab & ~sorv
col[roupa & ~biq] = PELE
top = biq & (z > 64.0); baixo = biq & (z <= 64.0)
col[top] = COURO; spec[top] = 0.4
col[baixo] = srgb('2e1a10'); col[baixo & (z > 57.6)] = PELE
# borda costurada do top
foraT = (~top).astype(np.float32); mT = foraT.copy(); bordaT = np.zeros(nv, bool)
for k in range(2):
    mT = np.minimum(1, mT + A @ mT)
bordaT = top & (mT > 0)
col[bordaT] = BORDA

# sorvete: bola rosa em cima, casquinha embaixo
col[sorv] = SORVETE; spec[sorv] = 0.5
casq = sorv & (z < 82.5)
col[casq] = CASQUINHA; spec[casq] = 0.2
# lábios e olhos (pequenos toques)
labio = (z > 84.2) & (z < 85.6) & (np.abs(x - 0.6) < 1.4) & (y < -6.4) & (L == 0)
col[labio] = srgb('c0726a')
# ---------- geometria extra: fita e adaga na coxa (+x) ----------
extra_t = []; extra_c = []; extra_s = []
def add_quad(a, b, c, dd, cor, s):
    extra_t.extend([[a, b, c], [a, c, dd]]); extra_c.extend([cor, cor]); extra_s.extend([s, s])

def prism(center, ax_u, ax_v, ax_w, hu, hv, hw, cor, s):
    """Caixa orientada: centro, eixos ortonormais u,v,w e meias medidas."""
    cs = [center + su * hu * ax_u + sv * hv * ax_v + sw * hw * ax_w for su in (-1, 1) for sv in (-1, 1) for sw in (-1, 1)]
    cs = np.array(cs)
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for f in faces:
        add_quad(*cs[list(f)], cor, s)

# fita: anel em volta da coxa na altura z~38.5
zr = 41.6
sel = (np.abs(z - zr) < 0.35) & (x > 0.2) & (L == 0)
pts = U[sel][:, :2]
cen = pts.mean(0)
ang = np.arctan2(pts[:, 1] - cen[1], pts[:, 0] - cen[0])
NS = 36; R = np.zeros(NS)
for i in range(NS):
    a0 = -np.pi + i * 2 * np.pi / NS
    dd_ = np.abs(((ang - a0 + np.pi) % (2 * np.pi)) - np.pi)
    w = dd_ < (np.pi / NS * 1.6)
    R[i] = np.linalg.norm(pts[w] - cen, axis=1).max() if w.any() else np.nan
R = np.where(np.isnan(R), np.nanmean(R), R) + 0.22
FITA = srgb('8e1b22')
for i in range(NS):
    j = (i + 1) % NS
    a0 = -np.pi + i * 2 * np.pi / NS; a1 = -np.pi + j * 2 * np.pi / NS
    p0 = np.array([cen[0] + R[i] * np.cos(a0), cen[1] + R[i] * np.sin(a0)])
    p1 = np.array([cen[0] + R[j] * np.cos(a1), cen[1] + R[j] * np.sin(a1)])
    add_quad(np.r_[p0, zr - 0.55], np.r_[p1, zr - 0.55], np.r_[p1, zr + 0.55], np.r_[p0, zr + 0.55], FITA, 0.3)
# laço da fita na frente-lateral
ia = int(np.argmin(np.abs(np.linspace(-np.pi, np.pi, NS, endpoint=False) - (-0.9))))
a_l = -np.pi + ia * 2 * np.pi / NS
pl = np.array([cen[0] + (R[ia] + 0.2) * np.cos(a_l), cen[1] + (R[ia] + 0.2) * np.sin(a_l), zr])
nl = np.array([np.cos(a_l), np.sin(a_l), 0.0]); tl = np.array([-np.sin(a_l), np.cos(a_l), 0.0]); up = np.array([0, 0, 1.0])
prism(pl + tl * 0.9 + up * 0.3, tl, up, nl, 0.9, 0.45, 0.15, FITA, 0.3)
prism(pl - tl * 0.9 + up * 0.3, tl, up, nl, 0.9, 0.45, 0.15, FITA, 0.3)
prism(pl + tl * 0.35 - up * 1.3, (tl - up * 2) / np.linalg.norm(tl - up * 2), np.cross(nl, (tl - up * 2) / np.linalg.norm(tl - up * 2)), nl, 0.9, 0.25, 0.1, FITA, 0.3)
prism(pl - tl * 0.35 - up * 1.3, (-tl - up * 2) / np.linalg.norm(-tl - up * 2), np.cross(nl, (-tl - up * 2) / np.linalg.norm(-tl - up * 2)), nl, 0.9, 0.25, 0.1, FITA, 0.3)
# adaga: lado de fora da coxa, ao longo do eixo da coxa, presa sob a fita
io = int(np.argmax(R * np.cos(np.linspace(-np.pi, np.pi, NS, endpoint=False) - 0.15)))
a_o = -np.pi + io * 2 * np.pi / NS
po = np.array([cen[0] + (R[io] + 0.35) * np.cos(a_o), cen[1] + (R[io] + 0.35) * np.sin(a_o), zr])
n_o = np.array([np.cos(a_o), np.sin(a_o), 0.0])
eixo = np.array([3.76 - 2.84, -4.14 + 7.11, 42 - 33.0]); eixo /= np.linalg.norm(eixo)   # para cima ao longo da coxa
lado = np.cross(eixo, n_o); lado /= np.linalg.norm(lado); n_o = np.cross(lado, eixo)
LAM = srgb('c9ccd2'); CABO = srgb('3a2416'); GUARDA = srgb('b08a4a')
guard_c = po + eixo * 1.6
prism(guard_c, lado, eixo, n_o, 2.0, 0.3, 0.4, GUARDA, 0.8)                 # guarda
prism(guard_c + eixo * 2.0, lado, eixo, n_o, 0.45, 1.9, 0.45, CABO, 0.2)     # cabo
prism(guard_c + eixo * 4.2, lado, eixo, n_o, 0.65, 0.5, 0.6, GUARDA, 0.8)     # pomo
# lâmina: losango achatado afinando até a ponta
b0 = guard_c - eixo * 0.25; L_B = 10.5
for k in range(8):
    f0 = k / 8; f1 = (k + 1) / 8
    w0 = 1.05 * (1 - f0 ** 2.2); w1 = 1.05 * (1 - f1 ** 2.2)
    c0 = b0 - eixo * L_B * f0; c1 = b0 - eixo * L_B * f1
    for sgn in (-1, 1):
        e0a = c0 + lado * w0; e0b = c0 - lado * w0; e1a = c1 + lado * w1; e1b = c1 - lado * w1
        r0 = c0 + n_o * 0.18 * sgn; r1 = c1 + n_o * 0.18 * sgn
        add_quad(e0a, e1a, r1, r0, LAM, 1.0)
        add_quad(r0, r1, e1b, e0b, LAM, 1.0)

# ---------- mini-saia de couro ----------
arm = np.load('arm.npy') if os.path.exists('arm.npy') else np.zeros(nv, bool)
Z_TOP, Z_BOT = 58.6, 47.2
corpo = (z > Z_BOT - 2) & (z < Z_TOP + 0.5) & ~arm & (L != 2) & (L != 3)
cpts = U[corpo]
ctr = cpts[:, :2].mean(0)
NA, NZ = 120, 10
th = np.linspace(-np.pi, np.pi, NA, endpoint=False)
angp = np.arctan2(cpts[:, 1] - ctr[1], cpts[:, 0] - ctr[0]); rp = np.linalg.norm(cpts[:, :2] - ctr, axis=1)
Rb = np.zeros((NZ, NA))
zs = np.linspace(Z_TOP, Z_BOT, NZ)
for i, zz_ in enumerate(zs):
    selz = np.abs(cpts[:, 2] - zz_) < 1.6 if i == 0 else (cpts[:, 2] < Z_TOP) & (cpts[:, 2] > zz_ - 1.0)
    for j, a0 in enumerate(th):
        dd_ = np.abs(((angp - a0 + np.pi) % (2 * np.pi)) - np.pi)
        w = selz & (dd_ < 2 * np.pi / NA * 1.5)
        Rb[i, j] = rp[w].max() if w.any() else np.nan
# preenche buracos e suaviza em volta
for i in range(NZ):
    r = Rb[i]; m_ = np.isnan(r)
    if m_.any(): r[m_] = np.interp(np.where(m_)[0], np.where(~m_)[0], r[~m_], period=NA)
    for k in range(3): r = (np.roll(r, 1) + r + np.roll(r, -1)) / 3
    Rb[i] = r
Rb = np.maximum.accumulate(Rb, axis=0)            # a saia só abre para baixo
fl = np.linspace(0, 1, NZ)[:, None]
R = Rb + 0.35 + 0.9 * fl + 0.18 * fl * np.sin(th[None, :] * 14)
SV = np.stack([ctr[0] + R * np.cos(th)[None, :], ctr[1] + R * np.sin(th)[None, :], np.repeat(zs[:, None], NA, 1)], 2)
# normais por diferenças
du = np.roll(SV, -1, 1) - np.roll(SV, 1, 1)
dv = np.vstack([SV[1:2] - SV[0:1], SV[2:] - SV[:-2], SV[-1:] - SV[-2:-1]])
SN = np.cross(dv, du); SN /= np.linalg.norm(SN, axis=2, keepdims=True) + 1e-12
out_ = np.stack([np.cos(th), np.sin(th), np.zeros_like(th)], 1)[None]
SN *= np.sign((SN * out_).sum(2, keepdims=True))
SAIA = srgb('3f2416')
SC = np.tile(SAIA, (NZ, NA, 1))
SC[-1] = BORDA; SC[0:2] = srgb('22140c')            # barra costurada e cinto
fiv = (np.abs(((th - (-np.pi / 2) + np.pi) % (2 * np.pi)) - np.pi) < 0.12)
SC[0:2, fiv] = FIVELA if 'FIVELA' in dir() else srgb('c8a050')
sk_t, sk_n, sk_c = [], [], []
for i in range(NZ - 1):
    for j in range(NA):
        j2 = (j + 1) % NA
        q = [(i, j), (i + 1, j), (i + 1, j2), (i, j2)]
        for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
            sk_t.append([SV[a_] for a_ in tri]); sk_n.append([SN[a_] for a_ in tri]); sk_c.append([SC[a_] for a_ in tri])
SKT, SKN, SKC = np.array(sk_t), np.array(sk_n), np.array(sk_c)
ET = np.array(extra_t); EC = np.array(extra_c); ES = np.array(extra_s)
EN = np.cross(ET[:, 1] - ET[:, 0], ET[:, 2] - ET[:, 0]); EN /= np.linalg.norm(EN, axis=1, keepdims=True) + 1e-12

# ---------- malha completa: posições, normais, cores, brilho por canto ----------
TP = np.concatenate([U[F], ET, SKT])
TN = np.concatenate([vn[F], np.repeat(EN[:, None], 3, 1), SKN])
TC = np.concatenate([col[F], np.repeat(EC[:, None], 3, 1), SKC])
TS = np.concatenate([spec[F][..., None].repeat(3, 2), np.repeat(ES[:, None, None], 3, 1).repeat(3, 2), np.full((len(SKT), 3, 3), 0.35)])
from scipy.sparse.csgraph import connected_components
_ok = (z < 42.5) & ~arm
_e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]); _m = _ok[_e[:, 0]] & _ok[_e[:, 1]]
_g = sp.coo_matrix((np.ones(_m.sum()), (_e[_m, 0], _e[_m, 1])), shape=(nv, nv))
_n, _lab = connected_components(_g, directed=False)
_lab[~_ok] = -1
_sz = np.bincount(_lab[_lab >= 0]); _top = np.argsort(-_sz)[:2]
lado_v = np.zeros(nv)
for c_ in _top:
    lado_v[_lab == c_] = np.sign(x[_lab == c_].mean())
print('pernas', _sz[_top], [np.sign(x[_lab == c_].mean()) for c_ in _top])
# vértices da virilha (z>=42.5) seguem o lado pela posição
lado_v[(lado_v == 0) & ~arm] = np.where(x[(lado_v == 0) & ~arm] > -0.4, 1, -1)
# extras (fita e adaga) ficam na perna +x
LADO = np.concatenate([lado_v[F], np.ones((len(ET), 3)), np.zeros((len(SKT), 3))])
ARMC = np.concatenate([arm[F], np.zeros((len(ET), 3), bool), np.zeros((len(SKT), 3), bool)])
np.savez('cena.npz', TP=TP, TN=TN, TC=TC, TS=TS, ARMC=ARMC, LADO=LADO)
print('tris', len(TP), 'extra', len(ET))
