# Ícones dos itens renderizados em 3D (estilo ficha de personagem dos ARPGs): o item vestido no
# corpo (que fica invisível), na pose parada, com luz quente de um lado e contraluz fria.
# uso: blender -b --python icones.py -- <pasta_saida> [ids separados por vírgula] [tamanho]
import bpy, sys, os, math
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
SO = [x for x in args[1].split(",") if x] if len(args) > 1 else []
SIZE = int(args[2]) if len(args) > 2 else 160

bpy.ops.wm.read_factory_settings(use_empty=True)
import rig, itens3d
R = rig.carregar()
arm, body = R.arm, R.body
fim = R.animacao("Idle_Loop")
itens = itens3d.ler_itens()

sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 64
sc.cycles.use_denoising = True
sc.render.film_transparent = True
sc.render.resolution_x = SIZE
sc.render.resolution_y = SIZE
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Filmic" if "Filmic" in [i.name for i in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items] else "AgX"
sc.view_settings.look = "None"
cd = bpy.data.cameras.new("cam")
cd.type = "ORTHO"
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam


def lamp(name, typ, energy, color, rot, size=1.0):
    ld = bpy.data.lights.new(name, typ)
    ld.energy = energy
    ld.color = color
    ld.angle = math.radians(size)
    lo = bpy.data.objects.new(name, ld)
    lo.rotation_euler = [math.radians(x) for x in rot]
    sc.collection.objects.link(lo)


lamp("principal", "SUN", 6.5, (1.0, 0.85, 0.66), (55, 0, -40), 8)
lamp("contraluz", "SUN", 6.0, (0.55, 0.68, 1.0), (65, 0, 160), 4)
lamp("preench", "SUN", 1.6, (0.75, 0.65, 0.6), (80, 0, 60), 30)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
sc.world = world
# só os itens aparecem: o corpo e as outras malhas do modelo (olhos, sobrancelhas) ficam invisíveis
for o in list(bpy.data.objects):
    if o.type == "MESH":
        o.hide_render = True
os.makedirs(OUT, exist_ok=True)
DIAG = {"staff", "rod", "wand"}

for iid, it in itens.items():
    if SO and iid not in SO:
        continue
    # monta na pose de descanso (as peças são feitas a partir do corpo parado)
    R.animacao("")
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    antes = set(bpy.data.objects.keys())
    pecas = itens3d.construir(arm, body, iid, it)
    novos = [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - antes]
    for o in novos:
        o.hide_render = False
    R.animacao("Idle_Loop")
    R.quadro(max(1, fim // 3))
    # enquadra só as peças (malhas avaliadas, já deformadas pela pose)
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in novos:
        if o.type != "MESH":
            continue
        oe = o.evaluated_get(dg)
        me = oe.to_mesh()
        mw = oe.matrix_world
        pts += [mw @ v.co for v in me.vertices]
        oe.to_mesh_clear()
    if not pts:
        continue
    c = sum(pts, Vector()) / len(pts)
    mn = Vector([min(p[i] for p in pts) for i in range(3)])
    mx = Vector([max(p[i] for p in pts) for i in range(3)])
    c = (mn + mx) * 0.5
    frente = it["estilo"] in ("amulet", "ring")
    az, el = (math.radians(0), math.radians(8)) if frente else (math.radians(28), math.radians(14))
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam.location = c + d * 6.0
    rot = (-d).to_track_quat("-Z", "Y").to_euler()
    if it["estilo"] in DIAG:
        rot.rotate_axis("Z", math.radians(-42))
    cam.rotation_euler = rot
    bpy.context.view_layer.update()
    inv = cam.matrix_world.inverted()
    ext = 0.0
    for p in pts:
        q = inv @ p
        ext = max(ext, abs(q.x - (inv @ c).x) * 2, abs(q.y - (inv @ c).y) * 2)
    cd.ortho_scale = max(0.06, ext * 1.16)
    sc.render.filepath = os.path.join(OUT, iid + ".png")
    bpy.ops.render.render(write_still=True)
    print("ICONE", iid, it["estilo"], len(novos))
    for o in novos:
        bpy.data.objects.remove(o, do_unlink=True)
print("ICONES OK")
