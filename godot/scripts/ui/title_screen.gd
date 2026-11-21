class_name TitleScreen
extends CanvasLayer
## Tela inicial: escolha da classe de mago (Fogo/Lava, Água/Gelo, Vento/Raio, Terra/Natureza)
## e do nome. O mundo aparece escuro ao fundo.

signal chosen(classe: String, nome: String)

const GOLD := Color(0.92, 0.82, 0.6)
const DIM := Color(0.72, 0.66, 0.58)

var selected := "fogo"
var _cards := {}
var _name: LineEdit
var _desc: Label


func setup(current: String, nome: String) -> void:
	layer = 10
	if MageClass.valid(current):
		selected = current
	_build(nome)
	_select(selected)


func _style(bg: Color, border: Color, w := 2, radius := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb


func _lbl(text: String, size: int, col: Color, center := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build(nome: String) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.012, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	col.add_child(_lbl("ARSON", 46, Color(1, 0.62, 0.22)))
	col.add_child(_lbl("Escolha a sua classe de mago — todas também dominam a magia de Luz", 15, DIM))

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(grid)
	for c in MageClass.ORDER:
		var card := _card(c)
		grid.add_child(card)
		_cards[c] = card

	_desc = _lbl("", 13, GOLD)
	_desc.custom_minimum_size = Vector2(880, 40)
	col.add_child(_desc)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var nl := _lbl("Nome:", 16, GOLD, false)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nl)
	_name = LineEdit.new()
	_name.text = nome
	_name.placeholder_text = "nome do personagem"
	_name.max_length = 16
	_name.custom_minimum_size = Vector2(240, 42)
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name.add_theme_font_size_override("font_size", 16)
	_name.text_submitted.connect(func(_t): _go())
	row.add_child(_name)
	var go := Button.new()
	go.text = "Entrar no mundo"
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(200, 46)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.add_theme_font_size_override("font_size", 18)
	go.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	go.add_theme_stylebox_override("normal", _style(Color(0.45, 0.16, 0.04), Color(1, 0.6, 0.25)))
	go.add_theme_stylebox_override("hover", _style(Color(0.6, 0.22, 0.05), Color(1, 0.75, 0.4)))
	go.add_theme_stylebox_override("pressed", _style(Color(0.3, 0.1, 0.03), Color(1, 0.6, 0.25)))
	go.pressed.connect(_go)
	row.add_child(go)


func _card(c: String) -> Control:
	var d := MageClass.info(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(214, 236)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			_select(c))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var emb := Emblem.new()
	emb.c1 = d.cor
	emb.c2 = d.cor2
	emb.custom_minimum_size = Vector2(0, 86)
	emb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(emb)
	v.add_child(_lbl(d.nome, 18, d.cor.lightened(0.15)))
	v.add_child(_lbl("%s · %s · Luz" % d.elementos, 13, GOLD))
	var ds := _lbl(d.desc, 12, DIM)
	ds.custom_minimum_size = Vector2(194, 0)
	v.add_child(ds)
	return p


func _select(c: String) -> void:
	selected = c
	for k in _cards:
		var d := MageClass.info(k)
		var on: bool = k == c
		_cards[k].add_theme_stylebox_override("panel", _style(
			Color(0.1, 0.07, 0.05, 0.95) if on else Color(0.05, 0.04, 0.035, 0.88),
			d.cor if on else Color(0.3, 0.24, 0.16), 3 if on else 2))
		_cards[k].modulate = Color.WHITE if on else Color(0.75, 0.75, 0.75)
	var d2 := MageClass.info(c)
	_desc.text = "Efeitos: %s\nInvocações: %s" % [d2.efeitos, d2.summon]


func _go() -> void:
	var nm := _name.text.strip_edges().substr(0, 16)
	if nm == "":
		nm = "Mago %d" % randi_range(100, 999)
	chosen.emit(selected, nm)
	queue_free()


## Emblema da classe: dois elementos girando em volta de um ponto de luz.
class Emblem:
	extends Control
	var c1 := Color.WHITE
	var c2 := Color.WHITE
	var _t := 0.0

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	func _draw() -> void:
		var o := size / 2
		for i in 6:
			var f := 1.0 - i / 6.0
			draw_circle(o, 34.0 * f + 4, Color(c1.r, c1.g, c1.b, 0.08 + 0.05 * i))
		for i in 2:
			var a := _t * 1.4 + PI * i
			var p := o + Vector2(cos(a) * 26, sin(a) * 12)
			var cc := c1 if i == 0 else c2
			draw_circle(p, 11, Color(cc.r, cc.g, cc.b, 0.35))
			draw_circle(p, 7, cc)
		draw_circle(o, 6, Color(1, 0.97, 0.85))
		draw_circle(o, 10, Color(1, 0.95, 0.7, 0.3))
