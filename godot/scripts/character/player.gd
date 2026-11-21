class_name Player
extends Actor
## Jogador: clique/toque para andar (segurar = seguir o dedo), botão direito ou 1 = magia,
## WASD/setas também andam, Shift corre.

var target = null
var run_toggle := false
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


## Magia: gasta mana; vira para a direção indicada (posição no mundo).
func cast_at(world_pos = null) -> void:
	if mp < CAST_COST or _action_time > 0.0:
		return
	mp -= CAST_COST
	if world_pos != null:
		facing = Iso.dir_from_vector(world_pos - global_position)
	play_action("cast", 0.6)


func _process(delta: float) -> void:
	mp = minf(max_mp, mp + delta * 4.0)
	hp = minf(max_hp, hp + delta * 1.0)


func _unhandled_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		target = get_global_mouse_position()
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
