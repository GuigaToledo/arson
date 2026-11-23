extends Control
## App Android: primeira tela. Confere atualização e, se o app fechou sozinho da última vez,
## mostra onde parou (para mandar print) antes de abrir o jogo em modo leve.

const GAME := "res://scenes/island.tscn"
const GOLD := Color(0.95, 0.8, 0.5)

var _status: Label
var _upd: AppUpdate
var _waiting_update := true
var _hold := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.025, 0.02)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	c.add_child(v)
	v.add_child(_lbl("ARSON", 46, Color(1, 0.62, 0.22)))
	_status = _lbl("Procurando atualização…", 17, GOLD)
	v.add_child(_status)
	var boot := get_node_or_null("/root/Boot")
	if boot:
		boot.step("abertura")
	var caixa := VBoxContainer.new()  # conteúdo da caixa de registro (abaixo dos botões)
	caixa.add_theme_constant_override("separation", 6)
	if boot and boot.crashes >= 1:
		_hold = true
		# parado esperando "Abrir o jogo": fechar aqui não é queda (o contador de tentativas já foi gravado)
		boot.step("ok")
		var extra: String = ["", "", " e com o chão simplificado", ", chão simplificado e sem luzes", ", chão simplificado, sem luzes e sem detalhes", ", chão simplificado, sem luzes, detalhes nem cenário"][mini(boot.crashes, 5)]
		var aviso := "O jogo fechou sozinho da última vez (parou em: %s). Tentativa %d.
Vou abrir no modo leve%s. Se fechar de novo, mande um print desta tela." % [
			_curto(boot.last_step, 60), boot.crashes, extra]
		v.add_child(_lbl(aviso, 15, Color(1, 0.7, 0.55)))
		var b := Button.new()
		b.text = "Abrir o jogo"
		b.custom_minimum_size = Vector2(220, 48)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func():
			_hold = false
			_go())
		var cb := CenterContainer.new()
		cb.add_child(b)
		v.add_child(cb)
	# registro: caixa com rolagem ABAIXO dos botões (o botão nunca sai da tela, por maior que seja o texto)
	if boot and boot.prev_steps != "":
		caixa.add_child(_texto("Última abertura: " + _sem_repeticao(boot.prev_steps), 11, Color(0.6, 0.56, 0.5)))
	if boot and boot.crashes >= 1:
		var tail := Boot.log_tail()
		if tail != "":
			caixa.add_child(_texto(tail, 11, Color(0.75, 0.7, 0.62)))
	if caixa.get_child_count() > 0:
		var rolagem := ScrollContainer.new()
		rolagem.custom_minimum_size = Vector2(900, 160 if boot and boot.crashes >= 1 else 100)
		rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		rolagem.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		var fundo := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.02, 0.015, 0.012, 0.9)
		st.border_color = Color(0.5, 0.38, 0.22)
		st.set_border_width_all(1)
		st.set_corner_radius_all(6)
		st.set_content_margin_all(8)
		fundo.add_theme_stylebox_override("panel", st)
		fundo.add_child(rolagem)
		rolagem.add_child(caixa)
		caixa.custom_minimum_size = Vector2(880, 0)
		v.add_child(_lbl("Registro (arraste para rolar)", 11, Color(0.55, 0.5, 0.44)))
		v.add_child(fundo)
	# só procura atualização depois da tela aparecer (se algo travar, a tela já foi vista)
	for i in 3:
		await get_tree().process_frame
	if boot:
		boot.step("abertura desenhada")
	_upd = AppUpdate.new()
	add_child(_upd)
	if boot:
		boot.step("procurando atualização")
	_upd.done.connect(func():
		_waiting_update = false
		_go())
	# sem resposta em 6 s, segue com a versão que já tem
	get_tree().create_timer(6.0).timeout.connect(func():
		if _waiting_update and _upd._box == null:
			_waiting_update = false
			_go())


func _go() -> void:
	if _hold or _waiting_update:
		return
	_status.text = "Carregando o mundo…"
	var boot := get_node_or_null("/root/Boot")
	if boot:
		boot.step("atualização ok")
	set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(GAME)


## Texto de várias linhas para dentro da caixa de registro.
func _texto(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = Vector2(860, 0)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _curto(t: String, n: int) -> String:
	return t if t.length() <= n else t.substr(0, n) + "…"


## "a → b → b → b → c" vira "a → b ×3 → c" (o registro enchia de passos repetidos).
func _sem_repeticao(passos: String) -> String:
	var partes := passos.split(" → ")
	var out := PackedStringArray()
	var i := 0
	while i < partes.size():
		var j := i
		while j + 1 < partes.size() and partes[j + 1] == partes[i]:
			j += 1
		out.append(partes[i] if j == i else "%s ×%d" % [partes[i], j - i + 1])
		i = j + 1
	return " → ".join(out)


func _lbl(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
