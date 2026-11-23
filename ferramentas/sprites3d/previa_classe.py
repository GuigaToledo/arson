# Prévia: corpo base + camadas dos itens (pintadas com as cores de cada item), como o jogo compõe.
# uso: blender -b --python previa_classe.py -- <saida.png> <anim> <dirs> <id1,id2,...> [...outra classe]
import bpy, sys, os, json
import numpy as np

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import itens3d

a = sys.argv[sys.argv.index("--") + 1:]
OUT, ANIM, DIRS_V = a[0], a[1], a[2].split(",")
CLASSES = [x.split(",") for x in a[3:]]
G = r"E:\Claude Jobs\arson\godot\assets"
DIRS = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
ITENS = itens3d.ler_itens()
ORDEM = [6, 4, 5, 1, 3, 2, 9, 0, 7, 8]  # capa, pernas, botas, peito, luvas, ombros, colar, cabeça, armas


def folha(pasta, nome):
    p = os.path.join(pasta, nome + ".png")
    if not os.path.exists(p):
        return None
    im = bpy.data.images.load(p)
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]
    bpy.data.images.remove(im)
    return px


def quadro(pasta, anim, d, k, suf=""):
    js = json.load(open(os.path.join(pasta, "sprites.json")))
    info = js["anims"].get(anim)
    if info is None:
        return None
    f = folha(pasta, anim + suf)
    if f is None:
        return None
    fw, fh = info["quadro"]
    di = DIRS.index(d)
    k = k % info["n"]
    cut = f[di * fh:(di + 1) * fh, k * fw:(k + 1) * fw]
    S = js.get("tamanho", 256)
    pq = js.get("pe_quadro", [128, 200.5])
    out = np.zeros((S, S, 4), dtype=np.float32)
    ox, oy = int(round(pq[0] - info["pe"][0])), int(round(pq[1] - info["pe"][1]))
    out[oy:oy + fh, ox:ox + fw] = cut
    return out


def sobre(dst, src, tint=(1, 1, 1)):
    a = src[:, :, 3:4]
    rgb = np.clip(src[:, :, :3] * np.array(tint), 0, 1)
    dst[:, :, :3] = rgb * a + dst[:, :, :3] * (1 - a)
    dst[:, :, 3:4] = a + dst[:, :, 3:4] * (1 - a)


linhas = []
for ids in CLASSES:
    for d in DIRS_V:
        row = []
        for k in range(8):
            fr = np.zeros((256, 256, 4), dtype=np.float32)
            fr[:, :, :3] = (0.32, 0.34, 0.3)
            fr[:, :, 3] = 1
            b = quadro(os.path.join(G, "personagens", "base"), ANIM, d, k)
            if b is not None:
                sobre(fr, b)
            its = sorted([i for i in ids if i in ITENS], key=lambda i: ORDEM.index(ITENS[i]["slot"]))
            for iid in its:
                it = ITENS[iid]
                pasta = os.path.join(G, "equip", it["estilo"])
                if not os.path.exists(os.path.join(pasta, "sprites.json")):
                    continue
                m = quadro(pasta, ANIM, d, k)
                if m is not None:
                    sobre(fr, m, tuple(c / 0.8 for c in it["cor"][:3]))
                ac = quadro(pasta, ANIM, d, k, "_ac")
                if ac is not None:
                    sobre(fr, ac, tuple(c / 0.85 for c in it["acento"][:3]))
            row.append(fr)
        linhas.append(np.hstack(row))
g = np.vstack(linhas)[::-1]
im = bpy.data.images.new("p", g.shape[1], g.shape[0], alpha=True)
im.pixels = g.ravel()
im.filepath_raw = OUT
im.file_format = "PNG"
im.save()
print("PREVIA", g.shape)
