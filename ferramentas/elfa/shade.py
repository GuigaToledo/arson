import numpy as np, json, os, sys, math
from numba import njit
from PIL import Image

c = np.load('cena.npz'); TP, TN, TC, TS, ARMC, LADO = c['TP'], c['TN'], c['TC'], c['TS'], c['ARMC'], c['LADO']
TN = TN / (np.linalg.norm(TN, axis=2, keepdims=True) + 1e-12)


@njit(cache=True)
def raster_attr(P, A, W, H, zbuf, abuf):
    na = A.shape[2]
    for t in range(P.shape[0]):
        x0, y0, z0 = P[t, 0]; x1, y1, z1 = P[t, 1]; x2, y2, z2 = P[t, 2]
        minx = max(int(np.floor(min(x0, x1, x2))), 0); maxx = min(int(np.ceil(max(x0, x1, x2))), W - 1)
        miny = max(int(np.floor(min(y0, y1, y2))), 0); maxy = min(int(np.ceil(max(y0, y1, y2))), H - 1)
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-12:
            continue
        for yy in range(miny, maxy + 1):
            for xx in range(minx, maxx + 1):
                px = xx + 0.5; py = yy + 0.5
                a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / den
                b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / den
                cc = 1 - a - b
                if a < 0 or b < 0 or cc < 0:
                    continue
                zv = a * z0 + b * z1 + cc * z2
                if zv > zbuf[yy, xx]:
                    zbuf[yy, xx] = zv
                    for k in range(na):
                        abuf[yy, xx, k] = a * A[t, 0, k] + b * A[t, 1, k] + cc * A[t, 2, k]


@njit(cache=True)
def depth_only(P, W, H, zbuf):
    for t in range(P.shape[0]):
        x0, y0, z0 = P[t, 0]; x1, y1, z1 = P[t, 1]; x2, y2, z2 = P[t, 2]
        minx = max(int(np.floor(min(x0, x1, x2))), 0); maxx = min(int(np.ceil(max(x0, x1, x2))), W - 1)
        miny = max(int(np.floor(min(y0, y1, y2))), 0); maxy = min(int(np.ceil(max(y0, y1, y2))), H - 1)
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-12:
            continue
        for yy in range(miny, maxy + 1):
            for xx in range(minx, maxx + 1):
                px = xx + 0.5; py = yy + 0.5
                a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / den
                b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / den
                cc = 1 - a - b
                if a < 0 or b < 0 or cc < 0:
                    continue
                zv = a * z0 + b * z1 + cc * z2
                if zv > zbuf[yy, xx]:
                    zbuf[yy, xx] = zv


def basis(dvec):
    """Base ortonormal com o terceiro eixo = direção de visão (para a luz/AO)."""
    w = dvec / np.linalg.norm(dvec)
    a = np.array([0, 0, 1.0]) if abs(w[2]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(a, w); u /= np.linalg.norm(u); v = np.cross(w, u)
    return np.stack([u, v, w])


def ambient_occlusion(points, normals, ndir=72, res=640):
    lo = TP.reshape(-1, 3).min(0) - 2; hi = TP.reshape(-1, 3).max(0) + 2
    ctr = (lo + hi) / 2; rad = np.linalg.norm(hi - lo) / 2
    vis = np.zeros(len(points)); wsum = np.zeros(len(points))
    gold = (1 + 5 ** 0.5) / 2
    for i in range(ndir):
        zc = 1 - 2 * (i + 0.5) / ndir
        r = math.sqrt(1 - zc * zc); th = 2 * math.pi * i / gold
        dv = np.array([r * math.cos(th), r * math.sin(th), zc])   # direção de onde vem a luz do céu
        B = basis(dv)
        q = (TP - ctr) @ B.T
        Pq = np.empty_like(q)
        s = res / (2 * rad)
        Pq[..., 0] = q[..., 0] * s + res / 2; Pq[..., 1] = q[..., 1] * s + res / 2; Pq[..., 2] = q[..., 2]
        zb = np.full((res, res), -1e18); depth_only(Pq, res, res, zb)
        pp = (points - ctr) @ B.T
        ix = np.clip((pp[:, 0] * s + res / 2).astype(int), 0, res - 1); iy = np.clip((pp[:, 1] * s + res / 2).astype(int), 0, res - 1)
        visible = pp[:, 2] >= zb[iy, ix] - 0.35
        w = np.clip(normals @ dv, 0, None)
        # chão: luz que vem de baixo é bloqueada
        w = w * (1.0 if dv[2] > -0.05 else 0.25)
        vis += w * visible; wsum += w
    return vis / np.maximum(wsum, 1e-6)


if not os.path.exists('ao.npy'):
    ao = ambient_occlusion(TP.reshape(-1, 3), TN.reshape(-1, 3)).reshape(-1, 3)
    np.save('ao.npy', ao)
AO = np.load('ao.npy')


def blender_sun(rx, ry, rz):
    rx, ry, rz = map(math.radians, (rx, ry, rz))
    Rx = np.array([[1, 0, 0], [0, math.cos(rx), -math.sin(rx)], [0, math.sin(rx), math.cos(rx)]])
    Ry = np.array([[math.cos(ry), 0, math.sin(ry)], [0, 1, 0], [-math.sin(ry), 0, math.cos(ry)]])
    Rz = np.array([[math.cos(rz), -math.sin(rz), 0], [math.sin(rz), math.cos(rz), 0], [0, 0, 1]])
    dvec = Rz @ Ry @ Rx @ np.array([0, 0, -1.0])
    return -dvec   # para a luz


LUZES = [(blender_sun(50, 0, -55), np.array([1.0, 0.86, 0.68]) * 1.9),
         (blender_sun(60, 0, 150), np.array([0.55, 0.65, 1.0]) * 1.5),
         (blender_sun(70, 0, 40), np.array([0.7, 0.6, 0.55]) * 0.35)]


def pernas(tp, tn, fase, amp=math.radians(24)):
    """Caminhada sem esqueleto: cada perna gira em volta do quadril (eixo lateral), com peso que
    vai de 0 na virilha a 1 na coxa; braços ficam parados. O corpo sobe e desce um pouco."""
    tp = tp.copy(); tn = tn.copy()
    zz = tp[..., 2]
    w = np.clip((46.0 - zz) / 8.0, 0, 1); w = w * w * (3 - 2 * w)
    w = np.where(ARMC, 0.0, w)
    lado = LADO
    ang = amp * math.sin(fase) * lado * w
    py, pz = -3.0, 45.0
    dy = tp[..., 1] - py; dz = tp[..., 2] - pz
    ca, sa = np.cos(ang), np.sin(ang)
    tp[..., 1] = py + dy * ca + dz * sa
    tp[..., 2] = pz - dy * sa + dz * ca
    ny, nz = tn[..., 1].copy(), tn[..., 2].copy()
    tn[..., 1] = ny * ca + nz * sa; tn[..., 2] = -ny * sa + nz * ca
    # pé mais baixo encosta no chão; sobe e desce no passo
    tp[..., 2] += -tp[..., 2].min() + 0.6 * abs(math.cos(fase))
    return tp, tn


def render_dir(model_yaw, breath, size=1024, pxu=7.39, foot=(0.5, 0.7832), el_deg=30, fase=None):
    tp = TP.copy(); TNl = TN
    if fase is not None:
        tp, TNl = pernas(tp, TN, fase)
    up = tp[..., 2] > 50
    tp[..., 2] = np.where(up, 50 + (tp[..., 2] - 50) * breath, tp[..., 2])
    feet = TP.reshape(-1, 3); fc = feet[feet[:, 2] < 2].mean(0); fc[2] = 0
    tp -= fc
    yaw = model_yaw; el = math.radians(el_deg)
    Rz = np.array([[math.cos(yaw), -math.sin(yaw), 0], [math.sin(yaw), math.cos(yaw), 0], [0, 0, 1]])
    Rx = np.array([[1, 0, 0], [0, math.cos(el), -math.sin(el)], [0, math.sin(el), math.cos(el)]])
    R = Rx @ Rz
    v = tp @ R.T; n = TNl @ R.T
    P = np.empty_like(v)
    P[..., 0] = v[..., 0] * pxu + size * foot[0]
    P[..., 1] = -v[..., 2] * pxu + size * foot[1]
    P[..., 2] = -v[..., 1]
    A = np.concatenate([n, TC, TS[..., :1], AO[..., None]], axis=2)
    zb = np.full((size, size), -1e18); ab = np.zeros((size, size, A.shape[2]))
    raster_attr(P, A, size, size, zb, ab)
    mask = zb > -1e17
    nn = ab[..., 0:3]; nn /= np.linalg.norm(nn, axis=2, keepdims=True) + 1e-12
    alb = np.clip(ab[..., 3:6], 0, 1) ** 2.2; sp_ = ab[..., 6]; ao = np.clip(ab[..., 7], 0, 1)
    V = np.array([0, -1.0, 0])
    lin = alb * (np.array([0.55, 0.52, 0.5]) * 0.45) * (0.35 + 0.65 * ao)[..., None]
    for Lw, Lc in LUZES:
        Lc_ = Rx @ Lw
        ndl = np.clip(nn @ Lc_, 0, None)
        Hh = (Lc_ + V); Hh /= np.linalg.norm(Hh)
        spec = np.clip(nn @ Hh, 0, None) ** 28 * sp_ * 0.35
        lin += (alb * ndl[..., None] + spec[..., None]) * Lc * (0.55 + 0.45 * ao)[..., None]
    # tom tipo filme
    tm = 1 - np.exp(-lin * 1.35)
    rgb = np.clip(tm, 0, 1) ** (1 / 2.2)
    img = np.zeros((size, size, 4)); img[..., :3] = rgb * mask[..., None]; img[..., 3] = mask
    # reduz 4x com alfa pré-multiplicado
    k = 4; s2 = size // k
    img = img.reshape(s2, k, s2, k, 4).mean((1, 3))
    out = np.zeros_like(img); a = img[..., 3:4]
    out[..., :3] = np.where(a > 0, img[..., :3] / np.maximum(a, 1e-6), 0); out[..., 3] = a[..., 0]
    return (np.clip(out, 0, 1) * 255).astype(np.uint8)


if __name__ == '__main__':
    DIRS = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
    out = sys.argv[1] if len(sys.argv) > 1 else 'saida'
    os.makedirs(out, exist_ok=True)
    meta = {"tamanho": 256, "pe_quadro": [128.0, 200.5], "anims": {}, "acento": False}
    for anim, NQ in (("idle", 4), ("walk", 8)):
        frames = {}
        for di, dname in enumerate(DIRS):
            a = di * math.pi / 4.0
            gx, gy = math.cos(a), math.sin(a) * 2.0
            yaw = math.atan2(-gy, gx) + math.pi / 2.0
            for q in range(NQ):
                if anim == "idle":
                    frames[(di, q)] = render_dir(yaw, 1 + 0.008 * math.sin(2 * math.pi * q / NQ))
                else:
                    frames[(di, q)] = render_dir(yaw, 1.0, fase=2 * math.pi * q / NQ)
        al = np.stack([f[..., 3] for f in frames.values()]).max(0)
        ys = np.where(al.max(1) > 0)[0]; xs = np.where(al.max(0) > 0)[0]
        y0, y1, x0, x1 = ys.min() - 2, ys.max() + 3, xs.min() - 2, xs.max() + 3
        fw, fh = int(x1 - x0), int(y1 - y0)
        sheet = np.zeros((fh * len(DIRS), fw * NQ, 4), np.uint8)
        for (di, q), f in frames.items():
            sheet[di * fh:(di + 1) * fh, q * fw:(q + 1) * fw] = f[y0:y1, x0:x1]
        Image.fromarray(sheet).save(os.path.join(out, anim + '.png'), optimize=True)
        meta["anims"][anim] = {"n": NQ, "quadro": [fw, fh], "pe": [float(128.0 - x0), float(200.5 - y0)], "ac": False}
        print(anim, flush=True)
    json.dump(meta, open(os.path.join(out, 'sprites.json'), 'w'))
    print(meta)
