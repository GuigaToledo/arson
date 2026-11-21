class_name SummonPainter
extends RefCounted
## Corpo de cada invocação, com o mesmo esqueleto articulado dos personagens (dá para socar,
## chutar, girar, dar cabeçada e agarrar), mas feito do próprio elemento:
## golem de terra/lava/gelo = blocos; fogo = chamas flutuando; vento = fitas de vento e redemoinho;
## raio = só raios; água = corpo líquido; natureza = raízes entrelaçadas.

static func lat(p: Dictionary, k: float) -> Vector2:
	return PlaceholderPainter.lat(p, k)


static func fwd(p: Dictionary, k: float) -> Vector2:
	return PlaceholderPainter.fwd(p, k)


static func bones(p: Dictionary) -> Array:
	return [[p.hipL, p.kneeL], [p.kneeL, p.footL], [p.hipR, p.kneeR], [p.kneeR, p.footR],
		[p.shL, p.elbowL], [p.elbowL, p.handL], [p.shR, p.elbowR], [p.elbowR, p.handR]]


static func arms(p: Dictionary) -> Array:
	return [[p.shL, p.elbowL], [p.elbowL, p.handL], [p.shR, p.elbowR], [p.elbowR, p.handR]]


static func draw(ci: CanvasItem, p: Dictionary, c: Dictionary) -> void:
	var el: String = c.summon
	PlaceholderPainter.ellipse(ci, Vector2.ZERO, 17, 7, Color(0, 0, 0, 0.4))
	match el:
		"terra", "lava", "gelo":
			_golem(ci, p, el)
		"fogo":
			_fire(ci, p)
		"vento":
			_wind(ci, p)
		"raio":
			_lightning(ci, p)
		"agua":
			_water(ci, p)
		"natureza":
			_roots(ci, p)
	var el2: String = c.get("summon2", "")
	if el2 != "":
		_accent(ci, p, el2)


# ------------------------------------------------------------ golens: corpo de blocos
static func _golem(ci: CanvasItem, p: Dictionary, el: String) -> void:
	var stone := Color(0.42, 0.37, 0.31)
	var seam := Color(0, 0, 0, 0)
	match el:
		"lava":
			stone = Color(0.17, 0.1, 0.08)
			seam = Color(1, 0.45 + 0.1 * sin(p.t * 4.0), 0.08)
		"gelo":
			stone = Color(0.62, 0.8, 0.92, 0.85)
			seam = Color(0.85, 0.97, 1, 0.8)
	var sd := 3
	# pernas e braços: blocos ao longo dos ossos (o de trás mais escuro)
	for b in bones(p):
		var a: Vector2 = b[0]
		var e: Vector2 = b[1]
		for k in 2:
			var q := a.lerp(e, (k + 0.5) / 2.0)
			if el == "gelo":
				_crystal(ci, q, 6.2, stone, sd)
			else:
				SpellArt.rock(ci, q, 6.4, stone.darkened(0.05 * (k % 2)), sd)
			sd += 7
		if seam.a > 0.0:
			ci.draw_line(a, e, Color(seam, 0.55), 1.6, true)
	# punhos e pés de pedra maiores
	for q in [p.handL, p.handR]:
		SpellArt.rock(ci, q, 5.5, stone.lightened(0.05), 41)
	for q in [p.footL, p.footR]:
		SpellArt.rock(ci, q + Vector2(0, -3), 5.5, stone.darkened(0.1), 43)
	# tronco: aglomerado de pedras, ombros enormes
	var torso := [p.shC + Vector2(0, 2), p.shC.lerp(p.hipC, 0.5), p.hipC + Vector2(0, -2)]
	for i in torso.size():
		var q2: Vector2 = torso[i]
		if el == "gelo":
			_crystal(ci, q2, 11.0 - i, stone, 50 + i)
		else:
			SpellArt.rock(ci, q2, 11.0 - i * 1.5, stone, 50 + i)
	for q3 in [p.shL, p.shR]:
		SpellArt.rock(ci, q3 + Vector2(0, -2), 7.5, stone.lightened(0.08), 61)
	if seam.a > 0.0:
		# rachaduras brilhando no peito
		var cc: Vector2 = p.shC.lerp(p.hipC, 0.4)
		for k2 in 4:
			var ang := TAU * k2 / 4.0 + 0.5
			ci.draw_line(cc, cc + Vector2(cos(ang) * 8, sin(ang) * 6), seam, 1.6, true)
		ci.draw_circle(cc, 3.5, seam)
	if el == "terra":
		for q4 in [p.shL + Vector2(0, -6), p.head + Vector2(-3, -5), p.hipC + Vector2(4, 0)]:
			ci.draw_circle(q4, 2.2, Color(0.32, 0.5, 0.2))
	# cabeça pequena e afundada entre os ombros
	var hd: Vector2 = p.head + Vector2(0, 5)
	if el == "gelo":
		_crystal(ci, hd, 6.0, stone, 77)
	else:
		SpellArt.rock(ci, hd, 6.0, stone.lightened(0.1), 77)
	if p.toward:
		var eye := Color(1, 0.6, 0.15) if el != "gelo" else Color(0.6, 0.9, 1)
		if el == "terra":
			eye = Color(0.6, 1, 0.4)
		for s in [-1.0, 1.0]:
			var e2: Vector2 = hd + lat(p, s * 2.2) + fwd(p, 3) + Vector2(0, 0.5)
			ci.draw_circle(e2, 2.0, Color(eye, 0.35))
			ci.draw_circle(e2, 1.0, eye)


static func _crystal(ci: CanvasItem, c: Vector2, r: float, col: Color, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var pts := PackedVector2Array()
	for i in 6:
		var a := TAU * i / 6.0
		var rr := r * (1.3 if i % 2 == 0 else 0.75) * rng.randf_range(0.85, 1.1)
		pts.append(c + Vector2(cos(a) * rr * 0.8, sin(a) * rr))
	SpellArt.poly(ci, pts, col)
	ci.draw_line(c + Vector2(-r * 0.3, -r * 0.6), c + Vector2(r * 0.2, r * 0.3), Color(1, 1, 1, 0.7), 1.0, true)


# ------------------------------------------------------------ fogo: chamas flutuando
static func _flame(ci: CanvasItem, base: Vector2, h: float, w: float, t: float, sd: float) -> void:
	var sway := sin(t * 8.0 + sd) * w * 0.5
	SpellArt.poly(ci, PackedVector2Array([base + Vector2(-w, 0), base + Vector2(sway, -h), base + Vector2(w, 0)]), Color(1, 0.35, 0.05, 0.75))
	SpellArt.poly(ci, PackedVector2Array([base + Vector2(-w * 0.55, 0), base + Vector2(sway * 0.6, -h * 0.65), base + Vector2(w * 0.55, 0)]), Color(1, 0.75, 0.2, 0.9))


static func _fire(ci: CanvasItem, p: Dictionary) -> void:
	var t: float = p.t
	# cauda de fogo no lugar das pernas
	for i in 5:
		var k := i / 4.0
		var q: Vector2 = p.hipC.lerp(Vector2(sin(t * 3.0) * 4, -4), k)
		_flame(ci, q + Vector2(0, 8), 14 - i * 1.5, 7 - i, t, i)
	# tronco de chamas
	for i in 4:
		var q2: Vector2 = p.hipC.lerp(p.shC, i / 3.0)
		_flame(ci, q2 + Vector2(0, 6), 18, 9 - i * 0.6, t, i * 1.7)
	# braços: línguas de fogo nos ossos
	for b in arms(p):
		var a: Vector2 = b[0]
		var e: Vector2 = b[1]
		ci.draw_line(a, e, Color(1, 0.35, 0.05, 0.6), 6.0, true)
		ci.draw_line(a, e, Color(1, 0.8, 0.3, 0.95), 2.5, true)
		_flame(ci, e, 8, 3.5, t, e.x)
	# cabeça: chama com olhos brancos
	_flame(ci, p.head + Vector2(0, 5), 20, 6, t, 9.0)
	ci.draw_circle(p.head, 4.0, Color(1, 0.9, 0.5))
	if p.toward:
		for s in [-1.0, 1.0]:
			ci.draw_circle(p.head + lat(p, s * 2.0) + fwd(p, 2.5), 1.1, Color(1, 1, 1))


# ------------------------------------------------------------ vento: fitas e redemoinho
static func _wind(ci: CanvasItem, p: Dictionary) -> void:
	var t: float = p.t
	var col := Color(0.8, 1, 0.92, 0.55)
	# redemoinho no lugar das pernas
	for i in 6:
		var y: float = lerpf(p.hipC.y, -2.0, i / 5.0)
		var r := lerpf(10.0, 3.0, i / 5.0)
		ci.draw_arc(Vector2(sin(t * 4.0 + i) * 2, y), r, t * 10 + i, t * 10 + i + 4.0, 16, col, 2.0, true)
	# tronco: fitas girando
	for i in 5:
		var y2: float = lerpf(p.shC.y, p.hipC.y, i / 4.0)
		var r2 := lerpf(10.0, 7.0, i / 4.0)
		ci.draw_set_transform(Vector2(0, y2), 0.0, Vector2(1.0, 0.45))
		ci.draw_arc(Vector2.ZERO, r2, t * 7 + i, t * 7 + i + 4.5, 18, Color(0.9, 1, 0.95, 0.7), 2.2, true)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in arms(p):
		var a: Vector2 = b[0]
		var e: Vector2 = b[1]
		var pts := PackedVector2Array()
		for k in 7:
			var q: Vector2 = a.lerp(e, k / 6.0)
			pts.append(q + Vector2(sin(t * 9 + k) * 2.5, cos(t * 9 + k) * 1.5))
		ci.draw_polyline(pts, Color(0.9, 1, 0.95, 0.8), 2.5, true)
	ci.draw_circle(p.head, 6.0, Color(0.85, 1, 0.95, 0.35))
	ci.draw_arc(p.head, 5.0, t * 6, t * 6 + 4.0, 14, Color(1, 1, 1, 0.8), 1.5, true)
	if p.toward:
		for s in [-1.0, 1.0]:
			ci.draw_circle(p.head + lat(p, s * 2.0) + fwd(p, 2.5), 1.0, Color(1, 1, 1))


# ------------------------------------------------------------ raio: feito só de raios
static func _lightning(ci: CanvasItem, p: Dictionary) -> void:
	var col := Color(0.78, 0.8, 1, 0.95)
	for b in bones(p):
		SpellArt.jag(ci, b[0], b[1], col, 1.6, 4, 2.5)
	# tronco: vários raios entre ombros e quadris
	for i in 4:
		SpellArt.jag(ci, (p.shL as Vector2).lerp(p.shR, i / 3.0), (p.hipL as Vector2).lerp(p.hipR, i / 3.0), col, 1.4, 5, 3.0)
	SpellArt.jag(ci, p.shL, p.shR, col, 1.4, 4, 2.0)
	SpellArt.jag(ci, p.neck, p.head, col, 1.4, 3, 2.0)
	var cc: Vector2 = p.shC.lerp(p.hipC, 0.4)
	ci.draw_circle(cc, 6.0, Color(0.6, 0.6, 1, 0.3))
	ci.draw_circle(cc, 2.5, Color(1, 1, 1))
	# cabeça: bola de energia estalando
	ci.draw_circle(p.head, 6.0, Color(0.6, 0.6, 1, 0.35))
	for i in 4:
		var a := randf() * TAU
		SpellArt.jag(ci, p.head, p.head + Vector2(cos(a), sin(a)) * 7.0, col, 1.0, 3, 1.5)
	ci.draw_circle(p.head, 2.5, Color(1, 1, 1))


# ------------------------------------------------------------ água: corpo líquido
static func _water(ci: CanvasItem, p: Dictionary) -> void:
	var t: float = p.t
	var col := Color(0.25, 0.55, 0.95, 0.75)
	var hi := Color(0.75, 0.92, 1, 0.9)
	for b in bones(p):
		ci.draw_line(b[0], b[1], col, 6.0, true)
		ci.draw_line(b[0] + Vector2(-1, -1), b[1] + Vector2(-1, -1), hi, 1.2, true)
	# tronco: gota ondulando
	var pts := PackedVector2Array()
	var cc: Vector2 = p.shC.lerp(p.hipC, 0.5)
	for i in 20:
		var a := TAU * i / 20.0
		var rr := 10.0 + sin(a * 3 + t * 4.0) * 1.2
		pts.append(cc + Vector2(cos(a) * rr, sin(a) * rr * 1.45))
	SpellArt.poly(ci, pts, col)
	ci.draw_arc(cc + Vector2(-3, -6), 5, PI, PI * 1.6, 8, hi, 1.5, true)
	ci.draw_circle(p.head, 6.0, col)
	ci.draw_arc(p.head + Vector2(-1.5, -1.5), 3.5, PI, PI * 1.6, 8, hi, 1.2, true)
	# gotas caindo das mãos
	for q in [p.handL, p.handR]:
		var y := fmod(t * 40.0 + q.x, 16.0)
		ci.draw_circle(q + Vector2(0, y), 1.4, hi)
	if p.toward:
		for s in [-1.0, 1.0]:
			ci.draw_circle(p.head + lat(p, s * 2.0) + fwd(p, 2.5), 1.1, Color(0.9, 1, 1))


# ------------------------------------------------------------ natureza: raízes entrelaçadas
static func _strands(ci: CanvasItem, a: Vector2, b: Vector2, n: int, w: float, col: Color, t: float) -> void:
	var d := b - a
	var nrm := Vector2(-d.y, d.x).normalized()
	for s in n:
		var pts := PackedVector2Array()
		for k in 7:
			var f := k / 6.0
			pts.append(a + d * f + nrm * sin(f * 7.0 + s * 2.1) * w)
		ci.draw_polyline(pts, col.darkened(0.15 * s), 2.0, true)


static func _roots(ci: CanvasItem, p: Dictionary) -> void:
	var t: float = p.t
	var bark := Color(0.38, 0.27, 0.14)
	for b in bones(p):
		_strands(ci, b[0], b[1], 3, 2.2, bark, t)
	# tronco: raízes trançadas
	for i in 5:
		_strands(ci, (p.shL as Vector2).lerp(p.shR, i / 4.0), (p.hipL as Vector2).lerp(p.hipR, i / 4.0), 2, 1.5, bark, t)
	# folhas nos ombros e na cabeça
	for q in [p.shL, p.shR, p.head + Vector2(-4, -6), p.head + Vector2(4, -6), p.head + Vector2(0, -8)]:
		var a := sin(t * 2.0 + q.x) * 0.3
		ci.draw_set_transform(q, a, Vector2.ONE)
		SpellArt.poly(ci, PackedVector2Array([Vector2(0, 0), Vector2(3, -3), Vector2(0, -7), Vector2(-3, -3)]), Color(0.35, 0.65, 0.22))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_circle(p.head, 5.0, bark)
	_strands(ci, p.head + Vector2(-5, 0), p.head + Vector2(5, 0), 2, 2.0, bark.darkened(0.2), t)
	if p.toward:
		for s in [-1.0, 1.0]:
			var e: Vector2 = p.head + lat(p, s * 2.0) + fwd(p, 2.5)
			ci.draw_circle(e, 1.6, Color(0.6, 1, 0.4, 0.4))
			ci.draw_circle(e, 0.9, Color(0.7, 1, 0.5))


# ------------------------------------------------------------ fundida: detalhe do 2º elemento
static func _accent(ci: CanvasItem, p: Dictionary, el: String) -> void:
	var t: float = p.t
	match el:
		"fogo", "lava":
			for q in [p.shL, p.shR, p.head]:
				_flame(ci, q + Vector2(0, -2), 10, 3.5, t, q.x)
		"gelo":
			for q in [p.shL, p.shR, p.elbowL, p.elbowR]:
				_crystal(ci, q + Vector2(0, -4), 4.0, Color(0.8, 0.95, 1, 0.9), int(q.x * 10))
		"raio":
			for i in 2:
				var a := randf() * TAU
				var q: Vector2 = p.shC + Vector2(cos(a) * 14, sin(a) * 18)
				SpellArt.jag(ci, q, q + Vector2(randf_range(-8, 8), randf_range(-8, 8)), Color(0.85, 0.85, 1), 1.2, 3, 2.0)
		"natureza":
			_strands(ci, p.shL, p.handL, 1, 2.0, Color(0.3, 0.55, 0.2), t)
			_strands(ci, p.shR, p.handR, 1, 2.0, Color(0.3, 0.55, 0.2), t)
