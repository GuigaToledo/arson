class_name PlaceholderPainter
extends RefCounted
## ARTE PROVISÓRIA. Desenha formas simples só para testar camadas, direções e
## troca de equipamentos. Será substituída pelos sprites renderizados (SpriteFrames
## no EquipmentItem); nenhum código do personagem precisa mudar quando isso acontecer.


static func lat(p: Dictionary, k: float) -> Vector2:
	var r: Vector2 = p.r
	return Vector2(r.x * k, r.y * k * 0.5)


static func fwd(p: Dictionary, k: float) -> Vector2:
	var f: Vector2 = p.f
	return Vector2(f.x * k, f.y * k * 0.5)


## Pose do esqueleto para a direção/animação atual.
static func pose(dir: String, anim: String, phase: float, t: float) -> Dictionary:
	var p := {}
	var f := Iso.dir_vector(dir)
	p.f = f
	p.r = Vector2(-f.y, f.x)
	p.toward = f.y > -0.25
	p.away = f.y < -0.3
	var moving := anim == "walk" or anim == "run"
	var amp := 11.0 if anim == "run" else (7.0 if anim == "walk" else 0.0)
	var swing := sin(phase) * amp
	var bob := (absf(sin(phase)) * -1.6) if moving else sin(t * 2.0) * 0.5
	var w := 9.0
	p.bob = bob
	var hip := Vector2(0, -36 + bob)
	var sh := Vector2(0, -60 + bob)
	p.hipL = hip + lat(p, -w * 0.45)
	p.hipR = hip + lat(p, w * 0.45)
	p.footL = lat(p, -w * 0.4) + fwd(p, swing) + Vector2(0, -maxf(0.0, sin(phase)) * 3.0 if moving else 0.0)
	p.footR = lat(p, w * 0.4) + fwd(p, -swing) + Vector2(0, -maxf(0.0, -sin(phase)) * 3.0 if moving else 0.0)
	p.shL = sh + lat(p, -w)
	p.shR = sh + lat(p, w)
	p.handL = p.shL + Vector2(0, 23) + fwd(p, -swing * 0.8)
	p.handR = p.shR + Vector2(0, 23) + fwd(p, swing * 0.8)
	p.casting = anim in ["cast", "spell", "attack"]
	if p.casting:
		p.handR = p.shR + Vector2(0, -12) + fwd(p, 9)
	p.head = Vector2(0, -69 + bob)
	p.w = w
	return p


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	ci.draw_circle(Vector2.ZERO, rx, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func eyes(ci: CanvasItem, p: Dictionary, col: Color, bright := true) -> void:
	if not p.toward:
		return
	var base: Vector2 = p.head + fwd(p, 3.2) + Vector2(0, 0.6)
	for s in [-1.0, 1.0]:
		var e: Vector2 = base + lat(p, s * 1.9)
		if bright:
			ci.draw_circle(e, 1.8, Color(col, 0.35))
		ci.draw_circle(e, 0.9, col)


static func draw_body(ci: CanvasItem, p: Dictionary, c: Dictionary) -> void:
	ellipse(ci, Vector2.ZERO, 15, 6.5, Color(0, 0, 0, 0.45))
	var skin: Color = c.get("skin", Color(0.55, 0.42, 0.34))
	var under: Color = c.get("under", Color(0.2, 0.18, 0.16))
	var hair: Color = c.get("hair", Color(0.08, 0.06, 0.05))
	ci.draw_line(p.hipL, p.footL, under.darkened(0.2), 5.5)
	ci.draw_line(p.hipR, p.footR, under.darkened(0.2), 5.5)
	var r: Vector2 = p.r
	var near_right := r.y > 0.2
	var near_left := r.y < -0.2
	if near_right:
		ci.draw_line(p.shL, p.handL, under.darkened(0.3), 4.5)
	if near_left:
		ci.draw_line(p.shR, p.handR, under.darkened(0.3), 4.5)
	ci.draw_colored_polygon(PackedVector2Array([p.shL, p.shR, p.hipR, p.hipL]), under)
	if not near_right:
		ci.draw_line(p.shL, p.handL, under.darkened(0.1), 4.5)
	if not near_left:
		ci.draw_line(p.shR, p.handR, under.darkened(0.1), 4.5)
	ci.draw_circle(p.handL, 2.2, skin)
	ci.draw_circle(p.handR, 2.2, skin)
	ci.draw_line(p.head + Vector2(0, 4), p.head + Vector2(0, 8), skin.darkened(0.2), 3.5)
	ci.draw_circle(p.head, 5.6, hair)
	if not p.away:
		ci.draw_circle(p.head + fwd(p, 1.8) + Vector2(0, 1.0), 4.6, skin)
	eyes(ci, p, c.get("eyes", Color(1, 0.62, 0.15)), c.get("glow_eyes", false))


static func draw_item(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var col := it.placeholder_color
	var acc := it.placeholder_accent
	match String(it.placeholder_style):
		"hood":
			ci.draw_circle(p.head + Vector2(0, -0.8), 7.2, col)
			ci.draw_colored_polygon(PackedVector2Array([p.head + lat(p, -5) + Vector2(0, -4), p.head + lat(p, 5) + Vector2(0, -4), p.head - fwd(p, 7) + Vector2(0, -9)]), col.darkened(0.15))
			ci.draw_colored_polygon(PackedVector2Array([p.shL + Vector2(0, -2), p.shR + Vector2(0, -2), p.head + Vector2(0, 5)]), col)
			if p.toward:
				ci.draw_circle(p.head + fwd(p, 2.4) + Vector2(0, 1.0), 4.3, Color(0.03, 0.02, 0.02))
				eyes(ci, p, acc, true)
		"helm":
			ci.draw_circle(p.head + Vector2(0, -0.5), 6.6, col)
			ci.draw_line(p.head + Vector2(0, -7), p.head + Vector2(0, 5) + fwd(p, 3), col.lightened(0.25), 1.2)
			if p.toward:
				ci.draw_line(p.head + fwd(p, 4) + lat(p, -3.5), p.head + fwd(p, 4) + lat(p, 3.5), Color(0.02, 0.02, 0.02), 2.0)
				eyes(ci, p, acc, true)
		"robe":
			var kL: Vector2 = Vector2(0, -6 + p.bob) + lat(p, -p.w * 1.15)
			var kR: Vector2 = Vector2(0, -6 + p.bob) + lat(p, p.w * 1.15)
			ci.draw_colored_polygon(PackedVector2Array([p.shL + Vector2(0, -1), p.shR + Vector2(0, -1), kR, kL]), col)
			ci.draw_line(p.hipL + Vector2(0, -2), p.hipR + Vector2(0, -2), acc, 2.0)
			ci.draw_line((p.shL + p.shR) * 0.5, (kL + kR) * 0.5, acc.darkened(0.3), 1.0)
			ci.draw_line(p.shL, p.handL, col, 5.0)
			ci.draw_line(p.shR, p.handR, col, 5.0)
		"vest":
			ci.draw_colored_polygon(PackedVector2Array([p.shL + Vector2(0, -1), p.shR + Vector2(0, -1), p.hipR + Vector2(0, 4), p.hipL + Vector2(0, 4)]), col)
			ci.draw_line(p.hipL + Vector2(0, 1), p.hipR + Vector2(0, 1), acc, 2.0)
		"apron":
			ci.draw_colored_polygon(PackedVector2Array([p.shL, p.shR, p.hipR + Vector2(0, 2), p.hipL + Vector2(0, 2)]), acc)
			if p.toward:
				var a: Vector2 = (p.hipL + p.hipR) * 0.5 + fwd(p, 2)
				ci.draw_colored_polygon(PackedVector2Array([a + lat(p, -6) + Vector2(0, -12), a + lat(p, 6) + Vector2(0, -12), a + lat(p, 7) + Vector2(0, 20), a + lat(p, -7) + Vector2(0, 20)]), col)
		"pauldron":
			for s in [p.shL, p.shR]:
				ellipse(ci, s + Vector2(0, -1), 5.0, 3.6, col)
				ci.draw_arc(s + Vector2(0, -1), 4.6, PI, TAU, 8, acc, 1.0)
		"gloves":
			ci.draw_circle(p.handL, 2.8, col)
			ci.draw_circle(p.handR, 2.8, col)
		"pants":
			ci.draw_line(p.hipL, p.footL + Vector2(0, -3), col, 6.0)
			ci.draw_line(p.hipR, p.footR + Vector2(0, -3), col, 6.0)
		"boots":
			ellipse(ci, p.footL + Vector2(0, -1.5), 3.6, 2.4, col)
			ellipse(ci, p.footR + Vector2(0, -1.5), 3.6, 2.4, col)
			ci.draw_line(p.footL + Vector2(0, -2), p.footL + Vector2(0, -8), col, 5.0)
			ci.draw_line(p.footR + Vector2(0, -2), p.footR + Vector2(0, -8), col, 5.0)
		"cape":
			var bot := Vector2(0, -3)
			ci.draw_colored_polygon(PackedVector2Array([p.shL + Vector2(0, 1), p.shR + Vector2(0, 1), bot + lat(p, p.w * 1.3) - fwd(p, 5), bot + lat(p, -p.w * 1.3) - fwd(p, 5)]), col)
			ci.draw_line(p.shL + Vector2(0, 1), p.shR + Vector2(0, 1), acc, 2.0)
		"staff":
			var top := staff_top(p)
			var base: Vector2 = p.handR + Vector2(0, 26) + fwd(p, 2)
			ci.draw_line(base, top, col, 3.0)
			ci.draw_line(base, top, col.lightened(0.2), 1.0)
			ci.draw_circle(top, 7.0, Color(acc, 0.18))
			ci.draw_circle(top, 4.2, acc)
			ci.draw_circle(top, 2.0, Color(1, 0.95, 0.75))
		"mimic":
			draw_mimic(ci, p, it)
		"amulet":
			if not p.away:
				var c := amulet_pos(p)
				ci.draw_line(p.shL + Vector2(0, 2), c, Color(0.5, 0.45, 0.35), 0.8)
				ci.draw_line(p.shR + Vector2(0, 2), c, Color(0.5, 0.45, 0.35), 0.8)
				ci.draw_circle(c, 3.0, Color(acc, 0.3))
				ci.draw_circle(c, 1.8, acc)


static func staff_top(p: Dictionary) -> Vector2:
	return p.handR + Vector2(0, -52) + fwd(p, 4)


static func amulet_pos(p: Dictionary) -> Vector2:
	return Vector2(0, -52 + p.bob) + fwd(p, 3)


static func shield_center(p: Dictionary) -> Vector2:
	return p.handL + lat(p, -3) + fwd(p, 5) + Vector2(0, -6)


static func draw_mimic(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var c := shield_center(p)
	var f: Vector2 = p.f
	var face := absf(f.y) * 0.7 + 0.3
	var hw := 8.0 * face
	var hh := 14.0
	var rect := PackedVector2Array([c + Vector2(-hw, -hh), c + Vector2(hw, -hh), c + Vector2(hw, hh), c + Vector2(-hw, hh)])
	ci.draw_colored_polygon(rect, it.placeholder_color)
	ci.draw_polyline(PackedVector2Array([rect[0], rect[1], rect[2], rect[3], rect[0]]), Color(0.45, 0.4, 0.32), 1.5)
	if p.toward and face > 0.5:
		var acc := it.placeholder_accent
		for s in [-1.0, 1.0]:
			ci.draw_circle(c + Vector2(s * hw * 0.45, -6), 1.4, acc)
		var mouth := PackedVector2Array()
		for i in 7:
			var x := lerpf(-hw * 0.8, hw * 0.8, i / 6.0)
			mouth.append(c + Vector2(x, 3.0 if i % 2 == 0 else 7.0))
		ci.draw_rect(Rect2(c + Vector2(-hw * 0.8, 1), Vector2(hw * 1.6, 8)), Color(0.12, 0.02, 0.02))
		ci.draw_polyline(mouth, Color(0.85, 0.8, 0.65), 1.2)


## Ponto onde o item emite luz (cajado, amuleto, olhos do escudo).
static func glow_point(it: EquipmentItem, p: Dictionary) -> Vector2:
	match String(it.placeholder_style):
		"staff":
			return staff_top(p)
		"amulet":
			return amulet_pos(p)
		"mimic":
			return shield_center(p)
	return Vector2(0, -40)
