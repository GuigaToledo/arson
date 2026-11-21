class_name Player
extends Actor
## Jogador: clique/toque para andar (segurar = seguir o dedo), botão direito ou 1 = magia,
## WASD/setas também andam, Shift corre.

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


## Magia: gasta mana; vira para a direção indicada (posição no mundo).
func cast_at(world_pos = null) -> void:
	if mp < CAST_COST or _action_time > 0.0:
		return
	mp -= CAST_COST
	var d := Iso.dir_vector(facing)
	if world_pos != null and (world_pos - global_position).length() > 4.0:
		d = (world_pos - global_position).normalized()
		facing = Iso.dir_from_vector(d)
	play_action("cast", 0.5)
	var fb := Fireball.new()
	fb.dir = d
	fb.global_position = global_position + Iso.ground_velocity(d, 1.0) * 18.0
	get_parent().add_child(fb)


func _process(delta: float) -> void:
	mp = minf(max_mp, mp + delta * 4.0)
	hp = minf(max_hp, hp + delta * 1.0)


func _unhandled_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		target = get_global_mouse_position()
		marker.show_at(target)
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		cast_at(get_global_mouse_position())
	var mm := ev as InputEventMouseMotion
	if mm and mm.button_mask & MOUSE_BUTTON_MASK_LEFT and target != null:
		target = get_global_mouse_position()
	var k := ev as InputEventKey
	if get_viewport().gui_get_focus_owner() == null and k and k.pressed and not k.echo and k.physical_keycode == KEY_1:
		cast_at()


func _physics_process(delta: float) -> void:
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
