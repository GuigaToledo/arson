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

ext, subs, anims = [], [], []
sid = 0
for ai, (anim, info) in enumerate(meta['animacoes'].items()):
    n = info['quadros']
    sheet = Image.new('RGBA', (S * n, S * len(ROWS)))
    for row, d in enumerate(ROWS):
        for i in range(n):
            fr = Image.open(os.path.join(TMP, 'frames', '%s_%s_%02d.png' % (anim, d, i)))
            sheet.paste(fr, (i * S, row * S))
    sheet.save(os.path.join(DST, anim + '.png'), optimize=True)
    tid = 't%d' % ai
    ext.append('[ext_resource type="Texture2D" path="%s%s.png" id="%s"]' % (res_dir, anim, tid))
    for row, d in enumerate(ROWS):
        frames = []
        for i in range(n):
            sid += 1
            subs.append('[sub_resource type="AtlasTexture" id="a%d"]\natlas = ExtResource("%s")\nregion = Rect2(%d, %d, %d, %d)\n' % (sid, tid, i * S, row * S, S, S))
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
''' % (res_dir, NOME, NOME, ', '.join('"%s"' % a for a in meta['animacoes']), S / 2 - ax, S / 2 - ay))
print('sprites prontos:', DST)
