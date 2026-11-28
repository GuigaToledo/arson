class_name Gate
extends Node2D
## Portão da muralha: duas folhas de madeira com ferro que abrem para dentro da cidade quando
## o jogador chega perto, e viga de pedra por cima. Fechado, bloqueia a passagem.

const PX_M := 46.0
const LEAF_H := 3.0   # metros
const LINTEL_H := 3.5

var rect := Rect2()         # vão em tiles (4x1 ou 1x4)
var inward := Vector2(0, 1) # direção para dentro da cidade
var isl: Node2D
var open := 0.0
var _body: StaticBody2D
var _cp: CollisionPolygon2D
var horiz := true
var _center := Vector2.ZERO


func build(island: Node2D, ents: Node2D) -> void:
	isl = island
	horiz = rect.size.x > rect.size.y
	_center = rect.position + rect.size * 0.5
	position = Iso.to_screen(_center)
	name = "Portao"
	ents.add_child(self)
	_body = StaticBody2D.new()
	_cp = CollisionPolygon2D.new()
	var r := rect.grow_individual(0, 0, 0, 0)
	if horiz:
		r = Rect2(rect.position.x, _center.y - 0.15, rect.size.x, 0.3)
	else:
		r = Rect2(_center.x - 0.15, rect.position.y, 0.3, rect.size.y)
	_cp.polygon = PackedVector2Array([Iso.to_screen(r.position), Iso.to_screen(Vector2(r.end.x, r.position.y)), Iso.to_screen(r.end), Iso.to_screen(Vector2(r.position.x, r.end.y))])
	_body.add_child(_cp)
	island.add_child(_body)


func _p(g: Vector2, z: float) -> Vector2:
	return Iso.to_screen(g) - position + Vector2(0, -z * PX_M)


func _leaf(hinge: Vector2, along: Vector2, sw: Vector2) -> void:
	var lw := 2.0
	var a := open * 1.5
	var tip := hinge + along * lw * cos(a) + sw * lw * sin(a)
	var sh := 0.8 + 0.2 * cos(a)
	var q := PackedVector2Array([_p(hinge, 0), _p(tip, 0), _p(tip, LEAF_H), _p(hinge, LEAF_H)])
	draw_colored_polygon(q, Color(0.3, 0.19, 0.09) * Color(sh, sh, sh, 1.0))
	for k in range(1, 8):
		var g := hinge.lerp(tip, k / 8.0)
		draw_line(_p(g, 0.05), _p(g, LEAF_H - 0.05), Color(0.13, 0.08, 0.04, 0.85), 1.4)
	for z in [0.5, 1.5, 2.5]:
		draw_line(_p(hinge, z), _p(tip, z), Color(0.1, 0.1, 0.12), 3.5)
		for k in range(1, 6):
			draw_circle(_p(hinge.lerp(tip, k / 6.0), z), 1.5, Color(0.55, 0.5, 0.4))
	draw_polyline(PackedVector2Array([_p(hinge, 0), _p(tip, 0), _p(tip, LEAF_H), _p(hinge, LEAF_H), _p(hinge, 0)]), Color(0.1, 0.06, 0.03), 2.0)


func _lintel() -> void:
	var th := 1.0
	var a: Vector2
	var b: Vector2
	var c: Vector2
	var d: Vector2
	if horiz:
		a = rect.position
		b = Vector2(rect.end.x, rect.position.y)
		c = Vector2(rect.end.x, rect.position.y + th)
		d = Vector2(rect.position.x, rect.position.y + th)
	else:
		a = rect.position
		b = Vector2(rect.position.x + th, rect.position.y)
		c = Vector2(rect.position.x + th, rect.end.y)
		d = Vector2(rect.position.x, rect.end.y)
	var z0 := LEAF_H + 0.05
	var z1 := LINTEL_H
	var stone := Color(0.3, 0.29, 0.27)
	# face da frente (+y) ou do lado direito (+x), e o topo
	if horiz:
		draw_colored_polygon(PackedVector2Array([_p(d, z0), _p(c, z0), _p(c, z1), _p(d, z1)]), stone.darkened(0.15))
	else:
		draw_colored_polygon(PackedVector2Array([_p(b, z0), _p(c, z0), _p(c, z1), _p(b, z1)]), stone.darkened(0.3))
	draw_colored_polygon(PackedVector2Array([_p(a, z1), _p(b, z1), _p(c, z1), _p(d, z1)]), stone.lightened(0.1))
	var n := 8
	for i in range(1, n):
		var t := i / float(n)
		if horiz:
			draw_line(_p(d.lerp(c, t), z0), _p(d.lerp(c, t), z1), Color(0.2, 0.19, 0.18, 0.7), 1.2)
		else:
			draw_line(_p(b.lerp(c, t), z0), _p(b.lerp(c, t), z1), Color(0.2, 0.19, 0.18, 0.7), 1.2)


func _draw() -> void:
	if horiz:
		var yc := _center.y
		var s := Vector2(0, inward.y)
		_leaf(Vector2(rect.position.x, yc), Vector2(1, 0), s)
		_leaf(Vector2(rect.end.x, yc), Vector2(-1, 0), s)
	else:
		var xc := _center.x
		var s2 := Vector2(inward.x, 0)
		_leaf(Vector2(xc, rect.position.y), Vector2(0, 1), s2)
		_leaf(Vector2(xc, rect.end.y), Vector2(0, -1), s2)
	_lintel()


func _process(delta: float) -> void:
	var pl = isl.get("player")
	if pl == null or not is_instance_valid(pl):
		return
	var gp: Vector2 = Iso.to_grid(pl.global_position)
	var near := gp.distance_to(_center) < 4.2
	var o := move_toward(open, 1.0 if near else 0.0, delta * 1.6)
	if o != open:
		open = o
		_cp.set_deferred("disabled", open > 0.55)
		queue_redraw()
