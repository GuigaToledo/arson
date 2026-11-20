class_name Npc
extends Actor
## NPC simples: fica parado olhando para um lado ou passeia entre pontos.

var waypoints: Array = []
var idle_facing := "S"
var _wp := 0
var _wait := 0.0
var _stuck := 0.0


func configure(colors: Dictionary, items: Array, face: String, pts: Array = []) -> Npc:
	body_colors = colors
	start_items = items
	idle_facing = face
	facing = face
	waypoints = pts
	walk_speed = 70.0
	return self


func _physics_process(delta: float) -> void:
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
