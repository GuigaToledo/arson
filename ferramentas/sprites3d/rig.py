# Corpo Quaternius + animações (mesma conversão de render.py), para outros scripts usarem.
# uso: import rig; R = rig.carregar("Superhero_Male"); R.animacao("Idle_Loop"); R.quadro(10)
import bpy, os, json, struct
from mathutils import Quaternion

Q = r"E:\Claude Jobs\arson\legado\3d-roupas-nao-publicado\q"


def _glb_nodes(path):
    with open(path, "rb") as f:
        data = f.read()
    ln = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + ln].decode("utf-8"))
    return {n.get("name", ""): n for n in js.get("nodes", [])}


class Rig:
    def __init__(self, model):
        bpy.ops.import_scene.gltf(filepath=os.path.join(Q, model + ".gltf"))
        self.arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
        self.body = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("SuperHero")][0]
        for o in bpy.data.objects:
            if o.name == "Icosphere":
                o.hide_render = True
        n0 = set(bpy.data.objects.keys())
        bpy.ops.import_scene.gltf(filepath=os.path.join(Q, "anims.glb"))
        self.empties = {o.name: o for o in bpy.data.objects if o.name not in n0 and o.type == "EMPTY"}
        self.root_e = [e for n, e in self.empties.items() if n.startswith("Armature")][0]
        for e in self.empties.values():
            if e.animation_data:
                e.animation_data.action = None
        for name, nd in _glb_nodes(os.path.join(Q, "anims.glb")).items():
            e = self.empties.get(name)
            if e is None or e == self.root_e:
                continue
            t = nd.get("translation", [0, 0, 0])
            r = nd.get("rotation", [0, 0, 0, 1])
            s = nd.get("scale", [1, 1, 1])
            e.rotation_mode = "QUATERNION"
            e.location = (t[0], -t[2], t[1])
            e.rotation_quaternion = Quaternion((r[3], r[0], -r[2], r[1]))
            e.scale = (s[0], s[2], s[1])
        self.pivot = bpy.data.objects.new("pivo", None)
        bpy.context.scene.collection.objects.link(self.pivot)
        self.root_e.parent = self.pivot
        bpy.context.view_layer.update()
        self.off = {}
        for b in self.arm.data.bones:
            e = self.empties.get(b.name)
            if e is not None:
                self.off[b.name] = e.matrix_world.inverted() @ (self.arm.matrix_world @ b.matrix_local)
        self.order = sorted(self.arm.data.bones, key=lambda b: len(b.parent_recursive))

    def pose(self):
        bpy.context.view_layer.update()
        arm = self.arm
        inv_arm = arm.matrix_world.inverted()
        want = {}
        for b in self.order:
            e = self.empties.get(b.name)
            if e is not None and b.name in self.off:
                want[b.name] = inv_arm @ e.matrix_world @ self.off[b.name]
            elif b.parent and b.parent.name in want:
                want[b.name] = want[b.parent.name] @ b.parent.matrix_local.inverted() @ b.matrix_local
            else:
                want[b.name] = b.matrix_local.copy()
        for b in self.order:
            pb = arm.pose.bones[b.name]
            if b.parent:
                rest_rel = b.parent.matrix_local.inverted() @ b.matrix_local
                pb.matrix_basis = rest_rel.inverted() @ want[b.parent.name].inverted() @ want[b.name]
            else:
                pb.matrix_basis = b.matrix_local.inverted() @ want[b.name]
        bpy.context.view_layer.update()

    def animacao(self, nome):
        fim = 1
        for name, e in self.empties.items():
            act = bpy.data.actions.get(nome + "_" + name)
            if e.animation_data is None:
                e.animation_data_create()
            slot = None
            if act is None:
                # Blender 5: uma ação só por animação, com um "slot" por objeto
                junta = bpy.data.actions.get(nome)
                if junta:
                    slot = next((s for s in junta.slots if s.identifier == "OB" + name), None)
                    act = junta if slot else None
            e.animation_data.action = act
            if slot:
                e.animation_data.action_slot = slot
            if act:
                fim = max(fim, int(act.frame_range[1]))
        return fim

    def quadro(self, f):
        bpy.context.scene.frame_set(f)
        self.pose()


def carregar(model="Superhero_Male"):
    return Rig(model)
