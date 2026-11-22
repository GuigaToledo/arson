class_name CreatureVisual
extends CharacterVisual
## Corpo de criaturas que não são humanoides, desenhado por código em 8 direções:
## slime, quadrúpede (lobo, urso, felino, onça), morcego, aranha e fantasma.
## Mesmo "contrato" do CharacterVisual (tick, modulate, scale), então o Monster não muda.

var body := "slime"
var variant := ""
var c_main := Color(0.4, 0.75, 0.3)
var c_dark := Color(0.2, 0.4, 0.15)
var c_belly := Color(0.6, 0.85, 0.5)
var c_eye := Color(1, 0.3, 0.1)
var _light: PointLight2D


func setup(eq: EquipmentComponent) -> void:
	equipment = eq
	c_main = body_colors.get("main", c_main)
	c_dark = body_colors.get("dark", c_main.darkened(0.45))
	c_belly = body_colors.get("belly", c_main.lightened(0.25))
	c_eye = body_colors.get("eyes", c_eye)
	if body_colors.get("glow", false):
		_light = LightKit.make(body_colors.get("glow_col", c_main), 0.7, 0.45, false, 0.15)
		_light.position = Vector2(0, -16)
		add_child(_light)


func set_glow(_a: Color, _b: Color) -> void:
	pass


func tick(delta: float, new_dir: String, new_anim: String, speed: float) -> void:
	_time += delta
	if new_anim != anim:
		_anim_t = 0.0
	_anim_t += delta
	dir = new_dir
	anim = new_anim
	if anim == "walk" or anim == "run":
		_phase += delta * maxf(speed, 40.0) * 0.09
	if view_rect.size.x > 0.0 and not view_rect.has_point(global_position):
		visible = false
		_draw_acc = 1.0
		return
	visible = true
	_draw_acc += delta
	if _draw_acc < 1.0 / minf(draw_hz, Settings.anim_hz()):
		return
	_draw_acc = 0.0
	queue_redraw()


# ------------------------------------------------------------ ajudas
func _f() -> Vector2:
	return Iso.dir_vector(dir)


func fwd(k: float) -> Vector2:
	var f := _f()
	return Vector2(f.x * k, f.y * k * 0.5)


func lat(k: float) -> Vector2:
	var f := _f()
	return Vector2(-f.y * k, f.x * k * 0.5)


func ell(c: Vector2, rx: float, ry: float, col: Color) -> void:
	PlaceholderPainter.ellipse(self, c, rx, ry, col)


func blobpoly(centers: Array, r: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for c: Vector2 in centers:
		for i in 14:
			var a := TAU * i / 14.0
			pts.append(c + Vector2(cos(a) * r, sin(a) * r * ry))
	var h := Geometry2D.convex_hull(pts)
	if h.size() > 1 and h[0].is_equal_approx(h[h.size() - 1]):
		h.remove_at(h.size() - 1)
	return h


func _lunge() -> float:
	if anim in ["attack", "punch", "kick", "cast"]:
		return sin(clampf(_anim_t / 0.4, 0.0, 1.0) * PI)
	return 0.0


func _draw() -> void:
	match body:
		"slime":
			_slime()
		"quadrupede":
			_quad()
		"morcego":
			_bat()
		"aranha":
			_spider()
		"fantasma":
			_ghost()


# ------------------------------------------------------------ slime
func _slime() -> void:
	var moving := anim == "walk" or anim == "run"
	var hop := absf(sin(_phase)) if moving else 0.0
	var wob := sin(_time * 3.0) * 0.06
	var land := 1.0 - hop
	var sx := 1.0 + 0.18 * land * (1.0 if moving else 0.4) + wob
	var sy := 1.0 - 0.12 * land + hop * 0.15 - wob
	var lg := _lunge()
	sx += lg * 0.2
	sy -= lg * 0.15
	var y0 := -hop * 12.0
	var off := fwd(lg * 8.0)
	ell(Vector2.ZERO, 15 * (1.0 - hop * 0.35), 6 * (1.0 - hop * 0.35), Color(0, 0, 0, 0.35))
	var rw := 15.0 * sx
	var hh := 19.0 * sy
	var pts := PackedVector2Array()
	for i in 17:
		var a := PI * i / 16.0
		pts.append(off + Vector2(cos(a) * rw, y0 - sin(a) * hh - 1.0))
	for i in range(1, 8):
		var a := PI * i / 8.0
		pts.append(off + Vector2(-cos(a) * rw, y0 + sin(a) * 3.0))
	var alpha := 0.88
	draw_colored_polygon(pts, Color(c_main, alpha))
	ell(off + Vector2(0, y0 - hh * 0.35), rw * 0.55, hh * 0.3, Color(c_dark, 0.45))
	if body_colors.get("glow", false):
		ell(off + Vector2(0, y0 - hh * 0.4), rw * 0.4, hh * 0.25, Color(body_colors.get("glow_col", c_main), 0.7))
	ell(off + Vector2(-rw * 0.38, y0 - hh * 0.72), rw * 0.22, hh * 0.12, Color(1, 1, 1, 0.55))
	var f := _f()
	if f.y > -0.3:
		var e := off + Vector2(0, y0 - hh * 0.55) + fwd(rw * 0.55)
		for s in [-1.0, 1.0]:
			var p := e + lat(s * 5.0)
			ell(p, 2.2, 3.0, Color(0.05, 0.04, 0.04))
			draw_circle(p + Vector2(-0.6, -1.0), 0.8, Color(1, 1, 1, 0.9))


# ------------------------------------------------------------ quadrúpedes
func _quad() -> void:
	var P := {
		"lobo": {"len": 24.0, "h": 19.0, "r": 8.0, "leg": 2.8, "head": 6.5, "snout": 7.0, "ears": "ponta", "tail": "peluda"},
		"urso": {"len": 28.0, "h": 23.0, "r": 13.0, "leg": 5.0, "head": 8.5, "snout": 5.0, "ears": "redonda", "tail": "curta"},
		"felino": {"len": 28.0, "h": 17.0, "r": 7.5, "leg": 2.6, "head": 6.0, "snout": 3.5, "ears": "redonda", "tail": "longa"},
	}
	var v: Dictionary = P.get(variant if variant != "onca" else "felino", P.lobo)
	var f := _f()
	var moving := anim == "walk" or anim == "run"
	var amp := (9.0 if anim == "run" else 6.0) if moving else 0.0
	var sw := sin(_phase) * amp
	var bob := absf(sin(_phase)) * 1.5 if moving else sin(_time * 2.0) * 0.5
	var lg := _lunge()
	var off := fwd(lg * 10.0) + Vector2(0, -lg * 3.0)
	var L: float = v.len
	var h: float = v.h - bob
	var c := off + Vector2(0, -h)
	var front := c + fwd(L * 0.4)
	var back := c - fwd(L * 0.4)
	ell(off, L * 0.55 + 4, 7, Color(0, 0, 0, 0.35))
	# patas: pares diagonais
	var legs := []
	var k := 0
	for base in [front, back]:
		for s in [-1.0, 1.0]:
			var swing := sw if (k == 0 or k == 3) else -sw
			var top: Vector2 = base + lat(s * v.r * 0.55)
			var lift := -maxf(0.0, sin(_phase + k * PI * 0.5)) * 2.5 if moving else 0.0
			var foot: Vector2 = off + (top - c) + fwd(swing)
			foot.y = off.y + (top.y - c.y) + lift
			legs.append([top, foot, lat(s).y])
			k += 1
	var far := []
	var near := []
	for l in legs:
		if l[2] < 0.0:
			far.append(l)
		else:
			near.append(l)
	var tail_first := f.y >= 0.0
	if tail_first:
		_tail(back, v, c)
	for l in far:
		draw_line(l[0], l[1], c_dark.darkened(0.2), v.leg)
	var body_pts := blobpoly([front, back], v.r, 0.85)
	draw_colored_polygon(body_pts, c_main)
	ell(c + Vector2(0, v.r * 0.35), L * 0.35, v.r * 0.35, Color(c_belly, 0.5))
	if variant == "onca":
		for i in 9:
			var sp := c + fwd((i % 3 - 1) * L * 0.25) + lat(((i / 3) - 1) * v.r * 0.5) + Vector2(0, -2)
			draw_circle(sp, 1.6, Color(0.1, 0.07, 0.04, 0.8))
	if variant == "urso":
		ell(front + Vector2(0, -v.r * 0.5), v.r * 0.9, v.r * 0.6, c_main.lightened(0.06))
	for l in near:
		draw_line(l[0], l[1], c_main.darkened(0.1), v.leg)
		draw_circle(l[1], v.leg * 0.6, c_dark)
	if not tail_first:
		_tail(back, v, c)
	var hc: Vector2 = front + fwd(L * 0.28) + Vector2(0, -v.r * 0.55 - lg * 2.0)
	if f.y < -0.2:
		# de costas: a cabeça fica atrás do corpo
		_quad_head(hc, v, f, lg)
		draw_colored_polygon(body_pts, c_main)
		for l in near:
			draw_line(l[0], l[1], c_main.darkened(0.1), v.leg)
	else:
		_quad_head(hc, v, f, lg)


func _quad_head(hc: Vector2, v: Dictionary, f: Vector2, lg: float) -> void:
	draw_circle(hc, v.head, c_main.lightened(0.04))
	var sn: Vector2 = hc + fwd(v.snout) + Vector2(0, 1.5)
	draw_colored_polygon(PackedVector2Array([hc + lat(-v.head * 0.55) + Vector2(0, 1), hc + lat(v.head * 0.55) + Vector2(0, 1), sn + lat(1.5), sn + lat(-1.5)]), c_belly.darkened(0.1))
	draw_circle(sn, 1.6, Color(0.05, 0.04, 0.04))
	for s in [-1.0, 1.0]:
		var ep: Vector2 = hc + lat(s * v.head * 0.75) + Vector2(0, -v.head * 0.7)
		if v.ears == "ponta":
			draw_colored_polygon(PackedVector2Array([ep + lat(-2.2), ep + lat(2.2), ep + Vector2(0, -7)]), c_dark)
		else:
			draw_circle(ep, 2.6, c_dark)
	if f.y > -0.35:
		for s in [-1.0, 1.0]:
			var e: Vector2 = hc + fwd(v.head * 0.55) + lat(s * 2.6) + Vector2(0, -1.5)
			draw_circle(e, 1.9, Color(c_eye, 0.35))
			draw_circle(e, 1.0, c_eye)
	if lg > 0.3 and f.y > -0.35:
		draw_colored_polygon(PackedVector2Array([sn + lat(-2), sn + lat(2), sn + Vector2(0, 4)]), Color(0.5, 0.1, 0.08))


func _tail(back: Vector2, v: Dictionary, c: Vector2) -> void:
	var sw := sin(_time * 4.0) * 4.0
	var base := back - fwd(3.0) + Vector2(0, -2)
	var pts := PackedVector2Array()
	var n := 6
	var ln := 16.0 if v.tail == "longa" else (13.0 if v.tail == "peluda" else 4.0)
	for i in n + 1:
		var t := float(i) / n
		pts.append(base - fwd(ln * t) + lat(sw * t * t) + Vector2(0, (-6.0 if v.tail == "longa" else 2.0) * t * t))
	var w := 5.0 if v.tail == "peluda" else (2.5 if v.tail == "longa" else 6.0)
	draw_polyline(pts, c_dark, w)
	if v.tail == "peluda":
		draw_circle(pts[n], 2.5, c_belly)


# ------------------------------------------------------------ morcego
func _bat() -> void:
	var f := _f()
	var hover := 40.0 + sin(_time * 5.0) * 4.0 - _lunge() * 18.0
	var c := fwd(_lunge() * 12.0) + Vector2(0, -hover)
	ell(Vector2.ZERO, 9, 3.5, Color(0, 0, 0, 0.3))
	var flap := sin(_time * 18.0)
	for s in [-1.0, 1.0]:
		var sh := c + lat(s * 4.0)
		var tip := c + lat(s * 24.0) + Vector2(0, -10.0 * flap)
		var mid := c + lat(s * 14.0) + Vector2(0, -4.0 * flap - 2.0)
		var pts := PackedVector2Array([sh + Vector2(0, -3), mid + Vector2(0, -4), tip, c + lat(s * 18.0) + Vector2(0, 6 - 6 * flap), c + lat(s * 10.0) + Vector2(0, 4 - 3 * flap), sh + Vector2(0, 4)])
		draw_colored_polygon(pts, c_dark)
		draw_line(sh, tip, c_main.darkened(0.3), 1.2)
	ell(c, 6, 8, c_main)
	var hd := c + Vector2(0, -8) + fwd(2)
	draw_circle(hd, 4.5, c_main)
	for s in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([hd + lat(s * 1.5) + Vector2(0, -2), hd + lat(s * 4.5) + Vector2(0, -2), hd + lat(s * 3.5) + Vector2(0, -9)]), c_dark)
		if f.y > -0.3:
			draw_circle(hd + fwd(2.5) + lat(s * 1.8), 1.0, c_eye)


# ------------------------------------------------------------ aranha
func _spider() -> void:
	var f := _f()
	var moving := anim == "walk" or anim == "run"
	var lg := _lunge()
	var off := fwd(lg * 8.0)
	var c := off + Vector2(0, -11 - (sin(_phase * 2.0) * 1.0 if moving else 0.0))
	var abd := c - fwd(11.0) + Vector2(0, -3)
	var ceph := c + fwd(5.0)
	ell(off, 24, 9, Color(0, 0, 0, 0.35))
	var legs := []
	for s in [-1.0, 1.0]:
		for i in 4:
			var k := (i - 1.5) * 4.0
			var sw := sin(_phase * 1.6 + i * 1.3 + (0.0 if s > 0 else PI)) * (4.0 if moving else 0.6)
			var base: Vector2 = ceph + lat(s * 4.0) + fwd(k * 0.3)
			var knee: Vector2 = base + lat(s * 13.0) + fwd(k * 1.4 + sw * 0.5) + Vector2(0, -10)
			var foot: Vector2 = off + (base - c) * 0.0 + lat(s * 22.0) + fwd(k * 2.2 + sw)
			legs.append([base, knee, foot, lat(s).y])
	for l in legs:
		if l[3] < 0.0:
			draw_polyline(PackedVector2Array([l[0], l[1], l[2]]), c_dark, 2.2)
	if f.y >= 0.0:
		draw_colored_polygon(blobpoly([abd], 12.0, 0.85), c_main)
		_abd_mark(abd)
		draw_colored_polygon(blobpoly([ceph], 7.0, 0.8), c_main.lightened(0.05))
	else:
		draw_colored_polygon(blobpoly([ceph], 7.0, 0.8), c_main.lightened(0.05))
		draw_colored_polygon(blobpoly([abd], 12.0, 0.85), c_main)
		_abd_mark(abd)
	for l in legs:
		if l[3] >= 0.0:
			draw_polyline(PackedVector2Array([l[0], l[1], l[2]]), c_main.darkened(0.15), 2.4)
	if f.y > -0.4:
		for i in 4:
			var e := ceph + fwd(5.0) + lat((i - 1.5) * 1.8) + Vector2(0, -1.5 - (1.0 if i % 3 == 0 else 0.0))
			draw_circle(e, 1.2, c_eye)
		if lg > 0.3:
			for s in [-1.0, 1.0]:
				draw_line(ceph + fwd(6) + lat(s * 1.5), ceph + fwd(9) + lat(s * 0.5) + Vector2(0, 3), Color(0.8, 0.75, 0.6), 1.4)


func _abd_mark(abd: Vector2) -> void:
	var mk: Color = body_colors.get("mark", Color(0.6, 0.1, 0.06))
	draw_colored_polygon(PackedVector2Array([abd + Vector2(-2.5, -4), abd + Vector2(2.5, -4), abd + Vector2(0, 0), abd + Vector2(2.5, 4), abd + Vector2(-2.5, 4), abd + Vector2(0, 0)]), mk)


# ------------------------------------------------------------ fantasma
func _ghost() -> void:
	var f := _f()
	var bob := sin(_time * 2.2) * 4.0
	var lg := _lunge()
	var c := fwd(lg * 10.0) + Vector2(0, -14 + bob)
	ell(Vector2.ZERO, 12, 4.5, Color(0, 0, 0, 0.22))
	var a := 0.62
	var top := c + Vector2(0, -58)
	var pts := PackedVector2Array()
	pts.append(top + lat(-9) + Vector2(0, 10))
	pts.append(top + Vector2(0, -2))
	pts.append(top + lat(9) + Vector2(0, 10))
	pts.append(c + lat(15) + Vector2(0, -20))
	for i in 7:
		var t := i / 6.0
		var x := lerpf(15.0, -15.0, t)
		pts.append(c + lat(x) + Vector2(0, (4.0 if i % 2 == 0 else -4.0) + sin(_time * 5.0 + i) * 2.5))
	pts.append(c + lat(-15) + Vector2(0, -20))
	draw_colored_polygon(pts, Color(c_main, a))
	for s in [-1.0, 1.0]:
		var sh := top + lat(s * 9) + Vector2(0, 16)
		var hand := sh + lat(s * 6) + fwd(10 + lg * 10) + Vector2(0, 14 + sin(_time * 3 + s) * 3)
		draw_line(sh, hand, Color(c_main, a), 5.0)
		draw_circle(hand, 2.5, Color(c_belly, a))
	draw_circle(top + Vector2(0, 8), 8.0, Color(c_dark, 0.85))
	if f.y > -0.3:
		for s in [-1.0, 1.0]:
			var e := top + Vector2(0, 8) + fwd(4) + lat(s * 3)
			draw_circle(e, 2.6, Color(c_eye, 0.35))
			draw_circle(e, 1.3, c_eye)
