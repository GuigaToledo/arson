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

	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.07, 0.05, 0.04, 0.88), Color(0.45, 0.32, 0.18)))
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -340
	panel.offset_right = -10
	panel.offset_top = 64
	root.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = "Equipamento (I)"
	title.add_theme_color_override("font_color", Color(1, 0.7, 0.35))
	top.add_child(title)
	var close := Button.new()
	close.text = "  X  "
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): panel.visible = false)
	top.add_child(close)
	var portrait := TextureRect.new()
	portrait.texture = load("res://assets/ui/retrato_mago.jpg")
	portrait.custom_minimum_size = Vector2(0, 120)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vb.add_child(portrait)
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
	for pair in [["Tirar tudo", _unequip_all]]:
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

	panel.visible = false


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_I:
		panel.visible = not panel.visible


func _cycle(slot: int) -> void:
	var options := ItemDB.for_slot(slot).filter(func(it): return player.owns(String(it.id)) and player.level >= it.level_req)
	var cur := player.equipment.get_item(slot)
	var idx := options.find(cur)
	if idx + 1 < options.size():
		player.try_equip(options[idx + 1])
	else:
		player.equipment.unequip(slot)


func _equip_all() -> void:
	for id in ["capa_lobo_infernal", "saia_lobo_infernal", "luvas_couro", "botas_couro", "cajado_brasa", "escudo_mimico"]:
		player.equipment.equip(ItemDB.get_item(id))


func _unequip_all() -> void:
	for s in EquipSlot.all():
		player.equipment.unequip(s)


func _refresh() -> void:
	for slot in buttons:
		var it := player.equipment.get_item(slot)
		var n_own := ItemDB.for_slot(slot).filter(func(x): return player.owns(String(x.id))).size()
		buttons[slot].text = "%s (%d)\n%s" % [EquipSlot.slot_name(slot), n_own, it.display_name if it else "—"]
		buttons[slot].tooltip_text = _stats_text(it.stats) if it else ""
	var st := _stats_text(player.equipment.total_stats())
	stats_label.text = "Atributos: " + (st if st != "" else "nenhum") + "\nToque num espaço para trocar pelos seus itens (o número é quantos você tem). Itens caem dos monstros e o Brann vende alguns."


func _stats_text(d: Dictionary) -> String:
	var parts := PackedStringArray()
	var nomes := {"vida": "vida", "mana": "mana", "defesa": "defesa", "magia": "% magias", "ataque": "ataque", "velocidade": "% velocidade"}
	for k in d:
		var nm: String = nomes.get(k, "% " + Rules.skill_name(k))
		parts.append("+%d %s" % [d[k], nm])
	return ", ".join(parts)


func toggle() -> void:
	panel.visible = not panel.visible
