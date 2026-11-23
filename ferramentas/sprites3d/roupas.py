# Roupas e equipamento dos magos, modelados por código em cima do corpo realista (Quaternius, CC0).
# Tudo segue a animação: as peças são "cascas" do próprio corpo (mesmos pesos dos ossos),
# peças presas a ossos (ombreiras, cinto) ou malhas com pesos montados aqui (saia da túnica, capa).
import bpy, bmesh, math
from mathutils import Vector

# cores por classe: tecido principal, tecido escuro, couro, metal, cristal (emissão)
PALETAS = {
    "fogo": dict(pano=(0.16, 0.018, 0.012), pano2=(0.035, 0.022, 0.02), couro=(0.13, 0.07, 0.04), metal=(0.75, 0.55, 0.22), cristal=(1.0, 0.35, 0.05)),
    "agua": dict(pano=(0.015, 0.045, 0.13), pano2=(0.02, 0.03, 0.06), couro=(0.09, 0.07, 0.06), metal=(0.72, 0.76, 0.8), cristal=(0.2, 0.6, 1.0)),
    "vento": dict(pano=(0.2, 0.23, 0.24), pano2=(0.08, 0.12, 0.12), couro=(0.16, 0.13, 0.1), metal=(0.7, 0.72, 0.75), cristal=(0.6, 0.55, 1.0)),
    "terra": dict(pano=(0.09, 0.06, 0.028), pano2=(0.07, 0.1, 0.04), couro=(0.12, 0.08, 0.04), metal=(0.55, 0.38, 0.18), cristal=(0.4, 0.95, 0.25)),
}


# ------------------------------------------------------------ materiais
def _mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m, m.node_tree.nodes, m.node_tree.links, m.node_tree.nodes["Principled BSDF"]


def tecido(name, cor, escala=180.0):
    """Pano com trama fina (relevo), variação de cor e desgaste."""
    m, n, l, p = _mat(name)
    tc = n.new("ShaderNodeTexCoord")
    noise = n.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 6.0; noise.inputs["Detail"].default_value = 8.0
    l.new(tc.outputs["Object"], noise.inputs["Vector"])
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (cor[0] * 0.55, cor[1] * 0.55, cor[2] * 0.55, 1)
    ramp.color_ramp.elements[1].color = (min(1, cor[0] * 1.35), min(1, cor[1] * 1.35), min(1, cor[2] * 1.35), 1)
    l.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    l.new(ramp.outputs["Color"], p.inputs["Base Color"])
    wave = n.new("ShaderNodeTexWave"); wave.inputs["Scale"].default_value = escala; wave.inputs["Distortion"].default_value = 2.0
    l.new(tc.outputs["Object"], wave.inputs["Vector"])
    bump = n.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25
    l.new(wave.outputs["Fac"], bump.inputs["Height"])
    l.new(bump.outputs["Normal"], p.inputs["Normal"])
    p.inputs["Roughness"].default_value = 0.88
    p.inputs["Sheen Weight"].default_value = 0.4
    return m


def couro(name, cor):
    m, n, l, p = _mat(name)
    tc = n.new("ShaderNodeTexCoord")
    noise = n.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 40.0; noise.inputs["Detail"].default_value = 10.0
    l.new(tc.outputs["Object"], noise.inputs["Vector"])
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (cor[0] * 0.5, cor[1] * 0.5, cor[2] * 0.5, 1)
    ramp.color_ramp.elements[1].color = (cor[0] * 1.6, cor[1] * 1.5, cor[2] * 1.4, 1)
    l.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    l.new(ramp.outputs["Color"], p.inputs["Base Color"])
    bump = n.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.45
    l.new(noise.outputs["Fac"], bump.inputs["Height"])
    l.new(bump.outputs["Normal"], p.inputs["Normal"])
    p.inputs["Roughness"].default_value = 0.55
    return m


def metal(name, cor):
    m, n, l, p = _mat(name)
    tc = n.new("ShaderNodeTexCoord")
    noise = n.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 90.0
    l.new(tc.outputs["Object"], noise.inputs["Vector"])
    mr = n.new("ShaderNodeMapRange"); mr.inputs["To Min"].default_value = 0.22; mr.inputs["To Max"].default_value = 0.6
    l.new(noise.outputs["Fac"], mr.inputs["Value"])
    l.new(mr.outputs["Result"], p.inputs["Roughness"])
    p.inputs["Base Color"].default_value = (*cor, 1)
    p.inputs["Metallic"].default_value = 1.0
    return m


def cristal(name, cor):
    m, n, l, p = _mat(name)
    p.inputs["Base Color"].default_value = (*cor, 1)
    p.inputs["Emission Color"].default_value = (*cor, 1)
    p.inputs["Emission Strength"].default_value = 6.0
    p.inputs["Roughness"].default_value = 0.1
    return m


# ------------------------------------------------------------ peças
def _peso(v, body, grupos):
    s = 0.0
    for g in v.groups:
        if body.vertex_groups[g.group].name in grupos:
            s += g.weight
    return s


def casca(body, nome, grupos, minimo, empurra, mat, alarga=None, corta=None):
    """Copia o corpo, mantém só a parte dos grupos de ossos e empurra para fora (segue a animação)."""
    o = body.copy()
    o.data = body.data.copy()
    o.name = nome
    bpy.context.scene.collection.objects.link(o)
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    dl = bm.verts.layers.deform.active
    tira = []
    for v in bm.verts:
        s = sum(w for gi, w in v[dl].items() if body.vertex_groups[gi].name in grupos)
        if s < minimo or (corta and corta(v.co)):
            tira.append(v)
    bmesh.ops.delete(bm, geom=tira, context="VERTS")
    for v in bm.verts:
        d = empurra + (alarga(v.co) if alarga else 0.0)
        v.co += v.normal * d
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    return o


def preso_ao_osso(obj, arm, osso):
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = osso
    bpy.context.view_layer.update()


def _no_osso(obj, arm, osso, pos_mundo):
    """Prende um objeto num osso mantendo a posição no mundo (pose de descanso)."""
    mw = obj.matrix_world.copy()
    preso_ao_osso(obj, arm, osso)
    obj.matrix_world = mw


def saia(arm, nome, mat, z_top=1.02, z_bot=0.16, r_top=(0.19, 0.14), r_bot=(0.42, 0.33), seg=28, aneis=10):
    """Saia da túnica: cone preso ao quadril e às coxas (abre e fecha com o passo)."""
    bm = bmesh.new()
    rings = []
    for i in range(aneis + 1):
        t = i / aneis
        z = z_top + (z_bot - z_top) * t
        rx = r_top[0] + (r_bot[0] - r_top[0]) * t
        ry = r_top[1] + (r_bot[1] - r_top[1]) * t
        ring = []
        for j in range(seg):
            a = 2 * math.pi * j / seg
            # dobras do pano na barra
            dob = 1.0 + 0.05 * math.sin(a * 9) * t
            ring.append(bm.verts.new((math.cos(a) * rx * dob, 0.03 + math.sin(a) * ry * dob, z)))
        rings.append(ring)
    for i in range(aneis):
        for j in range(seg):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % seg], rings[i + 1][(j + 1) % seg], rings[i + 1][j]))
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    for g in ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"]:
        o.vertex_groups.new(name=g)
    for v in me.vertices:
        t = (z_top - v.co.z) / (z_top - z_bot)
        lado = max(-1.0, min(1.0, v.co.x / 0.12))
        perna = min(1.0, t * 1.4)
        o.vertex_groups["pelvis"].add([v.index], max(0.0, 1.0 - perna), "REPLACE")
        coxa = perna * (1.0 - max(0.0, t - 0.5))
        canela = perna * max(0.0, t - 0.5)
        if lado > 0:
            o.vertex_groups["thigh_l"].add([v.index], coxa * (0.5 + 0.5 * lado), "REPLACE")
            o.vertex_groups["calf_l"].add([v.index], canela * (0.5 + 0.5 * lado), "REPLACE")
            o.vertex_groups["thigh_r"].add([v.index], coxa * (0.5 - 0.5 * lado), "REPLACE")
        else:
            o.vertex_groups["thigh_r"].add([v.index], coxa * (0.5 - 0.5 * lado), "REPLACE")
            o.vertex_groups["calf_r"].add([v.index], canela * (0.5 - 0.5 * lado), "REPLACE")
            o.vertex_groups["thigh_l"].add([v.index], coxa * (0.5 + 0.5 * lado), "REPLACE")
    md = o.modifiers.new("arm", "ARMATURE")
    md.object = arm
    sol = o.modifiers.new("esp", "SOLIDIFY")
    sol.thickness = 0.012
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    return o


def capa(arm, nome, mat, largura=0.46, z_top=1.5, z_bot=0.22, seg_x=10, seg_y=14):
    """Capa presa aos ombros, caindo atrás (presa às costas e um pouco às coxas)."""
    bm = bmesh.new()
    grid = []
    for i in range(seg_y + 1):
        t = i / seg_y
        z = z_top + (z_bot - z_top) * t
        w = largura * (0.55 + 0.75 * t)
        row = []
        for j in range(seg_x + 1):
            u = j / seg_x - 0.5
            y = 0.13 + 0.06 * t + 0.05 * math.cos(u * math.pi) * t + 0.02 * math.sin(u * 14) * t
            row.append(bm.verts.new((u * w, y, z)))
        grid.append(row)
    for i in range(seg_y):
        for j in range(seg_x):
            bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    for g in ["spine_03", "spine_01", "pelvis", "thigh_l", "thigh_r"]:
        o.vertex_groups.new(name=g)
    for v in me.vertices:
        t = (z_top - v.co.z) / (z_top - z_bot)
        o.vertex_groups["spine_03"].add([v.index], max(0.0, 1.0 - t * 2.5), "REPLACE")
        o.vertex_groups["spine_01"].add([v.index], max(0.0, 1.0 - abs(t - 0.4) * 2.5), "REPLACE")
        o.vertex_groups["pelvis"].add([v.index], max(0.0, min(1.0, (t - 0.35) * 2.0)) * 0.7, "REPLACE")
        perna = max(0.0, t - 0.6) * 0.6
        o.vertex_groups["thigh_l" if v.co.x > 0 else "thigh_r"].add([v.index], perna, "REPLACE")
    md = o.modifiers.new("arm", "ARMATURE")
    md.object = arm
    sol = o.modifiers.new("esp", "SOLIDIFY")
    sol.thickness = 0.008
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    return o


def ombreira(arm, lado, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1.0)
    o = bpy.context.active_object
    o.name = "ombreira_" + lado
    sx = 1 if lado == "l" else -1
    o.scale = (0.1, 0.11, 0.075)
    o.location = (sx * 0.24, 0.05, 1.5)
    o.rotation_euler = (0, sx * math.radians(-25), 0)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.15], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    sol = o.modifiers.new("esp", "SOLIDIFY")
    sol.thickness = 0.12
    bpy.context.view_layer.update()
    _no_osso(o, arm, "upperarm_" + lado, o.location)
    return o


def cinto(arm, mat, mat_fivela):
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.05, major_segments=40, minor_segments=8)
    o = bpy.context.active_object
    o.name = "cinto"
    o.scale = (0.18, 0.135, 0.5)
    o.location = (0, 0.03, 1.02)
    o.data.materials.append(mat)
    bpy.context.view_layer.update()
    _no_osso(o, arm, "pelvis", o.location)
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    f = bpy.context.active_object
    f.name = "fivela"
    f.scale = (0.045, 0.012, 0.035)
    f.location = (0, -0.108, 1.02)
    f.data.materials.append(mat_fivela)
    bpy.context.view_layer.update()
    _no_osso(f, arm, "pelvis", f.location)
    return o


def cajado(arm, mat_madeira, mat_metal, mat_cristal):
    """Cajado sempre em pé, acompanhando a mão direita (natural em todas as animações)."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.022, depth=1.75)
    s = bpy.context.active_object
    s.name = "cajado"
    s.data.materials.append(mat_madeira)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.06)
    c = bpy.context.active_object
    c.name = "cristal"
    c.scale = (0.8, 0.8, 1.5)
    c.location = (0, 0, 0.95)
    c.data.materials.append(mat_cristal)
    c.parent = s
    for k in range(3):
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.008, depth=0.16)
        g = bpy.context.active_object
        a = k * 2 * math.pi / 3
        g.location = (math.cos(a) * 0.05, math.sin(a) * 0.05, 0.9)
        g.rotation_euler = (math.sin(a) * 0.5, -math.cos(a) * 0.5, 0)
        g.data.materials.append(mat_metal)
        g.parent = s
    luz = bpy.data.lights.new("luz_cristal", "POINT")
    luz.energy = 8.0
    luz.color = tuple(mat_cristal.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value[:3])
    lo = bpy.data.objects.new("luz_cristal", luz)
    bpy.context.scene.collection.objects.link(lo)
    lo.parent = s
    lo.location = (0, 0, 0.95)
    cl = s.constraints.new("COPY_LOCATION")
    cl.target = arm
    cl.subtarget = "hand_r"
    # a mão segura o cajado um pouco abaixo do meio (deslocamento somado à posição da mão)
    cl.use_offset = True
    s.location = (0, -0.03, -0.22)
    return s


def dobras(o, forca=0.012, escala=0.08):
    """Dobras de pano na malha (antes da armação, para acompanhar a animação)."""
    tex = bpy.data.textures.new("dobras_" + o.name, "CLOUDS")
    tex.noise_scale = escala
    tex.noise_depth = 2
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    dp = o.modifiers.new("dobras", "DISPLACE")
    dp.texture = tex
    dp.strength = forca
    dp.mid_level = 0.5
    # a deformação dos ossos tem de vir depois das dobras
    for m in list(o.modifiers):
        if m.type == "ARMATURE":
            nm, ob = m.name, m.object
            o.modifiers.remove(m)
            na = o.modifiers.new(nm, "ARMATURE")
            na.object = ob
    return o


def faixa_barra(arm, mat, z=0.17, rx=0.42, ry=0.33):
    """Faixa bordada na barra da túnica (anel preso ao quadril e às coxas como a saia)."""
    return saia(arm, "barra", mat, z_top=z + 0.06, z_bot=z - 0.005, r_top=(rx * 0.985, ry * 0.985), r_bot=(rx * 1.02, ry * 1.02), seg=28, aneis=2)


def vestir(arm, body, classe):
    p = PALETAS.get(classe, PALETAS["fogo"])
    m_pano = tecido("pano_" + classe, p["pano"])
    m_pano2 = tecido("pano2_" + classe, p["pano2"], 220.0)
    m_couro = couro("couro_" + classe, p["couro"])
    m_metal = metal("metal_" + classe, p["metal"])
    m_cristal = cristal("cristal_" + classe, p["cristal"])
    m_madeira = couro("madeira", (0.16, 0.1, 0.05))
    pecas = []
    # calça escura e botas de couro
    pecas.append(casca(body, "calca", {"thigh_l", "thigh_r", "calf_l", "calf_r", "pelvis"}, 0.5, 0.012, m_pano2))
    pecas.append(casca(body, "botas", {"foot_l", "foot_r", "ball_l", "ball_r", "calf_l", "calf_r"}, 0.4, 0.02, m_couro,
        corta=lambda co: co.z > 0.42))
    # túnica (tronco e mangas que alargam no punho)
    pecas.append(casca(body, "tunica", {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r",
        "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "neck_01"}, 0.4, 0.02, m_pano,
        alarga=lambda co: 0.035 * max(0.0, min(1.0, (abs(co.x) - 0.45) / 0.2)),
        corta=lambda co: co.z > 1.58 or abs(co.x) > 0.68))
    # luvas
    pecas.append(casca(body, "luvas", {"hand_l", "hand_r"} | {f"{d}_{i:02d}_{s}" for d in ["index", "middle", "ring", "pinky", "thumb"] for i in (1, 2, 3) for s in "lr"},
        0.3, 0.006, m_couro))
    # capuz: casca da cabeça bem maior, aberta na frente do rosto e com ponta para trás
    def corta_rosto(co):
        return co.y < -0.02 and 1.6 < co.z < 1.76 and abs(co.x) < 0.075
    def ponta(co):
        return 0.03 + 0.05 * max(0.0, co.y) * 8.0 * max(0.0, co.z - 1.66) * 6.0
    pecas.append(casca(body, "capuz", {"Head", "neck_01"}, 0.5, 0.045, m_pano, alarga=ponta, corta=corta_rosto))
    pecas.append(saia(arm, "saia", m_pano))
    pecas.append(capa(arm, "capa", m_pano2))
    pecas.append(ombreira(arm, "l", m_metal))
    pecas.append(ombreira(arm, "r", m_metal))
    pecas.append(cinto(arm, m_couro, m_metal))
    pecas.append(cajado(arm, m_madeira, m_metal, m_cristal))
    # bandoleira de couro cruzando o peito (casca estreita do tronco)
    pecas.append(casca(body, "bandoleira", {"spine_01", "spine_02", "spine_03", "pelvis", "clavicle_l", "clavicle_r"}, 0.4, 0.04, m_couro,
        corta=lambda co: abs(co.x * 0.9 + (co.z - 1.27)) > 0.035 or co.z > 1.52 or co.z < 1.0))
    pecas.append(faixa_barra(arm, m_metal))
    for i, x in enumerate((-0.12, 0.13)):
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        b = bpy.context.active_object
        b.name = "bolsa%d" % i
        b.scale = (0.05, 0.03, 0.06)
        b.location = (x, -0.1, 0.96)
        b.data.materials.append(m_couro)
        bev = b.modifiers.new("bev", "BEVEL")
        bev.width = 0.01
        bev.segments = 2
        bpy.context.view_layer.update()
        _no_osso(b, arm, "pelvis", b.location)
        pecas.append(b)
    for o in pecas:
        if o.name in ("tunica", "saia", "capa", "capuz"):
            dobras(o, 0.014 if o.name != "capuz" else 0.008)
    return pecas
