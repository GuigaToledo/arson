class_name ItemSlot
extends Button
## Espaço de item desenhado por código: moldura, ícone do item ou do material, quantidade.
## Equipamento: forma pelo espaço (elmo, capa, cajado...), cores do próprio item.
## Saque: forma do material (gota, osso, pele, dente...).

var item: EquipmentItem = null
var loot_id := ""
var count := 0
var slot := -1
var selected := false
var hint := ""


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	custom_minimum_size = Vector2(52, 52)


func set_item(it: EquipmentItem, s: int) -> void:
	item = it
	slot = s
	loot_id = ""
	queue_redraw()


func set_loot(id: String, n: int) -> void:
	loot_id = id
	count = n
	item = null
	queue_redraw()


func _rarity() -> Color:
	if item:
		if String(item.id).begins_with("chefe_"):
			return Color(1, 0.35, 0.2)
		if item.level_req >= 20:
			return Color(0.75, 0.45, 1)
		if item.level_req >= 8:
			return Color(0.35, 0.65, 1)
		return Color(0.6, 0.5, 0.36)
	if loot_id != "":
		return Color(1, 0.55, 0.2) if Loot.preco(loot_id) >= 100 else Color(0.6, 0.5, 0.36)
	return Color(0.36, 0.27, 0.17)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rc := _rarity()
	var sb := UiKit.inner(Color(0.05, 0.035, 0.03), rc if not selected else Color(1, 0.85, 0.45), 6, 0)
	sb.set_border_width_all(2 if selected or item or loot_id != "" else 1)
	sb.shadow_color = Color(0, 0, 0, 0)
	draw_style_box(sb, r)
	# brilho interno da raridade
	if item or loot_id != "":
		draw_circle(size * 0.5, size.x * 0.34, Color(rc, 0.12))
	var c := size * 0.5
	var u := size.x / 52.0
	if item:
		_equip_icon(c, u, item.placeholder_color.lightened(0.15), item.placeholder_accent)
	elif loot_id != "":
		_loot_icon(c, u, Loot.cor(loot_id), Loot.forma(loot_id))
		if count > 1:
			var f := get_theme_default_font()
			var t := str(count)
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string_outline(f, Vector2(size.x - tw - 4, size.y - 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color.BLACK)
			draw_string(f, Vector2(size.x - tw - 4, size.y - 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.95, 0.8))
	elif slot >= 0:
		# silhueta apagada do espaço vazio
		_equip_icon(c, u, Color(0.25, 0.2, 0.15, 0.7), Color(0.3, 0.24, 0.17, 0.7))
	if hint != "" and item == null:
		var f2 := get_theme_default_font()
		var hw := f2.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string(f2, Vector2((size.x - hw) * 0.5, size.y - 3), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.52, 0.4, 0.8))


func _poly(pts: Array, col: Color) -> void:
	var p := PackedVector2Array(pts)
	draw_colored_polygon(p, col)
	p.append(p[0])
	draw_polyline(p, col.darkened(0.55), 1.5, true)


func _equip_icon(c: Vector2, u: float, a: Color, b: Color) -> void:
	match slot:
		EquipSlot.Slot.HEAD:
			_poly([c + Vector2(-14, 8) * u, c + Vector2(0, -16) * u, c + Vector2(14, 8) * u], a)
			draw_rect(Rect2(c + Vector2(-17, 7) * u, Vector2(34, 5) * u), b)
		EquipSlot.Slot.CHEST:
			_poly([c + Vector2(-9, -14) * u, c + Vector2(9, -14) * u, c + Vector2(16, 15) * u, c + Vector2(-16, 15) * u], a)
			draw_line(c + Vector2(0, -12) * u, c + Vector2(0, 14) * u, b, 2.0 * u)
		EquipSlot.Slot.SHOULDERS:
			for sx in [-1, 1]:
				_poly([c + Vector2(sx * 3, -6) * u, c + Vector2(sx * 16, -3) * u, c + Vector2(sx * 17, 8) * u, c + Vector2(sx * 4, 6) * u], a)
			draw_circle(c + Vector2(-10, 1) * u, 2.5 * u, b)
			draw_circle(c + Vector2(10, 1) * u, 2.5 * u, b)
		EquipSlot.Slot.HANDS:
			draw_arc(c, 10 * u, 0, TAU, 24, a, 4.0 * u, true)
			draw_circle(c + Vector2(0, -10) * u, 4.5 * u, b)
		EquipSlot.Slot.LEGS:
			_poly([c + Vector2(-12, -14) * u, c + Vector2(12, -14) * u, c + Vector2(11, 15) * u, c + Vector2(3, 15) * u, c + Vector2(0, -2) * u, c + Vector2(-3, 15) * u, c + Vector2(-11, 15) * u], a)
			draw_rect(Rect2(c + Vector2(-12, -14) * u, Vector2(24, 4) * u), b)
		EquipSlot.Slot.FEET:
			_poly([c + Vector2(-12, -14) * u, c + Vector2(-2, -14) * u, c + Vector2(-2, 6) * u, c + Vector2(14, 8) * u, c + Vector2(14, 14) * u, c + Vector2(-12, 14) * u], a)
			draw_rect(Rect2(c + Vector2(-13, 10) * u, Vector2(28, 4) * u), b)
		EquipSlot.Slot.CAPE:
			_poly([c + Vector2(-8, -15) * u, c + Vector2(8, -15) * u, c + Vector2(17, 15) * u, c + Vector2(0, 11) * u, c + Vector2(-17, 15) * u], a)
			draw_circle(c + Vector2(0, -13) * u, 3.0 * u, b)
		EquipSlot.Slot.MAIN_HAND:
			draw_line(c + Vector2(-12, 16) * u, c + Vector2(9, -9) * u, a.darkened(0.2), 4.0 * u, true)
			draw_circle(c + Vector2(11, -11) * u, 6.0 * u, b)
			draw_circle(c + Vector2(11, -11) * u, 9.0 * u, Color(b, 0.25))
		EquipSlot.Slot.OFF_HAND:
			_poly([c + Vector2(-13, -15) * u, c + Vector2(13, -15) * u, c + Vector2(13, 15) * u, c + Vector2(-13, 15) * u], a)
			draw_rect(Rect2(c + Vector2(-9, -11) * u, Vector2(18, 22) * u), b, false, 2.0 * u)
		EquipSlot.Slot.ACCESSORIES:
			draw_arc(c + Vector2(0, -6) * u, 11 * u, PI * 0.1, PI * 0.9, 16, a, 2.0 * u, true)
			draw_arc(c + Vector2(0, -6) * u, 11 * u, PI * 1.1, PI * 1.9, 16, a, 2.0 * u, true)
			draw_circle(c + Vector2(0, 8) * u, 7.0 * u, b)
			draw_circle(c + Vector2(-2, 6) * u, 2.0 * u, Color(1, 1, 1, 0.6))


func _loot_icon(c: Vector2, u: float, a: Color, f: String) -> void:
	var dk := a.darkened(0.45)
	match f:
		"gota":
			_poly([c + Vector2(0, -16) * u, c + Vector2(10, 2) * u, c + Vector2(7, 11) * u, c + Vector2(0, 14) * u, c + Vector2(-7, 11) * u, c + Vector2(-10, 2) * u], a)
			draw_circle(c + Vector2(-3, 2) * u, 3.0 * u, Color(1, 1, 1, 0.5))
		"osso":
			draw_line(c + Vector2(-10, 10) * u, c + Vector2(10, -10) * u, a, 5.0 * u, true)
			for e in [Vector2(-10, 10), Vector2(10, -10)]:
				draw_circle(c + (e + Vector2(-3, -3)) * u, 4.0 * u, a)
				draw_circle(c + (e + Vector2(3, 3)) * u, 4.0 * u, a)
		"cranio":
			draw_circle(c + Vector2(0, -3) * u, 12.0 * u, a)
			draw_rect(Rect2(c + Vector2(-7, 5) * u, Vector2(14, 9) * u), a)
			draw_circle(c + Vector2(-5, -3) * u, 3.5 * u, Color.BLACK)
			draw_circle(c + Vector2(5, -3) * u, 3.5 * u, Color.BLACK)
		"carne":
			draw_circle(c + Vector2(-2, 0) * u, 11.0 * u, a)
			draw_circle(c + Vector2(-2, 0) * u, 6.0 * u, a.lightened(0.2))
			draw_line(c + Vector2(6, 6) * u, c + Vector2(15, 14) * u, Color(0.9, 0.88, 0.8), 4.0 * u)
		"pano":
			_poly([c + Vector2(-14, -10) * u, c + Vector2(12, -14) * u, c + Vector2(14, 8) * u, c + Vector2(4, 14) * u, c + Vector2(-12, 12) * u], a)
			draw_line(c + Vector2(-8, -4) * u, c + Vector2(8, 2) * u, dk, 1.5 * u)
		"frasco":
			_poly([c + Vector2(-4, -15) * u, c + Vector2(4, -15) * u, c + Vector2(4, -6) * u, c + Vector2(12, 6) * u, c + Vector2(8, 14) * u, c + Vector2(-8, 14) * u, c + Vector2(-12, 6) * u, c + Vector2(-4, -6) * u], Color(0.85, 0.9, 0.95, 0.35))
			_poly([c + Vector2(-10, 4) * u, c + Vector2(10, 4) * u, c + Vector2(8, 12) * u, c + Vector2(-8, 12) * u], a)
		"orelha":
			_poly([c + Vector2(-10, 12) * u, c + Vector2(-6, -4) * u, c + Vector2(14, -14) * u, c + Vector2(4, 6) * u], a)
		"pena":
			_poly([c + Vector2(-12, 14) * u, c + Vector2(4, -6) * u, c + Vector2(13, -15) * u, c + Vector2(8, 0) * u], a)
			draw_line(c + Vector2(-12, 14) * u, c + Vector2(12, -14) * u, dk, 1.5 * u)
		"asa":
			_poly([c + Vector2(-15, -6) * u, c + Vector2(0, -12) * u, c + Vector2(15, -6) * u, c + Vector2(10, 4) * u, c + Vector2(5, 0) * u, c + Vector2(0, 8) * u, c + Vector2(-5, 0) * u, c + Vector2(-10, 4) * u], a)
		"dente":
			_poly([c + Vector2(-6, -14) * u, c + Vector2(6, -14) * u, c + Vector2(2, 15) * u], a)
		"garra":
			for k in 3:
				draw_arc(c + Vector2(-8 + k * 8, 4) * u, 9 * u, PI * 1.1, PI * 1.7, 10, a, 3.5 * u, true)
		"pele":
			_poly([c + Vector2(-14, -10) * u, c + Vector2(-6, -14) * u, c + Vector2(6, -14) * u, c + Vector2(14, -10) * u, c + Vector2(10, 4) * u, c + Vector2(14, 14) * u, c + Vector2(-14, 14) * u, c + Vector2(-10, 4) * u], a)
			draw_circle(c + Vector2(-4, 0) * u, 2.0 * u, dk)
			draw_circle(c + Vector2(5, 5) * u, 2.0 * u, dk)
		"seda":
			for k in 3:
				draw_arc(c, (5 + k * 5) * u, 0, TAU, 20, a, 1.5 * u, true)
			draw_line(c + Vector2(-15, 0) * u, c + Vector2(15, 0) * u, a, 1.2 * u)
			draw_line(c + Vector2(0, -15) * u, c + Vector2(0, 15) * u, a, 1.2 * u)
		"olho":
			draw_circle(c, 12.0 * u, Color(0.95, 0.92, 0.85))
			draw_circle(c, 7.0 * u, a)
			draw_circle(c, 3.0 * u, Color.BLACK)
		"cristal":
			_poly([c + Vector2(0, -16) * u, c + Vector2(9, -4) * u, c + Vector2(6, 14) * u, c + Vector2(-6, 14) * u, c + Vector2(-9, -4) * u], a)
			draw_circle(c, 14.0 * u, Color(a, 0.18))
		"ovo":
			draw_circle(c + Vector2(0, 2) * u, 12.0 * u, a)
			draw_circle(c + Vector2(-4, -3) * u, 3.0 * u, Color(1, 1, 1, 0.5))
		"coroa":
			_poly([c + Vector2(-14, 10) * u, c + Vector2(-14, -8) * u, c + Vector2(-7, 0) * u, c + Vector2(0, -12) * u, c + Vector2(7, 0) * u, c + Vector2(14, -8) * u, c + Vector2(14, 10) * u], a)
			draw_circle(c + Vector2(0, 4) * u, 2.5 * u, Color(1, 0.2, 0.2))
		"saco":
			draw_circle(c + Vector2(0, 4) * u, 12.0 * u, a)
			_poly([c + Vector2(-5, -8) * u, c + Vector2(5, -8) * u, c + Vector2(8, -14) * u, c + Vector2(-8, -14) * u], a)
			draw_string(get_theme_default_font(), c + Vector2(-4, 9) * u, "$", HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * u), dk)
		_:
			_poly([c + Vector2(-12, 4) * u, c + Vector2(-6, -10) * u, c + Vector2(8, -12) * u, c + Vector2(13, 2) * u, c + Vector2(6, 12) * u, c + Vector2(-8, 11) * u], a)
