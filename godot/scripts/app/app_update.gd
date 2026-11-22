class_name AppUpdate
extends CanvasLayer
## App Android: ao abrir, confere se tem versão nova do jogo. Se tiver, mostra um aviso no topo
## com o botão "Atualizar", que baixa só o pacote do jogo e reinicia. Se a mudança exigir o app
## novo (APK), o botão abre o download do app.

## Terminou: sem novidade, sem internet ou o jogador tocou em "Depois".
signal done

const BASE := "https://github.com/guigatoledo/arson/releases/download/app/"
const GOLD := Color(0.95, 0.8, 0.5)

var _http: HTTPRequest
var _box: PanelContainer
var _msg: Label
var _bar: ProgressBar
var _row: HBoxContainer
var _remote := {}
var _baixando := false


func _ready() -> void:
	layer = 30
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_versao)
	_http.request(BASE + "versao.json?t=%d" % Time.get_unix_time_from_system())


func _process(_d: float) -> void:
	if _baixando and _bar:
		var tot := int(_remote.get("tam", 0))
		if tot <= 0:
			tot = _http.get_body_size()
		if tot > 0:
			_bar.value = 100.0 * _http.get_downloaded_bytes() / tot
			_msg.text = "Baixando a atualização… %d%%  (%.1f de %.1f MB)" % [int(_bar.value), _http.get_downloaded_bytes() / 1048576.0, tot / 1048576.0]


func _on_versao(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_http.request_completed.disconnect(_on_versao)
	var bt := get_node_or_null("/root/Boot")
	if bt:
		bt.step("resposta da atualização %d/%d" % [result, code])
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		done.emit()
		return  # sem internet ou sem resposta: joga a versão que já tem
	var d = JSON.parse_string(body.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY:
		done.emit()
		return
	_remote = d
	var atual := Boot._read("res://app/jogo.txt")
	if str(d.get("jogo", "")) == atual or atual == "":
		done.emit()
		return
	var boot := get_node_or_null("/root/Boot")
	var sig: String = boot.app_sig if boot else ""
	if str(d.get("assinatura", "")) == sig:
		_show("Nova versão do jogo disponível!", "Atualizar", _baixar)
	else:
		_show("Saiu uma versão nova do app. Baixe e instale por cima (seu progresso continua).", "Baixar app", func():
			OS.shell_open(BASE + str(d.get("apk", "arson.apk"))))


func _show(text: String, label: String, cb: Callable) -> void:
	# esperando a escolha do jogador (Atualizar / Baixar app / Depois): se fechar aqui (inclusive para
	# instalar o app novo por cima), não é queda. Se travar depois, as etapas seguintes vêm depois deste ok.
	var bt0 := get_node_or_null("/root/Boot")
	if bt0:
		bt0.step("ok")
	_box = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.09, 0.05, 0.03, 0.94)
	st.border_color = Color(0.79, 0.55, 0.24)
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	_box.add_theme_stylebox_override("panel", st)
	_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.position.y = 10
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_box.add_child(v)
	_msg = Label.new()
	_msg.text = text
	_msg.add_theme_font_size_override("font_size", 17)
	_msg.add_theme_color_override("font_color", GOLD)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_msg)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(380, 14)
	_bar.show_percentage = false
	_bar.visible = false
	v.add_child(_bar)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 12)
	v.add_child(_row)
	_row.add_child(_btn(label, cb, true))
	_row.add_child(_btn("Depois", func():
		_box.queue_free()
		done.emit(), false))


func _btn(text: String, cb: Callable, main: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 44)
	b.add_theme_font_size_override("font_size", 18)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.85, 0.45, 0.14) if main else Color(0.2, 0.13, 0.09)
	st.border_color = Color(0.79, 0.55, 0.24)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.add_theme_color_override("font_color", Color(0.1, 0.04, 0.01) if main else GOLD)
	b.pressed.connect(cb)
	return b


func _baixar() -> void:
	if _baixando:
		return
	_baixando = true
	_row.visible = false
	_bar.visible = true
	_http.download_file = "user://jogo_novo.pck"
	_http.timeout = 0.0
	_http.request_completed.connect(_on_pack)
	_http.request(BASE + "jogo.pck?t=%d" % Time.get_unix_time_from_system())


func _on_pack(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_baixando = false
	var novo := "user://jogo_novo.pck"
	var tam := int(_remote.get("tam", 0))
	var f := FileAccess.open(novo, FileAccess.READ)
	var got := f.get_length() if f else 0
	f = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or got == 0 or (tam > 0 and got != tam):
		DirAccess.remove_absolute(novo)
		_msg.text = "Não deu para baixar (internet?). Tente de novo."
		_row.visible = true
		_bar.visible = false
		_http.request_completed.disconnect(_on_pack)
		_baixando = false
		return
	DirAccess.remove_absolute(Boot.PACK)
	DirAccess.rename_absolute(novo, Boot.PACK)
	var inf := FileAccess.open(Boot.INFO, FileAccess.WRITE)
	inf.store_string(JSON.stringify({"jogo": _remote.get("jogo", ""), "assinatura": _remote.get("assinatura", "")}))
	inf = null
	_msg.text = "Atualizado! Reiniciando o jogo… (se ele fechar, é só abrir de novo)"
	await get_tree().create_timer(1.5).timeout
	# fechar para atualizar não é falha: sem isso o app contava como "fechou sozinho" e, na
	# segunda vez, apagava a atualização (ficava pedindo para atualizar sem parar)
	var bt := get_node_or_null("/root/Boot")
	if bt:
		bt.step("ok")
	OS.set_restart_on_exit(true)
	get_tree().quit()
