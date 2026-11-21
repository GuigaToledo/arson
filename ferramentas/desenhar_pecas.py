#!/usr/bin/env python3
"""Desenha por código as peças simples do cenário em perspectiva isométrica,
com texturas (madeira procedural, pedra real ambientCG), luz vinda do alto à
esquerda e contorno escuro leve. Renderiza em 2x e reduz (bordas suaves).

  python3 ferramentas/desenhar_pecas.py   ->  godot/assets/objetos/<peça>.png
"""
import os, math
import numpy as np
from PIL import Image, ImageFilter

SS = 2                         # superamostragem
M = 46.0 * SS                  # pixels por metro (chão)
EX = np.array([0.894, 0.447]) * M   # eixo X do mundo na tela
EY = np.array([-0.894, 0.447]) * M  # eixo Y do mundo na tela
EZ = np.array([0.0, -1.0]) * M      # altura
OUT = 'godot/assets/objetos'
rng = np.random.default_rng(7)
ANCHORS = {}


def proj(x, y, z):
    return EX * x + EY * y + EZ * z


def smooth_noise(w, h, scale, seed=0):
    r = np.random.default_rng(seed)
    small = r.random((max(2, h // scale), max(2, w // scale)))
    return np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0


def wood_tex(w=256, h=256, planks=4, base=(0.25, 0.19, 0.14), seed=1, vertical=True):
    n = smooth_noise(w, h, 24, seed)
    fine = smooth_noise(w, h, 3, seed + 1)
    u = np.linspace(0, 1, w)[None, :].repeat(h, 0)
    v = np.linspace(0, 1, h)[:, None].repeat(w, 1)
    a, b = (u, v) if vertical else (v, u)
    grain = 0.5 + 0.5 * np.sin(a * 90 + n * 9 + b * 3)
    grime = smooth_noise(w, h, 10, seed + 9)
    idx = np.floor(a * planks)
    tint = np.random.default_rng(seed).random(planks + 1)[idx.astype(int)] * 0.25 + 0.85
    gap = (np.abs((a * planks) % 1 - 0.0) < 0.045) | (np.abs((a * planks) % 1 - 1.0) < 0.045)
    val = (0.62 + 0.26 * grain + 0.16 * fine) * tint * (0.7 + 0.45 * grime)
    val = np.where(gap, 0.35, val)
    img = np.stack([val * base[0], val * base[1], val * base[2]], -1) * 2.0
    return np.clip(img, 0, 1)


def photo_tex(path, darken=1.0):
    return np.asarray(Image.open(path).convert('RGB'), dtype=np.float32) / 255.0 * darken


def iron_tex():
    n = smooth_noise(64, 64, 6, 5)
    v = 0.22 + 0.12 * n
    return np.stack([v, v * 0.95, v * 0.9], -1)


class Canvas:
    def __init__(self, w, h, origin):
        self.w, self.h = w * SS, h * SS
        self.o = np.array(origin, dtype=float) * SS
        self.rgb = np.zeros((self.h, self.w, 3), np.float32)
        self.a = np.zeros((self.h, self.w), np.float32)
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        self.P = np.stack([xx, yy], -1).astype(np.float32)

    def face(self, p0, U, V, tex, shade, uv=(1, 1), tri=False):
        """Paralelogramo p0 + s*U + t*V (s,t em 0..1) com textura repetida uv vezes."""
        O = self.o + proj(*p0)
        u = proj(*U)
        v = proj(*V)
        Minv = np.linalg.inv(np.array([[u[0], v[0]], [u[1], v[1]]]))
        d = self.P - O
        st = d @ Minv.T
        s, t = st[..., 0], st[..., 1]
        m = (s >= 0) & (s <= 1) & (t >= 0) & (t <= 1)
        if tri:
            m &= (s + t) <= 1
        if not m.any():
            return
        th, tw = tex.shape[:2]
        tx = ((s[m] * uv[0]) % 1 * (tw - 1)).astype(int)
        ty = ((t[m] * uv[1]) % 1 * (th - 1)).astype(int)
        self.rgb[m] = tex[ty, tx] * shade
        self.a[m] = 1.0

    def box(self, x, y, z, dx, dy, dz, tex_side, tex_top=None, uv_side=(1, 1), uv_top=(1, 1), light=1.0):
        tex_top = tex_side if tex_top is None else tex_top
        # faces visíveis: frente-esquerda (y+dy), frente-direita (x+dx), topo
        self.face((x, y + dy, z + dz), (dx, 0, 0), (0, 0, -dz), tex_side, 0.82 * light, uv_side)
        self.face((x + dx, y + dy, z + dz), (0, -dy, 0), (0, 0, -dz), tex_side, 0.52 * light, uv_side)
        self.face((x, y, z + dz), (dx, 0, 0), (0, dy, 0), tex_top, 1.0 * light, uv_top)

    def cylinder(self, x, y, z, r, h, tex, bulge=0.0, top_tex=None, bands=(), band_tex=None):
        c = self.o + proj(x, y, z)
        R = r * M * 1.264  # raio horizontal na tela (círculo do chão vira elipse 2:1)
        rows_h = h * M
        th, tw = tex.shape[:2]
        dx = (self.P[..., 0] - c[0]) / R
        inside_x = np.abs(dx) <= 1.0
        e = np.sqrt(np.clip(1 - dx ** 2, 0, 1)) * R * 0.5
        top_y = c[1] - rows_h + e
        bot_y = c[1] + e
        py = self.P[..., 1]
        tt = np.clip((bot_y - py) / max(rows_h, 1e-3), 0, 1)
        k = 1 + bulge * np.sin(np.pi * tt)
        dxk = (self.P[..., 0] - c[0]) / (R * k)
        side = (np.abs(dxk) <= 1.0) & (py <= bot_y) & (py >= top_y)
        ang = np.arcsin(np.clip(dxk, -1, 1))
        shade = 0.38 + 0.62 * np.clip(np.cos(ang + 0.7), 0, 1)
        tx = ((ang / np.pi + 0.5) * 2 % 1 * (tw - 1)).astype(int)
        ty = (tt * (th - 1)).astype(int)
        col = tex[ty, tx] * shade[..., None]
        if bands:
            for b in bands:
                bm = np.abs(tt - b) < 0.045
                col = np.where(bm[..., None], band_tex[ty % band_tex.shape[0], tx % band_tex.shape[1]] * shade[..., None] * 1.3, col)
        self.rgb[side] = col[side]
        self.a[side] = 1.0
        # tampa
        ct = c + np.array([0, -rows_h])
        cap = ((self.P[..., 0] - ct[0]) / R) ** 2 + ((self.P[..., 1] - ct[1]) / (R * 0.5)) ** 2 <= 1.0
        tt_tex = top_tex if top_tex is not None else tex
        cy, cx = ((self.P[..., 1] - ct[1]) / R % 1 * (tt_tex.shape[0] - 1)).astype(int), ((self.P[..., 0] - ct[0]) / R % 1 * (tt_tex.shape[1] - 1)).astype(int)
        self.rgb[cap] = tt_tex[cy, cx][cap] * 0.95
        self.a[cap] = 1.0

    def roof(self, x, y, z, lx, dy, hr, tex, gable_tex):
        """Telhado de duas águas, cumeeira ao longo de X."""
        yc = y + dy / 2
        self.face((x, y, z), (lx, 0, 0), (0, dy / 2, hr), tex, 0.6, (3, 2))
        self.face((x + lx, y + dy, z), (0, -dy, 0), (0, -dy / 2, hr), gable_tex, 0.5, (1, 1), tri=True)
        self.face((x, yc, z + hr), (lx, 0, 0), (0, dy / 2, -hr), tex, 0.78, (3, 2))

    def glow(self, p, radius, color, strength=1.0):
        c = self.o + proj(*p)
        d = np.linalg.norm(self.P - c, axis=-1) / (radius * SS)
        g = np.clip(1 - d, 0, 1) ** 2 * strength
        self.rgb = self.rgb + np.array(color)[None, None, :] * g[..., None]
        self.a = np.maximum(self.a, np.clip(g * 1.2, 0, 1) * (d < 1))

    def save(self, name, outline=True):
        rgb = np.clip(self.rgb, 0, 1)
        # tom do jogo: dessatura, escurece e escurece mais perto do chão
        gray = rgb.mean(-1, keepdims=True)
        rgb = (gray + (rgb - gray) * 0.6) * 0.82
        ys = np.nonzero(self.a.max(1) > 0)[0]
        if len(ys):
            y0, y1 = ys.min(), ys.max()
            k = np.clip((np.arange(self.h) - y0) / max(1, y1 - y0), 0, 1)
            rgb = rgb * (1.08 - 0.38 * k ** 2)[:, None, None]
        a = self.a
        if outline:
            am = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3 * SS - 1))
            ring = (np.asarray(am, np.float32) / 255.0) * (1 - a)
            rgb = rgb * a[..., None] + np.array([0.06, 0.045, 0.035]) * ring[..., None]
            a = np.clip(a + ring * 0.85, 0, 1)
        img = Image.fromarray((np.dstack([rgb, a]) * 255).astype(np.uint8), 'RGBA')
        img = img.resize((self.w // SS, self.h // SS), Image.LANCZOS)
        bb = img.getchannel('A').getbbox() or (0, 0, img.size[0], img.size[1])
        img = img.crop(bb)
        img.save(os.path.join(OUT, name + '.png'))
        ANCHORS[name] = [round(self.o[0] / SS - bb[0], 1), round(self.o[1] / SS - bb[1], 1)]
        print(name, img.size, ANCHORS[name])


def main():
    os.makedirs(OUT, exist_ok=True)
    wood = wood_tex(seed=1)
    wood2 = wood_tex(seed=4, base=(0.30, 0.20, 0.12), planks=3)
    wood_h = wood_tex(seed=2, vertical=False)
    dark = wood_tex(seed=3, base=(0.2, 0.13, 0.08), planks=1)
    iron = iron_tex()
    stone = photo_tex('godot/assets/textures/stone_c.jpg', 0.62)

    # caixotes
    c = Canvas(200, 200, (100, 150))
    c.box(-0.5, -0.1, 0, 0.6, 0.6, 0.6, wood, uv_side=(1, 1))
    c.box(0.15, -0.5, 0, 0.6, 0.6, 0.6, wood2)
    c.box(-0.25, -0.35, 0.6, 0.55, 0.55, 0.55, wood)
    c.save('caixotes')

    # barril
    c = Canvas(120, 160, (60, 125))
    c.cylinder(0, 0, 0, 0.36, 0.95, wood_tex(seed=6, planks=10), bulge=0.12, top_tex=wood_tex(seed=7, vertical=False), bands=(0.15, 0.5, 0.85), band_tex=iron)
    c.save('barril')

    # cerca (ao longo do eixo X; espelhar na Godot para a outra diagonal)
    c = Canvas(260, 170, (40, 125))
    for i in range(6):
        x = i * 0.6
        c.box(x, 0, 0, 0.12, 0.12, 1.0 + 0.08 * math.sin(i * 2.1), dark)
    c.box(-0.05, 0.02, 0.3, 3.2, 0.08, 0.12, wood_h)
    c.box(-0.05, 0.02, 0.75, 3.2, 0.08, 0.12, wood_h)
    c.save('cerca')

    # banco
    c = Canvas(200, 140, (70, 100))
    c.box(0, 0, 0, 0.12, 0.38, 0.42, dark)
    c.box(1.45, 0, 0, 0.12, 0.38, 0.42, dark)
    c.box(-0.1, -0.02, 0.42, 1.8, 0.42, 0.09, wood_h)
    c.save('banco')

    # poste com lampião
    c = Canvas(130, 260, (55, 235))
    c.box(-0.1, -0.1, 0, 0.2, 0.2, 2.9, dark)
    c.box(-0.08, -0.08, 2.75, 0.75, 0.12, 0.09, dark)
    c.box(0.45, -0.12, 2.15, 0.26, 0.26, 0.42, iron)
    c.glow((0.58, 0.01, 2.36), 22, (1.0, 0.62, 0.22), 1.6)
    c.box(0.42, -0.15, 2.57, 0.32, 0.32, 0.06, iron)
    c.save('lampiao')

    # poço
    c = Canvas(240, 260, (120, 205))
    c.cylinder(0, 0, 0, 0.8, 0.75, stone, top_tex=np.zeros((8, 8, 3)) + np.array([0.03, 0.06, 0.08]))
    c.box(-0.85, -0.08, 0.75, 0.15, 0.15, 1.35, dark)
    c.box(0.72, -0.08, 0.75, 0.15, 0.15, 1.35, dark)
    c.box(-0.8, -0.04, 1.85, 1.65, 0.08, 0.08, dark)
    c.roof(-1.1, -0.7, 2.05, 2.2, 1.4, 0.55, wood_tex(seed=9, base=(0.2, 0.16, 0.13), planks=8, vertical=False), dark)
    c.cylinder(0.05, 0.05, 1.25, 0.16, 0.25, wood_tex(seed=8, planks=6), bands=(0.5,), band_tex=iron)
    c.save('poco')
    import json
    json.dump(ANCHORS, open(os.path.join(OUT, 'ancoras.json'), 'w'), indent=1)


main()
