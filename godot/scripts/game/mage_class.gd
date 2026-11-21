class_name MageClass
extends RefCounted
## As 4 classes de mago (escolhidas na tela inicial). Cada uma domina 2 elementos; todas usam Luz.
## Regras completas em docs/magias.md.

const ORDER := ["fogo", "agua", "vento", "terra"]

const DATA := {
	"fogo": {
		"nome": "Mago do Fogo", "elementos": ["Fogo", "Lava"],
		"cor": Color(1.0, 0.45, 0.12), "cor2": Color(0.85, 0.2, 0.05),
		"cajado": "cajado_brasa",
		"desc": "Queima os inimigos com dano contínuo. A lava atordoa quem ela atinge.",
		"efeitos": "Fogo: queimadura · Lava: queimadura + atordoamento",
		"summon": "Elemental de fogo flutuante · Golem de lava",
	},
	"agua": {
		"nome": "Mago da Água", "elementos": ["Água", "Gelo"],
		"cor": Color(0.3, 0.7, 1.0), "cor2": Color(0.7, 0.92, 1.0),
		"cajado": "cajado_mare",
		"desc": "A água impede o alvo de se curar. O gelo congela e deixa os inimigos lentos.",
		"efeitos": "Água: bloqueia cura · Gelo: congela + lentidão",
		"summon": "Elemental de água · Golem de gelo",
	},
	"vento": {
		"nome": "Mago do Vento", "elementos": ["Vento", "Raio"],
		"cor": Color(0.75, 0.95, 0.85), "cor2": Color(0.65, 0.6, 1.0),
		"cajado": "cajado_tempestade",
		"desc": "O vento afasta os inimigos. O raio eletriza, paralisa e dá choques contínuos.",
		"efeitos": "Vento: afasta · Raio: eletrizado + paralisia",
		"summon": "Elemental de vento flutuante · Elemental de raio super rápido",
	},
	"terra": {
		"nome": "Mago da Terra", "elementos": ["Terra", "Natureza"],
		"cor": Color(0.75, 0.55, 0.3), "cor2": Color(0.4, 0.85, 0.3),
		"cajado": "cajado_raiz",
		"desc": "A terra atordoa. Raízes com espinhos prendem os inimigos no chão e os ferem.",
		"efeitos": "Terra: atordoamento · Natureza: raízes com espinhos",
		"summon": "Golem de terra · Guardião de raízes entrelaçadas",
	},
}


static func info(c: String) -> Dictionary:
	return DATA.get(c, DATA.fogo)


static func valid(c: String) -> bool:
	return DATA.has(c)
