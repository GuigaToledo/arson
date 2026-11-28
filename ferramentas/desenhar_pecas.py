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
RES = 2                        # resolução final (2 = dobro; no jogo usa escala 0.5)
M = 46.0 * SS * RES            # pixels por metro
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
        self.w, self.h = w * SS * RES, h * SS * RES
        self.o = np.array(origin, dtype=float) * SS * RES
        self.rgb = np.zeros((self.h, self.w, 3), np.float32)
        self.a = np.zeros((self.h, self.w), np.float32)
        self.emit = np.zeros((self.h, self.w), np.float32)
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        self.P = np.stack([xx, yy], -1).astype(np.float32)

    def face(self, p0, U, V, tex, shade, uv=(1, 1), tri=False, disk=False, emit=False):
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
        if disk:
            m &= (s - 0.5) ** 2 + (t - 0.5) ** 2 <= 0.25
        if not m.any():
            return
        th, tw = tex.shape[:2]
        tx = ((s[m] * uv[0]) % 1 * (tw - 1)).astype(int)
        ty = ((t[m] * uv[1]) % 1 * (th - 1)).astype(int)
        col = tex[ty, tx]
        if col.shape[-1] == 4:
            keep = col[:, 3] > 0.5
            idx = np.nonzero(m)
            m2 = np.zeros_like(m)
            m2[idx[0][keep], idx[1][keep]] = True
            col = col[keep, :3]
            m = m2
        self.rgb[m] = col * shade
        self.a[m] = 1.0
        if emit:
            self.emit[m] = 1.0

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

    def blob(self, x, y, z, r, tex, ry=1.0, rough=0.18, seed=0, light=1.0):
        c = self.o + proj(x, y, z)
        R = r * M * 1.1
        d = self.P - c
        dx, dy = d[..., 0] / R, d[..., 1] / (R * ry)
        dd = dx * dx + dy * dy
        if not hasattr(self, '_nz'):
            self._nz = smooth_noise(self.w, self.h, max(2, int(6 * SS * RES / 2)), 99)
        m = dd < (1 - rough * self._nz) ** 2
        if not m.any():
            return
        nz = np.sqrt(np.clip(1 - dd, 0, 1))
        L = np.array([-0.55, -0.65, 0.52])
        L = L / np.linalg.norm(L)
        sh = 0.3 + 0.75 * np.clip(dx * L[0] + dy * L[1] + nz * L[2], 0, 1)
        th, tw = tex.shape[:2]
        tx = (self.P[..., 0] % tw).astype(int)
        ty = (self.P[..., 1] % th).astype(int)
        col = tex[ty, tx] * (sh * light)[..., None]
        self.rgb[m] = col[m]
        self.a[m] = 1.0

    def roof(self, x, y, z, lx, dy, hr, tex, gable_tex):
        """Telhado de duas águas, cumeeira ao longo de X."""
        yc = y + dy / 2
        self.face((x, y, z), (lx, 0, 0), (0, dy / 2, hr), tex, 0.6, (3, 2))
        self.face((x + lx, y + dy, z), (0, -dy, 0), (0, -dy / 2, hr), gable_tex, 0.5, (1, 1), tri=True)
        self.face((x, yc, z + hr), (lx, 0, 0), (0, dy / 2, -hr), tex, 0.78, (3, 2))

    def glow(self, p, radius, color, strength=1.0):
        c = self.o + proj(*p)
        d = np.linalg.norm(self.P - c, axis=-1) / (radius * SS * RES)
        g = np.clip(1 - d, 0, 1) ** 2 * strength
        self.rgb = self.rgb + np.array(color)[None, None, :] * g[..., None]
        self.a = np.maximum(self.a, np.clip(g * 1.2, 0, 1) * (d < 1))

    def weather(self, rgb):
        """Acabamento realista: sujeira em manchas, escorridos de chuva, oclusão de ambiente nas
        bordas e cantos, luz de contorno no lado da luz (alto à esquerda) e musgo/umidade na base."""
        a = self.a
        k = SS * RES
        big = smooth_noise(self.w, self.h, 22 * k, 11)
        fine = smooth_noise(self.w, self.h, 2 * k, 12)
        rgb = rgb * (0.78 + 0.34 * big)[..., None] * (0.9 + 0.2 * fine)[..., None]
        # escorridos verticais (chuva)
        st = np.asarray(Image.fromarray((smooth_noise(self.w, 8, 3 * k, 13) * 255).astype(np.uint8)).resize((self.w, self.h), Image.BICUBIC), np.float32) / 255.0
        rgb = rgb * (0.88 + 0.16 * st)[..., None]
        # oclusão de ambiente: perto da borda da silhueta fica mais escuro
        am = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5 * k))
        ab = np.asarray(am, np.float32) / 255.0
        ao = np.clip((ab - 0.45) / 0.55, 0, 1)
        rgb = rgb * (0.72 + 0.28 * ao)[..., None]
        # luz de contorno: pixel cheio com vizinho vazio no lado da luz
        sh = int(2 * k)
        nb = np.zeros_like(a)
        nb[sh:, sh:] = a[:-sh, :-sh]
        rim = np.clip(a - nb, 0, 1)
        rim = np.asarray(Image.fromarray((rim * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(k)), np.float32) / 255.0
        rgb = rgb + np.array([0.16, 0.12, 0.07])[None, None, :] * rim[..., None] * a[..., None]
        # base úmida com musgo
        ys = np.nonzero(a.max(1) > 0)[0]
        if len(ys):
            y0, y1 = ys.min(), ys.max()
            t = np.clip((np.arange(self.h) - (y1 - (y1 - y0) * 0.22)) / max(1, (y1 - y0) * 0.22), 0, 1)
            moss = (t[:, None] * np.clip(big * 1.6 - 0.5, 0, 1))[..., None]
            rgb = rgb * (1 - 0.25 * moss) + np.array([0.12, 0.16, 0.06]) * moss * 0.6
        return rgb

    def save(self, name, outline=True):
        rgb = np.clip(self.weather(self.rgb), 0, 1)
        # tom do jogo: dessatura, escurece e escurece mais perto do chão
        gray = rgb.mean(-1, keepdims=True)
        rgb = (gray + (rgb - gray) * 0.6) * 0.82
        ys = np.nonzero(self.a.max(1) > 0)[0]
        if len(ys):
            y0, y1 = ys.min(), ys.max()
            k = np.clip((np.arange(self.h) - y0) / max(1, y1 - y0), 0, 1)
            rgb = rgb * (1.08 - 0.38 * k ** 2)[:, None, None]
        e = self.emit[..., None]
        rgb = rgb * (1 - e) + np.clip(self.rgb, 0, 1) * e
        a = self.a
        if outline:
            am = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * SS * RES - 1))
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


def noise_tex(w, h, base, var=0.25, scale=6, seed=0, speck=0.15):
    n = smooth_noise(w, h, scale, seed) * 0.7 + smooth_noise(w, h, max(2, scale // 3), seed + 1) * 0.3
    sp = np.random.default_rng(seed).random((h, w)) * speck
    v = (1 - var) + var * 2 * n - sp
    return np.clip(np.stack([v * base[0], v * base[1], v * base[2]], -1), 0, 1)


def timber_wall(w_m, h_m, seed=0):
    W, H = int(64 * w_m), int(64 * h_m)
    img = noise_tex(W, H, (0.55, 0.5, 0.42), 0.18, 8, seed, 0.1)
    beam = noise_tex(W, H, (0.17, 0.12, 0.08), 0.2, 5, seed + 3, 0.05)
    m = np.zeros((H, W), bool)
    t = 9
    m[:t], m[-t:], m[H // 2 - t // 2:H // 2 + t // 2] = True, True, True
    n = max(2, int(round(w_m / 1.1)))
    for i in range(n + 1):
        x = int(i * (W - t) / n)
        m[:, x:x + t] = True
    yy, xx = np.mgrid[0:H, 0:W]
    bay = (W - t) / n
    for x0, sgn in ((0, 1), (W - t - bay, -1)):
        u = (xx - x0) / bay
        v = 1 - yy / (H / 2)
        diag = (np.abs((u if sgn > 0 else 1 - u) - v) < t / bay * 0.9) & (u >= 0) & (u <= 1) & (yy < H / 2)
        m |= diag
    img[m] = beam[m]
    return img


def shingles(w=256, h=256, base=(0.2, 0.16, 0.14), rows=12, seed=0):
    img = noise_tex(w, h, base, 0.25, 4, seed, 0.12)
    r = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w]
    rh = h / rows
    row = (yy // rh).astype(int)
    off = (row % 2) * 0.5
    cols = 10
    cell = ((xx / (w / cols) + off) % 1)
    gap = (cell < 0.06) | ((yy % rh) > rh * 0.86)
    tint = r.random((rows + 1, cols + 2))[row, ((xx / (w / cols) + off) // 1).astype(int) % (cols + 2)] * 0.35 + 0.8
    img = img * tint[..., None]
    shade = 0.75 + 0.25 * ((yy % rh) / rh)
    img = img * shade[..., None]
    img[gap] *= 0.45
    return img


def window_tex():
    w = h = 64
    img = np.zeros((h, w, 3), np.float32) + np.array([1.0, 0.68, 0.3])
    yy, xx = np.mgrid[0:h, 0:w]
    img *= (0.75 + 0.25 * (1 - yy / h))[..., None]
    frame = (xx < 6) | (xx > w - 7) | (yy < 6) | (yy > h - 7) | (np.abs(xx - w / 2) < 3) | (np.abs(yy - h / 2) < 3)
    img[frame] = [0.12, 0.08, 0.05]
    return img


def wheel_tex():
    s = 128
    yy, xx = np.mgrid[0:s, 0:s]
    dx, dy = (xx - s / 2) / (s / 2), (yy - s / 2) / (s / 2)
    r = np.sqrt(dx * dx + dy * dy)
    a = np.arctan2(dy, dx)
    wood = noise_tex(s, s, (0.27, 0.19, 0.12), 0.25, 4, 5)
    rim = (r > 0.8) & (r <= 1.0)
    hub = r < 0.18
    spokes = (np.abs(((a / (2 * np.pi / 8)) % 1) - 0.5) > 0.42) & (r < 0.85)
    al = (rim | hub | spokes).astype(np.float32)
    img = np.dstack([wood * np.where(rim, 0.8, 1.0)[..., None], al])
    img[rim & (r > 0.94), :3] = [0.15, 0.14, 0.13]
    return img


def leaves(base, seed):
    t = noise_tex(256, 256, base, 0.35, 3, seed, 0.35)
    clump = smooth_noise(256, 256, 14, seed + 5)
    return np.clip(t * (0.65 + 0.6 * clump)[..., None], 0, 1)


def tree(name, base, seed, pine=False):
    c = Canvas(280, 300, (140, 270))  # largo: a copa não pode ser cortada na borda (virava faixa reta ao ficar transparente)
    bark = noise_tex(64, 128, (0.2, 0.15, 0.11), 0.3, 3, seed + 2, 0.2)
    c.cylinder(0, 0, 0, 0.26, 2.0 if not pine else 1.2, bark)
    lv = leaves(base, seed)
    r = np.random.default_rng(seed)
    blobs = []
    if pine:
        for i in range(7):
            z = 1.0 + i * 0.55
            rad = 1.25 - i * 0.16
            blobs.append((0, 0, z, rad, 0.45))
    else:
        blobs.append((0, 0, 3.0, 1.4, 0.85))
        for i in range(9):
            ang = r.random() * 2 * np.pi
            d = 0.6 + r.random() * 0.5
            blobs.append((np.cos(ang) * d, np.sin(ang) * d, 2.3 + r.random() * 1.4, 0.8 + r.random() * 0.4, 0.85))
    blobs.sort(key=lambda b: b[0] + b[1] + b[2] * 0.3)
    for (x, y, z, rad, ry) in blobs:
        c.blob(x, y, z, rad, lv, ry=ry, rough=0.22)
    c.save(name)


def habitat_pieces(stone, stone_l, dark, wood_h, iron):
    """Peças das regiões novas: cemitério, caverna, selva e acampamentos."""
    moss = (0.28, 0.3, 0.22)
    grave = photo_tex('godot/assets/textures/stone_c.jpg', 0.55)
    # lápides
    for k in range(2):
        c = Canvas(120, 150, (60, 120))
        c.box(-0.3, -0.12, 0, 0.6, 0.24, 0.12, grave)
        if k == 0:
            c.box(-0.22, -0.07, 0.12, 0.44, 0.14, 0.7, grave)
            c.cylinder(0, 0, 0.72, 0.22, 0.1, grave)
        else:
            c.box(-0.06, -0.06, 0.12, 0.12, 0.12, 0.95, grave)
            c.box(-0.28, -0.06, 0.62, 0.56, 0.12, 0.12, grave)

        c.save('lapide' if k == 0 else 'lapide_cruz')
    # cruz de madeira torta
    c = Canvas(110, 160, (55, 130))
    c.box(-0.05, -0.05, 0, 0.1, 0.1, 1.1, dark)
    c.box(-0.3, -0.04, 0.72, 0.6, 0.08, 0.08, dark)
    c.save('cruz')
    # cerca de ferro
    c = Canvas(260, 170, (40, 125))
    for i in range(9):
        c.box(i * 0.4, 0, 0, 0.05, 0.05, 1.0 + 0.15 * (i % 2), iron)
    c.box(-0.05, 0.0, 0.25, 3.35, 0.05, 0.06, iron)
    c.box(-0.05, 0.0, 0.85, 3.35, 0.05, 0.06, iron)
    c.save('cerca_ferro')
    # cripta (mausoléu)
    c = Canvas(330, 330, (165, 200))
    L, D = 2.6, 2.2
    c.box(0, 0, 0, L, D, 0.3, grave, uv_side=(2, 1))
    c.box(0.1, 0.1, 0.3, L - 0.2, D - 0.2, 1.9, stone, uv_side=(2, 2))
    c.face((L / 2 - 0.4, D - 0.09, 1.75), (0.8, 0, 0), (0, 0, -1.45), np.zeros((4, 4, 3)) + 0.02, 1.0)
    for px in (L / 2 - 0.7, L / 2 + 0.55):
        c.box(px, D - 0.15, 0.3, 0.16, 0.16, 1.9, stone_l)
    slate = shingles(base=(0.12, 0.12, 0.14), seed=81, rows=8)
    c.roof(-0.15, -0.15, 2.2, L + 0.3, D + 0.3, 0.8, slate, stone)
    c.box(L / 2 - 0.05, D / 2 - 0.05, 3.0, 0.1, 0.1, 0.6, stone_l)
    c.box(L / 2 - 0.22, D / 2 - 0.05, 3.35, 0.44, 0.1, 0.1, stone_l)
    c.glow((L / 2, D, 1.0), 26, (0.45, 0.9, 0.55), 0.6)

    c.save('cripta')
    # árvore morta (galhos secos)
    c = Canvas(220, 280, (110, 250))
    bark = noise_tex(64, 128, (0.17, 0.14, 0.12), 0.3, 3, 90, 0.2)
    c.cylinder(0, 0, 0, 0.22, 2.4, bark, bulge=-0.05)
    r = np.random.default_rng(91)
    for i in range(6):
        ang = i / 6 * 2 * np.pi + r.random() * 0.5
        z = 1.4 + r.random() * 1.0
        for j in range(14):
            d = 0.12 + j * 0.06
            c.blob(np.cos(ang) * d, np.sin(ang) * d, z + j * 0.055 + (j / 14) ** 2 * 0.3, 0.07 - j * 0.0035, bark, rough=0.05)
    c.save('arvore_morta')
    # ossos no chão
    c = Canvas(130, 80, (65, 50))
    bone = noise_tex(32, 32, (0.78, 0.74, 0.62), 0.15, 3, 95)
    c.box(-0.4, -0.04, 0, 0.8, 0.08, 0.07, bone)
    c.box(0.0, -0.3, 0, 0.07, 0.6, 0.07, bone)
    c.blob(0.3, 0.25, 0.1, 0.14, bone, rough=0.08)
    c.save('ossos')
    # caverna: rochedo grande, estalagmite e cristal
    cave = noise_tex(128, 128, (0.3, 0.28, 0.26), 0.3, 5, 99, 0.25)
    for k in range(2):
        c = Canvas(300, 320, (150, 230))
        r = np.random.default_rng(100 + k)
        for i in range(5):
            c.blob(r.random() * 1.0 - 0.5, r.random() * 1.0 - 0.5, 0.5 + r.random() * 1.2 + i * 0.25, 0.7 + r.random() * 0.4, cave, ry=0.75, rough=0.12)
        c.save('rochedo' if k == 0 else 'rochedo2')
    c = Canvas(120, 220, (60, 190))
    for i in range(6):
        c.cylinder(0, 0, i * 0.3, 0.3 - i * 0.045, 0.32, cave)
    c.save('estalagmite')
    c = Canvas(130, 170, (65, 140))
    crys = noise_tex(32, 32, (0.35, 0.55, 0.85), 0.25, 3, 110)
    for (x, y, h) in ((0, 0, 1.1), (0.22, 0.1, 0.7), (-0.2, 0.12, 0.6)):
        c.box(x - 0.08, y - 0.08, 0, 0.16, 0.16, h, crys, light=1.3)
    c.glow((0, 0, 0.6), 30, (0.4, 0.7, 1.0), 0.9)
    c.save('cristal')
    # selva: árvore grande com copa larga, palmeira-de-folhas e samambaia
    tree('arvore_selva', (0.08, 0.2, 0.07), 120)
    tree('arvore_selva2', (0.15, 0.22, 0.05), 121)
    c = Canvas(220, 160, (110, 120))
    lv = leaves((0.12, 0.26, 0.08), 130)
    r = np.random.default_rng(131)
    for i in range(7):
        a = i / 7 * 2 * np.pi
        c.blob(np.cos(a) * 0.5, np.sin(a) * 0.5, 0.25 + r.random() * 0.2, 0.42, lv, ry=0.5, rough=0.3)
    c.blob(0, 0, 0.45, 0.45, lv, ry=0.6, rough=0.3)
    c.save('samambaia')
    # acampamentos: paliçada, tenda de couro, totem
    logs = wood_tex(seed=140, base=(0.24, 0.17, 0.1), planks=1)
    c = Canvas(260, 220, (40, 170))
    for i in range(7):
        h = 1.6 + 0.2 * math.sin(i * 1.7)
        c.cylinder(i * 0.45, 0, 0, 0.2, h, logs)
        c.cylinder(i * 0.45, 0, h, 0.12, 0.2, logs)
    c.box(-0.1, 0.15, 0.9, 3.1, 0.06, 0.1, dark)
    c.save('palicada')
    hide = noise_tex(128, 128, (0.42, 0.3, 0.2), 0.25, 5, 150, 0.1)
    for k, base in enumerate([(0.42, 0.3, 0.2), (0.3, 0.32, 0.22)]):
        hide = noise_tex(128, 128, base, 0.25, 5, 150 + k, 0.1)
        c = Canvas(260, 260, (130, 190))
        top = (0, 0, 2.3)
        b = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]
        for (p, q, sh) in ((b[0], b[3], 0.55), (b[3], b[2], 0.8), (b[2], b[1], 0.5)):
            c.face((p[0], p[1], 0), (q[0] - p[0], q[1] - p[1], 0), (top[0] - p[0], top[1] - p[1], 2.3), hide, sh, tri=True)
        c.face((-0.25, 1.0, 0.9), (0.5, 0, 0), (0, 0, -0.9), np.zeros((4, 4, 3)) + 0.04, 1.0)
        for (x, y) in ((0.15, 0.1), (-0.12, 0.12)):
            c.box(x - 0.03, y - 0.03, 2.2, 0.06, 0.06, 0.55, dark)
        c.save('tenda_couro' if k == 0 else 'tenda_orc')
    c = Canvas(130, 300, (65, 270))
    tot = wood_tex(seed=160, base=(0.3, 0.2, 0.12), planks=1)
    c.cylinder(0, 0, 0, 0.26, 2.8, tot, bands=(0.3, 0.55, 0.8), band_tex=noise_tex(16, 16, (0.55, 0.15, 0.1), 0.2, 2, 161))
    c.box(-0.6, -0.08, 2.2, 1.2, 0.16, 0.2, tot)
    c.blob(0, 0, 3.0, 0.24, noise_tex(32, 32, (0.78, 0.74, 0.62), 0.15, 3, 162), rough=0.1)
    c.save('totem')
    # rochas de ciclope (pedra rolada gigante)
    c = Canvas(280, 260, (140, 190))
    rk = noise_tex(128, 128, (0.4, 0.37, 0.33), 0.3, 5, 170, 0.25)
    c.blob(0, 0, 0.9, 1.1, rk, ry=0.85, rough=0.1)
    c.blob(0.7, 0.5, 0.4, 0.5, rk, ry=0.8, rough=0.1)
    c.save('pedregulho')


def main():
    os.makedirs(OUT, exist_ok=True)
    wood = wood_tex(seed=1)
    wood2 = wood_tex(seed=4, base=(0.22, 0.17, 0.12), planks=3)
    wood_h = wood_tex(seed=2, vertical=False)
    dark = wood_tex(seed=3, base=(0.18, 0.13, 0.09), planks=1)
    iron = iron_tex()
    stone = photo_tex('godot/assets/textures/stone_c.jpg', 0.62)
    stone_l = photo_tex('godot/assets/textures/stone_c.jpg', 0.78)
    win = window_tex()

    # ---------------- peças pequenas
    c = Canvas(200, 200, (100, 150))
    c.box(-0.5, -0.1, 0, 0.6, 0.6, 0.6, wood)
    c.box(0.15, -0.5, 0, 0.6, 0.6, 0.6, wood2)
    c.box(-0.25, -0.35, 0.6, 0.55, 0.55, 0.55, wood)
    c.save('caixotes')

    c = Canvas(120, 160, (60, 125))
    c.cylinder(0, 0, 0, 0.36, 0.95, wood_tex(seed=6, planks=10), bulge=0.12, top_tex=wood_tex(seed=7, vertical=False), bands=(0.15, 0.5, 0.85), band_tex=iron)
    c.save('barril')

    c = Canvas(260, 170, (40, 125))
    for i in range(6):
        c.box(i * 0.6, 0, 0, 0.12, 0.12, 1.0 + 0.08 * math.sin(i * 2.1), dark)
    c.box(-0.05, 0.02, 0.3, 3.2, 0.08, 0.12, wood_h)
    c.box(-0.05, 0.02, 0.75, 3.2, 0.08, 0.12, wood_h)
    c.save('cerca')

    c = Canvas(200, 140, (70, 100))
    c.box(0, 0, 0, 0.12, 0.38, 0.42, dark)
    c.box(1.45, 0, 0, 0.12, 0.38, 0.42, dark)
    c.box(-0.1, -0.02, 0.42, 1.8, 0.42, 0.09, wood_h)
    c.save('banco')

    c = Canvas(130, 260, (55, 235))
    c.box(-0.1, -0.1, 0, 0.2, 0.2, 2.9, dark)
    c.box(-0.08, -0.08, 2.75, 0.75, 0.12, 0.09, dark)
    c.box(0.45, -0.12, 2.15, 0.26, 0.26, 0.42, iron)
    c.face((0.46, 0.15, 2.52), (0.24, 0, 0), (0, 0, -0.34), win, 1.0, emit=True)
    c.glow((0.58, 0.01, 2.36), 22, (1.0, 0.62, 0.22), 1.4)
    c.box(0.42, -0.15, 2.57, 0.32, 0.32, 0.06, iron)
    c.save('lampiao')

    c = Canvas(240, 260, (120, 205))
    c.cylinder(0, 0, 0, 0.8, 0.75, stone, top_tex=np.zeros((8, 8, 3)) + np.array([0.03, 0.06, 0.08]))
    c.box(-0.85, -0.08, 0.75, 0.15, 0.15, 1.35, dark)
    c.box(0.72, -0.08, 0.75, 0.15, 0.15, 1.35, dark)
    c.box(-0.8, -0.04, 1.85, 1.65, 0.08, 0.08, dark)
    c.roof(-1.1, -0.7, 2.05, 2.2, 1.4, 0.55, shingles(seed=3), dark)
    c.cylinder(0.05, 0.05, 1.25, 0.16, 0.25, wood_tex(seed=8, planks=6), bands=(0.5,), band_tex=iron)
    c.save('poco')

    # ---------------- casa (enxaimel, fundação de pedra, telhado de ripas, chaminé)
    for k, (L, D) in enumerate([(4.4, 4.0), (4.0, 4.3)]):
        c = Canvas(430, 450, (215, 240))
        wall = timber_wall(max(L, D), 2.6, seed=10 + k)
        c.box(0, 0, 0, L, D, 0.45, stone, uv_side=(3, 1))
        c.box(0.05, 0.05, 0.45, L - 0.1, D - 0.1, 2.6, wall)
        for wx in (0.6, L - 1.3):
            c.face((wx, D - 0.04, 2.25), (0.7, 0, 0), (0, 0, -0.75), win, 1.0, emit=True)
            c.glow((wx + 0.35, D, 1.85), 34, (1.0, 0.6, 0.2), 0.55)
        c.face((L / 2 - 0.45, D - 0.04, 2.1), (0.9, 0, 0), (0, 0, -1.65), dark, 0.55)
        c.face((L - 0.04, D * 0.55 + 0.35, 2.25), (0, -0.7, 0), (0, 0, -0.75), win, 1.0, emit=True)
        sh = shingles(seed=20 + k, rows=14)
        def chimney(c=c, L=L, D=D):
            c.box(0.7, D * 0.2, 2.6, 0.6, 0.6, 3.0, stone_l, uv_side=(1, 2))
        yc = -0.35 + (D + 0.7) / 2
        c.face((-0.3, -0.35, 3.05), (L + 0.6, 0, 0), (0, (D + 0.7) / 2, 2.1), sh, 0.55, (3, 2))
        chimney()
        c.face((L + 0.3, D + 0.35, 3.05), (0, -(D + 0.7), 0), (0, -(D + 0.7) / 2, 2.1), timber_wall(D, 2.0, 30 + k), 0.5, (1, 1), tri=True)
        c.face((-0.3, yc, 5.15), (L + 0.6, 0, 0), (0, (D + 0.7) / 2, -2.1), sh, 0.8, (3, 2))
        c.save('casa' if k == 0 else 'casa2')

    # ---------------- templo de pedra com torre
    c = Canvas(740, 700, (215, 380))
    L, D = 9.0, 4.4
    c.box(0, 0, 0, L, D, 0.5, stone, uv_side=(5, 1))
    c.box(0.1, 0.1, 0.5, L - 0.2, D - 0.2, 3.6, stone_l, uv_side=(4, 2))
    # janelas na escala do personagem (ART_DIRECTION: altura ≤ 0,45 × personagem), com peitoril e verga de pedra
    for wx in (1.2, 3.0, 5.8):
        c.face((wx, D - 0.09, 2.9), (0.42, 0, 0), (0, 0, -0.95), win, 1.0, emit=True)
        c.box(wx - 0.08, D - 0.12, 1.88, 0.58, 0.12, 0.08, stone)
        c.box(wx - 0.06, D - 0.12, 2.9, 0.54, 0.12, 0.12, stone)
        c.glow((wx + 0.21, D, 2.4), 26, (1.0, 0.6, 0.2), 0.45)
    c.face((4.0, D - 0.09, 2.7), (1.1, 0, 0), (0, 0, -2.2), dark, 0.5)
    slate = shingles(base=(0.16, 0.16, 0.18), seed=40, rows=16)
    yc = -0.3 + (D + 0.6) / 2
    c.face((-0.3, -0.3, 4.1), (L + 0.6, 0, 0), (0, (D + 0.6) / 2, 2.4), slate, 0.55, (5, 2))
    c.face((L + 0.3, D + 0.3, 4.1), (0, -(D + 0.6), 0), (0, -(D + 0.6) / 2, 2.4), stone_l, 0.5, (2, 1), tri=True)
    c.face((-0.3, yc, 6.5), (L + 0.6, 0, 0), (0, (D + 0.6) / 2, -2.4), slate, 0.8, (5, 2))
    tx, ty = L - 0.1, 0.9
    c.box(tx, ty, 0, 2.4, 2.4, 8.0, stone_l, uv_side=(2, 4))
    c.face((tx + 0.8, ty + 2.39, 7.3), (0.8, 0, 0), (0, 0, -1.2), np.zeros((4, 4, 3)) + 0.03, 1.0)
    top = (tx + 1.2, ty + 1.2, 10.6)
    c.face((tx - 0.15, ty + 2.55, 8.0), (2.7, 0, 0), (top[0] - tx + 0.15, top[1] - ty - 2.55, 2.6), slate, 0.82, (2, 2), tri=True)
    c.face((tx + 2.55, ty + 2.55, 8.0), (0, -2.7, 0), (top[0] - tx - 2.55, top[1] - ty - 2.55, 2.6), slate, 0.5, (2, 2), tri=True)
    c.save('templo')

    # ---------------- árvores
    tree('arvore', (0.17, 0.24, 0.11), 11)
    tree('arvore_outono', (0.42, 0.21, 0.08), 12)
    tree('arvore_escura', (0.13, 0.17, 0.1), 13)
    tree('pinheiro', (0.1, 0.17, 0.1), 14, pine=True)

    # ---------------- carroça
    c = Canvas(300, 220, (110, 150))
    wt = wheel_tex()
    for wx in (0.25, 1.35):
        c.face((wx, -0.05, 1.0), (0.9, 0, 0), (0, 0, -0.9), wt, 0.45, disk=True)
    c.box(0, 0, 0.55, 2.2, 1.1, 0.12, wood_h)
    c.box(0, 0, 0.67, 2.2, 0.08, 0.45, wood2)
    c.box(0, 0.08, 0.67, 0.08, 0.95, 0.45, wood2)
    c.box(2.12, 0.08, 0.67, 0.08, 0.95, 0.45, wood2)
    c.box(0.3, 0.2, 0.67, 0.6, 0.6, 0.5, wood)
    c.cylinder(1.4, 0.55, 0.67, 0.3, 0.7, wood_tex(seed=6, planks=10), bulge=0.1, bands=(0.2, 0.8), band_tex=iron)
    c.box(0, 1.03, 0.67, 2.2, 0.08, 0.45, wood2)
    for wx in (0.25, 1.35):
        c.face((wx, 1.15, 1.0), (0.9, 0, 0), (0, 0, -0.9), wt, 0.85, disk=True)
    c.box(2.2, 0.35, 0.6, 1.3, 0.07, 0.07, dark)
    c.box(2.2, 0.75, 0.6, 1.3, 0.07, 0.07, dark)
    c.save('carroca')

    # ---------------- fogueira (o fogo vem das partículas no jogo)
    c = Canvas(160, 110, (80, 60))
    c.blob(0, 0, 0, 0.5, np.zeros((8, 8, 3)) + 0.06, ry=0.45, rough=0.1)
    for i in range(9):
        a = i / 9 * 2 * np.pi
        c.blob(np.cos(a) * 0.62, np.sin(a) * 0.62, 0.08, 0.17, stone_l, ry=0.8, rough=0.15)
    c.box(-0.45, -0.07, 0.05, 0.9, 0.14, 0.14, dark)
    c.box(-0.07, -0.45, 0.12, 0.14, 0.9, 0.14, wood2)
    c.glow((0, 0, 0.15), 28, (1.0, 0.45, 0.1), 0.9)
    c.save('fogueira')

    # ---------------- tenda de feira
    c = Canvas(260, 260, (90, 190))
    canvas = noise_tex(128, 128, (0.45, 0.36, 0.26), 0.2, 6, 50, 0.1)
    yy = np.mgrid[0:128, 0:128][1]
    canvas[(yy // 16) % 2 == 0] *= np.array([0.75, 0.5, 0.4])
    for px, py in ((0, 0), (2.2, 0), (0, 1.6), (2.2, 1.6)):
        c.box(px, py, 0, 0.12, 0.12, 2.3 if py == 0 else 1.9, dark)
    c.box(0.1, 0.5, 0, 2.0, 0.9, 0.85, wood_h)
    for i in range(5):
        c.blob(0.3 + i * 0.38, 0.9, 0.95, 0.13, noise_tex(32, 32, (0.5, 0.32, 0.12) if i % 2 else (0.35, 0.4, 0.15), 0.3, 3, 60 + i), ry=0.8)
    c.box(1.2, 0.6, 0.85, 0.5, 0.4, 0.3, wood)
    c.face((-0.25, -0.25, 2.45), (2.7, 0, 0), (0, 2.1, -0.6), canvas, 0.85, (1, 1))
    c.face((-0.25, 1.85, 1.85), (2.7, 0, 0), (0, 0, -0.35), canvas, 0.7, (2, 1))
    c.save('tenda')

    # ---------------- pedras
    for k in range(2):
        c = Canvas(200, 160, (100, 110))
        r = np.random.default_rng(70 + k)
        for i in range(3 + k):
            c.blob(r.random() * 0.8 - 0.4, r.random() * 0.8 - 0.4, 0.25 + r.random() * 0.2, 0.45 + r.random() * 0.35, stone, ry=0.7, rough=0.25)
        c.save('pedra' if k == 0 else 'pedra2')

    habitat_pieces(stone, stone_l, dark, wood_h, iron)

    import json
    json.dump(ANCHORS, open(os.path.join(OUT, 'ancoras.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
