class_name Actor
extends CharacterBody2D
## Base de jogador e NPCs: corpo físico + equipamento + visual em camadas.
## Movimento em 8 direções com velocidade uniforme no chão isométrico.

@export var walk_speed := 120.0
@export var run_speed := 210.0

var body_colors: Dictionary = {}
var start_items: Array = []
var equipment: EquipmentComponent
var visual: CharacterVisual
var facing := "S"
var anim := "idle"
var _action_time := 0.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	equipment = EquipmentComponent.new()
	equipment.name = "Equipment"
	add_child(equipment)
	for id in start_items:
		var it := ItemDB.get_item(id)
		if it:
			equipment.equip(it)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 11.0
	col.shape = shape
	add_child(col)
	visual = CharacterVisual.new()
	visual.name = "Visual"
	visual.body_colors = body_colors
	add_child(visual)
	visual.setup(equipment)


## d = direção desejada na tela (não precisa ser normalizada).
func move(d: Vector2, running: bool, delta: float) -> void:
	if d.length_squared() > 0.0001:
		velocity = Iso.ground_velocity(d, run_speed if running else walk_speed)
		facing = Iso.dir_from_vector(d)
		if _action_time <= 0.0:
			anim = "run" if running else "walk"
	else:
		velocity = Vector2.ZERO
		if _action_time <= 0.0:
			anim = "idle"
	move_and_slide()
	if _action_time > 0.0:
		_action_time -= delta
		if _action_time <= 0.0:
			anim = "idle"
	visual.tick(delta, facing, anim, velocity.length())


func play_action(a: String, duration: float) -> void:
	anim = a
	_action_time = duration
