#!/bin/bash
# Animações de magia em movimento (pernas andando/correndo + braços lançando) para o corpo base
# e todas as camadas; junta nas folhas que já existem (montar_camadas mescla o sprites.json).
B="/c/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe"
D="$(cd "$(dirname "$0")" && pwd -W)"
A="cast_walk=Walk_Loop+Spell_Simple_Shoot:8,cast_run=Jog_Fwd_Loop+Spell_Simple_Shoot:8"
L=${@:-base wolfcape wolfskirt mimic staff hood robe cape pauldron wizardhat helm circlet turban vest gloves pants kilt boots sandals rod wand book amulet}
for e in $L; do
  T="E:/Claude Jobs/arson/test/camadas_mag/$e"
  if [ "$e" = base ]; then O="E:/Claude Jobs/arson/godot/assets/personagens/base"; else O="E:/Claude Jobs/arson/godot/assets/equip/$e"; fi
  "$B" -b --factory-startup --python "$D/camadas.py" -- "$T" "$e" "$A" 16 CYCLES 2>&1 | grep -E "PRONTO|Error|Traceback" | cut -c1-80
  "$B" -b --factory-startup --python "$D/montar_camadas.py" -- "$T" "$O" 2>&1 | grep -E "MONTADO|Error" | cut -c1-80
  echo "FEITO $e $(date +%H:%M)"
done
echo LOTE_MAGIA_OK
