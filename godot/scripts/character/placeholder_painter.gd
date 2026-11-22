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


## Duas juntas (cinemática inversa): de a até b com ossos l1 e l2; o joelho/cotovelo dobra para "bend".
static func ik(a: Vector2, b: Vector2, l1: float, l2: float, bend: Vector2) -> Vector2:
	var d := b - a
	var dist := clampf(d.length(), 0.001, l1 + l2 - 0.01)
	var dir := d.normalized() if d.length() > 0.001 else Vector2.DOWN
	var x := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, l1 * l1 - x * x))
	var perp := Vector2(-dir.y, dir.x)
	if perp.dot(bend) < 0.0:
		perp = -perp
	return a + dir * x + perp * h


## Pose do esqueleto para a direção/animação atual. ak = segundos desde o começo da ação
## (golpe, magia). Juntas: pescoço, ombros, cotovelos, mãos, quadris, joelhos, pés.
## Golpes: "punch" (soco), "kick" (chute), "spin" (chute giratório), "headbutt" (cabeçada), "grab" (agarrar e morder).
static func pose(dir: String, anim: String, phase: float, t: float, ak := 0.0) -> Dictionary:
	var p := {}
	var f := Iso.dir_vector(dir)
	# chute giratório: o corpo gira uma volta inteira
	var strike := clampf(ak / 0.45, 0.0, 1.0)
	if anim == "spin":
		f = f.rotated(strike * TAU)
	p.f = f
	p.r = Vector2(-f.y, f.x)
	p.toward = f.y > -0.25
	p.away = f.y < -0.3
	p.t = t
	p.anim = anim
	var moving := anim == "walk" or anim == "run"
	var running := anim == "run"
	var amp := 12.0 if running else (7.5 if moving else 0.0)
	var swing := sin(phase) * amp
	var bob := (absf(sin(phase)) * -2.2 if running else absf(sin(phase)) * -1.4) if moving else sin(t * 2.0) * 0.6
	var lean := 4.0 if running else (1.5 if moving else 0.0)
	# golpe: prepara (0-0.3), acerta (0.3-0.6), volta
	var ext := 0.0
	if anim in ["punch", "kick", "spin", "headbutt", "grab", "attack"]:
		ext = sin(clampf((strike - 0.15) / 0.55, 0.0, 1.0) * PI)
		lean += ext * 4.0
	var w := 9.0
	p.bob = bob
	p.ext = ext
	var hip := Vector2(0, -36 + bob)
	var sh := Vector2(0, -60 + bob) + fwd(p, lean)
	p.hipL = hip + lat(p, -w * 0.45)
	p.hipR = hip + lat(p, w * 0.45)
	var liftL := maxf(0.0, sin(phase)) * (6.0 if running else 3.5) if moving else 0.0
	var liftR := maxf(0.0, -sin(phase)) * (6.0 if running else 3.5) if moving else 0.0
	p.footL = lat(p, -w * 0.42) + fwd(p, swing) + Vector2(0, -liftL)
	p.footR = lat(p, w * 0.42) + fwd(p, -swing) + Vector2(0, -liftR)
	p.shL = sh + lat(p, -w)
	p.shR = sh + lat(p, w)
	p.handL = p.shL + Vector2(0, 22) + fwd(p, -swing * 0.8)
	p.handR = p.shR + Vector2(0, 22) + fwd(p, swing * 0.8)
	p.head = Vector2(0, -69 + bob) + fwd(p, lean * 1.2)
	p.casting = anim in ["cast", "spell", "attack"]
	match anim:
		"cast", "spell", "attack":
			# ergue o cajado e empurra para a frente ao soltar a magia
			p.handR = p.shR + Vector2(0, -10 - ext * 4) + fwd(p, 8 + ext * 8)
			p.handL = p.shL + Vector2(0, 8) + fwd(p, 9 + ext * 4)
		"punch":
			p.handR = p.shR.lerp(p.shR + fwd(p, 24) + Vector2(0, 2), ext) + Vector2(0, 14 * (1.0 - ext))
			p.handL = p.shL + Vector2(0, 6) + fwd(p, 8)
		"kick", "spin":
			p.footR = p.hipR.lerp(p.hipR + fwd(p, 28) + Vector2(0, 6), ext) + Vector2(0, 36 * (1.0 - ext))
			p.footL = p.footL + fwd(p, -ext * 4)
			p.handL = p.shL + Vector2(0, 10) + lat(p, -6 * ext)
			p.handR = p.shR + Vector2(0, 10) + lat(p, 6 * ext)
		"headbutt":
			p.head = p.head + fwd(p, 9 * ext) + Vector2(0, 3 * ext)
			p.handL = p.shL + Vector2(0, 14) + fwd(p, 6)
			p.handR = p.shR + Vector2(0, 14) + fwd(p, 6)
		"grab":
			p.handL = p.shL + Vector2(0, 6) + fwd(p, 10 + 12 * ext)
			p.handR = p.shR + Vector2(0, 6) + fwd(p, 10 + 12 * ext)
			p.head = p.head + fwd(p, 6 * ext)
	# joelhos dobram para a frente; cotovelos para trás e para baixo
	p.kneeL = ik(p.hipL, p.footL, 19.0, 18.5, fwd(p, 1.0) + Vector2(0, -0.2))
	p.kneeR = ik(p.hipR, p.footR, 19.0, 18.5, fwd(p, 1.0) + Vector2(0, -0.2))
	p.elbowL = ik(p.shL, p.handL, 12.5, 12.0, fwd(p, -1.0) + Vector2(0, 0.6) + lat(p, -0.6))
	p.elbowR = ik(p.shR, p.handR, 12.5, 12.0, fwd(p, -1.0) + Vector2(0, 0.6) + lat(p, 0.6))
	p.neck = Vector2(0, -63 + bob) + fwd(p, lean)
	p.shC = (p.shL + p.shR) * 0.5
	p.hipC = (p.hipL + p.hipR) * 0.5
	p.kneeC = (p.kneeL + p.kneeR) * 0.5 + Vector2(0, 2)
	# capa: atrás quando anda, balança com o vento, cai com a gravidade parada
	var wind := sin(t * 1.3) * 1.5 + sin(t * 3.7) * 0.8
	var trail := (5.0 if moving else 0.0) + (5.0 if running else 0.0) + absf(sin(phase)) * (2.0 if moving else 0.0)
	p.cape = -fwd(p, 5.0 + trail) + lat(p, wind) + Vector2(0, -trail * 0.6)
	p.w = w
	return p


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	ElemArt.circle(ci, Vector2.ZERO, rx, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func eyes(ci: CanvasItem, p: Dictionary, col: Color, bright := true) -> void:
	if not p.toward:
		return
	var base: Vector2 = p.head + fwd(p, 3.2) + Vector2(0, 0.6)
	for s in [-1.0, 1.0]:
		var e: Vector2 = base + lat(p, s * 1.9)
		if bright:
			ElemArt.circle(ci, e, 1.8, Color(col, 0.35))
		ElemArt.circle(ci, e, 0.9, col)


static func draw_body(ci: CanvasItem, p: Dictionary, c: Dictionary) -> void:
	ellipse(ci, Vector2.ZERO, 15, 6.5, Color(0, 0, 0, 0.45))
	bulk = float(c.get("bulk", 1.0))
	var skin: Color = c.get("skin", Color(0.55, 0.42, 0.34))
	var under: Color = c.get("under", Color(0.2, 0.18, 0.16))
	var hair: Color = c.get("hair", Color(0.08, 0.06, 0.05))
	if c.has("summon"):
		SummonPainter.draw(ci, p, c)
		return
	var r: Vector2 = p.r
	var near_right := r.y > 0.2
	var near_left := r.y < -0.2
	# a perna de trás primeiro
	if near_right:
		leg(ci, p.hipL, p.kneeL, p.footL, under.darkened(0.3), p)
		leg(ci, p.hipR, p.kneeR, p.footR, under.darkened(0.15), p)
	else:
		leg(ci, p.hipR, p.kneeR, p.footR, under.darkened(0.3), p)
		leg(ci, p.hipL, p.kneeL, p.footL, under.darkened(0.15), p)
	if near_right:
		limb(ci, p.shL, p.elbowL, p.handL, 4.8, 4.0, under.darkened(0.35))
	if near_left:
		limb(ci, p.shR, p.elbowR, p.handR, 4.8, 4.0, under.darkened(0.35))
	var torso := vol(p, p.shC, p.w * bulk, 5.5 * bulk, p.hipC, p.w * 0.55 * maxf(1.0, bulk), 4.5 * bulk)
	SpellArt.spoly(ci, torso, under, 0.4)
	outline(ci, torso, under.darkened(0.5))
	if not near_right:
		limb(ci, p.shL, p.elbowL, p.handL, 4.8, 4.0, under.darkened(0.1))
	if not near_left:
		limb(ci, p.shR, p.elbowR, p.handR, 4.8, 4.0, under.darkened(0.1))
	ElemArt.circle(ci, p.handL, 2.3, skin)
	ElemArt.circle(ci, p.handR, 2.3, skin)
	ci.draw_line(p.neck, p.head + Vector2(0, 4), skin.darkened(0.2), 3.5, SpellArt.AA)
	# cabeça acompanha o corpanzil (sem isso trolls e ciclopes ficavam com cabeça de alfinete)
	var hs := 1.0 + (bulk - 1.0) * 0.55
	ElemArt.circle(ci, p.head, 5.6 * hs, hair)
	if not p.away:
		ElemArt.circle(ci, p.head + fwd(p, 1.8 * hs) + Vector2(0, 1.0), 4.6 * hs, skin)
	if c.get("core", false) and p.toward:
		var cc: Vector2 = Vector2(0, -51 + p.bob) + fwd(p, 3)
		var ccol: Color = c.get("core_col", Color(1, 0.45, 0.08))
		ElemArt.circle(ci, cc, 7.0, Color(ccol, 0.25))
		ElemArt.circle(ci, cc, 4.2, ccol)
		ElemArt.circle(ci, cc, 2.0, ccol.lightened(0.6))
		for k in 5:
			var a := TAU * k / 5.0 + 0.4
			ci.draw_line(cc + Vector2(cos(a), sin(a) * 0.6) * 4.0, cc + Vector2(cos(a), sin(a) * 0.6) * 9.5, Color(ccol.darkened(0.1), 0.8), 1.0)
	# traços de monstro: orelhas pontudas (goblin/orc), presas (orc/troll), olho único (ciclope)
	if c.get("orelhas", false):
		for s in [-1.0, 1.0]:
			var ear: Vector2 = p.head + lat(p, s * 5.0) + Vector2(0, -1)
			ci.draw_colored_polygon(PackedVector2Array([ear + Vector2(0, -2), ear + Vector2(0, 2), ear + lat(p, s * 6.0) + Vector2(0, -5)]), skin.darkened(0.1))
	if c.get("olho_unico", false):
		if p.toward:
			var e1: Vector2 = p.head + fwd(p, 3.4) + Vector2(0, -0.4)
			ElemArt.circle(ci, e1, 2.8, Color(0.95, 0.92, 0.85))
			ElemArt.circle(ci, e1, 1.5, c.get("eyes", Color(0.8, 0.2, 0.1)))
			ElemArt.circle(ci, e1, 0.6, Color.BLACK)
	else:
		eyes(ci, p, c.get("eyes", Color(1, 0.62, 0.15)), c.get("glow_eyes", false))
	if c.get("presas", false) and p.toward:
		var m0: Vector2 = p.head + fwd(p, 3.6) + Vector2(0, 3.2)
		for s in [-1.0, 1.0]:
			var t0: Vector2 = m0 + lat(p, s * 1.8)
			ci.draw_colored_polygon(PackedVector2Array([t0 + Vector2(-0.8, 0), t0 + Vector2(0.8, 0), t0 + Vector2(0, -3)]), Color(0.92, 0.88, 0.75))


## Membro com duas partes (braço: ombro-cotovelo-mão / perna: quadril-joelho-pé), com volume:
## músculo mais grosso perto da junta de cima, afinando na ponta, contorno escuro e realce no
## lado da luz (alto à esquerda). Visual Factory: nada de membros-palito.
static var bulk := 1.0


static func _seg(a: Vector2, b: Vector2, wa: float, wm: float, wb: float, grow := 0.0) -> PackedVector2Array:
	var d := b - a
	if d.length() < 0.5:
		d = Vector2(0, 1)
	var n := Vector2(-d.y, d.x).normalized()
	var m := a.lerp(b, 0.38)
	var pts := PackedVector2Array([(a + b + m) / 3.0])
	for q in [a + n * (wa + grow), m + n * (wm + grow), b + n * (wb + grow), b + d.normalized() * grow, b - n * (wb + grow), m - n * (wm + grow), a - n * (wa + grow), a - d.normalized() * grow]:
		pts.append(q)
	pts.append(pts[1])
	return pts


static func limb(ci: CanvasItem, a: Vector2, j: Vector2, b: Vector2, w1: float, w2: float, col: Color) -> void:
	var k := 0.72 * bulk
	var up_w := [w1 * k, w1 * k * 1.15, w1 * k * 0.78]
	var lo_w := [w2 * k * 0.85, w2 * k * 0.95, w2 * k * 0.6]
	var dark := col.darkened(0.55)
	# contorno
	ElemArt.fan(ci, _seg(a, j, up_w[0], up_w[1], up_w[2], 0.9), dark)
	ElemArt.fan(ci, _seg(j, b, lo_w[0], lo_w[1], lo_w[2], 0.9), dark)
	# volume
	ElemArt.fan(ci, _seg(a, j, up_w[0], up_w[1], up_w[2]), col)
	ElemArt.fan(ci, _seg(j, b, lo_w[0], lo_w[1], lo_w[2]), col.lightened(0.03))
	ElemArt.circle(ci, j, float(up_w[2]) * 1.02, col)
	# sombra do lado de baixo/direita e realce do lado da luz
	var hl := Vector2(-0.55, -0.65)
	ElemArt.fan(ci, _seg(a + hl * up_w[1] * 0.45, j + hl * up_w[2] * 0.45, up_w[0] * 0.35, up_w[1] * 0.4, up_w[2] * 0.3), Color(col.lightened(0.3), 0.5))
	ElemArt.fan(ci, _seg(j + hl * lo_w[1] * 0.45, b + hl * lo_w[2] * 0.45, lo_w[0] * 0.3, lo_w[1] * 0.35, lo_w[2] * 0.25), Color(col.lightened(0.25), 0.45))
	ElemArt.fan(ci, _seg(a - hl * up_w[1] * 0.5, j - hl * up_w[2] * 0.5, up_w[0] * 0.3, up_w[1] * 0.35, up_w[2] * 0.25), Color(col.darkened(0.3), 0.45))


## Perna (quadril-joelho-pé) com o pé apontando para a frente.
static func leg(ci: CanvasItem, a: Vector2, j: Vector2, b: Vector2, col: Color, p: Dictionary) -> void:
	limb(ci, a, j, b + Vector2(0, -1.5), 6.5, 5.2, col)
	ci.draw_line(b + Vector2(0, -1.5), b + fwd(p, 4.0) + Vector2(0, -0.5), col.darkened(0.25), 3.6, SpellArt.AA)


static func outline(ci: CanvasItem, poly: PackedVector2Array, col: Color) -> void:
	if poly.size() > 2:
		var o := poly.duplicate()
		o.append(poly[0])
		ElemArt.polyline(ci, o, Color(col, 0.6), 1.0, SpellArt.AA)


static func draw_item(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var col := it.placeholder_color
	var acc := it.placeholder_accent
	match String(it.placeholder_style):
		"hood":
			ElemArt.circle(ci, p.head + Vector2(0, -0.8), 7.2, col)
			SpellArt.poly(ci, PackedVector2Array([p.head + lat(p, -5) + Vector2(0, -4), p.head + lat(p, 5) + Vector2(0, -4), p.head - fwd(p, 7) + Vector2(0, -9)]), col.darkened(0.15))
			SpellArt.poly(ci, PackedVector2Array([p.shL + Vector2(0, -2), p.shR + Vector2(0, -2), p.head + Vector2(0, 5)]), col)
			if p.toward:
				ElemArt.circle(ci, p.head + fwd(p, 2.4) + Vector2(0, 1.0), 4.3, Color(0.03, 0.02, 0.02))
				eyes(ci, p, acc, true)
		"helm":
			ElemArt.circle(ci, p.head + Vector2(0, -0.5), 6.6, col)
			ci.draw_line(p.head + Vector2(0, -7), p.head + Vector2(0, 5) + fwd(p, 3), col.lightened(0.25), 1.2)
			if p.toward:
				ci.draw_line(p.head + fwd(p, 4) + lat(p, -3.5), p.head + fwd(p, 4) + lat(p, 3.5), Color(0.02, 0.02, 0.02), 2.0)
				eyes(ci, p, acc, true)
		"robe":
			var kL: Vector2 = Vector2(0, -6 + p.bob) + lat(p, -p.w * 1.15)
			var kR: Vector2 = Vector2(0, -6 + p.bob) + lat(p, p.w * 1.15)
			SpellArt.spoly(ci, vol(p, p.shC + Vector2(0, -1), p.w, 6.0, p.kneeC + Vector2(0, 4), p.w * 1.15, 7.5), col)
			ci.draw_line(p.hipL + Vector2(0, -2), p.hipR + Vector2(0, -2), acc, 2.0)
			ci.draw_line((p.shL + p.shR) * 0.5, (kL + kR) * 0.5, acc.darkened(0.3), 1.0)
			limb(ci, p.shL, p.elbowL, p.handL.lerp(p.elbowL, 0.15), 5.6, 5.0, col)
			limb(ci, p.shR, p.elbowR, p.handR.lerp(p.elbowR, 0.15), 5.6, 5.0, col)
		"vest":
			SpellArt.spoly(ci, vol(p, p.shC + Vector2(0, -1), p.w, 6.0, p.hipC + Vector2(0, 4), p.w * 0.6, 5.0), col)
			ci.draw_line(p.hipL + Vector2(0, 1), p.hipR + Vector2(0, 1), acc, 2.0)
		"apron":
			SpellArt.spoly(ci, vol(p, p.shC, p.w, 6.0, p.hipC + Vector2(0, 2), p.w * 0.6, 5.0), acc)
			if p.toward:
				var a: Vector2 = (p.hipL + p.hipR) * 0.5 + fwd(p, 2)
				SpellArt.poly(ci, PackedVector2Array([a + lat(p, -6) + Vector2(0, -12), a + lat(p, 6) + Vector2(0, -12), a + lat(p, 7) + Vector2(0, 20), a + lat(p, -7) + Vector2(0, 20)]), col)
		"pauldron":
			for s in [p.shL, p.shR]:
				ellipse(ci, s + Vector2(0, -1), 5.0, 3.6, col)
				ElemArt.arc(ci, s + Vector2(0, -1), 4.6, PI, TAU, 8, acc, 1.0)
		"gloves":
			ElemArt.circle(ci, p.handL, 2.8, col)
			ElemArt.circle(ci, p.handR, 2.8, col)
		"pants":
			limb(ci, p.hipL, p.kneeL, p.footL + Vector2(0, -3), 6.6, 5.6, col)
			limb(ci, p.hipR, p.kneeR, p.footR + Vector2(0, -3), 6.6, 5.6, col)
		"boots":
			ellipse(ci, p.footL + Vector2(0, -1.5), 3.6, 2.4, col)
			ellipse(ci, p.footR + Vector2(0, -1.5), 3.6, 2.4, col)
			ci.draw_line(p.footL + Vector2(0, -2), p.footL.lerp(p.kneeL, 0.4), col, 5.6, SpellArt.AA)
			ci.draw_line(p.footR + Vector2(0, -2), p.footR.lerp(p.kneeR, 0.4), col, 5.6, SpellArt.AA)
		"cape":
			var bot: Vector2 = Vector2(0, -3) + p.cape
			draw_cloth(ci, p, p.shC + Vector2(0, 1) - fwd(p, 3), bot - fwd(p, 6), p.w, p.w * 1.35, col)
			ci.draw_line(p.shL + Vector2(0, 1), p.shR + Vector2(0, 1), acc, 2.0)
		"staff":
			var top := staff_top(p)
			var base: Vector2 = p.handR + Vector2(0, 26) + fwd(p, 2)
			ci.draw_line(base, top, col, 3.0)
			ci.draw_line(base, top, col.lightened(0.2), 1.0)
			ElemArt.circle(ci, top, 7.0, Color(acc, 0.18))
			ElemArt.circle(ci, top, 4.2, acc)
			ElemArt.circle(ci, top, 2.0, Color(1, 0.95, 0.75))
		"mimic":
			draw_mimic(ci, p, it)
		"book":
			draw_book(ci, p, it)
		"wizardhat":
			# aba larga e ponta caída para trás
			ellipse(ci, p.head + Vector2(0, -4), 11.0, 4.0, col.darkened(0.2))
			var tip: Vector2 = p.head + Vector2(0, -26) - fwd(p, 6) + lat(p, 3)
			SpellArt.poly(ci, PackedVector2Array([p.head + lat(p, -6.5) + Vector2(0, -5), p.head + lat(p, 6.5) + Vector2(0, -5), tip]), col)
			ci.draw_line(p.head + lat(p, -6) + Vector2(0, -6), p.head + lat(p, 6) + Vector2(0, -6), acc, 2.0, SpellArt.AA)
			ElemArt.circle(ci, tip, 1.5, acc)
			if p.toward:
				ElemArt.circle(ci, p.head + fwd(p, 2.4) + Vector2(0, 1.0), 4.3, Color(0.03, 0.02, 0.02, 0.5))
				eyes(ci, p, Color(1, 0.75, 0.3), false)
		"turban":
			for i in 3:
				ellipse(ci, p.head + Vector2(0, -3 - i * 2.2), 7.0 - i * 0.8, 3.0, col.lightened(0.08 * (i % 2)))
			if p.toward:
				ElemArt.circle(ci, p.head + fwd(p, 5) + Vector2(0, -5), 1.8, acc)
		"circlet":
			ellipse(ci, p.head + Vector2(0, -3), 6.2, 2.4, Color(0, 0, 0, 0))
			ElemArt.arc(ci, p.head + Vector2(0, -3), 6.0, PI * 0.05, PI * 0.95, 12, col, 1.6, SpellArt.AA)
			if p.toward:
				ElemArt.circle(ci, p.head + fwd(p, 5) + Vector2(0, -4), 1.7, acc)
		"kilt":
			SpellArt.spoly(ci, vol(p, p.hipC + Vector2(0, -3), p.w * 0.6, 5.0, p.kneeC + Vector2(0, -2), p.w * 1.05, 7.0), col)
			for i in 5:
				var tk := (i + 0.5) / 5.0
				ci.draw_line((p.hipL as Vector2).lerp(p.hipR, tk), ((p.kneeL as Vector2) + lat(p, -3)).lerp((p.kneeR as Vector2) + lat(p, 3), tk), col.darkened(0.3), 1.0, SpellArt.AA)
		"sandals":
			for q in [p.footL, p.footR]:
				ellipse(ci, q + Vector2(0, -1), 3.6, 1.8, col)
				ci.draw_line(q + Vector2(-2, -2), q + Vector2(2, -4), acc, 1.0, SpellArt.AA)
		"wand":
			var hb: Vector2 = p.handR
			var wt: Vector2 = hb + Vector2(0, -14) + fwd(p, 5)
			ci.draw_line(hb + Vector2(0, 3), wt, col, 2.4, SpellArt.AA)
			ci.draw_line(hb + Vector2(0, 3), wt, col.lightened(0.25), 0.8, SpellArt.AA)
			ElemArt.circle(ci, wt, 3.6, Color(acc, 0.25))
			SpellArt.poly(ci, PackedVector2Array([wt + Vector2(0, -4), wt + Vector2(2.2, 0), wt + Vector2(0, 2.5), wt + Vector2(-2.2, 0)]), acc)
		"rod":
			var top2 := staff_top(p)
			var base2: Vector2 = p.handR + Vector2(0, 24) + fwd(p, 2)
			ci.draw_line(base2, top2, col, 3.2, SpellArt.AA)
			ci.draw_line(base2, top2, col.lightened(0.3), 1.0, SpellArt.AA)
			for s2 in [-1.0, 1.0]:
				ci.draw_line(top2 + Vector2(0, 6), top2 + lat(p, s2 * 5) + Vector2(0, -2), col, 1.6, SpellArt.AA)
			ElemArt.circle(ci, top2, 7.5, Color(acc, 0.22))
			SpellArt.poly(ci, PackedVector2Array([top2 + Vector2(0, -6), top2 + Vector2(3.5, 0), top2 + Vector2(0, 5), top2 + Vector2(-3.5, 0)]), acc)
			ElemArt.circle(ci, top2 + Vector2(-1, -1.5), 1.2, Color(1, 1, 1, 0.9))
		"ring":
			ElemArt.circle(ci, p.handR, 3.2, Color(acc, 0.35))
			ElemArt.arc(ci, p.handR, 2.0, 0, TAU, 10, col, 1.2, SpellArt.AA)
			ElemArt.circle(ci, p.handR + Vector2(0, -1.5), 1.0, acc)
		"wolfcape":
			draw_wolfcape_back(ci, p, it)
		"wolfskirt":
			draw_wolfskirt(ci, p, it)
		"amulet":
			if not p.away:
				var c := amulet_pos(p)
				ci.draw_line(p.shL + Vector2(0, 2), c, Color(0.5, 0.45, 0.35), 0.8)
				ci.draw_line(p.shR + Vector2(0, 2), c, Color(0.5, 0.45, 0.35), 0.8)
				ElemArt.circle(ci, c, 3.0, Color(acc, 0.3))
				ElemArt.circle(ci, c, 1.8, acc)


## Pano da capa: alarga para baixo, ondula com o vento (dobras) e segue p.cape (física).
static func draw_cloth(ci: CanvasItem, p: Dictionary, top: Vector2, bot: Vector2, w_top: float, w_bot: float, col: Color) -> void:
	var t: float = p.t
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := 6
	for i in n + 1:
		var k := float(i) / n
		var c := top.lerp(bot, k) + Vector2(0, k * k * 2.0)
		var wv := sin(t * 3.0 + k * 4.0) * 1.6 * k
		var ww := lerpf(w_top, w_bot, k)
		left.append(c + lat(p, -ww) + fwd(p, wv))
		right.append(c + lat(p, ww) + fwd(p, -wv))
	right.reverse()
	var poly := left + right
	SpellArt.spoly(ci, poly, col, 0.4)
	outline(ci, poly, col.darkened(0.5))
	for i in 4:
		var k2 := (i + 1) / 5.0
		ci.draw_line(top.lerp(top + lat(p, (k2 - 0.5) * w_top * 2), 1.0), bot + lat(p, (k2 - 0.5) * w_bot * 2) + Vector2(0, sin(t * 3.0 + i) * 1.2), Color(col.darkened(0.35), 0.7), 1.0, SpellArt.AA)


static func staff_top(p: Dictionary) -> Vector2:
	return p.handR + Vector2(0, -52) + fwd(p, 4)


static func amulet_pos(p: Dictionary) -> Vector2:
	return Vector2(0, -52 + p.bob) + fwd(p, 3)


static func shield_center(p: Dictionary) -> Vector2:
	var arm: Vector2 = (p.elbowL as Vector2).lerp(p.handL, 0.55)
	return arm + lat(p, -2.5) + fwd(p, 6) + Vector2(0, 4)


static func draw_mimic(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var c := shield_center(p)
	var f: Vector2 = p.f
	var face := absf(f.y) * 0.75 + 0.25
	var hw := 12.0 * face
	var hh := 27.0
	var rect := PackedVector2Array([c + Vector2(-hw, -hh + 3), c + Vector2(0, -hh), c + Vector2(hw, -hh + 3), c + Vector2(hw, hh - 2), c + Vector2(0, hh), c + Vector2(-hw, hh - 2)])
	SpellArt.poly(ci, rect, it.placeholder_color.darkened(0.1))
	var rim := rect.duplicate()
	rim.append(rect[0])
	ElemArt.polyline(ci, rim, Color(0.42, 0.36, 0.28), 2.0)
	if p.toward and face > 0.55:
		var acc := it.placeholder_accent
		for e in [Vector2(-0.45, -15), Vector2(0.45, -15), Vector2(-0.6, -6), Vector2(0.6, -6)]:
			var ep: Vector2 = c + Vector2(e.x * hw, e.y)
			ElemArt.circle(ci, ep, 2.6, Color(acc, 0.3))
			ElemArt.circle(ci, ep, 1.3, acc)
		SpellArt.poly(ci, PackedVector2Array([c + Vector2(-hw * 0.75, 0), c + Vector2(hw * 0.75, 0), c + Vector2(hw * 0.5, 16), c + Vector2(-hw * 0.5, 16)]), Color(0.1, 0.02, 0.02))
		SpellArt.poly(ci, PackedVector2Array([c + Vector2(-3, 6), c + Vector2(3, 6), c + Vector2(2, 15), c + Vector2(-2, 15)]), Color(0.55, 0.22, 0.2))
		for i in 6:
			var x := lerpf(-hw * 0.65, hw * 0.65, i / 5.0)
			SpellArt.poly(ci, PackedVector2Array([c + Vector2(x - 1.6, 0), c + Vector2(x + 1.6, 0), c + Vector2(x, 5)]), Color(0.88, 0.82, 0.68))
			SpellArt.poly(ci, PackedVector2Array([c + Vector2(x * 0.8 - 1.4, 16), c + Vector2(x * 0.8 + 1.4, 16), c + Vector2(x * 0.8, 11)]), Color(0.88, 0.82, 0.68))
		for r in [Vector2(0, -21), Vector2(0, 21)]:
			ElemArt.circle(ci, c + r, 2.2, Color(0.5, 0.42, 0.3))
	else:
		for k in [-0.5, 0.0, 0.5]:
			ci.draw_line(c + Vector2(k * hw, -hh + 4), c + Vector2(k * hw, hh - 4), Color(0.18, 0.1, 0.06), 1.0)


## Livro de feitiços na mão esquerda (fica onde fica o escudo): capa, cantoneiras e runa brilhando.
static func draw_book(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var c := shield_center(p) + Vector2(0, -6)
	var f: Vector2 = p.f
	var face := absf(f.y) * 0.7 + 0.3
	var hw := 8.0 * face
	var hh := 11.0
	var col := it.placeholder_color
	var acc := it.placeholder_accent
	SpellArt.poly(ci, PackedVector2Array([c + Vector2(-hw, -hh), c + Vector2(hw, -hh + 1), c + Vector2(hw, hh), c + Vector2(-hw, hh - 1)]), col)
	ci.draw_line(c + Vector2(-hw, -hh), c + Vector2(-hw, hh - 1), col.darkened(0.4), 2.0, SpellArt.AA)
	if p.toward and face > 0.5:
		# aberto: páginas e runa
		SpellArt.poly(ci, PackedVector2Array([c + Vector2(-hw + 1.5, -hh + 2), c + Vector2(hw - 1.5, -hh + 3), c + Vector2(hw - 1.5, hh - 2), c + Vector2(-hw + 1.5, hh - 3)]), Color(0.86, 0.8, 0.66))
		ci.draw_line(c + Vector2(0, -hh + 2), c + Vector2(0, hh - 2), Color(0.5, 0.42, 0.3), 1.0)
		ElemArt.arc(ci, c + Vector2(hw * 0.45, 0), 2.6, 0, TAU, 10, acc, 1.2, SpellArt.AA)
		ElemArt.circle(ci, c + Vector2(hw * 0.45, 0), 4.5, Color(acc, 0.2))
	for q in [Vector2(-hw, -hh), Vector2(hw, -hh + 1), Vector2(hw, hh), Vector2(-hw, hh - 1)]:
		ElemArt.circle(ci, c + q, 1.2, acc.lerp(Color(0.8, 0.7, 0.4), 0.6))


static func fur_edge(ci: CanvasItem, a: Vector2, b: Vector2, depth: float, col: Color, n: int, sd: float) -> void:
	for i in n:
		var t := (i + 0.5) / n
		var base := a.lerp(b, t)
		var ln := depth * (0.6 + 0.4 * absf(sin(sd + i * 2.3)))
		ci.draw_line(base, base + Vector2(sin(sd + i) * 1.5, ln), col, 1.6)


static func draw_wolfcape_back(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var col := it.placeholder_color
	var bot: Vector2 = Vector2(0, -2) + p.cape
	var w: float = p.w
	var bl: Vector2 = bot + lat(p, -w * 1.9) - fwd(p, 6)
	var br: Vector2 = bot + lat(p, w * 1.9) - fwd(p, 6)
	draw_cloth(ci, p, p.shC + Vector2(0, -3) - fwd(p, 3), bot - fwd(p, 8), w, w * 1.9, col)
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
	SpellArt.spoly(ci, vol(p, p.shC + Vector2(0, -3), w + 3.5, 7.0, p.shC + Vector2(0, 9), w + 1.0, 6.5), col)
	if p.toward:
		fur_edge(ci, p.shL + Vector2(0, 8), (p.shL + p.shR) * 0.5 + Vector2(0, 6), 7.0, col.lightened(0.05), 5, 2.0)
		fur_edge(ci, (p.shL + p.shR) * 0.5 + Vector2(0, 6), p.shR + Vector2(0, 8), 7.0, col.lightened(0.05), 5, 4.0)
		for s in [p.shL, p.shR]:
			ElemArt.circle(ci, s + Vector2(0, 2), 2.4, Color(0.55, 0.45, 0.32))
	# capuz com cabeça de lobo
	ElemArt.circle(ci, h + Vector2(0, -1), 7.6, col)
	var snout_base: Vector2 = h + Vector2(0, -5) + fwd(p, 3)
	SpellArt.poly(ci, PackedVector2Array([snout_base + lat(p, -3.5), snout_base + lat(p, 3.5), snout_base + fwd(p, 9) + Vector2(0, 1.5)]), col.darkened(0.2))
	for s in [-1.0, 1.0]:
		var e: Vector2 = h + lat(p, s * 4.2) + Vector2(0, -6) - fwd(p, 1)
		SpellArt.poly(ci, PackedVector2Array([e + lat(p, -2.0), e + lat(p, 2.0), e + Vector2(0, -7)]), col.darkened(0.1))
		ci.draw_line(e, e + Vector2(0, -6), Color(0.6, 0.08, 0.04), 1.0)
		if p.toward:
			var we: Vector2 = h + lat(p, s * 2.6) + Vector2(0, -6) + fwd(p, 4)
			ElemArt.circle(ci, we, 1.0, acc)
	if p.toward:
		ElemArt.circle(ci, h + fwd(p, 2.6) + Vector2(0, 1.4), 4.0, Color(0.02, 0.015, 0.015))
		eyes(ci, p, Color(1, 0.62, 0.15), true)


static func draw_wolfskirt(ci: CanvasItem, p: Dictionary, it: EquipmentItem) -> void:
	var col := it.placeholder_color
	var w: float = p.w
	limb(ci, p.hipL, p.kneeL, p.footL + Vector2(0, -3), 6.4, 5.4, Color(0.08, 0.07, 0.075))
	limb(ci, p.hipR, p.kneeR, p.footR + Vector2(0, -3), 6.4, 5.4, Color(0.08, 0.07, 0.075))
	var kl: Vector2 = Vector2(0, -12 + p.bob) + lat(p, -w * 1.2)
	var kr: Vector2 = Vector2(0, -12 + p.bob) + lat(p, w * 1.2)
	SpellArt.spoly(ci, vol(p, p.hipC + Vector2(0, -4), w * 0.65, 5.5, p.kneeC, w * 1.2, 8.5), col)
	ci.draw_line(p.hipL + Vector2(0, -3), p.hipR + Vector2(0, -3), Color(0.35, 0.28, 0.2), 2.0)
	fur_edge(ci, kl, kr, 7.0, col, 9, 3.0)
	for i in 6:
		var t := (i + 0.5) / 6.0
		ci.draw_line(p.hipL.lerp(p.hipR, t), kl.lerp(kr, t), Color(0.55, 0.07, 0.04, 0.5), 1.0)


## Ponto onde o item emite luz (cajado, amuleto, olhos do escudo).
static func glow_point(it: EquipmentItem, p: Dictionary) -> Vector2:
	match String(it.placeholder_style):
		"staff", "rod":
			return staff_top(p)
		"wand":
			return p.handR + Vector2(0, -14) + fwd(p, 5)
		"book":
			return shield_center(p) + Vector2(0, -6)
		"amulet":
			return amulet_pos(p)
		"mimic":
			return shield_center(p)
	return Vector2(0, -40)
