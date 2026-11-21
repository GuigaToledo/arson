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
	level = Rules.level_for(xp)
	_recalc()
	hp = max_hp
	mp = max_mp


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("jogador", "xp", xp)
	c.set_value("jogador", "ouro", gold)
	c.set_value("jogador", "nivel", level)
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
	hp -= n
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


## Bola de fogo: gasta mana; vai no alvo se houver, senão na direção indicada (posição no mundo).
func cast_at(world_pos = null) -> void:
	if dead or mp < CAST_COST or _action_time > 0.0:
		return
	mp -= CAST_COST
	var d := Iso.dir_vector(facing)
	if world_pos == null and _alive_foe():
		world_pos = foe.global_position
	if world_pos != null and (world_pos - global_position).length() > 4.0:
		d = (world_pos - global_position).normalized()
		facing = Iso.dir_from_vector(d)
	play_action("cast", 0.5)
	var fb := Fireball.new()
	fb.dir = d
	fb.power = 28.0 + 4.0 * level
	fb.caster = self
	fb.global_position = global_position + Iso.ground_velocity(d, 1.0) * 18.0
	get_parent().add_child(fb)


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
			tgt.take_damage(Rules.roll(9.0 + 1.3 * level, float(tgt.info.def)), self)
	get_parent().add_child(b)


func _process(delta: float) -> void:
	if dead:
		return
	mp = minf(max_mp, mp + delta * 4.0)
	hp = minf(max_hp, hp + delta * (3.0 if Rules.is_safe(global_position) else 1.0))
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
		if k.physical_keycode == KEY_1:
			cast_at()
		elif k.physical_keycode == KEY_SPACE:
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
