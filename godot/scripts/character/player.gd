class_name Player
extends Actor
## Jogador: clique/toque para andar (segurar = seguir o dedo), botão direito ou 1 = bola de fogo,
## WASD/setas também andam, Shift corre. Espaço mira o monstro mais próximo; clicar num
## monstro também o seleciona. O ataque básico sai sozinho quando o alvo está ao alcance.

var target = null
var run_toggle := false
## Direção do joystick virtual (o HUD preenche).
var joy := Vector2.ZERO
var marker: TapMarker
var camera: Camera2D
var max_hp := 100.0
var hp := 100.0
var max_mp := 100.0
var mp := 100.0
const CAST_COST := 12.0
const ATTACK_RANGE := 6.5  # tiles

## Classe de mago (fogo, agua, vento, terra) — escolhida na tela inicial.
var classe := "fogo"
var level := 1
var xp := 0
var gold := 0
var dead := false
## Monstro selecionado como alvo.
var foe: Node2D = null
var spawn_pos := Vector2.ZERO
var _atk_cd := 0.0
var _save_t := 10.0
## Tarefa da sacerdotisa: {type, need, count} (vazio = nenhuma).
var task := {}
## Versão do mapa (o mapa mudou numa atualização = volta para o início da vila).
static var map_hash := 0
## Onde estava ao sair (grade) e em qual versão do mapa.
var saved_pos := Vector2(-1, -1)
var saved_map := 0
## NPC com quem vai conversar ao chegar perto.
var _talk: Node2D = null


func _init() -> void:
	body_colors = {
		"skin": Color(0.09, 0.085, 0.09),
		"under": Color(0.11, 0.1, 0.1),
		"hair": Color(0.07, 0.065, 0.07),
		"eyes": Color(1.0, 0.62, 0.15),
		"glow_eyes": true,
		"core": true,
	}
	body_path = "res://assets/personagens/mago/corpo.tres"
	start_items = ["capa_lobo_infernal", "saia_lobo_infernal", "escudo_mimico", "cajado_brasa"]


func _ready() -> void:
	get_tree().create_timer(2.5).timeout.connect(func():
		if spells_migrated:
			spells_migrated = false
			CombatText.add(global_position + Vector2(0, -160), "Magias reorganizadas: %s nível %d" % [Rules.skill_name(elem_a()), elem_level(elem_a())], Color(1, 0.85, 0.45), true)
			save())
	super()
	visual.is_main = true
	add_to_group("player")
	spawn_pos = position
	_load()
	camera = Camera2D.new()
	Settings.load_all()
	camera.zoom = Vector2.ONE * Settings.zoom
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.offset = Vector2(0, -30)
	add_child(camera)
	camera.make_current()
	save()
	# raio de luz do herói (como no Diablo 2): o mundo é escuro, a luz acompanha o personagem
	var aura := LightKit.make(Color(1.0, 0.9, 0.78), 0.95, 3.6, false, 0.0)
	aura.range_item_cull_mask = 3  # ilumina chão (1) e personagens (2)
	aura.position = Vector2(0, -30)
	aura.height = 60.0
	add_child(aura)
	if bag.is_empty():
		bag = START_BAG.duplicate()
		for id in start_items:
			if not bag.has(str(id)):
				bag.append(str(id))
	equipment.equipment_changed.connect(func(_s, _i): _recalc())
	_recalc()
	_aura = StatusAura.new()
	add_child(_aura)
	var dfx := DebuffFx.new()
	dfx.pl = self
	add_child(dfx)
	var ca := ClassAura.new()
	add_child(ca)
	ca.setup(classe)
	marker = TapMarker.new()
	marker.top_level = true
	marker.z_index = -5
	add_child(marker)


# ------------------------------------------------------------ progresso
func _recalc() -> void:
	var g := gear()
	max_hp = 100.0 + 10.0 * (level - 1) + float(g.get("vida", 0))
	max_mp = 100.0 + 15.0 * (level - 1) + float(g.get("mana", 0))
	var v := 1.0 + float(g.get("velocidade", 0)) / 100.0
	walk_speed = 120.0 * v
	run_speed = 210.0 * v
	hp = minf(hp, max_hp)
	mp = minf(mp, max_mp)


## Atributos somados dos itens equipados.
func gear() -> Dictionary:
	return equipment.total_stats() if equipment else {}


## Itens que o jogador tem (a bolsa). Equipar só o que tem e com o nível pedido.
var bag: Array = []
const START_BAG := ["varinha_aprendiz", "livro_feiticos", "chapeu_aprendiz", "sandalias", "capa_lobo_infernal", "saia_lobo_infernal", "escudo_mimico"]


## Bolsa de saque: id do material -> quantidade (vende no Brann).
var loot: Dictionary = {}


func loot_slots_used() -> int:
	var n := 0
	for k in loot:
		n += int(ceil(float(loot[k]) / Loot.STACK))
	return n


func add_loot(id: String, q := 1) -> bool:
	var have := int(loot.get(id, 0))
	var need := int(ceil(float(have + q) / Loot.STACK)) - int(ceil(float(have) / Loot.STACK))
	if loot_slots_used() + need > Loot.SLOTS:
		_msg("Bolsa de saque cheia! Venda no Brann.")
		return false
	loot[id] = have + q
	CombatText.add(global_position + Vector2(0, -136), "+%d %s" % [q, Loot.nome(id)], Loot.cor(id).lightened(0.3))
	return true


func owns(id: String) -> bool:
	return bag.has(id)


func give_item(id: String) -> void:
	if not bag.has(id) and ItemDB.get_item(id):
		bag.append(id)
		var it := ItemDB.get_item(id)
		CombatText.add(global_position + Vector2(0, -150), "Novo item: %s" % it.display_name, Color(1, 0.85, 0.35), true)
		save()


func try_equip(it: EquipmentItem) -> bool:
	if it == null:
		return false
	if level < it.level_req:
		_msg("%s: nível %d" % [it.display_name, it.level_req])
		return false
	equipment.equip(it)
	return true


func _load() -> void:
	_reset_skills()
	var c := ConfigFile.new()
	if c.load(Chars.path()) == OK:
		xp = int(c.get_value("jogador", "xp", 0))
		if int(c.get_value("jogador", "xp_v", 1)) < 2:
			xp = Rules.convert_xp_v1(xp)  # curva nova: mantém o nível de quem já jogava
		gold = int(c.get_value("jogador", "ouro", 0))
		hp_pot = int(c.get_value("jogador", "pocao_vida", 5))
		mp_pot = int(c.get_value("jogador", "pocao_mana", 5))
		saved_pos = c.get_value("jogador", "posicao", Vector2(-1, -1))
		saved_map = int(c.get_value("jogador", "mapa", 0))
		var spn = c.get_value("jogador", "magias_nivel", {})
		if spn is Dictionary:
			spell_pts = spn
		var bg = c.get_value("jogador", "bolsa", [])
		if bg is Array and not bg.is_empty():
			bag = bg.map(func(x): return str(x))
		var lt = c.get_value("jogador", "saque", {})
		loot = lt if lt is Dictionary else {}
		var eq = c.get_value("jogador", "equip", {})
		if eq is Dictionary and not eq.is_empty():
			equipment.load_ids(eq)
		var tk = c.get_value("jogador", "tarefa", {})
		task = tk if tk is Dictionary and tk.has("type") and Monster.TYPES.has(str(tk.type)) else {}
		var bb = c.get_value("jogador", "barra", [])
		if bb is Array and bb.size() == 8:
			bar = bb.map(func(x): return str(x))
		var sk = c.get_value("jogador", "habilidades", {})
		if sk is Dictionary:
			# saves antigos: a habilidade "magia" vira o elemento principal da classe
			if sk.has("magia") and not sk.has(elem_a()):
				sk[elem_a()] = sk.magia
			for k in skills:
				if sk.get(k) is Array and sk[k].size() == 2:
					skills[k] = [maxi(0 if k == elem_b() else 1, int(sk[k][0])), float(sk[k][1])]
		if int(c.get_value("jogador", "magias_v", 1)) < 2:
			_migrate_spells()
	level = Rules.level_for(xp)
	_recalc()
	hp = max_hp
	mp = max_mp


## Recarrega o progresso do arquivo (depois de importar um código).
func reload() -> void:
	_load()
	foe = null


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("jogador", "classe", classe)
	c.set_value("jogador", "nome", Chars.nome)
	c.set_value("jogador", "xp", xp)
	c.set_value("jogador", "xp_v", 2)
	c.set_value("jogador", "magias_v", 2)
	c.set_value("jogador", "ouro", gold)
	c.set_value("jogador", "nivel", level)
	c.set_value("jogador", "pocao_vida", hp_pot)
	c.set_value("jogador", "pocao_mana", mp_pot)
	c.set_value("jogador", "habilidades", skills)
	c.set_value("jogador", "barra", bar)
	c.set_value("jogador", "tarefa", task)
	c.set_value("jogador", "magias_nivel", spell_pts)
	c.set_value("jogador", "bolsa", bag)
	c.set_value("jogador", "saque", loot)
	c.set_value("jogador", "equip", equipment.to_ids())
	if not dead:
		c.set_value("jogador", "posicao", Iso.to_grid(global_position))
		c.set_value("jogador", "mapa", map_hash)
	c.save(Chars.path())


## Saque ao matar: materiais da criatura (mais no elite) e chance de equipamento.
## Chefes deixam o troféu e podem deixar o equipamento único deles.
func _roll_drop(src: String) -> void:
	var lk := Monster.lookup(src)
	if lk.is_empty() or lk.t == "boneco":
		return
	var mt: Dictionary = Monster.TYPES[lk.t]
	var el: bool = lk.elite
	for pair in mt.get("saque", []):
		if randf() < float(pair[1]) * (1.6 if el else 1.0):
			add_loot(str(pair[0]), 2 if el and randf() < 0.4 else 1)
	if mt.get("chefe", false) and mt.has("drop"):
		if randf() < float(mt.get("drop_chance", 0.3)):
			var did := str(mt.drop)
			if bag.has(did):
				gold += 150
				_msg("Já tem %s: +150 ouro" % ItemDB.get_item(did).display_name)
			else:
				give_item(did)
				CombatText.add(global_position + Vector2(0, -170), "ITEM DE CHEFE!", Color(1, 0.4, 0.25), true)
		return
	if randf() > (0.25 if el else (0.35 if lk.t == "golem" else 0.1)):
		return
	var pool := []
	for id in ItemDB.items:
		var it: EquipmentItem = ItemDB.items[id]
		if it.level_req > 1 and it.level_req <= level + 5 and not bag.has(String(id)) and not String(id).begins_with("chefe_"):
			pool.append(String(id))
	if not pool.is_empty():
		give_item(pool[randi() % pool.size()])


func gain_xp(n: int, g: int, _src: String) -> void:
	_roll_drop(_src)
	# conta a morte para a tarefa da sacerdotisa
	if not task.is_empty() and int(task.count) < int(task.need) and Monster.lookup(_src).get("t", "") == str(task.type):
		task.count = int(task.count) + 1
		if int(task.count) >= int(task.need):
			CombatText.add(global_position + Vector2(0, -140), "Tarefa concluída! Volte até Lira", Color(1, 0.9, 0.5), true)
	xp += n
	gold += g
	CombatText.add(global_position + Vector2(0, -96), "+%d xp" % n, Color(1, 1, 1))
	if g > 0:
		CombatText.add(global_position + Vector2(0, -110), "+%d ouro" % g, Color(1, 0.85, 0.3))
	var nl := Rules.level_for(xp)
	if nl > level:
		level = nl
		_recalc()
		hp = max_hp
		mp = max_mp
		CombatText.add(global_position + Vector2(0, -126), "NÍVEL %d!" % level, Color(1, 0.82, 0.25), true)
		SpellFx.level_up(get_parent(), global_position, Color(1, 0.78, 0.25))
		save()


# ------------------------------------------------------------ efeitos dos monstros no jogador
## tipo -> [tempo restante, força]. veneno (dano por segundo), lento, preso, atordoado.
var debuffs := {}
var _poison_acc := 0.0
var _tinted := false
const DEBUFF_TXT := {"veneno": ["envenenado", Color(0.5, 0.95, 0.3)], "lento": ["lento", Color(0.6, 0.8, 1.0)],
	"preso": ["preso", Color(0.85, 0.85, 0.8)], "atordoado": ["atordoado", Color(1, 0.9, 0.4)]}


func apply_debuff(tipo: String, dur: float, power: float, src: String) -> void:
	if dead or Rules.is_safe(global_position) or immortal_t > 0.0:
		return
	var cur: Array = debuffs.get(tipo, [0.0, 0.0])
	debuffs[tipo] = [maxf(cur[0], dur), maxf(cur[1], power), src]
	var t: Array = DEBUFF_TXT.get(tipo, [tipo, Color.WHITE])
	CombatText.add(global_position + Vector2(0, -104), t[0], t[1])


func _tick_debuffs(delta: float) -> void:
	for k in debuffs.keys():
		debuffs[k][0] -= delta
		if debuffs[k][0] <= 0.0:
			debuffs.erase(k)
	if debuffs.has("veneno"):
		_poison_acc += delta
		if _poison_acc >= 1.0:
			_poison_acc = 0.0
			var n := maxi(1, int(debuffs.veneno[1]))
			hp -= n
			CombatText.add(global_position + Vector2(0, -88), str(n), Color(0.5, 0.95, 0.3))
			if hp <= 0.0:
				_die(str(debuffs.veneno[2]))
	var tint := Color.WHITE
	if debuffs.has("veneno"):
		tint = Color(0.88, 1.0, 0.84)
	elif debuffs.has("lento"):
		tint = Color(0.9, 0.94, 1.0)
	if dead:
		return
	if tint != Color.WHITE:
		visual.modulate = tint
	elif _tinted:
		visual.modulate = Color.WHITE
	_tinted = tint != Color.WHITE


func take_damage(n: int, src: String) -> void:
	if dead or Rules.is_safe(global_position):
		return
	if immortal_t > 0.0:
		CombatText.add(global_position + Vector2(0, -88), "imune", Color(1, 0.95, 0.6))
		return
	if src != "Boneco de Treino":
		n = maxi(1, int(round(n / (1.0 + 0.04 * int(skills.defesa[0])) * (0.8 if buff_t > 0.0 else 1.0))))
		n = maxi(1, n - int(float(gear().get("defesa", 0)) * 0.6))
	if shield_hp > 0.0:
		# escudo comum segura metade de cada golpe; o fundido segura tudo
		var part := float(n) * (1.0 if shield_els.size() > 1 else 0.5)
		var ab := minf(shield_hp, part)
		shield_hp -= ab
		n -= int(round(ab))
		CombatText.add(global_position + Vector2(0, -78), "escudo -%d" % int(ab), shield_col)
		if shield_hp <= 0.5:
			_break_shield()
		if n <= 0:
			return
	hp -= n
	SpellArt.blood(get_parent(), global_position, float(n) / max_hp)
	skill_gain("defesa", 1.0)
	CombatText.add(global_position + Vector2(0, -88), str(n), Color(1, 0.15, 0.1))
	visual.modulate = Color(1, 0.5, 0.45)
	create_tween().tween_property(visual, "modulate", Color.WHITE, 0.25)
	if hp <= 0.0:
		_die(src)


func _die(src: String) -> void:
	dead = true
	hp = 0.0
	foe = null
	target = null
	var lost := int(xp * 0.08)
	xp -= lost
	level = Rules.level_for(xp)
	_recalc()
	CombatText.add(global_position + Vector2(0, -100), "Morto por %s (-%d xp)" % [src, lost], Color(1, 0.3, 0.25), true)
	var tw := create_tween()
	tw.tween_property(visual, "modulate", Color(0.2, 0.2, 0.2, 0.0), 1.0)
	tw.tween_interval(1.6)
	tw.tween_callback(_respawn)


func _respawn() -> void:
	global_position = spawn_pos
	hp = max_hp
	mp = max_mp
	dead = false
	visual.modulate = Color.WHITE
	save()


# ------------------------------------------------------------ alvo e ataques
func _alive_foe() -> bool:
	return foe != null and is_instance_valid(foe) and not foe.dead and on_screen(foe)


## Retângulo do mundo que aparece na tela (as magias só miram e atiram em quem está aparecendo).
func view_world_rect() -> Rect2:
	var ct := get_viewport().get_canvas_transform()
	var vr := get_viewport().get_visible_rect()
	var sc := ct.get_scale()
	return Rect2(ct.affine_inverse() * vr.position, vr.size / sc)


func on_screen(n: Node2D) -> bool:
	return view_world_rect().grow(-12.0).has_point(n.global_position + Vector2(0, -24))


func target_nearest() -> void:
	var list := []
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.dead and on_screen(m):
			var d := Rules.gdist(global_position, m.global_position)
			if d < 10.0:
				list.append([d, m])
	if list.is_empty():
		foe = null
		return
	list.sort_custom(func(a, b): return a[0] < b[0])
	foe = list[1][1] if list[0][1] == foe and list.size() > 1 else list[0][1]


func npc_at(p: Vector2) -> Node2D:
	for n in get_tree().get_nodes_in_group("npcs"):
		var q: Vector2 = n.global_position
		if absf(p.x - q.x) < 22.0 and p.y < q.y + 12.0 and p.y > q.y - 90.0:
			return n
	return null


func _open_npc(n: Node2D) -> void:
	_talk = null
	target = null
	facing = Iso.dir_from_vector(n.global_position - global_position)
	if NpcDialog.inst:
		NpcDialog.inst.open(n, self)


func monster_at(p: Vector2) -> Node2D:
	var best: Node2D = null
	var bd := 1e9
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.dead:
			continue
		var s := float(m.info.scale)
		var mp2: Vector2 = m.global_position
		if absf(p.x - mp2.x) < 22.0 * s and p.y < mp2.y + 12.0 and p.y > mp2.y - 88.0 * s:
			var d := p.distance_to(mp2 + Vector2(0, -40 * s))
			if d < bd:
				bd = d
				best = m
	return best


## Barra de magias: 8 casas com ids do catálogo (Spells). Personalizável no menu → Magias.
var bar: Array = []
var cds := {}
## Uso de cada magia (id -> vezes usada). O nível da magia sobe sem parar; 5 melhorias.
var spell_pts := {}
const UPGRADES := [3, 6, 10, 16, 25]


func spell_lvl(id: String) -> int:
	return spell_up(id)


## Melhorias da magia (1 a 5): a magia nasce na melhoria 1 e ganha +1 a cada nível do elemento,
## até a 5ª; no nível seguinte libera a próxima magia (por isso elas vêm de 5 em 5).
func spell_up(id: String) -> int:
	var s := Spells.get_spell(id, classe)
	if s.is_empty() or not spell_unlocked(id):
		return 0
	var t := int(s.tier)
	var lv: int
	var req: int
	if id.begins_with("fus:"):
		lv = elem_level(elem_b())
		req = int(FUS_REQ.get(t, 30))
	else:
		lv = elem_level(str(s.els[0]))
		req = tier_req(t)
	return clampi(lv - req + 1, 1, 5)
## Habilidades: nome -> [nível, pontos]. Sobem com o uso e sem limite.
var skills := {}
## Escudo mágico (absorve dano), bênçãos e estados da Luz.
var shield_hp := 0.0
var shield_max := 1.0
var shield_t := 0.0
var shield_col := Color.WHITE
## Elemento(s) do escudo atual (desenho: chamas, rocha com lava, bolha d'água, gelo, vento, raios, pedra, casca).
var shield_els: Array = []
var hot_t := 0.0
var spirit_t := 0.0
var _spirit_acc := 0.0
var buff_t := 0.0
var invis := false
var immortal_t := 0.0
## Fotos da inspeção visual: imortal sem desenhar as asas.
var photo_mode := false
var _aura: StatusAura
## Invocações vivas: elemento (ou "fus") -> Summon.
var summons := {}


## Os 3 elementos da classe (A, B e Luz) e a Defesa, todos no nível 1.
func _reset_skills() -> void:
	skills = {}
	var els0 := Spellbook.elements_of(classe)
	skills[els0[0]] = [1, 0.0]
	# o segundo elemento fica bloqueado (nível 0) até o elemento base chegar ao nível 31
	skills[els0[1]] = [0, 0.0]
	skills["luz"] = [1, 0.0]
	skills["defesa"] = [1, 0.0]
	bar = Spells.default_bar(classe)


## Saves de antes do esquema novo: soma todos os pontos de magia já ganhos nos dois elementos
## e redistribui na ordem certa (primeiro elemento até o 31, o resto no segundo).
## A barra volta para a padrão e as melhorias passam a vir do nível.
var spells_migrated := false


static func _pts_of(k: String, sk: Array) -> float:
	var t := float(sk[1])
	for l in range(1, int(sk[0])):
		t += Rules.skill_need(k, l)
	return t


func _migrate_spells() -> void:
	var a := elem_a()
	var b := elem_b()
	var total := _pts_of(a, skills[a]) + (_pts_of(b, skills[b]) if int(skills[b][0]) > 0 else 0.0)
	var la := 1
	while la < 31 and total >= Rules.skill_need(a, la):
		total -= Rules.skill_need(a, la)
		la += 1
	if la < 31:
		skills[a] = [la, total]
		skills[b] = [0, 0.0]
	else:
		skills[a] = [31, 0.0]
		var lb := 1
		while total >= Rules.skill_need(b, lb):
			total -= Rules.skill_need(b, lb)
			lb += 1
		skills[b] = [lb, total]
	spell_pts = {}
	bar = Spells.default_bar(classe)
	spells_migrated = true


func elem_a() -> String:
	return Spellbook.elements_of(classe)[0]


func elem_b() -> String:
	return Spellbook.elements_of(classe)[1]


## Nível de um elemento (fogo, lava, ..., luz).
func elem_level(el: String) -> int:
	return int(skills[el][0]) if skills.has(el) else 0


## Progressão das magias: cada elemento tem o próprio nível de magia (sobe com o uso).
## A magia 1 vem no nível 1; cada próxima pede mais 5 níveis (6, 11, 16, 21, 26): no 30 o lado
## está completo. No 31 do primeiro elemento começa o segundo, do nível 1, com magias mais fortes.
## As misturas dos dois (ultimates) vêm conforme o segundo elemento sobe.
const STEP := 5
const FUS_REQ := {3: 11, 5: 21, 7: 26, 8: 30}


static func tier_req(t: int) -> int:
	return 1 + STEP * (t - 1)


## A magia (id) está liberada para este personagem?
func spell_unlocked(id: String) -> bool:
	var s := Spells.get_spell(id, classe)
	if s.is_empty():
		return false
	var t := int(s.tier)
	if id.begins_with("fus:"):
		return elem_level(elem_b()) >= int(FUS_REQ.get(t, 30))
	var el: String = s.els[0]
	return skills.has(el) and elem_level(el) >= 1 and elem_level(el) >= tier_req(t)


## Texto de requisito de uma magia bloqueada.
func spell_req(id: String) -> String:
	var s := Spells.get_spell(id, classe)
	var nb: String = Spellbook.ELEMENTS[elem_b()].nome
	var na: String = Spellbook.ELEMENTS[elem_a()].nome
	if id.begins_with("fus:"):
		return "%s nível %d (mistura: magia suprema)" % [nb, int(FUS_REQ.get(int(s.tier), 30))]
	if elem_level(str(s.els[0])) <= 0 and str(s.els[0]) == elem_b():
		return "%s nível %d (o %s começa no nível 31 de %s)" % [nb, tier_req(int(s.tier)), nb, na]
	return "%s nível %d" % [Spellbook.ELEMENTS[s.els[0]].nome, tier_req(int(s.tier))]


## Nível de magia que vale para o dano/cura: o segundo elemento vem depois do primeiro (mais forte);
## as misturas somam os dois.
func magic_level(s: Dictionary) -> float:
	var id := str(s.get("id", ""))
	if id.begins_with("fus:"):
		return float(elem_level(elem_a()) + elem_level(elem_b()))
	var el := str(s.els[0])
	if el == elem_b() and el != "luz":
		return float(elem_level(el)) + 25.0
	return float(elem_level(el))


func magic_mult(s: Dictionary) -> float:
	var id := str(s.get("id", ""))
	if id.begins_with("fus:"):
		return 2.0 if int(s.tier) >= 7 else 1.3
	return 1.35 if str(s.els[0]) == elem_b() and str(s.els[0]) != "luz" else 1.0


func bar_spell(i: int) -> Dictionary:
	if i < 0 or i >= bar.size():
		return {}
	return Spells.get_spell(str(bar[i]), classe)


func set_bar(i: int, id: String) -> void:
	if i < 0 or i >= 8:
		return
	while bar.size() < 8:
		bar.append("")
	# a mesma magia não fica em duas casas: troca de lugar
	var j := bar.find(id)
	if j >= 0 and j != i:
		bar[j] = bar[i]
	bar[i] = id
	save()


var hp_pot := 5
var mp_pot := 5
var _pot_cd := 0.0
var _auto_t := 0.0


func _msg(t: String, c := Color(1, 0.8, 0.5)) -> void:
	CombatText.add(global_position + Vector2(0, -100), t, c)


## Primeira casa da barra (botão grande do celular, botão direito).
func cast_at(world_pos = null) -> void:
	cast_slot(0, world_pos)


## Poder (dano e cura): vem do nível de MAGIA do elemento, não do nível do personagem
## (o nível do personagem dá vida e mana). Segundo elemento mais forte; misturas = dano supremo.
func spell_power(s: Dictionary) -> float:
	var ml := magic_level(s)
	var p := (float(s.get("base", 0.0)) + float(s.get("perL", 0.0)) * ml) * (1.0 + 0.02 * ml) * magic_mult(s)
	# nível da própria magia (+2% por nível) e melhorias (+8% cada)
	var sid := str(s.get("id", ""))
	p *= 1.0 + 0.12 * (spell_up(sid) - 1)  # melhorias 1 a 5: até +48%
	var g := gear()
	var bonus := float(g.get("magia", 0))
	for e in s.els:
		bonus += float(g.get(e, 0))
	p *= 1.0 + bonus / 100.0
	return p * (1.25 if buff_t > 0.0 else 1.0)


func skill_gain(k: String, amt: float) -> void:
	if not skills.has(k) or int(skills[k][0]) <= 0:
		return
	var sk: Array = skills[k]
	sk[1] = float(sk[1]) + amt
	var up := false
	while float(sk[1]) >= Rules.skill_need(k, int(sk[0])):
		sk[1] = float(sk[1]) - Rules.skill_need(k, int(sk[0]))
		sk[0] = int(sk[0]) + 1
		up = true
	if up:
		# magia: cor do elemento; Defesa (não é magia): dourado
		var col: Color = Spellbook.ELEMENTS[k].cor if Spellbook.ELEMENTS.has(k) else Color(1, 0.78, 0.25)
		CombatText.add(global_position + Vector2(0, -118), "%s %d!" % [Rules.skill_name(k), sk[0]], col.lightened(0.2), true)
		SpellFx.level_up(get_parent(), global_position, col)
		_announce_spells(k)
		# elemento base no 31: ganha o primeiro nível do segundo elemento
		if k == elem_a() and int(sk[0]) >= 31 and elem_level(elem_b()) <= 0:
			skills[elem_b()] = [1, 0.0]
			var c2: Color = Spellbook.ELEMENTS[elem_b()].cor
			CombatText.add(global_position + Vector2(0, -150), "NOVO ELEMENTO: %s!" % Spellbook.ELEMENTS[elem_b()].nome, c2, true)
			SpellFx.level_up(get_parent(), global_position, c2)


## Ao subir o nível de um elemento: avisa a melhoria da magia atual ou a magia nova liberada.
func _announce_spells(k: String) -> void:
	if not Spellbook.ELEMENTS.has(k):
		return
	var lv := elem_level(k)
	var n: int = Spellbook.ELEMENTS[k].magias.size()
	var col: Color = Spellbook.ELEMENTS[k].cor
	for t in range(1, n + 1):
		var id := "%s:%d" % [k, t]
		var sp := Spells.get_spell(id, classe)
		if sp.is_empty():
			continue
		if lv == tier_req(t):
			CombatText.add(global_position + Vector2(0, -170), "NOVA MAGIA: %s!" % sp.nome, col.lightened(0.3), true)
		elif lv > tier_req(t) and lv <= tier_req(t) + 4:
			CombatText.add(global_position + Vector2(0, -170), "%s: melhoria %d/5" % [sp.nome, spell_up(id)], col.lightened(0.3), true)
	if k == elem_b():
		for t in FUS_REQ:
			if lv == int(FUS_REQ[t]):
				var fs := Spells.get_spell("fus:%d" % t, classe)
				if not fs.is_empty():
					CombatText.add(global_position + Vector2(0, -190), "MAGIA SUPREMA: %s!" % fs.nome, Color(1, 0.85, 0.4), true)


func cast_slot(i: int, world_pos = null) -> void:
	if i >= 0 and i < bar.size():
		cast_spell(str(bar[i]), world_pos)


func _heal(v: float, col := Color(0.4, 1, 0.5)) -> void:
	var n := int(round(v))
	hp = minf(max_hp, hp + n)
	CombatText.add(global_position + Vector2(0, -92), "+%d" % n, col)


## Lança uma magia pelo id. Mira: no alvo se houver; senão na posição indicada; senão à frente.
func cast_spell(id: String, world_pos = null) -> void:
	if dead or id == "":
		return
	var s := Spells.get_spell(id, classe)
	if s.is_empty():
		return
	if not spell_unlocked(id):
		_msg("%s: requer %s" % [s.nome, spell_req(id)])
		return
	# invocação já viva: o mesmo botão a desfaz
	if s.type == "summon":
		var key := "fus" if id.begins_with("fus:") else str(s.els[0])
		var cur = summons.get(key)
		if cur != null and is_instance_valid(cur) and not cur.dead:
			SpellFx.burst(get_parent(), cur.global_position + Vector2(0, -40), 30, 90.0, 0.6, 0.08, (s.color as Color).lightened(0.4), s.color)
			cur.queue_free()
			summons.erase(key)
			_msg("%s dispensado" % cur.display_name, s.color)
			return
	if float(cds.get(id, 0.0)) > 0.0:
		return
	if mp < float(s.mana):
		_msg("Mana insuficiente", Color(0.5, 0.7, 1))
		return
	var attack := Spells.is_attack(s)
	if attack and Rules.is_safe(global_position):
		_msg("Não dá para atacar na vila")
		return
	var aim: Vector2 = global_position + Iso.dir_vector(facing) * 120.0
	if _alive_foe():
		aim = foe.global_position
	elif world_pos != null:
		aim = world_pos
	var col: Color = s.color
	var els: Array = s.els
	var pw := spell_power(s)
	SpellArt.boost = maxi(0, spell_up(id) - 1)
	var hard := int(s.tier) >= 2
	var ok := true
	match s.type:
		"single":
			var tgt: Node2D = foe if _alive_foe() and Rules.gdist(global_position, foe.global_position) <= float(s.range) + 0.5 else _nearest_to(aim, 3.0, {})
			if tgt == null or Rules.gdist(global_position, tgt.global_position) > float(s.range) + 0.5:
				tgt = _nearest_to(global_position, float(s.range), {})
			if tgt == null:
				_msg("Nenhum alvo ao alcance")
				ok = false
			else:
				if not _alive_foe():
					foe = tgt
				aim = tgt.global_position
				var big: bool = s.get("big", false)
				# visual do nome: Pedrada = pedra em arco, Espinho = espinhos, Faísca = raio...
				var pel: String = els[els.size() - 1] if big else els[0]
				SpellArt.projectile(get_parent(), global_position, tgt, pel, big, els, func():
					if is_instance_valid(tgt) and not tgt.dead:
						tgt.take_damage(Rules.roll(pw, float(tgt.info.def)), self)
						for e in els:
							tgt.apply_effect(e, pw, self, big)
							SpellArt.impact(tgt.get_parent(), tgt.global_position, e, big))
		"cc":
			var c2 := Iso.to_grid(aim)
			var gp := Iso.to_grid(global_position)
			if c2.distance_to(gp) > float(s.range):
				c2 = gp + (c2 - gp).normalized() * float(s.range)
			var center := Iso.to_screen(c2)
			for e in els:
				SpellArt.cc(get_parent(), center, float(s.radius), e)
			for m in _monsters():
				if Iso.to_grid(m.global_position).distance_to(c2) <= float(s.radius) + 0.3:
					m.take_damage(Rules.roll(pw, float(m.info.def)), self)
					for e in els:
						m.apply_effect(e, pw, self, true)
		"cone", "line":
			var gd := Iso.to_grid(aim) - Iso.to_grid(global_position)
			if gd.length() < 0.01:
				gd = Iso.to_grid(global_position + Iso.dir_vector(facing)) - Iso.to_grid(global_position)
			gd = gd.normalized()
			var screen_dir := (Iso.to_screen(Iso.to_grid(global_position) + gd) - global_position).normalized()
			if s.type == "cone":
				SpellArt.cone(get_parent(), global_position, screen_dir, float(s.range) * 64.0, float(s.ang), els[0])
			else:
				var end := Iso.to_screen(Iso.to_grid(global_position) + gd * float(s.range))
				SpellArt.line(get_parent(), global_position, end, els[0])
			for m in _monsters():
				var v := Iso.to_grid(m.global_position) - Iso.to_grid(global_position)
				var hit := false
				if s.type == "cone":
					hit = v.length() <= float(s.range) + 0.3 and (v.length() < 0.7 or absf(v.angle_to(gd)) <= float(s.ang) + 0.15)
				else:
					var along := v.dot(gd)
					hit = along >= -0.3 and along <= float(s.range) + 0.3 and absf(v.cross(gd)) <= 0.9
				if hit:
					m.take_damage(Rules.roll(pw, float(m.info.def)), self)
					for e in els:
						m.apply_effect(e, pw, self, hard)
		"area":
			var cg := Iso.to_grid(global_position)
			var tg := Iso.to_grid(aim) - cg
			if tg.length() > float(s.range):
				tg = tg.normalized() * float(s.range)
			cg += tg
			var center2 := Iso.to_screen(cg)
			var rad := float(s.radius)
			var boom := func():
				for m2 in _monsters():
					if Iso.to_grid(m2.global_position).distance_to(cg) <= rad + 0.3:
						m2.take_damage(Rules.roll(pw, float(m2.info.def)), self)
						for e in els:
							m2.apply_effect(e, pw, self, true)
			SpellArt.area(get_parent(), center2, rad, els[0], boom, els)
		"summon":
			ok = _summon(id, s)
		"shield":
			if els.size() == 1 and els[0] != "luz" and spell_unlocked("fus:3"):
				# os dois elementos no mesmo nível: os escudos se fundem e ficam mais fortes
				els = [elem_a(), elem_b()]
				pw = spell_power(Spells.get_spell("fus:3", classe))
				col = (Spellbook.ELEMENTS[elem_a()].cor as Color).lerp(Spellbook.ELEMENTS[elem_b()].cor, 0.5)
				_msg("Escudos fundidos: %s" % Spellbook.FUSOES[classe][0], col)
			# aguenta até 50% da vida máxima (o poder da magia só conta até esse teto)
			shield_hp = max_hp * 0.5
			shield_max = shield_hp
			shield_t = float(s.dur)
			shield_col = col
			shield_els = els.duplicate()
			_msg("%s (%d)" % [s.nome, int(shield_hp)], col)
		"heal":
			_heal(Rules.roll(pw))
			for sm in summons.values():
				if is_instance_valid(sm):
					sm.heal(pw)
			SpellArt.light(get_parent(), "heal", global_position)
			if s.has("ring"):
				SpellArt.light(get_parent(), "ring", global_position)
				for rp in _allies(float(s.ring)):
					_ally(rp, {"k": "heal", "n": int(Rules.roll(pw))})
		"chainheal":
			var pts := [global_position + Vector2(0, -40)]
			_heal(Rules.roll(pw))
			# pula de aliado em aliado, do mais ferido ao menos ferido
			var al := _allies(8.0)
			al.sort_custom(func(a, b): return a.hp_pct < b.hp_pct)
			for rp in al:
				pts.append(rp.global_position + Vector2(0, -40))
				_ally(rp, {"k": "heal", "n": int(Rules.roll(pw))})
			for sm in summons.values():
				if is_instance_valid(sm):
					sm.heal(pw * 0.8)
					pts.append(sm.global_position + Vector2(0, -40))
			pts.append(global_position + Vector2(0, -40))
			SpellFx.lightning(get_parent(), pts, Color(1, 0.95, 0.6))
			get_tree().create_timer(0.5).timeout.connect(func(): if not dead: _heal(Rules.roll(pw * 0.8)))
		"hot":
			hot_t = float(s.dur)
			SpellArt.light(get_parent(), "bless", global_position)
			for rp in _allies(8.0):
				_ally(rp, {"k": "hot", "d": float(s.dur)})
			_msg("Bênção: cura contínua por 1 minuto", col)
		"spirit":
			spirit_t = float(s.dur)
			_msg("Espírito de Luz por 5 minutos", col)
		"buff":
			buff_t = float(s.dur)
			SpellArt.light(get_parent(), "brave", global_position)
			for rp in _allies(8.0):
				_ally(rp, {"k": "buff", "d": float(s.dur)})
			_msg("Aura de Bravura: +25% ataque e defesa", col)
		"invis":
			invis = true
			SpellArt.light(get_parent(), "veil", global_position)
			_msg("Invisível até atacar", col)
		"immortal":
			immortal_t = float(s.dur)
			_msg("ASCENSÃO! Imortal por 30 s", col)
			SpellFx.level_up(get_parent(), global_position, col)
	var up := spell_up(id) - 1
	SpellArt.boost = 0
	if not ok:
		return
	if up > 0:
		SpellArt.upgrade_fx(get_parent(), aim if attack else global_position, col, up)
	if attack and invis:
		invis = false
	mp -= float(s.mana)
	cds[id] = float(s.cd)
	# só sobe o elemento usado (as fusões sobem os dois, metade cada)
	for e in els:
		skill_gain(e, float(s.mana) / els.size())
	if attack:
		facing = Iso.dir_from_vector(aim - global_position) if (aim - global_position).length() > 4.0 else facing
	play_action("cast", 0.45)


## Invoca (ou cura, se já estiver viva). A fundida desfaz as separadas e vice-versa.
func _summon(id: String, s: Dictionary) -> bool:
	var key := "fus" if id.begins_with("fus:") else str(s.els[0])
	for k in summons.keys():
		var other = summons[k]
		if (key == "fus") != (k == "fus") and is_instance_valid(other):
			other.queue_free()
			summons.erase(k)
	var sm := Summon.make(self, s.els, key == "fus", str(s.nome))
	sm.position = global_position + Vector2(-50, 24)
	get_parent().add_child(sm)
	summons[key] = sm
	_msg("%s invocado!" % sm.display_name, s.color)
	return true


## Outros jogadores vivos a até r quadrados.
func _allies(r: float) -> Array:
	return get_tree().get_nodes_in_group("remote_players").filter(func(rp): return not rp.dead and Rules.gdist(global_position, rp.global_position) <= r)


## Manda uma magia de Luz para um amigo (pela rede) e mostra o brilho nele.
func _ally(rp: Node2D, e: Dictionary) -> void:
	SpellFx.heal(get_parent(), rp.global_position)
	if NetSync.inst:
		e["t"] = "ally"
		e["to"] = rp.uid
		e["de"] = display_name
		NetSync.inst.send(e)


## Recebe a magia de Luz de um amigo.
func receive_ally(e: Dictionary) -> void:
	if dead:
		return
	var de := str(e.get("de", "amigo"))
	match str(e.get("k", "")):
		"heal":
			_heal(clampf(float(e.get("n", 0)), 0, 99999))
			SpellFx.heal(get_parent(), global_position)
		"hot":
			hot_t = maxf(hot_t, clampf(float(e.get("d", 0)), 0, 60))
			_msg("Bênção de %s" % de, Color(1, 0.95, 0.6))
		"buff":
			buff_t = maxf(buff_t, clampf(float(e.get("d", 0)), 0, 300))
			_msg("Aura de Bravura de %s" % de, Color(1, 0.95, 0.6))


## Invocação automática: se a invocação está na barra e não está viva (ou morreu), invoca de novo.
## Se a fundida está na barra e liberada, só ela (para não ficar trocando com as separadas).
func _auto_summon() -> void:
	var ids := []
	for id in bar:
		var s := Spells.get_spell(str(id), classe)
		if not s.is_empty() and s.type == "summon" and spell_unlocked(str(id)):
			ids.append(str(id))
	if ids.has("fus:5"):
		ids = ["fus:5"]
	for id in ids:
		var s2 := Spells.get_spell(id, classe)
		var key := "fus" if id.begins_with("fus:") else str(s2.els[0])
		var cur = summons.get(key)
		if cur != null and is_instance_valid(cur) and not cur.dead:
			continue
		if float(cds.get(id, 0.0)) > 0.0 or mp < float(s2.mana):
			continue
		cast_spell(id)
		return


func summon_died(sm: Summon) -> void:
	for k in summons.keys():
		if summons[k] == sm:
			summons.erase(k)


## Estado das invocações para a rede: [x, y, elemento, fundida, direção, animação].
func summons_state() -> Array:
	var out := []
	for sm in summons.values():
		if is_instance_valid(sm) and not sm.dead:
			out.append([int(sm.global_position.x), int(sm.global_position.y), str(sm.els[0]), 1 if sm.fused else 0, sm.facing, sm.anim])
	return out


## Escudo zerado: quebra em cacos com a cor do elemento.
func _break_shield() -> void:
	shield_hp = 0.0
	shield_t = 0.0
	CombatText.add(global_position + Vector2(0, -110), "Escudo quebrou!", shield_col.lightened(0.3), true)
	SpellArt.shield_break(get_parent(), global_position, shield_col, shield_els)


## Estados da Luz e do escudo (contagem e efeitos por segundo).
func _tick_states(delta: float) -> void:
	if shield_t > 0.0:
		shield_t -= delta
		if shield_t <= 0.0:
			shield_hp = 0.0
	if hot_t > 0.0:
		hot_t -= delta
		hp = minf(max_hp, hp + max_hp * 0.05 * delta)
	if spirit_t > 0.0:
		spirit_t -= delta
		_spirit_acc += delta
		if _spirit_acc >= 2.0:
			_spirit_acc = 0.0
			# cura leve em quem tiver menos vida (você ou uma invocação)
			var low: Node2D = self
			var lf := hp / max_hp
			for sm in summons.values():
				if is_instance_valid(sm) and not sm.dead and sm.hp / sm.max_hp < lf:
					low = sm
					lf = sm.hp / sm.max_hp
			var low_rp: Node2D = null
			for rp in _allies(8.0):
				if rp.hp_pct / 100.0 < lf:
					low_rp = rp
					lf = rp.hp_pct / 100.0
			if low_rp != null:
				_ally(low_rp, {"k": "heal", "n": int(max_hp * 0.04 + 4)})
			elif low == self and hp < max_hp:
				_heal(max_hp * 0.04 + 4, Color(1, 0.95, 0.6))
			elif low != self:
				low.heal(low.max_hp * 0.05 + 4)
	if buff_t > 0.0:
		buff_t -= delta
	if immortal_t > 0.0:
		immortal_t -= delta
	if _aura:
		_aura.shield = shield_hp > 0.0
		_aura.shield_col = shield_col
		_aura.shield_els = shield_els
		_aura.spirit = spirit_t > 0.0
		_aura.immortal = immortal_t > 0.0 and not photo_mode
		_aura.wing_cols = [Spellbook.ELEMENTS[elem_a()].cor, Spellbook.ELEMENTS[elem_b()].cor]
		_aura.hot = hot_t > 0.0
	visual.modulate.a = 0.35 if invis else 1.0


func _monsters() -> Array:
	return get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.dead)


func _nearest_to(p: Vector2, r_tiles: float, skip: Dictionary) -> Node2D:
	var best: Node2D = null
	var bd := r_tiles
	var vr := view_world_rect().grow(-12.0)
	for m in _monsters():
		if skip.has(m) or not vr.has_point(m.global_position + Vector2(0, -24)):
			continue
		var d := Rules.gdist(p, m.global_position)
		if d <= bd:
			bd = d
			best = m
	return best


func use_pot(kind: String) -> void:
	if dead or _pot_cd > 0.0:
		return
	if kind == "hp":
		if hp_pot <= 0 and not Settings.auto.infinitas:
			_msg("Sem poções de vida")
			return
		if not Settings.auto.infinitas:
			hp_pot -= 1
		var v := 90 + 3 * level
		hp = minf(max_hp, hp + v)
		CombatText.add(global_position + Vector2(0, -92), "+%d" % v, Color(0.4, 1, 0.5))
		SpellFx.heal(get_parent(), global_position)
	else:
		if mp_pot <= 0 and not Settings.auto.infinitas:
			_msg("Sem poções de mana")
			return
		if not Settings.auto.infinitas:
			mp_pot -= 1
		var v2 := 60 + 3 * level
		mp = minf(max_mp, mp + v2)
		CombatText.add(global_position + Vector2(0, -92), "+%d mana" % v2, Color(0.45, 0.65, 1))
	_pot_cd = 1.0


func _auto_attack(delta: float) -> void:
	_atk_cd -= delta
	if not _alive_foe():
		foe = null
		return
	var dist := Rules.gdist(global_position, foe.global_position)
	if dist > 12.0:
		foe = null
		return
	if _atk_cd > 0.0 or _action_time > 0.0 or Rules.is_safe(global_position) or dist > ATTACK_RANGE:
		return
	_atk_cd = 1.2
	facing = Iso.dir_from_vector(foe.global_position - global_position)
	play_action("cast", 0.35)
	var tgt := foe
	# ataque básico com a cara do elemento (bola de fogo pequena, espinho, jato...), sem bola de luz
	var ea := elem_a()
	SpellArt.projectile(get_parent(), global_position, tgt, ea, false, [ea], func():
		if is_instance_valid(tgt) and not tgt.dead:
			var ml := float(elem_level(elem_a()))
			tgt.take_damage(Rules.roll((9.0 + 1.3 * ml + float(gear().get("ataque", 0))) * (1.0 + 0.02 * ml) * (1.25 if buff_t > 0.0 else 1.0), float(tgt.info.def)), self))


## Zoom da câmera (menu → Gráficos, roda do mouse, + e -).
func set_zoom(z: float) -> void:
	Settings.zoom = clampf(z, Settings.ZOOM_MIN, Settings.ZOOM_MAX)
	if camera:
		camera.zoom = Vector2.ONE * Settings.zoom


## Automação (menu → Automação): cada item liga e desliga sozinho, como na versão 3D.
func _auto_play(delta: float) -> void:
	_auto_t -= delta
	if _auto_t > 0.0 or dead:
		return
	_auto_t = 0.15
	var A := Settings.auto
	var hp_pct := hp * 100.0 / max_hp
	# cura: a magia de cura (Luz 1 ou 4) que estiver na barra
	var heal_id := ""
	for id in bar:
		var hs := Spells.get_spell(str(id), classe)
		if not hs.is_empty() and hs.type == "heal" and spell_unlocked(str(id)):
			heal_id = str(id)
			break
	if A.pocao_vida and hp_pct <= float(A.pocao_vida_pct) and _pot_cd <= 0.0:
		use_pot("hp")
	# treino de magia: mana cheia -> lança a magia escolhida
	if A.get("treino", false) and _action_time <= 0.0 and mp >= max_mp - 0.5:
		var tid := str(A.get("treino_id", ""))
		var ts := Spells.get_spell(tid, classe)
		if not ts.is_empty() and spell_unlocked(tid) and float(cds.get(tid, 0.0)) <= 0.0 and (not Spells.is_attack(ts) or _alive_foe()):
			cast_spell(tid)
			return
	# escudo na barra: ativa sozinho e de novo sempre que quebra ou acaba
	if A.get("escudo_auto", true) and shield_hp <= 0.0 and _action_time <= 0.0:
		for id in bar:
			var sh := Spells.get_spell(str(id), classe)
			if not sh.is_empty() and sh.type == "shield" and spell_unlocked(str(id)) and float(cds.get(str(id), 0.0)) <= 0.0 and mp >= float(sh.mana):
				cast_spell(str(id))
				return
	if A.cura and heal_id != "" and hp_pct <= float(A.cura_pct) and float(cds.get(heal_id, 0.0)) <= 0.0 and _action_time <= 0.0:
		var hm := float(Spells.get_spell(heal_id, classe).mana)
		if mp < hm and A.pocao_mana and _pot_cd <= 0.0:
			use_pot("mp")
		if mp >= hm:
			cast_spell(heal_id)
			return
	if A.pocao_mana and mp * 100.0 / max_mp <= float(A.pocao_mana_pct) and _pot_cd <= 0.0:
		use_pot("mp")
	if Rules.is_safe(global_position):
		return
	if A.alvo:
		# sempre o inimigo mais próximo; só troca se o novo estiver claramente mais perto (evita ficar pulando)
		var near := _nearest_to(global_position, 12.0, {})
		if near and near != foe:
			if not _alive_foe() or Rules.gdist(global_position, near.global_position) + 0.6 < Rules.gdist(global_position, foe.global_position):
				foe = near
	if A.get("summon_auto", true):
		_auto_summon()
	if not A.ataque or not _alive_foe() or _action_time > 0.0:
		return
	var dd := Rules.gdist(global_position, foe.global_position)
	# da última casa da barra para a primeira: a primeira magia de ataque pronta que alcançar
	for i in range(bar.size() - 1, -1, -1):
		var sp := Spells.get_spell(str(bar[i]), classe)
		if sp.is_empty() or not Spells.is_attack(sp) or not spell_unlocked(str(bar[i])) or float(cds.get(str(bar[i]), 0.0)) > 0.0:
			continue
		if dd > float(sp.get("range", 7.0)) + 0.3:
			continue
		if mp < float(sp.mana):
			if A.pocao_mana and _pot_cd <= 0.0:
				use_pot("mp")
			if mp < float(sp.mana):
				continue
		cast_spell(str(bar[i]))
		return


func _process(delta: float) -> void:
	# área visível do mundo (com margem) para não desenhar o que está fora da tela
	var vp := get_viewport()
	var inv := vp.get_canvas_transform().affine_inverse()
	CharacterVisual.view_rect = (inv * Rect2(Vector2.ZERO, vp.get_visible_rect().size)).grow(160.0)
	if dead:
		return
	mp = minf(max_mp, mp + delta * 4.0)
	hp = minf(max_hp, hp + delta * (3.0 if Rules.is_safe(global_position) else 1.0))
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - delta)
	_pot_cd -= delta
	_auto_attack(delta)
	_auto_play(delta)
	_tick_states(delta)
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 10.0
		save()


func _unhandled_input(ev: InputEvent) -> void:
	if dead:
		return
	var mb := ev as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var np := npc_at(get_global_mouse_position())
		if np != null:
			if Rules.gdist(global_position, np.global_position) <= 2.5:
				_open_npc(np)
			else:
				_talk = np
				target = np.global_position
				marker.show_at(target)
			return
		var m := monster_at(get_global_mouse_position())
		if m != null:
			foe = m
			return
		target = get_global_mouse_position()
		marker.show_at(target)
	if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		set_zoom(Settings.zoom * (1.08 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.08))
		Settings.save()
		return
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		cast_at(get_global_mouse_position())
	var mm := ev as InputEventMouseMotion
	if mm and mm.button_mask & MOUSE_BUTTON_MASK_LEFT and target != null:
		target = get_global_mouse_position()
	var k := ev as InputEventKey
	if get_viewport().gui_get_focus_owner() == null and k and k.pressed and not k.echo:
		var kc := k.physical_keycode
		if kc >= KEY_1 and kc <= KEY_8:
			cast_slot(kc - KEY_1, get_global_mouse_position())
		elif kc >= KEY_KP_1 and kc <= KEY_KP_8:
			cast_slot(kc - KEY_KP_1, get_global_mouse_position())
		elif kc == KEY_EQUAL or kc == KEY_KP_ADD or kc == KEY_MINUS or kc == KEY_KP_SUBTRACT:
			set_zoom(Settings.zoom * (1.1 if kc == KEY_EQUAL or kc == KEY_KP_ADD else 1.0 / 1.1))
			Settings.save()
		elif kc == KEY_Q:
			use_pot("hp")
		elif kc == KEY_E:
			use_pot("mp")
		elif kc == KEY_SPACE:
			target_nearest()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		return
	if _talk != null and is_instance_valid(_talk) and Rules.gdist(global_position, _talk.global_position) <= 2.2:
		_open_npc(_talk)
	var d := Vector2.ZERO
	if get_viewport().gui_get_focus_owner() == null:
		d = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_physical_key_pressed(KEY_A): d.x -= 1
		if Input.is_physical_key_pressed(KEY_D): d.x += 1
		if Input.is_physical_key_pressed(KEY_W): d.y -= 1
		if Input.is_physical_key_pressed(KEY_S): d.y += 1
	if joy.length() > 0.15:
		d = joy
	if d != Vector2.ZERO:
		target = null
	elif target != null:
		var to: Vector2 = target - global_position
		if to.length() < 5.0:
			target = null
		else:
			d = to
			if get_slide_collision_count() > 0 and get_real_velocity().length() < 5.0:
				target = null
	_tick_debuffs(delta)
	if debuffs.has("preso") or debuffs.has("atordoado"):
		d = Vector2.ZERO
	var ws := walk_speed
	var rs := run_speed
	if debuffs.has("lento"):
		walk_speed *= 0.55
		run_speed *= 0.55
	move(d, run_toggle or Input.is_physical_key_pressed(KEY_SHIFT), delta)
	walk_speed = ws
	run_speed = rs
	if target != null and velocity == Vector2.ZERO:
		target = null


## Marcador no chão onde você tocou para andar.
class TapMarker:
	extends Node2D
	var _t := 1.0

	func show_at(p: Vector2) -> void:
		global_position = p
		_t = 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		if _t < 1.0:
			_t += delta * 1.8
			queue_redraw()

	func _draw() -> void:
		if _t >= 1.0:
			return
		var a := 1.0 - _t
		var r := 10.0 + _t * 10.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
		draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(1, 0.75, 0.35, a), 2.0)
		draw_arc(Vector2.ZERO, r * 0.5, 0, TAU, 16, Color(1, 0.75, 0.35, a * 0.6), 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Brilhos dos estados: escudo (elipse na cor do elemento), espírito de luz no ombro,
## bênção (cura contínua) e asas de luz na imortalidade.
class StatusAura:
	extends Node2D
	var shield := false
	var shield_col := Color.WHITE
	var shield_els: Array = []
	var spirit := false
	var immortal := false
	## Asas da Ascensão: uma de cada elemento que o mago domina.
	var wing_cols := [Color(1, 0.95, 0.7), Color(1, 0.95, 0.7)]
	var hot := false
	var _t := 0.0

	func _ready() -> void:
		material = SpellFx._add_mat()
		z_index = 3

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	## Escudo com a cara do elemento.
	func _draw_shield(el: String) -> void:
		var c := Vector2(0, -36)
		match el:
			"fogo":  # Escudo de Chamas: línguas de fogo em volta
				for i in 14:
					var a := TAU * i / 14.0 + _t * 1.5
					var p := c + Vector2(cos(a) * 26, sin(a) * 30)
					var h := 10 + sin(_t * 9 + i) * 5
					SpellArt.poly(self, PackedVector2Array([p + Vector2(-4, 0), p + Vector2(0, -h), p + Vector2(4, 0)]), Color(1, 0.5 + 0.2 * sin(i), 0.1, 0.55))
			"lava":  # placas de rocha com veios de lava girando
				for i in 5:
					var a := TAU * i / 5.0 + _t * 0.8
					var p := c + Vector2(cos(a) * 28, sin(a) * 16)
					SpellArt.rock(self, p, 7, Color(0.2, 0.08, 0.05), i, a)
					draw_line(p + Vector2(-3, 0), p + Vector2(3, 1), Color(1, 0.5, 0.1), 1.5)
			"agua":  # bolha d'água com ondulação
				draw_set_transform(c, 0.0, Vector2(1.0, 1.25))
				draw_circle(Vector2.ZERO, 30, Color(0.3, 0.6, 1, 0.12))
				for i in 2:
					draw_arc(Vector2.ZERO, 30 - i * 3 + sin(_t * 4 + i) * 1.5, 0, TAU, 40, Color(0.6, 0.85, 1, 0.45), 2.0, SpellArt.AA)
				draw_arc(Vector2(-10, -12), 8, PI, PI * 1.5, 10, Color(1, 1, 1, 0.6), 2.0, SpellArt.AA)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"gelo":  # Armadura de Gelo: cristais em volta
				for i in 9:
					var a := TAU * i / 9.0
					var p := c + Vector2(cos(a) * 22, sin(a) * 28)
					var tip := p + Vector2(cos(a), sin(a)) * 10
					SpellArt.poly(self, PackedVector2Array([p + Vector2(-3, 0), tip, p + Vector2(3, 0)]), Color(0.8, 0.95, 1, 0.75))
			"vento":  # vento girando
				for i in 3:
					var a0 := _t * 5.0 + i * 2.1
					draw_set_transform(c, 0.0, Vector2(1.0, 1.25))
					draw_arc(Vector2.ZERO, 26 + i * 3, a0, a0 + 2.0, 16, Color(0.85, 1, 0.95, 0.55), 2.0, SpellArt.AA)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"raio":  # arcos elétricos
				for i in 3:
					var a := randf() * TAU
					var p1 := c + Vector2(cos(a) * 26, sin(a) * 32)
					var p2 := c + Vector2(cos(a + 0.8) * 26, sin(a + 0.8) * 32)
					SpellArt.jag(self, p1, p2, Color(0.8, 0.8, 1, 0.9), 1.3, 4, 5.0)
			"terra":  # Pele de Pedra: placas de pedra no corpo
				for i in 6:
					var p := c + Vector2((i % 2) * 12 - 6, -18 + i * 9)
					SpellArt.rock(self, p, 6, Color(0.45, 0.4, 0.35, 0.8), i + 11)
			"natureza":  # Casca de Árvore: vinhas e casca em volta
				for i in 4:
					var a := TAU * i / 4.0 + _t * 0.4
					SpellArt.root(self, Vector2(cos(a) * 16, 4 + sin(a) * 6), 60, 10, 1.0, Color(0.35, 0.28, 0.15, 0.8), 2.5)
			_:
				draw_set_transform(c, 0.0, Vector2(1.0, 1.25))
				draw_arc(Vector2.ZERO, 30, 0, TAU, 40, Color(shield_col, 0.4), 3.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw() -> void:
		if shield:
			for e in shield_els:
				_draw_shield(str(e))
			if shield_els.is_empty():
				_draw_shield("")
		if hot:
			for i in 3:
				var k := fmod(_t * 0.6 + i / 3.0, 1.0)
				draw_circle(Vector2(sin(_t * 2 + i * 2.1) * 14, -10 - k * 60), 2.0, Color(1, 0.95, 0.6, 1.0 - k))
		if spirit:
			var p := Vector2(16 + sin(_t * 2.0) * 4, -78 + cos(_t * 3.0) * 4)
			draw_circle(p, 9, Color(1, 0.95, 0.65, 0.25))
			draw_circle(p, 4, Color(1, 0.98, 0.85))
		if immortal:
			var fl := 0.8 + 0.2 * sin(_t * 4.0)
			for wi in 2:
				var sgn := -1 if wi == 0 else 1
				var wc: Color = wing_cols[wi]
				var pts := PackedVector2Array([Vector2(0, -52), Vector2(sgn * 38 * fl, -88), Vector2(sgn * 52 * fl, -64), Vector2(sgn * 30 * fl, -48)])
				SpellArt.poly(self, pts, Color(wc, 0.5))
				for f in 3:
					draw_line(Vector2(0, -52), Vector2(sgn * (30 + f * 9) * fl, -84 + f * 10), Color(wc.lightened(0.5), 0.7), 1.5)



## Efeitos ruins no corpo do jogador: veneno (bolhas verdes estourando e pingando de partes
## do corpo), lento (gosma/geada escorrendo nas pernas), preso (fios de teia e raízes
## enrolando as pernas), atordoado (estrelas girando na cabeça).
class DebuffFx:
	extends Node2D
	var pl: Node
	var _t := 0.0
	const PTS := [Vector2(0, -80), Vector2(-11, -64), Vector2(11, -64), Vector2(-16, -46), Vector2(16, -46), Vector2(0, -52), Vector2(-6, -30), Vector2(6, -30), Vector2(-6, -12), Vector2(6, -12)]

	func _ready() -> void:
		z_index = 2

	func _process(d: float) -> void:
		_t += d
		visible = not pl.debuffs.is_empty() and not pl.dead
		if visible:
			queue_redraw()

	func _draw() -> void:
		var db: Dictionary = pl.debuffs
		if db.has("veneno"):
			for i in PTS.size():
				var p: Vector2 = PTS[i]
				var f := fmod(_t * (0.7 + (i % 3) * 0.2) + i * 0.29, 1.0)
				if f < 0.7:
					var r := 1.5 + f * 4.0
					draw_circle(p + Vector2(0, -f * 6.0), r, Color(0.45, 0.95, 0.3, 0.6))
					draw_arc(p + Vector2(-1, -f * 6.0 - 1), r * 0.6, PI * 1.1, PI * 1.6, 6, Color(0.9, 1, 0.8, 0.8), 1.0)
				else:
					var q := (f - 0.7) / 0.3
					ElemArt.drop(self, p + Vector2(0, q * 26.0), Vector2(0, 300), 2.0, Color(0.4, 0.85, 0.25, 0.8 * (1.0 - q)))
			for i in 3:
				var f2 := fmod(_t * 0.5 + i * 0.33, 1.0)
				ElemArt.puff(self, Vector2(sin(_t + i * 2.0) * 10.0, -50 - f2 * 40.0), 6.0 + f2 * 8.0, Color(0.4, 0.8, 0.25, 0.18 * (1.0 - f2)))
		if db.has("lento"):
			for i in 5:
				var x := (i - 2) * 5.0
				var f := fmod(_t * 0.6 + i * 0.21, 1.0)
				ElemArt.ribbon(self, PackedVector2Array([Vector2(x, -26), Vector2(x + sin(i) * 2.0, -26 + 10.0 + f * 14.0)]), 2.5, 1.0, Color(0.7, 0.85, 1.0, 0.55))
				ElemArt.drop(self, Vector2(x, -26 + 10.0 + f * 14.0), Vector2(0, 250), 1.8, Color(0.75, 0.9, 1.0, 0.7 * (1.0 - f)))
		if db.has("preso"):
			for i in 5:
				var a := TAU * i / 5.0 + _t * 0.3
				var b := Vector2(cos(a) * 14.0, sin(a) * 6.0)
				var lp := PackedVector2Array()
				for j in 8:
					var f := j / 7.0
					lp.append(b.lerp(Vector2(sin(a + f * 3.0) * 7.0, -8 - f * 26.0), f))
				draw_polyline(lp, Color(0.95, 0.95, 0.9, 0.75), 1.2)
				ElemArt.vine(self, lp, 1.0, 2.2, i * 17, 0.8, false)
		if db.has("atordoado"):
			for i in 3:
				var a := _t * 5.0 + TAU * i / 3.0
				ElemArt.star(self, Vector2(cos(a) * 13.0, -96 + sin(a) * 4.0), 4.5, Color(1, 0.9, 0.4), _t * 3.0)
