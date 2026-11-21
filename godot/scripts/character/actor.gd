class_name Actor
extends CharacterBody2D
## Base de jogador e NPCs: corpo físico + equipamento + visual em camadas.
## Movimento em 8 direções com velocidade uniforme no chão isométrico.

@export var walk_speed := 120.0
@export var run_speed := 210.0

## Se definido, diz se uma posição (tela) é caminhável. O mapa da ilha define isto.
static var walkable: Callable = Callable()

var display_name := ""
var body_colors: Dictionary = {}
var start_items: Array = []
## Caminho de um corpo renderizado (assets/personagens/<nome>/corpo.tres), se existir.
var body_path := ""
var equipment: EquipmentComponent
var visual: CharacterVisual
var facing := "S"
var anim := "idle"
var _action_time := 0.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("actors")
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
	visual = _make_visual()
	visual.name = "Visual"
	visual.body_colors = body_colors
	if body_path != "" and ResourceLoader.exists(body_path):
		visual.body_item = load(body_path)
	add_child(visual)
	visual.setup(equipment)


## Corpo visual (criaturas trocam por outro desenho).
func _make_visual() -> CharacterVisual:
	return CharacterVisual.new()


## d = direção desejada na tela (não precisa ser normalizada).
func move(d: Vector2, running: bool, delta: float) -> void:
	if d.length_squared() > 0.0001:
		velocity = Iso.ground_velocity(d, run_speed if running else walk_speed)
		if walkable.is_valid() and not walkable.call(global_position + velocity * delta * 3.0):
			if walkable.call(global_position + Vector2(velocity.x, 0) * delta * 3.0):
				velocity.y = 0.0
			elif walkable.call(global_position + Vector2(0, velocity.y) * delta * 3.0):
				velocity.x = 0.0
			else:
				velocity = Vector2.ZERO
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
