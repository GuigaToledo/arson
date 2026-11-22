class_name Rules
extends RefCounted

## MODO TESTE: todos os personagens e magias no nível 100 (não salva no progresso).
## Desligar (false) devolve cada personagem ao nível real.
const TESTE_NIVEL_100 := true
## Regras do jogo: níveis, experiência, dano. Distâncias de jogo em tiles (grade).


## Curva de experiência (v2, mais lenta): do 1 ao 2 são 120 xp, do 10 ao 11 uns 8.800, do 30 ao 31 uns 48.000.
static func xp_to_reach(lvl: int) -> int:
	return 0 if lvl <= 1 else int(round(120.0 * pow(lvl - 1, 2.5)))


## Curva antiga (saves de antes da v2 são convertidos mantendo o nível).
static func xp_to_reach_v1(lvl: int) -> int:
	return 0 if lvl <= 1 else int(round(60.0 * pow(lvl - 1, 2.2)))


static func convert_xp_v1(xp: int) -> int:
	var l := 1
	while xp_to_reach_v1(l + 1) <= xp:
		l += 1
	var a := xp_to_reach_v1(l)
	var b := xp_to_reach_v1(l + 1)
	var f := float(xp - a) / maxf(1.0, float(b - a))
	return xp_to_reach(l) + int(f * float(xp_to_reach(l + 1) - xp_to_reach(l)))


## Diferença de nível monstro - jogador: 10+ vermelho (bate 50x, xp 2x), 5-9 laranja (20x, xp 1,5x), resto verde.
static func danger(mlvl: int, plvl: int) -> int:
	var d := mlvl - plvl
	return 2 if d >= 10 else (1 if d >= 5 else 0)


static func danger_color(g: int) -> Color:
	return [Color(0.45, 1.0, 0.45), Color(1.0, 0.6, 0.15), Color(1.0, 0.22, 0.18)][g]


static func danger_dmg(g: int) -> float:
	return [1.0, 2.0, 5.0][g]


static func danger_xp(g: int) -> float:
	return [1.0, 1.5, 2.0][g]


static func level_for(xp: int) -> int:
	var l := 1
	while xp_to_reach(l + 1) <= xp:
		l += 1
	return l


## Distância em tiles entre duas posições de tela.
static func gdist(a: Vector2, b: Vector2) -> float:
	return Iso.to_grid(a).distance_to(Iso.to_grid(b))


## Dano com variação (75% a 100%) menos a defesa, mínimo 1.
static func roll(power: float, def := 0.0) -> int:
	return maxi(1, int(round(power * randf_range(0.75, 1.0) - def)))


## Habilidades: pontos para passar do nível l ao l+1 (elementos contam mana gasta; Defesa, golpes levados).
## Nome de uma habilidade: os elementos (fogo, lava, ..., luz) ou Defesa.
static func skill_name(k: String) -> String:
	if k == "defesa":
		return "Defesa"
	return str(Spellbook.ELEMENTS[k].nome) if Spellbook.ELEMENTS.has(k) else k.capitalize()


static func skill_need(k: String, l: int) -> int:
	return int(round((10.0 if k == "defesa" else 30.0) * pow(l, 1.5)))


## Zona segura: o calçamento da vila (ninguém ataca nem é atacado ali).
static var safe_check: Callable = Callable()


static func is_safe(pos: Vector2) -> bool:
	return safe_check.is_valid() and safe_check.call(pos)


## Nível máximo dos monstros pela distância da vila (em tiles do ponto inicial):
## até 14 tiles só nível 5; depois sobe 1 nível a cada 3,5 tiles.
static var town := Vector2(27, 26)


static func level_cap(grid_pos: Vector2) -> int:
	var d := grid_pos.distance_to(town)
	return 5 if d <= 14.0 else 5 + int((d - 14.0) / 3.5)


## Curvas de vida, ataque e experiência por nível (as mesmas usadas em data/monstros.json).
static func mon_hp(l: float) -> float:
	return 30.0 + 22.0 * l + 1.1 * l * l


static func mon_atk(l: float) -> float:
	return 7.0 + 1.1 * l


static func mon_xp(l: float) -> float:
	return 10.0 + 4.0 * l + 0.6 * l * l
