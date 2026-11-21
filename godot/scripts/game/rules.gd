class_name Rules
extends RefCounted
## Regras do jogo: níveis, experiência, dano. Distâncias de jogo em tiles (grade).


static func xp_to_reach(lvl: int) -> int:
	return 0 if lvl <= 1 else int(round(60.0 * pow(lvl - 1, 2.2)))


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


## Habilidades: pontos para passar do nível l ao l+1 (Magia conta mana gasta; Defesa, golpes levados).
const SKILL_NAMES := {"magia": "Magia", "defesa": "Defesa"}


static func skill_need(k: String, l: int) -> int:
	return int(round((30.0 if k == "magia" else 10.0) * pow(l, 1.5)))


## Zona segura: o calçamento da vila (ninguém ataca nem é atacado ali).
static var safe_check: Callable = Callable()


static func is_safe(pos: Vector2) -> bool:
	return safe_check.is_valid() and safe_check.call(pos)
