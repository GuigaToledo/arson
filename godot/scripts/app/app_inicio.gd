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
		if boot.prev_steps != "":
			var ps := _lbl("Última abertura: " + boot.prev_steps, 11, Color(0.6, 0.56, 0.5))
			ps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ps.custom_minimum_size = Vector2(880, 0)
			v.add_child(ps)
	if boot and boot.crashes >= 1:
		_hold = true
		var extra := ["", "", " e com o chão simplificado", ", chão simplificado e sem luzes", ", chão simplificado, sem luzes e sem detalhes", ", chão simplificado, sem luzes, detalhes nem cenário"][mini(boot.crashes, 5)]
		var aviso := "O jogo fechou sozinho da última vez (parou em: %s). Tentativa %d.\nVou abrir no modo leve%s. Se fechar de novo, mande um print desta tela." % [
			boot.last_step, boot.crashes, extra]
		v.add_child(_lbl(aviso, 16, Color(1, 0.7, 0.55)))
		var tail := Boot.log_tail()
		if tail != "":
			var lg := _lbl(tail, 11, Color(0.75, 0.7, 0.62))
			lg.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			lg.custom_minimum_size = Vector2(880, 0)
			lg.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			v.add_child(lg)
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


func _lbl(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
