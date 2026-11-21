class_name Monster
extends Actor
## Monstro: vaga perto de onde nasceu, persegue o jogador que chega perto,
## ataca (corpo a corpo ou à distância), morre, dá experiência e renasce.
## Arte provisória (mesmo boneco em camadas dos personagens).

const TYPES := {
	"esqueleto": {
		"name": "Esqueleto", "hp": 40, "atk": 6.0, "def": 0.0, "xp": 14, "gold": [1, 6], "speed": 75.0,
		"range": 0.9, "aspd": 1.4, "aggro": 5.0, "scale": 1.0,
		"colors": {"skin": Color(0.78, 0.74, 0.64), "under": Color(0.32, 0.3, 0.27), "hair": Color(0.78, 0.74, 0.64), "eyes": Color(1, 0.25, 0.1), "glow_eyes": true},
		"items": ["elmo_ferro"],
	},
	"carnical": {
		"name": "Carniçal", "hp": 70, "atk": 9.0, "def": 1.0, "xp": 25, "gold": [2, 10], "speed": 60.0,
		"range": 0.9, "aspd": 1.6, "aggro": 5.0, "scale": 1.05,
		"colors": {"skin": Color(0.38, 0.44, 0.33), "under": Color(0.22, 0.2, 0.16), "hair": Color(0.15, 0.14, 0.1), "eyes": Color(0.9, 0.85, 0.3), "glow_eyes": true},
		"items": ["calca_tecido"],
	},
	"bandido": {
		"name": "Bandido", "hp": 90, "atk": 12.0, "def": 2.0, "xp": 35, "gold": [5, 20], "speed": 95.0,
		"range": 0.9, "aspd": 1.3, "aggro": 6.0, "scale": 1.0,
		"colors": {"skin": Color(0.55, 0.42, 0.33), "under": Color(0.18, 0.15, 0.12), "hair": Color(0.12, 0.09, 0.06), "eyes": Color(0.2, 0.15, 0.1)},
		"items": ["capuz_aprendiz", "gibao_verde", "calca_tecido", "botas_couro", "luvas_couro"],
	},
	"cultista": {
		"name": "Cultista das Chamas", "hp": 80, "atk": 11.0, "def": 1.0, "xp": 40, "gold": [8, 25], "speed": 80.0,
		"range": 5.0, "aspd": 1.9, "aggro": 7.0, "scale": 1.0, "proj": Color(1.0, 0.4, 0.1), "el": "fogo",
		"colors": {"skin": Color(0.5, 0.38, 0.3), "under": Color(0.25, 0.05, 0.04), "hair": Color(0.05, 0.04, 0.04), "eyes": Color(1, 0.4, 0.1), "glow_eyes": true},
		"items": ["tunica_aprendiz", "capuz_aprendiz", "botas_couro"],
	},
	"boneco": {
		"name": "Boneco de Treino", "hp": 1000, "atk": 1.0, "def": 0.0, "xp": 0, "gold": [0, 0], "speed": 0.0,
		"range": 1.3, "aspd": 2.0, "aggro": 2.6, "scale": 1.0, "dummy": true,
		"colors": {"skin": Color(0.78, 0.64, 0.36), "under": Color(0.6, 0.48, 0.25), "hair": Color(0.85, 0.72, 0.4), "eyes": Color(0.2, 0.15, 0.1)},
		"items": ["avental_taverna"],
	},
	"golem": {
		"name": "Golem de Pedra", "hp": 320, "atk": 24.0, "def": 6.0, "xp": 160, "gold": [30, 70], "speed": 52.0,
		"range": 1.2, "aspd": 2.2, "aggro": 6.0, "scale": 1.55, "el": "terra",
		"colors": {"skin": Color(0.2, 0.19, 0.19), "under": Color(0.16, 0.15, 0.15), "hair": Color(0.18, 0.17, 0.17), "eyes": Color(1, 0.6, 0.15), "glow_eyes": true, "core": true},
		"items": [],
	},
}

var mtype := ""
## Número fixo do monstro (igual em todos os jogadores: o mapa espalha sempre igual).
var idx := -1
var _rpos := Vector2.ZERO
var info: Dictionary = {}
var hp := 1.0
var max_hp := 1.0
var home := Vector2.ZERO
var foe: Node2D = null
var dead := false
var hurt_t := 0.0
var _respawn := 0.0
var _atk_cd := 0.0
var _scan := 0.0
var _wander := Vector2.ZERO
var _wander_t := 0.0
var _col: CollisionShape2D


func configure(t: String, at: Vector2) -> Monster:
	mtype = t
	info = TYPES[t]
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


func _ready() -> void:
	super()
	add_to_group("monsters")
	visual.scale = Vector2.ONE * float(info.scale)
	for c in get_children():
		if c is CollisionShape2D:
			_col = c


## Jogador mais próximo (o meu e, no anfitrião, os dos amigos).
func _player() -> Node2D:
	var best: Node2D = null
	var bd := 1e9
	for p in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("remote_players"):
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
	if _tick_status(delta):
		return
	if foe != null and (not _valid_foe(foe) or Rules.gdist(global_position, foe.global_position) > 12.0):
		foe = null
	if foe == null and _scan <= 0.0:
		_scan = 0.4
		var p := _player()
		if _valid_foe(p) and Rules.gdist(global_position, p.global_position) < float(info.aggro):
			foe = p
	var d := Vector2.ZERO
	var running := false
	if foe != null:
		var dist := Rules.gdist(global_position, foe.global_position)
		var reach := float(info.range) + 0.45
		if info.get("dummy", false):
			reach = 8.0
			if dist > 9.0:
				foe = null
		if _root_t > 0.0 and dist > reach:
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
	move(d, running, delta)
	if foe != null and d == Vector2.ZERO:
		facing = Iso.dir_from_vector(foe.global_position - global_position)


func _attack() -> void:
	play_action("attack", 0.4)
	var tgt := foe
	if info.get("dummy", false):
		if Rules.gdist(global_position, tgt.global_position) > float(info.range) + 0.6:
			var b2 := Bolt.new()
			b2.color = Color(0.85, 0.72, 0.4)
			b2.speed = 420.0
			b2.target = tgt
			b2.global_position = global_position
			b2.on_hit = func(): if _valid_foe(tgt): tgt.take_damage(1, display_name)
			get_parent().add_child(b2)
		elif _valid_foe(tgt):
			tgt.take_damage(1, display_name)
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


func _hit(tgt) -> void:
	if dead or not _valid_foe(tgt):
		return
	if randf() < 0.12:
		CombatText.add(tgt.global_position + Vector2(0, -80), "errou", Color(0.75, 0.75, 0.75))
		return
	tgt.take_damage(Rules.roll(float(info.atk)), display_name)


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


## Cor do elemento enquanto o efeito dura.
func _tint(delta: float) -> void:
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
		NetSync.inst.send({"t": "dmg", "i": idx, "n": n})
		return
	hp -= n
	hurt_t = 0.25
	CombatText.add(global_position + Vector2(0, -80 * float(info.scale)), str(n), Color(1, 0.35, 0.25))
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
	_respawn = randf_range(25.0, 40.0)
	_die_visual()
	if by != null and is_instance_valid(by) and by.has_method("gain_xp"):
		var g: Array = info.gold
		by.gain_xp(int(info.xp), randi_range(int(g[0]), int(g[1])), display_name)


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
