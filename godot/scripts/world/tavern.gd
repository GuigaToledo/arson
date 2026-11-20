extends Node2D
## Demo da taverna: chão e paredes com textura de pedra real (com relevo),
## lareira e tochas com luz e sombra, móveis com colisão e transparência,
## jogador (Mago das Chamas) e dois NPCs.

const W := 12
const H := 10
const WALL_H := 230.0
const STONE_C := "res://assets/textures/stone_c.jpg"
const STONE_N := "res://assets/textures/stone_n.jpg"

const WOOD := Color(0.40, 0.26, 0.15)
const WOOD_DARK := Color(0.24, 0.15, 0.09)
const STONE := Color(0.40, 0.37, 0.35)

var entities: Node2D
var player: Player


func s(gx: float, gy: float) -> Vector2:
	return Iso.to_screen(Vector2(gx, gy))


func _ready() -> void:
	var cm := CanvasModulate.new()
	cm.color = Color(0.2, 0.16, 0.15)
	add_child(cm)
	_build_floor_and_walls()
	entities = Node2D.new()
	entities.name = "Entidades"
	entities.y_sort_enabled = true
	add_child(entities)
	_build_bounds()
	_build_props()
	_build_lights()
	_spawn_characters()
	var ui := EquipmentPanel.new()
	add_child(ui)
	ui.bind(player)


# ---------------------------------------------------------------- chão e paredes
func _stone_tex() -> CanvasTexture:
	var t := CanvasTexture.new()
	t.diffuse_texture = load(STONE_C)
	t.normal_texture = load(STONE_N)
	t.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return t


func _textured(points: Array, uvs: Array, tint: Color, z: int) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array(points)
	p.uv = PackedVector2Array(uvs)
	p.texture = _stone_tex()
	p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	p.color = tint
	p.z_index = z
	add_child(p)
	return p


func _build_floor_and_walls() -> void:
	var T := 256.0
	_textured([s(0, 0), s(W, 0), s(W, H), s(0, H)],
		[Vector2(0, 0), Vector2(W * T, 0), Vector2(W * T, H * T), Vector2(0, H * T)],
		Color(0.85, 0.78, 0.7), -20)
	var up := Vector2(0, -WALL_H)
	var vt := WALL_H * 3.6
	_textured([s(0, 0) + up, s(W, 0) + up, s(W, 0), s(0, 0)],
		[Vector2(0, 0), Vector2(W * T, 0), Vector2(W * T, vt), Vector2(0, vt)],
		Color(0.62, 0.56, 0.5), -15)
	_textured([s(0, H) + up, s(0, 0) + up, s(0, 0), s(0, H)],
		[Vector2(0, 0), Vector2(H * T, 0), Vector2(H * T, vt), Vector2(0, vt)],
		Color(0.55, 0.5, 0.45), -15)
	var beams := WallBeams.new()
	beams.z_index = -14
	beams.room = Vector2(W, H)
	beams.wall_h = WALL_H
	add_child(beams)


func _build_bounds() -> void:
	var body := StaticBody2D.new()
	var corners := [s(0, 0), s(W, 0), s(W, H), s(0, H)]
	for i in 4:
		var seg := SegmentShape2D.new()
		seg.a = corners[i]
		seg.b = corners[(i + 1) % 4]
		var cs := CollisionShape2D.new()
		cs.shape = seg
		body.add_child(cs)
	add_child(body)


# ---------------------------------------------------------------- móveis
func _prop(kind: String, gp: Vector2, gs: Vector2, h: float, col: Color) -> Prop:
	var p := Prop.new().setup(kind, gp, gs, h, col)
	entities.add_child(p)
	return p


func _build_props() -> void:
	var fp := Prop.new().setup("fireplace", Vector2(5.0, 0.0), Vector2(2.2, 0.7), 150.0, STONE)
	fp.casts_shadow = false
	fp.fade_when_behind = false
	fp.name = "Lareira"
	entities.add_child(fp)
	_add_fire(fp, fp.hearth_point(), 1.0)
	var fl := LightKit.make(Color(1.0, 0.52, 0.18), 1.7, 3.4, true, 0.18)
	fl.position = fp.hearth_point() + Vector2(-18, 22)
	fp.add_child(fl)

	_prop("box", Vector2(1.4, 2.0), Vector2(0.8, 4.5), 58.0, WOOD.darkened(0.15)).name = "Balcao"
	_prop("box", Vector2(0.0, 2.2), Vector2(0.35, 3.5), 140.0, WOOD_DARK).name = "Prateleira"
	for b in [Vector2(10.3, 0.35), Vector2(11.1, 0.6), Vector2(10.6, 1.3), Vector2(0.4, 8.6)]:
		_prop("barrel", b, Vector2(0.7, 0.7), 54.0, Color(0.36, 0.22, 0.12))
	_prop("crate", Vector2(11.0, 2.2), Vector2(0.8, 0.8), 46.0, Color(0.42, 0.3, 0.17))
	for t in [Vector2(4.0, 3.6), Vector2(8.2, 3.0), Vector2(7.2, 6.6), Vector2(3.6, 7.2)]:
		_prop("table", t, Vector2(1.5, 0.9), 34.0, WOOD)
		_prop("bench", t + Vector2(0, 1.0), Vector2(1.5, 0.35), 20.0, WOOD.darkened(0.1))
		_prop("bench", t + Vector2(0, -0.5), Vector2(1.5, 0.35), 20.0, WOOD.darkened(0.1))
	for pl in [Vector2(6.2, 4.9), Vector2(9.6, 5.3)]:
		_prop("box", pl, Vector2(0.35, 0.35), 270.0, WOOD_DARK).name = "Pilar"


func _add_fire(parent: Node2D, at: Vector2, size: float) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.92, 0.6, 1.0))
	g.set_color(1, Color(0.6, 0.08, 0.02, 0.0))
	g.add_point(0.4, Color(1.0, 0.45, 0.1, 0.8))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var p := CPUParticles2D.new()
	p.amount = int(44 * size)
	p.lifetime = 0.8
	p.preprocess = 1.0
	p.texture = LightKit.radial()
	p.material = mat
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(14, 3) * size
	p.direction = Vector2(0, -1)
	p.spread = 15.0
	p.gravity = Vector2(0, -50)
	p.initial_velocity_min = 15.0 * size
	p.initial_velocity_max = 40.0 * size
	p.scale_amount_min = 0.05 * size
	p.scale_amount_max = 0.12 * size
	p.color_ramp = g
	p.position = at
	parent.add_child(p)
	var e := CPUParticles2D.new()
	e.amount = int(10 * size)
	e.lifetime = 2.0
	e.texture = LightKit.radial()
	e.material = mat
	e.direction = Vector2(0, -1)
	e.spread = 30.0
	e.gravity = Vector2(0, -25)
	e.initial_velocity_min = 20.0
	e.initial_velocity_max = 50.0
	e.scale_amount_min = 0.01
	e.scale_amount_max = 0.02
	e.color = Color(1, 0.6, 0.2)
	e.position = at
	parent.add_child(e)


# ---------------------------------------------------------------- luzes
func _build_lights() -> void:
	var torches := [[s(0, 2.0), true], [s(0, 7.5), true], [s(9.0, 0), false]]
	for t in torches:
		var tn := WallTorch.new()
		tn.position = t[0] + Vector2(0, -125)
		tn.z_index = -10
		add_child(tn)
		_add_fire(tn, Vector2(0, -6), 0.35)
		var l := LightKit.make(Color(1.0, 0.6, 0.25), 1.0, 2.0, t[1], 0.22)
		l.position = Vector2(0, 90)
		tn.add_child(l)
	for c in [Vector2(4.8, 4.0), Vector2(8.0, 6.0)]:
		var ch := Chandelier.new()
		ch.position = Iso.to_screen(c)
		ch.z_index = 10
		add_child(ch)
		var l := LightKit.make(Color(1.0, 0.72, 0.4), 0.8, 2.6, false, 0.08)
		ch.add_child(l)


# ---------------------------------------------------------------- personagens
func _spawn_characters() -> void:
	player = Player.new()
	player.name = "Jogador"
	player.position = s(6.5, 8.2)
	entities.add_child(player)

	var barkeep := Npc.new().configure(
		{"skin": Color(0.62, 0.48, 0.38), "under": Color(0.35, 0.28, 0.22), "hair": Color(0.45, 0.3, 0.15), "eyes": Color(0.2, 0.15, 0.1)},
		["avental_taverna", "calca_tecido", "botas_couro"], "SE")
	barkeep.name = "Taverneira"
	barkeep.position = s(0.75, 4.0)
	entities.add_child(barkeep)

	var pts := []
	for g in [Vector2(5.5, 6.0), Vector2(6.5, 8.8), Vector2(10.6, 8.6), Vector2(10.8, 4.6), Vector2(10.2, 2.1), Vector2(7.0, 2.1)]:
		pts.append(Iso.to_screen(g))
	var patron := Npc.new().configure(
		{"skin": Color(0.5, 0.38, 0.3), "under": Color(0.2, 0.17, 0.14), "hair": Color(0.15, 0.1, 0.07), "eyes": Color(0.2, 0.15, 0.1)},
		["gibao_verde", "calca_tecido", "botas_couro", "capa_viagem"], "S", pts)
	patron.name = "Viajante"
	patron.position = pts[0]
	entities.add_child(patron)


# ---------------------------------------------------------------- peças desenhadas (provisórias)
class WallBeams:
	extends Node2D
	var room := Vector2.ONE
	var wall_h := 200.0

	func _draw() -> void:
		var col := Color(0.16, 0.1, 0.06)
		var top := Vector2(0, -wall_h)
		var o := Iso.to_screen(Vector2.ZERO)
		var r := Iso.to_screen(Vector2(room.x, 0))
		var l := Iso.to_screen(Vector2(0, room.y))
		for pair in [[o, r], [o, l]]:
			draw_line(pair[0] + top, pair[1] + top, col, 10.0)
			draw_line(pair[0] + top * 0.55, pair[1] + top * 0.55, col, 6.0)
			draw_line(pair[0], pair[1], col.lightened(0.05), 5.0)
		for i in range(0, int(room.x) + 1, 3):
			var b := Iso.to_screen(Vector2(i, 0))
			draw_line(b, b + top, col, 8.0)
		for i in range(3, int(room.y) + 1, 3):
			var b := Iso.to_screen(Vector2(0, i))
			draw_line(b, b + top, col, 8.0)


class WallTorch:
	extends Node2D

	func _draw() -> void:
		draw_line(Vector2(0, 14), Vector2(0, -2), Color(0.2, 0.17, 0.15), 3.0)
		draw_line(Vector2(-4, 10), Vector2(0, 16), Color(0.2, 0.17, 0.15), 2.0)
		draw_rect(Rect2(-3, -6, 6, 6), Color(0.28, 0.18, 0.1))


class Chandelier:
	extends Node2D
	const LIFT := 165.0

	func _draw() -> void:
		var c := Vector2(0, -LIFT)
		draw_line(c, c + Vector2(0, -400), Color(0.12, 0.1, 0.09), 1.5)
		_ring(c)

	func _ring(c: Vector2) -> void:
		var pts := PackedVector2Array()
		for i in 25:
			var a := TAU * i / 24.0
			pts.append(c + Vector2(cos(a) * 30.0, sin(a) * 13.0))
		draw_polyline(pts, Color(0.2, 0.16, 0.13), 3.0)
		for i in 8:
			var a := TAU * i / 8.0
			var p := c + Vector2(cos(a) * 30.0, sin(a) * 13.0)
			draw_line(p, p + Vector2(0, -8), Color(0.9, 0.85, 0.72), 2.5)
			draw_circle(p + Vector2(0, -11), 2.2, Color(1, 0.8, 0.4))
			draw_circle(p + Vector2(0, -11), 4.5, Color(1, 0.6, 0.2, 0.25))
