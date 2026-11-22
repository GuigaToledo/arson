class_name GroundDecals
extends Node2D
## Visual Factory, vegetação e detalhes do chão: tufos de grama, florzinhas, folhas caídas,
## gravetos, pedrinhas, musgo, raízes e grama seca, espalhados conforme o tipo de chão.
## Nada vai em cima de casas, portas ou no meio das estradas (só nas beiras).
## Um nó por pedaço do mapa, desenhado uma vez (não processa nada por quadro); o Godot só
## desenha os pedaços que aparecem na tela.

const CHUNK := 12
var map: WorldMap
var cx := 0
var cy := 0
var dens := 1.0


static func build(parent: Node, m: WorldMap) -> void:
	var root := Node2D.new()
	root.name = "DetalhesDoChao"
	root.z_index = -2
	root.z_as_relative = false
	parent.add_child(root)
	var d := 0.5 if (Settings.is_mobile() or Settings.level_now <= 3) else 1.0
	for y in range(0, m.h, CHUNK):
		for x in range(0, m.w, CHUNK):
			var g := GroundDecals.new()
			g.map = m
			g.cx = x
			g.cy = y
			g.dens = d
			root.add_child(g)


func _draw() -> void:
	for y in range(cy, mini(cy + CHUNK, map.h)):
		for x in range(cx, mini(cx + CHUNK, map.w)):
			_tile(x, y)


func _r(x: int, y: int, k: int) -> float:
	return map.tile_rand(x, y, 300 + k)


func _p(x: int, y: int, k: int) -> Vector2:
	return Iso.to_screen(Vector2(x + 0.1 + _r(x, y, k) * 0.8, y + 0.1 + _r(x, y, k + 50) * 0.8))


func _edge_of_road(x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if map.at(x + d.x, y + d.y) != ":":
			return true
	return false


func _tile(x: int, y: int) -> void:
	var ch := map.at(x, y)
	var n := 0
	match ch:
		".":
			n = 5
		"f", "j":
			n = 6
		"g":
			n = 4
		":":
			n = 2 if _edge_of_road(x, y) else 0
		"r", "k":
			n = 3
		",":
			n = 1
		"b", "o", "y":
			n = 2
		_:
			n = 0
	n = int(round(n * dens))
	for i in n:
		var p := _p(x, y, i)
		var r := _r(x, y, 20 + i)
		match ch:
			".":
				if r < 0.62:
					tuft(self, p, 0.8 + _r(x, y, 40 + i) * 0.6, x * 7 + y + i, false)
				elif r < 0.72:
					flowers(self, p, x * 3 + y * 5 + i)
				elif r < 0.8:
					pebbles(self, p, x + y * 11 + i)
				else:
					moss(self, p, 10.0 + r * 8.0)
			"f", "j":
				if r < 0.35:
					leaves(self, p, x * 5 + y + i, ch == "f")
				elif r < 0.6:
					tuft(self, p, 0.9 + _r(x, y, 40 + i) * 0.7, x * 7 + y + i, false)
				elif r < 0.75:
					twigs(self, p, x + y * 3 + i)
				elif r < 0.88:
					moss(self, p, 12.0 + r * 10.0)
				else:
					small_mush(self, p, x * 13 + y + i)
			"g":
				if r < 0.5:
					tuft(self, p, 0.7 + _r(x, y, 40 + i) * 0.5, x * 7 + y + i, true)
				elif r < 0.8:
					leaves(self, p, x * 5 + y + i, true)
				else:
					twigs(self, p, x + y * 3 + i)
			":", "b", "o", "y":
				if r < 0.6:
					pebbles(self, p, x + y * 11 + i)
				else:
					tuft(self, p, 0.6, x * 7 + y + i, r > 0.85)
			"r", "k":
				pebbles(self, p, x + y * 11 + i)
			",":
				pebbles(self, p, x + y * 11 + i)


# ---------------------------------------------------------------- peças
static func tuft(n: CanvasItem, p: Vector2, s: float, sd: int, dry: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var k := rng.randi_range(5, 9)
	var base := Color(0.14, 0.2, 0.08) if not dry else Color(0.34, 0.29, 0.17)
	var tip := Color(0.32, 0.4, 0.17) if not dry else Color(0.52, 0.45, 0.28)
	for i in k:
		var a := lerpf(-1.0, 1.0, (i + rng.randf() * 0.6) / k)
		var h := rng.randf_range(7.0, 14.0) * s * (1.0 - absf(a) * 0.35)
		var b := p + Vector2(a * 4.0 * s, 0)
		var t := b + Vector2(a * h * 0.55 + rng.randf_range(-1.5, 1.5), -h)
		var c := base.lerp(tip, rng.randf())
		ElemArt.fan(n, PackedVector2Array([b + Vector2(-1.1 * s, 0), t, b + Vector2(1.1 * s, 0)]), c)


static func flowers(n: CanvasItem, p: Vector2, sd: int) -> void:
	tuft(n, p, 0.7, sd, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var cols := [Color(0.85, 0.8, 0.55), Color(0.7, 0.55, 0.75), Color(0.8, 0.45, 0.35)]
	var c: Color = cols[sd % cols.size()]
	for i in rng.randi_range(2, 4):
		var q := p + Vector2(rng.randf_range(-6, 6), -rng.randf_range(6, 11))
		n.draw_circle(q, 1.6, c)
		n.draw_circle(q, 0.7, Color(0.95, 0.85, 0.4))


static func pebbles(n: CanvasItem, p: Vector2, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for i in rng.randi_range(1, 3):
		var q := p + Vector2(rng.randf_range(-9, 9), rng.randf_range(-4, 4))
		var r := rng.randf_range(1.2, 3.2)
		n.draw_set_transform(q + Vector2(0.8, 0.8), 0.0, Vector2(1, 0.6))
		n.draw_circle(Vector2.ZERO, r * 1.1, Color(0, 0, 0, 0.25))
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		ElemArt.boulder(n, q, r, rng.randi(), rng.randf() * TAU, Color(0.3, 0.28, 0.25).lerp(Color(0.4, 0.36, 0.3), rng.randf()))


static func leaves(n: CanvasItem, p: Vector2, sd: int, autumn: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for i in rng.randi_range(3, 6):
		var q := p + Vector2(rng.randf_range(-12, 12), rng.randf_range(-6, 6))
		var c := Color(0.45, 0.3, 0.14) if autumn else Color(0.3, 0.38, 0.16)
		c = c.lerp(Color(0.55, 0.42, 0.2) if autumn else Color(0.4, 0.45, 0.2), rng.randf())
		ElemArt.leaf(n, q, Vector2.from_angle(rng.randf() * TAU) * Vector2(1, 0.55), rng.randf_range(2.5, 4.0), c)


static func twigs(n: CanvasItem, p: Vector2, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for i in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		var d := Vector2(cos(a), sin(a) * 0.5) * rng.randf_range(6, 12)
		var q := p + Vector2(rng.randf_range(-5, 5), rng.randf_range(-3, 3))
		n.draw_line(q - d, q + d, Color(0.28, 0.2, 0.13), 1.4)
		n.draw_line(q + d * 0.3, q + d * 0.3 + d.rotated(0.8) * 0.4, Color(0.28, 0.2, 0.13), 1.0)


static func moss(n: CanvasItem, p: Vector2, r: float) -> void:
	n.draw_set_transform(p, 0.0, Vector2(1, 0.5))
	n.draw_circle(Vector2.ZERO, r, Color(0.12, 0.18, 0.07, 0.22))
	n.draw_circle(Vector2(r * 0.3, -r * 0.2), r * 0.6, Color(0.16, 0.24, 0.09, 0.2))
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func small_mush(n: CanvasItem, p: Vector2, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for i in rng.randi_range(1, 3):
		var q := p + Vector2(rng.randf_range(-6, 6), rng.randf_range(-3, 3))
		var h := rng.randf_range(3, 6)
		n.draw_line(q, q + Vector2(0, -h), Color(0.85, 0.8, 0.7), 1.4)
		var cap := q + Vector2(0, -h)
		ElemArt.fan(n, PackedVector2Array([cap, cap + Vector2(-3.5, 1), cap + Vector2(-2, -2.5), cap + Vector2(2, -2.5), cap + Vector2(3.5, 1)]), Color(0.55, 0.3, 0.18))
