# Renderiza personagens 3D realistas (Quaternius, CC0) como sprites 2.5D no estilo Diablo II:
# câmera ortográfica a 30° (chão isométrico 2:1 do jogo), 8 direções, luz dramática.
# uso: blender -b --python ferramentas/sprites3d/render.py -- <saida> <anim> <quadros> [modelo]
import bpy, math, sys, os
from mathutils import Vector

Q = r"E:\Claude Jobs\arson\legado\3d-roupas-nao-publicado\q"
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = args[0] if len(args) > 0 else r"E:\Claude Jobs\arson\test\sprites"
ANIM = args[1] if len(args) > 1 else "Walk_Loop"
NFRAMES = int(args[2]) if len(args) > 2 else 8
MODEL = args[3] if len(args) > 3 else "Superhero_Male"
CLASSE = args[4] if len(args) > 4 else ""
DIRS = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
SIZE = 256

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(Q, MODEL + ".gltf"))
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
body = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("SuperHero")]
for o in bpy.data.objects:
    if o.name == "Icosphere":
        o.hide_render = True
if CLASSE:
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    import roupas
    roupas.vestir(arm, body[0], CLASSE)

# animações: vêm como objetos vazios com o mesmo nome dos ossos. Cada osso segue o seu vazio
# (Child Of), guardando a diferença de orientação da pose de descanso (o importador reorienta os ossos).
n0 = set(bpy.data.objects.keys())
bpy.ops.import_scene.gltf(filepath=os.path.join(Q, "anims.glb"))
empties = {o.name: o for o in bpy.data.objects if o.name not in n0 and o.type == "EMPTY"}
root_e = [e for n, e in empties.items() if n.startswith("Armature")][0]
for e in empties.values():
    if e.animation_data:
        e.animation_data.action = None


def glb_nodes(path):
    """Pose de descanso de cada nó (lida do JSON do .glb)."""
    import json, struct
    with open(path, "rb") as f:
        data = f.read()
    ln = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + ln].decode("utf-8"))
    return {n.get("name", ""): n for n in js.get("nodes", [])}


# volta cada vazio para a pose de descanso (convertendo do glTF, Y para cima, para o Blender, Z para cima)
from mathutils import Quaternion
for name, nd in glb_nodes(os.path.join(Q, "anims.glb")).items():
    e = empties.get(name)
    if e is None or e == root_e:
        continue
    t = nd.get("translation", [0, 0, 0])
    r = nd.get("rotation", [0, 0, 0, 1])
    s = nd.get("scale", [1, 1, 1])
    e.rotation_mode = "QUATERNION"
    e.location = (t[0], -t[2], t[1])
    e.rotation_quaternion = Quaternion((r[3], r[0], -r[2], r[1]))
    e.scale = (s[0], s[2], s[1])
pivot = bpy.data.objects.new("pivo", None)
bpy.context.scene.collection.objects.link(pivot)
root_e.parent = pivot
bpy.context.view_layer.update()
# diferença de orientação de cada osso para o seu vazio, na pose de descanso
OFF = {}
for b in arm.data.bones:
    e = empties.get(b.name)
    if e is not None:
        OFF[b.name] = e.matrix_world.inverted() @ (arm.matrix_world @ b.matrix_local)
ORDER = sorted(arm.data.bones, key=lambda b: len(b.parent_recursive))


def pose_from_empties():
    """Calcula a pose de cada osso (do tronco às pontas) a partir dos vazios animados."""
    bpy.context.view_layer.update()
    inv_arm = arm.matrix_world.inverted()
    want = {}
    for b in ORDER:
        e = empties.get(b.name)
        if e is not None and b.name in OFF:
            want[b.name] = inv_arm @ e.matrix_world @ OFF[b.name]
        elif b.parent and b.parent.name in want:
            want[b.name] = want[b.parent.name] @ b.parent.matrix_local.inverted() @ b.matrix_local
        else:
            want[b.name] = b.matrix_local.copy()
    for b in ORDER:
        pb = arm.pose.bones[b.name]
        if b.parent:
            rest_rel = b.parent.matrix_local.inverted() @ b.matrix_local
            pb.matrix_basis = rest_rel.inverted() @ want[b.parent.name].inverted() @ want[b.name]
        else:
            pb.matrix_basis = b.matrix_local.inverted() @ want[b.name]
def usar_animacao(nome):
    """Coloca a animação em todos os vazios; devolve o último quadro."""
    fim = 1
    for name, e in empties.items():
        act = bpy.data.actions.get(nome + "_" + name)
        if e.animation_data is None:
            e.animation_data_create()
        e.animation_data.action = act
        if act:
            fim = max(fim, int(act.frame_range[1]))
    return fim

# cena: câmera ortográfica isométrica (30° de altura), fundo transparente
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 48
sc.cycles.use_denoising = True
sc.render.film_transparent = True
sc.render.resolution_x = SIZE
sc.render.resolution_y = SIZE
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Filmic" if "Filmic" in [i.name for i in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items] else "AgX"
sc.view_settings.look = "None"
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 2.6
cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam)
el = math.radians(30)
D = 10.0
cam.location = (0, -D * math.cos(el), D * math.sin(el) + 0.85)
cam.rotation_euler = (math.radians(90) - el, 0, 0)
sc.camera = cam
# luz: principal quente do alto à esquerda, contraluz fria atrás, preenchimento fraco
def lamp(name, typ, energy, color, rot, size=1.0):
    ld = bpy.data.lights.new(name, typ)
    ld.energy = energy
    ld.color = color
    if typ == "SUN":
        ld.angle = math.radians(size)
    lo = bpy.data.objects.new(name, ld)
    lo.rotation_euler = [math.radians(a) for a in rot]
    sc.collection.objects.link(lo)
lamp("principal", "SUN", 4.5, (1.0, 0.86, 0.68), (50, 0, -55), 6)
lamp("contraluz", "SUN", 3.0, (0.55, 0.65, 1.0), (60, 0, 150), 4)
lamp("preench", "SUN", 0.6, (0.7, 0.6, 0.55), (70, 0, 40), 30)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[1].default_value = 0.15
sc.world = world

# animações do jogo: nome_no_jogo=Animacao:quadros (ex.: walk=Walk_Loop:8,idle=Idle_Loop:8)
SPEC = ANIM if "=" in ANIM else "walk=%s:%d" % (ANIM, NFRAMES)
os.makedirs(OUT, exist_ok=True)
from bpy_extras.object_utils import world_to_camera_view
bpy.context.view_layer.update()
pe = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
meta = {"tamanho": SIZE, "pe": [round(pe.x * SIZE, 1), round((1 - pe.y) * SIZE, 1)], "anims": {}}
for item in SPEC.split(","):
    jogo, resto = item.split("=")
    nome, nq = resto.split(":")
    nq = int(nq)
    fend = usar_animacao(nome)
    meta["anims"][jogo] = nq
    for di, d in enumerate(DIRS):
        a = di * math.pi / 4.0
        gx, gy = math.cos(a), math.sin(a) * 2.0  # y da tela para baixo = em direção à câmera
        yaw = math.atan2(-gy, gx)  # mundo: +X direita, -Y em direção à câmera
        pivot.rotation_euler = (0, 0, yaw + math.pi / 2.0)
        for k in range(nq):
            # laços: quadros espalhados pelo ciclo; ações únicas (magia, golpe, morte): do começo ao fim
            fr = 1 + round(k * (fend - 1) / max(1, (nq if jogo in ("idle", "walk", "run") else nq - 1)))
            sc.frame_set(fr)
            pose_from_empties()
            sc.render.filepath = os.path.join(OUT, "%s_%s_%02d.png" % (jogo, d, k))
            bpy.ops.render.render(write_still=True)
import json
json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"))
print("PRONTO", meta)
