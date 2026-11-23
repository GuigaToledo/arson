#!/bin/bash
D="$(cd "$(dirname "$0")" && pwd)"
TODAS="idle=Idle_Loop:8,walk=Walk_Loop:8,run=Jog_Fwd_Loop:8,cast=Spell_Simple_Shoot:6,damage=Hit_Chest:3,death=Death01:8"
MAGIA="cast_walk=Walk_Loop+Spell_Simple_Shoot:8,cast_run=Jog_Fwd_Loop+Spell_Simple_Shoot:8"
SPEC="$TODAS,$MAGIA" bash "$D/lote_spec.sh" book mimic
SPEC="cast=Spell_Simple_Shoot:6,$MAGIA" bash "$D/lote_spec.sh" staff rod wand
SPEC="$MAGIA" bash "$D/lote_spec.sh" base wolfcape wolfskirt hood robe cape pauldron wizardhat helm circlet turban vest gloves pants kilt boots sandals amulet
echo LOTE_FINAL_OK
