class_name FlickerLight
extends PointLight2D
## Luz que tremula como fogo (velas, tochas, lareira).

var base_energy := 1.0
var flicker := 0.0
var _t := 0.0
var _seed := 0.0


func _ready() -> void:
	_seed = randf() * 100.0
	set_process(flicker > 0.0)


func _process(delta: float) -> void:
	_t += delta
	if flicker <= 0.0 or not visible:
		return
	# níveis baixos: tremula a 20 quadros por segundo (de 3 em 3) em vez de todo quadro
	if Settings.level_now <= 2 and Engine.get_process_frames() % 3 != 0:
		return
	var n := sin(_t * 11.0 + _seed) * 0.5 + sin(_t * 23.7 + _seed * 2.0) * 0.3 + sin(_t * 5.3) * 0.2
	energy = base_energy * (1.0 + n * flicker)
