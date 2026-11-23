class_name SpellArt
extends RefCounted
## Visual de cada magia, condizente com o nome: Pedrada lança uma pedra em arco, Espinho lança
## espinhos, Raízes brotam do chão, Tornado gira, Tempestade de Raios cai do céu, etc.
## Tudo desenhado por código (sem imagens), com gravidade nas partículas.

const RX := 90.5  # raio de 1 tile na tela (semieixo x da elipse isométrica)
## Melhorias da magia sendo lançada (0 a 5): mais partículas e efeitos extras.
static var boost := 0
## Celular/tablet: efeitos com menos partículas e redesenho mais espaçado.
static var MOBILE := Settings.is_mobile()
## Linhas suavizadas: na web a imagem já é desenhada com o dobro de pixels, então não precisa (e pesa).
static var AA := not OS.has_feature("web")


## Efeito extra das melhorias: 1 anel de brilho, 2 dois anéis, 3 faíscas subindo, 4 runa no chão, 5 onda de choque e clarão.
static func upgrade_fx(parent: Node, pos: Vector2, col: Color, up: int) -> void:
	return
	if up >= 1:
		SpellFx.ring(parent, pos, 0.6, col.lightened(0.3), 0.5)
	if up >= 2:
		SpellFx.ring(parent, pos, 1.0, col, 0.7)
	if up >= 3:
		parts(parent, pos + Vector2(0, -20), 24, 90.0, 0.9, 0.05, col.lightened(0.5), col, -160.0)
	if up >= 4:
		fxg(parent, pos, 1.0, func(n: DrawFx, k: float):
			var a := 1.0 - k
			_no(n, Vector2.ZERO, RX * 1.2, Color(col, 0.6 * a), false, 2.0)
			for i in 6:
				var t := TAU * i / 6.0 + k * 2.0
				n.draw_line(Vector2(cos(t), sin(t) * 0.5) * RX * 1.2, Vector2(cos(t + 2.1), sin(t + 2.1) * 0.5) * RX * 1.2, Color(col.lightened(0.3), a * 0.8), 1.5, SpellArt.AA))
	if up >= 5:
		fx(parent, pos, 0.6, func(n: DrawFx, k: float): _no(n, Vector2.ZERO, RX * (0.5 + k * 2.5), Color(1, 1, 1, (1.0 - k) * 0.7), false, 4.0 * (1.0 - k)))
		_no(parent, pos + Vector2(0, -30), col, 3.0, 2.0, 0.5)


# ------------------------------------------------------------ peças
## Nó que desenha com uma função por `life` segundos. f(n, k) com k = 0..1.
class DrawFx:
	extends Node2D
	var fn: Callable
	var life := 1.0
	var t := 0.0
	var seed_v := 0

	func _ready() -> void:
		seed_v = randi()

	func _process(d: float) -> void:
		t += d
		if t >= life:
			queue_free()
			return
		# celular: redesenha 30x por segundo (o efeito continua igual, só menos trabalho)
		if SpellArt.MOBILE and Engine.get_process_frames() % 2 == 1:
			return
		queue_redraw()

	func _draw() -> void:
		var t0 := Prof.t()
		fn.call(self, t / life)
		Prof.add("efeitos", t0)


static func fx(parent: Node, pos: Vector2, life: float, f: Callable, add := true, z := 4) -> DrawFx:
	var n := DrawFx.new()
	n.fn = f
	n.life = life
	n.position = pos
	n.z_index = z
	if add:
		n.material = SpellFx._add_mat()
	parent.add_child(n)
	return n


## Sem brilho somado (pedra, raiz, espinho).
static func fxn(parent: Node, pos: Vector2, life: float, f: Callable) -> DrawFx:
	return fx(parent, pos, life, f, false)


## No chão, atrás dos personagens (poça, rachadura, rio de lava).
static func fxg(parent: Node, pos: Vector2, life: float, f: Callable) -> DrawFx:
	return fx(parent, pos, life, f, false, -1)


## Partículas com gravidade (g > 0 cai).
static func parts(parent: Node, pos: Vector2, amount: int, speed: float, life: float, size: float, a: Color, b: Color, g := 0.0, spread := 180.0, dir := Vector2.UP, add := true) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = maxi(1, int(amount * (1.0 + 0.25 * boost) * (0.6 if MOBILE else 1.0)))
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.9
	p.texture = LightKit.radial()
	if add:
		p.material = SpellFx._add_mat()
	p.direction = dir
	p.spread = spread
	p.gravity = Vector2(0, g)
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.color_ramp = SpellFx._ramp(a, b)
	p.position = pos
	p.z_index = 5
	parent.add_child(p)
	p.emitting = true
	p.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)
	return p


## Convexo? (teste barato: o sinal da curva não muda) — aí não precisa triangular para conferir.
static func _convex(pts: PackedVector2Array) -> bool:
	var sgn := 0
	var n := pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var c: Vector2 = pts[(i + 2) % n]
		var cr := (b - a).cross(c - b)
		if absf(cr) < 0.0001:
			continue
		var sg := 1 if cr > 0.0 else -1
		if sgn == 0:
			sgn = sg
		elif sg != sgn:
			return false
	return true


## Polígono seguro: pula os sem área (ex.: espinho com altura 0) e conserta os torcidos (capa de lado).
static func poly(n: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	var area := 0.0
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	if absf(area) < 1.0:
		return
	if pts.size() > 3 and not _convex(pts) and Geometry2D.triangulate_polygon(pts).is_empty():
		pts = Geometry2D.convex_hull(pts)
		if pts.size() < 4:
			return
	ElemArt.poly(n, pts, col)


## Polígono com volume: escurece do lado oposto à luz (vem do alto à esquerda) e clareia o lado da luz.
static func spoly(n: CanvasItem, pts: PackedVector2Array, col: Color, k := 0.32) -> void:
	if pts.size() < 3:
		return
	var area := 0.0
	var cen := Vector2.ZERO
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
		cen += a
	if absf(area) < 1.0:
		return
	if pts.size() > 3 and not _convex(pts) and Geometry2D.triangulate_polygon(pts).is_empty():
		pts = Geometry2D.convex_hull(pts)
		if pts.size() < 4:
			return
		pts.remove_at(pts.size() - 1)
	cen /= pts.size()
	var L := Vector2(-0.6, -0.8)
	var cols := PackedColorArray()
	for q in pts:
		var d := (q - cen)
		var f := d.normalized().dot(L) if d.length() > 0.01 else 0.0
		cols.append(col.lightened(f * k) if f > 0.0 else col.darkened(-f * k * 1.4))
	var fi := PackedInt32Array()
	for i in range(1, pts.size() - 1):
		fi.append_array(PackedInt32Array([0, i, i + 1]))
	ElemArt.emit(n, fi, pts, cols)


static func ellipse(n: CanvasItem, c: Vector2, rx: float, col: Color, filled := true, w := 2.0) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * rx * 0.5))
	if filled:
		poly(n, pts, col)
	else:
		ElemArt.polyline(n, pts, col, w, SpellArt.AA)


## Polígono de pedra irregular (mesmo formato para a mesma semente).
static func rock(n: CanvasItem, c: Vector2, r: float, col: Color, sd: int, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		var a := TAU * i / 7.0 + rot
		var h := fposmod(sin(float(sd) * 12.9898 + i * 78.233) * 43758.5453, 1.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r * (0.7 + h * 0.35))
	poly(n, pts, col)
	ElemArt.polyline(n, pts + PackedVector2Array([pts[0]]), col.darkened(0.45), 1.2, SpellArt.AA)
	n.draw_line(c + Vector2(-r * 0.3, -r * 0.4), c + Vector2(r * 0.25, -r * 0.5), col.lightened(0.35), 1.2)


static func jag(n: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, segs := 7, amp := 9.0) -> void:
	var pts := PackedVector2Array([a])
	for k in range(1, segs):
		pts.append(a.lerp(b, float(k) / segs) + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)))
	pts.append(b)
	ElemArt.polyline(n, pts, Color(col, col.a * 0.35), w * 3.0, SpellArt.AA)
	ElemArt.polyline(n, pts, col, w, SpellArt.AA)
	ElemArt.polyline(n, pts, Color(1, 1, 1, col.a), maxf(1.0, w * 0.4), SpellArt.AA)


static func thorn(n: CanvasItem, base: Vector2, tip: Vector2, w: float, col: Color) -> void:
	var d := (tip - base).normalized()
	var s := Vector2(-d.y, d.x) * w
	poly(n, PackedVector2Array([base + s, tip, base - s]), col)
	n.draw_line(base, tip, col.lightened(0.3), 1.0, SpellArt.AA)


## Raiz/trepadeira crescendo: curva de `base` até altura h (k = quanto já cresceu).
static func root(n: CanvasItem, base: Vector2, h: float, bend: float, k: float, col: Color, w := 3.0) -> void:
	var pts := PackedVector2Array()
	var steps := 8
	for i in steps + 1:
		var f := float(i) / steps * k
		pts.append(base + Vector2(sin(f * 3.0) * bend * f, -h * f))
	if pts.size() > 1:
		ElemArt.polyline(n, pts, col.darkened(0.3), w + 1.5, SpellArt.AA)
		ElemArt.polyline(n, pts, col, w, SpellArt.AA)
		for i in range(2, pts.size(), 2):
			thorn(n, pts[i], pts[i] + Vector2(5 if i % 4 == 0 else -5, -2), 1.3, col.lightened(0.25))


static func cor(el: String) -> Color:
	return Spellbook.ELEMENTS[el].cor if Spellbook.ELEMENTS.has(el) else Color.WHITE


static func shake(node: Node, amount: float, dur: float) -> void:
	var cam := node.get_viewport().get_camera_2d()
	if cam == null:
		return
	var tw := cam.create_tween()
	for i in int(dur / 0.05):
		tw.tween_property(cam, "offset", Vector2(randf_range(-amount, amount), -30 + randf_range(-amount, amount)), 0.05)
	tw.tween_property(cam, "offset", Vector2(0, -30), 0.05)


# ------------------------------------------------------------ fogo e lava animados
## Uma chama: língua com base arredondada, corpo que ondula e ponta que dança, em 4 camadas
## (vermelho escuro por fora, laranja, amarelo e um miolo quase branco perto da base).
## Cada chama tem o próprio ritmo (sd): altura pulsa irregular, inclina com o "vento" e
## às vezes solta um fiapo de fogo que sobe e some. Desenhada em triângulos (nunca falha).
static func flame(n: CanvasItem, base: Vector2, h: float, w: float, t: float, sd: float, a := 1.0) -> void:
	if h < 2.0 or a <= 0.01:
		return
	var f1 := 4.7 + fmod(absf(sd) * 1.37, 3.0)
	var hh := h * (0.8 + 0.14 * sin(t * f1 + sd) + 0.08 * sin(t * 13.3 + sd * 2.1) + 0.05 * sin(t * 23.0 + sd * 4.0))
	var lean := sin(t * 1.9 + sd) * 0.22 + sin(t * 6.1 + sd * 3.0) * 0.1
	var cols := [Color(0.7, 0.08, 0.02, 0.42 * a), Color(1.0, 0.36, 0.05, 0.62 * a), Color(1.0, 0.7, 0.18, 0.8 * a), Color(1.0, 0.95, 0.72, 0.9 * a)]
	var ks := [1.0, 0.8, 0.56, 0.32]
	for layer in 4:
		var k: float = ks[layer]
		var lh := hh * (k if layer < 3 else 0.4)
		var lw := w * (k * 0.9 + 0.1)
		var col: Color = cols[layer]
		var L := PackedVector2Array()
		var R := PackedVector2Array()
		for i in 10:
			var f := i / 9.0
			var wig := sin(f * 4.2 - t * 9.0 + sd) * lw * 0.28 * f
			var cx := lean * lh * f * f + wig
			var hw := lw * pow(sin(pow(f, 0.62) * PI), 0.85) * (1.0 - 0.3 * f)
			if f < 0.12:
				hw = lerpf(lw * 0.55, hw, f / 0.12)
			var y := -lh * f
			L.append(base + Vector2(cx - hw, y))
			R.append(base + Vector2(cx + hw, y))
		# base arredondada (leque) + corpo (faixa), tudo numa chamada só de triângulos
		var pts := PackedVector2Array()
		var idx := PackedInt32Array()
		for i in 10:
			pts.append(L[i])
			pts.append(R[i])
		for i in 9:
			var o := i * 2
			idx.append_array(PackedInt32Array([o, o + 2, o + 3, o, o + 3, o + 1]))
		var c0 := pts.size()
		pts.append(base)
		var bc := base + Vector2(0, lw * 0.12)
		for j in 5:
			var an := PI * j / 4.0
			pts.append(bc + Vector2(cos(an) * lw * 0.55, sin(an) * lw * 0.22))
		for j in 4:
			idx.append_array(PackedInt32Array([c0, c0 + 1 + j, c0 + 2 + j]))
		var cols_v := PackedColorArray()
		cols_v.resize(pts.size())
		cols_v.fill(col)
		ElemArt.emit(n, idx, pts, cols_v)
	# fiapo que se solta da ponta e sobe
	var ph := fmod(t * (1.3 + fmod(absf(sd), 0.7)) + absf(sd) * 0.31, 1.0)
	if ph > 0.35:
		var q := (ph - 0.35) / 0.65
		var wp := base + Vector2(lean * hh + sin(t * 5.0 + sd) * w * 0.3, -hh * (0.85 + q * 0.8))
		var ws := w * 0.45 * (1.0 - q)
		var wc := Color(1, 0.5 + 0.3 * (1.0 - q), 0.1, 0.7 * a * (1.0 - q))
		var wcs := PackedColorArray([wc, wc, wc])
		n.draw_primitive(PackedVector2Array([wp + Vector2(-ws, 0), wp + Vector2(0, -ws * 2.4), wp + Vector2(ws, 0)]), wcs, PackedVector2Array())
		n.draw_primitive(PackedVector2Array([wp + Vector2(-ws, 0), wp + Vector2(ws, 0), wp + Vector2(0, ws * 0.8)]), wcs, PackedVector2Array())


## Fogo de verdade num pedaço de chão: mistura chamas altas e finas, médias, baixas e largas,
## fiapos e faíscas, cada uma com seu ritmo, de trás para a frente (as da frente por cima).
## g = quanto já cresceu (0..1), rx = raio em px.
static func flames_in(n: CanvasItem, rx: float, count: int, h: float, t: float, g: float, a: float, sd: int) -> void:
	if Settings.level_now <= 3:
		count = maxi(2, int(count * 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var arr := []
	var tot := count + int(count * 0.6) + 2
	for i in tot:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * rx
		var kind := rng.randi() % 3
		var hk: float = [rng.randf_range(1.1, 1.5), rng.randf_range(0.7, 0.95), rng.randf_range(0.35, 0.55)][kind]
		var wk: float = [rng.randf_range(4.5, 6.5), rng.randf_range(7.0, 10.0), rng.randf_range(11.0, 16.0)][kind]
		# mais altas no meio, mais baixas na borda
		hk *= 1.0 - 0.45 * (r / maxf(1.0, rx))
		arr.append([Vector2(cos(ang) * r, sin(ang) * r * 0.5), hk, wk, rng.randf() * 20.0, rng.randf_range(0.0, 0.6)])
	arr.sort_custom(func(p, q): return p[0].y < q[0].y)
	for e in arr:
		# cada chama nasce num tempo diferente (o fogo "pega" aos poucos)
		var gg := clampf((g - float(e[4]) * 0.5) / 0.5, 0.0, 1.0) if g < 1.0 else 1.0
		flame(n, e[0], h * float(e[1]) * gg, float(e[2]) * (0.6 + 0.4 * gg), t, float(e[3]), a)
	# faíscas subindo em zigue-zague
	for i in int(count * 0.8) + 2:
		var f := fmod(t * rng.randf_range(0.6, 1.1) + rng.randf(), 1.0)
		var p0 := Vector2(rng.randf_range(-1, 1) * rx * 0.8, rng.randf_range(-0.4, 0.4) * rx)
		var p := p0 + Vector2(sin(t * 7.0 + i) * 5.0, -h * (0.6 + f * 1.4))
		var sc := Color(1, 0.8, 0.35, a * (1.0 - f))
		n.draw_line(p, p + Vector2(sin(t * 9.0 + i) * 2.0, 3.5), sc, 1.4)


## Lava: crosta escura rachada por cima de magma que se mexe, veios brilhando e bolhas estourando.
static func lava(n: CanvasItem, c: Vector2, rx: float, t: float, sd: int, a := 1.0, ry_k := 0.5) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var edge := PackedVector2Array()
	var molten := PackedVector2Array()
	var ph := rng.randf() * TAU
	for i in 22:
		var ang := TAU * i / 22.0
		var wob := 1.0 + 0.12 * sin(ang * 3.0 + ph) + 0.06 * sin(ang * 7.0 + ph * 2.0)
		edge.append(c + Vector2(cos(ang), sin(ang) * ry_k) * rx * wob)
		var mw := wob * (0.8 + 0.05 * sin(t * 2.0 + ang * 4.0))
		molten.append(c + Vector2(cos(ang), sin(ang) * ry_k) * rx * mw)
	ElemArt.poly(n, edge, Color(0.16, 0.05, 0.03, 0.95 * a))
	ElemArt.poly(n, molten, Color(0.95, 0.28, 0.03, a))
	# manchas de magma mais quente deslizando
	for i in 6:
		var ang := rng.randf() * TAU + t * (0.25 + rng.randf() * 0.3)
		var r := rng.randf_range(0.1, 0.55) * rx
		var p := c + Vector2(cos(ang) * r, sin(ang) * r * ry_k)
		n.draw_set_transform(p, 0.0, Vector2(1, ry_k))
		ElemArt.circle(n, Vector2.ZERO, rx * rng.randf_range(0.12, 0.22), Color(1, 0.62 + 0.15 * sin(t * 3.0 + i), 0.12, 0.85 * a))
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# placas de crosta boiando
	for i in 5:
		var ang := rng.randf() * TAU + t * 0.15
		var r := rng.randf_range(0.2, 0.6) * rx
		var p := c + Vector2(cos(ang) * r, sin(ang) * r * ry_k)
		var sz := rx * rng.randf_range(0.08, 0.15)
		var pl := PackedVector2Array()
		for j in 5:
			var b := TAU * j / 5.0 + rng.randf() * 0.6
			pl.append(p + Vector2(cos(b), sin(b) * ry_k) * sz * rng.randf_range(0.7, 1.2))
		ElemArt.poly(n, pl, Color(0.22, 0.07, 0.04, 0.9 * a))
	# veios brilhando
	for i in 4:
		var p0 := c + Vector2(rng.randf_range(-0.6, 0.6) * rx, rng.randf_range(-0.25, 0.25) * rx)
		var pts := PackedVector2Array([p0])
		for j in 3:
			p0 += Vector2(rng.randf_range(-0.25, 0.25) * rx, rng.randf_range(-0.1, 0.1) * rx)
			pts.append(p0)
		ElemArt.polyline(n, pts, Color(1, 0.9, 0.45, (0.5 + 0.5 * sin(t * 4.0 + i)) * a), 2.0)
	# bolhas que incham e estouram
	for i in 5:
		var p := c + Vector2(rng.randf_range(-0.55, 0.55) * rx, rng.randf_range(-0.22, 0.22) * rx)
		var b := fmod(t * (0.8 + rng.randf() * 0.6) + rng.randf(), 1.0)
		if b < 0.75:
			ElemArt.circle(n, p + Vector2(0, -b * 4.0), 2.0 + b * 6.0, Color(1, 0.55 + b * 0.35, 0.15, a))
			ElemArt.arc(n, p + Vector2(-1, -b * 4.0 - 1), 1.5 + b * 4.0, PI * 1.1, PI * 1.6, 6, Color(1, 1, 0.8, 0.7 * a), 1.2)
		else:
			var q := (b - 0.75) / 0.25
			for j in 4:
				var d := Vector2(cos(j * 1.6 + i), -1.0).normalized() * q * 14.0
				ElemArt.circle(n, p + d + Vector2(0, q * q * 10.0), 1.8 * (1.0 - q), Color(1, 0.7, 0.2, a))


## Respingo de lava: gotas em arco que caem e deixam pingos no chão.
static func lava_splash(parent: Node, pos: Vector2, count: int, spread: float) -> void:
	var drops := []
	for i in count:
		drops.append([Vector2(randf_range(-1, 1), randf_range(-0.5, 0.5)) * spread, randf_range(30, 80), randf_range(2.5, 5.0)])
	fxn(parent, pos, 0.7, func(n: DrawFx, k: float):
		for d in drops:
			var p: Vector2 = d[0] * k + Vector2(0, -sin(k * PI) * d[1] - 30.0 * (1.0 - k))
			ElemArt.circle(n, p, d[2], Color(0.95, 0.35, 0.05))
			ElemArt.circle(n, p + Vector2(-1, -1), d[2] * 0.5, Color(1, 0.85, 0.4)))
	parent.get_tree().create_timer(0.7).timeout.connect(func():
		if not is_instance_valid(parent):
			return
		for d in drops:
			var at: Vector2 = pos + d[0]
			var sz: float = d[2]
			fxg(parent, at, 2.5, func(n: DrawFx, k: float):
				n.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
				ElemArt.circle(n, Vector2.ZERO, sz * 1.6, Color(0.15, 0.05, 0.03, 0.8 * (1.0 - k)))
				ElemArt.circle(n, Vector2.ZERO, sz * 1.1, Color(1, 0.4 * (1.0 - k) + 0.1, 0.05, 1.0 - k))
				n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)))


## Chão pegando fogo por um tempo.
static func fire_patch(parent: Node, pos: Vector2, rx: float, dur: float, count := 6) -> void:
	fx(parent, pos, dur, func(n: DrawFx, k: float):
		var g := minf(1.0, k * 6.0)
		var a := 1.0 - maxf(0.0, k - 0.65) / 0.35
		_no(n, Vector2.ZERO, rx * 1.1, Color(1, 0.3, 0.05, 0.12 * a))
		flames_in(n, rx, count, 34.0, n.t, g, a, n.seed_v))
	parts(parent, pos + Vector2(0, -10), int(6 + rx * 0.1), 30.0, 1.3, 0.04, Color(1, 0.75, 0.3), Color(0.6, 0.1, 0.0), -70.0, 40.0)


# ------------------------------------------------------------ projéteis (magia 1 e fusão 7)
## Projétil voando: corpo alongado com cauda afinando e pedacinhos do elemento soltando pelo
## caminho (gotas, folhas, brasas, lascas de gelo, pedrinhas, fiapos de vento). Sem bolinhas.
class Proj:
	extends Node2D
	var el := "fogo"
	var els: Array = []
	var target: Node2D
	var speed := 560.0
	var big := false
	var on_hit: Callable
	var _from := Vector2.ZERO
	var _last := Vector2.ZERO
	var _t := 0.0
	var _dist := 1.0
	var _trail := []
	var _light: PointLight2D
	## pedacinhos soltos: [pos global, vel, vida, vida_max, rot, giro]
	var _bits := []
	var _spawn := 0.0

	func _ready() -> void:
		material = SpellFx._add_mat() if el == "fogo" or el == "raio" else null
		z_index = 5
		_from = global_position
		_last = target.global_position
		_dist = maxf(1.0, _from.distance_to(_last))
		_light = LightKit.make(SpellArt.cor(el), 0.8 if not big else 1.4, 0.7, false, 0.2)
		_light.visible = el == "fogo" or el == "lava"
		add_child(_light)

	func _process(delta: float) -> void:
		_t += delta
		if is_instance_valid(target):
			_last = target.global_position
		var to := _last - _from
		var k := clampf(_t * speed / maxf(1.0, to.length()), 0.0, 1.0)
		var p := _from.lerp(_last, k)
		# bateu numa parede no caminho: explode ali, sem acertar
		if k < 1.0 and not Rules.has_sight(global_position, p):
			SpellArt.impact(get_parent(), global_position, el, big)
			_detach_bits()
			queue_free()
			return
		var h := 44.0
		if el == "terra":
			h = 44.0 + sin(k * PI) * minf(120.0, to.length() * 0.35)
		global_position = p
		_light.position = Vector2(0, -h)
		_trail.push_front(Vector2(0, -h) + global_position)
		if _trail.size() > 4:
			_trail.pop_back()
		# solta pedacinhos do elemento
		_spawn -= delta
		if _spawn <= 0.0 and k < 1.0:
			_spawn = 0.035
			var dir := to.normalized()
			var side := Vector2(-dir.y, dir.x)
			var v := -dir * randf_range(20, 70) + side * randf_range(-50, 50)
			match el:
				"agua", "lava": v += Vector2(0, -randf_range(10, 60))
				"natureza": v += Vector2(0, -randf_range(0, 30))
				"fogo": v += Vector2(0, -randf_range(30, 70))
			var life := randf_range(0.35, 0.7)
			_bits.append([global_position + Vector2(0, -h) + side * randf_range(-5, 5), v, life, life, randf() * TAU, randf_range(-8, 8)])
		for bt in _bits:
			bt[2] -= delta
			var g := 0.0
			match el:
				"agua", "lava", "terra", "gelo": g = 380.0
				"natureza": g = 60.0
				"fogo": g = -40.0
			bt[1] += Vector2(0, g * delta)
			if el == "natureza":
				var vv: Vector2 = bt[1]
				vv.x += sin(_t * 9.0 + float(bt[4])) * 40.0 * delta
				bt[1] = vv
			bt[0] += bt[1] * delta
			bt[4] += float(bt[5]) * delta
		_bits = _bits.filter(func(bt): return bt[2] > 0.0)
		queue_redraw()
		if k >= 1.0:
			if on_hit.is_valid() and is_instance_valid(target):
				on_hit.call()
			_detach_bits()
			queue_free()

	## os pedacinhos que ainda estão no ar continuam caindo depois do impacto
	func _detach_bits() -> void:
		if _bits.is_empty() or not is_instance_valid(get_parent()):
			return
		var bits := _bits.duplicate(true)
		var e := el
		SpellArt.fxn(get_parent(), Vector2.ZERO, 0.7, func(n: DrawFx, k: float):
			for bt in bits:
				var q: Vector2 = bt[0] + bt[1] * k * 0.7 + Vector2(0, 190.0 * k * k * 0.5)
				SpellArt.bit(n, e, q, float(bt[4]) + k * float(bt[5]), (1.0 - k) * float(bt[2]) / float(bt[3])))

	## cauda afinando a partir da cabeça (faixas de quadriláteros: sem bolinhas)
	func _tail(w0: float, col: Color, col2: Color) -> void:
		var n := _trail.size()
		if n < 3:
			return
		var L := []
		var R := []
		for i in n:
			var q: Vector2 = _trail[i] - global_position
			var dv: Vector2 = _trail[maxi(0, i - 1)] - _trail[mini(n - 1, i + 1)]
			var nx := Vector2(-dv.y, dv.x).normalized() if dv.length() > 0.01 else Vector2.UP
			var w := w0 * (1.0 - float(i) / n)
			L.append([q + nx * w, q + nx * w * 0.45])
			R.append([q - nx * w, q - nx * w * 0.45])
		for i in n - 1:
			var f := 1.0 - float(i) / n
			# triângulos direto (sem triangulação: não falha quando a cauda faz curva)
			for k2 in 2:
				var cc: Color = Color(col, col.a * f) if k2 == 0 else Color(col2, col2.a * f)
				var cs := PackedColorArray([cc, cc, cc])
				var a0: Vector2 = L[i][k2]
				var a1: Vector2 = L[i + 1][k2]
				var b0: Vector2 = R[i][k2]
				var b1: Vector2 = R[i + 1][k2]
				draw_primitive(PackedVector2Array([a0, a1, b1]), cs, PackedVector2Array())
				draw_primitive(PackedVector2Array([a0, b1, b0]), cs, PackedVector2Array())

	func _draw() -> void:
		var c: Vector2 = _trail[0] - global_position if _trail.size() > 0 else Vector2(0, -44)
		var dir := (_last - _from).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var s := 1.8 if big else 1.0
		for bt in _bits:
			SpellArt.bit(self, el, bt[0] - global_position, float(bt[4]), float(bt[2]) / float(bt[3]))
		match el:
			"fogo":
				# bola de fogo redonda com chamas curtinhas para trás
				_tail(5.0 * s, Color(0.95, 0.25, 0.03, 0.5), Color(1, 0.7, 0.2, 0.6))
				draw_set_transform(c, (-dir).angle() + PI * 0.5, Vector2.ONE * s)
				for j in 3:
					SpellArt.flame(self, Vector2((j - 1) * 4.0, 2.0), 16.0 - absf(j - 1) * 5.0, 6.0, _t, j * 2.3)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				ElemArt.circle(self, c, 9.5 * s, Color(0.95, 0.3, 0.04))
				ElemArt.circle(self, c + dir * 1.5 * s, 6.5 * s, Color(1, 0.62, 0.15))
				ElemArt.circle(self, c + dir * 2.5 * s, 3.5 * s, Color(1, 0.95, 0.7))
			"lava":
				_tail(4.5 * s, Color(0.35, 0.08, 0.03, 0.9), Color(1, 0.42, 0.06, 0.95))
				SpellArt.lava(self, c, 9.0 * s, _t * 2.0, 7, 1.0, 0.8)
			"agua":
				_tail(4.5 * s, Color(0.2, 0.5, 1.0, 0.55), Color(0.75, 0.92, 1.0, 0.8))
				SpellArt.poly(self, PackedVector2Array([c + dir * 10 * s, c + nrm * 5 * s, c - dir * 6 * s, c - nrm * 5 * s]), Color(0.6, 0.85, 1.0, 0.95))
			"gelo":
				_tail(4.0 * s, Color(0.7, 0.9, 1.0, 0.3), Color(1, 1, 1, 0.35))
				var tip := c + dir * 16 * s
				SpellArt.poly(self, PackedVector2Array([tip, c + nrm * 5 * s, c - dir * 12 * s, c - nrm * 5 * s]), Color(0.75, 0.92, 1, 0.95))
				draw_line(c - dir * 11 * s, tip, Color(1, 1, 1), 1.5, SpellArt.AA)
			"vento":
				for i in 4:
					var off := nrm * (i - 1.5) * 6.0 * s
					var pts := PackedVector2Array()
					for j in 8:
						var f := j / 7.0
						pts.append(c + off - dir * f * 22.0 * s + nrm * sin(_t * 18.0 + f * 5.0 + i) * 4.0)
					ElemArt.polyline(self, pts, Color(0.85, 1, 0.95, 0.7 - absf(i - 1.5) * 0.15), 2.0, SpellArt.AA)
				var a0 := dir.angle() - 1.2
				ElemArt.arc(self, c, 12 * s, a0, a0 + 2.4, 16, Color(0.9, 1, 0.97, 0.9), 3.0, SpellArt.AA)
			"terra":
				SpellArt.rock(self, c, 9 * s, Color(0.45, 0.38, 0.3), 3, _t * 9.0)
			"natureza":
				for i in 3:
					var b: Vector2 = c + nrm * (i - 1) * 7 - dir * absf(i - 1) * 8
					SpellArt.thorn(self, b - dir * 14, b + dir * 9, 2.5, Color(0.25, 0.55, 0.15))
			"faca", "flecha", "lanca":
				var L: float = {"faca": 14.0, "flecha": 26.0, "lanca": 34.0}[el] * s
				var spin := _t * 22.0 if el == "faca" else 0.0
				var dd := dir.rotated(spin)
				var qq := Vector2(-dd.y, dd.x)
				if el != "faca":
					ElemArt.ribbon(self, PackedVector2Array([c - dd * L, c + dd * L * 0.5]), 1.4, 1.4, Color(0.45, 0.32, 0.18))
					SpellArt.poly(self, PackedVector2Array([c + dd * L * 0.85, c + dd * L * 0.5 + qq * 4.0, c + dd * L * 0.5 - qq * 4.0]), Color(0.72, 0.74, 0.78))
					SpellArt.poly(self, PackedVector2Array([c - dd * L, c - dd * L * 0.75 + qq * 4.0, c - dd * L * 0.8]), Color(0.85, 0.82, 0.75))
					SpellArt.poly(self, PackedVector2Array([c - dd * L, c - dd * L * 0.75 - qq * 4.0, c - dd * L * 0.8]), Color(0.85, 0.82, 0.75))
				else:
					SpellArt.poly(self, PackedVector2Array([c + dd * L * 0.6, c + qq * 2.5, c - dd * L * 0.1, c - qq * 2.5]), Color(0.8, 0.82, 0.86))
					ElemArt.ribbon(self, PackedVector2Array([c - dd * L * 0.1, c - dd * L * 0.5]), 2.2, 2.2, Color(0.3, 0.2, 0.12))
			"teia":
				for i in 6:
					var a := TAU * i / 6.0 + _t * 3.0
					draw_line(c, c + Vector2.from_angle(a) * 10.0 * s, Color(0.95, 0.95, 0.9, 0.85), 1.2)
				for r in [4.0, 7.5]:
					ElemArt.arc(self, c, r * s, 0, TAU, 12, Color(0.95, 0.95, 0.9, 0.7), 1.0)
			"trevas":
				for i in 4:
					var off := Vector2(sin(_t * 9.0 + i * 1.7), cos(_t * 7.0 + i)) * 4.0
					ElemArt.puff(self, c + off - dir * i * 5.0, (8.0 - i * 1.4) * s, Color(0.28, 0.08, 0.36, 0.55 - i * 0.1))
				ElemArt.circle(self, c, 3.5 * s, Color(0.75, 0.45, 1.0, 0.9))
			"gosma":
				ElemArt.drop(self, c, dir * 300.0, 6.0 * s, Color(0.45, 0.9, 0.35, 0.92))
			"lasca":
				var sp := _t * 16.0
				SpellArt.poly(self, PackedVector2Array([c + Vector2.from_angle(sp) * 8.0, c + Vector2.from_angle(sp + 2.2) * 3.0, c + Vector2.from_angle(sp + 3.6) * 6.0]), Color(0.85, 0.72, 0.4))
			_:
				SpellArt.poly(self, PackedVector2Array([c + dir * 9 * s, c + nrm * 5 * s, c - dir * 9 * s, c - nrm * 5 * s]), SpellArt.cor(el))


## Pedacinho de elemento: gota, folha, brasa, lasca de gelo, pedrinha, fiapo de vento.
static func bit(n: CanvasItem, el: String, p: Vector2, rot: float, a: float) -> void:
	if a <= 0.02:
		return
	var d := Vector2.RIGHT.rotated(rot)
	var q := Vector2(-d.y, d.x)
	match el:
		"agua":
			poly(n, PackedVector2Array([p + Vector2(0, -4), p + Vector2(2.2, 1), p + Vector2(0, 2.5), p + Vector2(-2.2, 1)]), Color(0.65, 0.88, 1, 0.85 * a))
		"natureza":
			poly(n, PackedVector2Array([p + d * 5, p + q * 2.2, p - d * 5, p - q * 2.2]), Color(0.35, 0.68, 0.2, a).lerp(Color(0.6, 0.8, 0.25, a), 0.5 + 0.5 * sin(rot)))
			n.draw_line(p - d * 5, p + d * 5, Color(0.2, 0.4, 0.1, a), 0.8)
		"fogo":
			poly(n, PackedVector2Array([p + Vector2(0, -6), p + Vector2(2, 0), p + Vector2(0, 2), p + Vector2(-2, 0)]), Color(1, 0.6 + 0.3 * a, 0.15, a))
		"lava":
			poly(n, PackedVector2Array([p + Vector2(0, -4), p + Vector2(2.6, 1), p + Vector2(0, 3), p + Vector2(-2.6, 1)]), Color(1, 0.4 + 0.3 * a, 0.05, a))
		"gelo":
			poly(n, PackedVector2Array([p + d * 4, p + q * 1.5, p - d * 4, p - q * 1.5]), Color(0.85, 0.96, 1, 0.9 * a))
		"terra":
			rock(n, p, 2.5, Color(0.42, 0.35, 0.27, a), int(rot * 10.0) % 7, rot)
		"vento":
			ElemArt.arc(n, p, 5.0, rot, rot + 1.8, 6, Color(0.9, 1, 0.95, 0.7 * a), 1.2)
		"trevas":
			ElemArt.circle(n, p, 3.0, Color(0.3, 0.1, 0.4, 0.5 * a))
		"gosma":
			ElemArt.drop(n, p, Vector2(0, 200), 2.0, Color(0.45, 0.9, 0.35, 0.9 * a))
		"teia":
			n.draw_line(p, p + Vector2.from_angle(rot) * 5.0, Color(0.95, 0.95, 0.9, 0.6 * a), 0.8)
		_:
			pass


static func projectile(parent: Node, from: Vector2, target: Node2D, el: String, big: bool, els: Array, on_hit: Callable, spd := 0.0) -> void:
	if el == "raio":
		fx(parent, Vector2.ZERO, 0.32, func(n: DrawFx, k: float):
			if is_instance_valid(target):
				ElemArt.bolt(n, from + Vector2(0, -50), target.global_position + Vector2(0, -40), n.seed_v + int(n.t * 24.0), 2.0 if big else 1.4, 1.0 - k))
		parent.get_tree().create_timer(0.05).timeout.connect(func():
			on_hit.call()
			if is_instance_valid(target):
				impact(parent, target.global_position, "raio", big))
		return
	if el == "natureza" and big:
		# Estaca de Espinhos: brota do chão embaixo do alvo
		var p0 := target.global_position
		fxn(parent, p0, 0.9, func(n: DrawFx, k: float):
			var g := minf(1.0, k * 4.0)
			for i in 5:
				var a := TAU * i / 5.0
				thorn(n, Vector2(cos(a) * 14, sin(a) * 7), Vector2(cos(a) * 6, sin(a) * 3 - 70 * g * (0.7 + 0.3 * (i % 2))), 6.0, Color(0.42, 0.36, 0.28).lerp(Color(0.3, 0.55, 0.2), float(i) / 5)))
		parts(parent, p0, 30, 120.0, 0.7, 0.06, Color(0.6, 0.5, 0.4), Color(0.3, 0.25, 0.2), 300.0, 60.0, Vector2.UP, false)
		parent.get_tree().create_timer(0.12).timeout.connect(on_hit)
		return
	var pr := Proj.new()
	pr.el = el
	pr.els = els
	pr.target = target
	pr.big = big
	pr.on_hit = on_hit
	pr.speed = spd if spd > 0.0 else (380.0 if el == "terra" else 560.0)
	pr.global_position = from
	parent.add_child(pr)


## Impacto no alvo, na cara do elemento.
static func _impact_old(parent: Node, pos: Vector2, el: String, big := false) -> void:
	var c := cor(el)
	var s := 1.6 if big else 1.0
	match el:
		"fogo":
			parts(parent, pos + Vector2(0, -40), int(30 * s), 120.0, 0.6, 0.07, Color(1, 0.85, 0.4), Color(0.8, 0.1, 0.0), -80.0)
			fire_patch(parent, pos, 26.0 * s, 0.9, int(4 * s))
		"lava":
			parts(parent, pos + Vector2(0, -36), int(14 * s), 150.0, 0.8, 0.05, Color(1, 0.6, 0.15), Color(0.4, 0.05, 0.0), 420.0, 70.0)
			lava_splash(parent, pos, int(7 * s), 40.0 * s)
		"agua":
			parts(parent, pos + Vector2(0, -36), int(30 * s), 160.0, 0.7, 0.045, Color(0.8, 0.95, 1), Color(0.2, 0.45, 1), 520.0, 70.0)
			fx(parent, pos, 0.5, func(n: DrawFx, k: float): _no(n, Vector2.ZERO, 10 + 30 * k * s, Color(0.6, 0.85, 1, 1.0 - k), false, 2.0))
		"gelo": parts(parent, pos + Vector2(0, -36), int(24 * s), 130.0, 0.7, 0.05, Color(1, 1, 1), Color(0.6, 0.85, 1), 380.0, 90.0)
		"vento": fx(parent, pos + Vector2(0, -36), 0.4, func(n: DrawFx, k: float):
			for i in 3:
				ElemArt.arc(n, Vector2.ZERO, (10 + i * 8) * (0.5 + k) * s, k * 6 + i, k * 6 + i + 2.2, 14, Color(0.85, 1, 0.95, 1.0 - k), 2.0, SpellArt.AA))
		"terra":
			parts(parent, pos + Vector2(0, -30), int(20 * s), 150.0, 0.7, 0.06, Color(0.6, 0.5, 0.4), Color(0.35, 0.3, 0.25), 520.0, 80.0, Vector2.UP, false)
			for i in int(4 * s):
				var off := Vector2(randf_range(-14, 14), 0)
				var sd := randi()
				fxn(parent, pos + off, 0.7, func(n: DrawFx, k: float):
					var h := sin(k * PI) * 26.0
					rock(n, Vector2(off.x * k * 2.0, -h - 6), 3.5, Color(0.45, 0.38, 0.3), sd, k * 9.0))
		"natureza": parts(parent, pos + Vector2(0, -36), int(16 * s), 110.0, 0.6, 0.05, Color(0.6, 0.9, 0.35), Color(0.2, 0.45, 0.1), 300.0)
		"raio": parts(parent, pos + Vector2(0, -40), int(26 * s), 200.0, 0.3, 0.04, Color(1, 1, 0.9), Color(0.5, 0.5, 1), 0.0)
	_no(parent, pos + Vector2(0, -36), c, 1.4 * s, 0.9 * s, 0.4)


# ------------------------------------------------------------ controle de grupo (magia 2)
static func _cc_old(parent: Node, center: Vector2, radius: float, el: String) -> void:
	var rx := radius * RX
	var c := cor(el)
	match el:
		"fogo":  # Marca Ardente: o chão pega fogo
			# a runa acende e o chão pega fogo: chamas na borda e no meio
			fx(parent, center, 1.6, func(n: DrawFx, k: float):
				var g := minf(1.0, k * 5.0)
				var a := 1.0 - maxf(0.0, k - 0.6) / 0.4
				for i in 14:
					var t := TAU * i / 14.0
					flame(n, Vector2(cos(t), sin(t) * 0.5) * rx, (34.0 + 12.0 * sin(i * 1.7)) * g, 9.0, n.t, i * 1.3, a)
				flames_in(n, rx * 0.6, 7, 46.0, n.t, g, a, n.seed_v))
			parts(parent, center, 40, 40.0, 1.2, 0.06, Color(1, 0.8, 0.3), Color(0.8, 0.1, 0), -90.0, 180.0)
		"lava":  # Poça de Lava borbulhando: magma de verdade, bolhas, fumaça e calor
			fxg(parent, center, 3.0, func(n: DrawFx, k: float):
				var a := minf(1.0, k * 6.0) * (1.0 - maxf(0.0, k - 0.8) / 0.2)
				var g := minf(1.0, k * 5.0)
				lava(n, Vector2.ZERO, rx * (0.55 + 0.45 * g), n.t, n.seed_v, a))
			fx(parent, center, 3.0, func(n: DrawFx, k: float):
				var a := minf(1.0, k * 6.0) * (1.0 - maxf(0.0, k - 0.8) / 0.2)
				_no(n, Vector2.ZERO, rx * 1.15, Color(1, 0.35, 0.05, 0.14 * a))
				flames_in(n, rx * 0.7, 4, 22.0, n.t, 1.0, a * 0.6, n.seed_v))
			parts(parent, center, 30, 30.0, 2.5, 0.04, Color(1, 0.7, 0.25), Color(0.5, 0.08, 0.0), -60.0, 180.0)
			parts(parent, center + Vector2(0, -20), 14, 18.0, 2.5, 0.16, Color(0.25, 0.22, 0.2, 0.35), Color(0.1, 0.1, 0.1, 0.0), -40.0, 30.0, Vector2.UP, false)
		"agua":  # Maré Sufocante: redemoinho
			fx(parent, center, 1.6, func(n: DrawFx, k: float):
				var a := 1.0 - k
				for i in 4:
					var r := rx * (0.3 + i * 0.22)
					var pts := PackedVector2Array()
					for j in 20:
						var t := k * 9.0 + i + j * 0.25
						pts.append(Vector2(cos(t) * r * (j / 20.0 + 0.3), sin(t) * r * 0.5 * (j / 20.0 + 0.3)))
					ElemArt.polyline(n, pts, Color(0.5, 0.8, 1, a * 0.8), 3.0, SpellArt.AA))
			parts(parent, center + Vector2(0, -10), 40, 120.0, 0.9, 0.045, Color(0.8, 0.95, 1), Color(0.2, 0.45, 1), 420.0, 60.0)
		"gelo":  # Congelar: cristais de gelo saem do chão
			fx(parent, center, 1.6, func(n: DrawFx, k: float):
				var g := minf(1.0, k * 5.0)
				var a := 1.0 - maxf(0.0, k - 0.7) / 0.3
				var rng := RandomNumberGenerator.new()
				rng.seed = n.seed_v
				for i in 12:
					var p := Vector2(rng.randf_range(-1, 1) * rx * 0.8, rng.randf_range(-0.4, 0.4) * rx)
					var h := rng.randf_range(18, 40) * g
					poly(n, PackedVector2Array([p + Vector2(-5, 0), p + Vector2(0, -h), p + Vector2(5, 0)]), Color(0.75, 0.92, 1, 0.85 * a))
					n.draw_line(p, p + Vector2(0, -h), Color(1, 1, 1, a), 1.0)
				_no(n, Vector2.ZERO, rx, Color(0.8, 0.95, 1, 0.15 * a)))
		"vento":  # Rajada: lufadas para fora
			fx(parent, center, 0.7, func(n: DrawFx, k: float):
				for i in 12:
					var t := TAU * i / 12.0
					var d := Vector2(cos(t), sin(t) * 0.5)
					n.draw_line(d * rx * k * 0.6, d * rx * (0.3 + k), Color(0.85, 1, 0.95, 1.0 - k), 2.5, SpellArt.AA))
			parts(parent, center, 40, 260.0, 0.6, 0.05, Color(0.75, 0.7, 0.6), Color(0.5, 0.45, 0.4), 0.0, 180.0, Vector2.UP, false)
		"raio":  # Paralisia: campo elétrico que estala
			fx(parent, center, 1.2, func(n: DrawFx, k: float):
				_no(n, Vector2.ZERO, rx, Color(0.6, 0.6, 1, 0.12 * (1.0 - k)))
				for i in 6:
					var t := randf() * TAU
					var r := randf() * rx
					var p := Vector2(cos(t) * r, sin(t) * r * 0.5)
					jag(n, p, p + Vector2(randf_range(-20, 20), -randf_range(20, 50)), Color(0.85, 0.85, 1, 1.0 - k), 1.5, 4, 6.0))
		"terra":  # Tremor: rachaduras e pedras pulando
			shake(parent, 4.0, 0.4)
			fxg(parent, center, 1.2, func(n: DrawFx, k: float):
				var a := 1.0 - maxf(0.0, k - 0.6) / 0.4
				var rng := RandomNumberGenerator.new()
				rng.seed = n.seed_v
				for i in 8:
					var t := TAU * i / 8.0 + rng.randf() * 0.4
					var p := Vector2.ZERO
					var pts := PackedVector2Array([p])
					for j in 4:
						t += rng.randf_range(-0.5, 0.5)
						p += Vector2(cos(t), sin(t) * 0.5) * rx * 0.28 * minf(1.0, k * 4.0)
						pts.append(p)
					ElemArt.polyline(n, pts, Color(0.08, 0.06, 0.04, a), 3.0, SpellArt.AA))
			impact(parent, center, "terra", true)
		"natureza":  # Raízes brotam do chão
			fxn(parent, center, 3.0, func(n: DrawFx, k: float):
				var g := minf(1.0, k * 4.0)
				var a := 1.0 - maxf(0.0, k - 0.85) / 0.15
				var rng := RandomNumberGenerator.new()
				rng.seed = n.seed_v
				for i in 10:
					var p := Vector2(rng.randf_range(-1, 1) * rx * 0.8, rng.randf_range(-0.4, 0.4) * rx)
					root(n, p, rng.randf_range(45, 80), rng.randf_range(-16, 16), g, Color(0.35, 0.25, 0.12, a).lerp(Color(0.3, 0.55, 0.18, a), rng.randf()), 5.0))
			parts(parent, center, 25, 70.0, 0.7, 0.05, Color(0.5, 0.4, 0.3), Color(0.3, 0.25, 0.2), 300.0, 60.0, Vector2.UP, false)
	_no(parent, center + Vector2(0, -20), c, 1.6, 1.0 + radius * 0.6, 0.6)


# ------------------------------------------------------------ cone e linha (magia 4)
static func _cone_old(parent: Node, pos: Vector2, dir: Vector2, length_px: float, half_ang: float, el: String) -> void:
	var c := cor(el)
	var o := pos + Vector2(0, -36)
	match el:
		"fogo":
			SpellFx.cone(parent, pos, dir, length_px, half_ang, Color(1, 0.85, 0.5), Color(0.8, 0.12, 0.02))
			# lençol de chamas avançando no cone e o chão queimando onde passou
			fx(parent, pos, 0.9, func(n: DrawFx, k: float):
				var a := 1.0 - maxf(0.0, k - 0.55) / 0.45
				var base := dir.angle()
				for i in 9:
					var t := base - half_ang + 2.0 * half_ang * (i + 0.5) / 9.0
					for j in 3:
						var f := minf(1.0, k * 2.2) * (0.35 + j * 0.3)
						var p := Vector2(cos(t), sin(t) * 0.55) * length_px * f
						flame(n, p, (22.0 + j * 10.0) * (1.0 - absf(f - 0.6)), 8.0 + j * 2.0, n.t, i * 2.1 + j, a))
			for i in 3:
				var fp := pos + Vector2(dir.x, dir.y * 0.55) * length_px * (0.45 + i * 0.22)
				parent.get_tree().create_timer(0.15 + i * 0.1).timeout.connect(func(): fire_patch(parent, fp, 30.0, 1.2, 4))
			parts(parent, o + dir * length_px * 0.6, 30, 30.0, 1.4, 0.12, Color(0.3, 0.28, 0.26, 0.6), Color(0.1, 0.1, 0.1, 0.0), -50.0, 180.0, Vector2.UP, false)
		"agua":  # Onda: frente de água avançando
			fx(parent, pos, 0.7, func(n: DrawFx, k: float):
				var r := length_px * k
				var base := dir.angle()
				var pts := PackedVector2Array()
				for i in 17:
					var t := base - half_ang + 2.0 * half_ang * i / 16.0
					pts.append(Vector2(cos(t) * r, sin(t) * r * 0.55) + Vector2(0, -12 - sin(i * 0.8 + k * 12) * 6))
				ElemArt.polyline(n, pts, Color(0.3, 0.55, 1, 0.55 * (1.0 - k * 0.5)), 16.0, SpellArt.AA)
				ElemArt.polyline(n, pts, Color(0.85, 0.95, 1, 1.0 - k * 0.5), 4.0, SpellArt.AA))
			parts(parent, o + dir * length_px * 0.5, 50, 160.0, 0.8, 0.045, Color(0.8, 0.95, 1), Color(0.2, 0.45, 1), 450.0, rad_to_deg(half_ang), dir)
		"gelo":
			SpellFx.cone(parent, pos, dir, length_px, half_ang, Color(1, 1, 1), Color(0.5, 0.8, 1))
			fx(parent, pos, 0.8, func(n: DrawFx, k: float):
				for i in 8:
					var t := dir.angle() - half_ang + 2.0 * half_ang * (i + 0.5) / 8.0
					var p := Vector2(cos(t), sin(t) * 0.55) * length_px * minf(1.0, k * 1.8) * (0.5 + 0.5 * (i % 2))
					var d2 := Vector2(cos(t), sin(t) * 0.55)
					poly(n, PackedVector2Array([p - d2 * 10 + Vector2(0, -30), p + d2 * 10 + Vector2(0, -30), p + Vector2(0, -36) + Vector2(-d2.y, d2.x) * 4]), Color(0.8, 0.95, 1, 1.0 - k)))
		"vento":
			fx(parent, pos, 0.6, func(n: DrawFx, k: float):
				for i in 10:
					var t := dir.angle() - half_ang + 2.0 * half_ang * randf()
					var d2 := Vector2(cos(t), sin(t) * 0.55)
					var r0 := length_px * k * randf_range(0.3, 1.0)
					n.draw_line(d2 * r0 + Vector2(0, -30), d2 * (r0 + 40) + Vector2(0, -30), Color(0.85, 1, 0.95, (1.0 - k) * 0.8), 2.0, SpellArt.AA))
			parts(parent, o, 40, length_px * 2.0, 0.6, 0.05, Color(0.75, 0.7, 0.6), Color(0.5, 0.45, 0.4), 0.0, rad_to_deg(half_ang), dir, false)
		"natureza":  # Trepadeiras chicoteando no cone
			fxn(parent, pos, 1.0, func(n: DrawFx, k: float):
				for i in 5:
					var t := dir.angle() - half_ang + 2.0 * half_ang * (i + 0.5) / 5.0
					var d2 := Vector2(cos(t), sin(t) * 0.55)
					var pts := PackedVector2Array()
					var g := minf(1.0, k * 2.5)
					for j in 12:
						var f := j / 11.0 * g
						pts.append(d2 * length_px * f + Vector2(-d2.y, d2.x) * sin(f * 9 + i) * 10 + Vector2(0, -10 - f * 20))
					ElemArt.polyline(n, pts, Color(0.2, 0.4, 0.1, 1.0 - maxf(0, k - 0.7) / 0.3), 4.0, SpellArt.AA)
					ElemArt.polyline(n, pts, Color(0.4, 0.75, 0.25, 1.0 - maxf(0, k - 0.7) / 0.3), 2.0, SpellArt.AA))
		_:
			SpellFx.cone(parent, pos, dir, length_px, half_ang, c.lightened(0.4), c)


static func _line_old(parent: Node, a: Vector2, b: Vector2, el: String) -> void:
	var d := b - a
	match el:
		"lava":  # Rio de Lava: magma correndo pelo chão, esfriando no fim
			var segs := 7
			for i in segs:
				var f := (i + 0.5) / segs
				var p := a + d * f
				var dl := f * 0.35
				parent.get_tree().create_timer(dl).timeout.connect(func():
					fxg(parent, p, 2.0, func(n: DrawFx, k: float):
						var g := minf(1.0, k * 6.0)
						var al := 1.0 - maxf(0.0, k - 0.6) / 0.4
						lava(n, Vector2.ZERO, 30.0 * g, n.t, n.seed_v, al))
					parts(parent, p + Vector2(0, -6), 5, 50.0, 0.8, 0.04, Color(1, 0.6, 0.15), Color(0.4, 0.05, 0), 260.0, 40.0))
			fx(parent, a, 1.8, func(n: DrawFx, k: float):
				var al := 1.0 - maxf(0, k - 0.6) / 0.4
				for i in 10:
					var f := fmod(k * 1.8 + i / 10.0, 1.0)
					ElemArt.circle(n, d * f, 4.0, Color(1, 0.85, 0.4, al * 0.8)))
		"raio":  # Corrente Elétrica
			fx(parent, Vector2.ZERO, 0.4, func(n: DrawFx, k: float):
				jag(n, a + Vector2(0, -44), b + Vector2(0, -40), Color(0.85, 0.85, 1, 1.0 - k), 3.0, 14, 14.0)
				jag(n, a + Vector2(0, -44), b + Vector2(0, -40), Color(0.6, 0.6, 1, 0.7 * (1.0 - k)), 1.5, 14, 18.0))
		"terra":  # Fenda: o chão se abre com estacas de pedra
			shake(parent, 3.0, 0.35)
			fxn(parent, a, 1.4, func(n: DrawFx, k: float):
				var g := minf(1.0, k * 3.0)
				var al := 1.0 - maxf(0, k - 0.6) / 0.4
				var nrm := Vector2(-d.normalized().y, d.normalized().x)
				var pts := PackedVector2Array()
				for i in 14:
					var f := i / 13.0 * g
					pts.append(d * f + nrm * (i % 2 * 2 - 1) * 5)
				if pts.size() > 1:
					ElemArt.polyline(n, pts, Color(0.05, 0.03, 0.02, al), 7.0, SpellArt.AA)
				for i in 6:
					var f := (i + 0.5) / 6.0
					if f <= g:
						var p := d * f
						var h := 26.0 * minf(1.0, (g - f) * 6.0) * al
						poly(n, PackedVector2Array([p + Vector2(-7, 0), p + Vector2(-1, -h), p + Vector2(7, 0)]), Color(0.42, 0.36, 0.3, al)))
			for i in 5:
				parts(parent, a + d * (i + 1) / 5.0, 8, 120.0, 0.6, 0.05, Color(0.6, 0.5, 0.4), Color(0.35, 0.3, 0.25), 450.0, 50.0, Vector2.UP, false)
		_:
			SpellFx.line(parent, a, b, cor(el))


# ------------------------------------------------------------ área (magia 6 e fusão 8)
## Desenha a área e chama on_impact quando o dano acontece (algumas caem do céu primeiro).
static func _area_old(parent: Node, center: Vector2, radius: float, el: String, on_impact: Callable, els := []) -> void:
	var rx := radius * RX
	var tree := parent.get_tree()
	var c := cor(el)
	var fused := els.size() > 1
	match el if not fused else "fus_" + str(els[0]):
		"fogo":  # Chuva de Fogo: várias bolas caem
			for i in 9:
				var p := center + Vector2(randf_range(-1, 1) * rx * 0.8, randf_range(-0.4, 0.4) * rx)
				var dl := randf_range(0.0, 0.5)
				tree.create_timer(dl).timeout.connect(func(): _fall(parent, p, Color(1, 0.55, 0.1), 0.35, "fogo"))
			tree.create_timer(0.6).timeout.connect(on_impact)
		"lava", "fus_fogo":  # Meteoro / Erupção
			if fused:
				# Erupção: gêiseres de lava saem do chão
				for i in 6:
					var p := center + Vector2(randf_range(-1, 1) * rx * 0.7, randf_range(-0.35, 0.35) * rx)
					tree.create_timer(i * 0.08).timeout.connect(func():
						parts(parent, p, 40, 380.0, 1.1, 0.07, Color(1, 0.75, 0.25), Color(0.5, 0.05, 0), 600.0, 15.0)
						_no(parent, p + Vector2(0, -30), Color(1, 0.45, 0.1), 2.0, 1.2, 0.6))
				cc(parent, center, radius, "lava")
				shake(parent, 6.0, 0.6)
				tree.create_timer(0.3).timeout.connect(on_impact)
			else:
				var hit := func():
					impact(parent, center, "lava", true)
					cc(parent, center, radius * 0.8, "lava")
					shake(parent, 6.0, 0.4)
					on_impact.call()
				SpellFx.meteor(parent, center, 0.6, radius, hit, Color(1, 0.4, 0.08))
		"agua":  # Dilúvio: chuva forte e poças
			fx(parent, center, 1.2, func(n: DrawFx, k: float):
				for i in 40:
					var p := Vector2(randf_range(-1, 1) * rx, randf_range(-0.5, 0.5) * rx)
					var y := -200 + fmod(k * 900 + i * 37, 200)
					n.draw_line(p + Vector2(4, y - 14), p + Vector2(0, y), Color(0.6, 0.8, 1, 0.6), 1.5)
				_no(n, Vector2.ZERO, rx, Color(0.3, 0.55, 1, 0.15 * k)))
			tree.create_timer(0.4).timeout.connect(func():
				for i in 6:
					impact(parent, center + Vector2(randf_range(-1, 1) * rx * 0.7, randf_range(-0.35, 0.35) * rx), "agua")
				on_impact.call())
		"gelo", "fus_agua":  # Nevasca / Tempestade de Granizo
			fx(parent, center, 1.5, func(n: DrawFx, k: float):
				for i in 45:
					var p := Vector2(randf_range(-1, 1) * rx, randf_range(-0.5, 0.5) * rx)
					var y := -180 + fmod(k * 500 + i * 41, 180)
					ElemArt.circle(n, p + Vector2(sin(k * 10 + i) * 6, y), 2.0 if not fused else 3.5, Color(1, 1, 1, 0.85))
				_no(n, Vector2.ZERO, rx, Color(0.85, 0.95, 1, 0.22 * k)))
			if fused:
				for i in 8:
					var p := center + Vector2(randf_range(-1, 1) * rx * 0.8, randf_range(-0.4, 0.4) * rx)
					tree.create_timer(randf_range(0, 0.6)).timeout.connect(func(): _fall(parent, p, Color(0.85, 0.95, 1), 0.3, "gelo"))
			tree.create_timer(0.5).timeout.connect(func():
				cc(parent, center, radius * 0.8, "gelo")
				on_impact.call())
		"vento", "fus_vento":  # Tornado / Furacão Elétrico
			fx(parent, center, 1.6, func(n: DrawFx, k: float):
				var a := minf(1.0, k * 5.0) * (1.0 - maxf(0, k - 0.75) / 0.25)
				for i in 14:
					var y := -i * 11.0
					var r := rx * (0.25 + i * 0.05)
					var t := k * 22.0 + i * 0.7
					ElemArt.arc(n, Vector2(sin(k * 6 + i * 0.3) * 6, y), r, t, t + 4.0, 20, Color(0.85, 1, 0.95, 0.55 * a), 2.5, SpellArt.AA)
					if fused and i % 4 == 0:
						jag(n, Vector2(cos(t) * r, y), Vector2(cos(t + 1) * r, y - 14), Color(0.8, 0.8, 1, a), 1.5, 3, 5.0))
			parts(parent, center, 50, 200.0, 1.2, 0.05, Color(0.75, 0.7, 0.6), Color(0.5, 0.45, 0.4), -60.0, 180.0, Vector2.UP, false)
			tree.create_timer(0.5).timeout.connect(on_impact)
		"raio":  # Tempestade de Raios caindo do céu
			for i in 7:
				var p := center + Vector2(randf_range(-1, 1) * rx * 0.8, randf_range(-0.4, 0.4) * rx)
				tree.create_timer(i * 0.09).timeout.connect(func():
					fx(parent, Vector2.ZERO, 0.3, func(n: DrawFx, k: float): jag(n, p + Vector2(randf_range(-40, 40), -420), p, Color(0.9, 0.9, 1, 1.0 - k), 3.0, 10, 18.0))
					_no(parent, p, Color(0.7, 0.7, 1), 2.5, 1.2, 0.3)
					parts(parent, p, 16, 150.0, 0.3, 0.04, Color(1, 1, 0.9), Color(0.5, 0.5, 1), 0.0))
			tree.create_timer(0.35).timeout.connect(on_impact)
		"terra", "fus_terra":  # Terremoto / Floresta Petrificada
			shake(parent, 9.0, 0.8)
			cc(parent, center, radius, "terra")
			if fused:
				fxn(parent, center, 2.2, func(n: DrawFx, k: float):
					var g := minf(1.0, k * 4.0)
					var al := 1.0 - maxf(0, k - 0.8) / 0.2
					var rng := RandomNumberGenerator.new()
					rng.seed = n.seed_v
					for i in 7:
						var p := Vector2(rng.randf_range(-1, 1) * rx * 0.75, rng.randf_range(-0.38, 0.38) * rx)
						var h := rng.randf_range(40, 70) * g
						n.draw_line(p, p + Vector2(0, -h), Color(0.45, 0.42, 0.4, al), 6.0, SpellArt.AA)
						for j in 3:
							n.draw_line(p + Vector2(0, -h * (0.5 + j * 0.2)), p + Vector2((j % 2 * 2 - 1) * 14 * g, -h * (0.7 + j * 0.15)), Color(0.5, 0.47, 0.44, al), 3.0, SpellArt.AA)
						ellipse(n, p + Vector2(0, -h), 12 * g, Color(0.35, 0.5, 0.25, 0.8 * al)))
			tree.create_timer(0.25).timeout.connect(on_impact)
		"natureza":  # Chuva de Espinhos
			fxn(parent, center, 1.0, func(n: DrawFx, k: float):
				for i in 24:
					var p := Vector2(randf_range(-1, 1) * rx, randf_range(-0.5, 0.5) * rx)
					var y := -220 + fmod(k * 700 + i * 53, 220)
					thorn(n, p + Vector2(3, y - 16), p + Vector2(0, y), 2.0, Color(0.3, 0.55, 0.18)))
			tree.create_timer(0.45).timeout.connect(func():
				cc(parent, center, radius * 0.7, "natureza")
				on_impact.call())
		_:
			impact(parent, center, el, true)
			on_impact.call()


## Escudo quebrando: a bolha racha e estoura em cacos que voam girando e caem.
static func shield_break(parent: Node, pos: Vector2, col: Color, els: Array) -> void:
	var shards := []
	for i in 16:
		var a := TAU * i / 16.0 + randf_range(-0.15, 0.15)
		var from := Vector2(cos(a) * 34.0, sin(a) * 40.0 - 44.0)
		shards.append([from, Vector2(cos(a), sin(a) * 0.8 - 0.3) * randf_range(90, 180), randf() * TAU, randf_range(-9, 9), randf_range(5, 9)])
	var c2 := col.lightened(0.35)
	# rachaduras na bolha (bem rápido)
	fx(parent, pos, 0.18, func(n: DrawFx, k: float):
		for i in 7:
			var a := TAU * i / 7.0
			var p0 := Vector2(0, -44)
			var p1 := p0 + Vector2(cos(a), sin(a)) * 18.0
			var p2 := p1 + Vector2(cos(a + 0.4), sin(a + 0.4)) * 16.0
			ElemArt.polyline(n, PackedVector2Array([p0, p1, p2]), Color(1, 1, 1, 1.0 - k), 2.0))
	fxn(parent, pos, 0.9, func(n: DrawFx, k: float):
		for sd in shards:
			var p: Vector2 = sd[0] + sd[1] * k + Vector2(0, 260.0 * k * k)
			var r: float = sd[2] + sd[3] * k
			var sz: float = sd[4] * (1.0 - k * 0.4)
			var d := Vector2.RIGHT.rotated(r)
			var q := Vector2(-d.y, d.x)
			poly(n, PackedVector2Array([p + d * sz, p + q * sz * 0.5, p - d * sz * 0.7, p - q * sz * 0.4]), Color(col, 0.85 * (1.0 - k)))
			n.draw_line(p - d * sz * 0.5, p + d * sz, Color(c2, 1.0 - k), 1.2))
	parts(parent, pos + Vector2(0, -44), 26, 160.0, 0.6, 0.05, c2, col, 300.0, 180.0)


## Sem marcas no chão nem bolas de luz: só o elemento aparece.
static func _no(_a = null, _b = null, _c = null, _d = null, _e = null, _f = null) -> void:
	pass


## Algo caindo do céu (bola de fogo, granizo) com explosão.
static func _fall(parent: Node, p: Vector2, col: Color, dur: float, el: String) -> void:
	var f: DrawFx = fx(parent, p, dur, func(n: DrawFx, k: float):
		var q := Vector2(60, -380) * (1.0 - k)
		if el == "fogo":
			n.draw_set_transform(q, Vector2(60, -380).angle() + PI * 0.5, Vector2.ONE)
			for j in 3:
				flame(n, Vector2((j - 1) * 4.0, 2.0), 30.0 - absf(j - 1) * 9.0, 7.0, n.t, j * 1.7)
			n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		n.draw_line(q + Vector2(30, -190) * 0.2, q, Color(col, 0.4), 6.0, SpellArt.AA)
		ElemArt.circle(n, q, 7, col)
		ElemArt.circle(n, q, 3.5, Color(1, 1, 0.9)))
	f.tree_exited.connect(func():
		if is_instance_valid(parent):
			impact(parent, p, el))


# ------------------------------------------------------------ sangue
## Sangue ao levar dano: gotas com gravidade e uma mancha no chão que some devagar.
## kind: "sangue", "osso" (esqueleto: lascas), "pedra" (golem), "palha" (boneco) ou um elemento (invocação).
static func blood(parent: Node, pos: Vector2, dmg_frac: float, kind := "sangue", h := 44.0) -> void:
	var n := int(clampf(6 + dmg_frac * 60.0, 6, 26))
	match kind:
		"sangue":
			parts(parent, pos + Vector2(0, -h), n, 130.0, 0.7, 0.035, Color(0.6, 0.02, 0.02), Color(0.3, 0.0, 0.0), 620.0, 70.0, Vector2.UP, false)
			var sd := randi()
			var big := clampf(dmg_frac * 3.0, 0.4, 1.4)
			fxg(parent, pos + Vector2(randf_range(-6, 6), randf_range(-2, 2)), 7.0, func(nn: DrawFx, k: float):
				var a := (1.0 - maxf(0.0, k - 0.6) / 0.4) * 0.75
				var g := minf(1.0, k * 12.0)
				for i in 5:
					var hh := fposmod(sin(float(sd) * 1.7 + i * 3.1) * 999.0, 1.0)
					var p := Vector2(cos(i * 2.4 + sd) * 7.0, sin(i * 2.4 + sd) * 3.0) * hh * big
					ellipse(nn, p, (3.0 + hh * 5.0) * big * g, Color(0.32, 0.01, 0.01, a)))
		"osso":
			parts(parent, pos + Vector2(0, -h), n, 120.0, 0.6, 0.03, Color(0.85, 0.82, 0.72), Color(0.5, 0.48, 0.4), 600.0, 70.0, Vector2.UP, false)
		"pedra":
			parts(parent, pos + Vector2(0, -h), n, 120.0, 0.6, 0.04, Color(0.5, 0.45, 0.4), Color(0.3, 0.28, 0.25), 600.0, 70.0, Vector2.UP, false)
		"palha":
			parts(parent, pos + Vector2(0, -h), n, 90.0, 0.9, 0.035, Color(0.85, 0.72, 0.4), Color(0.6, 0.48, 0.25), 260.0, 80.0, Vector2.UP, false)
		_:
			var c := cor(kind)
			parts(parent, pos + Vector2(0, -h), n, 110.0, 0.5, 0.04, c.lightened(0.4), c, 200.0)


# ------------------------------------------------------------ Luz
static func _light_old(parent: Node, kind: String, pos: Vector2) -> void:
	var gold := Color(1, 0.92, 0.55)
	match kind:
		"heal":  # pilar de luz do céu
			fx(parent, pos, 0.9, func(n: DrawFx, k: float):
				var a := sin(k * PI)
				n.draw_rect(Rect2(-12, -260, 24, 260), Color(1, 0.95, 0.7, 0.25 * a))
				n.draw_rect(Rect2(-5, -260, 10, 260), Color(1, 1, 0.9, 0.5 * a))
				_no(n, Vector2.ZERO, 26, Color(1, 0.95, 0.6, 0.4 * a)))
			parts(parent, pos + Vector2(0, -20), 30, 60.0, 1.0, 0.05, Color(1, 1, 0.85), gold, -120.0)
		"ring":  # Círculo Sagrado: runas douradas no chão
			fx(parent, pos, 1.2, func(n: DrawFx, k: float):
				var a := 1.0 - k
				_no(n, Vector2.ZERO, RX * 3.0 * minf(1.0, k * 3.0), Color(1, 0.9, 0.5, a), false, 3.0)
				_no(n, Vector2.ZERO, RX * 2.4 * minf(1.0, k * 3.0), Color(1, 0.95, 0.7, a * 0.7), false, 2.0)
				for i in 8:
					var t := TAU * i / 8.0 + k
					ElemArt.circle(n, Vector2(cos(t), sin(t) * 0.5) * RX * 2.7, 3.0, Color(1, 1, 0.8, a)))
		"bless":  # halo subindo
			fx(parent, pos, 1.0, func(n: DrawFx, k: float):
				_no(n, Vector2(0, -80 - k * 30), 14, Color(1, 0.95, 0.6, 1.0 - k), false, 3.0))
		"brave":  # chamas douradas
			parts(parent, pos + Vector2(0, -30), 40, 60.0, 1.0, 0.07, Color(1, 0.95, 0.6), Color(1, 0.6, 0.1), -150.0)
		"veil":  # cintilar
			parts(parent, pos + Vector2(0, -40), 30, 40.0, 0.9, 0.04, Color(1, 1, 1), Color(0.7, 0.8, 1), 0.0)


# ================================================================ efeitos novos dos elementos
# Mesma ideia do fogo: vários formatos, tamanhos e ritmos somados, sem marcas no chão.
# Fogo e lava continuam nas versões _old (já refeitas).

static func _rs(sd: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = sd
	return r


## Respingo em coroa: gotas de tamanhos diferentes em arco, com gravidade.
static func splash(parent: Node, pos: Vector2, count: int, spread: float, col := Color(0.6, 0.85, 1.0, 0.9), h := 30.0, life := 0.65) -> void:
	if Settings.level_now <= 3:
		count = maxi(3, int(count * 0.6))
	fxn(parent, pos, life, func(n: DrawFx, k: float):
		var rng := _rs(n.seed_v)
		var tt := k * life
		for i in count:
			var v := Vector2(rng.randf_range(-1, 1) * spread, rng.randf_range(-0.4, 0.4) * spread * 0.5 - rng.randf_range(120, 260))
			var p0 := Vector2(rng.randf_range(-6, 6), -h)
			var g := 620.0
			var p := p0 + v * tt + Vector2(0, 0.5 * g * tt * tt)
			if p.y > 4.0:
				continue
			ElemArt.drop(n, p, v + Vector2(0, g * tt), rng.randf_range(1.6, 3.6), Color(col, col.a * (1.0 - k * 0.6)))
		if k < 0.35:
			var q := k / 0.35
			for i in 10:
				var a := TAU * i / 10.0
				var b := Vector2(cos(a), sin(a) * 0.5) * (10.0 + 18.0 * q)
				ElemArt.ribbon(n, PackedVector2Array([b, b + Vector2(cos(a) * 4.0, -16.0 * (1.0 - q) - 4.0)]), 2.2, 0.4, Color(0.75, 0.92, 1.0, 0.7 * (1.0 - q))))


## Pedaços que voam e caem (gelo, pedra, folhas, lascas).
static func debris(parent: Node, pos: Vector2, kind: String, count: int, spread: float, life := 0.9, up := 220.0) -> void:
	if Settings.level_now <= 3:
		count = maxi(2, int(count * 0.6))
	fxn(parent, pos, life, func(n: DrawFx, k: float): _debris_draw(n, k, kind, count, spread, life, up))


static func _debris_draw(n: DrawFx, k: float, kind: String, count: int, spread: float, life: float, up: float) -> void:
	var rng := _rs(n.seed_v)
	var tt := k * life
	for i in count:
		var v := Vector2(rng.randf_range(-1, 1) * spread, -rng.randf_range(up * 0.5, up))
		var g := 120.0 if kind == "folha" else 640.0
		var p := Vector2(0, -30) + v * tt + Vector2(0, 0.5 * g * tt * tt)
		if kind == "folha":
			p.x += sin(tt * 7.0 + i) * 14.0
		if p.y > 2.0:
			p.y = 2.0
		var rot := rng.randf() * TAU + tt * rng.randf_range(-12, 12)
		var sz := rng.randf_range(0.6, 1.4)
		var a := 1.0 - maxf(0.0, k - 0.7) / 0.3
		match kind:
			"gelo":
				ElemArt.shard(n, p, 10.0 * sz, 3.0 * sz, rot, a)
			"pedra":
				ElemArt.boulder(n, p, 4.5 * sz, rng.randi(), rot, Color(0.46, 0.39, 0.31), a)
			"folha":
				ElemArt.leaf(n, p, Vector2.from_angle(rot), 4.5 * sz, Color(0.32, 0.62, 0.2, a).lerp(Color(0.62, 0.72, 0.22, a), rng.randf()))
			"lasca":
				ElemArt.fan(n, PackedVector2Array([p, p + Vector2.from_angle(rot) * 7.0 * sz, p + Vector2.from_angle(rot + 2.4) * 3.0 * sz]), Color(0.55, 0.45, 0.28, a))


## Nuvem de poeira, névoa ou vapor que se espalha e some.
static func cloud(parent: Node, pos: Vector2, rx: float, col: Color, count := 7, life := 1.2, rise := 18.0) -> void:
	if Settings.level_now <= 3:
		count = maxi(2, count / 2)
	fxn(parent, pos, life, func(n: DrawFx, k: float):
		var rng := _rs(n.seed_v)
		for i in count:
			var p := Vector2(rng.randf_range(-1, 1) * rx, rng.randf_range(-0.45, 0.45) * rx) * (0.5 + k * 0.7) + Vector2(0, -rise * k - 8.0)
			var r := rng.randf_range(10, 20) * (0.6 + k * 0.9)
			ElemArt.puff(n, p, r, Color(col, col.a * sin(minf(1.0, k * 1.4) * PI))))


static func impact(parent: Node, pos: Vector2, el: String, big := false) -> void:
	var s := 1.6 if big else 1.0
	match el:
		"fogo", "lava":
			_impact_old(parent, pos, el, big)
		"agua":
			splash(parent, pos, int(14 * s), 110.0 * s)
			cloud(parent, pos, 16.0 * s, Color(0.85, 0.93, 1.0, 0.25), 4, 0.7)
		"gelo":
			debris(parent, pos, "gelo", int(9 * s), 120.0 * s, 0.8, 200.0)
			cloud(parent, pos + Vector2(0, -20), 18.0 * s, Color(0.9, 0.97, 1.0, 0.35), 5, 0.9)
			fx(parent, pos + Vector2(0, -36), 0.6, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v)
				for i in 8:
					var a := rng.randf() * TAU
					ElemArt.flake(n, Vector2(cos(a), sin(a)) * (8.0 + 30.0 * k) * s, rng.randf_range(2.5, 4.5), a + k * 3.0, Color(1, 1, 1, 1.0 - k)))
		"vento":
			fx(parent, pos + Vector2(0, -36), 0.5, func(n: DrawFx, k: float):
				for i in 4:
					var a := i * TAU / 4.0 + k * 4.0
					ElemArt.gust(n, Vector2.from_angle(a) * 6.0, Vector2.from_angle(a + 1.3), 40.0 * s * (0.4 + k), n.t, i * 1.7, 3.5 * s, 1.0 - k))
			debris(parent, pos, "folha", int(5 * s), 140.0, 0.8, 120.0)
			cloud(parent, pos, 14.0 * s, Color(0.75, 0.7, 0.6, 0.25), 4, 0.6)
		"terra":
			debris(parent, pos, "pedra", int(6 * s), 110.0 * s, 0.85, 240.0)
			cloud(parent, pos, 22.0 * s, Color(0.55, 0.46, 0.36, 0.45), 6, 1.0)
		"natureza":
			debris(parent, pos, "folha", int(9 * s), 120.0 * s, 1.1, 160.0)
			debris(parent, pos, "lasca", int(4 * s), 90.0, 0.6, 140.0)
		"raio":
			fx(parent, pos + Vector2(0, -40), 0.28, func(n: DrawFx, k: float):
				for i in 4:
					var a := n.seed_v % 7 + i * TAU / 4.0
					ElemArt.bolt(n, Vector2.ZERO, Vector2.from_angle(a) * (24.0 + 20.0 * s), n.seed_v + i, 1.4, 1.0 - k))
			parts(parent, pos + Vector2(0, -40), int(14 * s), 220.0, 0.25, 0.03, Color(1, 1, 0.95), Color(0.6, 0.6, 1), 0.0)
		_:
			fx(parent, pos + Vector2(0, -40), 0.6, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v)
				for i in 7:
					var a := rng.randf() * TAU
					ElemArt.star(n, Vector2.from_angle(a) * 26.0 * k * s, rng.randf_range(3, 7) * (1.0 - k), Color(1, 0.95, 0.7, 1.0 - k), k * 3.0))


static func cc(parent: Node, center: Vector2, radius: float, el: String) -> void:
	var rx := radius * RX
	match el:
		"fogo", "lava":
			_cc_old(parent, center, radius, el)
		"agua":  # Maré Sufocante: redemoinho de água subindo e prendendo
			fxn(parent, center, 1.8, func(n: DrawFx, k: float):
				var a := minf(1.0, k * 4.0) * (1.0 - maxf(0.0, k - 0.75) / 0.25)
				for i in 5:
					var lp := PackedVector2Array()
					for j in 22:
						var f := j / 21.0
						var ang := n.t * (3.0 + i * 0.4) + f * 5.5 + i * 1.25
						var r := rx * (0.15 + f * 0.85) * (0.85 + 0.1 * i)
						lp.append(Vector2(cos(ang) * r, sin(ang) * r * 0.5 - (1.0 - f) * 26.0 * a))
					ElemArt.ribbon(n, lp, 1.0, 5.0 - i * 0.6, Color(0.25 + i * 0.1, 0.55 + i * 0.07, 1.0, 0.55 * a))
				for i in 12:
					var ang := n.t * 4.0 + i * 0.9
					var r := rx * (0.3 + 0.6 * fmod(i * 0.37, 1.0))
					ElemArt.circle(n, Vector2(cos(ang) * r, sin(ang) * r * 0.5 - 6.0), 2.0, Color(0.95, 1, 1, 0.8 * a)))
			for i in 4:
				var p := center + Vector2(randf_range(-1, 1) * rx * 0.6, randf_range(-0.3, 0.3) * rx)
				parent.get_tree().create_timer(0.2 + i * 0.25).timeout.connect(func(): splash(parent, p, 8, 70.0, Color(0.6, 0.85, 1.0, 0.9), 10.0))
		"gelo":  # Congelar: cristais de vários tamanhos brotando, névoa fria e flocos
			fxn(parent, center, 2.0, func(n: DrawFx, k: float):
				var g := minf(1.0, k * 4.0)
				var a := 1.0 - maxf(0.0, k - 0.75) / 0.25
				var rng := _rs(n.seed_v)
				var arr := []
				for i in 18:
					var ang := rng.randf() * TAU
					var r := sqrt(rng.randf()) * rx * 0.9
					arr.append([Vector2(cos(ang) * r, sin(ang) * r * 0.5), rng.randf_range(10, 46) * (1.0 - r / rx * 0.5), rng.randf_range(3, 8), rng.randf_range(-0.55, 0.55), rng.randf() * 0.5])
				arr.sort_custom(func(p, q): return p[0].y < q[0].y)
				for e in arr:
					var gg := clampf((g - float(e[4])) / 0.5, 0.0, 1.0)
					ElemArt.shard(n, e[0], float(e[1]) * gg, float(e[2]), float(e[3]), a))
			cloud(parent, center, rx * 0.8, Color(0.88, 0.96, 1.0, 0.35), 8, 1.8, 10.0)
			fx(parent, center, 1.8, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v)
				for i in 14:
					var p := Vector2(rng.randf_range(-1, 1) * rx, -rng.randf_range(10, 70) + fmod(k * 60.0 + i * 13.0, 60.0))
					ElemArt.flake(n, p, rng.randf_range(2, 4), k * 4.0 + i, Color(1, 1, 1, 0.8 * (1.0 - k))))
		"vento":  # Rajada: fitas de vento girando para fora, levando poeira e folhas
			fx(parent, center, 0.9, func(n: DrawFx, k: float):
				var a := 1.0 - maxf(0.0, k - 0.5) / 0.5
				for i in 10:
					var ang := TAU * i / 10.0 + k * 1.5
					var d := Vector2(cos(ang), sin(ang) * 0.5).normalized()
					ElemArt.gust(n, d * rx * k * 0.5 + Vector2(0, -20), d.rotated(0.5), rx * (0.4 + k * 0.6), n.t, i * 2.3, 4.0, a, 1.0))
			debris(parent, center, "folha", 10, rx * 1.6, 1.0, 100.0)
			cloud(parent, center, rx * 0.7, Color(0.72, 0.66, 0.56, 0.35), 8, 0.9, 6.0)
		"raio":  # Paralisia: raios pulando entre pontos do chão e subindo, faíscas
			fx(parent, center, 1.3, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v + int(n.t * 14.0))
				for i in 4:
					var a := Vector2(rng.randf_range(-1, 1) * rx * 0.8, rng.randf_range(-0.4, 0.4) * rx)
					var b := a + Vector2(rng.randf_range(-40, 40), -rng.randf_range(20, 60))
					if i % 2 == 0:
						b = Vector2(rng.randf_range(-1, 1) * rx * 0.8, rng.randf_range(-0.4, 0.4) * rx)
					ElemArt.bolt(n, a, b, rng.randi(), 1.2, 1.0 - k * 0.7)
				for i in 6:
					ElemArt.star(n, Vector2(rng.randf_range(-1, 1) * rx, rng.randf_range(-0.5, 0.2) * rx), rng.randf_range(2, 5), Color(0.9, 0.9, 1, 1.0 - k), rng.randf() * TAU))
		"terra":  # Tremor: rachaduras fundas, estacas de pedra e poeira
			shake(parent, 4.0, 0.4)
			fxn(parent, center, 1.5, func(n: DrawFx, k: float):
				var a := 1.0 - maxf(0.0, k - 0.65) / 0.35
				var rng := _rs(n.seed_v)
				var g := minf(1.0, k * 4.0)
				for i in 7:
					var ang := TAU * i / 7.0 + rng.randf() * 0.4
					var p := Vector2.ZERO
					var pts := PackedVector2Array([p])
					for j in 5:
						ang += rng.randf_range(-0.5, 0.5)
						p += Vector2(cos(ang), sin(ang) * 0.5) * rx * 0.22 * g
						pts.append(p)
					ElemArt.ribbon(n, pts, 3.5, 0.5, Color(0.06, 0.04, 0.03, a))
					ElemArt.polyline(n, pts, Color(0.62, 0.52, 0.4, 0.5 * a), 1.0)
				var arr := []
				for i in 9:
					var ang := rng.randf() * TAU
					var r := sqrt(rng.randf()) * rx * 0.8
					arr.append([Vector2(cos(ang) * r, sin(ang) * r * 0.5), rng.randf_range(14, 34), rng.randf_range(4, 8), rng.randf_range(-0.4, 0.4)])
				arr.sort_custom(func(p, q): return p[0].y < q[0].y)
				for e in arr:
					ElemArt.shard(n, e[0], float(e[1]) * sin(minf(1.0, k * 3.0) * PI * 0.5), float(e[2]), float(e[3]), a, Color(0.5, 0.42, 0.34)))
			debris(parent, center, "pedra", 10, rx * 1.2, 1.0, 260.0)
			cloud(parent, center, rx * 0.9, Color(0.55, 0.46, 0.36, 0.45), 9, 1.4)
		"natureza":  # Raízes e cipós brotando, enrolando e soltando folhas
			fxn(parent, center, 3.0, func(n: DrawFx, k: float):
				var g := minf(1.0, k * 3.0)
				var a := 1.0 - maxf(0.0, k - 0.85) / 0.15
				var rng := _rs(n.seed_v)
				var arr := []
				for i in 9:
					var ang := rng.randf() * TAU
					var r := sqrt(rng.randf()) * rx * 0.8
					arr.append([Vector2(cos(ang) * r, sin(ang) * r * 0.5), rng.randf_range(40, 80), rng.randf_range(-1, 1), rng.randi()])
				arr.sort_custom(func(p, q): return p[0].y < q[0].y)
				for e in arr:
					var lp := PackedVector2Array()
					var b: Vector2 = e[0]
					for j in 12:
						var f := j / 11.0
						lp.append(b + Vector2(sin(f * 5.0 + float(e[2]) * 3.0 + n.t * 2.0) * 9.0 * f + float(e[2]) * f * 16.0, -float(e[1]) * f))
					ElemArt.vine(n, lp, g, 4.5, int(e[3]), a))
			debris(parent, center, "folha", 8, rx, 1.6, 90.0)
			cloud(parent, center, rx * 0.6, Color(0.45, 0.36, 0.25, 0.35), 5, 0.9)
		_:
			_cc_old(parent, center, radius, el)


static func cone(parent: Node, pos: Vector2, dir: Vector2, length_px: float, half_ang: float, el: String) -> void:
	match el:
		"fogo", "lava":
			_cone_old(parent, pos, dir, length_px, half_ang, el)
		"agua":  # Onda: parede de água avançando, espuma e gotas
			fxn(parent, pos, 0.85, func(n: DrawFx, k: float):
				var r := length_px * minf(1.0, k * 1.25)
				var base := dir.angle()
				var lp := PackedVector2Array()
				for i in 17:
					var t := base - half_ang + 2.0 * half_ang * i / 16.0
					lp.append(Vector2(cos(t) * r, sin(t) * r * 0.55))
				ElemArt.water_wall(n, lp, 34.0 * (1.0 - k * 0.5), n.t, 1.0 - maxf(0.0, k - 0.7) / 0.3))
			for i in 4:
				var f := 0.3 + i * 0.22
				var p := pos + Vector2(dir.x, dir.y * 0.55) * length_px * f
				parent.get_tree().create_timer(f * 0.65).timeout.connect(func(): splash(parent, p, 9, 90.0, Color(0.6, 0.85, 1.0, 0.9), 26.0))
		"gelo":  # Sopro gelado: cristais nascendo pelo cone, névoa e flocos
			fxn(parent, pos, 1.3, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v)
				var a := 1.0 - maxf(0.0, k - 0.7) / 0.3
				var arr := []
				for i in 16:
					var t := dir.angle() + rng.randf_range(-half_ang, half_ang)
					var f := rng.randf_range(0.2, 1.0)
					arr.append([Vector2(cos(t), sin(t) * 0.55) * length_px * f, f, rng.randf_range(10, 30), rng.randf_range(3, 6), rng.randf_range(-0.5, 0.5)])
				arr.sort_custom(func(p, q): return p[0].y < q[0].y)
				for e in arr:
					var gg := clampf((k * 2.0 - float(e[1])) * 3.0, 0.0, 1.0)
					ElemArt.shard(n, e[0], float(e[2]) * gg, float(e[3]), float(e[4]), a))
			for i in 4:
				var p := pos + Vector2(dir.x, dir.y * 0.55) * length_px * (0.25 + i * 0.22)
				cloud(parent, p, 26.0, Color(0.88, 0.96, 1.0, 0.4), 4, 1.1, 8.0)
		"vento":  # Ventania: fitas de vento de comprimentos diferentes, folhas e poeira
			fx(parent, pos + Vector2(0, -28), 0.7, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v)
				for i in 9:
					var t := dir.angle() + rng.randf_range(-half_ang, half_ang)
					var d := Vector2(cos(t), sin(t) * 0.55).normalized()
					var st := length_px * clampf(k * 1.6 - rng.randf() * 0.4, 0.0, 1.0) * 0.6
					ElemArt.gust(n, d * st, d, length_px * rng.randf_range(0.25, 0.5), n.t, i * 1.9, rng.randf_range(2.5, 5.0), 1.0 - k, 0.4))
			debris(parent, pos + Vector2(dir.x, dir.y * 0.55) * length_px * 0.5, "folha", 8, 80.0, 0.9, 80.0)
			cloud(parent, pos + Vector2(dir.x, dir.y * 0.55) * length_px * 0.6, 30.0, Color(0.72, 0.66, 0.56, 0.3), 5, 0.8)
		"natureza":  # Chicote de cipós espinhentos pelo cone
			fxn(parent, pos, 1.1, func(n: DrawFx, k: float):
				var a := 1.0 - maxf(0.0, k - 0.7) / 0.3
				for i in 5:
					var t := dir.angle() - half_ang + 2.0 * half_ang * (i + 0.5) / 5.0
					var d2 := Vector2(cos(t), sin(t) * 0.55)
					var lp := PackedVector2Array()
					for j in 14:
						var f := j / 13.0
						lp.append(d2 * length_px * f + Vector2(-d2.y, d2.x) * sin(f * 8.0 + i + n.t * 9.0) * 10.0 * f + Vector2(0, -8 - f * 18))
					ElemArt.vine(n, lp, minf(1.0, k * 2.5), 4.0, i * 31, a))
			debris(parent, pos + Vector2(dir.x, dir.y * 0.55) * length_px * 0.6, "folha", 8, 90.0, 1.0, 100.0)
		_:
			_cone_old(parent, pos, dir, length_px, half_ang, el)


static func line(parent: Node, a: Vector2, b: Vector2, el: String) -> void:
	var d := b - a
	match el:
		"raio":  # Corrente Elétrica: raio principal com galhos e um segundo raio tremendo
			fx(parent, Vector2.ZERO, 0.45, func(n: DrawFx, k: float):
				ElemArt.bolt(n, a + Vector2(0, -44), b + Vector2(0, -40), n.seed_v + int(n.t * 20.0), 2.0, 1.0 - k)
				ElemArt.bolt(n, a + Vector2(0, -44), b + Vector2(0, -40), n.seed_v + 99 + int(n.t * 26.0), 1.0, 0.6 * (1.0 - k)))
			impact(parent, b, "raio")
		"terra":  # Fenda: o chão racha e estacas de pedra sobem uma atrás da outra
			shake(parent, 3.0, 0.35)
			fxn(parent, a, 1.5, func(n: DrawFx, k: float):
				var g := minf(1.0, k * 3.0)
				var al := 1.0 - maxf(0, k - 0.65) / 0.35
				var nrm := Vector2(-d.normalized().y, d.normalized().x)
				var rng := _rs(n.seed_v)
				var pts := PackedVector2Array()
				for i in 16:
					var f := i / 15.0 * g
					pts.append(d * f + nrm * rng.randf_range(-5, 5))
				ElemArt.ribbon(n, pts, 4.5, 1.0, Color(0.06, 0.04, 0.03, al))
				for i in 8:
					var f := (i + 0.5) / 8.0
					if f <= g:
						var p := d * f + nrm * rng.randf_range(-10, 10)
						var h := rng.randf_range(18, 36) * minf(1.0, (g - f) * 6.0)
						ElemArt.shard(n, p, h, rng.randf_range(4, 8), rng.randf_range(-0.4, 0.4), al, Color(0.5, 0.42, 0.34)))
			for i in 4:
				var p := a + d * (i + 1) / 4.0
				parent.get_tree().create_timer(i * 0.12).timeout.connect(func():
					debris(parent, p, "pedra", 4, 60.0, 0.7, 200.0)
					cloud(parent, p, 20.0, Color(0.55, 0.46, 0.36, 0.4), 3, 0.9))
		_:
			_line_old(parent, a, b, el)


static func area(parent: Node, center: Vector2, radius: float, el: String, on_impact: Callable, els := []) -> void:
	var rx := radius * RX
	var tree := parent.get_tree()
	var fused := els.size() > 1
	var key: String = el if not fused else "fus_" + str(els[0])
	match key:
		"agua":  # Dilúvio: chuva pesada de pingos variados e respingos por todo lado
			fx(parent, center, 1.4, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v)
				for i in 55:
					var p := Vector2(rng.randf_range(-1, 1) * rx, rng.randf_range(-0.5, 0.5) * rx)
					var sp := rng.randf_range(700, 1100)
					var y := -220.0 + fmod(n.t * sp + i * 37.0, 220.0)
					var ln := rng.randf_range(8, 20)
					n.draw_line(p + Vector2(3, y - ln), p + Vector2(0, y), Color(0.65, 0.85, 1, rng.randf_range(0.3, 0.7)), rng.randf_range(1.0, 2.0)), false)
			for i in 10:
				var p := center + Vector2(randf_range(-1, 1) * rx * 0.8, randf_range(-0.4, 0.4) * rx)
				tree.create_timer(randf_range(0.15, 1.1)).timeout.connect(func(): splash(parent, p, 7, 60.0, Color(0.6, 0.85, 1.0, 0.85), 4.0, 0.5))
			cloud(parent, center + Vector2(0, -170), rx, Color(0.45, 0.5, 0.6, 0.35), 8, 1.4, 0.0)
			tree.create_timer(0.4).timeout.connect(on_impact)
		"gelo", "fus_agua":  # Nevasca / Granizo: flocos de tamanhos diferentes no vento, névoa
			fx(parent, center, 1.7, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v)
				for i in 50:
					var p := Vector2(rng.randf_range(-1, 1) * rx, rng.randf_range(-0.5, 0.5) * rx)
					var y := -190.0 + fmod(n.t * rng.randf_range(120, 260) + i * 41.0, 190.0)
					var drift := sin(n.t * 2.0 + i) * 12.0 + (190.0 + y) * 0.25
					ElemArt.flake(n, p + Vector2(drift, y), rng.randf_range(2, 5) * (1.4 if fused else 1.0), n.t * rng.randf_range(-3, 3), Color(1, 1, 1, 0.85)))
			cloud(parent, center, rx, Color(0.9, 0.97, 1.0, 0.35), 10, 1.8, 6.0)
			if fused:
				for i in 9:
					var p := center + Vector2(randf_range(-1, 1) * rx * 0.8, randf_range(-0.4, 0.4) * rx)
					tree.create_timer(randf_range(0, 0.7)).timeout.connect(func():
						_fall(parent, p, Color(0.85, 0.95, 1), 0.3, "gelo")
						tree.create_timer(0.3).timeout.connect(func(): debris(parent, p, "gelo", 5, 70.0, 0.6, 140.0)))
			tree.create_timer(0.5).timeout.connect(func():
				cc(parent, center, radius * 0.8, "gelo")
				on_impact.call())
		"vento", "fus_vento":  # Tornado: funil de fitas girando, poeira, folhas e pedrinhas subindo
			fx(parent, center, 1.8, func(n: DrawFx, k: float):
				var a := minf(1.0, k * 4.0) * (1.0 - maxf(0, k - 0.75) / 0.25)
				var rng := _rs(n.seed_v)
				for i in 16:
					var y := -i * 11.0
					var r := rx * (0.18 + i * 0.055)
					var lp := PackedVector2Array()
					var t0 := n.t * (9.0 - i * 0.2) + i * 0.8
					for j in 10:
						var ang := t0 + j * 0.32
						lp.append(Vector2(cos(ang) * r + sin(n.t * 3.0 + i * 0.4) * 8.0, y + sin(ang) * r * 0.28))
					ElemArt.ribbon(n, lp, 0.6, 3.5, Color(0.86, 0.98, 0.94, 0.45 * a), true)
					if fused and i % 4 == 0:
						ElemArt.bolt(n, lp[0], lp[lp.size() - 1] + Vector2(0, -14), rng.randi() + int(n.t * 12.0), 0.8, a)
				for i in 14:
					var f := fmod(n.t * 0.5 + i * 0.13, 1.0)
					var ang := n.t * 8.0 + i * 1.7
					var r := rx * (0.2 + f * 0.8)
					var p := Vector2(cos(ang) * r, -f * 170.0 + sin(ang) * r * 0.28)
					if i % 3 == 0:
						ElemArt.boulder(n, p, 3.0, i, ang, Color(0.45, 0.4, 0.32), a)
					else:
						ElemArt.leaf(n, p, Vector2.from_angle(ang), 4.0, Color(0.4, 0.62, 0.2, a)))
			cloud(parent, center, rx * 0.8, Color(0.72, 0.66, 0.56, 0.4), 9, 1.6, 30.0)
			tree.create_timer(0.5).timeout.connect(on_impact)
		"raio":  # Tempestade de Raios: raios com galhos caindo do céu, um por vez
			cloud(parent, center + Vector2(0, -260), rx * 1.1, Color(0.25, 0.25, 0.35, 0.5), 9, 1.1, 0.0)
			for i in 7:
				var p := center + Vector2(randf_range(-1, 1) * rx * 0.8, randf_range(-0.4, 0.4) * rx)
				tree.create_timer(i * 0.09).timeout.connect(func():
					var sky := p + Vector2(randf_range(-50, 50), -420)
					fx(parent, Vector2.ZERO, 0.3, func(n: DrawFx, k: float): ElemArt.bolt(n, sky, p, n.seed_v, 2.2, 1.0 - k))
					impact(parent, p, "raio"))
			tree.create_timer(0.35).timeout.connect(on_impact)
		"terra", "fus_terra":  # Terremoto / Floresta Petrificada
			shake(parent, 9.0, 0.8)
			cc(parent, center, radius, "terra")
			if fused:
				fxn(parent, center, 2.4, func(n: DrawFx, k: float):
					var g := minf(1.0, k * 3.0)
					var al := 1.0 - maxf(0, k - 0.8) / 0.2
					var rng := _rs(n.seed_v)
					for i in 7:
						var p := Vector2(rng.randf_range(-1, 1) * rx * 0.75, rng.randf_range(-0.38, 0.38) * rx)
						var h := rng.randf_range(40, 70) * g
						var lp := PackedVector2Array()
						for j in 8:
							lp.append(p + Vector2(sin(j * 0.8 + i) * 4.0, -h * j / 7.0))
						ElemArt.ribbon(n, lp, 6.0, 2.5, Color(0.46, 0.43, 0.4, al))
						for j in 3:
							var bp: Vector2 = lp[3 + j]
							ElemArt.ribbon(n, PackedVector2Array([bp, bp + Vector2((j % 2 * 2 - 1) * 16, -14) * g]), 2.5, 0.8, Color(0.5, 0.47, 0.44, al))
						ElemArt.boulder(n, lp[lp.size() - 1], 10.0 * g, i, 0.0, Color(0.42, 0.5, 0.36), al))
			tree.create_timer(0.25).timeout.connect(on_impact)
		"natureza":  # Chuva de Espinhos: espinhos de tamanhos variados caindo, folhas e cipós
			fxn(parent, center, 1.2, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v)
				for i in 28:
					var p := Vector2(rng.randf_range(-1, 1) * rx, rng.randf_range(-0.5, 0.5) * rx)
					var y := -230.0 + fmod(n.t * rng.randf_range(550, 800) + i * 53.0, 230.0)
					var ln := rng.randf_range(10, 20)
					thorn(n, p + Vector2(3, y - ln), p + Vector2(0, y), rng.randf_range(1.5, 3.0), Color(0.3, 0.55, 0.18).lerp(Color(0.5, 0.4, 0.2), rng.randf())))
			tree.create_timer(0.45).timeout.connect(func():
				cc(parent, center, radius * 0.7, "natureza")
				on_impact.call())
		_:
			_area_old(parent, center, radius, el, on_impact, els)


static func light(parent: Node, kind: String, pos: Vector2) -> void:
	match kind:
		"heal":  # raios de luz descendo e brilhos subindo pelo corpo
			fx(parent, pos, 1.0, func(n: DrawFx, k: float):
				var a := sin(k * PI)
				var rng := _rs(n.seed_v)
				for i in 5:
					var x := rng.randf_range(-18, 18)
					ElemArt.ribbon(n, PackedVector2Array([Vector2(x * 2.5, -300), Vector2(x, -10)]), rng.randf_range(3, 8), 1.5, Color(1, 0.96, 0.75, 0.22 * a))
				for i in 10:
					var f := fmod(k * 1.3 + i * 0.1, 1.0)
					ElemArt.star(n, Vector2(rng.randf_range(-18, 18), -10 - f * 90.0), rng.randf_range(2, 5) * (1.0 - f), Color(1, 1, 0.85, a), f * 4.0))
		"ring":  # Círculo Sagrado: colunas de luz subindo em volta e brilhos
			fx(parent, pos, 1.3, func(n: DrawFx, k: float):
				var a := sin(k * PI)
				for i in 10:
					var t := TAU * i / 10.0 + k * 0.8
					var b := Vector2(cos(t), sin(t) * 0.5) * RX * 2.6
					ElemArt.ribbon(n, PackedVector2Array([b, b + Vector2(0, -60 - 30 * sin(i * 1.3 + k * 6.0))]), 4.0, 0.5, Color(1, 0.92, 0.6, 0.4 * a), true)
					ElemArt.star(n, b + Vector2(0, -70 * k), 4.0, Color(1, 1, 0.85, a), k * 5.0 + i))
		"bless":  # penas de luz e brilho subindo
			fx(parent, pos, 1.1, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v)
				for i in 8:
					var f := fmod(k + i * 0.125, 1.0)
					var p := Vector2(rng.randf_range(-22, 22) + sin(k * 8.0 + i) * 6.0, -20 - f * 100.0)
					ElemArt.leaf(n, p, Vector2.from_angle(-PI * 0.5 + sin(k * 6.0 + i) * 0.6), 5.0, Color(1, 0.97, 0.85, 1.0 - f))
					ElemArt.star(n, p + Vector2(6, 4), 2.5, Color(1, 0.95, 0.7, 1.0 - f), f * 6.0))
		"brave":  # chamas douradas subindo pelo corpo
			fx(parent, pos, 1.0, func(n: DrawFx, k: float):
				var a := sin(k * PI)
				for i in 6:
					var x := (i - 2.5) * 6.0
					flame(n, Vector2(x, -10 - absf(x)), 26.0 + 10.0 * sin(i * 1.7), 6.0, n.t, i * 1.9, a * 0.8))
			parts(parent, pos + Vector2(0, -30), 20, 60.0, 1.0, 0.05, Color(1, 0.95, 0.6), Color(1, 0.6, 0.1), -150.0)
		"veil":  # cintilar azulado em volta do corpo
			fx(parent, pos, 1.0, func(n: DrawFx, k: float):
				var rng := _rs(n.seed_v)
				for i in 14:
					var ang := rng.randf() * TAU + k * 2.0
					var p := Vector2(cos(ang) * 22.0, -40 + sin(ang) * 36.0)
					ElemArt.star(n, p, rng.randf_range(2, 4.5) * sin(fmod(k * 3.0 + i * 0.3, 1.0) * PI), Color(0.9, 0.95, 1, 0.9), k * 4.0))
		_:
			_light_old(parent, kind, pos)


# ------------------------------------------------------------ aura de ki (escudo mágico)
## Aura de ki em volta do corpo (escudo mágico).
## c = centro do corpo (o personagem tem ~90 px de altura, pés em y=0, então use c ≈ Vector2(0, -42));
## h = altura da aura (~100); col = cor principal, col2 = cor do brilho interno; t = tempo em segundos;
## force = 0..1 (fica mais fraca quando o escudo está quase quebrado).
## el = elemento (fogo, lava, agua, gelo, vento, raio, terra, natureza). Vazio mantém as faíscas.
static func ki_aura(n: CanvasItem, c: Vector2, h: float, col: Color, col2: Color, t: float, force := 1.0, el := "") -> void:
	if h < 4.0:
		return
	# alpha geral: escudo cheio brilha; quase quebrado fica no mínimo, ainda visível
	var gain := 0.35 + 0.65 * clampf(force, 0.0, 1.0)
	# chama em volta do corpo, em coordenadas locais (origem = c). y positivo = para baixo.
	# base arredondada um pouco abaixo dos pés, laterais que incham (~0.55*h) e coroa de pontas.
	var ring := PackedVector2Array()
	var bulb := Vector2(0.0, h * 0.42)
	for i in 7:
		var ang := lerpf(PI, 0.0, float(i) / 6.0)
		ring.append(bulb + Vector2(cos(ang) * h * 0.17, sin(ang) * h * 0.10))
	var right := PackedVector2Array()
	for i in 7:
		var sf := float(i + 1) / 7.0
		var ss := sin(sf * PI)
		# onda sobe com o tempo (a crista vai para sf maior)
		var wave := sin(t * 5.2 - sf * 6.6) * 0.012 * ss
		var nx := 0.17 + 0.105 * ss * ss + wave
		if sf > 0.72:
			nx = lerpf(nx, 0.155, (sf - 0.72) / 0.28)
		var ny := lerpf(0.42, -0.40, sf) + sin(t * 4.0 - sf * 5.2) * 0.01 * ss
		right.append(Vector2(nx * h, ny * h))
	for i in right.size():
		ring.append(right[i])
	# cinco línguas, da direita para a esquerda; cada ponta tem a própria fase
	var tip_x := [0.145, 0.07, 0.0, -0.065, -0.14]
	var tip_y := [0.62, 0.71, 0.80, 0.69, 0.60]
	for i in 5:
		var ph := float(i)
		var s1 := sin(t * 6.4 + ph * 1.7)
		var flick := 0.022 * s1 + 0.012 * sin(t * 11.2 + ph * 2.6)
		var sway := sin(t * 4.3 + ph * 1.35) * 0.012
		ring.append(Vector2((tip_x[i] + sway) * h, -(tip_y[i] + flick) * h))
		if i < 4:
			var vx: float = (tip_x[i] + tip_x[i + 1]) * 0.5 + sin(t * 3.4 + ph) * 0.008
			var valley := 0.55 + 0.012 * sin(t * 5.2 + ph * 2.1)
			ring.append(Vector2(vx * h, -valley * h))
	for i in range(right.size() - 1, -1, -1):
		var rp: Vector2 = right[i]
		ring.append(Vector2(-rp.x, rp.y))
	var m := ring.size()
	if m < 6:
		return
	# cápsula vazia em volta do corpo (pés até o chapéu). O brilho fica FORA dela,
	# então o personagem continua visível e as pontas acima da cabeça ficam cheias.
	var rx := h * 0.15
	var ry := h * 0.48
	var ey := -h * 0.05
	var inner := PackedVector2Array()
	var hot := PackedVector2Array()
	var edge := PackedVector2Array()
	var far := PackedVector2Array()
	for i in m:
		var p: Vector2 = ring[i]
		var plen := maxf(p.length(), 1.0)
		var d := p / plen
		var A := (d.x * d.x) / (rx * rx) + (d.y * d.y) / (ry * ry)
		var B := -2.0 * d.y * ey / (ry * ry)
		var C := (ey * ey) / (ry * ry) - 1.0
		var disc := maxf(0.0, B * B - 4.0 * A * C)
		var inv := 1.0 / (2.0 * maxf(A, 0.0000001))
		var rad := maxf((-B + sqrt(disc)) * inv, (-B - sqrt(disc)) * inv)
		# fica dentro da chama, com um vão mínimo, e nunca cola no centro
		var rad_max := maxf(h * 0.08, plen - h * 0.035)
		rad = clampf(rad, h * 0.06, rad_max)
		var inn := d * rad
		inner.append(inn)
		hot.append(inn.lerp(p, 0.4))
		edge.append(p)
		far.append(p * 1.08)
	# três faixas concêntricas: fora larga e suave, dentro mais clara e estreita
	var c_far := Color(col, 0.0)
	var c_edge := Color(col.lerp(col2, 0.2), col.a * gain * 0.3)
	var c_hot := Color(col2, col2.a * gain * 0.5)
	var c_near := Color(col2, col2.a * gain * 0.05)
	var idx := PackedInt32Array()
	for i in m - 1:
		var o := i * 2
		idx.append_array(PackedInt32Array([o, o + 2, o + 3, o, o + 3, o + 1]))
	var oc := (m - 1) * 2
	idx.append_array(PackedInt32Array([oc, 0, 1, oc, 1, oc + 1]))
	var shells := [far, edge, hot, inner]
	var scols := [c_far, c_edge, c_hot, c_near]
	for si in 3:
		var oa := shells[si] as PackedVector2Array
		var ia := shells[si + 1] as PackedVector2Array
		var co := scols[si] as Color
		var ci := scols[si + 1] as Color
		var pts := PackedVector2Array()
		var cs := PackedColorArray()
		for i in m:
			pts.append(c + oa[i])
			pts.append(c + ia[i])
			cs.append(co)
			cs.append(ci)
		ElemArt.emit(n, idx, pts, cs)
	# contorno claro e fino na camada de fora (mais um halo largo e suave)
	var line := PackedVector2Array()
	for i in m:
		line.append(c + edge[i])
	line.append(line[0])
	ElemArt.polyline(n, line, Color(col, col.a * gain * 0.16), maxf(2.0, h * 0.032))
	var rim := col.lightened(0.3)
	ElemArt.polyline(n, line, Color(rim, rim.a * col.a * gain * 0.88), maxf(1.0, h * 0.013))
	# Partículas do elemento por cima da chama. A posição sai só de t, para não piscar.
	match el:
		"fogo":
			_ki_fogo(n, c, h, col, col2, t, gain)
		"lava":
			_ki_lava(n, c, h, col, col2, t, gain, line)
		"agua":
			_ki_agua(n, c, h, col, col2, t, gain)
		"gelo":
			_ki_gelo(n, c, h, col, col2, t, gain)
		"vento":
			_ki_vento(n, c, h, col, col2, t, gain)
		"raio":
			_ki_raio(n, c, h, col, col2, t, gain)
		"terra":
			_ki_terra(n, c, h, col, col2, t, gain)
		"natureza":
			_ki_natureza(n, c, h, col, col2, t, gain)
		_:
			# faíscas sobem e somem
			var spark_x := [0.2, -0.18, 0.15, -0.22, 0.11, -0.16, 0.23, -0.12, 0.17, -0.2, 0.08, -0.14]
			for i in spark_x.size():
				var spd := 0.62 + float(i % 4) * 0.16
				var kf := fposmod(t * spd + float(i) * 0.173, 1.0)
				var life := clampf(kf * 4.0, 0.0, 1.0) * (1.0 - kf)
				if life <= 0.03:
					continue
				var kx: float = spark_x[i] * lerpf(1.0, 0.38, kf)
				var ky := lerpf(0.28, -0.72, kf)
				var sp := c + Vector2(kx * h + sin(t * 3.1 + float(i)) * h * 0.01, ky * h)
				var hot_c := col2.lightened(0.4) if i % 2 == 0 else col.lightened(0.3)
				var sc := Color(hot_c, hot_c.a * gain * life * 0.9)
				var rr := maxf(0.7, h * 0.016 * (1.0 - kf * 0.5))
				if i % 4 == 0:
					ElemArt.star(n, sp, rr * 1.8, sc, t * 2.4 + float(i))
				else:
					ElemArt.circle(n, sp, rr, sc)
			# três riscos verticais rápidos na faixa de energia
			var streak_x := [-0.19, 0.1, 0.18]
			for i in 3:
				var qf := fposmod(t * (2.5 + float(i) * 0.55) + float(i) * 0.37, 1.0)
				var sa := gain * sin(qf * PI)
				if sa <= 0.03:
					continue
				var qx: float = streak_x[i] + sin(t * 2.4 + float(i) * 2.1) * 0.012
				var y0 := lerpf(0.22, -0.48, qf)
				var ln := 0.15 + float(i) * 0.02
				var p0 := c + Vector2(qx * h, y0 * h)
				var p1 := c + Vector2(qx * h, (y0 - ln) * h)
				ElemArt.ribbon(n, PackedVector2Array([p0, p1]), maxf(1.6, h * 0.026), maxf(0.3, h * 0.004), Color(col, col.a * sa * 0.4), true)
				n.draw_line(p0, p1, Color(col2.lightened(0.45), col2.a * sa * 0.85), maxf(1.0, h * 0.011), SpellArt.AA)


## Ponto na borda da chama, em coordenadas locais (ainda sem somar o centro).
## side = ±1; sf = 0 nos pés e 1 na coroa.
static func _ki_rim(side: float, sf: float, h: float) -> Vector2:
	var u := clampf(sf, 0.0, 1.0)
	var bulge := sin(u * PI)
	var nx := 0.168 + 0.108 * bulge * bulge
	var ny := lerpf(0.40, -0.64, u)
	return Vector2(side * nx * h, ny * h)


## Línguas de fogo nas bordas e brasas subindo. Tudo derivado de t.
static func _ki_fogo(n: CanvasItem, c: Vector2, h: float, col: Color, col2: Color, t: float, gain: float) -> void:
	var side := 1.0
	var kf := 0.0
	var life := 0.0
	var local := Vector2.ZERO
	var p := Vector2.ZERO
	var fc := col
	for i in 8:
		side = 1.0 if i % 2 == 0 else -1.0
		kf = fposmod(t * (0.7 + float(i % 4) * 0.09) + float(i) * 0.137, 1.0)
		life = sin(kf * PI)
		if life <= 0.05:
			continue
		local = _ki_rim(side, lerpf(0.06, 0.94, kf), h)
		p = c + local + local.normalized() * (h * 0.02) + Vector2(sin(t * 6.2 + float(i) * 1.6) * h * 0.012, 0.0)
		fc = col2.lightened(0.38) if i % 3 == 0 else col.lightened(0.1)
		ElemArt.drop(n, p, Vector2(side * 36.0, -460.0), h * (0.02 + 0.012 * sin(kf * PI)), Color(fc, fc.a * gain * life * 0.92))
	for i in 6:
		kf = fposmod(t * (0.45 + float(i) * 0.04) + float(i) * 0.21, 1.0)
		life = sin(kf * PI)
		if life <= 0.05:
			continue
		p = c + Vector2(sin(t * 1.6 + float(i) * 1.35) * h * 0.1, lerpf(0.22, -0.74, kf) * h)
		fc = col.darkened(0.08) if i % 2 == 0 else col.lightened(0.42)
		var er := h * 0.013 * (1.15 - kf * 0.4)
		ElemArt.circle(n, p, er, Color(fc, fc.a * gain * life * 0.8))
		if i % 2 == 1:
			var core := col2.lightened(0.45)
			ElemArt.circle(n, p, er * 0.4, Color(core, core.a * gain * life * 0.7))


## Gotas de magma pingando, veios laranja, brasas escuras e borda de rocha.
static func _ki_lava(n: CanvasItem, c: Vector2, h: float, col: Color, col2: Color, t: float, gain: float, edge: PackedVector2Array) -> void:
	var rock := col.darkened(0.68)
	var crust := PackedVector2Array()
	for i in edge.size():
		var ep: Vector2 = edge[i]
		crust.append(c + (ep - c) * 1.065)
	ElemArt.polyline(n, crust, Color(rock, rock.a * gain * 0.82), maxf(2.5, h * 0.028))
	var vein := col.lightened(0.32)
	var side := 1.0
	var local := Vector2.ZERO
	var al := 0.0
	for i in 4:
		side = 1.0 if i % 2 == 0 else -1.0
		local = _ki_rim(side, 0.18 + float(i) * 0.12, h) * 0.78
		var bend := sin(t * 2.4 + float(i) * 1.7) * h * 0.015
		al = gain * (0.45 + 0.35 * sin(t * 3.1 + float(i) * 1.4))
		if al < 0.04:
			al = 0.04
		ElemArt.polyline(n, PackedVector2Array([
			c + local,
			c + local * 0.62 + Vector2(bend, -h * 0.06),
			c + local * 0.4 + Vector2(-bend * 0.4, -h * 0.12),
		]), Color(vein, vein.a * al), maxf(1.15, h * 0.012))
	var kf := 0.0
	var life := 0.0
	var p := Vector2.ZERO
	var dc := col
	for i in 6:
		side = 1.0 if i % 2 == 0 else -1.0
		kf = fposmod(t * (0.42 + float(i % 3) * 0.06) + float(i) * 0.19, 1.0)
		life = sin(kf * PI)
		if life <= 0.05:
			continue
		local = _ki_rim(side, lerpf(0.58, 0.06, kf), h)
		p = c + local + Vector2(side * h * 0.012, kf * h * 0.18)
		dc = col.lightened(0.18) if i % 2 == 0 else col
		ElemArt.drop(n, p, Vector2(side * 18.0, 420.0), h * 0.02 * (1.05 - kf * 0.35), Color(dc, dc.a * gain * life * 0.9))
	for i in 4:
		kf = fposmod(t * (0.3 + float(i) * 0.05) + float(i) * 0.27, 1.0)
		life = sin(kf * PI)
		if life <= 0.05:
			continue
		p = c + Vector2(sin(t * 1.1 + float(i) * 1.8) * h * 0.12, lerpf(0.15, -0.55, kf) * h)
		var dark := col.darkened(0.45)
		var er := h * 0.014 * (1.0 - kf * 0.3)
		ElemArt.circle(n, p, er, Color(dark, dark.a * gain * life * 0.75))
		var hot := col2.lightened(0.2)
		ElemArt.circle(n, p, er * 0.4, Color(hot, hot.a * gain * life * 0.55))


## Bolhas com brilho subindo e ondulação nas laterais.
static func _ki_agua(n: CanvasItem, c: Vector2, h: float, col: Color, col2: Color, t: float, gain: float) -> void:
	var wave := col2.lightened(0.32)
	var side := 1.0
	var pts := PackedVector2Array()
	var sf := 0.0
	for s in 2:
		side = 1.0 if s == 0 else -1.0
		pts = PackedVector2Array()
		for i in 8:
			sf = float(i) / 7.0
			var wob := sin(t * 4.2 + sf * 8.0 + side) * h * 0.018
			pts.append(c + _ki_rim(side, lerpf(0.08, 0.92, sf), h) + Vector2(side * wob, 0.0))
		ElemArt.ribbon(n, pts, maxf(1.6, h * 0.014), maxf(0.4, h * 0.004), Color(wave, wave.a * gain * 0.45), true)
	var kf := 0.0
	var life := 0.0
	var p := Vector2.ZERO
	var r := 0.0
	for i in 8:
		kf = fposmod(t * (0.38 + float(i % 3) * 0.07) + float(i) * 0.13, 1.0)
		life = sin(kf * PI)
		if life <= 0.05:
			continue
		side = 1.0 if i % 2 == 0 else -1.0
		p = c + _ki_rim(side, lerpf(0.1, 0.9, kf), h) * lerpf(0.72, 0.96, life)
		p += Vector2(sin(t * 2.4 + float(i)) * h * 0.01, 0.0)
		r = h * lerpf(0.014, 0.032, life) * (0.75 + float(i % 3) * 0.12)
		var bc := col.lightened(0.12)
		ElemArt.circle(n, p, r, Color(bc, bc.a * gain * life * 0.5))
		var hi := col2.lightened(0.55)
		ElemArt.circle(n, p + Vector2(-r * 0.28, -r * 0.3), maxf(0.6, r * 0.38), Color(hi, hi.a * gain * life * 0.8))


## Cristais pontudos na borda e flocos caindo devagar.
static func _ki_gelo(n: CanvasItem, c: Vector2, h: float, col: Color, col2: Color, t: float, gain: float) -> void:
	var side := 1.0
	var sf := 0.0
	var local := Vector2.ZERO
	var outward := Vector2.UP
	var len := 0.0
	var base := Vector2.ZERO
	var tip := Vector2.ZERO
	var q := Vector2.ZERO
	var shade := col.darkened(0.18)
	var lit := col2.lightened(0.35)
	for i in 6:
		side = 1.0 if i < 3 else -1.0
		sf = 0.2 + float(i % 3) * 0.26
		local = _ki_rim(side, sf, h)
		outward = local.normalized()
		len = h * (0.075 + 0.02 * sin(t * 1.4 + float(i) * 1.1))
		base = c + local
		tip = base + outward * len
		q = Vector2(-outward.y, outward.x) * len * 0.34
		ElemArt.poly(n, PackedVector2Array([base, base + q, tip]), Color(shade, shade.a * gain * 0.9))
		ElemArt.poly(n, PackedVector2Array([base, tip, base - q]), Color(lit, lit.a * gain * 0.9))
		n.draw_line(base + outward * len * 0.2, tip, Color(col2.lightened(0.55), col2.a * gain * 0.75), maxf(1.0, h * 0.008), SpellArt.AA)
	var kf := 0.0
	var life := 0.0
	var fc := col2.lightened(0.42)
	for i in 6:
		kf = fposmod(t * (0.16 + float(i) * 0.02) + float(i) * 0.19, 1.0)
		life = sin(kf * PI)
		if life <= 0.05:
			continue
		var fp := c + Vector2(h * (-0.24 + float(i) * 0.09) + sin(t * 0.7 + float(i) * 1.5) * h * 0.02, lerpf(-0.72, 0.42, kf) * h)
		ElemArt.flake(n, fp, h * (0.03 + float(i % 3) * 0.006), t * 0.35 + float(i), Color(fc, fc.a * gain * life * 0.85))


## Correntes curvas em volta do corpo e folhas/riscos rápidos na horizontal.
static func _ki_vento(n: CanvasItem, c: Vector2, h: float, col: Color, col2: Color, t: float, gain: float) -> void:
	var band := col.lightened(0.22)
	var pts := PackedVector2Array()
	var a0 := 0.0
	for i in 3:
		pts = PackedVector2Array()
		a0 = t * (1.55 + float(i) * 0.2) + float(i) * TAU / 3.0
		for s in 8:
			var a := a0 + float(s) * 0.4
			pts.append(c + Vector2(cos(a) * h * 0.26, sin(a) * h * 0.48 + sin(a0 * 0.7) * h * 0.05))
		var al := gain * (0.3 + 0.12 * sin(t * 3.0 + float(i)))
		ElemArt.ribbon(n, pts, maxf(1.4, h * 0.015), maxf(0.3, h * 0.004), Color(band, band.a * al), true)
	var dir := 1.0
	var kf := 0.0
	var life := 0.0
	var p := Vector2.ZERO
	var streak := col2.lightened(0.4)
	for i in 8:
		kf = fposmod(t * (2.2 + float(i % 4) * 0.25) + float(i) * 0.131, 1.0)
		life = sin(kf * PI)
		if life <= 0.05:
			continue
		dir = 1.0 if i % 2 == 0 else -1.0
		p = c + Vector2(dir * lerpf(-0.32, 0.32, kf) * h, lerpf(0.28, -0.62, float(i) / 7.0) * h)
		if i % 3 == 0:
			var leaf_c := col.lightened(0.16)
			ElemArt.leaf(n, p, Vector2(dir, sin(t * 7.0 + float(i)) * 0.35).normalized(), h * 0.044, Color(leaf_c, leaf_c.a * gain * life * 0.85))
		else:
			n.draw_line(p, p + Vector2(dir * h * 0.12, 0.0), Color(streak, streak.a * gain * life * 0.75), maxf(1.0, h * 0.009), SpellArt.AA)


## Raios curtos na borda (a forma troca ~12 vezes por segundo) e faíscas.
static func _ki_raio(n: CanvasItem, c: Vector2, h: float, col: Color, col2: Color, t: float, gain: float) -> void:
	var step := int(floor(t * 12.0))
	var bolt_c := col.lightened(0.22)
	var side := 1.0
	var local := Vector2.ZERO
	var a := Vector2.ZERO
	for i in 5:
		side = 1.0 if i % 2 == 0 else -1.0
		local = _ki_rim(side, 0.14 + fposmod(float(i) * 0.17 + t * 0.35, 0.72), h)
		a = c + local
		var hop := 0.055 + 0.028 * float((step + i * 3) % 4)
		var al := gain * (0.6 + 0.4 * absf(sin(float(step) * 0.9 + float(i) * 1.3)))
		ElemArt.bolt(n, a, a + Vector2(side * h * 0.035, -h * hop), step * 13 + i * 29, maxf(0.8, h * 0.01), al, bolt_c)
	var spark := col2.lightened(0.5)
	var kf := 0.0
	var life := 0.0
	var p := Vector2.ZERO
	for i in 6:
		kf = fposmod(t * (3.2 + float(i % 3) * 0.35) + float(i) * 0.19, 1.0)
		life = sin(kf * PI)
		if life <= 0.08:
			continue
		side = 1.0 if i % 2 == 0 else -1.0
		p = c + _ki_rim(side, 0.18 + float(i) * 0.12, h) + Vector2(side * h * 0.02, -h * 0.03 * kf)
		ElemArt.star(n, p, h * 0.02 * (0.55 + life), Color(spark, spark.a * gain * life), t * 3.0 + float(i))


## Pedrinhas orbitando devagar na base e poeira.
static func _ki_terra(n: CanvasItem, c: Vector2, h: float, col: Color, col2: Color, t: float, gain: float) -> void:
	var ang := 0.0
	var p := Vector2.ZERO
	var rc := col
	for i in 5:
		ang = t * 0.65 + float(i) * TAU / 5.0
		p = c + Vector2(cos(ang) * h * 0.22, h * 0.38 + sin(ang) * h * 0.055)
		rc = col.darkened(0.12) if i % 2 == 0 else col.lightened(0.08)
		ElemArt.boulder(n, p, h * (0.034 + float(i % 3) * 0.008), 1800 + i * 23, ang * 0.8, rc, gain * col.a * 0.95)
	var kf := 0.0
	var life := 0.0
	var dc := col.lightened(0.18).lerp(col2, 0.35)
	for i in 8:
		kf = fposmod(t * (0.28 + float(i % 4) * 0.05) + float(i) * 0.17, 1.0)
		life = sin(kf * PI)
		if life <= 0.05:
			continue
		p = c + Vector2(sin(t * 0.9 + float(i) * 1.4) * h * 0.16, lerpf(0.42, -0.08, kf) * h)
		ElemArt.circle(n, p, h * 0.015 * (1.0 - kf * 0.45), Color(dc, dc.a * gain * life * 0.34))


## Folhas girando para cima e brotos/espinhos na borda.
static func _ki_natureza(n: CanvasItem, c: Vector2, h: float, col: Color, col2: Color, t: float, gain: float) -> void:
	var kf := 0.0
	var life := 0.0
	var ang := 0.0
	var p := Vector2.ZERO
	var lc := col
	for i in 8:
		kf = fposmod(t * (0.42 + float(i % 3) * 0.07) + float(i) * 0.125, 1.0)
		life = sin(kf * PI)
		if life <= 0.05:
			continue
		ang = t * (1.8 + float(i) * 0.15) + float(i) * 1.2
		p = c + Vector2(cos(ang) * h * lerpf(0.05, 0.2, life), lerpf(0.32, -0.7, kf) * h)
		lc = col.lightened(0.16) if i % 2 == 0 else col.darkened(0.18)
		ElemArt.leaf(n, p, Vector2(cos(ang), -0.65).normalized(), h * 0.048, Color(lc, lc.a * gain * life * 0.9))
	var side := 1.0
	var local := Vector2.ZERO
	var outward := Vector2.RIGHT
	var len := 0.0
	var base := Vector2.ZERO
	var tip := Vector2.ZERO
	var tc := col.darkened(0.32)
	for i in 7:
		side = 1.0 if i % 2 == 0 else -1.0
		local = _ki_rim(side, 0.16 + float(i) * 0.1, h)
		outward = Vector2(side, -0.35).normalized()
		len = h * (0.052 + 0.012 * sin(t * 2.2 + float(i) * 1.3))
		base = c + local
		tip = base + outward * len
		var q := Vector2(-outward.y, outward.x) * len * 0.28
		ElemArt.poly(n, PackedVector2Array([base - q, tip, base + q]), Color(tc, tc.a * gain * 0.88))
		if i % 2 == 0:
			var sprout := col2.lightened(0.22)
			ElemArt.leaf(n, tip, outward, h * 0.03, Color(sprout, sprout.a * gain * 0.8))

