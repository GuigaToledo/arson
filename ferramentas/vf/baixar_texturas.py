#!/usr/bin/env python3
"""Visual Factory: baixa as texturas de ferramentas/vf/fontes.json (ambientCG, CC0),
separa cor e normal, reduz para 1024 px e grava em godot/assets/vf/terreno/<nome>_c.jpg e _n.jpg.
Também reescreve ASSET_CREDITS.md. Roda no GitHub Actions (o ambiente do Claude não baixa).
Uso: python3 ferramentas/vf/baixar_texturas.py"""
import json, io, os, sys, zipfile, urllib.request
from PIL import Image

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
F = json.load(open(os.path.join(RAIZ, 'ferramentas/vf/fontes.json'), encoding='utf-8'))
OUT = os.path.join(RAIZ, 'godot/assets/vf/terreno')
os.makedirs(OUT, exist_ok=True)
LIC = {'ambientCG': ('CC0 1.0', 'https://docs.ambientcg.com/license/')}
creditos = []
for t in F['terreno']:
    url = f"https://ambientcg.com/get?file={t['id']}_1K-JPG.zip"
    dest_c = os.path.join(OUT, t['nome'] + '_c.jpg')
    dest_n = os.path.join(OUT, t['nome'] + '_n.jpg')
    if not (os.path.exists(dest_c) and os.path.exists(dest_n)):
        print('baixando', t['id'])
        req = urllib.request.Request(url, headers={'User-Agent': 'arson-visual-factory'})
        data = urllib.request.urlopen(req, timeout=120).read()
        z = zipfile.ZipFile(io.BytesIO(data))
        nomes = z.namelist()
        cor = [n for n in nomes if n.endswith('_Color.jpg')]
        nor = [n for n in nomes if n.endswith('_NormalGL.jpg')]
        if not cor or not nor:
            sys.exit(f"{t['id']}: zip sem Color/NormalGL ({nomes})")
        for src, dst in ((cor[0], dest_c), (nor[0], dest_n)):
            im = Image.open(io.BytesIO(z.read(src))).convert('RGB')
            if im.size != (1024, 1024):
                im = im.resize((1024, 1024), Image.LANCZOS)
            im.save(dst, quality=88)
    lic, lic_url = LIC[t['fonte']]
    creditos.append(f"| `{t['nome']}` | [{t['id']}](https://ambientcg.com/view?id={t['id']}) | {t['fonte']} | [{lic}]({lic_url}) | {t['uso']} |")

with open(os.path.join(RAIZ, 'ASSET_CREDITS.md'), 'w', encoding='utf-8') as f:
    f.write("# Créditos de recursos externos\n\n")
    f.write("Gerado por `ferramentas/vf/baixar_texturas.py` a partir de `ferramentas/vf/fontes.json`.\n")
    f.write("Todo o resto do visual (personagens, monstros, objetos, magias) é gerado por código no projeto.\n\n")
    f.write("## Texturas de chão (godot/assets/vf/terreno)\n\n")
    f.write("| Arquivo | Recurso | Fonte | Licença | Uso |\n| --- | --- | --- | --- | --- |\n")
    f.write("\n".join(creditos) + "\n\n")
    f.write("ambientCG: \"All ambientCG assets are provided under the Creative Commons CC0 1.0 Universal License\"; crédito não é obrigatório, mas é dado aqui.\n\n")
    f.write("## Outros\n\n- Texturas antigas em `godot/assets/textures/` (ambientCG CC0: Grass004, Ground037, Ground081, Ground054, PavingStones070, Rock030).\n- Motor: Godot Engine (MIT). Rede: PeerJS (MIT).\n")
print('ok', len(creditos))
