"""Rig e animação automáticos para um modelo 3D parado (gerado por IA).
Roda no Blender sem janela:
  blender -b -P ferramentas/blender_autorig.py -- <modelo.glb> <arte/personagens/nome> [rotacao_graus]

1. junta as malhas, reduz polígonos, põe os pés no chão e altura 1,8
2. cria um esqueleto humanoide pelas proporções do corpo
3. pesos por proximidade de cada osso (sem depender do "bone heat", que falha em malhas de IA)
4. cria animações: idle, walk, run, cast, attack, damage
5. exporta modelo.glb + config.json para a esteira de sprites
"""
import bpy, sys, os, json, math
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT = args[0], args[1]
ROT = float(args[2]) if len(args) > 2 else 0.0
os.makedirs(OUT, exist_ok=True)
H = 1.8

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
if SRC.lower().endswith(('.glb', '.gltf')):
    bpy.ops.import_scene.gltf(filepath=SRC)
else:
    bpy.ops.wm.obj_import(filepath=SRC)

meshes = [o for o in sc.objects if o.type == 'MESH']
for o in meshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in list(sc.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = 'Corpo'
body.rotation_euler.z += math.radians(ROT)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# remove "chão" gerado por engano (placa fina embaixo com muitos vértices)
import bmesh
bm = bmesh.new()
bm.from_mesh(body.data)
zs = [v.co.z for v in bm.verts]
z0, z1 = min(zs), max(zs)
cut = z0 + 0.04 * (z1 - z0)
low = [v for v in bm.verts if v.co.z < cut]
if len(low) > 0.25 * len(bm.verts):
    bmesh.ops.delete(bm, geom=low, context='VERTS')
    print('chão removido:', len(low), 'vértices')
bm.to_mesh(body.data)
bm.free()

faces = len(body.data.polygons)
if faces > 40000:
    m = body.modifiers.new('Reduzir', 'DECIMATE')
    m.ratio = 40000 / faces
    bpy.ops.object.modifier_apply(modifier=m.name)
print('faces:', faces, '->', len(body.data.polygons))

# normaliza: pés em z=0, altura H, centro do quadril na origem
n = len(body.data.vertices)
P = np.empty(n * 3)
body.data.vertices.foreach_get('co', P)
P = P.reshape(n, 3)
zmin, zmax = P[:, 2].min(), P[:, 2].max()
P = (P - [0, 0, zmin]) * (H / (zmax - zmin))
band = P[(P[:, 2] > 0.4 * H) & (P[:, 2] < 0.6 * H)]
cx, cy = np.median(band[:, 0]), np.median(band[:, 1])
P -= [cx, cy, 0]
body.data.vertices.foreach_set('co', P.ravel())
body.data.update()

# esqueleto (personagem olhando para -Y, esquerda dele = +X)
arm_data = bpy.data.armatures.new('Rig')
arm = bpy.data.objects.new('Rig', arm_data)
sc.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
B = {}
spec = [
    ('hips', (0, 0, .50), (0, 0, .58), None),
    ('spine', (0, 0, .58), (0, 0, .70), 'hips'),
    ('chest', (0, 0, .70), (0, 0, .80), 'spine'),
    ('neck', (0, 0, .80), (0, 0, .87), 'chest'),
    ('head', (0, 0, .87), (0, 0, 1.0), 'neck'),
]
for s, g in (('L', 1), ('R', -1)):
    spec += [
        ('shoulder.' + s, (g * .03, 0, .79), (g * .11, 0, .80), 'chest'),
        ('upper_arm.' + s, (g * .11, 0, .80), (g * .15, 0, .63), 'shoulder.' + s),
        ('forearm.' + s, (g * .15, 0, .63), (g * .17, -.02, .48), 'upper_arm.' + s),
        ('hand.' + s, (g * .17, -.02, .48), (g * .175, -.03, .42), 'forearm.' + s),
        ('thigh.' + s, (g * .06, 0, .50), (g * .065, -.01, .27), 'hips'),
        ('shin.' + s, (g * .065, -.01, .27), (g * .07, 0, .05), 'thigh.' + s),
        ('foot.' + s, (g * .07, 0, .05), (g * .07, -.08, .01), 'shin.' + s),
    ]
for name, h, t, parent in spec:
    b = arm_data.edit_bones.new(name)
    b.head = Vector(h) * H
    b.tail = Vector(t) * H
    b.align_roll(Vector((0, 0, 1)) if name.startswith('foot') else Vector((0, -1, 0)))
    if parent:
        b.parent = arm_data.edit_bones[parent]
    B[name] = (np.array(h) * H, np.array(t) * H)
bpy.ops.object.mode_set(mode='OBJECT')

# pesos por proximidade
names = list(B.keys())
D = np.empty((n, len(names)))
for j, nm in enumerate(names):
    a, b = B[nm]
    ab = b - a
    t = np.clip(((P - a) @ ab) / (ab @ ab), 0, 1)
    D[:, j] = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
    if any(k in nm for k in ('arm', 'hand', 'shoulder')):
        D[np.abs(P[:, 0]) < 0.09 * H, j] *= 3.0
    if any(k in nm for k in ('thigh', 'shin', 'foot')):
        D[P[:, 2] > 0.55 * H, j] *= 3.0
        D[P[:, 1] > 0.06 * H, j] *= 2.5  # capa atrás das pernas
    if nm in ('head', 'neck'):
        D[P[:, 2] < 0.78 * H, j] *= 3.0
W = 1.0 / (D ** 4 + 1e-6)
top = np.argsort(-W, axis=1)[:, :3]
rows = np.arange(n)[:, None]
keep = np.zeros_like(W)
keep[rows, top] = W[rows, top]
keep /= keep.sum(axis=1, keepdims=True)
for j, nm in enumerate(names):
    vg = body.vertex_groups.new(name=nm)
    idx = np.nonzero(keep[:, j] > 0.01)[0]
    for i in idx:
        vg.add([int(i)], float(keep[i, j]), 'REPLACE')
mod = body.modifiers.new('Esqueleto', 'ARMATURE')
mod.object = arm
body.parent = arm

# animações (rotação X positiva = para frente, em todos os ossos)
for pb in arm.pose.bones:
    pb.rotation_mode = 'XYZ'
arm.animation_data_create()
R = math.radians


def make(name, frames, fn, loop=True):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    for f in range(0, frames + 1, 2):
        for pb in arm.pose.bones:
            pb.rotation_euler = (0, 0, 0)
            pb.location = (0, 0, 0)
        fn((f % frames) / frames if loop else f / frames, f)
        for pb in arm.pose.bones:
            pb.keyframe_insert('rotation_euler', frame=f)
            pb.keyframe_insert('location', frame=f)
    print('animação:', name)


def pose(**kw):
    for k, v in kw.items():
        bone, attr = k.rsplit('__', 1)
        bone = bone.replace('_L', '.L').replace('_R', '.R').replace('upper.arm', 'upper_arm')
        pb = arm.pose.bones[bone]
        if attr in 'xyz':
            e = list(pb.rotation_euler)
            e['xyz'.index(attr)] = R(v)
            pb.rotation_euler = e
        else:
            l = list(pb.location)
            l[1] = v  # eixo do osso (para cima no quadril)
            pb.location = l


def idle(t, f):
    p = 2 * math.pi * t
    pose(chest__x=2 * math.sin(p), head__x=-1.5 * math.sin(p), upper_arm_L__x=1.5 * math.sin(p + 1),
         upper_arm_R__x=1.5 * math.sin(p + 1), hips__loc=-0.006 * (1 - math.cos(p)))


def gait(amp, knee, arm_r, arm_l, lean, bob):
    def fn(t, f):
        p = 2 * math.pi * t
        pose(thigh_L__x=amp * math.sin(p), thigh_R__x=-amp * math.sin(p),
             shin_L__x=-(8 + knee * max(0, math.sin(p + 0.9))), shin_R__x=-(8 + knee * max(0, math.sin(p + 0.9 + math.pi))),
             upper_arm_R__x=arm_r * math.sin(p), upper_arm_L__x=-arm_l * math.sin(p),
             forearm_R__x=10 + arm_r * 0.5, forearm_L__x=10, spine__x=lean, spine__y=4 * math.sin(p),
             hips__loc=-bob * math.cos(2 * p))
    return fn


def cast(t, f):
    k = min(1, t / 0.4) if t < 0.7 else max(0, 1 - (t - 0.7) / 0.3)
    pose(upper_arm_R__x=95 * k, forearm_R__x=15 * k, chest__x=-5 * k, head__x=-5 * k)


def attack(t, f):
    a = -30 * min(1, t / 0.25) if t < 0.25 else (-30 + 100 * min(1, (t - 0.25) / 0.3) if t < 0.55 else 70 * (1 - (t - 0.55) / 0.45))
    pose(upper_arm_R__x=a, forearm_R__x=20, spine__y=15 - 30 * t)


def damage(t, f):
    k = math.sin(math.pi * t)
    pose(chest__x=-15 * k, head__x=-10 * k, spine__x=-5 * k)


make('idle', 32, idle)
make('walk', 24, gait(25, 28, 15, 6, 3, 0.015 * H))
make('run', 16, gait(40, 50, 30, 10, 12, 0.03 * H))
make('cast', 20, cast, loop=False)
make('attack', 16, attack, loop=False)
make('damage', 10, damage, loop=False)
arm.animation_data.action = bpy.data.actions['idle']

bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
body.select_set(True)
out = os.path.join(OUT, 'modelo.glb')
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_animations=True,
                          export_animation_mode='ACTIONS', export_force_sampling=True)
cfg = {
    'modelo': 'modelo.glb',
    'animacoes': {a: {'arquivo': 'modelo.glb', 'acao': a} for a in ('idle', 'walk', 'run', 'cast', 'attack', 'damage')},
    'quadros': 8,
    'amostras': 24,
}
json.dump(cfg, open(os.path.join(OUT, 'config.json'), 'w'), indent=2)
print('rig pronto:', out)
