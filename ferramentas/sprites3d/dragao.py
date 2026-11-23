# Dragão (modelo esculpido sem esqueleto): anima por "skinning" procedural — o corpo é dividido em
# regiões com pesos suaves (cabeça, pescoço, asas, cauda, pernas) e cada região gira em volta de
# um pivô. Renderiza 8 direções com a mesma câmera isométrica dos personagens (2.5D).
# uso: blender -b --python dragao.py -- <dragao.blend> <pasta_saida> [anims] [amostras]
import bpy, sys, os, math, json
import numpy as np
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
BLEND, OUT = args[0], args[1]
SO = args[2].split(",") if len(args) > 2 and args[2] else None
AMOSTRAS = int(args[3]) if len(args) > 3 else 40
DIRS = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
SIZE = 360
ORTHO = 5.12          # mesma densidade de mundo por pixel x 0.7 dos personagens (256px = 2.6)
ESCALA = 1.5          # altura 2 (normalizada) -> 3 m: quase o dobro de um humano
ANIMS = {"idle": 8, "walk": 8, "cast": 8, "damage": 3, "death": 8}

bpy.ops.wm.open_mainfile(filepath=BLEND)
o = bpy.data.objects["Dragao"]
me = o.data
N = len(me.vertices)
rest = np.zeros(N * 3)
me.vertices.foreach_get("co", rest)
rest = rest.reshape(-1, 3)
rest[:, 1] += 0.3     # origem no meio do corpo (a cauda fica para trás)
X, Y, Z = rest[:, 0], rest[:, 1], rest[:, 2]
nrm = np.zeros(N * 3)
me.vertices.foreach_get("normal", nrm)
nrm = nrm.reshape(-1, 3)


def sm(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- regiões (pesos somam 1)
asa = sm(np.abs(X), 0.40, 0.50) * sm(Z, 0.45, 0.62)
asa_l = asa * (X > 0)
asa_r = asa * (X < 0)
livre = 1.0 - asa
cab = sm(Z, 1.45, 1.62) * sm(-Y, -0.25, -0.1) * livre
pesc = np.clip(sm(Z, 1.0, 1.28) * sm(-Y, -0.25, -0.1) * livre - cab, 0, 1)
cauda = sm(Y, 0.25, 0.5) * livre
cauda2 = sm(Y, 0.75, 0.95) * livre
cauda1 = np.clip(cauda - cauda2, 0, 1)
perna = sm(-Z, -0.5, -0.32) * (1 - sm(Y, 0.2, 0.4)) * livre * (1 - cauda)
perna_l = perna * sm(X, 0.04, 0.14)
perna_r = perna * sm(-X, 0.04, 0.14)
W = {"asa_l": asa_l, "asa_r": asa_r, "cab": cab, "pesc": pesc, "cauda1": cauda1, "cauda2": cauda2,
     "perna_l": perna_l, "perna_r": perna_r}
tronco = np.clip(1.0 - sum(W.values()), 0, 1)
W["tronco"] = tronco
soma = sum(W.values())
for k in W:
    W[k] = W[k] / soma

# pivôs (coordenadas normalizadas, já com a origem no corpo) e hierarquia
PIV = {"raiz": (0, 0, 0), "tronco": (0, -0.05, 0.45), "pesc": (0, -0.1, 1.05), "cab": (0, -0.25, 1.5),
       "asa_l": (0.38, 0.0, 1.2), "asa_r": (-0.38, 0.0, 1.2), "cauda1": (0, 0.3, 0.25),
       "cauda2": (0, 0.85, 0.12), "perna_l": (0.24, -0.1, 0.5), "perna_r": (-0.24, -0.1, 0.5), "queda": (0.36, 0, 0)}
PAI = {"raiz": "queda", "tronco": "raiz", "pesc": "tronco", "cab": "pesc", "asa_l": "tronco", "asa_r": "tronco",
       "cauda1": "raiz", "cauda2": "cauda1", "perna_l": "raiz", "perna_r": "raiz"}


def junta(p, rx=0.0, ry=0.0, rz=0.0, t=(0, 0, 0)):
    P = Matrix.Translation(Vector(p))
    R = Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
    return Matrix.Translation(Vector(t)) @ P @ R @ P.inverted()


def deformar(pose):
    """pose: osso -> dict(rx, ry, rz, t). Devolve as posições dos vértices."""
    mundo = {}

    def M(b):
        if b in mundo:
            return mundo[b]
        loc = junta(PIV[b], **pose.get(b, {}))
        m = (M(PAI[b]) @ loc) if b in PAI else loc
        mundo[b] = m
        return m
    out = np.zeros_like(rest)
    raiz = np.array(M("raiz"))
    for b, w in W.items():
        m = np.array(M(b))
        out += w[:, None] * (rest @ m[:3, :3].T + m[:3, 3])
    return out


# ---------------------------------------------------------------- poses
def ciclo(k, n):
    return 2 * math.pi * k / n


def pose_idle(k, n):
    a = ciclo(k, n)
    return {"tronco": {"rx": 0.02 * math.sin(a), "t": (0, 0, 0.012 * math.sin(a))},
            "pesc": {"rx": 0.05 * math.sin(a + 0.6), "rz": 0.06 * math.sin(a * 0.5 * 2)},
            "cab": {"rx": -0.04 * math.sin(a + 1.2)},
            "asa_l": {"ry": 0.06 * math.sin(a)}, "asa_r": {"ry": -0.06 * math.sin(a)},
            "cauda1": {"rz": 0.12 * math.sin(a)}, "cauda2": {"rz": 0.2 * math.sin(a - 0.8)}}


def pose_walk(k, n):
    a = ciclo(k, n)
    s = math.sin(a)
    return {"raiz": {"t": (0, 0, 0.03 * abs(math.cos(a)))},
            "tronco": {"rz": 0.08 * s, "ry": 0.07 * s, "rx": 0.04 * math.cos(2 * a)},
            "pesc": {"rz": -0.08 * s, "rx": 0.06 * math.cos(2 * a)},
            "cab": {"rz": 0.04 * s},
            "asa_l": {"ry": 0.1 + 0.08 * math.cos(2 * a)}, "asa_r": {"ry": -0.1 - 0.08 * math.cos(2 * a)},
            "cauda1": {"rz": -0.2 * s}, "cauda2": {"rz": -0.3 * math.sin(a - 0.9)},
            "perna_l": {"rx": 0.5 * s, "t": (0, -0.05 * s, 0.1 * max(0, s))},
            "perna_r": {"rx": -0.5 * s, "t": (0, 0.05 * s, 0.1 * max(0, -s))}}


def pose_cast(k, n):
    # recua erguendo a cabeça e abrindo as asas, depois avança mordendo/cuspindo e volta
    u = k / (n - 1)
    rec = math.sin(min(1, u / 0.45) * math.pi / 2) if u < 0.45 else max(0, 1 - (u - 0.45) / 0.15)
    bote = 0 if u < 0.45 else math.sin(min(1, (u - 0.45) / 0.55) * math.pi)
    abre = math.sin(u * math.pi)
    return {"tronco": {"rx": -0.12 * rec + 0.22 * bote},
            "pesc": {"rx": -0.35 * rec + 0.55 * bote},
            "cab": {"rx": -0.3 * rec + 0.25 * bote},
            "asa_l": {"ry": 0.55 * abre, "rz": -0.2 * abre}, "asa_r": {"ry": -0.55 * abre, "rz": 0.2 * abre},
            "cauda1": {"rz": 0.25 * rec - 0.2 * bote}, "cauda2": {"rz": 0.3 * rec - 0.3 * bote}}


def pose_damage(k, n):
    u = [0.6, 1.0, 0.4][k]
    return {"tronco": {"rx": -0.15 * u, "rz": 0.08 * u}, "pesc": {"rx": -0.25 * u, "rz": -0.15 * u},
            "cab": {"rx": -0.2 * u}, "asa_l": {"ry": 0.25 * u}, "asa_r": {"ry": -0.25 * u},
            "cauda1": {"rz": 0.2 * u}}


def pose_death(k, n):
    u = k / (n - 1)
    q = u * u * (3 - 2 * u)
    ergue = math.sin(min(1, u / 0.3) * math.pi) * (u < 0.3)
    return {"queda": {"ry": 1.35 * q, "t": (-0.5 * q, 0, -0.04 * q)},
            "tronco": {"rx": -0.2 * ergue + 0.25 * q},
            "pesc": {"rx": -0.4 * ergue + 0.7 * q, "rz": 0.3 * q},
            "cab": {"rx": -0.3 * ergue + 0.4 * q},
            "asa_l": {"ry": 0.6 * ergue - 0.5 * q}, "asa_r": {"ry": -0.6 * ergue + 0.9 * q},
            "cauda1": {"rz": 0.3 * q}, "cauda2": {"rz": 0.4 * q},
            "perna_l": {"rx": 0.3 * q}, "perna_r": {"rx": -0.2 * q}}


POSES = {"idle": pose_idle, "walk": pose_walk, "cast": pose_cast, "damage": pose_damage, "death": pose_death}

# ---------------------------------------------------------------- material: escamas vermelho-escuras,
# ventre cor de bronze, membrana das asas mais clara, pontas (chifres, espinhos, garras) cor de osso
cor = np.zeros((N, 4), dtype=np.float32)
costas = np.array([0.11, 0.022, 0.016])
ventre = np.array([0.36, 0.17, 0.06])
membrana = np.array([0.2, 0.04, 0.03])
frente = sm(-nrm[:, 1], 0.2, 0.7) * sm(0.32 - np.abs(X), 0.0, 0.12) * sm(Z, 0.25, 0.4) * (1 - sm(Z, 1.35, 1.5))
c = costas[None, :] * (1 - frente[:, None]) + ventre[None, :] * frente[:, None]
c = c * (1 - asa[:, None]) + membrana[None, :] * asa[:, None]
cor[:, :3] = c
cor[:, 3] = 1
at = me.color_attributes.get("cor") or me.color_attributes.new("cor", "FLOAT_COLOR", "POINT")
at.data.foreach_set("color", cor.ravel())

mat = bpy.data.materials.new("dragao")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
A = nt.nodes.new("ShaderNodeVertexColor")
A.layer_name = "cor"
geo = nt.nodes.new("ShaderNodeNewGeometry")
# pontas (pontiagudo = convexo) ficam cor de osso
pr = nt.nodes.new("ShaderNodeValToRGB")
pr.color_ramp.elements[0].position = 0.53
pr.color_ramp.elements[0].color = (0, 0, 0, 1)
pr.color_ramp.elements[1].position = 0.62
pr.color_ramp.elements[1].color = (1, 1, 1, 1)
nt.links.new(geo.outputs["Pointiness"], pr.inputs[0])
osso = nt.nodes.new("ShaderNodeMix")
osso.data_type = "RGBA"
osso.inputs[7].default_value = (0.55, 0.45, 0.32, 1)
nt.links.new(pr.outputs[0], osso.inputs[0])
nt.links.new(A.outputs["Color"], osso.inputs[6])
# fendas entre escamas (côncavo) mais escuras
fd = nt.nodes.new("ShaderNodeValToRGB")
fd.color_ramp.elements[0].position = 0.42
fd.color_ramp.elements[0].color = (0.35, 0.35, 0.35, 1)
fd.color_ramp.elements[1].position = 0.5
fd.color_ramp.elements[1].color = (1, 1, 1, 1)
nt.links.new(geo.outputs["Pointiness"], fd.inputs[0])
mul = nt.nodes.new("ShaderNodeMix")
mul.data_type = "RGBA"
mul.blend_type = "MULTIPLY"
mul.inputs[0].default_value = 1.0
nt.links.new(osso.outputs[2], mul.inputs[6])
nt.links.new(fd.outputs[0], mul.inputs[7])
nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.42
bsdf.inputs["Specular IOR Level"].default_value = 0.6
bsdf.inputs["Coat Weight"].default_value = 0.15
me.materials.clear()
me.materials.append(mat)
o.scale = (ESCALA, ESCALA, ESCALA)

# ---------------------------------------------------------------- cena (igual a render.py)
sc = bpy.context.scene
for ob in list(sc.objects):
    if ob.type in ("CAMERA", "LIGHT"):
        bpy.data.objects.remove(ob)
sc.render.engine = "CYCLES"
sc.cycles.samples = AMOSTRAS
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
cd.ortho_scale = ORTHO
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
el = math.radians(30)
D = 12.0
cam.location = (0, -D * math.cos(el), D * math.sin(el) + 1.25)
cam.rotation_euler = (math.radians(90) - el, 0, 0)
sc.camera = cam


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
lamp("contraluz", "SUN", 3.5, (0.55, 0.65, 1.0), (60, 0, 150), 4)
lamp("preench", "SUN", 0.6, (0.7, 0.6, 0.55), (70, 0, 40), 30)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[1].default_value = 0.15
sc.world = world
piv = bpy.data.objects.new("pivo", None)
sc.collection.objects.link(piv)
o.parent = piv

os.makedirs(OUT, exist_ok=True)
from bpy_extras.object_utils import world_to_camera_view
bpy.context.view_layer.update()
pe = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
# escala no jogo: mesma medida de mundo dos personagens (256px/2.6m a 0.47)
meta = {"tamanho": SIZE, "pe": [round(pe.x * SIZE, 1), round((1 - pe.y) * SIZE, 1)], "anims": {},
        "escala": round(0.47 * (256 / 2.6) / (SIZE / ORTHO), 3)}
for anim, n in ANIMS.items():
    if SO and anim not in SO:
        continue
    meta["anims"][anim] = n
    for k in range(n):
        co = deformar(POSES[anim](k, n))
        me.vertices.foreach_set("co", co.ravel())
        me.update()
        for di, d in enumerate(DIRS):
            a = di * math.pi / 4.0
            gx, gy = math.cos(a), math.sin(a) * 2.0
            piv.rotation_euler = (0, 0, math.atan2(-gy, gx) + math.pi / 2.0)
            sc.render.filepath = os.path.join(OUT, "%s_%s_%02d.png" % (anim, d, k))
            bpy.ops.render.render(write_still=True)
json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"))
print("PRONTO", meta)
