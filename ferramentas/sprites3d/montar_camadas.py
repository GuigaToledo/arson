# Junta os quadros de uma camada de equipamento em folhas por animação (mesmo formato de montar.py),
# separando a parte principal (<anim>.png) e o detalhe (<anim>_ac.png) pela passagem "acc".
# uso: blender -b --python montar_camadas.py -- <pasta_quadros> <pasta_saida>
import bpy, sys, os, json
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = args[0], args[1]
DIRS = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
os.makedirs(DST, exist_ok=True)
meta = json.load(open(os.path.join(SRC, "meta.json")))
S = meta["tamanho"]


def ler(path, canais=4):
    if not os.path.exists(path):
        return None
    im = bpy.data.images.load(path)
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]
    bpy.data.images.remove(im)
    return px


def salvar(arr, nome):
    h, w = arr.shape[:2]
    im = bpy.data.images.new(nome, w, h, alpha=True)
    im.pixels = arr[::-1].ravel()
    im.filepath_raw = os.path.join(DST, nome + ".png")
    im.file_format = "PNG"
    im.save()


saida = {"tamanho": S, "pe_quadro": meta["pe"], "anims": {}, "acento": False}
# renders feitos em partes (ex.: magia andando depois): junta com o que já existe na pasta
_ant = os.path.join(DST, "sprites.json")
if os.path.exists(_ant):
    _v = json.load(open(_ant))
    saida["anims"].update(_v.get("anims", {}))
    saida["acento"] = bool(_v.get("acento", False))
for anim, n in meta["anims"].items():
    fr = {}
    x0, y0, x1, y1 = S, S, 0, 0
    for d in DIRS:
        for k in range(n):
            base = os.path.join(SRC, "%s_%s_%02d" % (anim, d, k))
            px = ler(base + ".png")
            ac = ler(base + "_acc.png")
            fr[(d, k)] = (px, ac)
            ys, xs = np.nonzero(px[:, :, 3] > 0.02)
            if len(xs):
                x0, x1 = min(x0, xs.min()), max(x1, xs.max())
                y0, y1 = min(y0, ys.min()), max(y1, ys.max())
    if x1 < x0:
        continue  # nada visível nesta animação
    x0, y0 = max(0, x0 - 2), max(0, y0 - 2)
    x1, y1 = min(S - 1, x1 + 2), min(S - 1, y1 + 2)
    fw, fh = int(x1 - x0 + 1), int(y1 - y0 + 1)
    A = np.zeros((fh * len(DIRS), fw * n, 4), dtype=np.float32)
    B = np.zeros_like(A)
    tem_ac = False
    for di, d in enumerate(DIRS):
        for k in range(n):
            px, ac = fr[(d, k)]
            p = px[y0:y1 + 1, x0:x1 + 1]
            al = p[:, :, 3]
            if ac is not None:
                kk = np.clip(ac[y0:y1 + 1, x0:x1 + 1, 0] / np.maximum(al, 1e-3), 0.0, 1.0)
            else:
                kk = np.zeros_like(al)
            m = p.copy()
            m[:, :, 3] = al * (1.0 - kk)
            a = p.copy()
            a[:, :, 3] = al * kk
            if (a[:, :, 3] > 0.02).any():
                tem_ac = True
            A[di * fh:(di + 1) * fh, k * fw:(k + 1) * fw] = m
            B[di * fh:(di + 1) * fh, k * fw:(k + 1) * fw] = a
    salvar(A, anim)
    if tem_ac:
        salvar(B, anim + "_ac")
        saida["acento"] = True
    saida["anims"][anim] = {"n": n, "quadro": [fw, fh], "pe": [meta["pe"][0] - int(x0), meta["pe"][1] - int(y0)], "ac": tem_ac}
json.dump(saida, open(os.path.join(DST, "sprites.json"), "w"))
print("MONTADO", saida)
