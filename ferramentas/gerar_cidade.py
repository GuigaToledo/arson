#!/usr/bin/env python3
"""Cidade murada de Arson: abre a terra no sul da ilha inicial (lado esquerdo do mapa) e escreve o
desenho da cidade em godot/data/maps/ilha.txt. Roda quantas vezes quiser (sempre refaz a região).

Novos caracteres do mapa:
  M muralha     Q torre (blocos de 3x3)     C salão do castelo (bloco 10x6)
  G guilda      L loja                      F ferraria        H casa   T templo
A cidade fica entre x 2..55 e y 55..113. Eixo central: x = 28 (a ponte da vila cai nele).
  python3 ferramentas/gerar_cidade.py [--previa arquivo.png]
"""
import math, sys, random

PATH = 'godot/data/maps/ilha.txt'
rows = [list(r) for r in open(PATH).read().rstrip('\n').split('\n')]
W = max(len(r) for r in rows)
for r in rows:
    r.extend('~' * (W - len(r)))
H = len(rows)

# faixa da cidade (a ponte velha em x=27..28 y=49..54 continua e vira a entrada norte)
X0, X1, Y0, Y1 = 2, 55, 55, 113
random.seed(11)


def put(x, y, c):
    if 0 <= x < W and 0 <= y < H:
        rows[y][x] = c


def rect(x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(x, y, c)


def at(x, y):
    return rows[y][x] if 0 <= x < W and 0 <= y < H else '~'


# 1. água limpa e terra arredondada (areia na borda, grama dentro)
for y in range(Y0 - 2, Y1 + 4):
    for x in range(0, 58):
        if y >= 55:
            rows[y][x] = '~'
R = 7
for y in range(Y0, Y1 + 1):
    for x in range(X0, X1 + 1):
        # canto arredondado
        dx = max(X0 + R - x, 0, x - (X1 - R))
        dy = max(Y0 + R - y, 0, y - (Y1 - R))
        d = math.hypot(dx, dy)
        wob = math.sin(x * 0.9) * 0.4 + math.sin(y * 0.7) * 0.4
        if d > R + wob:
            continue
        edge = min(x - X0, X1 - x, y - Y0, Y1 - y)
        e2 = R - d if (dx or dy) else 99
        edge = min(edge, e2 + 0.0)
        rows[y][x] = ',' if edge < 2.2 + wob else '.'

WX0, WX1, WY0, WY1 = 6, 50, 60, 108   # muralha da cidade
GAP_X = (26, 29)                       # portões norte e sul (4 tiles)
GAP_Y = (82, 85)                       # portões oeste e leste
PX0, PX1, PY0, PY1 = 15, 40, 62, 89    # praça em volta do castelo
CX0, CX1, CY0, CY1 = 20, 36, 65, 77    # muralha do castelo


def torre(tx, ty):
    """Torre de 3x3 com o canto superior esquerdo em (tx, ty)."""
    rect(tx, ty, tx + 2, ty + 2, 'Q')


def muralha(x0, y0, x1, y1):
    rect(x0, y0, x1, y0, 'M'); rect(x0, y1, x1, y1, 'M')
    rect(x0, y0, x0, y1, 'M'); rect(x1, y0, x1, y1, 'M')


# 2. ruas: avenida norte-sul, avenida leste-oeste, praça em volta do castelo
rect(26, 55, 29, 112, '#')
rect(2, GAP_Y[0], 54, GAP_Y[1], '#')
rect(PX0, PY0, PX1, PY1, '#')
rect(2, GAP_Y[0], 5, GAP_Y[1], ':'); rect(51, GAP_Y[0], 54, GAP_Y[1], ':')   # caminho de terra fora dos portões

# 3. prédios (tipo, x, y, largura, altura), com chão de terra na frente e ruelas
PREDIOS = [
    ('G', 8, 65, 7, 5),
    ('H', 8, 75, 3, 3), ('H', 12, 75, 3, 3),
    ('L', 8, 89, 3, 3), ('F', 12, 89, 3, 3),
    ('H', 8, 96, 3, 3), ('H', 12, 96, 3, 3),
    ('T', 42, 66, 6, 3),
    ('H', 43, 75, 3, 3), ('H', 47, 75, 3, 3),
    ('H', 43, 89, 3, 3), ('H', 47, 89, 3, 3),
    ('H', 43, 96, 3, 3), ('H', 47, 96, 3, 3),
    ('H', 17, 95, 3, 3), ('H', 21, 95, 3, 3),
    ('H', 32, 95, 3, 3), ('H', 36, 95, 3, 3),
    ('H', 17, 101, 3, 3), ('H', 21, 101, 3, 3),
    ('H', 32, 101, 3, 3), ('H', 36, 101, 3, 3),
]
for ch, x, y, w, h in PREDIOS:
    rect(x - 1, y + h, x + w, y + h + 1, ':')
rect(7, 72, 14, 73, ':'); rect(42, 72, 49, 73, ':')
rect(7, 93, 14, 94, ':'); rect(42, 93, 49, 94, ':')
rect(16, 98, 38, 99, ':'); rect(16, 104, 38, 105, ':')
rect(26, 55, 29, 112, '#')   # a avenida passa por cima das ruelas
for ch, x, y, w, h in PREDIOS:
    rect(x, y, x + w - 1, y + h - 1, ch)

# 4. castelo: muralha interna, pátio calçado, salão (10x6, porta no lado sul) e torres
muralha(CX0, CY0, CX1, CY1)
rect(26, CY1, 29, CY1, '#')
rect(CX0 + 1, CY0 + 1, CX1 - 1, CY1 - 1, '#')
rect(23, 67, 32, 72, 'C')
for cx, cy in [(CX0, CY0), (CX1, CY0), (CX0, CY1), (CX1, CY1)]:
    torre(cx - 1, cy - 1)
torre(23, CY1 - 1); torre(30, CY1 - 1)

# 5. muralha da cidade, portões e torres (nos cantos, nos portões e no meio dos lados)
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
for my in (68, 100):
    torre(WX0 - 1, my - 1); torre(WX1 - 1, my - 1)

# 6. ponte da vila até o portão norte (a ponte velha termina em y=54)
for y in range(49, 55):
    put(27, y, '='); put(28, y, '=')

open(PATH, 'w').write('\n'.join(''.join(r) for r in rows) + '\n')

if '--previa' in sys.argv:
    from PIL import Image
    cor = {'~': (30, 60, 110), ',': (200, 185, 130), '.': (70, 120, 60), ':': (140, 105, 70), '#': (150, 150, 150),
           'M': (60, 60, 70), 'Q': (40, 40, 90), 'C': (160, 40, 40), 'G': (200, 120, 30), 'L': (60, 160, 160),
           'F': (180, 80, 30), 'H': (120, 80, 50), 'T': (230, 230, 240), '=': (120, 80, 40), 'j': (20, 80, 30),
           'f': (30, 90, 40), 'r': (100, 100, 100)}
    S = 12
    im = Image.new('RGB', (60 * S, (Y1 + 6 - 48) * S))
    px = im.load()
    for y in range(48, Y1 + 6):
        for x in range(0, 60):
            c = cor.get(at(x, y), (255, 0, 255))
            for a in range(S):
                for b in range(S):
                    px[x * S + a, (y - 48) * S + b] = c
    im.save(sys.argv[sys.argv.index('--previa') + 1])
