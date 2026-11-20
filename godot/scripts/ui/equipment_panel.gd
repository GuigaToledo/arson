class_name EquipmentPanel
extends CanvasLayer
## Painel de equipamento no layout do Tibia. Tocar num slot troca para o
## próximo item compatível; depois do último, o slot fica vazio.

const S := EquipSlot.Slot
## Grade 3x4 como no Tibia (colar, elmo, mochila / arma, armadura, escudo ...).
const LAYOUT := [
	EquipSlot.Slot.ACCESSORIES, EquipSlot.Slot.HEAD, EquipSlot.Slot.CAPE,
	EquipSlot.Slot.MAIN_HAND, EquipSlot.Slot.CHEST, EquipSlot.Slot.OFF_HAND,
	EquipSlot.Slot.HANDS, EquipSlot.Slot.LEGS, EquipSlot.Slot.SHOULDERS,
	-1, EquipSlot.Slot.FEET, -1,
]

var player: Player
var panel: PanelContainer
var buttons: Dictionary = {}
var stats_label: Label


func bind(p: Player) -> void:
	player = p
	_build()
	player.equipment.equipment_changed.connect(func(_s, _i): _refresh())
	_refresh()


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var toggle := Button.new()
	toggle.text = "Equipamento"
	toggle.add_theme_font_size_override("font_size", 15)
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toggle.offset_left = -160
	toggle.offset_right = -10
	toggle.offset_top = 10
	toggle.offset_bottom = 50
	toggle.pressed.connect(func(): panel.visible = not panel.visible)
	root.add_child(toggle)

	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.07, 0.05, 0.04, 0.88), Color(0.45, 0.32, 0.18)))
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -340
	panel.offset_right = -10
	panel.offset_top = 58
	root.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Mago das Chamas — equipamento"
	title.add_theme_color_override("font_color", Color(1, 0.7, 0.35))
	vb.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	vb.add_child(grid)
	for slot in LAYOUT:
		if slot == -1:
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(98, 50)
			grid.add_child(sp)
			continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(98, 50)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _style(Color(0.13, 0.1, 0.08), Color(0.3, 0.22, 0.14)))
		b.add_theme_stylebox_override("hover", _style(Color(0.2, 0.14, 0.1), Color(0.6, 0.4, 0.2)))
		b.add_theme_stylebox_override("pressed", _style(Color(0.25, 0.12, 0.06), Color(1, 0.55, 0.2)))
		b.pressed.connect(_cycle.bind(slot))
		grid.add_child(b)
		buttons[slot] = b
	var row := HBoxContainer.new()
	vb.add_child(row)
	for pair in [["Vestir tudo", _equip_all], ["Tirar tudo", _unequip_all]]:
		var b := Button.new()
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(pair[1])
		row.add_child(b)
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.custom_minimum_size = Vector2(300, 0)
	vb.add_child(stats_label)

	panel.visible = not DisplayServer.is_touchscreen_available()


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_I:
		panel.visible = not panel.visible


func _cycle(slot: int) -> void:
	var options := ItemDB.for_slot(slot)
	var cur := player.equipment.get_item(slot)
	var idx := options.find(cur)
	if idx + 1 < options.size():
		player.equipment.equip(options[idx + 1])
	else:
		player.equipment.unequip(slot)


func _equip_all() -> void:
	for id in ["capuz_aprendiz", "tunica_aprendiz", "ombreiras_ferro", "luvas_couro", "calca_tecido",
			"botas_couro", "capa_viagem", "cajado_brasa", "escudo_mimico", "amuleto_nucleo"]:
		player.equipment.equip(ItemDB.get_item(id))


func _unequip_all() -> void:
	for s in EquipSlot.all():
		player.equipment.unequip(s)


func _refresh() -> void:
	for slot in buttons:
		var it := player.equipment.get_item(slot)
		buttons[slot].text = "%s\n%s" % [EquipSlot.slot_name(slot), it.display_name if it else "—"]
		buttons[slot].tooltip_text = _stats_text(it.stats) if it else ""
	var st := _stats_text(player.equipment.total_stats())
	stats_label.text = "Atributos: " + (st if st != "" else "nenhum")


func _stats_text(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in d:
		parts.append("%s +%d" % [k, d[k]])
	return ", ".join(parts)
