class_name Monster
extends Actor
## Monstro: vaga perto de onde nasceu, persegue o jogador que chega perto,
## ataca (corpo a corpo ou à distância), morre, dá experiência e renasce.
## Arte provisória (mesmo boneco em camadas dos personagens).

## Tipos de monstro: lidos de data/monstros.json (a wiki do site usa o mesmo arquivo).
static var TYPES := _load_types()


static func _load_types() -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://data/monstros.json")
	var raw = JSON.parse_string(txt)
	if not raw is Dictionary:
		push_error("monstros.json inválido")
		return {}
	for k in raw:
		var m: Dictionary = raw[k]
		if m.has("colors"):
			var c: Dictionary = m.colors
			for ck in c:
				if c[ck] is String and str(c[ck]).begins_with("#"):
					c[ck] = Color.html(c[ck])
		if m.has("proj") and m.proj is String:
			m.proj = Color.html(m.proj)
		if not m.has("items"):
			m.items = []
	return raw

var mtype := ""
## Número fixo do monstro (igual em todos os jogadores: o mapa espalha sempre igual).
var idx := -1
var _rpos := Vector2.ZERO
var info: Dictionary = {}
var hp := 1.0
var max_hp := 1.0
var home := Vector2.ZERO
var _far := false
var foe: Node2D = null
var dead := false
var hurt_t := 0.0
var _respawn := 0.0
var _atk_cd := 0.0
var _scan := 0.0
var _wander := Vector2.ZERO
var _wander_t := 0.0
var _col: CollisionShape2D
## Habilidades (data/monstros.json): tempo de recarga de cada uma, ação em andamento e bônus de grito/uivo.
var _scd := {}
var _busy := 0.0
var _buff_t := 0.0


## Elite: versão mais forte de qualquer monstro comum (aura dourada, mais vida, dano e saque).
const ELITE_CHANCE := 0.07
var elite := false
var boss := false
## Nível do monstro (data/monstros.json "nivel"; elite +3).
var level := 1


## Nível de quem bate/apanha (jogador, amigo, ou o dono da invocação).
static func level_of(n) -> int:
	if n == null or not is_instance_valid(n):
		return 1
	if n.get("owner_p") != null and is_instance_valid(n.owner_p):
		return int(n.owner_p.get("level")) if n.owner_p.get("level") != null else 1
	return int(n.get("level")) if n.get("level") != null else 1


## Acha o tipo pelo nome mostrado (o saque e as tarefas chegam pelo nome, inclusive pela rede).
static var _by_name := {}


static func lookup(nome: String) -> Dictionary:
	if _by_name.is_empty():
		for k in TYPES:
			_by_name[str(TYPES[k].name)] = k
	var el := nome.ends_with(" Elite")
	var base := nome.trim_suffix(" Elite")
	if not _by_name.has(base):
		return {}
	return {"t": _by_name[base], "elite": el}


func configure(t: String, at: Vector2, is_elite := false, cap := 999) -> Monster:
	mtype = t
	info = TYPES[t]
	boss = bool(info.get("chefe", false))
	elite = is_elite and not boss and not info.get("dummy", false)
	if elite:
		info = info.duplicate(true)
		info["name"] = str(info.name) + " Elite"
		info["hp"] = float(info.hp) * 2.6
		info["atk"] = float(info.atk) * 1.45
		info["def"] = float(info.def) + 2.0
		info["xp"] = int(float(info.xp) * 3.0)
		info["gold"] = [int(info.gold[0]) * 3, int(info.gold[1]) * 3 + 2]
		info["scale"] = float(info.scale) * 1.2
		info["aggro"] = float(info.aggro) + 1.0
		info["speed"] = float(info.speed) * 1.08
		info["nivel"] = int(info.get("nivel", 1)) + 3
	# perto da vila os monstros são mais fracos: nível limitado pela distância
	var l0 := int(info.get("nivel", 1))
	if l0 > cap and not info.get("dummy", false):
		if not elite:
			info = info.duplicate(true)
		var l1 := maxi(1, cap)
		info["nivel"] = l1
		info["hp"] = float(info.hp) * Rules.mon_hp(l1) / Rules.mon_hp(l0)
		info["atk"] = float(info.atk) * Rules.mon_atk(l1) / Rules.mon_atk(l0)
		info["xp"] = int(round(float(info.xp) * Rules.mon_xp(l1) / Rules.mon_xp(l0)))
		info["def"] = float(info.def) * float(l1) / float(l0)
		var gk := Rules.mon_xp(l1) / Rules.mon_xp(l0)
		info["gold"] = [int(float(info.gold[0]) * gk), maxi(1, int(float(info.gold[1]) * gk))]
	level = int(info.get("nivel", 1))
	display_name = info.name
	body_colors = info.colors
	start_items = info.items
	max_hp = info.hp
	hp = max_hp
	home = at
	position = at
	walk_speed = info.speed
	run_speed = info.speed * 1.5
	_wander_t = randf() * 3.0
	return self


const CREATURES := ["slime", "quadrupede", "morcego", "aranha", "fantasma"]


func _make_visual() -> CharacterVisual:
	var b := str(info.get("body", "humano"))
	if b in CREATURES:
		var v := CreatureVisual.new()
		v.body = b
		v.variant = str(info.get("variant", ""))
		return v
	return CharacterVisual.new()


func _ready() -> void:
	super()
	add_to_group("monsters")
	for i in info.get("habilidades", []).size():
		_scd[i] = randf() * float(info.habilidades[i].get("cd", 6.0)) * 0.6
	visual.scale = Vector2.ONE * float(info.scale)
	if elite or boss:
		var au := RankAura.new()
		au.boss = boss
		au.r = 34.0 * float(info.scale)
		add_child(au)
		move_child(au, 0)
	for c in get_children():
		if c is CollisionShape2D:
			_col = c


## Jogador mais próximo (o meu e, no anfitrião, os dos amigos).
func _player() -> Node2D:
	var best: Node2D = null
	var bd := 1e9
	for p in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("remote_players") + get_tree().get_nodes_in_group("summons"):
		if not _valid_foe(p):
			continue
		var d := Rules.gdist(global_position, p.global_position)
		if d < bd:
			bd = d
			best = p
	return best


func _valid_foe(p) -> bool:
	return p != null and is_instance_valid(p) and not p.dead and not Rules.is_safe(p.global_position) and not p.get("invis")


func _physics_process(delta: float) -> void:
	if NetSync.is_puppet():
		_puppet(delta)
		return
	if dead:
		_respawn -= delta
		if _respawn <= 0.0:
			_revive()
		return
	_atk_cd -= delta
	_scan -= delta
	if hurt_t > 0.0:
		hurt_t -= delta
		visual.modulate = Color(1, 0.45, 0.4).lerp(Color.WHITE, 1.0 - hurt_t / 0.25)
	_tint(delta)
	if info.get("dummy", false):
		global_position = home  # nada empurra o boneco
	if _tick_status(delta):
		return
	for k in _scd:
		_scd[k] -= delta
	_buff_t -= delta
	if info.has("regen") and hp < max_hp:
		hp = minf(max_hp, hp + max_hp * float(info.regen) * delta)
	if _busy > 0.0:
		_busy -= delta
		visual.tick(delta, facing, anim, 0.0)
		return
	if foe != null and (not _valid_foe(foe) or Rules.gdist(global_position, foe.global_position) > 12.0):
		foe = null
	if foe == null and _scan <= 0.0:
		_scan = 0.4
		var p := _player()
		_far = p == null or Rules.gdist(global_position, p.global_position) > 24.0
		if _valid_foe(p) and Rules.gdist(global_position, p.global_position) < float(info.aggro):
			foe = p
	if foe == null and _far:
		return  # longe de todos: dorme (mapa grande, muitos monstros)
	var d := Vector2.ZERO
	var running := false
	if foe != null:
		var dist := Rules.gdist(global_position, foe.global_position)
		var reach := float(info.range) + 0.45
		if info.get("dummy", false):
			reach = 8.0
			if dist > 9.0:
				foe = null
				return
		if not info.get("dummy", false) and _root_t <= 0.0 and _skill(dist):
			pass
		elif _root_t > 0.0 and dist > reach:
			pass  # preso nas raízes: não anda, só ataca se alcançar
		elif dist <= reach:
			facing = Iso.dir_from_vector(foe.global_position - global_position)
			if _atk_cd <= 0.0:
				_atk_cd = float(info.aspd)
				_attack()
			if float(info.range) > 2.0 and dist < 1.8:
				d = global_position - foe.global_position
		else:
			d = foe.global_position - global_position
			running = true
	else:
		_wander_t -= delta
		if Rules.gdist(global_position, home) > 8.0:
			d = home - global_position
		else:
			if _wander_t <= 0.0:
				_wander_t = randf_range(2.0, 5.0)
				_wander = Vector2.ZERO if randf() < 0.4 else home + Iso.to_screen(Vector2(randf_range(-3, 3), randf_range(-3, 3)))
			if _wander != Vector2.ZERO:
				var to := _wander - global_position
				if to.length() < 6.0:
					_wander = Vector2.ZERO
				else:
					d = to
	if _root_t > 0.0:
		d = Vector2.ZERO
	var ws := walk_speed
	if _buff_t > 0.0:
		walk_speed *= 1.3
		run_speed = walk_speed * 1.5
	move(d, running, delta)
	walk_speed = ws
	run_speed = ws * 1.5
	if foe != null and d == Vector2.ZERO:
		facing = Iso.dir_from_vector(foe.global_position - global_position)


func _attack() -> void:
	if info.has("proj"):
		play_action("attack", 0.4)
	elif not info.get("dummy", false):
		play_action("punch" if randf() < 0.6 else "kick", 0.45)
	var tgt := foe
	if info.get("dummy", false):
		# o boneco revida em todos ao mesmo tempo (você e as invocações), 1% da vida total de cada um
		for t2 in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("remote_players"):
			if not _valid_foe(t2) or Rules.gdist(global_position, t2.global_position) > 8.0:
				continue
			var mh := float(t2.get("max_hp")) if t2.get("max_hp") != null else 100.0 + 10.0 * (int(t2.get("level")) - 1)
			var dmg := maxi(1, int(ceil(mh * 0.01)))
			var b2 := Bolt.new()
			b2.color = Color(0.85, 0.72, 0.4)
			b2.speed = 520.0
			b2.target = t2
			b2.global_position = global_position
			b2.on_hit = func(): if _valid_foe(t2): t2.take_damage(dmg, display_name)
			get_parent().add_child(b2)
		return
	if info.has("proj"):
		var b := Bolt.new()
		b.color = info.proj
		b.speed = 380.0
		b.target = tgt
		b.global_position = global_position
		b.on_hit = func(): _hit(tgt)
		get_parent().add_child(b)
	else:
		_hit(tgt)


func _hit(tgt, mult := 1.0, sk: Dictionary = {}) -> void:
	if dead or not _valid_foe(tgt):
		return
	if sk.is_empty() and randf() < 0.12:
		CombatText.add(tgt.global_position + Vector2(0, -80), "errou", Color(0.75, 0.75, 0.75))
		return
	var bonus := 1.25 if _buff_t > 0.0 else 1.0
	var dg := Rules.danger(level, level_of(tgt)) if not info.get("dummy", false) else 0
	tgt.take_damage(Rules.roll(float(info.atk) * mult * bonus * Rules.danger_dmg(dg)), display_name)
	var ef: Dictionary = sk.get("efeito", {}) if not sk.is_empty() else info.get("efeito_ataque", {})
	if not ef.is_empty() and tgt.has_method("apply_debuff") and randf() < float(ef.get("chance", 1.0)):
		tgt.apply_debuff(str(ef.tipo), float(ef.get("dur", 3.0)), float(ef.get("poder", 0.0)), display_name)


# ------------------------------------------------------------ habilidades dos monstros
func _skill(dist: float) -> bool:
	var list: Array = info.get("habilidades", [])
	for i in list.size():
		if _scd.get(i, 0.0) > 0.0:
			continue
		var s: Dictionary = list[i]
		var ok := false
		match str(s.tipo):
			"salto":
				ok = dist >= 1.6 and dist <= float(s.get("alcance", 4.0))
			"onda":
				ok = dist <= float(s.get("raio", 2.0))
			"disparo":
				ok = dist <= float(s.get("alcance", 6.0)) and dist >= 1.0
			"dreno":
				ok = dist <= float(s.get("alcance", 4.0))
			"cura":
				ok = _hurt_ally() != null
			"uivo":
				ok = _buff_t <= 0.0
		if not ok:
			continue
		_scd[i] = float(s.get("cd", 6.0))
		_do_skill(s)
		return true
	return false


func _foes_near(at: Vector2, r: float) -> Array:
	var out := []
	for p in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("remote_players") + get_tree().get_nodes_in_group("summons"):
		if _valid_foe(p) and Rules.gdist(at, p.global_position) <= r:
			out.append(p)
	return out


func _hurt_ally() -> Monster:
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.dead or m.info.get("dummy", false) or Rules.gdist(global_position, m.global_position) > 6.0:
			continue
		if m.hp < m.max_hp * 0.7:
			return m
	return null


func _do_skill(s: Dictionary) -> void:
	var col := Color.html(str(s.get("cor", "#ffd27a")))
	var tgt := foe
	var sc := float(info.scale)
	if tgt != null:
		facing = Iso.dir_from_vector(tgt.global_position - global_position)
	CombatText.add(global_position + Vector2(0, -96 * sc), str(s.get("nome", "")), col)
	match str(s.tipo):
		"salto":
			play_action("attack", 0.5)
			_busy = 0.5
			var to: Vector2 = tgt.global_position - global_position
			var end: Vector2 = tgt.global_position - to.normalized() * 20.0
			if Actor.walkable.is_valid() and not Actor.walkable.call(end):
				end = global_position
			var tw := create_tween()
			tw.tween_property(self, "global_position", end, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_callback(_land.bind(s, col))
		"onda":
			play_action("attack", 0.6)
			_busy = 0.55
			get_tree().create_timer(0.3).timeout.connect(_wave.bind(s, col))
		"disparo":
			play_action("attack", 0.45)
			_busy = 0.35
			var b := Bolt.new()
			b.color = col
			b.speed = float(s.get("vel", 360.0))
			b.size = float(s.get("tamanho", 1.0))
			b.target = tgt
			b.global_position = global_position
			b.on_hit = _bolt_hit.bind(tgt, s, col)
			get_parent().add_child(b)
		"dreno":
			play_action("attack", 0.5)
			_busy = 0.45
			MonsterFx.beam(get_parent(), self, tgt, col, 0.55)
			_hit(tgt, float(s.get("poder", 1.0)), s)
			var heal := float(info.atk) * float(s.get("poder", 1.0)) * 0.7
			hp = minf(max_hp, hp + heal)
			CombatText.add(global_position + Vector2(0, -80 * sc), "+%d" % int(heal), Color(0.4, 1, 0.4))
		"cura":
			var al := _hurt_ally()
			play_action("cast", 0.6)
			_busy = 0.5
			if al != null:
				var n := al.max_hp * float(s.get("poder", 0.25))
				al.hp = minf(al.max_hp, al.hp + n)
				MonsterFx.ring(get_parent(), al.global_position, 1.0, col, 0.6)
				CombatText.add(al.global_position + Vector2(0, -80), "+%d" % int(n), Color(0.4, 1, 0.4))
		"uivo":
			play_action("cast", 0.7)
			_busy = 0.6
			MonsterFx.ring(get_parent(), global_position, 3.5, col, 0.7)
			for m in get_tree().get_nodes_in_group("monsters"):
				if not m.dead and m.mtype == mtype and Rules.gdist(global_position, m.global_position) <= 7.0:
					m._buff_t = float(s.get("dur", 8.0))


func _land(s: Dictionary, col: Color) -> void:
	if dead:
		return
	MonsterFx.ring(get_parent(), global_position, 0.8, col, 0.35)
	if foe != null and _valid_foe(foe) and Rules.gdist(global_position, foe.global_position) <= 1.6:
		_hit(foe, float(s.get("poder", 1.5)), s)


func _wave(s: Dictionary, col: Color) -> void:
	if dead:
		return
	var r := float(s.get("raio", 2.0))
	MonsterFx.ring(get_parent(), global_position, r, col, 0.5)
	for p in _foes_near(global_position, r):
		_hit(p, float(s.get("poder", 1.3)), s)


func _bolt_hit(tgt, s: Dictionary, col: Color) -> void:
	if dead or tgt == null or not is_instance_valid(tgt):
		return
	var area := float(s.get("area", 0.0))
	if area > 0.0:
		MonsterFx.ring(get_parent(), tgt.global_position, area, col, 0.45)
		for p in _foes_near(tgt.global_position, area):
			_hit(p, float(s.get("poder", 1.2)), s)
	else:
		_hit(tgt, float(s.get("poder", 1.2)), s)


## Estado vindo do anfitrião: [idx, x, y, direção, animação, vida %, morto].
func apply_remote(row: Array) -> void:
	_rpos = Vector2(float(row[1]), float(row[2]))
	var f := str(row[3])
	if Iso.DIRS.has(f):
		facing = f
	anim = str(row[4])
	hp = max_hp * float(row[5]) / 100.0
	var now_dead := int(row[6]) == 1
	if now_dead and not dead:
		dead = true
		foe = null
		_die_visual()
	elif not now_dead and dead:
		dead = false
		global_position = _rpos
		_revive_visual()


func _puppet(delta: float) -> void:
	if dead or _rpos == Vector2.ZERO:
		return
	var to := _rpos - global_position
	if to.length() > 300.0:
		global_position = _rpos
	else:
		global_position += to * minf(1.0, delta * 10.0)
	if hurt_t > 0.0:
		hurt_t -= delta
		visual.modulate = Color(1, 0.45, 0.4).lerp(Color.WHITE, 1.0 - hurt_t / 0.25)
	_tint(delta)
	var spd := walk_speed * 1.5 if anim == "run" else (walk_speed if anim == "walk" else 0.0)
	visual.tick(delta, facing, anim, spd)


# ------------------------------------------------------------ efeitos das magias
var _dot_t := 0.0
var _dot_dps := 0.0
var _dot_acc := 0.0
var _dot_by: Node2D = null
var _stun_t := 0.0
var _slow_t := 0.0
var _root_t := 0.0
var _knock_v := Vector2.ZERO
var _knock_t := 0.0
var _st_col := Color.WHITE
var _st_t := 0.0
var _st_el := ""
var _sfx: StatusFx


func _clear_status() -> void:
	_dot_t = 0.0
	_stun_t = 0.0
	_slow_t = 0.0
	_root_t = 0.0
	_knock_t = 0.0
	_st_t = 0.0


## Efeito do elemento (docs/magias.md). hard = controle de grupo (atordoar, congelar, raízes).
## Criaturas do mesmo elemento: só atordoar, raízes (sem dano) e afastar funcionam.
func apply_effect(el: String, power: float, by: Node2D, hard: bool, from_net := false) -> void:
	if dead or not Spellbook.ELEMENTS.has(el) or el == "luz":
		return
	_st_col = Spellbook.ELEMENTS[el].cor
	_st_t = 3.0
	_st_el = el
	if NetSync.is_puppet() and not from_net:
		NetSync.inst.send({"t": "fx", "i": idx, "el": el, "p": power, "h": hard})
		return
	var same := str(info.get("el", "")) == el
	var tag := ""
	match el:
		"fogo":
			if not same: _dot(power * 0.12, 3.0, by); tag = "Queimando"
		"lava":
			if not same: _dot(power * 0.12, 3.0, by); tag = "Queimando"
			if hard and not same: _stun_t = maxf(_stun_t, 1.2); tag = "Atordoado"
		"agua":
			if not same: tag = "Sem cura"
		"gelo":
			if not same: _slow_t = maxf(_slow_t, 5.0); tag = "Lento"
			if hard and not same: _stun_t = maxf(_stun_t, 1.5); tag = "Congelado"
		"vento":
			if info.get("dummy", false):
				return  # o boneco de treino nunca sai do lugar
			var away := global_position - (by.global_position if by != null and is_instance_valid(by) else global_position + Vector2(0, -1))
			_knock_v = away.normalized() * 260.0
			_knock_t = 0.3
			tag = "Afastado"
		"raio":
			if not same: _dot(power * 0.1, 3.0, by); tag = "Eletrizado"
			if hard and not same: _stun_t = maxf(_stun_t, 1.0); tag = "Paralisado"
		"terra":
			if hard: _stun_t = maxf(_stun_t, 1.5); tag = "Atordoado"
		"natureza":
			if not same: _dot(power * 0.08, 3.0, by)
			if hard: _root_t = maxf(_root_t, 3.0); tag = "Preso"
	if tag != "" and (hard or el == "vento"):
		CombatText.add(global_position + Vector2(0, -100 * float(info.scale)), tag, _st_col)


func _dot(dps: float, dur: float, by: Node2D) -> void:
	_dot_dps = maxf(_dot_dps if _dot_t > 0.0 else 0.0, dps)
	_dot_t = dur
	_dot_by = by


## Cor do elemento enquanto o efeito dura, e o desenho do estado (gelo, raízes, chamas, faíscas).
func _tint(delta: float) -> void:
	if _sfx == null:
		_sfx = StatusFx.new()
		_sfx.m = self
		add_child(_sfx)
	if _st_t <= 0.0:
		return
	_st_t -= delta
	if hurt_t <= 0.0:
		visual.modulate = Color.WHITE.lerp(_st_col, 0.5 if _st_t > 0.0 else 0.0)


## Conta os efeitos. Devolve true se o monstro não pode agir neste quadro (atordoado/afastado).
func _tick_status(delta: float) -> bool:
	if _dot_t > 0.0:
		_dot_t -= delta
		_dot_acc += delta
		if _dot_acc >= 0.5:
			_dot_acc = 0.0
			take_damage(maxi(1, int(round(_dot_dps * 0.5))), _dot_by if is_instance_valid(_dot_by) else null)
			if dead:
				return true
	_slow_t -= delta
	_root_t -= delta
	walk_speed = float(info.speed) * (0.5 if _slow_t > 0.0 else 1.0)
	run_speed = walk_speed * 1.5
	if _knock_t > 0.0:
		_knock_t -= delta
		var np := global_position + _knock_v * delta
		if not Actor.walkable.is_valid() or Actor.walkable.call(np):
			global_position = np
		return true
	if _stun_t > 0.0:
		_stun_t -= delta
		move(Vector2.ZERO, false, delta)
		return true
	return false


func take_damage(n: int, by: Node2D, from_net := false) -> void:
	if dead:
		return
	# espelho: mostra o número na hora e manda o dano para quem hospeda
	if NetSync.is_puppet() and not from_net:
		hurt_t = 0.25
		CombatText.add(global_position + Vector2(0, -80 * float(info.scale)), str(n), Color(1, 0.35, 0.25))
		SpellArt.blood(get_parent(), global_position, float(n) / max_hp, str(info.get("sangue", "sangue")), 44.0 * float(info.scale))
		NetSync.inst.send({"t": "dmg", "i": idx, "n": n})
		return
	hp -= n
	hurt_t = 0.25
	CombatText.add(global_position + Vector2(0, -80 * float(info.scale)), str(n), Color(1, 0.35, 0.25))
	SpellArt.blood(get_parent(), global_position, float(n) / max_hp, str(info.get("sangue", "sangue")), 44.0 * float(info.scale))
	if foe == null and _valid_foe(by):
		foe = by
	if info.get("dummy", false):
		hp = max_hp  # imortal
		return
	if hp <= 0.0:
		_die(by)


func _die(by: Node2D) -> void:
	dead = true
	foe = null
	_respawn = float(info.get("respawn", 30.0)) * randf_range(0.85, 1.25) if boss else randf_range(25.0, 40.0) * (2.0 if elite else 1.0)
	_die_visual()
	if by != null and is_instance_valid(by) and by.has_method("gain_xp"):
		var g: Array = info.gold
		var xm := Rules.danger_xp(Rules.danger(level, level_of(by)))
		by.gain_xp(int(round(float(info.xp) * xm)), randi_range(int(g[0]), int(g[1])), display_name)


func _die_visual() -> void:
	if _col:
		_col.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(visual, "modulate", Color(0.2, 0.2, 0.2, 0.0), 0.8)
	tw.tween_callback(func(): visible = false)


func _revive_visual() -> void:
	visible = true
	visual.modulate = Color.WHITE
	if _col:
		_col.set_deferred("disabled", false)


func _revive() -> void:
	_clear_status()
	dead = false
	hp = max_hp
	global_position = home
	_revive_visual()


## Desenho do estado do monstro: bloco de gelo (congelado), raízes (preso), chamas (queimando),
## faíscas (paralisado/eletrizado), pedras rodando (atordoado).
class StatusFx:
	extends Node2D
	var m: Node
	var _t := 0.0

	func _ready() -> void:
		z_index = 2

	func _process(d: float) -> void:
		_t += d
		visible = m._st_t > 0.0 or m._root_t > 0.0 or m._stun_t > 0.0
		if visible:
			queue_redraw()

	func _draw() -> void:
		var s := float(m.info.scale)
		var el: String = m._st_el
		if m._stun_t > 0.0 and el == "gelo":
			draw_rect(Rect2(Vector2(-18, -86) * s, Vector2(36, 88) * s), Color(0.7, 0.9, 1, 0.35))
			draw_rect(Rect2(Vector2(-18, -86) * s, Vector2(36, 88) * s), Color(0.9, 1, 1, 0.7), false, 1.5)
			draw_line(Vector2(-12, -80) * s, Vector2(-4, -20) * s, Color(1, 1, 1, 0.6), 1.5)
		elif m._stun_t > 0.0:
			for i in 3:
				var a := _t * 5.0 + TAU * i / 3.0
				var p := Vector2(cos(a) * 12, -92 + sin(a) * 4) * s
				if el == "raio":
					SpellArt.jag(self, p, p + Vector2(6, 8), Color(0.85, 0.85, 1), 1.2, 3, 3.0)
				else:
					draw_circle(p, 3, Color(1, 0.9, 0.4))
		if m._root_t > 0.0:
			for i in 5:
				var a := TAU * i / 5.0
				SpellArt.root(self, Vector2(cos(a) * 12, sin(a) * 5) * s, 34 * s, (i % 2 * 2 - 1) * 8, 1.0, Color(0.35, 0.27, 0.13), 2.5)
		if m._dot_t > 0.0:
			if el == "fogo" or el == "lava":
				for i in 4:
					var x := sin(_t * 7 + i * 1.7) * 10 * s
					var h := (14 + sin(_t * 11 + i) * 6) * s
					SpellArt.poly(self, PackedVector2Array([Vector2(x - 4, -40 * s), Vector2(x, -40 * s - h), Vector2(x + 4, -40 * s)]), Color(1, 0.55, 0.1, 0.6))
			elif el == "raio":
				SpellArt.jag(self, Vector2(randf_range(-12, 12), -80) * s, Vector2(randf_range(-12, 12), -20) * s, Color(0.85, 0.85, 1, 0.8), 1.2, 4, 5.0)


## Aura no chão: dourada no elite, vermelha com runas girando no chefe.
class RankAura:
	extends Node2D
	var boss := false
	var r := 34.0
	var _t := 0.0

	func _ready() -> void:
		z_index = -1
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat

	func _process(d: float) -> void:
		_t += d
		var p := get_parent()
		visible = p.visible and not p.dead
		if visible:
			queue_redraw()

	func _draw() -> void:
		var c := Color(1.0, 0.25, 0.15) if boss else Color(1.0, 0.8, 0.3)
		var pulse := 0.75 + 0.25 * sin(_t * 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
		draw_circle(Vector2.ZERO, r * 1.1, Color(c, 0.12 * pulse))
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(c, 0.55 * pulse), 2.5)
		if boss:
			draw_arc(Vector2.ZERO, r * 1.25, 0, TAU, 48, Color(c, 0.3 * pulse), 1.5)
			for i in 6:
				var a := _t * 0.8 + i * TAU / 6.0
				draw_circle(Vector2(cos(a), sin(a)) * r * 1.12, 3.0, Color(1, 0.6, 0.3, 0.8 * pulse))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
