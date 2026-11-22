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
	run_speed = _chase_speed(float(info.speed))
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
		GlowProps.cull(au, Rect2(-au.r * 1.4, -au.r, au.r * 2.8, au.r * 2.0))
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


## Velocidade correndo atrás de alguém: os de 4 patas (e morcegos) são mais rápidos, mas
## ninguém alcança o jogador correndo (210); andando (120) só os rápidos alcançam.
func _chase_speed(ws: float) -> float:
	var four := ["quadrupede", "morcego"].has(str(info.get("body", "humano")))
	return minf(ws * (1.3 if four else 1.15), 175.0 if four else 135.0)


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
	_scan -= delta
	# dormindo longe de todos: só confere de vez em quando se alguém chegou perto
	if _far and foe == null and hurt_t <= 0.0 and _dot_t <= 0.0 and _st_t <= 0.0:
		if _scan > 0.0:
			return
		_scan = 0.6 + randf() * 0.3
		var p0 := _player()
		_far = p0 == null or Rules.gdist(global_position, p0.global_position) > 24.0
		if _far:
			return
	_atk_cd -= delta
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
	if _scan <= 0.0:
		_scan = 0.4
		var p := _player()
		_far = p == null or Rules.gdist(global_position, p.global_position) > 24.0
		if foe == null:
			if _valid_foe(p) and Rules.gdist(global_position, p.global_position) < float(info.aggro):
				foe = p
		elif p != null and p != foe and not info.get("dummy", false):
			# sempre vira para quem estiver mais perto (jogador, amigo ou invocação)
			if Rules.gdist(global_position, p.global_position) + 0.25 < Rules.gdist(global_position, foe.global_position):
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
		run_speed = _chase_speed(walk_speed)
	move(d, running, delta)
	walk_speed = ws
	run_speed = _chase_speed(ws)
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
			SpellArt.projectile(get_parent(), global_position, t2, "lasca", false, ["lasca"], func(): if _valid_foe(t2): t2.take_damage(dmg, display_name), 520.0)
		return
	if info.has("proj"):
		SpellArt.projectile(get_parent(), global_position, tgt, _shot_kind(), false, [], func(): _hit(tgt), 380.0)
	else:
		_hit(tgt)


func _hit(tgt, mult := 1.0, sk: Dictionary = {}) -> void:
	if dead or not _valid_foe(tgt):
		return
	if sk.is_empty() and randf() < 0.12:
		CombatText.add(tgt.global_position + Vector2(0, -80), "errou", Color(0.75, 0.75, 0.75))
		return
	var bonus := 1.25 if _buff_t > 0.0 else 1.0
	if info.get("dummy", false):
		# boneco de treino: sempre 5% da vida máxima de quem ele acerta
		var mh = tgt.get("max_hp")
		tgt.take_damage(maxi(1, int(round(float(mh if mh != null else 100.0) * 0.05))), display_name)
		return
	var dg := Rules.danger(level, level_of(tgt))
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
			_busy = 1.0
			var to: Vector2 = tgt.global_position - global_position
			# pulo de verdade: agacha, sobe num arco e cai (no máximo ~3 tiles, dá para ver e desviar)
			var end: Vector2 = global_position + to.limit_length(maxf(0.0, to.length() - 20.0)).limit_length(190.0)
			if Actor.walkable.is_valid() and not Actor.walkable.call(end):
				end = global_position
			var y0 := visual.position.y
			var tw := create_tween()
			tw.tween_interval(0.3)
			tw.tween_property(self, "global_position", end, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.parallel().tween_method(func(k: float): visual.position.y = y0 - sin(k * PI) * 46.0, 0.0, 1.0, 0.55)
			tw.tween_callback(func(): visual.position.y = y0)
			tw.tween_callback(_land.bind(s, col))
		"onda":
			play_action("attack", 0.6)
			_busy = 0.55
			get_tree().create_timer(0.3).timeout.connect(_wave.bind(s, col))
		"disparo":
			play_action("attack", 0.45)
			_busy = 0.35
			var th := _theme(s)
			var pel := th if th != "vento" else "terra"
			SpellArt.projectile(get_parent(), global_position, tgt, pel, float(s.get("tamanho", 1.0)) > 1.5, [pel], _bolt_hit.bind(tgt, s, col), float(s.get("vel", 360.0)))
		"dreno":
			play_action("attack", 0.5)
			_busy = 0.45
			_drain_fx(tgt, col)
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
				SpellArt.light(get_parent(), "heal", al.global_position)
				CombatText.add(al.global_position + Vector2(0, -80), "+%d" % int(n), Color(0.4, 1, 0.4))
		"uivo":
			play_action("cast", 0.7)
			_busy = 0.6
			_roar_fx(col)
			for m in get_tree().get_nodes_in_group("monsters"):
				if not m.dead and m.mtype == mtype and Rules.gdist(global_position, m.global_position) <= 7.0:
					m._buff_t = float(s.get("dur", 8.0))


## Dreno: fio de vida saindo do alvo e entrando no monstro (gotas correndo pela corrente).
func _drain_fx(tgt: Node2D, col: Color) -> void:
	var me := self
	SpellArt.fx(get_parent(), Vector2.ZERO, 0.7, func(n, k: float):
		if not is_instance_valid(tgt) or not is_instance_valid(me):
			return
		var p0: Vector2 = tgt.global_position + Vector2(0, -40)
		var p1: Vector2 = me.global_position + Vector2(0, -40)
		var nrm := (p1 - p0).orthogonal().normalized()
		var lp := PackedVector2Array()
		for i in 14:
			var f := i / 13.0
			lp.append(p0.lerp(p1, f) + nrm * sin(f * PI * 3.0 + n.t * 14.0) * 8.0 * sin(f * PI))
		ElemArt.ribbon(n, lp, 4.0, 2.0, Color(col, 0.35 * (1.0 - k)))
		ElemArt.ribbon(n, lp, 1.5, 0.8, Color(col.lightened(0.4), 0.8 * (1.0 - k)))
		for i in 6:
			var f := fmod(n.t * 1.8 + i / 6.0, 1.0)
			var q: Vector2 = lp[int(f * 13.0)]
			ElemArt.drop(n, q, (p1 - p0).normalized() * 300.0, 2.5, Color(col.lightened(0.2), 1.0 - k)))


## Urro/uivo: ar tremendo saindo da boca, poeira levantando, olhos acendendo.
func _roar_fx(col: Color) -> void:
	var sc := float(info.scale)
	var at := global_position + Vector2(0, -60 * sc)
	SpellArt.fx(get_parent(), at, 0.8, func(n, k: float):
		for i in 5:
			var f := fmod(k * 1.6 + i * 0.2, 1.0)
			var r := (14.0 + f * 70.0) * sc
			ElemArt.arc(n, Vector2.ZERO, r, -0.9, 0.9, 16, Color(1, 1, 1, 0.35 * (1.0 - f)), 2.0)
			ElemArt.arc(n, Vector2.ZERO, r, PI - 0.9, PI + 0.9, 16, Color(1, 1, 1, 0.35 * (1.0 - f)), 2.0)
		ElemArt.star(n, Vector2(-5, 2) * sc, 4.0 * sc * (1.0 - k), Color(col, 1.0 - k))
		ElemArt.star(n, Vector2(5, 2) * sc, 4.0 * sc * (1.0 - k), Color(col, 1.0 - k)))
	SpellArt.cloud(get_parent(), global_position, 40.0 * sc, Color(0.55, 0.47, 0.38, 0.35), 6, 1.0)


## O que o monstro atira no ataque normal à distância.
func _shot_kind() -> String:
	var t := mtype
	if t.contains("arqueiro"):
		return "flecha"
	if t.contains("lanceiro"):
		return "lanca"
	if t.contains("korvo") or t == "bandido":
		return "faca"
	if t.contains("aranha") or t.contains("aracn"):
		return "teia"
	if t.contains("slime"):
		return "gosma"
	if t.contains("necro") or t.contains("lich") or t.contains("fantasma"):
		return "trevas"
	var el := str(info.get("el", ""))
	return el if el != "" else "trevas"


## Tema visual da habilidade pelo nome/descrição (e elemento do monstro): fogo, gelo, raio,
## terra, trevas, gosma, teia, vento (urros), faca/flecha/lança (arremessos).
func _theme(s: Dictionary) -> String:
	var t := (str(s.get("nome", "")) + " " + str(s.get("desc", ""))).to_lower()
	for pair in [["chama|fogo|brasa|incandesc|flamej|magma|lava", "fogo"], ["gel|neve|congel|frio", "gelo"], ["raio|elétric|trov", "raio"],
			["teia|seda", "teia"], ["veneno|picada|ácido", "gosma"], ["gosma|geleia", "gosma"], ["morte|crânio|sombr|profan|necr|maldi|alma", "trevas"],
			["uivo|grito|rugido|fúria", "vento"], ["faca", "faca"], ["flecha", "flecha"], ["lança", "lanca"],
			["pedra|rocha|terra|terremoto|pisão|esmag|tremor|rúnic|pedregulho", "terra"], ["água|maré", "agua"]]:
		for w in str(pair[0]).split("|"):
			if t.contains(w):
				return str(pair[1])
	var el := str(info.get("el", ""))
	return el if el != "" else "terra"


## Explosão/onda da habilidade com a cara do tema (sem anel no chão).
func _burst(at: Vector2, r_tiles: float, th: String) -> void:
	var par := get_parent()
	match th:
		"gosma":
			SpellArt.splash(par, at, int(8 + r_tiles * 4), 60.0 * r_tiles, Color(0.45, 0.9, 0.35, 0.9), 12.0)
			SpellArt.cloud(par, at, 30.0 * r_tiles, Color(0.5, 0.85, 0.35, 0.3), 5, 1.0)
		"teia":
			SpellArt.fxn(par, at, 1.4, func(n, k: float):
				var a := 1.0 - maxf(0.0, k - 0.7) / 0.3
				for i in 10:
					var ang := TAU * i / 10.0
					n.draw_line(Vector2.ZERO, Vector2(cos(ang), sin(ang) * 0.5) * 70.0 * r_tiles * minf(1.0, k * 4.0), Color(0.95, 0.95, 0.9, 0.7 * a), 1.2)
				for j in 4:
					ElemArt.arc(n, Vector2.ZERO, 16.0 * (j + 1) * r_tiles * minf(1.0, k * 4.0), 0, TAU, 20, Color(0.95, 0.95, 0.9, 0.5 * a), 1.0))
		"trevas":
			SpellArt.cloud(par, at, 40.0 * r_tiles, Color(0.25, 0.06, 0.32, 0.55), 9, 1.2, 30.0)
			SpellArt.fx(par, at, 0.9, func(n, k: float):
				for i in 8:
					var ang := TAU * i / 8.0 + k * 2.0
					ElemArt.ribbon(n, PackedVector2Array([Vector2.ZERO + Vector2(0, -10), Vector2(cos(ang), sin(ang) * 0.5) * 60.0 * r_tiles * k + Vector2(0, -30 * k)]), 3.0, 0.5, Color(0.7, 0.35, 1.0, 0.6 * (1.0 - k)), true))
		"faca", "flecha", "lanca":
			SpellArt.impact(par, at, "terra")
		_:
			if r_tiles >= 1.5:
				SpellArt.cc(par, at, r_tiles * 0.8, th)
			else:
				SpellArt.impact(par, at, th, r_tiles >= 1.0)


func _land(s: Dictionary, col: Color) -> void:
	if dead:
		return
	SpellArt.impact(get_parent(), global_position, "terra", float(info.scale) > 1.4)
	SpellArt.cloud(get_parent(), global_position, 34.0 * float(info.scale), Color(0.55, 0.47, 0.38, 0.4), 6, 0.9)
	if foe != null and _valid_foe(foe) and Rules.gdist(global_position, foe.global_position) <= 1.6:
		_hit(foe, float(s.get("poder", 1.5)), s)


func _wave(s: Dictionary, col: Color) -> void:
	if dead:
		return
	var r := float(s.get("raio", 2.0))
	_burst(global_position, r, _theme(s))
	for p in _foes_near(global_position, r):
		_hit(p, float(s.get("poder", 1.3)), s)


func _bolt_hit(tgt, s: Dictionary, col: Color) -> void:
	if dead or tgt == null or not is_instance_valid(tgt):
		return
	var area := float(s.get("area", 0.0))
	var th := _theme(s)
	if area > 0.0:
		_burst(tgt.global_position, area, th)
		for p in _foes_near(tgt.global_position, area):
			_hit(p, float(s.get("poder", 1.2)), s)
	else:
		if th not in ["fogo", "gelo", "raio", "agua", "terra", "natureza"]:
			_burst(tgt.global_position, 0.6, th)
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
	if not _sfx.is_processing() and (_st_t > 0.0 or _root_t > 0.0 or _stun_t > 0.0 or _dot_t > 0.0):
		_sfx.set_process(true)
	if _st_t <= 0.0:
		return
	_st_t -= delta
	if hurt_t <= 0.0:
		var tk := 0.0
		if _st_t > 0.0:
			tk = 0.14
			if _st_el == "gelo":
				tk = 0.35
		var tc := Color(0.55, 0.3, 0.22) if _st_el == "fogo" or _st_el == "lava" else _st_col
		visual.modulate = Color.WHITE.lerp(tc, tk)


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
	run_speed = _chase_speed(walk_speed)
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


## Estado do monstro desenhado no próprio corpo: chamas saindo de várias partes (cabeça,
## ombros, braços, costas, pernas) com fumaça e brasas; geada grudada em pedaços do corpo e
## bloco de gelo facetado quando congela; arcos elétricos pulando entre partes; gotas d'água
## escorrendo; raízes subindo pelas pernas; estrelas/pedrinhas no atordoado.
class StatusFx:
	extends Node2D
	var m: Node
	var _t := 0.0
	var glow: StatusGlow
	var _smoke := []  # [pos, vel, vida, tam]

	func _ready() -> void:
		z_index = 2
		glow = StatusGlow.new()
		glow.fx = self
		add_child(glow)

	func _process(d: float) -> void:
		_t += d
		visible = m._st_t > 0.0 or m._root_t > 0.0 or m._stun_t > 0.0 or m._dot_t > 0.0 or not _smoke.is_empty()
		if not visible:
			set_process(false)  # volta quando o monstro recebe outro efeito
			return
		var el: String = m._st_el
		var burning: bool = m._dot_t > 0.0 and (el == "fogo" or el == "lava")
		if burning and randf() < d * 9.0:
			var an := anchors()
			var p: Vector2 = an[randi() % an.size()]
			_smoke.append([p + Vector2(randf_range(-3, 3), -6), Vector2(randf_range(-8, 8), randf_range(-38, -22)), 1.2, randf_range(4, 7)])
		for sm in _smoke:
			sm[2] -= d
			sm[0] += sm[1] * d
		_smoke = _smoke.filter(func(sm): return sm[2] > 0.0)
		queue_redraw()
		glow.queue_redraw()

	## Pontos do corpo (já na escala do monstro), pelo tipo de corpo.
	func anchors() -> Array:
		var s := float(m.info.scale)
		var pts: Array
		match str(m.info.get("body", "humano")):
			"quadrupede":
				pts = [Vector2(-20, -24), Vector2(-8, -30), Vector2(6, -30), Vector2(18, -26), Vector2(26, -36), Vector2(-16, -10), Vector2(14, -10), Vector2(-26, -26)]
			"slime":
				pts = [Vector2(-12, -10), Vector2(0, -22), Vector2(12, -10), Vector2(-6, -16), Vector2(8, -18)]
			"aranha":
				pts = [Vector2(-10, -16), Vector2(8, -18), Vector2(0, -22), Vector2(-22, -8), Vector2(22, -8), Vector2(-16, -4), Vector2(16, -4)]
			"morcego":
				pts = [Vector2(0, -52), Vector2(-20, -56), Vector2(20, -56), Vector2(-10, -50), Vector2(10, -50)]
			"fantasma":
				pts = [Vector2(0, -70), Vector2(-10, -56), Vector2(10, -56), Vector2(-6, -36), Vector2(6, -36)]
			_:
				pts = [Vector2(0, -80), Vector2(-11, -64), Vector2(11, -64), Vector2(-16, -46), Vector2(16, -46), Vector2(0, -52), Vector2(-6, -30), Vector2(6, -30), Vector2(-6, -12), Vector2(6, -12)]
		var out := []
		for p in pts:
			out.append(p * s)
		return out

	func _draw() -> void:
		var s := float(m.info.scale)
		var el: String = m._st_el
		var an := anchors()
		# fumaça das partes queimando (por baixo das chamas)
		for sm in _smoke:
			var k: float = 1.0 - float(sm[2]) / 1.2
			ElemArt.circle(self, sm[0], float(sm[3]) * (1.0 + k * 1.6) * s, Color(0.18, 0.16, 0.15, 0.32 * (1.0 - k)))
		if m._stun_t > 0.0 and el == "gelo":
			# bloco de gelo facetado em volta do corpo
			var h := 92.0 * s
			var w := 24.0 * s
			var outl := PackedVector2Array([Vector2(-w, 0), Vector2(-w * 1.1, -h * 0.45), Vector2(-w * 0.8, -h), Vector2(w * 0.3, -h * 1.05), Vector2(w * 1.05, -h * 0.7), Vector2(w, 0)])
			ElemArt.poly(self, outl, Color(0.72, 0.9, 1.0, 0.38))
			ElemArt.poly(self, PackedVector2Array([Vector2(-w * 0.8, -h), Vector2(w * 0.3, -h * 1.05), Vector2(w * 0.1, -h * 0.6), Vector2(-w * 0.5, -h * 0.55)]), Color(0.9, 0.97, 1.0, 0.35))
			var o2 := outl.duplicate()
			o2.append(outl[0])
			ElemArt.polyline(self, o2, Color(0.92, 1, 1, 0.8), 1.5)
			draw_line(Vector2(-w * 0.6, -h * 0.9), Vector2(-w * 0.2, -h * 0.2), Color(1, 1, 1, 0.55), 1.5)
			draw_line(Vector2(w * 0.5, -h * 0.75), Vector2(w * 0.7, -h * 0.35), Color(1, 1, 1, 0.4), 1.2)
		elif m._slow_t > 0.0 and el == "gelo":
			# geada grudada em partes do corpo
			for i in an.size():
				if i % 2 == 0:
					var p: Vector2 = an[i]
					for j in 3:
						var a := j * 2.1 + i
						var d := Vector2(cos(a), sin(a) - 0.6).normalized() * 6.0 * s
						ElemArt.poly(self, PackedVector2Array([p, p + d.rotated(0.4) * 0.5, p + d, p + d.rotated(-0.4) * 0.5]), Color(0.85, 0.96, 1, 0.75))
		elif el == "agua" and m._st_t > 0.0:
			for i in an.size():
				var p: Vector2 = an[i]
				var f := fmod(_t * 1.4 + i * 0.37, 1.0)
				var q := p + Vector2(0, f * 22.0 * s)
				ElemArt.poly(self, PackedVector2Array([q + Vector2(0, -3.5), q + Vector2(2, 1), q + Vector2(0, 2.5), q + Vector2(-2, 1)]), Color(0.55, 0.8, 1, 0.8 * (1.0 - f)))
		elif m._stun_t > 0.0 and el != "raio":
			for i in 3:
				var a := _t * 5.0 + TAU * i / 3.0
				var p := Vector2(cos(a) * 12, -96 + sin(a) * 4) * s
				if el == "terra":
					SpellArt.rock(self, p, 3.0, Color(0.5, 0.42, 0.32), i, _t * 6.0)
				else:
					var st := PackedVector2Array()
					for j in 10:
						var r := 4.0 if j % 2 == 0 else 1.8
						st.append(p + Vector2.from_angle(j * TAU / 10.0 - PI / 2 + _t * 3.0) * r)
					ElemArt.poly(self, st, Color(1, 0.9, 0.4))
		if m._root_t > 0.0:
			# raízes subindo pelas pernas e prendendo no chão
			for i in 6:
				var a := TAU * i / 6.0
				SpellArt.root(self, Vector2(cos(a) * 12, sin(a) * 5) * s, (26 + (i % 3) * 8) * s, (i % 2 * 2 - 1) * 9, 1.0, Color(0.33, 0.25, 0.12), 3.0)
			for i in 4:
				var p2 := Vector2((i - 1.5) * 6, -14 - i * 3) * s
				ElemArt.poly(self, PackedVector2Array([p2, p2 + Vector2(5, -3), p2 + Vector2(1, -6)]), Color(0.35, 0.65, 0.2))

## Camada que brilha (chamas, brasas, faíscas), somada à cor do monstro.
class StatusGlow:
	extends Node2D
	var fx

	func _ready() -> void:
		material = SpellFx._add_mat()

	func _draw() -> void:
		var m = fx.m
		var el: String = m._st_el
		var t: float = fx._t
		var s := float(m.info.scale)
		var an: Array = fx.anchors()
		if m._dot_t > 0.0 and (el == "fogo" or el == "lava"):
			# cada parte do corpo pega fogo num ritmo diferente (umas crescem, outras diminuem)
			for i in an.size():
				var p: Vector2 = an[i]
				var life := 0.5 + 0.5 * sin(t * (2.3 + i * 0.37) + i * 1.9)
				if life < 0.2:
					continue
				var hh := (10.0 + 9.0 * life) * s
				SpellArt.flame(self, p, hh, 4.5 * s, t, i * 2.7, 0.9)
				if el == "lava":
					ElemArt.circle(self, p + Vector2(0, 2), 2.2 * s, Color(1, 0.4, 0.05, 0.8))
			for i in 5:
				var f := fmod(t * 0.9 + i * 0.21, 1.0)
				var b: Vector2 = an[i % an.size()] + Vector2(sin(t * 3.0 + i) * 6.0, -f * 36.0 * s)
				ElemArt.circle(self, b, 1.3, Color(1, 0.7, 0.25, 1.0 - f))
		elif el == "raio" and (m._dot_t > 0.0 or m._stun_t > 0.0):
			# arcos pulando de uma parte do corpo para outra
			for i in 3:
				var a: Vector2 = an[(int(t * 12.0) + i * 3) % an.size()]
				var b: Vector2 = an[(int(t * 12.0) + i * 3 + 4) % an.size()]
				SpellArt.jag(self, a, b, Color(0.85, 0.85, 1, 0.9), 1.3, 5, 6.0 * s)
			var e: Vector2 = an[int(t * 7.0) % an.size()]
			SpellArt.jag(self, e, e + Vector2(randf_range(-14, 14), randf_range(8, 18)) * s, Color(0.75, 0.75, 1, 0.7), 1.0, 3, 4.0)


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
		ElemArt.circle(self, Vector2.ZERO, r * 1.1, Color(c, 0.12 * pulse))
		ElemArt.arc(self, Vector2.ZERO, r, 0, TAU, 48, Color(c, 0.55 * pulse), 2.5)
		if boss:
			ElemArt.arc(self, Vector2.ZERO, r * 1.25, 0, TAU, 48, Color(c, 0.3 * pulse), 1.5)
			for i in 6:
				var a := _t * 0.8 + i * TAU / 6.0
				ElemArt.circle(self, Vector2(cos(a), sin(a)) * r * 1.12, 3.0, Color(1, 0.6, 0.3, 0.8 * pulse))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
