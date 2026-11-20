#!/usr/bin/env python3
"""Peças de cenário: arte/objetos/*.png|jpg|webp -> godot/assets/objetos/<nome>.png

- Se a imagem já tem transparência, só recorta as bordas vazias.
- Se tem fundo liso (branco, verde, cinza...), remove o fundo a partir das bordas.
- Limita o tamanho para no máximo MAX px no lado maior.
"""
import os, sys
from collections import deque
from PIL import Image, ImageFilter

SRC, DST = sys.argv[1], sys.argv[2]
MAX = 768
TOL = 38


def bg_remove(im):
    im = im.convert('RGBA')
    w, h = im.size
    px = im.load()
    if any(px[x, y][3] < 250 for x, y in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]):
        return im
    border = [px[x, 0] for x in range(w)] + [px[x, h - 1] for x in range(w)] + [px[0, y] for y in range(h)] + [px[w - 1, y] for y in range(h)]
    ref = tuple(sorted(c[i] for c in border)[len(border) // 2] for i in range(3))
    near = lambda c: abs(c[0] - ref[0]) + abs(c[1] - ref[1]) + abs(c[2] - ref[2]) < TOL * 3
    mask = Image.new('L', (w, h), 255)
    mp = mask.load()
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if mp[x, y] == 0 or not near(px[x, y]):
            continue
        mp[x, y] = 0
        if x > 0: q.append((x - 1, y))
        if x < w - 1: q.append((x + 1, y))
        if y > 0: q.append((x, y - 1))
        if y < h - 1: q.append((x, y + 1))
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.0))
    im.putalpha(mask)
    return im


def main():
    os.makedirs(DST, exist_ok=True)
    if not os.path.isdir(SRC):
        return
    for f in sorted(os.listdir(SRC)):
        stem, ext = os.path.splitext(f)
        if ext.lower() not in ('.png', '.jpg', '.jpeg', '.webp'):
            continue
        src = os.path.join(SRC, f)
        dst = os.path.join(DST, stem.lower().replace(' ', '_') + '.png')
        if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
            continue
        im = bg_remove(Image.open(src))
        bbox = im.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
        if bbox:
            im = im.crop(bbox)
        im.thumbnail((MAX, MAX), Image.LANCZOS)
        im.save(dst)
        print('objeto:', dst, im.size)


main()
