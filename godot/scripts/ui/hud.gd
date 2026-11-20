class_name Hud
extends CanvasLayer
## HUD: status da rede, nomes sobre os personagens, chat e botões de toque.

var player: Player
var net: NetSync
var status: Label
var chat_log: Label
var chat_input: LineEdit
var rotate_msg: Label
var names: NameTags
var run_btn: Button
var _lines: PackedStringArray = PackedStringArray()


func bind(p: Player, n: NetSync) -> void:
	player = p
	net = n
	_build()
	net.chat_received.connect(_on_chat)


func _btn(text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(92, 52)
	b.add_theme_font_size_override("font_size", 15)
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

	status = _label(14, Color(0.92, 0.82, 0.66))
	status.position = Vector2(10, 8)
	root.add_child(status)

	chat_log = _label(14, Color(0.95, 0.9, 0.6))
	chat_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_log.offset_left = 10
	chat_log.offset_top = -170
	chat_log.offset_bottom = -52
	chat_log.offset_right = 520
	chat_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	chat_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(chat_log)

	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Escreva e aperte Enter"
	chat_input.max_length = 120
	chat_input.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_input.offset_left = 10
	chat_input.offset_right = 420
	chat_input.offset_top = -46
	chat_input.offset_bottom = -10
	chat_input.visible = false
	chat_input.text_submitted.connect(_on_submit)
	root.add_child(chat_input)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_right = -10
	bar.offset_bottom = -10
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	run_btn = _btn("Correr", func(on): player.run_toggle = on, true)
	bar.add_child(run_btn)
	bar.add_child(_btn("Magia", func(): player.play_action("cast", 0.7)))
	bar.add_child(_btn("Chat", _open_chat))
	bar.add_child(_btn("Tela\ncheia", _fullscreen))

	rotate_msg = _label(26, Color(1, 0.75, 0.4))
	rotate_msg.text = "Vire o celular\npara a horizontal"
	rotate_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotate_msg.set_anchors_preset(Control.PRESET_CENTER)
	rotate_msg.visible = false
	root.add_child(rotate_msg)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_d: float) -> void:
	if player == null:
		return
	var online := "%d online%s" % [net.online_count, " (anfitrião)" if net.is_host else ""] if net.enabled else ""
	status.text = "ARSON — taverna (arte provisória)\n%s %s\nPC: WASD · Shift corre · 1 magia · I equipamento · Enter chat" % [net.status, online]
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


## Nomes sobre as cabeças (verde para jogadores, como no Tibia; branco para NPCs).
class NameTags:
	extends Control

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for a in get_tree().get_nodes_in_group("actors"):
			var actor := a as Actor
			if actor == null or actor.display_name == "":
				continue
			var pos := actor.get_global_transform_with_canvas() * Vector2(0, -88)
			var col := Color(0.95, 0.92, 0.85) if actor is Npc else Color(0.35, 0.95, 0.35)
			var w := font.get_string_size(actor.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var at := pos + Vector2(-w * 0.5, 0)
			draw_string_outline(font, at, actor.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
			draw_string(font, at, actor.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
