# Prepara o dragão: importa o STL, reduz polígonos, normaliza (altura 2, pés em z=0, olhando -Y)
# e salva um .blend + vistas de cima/trás para análise.
# uso: blender -b --python dragao_prep.py -- <arquivo.stl> <saida.blend> <prefixo_vistas>
import bpy, sys, math
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.stl_import(filepath=args[0])
o = bpy.context.selected_objects[0]
o.name = "Dragao"
bpy.context.view_layer.objects.active = o
m = o.modifiers.new("dec", "DECIMATE")
m.ratio = 0.03
bpy.ops.object.modifier_apply(modifier="dec")
me = o.data
co = np.zeros(len(me.vertices) * 3)
me.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
mn, mx = co.min(0), co.max(0)
s = 2.0 / (mx[2] - mn[2])
co = (co - np.array([(mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, mn[2]])) * s
me.vertices.foreach_set("co", co.ravel())
me.update()
print("TRIS", len(me.polygons), "VERTS", len(me.vertices))
print("BBOX", co.min(0).round(3), co.max(0).round(3))
# ocupação: fatias em z, largura em x e extensão em y
for z0 in np.arange(0, 2.0, 0.2):
    sel = co[(co[:, 2] >= z0) & (co[:, 2] < z0 + 0.2)]
    if len(sel):
        print("Z %.1f n=%5d x[%.2f,%.2f] y[%.2f,%.2f]" % (z0, len(sel), sel[:, 0].min(), sel[:, 0].max(), sel[:, 1].min(), sel[:, 1].max()))
for y0 in np.arange(-1.2, 1.2, 0.2):
    sel = co[(co[:, 1] >= y0) & (co[:, 1] < y0 + 0.2)]
    if len(sel):
        print("Y %.1f n=%5d x[%.2f,%.2f] z[%.2f,%.2f]" % (y0, len(sel), sel[:, 0].min(), sel[:, 0].max(), sel[:, 2].min(), sel[:, 2].max()))
bpy.ops.object.shade_smooth()
bpy.ops.wm.save_as_mainfile(filepath=args[1])

sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE_NEXT"
sc.render.resolution_x = 640
sc.render.resolution_y = 640
cd = bpy.data.cameras.new("c")
cd.type = "ORTHO"
cd.ortho_scale = 2.8
cam = bpy.data.objects.new("c", cd)
sc.collection.objects.link(cam)
sc.camera = cam
ld = bpy.data.lights.new("l", "SUN")
ld.energy = 4
lo = bpy.data.objects.new("l", ld)
lo.rotation_euler = (math.radians(30), 0, math.radians(-40))
sc.collection.objects.link(lo)
for nome, pos in [("cima", (0, 0, 6)), ("tras", (0, 6, 1)), ("lado", (6, 0, 1))]:
    cam.location = pos
    d = Vector((0, 0, 1 if nome != "cima" else 0)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y" if nome != "cima" else "Y").to_euler()
    sc.render.filepath = args[2] + "_" + nome + ".png"
    bpy.ops.render.render(write_still=True)
print("PREP OK")
