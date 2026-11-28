#!/usr/bin/env python3
"""Prédios por dentro: para cada prédio gera duas imagens com a mesma origem.

  <nome>_fundo.png   piso, paredes dos fundos (por dentro) e janelas; fica sempre embaixo de tudo
  <nome>_frente.png  paredes da frente (com o vão da porta), telhado e detalhes; some quando o
                     jogador entra, deixando ver o interior

Também gera os móveis (sem colisão no jogo). Tamanhos em tiles do mapa (1 tile = 1/0,643 m).

  python3 ferramentas/desenhar_interiores.py [prédio|moveis ...]
"""
import os, sys, json, math
import numpy as np
import desenhar_pecas as dp
from desenhar_pecas import (noise_tex, photo_tex, wood_tex, shingles, timber_wall, window_tex, smooth_noise)
from desenhar_cidade import Big, cv, save, merlons, pyramid, slit, banner_tex, sign_tex, awning_tex, stones

T = 0.643
TW = 0.42   # espessura das paredes (m)


def m(t):
    return t / T


def stone_walls(L, H):
    st, stl = stones()
    return stl


def plaster():
    return noise_tex(128, 128, (0.58, 0.5, 0.4), 0.14, 6, 21, 0.06)


def floor_planks(seed=1, base=(0.3, 0.21, 0.13)):
    return wood_tex(seed=seed, planks=8, base=base, vertical=False)


def floor_slabs():
    return photo_tex('godot/assets/textures/stone_c.jpg', 0.75)


def rug_tex(a, b):
    w = h = 64
    img = np.zeros((h, w, 3), np.float32) + np.array(a)
    yy, xx = np.mgrid[0:h, 0:w]
    border = (xx < 6) | (xx > w - 7) | (yy < 6) | (yy > h - 7)
    inner = (xx > 14) & (xx < w - 15) & (yy > 14) & (yy < h - 15)
    img[border] = b
    img[inner] = np.array(a) * 0.75
    return img * (0.9 + 0.1 * smooth_noise(w, h, 3, 4))[..., None]


# estilos: parede (timber|stone), piso, telhado, altura da parede, janelas, tapetes
ESTILOS = {
    'casa_a': dict(wall='timber', floor='planks', roof=(0.2, 0.16, 0.14), H=3.1, door=3.2, win_f=[1.2, 5.0], win_l=[1.5, 3.8],
                   rugs=[(1.2, 1.2, 3.2, 2.2, (0.45, 0.14, 0.12), (0.7, 0.6, 0.3))], chim=True),
    'casa_b': dict(wall='timber', floor='planks', roof=(0.12, 0.2, 0.18), H=3.1, door=3.8, win_f=[1.4, 5.8], win_l=[1.6, 4.4],
                   rugs=[(1.8, 1.4, 3.4, 2.4, (0.2, 0.3, 0.4), (0.7, 0.65, 0.45))], chim=True),
    'loja': dict(wall='timber', floor='planks', roof=(0.12, 0.2, 0.18), H=3.2, door=6.2, win_f=[1.2, 3.0], win_l=[1.8, 4.8],
                 rugs=[(1.2, 3.0, 5.0, 2.0, (0.4, 0.12, 0.12), (0.75, 0.65, 0.3))], chim=True, awning=(1.0, 3.2), sign='pocao'),
    'ferraria': dict(wall='stone', floor='slabs', roof=(0.2, 0.16, 0.14), H=3.4, door=6.2, win_f=[1.4], win_l=[2.0, 4.6],
                     rugs=[], chim=True, sign='bigorna'),
    'guilda': dict(wall='timber', floor='planks', roof=(0.3, 0.17, 0.12), H=3.9, door=6.0, win_f=[1.5, 3.3, 8.2, 10.2], win_l=[2.2, 5.0],
                   rugs=[(2.0, 2.2, 8.0, 3.8, (0.15, 0.22, 0.45), (0.8, 0.68, 0.3))], banners=[2.6, 9.2], sign='espadas'),
    'templo': dict(wall='stone', floor='slabs', roof=(0.16, 0.16, 0.18), H=4.2, door=5.5, win_f=[1.6, 3.6, 7.4, 9.4], win_l=[1.8, 4.6],
                   rugs=[(3.4, 0.8, 4.4, 5.2, (0.35, 0.1, 0.12), (0.8, 0.7, 0.35))], tower=True),
    'salao': dict(wall='stone', floor='slabs', roof=(0.38, 0.14, 0.1), H=5.2, door=8.0, win_f=[2.0, 4.4, 11.6, 14.0], win_l=[2.6, 5.6, 8.4],
                  rugs=[(3.2, 1.6, 9.6, 6.6, (0.5, 0.1, 0.1), (0.85, 0.72, 0.3))], banners=[3.4, 6.4, 9.6, 12.6], tower=True),
}


def wall_tex(sty, w_m, h_m, seed):
    if sty['wall'] == 'stone':
        return photo_tex('godot/assets/textures/stone_c.jpg', 0.8)
    return timber_wall(w_m, h_m, seed=seed)


def casco(name, Wt, Ht, estilo, door_w_t=1.7):
    S = ESTILOS[estilo]
    L, D, H = m(Wt), m(Ht), S['H']
    st, stl = stones()
    dark = wood_tex(seed=3, base=(0.18, 0.13, 0.09), planks=1)
    win = window_tex()
    pl = plaster()
    hr = min(D * 0.3, 4.6)
    extra = (6.5 if S.get('tower') else 0.0) + (2.0 if S.get('chim') else 0.0)
    old = (dp.SS, dp.M, dp.EX, dp.EY, dp.EZ)
    if Wt * Ht > 60:
        dp.SS = 1   # peças grandes: sem superamostragem extra (memória)
        dp.M = 46.0 * dp.SS * dp.RES
        dp.EX = np.array([0.894, 0.447]) * dp.M
        dp.EY = np.array([-0.894, 0.447]) * dp.M
        dp.EZ = np.array([0.0, -1.0]) * dp.M
    try:
        # ---------------------------------------------------------------- fundo
        c = cv(L, D, H + hr + extra, pad=50, extra_h=0.5)
        fl = floor_planks(seed=len(name)) if S['floor'] == 'planks' else floor_slabs()
        c.face((0, 0, 0), (L, 0, 0), (0, D, 0), fl, 0.95, (max(2, int(L / 1.6)), max(2, int(D / 1.6))))
        for (rx, ry, rw, rh, ca, cb) in S.get('rugs', []):
            c.face((m(rx), m(ry), 0.01), (m(rw), 0, 0), (0, m(rh), 0), rug_tex(ca, cb), 0.95)
        # paredes dos fundos por dentro (y=0 e x=0)
        c.box(0, 0, 0, L, TW, H, pl, stl, uv_side=(max(2, int(L / 2.5)), 1))
        c.box(0, 0, 0, TW, D, H, pl, stl, uv_side=(max(2, int(D / 2.5)), 1))
        # rodapé de madeira
        c.face((TW, TW + 0.01, 0.9), (L - TW, 0, 0), (0, 0, -0.9), dark, 0.8)
        c.face((TW + 0.01, TW, 0.9), (0, D - TW, 0), (0, 0, -0.9), dark, 0.6)
        # janelas por dentro (claras: entra luz)
        for wx in S['win_f']:
            if wx + 1.0 < Wt:
                c.face((m(wx), TW + 0.02, H - 0.7), (0.9, 0, 0), (0, 0, -1.0), win, 1.0, emit=True)
        for wy in S['win_l']:
            c.face((TW + 0.02, m(wy) + 0.9, H - 0.7), (0, -0.9, 0), (0, 0, -1.0), win, 0.9, emit=True)
        if S.get('banners'):
            ban = banner_tex((0.15, 0.25, 0.5) if estilo == 'guilda' else (0.55, 0.1, 0.1))
            for bx in S['banners']:
                c.face((m(bx), TW + 0.03, H - 0.5), (0.8, 0, 0), (0, 0, -2.1), ban, 0.95)
        dp.ANCHORS.clear()
        save(c, name + '_fundo')

        # ---------------------------------------------------------------- frente
        c = cv(L, D, H + hr + extra, pad=50, extra_h=0.5)
        door_u = S['door']
        dw = m(door_w_t)
        dx0, dx1 = m(door_u) - dw / 2, m(door_u) + dw / 2
        dh = 2.5
        wt = wall_tex(S, L, H, 31)
        uvs = (max(2, int(L / 2.5)), 1)
        # parede da frente (+y) em três partes: esquerda, direita e verga sobre a porta
        c.box(0, D - TW, 0, dx0, TW, H, wt, stl, uv_side=(max(1, int(dx0 / 2.5)), 1))
        c.box(dx1, D - TW, 0, L - dx1, TW, H, wt, stl, uv_side=(max(1, int((L - dx1) / 2.5)), 1))
        c.box(dx0, D - TW, dh, dx1 - dx0, TW, H - dh, wt, stl)
        # batentes de pedra
        c.box(dx0 - 0.15, D - TW - 0.05, 0, 0.2, TW + 0.1, dh + 0.25, st)
        c.box(dx1 - 0.05, D - TW - 0.05, 0, 0.2, TW + 0.1, dh + 0.25, st)
        c.box(dx0 - 0.15, D - TW - 0.05, dh, dx1 - dx0 + 0.3, TW + 0.1, 0.25, st)
        # parede da direita (+x)
        c.box(L - TW, 0, 0, TW, D, H, wall_tex(S, D, H, 32), stl, uv_side=(max(2, int(D / 2.5)), 1))
        # soleira da porta
        c.box(dx0 - 0.1, D - 0.02, 0, dx1 - dx0 + 0.2, 0.5, 0.12, st)
        # janelas por fora
        for wx in S['win_f']:
            wxm = m(wx)
            if wxm + 0.9 < dx0 - 0.3 or wxm > dx1 + 0.3:
                c.face((wxm, D - 0.02, H - 0.55), (0.9, 0, 0), (0, 0, -1.0), win, 1.0, emit=True)
                c.glow((wxm + 0.45, D, H - 1.0), 34, (1.0, 0.6, 0.2), 0.4)
        for wy in S['win_l']:
            c.face((L - 0.02, m(wy) + 0.9, H - 0.55), (0, -0.9, 0), (0, 0, -1.0), win, 0.9, emit=True)
        if S.get('banners') and estilo == 'guilda':
            ban = banner_tex((0.15, 0.25, 0.5))
            for bx in (S['banners'][0] + 1.0, S['banners'][1] - 1.0):
                c.face((m(bx), D + 0.0, H - 0.5), (0.7, 0, 0), (0, 0, -1.6), ban, 0.95)
        if S.get('sign'):
            from desenhar_cidade import poste_placa
            poste_placa(c, dx1 + 0.4, D, H - 0.9, sign_tex(S['sign']), 'y')
        if S.get('awning'):
            aw = awning_tex()
            c.face((m(S['awning'][0]), D, H - 0.6), (m(S['awning'][1] - S['awning'][0]) + 0.2, 0, 0), (0, 0.95, -0.55), aw, 0.9)
        # telhado de duas águas, cumeeira ao longo de X, com beiral
        e = 0.55
        roof = shingles(base=S['roof'], seed=60 + len(name), rows=18)
        zr = H
        yc = -e + (D + 2 * e) / 2
        c.face((-e, -e, zr), (L + 2 * e, 0, 0), (0, (D + 2 * e) / 2, hr), roof, 0.6, (max(3, int(L / 2.2)), 2))
        gab = wall_tex(S, D, hr, 33)
        c.face((L + e, D + e, zr), (0, -(D + 2 * e), 0), (0, -(D + 2 * e) / 2, hr), gab, 0.5, (1, 1), tri=True)
        c.face((-e, yc, zr + hr), (L + 2 * e, 0, 0), (0, (D + 2 * e) / 2, -hr), roof, 0.8, (max(3, int(L / 2.2)), 2))
        if S.get('chim'):
            c.box(L * 0.18, D * 0.2, zr + 0.5, 0.7, 0.7, hr + 1.7, stl, uv_side=(1, 2))
            if estilo == 'ferraria':
                c.glow((L * 0.18 + 0.35, D * 0.2 + 0.7, zr + hr + 2.0), 30, (1.0, 0.4, 0.1), 0.35)
        if S.get('tower'):
            TS = 3.4 if estilo == 'templo' else 4.6
            tx, ty = L - TS - 0.4, D * 0.18
            tz = zr + hr * 0.5
            th = 6.0 if estilo == 'templo' else 5.5
            c.box(tx, ty, zr, TS, TS, th, stl, uv_side=(2, 3))
            slate = shingles(base=(0.16, 0.16, 0.18) if estilo == 'templo' else (0.38, 0.14, 0.1), seed=44, rows=14)
            pyramid(c, tx - 0.25, ty - 0.25, tx + TS + 0.25, ty + TS + 0.25, zr + th, 2.9, slate, uv=(2, 2))
            c.face((tx + TS * 0.5 - 0.3, ty + TS - 0.03, zr + th - 1.4), (0.6, 0, 0), (0, 0, -1.0), win, 1.0, emit=True)
        dp.ANCHORS.clear()
        save(c, name + '_frente')
    finally:
        dp.SS, dp.M, dp.EX, dp.EY, dp.EZ = old


# ---------------------------------------------------------------- móveis (pequenos, sem colisão)

def moveis():
    st, stl = stones()
    wood = wood_tex(seed=1)
    wood2 = wood_tex(seed=4, base=(0.22, 0.17, 0.12), planks=3)
    dark = wood_tex(seed=3, base=(0.18, 0.13, 0.09), planks=1)
    wood_h = wood_tex(seed=2, vertical=False)
    iron = dp.iron_tex()
    cloth_r = noise_tex(64, 64, (0.5, 0.12, 0.12), 0.15, 4, 5, 0.05)
    cloth_w = noise_tex(64, 64, (0.75, 0.72, 0.65), 0.12, 4, 6, 0.05)
    cloth_b = noise_tex(64, 64, (0.15, 0.25, 0.5), 0.12, 4, 7, 0.05)
    straw = noise_tex(64, 64, (0.6, 0.5, 0.25), 0.2, 3, 8, 0.1)

    def mk(name, L, D, H, fn, pad=20):
        c = cv(L, D, H, pad=pad)
        fn(c)
        dp.ANCHORS.clear()
        save(c, name)

    mk('mov_cama', 2.1, 1.3, 1.0, lambda c: (
        c.box(0, 0, 0, 2.1, 1.3, 0.4, wood), c.box(0.05, 0.05, 0.4, 1.95, 1.2, 0.2, cloth_w),
        c.box(0.05, 0.1, 0.6, 0.5, 1.1, 0.14, cloth_w), c.box(1.0, 0.05, 0.6, 1.1, 1.2, 0.08, cloth_r),
        c.box(0, 0, 0.4, 0.1, 1.3, 0.6, wood2)))
    mk('mov_mesa', 1.5, 0.9, 0.9, lambda c: (
        [c.box(x, y, 0, 0.1, 0.1, 0.78, dark) for x in (0.05, 1.35) for y in (0.05, 0.75)],
        c.box(0, 0, 0.78, 1.5, 0.9, 0.1, wood_h)))
    mk('mov_mesa_longa', 3.6, 1.0, 0.9, lambda c: (
        [c.box(x, y, 0, 0.12, 0.12, 0.78, dark) for x in (0.1, 3.38) for y in (0.06, 0.82)],
        c.box(0, 0, 0.78, 3.6, 1.0, 0.1, wood_h), c.box(0.4, 0.3, 0.88, 0.25, 0.25, 0.3, iron), c.box(1.8, 0.4, 0.88, 0.3, 0.3, 0.12, straw)))
    mk('mov_cadeira', 0.5, 0.5, 1.0, lambda c: (
        [c.box(x, y, 0, 0.06, 0.06, 0.45, dark) for x in (0.02, 0.42) for y in (0.02, 0.42)],
        c.box(0, 0, 0.45, 0.5, 0.5, 0.06, wood), c.box(0, 0, 0.51, 0.5, 0.06, 0.5, wood2)))
    mk('mov_banco_p', 1.6, 0.45, 0.55, lambda c: (
        c.box(0.05, 0.05, 0, 0.1, 0.35, 0.4, dark), c.box(1.45, 0.05, 0, 0.1, 0.35, 0.4, dark), c.box(0, 0, 0.4, 1.6, 0.45, 0.08, wood_h)))
    mk('mov_estante', 1.6, 0.45, 2.2, lambda c: (
        c.box(0, 0, 0, 1.6, 0.45, 2.2, dark),
        [c.box(0.08 + i * 0.4, 0.05, z, 0.28, 0.3, 0.32, noise_tex(16, 16, col, 0.2, 3, 90 + i))
         for z, cols in ((0.1, [(0.5, 0.15, 0.15), (0.15, 0.3, 0.5), (0.5, 0.4, 0.1), (0.2, 0.4, 0.2)]), (0.8, [(0.4, 0.2, 0.1), (0.5, 0.5, 0.45), (0.2, 0.2, 0.4), (0.5, 0.15, 0.3)]), (1.5, [(0.3, 0.3, 0.4), (0.5, 0.35, 0.1), (0.4, 0.1, 0.1), (0.2, 0.35, 0.3)]))
         for i, col in enumerate(cols)]))
    mk('mov_bau', 1.0, 0.6, 0.7, lambda c: (
        c.box(0, 0, 0, 1.0, 0.6, 0.5, wood2), c.box(-0.02, -0.02, 0.5, 1.04, 0.64, 0.2, wood), c.box(0.45, 0.58, 0.3, 0.1, 0.06, 0.2, iron)))
    mk('mov_lareira', 2.0, 0.8, 2.4, lambda c: (
        c.box(0, 0, 0, 2.0, 0.8, 2.4, stl, uv_side=(2, 2)),
        c.face((0.4, 0.8 - 0.02, 1.2), (1.2, 0, 0), (0, 0, -1.1), np.zeros((4, 4, 3)) + 0.05, 1.0),
        c.face((0.55, 0.8 - 0.03, 0.55), (0.9, 0, 0), (0, 0, -0.4), np.zeros((4, 4, 3)) + np.array([1.0, 0.45, 0.12]), 1.0, emit=True),
        c.glow((1.0, 0.8, 0.5), 46, (1.0, 0.45, 0.1), 0.8), c.box(-0.1, 0, 2.3, 2.2, 0.9, 0.12, st)))
    mk('mov_balcao_x', 3.4, 0.9, 1.1, lambda c: (
        c.box(0, 0, 0, 3.4, 0.9, 1.0, wood2, wood_h, uv_side=(3, 1)), c.box(-0.05, -0.05, 1.0, 3.5, 1.0, 0.1, dark),
        c.box(0.4, 0.3, 1.1, 0.35, 0.35, 0.3, noise_tex(16, 16, (0.7, 0.2, 0.3), 0.2, 3, 91)),
        c.box(1.2, 0.2, 1.1, 0.5, 0.4, 0.14, cloth_w), c.box(2.4, 0.3, 1.1, 0.3, 0.3, 0.3, noise_tex(16, 16, (0.2, 0.4, 0.7), 0.2, 3, 92))))
    mk('mov_balcao_y', 0.9, 3.4, 1.1, lambda c: (
        c.box(0, 0, 0, 0.9, 3.4, 1.0, wood2, wood_h, uv_side=(3, 1)), c.box(-0.05, -0.05, 1.0, 1.0, 3.5, 0.1, dark),
        c.box(0.3, 0.5, 1.1, 0.3, 0.3, 0.3, noise_tex(16, 16, (0.7, 0.2, 0.3), 0.2, 3, 91)), c.box(0.2, 1.7, 1.1, 0.4, 0.5, 0.14, cloth_w)))
    mk('mov_prateleira', 2.0, 0.4, 1.9, lambda c: (
        c.box(0, 0, 0, 2.0, 0.4, 1.9, dark),
        [c.box(0.12 + i * 0.36, 0.08, z, 0.2, 0.22, 0.34, noise_tex(16, 16, col, 0.3, 3, 80 + i + int(z * 10)))
         for z in (0.15, 0.75, 1.35) for i, col in enumerate([(0.75, 0.15, 0.2), (0.15, 0.4, 0.75), (0.2, 0.65, 0.3), (0.7, 0.55, 0.1), (0.5, 0.2, 0.6)])]))
    mk('mov_bigorna', 1.0, 0.6, 1.0, lambda c: (
        c.box(0.25, 0.15, 0, 0.5, 0.3, 0.45, dark), c.box(0.1, 0.08, 0.45, 0.8, 0.44, 0.2, iron), c.box(-0.1, 0.18, 0.55, 0.25, 0.24, 0.1, iron)))
    mk('mov_forja', 2.2, 1.6, 1.8, lambda c: (
        c.box(0, 0, 0, 2.2, 1.6, 0.9, stl, uv_side=(2, 1)),
        c.face((0.4, 1.58, 0.9), (1.4, 0, 0), (0, 0, -0.55), np.zeros((4, 4, 3)) + np.array([1.0, 0.4, 0.1]), 1.0, emit=True),
        c.glow((1.1, 1.0, 0.9), 54, (1.0, 0.4, 0.1), 0.9), c.box(0.3, 0.1, 0.9, 1.6, 0.7, 0.9, stl, uv_side=(2, 1))))
    mk('mov_mesa_trabalho', 2.0, 0.8, 0.95, lambda c: (
        [c.box(x, y, 0, 0.1, 0.1, 0.82, dark) for x in (0.05, 1.85) for y in (0.05, 0.65)],
        c.box(0, 0, 0.82, 2.0, 0.8, 0.1, wood_h), c.box(0.2, 0.2, 0.92, 0.9, 0.12, 0.06, iron), c.box(1.3, 0.3, 0.92, 0.3, 0.3, 0.14, iron)))
    mk('mov_armas', 1.8, 0.4, 1.7, lambda c: (
        c.box(0, 0, 0, 1.8, 0.1, 1.7, dark),
        [c.box(0.2 + i * 0.4, 0.12, 0.3, 0.07, 0.07, 1.2, iron) for i in range(4)],
        [c.box(0.15 + i * 0.4, 0.1, 1.45, 0.18, 0.1, 0.12, dark) for i in range(4)]))
    mk('mov_altar', 2.4, 1.0, 1.4, lambda c: (
        c.box(0, 0, 0, 2.4, 1.0, 0.25, st), c.box(0.2, 0.1, 0.25, 2.0, 0.8, 0.85, stl, uv_side=(2, 1)), c.box(0.1, 0.0, 1.1, 2.2, 1.0, 0.12, st),
        [c.box(0.35 + i * 0.7, 0.35, 1.22, 0.16, 0.16, 0.35, noise_tex(16, 16, (0.85, 0.8, 0.6), 0.1, 3, 70)) for i in range(3)],
        [c.glow((0.43 + i * 0.7, 0.43, 1.6), 22, (1.0, 0.7, 0.3), 0.7) for i in range(3)],
        c.box(1.05, 0.38, 1.22, 0.3, 0.24, 0.1, cloth_w)))
    mk('mov_banco_igreja', 2.6, 0.7, 0.9, lambda c: (
        c.box(0.05, 0.05, 0, 0.12, 0.6, 0.45, dark), c.box(2.43, 0.05, 0, 0.12, 0.6, 0.45, dark), c.box(0, 0.1, 0.45, 2.6, 0.55, 0.08, wood_h),
        c.box(0, 0, 0.45, 2.6, 0.08, 0.5, wood2)))
    mk('mov_quadro', 2.2, 0.2, 2.0, lambda c: (
        c.box(0, 0, 0, 0.12, 0.12, 1.9, dark), c.box(2.08, 0, 0, 0.12, 0.12, 1.9, dark), c.box(0, 0, 0.8, 2.2, 0.1, 1.1, wood2),
        [c.box(0.2 + (i % 3) * 0.65, 0.1, 1.05 + (i // 3) * 0.45, 0.45, 0.02, 0.35, cloth_w) for i in range(6)]))
    mk('mov_trono', 1.1, 1.0, 2.2, lambda c: (
        c.box(0, 0, 0, 1.1, 1.0, 0.25, st), c.box(0.1, 0.1, 0.25, 0.9, 0.8, 0.5, cloth_r), c.box(0.1, 0.0, 0.25, 0.9, 0.14, 1.9, dark),
        c.box(0.0, 0.1, 0.5, 0.12, 0.8, 0.4, dark), c.box(1.0, 0.1, 0.5, 0.12, 0.8, 0.4, dark),
        c.box(0.3, 0.0, 2.15, 0.5, 0.14, 0.2, noise_tex(16, 16, (0.85, 0.7, 0.2), 0.1, 3, 71))))
    mk('mov_estandarte', 0.5, 0.5, 2.6, lambda c: (
        c.box(0.2, 0.2, 0, 0.1, 0.1, 2.5, dark), c.face((0.3, 0.25, 2.4), (0.0, 0.0, 0), (0, 0, 0), dark, 1.0),
        c.face((0.12, 0.25, 2.45), (0.38, 0, 0), (0, 0, -1.6), banner_tex((0.55, 0.1, 0.1)), 0.95)))
    mk('mov_pilar', 0.7, 0.7, 4.0, lambda c: (
        c.box(0, 0, 0, 0.7, 0.7, 0.3, st), c.box(0.08, 0.08, 0.3, 0.54, 0.54, 3.5, stl, uv_side=(1, 3)), c.box(0, 0, 3.8, 0.7, 0.7, 0.2, st)))
    mk('mov_vaso', 0.6, 0.6, 1.2, lambda c: (
        c.box(0.15, 0.15, 0, 0.3, 0.3, 0.45, noise_tex(16, 16, (0.5, 0.3, 0.2), 0.2, 3, 72)),
        c.blob(0.3, 0.3, 0.75, 0.3, noise_tex(16, 16, (0.15, 0.4, 0.15), 0.3, 3, 73), ry=0.8) if hasattr(c, 'blob') and False else c.box(0.1, 0.1, 0.45, 0.4, 0.4, 0.5, noise_tex(16, 16, (0.15, 0.4, 0.15), 0.3, 3, 73))))
    mk('mov_tapete_p', 1.0, 1.0, 0.1, lambda c: c.face((0, 0, 0.01), (1.0, 0, 0), (0, 1.0, 0), rug_tex((0.4, 0.12, 0.12), (0.8, 0.7, 0.3)), 1.0))
    mk('mov_armario', 1.4, 0.6, 2.0, lambda c: (
        c.box(0, 0, 0, 1.4, 0.6, 2.0, wood2), c.box(0.68, 0.58, 0.3, 0.04, 0.04, 1.4, dark), c.box(0.25, 0.58, 0.9, 0.08, 0.06, 0.25, iron)))
    mk('mov_fogao', 1.2, 0.8, 1.2, lambda c: (
        c.box(0, 0, 0, 1.2, 0.8, 0.9, stl, uv_side=(1, 1)), c.face((0.25, 0.78, 0.7), (0.6, 0, 0), (0, 0, -0.4), np.zeros((4, 4, 3)) + np.array([1.0, 0.4, 0.1]), 1.0, emit=True),
        c.glow((0.55, 0.8, 0.5), 30, (1.0, 0.4, 0.1), 0.6), c.box(0.5, 0.3, 0.9, 0.2, 0.2, 0.9, stl)))


PREDIOS = {
    'casa_a': (7, 6, 'casa_a'),
    'casa_b': (8, 6, 'casa_b'),
    'loja': (9, 7, 'loja'),
    'ferraria': (9, 7, 'ferraria'),
    'guilda': (12, 8, 'guilda'),
    'templo': (11, 7, 'templo'),
    'salao': (16, 11, 'salao'),
}

if __name__ == '__main__':
    os.makedirs(dp.OUT, exist_ok=True)
    want = sys.argv[1:] or (list(PREDIOS) + ['moveis'])
    for n in want:
        if n == 'moveis':
            moveis()
        else:
            w, h, e = PREDIOS[n]
            casco(n, w, h, e)
