#!/usr/bin/env python3
"""Layout da decoração dos prédios (móveis sem colisão, luzes e lugar dos NPCs) -> godot/data/interiores.json.
Medidas em metros a partir do canto de trás-esquerda do prédio (x leste, y sul); o script converte para tiles."""
import json
T = 0.643
Wm = {'casa_a': (7, 6), 'casa_b': (8, 6), 'loja': (9, 7), 'ferraria': (9, 7), 'guilda': (12, 8), 'templo': (11, 7), 'salao': (16, 11)}

SZ = {'mov_cama': (2.1, 1.3), 'mov_mesa': (1.5, .9), 'mov_mesa_longa': (3.6, 1.0), 'mov_cadeira': (.5, .5), 'mov_banco_p': (1.6, .45),
      'mov_estante': (1.6, .45), 'mov_bau': (1.0, .6), 'mov_lareira': (2.0, .8), 'mov_balcao_x': (3.4, .9), 'mov_balcao_y': (.9, 3.4),
      'mov_prateleira': (2.0, .4), 'mov_bigorna': (1.0, .6), 'mov_forja': (2.2, 1.6), 'mov_mesa_trabalho': (2.0, .8), 'mov_armas': (1.8, .4),
      'mov_altar': (2.4, 1.0), 'mov_banco_igreja': (2.6, .7), 'mov_quadro': (2.2, .2), 'mov_trono': (1.1, 1.0), 'mov_estandarte': (.5, .5),
      'mov_pilar': (.7, .7), 'mov_vaso': (.6, .6), 'mov_armario': (1.4, .6), 'mov_fogao': (1.2, .8)}

LAY = {
 'casa_a': dict(
   m=[('mov_lareira', .6, .45), ('mov_fogao', 3.1, .45), ('mov_estante', 5.0, .45), ('mov_armario', 8.4, .45),
      ('mov_cama', 8.2, 2.0), ('mov_mesa', 3.4, 3.6), ('mov_cadeira', 2.8, 3.8), ('mov_cadeira', 5.0, 3.8),
      ('mov_cadeira', 3.9, 2.8), ('mov_cadeira', 3.9, 4.6), ('mov_bau', .7, 6.6), ('mov_vaso', .7, 8.1), ('mov_vaso', 9.6, 8.1), ('mov_banco_p', 7.6, 6.8)],
   luz=[(1.6, 1.5, 'fogo'), (5.0, 4.0, 'sala')], npc=(4.4, 5.4)),
 'casa_b': dict(
   m=[('mov_cama', .6, .6), ('mov_armario', 3.3, .45), ('mov_estante', 5.4, .45), ('mov_lareira', 9.0, .45), ('mov_fogao', 7.3, .45),
      ('mov_mesa_longa', 4.4, 4.6), ('mov_banco_p', 4.9, 3.9), ('mov_banco_p', 4.9, 5.8), ('mov_bau', 10.4, 6.6),
      ('mov_vaso', 11.3, 8.1), ('mov_vaso', .7, 8.1), ('mov_cadeira', 3.7, 5.0), ('mov_cadeira', 8.4, 5.0)],
   luz=[(10.0, 1.5, 'fogo'), (6.0, 4.0, 'sala')], npc=(6.2, 7.2)),
 'loja': dict(
   m=[('mov_prateleira', 1.0, .45), ('mov_prateleira', 3.4, .45), ('mov_prateleira', 5.8, .45), ('mov_estante', 8.4, .45),
      ('mov_armario', 10.6, .45), ('mov_balcao_x', 3.0, 5.0), ('mov_balcao_y', 11.9, 3.0), ('mov_bau', .8, 8.4), ('mov_bau', 2.0, 8.4),
      ('mov_vaso', 12.9, .8), ('mov_vaso', 12.9, 9.8), ('mov_banco_p', 6.4, 8.8)],
   luz=[(4.8, 3.0, 'sala'), (10.0, 5.0, 'sala')], npc=(4.7, 3.9)),
 'ferraria': dict(
   m=[('mov_forja', .8, .45), ('mov_bigorna', 4.0, 2.6), ('mov_mesa_trabalho', 6.6, .45), ('mov_armas', 9.2, .45), ('mov_armas', 11.4, .45),
      ('mov_bau', 12.3, 6.8), ('mov_balcao_x', 5.0, 6.4), ('mov_prateleira', 12.0, 3.0), ('mov_banco_p', .9, 7.5)],
   luz=[(2.0, 1.8, 'fogo'), (7.0, 4.5, 'sala')], npc=(3.4, 4.2)),
 'guilda': dict(
   m=[('mov_estante', 5.2, .45), ('mov_lareira', 8.4, .45), ('mov_estante', 11.6, .45), ('mov_quadro', 1.6, .45), ('mov_quadro', 14.4, .45),
      ('mov_armas', 16.6, .45), ('mov_balcao_x', 7.6, 3.6), ('mov_mesa_longa', 1.2, 7.4), ('mov_banco_p', 1.6, 6.7), ('mov_banco_p', 1.6, 8.5),
      ('mov_mesa_longa', 13.0, 7.4), ('mov_banco_p', 13.4, 6.7), ('mov_banco_p', 13.4, 8.5), ('mov_vaso', .7, 11.2), ('mov_vaso', 17.6, 11.2), ('mov_bau', 16.8, 5.2)],
   luz=[(9.3, 2.0, 'fogo'), (4.0, 6.0, 'sala'), (15.0, 6.0, 'sala')], npc=(9.3, 2.4)),
 'templo': dict(
   m=[('mov_altar', 7.4, .8), ('mov_vaso', 5.6, .8), ('mov_vaso', 10.7, .8), ('mov_estandarte', 4.0, .8), ('mov_estandarte', 12.6, .8),
      ('mov_banco_igreja', 3.5, 4.4), ('mov_banco_igreja', 3.5, 6.0), ('mov_banco_igreja', 3.5, 7.6),
      ('mov_banco_igreja', 11.0, 4.4), ('mov_banco_igreja', 11.0, 6.0), ('mov_banco_igreja', 11.0, 7.6),
      ('mov_pilar', 1.6, 3.2), ('mov_pilar', 14.8, 3.2), ('mov_pilar', 1.6, 8.0), ('mov_pilar', 14.8, 8.0)],
   luz=[(8.5, 2.2, 'vela'), (4.0, 3.0, 'vela'), (13.0, 3.0, 'vela')], npc=(8.5, 3.4)),
 'salao': dict(
   m=[('mov_trono', 11.9, 1.0), ('mov_estandarte', 9.0, 1.0), ('mov_estandarte', 15.3, 1.0), ('mov_lareira', 2.6, .45), ('mov_lareira', 20.3, .45),
      ('mov_armas', 6.0, .45), ('mov_armas', 17.0, .45), ('mov_pilar', 5.0, 5.0), ('mov_pilar', 19.2, 5.0), ('mov_pilar', 5.0, 11.2), ('mov_pilar', 19.2, 11.2),
      ('mov_mesa_longa', 4.2, 9.0), ('mov_banco_p', 4.7, 8.3), ('mov_banco_p', 4.7, 10.1), ('mov_mesa_longa', 16.8, 9.0), ('mov_banco_p', 17.2, 8.3), ('mov_banco_p', 17.2, 10.1),
      ('mov_bau', 1.0, 14.6), ('mov_bau', 22.8, 14.6), ('mov_vaso', .8, 8.0), ('mov_vaso', 23.4, 8.0)],
   luz=[(3.5, 2.0, 'fogo'), (21.0, 2.0, 'fogo'), (12.4, 6.0, 'sala'), (12.4, 12.0, 'sala')], npc=(12.4, 4.0)),
}
out = {}
for tipo, d in LAY.items():
    out[tipo] = dict(
        w=Wm[tipo][0], h=Wm[tipo][1],
        moveis=[[n, round(x * T, 3), round(y * T, 3), round(SZ[n][0] * T, 3), round(SZ[n][1] * T, 3)] for n, x, y in d['m']],
        luzes=[[round(x * T, 2), round(y * T, 2), k] for x, y, k in d['luz']],
        npc=[round(d['npc'][0] * T, 2), round(d['npc'][1] * T, 2)])
json.dump(out, open('godot/data/interiores.json', 'w'), indent=0)
print('ok', {k: len(v['moveis']) for k, v in out.items()})
