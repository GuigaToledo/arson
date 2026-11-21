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


## Casca de volume: une duas "fatias" (largura lateral w e profundidade d),
## para o corpo ter volume também visto de lado.
static func slab(p: Dictionary, c: Vector2, w: float, d: float) -> Array:
	return [c + lat(p, -w) + fwd(p, -d), c + lat(p, w) + fwd(p, -d), c + lat(p, w) + fwd(p, d), c + lat(p, -w) + fwd(p, d)]


static func vol(p: Dictionary, c1: Vector2, w1: float, d1: float, c2: Vector2, w2: float, d2: float) -> PackedVector2Array:
	var h := Geometry2D.convex_hull(PackedVector2Array(slab(p, c1, w1, d1) + slab(p, c2, w2, d2)))
	if h.size() > 1 and h[0].is_equal_approx(h[h.size() - 1]):
		h.remove_at(h.size() - 1)
	return h


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
	p.shC = (p.shL + p.shR) * 0.5
	p.hipC = (p.hipL + p.hipR) * 0.5
	p.kneeC = Vector2(0, -10 + bob)
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
	ci.draw_line(p.hipL, p.footL, under.darkened(0.2), 6.5)
	ci.draw_line(p.hipR, p.footR, under.darkened(0.2), 6.5)
	var r: Vector2 = p.r
	var near_right := r.y > 0.2
	var near_left := r.y < -0.2
	if near_right:
		ci.draw_line(p.shL, p.handL, under.darkened(0.3), 4.5)
	if near_left:
		ci.draw_line(p.shR, p.handR, under.darkened(0.3), 4.5)
	ci.draw_colored_polygon(vol(p, p.shC, p.w, 5.5, p.hipC, p.w * 0.55, 4.5), under)
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
	if c.get("core", false) and p.toward:
		var cc: Vector2 = Vector2(0, -51 + p.bob) + fwd(p, 3)
		var ccol: Color = c.get("core_col", Color(1, 0.45, 0.08))
		ci.draw_circle(cc, 7.0, Color(ccol, 0.25))
		ci.draw_circle(cc, 4.2, ccol)
		ci.draw_circle(cc, 2.0, ccol.lightened(0.6))
		for k in 5:
			var a := TAU * k / 5.0 + 0.4
			ci.draw_line(cc + Vector2(cos(a), sin(a) * 0.6) * 4.0, cc + Vector2(cos(a), sin(a) * 0.6) * 9.5, Color(ccol.darkened(0.1), 0.8), 1.0)
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
			ci.draw_colored_polygon(vol(p, p.shC + Vector2(0, -1), p.w, 6.0, p.kneeC + Vector2(0, 4), p.w * 1.15, 7.5), col)
			ci.draw_line(p.hipL + Vector2(0, -2), p.hipR + Vector2(0, -2), acc, 2.0)
			ci.draw_line((p.shL + p.shR) * 0.5, (kL + kR) * 0.5, acc.darkened(0.3), 1.0)
			ci.draw_line(p.shL, p.handL, col, 5.0)
			ci.draw_line(p.shR, p.handR, col, 5.0)
		"vest":
			ci.draw_colored_polygon(vol(p, p.shC + Vector2(0, -1), p.w, 6.0, p.hipC + Vector2(0, 4), p.w * 0.6, 5.0), col)
			ci.draw_line(p.hipL + Vector2(0, 1), p.hipR + Vector2(0, 1), acc, 2.0)
		"apron":
			ci.draw_colored_polygon(vol(p, p.shC, p.w, 6.0, p.hipC + Vector2(0, 2), p.w * 0.6, 5.0), acc)
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
			ci.draw_colored_polygon(vol(p, p.shC + Vector2(0, 1) - fwd(p, 3), p.w, 3.0, bot - fwd(p, 8), p.w * 1.3, 3.0), col)
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
		"wolfcape":
			draw_wolfcape_back(ci, p, it)
		"wolfskirt":
			draw_wolfskirt(ci, p, it)
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
	return Vector2(p.handL.x, -34.0 + p.bob) + lat(p, -4) + fwd(p, 7)


static func draw_mimic(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var c := shield_center(p)
	var f: Vector2 = p.f
	var face := absf(f.y) * 0.75 + 0.25
	var hw := 12.0 * face
	var hh := 27.0
	var rect := PackedVector2Array([c + Vector2(-hw, -hh + 3), c + Vector2(0, -hh), c + Vector2(hw, -hh + 3), c + Vector2(hw, hh - 2), c + Vector2(0, hh), c + Vector2(-hw, hh - 2)])
	ci.draw_colored_polygon(rect, it.placeholder_color.darkened(0.1))
	var rim := rect.duplicate()
	rim.append(rect[0])
	ci.draw_polyline(rim, Color(0.42, 0.36, 0.28), 2.0)
	if p.toward and face > 0.55:
		var acc := it.placeholder_accent
		for e in [Vector2(-0.45, -15), Vector2(0.45, -15), Vector2(-0.6, -6), Vector2(0.6, -6)]:
			var ep: Vector2 = c + Vector2(e.x * hw, e.y)
			ci.draw_circle(ep, 2.6, Color(acc, 0.3))
			ci.draw_circle(ep, 1.3, acc)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-hw * 0.75, 0), c + Vector2(hw * 0.75, 0), c + Vector2(hw * 0.5, 16), c + Vector2(-hw * 0.5, 16)]), Color(0.1, 0.02, 0.02))
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 6), c + Vector2(3, 6), c + Vector2(2, 15), c + Vector2(-2, 15)]), Color(0.55, 0.22, 0.2))
		for i in 6:
			var x := lerpf(-hw * 0.65, hw * 0.65, i / 5.0)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(x - 1.6, 0), c + Vector2(x + 1.6, 0), c + Vector2(x, 5)]), Color(0.88, 0.82, 0.68))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(x * 0.8 - 1.4, 16), c + Vector2(x * 0.8 + 1.4, 16), c + Vector2(x * 0.8, 11)]), Color(0.88, 0.82, 0.68))
		for r in [Vector2(0, -21), Vector2(0, 21)]:
			ci.draw_circle(c + r, 2.2, Color(0.5, 0.42, 0.3))
	else:
		for k in [-0.5, 0.0, 0.5]:
			ci.draw_line(c + Vector2(k * hw, -hh + 4), c + Vector2(k * hw, hh - 4), Color(0.18, 0.1, 0.06), 1.0)


static func fur_edge(ci: CanvasItem, a: Vector2, b: Vector2, depth: float, col: Color, n: int, sd: float) -> void:
	for i in n:
		var t := (i + 0.5) / n
		var base := a.lerp(b, t)
		var ln := depth * (0.6 + 0.4 * absf(sin(sd + i * 2.3)))
		ci.draw_line(base, base + Vector2(sin(sd + i) * 1.5, ln), col, 1.6)


static func draw_wolfcape_back(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var col := it.placeholder_color
	var bot := Vector2(0, -2)
	var w: float = p.w
	var bl: Vector2 = bot + lat(p, -w * 1.9) - fwd(p, 6)
	var br: Vector2 = bot + lat(p, w * 1.9) - fwd(p, 6)
	ci.draw_colored_polygon(vol(p, p.shC + Vector2(0, -3) - fwd(p, 3), w, 4.0, bot - fwd(p, 9), w * 1.9, 4.0), col)
	for i in 9:
		var t := i / 8.0
		var top: Vector2 = p.shL.lerp(p.shR, t)
		var low: Vector2 = bl.lerp(br, t)
		ci.draw_line(top, low, Color(0.5, 0.06, 0.04, 0.55), 1.0)
	fur_edge(ci, bl, br, 6.0, col, 12, 1.0)


static func draw_wolfcape_front(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var col := it.placeholder_color
	var acc := it.placeholder_accent
	var h: Vector2 = p.head
	var w: float = p.w
	# manto de pelo nos ombros
	ci.draw_colored_polygon(vol(p, p.shC + Vector2(0, -3), w + 3.5, 7.0, p.shC + Vector2(0, 9), w + 1.0, 6.5), col)
	if p.toward:
		fur_edge(ci, p.shL + Vector2(0, 8), (p.shL + p.shR) * 0.5 + Vector2(0, 6), 7.0, col.lightened(0.05), 5, 2.0)
		fur_edge(ci, (p.shL + p.shR) * 0.5 + Vector2(0, 6), p.shR + Vector2(0, 8), 7.0, col.lightened(0.05), 5, 4.0)
		for s in [p.shL, p.shR]:
			ci.draw_circle(s + Vector2(0, 2), 2.4, Color(0.55, 0.45, 0.32))
	# capuz com cabeça de lobo
	ci.draw_circle(h + Vector2(0, -1), 7.6, col)
	var snout_base: Vector2 = h + Vector2(0, -5) + fwd(p, 3)
	ci.draw_colored_polygon(PackedVector2Array([snout_base + lat(p, -3.5), snout_base + lat(p, 3.5), snout_base + fwd(p, 9) + Vector2(0, 1.5)]), col.darkened(0.2))
	for s in [-1.0, 1.0]:
		var e: Vector2 = h + lat(p, s * 4.2) + Vector2(0, -6) - fwd(p, 1)
		ci.draw_colored_polygon(PackedVector2Array([e + lat(p, -2.0), e + lat(p, 2.0), e + Vector2(0, -7)]), col.darkened(0.1))
		ci.draw_line(e, e + Vector2(0, -6), Color(0.6, 0.08, 0.04), 1.0)
		if p.toward:
			var we: Vector2 = h + lat(p, s * 2.6) + Vector2(0, -6) + fwd(p, 4)
			ci.draw_circle(we, 1.0, acc)
	if p.toward:
		ci.draw_circle(h + fwd(p, 2.6) + Vector2(0, 1.4), 4.0, Color(0.02, 0.015, 0.015))
		eyes(ci, p, Color(1, 0.62, 0.15), true)


static func draw_wolfskirt(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var col := it.placeholder_color
	var w: float = p.w
	ci.draw_line(p.hipL, p.footL + Vector2(0, -3), Color(0.08, 0.07, 0.075), 6.0)
	ci.draw_line(p.hipR, p.footR + Vector2(0, -3), Color(0.08, 0.07, 0.075), 6.0)
	var kl: Vector2 = Vector2(0, -12 + p.bob) + lat(p, -w * 1.2)
	var kr: Vector2 = Vector2(0, -12 + p.bob) + lat(p, w * 1.2)
	ci.draw_colored_polygon(vol(p, p.hipC + Vector2(0, -4), w * 0.65, 5.5, p.kneeC, w * 1.2, 8.5), col)
	ci.draw_line(p.hipL + Vector2(0, -3), p.hipR + Vector2(0, -3), Color(0.35, 0.28, 0.2), 2.0)
	fur_edge(ci, kl, kr, 7.0, col, 9, 3.0)
	for i in 6:
		var t := (i + 0.5) / 6.0
		ci.draw_line(p.hipL.lerp(p.hipR, t), kl.lerp(kr, t), Color(0.55, 0.07, 0.04, 0.5), 1.0)


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
