import numpy as np, json, os, sys, math
from numba import njit
from PIL import Image

c = np.load('cena.npz'); TP, TN, TC, TS = c['TP'], c['TN'], c['TC'], c['TS']
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


def render_dir(model_yaw, breath, size=1024, pxu=6.9, foot=(0.5, 0.7832), el_deg=30):
    tp = TP.copy()
    up = tp[..., 2] > 50
    tp[..., 2] = np.where(up, 50 + (tp[..., 2] - 50) * breath, tp[..., 2])
    feet = TP.reshape(-1, 3); fc = feet[feet[:, 2] < 2].mean(0); fc[2] = 0
    tp -= fc
    yaw = model_yaw; el = math.radians(el_deg)
    Rz = np.array([[math.cos(yaw), -math.sin(yaw), 0], [math.sin(yaw), math.cos(yaw), 0], [0, 0, 1]])
    Rx = np.array([[1, 0, 0], [0, math.cos(el), -math.sin(el)], [0, math.sin(el), math.cos(el)]])
    R = Rx @ Rz
    v = tp @ R.T; n = TN @ R.T
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
    NQ = 4
    frames = {}
    for di, dname in enumerate(DIRS):
        a = di * math.pi / 4.0
        gx, gy = math.cos(a), math.sin(a) * 2.0
        yaw = math.atan2(-gy, gx) + math.pi / 2.0
        for q in range(NQ):
            br = 1 + 0.008 * math.sin(2 * math.pi * q / NQ)
            frames[(di, q)] = render_dir(yaw, br)
        print(dname, flush=True)
    # recorte comum
    al = np.stack([f[..., 3] for f in frames.values()]).max(0)
    ys = np.where(al.max(1) > 0)[0]; xs = np.where(al.max(0) > 0)[0]
    y0, y1, x0, x1 = ys.min() - 2, ys.max() + 3, xs.min() - 2, xs.max() + 3
    fw, fh = x1 - x0, y1 - y0
    sheet = np.zeros((fh * len(DIRS), fw * NQ, 4), np.uint8)
    for (di, q), f in frames.items():
        sheet[di * fh:(di + 1) * fh, q * fw:(q + 1) * fw] = f[y0:y1, x0:x1]
    out = sys.argv[1] if len(sys.argv) > 1 else 'saida'
    os.makedirs(out, exist_ok=True)
    Image.fromarray(sheet).save(os.path.join(out, 'idle.png'), optimize=True)
    pe = [round(128.0 - x0, 1), round(200.5 - y0, 1)]
    meta = {"tamanho": 256, "pe_quadro": [128.0, 200.5],
            "anims": {"idle": {"n": NQ, "quadro": [int(fw), int(fh)], "pe": pe, "ac": False}}, "acento": False}
    json.dump(meta, open(os.path.join(out, 'sprites.json'), 'w'))
    print(meta)
