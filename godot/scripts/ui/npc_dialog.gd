class_name NpcDialog
extends CanvasLayer
## Conversa com os NPCs da vila: Brann (poções) e Lira (cura e tarefas). Como na versão 3D.

const GOLD := Color(0.92, 0.82, 0.6)
const DIM := Color(0.72, 0.66, 0.58)
const POTION_PRICE := 20
## Preço fixo de alguns itens do Brann: [id, preço]. O resto sai de item_price().
const SHOP := [["varinha_aprendiz", 30], ["livro_feiticos", 40], ["chapeu_aprendiz", 40], ["sandalias", 20], ["manto_estudioso", 60], ["saia_linho", 30], ["colar_protecao", 150], ["turbante_mistico", 300], ["botas_ligeiras", 350], ["amuleto_mana", 400]]
## Tarefas por faixa de nível: [até o nível, monstro, quantidade].
const TASKS := [[5, "esqueleto", 10], [10, "carnical", 12], [18, "bandido", 15], [28, "cultista", 15], [99999, "golem", 8]]

static var inst: NpcDialog
var player: Player
var npc: Npc
var _box: PanelContainer
var _col: VBoxContainer


func _enter_tree() -> void:
	inst = self
	layer = 3


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	return UiKit.inner(bg, border, 8, 10)


func _lbl(t: String, size := 16, col := GOLD) -> Label:
	var l := UiKit.label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(480.0, _w() - 40.0), 0)
	return l


func _btn(t: String, cb: Callable) -> Button:
	var b := UiKit.button(t, cb, 14)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _w() -> float:
	return UiKit.center_rect(get_viewport().get_visible_rect().size, Vector2(600, 440)).size.x


var _tab := "pocoes"
var _scroll: ScrollContainer


## Falas da Elyra, recepcionista da Guilda dos Aventureiros (na cidade murada).
const FALAS_ELFA := [
	"Vim das florestas do leste. A cidade é barulhenta, mas o balcão da guilda tem a melhor vista da praça.",
	"Essa adaga na perna? Presente da minha mãe. Nunca saio sem ela, nem pra tomar sorvete.",
	"Dizem que tem um dragão vermelho lá no norte, depois da caverna. Eu é que não vou lá sozinha.",
	"Os guardas dos portões falam muito, mas lutam bem. Já vi um derrubar um lobo com um soco.",
	"Elfos vivem muito tempo. Mesmo assim, eu acho que a vida é curta demais pra recusar um gelado.",
]
const SOBRE_GUILDA := "A Guilda dos Aventureiros reúne quem caça fora das muralhas: aqui você se registra, pega pedidos do quadro e recebe pelo que trouxe. O quadro ainda está sendo montado."
const SERVICO_ELFA := "O quadro de missões da guilda abre em breve. Por enquanto, a Lira, no templo, aceita caçadas. Fica de olho: logo vou ter trabalho de verdade pra quem for corajoso."
var _fala_elfa := -1


func _conversar_elfa() -> void:
	_fala_elfa = (_fala_elfa + 1) % FALAS_ELFA.size()
	_render(FALAS_ELFA[_fala_elfa])


## Há conversa aberta? (o HUD não usa os toques enquanto isso)
static var talking := false


func open(n: Npc, p: Player) -> void:
	talking = true
	npc = n
	player = p
	if _box:
		_box.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", UiKit.box())
	center.add_child(_box)
	_box.tree_exited.connect(center.queue_free)
	var r := UiKit.center_rect(get_viewport().get_visible_rect().size, Vector2(600, 440))
	_box.custom_minimum_size = Vector2(r.size.x, 0)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(r.size.x - 28, minf(r.size.y, get_viewport().get_visible_rect().size.y - 40.0))
	_box.add_child(_scroll)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 8)
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_col)
	_tab = "pocoes"
	_render("")


func close() -> void:
	talking = false
	if _box:
		_box.queue_free()
		_box = null
	npc = null


func is_open() -> bool:
	return _box != null


func _row(btns: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for b in btns:
		h.add_child(b)
	return h


func _render(say: String) -> void:
	for c in _col.get_children():
		c.queue_free()
	_col.add_child(UiKit.title(npc.display_name, 22))
	var nm := player.display_name if player.display_name != "" else Chars.nome
	if npc.role == "mercador":
		_col.add_child(_lbl("Olá, %s! Compro o saque das criaturas e vendo poções e itens de mago." % nm, 15))
		var tabs := []
		for tb in [["pocoes", "Poções"], ["itens", "Equipamentos"], ["vender", "Vender saque"]]:
			var key: String = tb[0]
			var bt := UiKit.button(tb[1], func():
				_tab = key
				_render(""), 14, _tab == key)
			bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tabs.append(bt)
		_col.add_child(_row(tabs))
		_col.add_child(_lbl("Seu ouro: %d" % player.gold, 14, Color(1, 0.85, 0.35)))
		match _tab:
			"pocoes":
				_col.add_child(_lbl("%d de ouro cada  ·  você tem %d de vida e %d de mana" % [POTION_PRICE, player.hp_pot, player.mp_pot], 13, DIM))
				_col.add_child(_row([_btn("Vida ×1", func(): _buy("hp", 1)), _btn("Vida ×5", func(): _buy("hp", 5)), _btn("Vida ×20", func(): _buy("hp", 20))]))
				_col.add_child(_row([_btn("Mana ×1", func(): _buy("mp", 1)), _btn("Mana ×5", func(): _buy("mp", 5)), _btn("Mana ×20", func(): _buy("mp", 20))]))
			"itens":
				_equip_shop()
			"vender":
				_sell_page()
	elif npc.role == "elfa":
		_col.add_child(_lbl("Bem-vindo à Guilda dos Aventureiros, %s! Eu sou a Elyra, cuido do balcão." % nm, 15))
		_col.add_child(_row([_btn("Conversar", _conversar_elfa), _btn("Sobre a guilda", func(): _render(SOBRE_GUILDA)), _btn("Missões", func(): _render(SERVICO_ELFA))]))
	else:
		var t := ""
		var tk: Dictionary = player.task
		if not tk.is_empty():
			var mn: String = Monster.TYPES[tk.type].name
			t = ("Você completou a tarefa contra %s!" % mn) if int(tk.count) >= int(tk.need) else ("Tarefa: %d/%d %s." % [tk.count, tk.need, mn])
		_col.add_child(_lbl("Que a luz te guarde, %s. %s" % [nm, t]))
		var tlabel := "Pedir tarefa"
		if not tk.is_empty():
			tlabel = "Receber recompensa" if int(tk.count) >= int(tk.need) else "Ver tarefa"
		_col.add_child(_row([_btn("Curar", _cure), _btn(tlabel, _task)]))
	if say != "":
		_col.add_child(_lbl("“%s”" % say, 15, Color(1, 0.92, 0.75)))
	_col.add_child(UiKit.sep())
	_col.add_child(UiKit.button("Fechar", close, 15, true))


## Preço de um equipamento: o da tabela SHOP, ou nível e atributos. Chefe custa o triplo.
static func item_price(id: String) -> int:
	for linha in SHOP:
		if String(linha[0]) == id:
			return int(linha[1])
	var it := ItemDB.get_item(id)
	if it == null:
		return 0
	var soma := 0
	for k in it.stats:
		soma += int(it.stats[k])
	var preco := int(round(float(40 + it.level_req * it.level_req * 6 + soma * 10) / 5.0)) * 5
	if id.begins_with("chefe_"):
		preco *= 3
	return preco


func _stats_short(d: Dictionary) -> String:
	var nomes := {"vida": "vida", "mana": "mana", "defesa": "defesa", "magia": "magias", "ataque": "ataque", "velocidade": "velocidade"}
	var partes := PackedStringArray()
	for k in d:
		var chave := str(k)
		var nm: String = nomes.get(chave, Rules.skill_name(chave).to_lower())
		partes.append("+%d %s" % [int(d[k]), nm])
	return ", ".join(partes)


func _equip_shop() -> void:
	var lista := ScrollContainer.new()
	lista.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lista.custom_minimum_size = Vector2(0, 260)
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_child(lista)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lista.add_child(box)
	var itens: Array[EquipmentItem] = []
	for it in ItemDB.items.values():
		if it is EquipmentItem:
			itens.append(it)
	if itens.is_empty():
		var vazio := UiKit.label("Não há equipamentos à venda.", 14, DIM)
		vazio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vazio.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(vazio)
		return
	itens.sort_custom(func(a, b):
		if a.slot != b.slot:
			return a.slot < b.slot
		if a.level_req != b.level_req:
			return a.level_req < b.level_req
		return String(a.display_name) < String(b.display_name)
	)
	var ultimo := -1
	for it in itens:
		if it.slot != ultimo:
			if ultimo != -1:
				var espaco := Control.new()
				espaco.custom_minimum_size = Vector2(0, 6)
				espaco.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(espaco)
			ultimo = it.slot
			var hdr := UiKit.label(EquipSlot.slot_name(it.slot), 12, Color(1, 0.82, 0.4))
			hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(hdr)
		box.add_child(_equip_row(it))


func _equip_row(item: EquipmentItem) -> HBoxContainer:
	var id := String(item.id)
	var preco := item_price(id)
	var ja_tem := player.owns(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = 36
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := ItemSlot.new()
	s.custom_minimum_size = Vector2(32, 32)
	s.set_item(item, item.slot)
	s.disabled = true
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nome := UiKit.label(item.display_name, 14, GOLD)
	nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(nome)
	var nv := UiKit.label("nv %d" % item.level_req, 12, Color(1, 0.35, 0.3) if player.level < item.level_req else DIM)
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(nv)
	var st := _stats_short(item.stats)
	if st != "":
		var sl := UiKit.label(st, 12, DIM)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.add_child(sl)
	row.add_child(mid)
	var direita := VBoxContainer.new()
	direita.add_theme_constant_override("separation", 2)
	direita.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	direita.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ouro := UiKit.label("%d ouro" % preco, 12, Color(1, 0.85, 0.35))
	ouro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ouro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ouro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	direita.add_child(ouro)
	var comprar := UiKit.button("Já tem" if ja_tem else "Comprar", _buy_item.bind(id, preco), 13)
	comprar.disabled = ja_tem
	comprar.custom_minimum_size = Vector2(84, 36)
	comprar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ja_tem:
		comprar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	direita.add_child(comprar)
	row.add_child(direita)
	return row


func _sell_page() -> void:
	var keys := player.loot.keys()
	if keys.is_empty():
		_col.add_child(_lbl("Sua bolsa de saque está vazia. Cace criaturas: elas deixam peles, ossos, gosmas e mais.", 14, DIM))
		return
	keys.sort_custom(func(a, b): return Loot.preco(str(a)) > Loot.preco(str(b)))
	var total := 0
	for k in keys:
		total += int(player.loot[k]) * Loot.preco(str(k))
	_col.add_child(UiKit.button("Vender todo o saque  (+%d ouro)" % total, _sell_all, 15, true))
	for k in keys:
		var id := str(k)
		var q := int(player.loot[k])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var ic := ItemSlot.new()
		ic.custom_minimum_size = Vector2(40, 40)
		ic.set_loot(id, q)
		ic.disabled = true
		h.add_child(ic)
		var l := UiKit.label("%s ×%d\n%d ouro cada" % [Loot.nome(id), q, Loot.preco(id)], 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var b1 := UiKit.button("Vender 1", func(): _sell(id, 1), 13)
		b1.custom_minimum_size = Vector2(86, 36)
		h.add_child(b1)
		var b2 := UiKit.button("Todos", func(): _sell(id, int(player.loot.get(id, 0))), 13)
		b2.custom_minimum_size = Vector2(70, 36)
		h.add_child(b2)
		_col.add_child(h)


func _sell(id: String, q: int) -> void:
	q = mini(q, int(player.loot.get(id, 0)))
	if q <= 0:
		return
	var g := q * Loot.preco(id)
	player.loot[id] = int(player.loot[id]) - q
	if int(player.loot[id]) <= 0:
		player.loot.erase(id)
	player.gold += g
	player.save()
	_render("Negócio fechado: %d %s por %d de ouro." % [q, Loot.nome(id), g])


func _sell_all() -> void:
	var g := 0
	for k in player.loot:
		g += int(player.loot[k]) * Loot.preco(str(k))
	player.loot.clear()
	player.gold += g
	player.save()
	_render("Levo tudo! Aqui estão %d de ouro." % g)


func _buy(kind: String, q: int) -> void:
	var cost := q * POTION_PRICE
	if player.gold < cost:
		_render("Isso custa %d de ouro, e você só tem %d." % [cost, player.gold])
		return
	player.gold -= cost
	if kind == "hp":
		player.hp_pot += q
	else:
		player.mp_pot += q
	player.save()
	_render("Aqui estão %d poção(ões) de %s. Boa caçada!" % [q, "vida" if kind == "hp" else "mana"])


func _buy_item(id: String, price: int) -> void:
	if player.gold < price:
		_render("Isso custa %d de ouro, e você só tem %d." % [price, player.gold])
		return
	player.gold -= price
	player.give_item(id)
	_render("Bom uso! Equipe no painel de equipamento (tecla I ou Menu → Equipamento).")


func _cure() -> void:
	player.hp = player.max_hp
	player.mp = player.max_mp
	SpellFx.heal(player.get_parent(), player.global_position)
	_render("Suas feridas se fecham e sua mente clareia.")


func _task() -> void:
	var tk: Dictionary = player.task
	if tk.is_empty():
		for row in TASKS:
			if player.level < int(row[0]):
				player.task = {"type": row[1], "need": row[2], "count": 0}
				break
		var mn: String = Monster.TYPES[player.task.type].name
		player.save()
		_render("Elimine %d %s e volte aqui." % [player.task.need, mn])
	elif int(tk.count) >= int(tk.need):
		var mt: Dictionary = Monster.TYPES[tk.type]
		var xp := int(round(float(mt.xp) * int(tk.need) * 1.5))
		var g := int(tk.need) * int(mt.gold[1])
		player.task = {}
		player.gain_xp(xp, g, "Lira")
		player.save()
		_render("Muito bem! Tome %d de experiência e %d de ouro." % [xp, g])
	else:
		_render("Você já eliminou %d de %d %s. Continue!" % [tk.count, tk.need, Monster.TYPES[tk.type].name])


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if is_open() and k and k.pressed and k.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
