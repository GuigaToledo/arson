class_name Fireball
extends Node2D
## Bola de fogo: voa no chão isométrico, ilumina o caminho e explode no fim.

const SPEED := 420.0
const LIFE := 0.85
const HEIGHT := 48.0

var dir := Vector2.RIGHT
var _t := 0.0
var _done := false
var _light: PointLight2D
var _trail: CPUParticles2D


func _ready() -> void:
	_light = LightKit.make(Color(1.0, 0.5, 0.15), 1.6, 1.4, false, 0.25)
	_light.position = Vector2(0, -HEIGHT)
	add_child(_light)
	_trail = _particles(28, 0.45, 0.06, 0.12, Vector2.ZERO, 10.0)
	_trail.local_coords = false
	_trail.position = Vector2(0, -HEIGHT)
	add_child(_trail)


func _particles(amount: int, life: float, smin: float, smax: float, grav: Vector2, vel: float) -> CPUParticles2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.7, 1))
	g.set_color(1, Color(0.6, 0.08, 0.02, 0))
	g.add_point(0.35, Color(1, 0.5, 0.1, 0.9))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = life
	p.texture = LightKit.radial()
	p.material = mat
	p.spread = 180.0
	p.gravity = grav
	p.initial_velocity_min = vel * 0.3
	p.initial_velocity_max = vel
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	p.color_ramp = g
	return p


func _process(delta: float) -> void:
	_t += delta
	if _done:
		if _t > 0.9:
			queue_free()
		return
	var step := Iso.ground_velocity(dir, SPEED) * delta
	var nxt := global_position + step
	if _t >= LIFE or (Actor.walkable.is_valid() and not Actor.walkable.call(nxt)):
		_explode()
		return
	global_position = nxt
	queue_redraw()


func _explode() -> void:
	_done = true
	_t = 0.0
	_trail.emitting = false
	var b := _particles(60, 0.6, 0.08, 0.2, Vector2(0, -60), 160.0)
	b.one_shot = true
	b.explosiveness = 0.95
	b.position = Vector2(0, -HEIGHT * 0.6)
	add_child(b)
	b.emitting = true
	var tw := create_tween()
	tw.tween_property(_light, "energy", 0.0, 0.7).from(2.6)
	queue_redraw()


func _draw() -> void:
	if _done:
		return
	var c := Vector2(0, -HEIGHT)
	draw_circle(c, 9.0, Color(1, 0.45, 0.1, 0.35))
	draw_circle(c, 5.5, Color(1, 0.65, 0.2))
	draw_circle(c, 2.8, Color(1, 0.95, 0.75))
	PlaceholderPainter.ellipse(self, Vector2.ZERO, 8, 4, Color(0, 0, 0, 0.3))
