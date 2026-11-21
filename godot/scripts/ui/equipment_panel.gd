class_name EquipmentPanel
extends CanvasLayer
## Inventário (tecla I ou botão Bolsa): equipamento à esquerda no layout do Tibia,
## saque das criaturas à direita. Fica no meio da tela, livre do joystick e dos botões
## de ataque, e o jogo continua por trás. Tocar num espaço de equipamento troca pelo
## próximo item seu; tocar num material mostra o nome e o preço no Brann.

const LAYOUT := [
	EquipSlot.Slot.ACCESSORIES, EquipSlot.Slot.HEAD, EquipSlot.Slot.CAPE,
	EquipSlot.Slot.MAIN_HAND, EquipSlot.Slot.CHEST, EquipSlot.Slot.OFF_HAND,
	EquipSlot.Slot.HANDS, EquipSlot.Slot.LEGS, EquipSlot.Slot.SHOULDERS,
	-1, EquipSlot.Slot.FEET, -1,
]
const HINTS := {0: "elmo", 1: "peito", 2: "ombros", 3: "anel", 4: "calça", 5: "botas", 6: "capa", 7: "arma", 8: "mão", 9: "colar"}
const LOOT_COLS := 6

var player: Player
var panel: PanelContainer
var buttons: Dictionary = {}
var loot_slots: Array[ItemSlot] = []
var stats_label: Label
var info_label: Label
var gold_label: Label
var loot_title: Label
var _sel_loot := ""


func bind(p: Player) -> void:
	player = p
	_build()
	player.equipment.equipment_changed.connect(func(_s, _i): _refresh())
	get_viewport().size_changed.connect(_place)
	_refresh()


func _build() -> void:
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.06, 0.045, 0.035, 0.96)))
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	vb.add_child(top)
	var title := UiKit.title("Inventário", 19)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	gold_label = UiKit.label("", 15, Color(1, 0.85, 0.35), true)
	top.add_child(gold_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	top.add_child(gap)
	var close := UiKit.button("✕", toggle, 16, true)
	close.custom_minimum_size = Vector2(40, 34)
	top.add_child(close)
	vb.add_child(UiKit.sep())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	vb.add_child(body)

	# equipamento
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UiKit.inner(Color(0.09, 0.065, 0.05), Color(0.34, 0.25, 0.15), 8, 8))
	body.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(UiKit.label("Equipado", 13, UiKit.DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	lv.add_child(grid)
	for slot in LAYOUT:
		if slot == -1:
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(52, 52)
			grid.add_child(sp)
			continue
		var b := ItemSlot.new()
		b.slot = slot
		b.hint = HINTS.get(slot, "")
		b.pressed.connect(_cycle.bind(slot))
		grid.add_child(b)
		buttons[slot] = b
	var off := UiKit.button("Tirar tudo", _unequip_all, 13)
	off.custom_minimum_size = Vector2(0, 32)
	lv.add_child(off)

	# saque
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", UiKit.inner(Color(0.09, 0.065, 0.05), Color(0.34, 0.25, 0.15), 8, 8))
	body.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	loot_title = UiKit.label("Saque", 13, UiKit.DIM)
	rv.add_child(loot_title)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(LOOT_COLS * 46 + 4, 4 * 46)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sc)
	var lg := GridContainer.new()
	lg.columns = LOOT_COLS
	lg.add_theme_constant_override("h_separation", 4)
	lg.add_theme_constant_override("v_separation", 4)
	sc.add_child(lg)
	for i in Loot.SLOTS:
		var s := ItemSlot.new()
		s.custom_minimum_size = Vector2(42, 42)
		s.pressed.connect(_pick_loot.bind(i))
		lg.add_child(s)
		loot_slots.append(s)

	info_label = UiKit.label("", 13, Color(1, 0.92, 0.75))
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info_label)
	stats_label = UiKit.label("", 12, UiKit.DIM)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(stats_label)
	panel.visible = false
	_place()


func _place() -> void:
	if panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var r := UiKit.center_rect(vp, Vector2(560, 400))
	panel.position = r.position
	panel.size = Vector2(r.size.x, 0)
	panel.custom_minimum_size = Vector2(r.size.x, 0)


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_I:
		toggle()


func toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_place()
		_refresh()


func _cycle(slot: int) -> void:
	var options := ItemDB.for_slot(slot).filter(func(it): return player.owns(String(it.id)) and player.level >= it.level_req)
	var cur := player.equipment.get_item(slot)
	var idx := options.find(cur)
	if idx + 1 < options.size():
		player.try_equip(options[idx + 1])
	else:
		player.equipment.unequip(slot)
	var it := player.equipment.get_item(slot)
	_sel_loot = ""
	if it:
		info_label.text = "%s  ·  nv %d\n%s" % [it.display_name, it.level_req, _stats_text(it.stats)]
	else:
		var n_own := ItemDB.for_slot(slot).filter(func(x): return player.owns(String(x.id))).size()
		info_label.text = "%s vazio  ·  você tem %d item(ns) para este espaço" % [EquipSlot.slot_name(slot), n_own]
	_refresh()


func _pick_loot(i: int) -> void:
	var ids := _loot_list()
	if i >= ids.size():
		_sel_loot = ""
		info_label.text = "Espaço livre. Materiais caem das criaturas (elites e chefes deixam mais)."
	else:
		_sel_loot = ids[i][0]
		var q := int(player.loot.get(_sel_loot, 0))
		info_label.text = "%s  ·  %d unid.  ·  %d ouro cada no Brann (total %d)" % [Loot.nome(_sel_loot), q, Loot.preco(_sel_loot), q * Loot.preco(_sel_loot)]
	_refresh()


## Pilhas do saque em ordem (uma pilha por espaço, até 100 cada).
func _loot_list() -> Array:
	var out := []
	var keys := player.loot.keys()
	keys.sort_custom(func(a, b): return Loot.preco(str(a)) > Loot.preco(str(b)))
	for k in keys:
		var q := int(player.loot[k])
		while q > 0:
			out.append([str(k), mini(q, Loot.STACK)])
			q -= Loot.STACK
	return out


func _unequip_all() -> void:
	for s in EquipSlot.all():
		player.equipment.unequip(s)


func _refresh() -> void:
	if panel == null or not panel.visible:
		return
	for slot in buttons:
		var it := player.equipment.get_item(slot)
		buttons[slot].set_item(it, slot)
		buttons[slot].tooltip_text = (it.display_name + "\n" + _stats_text(it.stats)) if it else EquipSlot.slot_name(slot)
	var ids := _loot_list()
	var total := 0
	for k in player.loot:
		total += int(player.loot[k]) * Loot.preco(str(k))
	for i in loot_slots.size():
		var s := loot_slots[i]
		if i < ids.size():
			s.set_loot(ids[i][0], ids[i][1])
			s.selected = ids[i][0] == _sel_loot
			s.tooltip_text = Loot.nome(ids[i][0])
		else:
			s.set_loot("", 0)
			s.selected = false
		s.queue_redraw()
	loot_title.text = "Saque  %d/%d  ·  vale %d ouro" % [player.loot_slots_used(), Loot.SLOTS, total]
	gold_label.text = "%d ouro" % player.gold
	var st := _stats_text(player.equipment.total_stats())
	stats_label.text = "Atributos: " + (st if st != "" else "nenhum") + "  ·  Toque num espaço para trocar de item."
	if info_label.text == "":
		info_label.text = "Venda o saque com o Brann, na vila."


func _process(_d: float) -> void:
	# o saque e o ouro mudam enquanto você caça com a bolsa aberta
	if panel and panel.visible and Engine.get_process_frames() % 20 == 0:
		_refresh()


func _stats_text(d: Dictionary) -> String:
	var parts := PackedStringArray()
	var nomes := {"vida": "vida", "mana": "mana", "defesa": "defesa", "magia": "% magias", "ataque": "ataque", "velocidade": "% velocidade"}
	for k in d:
		var nm: String = nomes.get(k, "% " + Rules.skill_name(k))
		parts.append("+%d %s" % [d[k], nm])
	return ", ".join(parts)
