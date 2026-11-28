# Prepara STLs sem cor (NPCs e objetos): importa, reduz polígonos, normaliza (altura/maior lado 2,
# pés em z=0), salva .blend e uma prévia de frente.
# uso: blender -b --python npcs_prep.py -- <pasta_stl> <pasta_blend> <pasta_previa>
import bpy, sys, os, math
import numpy as np
from mathutils import Vector

SRC, OUTB, OUTP = sys.argv[sys.argv.index("--") + 1:][:3]
for f in sorted(os.listdir(SRC)):
    if not f.lower().endswith(".stl"):
        continue
    nome = os.path.splitext(f)[0].replace("NPC_act2_extras_", "")
    if os.path.exists(os.path.join(OUTB, nome + ".blend")):
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.stl_import(filepath=os.path.join(SRC, f))
    o = bpy.context.selected_objects[0]
    o.name = "M"
    bpy.context.view_layer.objects.active = o
    n = len(o.data.polygons)
    m = o.modifiers.new("dec", "DECIMATE")
    m.ratio = min(1.0, 60000.0 / n)
    bpy.ops.object.modifier_apply(modifier="dec")
    me = o.data
    co = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mn, mx = co.min(0), co.max(0)
    print("MODELO", nome, n, "dim", (mx - mn).round(1))
    s = 2.0 / (mx - mn).max()
    co = (co - np.array([(mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, mn[2]])) * s
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    bpy.ops.object.shade_smooth()
    mat = bpy.data.materials.new("m")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.33, 0.32, 1)
    me.materials.append(mat)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTB, nome + ".blend"))
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.resolution_x = sc.render.resolution_y = 320
    cd = bpy.data.cameras.new("c")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.3
    cam = bpy.data.objects.new("c", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    ld = bpy.data.lights.new("l", "SUN")
    ld.energy = 4
    lo = bpy.data.objects.new("l", ld)
    lo.rotation_euler = (math.radians(45), 0, math.radians(-35))
    sc.collection.objects.link(lo)
    z = (mx - mn)[2] * s / 2
    cam.location = (0, -6, z + 1.6)
    cam.rotation_euler = (Vector((0, 0, z)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUTP, nome + ".png")
    bpy.ops.render.render(write_still=True)
print("PREP OK")
