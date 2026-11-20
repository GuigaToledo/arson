class_name Player
extends Actor
## Jogador: teclado (WASD/setas), clique ou toque para andar, Shift corre, 1 conjura.

var target = null
var run_toggle := false
var camera: Camera2D


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
	camera.zoom = Vector2(1.0, 1.0)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.offset = Vector2(0, -40)
	add_child(camera)
	camera.make_current()


func _unhandled_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		target = get_global_mouse_position()
	var mm := ev as InputEventMouseMotion
	if mm and mm.button_mask & MOUSE_BUTTON_MASK_LEFT and target != null:
		target = get_global_mouse_position()
	var k := ev as InputEventKey
	if get_viewport().gui_get_focus_owner() == null and k and k.pressed and not k.echo and k.physical_keycode == KEY_1:
		play_action("cast", 0.7)


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
