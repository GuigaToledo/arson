# Recorta os objetos renderizados (estatuas.py) para o mapa e anota o ponto de apoio de cada um.
# uso: blender -b --factory-startup --python objetos_cidade.py -- <pasta_quadros> <pasta_objetos>
import bpy, sys, os, json, glob
import numpy as np

SRC, DST = sys.argv[sys.argv.index("--") + 1:][:2]
anc_path = os.path.join(DST, "ancoras.json")
anc = json.load(open(anc_path, encoding="utf-8"))
for d in sorted(glob.glob(os.path.join(SRC, "npc_*"))):
    nome = os.path.basename(d)
    meta = json.load(open(os.path.join(d, "meta.json")))
    im = bpy.data.images.load(os.path.join(d, "idle_S_00.png"))
    w, h = im.size
    px = np.array(im.pixels[:], np.float32).reshape(h, w, 4)[::-1]
    ys, xs = np.nonzero(px[:, :, 3] > 0.02)
    x0, x1, y0, y1 = max(0, xs.min() - 2), min(w, xs.max() + 3), max(0, ys.min() - 2), min(h, ys.max() + 3)
    corte = px[y0:y1, x0:x1]
    o = bpy.data.images.new(nome, int(x1 - x0), int(y1 - y0), alpha=True)
    o.pixels = corte[::-1].ravel()
    o.filepath_raw = os.path.join(DST, nome + ".png")
    o.file_format = "PNG"
    o.save()
    anc[nome] = [round(meta["pe"][0] - float(x0), 1), round(meta["pe"][1] - float(y0), 1)]
    print("OBJETO", nome, corte.shape[1], corte.shape[0], anc[nome])
json.dump(anc, open(anc_path, "w", encoding="utf-8"), indent=1)
