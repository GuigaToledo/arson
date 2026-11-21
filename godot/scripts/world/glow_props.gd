class_name GlowProps
extends RefCounted
## Coisas do mapa que brilham sozinhas, desenhadas por código: cogumelos verdes nas florestas,
## cristais de várias cores nas cavernas e poças de lava nos morros de pedra.
## Cada uma tem uma luz própria que ilumina o chão em volta (aparece muito mais à noite).

const CRYSTAL_COLS := [Color(0.35, 0.8, 1.0), Color(1.0, 0.35, 0.85), Color(0.4, 1.0, 0.5), Color(1.0, 0.72, 0.25), Color(0.65, 0.45, 1.0), Color(1.0, 0.3, 0.3)]


static func mushrooms(parent: Node, pos: Vector2, sd: int) -> Node2D:
	var m := Mushrooms.new()
	m.sd = sd
	m.position = pos
	parent.add_child(m)
	var l := LightKit.make(Color(0.35, 1.0, 0.45), 0.8, 0.75, false, 0.04)
	l.position = Vector2(0, -12)
	m.add_child(l)
	return m


static func crystal(parent: Node, pos: Vector2, sd: int) -> Node2D:
	var c := Crystal.new()
	c.sd = sd
	c.col = CRYSTAL_COLS[sd % CRYSTAL_COLS.size()]
	c.position = pos
	parent.add_child(c)
	var l := LightKit.make(c.col, 1.0, 1.1, false, 0.06)
	l.position = Vector2(0, -30)
	c.add_child(l)
	return c


static func lava_pool(parent: Node, pos: Vector2, sd: int, r := 52.0) -> Node2D:
	var p := LavaPool.new()
	p.sd = sd
	p.r = r
	p.position = pos
	parent.add_child(p)
	var l := LightKit.make(Color(1.0, 0.45, 0.12), 1.4, 1.6 * r / 52.0, false, 0.18)
	l.position = Vector2(0, -10)
	p.add_child(l)
	return p


## Só redesenha quando está na tela (o mapa é grande).
static func on_screen(n: CanvasItem, margin := 120.0) -> bool:
	var xf := n.get_global_transform_with_canvas()
	var vr := n.get_viewport_rect().grow(margin)
	return vr.has_point(xf.origin)


class Mushrooms:
	extends Node2D
	var sd := 0
	var _t := 0.0

	func _ready() -> void:
		_t = float(sd % 100)

	func _process(d: float) -> void:
		_t += d
		if Engine.get_process_frames() % 6 == 0 and GlowProps.on_screen(self):
			queue_redraw()

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		var n := rng.randi_range(3, 6)
		var arr := []
		for i in n:
			arr.append([Vector2(rng.randf_range(-22, 22), rng.randf_range(-8, 8)), rng.randf_range(0.6, 1.25), rng.randf() * 6.0])
		arr.sort_custom(func(a, b): return a[0].y < b[0].y)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
		draw_circle(Vector2.ZERO, 34, Color(0.3, 1.0, 0.4, 0.10))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for e in arr:
			var p: Vector2 = e[0]
			var s: float = e[1]
			var pulse := 0.8 + 0.2 * sin(_t * 1.6 + float(e[2]))
			var h := 14.0 * s
			draw_line(p, p + Vector2(0, -h), Color(0.82, 0.86, 0.72), 3.0 * s)
			var cap := p + Vector2(0, -h)
			var pts := PackedVector2Array()
			for j in 9:
				var a := PI + PI * j / 8.0
				pts.append(cap + Vector2(cos(a) * 9.0 * s, sin(a) * 6.0 * s))
			pts.append(cap + Vector2(7.0 * s, 1.5 * s))
			pts.append(cap + Vector2(-7.0 * s, 1.5 * s))
			draw_circle(cap + Vector2(0, -2 * s), 12.0 * s, Color(0.3, 1.0, 0.45, 0.16 * pulse))
			draw_colored_polygon(pts, Color(0.2, 0.75, 0.3).lerp(Color(0.55, 1.0, 0.55), pulse - 0.6))
			for k in 3:
				draw_circle(cap + Vector2((k - 1) * 4.0 * s, -3.0 * s - (k % 2) * 2.0 * s), 1.3 * s, Color(0.85, 1.0, 0.8, pulse))


class Crystal:
	extends Node2D
	var sd := 0
	var col := Color.CYAN
	var _t := 0.0

	func _process(d: float) -> void:
		_t += d
		if Engine.get_process_frames() % 6 == 0 and GlowProps.on_screen(self):
			queue_redraw()

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		var pulse := 0.85 + 0.15 * sin(_t * 1.3 + sd)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
		draw_circle(Vector2.ZERO, 40, Color(col, 0.12 * pulse))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var shards := []
		for i in rng.randi_range(3, 5):
			shards.append([Vector2(rng.randf_range(-16, 16), rng.randf_range(-5, 5)), rng.randf_range(24, 58), rng.randf_range(-0.45, 0.45), rng.randf_range(6, 10)])
		shards.sort_custom(func(a, b): return a[0].y < b[0].y)
		for e in shards:
			var b: Vector2 = e[0]
			var h: float = e[1]
			var tilt: float = e[2]
			var w: float = e[3]
			var up := Vector2(sin(tilt), -cos(tilt))
			var side := Vector2(-up.y, up.x)
			var tip := b + up * h
			var l1 := b - side * w
			var r1 := b + side * w
			var l2 := b + up * h * 0.78 - side * w * 0.8
			var r2 := b + up * h * 0.78 + side * w * 0.8
			draw_colored_polygon(PackedVector2Array([l1, b, b + up * h * 0.8, l2]), col.darkened(0.35))
			draw_colored_polygon(PackedVector2Array([b, r1, r2, b + up * h * 0.8]), col.lightened(0.1 * pulse))
			draw_colored_polygon(PackedVector2Array([l2, b + up * h * 0.8, r2, tip]), col.lightened(0.45))
			draw_line(b, tip, Color(1, 1, 1, 0.5 * pulse), 1.2)
		for i in 3:
			var a := _t * 0.7 + i * 2.1 + sd
			draw_circle(Vector2(cos(a) * 18, -30 + sin(a * 1.3) * 16), 1.5, Color(col.lightened(0.6), 0.8 * pulse))


class LavaPool:
	extends StaticBody2D
	var sd := 0
	var r := 52.0
	var _t := 0.0

	func _ready() -> void:
		z_index = -1
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = r * 0.55
		cs.shape = sh
		cs.scale = Vector2(1, 0.5)
		add_child(cs)
		_t = float(sd % 50)

	func _process(d: float) -> void:
		_t += d
		if Engine.get_process_frames() % 3 == 0 and GlowProps.on_screen(self, 200.0):
			queue_redraw()
			if randf() < 0.05:
				SpellArt.parts(get_parent(), global_position + Vector2(randf_range(-r, r) * 0.5, -4), 3, 30.0, 1.4, 0.035, Color(1, 0.75, 0.3), Color(0.6, 0.1, 0.0), -60.0, 30.0)

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
		draw_circle(Vector2.ZERO, r * 1.35, Color(0.12, 0.08, 0.06, 0.55))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		SpellArt.lava(self, Vector2.ZERO, r, _t * 0.6, sd, 1.0)
