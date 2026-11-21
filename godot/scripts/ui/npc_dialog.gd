class_name NpcDialog
extends CanvasLayer
## Conversa com os NPCs da vila: Brann (poções) e Lira (cura e tarefas). Como na versão 3D.

const GOLD := Color(0.92, 0.82, 0.6)
const DIM := Color(0.72, 0.66, 0.58)
const POTION_PRICE := 20
## Tarefas por faixa de nível: [até o nível, monstro, quantidade].
const TASKS := [[5, "esqueleto", 10], [10, "carnical", 12], [18, "bandido", 15], [28, "cultista", 15], [99999, "golem", 8]]

static var inst: NpcDialog
var player: Player
var npc: Npc
var _box: PanelContainer
var _col: VBoxContainer


func _enter_tree() -> void:
	inst = self
	layer = 3


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	return sb


func _lbl(t: String, size := 16, col := GOLD) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	return l


func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_stylebox_override("normal", _style(Color(0.14, 0.09, 0.05), Color(0.55, 0.4, 0.22)))
	b.add_theme_stylebox_override("hover", _style(Color(0.24, 0.14, 0.06), Color(0.8, 0.58, 0.3)))
	b.add_theme_stylebox_override("pressed", _style(Color(0.38, 0.15, 0.05), Color(0.95, 0.62, 0.3)))
	b.pressed.connect(cb)
	return b


func open(n: Npc, p: Player) -> void:
	npc = n
	player = p
	if _box:
		_box.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", _style(Color(0.06, 0.045, 0.035, 0.96), Color(0.62, 0.45, 0.24)))
	center.add_child(_box)
	_box.tree_exited.connect(center.queue_free)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 10)
	_box.add_child(_col)
	_render("")


func close() -> void:
	if _box:
		_box.queue_free()
		_box = null
	npc = null


func is_open() -> bool:
	return _box != null


func _row(btns: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for b in btns:
		h.add_child(b)
	return h


func _render(say: String) -> void:
	for c in _col.get_children():
		c.queue_free()
	_col.add_child(_lbl(npc.display_name, 22, Color(1, 0.75, 0.35)))
	var nm := player.display_name if player.display_name != "" else Chars.nome
	if npc.role == "mercador":
		_col.add_child(_lbl("Olá, %s! Poções fresquinhas, %d de ouro cada. Você tem %d de ouro." % [nm, POTION_PRICE, player.gold]))
		_col.add_child(_lbl("Poções: %d de vida · %d de mana" % [player.hp_pot, player.mp_pot], 14, DIM))
		_col.add_child(_row([_btn("Vida ×1", func(): _buy("hp", 1)), _btn("Vida ×5", func(): _buy("hp", 5)), _btn("Vida ×20", func(): _buy("hp", 20))]))
		_col.add_child(_row([_btn("Mana ×1", func(): _buy("mp", 1)), _btn("Mana ×5", func(): _buy("mp", 5)), _btn("Mana ×20", func(): _buy("mp", 20))]))
	else:
		var t := ""
		var tk: Dictionary = player.task
		if not tk.is_empty():
			var mn: String = Monster.TYPES[tk.type].name
			t = ("Você completou a tarefa contra %s!" % mn) if int(tk.count) >= int(tk.need) else ("Tarefa: %d/%d %s." % [tk.count, tk.need, mn])
		_col.add_child(_lbl("Que a luz te guarde, %s. %s" % [nm, t]))
		var tlabel := "Pedir tarefa"
		if not tk.is_empty():
			tlabel = "Receber recompensa" if int(tk.count) >= int(tk.need) else "Ver tarefa"
		_col.add_child(_row([_btn("Curar", _cure), _btn(tlabel, _task)]))
	if say != "":
		_col.add_child(_lbl("“%s”" % say, 15, Color(1, 0.92, 0.75)))
	_col.add_child(_btn("Fechar", close))


func _buy(kind: String, q: int) -> void:
	var cost := q * POTION_PRICE
	if player.gold < cost:
		_render("Isso custa %d de ouro, e você só tem %d." % [cost, player.gold])
		return
	player.gold -= cost
	if kind == "hp":
		player.hp_pot += q
	else:
		player.mp_pot += q
	player.save()
	_render("Aqui estão %d poção(ões) de %s. Boa caçada!" % [q, "vida" if kind == "hp" else "mana"])


func _cure() -> void:
	player.hp = player.max_hp
	player.mp = player.max_mp
	SpellFx.heal(player.get_parent(), player.global_position)
	_render("Suas feridas se fecham e sua mente clareia.")


func _task() -> void:
	var tk: Dictionary = player.task
	if tk.is_empty():
		for row in TASKS:
			if player.level < int(row[0]):
				player.task = {"type": row[1], "need": row[2], "count": 0}
				break
		var mn: String = Monster.TYPES[player.task.type].name
		player.save()
		_render("Elimine %d %s e volte aqui." % [player.task.need, mn])
	elif int(tk.count) >= int(tk.need):
		var mt: Dictionary = Monster.TYPES[tk.type]
		var xp := int(round(float(mt.xp) * int(tk.need) * 1.5))
		var g := int(tk.need) * int(mt.gold[1])
		player.task = {}
		player.gain_xp(xp, g, "Lira")
		player.save()
		_render("Muito bem! Tome %d de experiência e %d de ouro." % [xp, g])
	else:
		_render("Você já eliminou %d de %d %s. Continue!" % [tk.count, tk.need, Monster.TYPES[tk.type].name])


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if is_open() and k and k.pressed and k.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
