# Itens do jogo modelados em 3D por cima do corpo Quaternius (mesmo esqueleto das animações).
# Cada estilo (placeholder_style do .tres) vira uma ou mais peças que seguem os ossos.
# Usado para os ícones (icones.py) e para as camadas vestidas nos personagens (camadas.py).
import bpy, bmesh, math, re, os, glob
import roupas
from roupas import casca, saia, capa, dobras, tecido, metal, cristal
from roupas import _no_osso as _no_osso0
from roupas import couro as _couro0


def _no_osso(obj, arm, osso, pos=None):
    bpy.context.view_layer.update()
    _no_osso0(obj, arm, osso, pos)


def couro(name, cor):
    """Couro mais liso que o das roupas (nos itens pequenos o relevo grosso parecia pedra)."""
    m = _couro0(name, cor)
    for nd in m.node_tree.nodes:
        if nd.type == "BUMP":
            nd.inputs["Strength"].default_value = 0.12
        if nd.type == "TEX_NOISE":
            nd.inputs["Scale"].default_value = 110.0
    return m

ITENS = r"E:\Claude Jobs\arson\godot\data\items"


def lin(c):
    """Cor do Godot (sRGB) para a cor linear do Blender."""
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c[:3])


def ler_itens():
    """id -> {estilo, cor, acento, brilho, slot, nome} lido dos .tres."""
    out = {}
    for f in sorted(glob.glob(os.path.join(ITENS, "*.tres"))):
        t = open(f, encoding="utf-8").read()

        def cor(campo, padrao):
            m = re.search(campo + r" = Color\(([^)]*)\)", t)
            return tuple(float(x) for x in m.group(1).split(",")) if m else padrao
        idm = re.search(r'id = &"([^"]+)"', t)
        st = re.search(r'placeholder_style = &"([^"]+)"', t)
        if not idm or not st:
            continue
        gl = re.search(r"glow = ([0-9.]+)", t)
        sl = re.search(r"slot = (\d+)", t)
        nm = re.search(r'display_name = "([^"]*)"', t)
        out[idm.group(1)] = dict(estilo=st.group(1), cor=cor("placeholder_color", (0.3, 0.3, 0.3, 1)),
            acento=cor("placeholder_accent", (1, 0.5, 0.1, 1)), brilho=float(gl.group(1)) if gl else 0.0,
            slot=int(sl.group(1)) if sl else 1, nome=nm.group(1) if nm else idm.group(1))
    return out


DEDOS = {f"{d}_{i:02d}_{s}" for d in ["index", "middle", "ring", "pinky", "thumb"] for i in (1, 2, 3) for s in "lr"}


def _osso_pos(arm, osso, cauda=False):
    b = arm.data.bones[osso]
    return arm.matrix_world @ (b.tail_local if cauda else b.head_local)


def _malha(nome, bm, mat):
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    return o


def _tubo(nome, pontos, mat):
    """Galho curvo afinando: pontos = [((x, y, z), raio), ...]."""
    cu = bpy.data.curves.new(nome, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 1.0
    cu.bevel_resolution = 3
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(pontos) - 1)
    for p, (co, r) in zip(sp.points, pontos):
        p.co = (co[0], co[1], co[2], 1.0)
        p.radius = r
    tmp = bpy.data.objects.new(nome + "_c", cu)
    bpy.context.scene.collection.objects.link(tmp)
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    me.materials.clear()
    me.materials.append(mat)
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    for f in me.polygons:
        f.use_smooth = True
    return o


def _torno(nome, perfil, mat, seg=32):
    """Sólido de revolução em volta de Z: perfil = [(raio, z), ...]."""
    bm = bmesh.new()
    rings = []
    for r, z in perfil:
        rings.append([bm.verts.new((math.cos(2 * math.pi * j / seg) * r, math.sin(2 * math.pi * j / seg) * r, z)) for j in range(seg)])
    for i in range(len(rings) - 1):
        for j in range(seg):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % seg], rings[i + 1][(j + 1) % seg], rings[i + 1][j]))
    return _malha(nome, bm, mat)


def _cubo(nome, tam, pos, mat, bevel=0.006):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    o = bpy.context.active_object
    o.name = nome
    o.scale = tam
    o.location = pos
    o.data.materials.append(mat)
    if bevel:
        b = o.modifiers.new("bev", "BEVEL")
        b.width = bevel
        b.segments = 2
    return o


def _esfera(nome, r, pos, mat, esc=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=r)
    o = bpy.context.active_object
    o.name = nome
    o.location = pos
    o.scale = esc
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def _toro(nome, R, r, pos, mat, esc=(1, 1, 1), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=36, minor_segments=10)
    o = bpy.context.active_object
    o.name = nome
    o.location = pos
    o.scale = esc
    o.rotation_euler = rot
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def _segue_mao(obj, arm, mao, offset):
    """Objeto em pé acompanhando a posição da mão (cajados, varinhas)."""
    cl = obj.constraints.new("COPY_LOCATION")
    cl.target = arm
    cl.subtarget = mao
    cl.use_offset = True
    obj.location = offset


def _grosso(o, esp=0.008):
    s = o.modifiers.new("esp", "SOLIDIFY")
    s.thickness = esp
    s.offset = 1.0
    return o


def construir(arm, body, item_id, it):
    """Peças 3D de um item. Devolve a lista de objetos (sem o corpo)."""
    e = it["estilo"]
    c = lin(it["cor"])
    a = lin(it["acento"])
    tag = item_id
    m_pano = tecido("pano_" + tag, c)
    m_couro = couro("couro_" + tag, c)
    m_metal = metal("metal_" + tag, tuple(min(1.0, x * 1.6 + 0.05) for x in c))
    m_ouro = metal("ouro_" + tag, a)
    m_gema = cristal("gema_" + tag, a)
    if it["brilho"] <= 0.0:
        bs = m_gema.node_tree.nodes["Principled BSDF"]
        bs.inputs["Emission Strength"].default_value = 0.6
    pecas = []
    cabeca = {"Head", "neck_01"}
    if e == "hood":
        def corta_rosto(co):
            return co.y < -0.02 and 1.6 < co.z < 1.76 and abs(co.x) < 0.075
        def ponta(co):
            return 0.03 + 0.05 * max(0.0, co.y) * 8.0 * max(0.0, co.z - 1.66) * 6.0
        o = _grosso(casca(body, tag + "_capuz", cabeca, 0.5, 0.045, m_pano, alarga=ponta, corta=corta_rosto))
        dobras(o, 0.008)
        pecas.append(o)
        # gola do capuz caindo sobre os ombros
        g = _grosso(casca(body, tag + "_gola", {"neck_01", "spine_03", "clavicle_l", "clavicle_r"}, 0.3, 0.035, m_pano,
            corta=lambda co: co.z < 1.36 or co.z > 1.6 or abs(co.x) > 0.24))
        dobras(g, 0.01)
        pecas.append(g)
    elif e in ("helm",):
        o = _grosso(casca(body, tag + "_elmo", {"Head"}, 0.5, 0.03, m_metal,
            corta=lambda co: (co.y < -0.03 and 1.6 < co.z < 1.73 and abs(co.x) < 0.06) or co.z < 1.6), 0.012)
        pecas.append(o)
        n = _cubo(tag + "_nasal", (0.016, 0.012, 0.09), (0, -0.115, 1.66), m_metal)
        _no_osso(n, arm, "Head", n.location)
        pecas.append(n)
        hz = _osso_pos(arm, "Head").z + 0.035
        cr = _toro(tag + "_aro", 0.118, 0.012, (0, 0.012, hz), m_ouro, esc=(1, 1.12, 1))
        _no_osso(cr, arm, "Head", cr.location)
        pecas.append(cr)
    elif e in ("wizardhat",):
        topo = _osso_pos(arm, "Head").z + 0.13
        perfil = [(0.0, topo - 0.02), (0.24, topo - 0.03), (0.25, topo - 0.015), (0.11, topo - 0.005),
                  (0.1, topo + 0.06), (0.075, topo + 0.16), (0.045, topo + 0.27), (0.015, topo + 0.36), (0.001, topo + 0.4)]
        o = _torno(tag + "_chapeu", perfil, m_pano)
        o.location.y = 0.02
        # ponta caída para trás
        for v in o.data.vertices:
            k = max(0.0, v.co.z - (topo + 0.12)) / 0.28
            v.co.y += 0.12 * k * k
        pecas.append(o)
        f = _torno(tag + "_faixa", [(0.104, topo - 0.004), (0.1, topo + 0.035)], m_ouro)
        f.location.y = 0.02
        pecas.append(f)
        for p in (o, f):
            bpy.context.view_layer.update()
            _no_osso(p, arm, "Head", p.location)
    elif e == "circlet":
        hz = _osso_pos(arm, "Head").z + 0.085
        o = _toro(tag + "_diadema", 0.098, 0.009, (0, 0.012, hz), m_ouro, esc=(1, 1.12, 1))
        g = _esfera(tag + "_gema", 0.018, (0, -0.1, hz + 0.01), m_gema, (1, 0.6, 1.3))
        for p in (o, g):
            bpy.context.view_layer.update()
            _no_osso(p, arm, "Head", p.location)
            pecas.append(p)
    elif e == "turban":
        o = _grosso(casca(body, tag + "_turbante", {"Head"}, 0.5, 0.06, m_pano, corta=lambda co: co.z < 1.74,
            alarga=lambda co: 0.025 * max(0.0, co.z - 1.8) * 10.0))
        dobras(o, 0.012, 0.05)
        pecas.append(o)
        hz = _osso_pos(arm, "Head").z + 0.06
        for k in range(2):
            t = _toro(tag + "_volta%d" % k, 0.115 - k * 0.01, 0.022, (0, 0.012, hz + k * 0.045), m_pano, esc=(1, 1.1, 1), rot=(0.15 * (k - 0.5), 0, 0))
            bpy.context.view_layer.update()
            _no_osso(t, arm, "Head", t.location)
            pecas.append(t)
        g = _esfera(tag + "_gema", 0.02, (0, -0.125, hz + 0.03), m_gema)
        bpy.context.view_layer.update()
        _no_osso(g, arm, "Head", g.location)
        pecas.append(g)
    elif e in ("robe",):
        o = _grosso(casca(body, tag + "_tunica", {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r",
            "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "neck_01"}, 0.4, 0.02, m_pano,
            alarga=lambda co: 0.035 * max(0.0, min(1.0, (abs(co.x) - 0.45) / 0.2)),
            corta=lambda co: co.z > 1.58 or abs(co.x) > 0.68))
        dobras(o, 0.014)
        s = saia(arm, tag + "_saia", m_pano)
        dobras(s, 0.014)
        pecas += [o, s, roupas.faixa_barra(arm, m_ouro), roupas.cinto(arm, m_couro if sum(c) > 0.3 else couro("cinto_" + tag, (0.08, 0.05, 0.03)), m_ouro)]
    elif e in ("vest", "apron"):
        frente = e == "apron"
        o = _grosso(casca(body, tag + "_colete", {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"}, 0.45, 0.024,
            m_pano if frente else m_couro, corta=lambda co: co.z > 1.52 or abs(co.x) > 0.24 or co.z < 0.9 or (frente and co.y > 0.0)), 0.01)
        pecas.append(o)
        if not frente:
            for k in range(4):
                b = _esfera(tag + "_botao%d" % k, 0.009, (0, -0.135, 1.42 - k * 0.1), m_ouro)
                bpy.context.view_layer.update()
                _no_osso(b, arm, "spine_02", b.location)
                pecas.append(b)
    elif e in ("cape", "wolfcape"):
        o = capa(arm, tag + "_capa", m_pano)
        dobras(o, 0.014)
        pecas.append(o)
        fe = _esfera(tag + "_fecho", 0.022, (0, -0.12, 1.47), m_ouro, (1, 0.5, 1))
        bpy.context.view_layer.update()
        _no_osso(fe, arm, "spine_03", fe.location)
        pecas.append(fe)
        if e == "wolfcape":
            m_pelo = tecido("pelo_" + tag, tuple(x * 0.7 for x in c), 60.0)
            g = _toro(tag + "_gola", 0.15, 0.05, (0, 0.03, 1.5), m_pelo, esc=(1.05, 0.85, 0.7))
            bpy.context.view_layer.update()
            _no_osso(g, arm, "spine_03", g.location)
            dobras(g, 0.03, 0.03)
            pecas.append(g)
    elif e == "pauldron":
        for lado in "lr":
            pecas.append(roupas.ombreira(arm, lado, m_metal))
            sx = 1 if lado == "l" else -1
            r = _toro(tag + "_borda_" + lado, 0.085, 0.01, (sx * 0.25, 0.05, 1.49), m_ouro, esc=(1, 1.1, 1), rot=(0, sx * math.radians(-25), 0))
            bpy.context.view_layer.update()
            _no_osso(r, arm, "upperarm_" + lado, r.location)
            pecas.append(r)
    elif e == "gloves":
        pecas.append(_grosso(casca(body, tag + "_luvas", {"hand_l", "hand_r"} | DEDOS, 0.3, 0.006, m_couro), 0.004))
        pecas.append(_grosso(casca(body, tag + "_punho", {"lowerarm_l", "lowerarm_r", "hand_l", "hand_r"}, 0.3, 0.02, m_couro,
            corta=lambda co: abs(co.x) < 0.62 or abs(co.x) > 0.72), 0.006))
    elif e == "pants":
        pecas.append(_grosso(casca(body, tag + "_calca", {"thigh_l", "thigh_r", "calf_l", "calf_r", "pelvis"}, 0.5, 0.014, m_pano,
            corta=lambda co: co.z > 1.05), 0.006))
    elif e in ("kilt", "wolfskirt"):
        s = saia(arm, tag + "_saia", m_pano, z_top=1.02, z_bot=0.55, r_bot=(0.3, 0.24), aneis=6)
        dobras(s, 0.012)
        pecas += [s, roupas.cinto(arm, m_couro if e == "kilt" else couro("cinto_" + tag, (0.06, 0.03, 0.02)), m_ouro)]
    elif e in ("boots", "sandals"):
        alto = 0.42 if e == "boots" else 0.1
        pecas.append(_grosso(casca(body, tag + "_botas", {"foot_l", "foot_r", "ball_l", "ball_r", "calf_l", "calf_r"}, 0.4, 0.02 if e == "boots" else 0.01, m_couro,
            corta=lambda co: co.z > alto), 0.006))
        if e == "boots":
            for lado, x in (("l", 0.1), ("r", -0.1)):
                f = _toro(tag + "_dobra_" + lado, 0.065, 0.014, (x, 0.02, alto - 0.02), m_couro, esc=(1, 1.1, 1))
                bpy.context.view_layer.update()
                _no_osso(f, arm, "calf_" + lado, f.location)
                pecas.append(f)
    elif e in ("staff", "rod", "wand"):
        m_mad = couro("madeira_" + tag, c)
        comp = {"staff": 1.75, "rod": 0.95, "wand": 0.42}[e]
        raio = {"staff": 0.022, "rod": 0.018, "wand": 0.011}[e]
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=raio, depth=comp)
        s = bpy.context.active_object
        s.name = tag + "_haste"
        s.data.materials.append(m_mad)
        top = comp * 0.5
        gr = {"staff": 0.075, "rod": 0.055, "wand": 0.022}[e]
        alt = top + gr * (1.45 if e == "staff" else 0.9)
        g = _esfera(tag + "_cristal", gr, (0, 0, alt), m_gema, (1, 1, 1.15) if e != "wand" else (0.8, 0.8, 1.5))
        g.parent = s
        if e == "staff":
            # garras curvas abraçando o orbe, como uma coroa de galhos
            for k, (an, alto) in enumerate([(0.0, 1.0), (math.pi, 1.0), (math.pi * 0.5, 0.7), (math.pi * 1.5, 0.7)]):
                cx, cy = math.cos(an), math.sin(an)
                pts = [(0.012, -0.03, 0.026), (0.095, 0.045, 0.023), (0.132, 0.13, 0.019), (0.112, 0.215 * alto, 0.014), (0.05, 0.285 * alto, 0.003)]
                gg = _tubo(tag + "_garra%d" % k, [((cx * r, cy * r, top + z), esp) for r, z, esp in pts], m_ouro if k > 1 else m_mad)
                gg.parent = s
                pecas.append(gg)
                esp = _tubo(tag + "_espinho%d" % k, [((cx * 0.118, cy * 0.118, top + 0.12), 0.011), ((cx * 0.185, cy * 0.185, top + 0.17 * alto), 0.001)], m_mad)
                esp.parent = s
                pecas.append(esp)
        elif e == "rod":
            for k in range(3):
                bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.008, depth=gr * 2.6)
                gg = bpy.context.active_object
                an = k * 2 * math.pi / 3
                gg.location = (math.cos(an) * gr * 0.85, math.sin(an) * gr * 0.85, top + gr * 0.6)
                gg.rotation_euler = (math.sin(an) * 0.5, -math.cos(an) * 0.5, 0)
                gg.data.materials.append(m_ouro)
                gg.parent = s
                pecas.append(gg)
        an2 = _torno(tag + "_anel", [(raio * 1.5, top - 0.03), (raio * 1.6, top), (raio * 1.2, top + 0.02)], m_ouro, 16)
        an2.parent = s
        pecas += [s, g, an2]
        if it["brilho"] > 0:
            luz = bpy.data.lights.new("luz_" + tag, "POINT")
            luz.energy = 6.0 * it["brilho"]
            luz.color = a
            lo = bpy.data.objects.new("luz_" + tag, luz)
            bpy.context.scene.collection.objects.link(lo)
            lo.parent = s
            lo.location = (0, 0, top + gr)
            pecas.append(lo)
        # na mão direita: o cajado fica em pé com a mão um pouco abaixo do meio
        _segue_mao(s, arm, "hand_r", {"staff": (0, -0.03, -0.22), "rod": (0, -0.03, 0.18), "wand": (0, -0.04, 0.1)}[e])
    elif e == "book":
        # grimório ABERTO em V: lombada embaixo ao longo da frente, capas subindo para os lados,
        # folhas soltas e um selo brilhando. Tudo preso a um vazio; maos.py o põe sobre a palma.
        m_pap = couro("papel_" + tag, (0.72, 0.66, 0.52))
        raiz = bpy.data.objects.new(tag + "_livro", None)
        bpy.context.scene.collection.objects.link(raiz)
        raiz.location = (0.4, -0.34, 1.3)
        lv = []
        ab = math.radians(27)
        for k, sx in enumerate((-1, 1)):
            gira = (0, -sx * ab, 0)

            def no_lado(x, y, z):
                return (sx * (x * math.cos(ab)) - sx * z * math.sin(ab), y, x * math.sin(ab) + z * math.cos(ab))
            cp = _cubo(tag + "_capa%d" % k, (0.215, 0.31, 0.022), no_lado(0.108, 0, 0), m_couro, 0.004)
            fl = _cubo(tag + "_folhas%d" % k, (0.19, 0.28, 0.034), no_lado(0.1, 0, 0.027), m_pap, 0.006)
            cp.rotation_euler = fl.rotation_euler = gira
            lv += [cp, fl]
            for j, y in enumerate((-0.148, 0.148)):
                q = _cubo(tag + "_canto%d%d" % (k, j), (0.045, 0.028, 0.034), no_lado(0.198, y, 0), m_ouro, 0.003)
                q.rotation_euler = gira
                lv.append(q)
            borda = _cubo(tag + "_filete%d" % k, (0.012, 0.31, 0.03), no_lado(0.215, 0, 0), m_ouro, 0.002)
            borda.rotation_euler = gira
            selo = _toro(tag + "_selo%d" % k, 0.048, 0.007, no_lado(0.11, 0, -0.016), m_gema, rot=gira)
            runa = _toro(tag + "_runa%d" % k, 0.04, 0.005, no_lado(0.1, 0.0, 0.047), m_gema, rot=gira)
            folha = _cubo(tag + "_solta%d" % k, (0.13, 0.24, 0.004), (sx * 0.045, 0, 0.115), m_pap, 0.001)
            folha.rotation_euler = (0, -sx * math.radians(64), 0)
            lv += [borda, selo, runa, folha]
        lomb = _cubo(tag + "_lombada", (0.04, 0.32, 0.045), (0, 0, -0.004), m_ouro, 0.006)
        nucleo = _esfera(tag + "_nucleo", 0.026, (0, 0, 0.2), m_gema)
        lv += [lomb, nucleo]
        for k, (x, y, z) in enumerate([(-0.1, -0.06, 0.2), (0.08, 0.08, 0.23), (0.02, -0.11, 0.27), (-0.05, 0.1, 0.29)]):
            q = _cubo(tag + "_glifo%d" % k, (0.022, 0.008, 0.03), (x, y, z), m_gema, 0.001)
            lv.append(q)
        for p in lv:
            p.parent = raiz
            pecas.append(p)
        pecas.append(raiz)
    elif e == "mimic":
        # escudo mímico preso ao antebraço esquerdo: na pose de descanso (braço em T) fica por cima do
        # antebraço, deitado; com o braço caído, fica em pé do lado de fora, segurado pela mão
        hp = _osso_pos(arm, "hand_l")
        la = _osso_pos(arm, "lowerarm_l")
        cx = (hp.x + la.x) * 0.5 + 0.02
        cz = (hp.z + la.z) * 0.5 + 0.075
        corpo = _cubo(tag + "_escudo", (0.45, 0.37, 0.05), (cx, hp.y, cz), m_couro, 0.02)
        borda = _cubo(tag + "_borda", (0.47, 0.39, 0.035), (cx, hp.y, cz - 0.004), m_ouro, 0.01)
        boca = _cubo(tag + "_boca", (0.26, 0.035, 0.02), (cx - 0.03, hp.y, cz + 0.03), couro("boca_" + tag, (0.05, 0.01, 0.01)), 0.004)
        dentes = [_cubo(tag + "_dente%d" % k, (0.018, 0.016, 0.02), (cx - 0.14 + k * 0.04, hp.y + 0.02 * (1 if k % 2 else -1), cz + 0.042), m_ouro, 0.002) for k in range(7)]
        olhos = [_esfera(tag + "_olho%d" % k, 0.022, (cx + 0.1, hp.y + sy * 0.07, cz + 0.035), m_gema, (1, 1, 0.5)) for k, sy in enumerate((-1, 1))]
        for p in [corpo, borda, boca] + dentes + olhos:
            bpy.context.view_layer.update()
            _no_osso(p, arm, "lowerarm_l", p.location)
            pecas.append(p)
    elif e == "amulet":
        n = _osso_pos(arm, "neck_01")
        pend = _toro(tag + "_aro", 0.026, 0.006, (0, n.y - 0.135, n.z - 0.16), m_ouro, rot=(math.radians(80), 0, 0))
        gema = _esfera(tag + "_gema", 0.022, (0, n.y - 0.137, n.z - 0.16), m_gema, (1, 0.6, 1))
        cords = []
        for k, sx in enumerate((-1, 1)):
            a0 = (sx * 0.07, n.y + 0.01, n.z - 0.02)
            a1 = (sx * 0.012, n.y - 0.13, n.z - 0.135)
            mid = tuple((x + y) * 0.5 for x, y in zip(a0, a1))
            dv = [y - x for x, y in zip(a0, a1)]
            ln = math.sqrt(sum(x * x for x in dv))
            bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.003, depth=ln, location=mid)
            cy = bpy.context.active_object
            cy.name = tag + "_corrente%d" % k
            cy.rotation_mode = "QUATERNION"
            from mathutils import Vector as _V
            cy.rotation_quaternion = _V(dv).to_track_quat("Z", "Y")
            cy.data.materials.append(m_ouro)
            cords.append(cy)
        for p in cords + [pend, gema]:
            bpy.context.view_layer.update()
            _no_osso(p, arm, "spine_03", p.location)
            pecas.append(p)
    elif e == "ring":
        dp = _osso_pos(arm, "ring_01_r")
        r = _toro(tag + "_anel", 0.011, 0.0028, dp, m_ouro, rot=(math.radians(75), 0, math.radians(20)))
        g = _esfera(tag + "_gema", 0.0055, (dp.x, dp.y, dp.z + 0.0135), m_gema)
        for p in (r, g):
            bpy.context.view_layer.update()
            _no_osso(p, arm, "ring_01_r", p.location)
            pecas.append(p)
    return pecas
