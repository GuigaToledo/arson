class_name Spells
extends RefCounted
## Catálogo das magias. Id: "elemento:nível" (ex.: "fogo:1", "luz:2") ou "fus:3|7|8" (fusões da classe).
## Nível do elemento >= nível da magia libera. Fusões: 3 = elementos no MESMO nível (>= 3);
## 7 e 8 = os dois elementos no nível. As 8 casas da barra guardam ids.

## Elementos que atacam em linha no nível 4 (os outros, em cone).
const LINE := ["lava", "raio", "terra"]


static func short(nome: String) -> String:
	var w := nome.split(" ")
	var s: String = w[0] if w[0].length() > 2 or w.size() == 1 else w[0] + " " + w[1]
	return s.substr(0, 8)


static func get_spell(id: String, classe: String) -> Dictionary:
	var parts := id.split(":")
	if parts.size() != 2:
		return {}
	var el := parts[0]
	var t := int(parts[1])
	var s := {"id": id, "tier": t}
	if el == "fus":
		var els := Spellbook.elements_of(classe)
		var names: Array = Spellbook.FUSOES[classe]
		s.els = els
		s.color = (Spellbook.ELEMENTS[els[0]].cor as Color).lerp(Spellbook.ELEMENTS[els[1]].cor, 0.5)
		match t:
			5: s.merge({"nome": Spellbook.SUMMON_FUSION[classe], "type": "summon", "mana": 120, "cd": 30.0})
			3: s.merge({"nome": names[0], "type": "shield", "mana": 50, "cd": 25.0, "base": 90.0, "perL": 16.0, "dur": 30.0})
			7: s.merge({"nome": names[1], "type": "single", "mana": 45, "cd": 4.0, "base": 70.0, "perL": 9.0, "range": 8.0, "big": true})
			8: s.merge({"nome": names[2], "type": "area", "mana": 100, "cd": 10.0, "base": 75.0, "perL": 9.0, "range": 8.0, "radius": 3.0, "delay": 0.6})
			_: return {}
		s.curto = short(s.nome)
		return s
	if not Spellbook.ELEMENTS.has(el) or t < 1 or t > 8:
		return {}
	var e: Dictionary = Spellbook.ELEMENTS[el]
	s.els = [el]
	s.color = e.cor
	s.nome = e.magias[t - 1] if t <= e.magias.size() else ""
	if s.nome == "":
		return {}
	s.curto = short(s.nome)
	if el == "luz":
		match t:
			1: s.merge({"type": "heal", "mana": 25, "cd": 1.5, "base": 45.0, "perL": 6.0})
			2: s.merge({"type": "hot", "mana": 60, "cd": 90.0, "dur": 60.0})
			3: s.merge({"type": "chainheal", "mana": 40, "cd": 6.0, "base": 28.0, "perL": 4.0})
			4: s.merge({"type": "heal", "mana": 45, "cd": 8.0, "base": 35.0, "perL": 5.0, "ring": 3.0})
			5: s.merge({"type": "spirit", "mana": 70, "cd": 120.0, "dur": 300.0})
			6: s.merge({"type": "buff", "mana": 80, "cd": 180.0, "dur": 300.0})
			7: s.merge({"type": "invis", "mana": 50, "cd": 30.0})
			8: s.merge({"type": "immortal", "mana": 120, "cd": 300.0, "dur": 30.0})
		return s
	match t:
		1: s.merge({"type": "single", "mana": 12, "cd": 0.9, "base": 26.0, "perL": 4.0, "range": 7.0})
		2: s.merge({"type": "cc", "mana": 30, "cd": 7.0, "base": 14.0, "perL": 2.0, "range": 7.0, "radius": 2.0})
		3: s.merge({"type": "shield", "mana": 35, "cd": 25.0, "base": 40.0, "perL": 8.0, "dur": 30.0})
		4:
			if LINE.has(el):
				s.merge({"type": "line", "mana": 30, "cd": 3.0, "base": 30.0, "perL": 4.5, "range": 7.0})
			else:
				s.merge({"type": "cone", "mana": 30, "cd": 3.0, "base": 30.0, "perL": 4.5, "range": 4.5, "ang": 0.6})
		5: s.merge({"type": "summon", "mana": 80, "cd": 20.0})
		6: s.merge({"type": "area", "mana": 65, "cd": 6.0, "base": 46.0, "perL": 6.0, "range": 8.0, "radius": 2.3, "delay": 0.5 if el == "lava" else 0.0})
	return s


## Ataque? (para a automação: cura, escudos e bênçãos ficam de fora)
static func is_attack(s: Dictionary) -> bool:
	return ["single", "cc", "cone", "line", "area"].has(s.get("type", ""))


## Barra inicial de cada classe.
static func default_bar(classe: String) -> Array:
	var e := Spellbook.elements_of(classe)
	# começa só com o elemento base e a Luz (o segundo elemento vem no nível 31 do base)
	return ["%s:1" % e[0], "luz:1", "%s:2" % e[0], "%s:3" % e[0], "%s:4" % e[0], "%s:6" % e[0], "luz:2", "%s:5" % e[0]]
