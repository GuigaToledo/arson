"""Rasterizador simples (z-buffer) para STL: gera imagem de profundidade, normais e máscara."""
import numpy as np, struct, sys
from numba import njit
from PIL import Image


def load_stl(path):
    b = open(path, 'rb').read()
    n = struct.unpack('<I', b[80:84])[0]
    dt = np.dtype([('n', '<f4', 3), ('v', '<f4', (3, 3)), ('a', '<u2')])
    d = np.frombuffer(b, dt, n, 84)
    return d['v'].astype(np.float64)


def vertex_normals(tris):
    # normais suavizadas por vértice (agrupa vértices iguais)
    v = tris.reshape(-1, 3)
    key = np.round(v, 4)
    uniq, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.ravel()
    fn = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    acc = np.zeros((len(uniq), 3))
    for k in range(3):
        np.add.at(acc, inv[k::3], fn)
    acc /= np.linalg.norm(acc, axis=1, keepdims=True) + 1e-12
    return acc[inv].reshape(-1, 3, 3)


@njit(cache=True)
def raster(P, N, W, H, zbuf, nbuf, posbuf, W3):
    for t in range(P.shape[0]):
        x0, y0, z0 = P[t, 0]; x1, y1, z1 = P[t, 1]; x2, y2, z2 = P[t, 2]
        minx = max(int(np.floor(min(x0, x1, x2))), 0); maxx = min(int(np.ceil(max(x0, x1, x2))), W - 1)
        miny = max(int(np.floor(min(y0, y1, y2))), 0); maxy = min(int(np.ceil(max(y0, y1, y2))), H - 1)
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-12:
            continue
        for y in range(miny, maxy + 1):
            for x in range(minx, maxx + 1):
                px = x + 0.5; py = y + 0.5
                a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / den
                b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / den
                c = 1 - a - b
                if a < 0 or b < 0 or c < 0:
                    continue
                z = a * z0 + b * z1 + c * z2
                if z > zbuf[y, x]:
                    zbuf[y, x] = z
                    for k in range(3):
                        nbuf[y, x, k] = a * N[t, 0, k] + b * N[t, 1, k] + c * N[t, 2, k]
                        posbuf[y, x, k] = a * W3[t, 0, k] + b * W3[t, 1, k] + c * W3[t, 2, k]


def render(tris, normals, yaw_deg, elev_deg, size, scale, center):
    """yaw: rotação em torno do eixo vertical (Z do STL). elev: inclinação da câmera."""
    yaw = np.radians(yaw_deg); el = np.radians(elev_deg)
    Rz = np.array([[np.cos(yaw), -np.sin(yaw), 0], [np.sin(yaw), np.cos(yaw), 0], [0, 0, 1]])
    # câmera olhando de -Y para +Y, inclinada de cima
    Rx = np.array([[1, 0, 0], [0, np.cos(el), -np.sin(el)], [0, np.sin(el), np.cos(el)]])
    R = Rx @ Rz
    v = (tris - center) @ R.T
    n = normals @ R.T
    W, H = size
    # tela: x -> direita, z (cima) -> -y da imagem, profundidade = -y (mais perto = maior)
    P = np.empty_like(v)
    P[..., 0] = v[..., 0] * scale + W / 2
    P[..., 1] = -v[..., 2] * scale + H * 0.92
    P[..., 2] = -v[..., 1]
    zbuf = np.full((H, W), -1e18); nbuf = np.zeros((H, W, 3)); posbuf = np.zeros((H, W, 3))
    raster(P, n, W, H, zbuf, nbuf, posbuf, tris - center)
    nb = nbuf.copy()
    nb[..., 1], nb[..., 2] = -nbuf[..., 2], -nbuf[..., 1]  # para espaço da tela (x dir, y baixo, z p/ câmera)
    nb /= np.linalg.norm(nb, axis=2, keepdims=True) + 1e-12
    mask = zbuf > -1e17
    return mask, nb, zbuf, posbuf


if __name__ == '__main__':
    tris = load_stl(sys.argv[1])
    print('bbox', tris.reshape(-1, 3).min(0), tris.reshape(-1, 3).max(0))
