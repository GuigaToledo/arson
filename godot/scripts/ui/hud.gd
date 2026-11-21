class_name Hud
extends CanvasLayer
## Controles pensados para o celular (e que também funcionam no PC):
## - joystick à esquerda embaixo (ou toque no chão para andar)
## - botão grande de Bola de Fogo e botão de Correr à direita embaixo
## - retrato com vida e mana no canto superior esquerdo
## - menu (Menu, Equipamento, Chat, Tela cheia) no canto superior direito

const EMU := InputEvent.DEVICE_ID_EMULATION
const MOUSE_JOY := 999

var player: Player
var net: NetSync
var panel: EquipmentPanel
var bars: StatusBars
var joystick: Joystick
var fire_btn: RoundButton
var run_btn: RoundButton
var chat_log: Label
var chat_input: LineEdit
var rotate_msg: Label
var names: NameTags
var spellbar: SpellBar
var skill_panel: SkillPanel
var game_menu: GameMenu
var _joy_idx := -1
var _lines: PackedStringArray = PackedStringArray()


func bind(p: Player, n: NetSync, eq_panel: EquipmentPanel = null) -> void:
	player = p
	net = n
	panel = eq_panel
	_build()
	net.chat_received.connect(_on_chat)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _menu_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(78, 40)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(0.92, 0.82, 0.6))
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.06, 0.05, 0.85) if st != "pressed" else Color(0.3, 0.12, 0.05, 0.9)
		sb.border_color = Color(0.5, 0.38, 0.22)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	return b


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	names = NameTags.new()
	names.set_anchors_preset(Control.PRESET_FULL_RECT)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(names)

	bars = StatusBars.new()
	bars.position = Vector2(8, 8)
	bars.size = Vector2(280, 84)
	bars.portrait = load("res://assets/ui/retrato_mago.jpg")
	root.add_child(bars)

	var menu := HBoxContainer.new()
	menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu.offset_right = -8
	menu.offset_top = 8
	menu.add_theme_constant_override("separation", 6)
	root.add_child(menu)
	menu.add_child(_menu_btn("Menu", func(): if game_menu: game_menu.toggle()))
	menu.add_child(_menu_btn("Equip.", _toggle_panel))
	menu.add_child(_menu_btn("Chat", _open_chat))
	menu.add_child(_menu_btn("Tela cheia", _fullscreen))

	joystick = Joystick.new()
	joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick.offset_left = 10
	joystick.offset_top = -190
	joystick.offset_right = 190
	joystick.offset_bottom = -10
	joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(joystick)

	fire_btn = RoundButton.new()
	fire_btn.text = "Bola de\nfogo"
	fire_btn.color = Color(0.75, 0.22, 0.05)
	fire_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fire_btn.offset_left = -128
	fire_btn.offset_top = -128
	fire_btn.offset_right = -18
	fire_btn.offset_bottom = -18
	root.add_child(fire_btn)

	run_btn = RoundButton.new()
	run_btn.text = "Correr"
	run_btn.color = Color(0.35, 0.3, 0.22)
	run_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	run_btn.offset_left = -200
	run_btn.offset_top = -88
	run_btn.offset_right = -138
	run_btn.offset_bottom = -26
	root.add_child(run_btn)

	skill_panel = SkillPanel.new()
	skill_panel.player = player
	skill_panel.position = Vector2(8, 96)
	skill_panel.size = Vector2(200, 46)
	root.add_child(skill_panel)

	# barra de magias e poções (teclas 1-6 / Numpad, Q e E; também tocável)
	spellbar = SpellBar.new()
	spellbar.player = player
	spellbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spellbar.offset_left = -211
	spellbar.offset_right = 211
	spellbar.offset_top = -58
	spellbar.offset_bottom = -10
	root.add_child(spellbar)

	chat_log = _label(13, Color(0.95, 0.9, 0.6))
	chat_log.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	chat_log.offset_left = -220
	chat_log.offset_right = 220
	chat_log.offset_top = -220
	chat_log.offset_bottom = -110
	chat_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	chat_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(chat_log)

	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Escreva e aperte Enter"
	chat_input.max_length = 120
	chat_input.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	chat_input.offset_left = -220
	chat_input.offset_right = 220
	chat_input.offset_top = -104
	chat_input.offset_bottom = -66
	chat_input.visible = false
	chat_input.text_submitted.connect(_on_submit)
	root.add_child(chat_input)

	rotate_msg = _label(26, Color(1, 0.75, 0.4))
	rotate_msg.text = "Vire o celular\npara a horizontal"
	rotate_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotate_msg.set_anchors_preset(Control.PRESET_CENTER)
	rotate_msg.visible = false
	root.add_child(rotate_msg)


# ------------------------------------------------------------ toque e mouse
func _input(ev: InputEvent) -> void:
	if player == null:
		return
	var st := ev as InputEventScreenTouch
	if st:
		if st.pressed:
			if _start(st.position, st.index):
				get_viewport().set_input_as_handled()
		elif st.index == _joy_idx:
			_release_joy()
			get_viewport().set_input_as_handled()
		return
	var sd := ev as InputEventScreenDrag
	if sd:
		if sd.index == _joy_idx:
			_move_joy(sd.position)
			get_viewport().set_input_as_handled()
		return
	var mb := ev as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.device == EMU:
			if mb.pressed and _over_controls(mb.position):
				get_viewport().set_input_as_handled()
			return
		if mb.pressed and _start(mb.position, MOUSE_JOY):
			get_viewport().set_input_as_handled()
		elif not mb.pressed and _joy_idx == MOUSE_JOY:
			_release_joy()
			get_viewport().set_input_as_handled()
		return
	var mm := ev as InputEventMouseMotion
	if mm:
		if mm.device == EMU and _joy_idx >= 0:
			get_viewport().set_input_as_handled()
		elif mm.device != EMU and _joy_idx == MOUSE_JOY:
			_move_joy(mm.position)
			get_viewport().set_input_as_handled()


func _over_controls(pos: Vector2) -> bool:
	return joystick.hit(pos) or fire_btn.hit(pos) or run_btn.hit(pos) or spellbar.slot_at(pos) >= 0


func _start(pos: Vector2, idx: int) -> bool:
	var si := spellbar.slot_at(pos)
	if si >= 0:
		if si < Player.SPELLS.size():
			player.cast_slot(si)
		elif si == Player.SPELLS.size():
			player.use_pot("hp")
		else:
			player.use_pot("mp")
		return true
	if fire_btn.hit(pos):
		fire_btn.flash()
		player.cast_at()
		return true
	if run_btn.hit(pos):
		player.run_toggle = not player.run_toggle
		run_btn.active = player.run_toggle
		run_btn.queue_redraw()
		return true
	if joystick.hit(pos) and _joy_idx == -1:
		_joy_idx = idx
		_move_joy(pos)
		return true
	return false


func _move_joy(pos: Vector2) -> void:
	player.joy = joystick.set_point(pos)
	player.target = null


func _release_joy() -> void:
	_joy_idx = -1
	joystick.reset()
	player.joy = Vector2.ZERO


func _process(_d: float) -> void:
	if player == null:
		return
	var online := ("%d online%s" % [net.online_count, " · anfitrião" if net.is_host else ""]) if net.enabled else ""
	bars.hp = player.hp / player.max_hp
	bars.mp = player.mp / player.max_mp
	bars.title = "%s · nível %d" % [player.display_name if player.display_name != "" else MageClass.info(player.classe).nome, player.level]
	var a := Rules.xp_to_reach(player.level)
	var b := Rules.xp_to_reach(player.level + 1)
	bars.xp = float(player.xp - a) / float(maxi(1, b - a))
	bars.gold = player.gold
	bars.sub = "%s %s" % [net.status, online]
	CombatText.step(get_process_delta_time())
	names.foe = player.foe
	spellbar.queue_redraw()
	skill_panel.queue_redraw()
	bars.queue_redraw()
	fire_btn.enabled = player.mp >= Player.CAST_COST
	fire_btn.queue_redraw()
	var vs := get_viewport().get_visible_rect().size
	rotate_msg.visible = vs.y > vs.x * 1.1
	names.queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_K and get_viewport().gui_get_focus_owner() == null:
		skill_panel.visible = not skill_panel.visible
		get_viewport().set_input_as_handled()
		return
	if k and k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and not chat_input.visible:
		_open_chat()
		get_viewport().set_input_as_handled()


func _toggle_panel() -> void:
	if panel:
		panel.toggle()


func _open_chat() -> void:
	chat_input.visible = true
	chat_input.grab_focus()


func _on_submit(text: String) -> void:
	text = text.strip_edges()
	if text != "":
		net.say(text)
	chat_input.text = ""
	chat_input.release_focus()
	chat_input.visible = false


func _on_chat(who: String, text: String) -> void:
	_lines.append("%s: %s" % [who, text])
	while _lines.size() > 5:
		_lines.remove_at(0)
	chat_log.text = "\n".join(_lines)


func _fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Joystick virtual: base redonda e "pino" que segue o dedo.
class Joystick:
	extends Control
	const R := 62.0
	var knob := Vector2.ZERO

	func center() -> Vector2:
		return get_global_rect().get_center()

	func hit(pos: Vector2) -> bool:
		return pos.distance_to(center()) < R * 1.6

	func set_point(pos: Vector2) -> Vector2:
		knob = (pos - center()).limit_length(R)
		queue_redraw()
		return knob / R

	func reset() -> void:
		knob = Vector2.ZERO
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, R, Color(0, 0, 0, 0.35))
		draw_arc(c, R, 0, TAU, 48, Color(0.85, 0.7, 0.45, 0.5), 2.5)
		for a in 4:
			var d := Vector2.RIGHT.rotated(a * PI / 2) * (R - 10)
			draw_circle(c + d, 3, Color(0.85, 0.7, 0.45, 0.4))
		draw_circle(c + knob, 26, Color(0.55, 0.42, 0.28, 0.85))
		draw_arc(c + knob, 26, 0, TAU, 32, Color(1, 0.85, 0.55, 0.8), 2.0)


## Botão redondo de ação.
class RoundButton:
	extends Control
	var text := ""
	var color := Color.RED
	var active := false
	var enabled := true
	var _flash := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func hit(pos: Vector2) -> bool:
		var r := get_global_rect()
		return pos.distance_to(r.get_center()) < r.size.x * 0.55

	func flash() -> void:
		_flash = 1.0

	func _process(delta: float) -> void:
		if _flash > 0.0:
			_flash = maxf(0.0, _flash - delta * 4.0)
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var col := color if enabled else color.darkened(0.6)
		if active:
			col = col.lightened(0.35)
		draw_circle(c, r, Color(0, 0, 0, 0.45))
		draw_circle(c, r - 4, col.lerp(Color(1, 0.9, 0.6), _flash * 0.6))
		draw_arc(c, r - 2, 0, TAU, 48, Color(0.95, 0.8, 0.5, 0.9), 3.0)
		var font := ThemeDB.fallback_font
		var lines := text.split("\n")
		for i in lines.size():
			var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var y := c.y + 5 + (i - (lines.size() - 1) * 0.5) * 16
			draw_string_outline(font, Vector2(c.x - w * 0.5, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
			draw_string(font, Vector2(c.x - w * 0.5, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.85))


## Barra de atalhos: 6 magias + 2 poções. Mostra recarga, nível bloqueado e falta de mana.
class SpellBar:
	extends Control
	const SZ := 46.0
	const GAP := 6.0
	var player: Player

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _rect(i: int) -> Rect2:
		var x := i * (SZ + GAP) + (12.0 if i >= Player.SPELLS.size() else 0.0)
		return Rect2(Vector2(x, 0), Vector2(SZ, SZ))

	func slot_at(pos: Vector2) -> int:
		if not visible:
			return -1
		var lp := pos - get_global_rect().position
		for i in Player.SPELLS.size() + 2:
			if _rect(i).has_point(lp):
				return i
		return -1

	func _draw() -> void:
		if player == null:
			return
		var font := ThemeDB.fallback_font
		var n := Player.SPELLS.size()
		for i in n + 2:
			var r := _rect(i)
			draw_rect(r, Color(0.06, 0.05, 0.04, 0.88))
			var c := r.get_center() + Vector2(0, -5)
			var key := ""
			var label := ""
			if i < n:
				var s: Dictionary = Player.SPELLS[i]
				var col: Color = {"fireball": Color(1, 0.5, 0.15), "cone": Color(1, 0.32, 0.08), "chain": Color(0.55, 0.72, 1), "area": Color(1, 0.62, 0.15), "heal": Color(0.4, 1, 0.5)}[s.type]
				draw_circle(c, 13, Color(col, 0.3))
				draw_circle(c, 7, col)
				draw_circle(c, 3, Color(1, 1, 0.9))
				key = str(i + 1)
				label = s.curto
				var cd := float(player.cds.get(s.k, 0.0))
				if player.level < int(s.lvl):
					draw_rect(r, Color(0, 0, 0, 0.72))
					label = "nv %d" % s.lvl
				elif cd > 0.0:
					var f := cd / float(s.cd)
					draw_rect(Rect2(r.position + Vector2(0, r.size.y * (1.0 - f)), Vector2(r.size.x, r.size.y * f)), Color(0, 0, 0, 0.65))
				elif player.mp < float(s.mana):
					draw_rect(r, Color(0, 0, 0.15, 0.5))
			else:
				var hpk := i == n
				var col2 := Color(0.85, 0.15, 0.12) if hpk else Color(0.2, 0.35, 0.95)
				draw_rect(Rect2(c + Vector2(-3, -12), Vector2(6, 6)), Color(0.6, 0.45, 0.3))
				draw_circle(c + Vector2(0, 2), 9, col2)
				draw_circle(c + Vector2(-3, -1), 3, Color(1, 1, 1, 0.5))
				key = "Q" if hpk else "E"
				label = str(player.hp_pot if hpk else player.mp_pot)
			draw_rect(r, Color(0.6, 0.46, 0.27), false, 1.5)
			draw_string_outline(font, r.position + Vector2(3, 11), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color.BLACK)
			draw_string(font, r.position + Vector2(3, 11), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.9, 0.6))
			var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string_outline(font, Vector2(r.get_center().x - lw * 0.5, r.end.y - 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color.BLACK)
			draw_string(font, Vector2(r.get_center().x - lw * 0.5, r.end.y - 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.9, 0.82))


## Habilidades (Magia, Defesa) com nível e barra de progresso. K esconde/mostra.
class SkillPanel:
	extends Control
	var player: Player

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if player == null:
			return
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.04, 0.03, 0.7))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.38, 0.22, 0.8), false, 1.0)
		var y := 15.0
		for k in player.skills:
			var sk: Array = player.skills[k]
			var f := clampf(float(sk[1]) / float(Rules.skill_need(k, int(sk[0]))), 0, 1)
			draw_string_outline(font, Vector2(8, y), Rules.SKILL_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
			draw_string(font, Vector2(8, y), Rules.SKILL_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.88, 0.8))
			draw_string_outline(font, Vector2(70, y), str(sk[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
			draw_string(font, Vector2(70, y), str(sk[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.82, 0.3))
			draw_rect(Rect2(98, y - 8, 94, 5), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(99, y - 7, 92 * f, 3), Color(1, 0.65, 0.2))
			y += 19.0


## Retrato + barras de vida e mana.
class StatusBars:
	extends Control
	var portrait: Texture2D
	var hp := 1.0
	var mp := 1.0
	var title := ""
	var sub := ""
	var xp := 0.0
	var gold := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _bar(pos: Vector2, w: float, v: float, col: Color, label: String) -> void:
		draw_rect(Rect2(pos, Vector2(w, 16)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(pos + Vector2(2, 2), Vector2((w - 4) * clampf(v, 0, 1), 12)), col)
		draw_rect(Rect2(pos + Vector2(2, 2), Vector2((w - 4) * clampf(v, 0, 1), 4)), col.lightened(0.3))
		draw_rect(Rect2(pos, Vector2(w, 16)), Color(0.6, 0.48, 0.3), false, 1.5)
		var font := ThemeDB.fallback_font
		draw_string_outline(font, pos + Vector2(6, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
		draw_string(font, pos + Vector2(6, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.95, 0.9))

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 64, 64), Color(0, 0, 0, 0.6))
		if portrait:
			var ts := portrait.get_size()
			var side := minf(ts.x, ts.y * 0.66)
			draw_texture_rect_region(portrait, Rect2(2, 2, 60, 60), Rect2((ts.x - side) * 0.5, 0, side, side))
		draw_rect(Rect2(0, 0, 64, 64), Color(0.7, 0.55, 0.32), false, 2.0)
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(72, 13), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
		draw_string(font, Vector2(72, 13), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.95, 0.4))
		_bar(Vector2(72, 19), 190, hp, Color(0.72, 0.08, 0.06), "Vida %d%%" % int(hp * 100))
		_bar(Vector2(72, 39), 190, mp, Color(0.12, 0.22, 0.8), "Mana %d%%" % int(mp * 100))
		# experiência (barra fina dourada) e ouro
		draw_rect(Rect2(72, 58, 190, 5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(73, 59, 188 * clampf(xp, 0, 1), 3), Color(0.95, 0.72, 0.2))
		var gs := "%d ouro" % gold
		draw_string_outline(font, Vector2(268, 63), gs, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
		draw_string(font, Vector2(268, 63), gs, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.85, 0.35))
		draw_string_outline(font, Vector2(72, 76), sub, HORIZONTAL_ALIGNMENT_LEFT, 210, 10, 3, Color.BLACK)
		draw_string(font, Vector2(72, 76), sub, HORIZONTAL_ALIGNMENT_LEFT, 210, 10, Color(0.85, 0.78, 0.65))


## Nomes sobre as cabeças (verde para jogadores; branco para NPCs; monstros com barra de
## vida), anel no alvo selecionado e números de dano/experiência.
class NameTags:
	extends Control
	var foe: Node2D = null

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var ct := get_viewport().get_canvas_transform()
		var zoom := ct.get_scale().x
		# anel no chão do alvo
		if foe != null and is_instance_valid(foe) and not foe.dead:
			var c: Vector2 = ct * foe.global_position
			var r := 20.0 * float(foe.info.scale) * zoom
			draw_set_transform(c, 0.0, Vector2(1, 0.5))
			draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(1, 0.2, 0.12, 0.95), 2.5)
			draw_arc(Vector2.ZERO, r + 3, 0, TAU, 40, Color(1, 0.4, 0.2, 0.35), 4.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for a in get_tree().get_nodes_in_group("actors"):
			var actor := a as Actor
			if actor == null or actor.display_name == "" or not actor.visible:
				continue
			var mon := actor as Monster
			if mon != null and mon.dead:
				continue
			var h := 92.0 * (float(mon.info.scale) if mon else 1.0)
			var pos := actor.get_global_transform_with_canvas() * Vector2(0, -h)
			var col := Color(0.92, 0.88, 0.78) if actor is Npc else Color(0.35, 0.95, 0.35)
			if mon:
				col = Color(1, 0.55, 0.45) if mon == foe else Color(0.9, 0.78, 0.7)
			var w := font.get_string_size(actor.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var at := pos + Vector2(-w * 0.5, 0)
			draw_string_outline(font, at, actor.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
			draw_string(font, at, actor.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
			if mon:
				var f := clampf(mon.hp / mon.max_hp, 0, 1)
				var bc := Color(0.25, 0.85, 0.25) if f > 0.6 else (Color(0.9, 0.75, 0.2) if f > 0.3 else Color(0.9, 0.2, 0.15))
				draw_rect(Rect2(pos + Vector2(-20, 4), Vector2(40, 5)), Color(0, 0, 0, 0.8))
				draw_rect(Rect2(pos + Vector2(-19, 5), Vector2(38 * f, 3)), bc)
		# números de dano, cura e experiência
		for it in CombatText.items:
			var life := 1.6 if it.big else 1.0
			var k: float = it.t / life
			var p: Vector2 = ct * it.p + Vector2(0, -k * 36.0)
			var sz := 18 if it.big else 14
			var tw := font.get_string_size(it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			var c2: Color = it.c
			c2.a = 1.0 - k * k
			draw_string_outline(font, p + Vector2(-tw * 0.5, 0), it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, c2.a))
			draw_string(font, p + Vector2(-tw * 0.5, 0), it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c2)
