class_name EquipmentPanel
extends CanvasLayer
## Personagem e inventário (tecla I ou botão Bolsa), no estilo das fichas de personagem dos ARPGs:
## vitrine com o mago renderizado no meio e os espaços de equipamento dos dois lados, coluna de
## atributos com emblemas à direita e, embaixo, abas com os itens da bolsa, o saque e as poções.
## Fica no meio da tela, livre do joystick e dos botões de ataque; o jogo continua por trás.
## Tocar num espaço de equipamento troca pelo próximo item seu; tocar num item da bolsa equipa;
## tocar num material mostra o nome e o preço no Brann.

## Espaços: coluna da esquerda, coluna da direita e as duas mãos embaixo.
const LEFT := [EquipSlot.Slot.HEAD, EquipSlot.Slot.CHEST, EquipSlot.Slot.HANDS, EquipSlot.Slot.LEGS, EquipSlot.Slot.FEET]
const RIGHT := [EquipSlot.Slot.ACCESSORIES, EquipSlot.Slot.SHOULDERS, EquipSlot.Slot.CAPE]
const HINTS := {0: "elmo", 1: "peito", 2: "ombros", 3: "luvas", 4: "calça", 5: "botas", 6: "capa", 7: "arma", 8: "mão", 9: "colar"}
const GRID_COLS := 9
const CELL := 36.0

var player: Player
var panel: PanelContainer
var buttons: Dictionary = {}
var loot_slots: Array[ItemSlot] = []
var bag_slots: Array[ItemSlot] = []
var info_label: Label
var gold_label: Label
var _sel_loot := ""
var _tab := 0
var _tab_btns: Array = []
var _pages: Array = []
var _stats: Control
var _show: Control
var _portrait: AnimatedSprite2D
## Conteúdo da bolsa em ordem: ["pocao", "hp"|"mp", qtd] | ["item", id] | ["saque", id, qtd].
var _bag: Array = []
var _bag_title: Label
var _bag_ids: Array = []
## Camadas dos itens vestidos por cima do mago da vitrine.
var _pl: Array = []
var _pl_key := ""


func bind(p: Player) -> void:
	player = p
	# por cima dos nomes e números do mundo
	layer = 6
	_build()
	player.equipment.equipment_changed.connect(func(_s, _i): _refresh())
	get_viewport().size_changed.connect(_place)
	_refresh()


func _build() -> void:
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.05, 0.045, 0.04, 0.97), Color(0.5, 0.42, 0.3), 6, 8))
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	vb.add_child(top)
	var title := UiKit.title("Personagem", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	gold_label = UiKit.label("", 15, Color(1, 0.85, 0.35), true)
	top.add_child(gold_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	top.add_child(gap)
	var close := UiKit.button("X", toggle, 16, true)
	close.custom_minimum_size = Vector2(38, 30)
	top.add_child(close)

	# vitrine (mago + espaços) e atributos
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	vb.add_child(body)
	_show = Control.new()
	_show.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_show.custom_minimum_size = Vector2(300, 6 * 40 + 4)
	_show.clip_contents = true
	body.add_child(_show)
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = SpellTree.BG_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("seed", 5.3)
	m.set_shader_parameter("base", Color(0.07, 0.055, 0.045))
	m.set_shader_parameter("glow", Color(0.45, 0.3, 0.18))
	bg.material = m
	_show.add_child(bg)
	var deco := Control.new()
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.draw.connect(_draw_show.bind(deco))
	_show.add_child(deco)
	_portrait = AnimatedSprite2D.new()
	_portrait.centered = true
	_show.add_child(_portrait)
	for slot in LEFT + RIGHT + [EquipSlot.Slot.MAIN_HAND, EquipSlot.Slot.OFF_HAND]:
		var b := ItemSlot.new()
		b.slot = slot
		b.hint = HINTS.get(slot, "")
		b.custom_minimum_size = Vector2(38, 38)
		b.size = Vector2(38, 38)
		b.pressed.connect(_cycle.bind(slot))
		_show.add_child(b)
		buttons[slot] = b
	_show.resized.connect(_lay_show)

	_stats = Control.new()
	_stats.custom_minimum_size = Vector2(170, 0)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.draw.connect(_draw_stats)
	body.add_child(_stats)

	# bolsa: uma grade só (poções, equipamentos guardados e saque dividem os espaços)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	vb.add_child(tabs)
	_bag_title = UiKit.label("Bolsa", 14, UiKit.GOLD)
	_bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(_bag_title)
	var off := UiKit.button("Equipar melhores", _equip_best, 12, true)
	off.custom_minimum_size = Vector2(118, 28)
	tabs.add_child(off)
	var pages := PanelContainer.new()
	pages.add_theme_stylebox_override("panel", UiKit.inner(Color(0.06, 0.05, 0.045), Color(0.3, 0.24, 0.16), 4, 4))
	vb.add_child(pages)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 2 * (CELL + 3) + 2)
	pages.add_child(stack)
	var sc1 := _grid_page(stack)
	for i in Loot.SLOTS:
		var s := ItemSlot.new()
		s.custom_minimum_size = Vector2(CELL, CELL)
		s.pressed.connect(_pick.bind(i))
		sc1.get_child(0).add_child(s)
		bag_slots.append(s)

	info_label = UiKit.label("", 13, Color(1, 0.92, 0.75))
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(0, 34)
	vb.add_child(info_label)
	panel.visible = false
	_place()


func _grid_page(stack: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var g := GridContainer.new()
	g.columns = GRID_COLS
	g.add_theme_constant_override("h_separation", 3)
	g.add_theme_constant_override("v_separation", 3)
	sc.add_child(g)
	stack.add_child(sc)
	return sc


func _place() -> void:
	if panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var r := UiKit.center_rect(vp, Vector2(600, 470))
	panel.position = Vector2(r.position.x, maxf(6.0, r.position.y - 20.0))
	panel.size = Vector2(r.size.x, 0)
	panel.custom_minimum_size = Vector2(r.size.x, 0)


## Espaços em volta do mago: 5 à esquerda, 3 à direita, as mãos nos cantos de baixo.
func _lay_show() -> void:
	var w := _show.size.x
	var h := _show.size.y
	var step := (h - 4.0) / 6.0
	for i in LEFT.size():
		(buttons[LEFT[i]] as Control).position = Vector2(5, 2 + i * step)
	for i in RIGHT.size():
		(buttons[RIGHT[i]] as Control).position = Vector2(w - 44, 2 + (i + 1) * step)
	(buttons[EquipSlot.Slot.MAIN_HAND] as Control).position = Vector2(5, 2 + 5 * step)
	(buttons[EquipSlot.Slot.OFF_HAND] as Control).position = Vector2(w - 44, 2 + 5 * step)
	_fit_portrait()


func _fit_portrait() -> void:
	if player == null or _show == null:
		return
	var it: EquipmentItem = player.visual.body_item if player.visual else null
	if it == null or it.sprite_frames == null or not it.sprite_frames.has_animation("idle_S"):
		_portrait.visible = false
		return
	_portrait.visible = true
	if _portrait.sprite_frames != it.sprite_frames:
		_portrait.sprite_frames = it.sprite_frames
		_portrait.play("idle_S")
		_portrait.speed_scale = 1.6
	_portrait_layers()
	var th := (_portrait.sprite_frames.get_frame_texture("idle_S", 0) as Texture2D).get_size().y
	var k := (_show.size.y * 1.02) / maxf(1.0, th)
	_portrait.scale = Vector2(k, k)
	# o pé fica um pouco acima do fundo da vitrine
	_portrait.position = Vector2(_show.size.x * 0.5, _show.size.y * 0.5 - th * k * 0.06)


## Itens vestidos (camadas 3D) por cima do mago da vitrine, na mesma animação.
func _portrait_layers() -> void:
	var key := str(player.equipment.to_ids())
	if key == _pl_key:
		return
	_pl_key = key
	for sp in _pl:
		(sp as Node).queue_free()
	_pl.clear()
	var ordem := [EquipSlot.Slot.CAPE, EquipSlot.Slot.LEGS, EquipSlot.Slot.FEET, EquipSlot.Slot.CHEST, EquipSlot.Slot.HANDS,
		EquipSlot.Slot.SHOULDERS, EquipSlot.Slot.ACCESSORIES, EquipSlot.Slot.HEAD, EquipSlot.Slot.MAIN_HAND, EquipSlot.Slot.OFF_HAND]
	for s in ordem:
		var it := player.equipment.get_item(s)
		if it == null:
			continue
		var lp := "res://assets/equip/%s/sprites.json" % String(it.placeholder_style)
		if not FileAccess.file_exists(lp):
			continue
		for par in [["", it.placeholder_color, 0.8], ["_ac", it.placeholder_accent, 0.85]]:
			var li := Actor.sprite_body(lp, par[0])
			if li == null or not li.sprite_frames.has_animation("idle_S"):
				continue
			var sp := AnimatedSprite2D.new()
			sp.sprite_frames = li.sprite_frames
			sp.animation = "idle_S"
			sp.centered = true
			var cc: Color = par[1]
			sp.modulate = Color(cc.r / par[2], cc.g / par[2], cc.b / par[2])
			_portrait.add_child(sp)
			_pl.append(sp)


func _draw_show(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	# chão iluminado embaixo do mago e moldura
	ElemArt.circle(c, Vector2(w * 0.5, h * 0.86), w * 0.22, Color(1, 0.75, 0.45, 0.07))
	var cls: Color = MageClass.info(player.classe).cor if player else Color(1, 0.7, 0.4)
	ElemArt.circle(c, Vector2(w * 0.5, h * 0.45), w * 0.3, Color(cls, 0.06))
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0, 0, 0, 0.9), false, 3.0)
	c.draw_rect(Rect2(Vector2(2, 2), c.size - Vector2(4, 4)), Color(0.5, 0.42, 0.3, 0.8), false, 1.0)


## Coluna de atributos: faixa com o nível e emblemas redondos.
func _draw_stats() -> void:
	if player == null:
		return
	var c := _stats
	var font := ThemeDB.fallback_font
	var w := c.size.x
	var h := c.size.y
	var sb := UiKit.inner(Color(0.07, 0.09, 0.09), Color(0.32, 0.36, 0.34), 4, 0)
	c.draw_style_box(sb, Rect2(Vector2.ZERO, c.size))
	# faixa do nível (fita pendurada)
	var rb := Rect2(8, 0, 40, 46)
	ElemArt.poly(c, PackedVector2Array([rb.position, Vector2(rb.end.x, rb.position.y), rb.end, Vector2(rb.get_center().x, rb.end.y - 9), Vector2(rb.position.x, rb.end.y)]), Color(0.45, 0.16, 0.14))
	ElemArt.polyline(c, PackedVector2Array([Vector2(rb.position.x + 2, 0), Vector2(rb.position.x + 2, rb.end.y - 3), Vector2(rb.get_center().x, rb.end.y - 11), Vector2(rb.end.x - 2, rb.end.y - 3), Vector2(rb.end.x - 2, 0)]), Color(0.9, 0.7, 0.45, 0.7), 1.0)
	_ctext(c, font, Vector2(rb.get_center().x, 27), str(player.level), 18, Color(1, 0.95, 0.85))
	c.draw_string(font, Vector2(56, 22), "NÍVEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.85, 0.7))
	var xl := Rules.level_for(player.xp)
	var a := Rules.xp_to_reach(xl)
	var b := Rules.xp_to_reach(xl + 1)
	var f := clampf(float(player.xp - a) / maxf(1.0, float(b - a)), 0, 1)
	c.draw_rect(Rect2(56, 30, w - 64, 4), Color(0, 0, 0, 0.8))
	c.draw_rect(Rect2(56, 30, (w - 64) * f, 4), Color(1, 0.62, 0.18))
	var g := player.gear()
	var rows := [
		["Poder", "+%d%% magias" % int(g.get("magia", 0)), "poder", Color(1, 0.6, 0.3)],
		["Defesa", str(player.elem_level("defesa") + int(g.get("defesa", 0))), "defesa", Color(0.7, 0.8, 0.9)],
		["Vida", "%d / %d" % [int(player.hp), int(player.max_hp)], "vida", Color(1, 0.4, 0.4)],
		["Mana", "%d / %d" % [int(player.mp), int(player.max_mp)], "mana", Color(0.45, 0.65, 1)],
	]
	var y := 56.0
	var step := minf(34.0, (h - 56.0) / 7.2)
	for r in rows:
		_emblem(c, Vector2(22, y + 9), str(r[2]), r[3])
		_row(c, font, y, step, str(r[0]), str(r[1]), (r[3] as Color).lightened(0.25))
		y += step
	c.draw_line(Vector2(10, y - 4), Vector2(w - 10, y - 4), Color(0.4, 0.4, 0.36, 0.6), 1.0)
	# um só nível mágico; o segundo elemento desperta no 31
	var els := Spellbook.elements_of(player.classe)
	var linhas := [[els[0], "Nível mágico", str(player.magia())],
		[els[1], Spellbook.ELEMENTS[els[1]].nome, "ativo" if player.magia() >= 31 else "desperta no 31"],
		["luz", "Luz", "ativa"]]
	for ln in linhas:
		var el: String = ln[0]
		var ce: Color = Spellbook.ELEMENTS[el].cor
		ElemArt.circle(c, Vector2(22, y + 9), 12, Color(0, 0, 0, 0.6))
		ElemArt.arc(c, Vector2(22, y + 9), 12, 0, TAU, 24, Color(ce, 0.7), 1.5)
		SpellTree._motif(c, Vector2(22, y + 9), 5.5, el, ce)
		_row(c, font, y, step, str(ln[1]), str(ln[2]), ce.lightened(0.3))
		y += step


## Nome e valor: em duas linhas se couber, senão na mesma linha (valor à direita).
func _row(c: Control, font: Font, y: float, step: float, nome: String, val: String, col: Color) -> void:
	var w := c.size.x
	if step >= 31.0:
		c.draw_string(font, Vector2(42, y + 5), nome, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		c.draw_string(font, Vector2(42, y + 20), val, HORIZONTAL_ALIGNMENT_LEFT, w - 46, 14, Color(0.95, 0.92, 0.86))
	else:
		c.draw_string(font, Vector2(40, y + 14), nome, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		c.draw_string(font, Vector2(40, y + 14), val, HORIZONTAL_ALIGNMENT_RIGHT, w - 48, 13, Color(0.95, 0.92, 0.86))


func _emblem(c: Control, p: Vector2, k: String, col: Color) -> void:
	ElemArt.circle(c, p, 12, Color(0, 0, 0, 0.6))
	ElemArt.arc(c, p, 12, 0, TAU, 24, Color(0.75, 0.62, 0.42), 1.5)
	var cc := col.lightened(0.1)
	match k:
		"poder":
			ElemArt.star(c, p, 8, cc, PI / 8.0)
		"defesa":
			var pts := PackedVector2Array([p + Vector2(-6, -6), p + Vector2(6, -6), p + Vector2(6, 1), p + Vector2(0, 7), p + Vector2(-6, 1)])
			ElemArt.poly(c, pts, cc)
			c.draw_rect(Rect2(p + Vector2(-1, -4), Vector2(2, 8)), Color(0.15, 0.15, 0.18))
			c.draw_rect(Rect2(p + Vector2(-4, -2), Vector2(8, 2)), Color(0.15, 0.15, 0.18))
		"vida":
			ElemArt.circle(c, p + Vector2(-3, -2), 3.8, cc)
			ElemArt.circle(c, p + Vector2(3, -2), 3.8, cc)
			ElemArt.poly(c, PackedVector2Array([p + Vector2(-6.6, -1), p + Vector2(6.6, -1), p + Vector2(0, 7)]), cc)
		"mana":
			SpellTree._tear(c, p + Vector2(0, -1), 7, cc)


func _ctext(c: Control, font: Font, p: Vector2, s: String, fs: int, col: Color) -> void:
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, p - Vector2(tw * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_I:
		toggle()


func toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_place()
		_lay_show.call_deferred()
		_refresh()


func _cycle(slot: int) -> void:
	var options := ItemDB.for_slot(slot).filter(func(it): return player.owns(String(it.id)) and player.level >= it.level_req)
	if options.is_empty():
		# tem o item mas não o nível: avisa em vez de não fazer nada
		var locked := ItemDB.for_slot(slot).filter(func(it): return player.owns(String(it.id)))
		_sel_loot = ""
		if locked.is_empty():
			info_label.text = "%s: você ainda não tem item para este espaço (compre no Brann ou cace)." % EquipSlot.slot_name(slot)
		else:
			var parts := PackedStringArray()
			for it in locked:
				parts.append("%s (nível %d)" % [it.display_name, it.level_req])
			info_label.text = "Você é nível %d. Precisa de: %s" % [player.level, ", ".join(parts)]
		_refresh()
		return
	var cur := player.equipment.get_item(slot)
	var idx := options.find(cur)
	if idx + 1 < options.size():
		player.try_equip(options[idx + 1])
	else:
		player.equipment.unequip(slot)
	var it := player.equipment.get_item(slot)
	_sel_loot = ""
	if it:
		info_label.text = "%s  ·  nv %d\n%s" % [it.display_name, it.level_req, _stats_text(it.stats)]
	else:
		var n_own := ItemDB.for_slot(slot).filter(func(x): return player.owns(String(x.id))).size()
		info_label.text = "%s vazio  ·  você tem %d item(ns) para este espaço" % [EquipSlot.slot_name(slot), n_own]
	_refresh()


## Itens da bolsa que não estão vestidos (tocar equipa).
func _bag_list() -> Array:
	var worn := {}
	for s in EquipSlot.all():
		var it := player.equipment.get_item(s)
		if it:
			worn[String(it.id)] = true
	var out := []
	for id in player.bag:
		if not worn.has(str(id)) and ItemDB.get_item(str(id)):
			out.append(str(id))
	out.sort_custom(func(a, b): return ItemDB.get_item(a).level_req < ItemDB.get_item(b).level_req)
	return out


## Toque num espaço da bolsa.
func _pick(i: int) -> void:
	if i >= _bag.size():
		_sel_loot = ""
		info_label.text = "Espaço livre. Saque, itens e poções dividem os %d espaços." % Loot.SLOTS
		_refresh()
		return
	var e: Array = _bag[i]
	match str(e[0]):
		"pocao":
			_sel_loot = ""
			info_label.text = ("Poção de vida  ·  %d  ·  tecla Q (ou o botão vermelho)" if e[1] == "hp" else "Poção de mana  ·  %d  ·  tecla E (ou o botão azul)") % int(e[2])
			_refresh()
		"item":
			_pick_bag(_bag_ids.find(str(e[1])))
		"saque":
			_pick_loot(_loot_list().map(func(x): return x[0]).find(str(e[1])))


func _pick_bag(i: int) -> void:
	if i < 0 or i >= _bag_ids.size():
		return
	var it := ItemDB.get_item(str(_bag_ids[i]))
	if player.level < it.level_req:
		info_label.text = "%s  ·  precisa do nível %d (você é %d)\n%s" % [it.display_name, it.level_req, player.level, _stats_text(it.stats)]
		return
	player.try_equip(it)
	info_label.text = "Equipado: %s  ·  nv %d\n%s" % [it.display_name, it.level_req, _stats_text(it.stats)]
	_refresh()


func _pick_loot(i: int) -> void:
	var ids := _loot_list()
	if i >= ids.size():
		_sel_loot = ""
		info_label.text = "Espaço livre. Materiais caem das criaturas (elites e chefes deixam mais)."
	else:
		_sel_loot = ids[i][0]
		var q := int(player.loot.get(_sel_loot, 0))
		info_label.text = "%s  ·  %d unid.  ·  %d ouro cada no Brann (total %d)" % [Loot.nome(_sel_loot), q, Loot.preco(_sel_loot), q * Loot.preco(_sel_loot)]
	_refresh()


## Pilhas do saque em ordem (uma pilha por espaço, até 100 cada).
func _loot_list() -> Array:
	var out := []
	var keys := player.loot.keys()
	keys.sort_custom(func(a, b): return Loot.preco(str(a)) > Loot.preco(str(b)))
	for k in keys:
		var q := int(player.loot[k])
		while q > 0:
			out.append([str(k), mini(q, Loot.STACK)])
			q -= Loot.STACK
	return out


func _unequip_all() -> void:
	for s in EquipSlot.all():
		player.equipment.unequip(s)


## Valor de um item para o mago: bônus de magia e dos elementos da classe pesam mais.
func _item_score(it: EquipmentItem) -> float:
	var els := Spellbook.elements_of(player.classe) + ["luz"]
	var v := 0.0
	for k in it.stats:
		var q := float(it.stats[k])
		match str(k):
			"magia": v += q * 3.0
			"defesa": v += q * 2.0
			"velocidade": v += q * 1.5
			"ataque": v += q * 1.0
			"vida": v += q * 0.4
			"mana": v += q * 0.3
			_: v += q * (2.5 if els.has(str(k)) else 0.5)
	return v + it.level_req * 0.01


## Veste o melhor item que você tem (e pode usar no seu nível) em cada espaço.
func _equip_best() -> void:
	var trocas := 0
	for s in EquipSlot.all():
		var best: EquipmentItem = null
		var bv := -1.0
		for it in ItemDB.for_slot(s):
			if not player.owns(String(it.id)) or player.level < it.level_req:
				continue
			var v := _item_score(it)
			if v > bv:
				bv = v
				best = it
		if best != null and player.equipment.get_item(s) != best:
			player.try_equip(best)
			trocas += 1
	_sel_loot = ""
	info_label.text = ("Equipados os melhores itens (%d troca(s))." % trocas) if trocas > 0 else "Você já está com os melhores itens que tem."
	_refresh()


func _refresh() -> void:
	if panel == null or not panel.visible:
		return
	for slot in buttons:
		var it := player.equipment.get_item(slot)
		buttons[slot].set_item(it, slot)
		buttons[slot].tooltip_text = (it.display_name + "\n" + _stats_text(it.stats)) if it else EquipSlot.slot_name(slot)
	_bag_ids = _bag_list()
	var ids := _loot_list()
	var total := 0
	for k in player.loot:
		total += int(player.loot[k]) * Loot.preco(str(k))
	_bag = []
	if player.hp_pot > 0:
		_bag.append(["pocao", "hp", player.hp_pot])
	if player.mp_pot > 0:
		_bag.append(["pocao", "mp", player.mp_pot])
	for id in _bag_ids:
		_bag.append(["item", id])
	for l in ids:
		_bag.append(["saque", l[0], l[1]])
	for i in bag_slots.size():
		var bs := bag_slots[i]
		bs.modulate = Color.WHITE
		bs.selected = false
		if i >= _bag.size():
			bs.set_item(null, -1)
			bs.tooltip_text = ""
			continue
		var e: Array = _bag[i]
		match str(e[0]):
			"pocao":
				bs.set_potion(str(e[1]), int(e[2]))
				bs.tooltip_text = "Poção de vida" if e[1] == "hp" else "Poção de mana"
			"item":
				var bi := ItemDB.get_item(str(e[1]))
				bs.set_item(bi, bi.slot)
				bs.modulate = Color.WHITE if player.level >= bi.level_req else Color(0.6, 0.55, 0.55)
				bs.tooltip_text = "%s (nv %d)" % [bi.display_name, bi.level_req]
			"saque":
				bs.set_loot(str(e[1]), int(e[2]))
				bs.selected = str(e[1]) == _sel_loot
				bs.tooltip_text = Loot.nome(str(e[1]))
		bs.queue_redraw()
	_bag_title.text = "Bolsa  %d/%d  ·  o saque vale %d ouro no Brann" % [_bag.size(), Loot.SLOTS, total]
	gold_label.text = "%d ouro" % player.gold
	if info_label.text == "":
		info_label.text = "Toque num espaço para trocar de item, ou num item da bolsa para vestir."
	_fit_portrait()
	_stats.queue_redraw()
	_show.queue_redraw()
	for ch in _show.get_children():
		if ch is Control:
			(ch as Control).queue_redraw()


func _process(_d: float) -> void:
	for sp in _pl:
		(sp as AnimatedSprite2D).frame = _portrait.frame
	# o saque, o ouro e a vida mudam enquanto você caça com a bolsa aberta
	if panel and panel.visible and Engine.get_process_frames() % 20 == 0:
		_refresh()


func _stats_text(d: Dictionary) -> String:
	var parts := PackedStringArray()
	var nomes := {"vida": "vida", "mana": "mana", "defesa": "defesa", "magia": "% magias", "ataque": "ataque", "velocidade": "% velocidade"}
	for k in d:
		var nm: String = nomes.get(k, "% " + Rules.skill_name(k))
		parts.append("+%d %s" % [d[k], nm])
	return ", ".join(parts)
