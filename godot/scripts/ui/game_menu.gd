class_name GameMenu
extends CanvasLayer
## Menu do jogo (Esc ou botão "Menu"): Habilidades, Automação, Gráficos e Progresso.
## O jogo não pausa (é online); tudo vale na hora e fica salvo.

const GOLD := Color(0.92, 0.82, 0.6)
const DIM := Color(0.7, 0.64, 0.55)

var player: Player
var perf: Perf
var _box: PanelContainer
var _tabs: TabContainer
var _skills_box: VBoxContainer
var _q_info: Label
var _zoom_slider: HSlider


func bind(p: Player, pf: Perf) -> void:
	player = p
	perf = pf
	layer = 4
	_build()
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_skills()
		_refresh_quality()
		_zoom_slider.set_value_no_signal(Settings.zoom)


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE and get_viewport().gui_get_focus_owner() == null:
		toggle()
		get_viewport().set_input_as_handled()


func _process(_d: float) -> void:
	if visible and _tabs.current_tab == 2:
		_refresh_quality()


# ------------------------------------------------------------ construção
func _style(bg: Color, border: Color, radius := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	return sb


func _lbl(text: String, size := 14, col := GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_stylebox_override("normal", _style(Color(0.12, 0.08, 0.05), Color(0.5, 0.38, 0.22), 8))
	b.add_theme_stylebox_override("hover", _style(Color(0.2, 0.12, 0.06), Color(0.75, 0.55, 0.3), 8))
	b.add_theme_stylebox_override("pressed", _style(Color(0.35, 0.14, 0.05), Color(0.9, 0.6, 0.3), 8))
	b.pressed.connect(cb)
	return b


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			toggle())
	add_child(dim)

	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", _style(Color(0.06, 0.045, 0.035, 0.97), Color(0.55, 0.4, 0.22)))
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.custom_minimum_size = Vector2(520, 400)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_box.add_child(col)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(496, 320)
	_tabs.add_theme_color_override("font_selected_color", Color(1, 0.8, 0.4))
	_tabs.add_theme_color_override("font_unselected_color", DIM)
	_tabs.add_theme_font_size_override("font_size", 14)
	_tabs.add_theme_stylebox_override("panel", _style(Color(0.09, 0.065, 0.05), Color(0.35, 0.26, 0.15), 6))
	_tabs.tab_changed.connect(func(_i): _refresh_skills())
	col.add_child(_tabs)

	_tabs.add_child(_page_skills())
	_tabs.add_child(_page_auto())
	_tabs.add_child(_page_graphics())
	_tabs.add_child(_page_save())

	col.add_child(_btn("Continuar jogando", toggle))


func _scroll(name: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	return [sc, v]


# ------------------------------------------------------------ Habilidades
func _page_skills() -> Control:
	var r := _scroll("Habilidades")
	_skills_box = r[1]
	return r[0]


func _refresh_skills() -> void:
	if _skills_box == null or player == null:
		return
	for c in _skills_box.get_children():
		c.queue_free()
	var a := Rules.xp_to_reach(player.level)
	var b := Rules.xp_to_reach(player.level + 1)
	var cd := MageClass.info(player.classe)
	_skills_box.add_child(_lbl("%s — %s, %s e Luz" % [cd.nome, cd.elementos[0], cd.elementos[1]], 16, cd.cor))
	_skills_box.add_child(_bar_row("Nível", player.level, float(player.xp - a) / maxf(1, b - a),
		"%d / %d xp" % [player.xp - a, b - a], "Sobe matando criaturas. Aumenta vida, mana e dano. Não tem limite."))
	var tips := {"magia": "Sobe usando magias (cura também conta). +6% de dano por nível.",
		"defesa": "Sobe apanhando de criaturas. Diminui o dano recebido."}
	for k in player.skills:
		var sk: Array = player.skills[k]
		var need := Rules.skill_need(k, int(sk[0]))
		_skills_box.add_child(_bar_row(Rules.SKILL_NAMES[k], int(sk[0]), float(sk[1]) / need,
			"%d / %d" % [int(sk[1]), need], tips.get(k, "")))
	_skills_box.add_child(_lbl("Dica: os bonecos de treino logo fora da vila sobem as habilidades sem risco.", 12, DIM))


func _bar_row(name: String, lv: int, f: float, txt: String, tip: String) -> Control:
	var v := VBoxContainer.new()
	var h := HBoxContainer.new()
	var n := _lbl(name, 15)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(_lbl(str(lv), 17, Color(1, 0.82, 0.3)))
	v.add_child(h)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 1
	bar.value = clampf(f, 0, 1)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("background", _style(Color(0, 0, 0, 0.6), Color(0.3, 0.22, 0.12), 4))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 0.62, 0.18)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	v.add_child(_lbl("%s — %s" % [txt, tip], 12, DIM))
	return v


# ------------------------------------------------------------ Automação
func _page_auto() -> Control:
	var r := _scroll("Automação")
	var v: VBoxContainer = r[1]
	v.add_child(_lbl("Ligue só o que quiser. Vale na hora e fica salvo.", 12, DIM))
	v.add_child(_toggle("alvo", "Alvo automático", "Mira sozinho o inimigo mais próximo (até 12 quadrados).", Color(1, 0.82, 0.23)))
	v.add_child(_toggle("ataque", "Magias de ataque automáticas", "Lança as magias de ataque no alvo assim que recarregam.", Color(1, 0.54, 0.23)))
	v.add_child(_pct("cura", "Cura automática", "quando a vida chegar a", Color(0.36, 1, 0.48)))
	v.add_child(_pct("pocao_vida", "Poção de vida automática", "quando a vida chegar a", Color(1, 0.42, 0.35)))
	v.add_child(_pct("pocao_mana", "Poção de mana automática", "quando a mana chegar a", Color(0.42, 0.66, 1)))
	v.add_child(_toggle("infinitas", "Poções infinitas", "As poções não acabam (pensado para celular e controle).", Color(0.91, 0.86, 0.8)))
	return r[0]


func _check(key: String, name: String, col: Color) -> CheckBox:
	var c := CheckBox.new()
	c.text = name
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(Settings.auto[key])
	c.add_theme_color_override("font_color", col)
	c.add_theme_color_override("font_pressed_color", col)
	c.add_theme_color_override("font_hover_color", col.lightened(0.2))
	c.add_theme_font_size_override("font_size", 15)
	c.toggled.connect(func(on):
		Settings.auto[key] = on
		Settings.save())
	return c


func _toggle(key: String, name: String, desc: String, col: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(_check(key, name, col))
	v.add_child(_lbl("      " + desc, 12, DIM))
	return v


func _pct(key: String, name: String, when: String, col: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(_check(key, name, col))
	var h := HBoxContainer.new()
	var lab := _lbl("      %s %d%%" % [when, Settings.auto[key + "_pct"]], 12, DIM)
	lab.custom_minimum_size = Vector2(250, 0)
	h.add_child(lab)
	var s := HSlider.new()
	s.min_value = 5
	s.max_value = 95
	s.step = 5
	s.value = float(Settings.auto[key + "_pct"])
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(x):
		Settings.auto[key + "_pct"] = int(x)
		lab.text = "      %s %d%%" % [when, int(x)]
		Settings.save())
	h.add_child(s)
	v.add_child(h)
	return v


# ------------------------------------------------------------ Gráficos
func _page_graphics() -> Control:
	var r := _scroll("Gráficos")
	var v: VBoxContainer = r[1]

	v.add_child(_lbl("Resolução", 15))
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	for i in Settings.LEVEL_NAMES.size():
		opt.add_item(Settings.LEVEL_NAMES[i], i)
	opt.select(Settings.quality)
	opt.item_selected.connect(func(i):
		Settings.quality = i
		if i == 0:
			Settings.level_now = 3 if Settings.is_mobile() else 6
		Settings.save()
		perf.apply()
		_refresh_quality())
	v.add_child(opt)
	_q_info = _lbl("", 12, DIM)
	v.add_child(_q_info)

	v.add_child(_lbl("Distância de visão (zoom)", 15))
	var h := HBoxContainer.new()
	h.add_child(_lbl("Longe", 12, DIM))
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = Settings.ZOOM_MIN
	_zoom_slider.max_value = Settings.ZOOM_MAX
	_zoom_slider.step = 0.05
	_zoom_slider.value = Settings.zoom
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_slider.focus_mode = Control.FOCUS_NONE
	_zoom_slider.value_changed.connect(func(z):
		player.set_zoom(z)
		Settings.save())
	h.add_child(_zoom_slider)
	h.add_child(_lbl("Perto", 12, DIM))
	v.add_child(h)
	v.add_child(_lbl("No PC também dá para usar a roda do mouse ou as teclas + e −.", 12, DIM))
	return r[0]


func _refresh_quality() -> void:
	if _q_info == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var ws := get_window().size
	var pct := int(round(Settings.LEVELS[clampi(Settings.level_now, 1, 6)] * 100))
	var how := "Automática: começa na máxima e só baixa se o jogo engasgar; sobe de novo quando sobra desempenho." if Settings.quality == 0 else "Fixa no nível escolhido."
	_q_info.text = "%s\nEm uso agora: nível %d (%d%% da tela) · %d FPS · janela %dx%d" % [how, Settings.level_now, pct, int(Perf.fps), ws.x, ws.y]
	if vs.x < 0:
		_q_info.text += ""


# ------------------------------------------------------------ Progresso
func _page_save() -> Control:
	var r := _scroll("Progresso")
	var v: VBoxContainer = r[1]
	v.add_child(_lbl("Seu progresso é salvo sozinho neste navegador a cada poucos segundos. Para não perder nada se o navegador limpar os dados (ou para jogar em outro aparelho), exporte e guarde o código ou o arquivo.", 13, DIM))
	var h1 := HBoxContainer.new()
	var b1 := _btn("Baixar arquivo de progresso", _download)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h1.add_child(b1)
	var b2 := _btn("Copiar código", _copy)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h1.add_child(b2)
	v.add_child(h1)
	var b3 := _btn("Importar (colar código)", _paste)
	v.add_child(b3)
	v.add_child(_lbl("Trocar de classe volta para a tela inicial. Seu nível e suas habilidades continuam.", 13, DIM))
	v.add_child(_btn("Trocar de classe", func():
		player.save()
		if OS.has_feature("web"):
			JavaScriptBridge.eval("location.reload()")
		else:
			get_tree().reload_current_scene()))
	return r[0]


func _export_code() -> String:
	player.save()
	var f := FileAccess.open(Player.SAVE_PATH, FileAccess.READ)
	if f == null:
		return ""
	return "ARSON2:" + Marshalls.utf8_to_base64(f.get_as_text())


func _download() -> void:
	var code := _export_code()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(code.to_utf8_buffer(), "arson-progresso-%s.txt" % Time.get_date_string_from_system(), "text/plain")
	else:
		DisplayServer.clipboard_set(code)
	CombatText.add(player.global_position + Vector2(0, -130), "Progresso exportado", Color(1, 0.85, 0.4), true)


func _copy() -> void:
	DisplayServer.clipboard_set(_export_code())
	CombatText.add(player.global_position + Vector2(0, -130), "Código copiado", Color(1, 0.85, 0.4), true)


func _paste() -> void:
	if not OS.has_feature("web"):
		import_code(DisplayServer.clipboard_get())
		return
	var s = JavaScriptBridge.eval("prompt('Cole aqui o código de progresso (começa com ARSON2:)') || ''", true)
	if str(s).strip_edges() == "":
		return
	var ok = JavaScriptBridge.eval("confirm('Importar vai substituir o progresso deste navegador. Continuar?')", true)
	if ok:
		import_code(str(s))


func import_code(code: String) -> void:
	code = code.strip_edges()
	if not code.begins_with("ARSON2:"):
		_alert("Código inválido: ele começa com ARSON2:")
		return
	var text := Marshalls.base64_to_utf8(code.substr(7))
	var c := ConfigFile.new()
	if c.parse(text) != OK or not c.has_section("jogador"):
		_alert("Código inválido ou incompleto.")
		return
	c.save(Player.SAVE_PATH)
	player.reload()
	_refresh_skills()
	CombatText.add(player.global_position + Vector2(0, -130), "Progresso importado!", Color(0.5, 1, 0.5), true)


func _alert(t: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("alert(%s)" % JSON.stringify(t))
	else:
		push_warning(t)
