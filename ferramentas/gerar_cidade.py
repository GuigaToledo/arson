#!/usr/bin/env python3
"""Cidade murada de Arson (v2, prédios entráveis).

Abre a terra no sul da ilha inicial, estica o mapa para 150 linhas, escreve o desenho em
godot/data/maps/ilha.txt e a lista de prédios em godot/data/predios.json. Pode rodar sempre.
Caracteres: M muralha, Q torre (3x3), I chão por dentro dos prédios (a parede é desenhada pelo jogo).
A cidade ocupa x 2..55, y 55..141. Eixo central x = 28.
  python3 ferramentas/gerar_cidade.py [--previa arquivo.png]
"""
import math, sys, json

PATH = 'godot/data/maps/ilha.txt'
ALTURA = 150
rows = [list(r) for r in open(PATH).read().rstrip('\n').split('\n')]
W = max(len(r) for r in rows)
for r in rows:
    r.extend('~' * (W - len(r)))
while len(rows) < ALTURA:
    rows.append(['~'] * W)
H = len(rows)
X0, X1, Y0, Y1 = 2, 55, 55, 141


def put(x, y, c):
    if 0 <= x < W and 0 <= y < H:
        rows[y][x] = c


def rect(x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(x, y, c)


def at(x, y):
    return rows[y][x] if 0 <= x < W and 0 <= y < H else '~'


for y in range(55, H):
    for x in range(0, 58):
        rows[y][x] = '~'
R = 7
for y in range(Y0, Y1 + 1):
    for x in range(X0, X1 + 1):
        dx = max(X0 + R - x, 0, x - (X1 - R))
        dy = max(Y0 + R - y, 0, y - (Y1 - R))
        d = math.hypot(dx, dy)
        wob = math.sin(x * 0.9) * 0.4 + math.sin(y * 0.7) * 0.4
        if d > R + wob:
            continue
        edge = min(x - X0, X1 - x, y - Y0, Y1 - y)
        if dx or dy:
            edge = min(edge, R - d)
        rows[y][x] = ',' if edge < 2.2 + wob else '.'

WX0, WX1, WY0, WY1 = 6, 50, 60, 136
GAP_X = (26, 29)
GAP_Y = (100, 103)
CX0, CX1, CY0, CY1 = 12, 44, 64, 88
PX0, PX1, PY0, PY1 = 8, 48, 61, 95


def torre(tx, ty):
    rect(tx, ty, tx + 2, ty + 2, 'Q')


def muralha(x0, y0, x1, y1):
    rect(x0, y0, x1, y0, 'M'); rect(x0, y1, x1, y1, 'M')
    rect(x0, y0, x0, y1, 'M'); rect(x1, y0, x1, y1, 'M')


PREDIOS = [
    ('guilda', 'guilda', 8, 92, 12, 8),
    ('templo', 'templo', 30, 93, 11, 7),
    ('casa_elyra', 'casa_b', 41, 94, 8, 6),
    ('loja', 'loja', 8, 104, 9, 7),
    ('ferraria', 'ferraria', 17, 104, 9, 7),
    ('casa_lira', 'casa_a', 31, 104, 7, 6),
    ('casa_zaira', 'casa_b', 38, 104, 8, 6),
    ('casa_nadira', 'casa_a', 8, 115, 7, 6),
    ('casa_samira', 'casa_b', 15, 115, 8, 6),
    ('casa_tarek', 'casa_a', 32, 115, 7, 6),
    ('casa_9', 'casa_b', 39, 115, 8, 6),
    ('casa_10', 'casa_a', 8, 125, 7, 6),
    ('casa_11', 'casa_b', 15, 125, 8, 6),
    ('casa_12', 'casa_a', 32, 125, 7, 6),
    ('casa_13', 'casa_b', 39, 125, 8, 6),
    ('salao', 'salao', 20, 68, 16, 11),
]
rect(PX0, PY0, PX1, PY1, '#')
for pid, tipo, x, y, w, h in PREDIOS:
    rect(x - 1, y + h, x + w, y + h + 1, ':')
for yy in (113, 123, 133):
    rect(7, yy - 1, 49, yy, ':')
rect(26, 55, 29, 140, '#')
rect(2, GAP_Y[0], 54, GAP_Y[1], '#')
rect(2, GAP_Y[0], 5, GAP_Y[1], ':'); rect(51, GAP_Y[0], 54, GAP_Y[1], ':')
muralha(CX0, CY0, CX1, CY1)
rect(CX0 + 1, CY0 + 1, CX1 - 1, CY1 - 1, '#')
rect(26, CY1, 29, CY1, '#')
for pid, tipo, x, y, w, h in PREDIOS:
    rect(x, y, x + w - 1, y + h - 1, 'I')
for cx, cy in [(CX0, CY0), (CX1, CY0), (CX0, CY1), (CX1, CY1)]:
    torre(cx - 1, cy - 1)
torre(23, CY1 - 1); torre(30, CY1 - 1)
for mx in (CX0 + 9, CX1 - 9):
    torre(mx - 1, CY0 - 1)

muralha(WX0, WY0, WX1, WY1)
rect(GAP_X[0], WY0, GAP_X[1], WY0, '#'); rect(GAP_X[0], WY1, GAP_X[1], WY1, '#')
rect(WX0, GAP_Y[0], WX0, GAP_Y[1], '#'); rect(WX1, GAP_Y[0], WX1, GAP_Y[1], '#')
for cx, cy in [(WX0, WY0), (WX1, WY0), (WX0, WY1), (WX1, WY1)]:
    torre(cx - 1, cy - 1)
for gx in (GAP_X[0] - 3, GAP_X[1] + 1):
    torre(gx, WY0 - 1); torre(gx, WY1 - 1)
for gy in (GAP_Y[0] - 3, GAP_Y[1] + 1):
    torre(WX0 - 1, gy); torre(WX1 - 1, gy)
for mx in (15, 41):
    torre(mx - 1, WY0 - 1); torre(mx - 1, WY1 - 1)
for my in (78, 118):
    torre(WX0 - 1, my - 1); torre(WX1 - 1, my - 1)
for y in range(49, 55):
    put(27, y, '='); put(28, y, '=')

open(PATH, 'w').write('\n'.join(''.join(r) for r in rows) + '\n')
json.dump([dict(id=p[0], tipo=p[1], x=p[2], y=p[3], w=p[4], h=p[5]) for p in PREDIOS],
          open('godot/data/predios.json', 'w'), ensure_ascii=False, indent=1)

if '--previa' in sys.argv:
    from PIL import Image
    cor = {'~': (30, 60, 110), ',': (200, 185, 130), '.': (70, 120, 60), ':': (140, 105, 70), '#': (150, 150, 150),
           'M': (60, 60, 70), 'Q': (40, 40, 90), 'I': (200, 120, 30), 'H': (120, 80, 50), 'T': (230, 230, 240),
           '=': (120, 80, 40), 'j': (20, 80, 30), 'f': (30, 90, 40), 'r': (100, 100, 100)}
    S = 8
    im = Image.new('RGB', (60 * S, (Y1 + 6 - 48) * S))
    px = im.load()
    for y in range(48, Y1 + 6):
        for x in range(0, 60):
            c = cor.get(at(x, y), (255, 0, 255))
            for a in range(S):
                for b in range(S):
                    px[x * S + a, (y - 48) * S + b] = c
    im.save(sys.argv[sys.argv.index('--previa') + 1])
