class_name TitleScreen
extends CanvasLayer
## Tela inicial: 4 vagas de personagem. Vaga vazia → criar (escolher a classe de mago e o nome).
## O mundo aparece escuro ao fundo.

signal chosen(slot: int)

const GOLD := Color(0.92, 0.82, 0.6)
const DIM := Color(0.72, 0.66, 0.58)

var selected := "fogo"
var _slot_new := 1
var _cards := {}
var _name: LineEdit
var _desc: Label
var _page: Control
var _confirm_del := -1


func setup() -> void:
	layer = 10
	Chars.migrate()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.012, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_show_slots()


func _clear() -> CenterContainer:
	if _page:
		_page.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_page = center
	return center


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


func _button(text: String, cb: Callable, main := true, size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(1, 0.9, 0.7) if main else DIM)
	var c1 := Color(0.45, 0.16, 0.04) if main else Color(0.1, 0.07, 0.05)
	var c2 := Color(1, 0.6, 0.25) if main else Color(0.4, 0.3, 0.2)
	b.add_theme_stylebox_override("normal", _style(c1, c2))
	b.add_theme_stylebox_override("hover", _style(c1.lightened(0.15), c2.lightened(0.2)))
	b.add_theme_stylebox_override("pressed", _style(c1.darkened(0.3), c2))
	b.pressed.connect(cb)
	return b


# ------------------------------------------------------------ vagas
func _show_slots() -> void:
	var center := _clear()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)
	col.add_child(_lbl("ARSON", 46, Color(1, 0.62, 0.22)))
	col.add_child(_lbl("Escolha o seu personagem — até 4 por navegador", 15, DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for n in range(1, Chars.MAX + 1):
		row.add_child(_slot_card(n))


func _slot_card(n: int) -> Control:
	var inf := Chars.info(n)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(214, 270)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	if not inf.existe:
		p.add_theme_stylebox_override("panel", _style(Color(0.05, 0.04, 0.035, 0.85), Color(0.3, 0.24, 0.16)))
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 70)
		v.add_child(sp)
		v.add_child(_lbl("Vaga %d livre" % n, 17, DIM))
		var sp2 := Control.new()
		sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sp2)
		v.add_child(_button("+ Criar personagem", func(): _show_create(n)))
		return p
	var d := MageClass.info(inf.classe)
	p.add_theme_stylebox_override("panel", _style(Color(0.09, 0.065, 0.05, 0.95), d.cor.darkened(0.3)))
	var emb := Emblem.new()
	emb.c1 = d.cor
	emb.c2 = d.cor2
	emb.custom_minimum_size = Vector2(0, 80)
	emb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(emb)
	v.add_child(_lbl(inf.nome, 19, Color(1, 0.92, 0.78)))
	v.add_child(_lbl(d.nome, 14, d.cor.lightened(0.15)))
	v.add_child(_lbl("Nível %d" % inf.nivel, 14, GOLD))
	var sp3 := Control.new()
	sp3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp3)
	v.add_child(_button("Jogar", func(): _play(n), true, 18))
	var del := _button("Apagar" if _confirm_del != n else "Confirmar: apagar!", func(): _delete(n), false, 12)
	del.custom_minimum_size = Vector2(0, 30)
	v.add_child(del)
	return p


func _delete(n: int) -> void:
	if _confirm_del != n:
		_confirm_del = n
	else:
		_confirm_del = -1
		Chars.delete(n)
	_show_slots()


func _play(n: int) -> void:
	Chars.use(n)
	chosen.emit(n)
	queue_free()


# ------------------------------------------------------------ criar
func _show_create(n: int) -> void:
	_slot_new = n
	_confirm_del = -1
	var center := _clear()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	col.add_child(_lbl("Novo personagem (vaga %d)" % n, 30, Color(1, 0.62, 0.22)))
	col.add_child(_lbl("Escolha a classe de mago — todas também dominam a magia de Luz", 15, DIM))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(grid)
	_cards.clear()
	for c in MageClass.ORDER:
		var card := _class_card(c)
		grid.add_child(card)
		_cards[c] = card
	_desc = _lbl("", 13, GOLD)
	_desc.custom_minimum_size = Vector2(880, 40)
	col.add_child(_desc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	row.add_child(_button("Voltar", _show_slots, false, 15))
	var nl := _lbl("Nome:", 16, GOLD, false)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nl)
	_name = LineEdit.new()
	_name.placeholder_text = "nome do personagem"
	_name.max_length = 16
	_name.custom_minimum_size = Vector2(240, 42)
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name.add_theme_font_size_override("font_size", 16)
	_name.text_submitted.connect(func(_t): _create())
	row.add_child(_name)
	var go := _button("Criar e entrar", _create, true, 18)
	go.custom_minimum_size = Vector2(190, 46)
	row.add_child(go)
	_select(selected)


func _class_card(c: String) -> Control:
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


func _create() -> void:
	var nm := _name.text.strip_edges().substr(0, 16)
	if nm == "":
		nm = "Mago %d" % randi_range(100, 999)
	Chars.create(_slot_new, selected, nm)
	_play(_slot_new)


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
			ElemArt.circle(self, o, 34.0 * f + 4, Color(c1.r, c1.g, c1.b, 0.08 + 0.05 * i))
		for i in 2:
			var a := _t * 1.4 + PI * i
			var p := o + Vector2(cos(a) * 26, sin(a) * 12)
			var cc := c1 if i == 0 else c2
			ElemArt.circle(self, p, 11, Color(cc.r, cc.g, cc.b, 0.35))
			ElemArt.circle(self, p, 7, cc)
		ElemArt.circle(self, o, 6, Color(1, 0.97, 0.85))
		ElemArt.circle(self, o, 10, Color(1, 0.95, 0.7, 0.3))
