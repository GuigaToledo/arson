class_name SpellTree
extends Control
## Grimório: árvore de magias da classe em três painéis pintados (elemento A | elemento B | Luz),
## no estilo das árvores de talentos clássicas: placa com o nível no topo, ícones quadrados que
## ficam cinza enquanto bloqueados e setas que mostram a ordem em que as magias liberam.
## As fusões (escudo fundido, invocação fundida e as duas supremas) ficam na COSTURA entre os
## painéis dos dois elementos, como medalhões das duas cores, com setas vindo dos dois lados.
## Toque/passe o mouse numa magia para ver a descrição; toque e depois uma casa da barra para colocá-la.

var player: Player
var _nodes: Array = []  # [Rect2, info]
var _hover := -1
## Magia escolhida (toque/clique) para colocar na barra.
var _sel_id := ""
var _slots: Array = []  # Rect2 das 8 casas da barra
var _t := 0.0
var _canvas: Control
var _bgs: Array = []  # ColorRect com o fundo pintado de cada painel

const BOTTOM := 106.0
const HEAD := 38.0
## Coluna (0, 1, 2) de cada magia dentro do painel. No elemento A a coluna 2 encosta na costura
## das fusões (escudo e invocação ficam ali); no B é espelhado.
const COL_A := [1, 0, 2, 1, 2, 1]
const COL_LUZ := [1, 0, 2, 1, 0, 2, 1, 1]
const FUS_ROW := {3: 3, 5: 5, 7: 7, 8: 8}

const BG_SHADER := """
shader_type canvas_item;
uniform vec4 glow : source_color;
uniform vec4 base : source_color;
uniform float seed = 0.0;
uniform float locked = 0.0;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.0) * 43758.5453); }
float n(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p){ float v = 0.0; float a = 0.5; for (int k = 0; k < 5; k++){ v += a * n(p); p = p * 2.03 + 7.1; a *= 0.5; } return v; }
void fragment(){
	vec2 uv = UV;
	float t = TIME * 0.025;
	float s = fbm(uv * vec2(2.2, 4.0) + vec2(seed, -t * 3.0));
	float s2 = fbm(uv * vec2(5.0, 9.0) + vec2(-t, seed * 2.0) + s);
	vec3 c = mix(base.rgb * 0.55, base.rgb, uv.y);
	float rise = smoothstep(0.15, 1.0, uv.y) * (0.45 + 0.75 * s);
	c += glow.rgb * rise * 0.42;
	c += glow.rgb * pow(s2, 3.0) * 0.35;
	c *= 0.9 + 0.12 * sin((uv.x * 3.0 + uv.y * 7.0) + s * 6.0);
	vec2 e = min(uv, 1.0 - uv);
	float vig = smoothstep(0.0, 0.22, min(e.x * 1.4, e.y));
	c *= mix(0.35, 1.0, vig);
	float g = dot(c, vec3(0.3, 0.55, 0.15));
	c = mix(c, vec3(g) * 0.55, locked);
	COLOR = vec4(c, 1.0);
}
"""

const BASE_COL := {
	"fogo": Color(0.16, 0.05, 0.03), "lava": Color(0.14, 0.04, 0.02), "agua": Color(0.03, 0.07, 0.15),
	"gelo": Color(0.06, 0.1, 0.15), "vento": Color(0.05, 0.11, 0.09), "raio": Color(0.07, 0.05, 0.15),
	"terra": Color(0.12, 0.08, 0.04), "natureza": Color(0.04, 0.1, 0.04), "luz": Color(0.14, 0.11, 0.05),
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sh := Shader.new()
	sh.code = BG_SHADER
	for i in 3:
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("seed", float(i) * 3.7 + 1.0)
		r.material = m
		add_child(r)
		_bgs.append(r)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_paint)
	add_child(_canvas)


func _process(d: float) -> void:
	if is_visible_in_tree():
		_t += d
		_canvas.queue_redraw()


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
		if (_nodes[i][0] as Rect2).grow(5).has_point(p):
			_hover = i
			if click:
				_sel_id = str(_nodes[i][1].id)
	if click:
		for j in _slots.size():
			if (_slots[j] as Rect2).has_point(p) and _sel_id != "":
				player.set_bar(j, _sel_id)
				_sel_id = ""


# ------------------------------------------------------------ medidas
var _icon := 34.0
var _rowh := 40.0
var _pw := 200.0
var _seam := 46.0
var _px := [0.0, 0.0, 0.0]
var _treeh := 300.0


func _layout() -> void:
	var w := size.x
	_treeh = size.y - BOTTOM - 4.0
	_rowh = (_treeh - HEAD - 6.0) / 8.0
	_icon = clampf(_rowh * 0.8, 22.0, 46.0)
	_seam = _icon * 1.45
	var gap := 8.0
	_pw = (w - _seam - gap) / 3.0
	_px = [0.0, _pw + _seam, 2.0 * _pw + _seam + gap]
	for i in 3:
		var r: ColorRect = _bgs[i]
		r.position = Vector2(_px[i], 0)
		r.size = Vector2(_pw, _treeh)


func _cx(panel: int, col: int) -> float:
	return _px[panel] + _pw * (0.2 + 0.3 * col)


func _ry(t: int) -> float:
	return HEAD + 6.0 + _rowh * (t - 0.5)


func _seam_x() -> float:
	return _pw + _seam * 0.5


# ------------------------------------------------------------ desenho
func _paint() -> void:
	if player == null:
		return
	_layout()
	_nodes.clear()
	var c := _canvas
	var font := ThemeDB.fallback_font
	var els := Spellbook.elements_of(player.classe)
	var ea: String = els[0]
	var eb: String = els[1]
	var la := player.elem_level(ea)
	var lb := player.elem_level(eb)
	var pe := [ea, eb, "luz"]
	for i in 3:
		var m: ShaderMaterial = (_bgs[i] as ColorRect).material
		var ce: Color = Spellbook.ELEMENTS[pe[i]].cor
		m.set_shader_parameter("glow", ce)
		m.set_shader_parameter("base", BASE_COL.get(pe[i], Color(0.1, 0.08, 0.06)))
		m.set_shader_parameter("locked", 0.85 if i == 1 and lb <= 0 else 0.0)
	var U := func(id: String) -> bool: return player.spell_unlocked(id)

	# molduras dos painéis e placas do topo
	for i in 3:
		var pr := Rect2(_px[i], 0, _pw, _treeh)
		c.draw_rect(pr, Color(0, 0, 0, 0.9), false, 3.0)
		c.draw_rect(pr.grow(-2), Color(0.5, 0.38, 0.2, 0.9), false, 1.0)
	_plaque(c, font, 0, Spellbook.ELEMENTS[ea].nome, la, player.skills[ea], ea)
	_plaque(c, font, 1, Spellbook.ELEMENTS[eb].nome, lb, player.skills[eb], eb)
	_plaque(c, font, 2, "Luz", player.elem_level("luz"), player.skills.luz, "luz")

	# setas dentro de cada elemento (acendem quando a magia de destino libera)
	for side in 2:
		var el: String = pe[side]
		var col: Color = Spellbook.ELEMENTS[el].cor
		for t in range(1, 6):
			_link(c, _spos(side, t), _spos(side, t + 1), col, U.call("%s:%d" % [el, t + 1]))
	var cl: Color = Spellbook.ELEMENTS.luz.cor
	for t in range(1, 8):
		_link(c, _lpos(t), _lpos(t + 1), cl, U.call("luz:%d" % (t + 1)))
	# setas até as fusões, dos dois lados da costura
	var sx := _seam_x()
	var r2 := _icon * 0.62
	for side in 2:
		var el2: String = pe[side]
		var col2: Color = Spellbook.ELEMENTS[el2].cor
		var dirx := 1.0 if side == 0 else -1.0
		for ft in [3, 5]:
			var a := _spos(side, ft)
			_arrow(c, PackedVector2Array([a + Vector2(dirx * _icon * 0.5, 0), Vector2(sx - dirx * r2, a.y)]), col2, U.call("fus:%d" % ft))
		var a6 := _spos(side, 6)
		var y7 := _ry(7)
		_arrow(c, PackedVector2Array([a6 + Vector2(0, _icon * 0.5), Vector2(a6.x, y7), Vector2(sx - dirx * r2, y7)]), col2, U.call("fus:7"))
	var cf := (Spellbook.ELEMENTS[ea].cor as Color).lerp(Spellbook.ELEMENTS[eb].cor, 0.5)
	_arrow(c, PackedVector2Array([Vector2(sx, _ry(7) + r2), Vector2(sx, _ry(8) - r2)]), cf, U.call("fus:8"))

	# ícones das magias
	for side in 2:
		var el3: String = pe[side]
		for t in range(1, 7):
			var id := "%s:%d" % [el3, t]
			_node(c, font, _spos(side, t), id, false, {"id": id, "el": el3, "t": t, "req": player.spell_req(id)})
	for t in range(1, 9):
		var idl := "luz:%d" % t
		_node(c, font, _lpos(t), idl, false, {"id": idl, "el": "luz", "t": t, "req": player.spell_req(idl)})
	var fus: Array = Spellbook.FUSOES[player.classe]
	var fdesc := {
		3: [fus[0], "Escudo fundido", "Os dois escudos se fundem num só, mais forte."],
		5: [Spellbook.SUMMON_FUSION[player.classe], "Invocação fundida", "Funde as duas invocações num só guardião aprimorado (mais vida e força, os dois efeitos). Usar uma invocação separada desfaz a fundida."],
		7: [fus[1], Spellbook.TIER_KIND[7], "Magia suprema: os dois elementos num ataque de alvo único, dano altíssimo."],
		8: [fus[2], Spellbook.TIER_KIND[8], "Magia suprema em área com os dois elementos, dano altíssimo."],
	}
	for ft in FUS_ROW:
		var fid := "fus:%d" % ft
		_node(c, font, Vector2(sx, _ry(FUS_ROW[ft])), fid, true,
			{"id": fid, "fus": ft, "nome": fdesc[ft][0], "kind": fdesc[ft][1], "desc": fdesc[ft][2], "req": player.spell_req(fid)})

	# segundo elemento ainda adormecido: selo por cima do painel
	if lb <= 0:
		var pr2 := Rect2(_px[1] + 6, _treeh * 0.4, _pw - 12, 62)
		c.draw_rect(pr2, Color(0.03, 0.02, 0.02, 0.88))
		c.draw_rect(pr2, Color(Spellbook.ELEMENTS[ea].cor, 0.8), false, 1.5)
		_ctext(c, font, Vector2(pr2.get_center().x, pr2.position.y + 22), "Adormecido", 16, Color(1, 0.85, 0.6))
		_ctext(c, font, Vector2(pr2.get_center().x, pr2.position.y + 42), "Desperta no nível 31 de %s" % Spellbook.ELEMENTS[ea].nome, 12, Color(0.85, 0.78, 0.68))
		var f := clampf(float(la) / 31.0, 0.0, 1.0)
		var br := Rect2(pr2.position.x + 12, pr2.position.y + 50, pr2.size.x - 24, 4)
		c.draw_rect(br, Color(0, 0, 0, 0.8))
		c.draw_rect(Rect2(br.position, Vector2(br.size.x * f, 4)), Spellbook.ELEMENTS[ea].cor)

	_draw_bar(c, font)
	_draw_desc(c, font)


func _spos(side: int, t: int) -> Vector2:
	var col: int = COL_A[t - 1]
	if side == 1:
		col = 2 - col
	return Vector2(_cx(side, col), _ry(t))


func _lpos(t: int) -> Vector2:
	return Vector2(_cx(2, COL_LUZ[t - 1]), _ry(t))


func _plaque(c: Control, font: Font, i: int, name: String, lv: int, sk: Array, k: String) -> void:
	var r := Rect2(_px[i] + 4, 4, _pw - 8, HEAD - 6)
	var col: Color = Spellbook.ELEMENTS[k].cor
	c.draw_rect(r, Color(0.06, 0.04, 0.03, 0.94))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45)), Color(1, 0.9, 0.7, 0.05))
	c.draw_rect(r, Color(0.72, 0.55, 0.3), false, 1.5)
	# cantos ornamentados
	for q in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		ElemArt.star(c, q, 5.0, Color(0.95, 0.78, 0.45), PI / 4.0)
	# caixa do nível
	var b := Rect2(r.position + Vector2(5, 4), Vector2(r.size.y - 8, r.size.y - 8))
	c.draw_rect(b, Color(0, 0, 0, 0.9))
	c.draw_rect(b, col.darkened(0.1), false, 1.5)
	_ctext(c, font, b.get_center() + Vector2(0, 6), str(lv), 16, Color(1, 1, 1))
	var tx := b.end.x + 8
	c.draw_string(font, Vector2(tx, r.position.y + 15), name, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - tx - 4, 15, col.lightened(0.35))
	var f := 0.0
	if lv > 0:
		f = clampf(float(sk[1]) / float(Rules.skill_need(k, int(sk[0]))), 0, 1)
	var bar := Rect2(tx, r.position.y + 21, r.end.x - tx - 8, 4)
	c.draw_rect(bar, Color(0, 0, 0, 0.8))
	c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), col)


func _ctext(c: Control, font: Font, p: Vector2, s: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Seta entre dois ícones: desce do de cima e entra pelo lado (em L) ou reta se estiverem na mesma coluna.
func _link(c: Control, a: Vector2, b: Vector2, col: Color, on: bool) -> void:
	var h := _icon * 0.5
	if absf(a.x - b.x) < 2.0:
		_arrow(c, PackedVector2Array([a + Vector2(0, h), b - Vector2(0, h)]), col, on)
	else:
		var dx := signf(b.x - a.x)
		_arrow(c, PackedVector2Array([a + Vector2(0, h), Vector2(a.x, b.y), Vector2(b.x - dx * h, b.y)]), col, on)


func _arrow(c: Control, pts: PackedVector2Array, col: Color, on: bool) -> void:
	var n := pts.size()
	if n < 2:
		return
	var end := pts[n - 1]
	var d := (end - pts[n - 2]).normalized()
	var hs := clampf(_icon * 0.2, 5.0, 8.0)
	var body := pts.duplicate()
	body[n - 1] = end - d * hs * 0.8
	var fill := col.lightened(0.15) if on else Color(0.36, 0.33, 0.3)
	if on:
		ElemArt.polyline(c, body, Color(col, 0.22), 9.0)
	ElemArt.polyline(c, body, Color(0, 0, 0, 0.85), 6.0)
	ElemArt.polyline(c, body, fill, 3.0)
	# juntas arredondadas nos cotovelos
	for i in range(1, n - 1):
		ElemArt.circle(c, pts[i], 3.0, Color(0, 0, 0, 0.85))
		ElemArt.circle(c, pts[i], 1.6, fill)
	var q := Vector2(-d.y, d.x)
	ElemArt.poly(c, PackedVector2Array([end + d * 1.5, end - d * (hs + 2) + q * (hs + 1), end - d * (hs + 2) - q * (hs + 1)]), Color(0, 0, 0, 0.85))
	ElemArt.poly(c, PackedVector2Array([end, end - d * hs + q * hs * 0.75, end - d * hs - q * hs * 0.75]), fill)


func _node(c: Control, font: Font, p: Vector2, id: String, round: bool, info: Dictionary) -> void:
	var ok := player.spell_unlocked(id)
	info["ok"] = ok
	var i := _nodes.size()
	var s := _icon * (1.18 if round else 1.0)
	var r := Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s))
	_nodes.append([r, info])
	var hov := i == _hover or id == _sel_id
	if ok:
		var pulse := 0.5 + 0.5 * sin(_t * 2.2 + p.y * 0.05)
		var gc: Color = Spells.get_spell(id, player.classe).get("color", Color.WHITE)
		ElemArt.circle(c, p, s * (0.85 + 0.06 * pulse), Color(gc, 0.13 + 0.05 * pulse))
	if round:
		medal(c, p, s * 0.5, id, player.classe, ok, _t)
	else:
		icon(c, r, id, player.classe, ok, _t)
	if hov:
		c.draw_rect(r.grow(3), Color(1, 0.92, 0.6), false, 2.0)
	# selo: nível de melhoria (liberada) ou nível que falta (bloqueada)
	var badge := ""
	var bcol := Color(0.35, 0.95, 0.4)
	if ok:
		badge = str(player.spell_up(id))
	else:
		badge = _req_lv(id)
		bcol = Color(0.75, 0.7, 0.62)
	if badge != "":
		var fs := 11
		var bw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6
		var br := Rect2(r.end - Vector2(bw - 3, 11), Vector2(bw, 13))
		c.draw_rect(br, Color(0, 0, 0, 0.92))
		c.draw_rect(br, Color(bcol, 0.8), false, 1.0)
		c.draw_string(font, br.position + Vector2(3, 10.5), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, bcol)
	if player.bar.has(id):
		ElemArt.circle(c, r.position + Vector2(2, 2), 4.5, Color(0, 0, 0, 0.9))
		ElemArt.circle(c, r.position + Vector2(2, 2), 3.2, Color(1, 0.8, 0.3))


func _req_lv(id: String) -> String:
	if id.begins_with("fus:"):
		return str(int(Player.FUS_REQ.get(int(id.split(":")[1]), 30)))
	return str(Player.tier_req(int(id.split(":")[1])))


## Barra de magias (8 casas) embaixo da árvore, com os ícones.
func _draw_bar(c: Control, font: Font) -> void:
	_slots.clear()
	var y := size.y - 44
	var lab := "Escolha a casa:" if _sel_id != "" else "Sua barra:"
	c.draw_string(font, Vector2(0, y + 26), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.85, 0.5) if _sel_id != "" else Color(0.72, 0.66, 0.58))
	var x0 := 120.0 if _sel_id != "" else 90.0
	var w := (size.x - x0) / 8.0
	for i in 8:
		var r := Rect2(x0 + i * w + 2, y, w - 4, 42)
		_slots.append(r)
		var sp := player.bar_spell(i)
		c.draw_rect(r, Color(0.05, 0.04, 0.03, 0.92))
		var bc := Color(1, 0.8, 0.4) if _sel_id != "" else Color(0.5, 0.38, 0.22)
		c.draw_rect(r, bc, false, 2.0 if _sel_id != "" else 1.0)
		var ir := Rect2(r.position + Vector2(3, 3), Vector2(36, 36))
		if not sp.is_empty():
			var bid := str(player.bar[i])
			icon(c, ir, bid, player.classe, player.spell_unlocked(bid), _t)
			c.draw_string(font, Vector2(ir.end.x + 4, r.position.y + 26), str(sp.curto), HORIZONTAL_ALIGNMENT_LEFT, r.end.x - ir.end.x - 6, 12, Color(0.95, 0.9, 0.8))
		c.draw_string(font, r.position + Vector2(3, 13), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.9, 0.6))


func _draw_desc(c: Control, font: Font) -> void:
	var box := Rect2(0, size.y - BOTTOM + 2, size.x, 56)
	if _hover < 0 and _sel_id != "":
		for k in _nodes.size():
			if str(_nodes[k][1].id) == _sel_id:
				_hover = k
	c.draw_rect(box, Color(0.04, 0.03, 0.02, 0.9))
	c.draw_rect(box, Color(0.45, 0.34, 0.2, 0.8), false, 1.0)
	if _hover < 0 or _hover >= _nodes.size():
		c.draw_string(font, box.position + Vector2(10, 22), "Toque numa magia para ver o que ela faz; depois toque numa casa da barra para colocá-la.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 14, Color(0.72, 0.66, 0.58))
		c.draw_string(font, box.position + Vector2(10, 43), "As fusões, entre os dois elementos, juntam as duas magias ligadas a elas.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 13, Color(0.6, 0.55, 0.48))
		return
	var n: Dictionary = _nodes[_hover][1]
	var title := ""
	var desc := ""
	if n.has("fus"):
		title = "%s — %s" % [n.nome, n.kind]
		desc = n.desc
	else:
		var el: Dictionary = Spellbook.ELEMENTS[n.el]
		title = "%s — %s %d" % [el.magias[n.t - 1], el.nome, n.t]
		if n.el != "luz":
			title += " · " + Spellbook.TIER_KIND[n.t]
		desc = Spellbook.spell_desc(n.el, n.t)
		desc += "   ·   Melhoria %d/5" % player.spell_up(str(n.id))
	var col := Color(0.5, 1, 0.55) if n.ok else Color(1, 0.55, 0.4)
	c.draw_string(font, box.position + Vector2(10, 21), title, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.6, 15, Color(1, 0.88, 0.6))
	c.draw_string(font, box.position + Vector2(size.x * 0.62, 21), ("Liberada" if n.ok else "Requer: " + n.req), HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.38 - 8, 13, col)
	c.draw_string(font, box.position + Vector2(10, 43), desc, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 13, Color(0.85, 0.8, 0.72))


# ------------------------------------------------------------ ícones (também usados fora da árvore)
static var _gray := false


static func _g(col: Color) -> Color:
	if not _gray:
		return col
	var l := col.r * 0.3 + col.g * 0.55 + col.b * 0.15
	return Color(l * 0.62, l * 0.6, l * 0.58, col.a)


## Ícone quadrado de uma magia ("fogo:1", "luz:3", "fus:7"...). Bloqueada = cinza.
static func icon(n: CanvasItem, r: Rect2, id: String, classe: String, ok: bool, t := 0.0) -> void:
	var parts := id.split(":")
	if parts.size() != 2:
		return
	var el := parts[0]
	var tier := int(parts[1])
	if el == "fus":
		medal(n, r.get_center(), r.size.x * 0.5, id, classe, ok, t)
		return
	_gray = not ok
	var col: Color = Spellbook.ELEMENTS[el].cor if Spellbook.ELEMENTS.has(el) else Color.WHITE
	var p := r.get_center()
	var s := r.size.x
	n.draw_rect(r, _g(col.darkened(0.82)))
	ElemArt.circle(n, p + Vector2(0, s * 0.08), s * 0.48, _g(Color(col.darkened(0.45), 0.55)))
	ElemArt.circle(n, p + Vector2(0, s * 0.05), s * 0.3, _g(Color(col.darkened(0.2), 0.35)))
	if el == "luz":
		_luz_glyph(n, p, s, tier, col, t)
	else:
		_glyph(n, p, s, el, tier, col, t)
	_frame(n, r, ok)
	_gray = false


## Medalhão redondo das fusões: as duas cores da classe, uma de cada lado.
static func medal(n: CanvasItem, p: Vector2, rad: float, id: String, classe: String, ok: bool, t := 0.0) -> void:
	_gray = not ok
	var els := Spellbook.elements_of(classe)
	var ca: Color = Spellbook.ELEMENTS[els[0]].cor
	var cb: Color = Spellbook.ELEMENTS[els[1]].cor
	var tier := int(id.split(":")[1])
	ElemArt.circle(n, p, rad + 3, Color(0, 0, 0, 0.9))
	ElemArt.circle(n, p, rad, _g(Color(0.75, 0.58, 0.3)))
	ElemArt.circle(n, p, rad - 2.5, _g(ca.darkened(0.75)))
	# metade do elemento B (direita), por cima
	var half := PackedVector2Array([p])
	for k in 13:
		var a := -PI * 0.5 + PI * k / 12.0
		half.append(p + Vector2(cos(a), sin(a)) * (rad - 2.5))
	ElemArt.poly(n, half, _g(cb.darkened(0.72)))
	ElemArt.circle(n, p - Vector2(rad * 0.3, 0), rad * 0.42, _g(Color(ca, 0.28)))
	ElemArt.circle(n, p + Vector2(rad * 0.3, 0), rad * 0.42, _g(Color(cb, 0.28)))
	var s := rad * 2.0
	match tier:
		3:
			_shield(n, p + Vector2(0, s * 0.02), s * 0.62, ca, cb)
		5:
			_figure(n, p + Vector2(0, s * 0.06), s * 0.78, ca.lerp(cb, 0.5))
			_motif(n, p + Vector2(-s * 0.2, -s * 0.05), s * 0.13, els[0], ca, t)
			_motif(n, p + Vector2(s * 0.2, -s * 0.05), s * 0.13, els[1], cb, t)
		7:
			var a0 := p + Vector2(-s * 0.3, s * 0.3)
			var a1 := p + Vector2(s * 0.24, -s * 0.24)
			ElemArt.ribbon(n, PackedVector2Array([a0, a0.lerp(a1, 0.5) + Vector2(0, -s * 0.08), a1]), s * 0.02, s * 0.09, _g(Color(ca, 0.85)))
			ElemArt.ribbon(n, PackedVector2Array([a0, a0.lerp(a1, 0.5) + Vector2(s * 0.08, 0), a1]), s * 0.02, s * 0.07, _g(Color(cb, 0.85)))
			_motif(n, a1, s * 0.17, els[0], ca, t)
			_motif(n, a1 + Vector2(s * 0.06, s * 0.04), s * 0.12, els[1], cb, t)
		8:
			_ground(n, p + Vector2(0, s * 0.24), s * 0.36, ca.lerp(cb, 0.5))
			_motif(n, p + Vector2(-s * 0.16, -s * 0.12), s * 0.15, els[0], ca, t)
			_motif(n, p + Vector2(s * 0.16, -s * 0.02), s * 0.15, els[1], cb, t)
			_motif(n, p + Vector2(0, -s * 0.28), s * 0.1, els[0], ca, t)
	ElemArt.arc(n, p, rad - 1, 0, TAU, 40, _g(Color(1, 0.86, 0.55)), 1.5)
	if not ok:
		ElemArt.circle(n, p, rad, Color(0, 0, 0, 0.35))
	_gray = false


static func _frame(n: CanvasItem, r: Rect2, ok: bool) -> void:
	var gold := Color(0.82, 0.65, 0.38) if ok else Color(0.38, 0.36, 0.33)
	n.draw_rect(r.grow(1.5), Color(0, 0, 0, 0.95), false, 3.0)
	n.draw_rect(r, gold, false, 1.5)
	# chanfro: luz em cima/esquerda, sombra embaixo/direita
	var a := r.position + Vector2(2, 2)
	var b := r.end - Vector2(2, 2)
	n.draw_line(a, Vector2(b.x, a.y), Color(1, 1, 1, 0.22), 1.0)
	n.draw_line(a, Vector2(a.x, b.y), Color(1, 1, 1, 0.15), 1.0)
	n.draw_line(Vector2(a.x, b.y), b, Color(0, 0, 0, 0.5), 1.0)
	n.draw_line(Vector2(b.x, a.y), b, Color(0, 0, 0, 0.5), 1.0)
	if not ok:
		n.draw_rect(r, Color(0, 0, 0, 0.3))


## Símbolo pequeno de cada elemento.
static func _motif(n: CanvasItem, p: Vector2, s: float, el: String, col: Color, t := 0.0) -> void:
	match el:
		"fogo":
			_tear(n, p, s * 1.15, _g(col))
			_tear(n, p + Vector2(0, s * 0.3), s * 0.6, _g(Color(1, 0.9, 0.45)))
		"lava":
			ElemArt.circle(n, p, s, _g(Color(0.22, 0.08, 0.04)))
			n.draw_line(p + Vector2(-s * 0.6, -s * 0.2), p + Vector2(s * 0.1, s * 0.15), _g(Color(1, 0.55, 0.1)), maxf(1.0, s * 0.18))
			n.draw_line(p + Vector2(s * 0.1, s * 0.15), p + Vector2(s * 0.5, -s * 0.45), _g(Color(1, 0.55, 0.1)), maxf(1.0, s * 0.15))
			n.draw_line(p + Vector2(s * 0.1, s * 0.15), p + Vector2(0, s * 0.7), _g(Color(1, 0.4, 0.05)), maxf(1.0, s * 0.12))
		"agua":
			_tear(n, p, s * 1.1, _g(col))
			ElemArt.circle(n, p + Vector2(-s * 0.25, s * 0.15), s * 0.2, _g(Color(1, 1, 1, 0.6)))
		"gelo":
			ElemArt.poly(n, PackedVector2Array([p + Vector2(0, -s * 1.2), p + Vector2(s * 0.5, 0), p + Vector2(0, s * 1.0), p + Vector2(-s * 0.5, 0)]), _g(col))
			ElemArt.poly(n, PackedVector2Array([p + Vector2(0, -s * 1.2), p + Vector2(s * 0.5, 0), p]), _g(Color(1, 1, 1, 0.5)))
		"vento":
			for k in 3:
				var rr := s * (0.4 + 0.3 * k)
				ElemArt.arc(n, p + Vector2(k * s * 0.15, 0), rr, PI * 0.9 + t, PI * 2.3 + t, 10, _g(Color(col, 1.0 - k * 0.25)), maxf(1.2, s * 0.2))
		"raio":
			var pts := PackedVector2Array([p + Vector2(s * 0.2, -s * 1.2), p + Vector2(-s * 0.45, s * 0.1), p + Vector2(0, s * 0.1), p + Vector2(-s * 0.2, s * 1.2), p + Vector2(s * 0.5, -s * 0.15), p + Vector2(0, -s * 0.15)])
			ElemArt.poly(n, PackedVector2Array([pts[0], pts[1], pts[2], pts[5]]), _g(col.lightened(0.2)))
			ElemArt.poly(n, PackedVector2Array([pts[5], pts[2], pts[3], pts[4]]), _g(col.lightened(0.2)))
		"terra":
			var b := PackedVector2Array()
			for k in 7:
				var a := TAU * k / 7.0 + 0.3
				b.append(p + Vector2(cos(a), sin(a) * 0.85) * s * (0.85 + 0.18 * sin(k * 2.3)))
			ElemArt.poly(n, b, _g(col.darkened(0.15)))
			ElemArt.circle(n, p + Vector2(-s * 0.25, -s * 0.25), s * 0.3, _g(Color(1, 1, 1, 0.18)))
		"natureza":
			var a0 := p + Vector2(-s * 0.9, s * 0.9)
			var a1 := p + Vector2(s * 0.9, -s * 0.9)
			var nv := Vector2(1, 1).normalized()
			var lf := PackedVector2Array()
			for k in 9:
				var f := k / 8.0
				lf.append(a0.lerp(a1, f) + nv * sin(f * PI) * s * 0.55)
			for k in range(1, 8):
				var f2 := 1.0 - k / 8.0
				lf.append(a0.lerp(a1, f2) - nv * sin(f2 * PI) * s * 0.55)
			ElemArt.poly(n, lf, _g(col))
			n.draw_line(a0, p + Vector2(s * 0.7, -s * 0.7), _g(col.darkened(0.45)), maxf(1.0, s * 0.1))
		_:
			ElemArt.star(n, p, s * 1.2, _g(col))


## Gota/chama: ponta para cima, base redonda.
static func _tear(n: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	var c := p + Vector2(0, s * 0.3)
	var pts := PackedVector2Array([p + Vector2(0, -s)])
	for k in 13:
		var a := -PI * 0.15 + (PI * 1.3) * k / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * s * 0.55)
	ElemArt.poly(n, pts, col)


static func _shield(n: CanvasItem, p: Vector2, s: float, ca: Color, cb: Color) -> void:
	var w := s * 0.42
	var pts := PackedVector2Array([p + Vector2(-w, -s * 0.45), p + Vector2(w, -s * 0.45), p + Vector2(w, s * 0.05), p + Vector2(0, s * 0.5), p + Vector2(-w, s * 0.05)])
	var out := PackedVector2Array()
	for q in pts:
		out.append(p + (q - p) * 1.14)
	ElemArt.poly(n, out, _g(Color(0.85, 0.7, 0.45)))
	ElemArt.poly(n, PackedVector2Array([pts[0], p + Vector2(0, -s * 0.45), p + Vector2(0, s * 0.5), pts[4]]), _g(ca.darkened(0.25)))
	ElemArt.poly(n, PackedVector2Array([p + Vector2(0, -s * 0.45), pts[1], pts[2], p + Vector2(0, s * 0.5)]), _g(cb.darkened(0.25)))
	ElemArt.poly(n, PackedVector2Array([pts[0], pts[1], p + Vector2(w, -s * 0.3), p + Vector2(-w, -s * 0.3)]), _g(Color(1, 1, 1, 0.18)))


static func _figure(n: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	var dk := _g(col.darkened(0.35))
	ElemArt.circle(n, p + Vector2(0, -s * 0.32), s * 0.12, dk)
	ElemArt.poly(n, PackedVector2Array([p + Vector2(-s * 0.2, -s * 0.18), p + Vector2(s * 0.2, -s * 0.18), p + Vector2(s * 0.14, s * 0.18), p + Vector2(-s * 0.14, s * 0.18)]), dk)
	ElemArt.poly(n, PackedVector2Array([p + Vector2(-s * 0.2, -s * 0.16), p + Vector2(-s * 0.36, s * 0.05), p + Vector2(-s * 0.3, s * 0.1), p + Vector2(-s * 0.15, -s * 0.05)]), dk)
	ElemArt.poly(n, PackedVector2Array([p + Vector2(s * 0.2, -s * 0.16), p + Vector2(s * 0.36, s * 0.05), p + Vector2(s * 0.3, s * 0.1), p + Vector2(s * 0.15, -s * 0.05)]), dk)
	ElemArt.poly(n, PackedVector2Array([p + Vector2(-s * 0.14, s * 0.16), p + Vector2(-s * 0.02, s * 0.16), p + Vector2(-s * 0.06, s * 0.45), p + Vector2(-s * 0.18, s * 0.45)]), dk)
	ElemArt.poly(n, PackedVector2Array([p + Vector2(s * 0.02, s * 0.16), p + Vector2(s * 0.14, s * 0.16), p + Vector2(s * 0.18, s * 0.45), p + Vector2(s * 0.06, s * 0.45)]), dk)
	ElemArt.circle(n, p + Vector2(0, -s * 0.34), s * 0.05, _g(col.lightened(0.5)))


static func _ground(n: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	for k in 3:
		var rr := s * (1.0 - k * 0.28)
		var pts := PackedVector2Array()
		for j in 17:
			var a := TAU * j / 16.0
			pts.append(p + Vector2(cos(a) * rr, sin(a) * rr * 0.38))
		ElemArt.polyline(n, pts, _g(Color(col, 0.5 + k * 0.2)), 1.5)


## Símbolo do tipo de magia (1 a 6) com o elemento.
static func _glyph(n: CanvasItem, p: Vector2, s: float, el: String, tier: int, col: Color, t: float) -> void:
	match tier:
		1:  # projétil
			var a := p + Vector2(-s * 0.36, s * 0.34)
			var b := p + Vector2(s * 0.14, -s * 0.14)
			ElemArt.ribbon(n, PackedVector2Array([a, a.lerp(b, 0.5), b]), s * 0.01, s * 0.11, _g(Color(col, 0.75)), false)
			_motif(n, b + Vector2(s * 0.04, -s * 0.04), s * 0.2, el, col, t)
		2:  # controle: runa em volta
			ElemArt.arc(n, p, s * 0.3, 0, TAU, 28, _g(col.lightened(0.2)), maxf(1.2, s * 0.05))
			for k in 6:
				var a2 := TAU * k / 6.0 + t * 0.4
				var q := p + Vector2(cos(a2), sin(a2)) * s * 0.3
				ElemArt.circle(n, q, s * 0.045, _g(col.lightened(0.4)))
			_motif(n, p, s * 0.16, el, col, t)
			ElemArt.arc(n, p, s * 0.41, 0.3, 1.2, 6, _g(Color(col, 0.6)), 1.2)
			ElemArt.arc(n, p, s * 0.41, PI + 0.3, PI + 1.2, 6, _g(Color(col, 0.6)), 1.2)
		3:  # escudo
			_shield(n, p, s * 0.7, col, col.darkened(0.2))
			_motif(n, p + Vector2(0, -s * 0.02), s * 0.13, el, col.lightened(0.3), t)
		4:  # cone ou linha
			if Spells.LINE.has(el):
				var a3 := p + Vector2(-s * 0.4, s * 0.2)
				var b3 := p + Vector2(s * 0.4, -s * 0.2)
				ElemArt.ribbon(n, PackedVector2Array([a3, a3.lerp(b3, 0.5), b3]), s * 0.05, s * 0.12, _g(Color(col, 0.45)))
				ElemArt.ribbon(n, PackedVector2Array([a3, a3.lerp(b3, 0.5), b3]), s * 0.02, s * 0.05, _g(col.lightened(0.4)))
				_motif(n, b3, s * 0.14, el, col, t)
			else:
				var o := p + Vector2(-s * 0.38, s * 0.36)
				for k in 3:
					var rr2 := s * (0.85 - k * 0.22)
					var fan := PackedVector2Array([o])
					for j in 8:
						var a4 := -PI * 0.5 + PI * 0.5 * j / 7.0
						fan.append(o + Vector2(cos(a4), sin(a4)) * rr2)
					ElemArt.poly(n, fan, _g(Color(col.lightened(0.15 * k), 0.3 + 0.15 * k)))
				_motif(n, p + Vector2(s * 0.12, -s * 0.12), s * 0.12, el, col, t)
				_motif(n, p + Vector2(-s * 0.08, -s * 0.22), s * 0.08, el, col, t)
		5:  # invocação
			_figure(n, p + Vector2(0, s * 0.04), s * 0.86, col)
			_motif(n, p + Vector2(0, -s * 0.03), s * 0.09, el, col.lightened(0.3), t)
		6:  # área
			_ground(n, p + Vector2(0, s * 0.26), s * 0.36, col)
			for k in 3:
				var q2 := p + Vector2((k - 1) * s * 0.22, -s * 0.2 + (k % 2) * s * 0.14)
				n.draw_line(q2 + Vector2(-s * 0.08, -s * 0.16), q2, _g(Color(col, 0.5)), maxf(1.0, s * 0.04))
				_motif(n, q2, s * 0.1, el, col, t)


## Símbolos da Luz (cada magia tem o seu).
static func _luz_glyph(n: CanvasItem, p: Vector2, s: float, tier: int, col: Color, t: float) -> void:
	var c := _g(col.lightened(0.2))
	var w := s * 0.1
	match tier:
		1:  # cura: cruz
			n.draw_rect(Rect2(p - Vector2(w, s * 0.3), Vector2(w * 2, s * 0.6)), c)
			n.draw_rect(Rect2(p - Vector2(s * 0.3, w), Vector2(s * 0.6, w * 2)), c)
			ElemArt.star(n, p + Vector2(s * 0.26, -s * 0.26), s * 0.1, _g(Color.WHITE), t)
		2:  # bênção: sol
			for k in 8:
				var a := TAU * k / 8.0 + t * 0.3
				n.draw_line(p + Vector2(cos(a), sin(a)) * s * 0.2, p + Vector2(cos(a), sin(a)) * s * 0.38, c, maxf(1.0, s * 0.05))
			ElemArt.circle(n, p, s * 0.17, c)
			ElemArt.circle(n, p, s * 0.1, _g(Color(1, 1, 0.92)))
		3:  # corrente de luz: elos
			var pts := PackedVector2Array([p + Vector2(-s * 0.3, s * 0.2), p + Vector2(0, -s * 0.22), p + Vector2(s * 0.3, s * 0.2)])
			ElemArt.polyline(n, pts, c, maxf(1.2, s * 0.05))
			for q in pts:
				ElemArt.circle(n, q, s * 0.1, c)
				ElemArt.circle(n, q, s * 0.05, _g(Color(1, 1, 0.92)))
		4:  # círculo sagrado
			_ground(n, p + Vector2(0, s * 0.12), s * 0.4, col)
			n.draw_rect(Rect2(p + Vector2(-w * 0.7, -s * 0.34), Vector2(w * 1.4, s * 0.42)), c)
			n.draw_rect(Rect2(p + Vector2(-s * 0.15, -s * 0.2), Vector2(s * 0.3, w * 1.4)), c)
		5:  # espírito
			_tear(n, p + Vector2(0, s * 0.04), s * 0.28, Color(c, 0.85))
			ElemArt.circle(n, p + Vector2(0, -s * 0.02), s * 0.08, _g(Color(1, 1, 0.95)))
			for k in 3:
				var a2 := t * 1.5 + TAU * k / 3.0
				ElemArt.star(n, p + Vector2(cos(a2), sin(a2) * 0.6) * s * 0.34, s * 0.06, c)
		6:  # aura de bravura: espada
			ElemArt.arc(n, p, s * 0.34, 0, TAU, 24, _g(Color(col, 0.5)), 1.5)
			ElemArt.poly(n, PackedVector2Array([p + Vector2(0, -s * 0.36), p + Vector2(w * 0.8, -s * 0.22), p + Vector2(w * 0.8, s * 0.12), p + Vector2(-w * 0.8, s * 0.12), p + Vector2(-w * 0.8, -s * 0.22)]), c)
			n.draw_rect(Rect2(p + Vector2(-s * 0.16, s * 0.12), Vector2(s * 0.32, w)), _g(Color(0.85, 0.65, 0.35)))
			n.draw_rect(Rect2(p + Vector2(-w * 0.5, s * 0.12 + w), Vector2(w, s * 0.16)), _g(Color(0.5, 0.35, 0.2)))
		7:  # véu: olho velado
			var eye := PackedVector2Array()
			for k in 13:
				var a3 := PI * k / 12.0
				eye.append(p + Vector2(-cos(a3) * s * 0.36, -sin(a3) * s * 0.17))
			for k in range(1, 12):
				var a4 := PI * k / 12.0
				eye.append(p + Vector2(cos(a4) * s * 0.36, sin(a4) * s * 0.17))
			ElemArt.poly(n, eye, _g(Color(col, 0.75)))
			ElemArt.circle(n, p, s * 0.1, _g(col.darkened(0.6)))
			ElemArt.poly(n, PackedVector2Array([p + Vector2(-s * 0.4, -s * 0.3), p + Vector2(s * 0.4, -s * 0.3), p + Vector2(s * 0.4, 0), p + Vector2(-s * 0.4, 0)]), _g(Color(0.1, 0.08, 0.06, 0.55)))
		8:  # ascensão: asas
			for side in [-1.0, 1.0]:
				var wing := PackedVector2Array([p + Vector2(side * s * 0.05, 0)])
				for k in 6:
					var f := k / 5.0
					wing.append(p + Vector2(side * s * (0.1 + 0.32 * f), -s * (0.32 - 0.1 * f) + f * f * s * 0.5))
				wing.append(p + Vector2(side * s * 0.12, s * 0.2))
				ElemArt.poly(n, wing, c)
			ElemArt.arc(n, p + Vector2(0, -s * 0.3), s * 0.12, 0, TAU, 16, _g(Color(1, 0.95, 0.7)), 1.5)
