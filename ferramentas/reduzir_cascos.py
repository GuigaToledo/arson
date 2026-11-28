#!/usr/bin/env python3
"""Reduz os cascos dos prédios (muito grandes para a memória de vídeo do celular).
fundo a 50% e frente a 70% do tamanho original (que está em resolução dupla). A escala que o
jogo deve usar fica como 3º número da âncora em ancoras.json: [x, y, escala]."""
import json, sys, os
from PIL import Image
D = 'godot/assets/objetos'
A = json.load(open(D + '/ancoras.json'))
FATOR = {'_fundo': 0.5, '_frente': 0.7}
for n in list(A):
    for suf, f in FATOR.items():
        if n.endswith(suf) and len(A[n]) == 2:
            im = Image.open('%s/%s.png' % (D, n))
            im = im.resize((max(1, int(im.width * f)), max(1, int(im.height * f))), Image.LANCZOS)
            im.save('%s/%s.png' % (D, n))
            A[n] = [round(A[n][0] * f, 1), round(A[n][1] * f, 1), round(0.5 / f, 4)]
            print(n, im.size, A[n])
json.dump(A, open(D + '/ancoras.json', 'w'), indent=1)
