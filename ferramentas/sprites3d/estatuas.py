# Anima estátuas (modelos esculpidos sem esqueleto e sem cor), pinta e renderiza em 2.5D.
# A animação é um "skinning" procedural: pernas, braços, cabeça e tronco com pesos suaves girando
# em volta de pivôs. Renderiza na placa de vídeo (Cycles/OptiX), mesma câmera dos personagens.
# uso: blender -b --factory-startup --python estatuas.py -- <config.json> <pasta_quadros> [nomes|todos] [--previa]
import bpy, sys, os, math, json
import numpy as np
from mathutils import Matrix, Vector
from bpy_extras.object_utils import world_to_camera_view

args = sys.argv[sys.argv.index("--") + 1:]
CFG = json.load(open(args[0], encoding="utf-8"))
OUT = args[1]
SO = args[2].split(",") if len(args) > 2 and args[2] != "todos" else None
PREVIA = "--previa" in args
DIRS = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
SIZE = 256


def sm(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def gpu():
    pr = bpy.context.preferences.addons["cycles"].preferences
    for tipo in ("OPTIX", "CUDA"):
        try:
            pr.compute_device_type = tipo
        except TypeError:
            continue
        pr.get_devices()
        usados = [d for d in pr.devices if d.type == tipo]
        if usados:
            for d in pr.devices:
                d.use = d.type == tipo
            print("GPU", tipo, [d.name for d in usados])
            return True
    print("GPU nao encontrada: usando o processador")
    return False


def junta(p, rx=0.0, ry=0.0, rz=0.0, t=(0, 0, 0)):
    P = Matrix.Translation(Vector(p))
    R = Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
    return Matrix.Translation(Vector(t)) @ P @ R @ P.inverted()


def cor_lin(h):
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def mat_pintado(me, rest, c, H):
    """Cor por regiões (altura, braços, cabeça, caixas) + relevo realçado por oclusão e quinas."""
    X, Y, Z = rest[:, 0], rest[:, 1], rest[:, 2]
    h = Z / H
    N = len(rest)
    cor = np.zeros((N, 3))
    p = c["cores"]

    if "unica" in p:  # objetos: uma cor de base, detalhes pelas caixas
        for k in ("calca", "bota", "cinto", "tronco", "manga", "pele", "cabelo"):
            p.setdefault(k, p["unica"])

    def pinta(m, nome):
        cor[m] = cor_lin(p[nome])
    cinto = c.get("cinto_h", [0.54, 0.61])
    pinta(h > -9, "calca")
    pinta(h < c.get("bota_h", 0.09), "bota")
    pinta(h >= cinto[0], "cinto")
    pinta(h >= cinto[1], "tronco")
    ax = c.get("braco_x", 0.2)
    braco = (np.abs(X) > ax) & (h > 0.36) & (h < 0.82)
    pinta(braco, "manga")
    pinta(braco & (h < c.get("mao_h", 0.53)), "pele")
    cab = h > c.get("cabeca_h", 0.86)
    pinta(cab, "pele")
    pinta(cab & ((h > c.get("cabelo_h", 0.945)) | (Y > c.get("nuca_y", 0.035))), "cabelo")
    if "barba" in p:
        pinta(cab & (h < c.get("cabeca_h", 0.86) + 0.05) & (Y < -0.04), "barba")
    for cx in c.get("caixas", []):
        x0, x1, y0, y1, h0, h1 = cx[:6]
        pinta((X >= x0) & (X <= x1) & (Y >= y0) & (Y <= y1) & (h >= h0) & (h <= h1), cx[6])
    at = me.color_attributes.new("cor", "FLOAT_COLOR", "POINT")
    at.data.foreach_set("color", np.concatenate([cor, np.ones((N, 1))], 1).astype(np.float32).ravel())
    mat = bpy.data.materials.new("npc")
    mat.use_nodes = True
    nt = mat.node_tree
    L = nt.links.new
    bsdf = nt.nodes["Principled BSDF"]
    A = nt.nodes.new("ShaderNodeVertexColor")
    A.layer_name = "cor"

    def rampa(src, p0, c0, p1, c1):
        r = nt.nodes.new("ShaderNodeValToRGB")
        r.color_ramp.elements[0].position = p0
        r.color_ramp.elements[0].color = (c0, c0, c0, 1)
        r.color_ramp.elements[1].position = p1
        r.color_ramp.elements[1].color = (c1, c1, c1, 1)
        L(src, r.inputs[0])
        return r.outputs[0]

    def mult(a, b):
        m = nt.nodes.new("ShaderNodeMix")
        m.data_type = "RGBA"
        m.blend_type = "MULTIPLY"
        m.inputs[0].default_value = 1.0
        L(a, m.inputs[6])
        L(b, m.inputs[7])
        return m.outputs[2]
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.12
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    s = mult(A.outputs["Color"], rampa(ao.outputs["AO"], 0.3, 0.3, 0.95, 1.0))
    s = mult(s, rampa(geo.outputs["Pointiness"], 0.44, 0.45, 0.56, 1.35))
    L(s, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.72
    return mat, None


def mat_fogo():
    """Corpo em chamas: emissao com ruido que sobe em ciclo; pontas amarelas, fendas vermelho-escuras."""
    mat = bpy.data.materials.new("fogo")
    mat.use_nodes = True
    nt = mat.node_tree
    L = nt.links.new
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    saida = nt.nodes["Material Output"]
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    L(tc.outputs["Object"], mp.inputs["Vector"])
    mp.inputs["Scale"].default_value = (1.0, 1.0, 0.55)
    ru = nt.nodes.new("ShaderNodeTexNoise")
    ru.noise_dimensions = "4D"
    ru.inputs["Scale"].default_value = 5.5
    ru.inputs["Detail"].default_value = 2.0
    L(mp.outputs[0], ru.inputs["Vector"])

    def op(nome, a, b):
        m = nt.nodes.new("ShaderNodeMath")
        m.operation = nome
        for i, v in enumerate((a, b)):
            if isinstance(v, (int, float)):
                m.inputs[i].default_value = v
            else:
                L(v, m.inputs[i])
        return m.outputs[0]
    ponta = op("MULTIPLY", op("SUBTRACT", geo.outputs["Pointiness"], 0.5), 3.4)
    calor = op("ADD", op("ADD", op("MULTIPLY", op("SUBTRACT", ru.outputs["Fac"], 0.5), 1.5), ponta), 0.40)
    r = nt.nodes.new("ShaderNodeValToRGB")
    el = r.color_ramp.elements
    el[0].position, el[0].color = 0.05, (0.045, 0.002, 0.0, 1)
    el[1].position, el[1].color = 0.95, (1.0, 0.85, 0.35, 1)
    for pos, col in ((0.3, (0.38, 0.012, 0.0, 1)), (0.5, (0.95, 0.12, 0.0, 1)), (0.72, (1.0, 0.38, 0.01, 1))):
        e = el.new(pos)
        e.color = col
    L(calor, r.inputs[0])
    em = nt.nodes.new("ShaderNodeEmission")
    L(r.outputs[0], em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.25
    L(em.outputs[0], saida.inputs["Surface"])

    def quadro(a):
        mp.inputs["Location"].default_value = (0, 0, 0.22 * math.cos(a))
        ru.inputs["W"].default_value = 0.35 * math.sin(a)
    return mat, quadro


def pose(anim, k, n, c):
    """Angulos de cada parte do corpo no quadro k."""
    a = 2 * math.pi * k / n
    s = math.sin(a)
    if c.get("sentado"):
        return {"tronco": {"rx": 0.025 * s, "rz": 0.03 * math.sin(a + 1)},
                "cabeca": {"rz": 0.22 * math.sin(a), "rx": 0.05 * math.sin(2 * a)},
                "braco_e": {"rx": 0.04 * math.sin(a + 0.5)}, "braco_d": {"rx": -0.04 * math.sin(a)}}
    amp = c.get("passo", 0.42)
    br = c.get("balanco", 0.32)
    if anim == "idle":
        return {"tronco": {"rx": 0.018 * s, "rz": 0.025 * s, "t": (0, 0, 0.006 * s)},
                "cabeca": {"rz": 0.12 * math.sin(a), "rx": 0.03 * math.sin(a + 1)},
                "braco_e": {"ry": 0.09 * br * s}, "braco_d": {"ry": -0.09 * br * s}}
    if anim == "walk":
        sobe = 0.035 * abs(math.cos(a))
        return {"raiz": {"t": (0, 0, sobe)},
                "tronco": {"rz": 0.07 * s, "ry": 0.035 * s, "rx": 0.03},
                "cabeca": {"rz": -0.06 * s},
                "braco_e": {"rx": -br * s}, "braco_d": {"rx": br * s},
                "coxa_e": {"rx": amp * s}, "coxa_d": {"rx": -amp * s},
                "canela_e": {"rx": amp * 1.1 * max(0.0, math.cos(a))},
                "canela_d": {"rx": amp * 1.1 * max(0.0, -math.cos(a))}}
    # golpe (cast): recua e avanca com os bracos
    u = k / (n - 1)
    rec = math.sin(min(1, u / 0.4) * math.pi / 2) if u < 0.4 else max(0.0, 1 - (u - 0.4) / 0.2)
    bote = 0.0 if u < 0.4 else math.sin(min(1.0, (u - 0.4) / 0.6) * math.pi)
    return {"raiz": {"t": (0, -0.18 * bote + 0.05 * rec, 0)},
            "tronco": {"rx": 0.28 * bote - 0.18 * rec, "rz": 0.3 * rec - 0.35 * bote},
            "cabeca": {"rx": -0.1 * bote, "rz": 0.2 * bote - 0.2 * rec},
            "braco_d": {"rx": 0.9 * rec - 1.35 * bote}, "braco_e": {"rx": 0.5 * bote - 0.5 * rec},
            "coxa_e": {"rx": -0.25 * bote}, "coxa_d": {"rx": 0.25 * bote}}


PAI = {"tronco": "raiz", "cabeca": "tronco", "braco_e": "tronco", "braco_d": "tronco",
       "coxa_e": "raiz", "coxa_d": "raiz", "canela_e": "coxa_e", "canela_d": "coxa_d"}


def pesos(rest, c, H):
    X, Z = rest[:, 0], rest[:, 2]
    h = Z / H
    ax = c.get("braco_x", 0.2)
    braco = sm(np.abs(X), ax - 0.03, ax + 0.05) * sm(h, 0.3, 0.42) * (1 - sm(h, 0.74, 0.82))
    cab = sm(h, c.get("pescoco_h", 0.82), c.get("pescoco_h", 0.82) + 0.06)
    if c.get("sentado"):
        perna = np.zeros_like(h)
    else:
        perna = (1 - sm(h, 0.36, 0.52)) * (1 - braco)
    lado = sm(X, -0.05, 0.05)
    baixo = 1 - sm(h, 0.2, 0.3)
    W = {"braco_e": braco * (X > 0), "braco_d": braco * (X <= 0), "cabeca": cab,
         "coxa_e": perna * lado * (1 - baixo), "coxa_d": perna * (1 - lado) * (1 - baixo),
         "canela_e": perna * lado * baixo, "canela_d": perna * (1 - lado) * baixo}
    W["tronco"] = np.clip(1 - sum(W.values()), 0, 1)
    soma = sum(W.values())
    return {b: w / soma for b, w in W.items()}


def cena(c):
    sc = bpy.context.scene
    for ob in list(sc.objects):
        if ob.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(ob)
    sc.render.engine = "CYCLES"
    sc.cycles.device = "GPU" if gpu() else "CPU"
    sc.cycles.samples = 32
    sc.cycles.use_denoising = True
    sc.render.use_persistent_data = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = SIZE
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard" if c.get("tipo") == "fogo" else "AgX"
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
    for nome, energia, cor, rot, ang in (("principal", 4.5, (1.0, 0.86, 0.68), (50, 0, -55), 6),
                                         ("contraluz", 3.0, (0.55, 0.65, 1.0), (60, 0, 150), 4),
                                         ("preench", 0.9, (0.7, 0.6, 0.55), (70, 0, 40), 30)):
        ld = bpy.data.lights.new(nome, "SUN")
        ld.energy, ld.color, ld.angle = energia, cor, math.radians(ang)
        lo = bpy.data.objects.new(nome, ld)
        lo.rotation_euler = [math.radians(v) for v in rot]
        sc.collection.objects.link(lo)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.2
    sc.world = w
    return sc, cam


for nome, c in CFG["modelos"].items():
    if SO and nome not in SO:
        continue
    pad = CFG.get("padrao", {})
    cores = dict(pad.get("cores", {}), **c.get("cores", {}))
    c = dict(pad, **c)
    c["cores"] = cores
    bpy.ops.wm.open_mainfile(filepath=os.path.join(CFG["pasta_blend"], c["blend"] + ".blend"))
    o = bpy.data.objects["M"]
    me = o.data
    if c.get("corta_base", 0) > 0:  # tira o disco de base da miniatura
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(me)
        zc = c["corta_base"]
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < zc], context="VERTS")
        for v in bm.verts:
            v.co.z -= zc
        bm.to_mesh(me)
        bm.free()
    N = len(me.vertices)
    rest = np.zeros(N * 3)
    me.vertices.foreach_get("co", rest)
    rest = rest.reshape(-1, 3)
    if c.get("gira"):
        rest = rest @ np.array(Matrix.Rotation(math.radians(c["gira"]), 3, "Z")).T
    objeto = c.get("tipo") == "objeto"
    H = float(rest[:, 2].max())
    # centro pelo tronco (o que está nas mãos não desloca o eixo do giro)
    meio = rest[(rest[:, 2] > 0.5 * H) & (rest[:, 2] < 0.75 * H)]
    if len(meio) and not objeto:
        rest[:, 0] -= np.median(meio[:, 0])
        rest[:, 1] -= np.median(meio[:, 1])
    corpo_h = float(c.get("corpo", 1.0)) * H  # fração da altura que é o corpo (sem o que leva na cabeça)
    me.vertices.foreach_set("co", rest.ravel())
    me.update()
    mat, anima_mat = mat_fogo() if c.get("tipo") == "fogo" else mat_pintado(me, rest, c, corpo_h)
    me.materials.clear()
    me.materials.append(mat)
    escala = c["altura"] / corpo_h if "altura" in c else c.get("escala", 1.0)
    o.scale = (escala, escala, escala)
    sc, cam = cena(c)
    piv = bpy.data.objects.new("pivo", None)
    sc.collection.objects.link(piv)
    o.parent = piv
    dest = os.path.join(OUT, nome)
    os.makedirs(dest, exist_ok=True)
    bpy.context.view_layer.update()
    pe = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
    anims = c.get("anims", {"idle": 8, "walk": 8})
    meta = {"tamanho": SIZE, "pe": [round(pe.x * SIZE, 1), round((1 - pe.y) * SIZE, 1)], "anims": {}}
    W = None if objeto else pesos(rest, c, corpo_h)
    bx = c.get("braco_x", 0.2)
    PIV = {"raiz": (0, 0, 0), "tronco": (0, 0, 0.5 * corpo_h), "cabeca": (0, 0, 0.84 * corpo_h),
           "braco_e": (bx, 0, 0.76 * corpo_h), "braco_d": (-bx, 0, 0.76 * corpo_h),
           "coxa_e": (0.1, 0, 0.49 * corpo_h), "coxa_d": (-0.1, 0, 0.49 * corpo_h),
           "canela_e": (0.1, 0, 0.27 * corpo_h), "canela_d": (-0.1, 0, 0.27 * corpo_h)}
    chama = c.get("tipo") == "fogo"
    fase = rest[:, 0] * 11.0 + rest[:, 1] * 9.0 - rest[:, 2] * 8.0
    for anim, n in anims.items():
        meta["anims"][anim] = n
        for k in ([0, n // 4] if PREVIA else range(n)):
            if not objeto:
                P = pose(anim, k, n, c)
                mundo = {}

                def M(b):
                    if b not in mundo:
                        loc = junta(PIV[b], **P.get(b, {}))
                        mundo[b] = (M(PAI[b]) @ loc) if b in PAI else loc
                    return mundo[b]
                co = np.zeros_like(rest)
                for b, w in W.items():
                    m = np.array(M(b))
                    co += w[:, None] * (rest @ m[:3, :3].T + m[:3, 3])
                if chama:  # labaredas: sobem e tremulam em ciclo, mais fortes em cima e nas bordas
                    a = 2 * math.pi * k / n
                    f = sm(rest[:, 2] / H, 0.08, 0.5) * (0.45 + 0.55 * sm(np.hypot(rest[:, 0], rest[:, 1]), 0.1, 0.45))
                    co[:, 2] += 0.075 * f * np.maximum(0, np.sin(fase + a)) ** 2
                    co[:, 0] += 0.028 * f * np.sin(fase * 0.7 + a * 2)
                    co[:, 1] += 0.028 * f * np.cos(fase * 0.8 - a)
                me.vertices.foreach_set("co", co.ravel())
                me.update()
                if anima_mat:
                    anima_mat(2 * math.pi * k / n)
            for di, d in enumerate(DIRS):
                if (PREVIA and d not in ("S", "E")) or (objeto and d != "S"):
                    continue
                a = di * math.pi / 4.0
                gx, gy = math.cos(a), math.sin(a) * 2.0
                piv.rotation_euler = (0, 0, math.atan2(-gy, gx) + math.pi / 2.0)
                sc.render.filepath = os.path.join(dest, "%s_%s_%02d.png" % (anim, d, k))
                bpy.ops.render.render(write_still=True)
    json.dump(meta, open(os.path.join(dest, "meta.json"), "w"))
    print("PRONTO", nome, meta, "H=%.2f" % H, flush=True)
