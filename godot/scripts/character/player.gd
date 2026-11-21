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
const SAVE_PATH := "user://arson_jogador.cfg"

var level := 1
var xp := 0
var gold := 0
var dead := false
## Monstro selecionado como alvo.
var foe: Node2D = null
var spawn_pos := Vector2.ZERO
var _atk_cd := 0.0
var _save_t := 10.0


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
	camera.zoom = Vector2(1.9, 1.9)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.offset = Vector2(0, -30)
	add_child(camera)
	camera.make_current()
	# raio de luz do herói (como no Diablo 2): o mundo é escuro, a luz acompanha o personagem
	var aura := LightKit.make(Color(1.0, 0.9, 0.78), 0.95, 3.6, true, 0.0)
	aura.position = Vector2(0, -30)
	aura.height = 60.0
	add_child(aura)
	marker = TapMarker.new()
	marker.top_level = true
	marker.z_index = -5
	add_child(marker)


# ------------------------------------------------------------ progresso
func _recalc() -> void:
	max_hp = 100.0 + 10.0 * (level - 1)
	max_mp = 100.0 + 15.0 * (level - 1)


func _load() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) == OK:
		xp = int(c.get_value("jogador", "xp", 0))
		gold = int(c.get_value("jogador", "ouro", 0))
		hp_pot = int(c.get_value("jogador", "pocao_vida", 5))
		mp_pot = int(c.get_value("jogador", "pocao_mana", 5))
		var sk = c.get_value("jogador", "habilidades", {})
		if sk is Dictionary:
			for k in skills:
				if sk.get(k) is Array and sk[k].size() == 2:
					skills[k] = [maxi(1, int(sk[k][0])), float(sk[k][1])]
	level = Rules.level_for(xp)
	_recalc()
	hp = max_hp
	mp = max_mp


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("jogador", "xp", xp)
	c.set_value("jogador", "ouro", gold)
	c.set_value("jogador", "nivel", level)
	c.set_value("jogador", "pocao_vida", hp_pot)
	c.set_value("jogador", "pocao_mana", mp_pot)
	c.set_value("jogador", "habilidades", skills)
	c.save(SAVE_PATH)


func gain_xp(n: int, g: int, _src: String) -> void:
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
		save()


func take_damage(n: int, src: String) -> void:
	if dead or Rules.is_safe(global_position):
		return
	n = maxi(1, int(round(n / (1.0 + 0.04 * int(skills.defesa[0])))))
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


## Magias do mago (como na versão 3D). range/radius em tiles; poder = base + perL × nível.
const SPELLS := [
	{"k": "ignis", "nome": "Bola de Fogo", "curto": "Fogo", "lvl": 1, "mana": 12, "cd": 0.8, "type": "fireball", "base": 28.0, "perL": 4.0},
	{"k": "sopro", "nome": "Sopro de Chamas", "curto": "Sopro", "lvl": 2, "mana": 30, "cd": 3.0, "type": "cone", "range": 4.5, "ang": 0.6, "base": 30.0, "perL": 4.5},
	{"k": "corrente", "nome": "Corrente Elétrica", "curto": "Raio", "lvl": 4, "mana": 40, "cd": 3.5, "type": "chain", "range": 7.0, "jumps": 6, "jumpR": 3.6, "decay": 0.85, "base": 34.0, "perL": 5.0},
	{"k": "meteoro", "nome": "Meteoro", "curto": "Meteoro", "lvl": 6, "mana": 65, "cd": 5.0, "type": "area", "at": "aim", "range": 8.0, "radius": 2.3, "delay": 0.7, "base": 48.0, "perL": 6.0},
	{"k": "nova", "nome": "Nova Flamejante", "curto": "Nova", "lvl": 10, "mana": 90, "cd": 7.0, "type": "area", "at": "self", "radius": 3.4, "delay": 0.0, "base": 52.0, "perL": 6.0},
	{"k": "cura", "nome": "Cura", "curto": "Cura", "lvl": 1, "mana": 25, "cd": 1.0, "type": "heal", "base": 30.0, "perL": 4.0},
]
var cds := {}
## Habilidades: nome -> [nível, pontos]. Sobem com o uso e sem limite.
var skills := {"magia": [1, 0.0], "defesa": [1, 0.0]}
var hp_pot := 5
var mp_pot := 5
var _pot_cd := 0.0


func _msg(t: String, c := Color(1, 0.8, 0.5)) -> void:
	CombatText.add(global_position + Vector2(0, -100), t, c)


## Bola de fogo (botão do celular, botão direito, tecla 1).
func cast_at(world_pos = null) -> void:
	cast_slot(0, world_pos)


func spell_power(s: Dictionary) -> float:
	return (float(s.base) + float(s.perL) * level) * (1.0 + 0.06 * int(skills.magia[0]))


func skill_gain(k: String, amt: float) -> void:
	var sk: Array = skills[k]
	sk[1] = float(sk[1]) + amt
	var up := false
	while float(sk[1]) >= Rules.skill_need(k, int(sk[0])):
		sk[1] = float(sk[1]) - Rules.skill_need(k, int(sk[0]))
		sk[0] = int(sk[0]) + 1
		up = true
	if up:
		CombatText.add(global_position + Vector2(0, -118), "%s %d!" % [Rules.SKILL_NAMES[k], sk[0]], Color(0.6, 0.85, 1), true)


## Lança a magia `i`. Mira: no alvo se houver; senão na posição indicada; senão à frente.
func cast_slot(i: int, world_pos = null) -> void:
	if dead or i < 0 or i >= SPELLS.size() or _action_time > 0.0:
		return
	var s: Dictionary = SPELLS[i]
	if level < int(s.lvl):
		_msg("%s: nível %d" % [s.nome, s.lvl])
		return
	if float(cds.get(s.k, 0.0)) > 0.0:
		return
	if mp < float(s.mana):
		_msg("Mana insuficiente", Color(0.5, 0.7, 1))
		return
	if s.type != "heal" and Rules.is_safe(global_position):
		_msg("Não dá para atacar na vila")
		return
	var aim: Vector2 = global_position + Iso.dir_vector(facing) * 120.0
	if _alive_foe():
		aim = foe.global_position
	elif world_pos != null:
		aim = world_pos
	var ok := true
	match s.type:
		"fireball":
			var d := (aim - global_position).normalized() if (aim - global_position).length() > 4.0 else Iso.dir_vector(facing)
			var fb := Fireball.new()
			fb.dir = d
			fb.power = spell_power(s)
			fb.caster = self
			fb.global_position = global_position + Iso.ground_velocity(d, 1.0) * 18.0
			get_parent().add_child(fb)
		"cone":
			var gd := Iso.to_grid(aim) - Iso.to_grid(global_position)
			if gd.length() < 0.01:
				gd = Iso.to_grid(global_position + Iso.dir_vector(facing)) - Iso.to_grid(global_position)
			gd = gd.normalized()
			var screen_dir := (Iso.to_screen(Iso.to_grid(global_position) + gd) - global_position).normalized()
			SpellFx.cone(get_parent(), global_position, screen_dir, float(s.range) * 64.0, float(s.ang))
			for m in _monsters():
				var v := Iso.to_grid(m.global_position) - Iso.to_grid(global_position)
				if v.length() <= float(s.range) + 0.3 and (v.length() < 0.7 or absf(v.angle_to(gd)) <= float(s.ang) + 0.15):
					m.take_damage(Rules.roll(spell_power(s), float(m.info.def)), self)
		"chain":
			var first: Node2D = foe if _alive_foe() and Rules.gdist(global_position, foe.global_position) <= float(s.range) + 1.0 else _nearest_to(aim, 2.5, {})
			if first == null or Rules.gdist(global_position, first.global_position) > float(s.range) + 1.0:
				first = _nearest_to(global_position, float(s.range), {})
			if first == null:
				_msg("Nenhum alvo ao alcance")
				ok = false
			else:
				var hit := {}
				var pts := [global_position]
				var pw := spell_power(s)
				var m: Node2D = first
				for j in int(s.jumps):
					if m == null:
						break
					hit[m] = true
					pts.append(m.global_position)
					m.take_damage(Rules.roll(pw, float(m.info.def)), self)
					pw *= float(s.decay)
					m = _nearest_to(m.global_position, float(s.jumpR), hit)
				SpellFx.lightning(get_parent(), pts)
		"area":
			var cg := Iso.to_grid(global_position)
			if s.at == "aim":
				var tg := Iso.to_grid(aim) - cg
				if tg.length() > float(s.range):
					tg = tg.normalized() * float(s.range)
				cg += tg
			var center := Iso.to_screen(cg)
			var pw2 := spell_power(s)
			var rad := float(s.radius)
			var boom := func():
				for m2 in _monsters():
					if Iso.to_grid(m2.global_position).distance_to(cg) <= rad + 0.3:
						m2.take_damage(Rules.roll(pw2, float(m2.info.def)), self)
			if float(s.delay) > 0.0:
				SpellFx.meteor(get_parent(), center, float(s.delay), rad, boom)
			else:
				SpellFx.explosion(get_parent(), center, rad)
				boom.call()
		"heal":
			var v2 := Rules.roll(spell_power(s))
			hp = minf(max_hp, hp + v2)
			CombatText.add(global_position + Vector2(0, -92), "+%d" % v2, Color(0.4, 1, 0.5))
			SpellFx.heal(get_parent(), global_position)
	if not ok:
		return
	mp -= float(s.mana)
	cds[s.k] = float(s.cd)
	skill_gain("magia", float(s.mana))
	if s.type != "heal":
		facing = Iso.dir_from_vector(aim - global_position) if (aim - global_position).length() > 4.0 else facing
	play_action("cast", 0.45)


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
		if hp_pot <= 0:
			_msg("Sem poções de vida")
			return
		hp_pot -= 1
		var v := 90 + 3 * level
		hp = minf(max_hp, hp + v)
		CombatText.add(global_position + Vector2(0, -92), "+%d" % v, Color(0.4, 1, 0.5))
		SpellFx.heal(get_parent(), global_position)
	else:
		if mp_pot <= 0:
			_msg("Sem poções de mana")
			return
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
			tgt.take_damage(Rules.roll((9.0 + 1.3 * level) * (1.0 + 0.06 * int(skills.magia[0])), float(tgt.info.def)), self)
	skill_gain("magia", 3.0)
	get_parent().add_child(b)


func _process(delta: float) -> void:
	if dead:
		return
	mp = minf(max_mp, mp + delta * 4.0)
	hp = minf(max_hp, hp + delta * (3.0 if Rules.is_safe(global_position) else 1.0))
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - delta)
	_pot_cd -= delta
	_auto_attack(delta)
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 10.0
		save()


func _unhandled_input(ev: InputEvent) -> void:
	if dead:
		return
	var mb := ev as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var m := monster_at(get_global_mouse_position())
		if m != null:
			foe = m
			return
		target = get_global_mouse_position()
		marker.show_at(target)
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		cast_at(get_global_mouse_position())
	var mm := ev as InputEventMouseMotion
	if mm and mm.button_mask & MOUSE_BUTTON_MASK_LEFT and target != null:
		target = get_global_mouse_position()
	var k := ev as InputEventKey
	if get_viewport().gui_get_focus_owner() == null and k and k.pressed and not k.echo:
		var kc := k.physical_keycode
		if kc >= KEY_1 and kc <= KEY_6:
			cast_slot(kc - KEY_1, get_global_mouse_position())
		elif kc >= KEY_KP_1 and kc <= KEY_KP_6:
			cast_slot(kc - KEY_KP_1, get_global_mouse_position())
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
