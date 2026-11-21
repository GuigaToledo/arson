#!/usr/bin/env python3
"""Gera o mapa grande: a ilha inicial (ilha_base.txt, 56x56, intacta no canto) +
o continente a leste com as regiões de cada categoria de monstro.

  python3 ferramentas/gerar_mapa.py  ->  godot/data/maps/ilha.txt

Novos caracteres:  g chão de cemitério   j selva   k chão de caverna
R parede de caverna (bloqueia)   b/o/y chão dos acampamentos goblin/orc/ciclope
"""
import math, random

W, H = 150, 120
BASE = 'godot/data/maps/ilha_base.txt'
OUT = 'godot/data/maps/ilha.txt'
rnd = random.Random(42)


def vnoise(seed):
    pts = {}
    def h(ix, iy):
        k = (ix, iy)
        if k not in pts:
            pts[k] = random.Random(ix * 7919 + iy * 104729 + seed).random()
        return pts[k]
    def f(x, y, s):
        x, y = x / s, y / s
        ix, iy = math.floor(x), math.floor(y)
        fx, fy = x - ix, y - iy
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = h(ix, iy) + (h(ix + 1, iy) - h(ix, iy)) * fx
        b = h(ix, iy + 1) + (h(ix + 1, iy + 1) - h(ix, iy + 1)) * fx
        return a + (b - a) * fy
    return f


n1, n2, n3 = vnoise(1), vnoise(2), vnoise(3)
m = [['~'] * W for _ in range(H)]
base = [l.rstrip('\n') for l in open(BASE) if l.strip()]
for y, l in enumerate(base):
    for x, c in enumerate(l):
        m[y][x] = c


def setc(x, y, c, only=None):
    if 0 <= x < W and 0 <= y < H and (x >= 58 or y >= 58):
        if only is None or m[y][x] in only:
            m[y][x] = c


def disk(cx, cy, r, c, only=None, wob=0.0):
    for y in range(int(cy - r - 3), int(cy + r + 4)):
        for x in range(int(cx - r - 3), int(cx + r + 4)):
            rr = r + (n3(x, y, 3) - 0.5) * wob
            if (x - cx) ** 2 + (y - cy) ** 2 <= rr * rr:
                setc(x, y, c, only)


# ---- continente: tudo a leste de x~60, borda irregular com areia
for y in range(H):
    for x in range(W):
        if x < 58 and y < 58:
            continue
        edge = min(x - 60, y - 2, W - 3 - x, H - 3 - y) + (n1(x, y, 6) - 0.5) * 7
        if x < 60 and y >= 58:
            edge = min(edge, y - 62 + (n1(x, y, 6) - 0.5) * 6, x - 4)
        if edge > 1.5:
            m[y][x] = '.'
        elif edge > 0:
            m[y][x] = ','

LAND = '.,'
# ---- Cemitério Esquecido (norte)
disk(86, 10, 9, 'g', LAND, 3)
# ---- Selva Rubra (sul), com borda de floresta comum
for y in range(44, H):
    for x in range(W):
        if m[y][x] == '.':
            v = n2(x, y, 9) + (y - 50) * 0.04
            if v > 0.75:
                m[y][x] = 'j'
            elif v > 0.5:
                m[y][x] = 'f'
for y in range(52, H):
    for x in range(W):
        if m[y][x] in '.f' and n1(x + 300, y, 5) > 0.35:
            m[y][x] = 'j'
# bosques na planície
for y in range(18, 46):
    for x in range(62, 102):
        if m[y][x] == '.' and n2(x + 100, y, 5) > 0.72:
            m[y][x] = 'f'
# ---- Caverna Uivante (nordeste): maciço de rocha com salões escavados
for y in range(5, 44):
    for x in range(104, 146):
        if m[y][x] in LAND + 'f':
            d = min(x - 104, y - 5, 145 - x, 43 - y)
            if d + (n1(x, y, 4) - 0.5) * 5 > 0:
                m[y][x] = 'R'
halls = [(108, 24, 3.5), (116, 22, 4.5), (124, 14, 5), (132, 22, 5.5), (126, 32, 5), (138, 34, 4.5), (139, 13, 4)]
for i, (cx, cy, r) in enumerate(halls):
    disk(cx, cy, r, 'k', 'R', 2.5)
    if i:
        px, py, _ = halls[i - 1] if i != 4 else halls[2]
        if i == 6:
            px, py, _ = halls[2]
        steps = int(math.hypot(cx - px, cy - py) * 2)
        for s in range(steps + 1):
            t = s / steps
            disk(px + (cx - px) * t, py + (cy - py) * t + math.sin(t * 6) * 1.2, 1.6, 'k', 'R')
disk(104.5, 24, 2.2, 'k', 'R')   # boca da caverna
# ---- acampamentos (clareiras)
CAMPS = {'b': (76, 66, 6.5), 'o': (124, 74, 7.5), 'y': (106, 104, 7)}
for c, (cx, cy, r) in CAMPS.items():
    disk(cx, cy, r + 2.5, '.', 'jf', 2)
    disk(cx, cy, r, c, None, 2)
# colinas de pedra perto dos ciclopes
for y in range(92, 116):
    for x in range(92, 124):
        if m[y][x] in 'jf.' and n1(x, y + 50, 4) > 0.62:
            m[y][x] = 'r'


# ---- estradas de terra
def road(pts, wdt=1.2):
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        steps = int(math.hypot(bx - ax, by - ay) * 3) + 1
        for s in range(steps + 1):
            t = s / steps
            x = ax + (bx - ax) * t + (n3(ax + t * 40, ay, 7) - 0.5) * 2.0 * (1 if abs(bx - ax) < abs(by - ay) else 0)
            y = ay + (by - ay) * t + (n3(ax, ay + t * 40, 7) - 0.5) * 2.0 * (1 if abs(bx - ax) >= abs(by - ay) else 0)
            disk(x, y, wdt, ':', '.,fjgr')


# ponte da estrada leste da vila até o continente (linhas 27-28)
for x in range(51, 63):
    for y in (27, 28):
        if m[y][x] in '~,':
            m[y][x] = '='
X = (95, 28)
road([(62, 27.5), (78, 27), X])
road([X, (90, 20), (86, 14)])
road([X, (100, 25), (103, 24)])
road([X, (92, 40), (84, 52), (78, 60)])
road([(92, 40), (104, 52), (118, 62), (122, 68)])
road([(104, 52), (100, 70), (98, 86), (104, 98)])

with open(OUT, 'w') as f:
    for row in m:
        f.write(''.join(row) + '\n')
print('mapa', W, 'x', H)
