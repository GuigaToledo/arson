class_name Prop
extends StaticBody2D
## Objeto do cenário em perspectiva isométrica (mesa, banco, barril, balcão,
## pilar, lareira). ARTE PROVISÓRIA desenhada por formas; a colisão, a sombra
## (LightOccluder2D) e a transparência quando o jogador passa atrás já são as finais.

var kind := "box"
var gpos := Vector2.ZERO
var gsize := Vector2.ONE
var height := 40.0
var color := Color(0.3, 0.2, 0.12)
var casts_shadow := false
var fade_when_behind := false
## Imagem da peça (arte final). Se vazio, desenha a forma provisória.
var tex: Texture2D
var tex_scale := 1.0
var tex_flip := false
## Onde fica o "pé" da imagem (base, centro embaixo), relativo à origem da peça.
var tex_foot := Vector2.ZERO
## Pixel da imagem que encosta no chão (origem da peça). Negativo = centro da base.
var tex_anchor := Vector2(-1, -1)

var A: Vector2
var B: Vector2
var C: Vector2
var D: Vector2
var _bounds: Rect2
var _player: Node2D
var _fade := 1.0


func with_image(path: String, sc: float, foot := Vector2.ZERO, flip := false, anchor := Vector2(-1, -1)) -> Prop:
	if ResourceLoader.exists(path):
		tex = load(path)
		tex_anchor = anchor
		tex_scale = sc
		tex_foot = foot
		tex_flip = flip
		var sz := tex.get_size() * sc
		height = sz.y
		fade_when_behind = sz.y > 90.0
	return self


func setup(k: String, gp: Vector2, gs: Vector2, h: float, col: Color) -> Prop:
	kind = k
	gpos = gp
	gsize = gs
	height = h
	color = col
	casts_shadow = h > 50.0
	fade_when_behind = h > 90.0
	return self


func _ready() -> void:
	position = Iso.to_screen(gpos + gsize * 0.5)
	A = Iso.to_screen(gpos) - position
	B = Iso.to_screen(gpos + Vector2(gsize.x, 0)) - position
	C = Iso.to_screen(gpos + gsize) - position
	D = Iso.to_screen(gpos + Vector2(0, gsize.y)) - position
	var foot := PackedVector2Array([A, B, C, D])
	var cp := CollisionPolygon2D.new()
	cp.polygon = foot
	add_child(cp)
	if casts_shadow:
		var occ := LightOccluder2D.new()
		var op := OccluderPolygon2D.new()
		op.polygon = foot
		occ.occluder = op
		add_child(occ)
	_bounds = Rect2(Vector2(D.x, A.y - height), Vector2(B.x - D.x, C.y - A.y + height))
	if tex:
		_bounds = _tex_rect()
		if tex_flip:
			_bounds.position.x = -_bounds.position.x - _bounds.size.x
		_bounds.position += tex_foot
		_bounds = _bounds.grow(-_bounds.size.x * 0.08)
	set_process(false)
	if fade_when_behind or tex != null:
		var k := _cell(global_position)
		if not _cells.has(k):
			_cells[k] = []
		_cells[k].append(self)


## Transparência central: só as peças perto do jogador são testadas a cada quadro
## (antes cada árvore rodava o próprio _process, pesado com o mapa grande).
static var _cells := {}
const CELL := 512.0


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


static func update_fades(pl: Node2D, delta: float) -> void:
	if pl == null or not is_instance_valid(pl):
		return
	var c := _cell(pl.global_position)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var arr = _cells.get(c + Vector2i(dx, dy))
			if arr == null:
				continue
			for pr in arr:
				if is_instance_valid(pr) and pr.fade_when_behind:
					pr._fade_step(pl, delta)


func _exit_tree() -> void:
	var arr = _cells.get(_cell(global_position))
	if arr != null:
		arr.erase(self)


func _fade_step(pl: Node2D, delta: float) -> void:
	var lp := pl.global_position - global_position
	var behind := lp.y < 0.0 and _bounds.grow(6).has_point(lp + Vector2(0, -35))
	_fade = move_toward(_fade, 0.35 if behind else 1.0, delta * 3.0)
	modulate.a = _fade


## Retângulo da imagem relativo ao ponto de apoio (antes do espelhamento).
func _tex_rect() -> Rect2:
	var sz := tex.get_size() * tex_scale
	var an := Vector2(sz.x * 0.5, sz.y) if tex_anchor.x < 0 else tex_anchor * tex_scale
	return Rect2(-an, sz)


func up(p: Vector2, h: float) -> Vector2:
	return p + Vector2(0, -h)


func box(a: Vector2, b: Vector2, c: Vector2, d: Vector2, h0: float, h1: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([up(d, h0), up(c, h0), up(c, h1), up(d, h1)]), col)
	draw_colored_polygon(PackedVector2Array([up(c, h0), up(b, h0), up(b, h1), up(c, h1)]), col.darkened(0.35))
	draw_colored_polygon(PackedVector2Array([up(a, h1), up(b, h1), up(c, h1), up(d, h1)]), col.lightened(0.12))


func inset(k: float) -> Array:
	var ctr := (A + C) * 0.5
	return [A.lerp(ctr, k), B.lerp(ctr, k), C.lerp(ctr, k), D.lerp(ctr, k)]


func _draw() -> void:
	if tex:
		draw_set_transform(tex_foot, 0.0, Vector2(-1, 1) if tex_flip else Vector2.ONE)
		draw_texture_rect(tex, _tex_rect(), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	match kind:
		"table":
			var legs := inset(0.18)
			for i in [0, 1, 3, 2]:
				draw_line(legs[i], up(legs[i], height - 5), color.darkened(0.45), 3.0)
			box(A, B, C, D, height - 5, height, color)
			for i in 4:
				var t := 0.18 + 0.2 * i
				draw_line(up(A.lerp(D, t), height), up(B.lerp(C, t), height), color.darkened(0.12), 1.0)
			var mid := up((A + C) * 0.5, height)
			draw_rect(Rect2(mid + Vector2(-14, -7), Vector2(5, 7)), Color(0.55, 0.5, 0.42))
			draw_rect(Rect2(mid + Vector2(10, -6), Vector2(5, 6)), Color(0.45, 0.33, 0.2))
			draw_rect(Rect2(mid + Vector2(-1.5, -10), Vector2(3, 10)), Color(0.9, 0.86, 0.75))
			draw_circle(mid + Vector2(0, -13), 2.5, Color(1, 0.75, 0.3))
		"bench":
			var legs := inset(0.12)
			for i in [0, 1, 3, 2]:
				draw_line(legs[i], up(legs[i], height - 4), color.darkened(0.45), 2.5)
			box(A, B, C, D, height - 4, height, color)
		"campfire":
			var ctr := (A + C) * 0.5
			for i in 8:
				var a := TAU * i / 8.0
				PlaceholderPainter.ellipse(self, ctr + Vector2(cos(a) * 16, sin(a) * 8), 4, 3, Color(0.32, 0.3, 0.28))
		"barrel":
			var ctr := (A + C) * 0.5
			var rx := (B.x - D.x) * 0.36
			var ry := rx * 0.5
			PlaceholderPainter.ellipse(self, ctr, rx, ry, color.darkened(0.2))
			draw_colored_polygon(PackedVector2Array([ctr + Vector2(-rx, 0), ctr + Vector2(rx, 0), ctr + Vector2(rx, -height), ctr + Vector2(-rx, -height)]), color)
			for k in [0.15, 0.85]:
				draw_line(ctr + Vector2(-rx, -height * k), ctr + Vector2(rx, -height * k), Color(0.18, 0.17, 0.16), 2.0)
			PlaceholderPainter.ellipse(self, ctr + Vector2(0, -height), rx, ry, color.lightened(0.1))
			PlaceholderPainter.ellipse(self, ctr + Vector2(0, -height), rx * 0.85, ry * 0.85, color.darkened(0.15))
		"fireplace":
			box(A, B, C, D, 0, height, color)
			var o0 := D.lerp(C, 0.22)
			var o1 := D.lerp(C, 0.78)
			var hole := PackedVector2Array([o0, o1, up(o1, height * 0.42)])
			for i in range(1, 8):
				var t := i / 8.0
				hole.append(up(o1.lerp(o0, t), height * 0.42 + sin(t * PI) * height * 0.12))
			hole.append(up(o0, height * 0.42))
			draw_colored_polygon(hole, Color(0.05, 0.03, 0.02))
			draw_line(up(D, height), up(C, height), color.lightened(0.2), 4.0)
			var mid := o0.lerp(o1, 0.5)
			draw_line(mid + Vector2(-12, -3), mid + Vector2(10, -6), Color(0.2, 0.12, 0.06), 4.0)
			draw_line(mid + Vector2(-8, -6), mid + Vector2(13, -2), Color(0.25, 0.14, 0.07), 4.0)
		"house":
			var wall := height * 0.55
			box(A, B, C, D, 0, wall, color)
			var roof := Color(0.2, 0.15, 0.12)
			var r1 := up((A + D) * 0.5, height)
			var r2 := up((B + C) * 0.5, height)
			draw_colored_polygon(PackedVector2Array([up(A, wall), up(B, wall), r2, r1]), roof.darkened(0.3))
			draw_colored_polygon(PackedVector2Array([up(C, wall), up(B, wall), r2]), color.darkened(0.45))
			draw_colored_polygon(PackedVector2Array([up(D, wall), up(C, wall), r2, r1]), roof)
			for k in [0.3, 0.7]:
				var wp := D.lerp(C, k)
				draw_rect(Rect2(up(wp, wall * 0.75) + Vector2(-6, 0), Vector2(12, wall * 0.3)), Color(1, 0.7, 0.35, 0.9))
			var door := D.lerp(C, 0.5)
			draw_colored_polygon(PackedVector2Array([door + Vector2(-9, -4), door + Vector2(9, 4), up(door + Vector2(9, 4), wall * 0.5), up(door + Vector2(-9, -4), wall * 0.5)]), Color(0.18, 0.11, 0.06))
		_:
			box(A, B, C, D, 0, height, color)
			if kind == "crate":
				draw_line(up(D, 0), up(C, height), color.darkened(0.3), 2.0)
				draw_line(up(C, 0), up(B, height), color.darkened(0.5), 2.0)


## Ponto central da abertura da lareira (para fogo e luz).
func hearth_point() -> Vector2:
	return D.lerp(C, 0.5) + Vector2(0, -8)
