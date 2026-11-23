# Folha de conferência: junta quadros <anim>_<dir>_<k>.png numa grade (linhas = direções) com fundo cinza.
# uso: blender -b --python folha.py -- <pasta> <anim> <dirs separadas por vírgula> <saida.png>
import bpy, sys, os, glob
import numpy as np

a = sys.argv[sys.argv.index("--") + 1:]
SRC, ANIM, DIRS, OUT = a[0], a[1], a[2].split(","), a[3]
linhas = []
for d in DIRS:
    fs = sorted(glob.glob(os.path.join(SRC, "%s_%s_*.png" % (ANIM, d))))
    row = []
    for f in fs:
        im = bpy.data.images.load(f)
        w, h = im.size
        px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
        bpy.data.images.remove(im)
        bg = np.array([0.32, 0.34, 0.3])
        rgb = px[:, :, :3] * px[:, :, 3:] + bg * (1 - px[:, :, 3:])
        row.append(np.dstack([rgb, np.ones((h, w))]))
    linhas.append(np.hstack(row))
g = np.vstack(linhas[::-1])
im = bpy.data.images.new("f", g.shape[1], g.shape[0], alpha=True)
im.pixels = g.ravel()
im.filepath_raw = OUT
im.file_format = "PNG"
im.save()
print("FOLHA", g.shape)
