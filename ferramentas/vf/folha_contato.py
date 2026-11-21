#!/usr/bin/env python3
"""Visual Factory: junta as fotos de inspeção numa folha só (miniaturas com o nome).
Uso: python3 ferramentas/vf/folha_contato.py <pasta> <saida.png>"""
import sys, os
from PIL import Image, ImageDraw

pasta, saida = sys.argv[1], sys.argv[2]
fs = sorted(f for f in os.listdir(pasta) if f.endswith('.png') and not f.startswith('_'))
if not fs:
    sys.exit('sem fotos')
W, H, C = 480, 270, 3
rows = (len(fs) + C - 1) // C
sheet = Image.new('RGB', (W * C, (H + 22) * rows), (20, 18, 16))
d = ImageDraw.Draw(sheet)
for i, f in enumerate(fs):
    im = Image.open(os.path.join(pasta, f)).convert('RGB').resize((W, H))
    x, y = (i % C) * W, (i // C) * (H + 22)
    sheet.paste(im, (x, y + 22))
    d.text((x + 6, y + 5), f[:-4], fill=(240, 220, 170))
sheet.save(saida)
print('folha', saida, len(fs))
