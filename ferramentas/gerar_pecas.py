#!/usr/bin/env python3
"""Gera peças de cenário 2D com IA de imagem gratuita (Pollinations / FLUX),
usando o mesmo pedido de estilo para todas (arte/gerar2d/pedidos.json).
Salva em arte/objetos/<nome>.png (fundo branco); a etapa seguinte remove o fundo.
Só gera o que ainda não existe."""
import json, os, time, urllib.parse, urllib.request

cfg = json.load(open('arte/gerar2d/pedidos.json', encoding='utf-8'))
os.makedirs('arte/objetos', exist_ok=True)
for i, (nome, obj) in enumerate(cfg['pecas'].items()):
    dst = os.path.join('arte/objetos', nome + '.png')
    if os.path.exists(dst) or os.path.exists(os.path.join('godot/assets/objetos', nome + '.png')):
        continue
    prompt = cfg['estilo'].replace('{obj}', obj)
    url = 'https://image.pollinations.ai/prompt/' + urllib.parse.quote(prompt) + '?width=1024&height=1024&nologo=true&model=flux&seed=%d' % (1000 + i)
    for tent in range(4):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            data = urllib.request.urlopen(req, timeout=180).read()
            if len(data) > 20000:
                open(dst, 'wb').write(data)
                print('gerada:', nome, len(data))
                break
        except Exception as e:
            print('falhou', nome, tent, e)
        time.sleep(8)
