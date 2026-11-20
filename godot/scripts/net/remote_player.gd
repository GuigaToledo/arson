class_name RemotePlayer
extends Actor
## Outro jogador vindo da rede: só mostra posição, direção, animação e equipamentos.

var _target := Vector2.ZERO
var _eq_key := ""


func _init() -> void:
	body_colors = {
		"skin": Color(0.42, 0.33, 0.28),
		"under": Color(0.13, 0.11, 0.1),
		"hair": Color(0.05, 0.04, 0.04),
		"eyes": Color(1.0, 0.62, 0.15),
		"glow_eyes": true,
	}
	body_path = "res://assets/personagens/mago/corpo.tres"


func _ready() -> void:
	super()
	collision_layer = 0
	collision_mask = 0
	_target = position


func apply_state(s: Dictionary) -> void:
	_target = Vector2(float(s.get("x", position.x)), float(s.get("y", position.y)))
	facing = str(s.get("f", "S"))
	if not Iso.DIRS.has(facing):
		facing = "S"
	anim = str(s.get("a", "idle"))
	display_name = str(s.get("n", ""))
	var eq: Dictionary = s.get("eq", {})
	var key := JSON.stringify(eq)
	if key != _eq_key:
		_eq_key = key
		var ids := {}
		for k in eq:
			ids[int(k)] = eq[k]
		equipment.load_ids(ids)


func _physics_process(delta: float) -> void:
	var to := _target - position
	if to.length() > 400.0:
		position = _target
	else:
		position += to * minf(1.0, delta * 10.0)
	var spd := 210.0 if anim == "run" else (120.0 if anim == "walk" else 0.0)
	visual.tick(delta, facing, anim, spd)
