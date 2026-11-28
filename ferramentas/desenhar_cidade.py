#!/usr/bin/env python3
"""Peças da cidade murada (muralha, torres, castelo, guilda, lojas) no mesmo estilo das casas
de desenhar_pecas.py. Usa as mesmas texturas e o mesmo acabamento.

  python3 ferramentas/desenhar_cidade.py [peça ...]   ->  godot/assets/objetos/<peça>.png
  (sem argumentos desenha todas; as âncoras entram em ancoras.json sem apagar as outras)

Medidas: 1 tile do mapa = 1/0,643 m. Uma peça de W x H tiles tem (W-0,3)/0,643 m por (H-0,3)/0,643 m
quando é uma casa (ver island.gd), e exatamente W/0,643 por H/0,643 m quando é muralha/torre.
"""
import os, sys, json, math
import numpy as np
from PIL import Image
import desenhar_pecas as dp
from desenhar_pecas import (proj, noise_tex, photo_tex, wood_tex, shingles, timber_wall,
                            window_tex, smooth_noise)

OUT = dp.OUT
T = 0.643
PX = 46.0  # pixels por metro antes do SS*RES


class Big(dp.Canvas):
    """Canvas que só calcula a área de cada face (as peças grandes ficam rápidas e leves)."""

    def __init__(self, w, h, origin):
        self.w, self.h = w * dp.SS * dp.RES, h * dp.SS * dp.RES
        self.o = np.array(origin, dtype=float) * dp.SS * dp.RES
        self.rgb = np.zeros((self.h, self.w, 3), np.float32)
        self.a = np.zeros((self.h, self.w), np.float32)
        self.emit = np.zeros((self.h, self.w), np.float32)

    def face(self, p0, U, V, tex, shade, uv=(1, 1), tri=False, disk=False, emit=False):
        O = self.o + proj(*p0)
        u = proj(*U)
        v = proj(*V)
        det = u[0] * v[1] - u[1] * v[0]
        if abs(det) < 1e-6:
            return
        pts = np.array([O, O + u, O + v, O + u + v])
        x0 = max(int(np.floor(pts[:, 0].min())) - 1, 0)
        x1 = min(int(np.ceil(pts[:, 0].max())) + 2, self.w)
        y0 = max(int(np.floor(pts[:, 1].min())) - 1, 0)
        y1 = min(int(np.ceil(pts[:, 1].max())) + 2, self.h)
        if x1 <= x0 or y1 <= y0:
            return
        yy, xx = np.mgrid[y0:y1, x0:x1]
        dx = xx.astype(np.float32) - O[0]
        dy = yy.astype(np.float32) - O[1]
        s = (dx * v[1] - dy * v[0]) / det
        t = (-dx * u[1] + dy * u[0]) / det
        m = (s >= 0) & (s <= 1) & (t >= 0) & (t <= 1)
        if tri:
            m &= (s + t) <= 1
        if disk:
            m &= (s - 0.5) ** 2 + (t - 0.5) ** 2 <= 0.25
        if not m.any():
            return
        th, tw = tex.shape[:2]
        tx = ((s[m] * uv[0]) % 1 * (tw - 1)).astype(int)
        ty = ((t[m] * uv[1]) % 1 * (th - 1)).astype(int)
        col = tex[ty, tx]
        ii, jj = np.nonzero(m)
        if col.shape[-1] == 4:
            keep = col[:, 3] > 0.5
            ii, jj, col = ii[keep], jj[keep], col[keep, :3]
        self.rgb[y0 + ii, x0 + jj] = col * shade
        self.a[y0 + ii, x0 + jj] = 1.0
        if emit:
            self.emit[y0 + ii, x0 + jj] = 1.0

    def glow(self, p, radius, color, strength=1.0):
        c = self.o + proj(*p)
        r = radius * dp.SS * dp.RES
        x0, x1 = max(int(c[0] - r), 0), min(int(c[0] + r) + 1, self.w)
        y0, y1 = max(int(c[1] - r), 0), min(int(c[1] + r) + 1, self.h)
        if x1 <= x0 or y1 <= y0:
            return
        yy, xx = np.mgrid[y0:y1, x0:x1]
        d = np.sqrt((xx - c[0]) ** 2 + (yy - c[1]) ** 2) / r
        g = np.clip(1 - d, 0, 1) ** 2 * strength
        self.rgb[y0:y1, x0:x1] += np.array(color)[None, None, :] * g[..., None]
        self.a[y0:y1, x0:x1] = np.maximum(self.a[y0:y1, x0:x1], np.clip(g * 1.2, 0, 1) * (d < 1))


def cv(L, D, H, pad=26, extra_h=0.0, extra_w=0.0):
    """Canvas do tamanho certo para uma peça de L x D metros no chão e H de altura."""
    ox = D * 0.894 * PX + pad + extra_w
    w = int((L + D) * 0.894 * PX + 2 * pad + 2 * extra_w)
    oy = (H + extra_h) * PX + pad
    h = int(oy + (L + D) * 0.447 * PX + pad)
    return Big(w, h, (ox, oy))


def save(c, name):
    c.save(name)
    # junta a âncora nova ao arquivo sem apagar as das outras peças
    path = os.path.join(OUT, 'ancoras.json')
    cur = json.load(open(path)) if os.path.exists(path) else {}
    cur[name] = dp.ANCHORS[name]
    json.dump(cur, open(path, 'w'), indent=1)


def pyramid(c, x0, y0, x1, y1, z, h, tex, uv=(2, 2)):
    """Telhado de pirâmide: as duas faces voltadas para a câmera."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    c.face((x0, y1, z), (x1 - x0, 0, 0), (cx - x0, cy - y1, h), tex, 0.82, uv, tri=True)
    c.face((x1, y1, z), (0, -(y1 - y0), 0), (cx - x1, cy - y1, h), tex, 0.5, uv, tri=True)


def merlons(c, x, y, z, L, D, tex, n_x=None, n_y=None, h=0.5, w=0.42, thick=0.34):
    """Ameias nas quatro bordas do topo de um bloco x..x+L, y..y+D, à altura z."""
    nx = n_x or max(2, int(L / 0.95))
    ny = n_y or max(2, int(D / 0.95))
    for i in range(nx):
        px = x + (i + 0.5) * L / nx - w / 2
        c.box(px, y, z, w, thick, h, tex)
        c.box(px, y + D - thick, z, w, thick, h, tex)
    for j in range(ny):
        py = y + (j + 0.5) * D / ny - w / 2
        c.box(x, py, z, thick, w, h, tex)
        c.box(x + L - thick, py, z, thick, w, h, tex)


def slit(c, x, y, z, along='x', h=0.9, w=0.2):
    """Seteira escura (janela estreita) numa face frontal."""
    dark = np.zeros((4, 4, 3), np.float32) + 0.03
    if along == 'x':   # face voltada para +y
        c.face((x, y, z + h), (w, 0, 0), (0, 0, -h), dark, 1.0)
    else:              # face voltada para +x
        c.face((x, y, z + h), (0, -w, 0), (0, 0, -h), dark, 1.0)


def stones():
    st = photo_tex('godot/assets/textures/stone_c.jpg', 0.66)
    stl = photo_tex('godot/assets/textures/stone_c.jpg', 0.82)
    return st, stl


def banner_tex(col, emblem=(0.9, 0.78, 0.35)):
    """Bandeira de pano com um brasão simples (losango) no meio."""
    h, w = 128, 64
    img = noise_tex(w, h, col, 0.12, 6, 3, 0.05)
    yy, xx = np.mgrid[0:h, 0:w]
    dia = (np.abs(xx - w / 2) / 14 + np.abs(yy - h * 0.42) / 18) < 1
    ring = (np.abs(xx - w / 2) / 20 + np.abs(yy - h * 0.42) / 26) < 1
    img[ring & ~dia] *= 0.6
    img[dia] = np.array(emblem)
    img[:6] *= 0.55
    # ponta em V embaixo
    vcut = (yy > h - 22) & (np.abs(xx - w / 2) < (yy - (h - 22)))
    out = np.zeros((h, w, 4), np.float32)
    out[..., :3] = img
    out[..., 3] = 1.0
    out[vcut, 3] = 0.0
    return out


# ---------------------------------------------------------------- peças

def muralha(name, along, seed):
    st, stl = stones()
    tile = 1.0 / T
    L, D = (2 * tile, tile) if along == 'x' else (tile, 2 * tile)
    H = 3.4
    c = cv(L, D, H + 0.7)
    uv = (2, 1)
    c.box(0, 0, 0, L, D, H, st, stl, uv_side=uv, uv_top=(2, 1))
    # base mais larga (pé da muralha)
    if along == 'x':
        merlons(c, 0, 0, H, L, D, stl, n_x=3, n_y=1)
    else:
        merlons(c, 0, 0, H, L, D, stl, n_x=1, n_y=3)
    # seteiras
    if along == 'x':
        slit(c, L * 0.5 - 0.1, D + 0.001, 1.6, 'x')
    else:
        slit(c, D + 0.001, L * 0.5 + 0.1, 1.6, 'y')
    save(c, name)


def torre(name, roof_base, H, seed, size_t=3.0, flag=None):
    st, stl = stones()
    S = size_t / T
    c = cv(S, S, H + 4.5, extra_w=10)
    c.box(0, 0, 0, S, S, 0.6, st, uv_side=(3, 1))
    c.box(0.12, 0.12, 0.6, S - 0.24, S - 0.24, H - 0.6, stl, uv_side=(3, 3))
    # faixa de pedra escura no alto e ameias
    c.box(-0.12, -0.12, H - 0.35, S + 0.24, S + 0.24, 0.35, st, uv_side=(4, 1))
    slate = shingles(base=roof_base, seed=seed, rows=14)
    pyramid(c, -0.35, -0.35, S + 0.35, S + 0.35, H, 3.2, slate, uv=(2, 2))
    # seteiras e janela iluminada
    win = window_tex()
    c.face((S * 0.5 - 0.28, S - 0.1, H - 1.9), (0.56, 0, 0), (0, 0, -0.9), win, 1.0, emit=True)
    c.glow((S * 0.5, S, H - 1.45), 30, (1.0, 0.6, 0.2), 0.5)
    slit(c, S * 0.2, S - 0.1, 1.6, 'x', h=1.1)
    slit(c, S * 0.76, S - 0.1, 1.6, 'x', h=1.1)
    slit(c, S - 0.1, S * 0.3, 1.6, 'y', h=1.1)
    slit(c, S - 0.1, S * 0.74, 1.6, 'y', h=1.1)
    if flag is not None:
        mast = wood_tex(seed=5, planks=1, base=(0.18, 0.13, 0.09))
        c.box(S / 2 - 0.05, S / 2 - 0.05, H + 3.2, 0.1, 0.1, 2.0, mast)
        c.face((S / 2 + 0.05, S / 2 - 0.02, H + 5.1), (0.0, -0.0, 0), (0, 0, 0), mast, 1.0)
        c.face((S / 2 + 0.05, S / 2, H + 5.1), (0.9, 0.0, 0), (0.0, 0.0, -1.25), flag, 0.9)
    save(c, name)


def castelo():
    """Salão do castelo: salão de pedra com telhado, torre alta ao centro e duas torrinhas."""
    st, stl = stones()
    wood = wood_tex(seed=1)
    dark = wood_tex(seed=3, base=(0.18, 0.13, 0.09), planks=1)
    win = window_tex()
    L, D = 15.0, 8.8
    HW = 6.2
    c = cv(L, D, 17.0, pad=40, extra_h=1.0, extra_w=120)
    # degraus da entrada e fundação
    c.box(0, 0, 0, L, D, 0.7, st, uv_side=(8, 1))
    c.box(0.15, 0.15, 0.7, L - 0.3, D - 0.3, HW, stl, uv_side=(8, 3))
    c.box(-0.15, -0.15, HW + 0.7 - 0.4, L + 0.3, D + 0.3, 0.4, st, uv_side=(9, 1))
    # janelas altas em arco simples, iluminadas
    for wx in (1.5, 3.7, 10.3, 12.5):
        c.face((wx, D - 0.2, 4.6), (0.6, 0, 0), (0, 0, -1.5), win, 1.0, emit=True)
        c.box(wx - 0.1, D - 0.22, 3.05, 0.8, 0.14, 0.1, st)
        c.glow((wx + 0.3, D, 3.8), 30, (1.0, 0.6, 0.2), 0.5)
    # janelas na empena direita
    for wy in (2.0, 5.4):
        c.face((L - 0.2, wy + 0.6, 4.6), (0, -0.6, 0), (0, 0, -1.5), win, 1.0, emit=True)
        c.glow((L, wy + 0.3, 3.8), 26, (1.0, 0.6, 0.2), 0.35)
    # portão grande ao centro com moldura e degraus
    c.box(L / 2 - 1.9, D - 0.2, 0.7, 3.8, 0.9, 0.5, st)
    c.face((L / 2 - 1.1, D - 0.14, 3.9), (2.2, 0, 0), (0, 0, -3.2), dark, 0.6)
    c.box(L / 2 - 1.35, D - 0.16, 3.9, 2.7, 0.2, 0.3, st)
    for sx in (-1.35, 1.1):
        c.box(L / 2 + sx, D - 0.16, 0.7, 0.25, 0.2, 3.5, st)
    c.glow((L / 2, D, 3.0), 36, (1.0, 0.6, 0.25), 0.35)
    # telhado de duas águas (cumeeira ao longo de X)
    sl = shingles(base=(0.36, 0.13, 0.1), seed=61, rows=16)
    zr = HW + 0.7
    yc = -0.5 + (D + 1.0) / 2
    c.face((-0.5, -0.5, zr), (L + 1.0, 0, 0), (0, (D + 1.0) / 2, 2.8), sl, 0.6, (6, 2))
    c.face((L + 0.5, D + 0.5, zr), (0, -(D + 1.0), 0), (0, -(D + 1.0) / 2, 2.8), stl, 0.5, (2, 1), tri=True)
    c.face((-0.5, yc, zr + 2.8), (L + 1.0, 0, 0), (0, (D + 1.0) / 2, -2.8), sl, 0.8, (6, 2))
    # torrinhas nas pontas da frente
    for tx in (-1.1, L - 2.3):
        TS = 3.4
        c.box(tx, D - 2.6, 0, TS, TS, 0.6, st, uv_side=(3, 1))
        c.box(tx + 0.1, D - 2.5, 0.6, TS - 0.2, TS - 0.2, 9.0, stl, uv_side=(3, 3))
        c.box(tx - 0.1, D - 2.7, 8.9, TS + 0.2, TS + 0.2, 0.4, st, uv_side=(4, 1))
        pyramid(c, tx - 0.35, D - 2.95, tx + TS + 0.35, D + 0.45 - 0.0, 9.3, 3.0, sl, uv=(2, 2))
        c.face((tx + TS * 0.5 - 0.3, D + 0.7 - 0.05, 7.4), (0.6, 0, 0), (0, 0, -1.0), win, 1.0, emit=True)
        slit(c, tx + 0.5, D + 0.8 - 0.05, 2.0, 'x', h=1.2)
    # torre mestra alta no centro-fundo
    TS = 5.0
    tx, ty = L / 2 - TS / 2, 0.9
    c.box(tx, ty, HW, TS, TS, 8.2, stl, uv_side=(3, 4))
    c.box(tx - 0.2, ty - 0.2, HW + 8.0, TS + 0.4, TS + 0.4, 0.5, st, uv_side=(4, 1))
    merlons(c, tx - 0.2, ty - 0.2, HW + 8.5, TS + 0.4, TS + 0.4, stl, n_x=4, n_y=4, h=0.7, w=0.65)
    for k, wx in enumerate((tx + 0.9, tx + 3.0)):
        c.face((wx, ty + TS - 0.05, HW + 5.6), (0.6, 0, 0), (0, 0, -1.3), win, 1.0, emit=True)
        c.glow((wx + 0.3, ty + TS, HW + 4.9), 30, (1.0, 0.6, 0.2), 0.4)
    slit(c, tx + TS - 0.05, ty + 1.2, HW + 3.0, 'y', h=1.4)
    slit(c, tx + TS - 0.05, ty + 3.2, HW + 3.0, 'y', h=1.4)
    # bandeiras vermelhas na fachada
    ban = banner_tex((0.55, 0.1, 0.1))
    for bx in (L / 2 - 3.4, L / 2 + 2.7):
        c.face((bx, D - 0.14, 5.7), (0.7, 0, 0), (0, 0, -2.0), ban, 0.95)
    # mastro com bandeira no topo da torre
    mast = wood_tex(seed=5, planks=1, base=(0.18, 0.13, 0.09))
    c.box(tx + TS / 2 - 0.06, ty + TS / 2 - 0.06, HW + 8.5 + 0.7, 0.12, 0.12, 3.0, mast)
    c.face((tx + TS / 2 + 0.06, ty + TS / 2, HW + 12.0), (1.2, 0, 0), (0, 0, -1.6), ban, 0.95)
    save(c, 'castelo')


def sign_tex(kind, bg=(0.2, 0.14, 0.09)):
    """Placa de madeira com um desenho simples (espadas, poção, bigorna)."""
    w, h = 96, 64
    img = noise_tex(w, h, bg, 0.18, 6, 7, 0.05)
    yy, xx = np.mgrid[0:h, 0:w]
    ink = np.zeros((h, w), bool)
    if kind == 'espadas':
        for sgn in (1, -1):
            d = np.abs((xx - w / 2) * sgn * 0.55 - (yy - h / 2)) < 2.2
            ink |= d & (np.abs(xx - w / 2) < 30)
        ink |= (np.abs(yy - h * 0.72) < 2.5) & (np.abs(xx - w / 2) < 9)
    elif kind == 'pocao':
        ink |= ((xx - w / 2) ** 2 + (yy - h * 0.62) ** 2) < 15 ** 2
        ink |= (np.abs(xx - w / 2) < 4) & (yy > h * 0.18) & (yy < h * 0.5)
    elif kind == 'bigorna':
        ink |= (np.abs(xx - w / 2) < 25 - (yy - h * 0.3) * 0.5) & (yy > h * 0.3) & (yy < h * 0.55)
        ink |= (np.abs(xx - w / 2) < 8) & (yy >= h * 0.55) & (yy < h * 0.7)
        ink |= (np.abs(xx - w / 2) < 17) & (yy >= h * 0.7) & (yy < h * 0.8)
    col = {'espadas': (0.82, 0.78, 0.7), 'pocao': (0.75, 0.2, 0.3), 'bigorna': (0.7, 0.7, 0.72)}[kind]
    img[ink] = col
    img[:3] = img[-3:] = img[:, :3] = img[:, -3:] = (0.1, 0.07, 0.04)
    return img


def awning_tex(a=(0.6, 0.12, 0.1), b=(0.85, 0.8, 0.7)):
    img = np.zeros((16, 64, 3), np.float32)
    for i in range(64):
        img[:, i] = a if (i // 8) % 2 == 0 else b
    return img * (0.9 + 0.1 * smooth_noise(64, 16, 4, 3))[..., None]


def porta(c, x, y, wdt, hgt, dark, st):
    """Porta de madeira com moldura de pedra na face voltada para +y."""
    c.face((x, y - 0.04, hgt), (wdt, 0, 0), (0, 0, -hgt), dark, 0.58)
    c.box(x - 0.2, y - 0.1, hgt, wdt + 0.4, 0.24, 0.28, st)
    c.box(x - 0.2, y - 0.1, 0, 0.2, 0.24, hgt, st)
    c.box(x + wdt, y - 0.1, 0, 0.2, 0.24, hgt, st)


def poste_placa(c, x, y, z, tex, face='y'):
    """Placa pendurada num braço de madeira, na parede da frente (+y) ou do lado (+x)."""
    d = wood_tex(seed=3, base=(0.18, 0.13, 0.09), planks=1)
    if face == 'y':
        c.box(x, y, z + 0.55, 0.9, 0.08, 0.08, d)
        c.box(x + 0.05, y, z, 0.05, 0.08, 0.6, d)
        c.face((x + 0.1, y + 0.12, z + 0.05), (0.75, 0, 0), (0, 0, -0.55), tex, 0.95)
    else:
        c.box(x, y, z + 0.55, 0.08, 0.9, 0.08, d)
        c.face((x + 0.12, y + 0.8, z + 0.05), (0, -0.75, 0), (0, 0, -0.55), tex, 0.75)


def guilda():
    st, stl = stones()
    dark = wood_tex(seed=3, base=(0.18, 0.13, 0.09), planks=1)
    win = window_tex()
    L, D, HW = 10.4, 7.3, 3.7
    c = cv(L, D, HW + 6.0, pad=40)
    wall = timber_wall(L, HW, seed=51)
    wall2 = timber_wall(D, HW, seed=52)
    c.box(0, 0, 0, L, D, 0.5, st, uv_side=(5, 1))
    c.box(0.08, 0.08, 0.5, L - 0.16, D - 0.16, HW, wall)
    for wx in (0.9, 2.7, 6.6, 8.4):
        c.face((wx, D - 0.06, 3.1), (0.8, 0, 0), (0, 0, -0.95), win, 1.0, emit=True)
        c.glow((wx + 0.4, D, 2.6), 36, (1.0, 0.6, 0.2), 0.45)
    for wy in (1.6, 4.4):
        c.face((L - 0.06, wy + 0.8, 3.1), (0, -0.8, 0), (0, 0, -0.95), win, 1.0, emit=True)
    porta(c, L / 2 - 0.9, D - 0.05, 1.8, 2.5, dark, st)
    c.box(L / 2 - 1.3, D - 0.05, 0.5, 2.6, 0.7, 0.18, st)   # degrau
    poste_placa(c, L / 2 + 1.8, D, 2.6, sign_tex('espadas'), 'y')
    ban = banner_tex((0.15, 0.25, 0.5))
    for bx in (1.7, L - 2.6):
        c.face((bx, D - 0.05, 3.6), (0.7, 0, 0), (0, 0, -1.6), ban, 0.95)
    sl = shingles(base=(0.3, 0.17, 0.12), seed=71, rows=16)
    zr = HW + 0.5
    yc = -0.4 + (D + 0.8) / 2
    c.face((-0.4, -0.4, zr), (L + 0.8, 0, 0), (0, (D + 0.8) / 2, 2.6), sl, 0.6, (5, 2))
    c.face((L + 0.4, D + 0.4, zr), (0, -(D + 0.8), 0), (0, -(D + 0.8) / 2, 2.6), timber_wall(D, 2.4, 53), 0.5, (1, 1), tri=True)
    c.face((-0.4, yc, zr + 2.6), (L + 0.8, 0, 0), (0, (D + 0.8) / 2, -2.6), sl, 0.8, (5, 2))
    c.box(L * 0.2, D * 0.18, zr, 0.7, 0.7, 3.3, stl, uv_side=(1, 2))
    save(c, 'guilda')


def loja():
    st, stl = stones()
    dark = wood_tex(seed=3, base=(0.18, 0.13, 0.09), planks=1)
    wood = wood_tex(seed=1)
    win = window_tex()
    L, D, HW = 4.2, 4.2, 2.6
    c = cv(L, D, HW + 3.6, pad=40)
    wall = timber_wall(L, HW, seed=61)
    c.box(0, 0, 0, L, D, 0.4, st, uv_side=(3, 1))
    c.box(0.05, 0.05, 0.4, L - 0.1, D - 0.1, HW, wall)
    # balcão aberto na frente, com toldo listrado
    c.face((0.5, D - 0.04, 2.2), (1.7, 0, 0), (0, 0, -1.0), win, 1.0, emit=True)
    c.glow((1.35, D, 1.7), 36, (1.0, 0.6, 0.2), 0.5)
    c.box(0.4, D, 0.4, 1.9, 0.5, 0.75, wood)
    porta(c, 2.8, D - 0.04, 0.9, 1.7, dark, st)
    aw = awning_tex()
    c.face((0.3, D, 2.55), (2.2, 0, 0), (0, 0.95, -0.55), aw, 0.9, (1, 1))
    poste_placa(c, 3.1, D, 2.35, sign_tex('pocao'), 'y')
    c.face((L - 0.04, D * 0.5 + 0.3, 2.2), (0, -0.7, 0), (0, 0, -0.8), win, 1.0, emit=True)
    sh = shingles(base=(0.12, 0.2, 0.18), seed=81, rows=14)
    yc = -0.35 + (D + 0.7) / 2
    c.face((-0.3, -0.35, 3.0), (L + 0.6, 0, 0), (0, (D + 0.7) / 2, 2.0), sh, 0.55, (3, 2))
    c.face((L + 0.3, D + 0.35, 3.0), (0, -(D + 0.7), 0), (0, -(D + 0.7) / 2, 2.0), timber_wall(D, 2.0, 62), 0.5, (1, 1), tri=True)
    c.face((-0.3, yc, 5.0), (L + 0.6, 0, 0), (0, (D + 0.7) / 2, -2.0), sh, 0.8, (3, 2))
    c.box(0.7, D * 0.2, 2.9, 0.55, 0.55, 2.8, stl, uv_side=(1, 2))
    save(c, 'loja')


def ferraria():
    st, stl = stones()
    dark = wood_tex(seed=3, base=(0.18, 0.13, 0.09), planks=1)
    win = window_tex()
    iron = dp.iron_tex()
    L, D, HW = 4.2, 4.2, 2.6
    c = cv(L, D, HW + 5.0, pad=40)
    c.box(0, 0, 0, L, D, 0.4, st, uv_side=(3, 1))
    c.box(0.05, 0.05, 0.4, L - 0.1, D - 0.1, HW, stl, uv_side=(3, 2))
    # forja aberta: boca escura com brasa
    c.face((0.6, D - 0.04, 2.2), (1.9, 0, 0), (0, 0, -1.7), np.zeros((4, 4, 3)) + 0.05, 1.0)
    c.face((0.9, D - 0.05, 1.0), (1.3, 0, 0), (0, 0, -0.45), np.zeros((4, 4, 3)) + np.array([1.0, 0.38, 0.1]), 1.0, emit=True)
    c.glow((1.55, D, 0.9), 50, (1.0, 0.45, 0.1), 0.9)
    c.box(2.8, D + 0.3, 0.4, 0.8, 0.45, 0.45, iron)       # bigorna na frente
    c.box(2.95, D + 0.38, 0.85, 0.5, 0.3, 0.12, iron)
    porta(c, 2.9, D - 0.04, 0.9, 1.75, dark, st)
    poste_placa(c, 2.3, D, 2.4, sign_tex('bigorna'), 'y')
    sh = shingles(base=(0.2, 0.16, 0.14), seed=91, rows=14)
    yc = -0.35 + (D + 0.7) / 2
    c.face((-0.3, -0.35, 3.0), (L + 0.6, 0, 0), (0, (D + 0.7) / 2, 1.8), sh, 0.55, (3, 2))
    c.face((L + 0.3, D + 0.35, 3.0), (0, -(D + 0.7), 0), (0, -(D + 0.7) / 2, 1.8), stl, 0.5, (1, 1), tri=True)
    c.face((-0.3, yc, 4.8), (L + 0.6, 0, 0), (0, (D + 0.7) / 2, -1.8), sh, 0.8, (3, 2))
    # chaminé alta, quente no topo
    c.box(L - 1.5, D * 0.35, 2.8, 0.8, 0.8, 4.4, stl, uv_side=(1, 3))
    c.glow((L - 1.1, D * 0.35 + 0.8, 7.0), 30, (1.0, 0.4, 0.1), 0.35)
    save(c, 'ferraria')


PECAS = {
    'guilda': guilda,
    'loja': loja,
    'ferraria': ferraria,
    'muralha_x': lambda: muralha('muralha_x', 'x', 1),
    'muralha_y': lambda: muralha('muralha_y', 'y', 2),
    'torre_cidade': lambda: torre('torre_cidade', (0.17, 0.18, 0.22), 8.2, 41, 3.0, banner_tex((0.15, 0.25, 0.5))),
    'torre_castelo': lambda: torre('torre_castelo', (0.38, 0.14, 0.1), 6.8, 43, 3.0),
    'castelo': castelo,
}

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    want = sys.argv[1:] or list(PECAS)
    for n in want:
        PECAS[n]()
