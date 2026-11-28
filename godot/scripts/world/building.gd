class_name Building
extends Node
## Prédio entrável: piso e paredes dos fundos (embaixo de tudo), parede da frente + telhado em
## tiras ordenadas pela profundidade (somem quando o jogador entra), paredes com colisão, porta
## que abre e móveis sem colisão. Arte gerada por ferramentas/desenhar_interiores.py.

const OBJ := "res://assets/objetos/"
const TW_T := 0.27          # espessura da parede em tiles (0,42 m)
const DOOR_W := 1.7         # largura do vão da porta em tiles
const PX_M := 46.0          # pixels por metro na vertical
const PORTAS := {"casa_a": 3.2, "casa_b": 3.8, "loja": 6.2, "ferraria": 6.2, "guilda": 6.0, "templo": 5.5, "salao": 8.0}
const TIRA := 64.0          # largura (px) de cada tira da frente

var id := ""
var tipo := ""
var rect := Rect2()
var og := Vector2.ZERO
var door_u := 3.0
var isl: Node2D
var door: Node2D
var _tiras: Array = []
var _fade := 1.0
var _open := 0.0
var _lights: Array = []

static var _layout := {}
static var _anchors := {}


static func layout(tipo_: String) -> Dictionary:
	if _layout.is_empty():
		var p = JSON.parse_string(FileAccess.get_file_as_string("res://data/interiores.json"))
		_layout = p if p is Dictionary else {"_": {}}
	return _layout.get(tipo_, {})


static func anchor(nm: String) -> Array:
	if _anchors.is_empty():
		var p = JSON.parse_string(FileAccess.get_file_as_string(OBJ + "ancoras.json"))
		_anchors = p if p is Dictionary else {"_": 0}
	var a = _anchors.get(nm)
	return a if a is Array else [0.0, 0.0]


## Ponto (em tiles) onde o morador do prédio fica.
func npc_spot() -> Vector2:
	var n: Array = layout(tipo).get("npc", [rect.size.x * 0.5, rect.size.y * 0.5])
	return og + Vector2(float(n[0]), float(n[1]))


func build(island: Node2D, fundos: Node2D, ents: Node2D) -> void:
	isl = island
	og = rect.position
	door_u = float(PORTAS.get(tipo, rect.size.x * 0.5))
	name = "Predio_" + id
	_build_fundo(fundos)
	_build_frente(ents)
	_build_walls()
	_build_door(ents)
	_build_decor(ents)


func _grid(p: Vector2) -> Vector2:
	return Iso.to_screen(og + p)


func _build_fundo(fundos: Node2D) -> void:
	var nm := tipo + "_fundo"
	var tex: Texture2D = load(OBJ + nm + ".png")
	if tex == null:
		return
	var a := anchor(nm)
	var s := float(a[2]) if a.size() > 2 else 0.5
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = false
	sp.scale = Vector2(s, s)
	sp.offset = -Vector2(float(a[0]), float(a[1]))
	sp.position = Iso.to_screen(og)
	sp.name = "Fundo_" + id
	fundos.add_child(sp)


class Tira extends Node2D:
	var tex: Texture2D
	var src := Rect2()
	var dst := Rect2()

	func _draw() -> void:
		draw_texture_rect_region(tex, dst, src)


func _build_frente(ents: Node2D) -> void:
	var nm := tipo + "_frente"
	var tex: Texture2D = load(OBJ + nm + ".png")
	if tex == null:
		return
	var a := anchor(nm)
	var s := float(a[2]) if a.size() > 2 else 0.5
	var o := Iso.to_screen(og)
	var top_left := o - Vector2(float(a[0]), float(a[1])) * s
	var size := tex.get_size() * s
	var w := rect.size.x
	var h := rect.size.y
	var n := int(ceil(size.x / TIRA))
	for i in n:
		var x0 := top_left.x + i * TIRA
		var wd := minf(TIRA, top_left.x + size.x - x0)
		var sxc := x0 + wd * 0.5 - o.x
		var sum_rel := sxc / 64.0 + 2.0 * h if sxc <= (w - h) * 64.0 else 2.0 * w - sxc / 64.0
		var t := Tira.new()
		t.tex = tex
		t.position = Vector2(x0 + wd * 0.5, o.y + sum_rel * 32.0)
		t.dst = Rect2(-wd * 0.5 - 0.4, top_left.y - t.position.y, wd + 0.8, size.y)
		t.src = Rect2((x0 - top_left.x - 0.4) / s, 0, (wd + 0.8) / s, tex.get_height())
		t.name = "Frente_%s_%d" % [id, i]
		ents.add_child(t)
		_tiras.append(t)


func _poly(body: StaticBody2D, x0: float, y0: float, x1: float, y1: float) -> void:
	var cp := CollisionPolygon2D.new()
	cp.polygon = PackedVector2Array([_grid(Vector2(x0, y0)), _grid(Vector2(x1, y0)), _grid(Vector2(x1, y1)), _grid(Vector2(x0, y1))])
	body.add_child(cp)


func _build_walls() -> void:
	var w := rect.size.x
	var h := rect.size.y
	var body := StaticBody2D.new()
	body.name = "Paredes_" + id
	_poly(body, 0, 0, w, TW_T)
	_poly(body, 0, 0, TW_T, h)
	_poly(body, w - TW_T, 0, w, h)
	var d0 := door_u - DOOR_W * 0.5
	var d1 := door_u + DOOR_W * 0.5
	_poly(body, 0, h - TW_T, d0, h)
	_poly(body, d1, h - TW_T, w, h)
	isl.add_child(body)


## Folhas da porta (duas) que giram para dentro quando o jogador chega perto.
class Porta extends Node2D:
	var og := Vector2.ZERO
	var u := 3.0
	var hy := 0.0
	var open := 0.0

	func _p(gx: float, gy: float, z: float) -> Vector2:
		return Iso.to_screen(og + Vector2(gx, gy)) - position + Vector2(0, -z)

	func _leaf(hx: float, dirx: float) -> void:
		var lw := Building.DOOR_W * 0.5
		var a := open * 1.65
		var tx := hx + dirx * lw * cos(a)
		var ty := hy - lw * sin(a)
		var hgt := 2.38 * Building.PX_M
		var q := PackedVector2Array([_p(hx, hy, 0), _p(tx, ty, 0), _p(tx, ty, hgt), _p(hx, hy, hgt)])
		var sh := 0.78 + 0.22 * cos(a * 0.9)
		draw_colored_polygon(q, Color(0.34, 0.21, 0.1) * Color(sh, sh, sh, 1.0))
		for k in [0.25, 0.5, 0.75]:
			var gx := lerpf(hx, tx, k)
			var gy := lerpf(hy, ty, k)
			draw_line(_p(gx, gy, 2.0), _p(gx, gy, hgt - 2.0), Color(0.16, 0.09, 0.04, 0.8), 1.4)
		for z in [0.28, 0.72]:
			draw_line(_p(hx, hy, hgt * z), _p(tx, ty, hgt * z), Color(0.1, 0.1, 0.11), 3.0)
		draw_circle((_p(hx, hy, hgt * 0.45) * 0.28 + _p(tx, ty, hgt * 0.45) * 0.72), 2.2, Color(0.75, 0.62, 0.3))
		draw_polyline(PackedVector2Array([_p(hx, hy, 0), _p(tx, ty, 0), _p(tx, ty, hgt), _p(hx, hy, hgt), _p(hx, hy, 0)]), Color(0.12, 0.07, 0.03), 2.0)

	func _draw() -> void:
		var d0 := u - Building.DOOR_W * 0.5
		var d1 := u + Building.DOOR_W * 0.5
		_leaf(d0, 1.0)
		_leaf(d1, -1.0)


func _build_door(ents: Node2D) -> void:
	door = Porta.new()
	var d := door as Porta
	d.og = og
	d.u = door_u
	d.hy = rect.size.y - TW_T * 0.5
	d.position = Iso.to_screen(og + Vector2(door_u, d.hy + 0.02))
	d.name = "Porta_" + id
	ents.add_child(d)


func _build_decor(ents: Node2D) -> void:
	var lay := layout(tipo)
	for m in lay.get("moveis", []):
		var nm: String = m[0]
		var tex: Texture2D = load(OBJ + nm + ".png")
		if tex == null:
			continue
		var a := anchor(nm)
		var corner := og + Vector2(float(m[1]), float(m[2]))
		var center := corner + Vector2(float(m[3]), float(m[4])) * 0.5
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.scale = Vector2(0.5, 0.5)
		sp.position = Iso.to_screen(center)
		sp.offset = (Iso.to_screen(corner) - sp.position) / 0.5 - Vector2(float(a[0]), float(a[1]))
		sp.name = "Deco_" + nm
		ents.add_child(sp)
	var cores := {"fogo": [Color(1.0, 0.55, 0.22), 1.1, 1.8], "sala": [Color(1.0, 0.8, 0.5), 0.75, 2.2], "vela": [Color(1.0, 0.75, 0.4), 0.8, 1.9]}
	for l in lay.get("luzes", []):
		var c: Array = cores.get(str(l[2]), cores["sala"])
		var li := LightKit.make(c[0], c[1], c[2], false, 0.12)
		li.range_item_cull_mask = 3
		li.position = Iso.to_screen(og + Vector2(float(l[0]), float(l[1]))) + Vector2(0, -60)
		isl.add_child(li)


func _process(delta: float) -> void:
	var pl = isl.get("player")
	if pl == null or not is_instance_valid(pl):
		return
	var gp: Vector2 = Iso.to_grid(pl.global_position)
	var inside := gp.x > og.x + 0.1 and gp.x < og.x + rect.size.x - 0.1 and gp.y > og.y + 0.1 and gp.y < og.y + rect.size.y - 0.05
	var f := move_toward(_fade, 0.0 if inside else 1.0, delta * 3.5)
	if f != _fade:
		_fade = f
		for t: Tira in _tiras:
			t.modulate.a = _fade
			t.visible = _fade > 0.01
	var dc := og + Vector2(door_u, rect.size.y)
	var near := gp.distance_to(dc) < 2.2
	var o := move_toward(_open, 1.0 if near else 0.0, delta * 2.6)
	if o != _open:
		_open = o
		(door as Porta).open = _open
		door.queue_redraw()
