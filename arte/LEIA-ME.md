# Arte do Arson — como mandar arte nova

Tudo o que for colocado aqui é convertido sozinho pelo GitHub (sem gastar créditos do Claude)
e entra no jogo no próximo build.

## Personagens 3D → sprites em 8 direções (`arte/personagens/<nome>/`)

1. Gere o modelo 3D a partir da imagem no **Meshy** (meshy.ai ou app do celular, plano grátis):
   *Image to 3D* → envie a imagem do personagem de corpo inteiro.
2. No Meshy, use **Animate / Auto-Rig** (humanoide) e escolha as animações:
   parado (idle), andando (walk), correndo (run), ataque (attack), magia (cast), dano (damage), morte (death).
3. Baixe cada animação em **GLB** e coloque numa pasta, por exemplo `arte/personagens/mago/`:
   `idle.glb`, `walk.glb`, `run.glb`, `attack.glb`, `cast.glb` ...
4. Crie `config.json` na mesma pasta:

```json
{
  "modelo": "idle.glb",
  "animacoes": {
    "idle":   {"arquivo": "idle.glb"},
    "walk":   {"arquivo": "walk.glb"},
    "run":    {"arquivo": "run.glb"},
    "attack": {"arquivo": "attack.glb"},
    "cast":   {"arquivo": "cast.glb"}
  },
  "quadros": 8
}
```

A pasta `mago` vira automaticamente o corpo do jogador. Se o personagem aparecer de costas,
acrescente `"rotacao": 180` no config.

## Peças de cenário (`arte/objetos/`)

Uma imagem por peça (casa, árvore, cerca, carroça, poste...), com **fundo liso** (branco ou verde)
ou transparente. O fundo é removido sozinho. Use sempre o mesmo pedido na IA de imagem:

> isometric 3/4 view from above, single [OBJETO] isolated on plain white background,
> realistic dark medieval fantasy, hand-painted HD game asset, warm evening light from the upper left,
> soft shadows, highly detailed textures, no text, no frame, full object visible
