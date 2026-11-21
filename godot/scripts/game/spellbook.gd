class_name Spellbook
extends RefCounted
## Nomes e descrições das magias de cada elemento (docs/magias.md).
## Magias 1 a 6: uma por nível do elemento. 7 e 8: mistura dos dois elementos da classe
## (os dois precisam estar no nível). O escudo (3) se funde quando os dois elementos têm o mesmo nível.

const TIER_KIND := ["", "Alvo único", "Controle / enfraquecer", "Escudo mágico", "Cone ou linha", "Invocação", "Área", "Mistura · alvo único", "Mistura · área"]

const ELEMENTS := {
	"fogo": {"nome": "Fogo", "cor": Color(1.0, 0.45, 0.12), "efeito": "queimadura (dano contínuo)",
		"magias": ["Bola de Fogo", "Marca Ardente", "Escudo de Chamas", "Sopro de Chamas", "Elemental de Fogo", "Chuva de Fogo"]},
	"lava": {"nome": "Lava", "cor": Color(0.9, 0.25, 0.05), "efeito": "queimadura + atordoamento",
		"magias": ["Projétil de Lava", "Poça de Lava", "Escudo de Lava", "Rio de Lava", "Golem de Lava", "Meteoro"]},
	"agua": {"nome": "Água", "cor": Color(0.3, 0.6, 1.0), "efeito": "o alvo não consegue se curar",
		"magias": ["Jato d'Água", "Maré Sufocante", "Escudo d'Água", "Onda", "Elemental de Água", "Dilúvio"]},
	"gelo": {"nome": "Gelo", "cor": Color(0.7, 0.92, 1.0), "efeito": "congela + lentidão de 5 s",
		"magias": ["Estilhaço de Gelo", "Congelar", "Armadura de Gelo", "Rajada Glacial", "Golem de Gelo", "Nevasca"]},
	"vento": {"nome": "Vento", "cor": Color(0.7, 0.95, 0.8), "efeito": "afasta o alvo",
		"magias": ["Lâmina de Vento", "Rajada", "Escudo de Vento", "Vendaval", "Elemental de Vento", "Tornado"]},
	"raio": {"nome": "Raio", "cor": Color(0.7, 0.65, 1.0), "efeito": "eletrizado: choques contínuos + paralisia",
		"magias": ["Faísca", "Paralisia", "Escudo Elétrico", "Corrente Elétrica", "Elemental de Raio", "Tempestade de Raios"]},
	"terra": {"nome": "Terra", "cor": Color(0.78, 0.58, 0.32), "efeito": "atordoamento",
		"magias": ["Pedrada", "Tremor", "Pele de Pedra", "Fenda", "Golem de Terra", "Terremoto"]},
	"natureza": {"nome": "Natureza", "cor": Color(0.4, 0.85, 0.3), "efeito": "raízes com espinhos prendem e ferem",
		"magias": ["Espinho", "Raízes", "Casca de Árvore", "Trepadeiras", "Guardião de Raízes", "Chuva de Espinhos"]},
	"luz": {"nome": "Luz", "cor": Color(1.0, 0.93, 0.6), "efeito": "cura e proteção",
		"magias": ["Cura Maior", "Bênção", "Corrente de Luz", "Círculo Sagrado", "Espírito de Luz", "Aura de Bravura", "Véu de Luz", "Ascensão"]},
}

const LUZ_DESC := [
	"Cura muito você e o seu summon.",
	"Cura você e os aliados em 5% da vida máxima por segundo, durante 1 minuto.",
	"Raio de cura que pula de aliado em aliado (do mais ferido ao menos ferido) e volta para você.",
	"Cura média numa área grande.",
	"Espírito de luz no seu ombro: cura leve a cada 2 s em quem tiver menos vida, por 5 minutos.",
	"Aumenta o ataque e a defesa do grupo por 5 minutos.",
	"Fica invisível até lançar um ataque (cura não conta).",
	"Imortal por 30 s, com asas de anjo dos seus elementos.",
]

## Fusões de cada classe: escudo fundido (3), mistura alvo único (7) e mistura em área (8).
const FUSOES := {
	"fogo": ["Escudo de Magma", "Cometa de Magma", "Erupção"],
	"agua": ["Escudo Glacial", "Lança de Granizo", "Tempestade de Granizo"],
	"vento": ["Égide da Tempestade", "Lança da Tempestade", "Furacão Elétrico"],
	"terra": ["Bastião Vivo", "Estaca de Espinhos", "Floresta Petrificada"],
}

## Elementos de cada classe: [elemento A, elemento B].
const CLASS_ELEMENTS := {
	"fogo": ["fogo", "lava"], "agua": ["agua", "gelo"], "vento": ["vento", "raio"], "terra": ["terra", "natureza"],
}


static func elements_of(classe: String) -> Array:
	return CLASS_ELEMENTS.get(classe, CLASS_ELEMENTS.fogo)


static func spell_desc(el: String, tier: int) -> String:
	if el == "luz":
		return LUZ_DESC[tier - 1]
	var e: Dictionary = ELEMENTS[el]
	match tier:
		1: return "Ataque num alvo; fica mais forte com o nível. Efeito: %s." % e.efeito
		2: return "Controle de grupo e enfraquecimento: %s em vários inimigos." % e.efeito
		3: return "Escudo mágico de %s que absorve dano." % e.nome
		4: return "Ataque em cone ou em linha com %s." % e.efeito
		5: return "Invocação: tanque que luta como monge shaolin, segue você e sobe de nível com você."
		6: return "Dano em área com %s." % e.efeito
	return ""
