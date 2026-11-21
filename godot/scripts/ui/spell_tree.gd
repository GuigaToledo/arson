class_name SpellTree
extends Control
## Árvore de magias da classe: elemento A | fusões | elemento B | Luz.
## Cada magia libera 5 níveis depois da anterior (1, 6, 11, 16, 21, 26). As fusões (escudo fundido, 7 e 8) ficam no meio,
## ligadas aos dois elementos. Toque/passe o mouse num círculo para ver a descrição.

var player: Player
var _nodes: Array = []  # [pos, info]
var _hover := -1
## Magia escolhida (toque/clique) para colocar na barra.
var _sel_id := ""
var _slots: Array = []  # Rect2 das 8 casas da barra
var _t := 0.0

const R := 16.0
const TOP := 62.0
const STEP := 38.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(d: float) -> void:
	if is_visible_in_tree():
		_t += d
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	var p := Vector2(-1, -1)
	if e is InputEventMouseMotion or (e is InputEventMouseButton and e.pressed):
		p = e.position
	elif e is InputEventScreenTouch and e.pressed:
		p = e.position
	if p.x < 0:
		return
	var click: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT) or e is InputEventScreenTouch
	_hover = -1
	for i in _nodes.size():
		if p.distance_to(_nodes[i][0]) <= R + 6:
			_hover = i
			if click:
				_sel_id = str(_nodes[i][1].id)
	if click:
		for j in _slots.size():
			if (_slots[j] as Rect2).has_point(p) and _sel_id != "":
				player.set_bar(j, _sel_id)
				_sel_id = ""


func _row(t: int) -> float:
	return TOP + (t - 1) * STEP


func _draw() -> void:
	if player == null:
		return
	_nodes.clear()
	var font := ThemeDB.fallback_font
	var els := Spellbook.elements_of(player.classe)
	var ea: String = els[0]
	var eb: String = els[1]
	var la := player.elem_level(ea)
	var lb := player.elem_level(eb)
	var w := size.x
	var xa := w * 0.05 + R
	var xf := w * 0.29
	var xb := w * 0.53
	var xl := w * 0.79
	var ca: Color = Spellbook.ELEMENTS[ea].cor
	var cb: Color = Spellbook.ELEMENTS[eb].cor
	var cl: Color = Spellbook.ELEMENTS.luz.cor
	var cf := ca.lerp(cb, 0.5)
	var fus: Array = Spellbook.FUSOES[player.classe]

	# divisória antes da Luz
	draw_line(Vector2(xl - 28, 8), Vector2(xl - 28, _row(8) + 22), Color(0.4, 0.3, 0.18, 0.6), 1.0)

	# cabeçalhos
	_header(font, Vector2(xa - R, 20), Spellbook.ELEMENTS[ea].nome, la, player.skills[ea], ca, ea)
	_header(font, Vector2(xb - R, 20), Spellbook.ELEMENTS[eb].nome + ("" if lb > 0 else " (base 31)"), lb, player.skills[eb], cb, eb)
	_header(font, Vector2(xl - R, 20), "Luz", player.elem_level("luz"), player.skills.luz, cl, "luz")
	draw_string(font, Vector2(xf - 30, 20), "Fusões", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cf.lightened(0.2))

	# ligações (acendem quando a magia de baixo realmente libera)
	var U := func(id: String) -> bool: return player.spell_unlocked(id)
	for t in range(1, 6):
		_link(Vector2(xa, _row(t)), Vector2(xa, _row(t + 1)), ca, U.call("%s:%d" % [ea, t + 1]))
		_link(Vector2(xb, _row(t)), Vector2(xb, _row(t + 1)), cb, U.call("%s:%d" % [eb, t + 1]))
	for t in range(1, 8):
		_link(Vector2(xl, _row(t)), Vector2(xl, _row(t + 1)), cl, U.call("luz:%d" % (t + 1)))
	_link(Vector2(xa, _row(3)), Vector2(xf, _row(3)), ca, U.call("fus:3"))
	_link(Vector2(xb, _row(3)), Vector2(xf, _row(3)), cb, U.call("fus:3"))
	_link(Vector2(xa, _row(5)), Vector2(xf, _row(5)), ca, U.call("fus:5"))
	_link(Vector2(xb, _row(5)), Vector2(xf, _row(5)), cb, U.call("fus:5"))
	_link(Vector2(xa, _row(6)), Vector2(xf, _row(7)), ca, U.call("fus:7"))
	_link(Vector2(xb, _row(6)), Vector2(xf, _row(7)), cb, U.call("fus:7"))
	_link(Vector2(xf, _row(7)), Vector2(xf, _row(8)), cf, U.call("fus:8"))

	# nós
	for t in range(1, 7):
		var ida := "%s:%d" % [ea, t]
		var idb := "%s:%d" % [eb, t]
		_node(font, Vector2(xa, _row(t)), t, Spellbook.ELEMENTS[ea].magias[t - 1], ca, U.call(ida),
			{"id": ida, "el": ea, "t": t, "req": player.spell_req(ida)})
		_node(font, Vector2(xb, _row(t)), t, Spellbook.ELEMENTS[eb].magias[t - 1], cb, U.call(idb),
			{"id": idb, "el": eb, "t": t, "req": player.spell_req(idb)})
	for t in range(1, 9):
		var idl := "luz:%d" % t
		_node(font, Vector2(xl, _row(t)), t, Spellbook.ELEMENTS.luz.magias[t - 1], cl, U.call(idl),
			{"id": idl, "el": "luz", "t": t, "req": player.spell_req(idl)})
	_node(font, Vector2(xf, _row(3)), 3, fus[0], cf, U.call("fus:3"),
		{"id": "fus:3", "fus": 3, "nome": fus[0], "req": player.spell_req("fus:3"),
		"desc": "Os dois escudos se fundem num só, mais forte."})
	_node(font, Vector2(xf, _row(5)), 5, Spellbook.SUMMON_FUSION[player.classe], cf, U.call("fus:5"),
		{"id": "fus:5", "fus": 5, "nome": Spellbook.SUMMON_FUSION[player.classe], "req": player.spell_req("fus:5"),
		"desc": "Funde as duas invocações num só guardião aprimorado (mais vida e força, os dois efeitos). Usar uma invocação separada desfaz a fundida."})
	_node(font, Vector2(xf, _row(7)), 7, fus[1], cf, U.call("fus:7"),
		{"id": "fus:7", "fus": 7, "nome": fus[1], "req": player.spell_req("fus:7"),
		"desc": "Magia suprema: os dois elementos num ataque de alvo único, dano altíssimo."})
	_node(font, Vector2(xf, _row(8)), 8, fus[2], cf, U.call("fus:8"),
		{"id": "fus:8", "fus": 8, "nome": fus[2], "req": player.spell_req("fus:8"),
		"desc": "Magia suprema em área com os dois elementos, dano altíssimo."})

	# descrição do círculo escolhido
	_draw_bar(font)
	var box := Rect2(0, size.y - 104, size.x, 54)
	if _hover < 0 and _sel_id != "":
		for k in _nodes.size():
			if str(_nodes[k][1].id) == _sel_id:
				_hover = k
	draw_rect(box, Color(0.04, 0.03, 0.02, 0.85))
	draw_rect(box, Color(0.4, 0.3, 0.18, 0.7), false, 1.0)
	if _hover < 0 or _hover >= _nodes.size():
		draw_string(font, box.position + Vector2(10, 22), "Toque numa magia para ver o que ela faz; depois toque numa casa da barra para colocá-la.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.66, 0.58))
		draw_string(font, box.position + Vector2(10, 42), "Cada elemento sobe de nível sozinho, quando você usa as magias dele.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.55, 0.48))
		return
	var n: Dictionary = _nodes[_hover][1]
	var title := ""
	var desc := ""
	if n.has("fus"):
		title = "%s — %s" % [n.nome, "Escudo fundido" if n.fus == 3 else ("Invocação fundida" if n.fus == 5 else Spellbook.TIER_KIND[n.fus])]
		desc = n.desc
	else:
		var el: Dictionary = Spellbook.ELEMENTS[n.el]
		title = "%s — %s %d" % [el.magias[n.t - 1], el.nome, n.t]
		if n.el != "luz":
			title += " · " + Spellbook.TIER_KIND[n.t]
		desc = Spellbook.spell_desc(n.el, n.t)
		var sid2 := "%s:%d" % [n.el, n.t]
		desc += "   ·   Melhoria %d/5" % player.spell_up(sid2)
	var col := Color(0.5, 1, 0.55) if n.ok else Color(1, 0.55, 0.4)
	draw_string(font, box.position + Vector2(10, 21), title, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.62, 15, Color(1, 0.88, 0.6))
	draw_string(font, box.position + Vector2(size.x * 0.64, 21), ("Liberada" if n.ok else "Requer: " + n.req), HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.36 - 8, 13, col)
	draw_string(font, box.position + Vector2(10, 43), desc, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 13, Color(0.85, 0.8, 0.72))


## Barra de magias (8 casas) embaixo da árvore.
func _draw_bar(font: Font) -> void:
	_slots.clear()
	var y := size.y - 42
	var lab := "Escolha a casa da barra:" if _sel_id != "" else "Sua barra:"
	draw_string(font, Vector2(0, y + 26), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.85, 0.5) if _sel_id != "" else Color(0.72, 0.66, 0.58))
	var x0 := 190.0 if _sel_id != "" else 90.0
	var w := (size.x - x0) / 8.0
	for i in 8:
		var r := Rect2(x0 + i * w + 2, y, w - 4, 40)
		_slots.append(r)
		var s := player.bar_spell(i)
		var col: Color = s.color if not s.is_empty() else Color(0.4, 0.35, 0.3)
		draw_rect(r, Color(0.05, 0.04, 0.03, 0.9))
		var bc := Color(1, 0.8, 0.4) if _sel_id != "" else Color(col, 0.7)
		draw_rect(r, bc, false, 2.0 if _sel_id != "" else 1.5)
		draw_string(font, r.position + Vector2(4, 13), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.9, 0.6))
		draw_circle(r.position + Vector2(r.size.x - 10, 11), 5, col)
		var nm: String = s.curto if not s.is_empty() else "vazio"
		draw_string(font, r.position + Vector2(4, 33), nm, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 6, 12, Color(0.95, 0.9, 0.8) if not s.is_empty() and player.spell_unlocked(str(player.bar[i])) else Color(0.55, 0.5, 0.45))


func _header(font: Font, p: Vector2, name: String, lv: int, sk: Array, c: Color, k: String) -> void:
	draw_string(font, p, "%s  nv %d" % [name, lv], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c.lightened(0.2))
	var f := clampf(float(sk[1]) / float(Rules.skill_need(k, int(sk[0]))), 0, 1)
	draw_rect(Rect2(p + Vector2(0, 7), Vector2(120, 4)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(p + Vector2(0, 7), Vector2(120 * f, 4)), c)


func _link(a: Vector2, b: Vector2, c: Color, on: bool) -> void:
	if on:
		draw_line(a, b, Color(c.r, c.g, c.b, 0.25), 7.0)
		draw_line(a, b, c, 2.0)
	else:
		draw_line(a, b, Color(0.3, 0.27, 0.24, 0.7), 2.0)


func _node(font: Font, p: Vector2, t: int, name: String, c: Color, ok: bool, info: Dictionary) -> void:
	info["ok"] = ok
	var i := _nodes.size()
	_nodes.append([p, info])
	var hov := i == _hover
	if ok:
		var pulse := 0.5 + 0.5 * sin(_t * 2.5 + t)
		draw_circle(p, R + 6 + pulse * 2, Color(c.r, c.g, c.b, 0.12))
		draw_circle(p, R, c.darkened(0.55))
		draw_circle(p, R - 4, c.darkened(0.15))
		draw_arc(p, R, 0, TAU, 32, c.lightened(0.3), 2.0)
	else:
		draw_circle(p, R, Color(0.1, 0.09, 0.08))
		draw_arc(p, R, 0, TAU, 32, Color(0.35, 0.3, 0.26), 2.0)
	if hov or str(info.id) == _sel_id:
		draw_arc(p, R + 4, 0, TAU, 32, Color(1, 0.9, 0.6), 2.0)
	if player.bar.has(str(info.id)):
		draw_circle(p + Vector2(R - 2, -R + 2), 5, Color(1, 0.8, 0.3))
	var num := str(t)
	var tw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, p + Vector2(-tw / 2, 5), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1) if ok else Color(0.5, 0.46, 0.42))
	draw_string(font, p + Vector2(R + 6, 5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.9, 0.8) if ok else Color(0.5, 0.46, 0.42))
