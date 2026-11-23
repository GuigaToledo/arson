# Junta ícones (png) numa grade com fundo escuro, para conferir.
# uso: blender -b --python folha_icones.py -- <pasta> <saida.png> [colunas]
import bpy, sys, os, glob
import numpy as np
a = sys.argv[sys.argv.index("--") + 1:]
fs = sorted(glob.glob(os.path.join(a[0], "*.png")))
cols = int(a[2]) if len(a) > 2 else 8
ims = []
for f in fs:
    im = bpy.data.images.load(f)
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(im)
    bg = np.array([0.06, 0.05, 0.045])
    rgb = px[:, :, :3] * px[:, :, 3:] + bg * (1 - px[:, :, 3:])
    rgb[:2, :] = 0.4; rgb[-2:, :] = 0.4; rgb[:, :2] = 0.4; rgb[:, -2:] = 0.4
    ims.append(np.dstack([rgb, np.ones((h, w))]))
h, w = ims[0].shape[:2]
rows = (len(ims) + cols - 1) // cols
g = np.zeros((rows * h, cols * w, 4), dtype=np.float32); g[:, :, 3] = 1
for i, im in enumerate(ims):
    r, c = divmod(i, cols)
    r = rows - 1 - r
    g[r * h:(r + 1) * h, c * w:(c + 1) * w] = im
out = bpy.data.images.new("f", g.shape[1], g.shape[0], alpha=True)
out.pixels = g.ravel(); out.filepath_raw = a[1]; out.file_format = "PNG"; out.save()
print("FOLHA", len(ims))
