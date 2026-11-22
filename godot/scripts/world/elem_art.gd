class_name ElemArt
## Peças de desenho dos elementos, feitas para parecer o elemento de verdade:
## formas variadas, cada pedaço com seu tamanho, ritmo e movimento. Tudo em triângulos
## (RenderingServer), para não falhar nem pesar. Usado pelas magias dos jogadores e dos monstros.


## Desenha triângulos indexados como "primitivas" (3 ou 4 pontos) em vez de um triangle array.
## No celular (Android/GLES3) cada triangle array cria e apaga um buffer de vídeo; com dezenas
## por personagem a cada quadro, o driver de vídeo de alguns aparelhos acabava fechando o jogo.
## Primitivas vão no lote comum do Godot, sem buffer novo. Dois triângulos seguidos que formam
## um quadrilátero (leque ou faixa) viram uma primitiva só.
static func emit(n: CanvasItem, idx: PackedInt32Array, pts: PackedVector2Array, cs: PackedColorArray) -> void:
	var ci := n.get_canvas_item()
	var nt := idx.size() / 3
	var np := pts.size()
	var k := 0
	while k < nt:
		var a := idx[k * 3]
		var b := idx[k * 3 + 1]
		var c := idx[k * 3 + 2]
		if a >= np or b >= np or c >= np:
			k += 1
			continue
		if k + 1 < nt and idx[k * 3 + 3] == a and idx[k * 3 + 4] == c and idx[k * 3 + 5] < np:
			var d := idx[k * 3 + 5]
			RenderingServer.canvas_item_add_primitive(ci, PackedVector2Array([pts[a], pts[b], pts[c], pts[d]]),
				PackedColorArray([cs[a], cs[b], cs[c], cs[d]]), PackedVector2Array(), RID())
			k += 2
		else:
			RenderingServer.canvas_item_add_primitive(ci, PackedVector2Array([pts[a], pts[b], pts[c]]),
				PackedColorArray([cs[a], cs[b], cs[c]]), PackedVector2Array(), RID())
			k += 1


## Polígono de uma cor (leque), sem triangle array (ver emit).
static func poly(n: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var m := pts.size()
	if m < 3:
		return
	if m <= 4:
		var cs := PackedColorArray()
		cs.resize(m)
		cs.fill(col)
		RenderingServer.canvas_item_add_primitive(n.get_canvas_item(), pts, cs, PackedVector2Array(), RID())
		return
	fan(n, pts, col)


## Círculo cheio como retângulo com textura de disco (vai no lote comum, sem buffer novo de
## vídeo como o draw_circle, que no Android cria um polígono a cada chamada).
static var _disc: ImageTexture


static func circle(n: CanvasItem, p: Vector2, r: float, col: Color, _filled := true, _w := -1.0, _aa := false) -> void:
	if r <= 0.0:
		return
	if _disc == null:
		var S := 64
		var im := Image.create(S, S, false, Image.FORMAT_RGBA8)
		var c := (S - 1) / 2.0
		for y in S:
			for x in S:
				var d := Vector2(x - c, y - c).length()
				im.set_pixel(x, y, Color(1, 1, 1, clampf(c + 0.5 - d, 0.0, 1.0)))
		_disc = ImageTexture.create_from_image(im)
	n.draw_texture_rect(_disc, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


## Linha com vários pontos feita de segmentos (draw_polyline/draw_arc criam polígono novo a cada
## chamada no Android; segmentos vão no lote comum).
static func polyline(n: CanvasItem, pts: PackedVector2Array, col: Color, w := -1.0, _aa := false) -> void:
	for i in pts.size() - 1:
		n.draw_line(pts[i], pts[i + 1], col, w)


static func arc(n: CanvasItem, c: Vector2, r: float, a0: float, a1: float, segs: int, col: Color, w := -1.0, _aa := false) -> void:
	segs = maxi(2, segs)
	var prev := c + Vector2(cos(a0), sin(a0)) * r
	for i in range(1, segs):
		var a := lerpf(a0, a1, float(i) / (segs - 1))
		var q := c + Vector2(cos(a), sin(a)) * r
		n.draw_line(prev, q, col, w)
		prev = q


static func tris(n: CanvasItem, pts: PackedVector2Array, idx: PackedInt32Array, col: Color) -> void:
	if pts.size() < 3 or idx.size() < 3:
		return
	var cs := PackedColorArray()
	cs.resize(pts.size())
	cs.fill(col)
	emit(n, idx, pts, cs)


## Polígono em leque a partir do primeiro ponto (bom para formas quase convexas).
static func fan(n: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var idx := PackedInt32Array()
	for i in range(1, pts.size() - 1):
		idx.append_array(PackedInt32Array([0, i, i + 1]))
	tris(n, pts, idx, col)


## Faixa que afina ao longo de uma linha (fita de vento, onda, cipó, raio com brilho).
static func ribbon(n: CanvasItem, line: PackedVector2Array, w0: float, w1: float, col: Color, fade := false) -> void:
	var m := line.size()
	if m < 2:
		return
	var pts := PackedVector2Array()
	var cs := PackedColorArray()
	for i in m:
		var f := float(i) / (m - 1)
		var dv: Vector2 = line[mini(m - 1, i + 1)] - line[maxi(0, i - 1)]
		var nx := Vector2(-dv.y, dv.x).normalized() if dv.length() > 0.001 else Vector2.UP
		var w := lerpf(w0, w1, f)
		pts.append(line[i] + nx * w)
		pts.append(line[i] - nx * w)
		var c := Color(col, col.a * (1.0 - f * 0.9 if fade else 1.0))
		cs.append(c)
		cs.append(c)
	var idx := PackedInt32Array()
	for i in m - 1:
		var o := i * 2
		idx.append_array(PackedInt32Array([o, o + 2, o + 3, o, o + 3, o + 1]))
	emit(n, idx, pts, cs)


## Gota alongada na direção do movimento (frente redonda, rabinho para trás).
static func drop(n: CanvasItem, p: Vector2, vel: Vector2, r: float, col: Color) -> void:
	var d := vel.normalized() if vel.length() > 1.0 else Vector2.DOWN
	var q := Vector2(-d.y, d.x)
	var stretch := clampf(vel.length() / 200.0, 1.0, 3.0)
	var pts := PackedVector2Array([p])
	for i in 9:
		var a := -PI * 0.5 + PI * i / 8.0
		pts.append(p + (d * cos(a) + q * sin(a)) * r)
	pts.append(p - d * r * stretch * 1.6)
	pts.append(pts[1])
	fan(n, pts, col)
	circle(n, p + q * r * 0.35 + d * r * 0.3, r * 0.28, Color(1, 1, 1, col.a * 0.7))


## Nuvem macia (fumaça, poeira, névoa): camadas que se somam.
static func puff(n: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	for i in 3:
		var k := 1.0 - i * 0.28
		circle(n, c + Vector2(i * r * 0.12, -i * r * 0.1), r * k, Color(col, col.a * (0.35 + i * 0.22)))


## Estrela de brilho (4 pontas) para luz e faíscas.
static func star(n: CanvasItem, p: Vector2, r: float, col: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array([p])
	for i in 9:
		var a := rot + TAU * i / 8.0
		var rr := r if i % 2 == 0 else r * 0.22
		pts.append(p + Vector2(cos(a), sin(a)) * rr)
	fan(n, pts, col)


## Floco de neve de 6 braços.
static func flake(n: CanvasItem, p: Vector2, r: float, rot: float, col: Color) -> void:
	for i in 6:
		var a := rot + TAU * i / 6.0
		var d := Vector2(cos(a), sin(a))
		n.draw_line(p, p + d * r, col, 1.2)
		n.draw_line(p + d * r * 0.55, p + d * r * 0.55 + d.rotated(0.8) * r * 0.35, col, 1.0)
		n.draw_line(p + d * r * 0.55, p + d * r * 0.55 + d.rotated(-0.8) * r * 0.35, col, 1.0)


## Cristal de gelo facetado: lado escuro, lado claro, faceta de cima e um reflexo.
static func shard(n: CanvasItem, base: Vector2, h: float, w: float, lean: float, a: float, tint := Color(0.72, 0.9, 1.0)) -> void:
	if h < 2.0:
		return
	var up := Vector2(sin(lean), -cos(lean))
	var side := Vector2(-up.y, up.x)
	var tip := base + up * h
	var sh := base + up * h * 0.74
	var l1 := base - side * w
	var r1 := base + side * w
	var l2 := sh - side * w * 0.85
	var r2 := sh + side * w * 0.85
	fan(n, PackedVector2Array([base, l1, l2, sh]), Color(tint.darkened(0.35), 0.92 * a))
	fan(n, PackedVector2Array([base, sh, r2, r1]), Color(tint.lightened(0.15), 0.92 * a))
	fan(n, PackedVector2Array([sh, l2, tip, r2]), Color(tint.lightened(0.5), 0.95 * a))
	n.draw_line(base + side * w * 0.3, sh + side * w * 0.3, Color(1, 1, 1, 0.6 * a), 1.2)
	n.draw_line(l2, tip, Color(1, 1, 1, 0.35 * a), 1.0)


## Pedra facetada (luz de cima): forma irregular, topo claro, sombra embaixo, rachadinha.
static func boulder(n: CanvasItem, c: Vector2, r: float, sd: int, rot: float, col: Color, a := 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var k := rng.randi_range(6, 9)
	var pts := PackedVector2Array([c])
	var ring := []
	for i in k + 1:
		var ang := rot + TAU * (i % k) / k
		var rr := r * rng.randf_range(0.72, 1.12) if i < k else 0.0
		if i == k:
			ring.append(ring[0])
		else:
			ring.append(c + Vector2(cos(ang), sin(ang) * 0.82) * rr)
	for p in ring:
		pts.append(p)
	fan(n, pts, Color(col, a))
	# faceta de cima mais clara
	var top := PackedVector2Array([c + Vector2(0, -r * 0.2)])
	for p in ring:
		if (p as Vector2).y < c.y + r * 0.1:
			top.append(c + Vector2(0, -r * 0.2) + ((p as Vector2) - c) * 0.78)
	if top.size() >= 3:
		fan(n, top, Color(col.lightened(0.28), a))
	n.draw_line(c + Vector2(-r * 0.3, -r * 0.1), c + Vector2(r * 0.05, r * 0.35), Color(col.darkened(0.5), 0.7 * a), 1.2)


## Raio de verdade: caminho principal quebrado, galhos que se soltam, três camadas de brilho.
static func bolt(n: CanvasItem, a: Vector2, b: Vector2, sd: int, w: float, al: float, col := Color(0.75, 0.8, 1.0)) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var main := PackedVector2Array([a])
	var segs := maxi(5, int(a.distance_to(b) / 22.0))
	var nrm := (b - a).orthogonal().normalized()
	for i in range(1, segs):
		var f := float(i) / segs
		main.append(a.lerp(b, f) + nrm * rng.randf_range(-1, 1) * a.distance_to(b) * 0.07)
	main.append(b)
	var branches := []
	for i in range(1, segs - 1):
		if rng.randf() < 0.35:
			var p0: Vector2 = main[i]
			var dir := (b - a).normalized().rotated(rng.randf_range(-1.0, 1.0))
			var br := PackedVector2Array([p0])
			var p := p0
			for j in rng.randi_range(2, 4):
				p += dir.rotated(rng.randf_range(-0.6, 0.6)) * rng.randf_range(10, 22)
				br.append(p)
			branches.append(br)
	for pass_i in 3:
		var ww: float = [w * 5.0, w * 2.2, w * 0.9][pass_i]
		var cc: Color = [Color(col, 0.18 * al), Color(col.lightened(0.3), 0.55 * al), Color(1, 1, 1, al)][pass_i]
		polyline(n, main, cc, ww)
		for br in branches:
			polyline(n, br, Color(cc, cc.a * 0.7), ww * 0.55)


## Cipó crescendo por uma curva: caule que afina, folhas alternadas e espinhos.
static func vine(n: CanvasItem, line: PackedVector2Array, g: float, w: float, sd: int, a := 1.0, thorns := true) -> void:
	var m := int(line.size() * clampf(g, 0.0, 1.0))
	if m < 2:
		return
	var part := line.slice(0, m)
	ribbon(n, part, w, w * 0.25, Color(0.22, 0.38, 0.12, a))
	ribbon(n, part, w * 0.45, w * 0.1, Color(0.38, 0.62, 0.22, a))
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for i in range(1, m - 1):
		var p: Vector2 = part[i]
		var dv: Vector2 = part[i + 1] - part[i - 1]
		var nx := Vector2(-dv.y, dv.x).normalized()
		var sgn := 1.0 if i % 2 == 0 else -1.0
		if rng.randf() < 0.55:
			leaf(n, p, (nx * sgn + dv.normalized() * 0.6).normalized(), rng.randf_range(5, 9) * (1.0 - float(i) / m * 0.5), Color(0.3, 0.62, 0.2, a).lerp(Color(0.5, 0.75, 0.25, a), rng.randf()))
		elif thorns and rng.randf() < 0.5:
			var tp := p + nx * -sgn * w * 2.2
			fan(n, PackedVector2Array([p + dv.normalized() * w * 0.6, tp, p - dv.normalized() * w * 0.6]), Color(0.55, 0.45, 0.25, a))


static func leaf(n: CanvasItem, p: Vector2, d: Vector2, s: float, col: Color) -> void:
	var q := Vector2(-d.y, d.x)
	var tip := p + d * s * 2.0
	var pts := PackedVector2Array([p])
	for i in 5:
		var f := (i + 1) / 6.0
		pts.append(p.lerp(tip, f) + q * sin(f * PI) * s * 0.55)
	pts.append(tip)
	for i in range(4, -1, -1):
		var f := (i + 1) / 6.0
		pts.append(p.lerp(tip, f) - q * sin(f * PI) * s * 0.55)
	fan(n, pts, col)
	n.draw_line(p, tip, Color(col.darkened(0.4), col.a), 0.8)


## Fita de vento: curva que ondula, mais grossa no meio e transparente nas pontas.
static func gust(n: CanvasItem, from: Vector2, dir: Vector2, length: float, t: float, sd: float, w: float, a: float, curl := 0.6) -> void:
	var nrm := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array()
	for i in 14:
		var f := i / 13.0
		var bend := sin(f * PI * 1.4 + t * 6.0 + sd) * length * 0.06 + f * f * curl * length * 0.25 * sin(sd)
		pts.append(from + dir * length * f + nrm * bend)
	var cs := PackedColorArray()
	var p2 := PackedVector2Array()
	for i in pts.size():
		var f := float(i) / (pts.size() - 1)
		var ww := w * sin(f * PI)
		var dv: Vector2 = pts[mini(pts.size() - 1, i + 1)] - pts[maxi(0, i - 1)]
		var nx := Vector2(-dv.y, dv.x).normalized()
		p2.append(pts[i] + nx * ww)
		p2.append(pts[i] - nx * ww)
		var c := Color(0.88, 1.0, 0.96, a * sin(f * PI) * 0.75)
		cs.append(c)
		cs.append(c)
	var idx := PackedInt32Array()
	for i in pts.size() - 1:
		var o := i * 2
		idx.append_array(PackedInt32Array([o, o + 2, o + 3, o, o + 3, o + 1]))
	emit(n, idx, p2, cs)


## Lençol de água: parede ondulada, escura embaixo e espuma em cima, com gotas soltando.
static func water_wall(n: CanvasItem, line: PackedVector2Array, h: float, t: float, a: float) -> void:
	var m := line.size()
	if m < 2:
		return
	var pts := PackedVector2Array()
	var cs := PackedColorArray()
	for i in m:
		var hh := h * (0.75 + 0.25 * sin(i * 0.9 + t * 7.0))
		pts.append(line[i])
		pts.append(line[i] + Vector2(0, -hh))
		cs.append(Color(0.12, 0.35, 0.75, 0.55 * a))
		cs.append(Color(0.6, 0.85, 1.0, 0.75 * a))
	var idx := PackedInt32Array()
	for i in m - 1:
		var o := i * 2
		idx.append_array(PackedInt32Array([o, o + 2, o + 3, o, o + 3, o + 1]))
	emit(n, idx, pts, cs)
	# crista de espuma
	var crest := PackedVector2Array()
	for i in m:
		crest.append(pts[i * 2 + 1])
	polyline(n, crest, Color(0.95, 0.99, 1.0, 0.9 * a), 2.5)
	for i in m:
		if (i + int(t * 10.0)) % 3 == 0:
			circle(n, pts[i * 2 + 1] + Vector2(sin(t * 9.0 + i) * 3.0, -2), 2.2, Color(1, 1, 1, 0.8 * a))
