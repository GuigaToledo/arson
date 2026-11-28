# Pose dos braços do mago e do que ele segura, quadro a quadro (usado por camadas.py).
# A mão direita segura o cajado/varinha (o objeto é colocado dentro do punho fechado e acompanha
# o braço); a esquerda fica com a palma para cima e o grimório flutua sobre ela; o escudo mímico
# fica em pé no antebraço esquerdo. A mesma pose vale para o corpo e para todas as camadas.
# Eixos do personagem (antes de girar para a direção): frente = -Y, esquerda = +X, cima = +Z.
import bpy, math, re
from mathutils import Vector, Matrix

# comprimento total e distância da ponta de baixo até onde a mão segura (parado, na magia)
HASTES = {"staff": (1.75, 1.02, 1.12), "rod": (0.95, 0.34, 0.34), "wand": (0.42, 0.07, 0.07)}
CAST6 = [0.35, 0.85, 1.0, 1.0, 0.7, 0.3]
CAST8 = [0.55, 0.85, 1.0, 1.0, 1.0, 0.85, 0.65, 0.5]


def _v(x, y, z):
    return Vector((x, y, z))


def _base(eixo, ref):
    """Base ortonormal com o 1º vetor no eixo e o 2º o mais perto possível de ref."""
    a = eixo.normalized()
    b = ref - a * ref.dot(a)
    if b.length < 1e-4:
        b = a.orthogonal()
    b.normalize()
    return Matrix((a, b, a.cross(b))).transposed()


class Maos:
    def __init__(self, R, pecas, estilo):
        self.R = R
        self.arm = R.arm
        self.estilo = estilo
        b = self.arm.data.bones
        self.rest = {x.name: x.matrix_local.copy() for x in b}
        self.mao = {}
        for s in "lr":
            h = b["hand_" + s].head_local
            f = (b["middle_01_" + s].head_local - h).normalized()
            p = f.cross(b["thumb_01_" + s].head_local - h).normalized()
            if p.z > 0:
                p = -p
            self.mao[s] = (f, p)
        bpy.context.view_layer.update()
        self.haste = None
        self.livro = None
        self.escudo = None
        for o in pecas:
            if o.name.endswith("_haste"):
                self.haste = o
                for c in list(o.constraints):
                    o.constraints.remove(c)
            if o.name.endswith("_livro"):
                self.livro = o
        if estilo == "mimic":
            self.escudo = self._agrupar([o for o in pecas if o.type == "MESH"])
        # posição em relação à mão na pose parada: usada na queda (morte), sem forçar o braço
        R.animacao("Idle_Loop")
        R.quadro(1)
        self.rel = {}
        self.aplicar("idle", 0, 8)
        for chave, obj, osso in (("haste", self.haste, "hand_r"), ("escudo", self.escudo, "lowerarm_l")):
            if obj:
                self.rel[chave] = self._osso(osso).inverted() @ obj.matrix_world.copy()

    def _agrupar(self, objs):
        """Junta as peças do escudo num vazio no centro dele (solta dos ossos)."""
        corpo = next(o for o in objs if o.name.endswith("_escudo"))
        centro = corpo.matrix_world.translation.copy()
        g = bpy.data.objects.new("grupo_escudo", None)
        bpy.context.scene.collection.objects.link(g)
        g.location = centro
        mundos = {o.name: o.matrix_world.copy() for o in objs}
        bpy.context.view_layer.update()
        for o in objs:
            o.parent = None
            o.parent_type = "OBJECT"
            o.parent = g
            o.matrix_parent_inverse = Matrix.Translation(-centro)
            o.matrix_basis = mundos[o.name]
        bpy.context.view_layer.update()
        return g

    def _osso(self, nome):
        return self.arm.matrix_world @ self.arm.pose.bones[nome].matrix

    def _por(self, nome, cabeca, rot3):
        pb = self.arm.pose.bones[nome]
        pb.matrix = Matrix.Translation(cabeca) @ (rot3 @ self.rest[nome].to_3x3()).to_4x4()
        bpy.context.view_layer.update()

    def braco(self, s, Q, punho, polo, dedos, palma):
        """IK do braço: punho (deslocamento a partir do ombro), cotovelo para o lado de polo,
        mão com os dedos e a palma nas direções pedidas (eixos do personagem)."""
        up, lo, ha = "upperarm_" + s, "lowerarm_" + s, "hand_" + s
        b = self.arm.data.bones
        S = self.arm.pose.bones[up].head.copy()
        u0 = b[lo].head_local - b[up].head_local
        f0 = b[ha].head_local - b[lo].head_local
        L1, L2 = u0.length, f0.length
        d = Q @ punho
        dist = max(abs(L1 - L2) + 0.01, min(L1 + L2 - 0.004, d.length))
        dn = d.normalized()
        W = S + dn * dist
        a = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
        h = math.sqrt(max(0.0, L1 * L1 - a * a))
        pl = Q @ polo
        perp = (pl - dn * pl.dot(dn)).normalized()
        E = S + dn * a + perp * h
        sinal = 1.0 if s == "l" else -1.0
        # braço: a dobra do cotovelo (na pose em T é para a frente) vai na direção do antebraço
        ru = _base(E - S, W - E) @ _base(u0, _v(0, -1, 0)).inverted()
        self._por(up, S, ru)
        pq = (Q @ palma).normalized()
        dq = (Q @ dedos).normalized()
        rp = self.mao[s][1]
        # antebraço: parte da torção do braço, parte girada para a palma (evita torcer o punho)
        sem = (ru @ f0).rotation_difference(W - E).to_matrix() @ ru
        com = _base(W - E, pq) @ _base(f0, rp).inverted()
        rl = sem.to_quaternion().slerp(com.to_quaternion(), 0.65).to_matrix()
        self._por(lo, self.arm.pose.bones[lo].head.copy(), rl)
        rh = _base(dq, pq) @ _base(self.mao[s][0], rp).inverted()
        self._por(ha, self.arm.pose.bones[ha].head.copy(), rh)
        W = self.arm.pose.bones[ha].head.copy()
        return W, dq, (pq - dq * pq.dot(dq)).normalized()

    def dedos(self, s, angulos, polegar):
        f, p = self.mao[s]
        b = self.arm.data.bones
        for nome in ("index", "middle", "ring", "pinky", "thumb"):
            for i in (1, 2, 3):
                bn = "%s_%02d_%s" % (nome, i, s)
                if bn not in self.rest:
                    continue
                ang = (polegar if nome == "thumb" else angulos)[i - 1]
                dirb = (b[bn].tail_local - b[bn].head_local).normalized()
                prox = "%s_%02d_%s" % (nome, i + 1, s)
                if prox in self.rest:
                    dirb = (b[prox].head_local - b[bn].head_local).normalized()
                eixo = dirb.cross(p).normalized()
                local = self.rest[bn].to_3x3().inverted() @ eixo
                self.arm.pose.bones[bn].matrix_basis = Matrix.Rotation(math.radians(ang), 4, local)
        bpy.context.view_layer.update()

    def aplicar(self, jogo, k, n):
        """Chamar depois de posicionar o quadro da animação."""
        Q = Matrix.Rotation(self.R.pivot.rotation_euler.z, 3, "Z")
        fase = 2 * math.pi * k / max(1, n)
        s, c = math.sin(fase), math.cos(fase)
        if jogo == "death":
            self._queda(Q, k / max(1, n - 1))
            return
        g = 0.0
        if jogo.startswith("cast"):
            tab = CAST6 if n == 6 else CAST8
            g = tab[min(len(tab) - 1, int(k * len(tab) / max(1, n)))]
        # ---- mão direita (cajado)
        punho = _v(-0.13, -0.23, -0.30 + 0.008 * s)
        eixo = _v(-0.16, -0.20, 1.0)
        if jogo in ("walk", "cast_walk"):
            punho = _v(-0.14, -0.23 - 0.06 * s, -0.29 + 0.012 * abs(c))
            eixo = _v(-0.16, -0.24 - 0.10 * s, 1.0)
        elif jogo in ("run", "cast_run"):
            punho = _v(-0.16, -0.22 - 0.09 * s, -0.25 + 0.02 * abs(c))
            eixo = _v(-0.20, -0.38 - 0.12 * s, 1.0)
        elif jogo == "damage":
            punho = _v(-0.15, -0.18 + 0.04 * s, -0.28)
        if g > 0.0:
            # ergue o braço e aponta a ponta do cajado para o alvo
            punho = punho.lerp(_v(-0.03, -0.52, -0.06), g)
            eixo = eixo.normalized().lerp(_v(-0.05, -math.sin(math.radians(66)), math.cos(math.radians(66))), g)
        eixo.normalize()
        frente = _v(0, -1, 0) - eixo * eixo.dot(_v(0, -1, 0))
        frente.normalize()
        palma = eixo.cross(frente)
        W, dq, pq = self.braco("r", Q, punho, _v(-0.7, 0.45, -0.55), frente, palma)
        self.dedos("r", (62, 78, 55), (14, 30, 30))
        if self.haste:
            comp, base0, base1 = HASTES[self.estilo]
            segura = base0 + (base1 - base0) * g
            punhada = W + dq * 0.072 + pq * 0.03
            d = Q @ eixo
            rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
            self.haste.matrix_world = Matrix.Translation(punhada + d * (comp * 0.5 - segura)) @ rot
        # ---- mão esquerda (livro / escudo)
        punho = _v(0.17, -0.25, -0.22 + 0.01 * c)
        if jogo in ("walk", "cast_walk"):
            punho = _v(0.18, -0.24 + 0.04 * s, -0.22)
        elif jogo in ("run", "cast_run"):
            punho = _v(0.19, -0.22 + 0.07 * s, -0.19)
        elif jogo == "damage":
            punho = _v(0.2, -0.18, -0.2)
        if g > 0.0:
            punho = punho.lerp(_v(0.33, -0.24, -0.09), g)
        W, dq, pq = self.braco("l", Q, punho, _v(0.7, 0.45, -0.55), _v(0.42, -0.9, 0.06), _v(0.05, 0.0, 1.0))
        self.dedos("l", (10, 18, 14), (0, 8, 8))
        if self.livro:
            palm = W + dq * 0.07
            alto = 0.19 + 0.022 * s + 0.05 * g
            rot = Q @ Matrix.Rotation(math.radians(14 + 3 * c), 3, "X") @ Matrix.Rotation(math.radians(4 * s), 3, "Y")
            self.livro.matrix_world = Matrix.Translation(palm + _v(0, 0, alto)) @ rot.to_4x4()
        if self.escudo:
            la = self.arm.pose.bones["lowerarm_l"].head
            meio = la.lerp(W, 0.62) + Q @ _v(0.07, -0.05, -0.02)
            normal = (Q @ _v(0.6, -0.8, 0.06)).normalized()
            alto = _v(0, 0, 1) - normal * normal.z
            alto.normalize()
            rot = Matrix((alto, normal.cross(alto), normal)).transposed()
            self.escudo.matrix_world = Matrix.Translation(meio) @ rot.to_4x4()
        bpy.context.view_layer.update()

    def _queda(self, Q, u):
        """Morte: os braços seguem a animação; cajado e escudo acompanham a mão, o livro cai."""
        bpy.context.view_layer.update()
        self.dedos("r", (62, 78, 55), (14, 30, 30))
        if self.haste:
            # continua na mão; na queda vai deitando até ficar no chão, sem atravessá-lo
            d = ((self._osso("hand_r") @ self.rel["haste"]).to_3x3() @ _v(0, 0, 1)).normalized()
            chao = _v(d.x, d.y, 0).normalized()
            d = d.lerp(chao, min(1.0, u * 1.4) ** 2).normalized()
            G = self.arm.pose.bones["hand_r"].head.lerp(self.arm.pose.bones["hand_r"].tail, 0.6)
            G.z = max(G.z, 0.04)
            comp, segura = HASTES[self.estilo][0], HASTES[self.estilo][1]
            z = max(-(G.z - 0.03) / (comp - segura), min((G.z - 0.03) / segura, d.z))
            d = _v(chao.x, chao.y, 0) * math.sqrt(max(0.0, 1.0 - z * z)) + _v(0, 0, z) if z != d.z else d
            rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
            self.haste.matrix_world = Matrix.Translation(G + d * (comp * 0.5 - segura)) @ rot
        if self.escudo:
            self.escudo.matrix_world = self._osso("lowerarm_l") @ self.rel["escudo"]
        if self.livro:
            cai = min(1.0, u * 1.6) ** 2
            p = Q @ _v(0.38, -0.36, 1.42 * (1.0 - cai) + 0.06)
            rot = Q @ Matrix.Rotation(math.radians(14 * (1.0 - cai)), 3, "X") @ Matrix.Rotation(math.radians(30 * math.sin(cai * math.pi)), 3, "Y")
            self.livro.matrix_world = Matrix.Translation(p) @ rot.to_4x4()
        bpy.context.view_layer.update()
