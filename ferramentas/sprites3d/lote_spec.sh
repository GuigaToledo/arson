#!/bin/bash
# Renderiza camadas com uma lista de animações qualquer e mescla nas folhas existentes.
# uso: SPEC="cast=Spell_Simple_Shoot:6" bash lote_spec.sh estilo1 estilo2 ...
B="/e/Claude Jobs/blender/blender-4.2.3-windows-x64/blender.exe"
D="$(cd "$(dirname "$0")" && pwd -W)"
for e in "$@"; do
  T="E:/Claude Jobs/arson/test/camadas_spec/$e-$RANDOM"
  if [ "$e" = base ]; then O="E:/Claude Jobs/arson/godot/assets/personagens/base"; else O="E:/Claude Jobs/arson/godot/assets/equip/$e"; fi
  "$B" -b --python "$D/camadas.py" -- "$T" "$e" "$SPEC" 16 CYCLES 2>&1 | grep -E "PRONTO|Error|Traceback" | cut -c1-80
  "$B" -b --python "$D/montar_camadas.py" -- "$T" "$O" 2>&1 | grep -E "MONTADO|Error" | cut -c1-80
  echo "FEITO $e $(date +%H:%M)"
done
