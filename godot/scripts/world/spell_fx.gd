class_name SpellFx
extends RefCounted
## Efeitos visuais das magias: explosão, anel de área, raio em corrente, cone de fogo,
## meteoro caindo e brilho de cura. Tudo brilha (soma de cor) e ignora a escuridão da cena.

## raio em tiles -> semieixo horizontal da elipse na tela (losango 128x64)
const TILE_RX := 90.5


static func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m


static func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, Color(b, 0))
	return g


static func burst(parent: Node, pos: Vector2, amount: int, speed: float, life: float, size: float, a: Color, b: Color, up := 0.0) -> void:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.texture = LightKit.radial()
	p.material = _add_mat()
	p.spread = 180.0
	p.gravity = Vector2(0, -up)
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.color_ramp = _ramp(a, b)
	p.position = pos
	p.z_index = 5
	parent.add_child(p)
	p.emitting = true
	p.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


static func flash(parent: Node, pos: Vector2, color: Color, energy: float, scale: float, dur: float) -> void:
	var l := LightKit.make(color, energy, scale, false, 0.0)
	l.position = pos
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "energy", 0.0, dur)
	tw.tween_callback(l.queue_free)


static func explosion(parent: Node, pos: Vector2, radius_tiles: float) -> void:
	burst(parent, pos + Vector2(0, -10), int(60 + radius_tiles * 30), 120.0 + radius_tiles * 80.0, 0.7, 0.22, Color(1, 0.9, 0.6), Color(0.7, 0.1, 0.02), 40.0)
	burst(parent, pos, 24, 60.0, 1.2, 0.3, Color(0.35, 0.3, 0.28), Color(0.1, 0.1, 0.1), 30.0)
	flash(parent, pos + Vector2(0, -20), Color(1, 0.55, 0.2), 3.0, 1.2 + radius_tiles * 0.8, 0.7)
	ring(parent, pos, radius_tiles, Color(1, 0.7, 0.3), 0.6)


## Anel que se expande no chão (área da magia).
static func ring(parent: Node, pos: Vector2, radius_tiles: float, color: Color, dur: float, grow := true) -> Node2D:
	var r := Ring.new()
	r.position = pos
	r.rx = radius_tiles * TILE_RX
	r.color = color
	r.dur = dur
	r.grow = grow
	parent.add_child(r)
	return r


## Raio que pula de um ponto a outro (corrente elétrica).
static func lightning(parent: Node, pts: Array) -> void:
	var z := Lightning.new()
	z.pts = pts
	parent.add_child(z)
	for p in pts:
		flash(parent, p, Color(0.55, 0.7, 1.0), 1.6, 0.8, 0.4)
		burst(parent, p, 14, 90.0, 0.35, 0.08, Color(0.9, 0.95, 1), Color(0.3, 0.45, 1))


## Jato de fogo em cone.
static func cone(parent: Node, pos: Vector2, dir: Vector2, length_px: float, half_ang: float) -> void:
	var p := CPUParticles2D.new()
	p.amount = 90
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.6
	p.texture = LightKit.radial()
	p.material = _add_mat()
	p.direction = dir
	p.spread = rad_to_deg(half_ang)
	p.initial_velocity_min = length_px * 1.3
	p.initial_velocity_max = length_px * 2.1
	p.damping_min = length_px * 1.5
	p.damping_max = length_px * 2.5
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.3
	p.color_ramp = _ramp(Color(1, 0.85, 0.5), Color(0.8, 0.12, 0.02))
	p.position = pos + Vector2(0, -40)
	p.z_index = 5
	parent.add_child(p)
	p.emitting = true
	p.get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	flash(parent, pos + dir * length_px * 0.5, Color(1, 0.5, 0.15), 2.2, 1.6, 0.6)


## Meteoro: cai do céu em `delay` segundos e chama `on_impact`.
static func meteor(parent: Node, at: Vector2, delay: float, radius_tiles: float, on_impact: Callable) -> void:
	var m := Meteor.new()
	m.target = at
	m.delay = delay
	m.radius_tiles = radius_tiles
	m.on_impact = on_impact
	parent.add_child(m)


static func heal(parent: Node, pos: Vector2) -> void:
	burst(parent, pos + Vector2(0, -30), 30, 50.0, 1.0, 0.08, Color(0.75, 1, 0.75), Color(0.1, 0.8, 0.3), 70.0)
	flash(parent, pos + Vector2(0, -30), Color(0.4, 1, 0.5), 1.5, 1.0, 0.7)


class Ring:
	extends Node2D
	var rx := 90.0
	var color := Color.WHITE
	var dur := 0.6
	var grow := true
	var _t := 0.0

	func _ready() -> void:
		material = SpellFx._add_mat()
		z_index = -4

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _t / dur
		var r := rx * (0.3 + 0.7 * k) if grow else rx
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(color, 1.0 - k), 4.0 * (1.0 - k) + 1.0)
		if not grow:
			draw_circle(Vector2.ZERO, r, Color(color, 0.12 * (1.0 - k)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class Lightning:
	extends Node2D
	var pts: Array = []
	var _t := 0.0

	func _ready() -> void:
		material = SpellFx._add_mat()
		z_index = 6

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.45:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var a := 1.0 - _t / 0.45
		for s in pts.size() - 1:
			var p0: Vector2 = pts[s] + Vector2(0, -45)
			var p1: Vector2 = pts[s + 1] + Vector2(0, -45)
			var line := PackedVector2Array([p0])
			for k in range(1, 8):
				var q := p0.lerp(p1, k / 8.0) + Vector2(randf_range(-9, 9), randf_range(-9, 9))
				line.append(q)
			line.append(p1)
			draw_polyline(line, Color(0.35, 0.5, 1.0, 0.35 * a), 9.0)
			draw_polyline(line, Color(0.7, 0.82, 1.0, 0.85 * a), 3.5)
			draw_polyline(line, Color(1, 1, 1, a), 1.4)


class Meteor:
	extends Node2D
	var target := Vector2.ZERO
	var delay := 0.7
	var radius_tiles := 2.0
	var on_impact: Callable
	var _t := 0.0
	var _ring: Node2D
	var _light: PointLight2D

	func _ready() -> void:
		material = SpellFx._add_mat()
		z_index = 6
		_ring = SpellFx.ring(get_parent(), target, radius_tiles, Color(1, 0.3, 0.1), delay, false)
		_light = LightKit.make(Color(1, 0.55, 0.2), 2.0, 1.2, false, 0.2)
		add_child(_light)

	func _process(delta: float) -> void:
		_t += delta
		var k := clampf(_t / delay, 0, 1)
		position = target + Vector2(220, -520) * (1.0 - k)
		queue_redraw()
		if k >= 1.0:
			SpellFx.explosion(get_parent(), target, radius_tiles)
			if on_impact.is_valid():
				on_impact.call()
			queue_free()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 26, Color(1, 0.45, 0.1, 0.35))
		draw_circle(Vector2.ZERO, 15, Color(1, 0.6, 0.2))
		draw_circle(Vector2.ZERO, 8, Color(1, 0.95, 0.75))
		for i in 6:
			var d := Vector2(220, -520).normalized() * (20 + i * 14)
			draw_circle(d, 12 - i * 1.6, Color(1, 0.4, 0.08, 0.5 - i * 0.07))
