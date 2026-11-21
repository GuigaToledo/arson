#!/usr/bin/env python3
"""Recorta peças de uma imagem de referência (arte/recortes.json), separa cada
peça do fundo com o rembg e salva em godot/assets/objetos/<nome>.png.
Só refaz as peças que ainda não existem (apague o PNG para refazer)."""
import json, os
from PIL import Image
from rembg import remove, new_session

cfg = json.load(open('arte/recortes.json', encoding='utf-8'))
src = Image.open(cfg['fonte']).convert('RGB')
out = 'godot/assets/objetos'
os.makedirs(out, exist_ok=True)
session = None
for nome, box in cfg['pecas'].items():
    dst = os.path.join(out, nome + '.png')
    if os.path.exists(dst):
        continue
    session = session or new_session('isnet-general-use')
    crop = src.crop(tuple(box))
    im = remove(crop, session=session, post_process_mask=True)
    bbox = im.getchannel('A').point(lambda a: 255 if a > 24 else 0).getbbox()
    if bbox:
        im = im.crop(bbox)
    im.save(dst)
    print('peça:', nome, im.size)
