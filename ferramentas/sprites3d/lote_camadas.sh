#!/bin/bash
# Renderiza o corpo base e as camadas de todos os estilos de item (horas; roda em segundo plano).
# uso: bash lote_camadas.sh [estilos...]
B="/e/Claude Jobs/blender/blender-4.2.3-windows-x64/blender.exe"
D="$(cd "$(dirname "$0")" && pwd -W)"
A="idle=Idle_Loop:8,walk=Walk_Loop:8,run=Jog_Fwd_Loop:8,cast=Spell_Simple_Shoot:6,damage=Hit_Chest:3,death=Death01:8"
L=${@:-base wolfcape wolfskirt mimic staff hood robe cape pauldron wizardhat helm circlet turban vest gloves pants kilt boots sandals rod wand book amulet}
for e in $L; do
  T="E:/Claude Jobs/arson/test/camadas/$e"
  if [ "$e" = base ]; then O="E:/Claude Jobs/arson/godot/assets/personagens/base"; else O="E:/Claude Jobs/arson/godot/assets/equip/$e"; fi
  "$B" -b --python "$D/camadas.py" -- "$T" "$e" "$A" 16 CYCLES 2>&1 | grep -E "PRONTO|Error|Traceback" | cut -c1-80
  "$B" -b --python "$D/montar_camadas.py" -- "$T" "$O" 2>&1 | grep -E "MONTADO|Error" | cut -c1-80
  echo "FEITO $e $(date +%H:%M)"
done
echo LOTE_OK
