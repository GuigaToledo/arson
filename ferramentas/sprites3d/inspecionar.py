# Grupos de peso e medidas do corpo (para modelar as roupas por cima).
# uso: blender -b --python ferramentas/sprites3d/inspecionar.py
import bpy

Q = r"E:\Claude Jobs\arson\legado\3d-roupas-nao-publicado\q"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=Q + r"\Superhero_Male.gltf")
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
body = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("SuperHero")][0]
print("GRUPOS", [g.name for g in body.vertex_groups])
bpy.context.view_layer.update()
ws = [body.matrix_world @ v.co for v in body.data.vertices]
print("ALTURA", min(w.z for w in ws), max(w.z for w in ws), "LARGURA", min(w.x for w in ws), max(w.x for w in ws), "PROF", min(w.y for w in ws), max(w.y for w in ws))
for b in ["pelvis", "spine_03", "neck_01", "Head", "clavicle_l", "upperarm_l", "hand_r", "thigh_l", "calf_l", "foot_l"]:
    bb = arm.data.bones.get(b)
    if bb:
        print("OSSO", b, tuple(round(c, 3) for c in (arm.matrix_world @ bb.head_local)), tuple(round(c, 3) for c in (arm.matrix_world @ bb.tail_local)))
print("ESCALA_ARM", tuple(arm.scale), tuple(arm.rotation_euler))
