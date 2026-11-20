class_name Fx
extends RefCounted
## Efeitos: fogo (lareira, tochas, fogueira).


static func fire(parent: Node2D, at: Vector2, size: float) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.92, 0.6, 1.0))
	g.set_color(1, Color(0.6, 0.08, 0.02, 0.0))
	g.add_point(0.4, Color(1.0, 0.45, 0.1, 0.8))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var p := CPUParticles2D.new()
	p.amount = int(44 * size)
	p.lifetime = 0.8
	p.preprocess = 1.0
	p.texture = LightKit.radial()
	p.material = mat
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(14, 3) * size
	p.direction = Vector2(0, -1)
	p.spread = 15.0
	p.gravity = Vector2(0, -50)
	p.initial_velocity_min = 15.0 * size
	p.initial_velocity_max = 40.0 * size
	p.scale_amount_min = 0.05 * size
	p.scale_amount_max = 0.12 * size
	p.color_ramp = g
	p.position = at
	parent.add_child(p)
	var e := CPUParticles2D.new()
	e.amount = int(10 * size)
	e.lifetime = 2.0
	e.texture = LightKit.radial()
	e.material = mat
	e.direction = Vector2(0, -1)
	e.spread = 30.0
	e.gravity = Vector2(0, -25)
	e.initial_velocity_min = 20.0
	e.initial_velocity_max = 50.0
	e.scale_amount_min = 0.01
	e.scale_amount_max = 0.02
	e.color = Color(1, 0.6, 0.2)
	e.position = at
	parent.add_child(e)
