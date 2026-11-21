#!/usr/bin/env python3
"""Gera wiki.json (lido por wiki.html) a partir dos dados do próprio jogo:
classes (mage_class.gd), magias (spellbook.gd), monstros (data/monstros.json),
regiões (data/regioes.json), itens (data/items/*.tres) e NPCs (lista abaixo).
Roda no GitHub Actions a cada publicação, então a wiki nunca fica desatualizada.

uso: python3 ferramentas/gerar_wiki.py <saida/wiki.json>
"""
import glob, json, os, re, sys

G = 'godot'
out = sys.argv[1] if len(sys.argv) > 1 else 'wiki.json'


def color_hex(txt):
    v = [float(x) for x in txt.split(',')[:3]]
    return '#%02x%02x%02x' % tuple(max(0, min(255, round(c * 255))) for c in v)


def gd_strings(txt):
    return re.findall(r'"((?:[^"\\]|\\.)*)"', txt)


sb = open(f'{G}/scripts/game/spellbook.gd', encoding='utf-8').read()
tipos = gd_strings(re.search(r'const TIER_KIND := \[(.*?)\]', sb, re.S).group(1))
elementos = {}
for m in re.finditer(r'"(\w+)": \{"nome": "([^"]+)", "cor": Color\(([^)]*)\), "efeito": "([^"]+)",\s*"magias": \[(.*?)\]\}', sb, re.S):
    elementos[m.group(1)] = {'nome': m.group(2), 'cor': color_hex(m.group(3)), 'efeito': m.group(4), 'magias': gd_strings(m.group(5))}
luz_desc = gd_strings(re.search(r'const LUZ_DESC := \[(.*?)\]', sb, re.S).group(1))
fus = {m.group(1): gd_strings(m.group(2)) for m in re.finditer(r'"(\w+)": \[([^\]]*)\]', sb[sb.find('const FUSOES'):sb.find('}', sb.find('const FUSOES'))])}

mc = open(f'{G}/scripts/game/mage_class.gd', encoding='utf-8').read()
classes = []
name_to_key = {v['nome']: k for k, v in elementos.items()}
for m in re.finditer(r'"(\w+)": \{\s*"nome": "([^"]+)", "elementos": \[([^\]]*)\].*?"desc": "([^"]+)"', mc, re.S):
    els = [name_to_key.get(e, e.lower()) for e in gd_strings(m.group(3))]
    f = fus.get(m.group(1), [])
    classes.append({'id': m.group(1), 'nome': m.group(2), 'elementos': els, 'desc': m.group(4),
                    'fusoes': f})

itens = []
for f in sorted(glob.glob(f'{G}/data/items/*.tres')):
    t = open(f, encoding='utf-8').read()
    get = lambda k, d='': (re.search(rf'^{k} = (.*)$', t, re.M) or [None, d])[1]
    stats = {}
    st = get('stats', '{}')
    for k, v in re.findall(r'"(\w+)": (-?[\d.]+)', st):
        stats[k] = float(v) if '.' in v else int(v)
    itens.append({'id': os.path.basename(f)[:-5], 'nome': get('display_name').strip('"'), 'tipo': get('item_type', '"armadura"').strip('"'),
                  'slot': int(get('slot', '1')), 'nivel': int(get('level_req', '1')), 'atributos': stats})

mons_raw = json.load(open(f'{G}/data/monstros.json', encoding='utf-8')) if os.path.exists(f'{G}/data/monstros.json') else {}
saque_db = json.load(open(f'{G}/data/saque.json', encoding='utf-8')) if os.path.exists(f'{G}/data/saque.json') else {}
monstros = []
for k, m in mons_raw.items():
    if m.get('dummy') or m.get('wiki') is False:
        continue
    cor = (m.get('colors') or {}).get('main') or (m.get('colors') or {}).get('skin') or '#888888'
    monstros.append({'id': k, 'nome': m['name'], 'regiao': m.get('regiao', 'Ilha inicial'), 'desc': m.get('desc', ''),
                     'hp': m['hp'], 'atk': m['atk'], 'def': m.get('def', 0), 'xp': m['xp'], 'gold': '%d–%d' % tuple(m['gold']),
                     'distancia': float(m.get('range', 1)) > 2.0, 'elemento': m.get('el', ''), 'cor': cor,
                     'habilidades': [{'nome': s.get('nome', s['tipo']), 'desc': s.get('desc', '')} for s in m.get('habilidades', [])],
                     'chefe': bool(m.get('chefe')),
                     'saque': ['%s (%d ouro, %d%%)' % (saque_db[i]['nome'], saque_db[i]['preco'], round(c * 100)) for i, c in m.get('saque', []) if i in saque_db],
                     'drop': m.get('drop', ''), 'drop_chance': m.get('drop_chance', 0)})
monstros.sort(key=lambda x: (x['chefe'], x['xp']))
_nomes = {i['id']: i['nome'] for i in itens}
for m in monstros:
    m['drop'] = ('%s (%d%%)' % (_nomes.get(m['drop'], m['drop']), round(m['drop_chance'] * 100))) if m['drop'] else ''

regioes = json.load(open(f'{G}/data/regioes.json', encoding='utf-8')) if os.path.exists(f'{G}/data/regioes.json') else []
regioes = [{'nome': r['nome'], 'desc': r['desc'], 'monstros': [m['nome'] for m in monstros if m['regiao'] == r['nome']]} for r in regioes]

npcs = [
    {'nome': 'Guarda do Templo', 'local': 'Templo da vila', 'desc': 'Vigia a entrada do templo, onde todo aventureiro começa.'},
    {'nome': 'Brann, o Mercador', 'local': 'Beco ao lado do templo', 'desc': 'Vende poções de vida e de mana e equipamentos de mago.'},
    {'nome': 'Lira, a Sacerdotisa', 'local': 'Beco ao lado do templo', 'desc': 'Cura os feridos e dá tarefas de caça com recompensa.'},
    {'nome': 'Viajante', 'local': 'Estradas da ilha', 'desc': 'Anda pelas estradas da ilha contando o que viu pelo caminho.'},
]

regras = [
    'Toque no chão ou use o joystick para andar; no PC, WASD ou clique. Shift corre.',
    'O alvo é escolhido sozinho: o inimigo mais próximo. As magias ficam na barra (1 a 8 no PC).',
    'Cada elemento sobe de nível com o uso. A Defesa sobe quando você leva golpes.',
    'Monstros dão experiência e ouro e podem deixar itens. Cada região tem os seus monstros.',
    'Qualquer monstro comum pode nascer Elite (aura dourada): 2,6x vida, mais dano, 3x experiência e ouro e mais saque.',
    'Cada região tem um chefe (aura vermelha). Ele demora alguns minutos para voltar, deixa um troféu valioso e pode deixar um equipamento único.',
    'O saque das criaturas (peles, ossos, gosmas...) vai para a bolsa de saque e é vendido ao Brann, na vila.',
    'A vila e o templo são áreas seguras: lá ninguém ataca você.',
    'Morrer faz perder um pouco da experiência e voltar ao templo.',
    'Jogue com amigos: todos que abrem o jogo entram no mesmo mundo.',
]

json.dump({'tipos': tipos, 'elementos': elementos, 'luz_desc': luz_desc, 'classes': classes, 'itens': itens,
           'monstros': monstros, 'regioes': regioes, 'npcs': npcs, 'regras': regras},
          open(out, 'w', encoding='utf-8'), ensure_ascii=False)
print('wiki:', len(classes), 'classes,', len(elementos), 'elementos,', len(monstros), 'monstros,', len(itens), 'itens')
