# Camadas de equipamento para os personagens 2.5D: cada ESTILO de item é renderizado em cinza
# neutro, vestido no corpo (que vira recorte: esconde o que fica atrás dele), em todas as
# animações e direções, com a mesma câmera de render.py. Uma passagem AOV ("acc") marca as
# partes de detalhe (metal, gema): o jogo pinta a parte principal com a cor do item e o detalhe
# com a cor de destaque. Com "base", renderiza o corpo com a roupa de baixo (sem itens).
# uso: blender -b --python camadas.py -- <pasta_saida> <estilo|base> "idle=Idle_Loop:8,..." [amostras] [motor]
import bpy, sys, os, math, glob, json
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[sys.argv.index("--") + 1:]
OUT, ESTILO, SPEC = args[0], args[1], args[2]
AMOSTRAS = int(args[3]) if len(args) > 3 else 24
MOTOR = args[4] if len(args) > 4 else "CYCLES"
DIRS = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
SIZE = 256

bpy.ops.wm.read_factory_settings(use_empty=True)
import rig, itens3d, roupas
R = rig.carregar()
arm, body = R.arm, R.body
sc = bpy.context.scene


def roupa_de_baixo():
    """Camisa de linho e calção simples (o que aparece sem itens)."""
    m1 = roupas.tecido("linho", (0.085, 0.065, 0.045), 200.0)
    m2 = roupas.tecido("linho2", (0.05, 0.04, 0.032), 200.0)
    p = [roupas.casca(body, "camisa", {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r"},
            0.45, 0.008, m1, corta=lambda co: co.z > 1.56 or abs(co.x) > 0.42),
         roupas.casca(body, "calcao", {"pelvis", "thigh_l", "thigh_r"}, 0.45, 0.008, m2, corta=lambda co: co.z < 0.62 or co.z > 1.08)]
    return p


malhas_modelo = [o for o in bpy.data.objects if o.type == "MESH"]
base = roupa_de_baixo()
if ESTILO == "base":
    pecas = []
else:
    # todo o corpo (e a roupa de baixo) vira recorte: o item atrás dele não aparece
    for o in malhas_modelo + base:
        o.is_holdout = True
    it = dict(estilo=ESTILO, cor=(0.8, 0.8, 0.8, 1), acento=(0.85, 0.85, 0.85, 1), brilho=0.6, slot=0, nome=ESTILO)
    antes = set(bpy.data.objects.keys())
    itens3d.construir(arm, body, "x", it)
    pecas = [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - antes]
    for o in pecas:
        o.is_holdout = False  # cascas copiadas do corpo herdam o recorte
    # AOV "acc" = 1 nos materiais de detalhe
    for o in pecas:
        if o.type != "MESH":
            continue
        for m in o.data.materials:
            if m is None or "acc_feito" in m:
                continue
            m["acc_feito"] = 1
            nt = m.node_tree
            ao = nt.nodes.new("ShaderNodeOutputAOV")
            ao.aov_name = "acc"
            ao.inputs["Value"].default_value = 1.0 if (m.name.startswith("ouro_") or m.name.startswith("gema_")) else 0.0
    for lo in [o for o in pecas if o.type == "LIGHT"]:
        lo.data.energy *= 0.6

sc.render.engine = "CYCLES" if MOTOR == "CYCLES" else "BLENDER_EEVEE_NEXT"
if MOTOR == "CYCLES":
    sc.cycles.samples = AMOSTRAS
    sc.cycles.use_denoising = True
else:
    sc.eevee.taa_render_samples = AMOSTRAS
sc.render.film_transparent = True
# deixa núcleos livres para o computador continuar usável durante o render longo
sc.render.threads_mode = "FIXED"
sc.render.threads = 20
sc.render.resolution_x = SIZE
sc.render.resolution_y = SIZE
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Filmic" if "Filmic" in [i.name for i in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items] else "AgX"
sc.view_settings.look = "None"
cd = bpy.data.cameras.new("cam")
cd.type = "ORTHO"
cd.ortho_scale = 2.6
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
el = math.radians(30)
D = 10.0
cam.location = (0, -D * math.cos(el), D * math.sin(el) + 0.85)
cam.rotation_euler = (math.radians(90) - el, 0, 0)
sc.camera = cam


def lamp(name, typ, energy, color, rot, size=1.0):
    ld = bpy.data.lights.new(name, typ)
    ld.energy = energy
    ld.color = color
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

# passagem AOV gravada ao lado de cada quadro (compositor)
fo = None
if ESTILO != "base":
    vl = sc.view_layers[0]
    a = vl.aovs.add()
    a.name = "acc"
    a.type = "VALUE"
    sc.use_nodes = True
    nt = sc.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    rl = nt.nodes.new("CompositorNodeRLayers")
    comp = nt.nodes.new("CompositorNodeComposite")
    nt.links.new(rl.outputs["Image"], comp.inputs["Image"])
    nt.links.new(rl.outputs["Alpha"], comp.inputs["Alpha"])
    fo = nt.nodes.new("CompositorNodeOutputFile")
    fo.format.file_format = "PNG"
    fo.format.color_mode = "BW"
    fo.format.color_depth = "8"
    nt.links.new(rl.outputs["acc"], fo.inputs[0])

os.makedirs(OUT, exist_ok=True)
from bpy_extras.object_utils import world_to_camera_view
bpy.context.view_layer.update()
pe = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
meta = {"tamanho": SIZE, "pe": [round(pe.x * SIZE, 1), round((1 - pe.y) * SIZE, 1)], "anims": {}}
# animação mista "Pernas+Braços" (ex.: Walk_Loop+Spell_Simple_Shoot): pernas e quadril de uma, tronco e braços da outra
CIMA = [b.name for b in arm.data.bones if b.name == "spine_01" or "spine_01" in [p.name for p in b.parent_recursive]]
for item in SPEC.split(","):
    jogo, resto = item.split("=")
    nome, nq = resto.split(":")
    nq = int(nq)
    partes = nome.split("+")
    fend2 = R.animacao(partes[1]) if len(partes) > 1 else 0
    fend = R.animacao(partes[0])
    meta["anims"][jogo] = nq
    for di, d in enumerate(DIRS):
        a = di * math.pi / 4.0
        gx, gy = math.cos(a), math.sin(a) * 2.0
        R.pivot.rotation_euler = (0, 0, math.atan2(-gy, gx) + math.pi / 2.0)
        for k in range(nq):
            if len(partes) > 1:
                R.animacao(partes[1])
                R.quadro(1 + round(k * (fend2 - 1) / max(1, nq - 1)))
                cima = {b: arm.pose.bones[b].matrix_basis.copy() for b in CIMA}
                R.animacao(partes[0])
                R.quadro(1 + round(k * (fend - 1) / max(1, nq)))
                for b, m in cima.items():
                    arm.pose.bones[b].matrix_basis = m
                bpy.context.view_layer.update()
            else:
                fr = 1 + round(k * (fend - 1) / max(1, (nq if jogo in ("idle", "walk", "run") else nq - 1)))
                R.quadro(fr)
            nomeq = "%s_%s_%02d" % (jogo, d, k)
            sc.render.filepath = os.path.join(OUT, nomeq + ".png")
            if fo:
                fo.base_path = OUT
                fo.file_slots[0].path = nomeq + "_acc_"
            bpy.ops.render.render(write_still=True)
            if fo:
                for f in glob.glob(os.path.join(OUT, nomeq + "_acc_*.png")):
                    os.replace(f, os.path.join(OUT, nomeq + "_acc.png"))
json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"))
print("PRONTO", ESTILO, meta)
