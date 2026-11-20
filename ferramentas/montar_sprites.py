#!/usr/bin/env python3
"""Junta os quadros renderizados pelo Blender em folhas (uma por animação,
linhas = direções) e gera os recursos do Godot:
  godot/assets/personagens/<nome>/<animação>.png
  godot/assets/personagens/<nome>/quadros.tres  (SpriteFrames, animações "walk_SE" etc.)
  godot/assets/personagens/<nome>/corpo.tres    (EquipmentItem usado como corpo)

uso: montar_sprites.py <saida_do_blender> <pasta_godot_destino> <nome>
"""
import json, os, sys
from PIL import Image

TMP, DST, NOME = sys.argv[1], sys.argv[2], sys.argv[3]
ROWS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
meta = json.load(open(os.path.join(TMP, 'meta.json')))
S = meta['tamanho']
os.makedirs(DST, exist_ok=True)
res_dir = 'res://assets/personagens/%s/' % NOME

# recorte comum a todos os quadros (tira o espaço vazio) e altura do corpo
files = [os.path.join(TMP, 'frames', f) for f in os.listdir(os.path.join(TMP, 'frames')) if f.endswith('.png')]
box, body_h = None, 0
for fp in files:
    a = Image.open(fp).getchannel('A')
    b = a.point(lambda v: 255 if v > 8 else 0).getbbox()
    if b:
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    bb = a.point(lambda v: 255 if v > 200 else 0).getbbox()
    if bb:
        body_h = max(body_h, bb[3] - bb[1])
box = box or (0, 0, S, S)
box = (max(0, box[0] - 4), max(0, box[1] - 4), min(S, box[2] + 4), min(S, box[3] + 4))
BW, BH = box[2] - box[0], box[3] - box[1]
ALTURA_JOGO = 84.0
escala = ALTURA_JOGO / max(1, body_h)

ext, subs, anims = [], [], []
sid = 0
for ai, (anim, info) in enumerate(meta['animacoes'].items()):
    n = info['quadros']
    sheet = Image.new('RGBA', (BW * n, BH * len(ROWS)))
    for row, d in enumerate(ROWS):
        for i in range(n):
            fr = Image.open(os.path.join(TMP, 'frames', '%s_%s_%02d.png' % (anim, d, i)))
            sheet.paste(fr.crop(box), (i * BW, row * BH))
    sheet.save(os.path.join(DST, anim + '.png'), optimize=True)
    tid = 't%d' % ai
    ext.append('[ext_resource type="Texture2D" path="%s%s.png" id="%s"]' % (res_dir, anim, tid))
    for row, d in enumerate(ROWS):
        frames = []
        for i in range(n):
            sid += 1
            subs.append('[sub_resource type="AtlasTexture" id="a%d"]\natlas = ExtResource("%s")\nregion = Rect2(%d, %d, %d, %d)\n' % (sid, tid, i * BW, row * BH, BW, BH))
            frames.append('{"duration": 1.0, "texture": SubResource("a%d")}' % sid)
        anims.append('{"frames": [%s], "loop": %s, "name": &"%s_%s", "speed": %.1f}' % (
            ', '.join(frames), 'true' if info['loop'] else 'false', anim, d, info['fps']))

with open(os.path.join(DST, 'quadros.tres'), 'w') as f:
    f.write('[gd_resource type="SpriteFrames" load_steps=%d format=3]\n\n' % (len(ext) + len(subs) + 1))
    f.write('\n'.join(ext) + '\n\n')
    f.write('\n'.join(subs) + '\n')
    f.write('[resource]\nanimations = [%s]\n' % ', '.join(anims))

ax, ay = meta['ancora']
cfg = {}
with open(os.path.join(DST, 'corpo.tres'), 'w') as f:
    f.write('''[gd_resource type="Resource" script_class="EquipmentItem" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/equipment/equipment_item.gd" id="1"]
[ext_resource type="SpriteFrames" path="%squadros.tres" id="2"]

[resource]
script = ExtResource("1")
id = &"corpo_%s"
display_name = "%s"
item_type = "corpo"
sprite_frames = ExtResource("2")
animations = PackedStringArray(%s)
anchor = Vector2(%.1f, %.1f)
sprite_scale = %.4f
''' % (res_dir, NOME, NOME, ', '.join('"%s"' % a for a in meta['animacoes']), BW / 2 - (ax - box[0]), BH / 2 - (ay - box[1]), escala))
print('sprites prontos:', DST)
