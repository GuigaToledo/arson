# Prévia de um modelo STL (só a forma): importa, centraliza e renderiza 2 vistas.
# uso: blender -b --python previa_stl.py -- <arquivo.stl> <saida_prefixo>
import bpy, sys, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.stl_import(filepath=args[0])
o = bpy.context.selected_objects[0]
me = o.data
print("TRIANGULOS", len(me.polygons), "DIM", tuple(round(d, 2) for d in o.dimensions))
bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
o.location = (0, 0, 0)
s = 2.0 / max(o.dimensions)
o.scale = (s, s, s)
mat = bpy.data.materials.new("m")
mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.33, 0.32, 1)
me.materials.append(mat)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE_NEXT"
sc.render.resolution_x = 640
sc.render.resolution_y = 480
cd = bpy.data.cameras.new("c")
cd.type = "ORTHO"
cd.ortho_scale = 2.6
cam = bpy.data.objects.new("c", cd)
sc.collection.objects.link(cam)
sc.camera = cam
ld = bpy.data.lights.new("l", "SUN")
ld.energy = 4
lo = bpy.data.objects.new("l", ld)
lo.rotation_euler = (math.radians(50), 0, math.radians(-40))
sc.collection.objects.link(lo)
for i, (az, el) in enumerate([(0, 20), (90, 25)]):
    a, e = math.radians(az), math.radians(el)
    cam.location = (math.sin(a) * 6 * math.cos(e), -math.cos(a) * 6 * math.cos(e), math.sin(e) * 6)
    d = Vector((0, 0, 0)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = args[1] + "_%d.png" % i
    bpy.ops.render.render(write_still=True)
print("PREVIA OK")
