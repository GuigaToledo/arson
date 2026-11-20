#!/usr/bin/env python3
"""Gera o rascunho da ilha inicial (inspirada na estrutura de Rookgaard) em
godot/data/maps/ilha.txt. Depois de gerado, o mapa pode ser editado à mão.

Legenda:
  ~ água      , areia     . grama     : terra (estrada)   # calçamento
  f floresta  r rocha     = ponte/píer (anda sobre a água)
  H construção (bloqueia)  T templo (bloqueia)  @ início do jogador
"""
import math, random, sys

N = 56
random.seed(7)
g = [['~'] * N for _ in range(N)]
cx, cy = N / 2, N / 2

def noise(a):
    return sum(math.sin(a * k + p) * w for k, p, w in [(2, 0.3, 2.2), (3, 1.7, 1.5), (5, 2.9, 1.0), (7, 0.4, 0.6)])

# contorno da ilha
for y in range(N):
    for x in range(N):
        dx, dy = x - cx, y - cy
        r = math.hypot(dx, dy)
        edge = 22 + noise(math.atan2(dy, dx))
        if r < edge - 2.2:
            g[y][x] = '.'
        elif r < edge:
            g[y][x] = ','

def put(x, y, c, only=None):
    if 0 <= x < N and 0 <= y < N and (only is None or g[y][x] in only):
        g[y][x] = c

def rect(x0, y0, x1, y1, c, only=None):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(x, y, c, only)

def blob(x0, y0, rad, c, only='.,'):
    for y in range(int(y0 - rad - 2), int(y0 + rad + 3)):
        for x in range(int(x0 - rad - 2), int(x0 + rad + 3)):
            if math.hypot(x - x0, y - y0) < rad + noise(math.atan2(y - y0, x - x0) * 1.3) * 0.5:
                put(x, y, c, only)

# morros de rocha ao norte (cavernas), floresta a oeste e a leste do rio
blob(27, 11, 6.5, 'r')
blob(13, 26, 6.0, 'f')
blob(15, 36, 4.5, 'f')
blob(44, 22, 4.5, 'f')
blob(43, 36, 5.0, 'f')

# rio a leste, de norte a sul
for y in range(N):
    x = int(37 + math.sin(y * 0.25) * 1.5)
    for k in range(2):
        if g[y][x + k] != '~':
            put(x + k, y, '~')

# vila central: praça calçada
rect(22, 23, 33, 32, '#')
# estradas
for y in range(10, 23):
    put(27, y, ':', '.,rf'); put(28, y, ':', '.,rf')
for y in range(33, 50):
    put(27, y, ':', '.,f'); put(28, y, ':', '.,f')
for x in range(8, 22):
    put(x, 27, ':', '.,f'); put(x, 28, ':', '.,f')
for x in range(34, 52):
    put(x, 27, ':', '.,f'); put(x, 28, ':', '.,f')
# ponte sobre o rio e píer ao sul
for x in range(34, 42):
    for y in (27, 28):
        if g[y][x] == '~':
            put(x, y, '=')
for y in range(44, 55):
    for x in (27, 28):
        if g[y][x] in '~,':
            put(x, y, '=')

# construções da vila (templo ao norte da praça)
rect(25, 23, 30, 25, 'T')
for (x0, y0, x1, y1) in [(22, 29, 24, 31), (31, 29, 33, 31), (19, 23, 21, 25), (34, 23, 36, 25), (18, 33, 20, 35), (35, 33, 37, 35)]:
    rect(x0, y0, x1, y1, 'H', '.,#:')
put(27, 26, '@')

open(sys.argv[1] if len(sys.argv) > 1 else 'godot/data/maps/ilha.txt', 'w').write('\n'.join(''.join(r) for r in g) + '\n')
