class_name Hud
extends CanvasLayer
## HUD no estilo Diablo 2: globo de vida (esquerda), globo de mana (direita),
## barra de pedra com atalhos no centro, nomes sobre os personagens e chat.

var player: Player
var net: NetSync
var status: Label
var chat_log: Label
var chat_input: LineEdit
var rotate_msg: Label
var names: NameTags
var life: Globe
var mana: Globe
var _lines: PackedStringArray = PackedStringArray()

const BAR_H := 92.0


func bind(p: Player, n: NetSync) -> void:
	player = p
	net = n
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


func _slot(text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(64, 62)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.07, 0.06) if st == "normal" else (Color(0.16, 0.11, 0.07) if st == "hover" else Color(0.3, 0.12, 0.05))
		sb.border_color = Color(0.42, 0.34, 0.22)
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override(st, sb)
	if toggle:
		b.toggled.connect(cb)
	else:
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

	status = _label(12, Color(0.8, 0.72, 0.6))
	status.position = Vector2(10, 6)
	root.add_child(status)

	# barra de pedra
	var bar := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.1, 0.09, 0.96)
	sb.border_color = Color(0.36, 0.3, 0.22)
	sb.border_width_top = 3
	bar.add_theme_stylebox_override("panel", sb)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -BAR_H + 22
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bar)

	var slots := HBoxContainer.new()
	slots.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	slots.grow_horizontal = Control.GROW_DIRECTION_BOTH
	slots.grow_vertical = Control.GROW_DIRECTION_BEGIN
	slots.offset_bottom = -4
	slots.add_theme_constant_override("separation", 4)
	root.add_child(slots)
	slots.add_child(_slot("Correr", func(on): player.run_toggle = on, true))
	slots.add_child(_slot("Magia\n(1)", func(): player.cast_at()))
	slots.add_child(_slot("Chat", _open_chat))
	slots.add_child(_slot("Tela\ncheia", _fullscreen))

	life = Globe.new()
	life.fill = Color(0.75, 0.05, 0.04)
	life.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	life.offset_left = 6
	life.offset_top = -BAR_H - 4
	life.offset_right = 6 + BAR_H
	life.offset_bottom = -4
	root.add_child(life)
	mana = Globe.new()
	mana.fill = Color(0.1, 0.18, 0.8)
	mana.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mana.offset_left = -6 - BAR_H
	mana.offset_top = -BAR_H - 4
	mana.offset_right = -6
	mana.offset_bottom = -4
	root.add_child(mana)

	chat_log = _label(13, Color(0.95, 0.9, 0.6))
	chat_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_log.offset_left = BAR_H + 14
	chat_log.offset_top = -BAR_H - 130
	chat_log.offset_bottom = -BAR_H + 10
	chat_log.offset_right = 520
	chat_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	chat_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(chat_log)

	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Escreva e aperte Enter"
	chat_input.max_length = 120
	chat_input.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_input.offset_left = BAR_H + 14
	chat_input.offset_right = 520
	chat_input.offset_top = -BAR_H - 36 + 10
	chat_input.offset_bottom = -BAR_H + 4
	chat_input.visible = false
	chat_input.text_submitted.connect(_on_submit)
	root.add_child(chat_input)

	rotate_msg = _label(26, Color(1, 0.75, 0.4))
	rotate_msg.text = "Vire o celular\npara a horizontal"
	rotate_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotate_msg.set_anchors_preset(Control.PRESET_CENTER)
	rotate_msg.visible = false
	root.add_child(rotate_msg)


func _process(_d: float) -> void:
	if player == null:
		return
	var online := ("%d online%s" % [net.online_count, " · anfitrião" if net.is_host else ""]) if net.enabled else ""
	status.text = "%s  %s\nPC: clique anda · botão direito/1 magia · Shift corre · I equipamento · Enter chat" % [net.status, online]
	life.ratio = player.hp / player.max_hp
	mana.ratio = player.mp / player.max_mp
	life.label = "%d" % player.hp
	mana.label = "%d" % player.mp
	life.queue_redraw()
	mana.queue_redraw()
	var vs := get_viewport().get_visible_rect().size
	rotate_msg.visible = vs.y > vs.x * 1.1
	names.queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k and k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and not chat_input.visible:
		_open_chat()
		get_viewport().set_input_as_handled()


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
	while _lines.size() > 6:
		_lines.remove_at(0)
	chat_log.text = "\n".join(_lines)


func _fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Globo de vida/mana: esfera de vidro com líquido no nível atual.
class Globe:
	extends Control
	var fill := Color.RED
	var ratio := 1.0
	var label := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c, r + 4.0, Color(0.3, 0.25, 0.18))
		draw_circle(c, r + 1.5, Color(0.05, 0.04, 0.04))
		var level := c.y + r - 2.0 * r * clampf(ratio, 0.0, 1.0)
		var y := c.y - r
		while y <= c.y + r:
			if y >= level:
				var dx := sqrt(maxf(0.0, r * r - (y - c.y) * (y - c.y)))
				var shade := 0.55 + 0.45 * (1.0 - absf(y - c.y) / r)
				draw_line(Vector2(c.x - dx, y), Vector2(c.x + dx, y), fill * shade, 1.2)
			y += 1.0
		draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.22, Color(1, 1, 1, 0.12))
		draw_arc(c, r + 1.5, 0, TAU, 48, Color(0.55, 0.45, 0.3), 2.0)
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(font, c + Vector2(-w * 0.5, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
		draw_string(font, c + Vector2(-w * 0.5, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.8))


## Nomes sobre as cabeças (verde para jogadores; branco para NPCs).
class NameTags:
	extends Control

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for a in get_tree().get_nodes_in_group("actors"):
			var actor := a as Actor
			if actor == null or actor.display_name == "":
				continue
			var pos := actor.get_global_transform_with_canvas() * Vector2(0, -90)
			var col := Color(0.92, 0.88, 0.78) if actor is Npc else Color(0.35, 0.95, 0.35)
			var w := font.get_string_size(actor.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var at := pos + Vector2(-w * 0.5, 0)
			draw_string_outline(font, at, actor.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
			draw_string(font, at, actor.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
