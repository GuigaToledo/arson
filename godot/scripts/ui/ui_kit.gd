class_name UiKit
## Estilo comum dos menus (inventário, loja, menu do jogo): couro escuro, borda dourada,
## sombra e cantos arredondados, como as janelas do Diablo 2 com cara de desenho.

const GOLD := Color(0.95, 0.8, 0.5)
const DIM := Color(0.72, 0.66, 0.58)
const EMBER := Color(1, 0.6, 0.25)


static func box(bg := Color(0.07, 0.05, 0.04, 0.97), border := Color(0.66, 0.48, 0.26), radius := 12, margin := 12, bw := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	sb.anti_aliasing = true
	return sb


static func inner(bg := Color(0.11, 0.08, 0.06), border := Color(0.34, 0.25, 0.15), radius := 8, margin := 10) -> StyleBoxFlat:
	var sb := box(bg, border, radius, margin, 1)
	sb.shadow_size = 0
	return sb


static func label(text: String, size := 15, col := GOLD, outline := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.0))
	return l


static func title(text: String, size := 20) -> Label:
	return label(text, size, Color(1, 0.72, 0.36), true)


static func button(text: String, cb: Callable, size := 15, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_hover_color", Color(1, 0.9, 0.7))
	var base := Color(0.36, 0.13, 0.04) if accent else Color(0.15, 0.1, 0.06)
	var edge := Color(1, 0.6, 0.25) if accent else Color(0.55, 0.4, 0.22)
	b.add_theme_stylebox_override("normal", inner(base, edge, 8, 8))
	b.add_theme_stylebox_override("hover", inner(base.lightened(0.12), edge.lightened(0.2), 8, 8))
	b.add_theme_stylebox_override("pressed", inner(Color(0.42, 0.16, 0.05), Color(1, 0.7, 0.35), 8, 8))
	b.add_theme_stylebox_override("disabled", inner(Color(0.1, 0.08, 0.07), Color(0.25, 0.2, 0.15), 8, 8))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func sep() -> HSeparator:
	var s := HSeparator.new()
	var st := StyleBoxLine.new()
	st.color = Color(0.5, 0.36, 0.2, 0.6)
	st.thickness = 1
	s.add_theme_stylebox_override("separator", st)
	return s


## Área de jogo livre no meio da tela (entre o joystick e os botões de ataque, acima da barra de magias).
static func center_rect(vp: Vector2, want: Vector2) -> Rect2:
	var w := clampf(minf(want.x, vp.x - 2.0 * 316.0), minf(470.0, vp.x - 20.0), want.x)
	var h := minf(want.y, vp.y - 120.0)
	return Rect2(Vector2(floor((vp.x - w) * 0.5), floor(maxf(54.0, (vp.y - 64.0 - h) * 0.5))), Vector2(w, h))
