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
	super()
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
	var aura := LightKit.make(Color(1.0, 0.9, 0.78), 0.95, 3.6, true, 0.0)
	aura.position = Vector2(0, -30)
	aura.height = 60.0
	add_child(aura)
	_aura = StatusAura.new()
	add_child(_aura)
	var ca := ClassAura.new()
	add_child(ca)
	ca.setup(classe)
	marker = TapMarker.new()
	marker.top_level = true
	marker.z_index = -5
	add_child(marker)


# ------------------------------------------------------------ progresso
func _recalc() -> void:
	max_hp = 100.0 + 10.0 * (level - 1)
	max_mp = 100.0 + 15.0 * (level - 1)


func _load() -> void:
	_reset_skills()
	var c := ConfigFile.new()
	if c.load(Chars.path()) == OK:
		xp = int(c.get_value("jogador", "xp", 0))
		gold = int(c.get_value("jogador", "ouro", 0))
		hp_pot = int(c.get_value("jogador", "pocao_vida", 5))
		mp_pot = int(c.get_value("jogador", "pocao_mana", 5))
		saved_pos = c.get_value("jogador", "posicao", Vector2(-1, -1))
		saved_map = int(c.get_value("jogador", "mapa", 0))
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
					skills[k] = [maxi(1, int(sk[k][0])), float(sk[k][1])]
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
	c.set_value("jogador", "ouro", gold)
	c.set_value("jogador", "nivel", level)
	c.set_value("jogador", "pocao_vida", hp_pot)
	c.set_value("jogador", "pocao_mana", mp_pot)
	c.set_value("jogador", "habilidades", skills)
	c.set_value("jogador", "barra", bar)
	c.set_value("jogador", "tarefa", task)
	if not dead:
		c.set_value("jogador", "posicao", Iso.to_grid(global_position))
		c.set_value("jogador", "mapa", map_hash)
	c.save(Chars.path())


func gain_xp(n: int, g: int, _src: String) -> void:
	# conta a morte para a tarefa da sacerdotisa
	if not task.is_empty() and int(task.count) < int(task.need) and str(Monster.TYPES[task.type].name) == _src:
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


func take_damage(n: int, src: String) -> void:
	if dead or Rules.is_safe(global_position):
		return
	if immortal_t > 0.0:
		CombatText.add(global_position + Vector2(0, -88), "imune", Color(1, 0.95, 0.6))
		return
	n = maxi(1, int(round(n / (1.0 + 0.04 * int(skills.defesa[0])) * (0.8 if buff_t > 0.0 else 1.0))))
	if shield_hp > 0.0:
		var ab := minf(shield_hp, n)
		shield_hp -= ab
		n -= int(ab)
		CombatText.add(global_position + Vector2(0, -78), "escudo -%d" % int(ab), shield_col)
		if n <= 0:
			return
	hp -= n
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
	return foe != null and is_instance_valid(foe) and not foe.dead


func target_nearest() -> void:
	var list := []
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.dead:
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
## Habilidades: nome -> [nível, pontos]. Sobem com o uso e sem limite.
var skills := {}
## Escudo mágico (absorve dano), bênçãos e estados da Luz.
var shield_hp := 0.0
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
var _aura: StatusAura
## Invocações vivas: elemento (ou "fus") -> Summon.
var summons := {}


## Os 3 elementos da classe (A, B e Luz) e a Defesa, todos no nível 1.
func _reset_skills() -> void:
	skills = {}
	for e in Spellbook.elements_of(classe):
		skills[e] = [1, 0.0]
	skills["luz"] = [1, 0.0]
	skills["defesa"] = [1, 0.0]
	bar = Spells.default_bar(classe)


func elem_a() -> String:
	return Spellbook.elements_of(classe)[0]


func elem_b() -> String:
	return Spellbook.elements_of(classe)[1]


## Nível de um elemento (fogo, lava, ..., luz).
func elem_level(el: String) -> int:
	return int(skills[el][0]) if skills.has(el) else 0


## A magia (id) está liberada para este personagem?
func spell_unlocked(id: String) -> bool:
	var s := Spells.get_spell(id, classe)
	if s.is_empty():
		return false
	var t := int(s.tier)
	if id.begins_with("fus:"):
		var la := elem_level(elem_a())
		var lb := elem_level(elem_b())
		return (la == lb and la >= 3) if t == 3 else mini(la, lb) >= t
	var el: String = s.els[0]
	return skills.has(el) and elem_level(el) >= t


## Texto de requisito de uma magia bloqueada.
func spell_req(id: String) -> String:
	var s := Spells.get_spell(id, classe)
	if id.begins_with("fus:"):
		var both := "%s e %s" % [Spellbook.ELEMENTS[elem_a()].nome, Spellbook.ELEMENTS[elem_b()].nome]
		return ("%s no mesmo nível (3+)" % both) if int(s.tier) == 3 else ("%s no nível %d" % [both, s.tier])
	return "%s nível %d" % [Spellbook.ELEMENTS[s.els[0]].nome, s.tier]


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


## Poder: base + por nível do personagem, × nível do(s) elemento(s) e bênção de ataque.
func spell_power(s: Dictionary) -> float:
	var el_lv := 0.0
	for e in s.els:
		el_lv += elem_level(e)
	el_lv /= maxf(1, s.els.size())
	var p := (float(s.get("base", 0.0)) + float(s.get("perL", 0.0)) * level) * (1.0 + 0.06 * el_lv)
	return p * (1.25 if buff_t > 0.0 else 1.0)


func skill_gain(k: String, amt: float) -> void:
	if not skills.has(k):
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
			shield_hp = pw * 1.5
			shield_t = float(s.dur)
			shield_col = col
			shield_els = els.duplicate()
			SpellFx.ring(get_parent(), global_position, 0.9, col, 0.6)
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
	if not ok:
		return
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
		_aura.immortal = immortal_t > 0.0
		_aura.wing_cols = [Spellbook.ELEMENTS[elem_a()].cor, Spellbook.ELEMENTS[elem_b()].cor]
		_aura.hot = hot_t > 0.0
	visual.modulate.a = 0.35 if invis else 1.0


func _monsters() -> Array:
	return get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.dead)


func _nearest_to(p: Vector2, r_tiles: float, skip: Dictionary) -> Node2D:
	var best: Node2D = null
	var bd := r_tiles
	for m in _monsters():
		if skip.has(m):
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
	var b := Bolt.new()
	b.target = tgt
	b.global_position = global_position + Vector2(0, -2)
	b.on_hit = func():
		if is_instance_valid(tgt) and not tgt.dead:
			tgt.take_damage(Rules.roll((9.0 + 1.3 * level) * (1.0 + 0.06 * elem_level(elem_a())) * (1.25 if buff_t > 0.0 else 1.0), float(tgt.info.def)), self)
	get_parent().add_child(b)


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
	move(d, run_toggle or Input.is_physical_key_pressed(KEY_SHIFT), delta)
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
					draw_colored_polygon(PackedVector2Array([p + Vector2(-4, 0), p + Vector2(0, -h), p + Vector2(4, 0)]), Color(1, 0.5 + 0.2 * sin(i), 0.1, 0.55))
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
					draw_arc(Vector2.ZERO, 30 - i * 3 + sin(_t * 4 + i) * 1.5, 0, TAU, 40, Color(0.6, 0.85, 1, 0.45), 2.0, true)
				draw_arc(Vector2(-10, -12), 8, PI, PI * 1.5, 10, Color(1, 1, 1, 0.6), 2.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"gelo":  # Armadura de Gelo: cristais em volta
				for i in 9:
					var a := TAU * i / 9.0
					var p := c + Vector2(cos(a) * 22, sin(a) * 28)
					var tip := p + Vector2(cos(a), sin(a)) * 10
					draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 0), tip, p + Vector2(3, 0)]), Color(0.8, 0.95, 1, 0.75))
			"vento":  # vento girando
				for i in 3:
					var a0 := _t * 5.0 + i * 2.1
					draw_set_transform(c, 0.0, Vector2(1.0, 1.25))
					draw_arc(Vector2.ZERO, 26 + i * 3, a0, a0 + 2.0, 16, Color(0.85, 1, 0.95, 0.55), 2.0, true)
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
				draw_colored_polygon(pts, Color(wc, 0.5))
				for f in 3:
					draw_line(Vector2(0, -52), Vector2(sgn * (30 + f * 9) * fl, -84 + f * 10), Color(wc.lightened(0.5), 0.7), 1.5)
