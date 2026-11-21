class_name RemotePlayer
extends Actor
## Outro jogador vindo da rede: mostra posição, direção, animação e equipamentos.
## No anfitrião, também é alvo dos monstros: dano e experiência vão pela rede.

var uid := ""
var dead := false
var level := 1
var classe := ""
var _class_aura: ClassAura


func take_damage(n: int, src: String) -> void:
	if NetSync.inst:
		NetSync.inst.send_to(uid, {"t": "hit", "n": n, "src": src})


func gain_xp(n: int, g: int, src: String) -> void:
	if NetSync.inst:
		NetSync.inst.send_to(uid, {"t": "xp", "n": n, "g": g, "src": src})

var _target := Vector2.ZERO
var _eq_key := ""


func _init() -> void:
	body_colors = {
		"skin": Color(0.09, 0.085, 0.09),
		"under": Color(0.11, 0.1, 0.1),
		"hair": Color(0.07, 0.065, 0.07),
		"eyes": Color(1.0, 0.62, 0.15),
		"glow_eyes": true,
		"core": true,
	}
	body_path = "res://assets/personagens/mago/corpo.tres"


func _ready() -> void:
	super()
	collision_layer = 0
	collision_mask = 0
	_target = position
	add_to_group("remote_players")


func apply_state(s: Dictionary) -> void:
	_target = Vector2(float(s.get("x", position.x)), float(s.get("y", position.y)))
	dead = int(s.get("d", 0)) == 1
	level = int(s.get("l", 1))
	var c := str(s.get("c", ""))
	if MageClass.valid(c) and c != classe:
		classe = c
		var ci := MageClass.info(c)
		visual.set_glow(ci.nucleo, ci.olhos)
		if _class_aura == null:
			_class_aura = ClassAura.new()
			add_child(_class_aura)
		_class_aura.setup(c)
	visible = not dead
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
