# Junta os quadros renderizados em folhas (atlas) por animação, recortando o espaço vazio.
# uso: blender -b --python ferramentas/sprites3d/montar.py -- <pasta_quadros> <pasta_saida>
# Saída: <anim>.png (8 direções x N quadros, uma linha por direção) + sprites.json (tamanho, pé, colunas).
import bpy, sys, os, json, glob
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = args[0], args[1]
DIRS = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
os.makedirs(DST, exist_ok=True)
meta = json.load(open(os.path.join(SRC, "meta.json")))
S = meta["tamanho"]


def ler(path):
    im = bpy.data.images.load(path)
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]  # de cima para baixo
    bpy.data.images.remove(im)
    return px


# recorte por animação (cada uma tem seu tamanho; a morte é larga, andar é estreito)
saida = {"anims": {}}
for anim, n in meta["anims"].items():
    fr = {}
    x0, y0, x1, y1 = S, S, 0, 0
    for d in DIRS:
        for k in range(n):
            px = ler(os.path.join(SRC, "%s_%s_%02d.png" % (anim, d, k)))
            fr[(d, k)] = px
            ys, xs = np.nonzero(px[:, :, 3] > 0.02)
            if len(xs):
                x0, x1 = min(x0, xs.min()), max(x1, xs.max())
                y0, y1 = min(y0, ys.min()), max(y1, ys.max())
    x0, y0 = max(0, x0 - 2), max(0, y0 - 2)
    x1, y1 = min(S - 1, x1 + 2), min(S - 1, y1 + 2)
    fw, fh = int(x1 - x0 + 1), int(y1 - y0 + 1)
    atlas = np.zeros((fh * len(DIRS), fw * n, 4), dtype=np.float32)
    for di, d in enumerate(DIRS):
        for k in range(n):
            atlas[di * fh:(di + 1) * fh, k * fw:(k + 1) * fw] = fr[(d, k)][y0:y1 + 1, x0:x1 + 1]
    h, w = atlas.shape[:2]
    im = bpy.data.images.new(anim, w, h, alpha=True)
    im.pixels = atlas[::-1].ravel()
    im.filepath_raw = os.path.join(DST, anim + ".png")
    im.file_format = "PNG"
    im.save()
    saida["anims"][anim] = {"n": n, "quadro": [fw, fh], "pe": [meta["pe"][0] - int(x0), meta["pe"][1] - int(y0)]}
json.dump(saida, open(os.path.join(DST, "sprites.json"), "w"))
print("MONTADO", saida)
