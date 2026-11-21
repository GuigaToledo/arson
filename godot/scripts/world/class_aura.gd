class_name ClassAura
extends Node2D
## Aura do mago, na cara do elemento da classe:
## fogo = brasas subindo; água = gotas e flocos de gelo; vento = redemoinho com faíscas; terra = folhas e poeira.

var classe := ""
var _p: Array[CPUParticles2D] = []


func setup(c: String) -> void:
	if c == classe:
		return
	classe = c
	for p in _p:
		p.queue_free()
	_p.clear()
	match c:
		"fogo":
			_add(Color(1, 0.75, 0.3), Color(0.9, 0.2, 0.02), 10, 1.4, Vector2(0, -40), 70.0, 14.0, 0.05)
		"agua":
			_add(Color(0.6, 0.9, 1), Color(0.2, 0.5, 1), 8, 1.6, Vector2(0, 20), 0.0, 16.0, 0.045)
			_add(Color(0.95, 1, 1), Color(0.7, 0.9, 1), 5, 2.2, Vector2(0, 8), 0.0, 18.0, 0.035)
		"vento":
			var w := _add(Color(0.85, 1, 0.95), Color(0.5, 0.9, 0.8), 12, 1.0, Vector2(0, -10), 0.0, 6.0, 0.04)
			w.orbit_velocity_min = 0.6
			w.orbit_velocity_max = 0.9
			w.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
			w.emission_sphere_radius = 20.0
			_add(Color(0.9, 0.85, 1), Color(0.55, 0.5, 1), 4, 0.5, Vector2(0, -60), 30.0, 20.0, 0.03)
		"terra":
			_add(Color(0.55, 0.9, 0.35), Color(0.25, 0.5, 0.1), 7, 2.0, Vector2(0, 22), 0.0, 18.0, 0.045)
			_add(Color(0.75, 0.6, 0.4), Color(0.4, 0.3, 0.2), 6, 1.2, Vector2(0, -6), 10.0, 14.0, 0.05)


## a = cor inicial, b = cor final, gravity_y > 0 cai, < 0 sobe.
func _add(a: Color, b: Color, amount: int, life: float, gravity: Vector2, up: float, spread_px: float, size: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = life
	p.texture = LightKit.radial()
	p.material = SpellFx._add_mat()
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(spread_px, 26)
	p.position = Vector2(0, -40)
	p.direction = Vector2(0, -1)
	p.spread = 30.0
	p.initial_velocity_min = up * 0.5
	p.initial_velocity_max = up
	p.gravity = gravity
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var g := Gradient.new()
	g.set_color(0, Color(a, 0.9))
	g.set_color(1, Color(b, 0))
	p.color_ramp = g
	p.z_index = 2
	add_child(p)
	_p.append(p)
	return p
