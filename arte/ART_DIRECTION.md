# Arson — Direção de Arte (Visual Factory)

Dark fantasy isométrico semi-realista, 2.5D, inspirado em Diablo 2. Todo recurso novo segue
este documento. Referência viva: as fotos da inspeção automática (ramo `visual-qa`).

## 1. Perspectiva e escala

| Item | Regra |
| --- | --- |
| Projeção | Isométrica 2:1. Um tile = 128 × 64 px na tela (`Iso.to_screen`). |
| Câmera | Não muda. Zoom só pelo menu do jogador. |
| Personagem adulto | ~92 px de altura (≈ 1,45 tile). Medida de tudo. |
| Porta | 1,3 × a altura do personagem (~120 px). |
| Janela | Altura ≤ 0,45 × personagem (~40 px); peitoril na altura do peito. |
| Árvore comum | 3,5 a 5 × o personagem. |
| Pedra pequena / arbusto | 0,3 a 0,6 × o personagem. |
| Monstros | Pela espécie (slime 0,4 ×, lobo 0,7 ×, troll 1,4 ×, ciclope 2 ×); chefes até +60%. |
| Resolução dos PNG | Desenhados em 2× e mostrados em 0,5 (nitidez em telas densas). |

Pé no chão: todo objeto tem âncora no ponto de contato com o solo (`ancoras.json`) e
sombra de contato. Nada flutua.

## 2. Paleta

Cores frias e terrosas, pouco saturadas; a saturação alta fica reservada para luz, magia e perigo.

| Uso | Cores (hex) |
| --- | --- |
| Terra e pedra | `#3a332b` `#5a4e40` `#7a6c5a` `#8c8478` |
| Vegetação | `#2e3a22` `#3f5230` `#5a6b3a` (outono `#7a4a22`) |
| Madeira | `#3b2a1c` `#5a3f28` `#7a5a3a` |
| Tecido e couro | `#4a2a24` `#5a4632` `#2f3440` |
| Metal | `#4a4e55` `#8a8f96` (brilho `#c8ccd2`) |
| Luz quente (fogo, lampião) | `#ff9a3c` `#ffcf7a` |
| Luz fria (lua, gelo) | `#7fa8ff` `#c8e4ff` |
| Magia | a cor do elemento em `Spellbook.ELEMENTS` |
| Perigo / chefes | `#ff3a2a` |

Proibido: preto puro (`#000`) em áreas grandes, branco puro fora de brilhos, verde neon fora de veneno e cogumelos.

## 3. Luz e contraste

- O dia é escurecido, mas legível: o chão nunca fica abaixo de ~30% de brilho (CanvasModulate do dia ≈ `#9e998c`).
- A noite é azulada; tudo que emite luz (fogo, lampião, cristal, lava, magia) ganha destaque.
- Fogueiras, lampiões, lava e magias de fogo usam PointLight2D. A luz do sol não projeta sombra por oclusor (gerava faixas duras); cada objeto tem sombra macia própria, puxada para baixo e à direita.
- Contraste: silhuetas escuras contra o chão médio; o detalhe fica no meio-tom.
- Orçamento de luzes dinâmicas na tela: Ultra 24 · Alto 16 · Médio 10 · Baixo 6.

## 4. Materiais e detalhe

- Madeira: veio, tábuas com variação de tom, quinas gastas.
- Pedra: blocos irregulares, musgo na base, rachaduras finas.
- Telhado: telhas/palha com fileiras, beiral escuro, sujeira na parte baixa.
- Tecido: dobras, bainha desgastada, sem cor chapada.
- Metal: reflexo pequeno e duro, ferrugem nas juntas.
- Desgaste em tudo que é de vila (nada novo de fábrica).
- Repetição: no máximo 2 peças iguais lado a lado; variar escala (±15%), espelhamento e tom (±8%).

## 5. Estilo por grupo

- **Personagens:** proporção realista (cabeça ≈ 1/7 da altura), volume (nada de membros-palito), luz de cima e da esquerda, contorno escuro fino de 1 px.
- **Monstros:** a silhueta conta a espécie à distância; olhos podem brilhar; chefes têm detalhe extra (coroa, runas, cicatrizes).
- **Cenários:** chão com transições irregulares (sem linha reta entre texturas), decalques de folhas, pedrinhas, musgo e sujeira; vegetação rasteira afastada de caminhos e portas.

## 6. Efeitos mágicos

- Só o elemento aparece: nada de anel, disco ou marca no chão, nem bola de luz genérica.
- Cada efeito soma formas diferentes (tamanho, ritmo e movimento próprios); nada copiado e colado.
- Brilho aditivo só no que emite luz (fogo, raio, luz). Água, terra, natureza e gelo usam mistura normal.
- Quem é atingido mostra o efeito no corpo (partes queimando, geada grudada, raízes nas pernas), não um disco por cima.
- Menos pedaços na qualidade baixa, com a mesma identidade.

## 7. Presets de desempenho

| Preset | Resolução do mundo | Luzes na tela | Pedaços por efeito | Pós-processamento |
| --- | --- | --- | --- | --- |
| Ultra | 100% + MSAA (PC) | 24 | 100% | névoa + poeira |
| Alto | 100% | 16 | 100% | névoa |
| Médio | ~75% | 10 | 60% | névoa leve |
| Baixo | ~55% | 6 | 40% | desligado |

## 8. Fontes externas (caminho híbrido)

- Do lado de fora, só texturas de chão, pedras, rochas, plantas, madeira, telhado e materiais. Personagens, monstros e magias continuam por código.
- Licença conferida uma a uma, com prioridade para CC0, e tudo registrado em `ASSET_CREDITS.md`.
- Nunca misturar pixel art com textura fotográfica na mesma camada.
- Novos arquivos ficam em `godot/assets/vf/<categoria>/` e as ferramentas em `ferramentas/vf/`.
