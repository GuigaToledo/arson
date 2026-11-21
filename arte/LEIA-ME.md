# Arte do Arson — 2.5D isométrico no estilo Diablo 2

Tudo é **2D**. A sensação de 3D vem da câmera isométrica, da luz dinâmica (o mundo é escuro e
a luz acompanha o herói), das sombras e do relevo das texturas. Nada de modelos 3D.

**Estilo:** fantasia sombria e realista, pintada à mão, cores dessaturadas (marrom, cinza, preto,
vermelho-escuro), luz quente de fogo contra sombras frias. Proporções humanas reais, nada de cartoon
ou pixel art. Referências: Diablo 2 (Rogue Encampment, Tristram), e as imagens em `arte/referencias/`.

**Ângulo fixo de tudo:** isométrico 3/4, câmera a ~30° de altura, vista de cima em diagonal.
**Luz fixa de tudo:** vinda do alto à esquerda, sombra caindo para baixo à direita.

## Peças de cenário → `arte/objetos/`

Uma imagem por peça, fundo branco liso. O fundo é removido sozinho e eu encaixo a peça no mapa.
Pedido para a IA de imagem (troque o que está entre colchetes):

> Diablo 2 style isometric game asset, single [medieval timber house with dark wooden roof],
> isometric 3/4 top-down view at 30 degrees, isolated on plain white background,
> dark gritty fantasy, realistic hand-painted, desaturated earthy colors,
> light from the upper left, soft shadow to the lower right, highly detailed, no text, full object visible

Ideias para a vila: casa de madeira, templo de pedra, tenda de lona, carroça, barril, caixote,
cerca de madeira, poste com lampião, fogueira com caldeirão, árvore de outono, árvore escura,
pedra grande, poço, banco, ponte de pedra, estátua.

## Personagens → `arte/personagens/<nome>/`

Primeiro uma folha com o personagem nas 5 direções (as outras 3 são espelhadas):

> Diablo 2 style character turnaround sheet of [a dark fantasy fire mage wearing a red infernal wolf
> pelt hood and cape, wolf fur skirt, black stone armor with a glowing fire core on the chest,
> holding a huge wooden mimic shield with fangs and glowing eyes], 5 views in one row:
> front, front-right 3/4, right side, back-right 3/4, back, isometric top-down 30 degree camera,
> same character and same scale in every view, full body, plain white background,
> realistic hand-painted, desaturated, no text

Depois disso eu peço as partes separadas (cabeça, tronco, braços, pernas, capa, escudo) para
animar com ossos 2D, sempre igual ao personagem da folha.

## Referências (`arte/referencias/`)

- `vila_principal.jpg` — padrão do cenário externo (vila, estradas de pedra, ponte, rio, fogueira, lampiões).
- `ferraria_interior.jpg`, `taverna_1.jpg`, `taverna_2.jpg` — padrão dos interiores (luz de fogo e velas).
- `mago_lendario.jpg` — o Mago das Chamas com o equipamento final (capa e saia de lobo infernal, escudo mímico).
- `mago_sem_equipamento.jpg`, `golem_de_pedra.jpg` — o corpo do Mago sem equipamento (armadura negra, núcleo de fogo, olhos âmbar).
- `casa_isometrica.jpg`, `ilha_flutuante.jpg` — só como referência de composição isométrica; o estilo cartoon delas não vale.
