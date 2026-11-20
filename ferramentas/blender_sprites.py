"""Roda dentro do Blender (sem janela):
  blender -b -P ferramentas/blender_sprites.py -- arte/personagens/<nome> <saida_temporaria>

Lê config.json da pasta, importa o modelo .glb e as animações, e renderiza cada
animação nas 8 direções com câmera isométrica fixa e luz fixa (vinda do alto à
esquerda), fundo transparente e sombra no chão. Gera PNGs soltos + meta.json.
"""
import bpy, sys, os, json, math
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

args = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT = args[0], args[1]
cfg = json.load(open(os.path.join(SRC, 'config.json'), encoding='utf-8'))
os.makedirs(os.path.join(OUT, 'frames'), exist_ok=True)

DIRS = [('S', 0), ('SE', 45), ('E', 90), ('NE', 135), ('N', 180), ('NW', 225), ('W', 270), ('SW', 315)]
LOOPING = ('idle', 'walk', 'run')
SIZE = int(cfg.get('tamanho', 256))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def import_glb(path):
    objs0, acts0 = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in objs0], [a for a in bpy.data.actions if a not in acts0]


model_objs, model_acts = import_glb(os.path.join(SRC, cfg['modelo']))
for a in model_acts:
    a.use_fake_user = True
arm = next((o for o in model_objs if o.type == 'ARMATURE'), None)
meshes = [o for o in model_objs if o.type == 'MESH']

pivot = bpy.data.objects.new('Pivot', None)
sc.collection.objects.link(pivot)
for o in model_objs:
    if o.parent is None:
        o.parent = pivot

# ações por arquivo
cache = {cfg['modelo']: model_acts}


def actions_of(fname):
    if fname not in cache:
        objs, acts = import_glb(os.path.join(SRC, fname))
        for a in acts:
            a.use_fake_user = True
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
        cache[fname] = acts
    return [a for a in cache[fname] if any('pose.bones' in fc.data_path for fc in a.fcurves)] or cache[fname]


def pick(spec):
    acts = actions_of(spec.get('arquivo', cfg['modelo']))
    want = spec.get('acao')
    if want:
        for a in acts:
            if a.name == want or a.name.startswith(want + '_') or want in a.name:
                return a
    return acts[0] if acts else None


# altura e pés medidos na geometria já deformada pela primeira animação
def measure():
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    zs = []
    for o in meshes:
        if o.hide_render:
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        oz = [(ev.matrix_world @ v.co).z for v in me.vertices]
        print('  malha', o.name, 'z', round(min(oz), 3), round(max(oz), 3), 'pai', o.parent.name if o.parent else '-')
        zs += oz
        ev.to_mesh_clear()
    return min(zs), max(zs)


first = next(iter((cfg.get('animacoes') or {'idle': {}}).values()))
if arm is not None and pick(first):
    arm.animation_data_create()
    arm.animation_data.action = pick(first)
    sc.frame_set(int(pick(first).frame_range[0]))
zmin, zmax = measure()
height = zmax - zmin
pivot.location.z = -zmin
print('altura do modelo:', height)

# câmera isométrica (30° de elevação)
cam_data = bpy.data.cameras.new('Cam')
cam_data.type = 'ORTHO'
cam_data.ortho_scale = height * float(cfg.get('enquadramento', 1.5))
cam = bpy.data.objects.new('Cam', cam_data)
sc.collection.objects.link(cam)
target = Vector((0, 0, height * 0.42))
el = math.radians(30)
cam.location = target + Vector((0, -math.cos(el), math.sin(el))) * height * 10
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
sc.camera = cam


def sun(name, energy, color, rot):
    d = bpy.data.lights.new(name, 'SUN')
    d.energy = energy
    d.color = color
    d.angle = math.radians(8)
    o = bpy.data.objects.new(name, d)
    o.rotation_euler = [math.radians(v) for v in rot]
    sc.collection.objects.link(o)


sun('Principal', 3.2, (1.0, 0.86, 0.7), (35, 0, -40))
sun('Preenchimento', 0.7, (0.6, 0.7, 1.0), (60, 0, 140))
sun('Contorno', 1.6, (1.0, 0.7, 0.45), (70, 0, 200))
world = bpy.data.worlds.new('Mundo')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = (0.08, 0.07, 0.07, 1)
world.node_tree.nodes['Background'].inputs[1].default_value = 0.6
sc.world = world

bpy.ops.mesh.primitive_plane_add(size=height * 6)
plane = bpy.context.active_object
plane.is_shadow_catcher = True

r = sc.render
r.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = int(cfg.get('amostras', 24))
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 4
r.film_transparent = True
r.resolution_x = r.resolution_y = SIZE
r.resolution_percentage = 100
r.image_settings.file_format = 'PNG'
r.image_settings.color_mode = 'RGBA'
sc.view_settings.view_transform = 'Standard'

foot = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
meta = {'tamanho': SIZE, 'ancora': [foot.x * SIZE, (1 - foot.y) * SIZE], 'animacoes': {}}

anims = cfg.get('animacoes') or {'idle': {}}
for name, spec in anims.items():
    act = pick(spec) if arm else None
    n = int(spec.get('quadros', cfg.get('quadros', 8)))
    loop = bool(spec.get('loop', name in LOOPING))
    if arm is not None:
        arm.animation_data_create()
        arm.animation_data.action = act
    s, e = (act.frame_range if act else (1, 1))
    if not act:
        n = 1
    print('animação', name, '->', act.name if act else '(nenhuma)', s, e)
    for dname, ang in DIRS:
        pivot.rotation_euler = (0, 0, math.radians(ang + float(cfg.get('rotacao', 0))))
        for i in range(n):
            f = s + (e - s) * (i / n if loop else i / max(1, n - 1))
            sc.frame_set(int(f), subframe=f - int(f))
            r.filepath = os.path.join(OUT, 'frames', '%s_%s_%02d.png' % (name, dname, i))
            bpy.ops.render.render(write_still=True)
    meta['animacoes'][name] = {'quadros': n, 'loop': loop, 'fps': float(spec.get('fps', 10 if name != 'run' else 13))}

json.dump(meta, open(os.path.join(OUT, 'meta.json'), 'w'))
print('pronto')
