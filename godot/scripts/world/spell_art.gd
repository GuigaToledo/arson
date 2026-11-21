class_name SpellArt
extends RefCounted
## Visual de cada magia, condizente com o nome: Pedrada lança uma pedra em arco, Espinho lança
## espinhos, Raízes brotam do chão, Tornado gira, Tempestade de Raios cai do céu, etc.
## Tudo desenhado por código (sem imagens), com gravidade nas partículas.

const RX := 90.5  # raio de 1 tile na tela (semieixo x da elipse isométrica)
## Melhorias da magia sendo lançada (0 a 5): mais partículas e efeitos extras.
static var boost := 0
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
		queue_redraw()

	func _draw() -> void:
		fn.call(self, t / life)


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
	p.amount = maxi(1, int(amount * (1.0 + 0.25 * boost)))
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
	n.draw_colored_polygon(pts, col)


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
	n.draw_polygon(pts, cols)


static func ellipse(n: CanvasItem, c: Vector2, rx: float, col: Color, filled := true, w := 2.0) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * rx * 0.5))
	if filled:
		poly(n, pts, col)
	else:
		n.draw_polyline(pts, col, w, SpellArt.AA)


## Polígono de pedra irregular (mesmo formato para a mesma semente).
static func rock(n: CanvasItem, c: Vector2, r: float, col: Color, sd: int, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		var a := TAU * i / 7.0 + rot
		var h := fposmod(sin(float(sd) * 12.9898 + i * 78.233) * 43758.5453, 1.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r * (0.7 + h * 0.35))
	poly(n, pts, col)
	n.draw_polyline(pts + PackedVector2Array([pts[0]]), col.darkened(0.45), 1.2, SpellArt.AA)
	n.draw_line(c + Vector2(-r * 0.3, -r * 0.4), c + Vector2(r * 0.25, -r * 0.5), col.lightened(0.35), 1.2)


static func jag(n: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, segs := 7, amp := 9.0) -> void:
	var pts := PackedVector2Array([a])
	for k in range(1, segs):
		pts.append(a.lerp(b, float(k) / segs) + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)))
	pts.append(b)
	n.draw_polyline(pts, Color(col, col.a * 0.35), w * 3.0, SpellArt.AA)
	n.draw_polyline(pts, col, w, SpellArt.AA)
	n.draw_polyline(pts, Color(1, 1, 1, col.a), maxf(1.0, w * 0.4), SpellArt.AA)


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
		n.draw_polyline(pts, col.darkened(0.3), w + 1.5, SpellArt.AA)
		n.draw_polyline(pts, col, w, SpellArt.AA)
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
## Língua de fogo tremulando: base no chão, ponta para cima. Camadas vermelha, laranja e amarela.
static func flame(n: CanvasItem, base: Vector2, h: float, w: float, t: float, sd: float, a := 1.0) -> void:
	if h < 2.0 or a <= 0.01:
		return
	var sway := sin(t * 7.0 + sd * 3.1) * w * 0.35 + sin(t * 13.0 + sd) * w * 0.15
	for layer in 3:
		var k: float = [1.0, 0.68, 0.38][layer]
		var col: Color = [Color(0.9, 0.18, 0.02, 0.55 * a), Color(1, 0.5, 0.08, 0.75 * a), Color(1, 0.88, 0.45, 0.9 * a)][layer]
		var hh := h * k * (0.9 + 0.1 * sin(t * 17.0 + sd * 5.0 + layer))
		var ww := w * k
		var tip := base + Vector2(sway * k, -hh)
		var pts := PackedVector2Array()
		for i in 7:
			var f := i / 6.0
			var bulge := sin(f * PI) * ww * (1.0 - f * 0.55)
			pts.append(base.lerp(tip, f) + Vector2(-bulge + sway * f * f * 0.5, 0) + Vector2(0, -sin(f * PI) * 0.0))
		for i in range(6, -1, -1):
			var f := i / 6.0
			var bulge := sin(f * PI) * ww * (1.0 - f * 0.55)
			pts.append(base.lerp(tip, f) + Vector2(bulge + sway * f * f * 0.5, 0))
		n.draw_colored_polygon(pts, col)


## Várias chamas espalhadas numa elipse (chão em chamas). g = altura 0..1.
static func flames_in(n: CanvasItem, rx: float, count: int, h: float, t: float, g: float, a: float, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var arr := []
	for i in count:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * rx
		arr.append([Vector2(cos(ang) * r, sin(ang) * r * 0.5), rng.randf_range(0.6, 1.2), rng.randf() * 10.0])
	arr.sort_custom(func(p, q): return p[0].y < q[0].y)
	for e in arr:
		flame(n, e[0], h * e[1] * g, 7.0 + 5.0 * e[1], t, e[2], a)


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
	n.draw_colored_polygon(edge, Color(0.16, 0.05, 0.03, 0.95 * a))
	n.draw_colored_polygon(molten, Color(0.95, 0.28, 0.03, a))
	# manchas de magma mais quente deslizando
	for i in 6:
		var ang := rng.randf() * TAU + t * (0.25 + rng.randf() * 0.3)
		var r := rng.randf_range(0.1, 0.55) * rx
		var p := c + Vector2(cos(ang) * r, sin(ang) * r * ry_k)
		n.draw_set_transform(p, 0.0, Vector2(1, ry_k))
		n.draw_circle(Vector2.ZERO, rx * rng.randf_range(0.12, 0.22), Color(1, 0.62 + 0.15 * sin(t * 3.0 + i), 0.12, 0.85 * a))
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
		n.draw_colored_polygon(pl, Color(0.22, 0.07, 0.04, 0.9 * a))
	# veios brilhando
	for i in 4:
		var p0 := c + Vector2(rng.randf_range(-0.6, 0.6) * rx, rng.randf_range(-0.25, 0.25) * rx)
		var pts := PackedVector2Array([p0])
		for j in 3:
			p0 += Vector2(rng.randf_range(-0.25, 0.25) * rx, rng.randf_range(-0.1, 0.1) * rx)
			pts.append(p0)
		n.draw_polyline(pts, Color(1, 0.9, 0.45, (0.5 + 0.5 * sin(t * 4.0 + i)) * a), 2.0)
	# bolhas que incham e estouram
	for i in 5:
		var p := c + Vector2(rng.randf_range(-0.55, 0.55) * rx, rng.randf_range(-0.22, 0.22) * rx)
		var b := fmod(t * (0.8 + rng.randf() * 0.6) + rng.randf(), 1.0)
		if b < 0.75:
			n.draw_circle(p + Vector2(0, -b * 4.0), 2.0 + b * 6.0, Color(1, 0.55 + b * 0.35, 0.15, a))
			n.draw_arc(p + Vector2(-1, -b * 4.0 - 1), 1.5 + b * 4.0, PI * 1.1, PI * 1.6, 6, Color(1, 1, 0.8, 0.7 * a), 1.2)
		else:
			var q := (b - 0.75) / 0.25
			for j in 4:
				var d := Vector2(cos(j * 1.6 + i), -1.0).normalized() * q * 14.0
				n.draw_circle(p + d + Vector2(0, q * q * 10.0), 1.8 * (1.0 - q), Color(1, 0.7, 0.2, a))


## Respingo de lava: gotas em arco que caem e deixam pingos no chão.
static func lava_splash(parent: Node, pos: Vector2, count: int, spread: float) -> void:
	var drops := []
	for i in count:
		drops.append([Vector2(randf_range(-1, 1), randf_range(-0.5, 0.5)) * spread, randf_range(30, 80), randf_range(2.5, 5.0)])
	fxn(parent, pos, 0.7, func(n: DrawFx, k: float):
		for d in drops:
			var p: Vector2 = d[0] * k + Vector2(0, -sin(k * PI) * d[1] - 30.0 * (1.0 - k))
			n.draw_circle(p, d[2], Color(0.95, 0.35, 0.05))
			n.draw_circle(p + Vector2(-1, -1), d[2] * 0.5, Color(1, 0.85, 0.4)))
	parent.get_tree().create_timer(0.7).timeout.connect(func():
		if not is_instance_valid(parent):
			return
		for d in drops:
			var at: Vector2 = pos + d[0]
			var sz: float = d[2]
			fxg(parent, at, 2.5, func(n: DrawFx, k: float):
				n.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
				n.draw_circle(Vector2.ZERO, sz * 1.6, Color(0.15, 0.05, 0.03, 0.8 * (1.0 - k)))
				n.draw_circle(Vector2.ZERO, sz * 1.1, Color(1, 0.4 * (1.0 - k) + 0.1, 0.05, 1.0 - k))
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
		var h := 44.0
		if el == "terra":
			h = 44.0 + sin(k * PI) * minf(120.0, to.length() * 0.35)
		global_position = p
		_light.position = Vector2(0, -h)
		_trail.push_front(Vector2(0, -h) + global_position)
		if _trail.size() > 9:
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
			draw_colored_polygon(PackedVector2Array([L[i][0], L[i + 1][0], R[i + 1][0], R[i][0]]), Color(col, col.a * f))
			draw_colored_polygon(PackedVector2Array([L[i][1], L[i + 1][1], R[i + 1][1], R[i][1]]), Color(col2, col2.a * f))

	func _draw() -> void:
		var c: Vector2 = _trail[0] - global_position if _trail.size() > 0 else Vector2(0, -44)
		var dir := (_last - _from).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var s := 1.8 if big else 1.0
		for bt in _bits:
			SpellArt.bit(self, el, bt[0] - global_position, float(bt[4]), float(bt[2]) / float(bt[3]))
		match el:
			"fogo":
				_tail(9.0 * s, Color(0.95, 0.25, 0.03, 0.55), Color(1, 0.75, 0.25, 0.7))
				draw_set_transform(c, (-dir).angle() + PI * 0.5, Vector2.ONE * s)
				for j in 3:
					SpellArt.flame(self, Vector2((j - 1) * 4.0, 4.0), 30.0 - absf(j - 1) * 9.0, 7.0, _t, j * 2.3)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				SpellArt.poly(self, PackedVector2Array([c + dir * 9 * s, c + nrm * 6 * s, c - dir * 6 * s, c - nrm * 6 * s]), Color(1, 0.7, 0.2))
				SpellArt.poly(self, PackedVector2Array([c + dir * 6 * s, c + nrm * 3 * s, c - dir * 3 * s, c - nrm * 3 * s]), Color(1, 0.95, 0.7))
			"lava":
				_tail(7.0 * s, Color(0.35, 0.08, 0.03, 0.9), Color(1, 0.42, 0.06, 0.95))
				SpellArt.lava(self, c, 9.0 * s, _t * 2.0, 7, 1.0, 0.8)
			"agua":
				_tail(7.0 * s, Color(0.2, 0.5, 1.0, 0.55), Color(0.75, 0.92, 1.0, 0.8))
				SpellArt.poly(self, PackedVector2Array([c + dir * 10 * s, c + nrm * 5 * s, c - dir * 6 * s, c - nrm * 5 * s]), Color(0.6, 0.85, 1.0, 0.95))
			"gelo":
				_tail(6.0 * s, Color(0.7, 0.9, 1.0, 0.3), Color(1, 1, 1, 0.35))
				var tip := c + dir * 16 * s
				SpellArt.poly(self, PackedVector2Array([tip, c + nrm * 5 * s, c - dir * 12 * s, c - nrm * 5 * s]), Color(0.75, 0.92, 1, 0.95))
				draw_line(c - dir * 11 * s, tip, Color(1, 1, 1), 1.5, SpellArt.AA)
			"vento":
				for i in 4:
					var off := nrm * (i - 1.5) * 6.0 * s
					var pts := PackedVector2Array()
					for j in 8:
						var f := j / 7.0
						pts.append(c + off - dir * f * 46.0 * s + nrm * sin(_t * 18.0 + f * 5.0 + i) * 4.0)
					draw_polyline(pts, Color(0.85, 1, 0.95, 0.7 - absf(i - 1.5) * 0.15), 2.0, SpellArt.AA)
				var a0 := dir.angle() - 1.2
				draw_arc(c, 12 * s, a0, a0 + 2.4, 16, Color(0.9, 1, 0.97, 0.9), 3.0, SpellArt.AA)
			"terra":
				SpellArt.rock(self, c, 9 * s, Color(0.45, 0.38, 0.3), 3, _t * 9.0)
			"natureza":
				for i in 3:
					var b: Vector2 = c + nrm * (i - 1) * 7 - dir * absf(i - 1) * 8
					SpellArt.thorn(self, b - dir * 14, b + dir * 9, 2.5, Color(0.25, 0.55, 0.15))
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
			n.draw_arc(p, 5.0, rot, rot + 1.8, 6, Color(0.9, 1, 0.95, 0.7 * a), 1.2)
		_:
			pass


static func projectile(parent: Node, from: Vector2, target: Node2D, el: String, big: bool, els: Array, on_hit: Callable) -> void:
	if el == "raio":
		var b := fx(parent, Vector2.ZERO, 0.35, func(n: DrawFx, k: float):
			if is_instance_valid(target):
				jag(n, from + Vector2(0, -50), target.global_position + Vector2(0, -40), Color(0.85, 0.85, 1, 1.0 - k), 3.0 if big else 2.0, 9, 12.0))
		_no(parent, target.global_position + Vector2(0, -40), cor("raio"), 2.0, 1.0, 0.3)
		parent.get_tree().create_timer(0.05).timeout.connect(on_hit)
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
	pr.speed = 380.0 if el == "terra" else 560.0
	pr.global_position = from
	parent.add_child(pr)


## Impacto no alvo, na cara do elemento.
static func impact(parent: Node, pos: Vector2, el: String, big := false) -> void:
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
				n.draw_arc(Vector2.ZERO, (10 + i * 8) * (0.5 + k) * s, k * 6 + i, k * 6 + i + 2.2, 14, Color(0.85, 1, 0.95, 1.0 - k), 2.0, SpellArt.AA))
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
static func cc(parent: Node, center: Vector2, radius: float, el: String) -> void:
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
					n.draw_polyline(pts, Color(0.5, 0.8, 1, a * 0.8), 3.0, SpellArt.AA))
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
					n.draw_polyline(pts, Color(0.08, 0.06, 0.04, a), 3.0, SpellArt.AA))
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
static func cone(parent: Node, pos: Vector2, dir: Vector2, length_px: float, half_ang: float, el: String) -> void:
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
				n.draw_polyline(pts, Color(0.3, 0.55, 1, 0.55 * (1.0 - k * 0.5)), 16.0, SpellArt.AA)
				n.draw_polyline(pts, Color(0.85, 0.95, 1, 1.0 - k * 0.5), 4.0, SpellArt.AA))
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
					n.draw_polyline(pts, Color(0.2, 0.4, 0.1, 1.0 - maxf(0, k - 0.7) / 0.3), 4.0, SpellArt.AA)
					n.draw_polyline(pts, Color(0.4, 0.75, 0.25, 1.0 - maxf(0, k - 0.7) / 0.3), 2.0, SpellArt.AA))
		_:
			SpellFx.cone(parent, pos, dir, length_px, half_ang, c.lightened(0.4), c)


static func line(parent: Node, a: Vector2, b: Vector2, el: String) -> void:
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
					n.draw_circle(d * f, 4.0, Color(1, 0.85, 0.4, al * 0.8)))
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
					n.draw_polyline(pts, Color(0.05, 0.03, 0.02, al), 7.0, SpellArt.AA)
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
static func area(parent: Node, center: Vector2, radius: float, el: String, on_impact: Callable, els := []) -> void:
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
					n.draw_circle(p + Vector2(sin(k * 10 + i) * 6, y), 2.0 if not fused else 3.5, Color(1, 1, 1, 0.85))
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
					n.draw_arc(Vector2(sin(k * 6 + i * 0.3) * 6, y), r, t, t + 4.0, 20, Color(0.85, 1, 0.95, 0.55 * a), 2.5, SpellArt.AA)
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
		n.draw_circle(q, 7, col)
		n.draw_circle(q, 3.5, Color(1, 1, 0.9)))
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
static func light(parent: Node, kind: String, pos: Vector2) -> void:
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
					n.draw_circle(Vector2(cos(t), sin(t) * 0.5) * RX * 2.7, 3.0, Color(1, 1, 0.8, a)))
		"bless":  # halo subindo
			fx(parent, pos, 1.0, func(n: DrawFx, k: float):
				_no(n, Vector2(0, -80 - k * 30), 14, Color(1, 0.95, 0.6, 1.0 - k), false, 3.0))
		"brave":  # chamas douradas
			parts(parent, pos + Vector2(0, -30), 40, 60.0, 1.0, 0.07, Color(1, 0.95, 0.6), Color(1, 0.6, 0.1), -150.0)
		"veil":  # cintilar
			parts(parent, pos + Vector2(0, -40), 30, 40.0, 0.9, 0.04, Color(1, 1, 1), Color(0.7, 0.8, 1), 0.0)
