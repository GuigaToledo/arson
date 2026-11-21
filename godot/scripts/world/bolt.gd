class_name Bolt
extends Node2D
## Projétil teleguiado (ataque básico do mago, flecha de fogo dos cultistas).
## Ao chegar no alvo chama `on_hit` e some.

const HEIGHT := 46.0

var target: Node2D
var speed := 520.0
var color := Color(1.0, 0.55, 0.15)
## Tamanho da bola (fusões são maiores).
var size := 1.0
var on_hit: Callable = Callable()
var _light: PointLight2D
var _trail: CPUParticles2D
var _last := Vector2.ZERO


func _ready() -> void:
	_light = LightKit.make(color, 1.0, 0.9, false, 0.2)
	_light.position = Vector2(0, -HEIGHT)
	add_child(_light)
	var g := Gradient.new()
	g.set_color(0, Color(color.lightened(0.5), 1))
	g.set_color(1, Color(color.darkened(0.5), 0))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_trail = CPUParticles2D.new()
	_trail.amount = 16
	_trail.lifetime = 0.3
	_trail.texture = LightKit.radial()
	_trail.material = mat
	_trail.spread = 180.0
	_trail.initial_velocity_max = 8.0
	_trail.scale_amount_min = 0.03
	_trail.scale_amount_max = 0.07
	_trail.color_ramp = g
	_trail.local_coords = false
	_trail.position = Vector2(0, -HEIGHT)
	add_child(_trail)


func _process(delta: float) -> void:
	if target != null and is_instance_valid(target):
		_last = target.global_position
	var to := _last - global_position
	var step := speed * delta
	if to.length() <= step:
		global_position = _last
		if on_hit.is_valid() and target != null and is_instance_valid(target):
			on_hit.call()
		set_process(false)
		_trail.emitting = false
		hide_orb()
		get_tree().create_timer(0.4).timeout.connect(queue_free)
		return
	global_position += to.normalized() * step
	queue_redraw()


func hide_orb() -> void:
	_light.energy = 0.0
	queue_redraw()


func _draw() -> void:
	if not is_processing():
		return
	var c := Vector2(0, -HEIGHT)
	draw_circle(c, 6.0 * size, Color(color, 0.35))
	draw_circle(c, 3.5 * size, color.lightened(0.3))
	draw_circle(c, 1.8 * size, Color(1, 0.97, 0.85))
