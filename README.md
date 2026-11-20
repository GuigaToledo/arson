# Arson

MMORPG online no navegador. Todos os jogadores ficam no mesmo mundo.

**Jogar:** https://guigatoledo.github.io/arson/

- Movimento livre (WASD / setas)
- Espaço seleciona alvo · Numpad 1–6 lança magias · Q/E poções · Enter abre o chat
- Mago: Ignis, Sopro de Chamas (cone), Corrente Elétrica (chain lightning), Meteoro (área), Nova Flamejante
- Mundo em 3D com personagens e monstros animados por esqueleto; o chão e o cenário são gerados por código.

Rede: PeerJS. O primeiro jogador hospeda o mundo e, se ele sair, outro assume automaticamente.

## Nova versão (Godot 4, 2D isométrico) — em construção

**Demo da taverna:** https://guigatoledo.github.io/arson/jogo/

- Projeto em `godot/` (abre no Godot 4.4+). Cada push em `godot/` é testado e exportado automaticamente para `/jogo/` pelo GitHub Actions.
- Equipamentos: um arquivo `.tres` por item em `godot/data/items/` (slot, atributos, sprites por direção). Item novo = arquivo novo; o código do personagem não muda.
- Personagem em camadas (corpo + 10 slots), 8 direções, camadas reordenadas por direção.
- A arte atual é provisória (formas simples). Os sprites finais virão de modelos 3D renderizados em 2D nas 8 direções.
- A versão antiga (3D, Three.js) continua na raiz do site.

## Créditos
Modelos 3D e animações: **KayKit** por Kay Lousberg (www.kaylousberg.com), licença CC0 (domínio público). Licença em `models/LICENSE-KayKit-CC0.txt`.
Motor 3D: Three.js (MIT). Rede: PeerJS (MIT).
Texturas do chão: **ambientCG** (Grass004, Ground037, Ground081, Ground054, PavingStones070, Rock030), licença CC0.
