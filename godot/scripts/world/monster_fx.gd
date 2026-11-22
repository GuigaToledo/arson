class_name MonsterFx
extends Node2D
## Efeitos rápidos das habilidades dos monstros: onda no chão (anel que se abre)
## e feixe entre dois corpos (dreno de vida).

var kind := "ring"
var color := Color.WHITE
var radius := 1.0  # em tiles
var dur := 0.5
var a: Node2D
var b: Node2D
var _t := 0.0


static func ring(parent: Node, pos: Vector2, r_tiles: float, col: Color, d := 0.5) -> void:
	var f := MonsterFx.new()
	f.kind = "ring"
	f.color = col
	f.radius = r_tiles
	f.dur = d
	f.global_position = pos
	f.z_index = -4
	parent.add_child(f)


static func beam(parent: Node, from: Node2D, to: Node2D, col: Color, d := 0.5) -> void:
	var f := MonsterFx.new()
	f.kind = "beam"
	f.color = col
	f.a = from
	f.b = to
	f.dur = d
	f.z_index = 3
	parent.add_child(f)


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


func _process(delta: float) -> void:
	_t += delta
	if _t >= dur:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / dur
	var al := 1.0 - k
	if kind == "ring":
		var rx := radius * 90.0 * (0.35 + 0.65 * k)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
		ElemArt.arc(self, Vector2.ZERO, rx, 0, TAU, 40, Color(color, al), 5.0 * al + 1.0)
		ElemArt.arc(self, Vector2.ZERO, rx * 0.8, 0, TAU, 40, Color(color, al * 0.5), 2.0)
		ElemArt.circle(self, Vector2.ZERO, rx * 0.6, Color(color, al * 0.12))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif kind == "beam":
		if not is_instance_valid(a) or not is_instance_valid(b):
			return
		var p0 := a.global_position + Vector2(0, -40) - global_position
		var p1 := b.global_position + Vector2(0, -40) - global_position
		var pts := PackedVector2Array()
		for i in 9:
			var t := i / 8.0
			var n := (p1 - p0).orthogonal().normalized() * sin(t * PI * 3.0 + _t * 30.0) * 5.0 * sin(t * PI)
			pts.append(p0.lerp(p1, t) + n)
		ElemArt.polyline(self, pts, Color(color, al * 0.5), 6.0)
		ElemArt.polyline(self, pts, Color(color.lightened(0.4), al), 2.0)
