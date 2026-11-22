class_name GameMenu
extends CanvasLayer
## Menu único do jogo (botão "Menu" ou Esc). Abas na lateral: Personagem, Magias (árvore),
## Equipamento, Automação, Gráficos, Progresso; e atalhos para Chat e Tela cheia.
## Tudo cabe sem rolagem. Enquanto está aberto, desenha em resolução máxima (texto nítido).
## O jogo não pausa (é online); tudo vale na hora e fica salvo.

const GOLD := Color(0.92, 0.82, 0.6)
const DIM := Color(0.72, 0.66, 0.58)
const PANEL := Vector2(940, 520)

var player: Player
var perf: Perf
## O HUD preenche: abrir o chat, o equipamento e alternar tela cheia.
var on_chat: Callable
var on_equip: Callable
var on_full: Callable

var _pages: Array[Control] = []
var _tab_btns: Array[Button] = []
var _cur := 0
var _char_box: VBoxContainer
var _tree: SpellTree
var _q_info: Label
var _zoom_slider: HSlider
var _box: PanelContainer


## Cabe em qualquer tela: no máximo o tamanho de desenho, sempre com margem.
func _fit() -> void:
	if _box == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_box.custom_minimum_size = Vector2(minf(PANEL.x, vp.x - 16.0), minf(PANEL.y, vp.y - 16.0))


func bind(p: Player, pf: Perf) -> void:
	player = p
	perf = pf
	layer = 4
	_build()
	visible = false


func toggle() -> void:
	visible = not visible
	Perf.force_full = visible
	if perf:
		perf.apply()
	if visible:
		_fit()
		_fill_trainer()
		_show(_cur)
		_zoom_slider.set_value_no_signal(Settings.zoom)


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE and get_viewport().gui_get_focus_owner() == null:
		toggle()
		get_viewport().set_input_as_handled()


func _process(_d: float) -> void:
	if visible and _cur == 4:
		_refresh_quality()


# ------------------------------------------------------------ peças
func _style(bg: Color, border: Color, radius := 10, margin := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _lbl(text: String, size := 15, col := GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _btn(text: String, cb: Callable, size := 15) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 42)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_hover_color", Color(1, 0.9, 0.7))
	b.add_theme_stylebox_override("normal", _style(Color(0.12, 0.08, 0.05), Color(0.5, 0.38, 0.22), 8, 8))
	b.add_theme_stylebox_override("hover", _style(Color(0.2, 0.12, 0.06), Color(0.75, 0.55, 0.3), 8, 8))
	b.add_theme_stylebox_override("pressed", _style(Color(0.35, 0.14, 0.05), Color(0.9, 0.6, 0.3), 8, 8))
	b.pressed.connect(cb)
	return b


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			toggle())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.box(Color(0.06, 0.045, 0.035, 0.98), Color(0.66, 0.48, 0.26), 12, 10))
	_box = box
	_fit()
	get_viewport().size_changed.connect(_fit)
	center.add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	# abas na lateral
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(160, 0)
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	var t := _lbl("ARSON", 24, Color(1, 0.62, 0.22))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(t)
	var names := ["Personagem", "Magias", "Inventário", "Automação", "Gráficos", "Progresso"]
	for i in names.size():
		var b := _btn(names[i], func(): _tab(i), 16)
		_tab_btns.append(b)
		side.add_child(b)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(sp)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	side.add_child(h)
	var bc := _btn("Chat", func():
		toggle()
		if on_chat.is_valid(): on_chat.call(), 14)
	bc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(bc)
	var bf := _btn("Tela cheia", func():
		if on_full.is_valid(): on_full.call(), 14)
	bf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(bf)
	var close := _btn("Voltar ao jogo", toggle, 16)
	close.add_theme_stylebox_override("normal", _style(Color(0.4, 0.14, 0.04), Color(1, 0.6, 0.25), 8, 8))
	side.add_child(close)

	# conteúdo
	var content := PanelContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_stylebox_override("panel", _style(Color(0.09, 0.065, 0.05), Color(0.35, 0.26, 0.15), 8, 14))
	row.add_child(content)
	for pg in [_page_char(), _page_spells(), _page_equip(), _page_auto(), _page_graphics(), _page_save()]:
		content.add_child(pg)
		_pages.append(pg)
	# X no canto de cima à direita (por cima de tudo, só o botão recebe toque)
	var over := Control.new()
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(over)
	var x := UiKit.button("✕", toggle, 20, true)
	x.custom_minimum_size = Vector2(46, 42)
	x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x.offset_left = -40
	x.offset_top = -6
	x.offset_right = 6
	x.offset_bottom = 36
	over.add_child(x)
	_show(0)


func _tab(i: int) -> void:
	if i == 2:
		# Equipamento abre o painel de equipamento (fora do menu)
		toggle()
		if on_equip.is_valid():
			on_equip.call()
		return
	_show(i)


func _show(i: int) -> void:
	_cur = i
	for j in _pages.size():
		_pages[j].visible = j == i
		var on := j == i
		_tab_btns[j].add_theme_stylebox_override("normal", _style(
			Color(0.3, 0.13, 0.05) if on else Color(0.12, 0.08, 0.05),
			Color(1, 0.65, 0.3) if on else Color(0.5, 0.38, 0.22), 8, 8))
	if i == 0:
		_refresh_char()
	elif i == 4:
		_refresh_quality()


func _vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


# ------------------------------------------------------------ Personagem
func _page_char() -> Control:
	_char_box = _vbox(8)
	return _char_box


func _refresh_char() -> void:
	if player == null:
		return
	for c in _char_box.get_children():
		c.queue_free()
	var cd := MageClass.info(player.classe)
	_char_box.add_child(_lbl("%s — %s" % [player.display_name if player.display_name != "" else Chars.nome, cd.nome], 20, cd.cor.lightened(0.15)))
	var a := Rules.xp_to_reach(player.level)
	var b := Rules.xp_to_reach(player.level + 1)
	_char_box.add_child(_bar_row("Nível", player.level, float(player.xp - a) / maxf(1, b - a),
		"%d / %d xp — sobe matando criaturas; aumenta vida, mana e dano (sem limite)" % [player.xp - a, b - a], Color(1, 0.62, 0.18)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	_char_box.add_child(grid)
	for k in player.skills:
		var sk: Array = player.skills[k]
		var need := Rules.skill_need(k, int(sk[0]))
		var col: Color = Spellbook.ELEMENTS[k].cor if Spellbook.ELEMENTS.has(k) else Color(0.7, 0.75, 0.8)
		var tip := "sobe apanhando; diminui o dano recebido" if k == "defesa" else "sobe usando as magias deste elemento"
		var r := _bar_row(Rules.skill_name(k), int(sk[0]), float(sk[1]) / need, "%d / %d — %s" % [int(sk[1]), need, tip], col)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.custom_minimum_size = Vector2(340, 0)
		grid.add_child(r)
	_char_box.add_child(_lbl("Ouro: %d   ·   Poções: %d de vida, %d de mana" % [player.gold, player.hp_pot, player.mp_pot], 14, GOLD))
	_char_box.add_child(_lbl("Dica: os bonecos de treino logo fora da vila sobem as habilidades sem risco. A aba Magias mostra a árvore completa.", 13, DIM))


func _bar_row(name: String, lv: int, f: float, txt: String, col: Color) -> Control:
	var v := _vbox(2)
	var h := HBoxContainer.new()
	var n := _lbl(name, 16, col.lightened(0.2))
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(_lbl(str(lv), 18, Color(1, 0.85, 0.35)))
	v.add_child(h)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 1
	bar.value = clampf(f, 0, 1)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.add_theme_stylebox_override("background", _style(Color(0, 0, 0, 0.6), Color(0.3, 0.22, 0.12), 4, 0))
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	v.add_child(_lbl(txt, 12, DIM))
	return v


# ------------------------------------------------------------ Magias
func _page_spells() -> Control:
	_tree = SpellTree.new()
	_tree.player = player
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return _tree


# ------------------------------------------------------------ Equipamento (abre o painel)
func _page_equip() -> Control:
	return Control.new()


# ------------------------------------------------------------ Automação
func _page_auto() -> Control:
	var v := _vbox(12)
	v.add_child(_lbl("Ligue só o que quiser. Vale na hora e fica salvo.", 14, DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 16)
	v.add_child(grid)
	for w in [
		_toggle("alvo", "Alvo automático", "Mira sozinho o inimigo mais próximo (até 12 quadrados).", Color(1, 0.82, 0.23)),
		_toggle("ataque", "Magias de ataque automáticas", "Lança as magias de ataque no alvo assim que recarregam.", Color(1, 0.54, 0.23)),
		_pct("cura", "Cura automática", "quando a vida chegar a", Color(0.36, 1, 0.48)),
		_pct("pocao_vida", "Poção de vida automática", "quando a vida chegar a", Color(1, 0.42, 0.35)),
		_pct("pocao_mana", "Poção de mana automática", "quando a mana chegar a", Color(0.42, 0.66, 1)),
		_toggle("infinitas", "Poções infinitas", "As poções não acabam (pensado para celular e controle).", Color(0.91, 0.86, 0.8)),
		_toggle("escudo_auto", "Escudo automático", "Se o escudo está na barra, ativa sozinho e ativa de novo quando quebra ou acaba.", Color(0.6, 0.85, 1)),
		_toggle("summon_auto", "Invocação automática", "Se a invocação está na barra, invoca sozinha e invoca de novo quando ela morre.", Color(1, 0.8, 0.5)),
		_toggle("summon_agressivo", "Invocação agressiva", "Ligado: ataca sozinha o seu alvo e os inimigos perto. Desligado: só revida.", Color(1, 0.7, 0.4)),
		_trainer(),
	]:
		w.custom_minimum_size = Vector2(340, 0)
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(w)
	return v


## Treino de magia: com a mana cheia, lança sozinho a magia escolhida (bom para subir a Luz curando).
var _train_opt: OptionButton


func _trainer() -> Control:
	var v := _vbox(4)
	v.add_child(_check("treino", "Treino de magia", Color(1, 0.93, 0.6)))
	_train_opt = OptionButton.new()
	_train_opt.focus_mode = Control.FOCUS_NONE
	_train_opt.add_theme_font_size_override("font_size", 15)
	_train_opt.custom_minimum_size = Vector2(0, 38)
	_train_opt.item_selected.connect(func(i):
		Settings.auto["treino_id"] = str(_train_opt.get_item_metadata(i))
		Settings.save())
	v.add_child(_train_opt)
	v.add_child(_lbl("Com a mana cheia, lança a magia escolhida (funciona até na vila).", 13, DIM))
	_fill_trainer()
	return v


func _fill_trainer() -> void:
	if _train_opt == null or player == null:
		return
	_train_opt.clear()
	var cur := str(Settings.auto.get("treino_id", "luz:1"))
	var els := Spellbook.elements_of(player.classe) + ["luz"]
	var ids := []
	for e in els:
		for t in range(1, 9):
			ids.append("%s:%d" % [e, t])
	for t in [3, 5, 7, 8]:
		ids.append("fus:%d" % t)
	for id in ids:
		var sp := Spells.get_spell(id, player.classe)
		if sp.is_empty() or not player.spell_unlocked(id) or sp.type == "summon":
			continue
		_train_opt.add_item("%s  (%d mana)" % [sp.nome, int(sp.mana)])
		_train_opt.set_item_metadata(_train_opt.item_count - 1, id)
		if id == cur:
			_train_opt.select(_train_opt.item_count - 1)


func _check(key: String, name: String, col: Color) -> CheckBox:
	var c := CheckBox.new()
	c.text = name
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(Settings.auto[key])
	c.add_theme_color_override("font_color", col)
	c.add_theme_color_override("font_pressed_color", col)
	c.add_theme_color_override("font_hover_color", col.lightened(0.2))
	c.add_theme_color_override("font_hover_pressed_color", col.lightened(0.2))
	c.add_theme_font_size_override("font_size", 16)
	c.add_theme_icon_override("checked", _box_icon(true))
	c.add_theme_icon_override("unchecked", _box_icon(false))
	c.toggled.connect(func(on):
		Settings.auto[key] = on
		Settings.save())
	return c


static var _icons := {}


## Caixinha de marcar bem visível (o ícone padrão é escuro demais no fundo escuro).
func _box_icon(on: bool) -> Texture2D:
	if _icons.has(on):
		return _icons[on]
	var n := 22
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var edge := x < 2 or y < 2 or x >= n - 2 or y >= n - 2
			if edge:
				img.set_pixel(x, y, Color(1, 0.75, 0.4))
			elif on and x >= 5 and y >= 5 and x < n - 5 and y < n - 5:
				img.set_pixel(x, y, Color(1, 0.62, 0.2))
			else:
				img.set_pixel(x, y, Color(0.05, 0.035, 0.025))
	_icons[on] = ImageTexture.create_from_image(img)
	return _icons[on]


func _toggle(key: String, name: String, desc: String, col: Color) -> Control:
	var v := _vbox(2)
	v.add_child(_check(key, name, col))
	v.add_child(_lbl(desc, 13, DIM))
	return v


func _pct(key: String, name: String, when: String, col: Color) -> Control:
	var v := _vbox(2)
	v.add_child(_check(key, name, col))
	var h := HBoxContainer.new()
	var lab := _lbl("%s %d%%" % [when, Settings.auto[key + "_pct"]], 13, DIM)
	lab.custom_minimum_size = Vector2(190, 0)
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
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
		lab.text = "%s %d%%" % [when, int(x)]
		Settings.save())
	h.add_child(s)
	v.add_child(h)
	return v


# ------------------------------------------------------------ Gráficos
func _page_graphics() -> Control:
	var v := _vbox(12)
	v.add_child(_lbl("Resolução do mundo", 17))
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	opt.add_theme_font_size_override("font_size", 15)
	opt.custom_minimum_size = Vector2(0, 40)
	for i in Settings.LEVEL_NAMES.size():
		opt.add_item(Settings.LEVEL_NAMES[i], i)
	opt.select(Settings.quality)
	opt.item_selected.connect(func(i):
		Settings.quality = i
		# escolher a qualidade na mão desliga o modo leve de segurança
		if OS.has_feature("web"):
			JavaScriptBridge.eval("try{localStorage.removeItem('arson-leve')}catch(e){}", true)
		if i == 0:
			Settings.level_now = 1
		Settings.save()
		perf.apply()
		_refresh_quality())
	v.add_child(opt)
	_q_info = _lbl("", 13, DIM)
	v.add_child(_q_info)

	v.add_child(_lbl("Distância de visão (zoom)", 17))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_lbl("Longe", 14, DIM))
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
	h.add_child(_lbl("Perto", 14, DIM))
	v.add_child(h)
	v.add_child(_lbl("No PC também dá para usar a roda do mouse ou as teclas + e −.", 13, DIM))
	v.add_child(_btn("Alternar tela cheia", func():
		if on_full.is_valid(): on_full.call()))
	return v


func _refresh_quality() -> void:
	if _q_info == null:
		return
	var ws := get_window().size
	var lv := clampi(Settings.level_now, 1, 6)
	var pct := int(round(Settings.LEVELS[lv] * 100))
	var how := "Automática: começa no mais leve e vai subindo enquanto o jogo roda liso; baixa sozinha se engasgar." if Settings.quality == 0 else "Fixa no nível escolhido."
	_q_info.text = "%s\nNo jogo: nível %d (%d%% da tela) · %d FPS · janela %dx%d\n(Com o menu aberto, tudo é desenhado em resolução máxima.)" % [how, lv, pct, int(Perf.fps), ws.x, ws.y]


# ------------------------------------------------------------ Progresso
func _page_save() -> Control:
	var v := _vbox(12)
	v.add_child(_lbl("O progresso é salvo sozinho neste navegador a cada poucos segundos. Para não perder nada se o navegador limpar os dados (ou para jogar em outro aparelho), exporte e guarde o código ou o arquivo.", 14, DIM))
	var h1 := HBoxContainer.new()
	h1.add_theme_constant_override("separation", 8)
	for b in [_btn("Baixar arquivo de progresso", _download), _btn("Copiar código", _copy), _btn("Importar (colar código)", _paste)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h1.add_child(b)
	v.add_child(h1)
	v.add_child(_lbl("Trocar de personagem volta para a tela inicial, onde você escolhe ou cria outro (até 4).", 14, DIM))
	v.add_child(_btn("Trocar de personagem", func():
		player.save()
		_go_title()))
	return v


func _go_title() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload()")
	else:
		get_tree().reload_current_scene()


func _export_code() -> String:
	player.save()
	var f := FileAccess.open(Chars.path(), FileAccess.READ)
	if f == null:
		return ""
	return "ARSON2:" + Marshalls.utf8_to_base64(f.get_as_text())


func _download() -> void:
	var code := _export_code()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(code.to_utf8_buffer(), "arson-%s-%s.txt" % [Chars.nome, Time.get_date_string_from_system()], "text/plain")
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
	var ok = JavaScriptBridge.eval("confirm('Importar vai substituir o progresso DESTE personagem. Continuar?')", true)
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
	if str(c.get_value("jogador", "nome", "")) == "":
		c.set_value("jogador", "nome", Chars.nome)
	c.save(Chars.path())
	if str(c.get_value("jogador", "classe", player.classe)) != player.classe:
		# outra classe: volta à tela inicial para carregar o personagem certo
		_go_title()
		return
	player.reload()
	_refresh_char()
	CombatText.add(player.global_position + Vector2(0, -130), "Progresso importado!", Color(0.5, 1, 0.5), true)


func _alert(t: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("alert(%s)" % JSON.stringify(t))
	else:
		push_warning(t)
