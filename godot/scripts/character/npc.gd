class_name Npc
extends Actor
## NPC simples: fica parado olhando para um lado ou passeia entre pontos.

var waypoints: Array = []
## "mercador" ou "sacerdotisa" = dá para conversar (clique/toque).
var role := ""
var idle_facing := "S"
var _wp := 0
var _wait := 0.0
var _stuck := 0.0
## Guarda: ataca monstros que chegarem perto e depois volta à patrulha.
var guarda := false
var dead := false
var _foe: Node2D = null
var _atk := 0.0
var _scan := 0.0
const GUARDA_ALCANCE := 9.0


func configure(nm: String, colors: Dictionary, items: Array, face: String, pts: Array = []) -> Npc:
	display_name = nm
	body_colors = colors
	start_items = items
	idle_facing = face
	facing = face
	waypoints = pts
	walk_speed = 70.0
	return self


func _physics_process(delta: float) -> void:
	if guarda and _guarda_combate(delta):
		return
	if waypoints.is_empty() or _wait > 0.0:
		_wait -= delta
		move(Vector2.ZERO, false, delta)
		if waypoints.is_empty():
			facing = idle_facing
		return
	var to: Vector2 = waypoints[_wp] - global_position
	if to.length() < 6.0:
		_wp = (_wp + 1) % waypoints.size()
		_wait = randf_range(1.5, 4.0)
		move(Vector2.ZERO, false, delta)
	else:
		move(to, false, delta)
		_stuck = _stuck + delta if get_real_velocity().length() < 10.0 else 0.0
		if _stuck > 1.2:
			_stuck = 0.0
			_wp = (_wp + 1) % waypoints.size()


## Devolve true quando está lutando (já moveu). Persegue o monstro mais perto e golpeia.
func _guarda_combate(delta: float) -> bool:
	_atk -= delta
	_scan -= delta
	if _foe != null and (not is_instance_valid(_foe) or _foe.dead or Rules.gdist(global_position, _foe.global_position) > GUARDA_ALCANCE + 4.0):
		_foe = null
	if _foe == null and _scan <= 0.0:
		_scan = 0.3
		var bd := GUARDA_ALCANCE
		for m in get_tree().get_nodes_in_group("monsters"):
			if not (m is Monster) or m.dead or m.info.get("dummy", false):
				continue
			var d := Rules.gdist(global_position, m.global_position)
			if d < bd:
				bd = d
				_foe = m
	if _foe == null:
		return false
	var dist := Rules.gdist(global_position, _foe.global_position)
	if dist > 1.4:
		move(_foe.global_position - global_position, true, delta)
	else:
		move(Vector2.ZERO, false, delta)
		facing = Iso.dir_from_vector(_foe.global_position - global_position)
		if _atk <= 0.0:
			_atk = 0.8
			play_action("punch", 0.4)
			_foe.take_damage(int(Rules.roll(60.0, float(_foe.info.get("def", 0))) ), self)
	return true
