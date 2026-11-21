class_name CharacterVisual
extends Node2D
## Monta o personagem em camadas (corpo + um nó por slot), mantém todas
## sincronizadas na mesma direção/animação/quadro e reordena as camadas
## conforme a direção (capa atrás ou na frente, escudo do lado certo...).

const FPS := 10.0
## Camada extra desenhada na frente (capuz/manto da capa).
const CAPE_FRONT := 100
const S := EquipSlot.Slot
const BASE_DEPTH := {
	-1: 0.0,
	EquipSlot.Slot.LEGS: 0.1,
	EquipSlot.Slot.FEET: 0.15,
	EquipSlot.Slot.CHEST: 0.2,
	EquipSlot.Slot.HANDS: 0.3,
	EquipSlot.Slot.SHOULDERS: 0.4,
	EquipSlot.Slot.ACCESSORIES: 0.45,
	EquipSlot.Slot.HEAD: 0.5,
}

var body_colors: Dictionary = {}
## Corpo renderizado (EquipmentItem com SpriteFrames). Nulo = arte provisória.
var body_item: EquipmentItem
var equipment: EquipmentComponent
var layers: Dictionary = {}
var dir := "S"
var anim := "idle"
var _phase := 0.0
var _time := 0.0
var _frame := 0
var _frame_acc := 0.0
var _order_key := ""
## Segundos desde o começo da animação atual (golpes e magias usam para o movimento).
var _anim_t := 0.0
## Área do mundo na tela (o jogador atualiza): quem está fora não é desenhado nem animado.
static var view_rect := Rect2()
var _draw_acc := 1.0
var _eye_light: PointLight2D
var _core_light: PointLight2D


func setup(eq: EquipmentComponent) -> void:
	equipment = eq
	for s in [-1] + EquipSlot.all() + [CAPE_FRONT]:
		var l := EquipLayer.new()
		l.slot = s
		l.body_colors = body_colors
		l.name = "Corpo" if s == -1 else ("CapaFrente" if s == CAPE_FRONT else EquipSlot.slot_name(s))
		add_child(l)
		layers[s] = l
		if s == CAPE_FRONT:
			l.set_item(eq.get_item(S.CAPE))
		elif s != -1:
			l.set_item(eq.get_item(s))
		else:
			l.set_item(body_item)
	eq.equipment_changed.connect(_on_equipment_changed)
	if body_colors.get("core", false) and body_item == null:
		_core_light = LightKit.make(body_colors.get("core_col", Color(1, 0.45, 0.1)), 0.6, 0.2, false, 0.2)
		add_child(_core_light)
	if body_colors.get("glow_eyes", false) and body_item == null:
		_eye_light = LightKit.make(body_colors.get("eyes", Color(1, 0.55, 0.15)), 0.45, 0.08, false, 0.1)
		add_child(_eye_light)
	_reorder(true)


## Troca a cor do núcleo e dos olhos (skin da classe).
func set_glow(core_col: Color, eye_col: Color) -> void:
	body_colors["core_col"] = core_col
	body_colors["eyes"] = eye_col
	if _core_light:
		_core_light.color = core_col
	if _eye_light:
		_eye_light.color = eye_col
	for l in layers.values():
		l.queue_redraw()


func _on_equipment_changed(slot: int, item: EquipmentItem) -> void:
	layers[slot].set_item(item)
	if slot == S.CAPE:
		layers[CAPE_FRONT].set_item(item)


func tick(delta: float, new_dir: String, new_anim: String, speed: float) -> void:
	_time += delta
	if new_anim != anim:
		_frame = 0
		_anim_t = 0.0
	_anim_t += delta
	dir = new_dir
	anim = new_anim
	if anim == "walk" or anim == "run":
		_phase += delta * speed * 0.085
	else:
		_phase = lerpf(_phase, roundf(_phase / PI) * PI, delta * 8.0)
	_frame_acc += delta * FPS
	while _frame_acc >= 1.0:
		_frame_acc -= 1.0
		_frame += 1
	# otimização: fora da tela não desenha; na tela, atualiza o desenho no máximo 30x por segundo
	if view_rect.size.x > 0.0 and not view_rect.has_point(global_position):
		visible = false
		_draw_acc = 1.0
		return
	visible = true
	_draw_acc += delta
	if _draw_acc < 1.0 / 30.0:
		return
	_draw_acc = 0.0
	var pose := PlaceholderPainter.pose(dir, anim, _phase, _time, _anim_t)
	for l: EquipLayer in layers.values():
		l.update_pose(dir, anim, _frame, pose)
	if _eye_light:
		_eye_light.visible = pose.toward
		_eye_light.position = pose.head + Vector2(0, 0.5)
	if _core_light:
		_core_light.visible = pose.toward
		_core_light.position = Vector2(0, -51)
	_reorder(false)


## Profundidade de cada camada para a direção atual (menor = desenhado antes).
func _depth(slot: int, f: Vector2) -> float:
	var r := Vector2(-f.y, f.x)
	if slot == S.CAPE:
		return -1.0 - f.y * 5.0
	if slot == CAPE_FRONT:
		return 0.6
	# mão direita = lado r; esquerda = lado -r. O item fica na frente do corpo quando o lado dele
	# está virado para a câmera, e atrás quando o personagem está de costas (o item fica do outro lado).
	if slot == S.MAIN_HAND:
		return 1.0 if r.y * 0.8 + f.y * 0.6 >= -0.1 else -2.0
	if slot == S.OFF_HAND:
		return 1.1 if -r.y * 0.8 + f.y * 0.6 >= -0.1 else -2.1
	return BASE_DEPTH.get(slot, 0.0)


func _reorder(force: bool) -> void:
	if not force and _order_key == dir:
		return
	_order_key = dir
	var f := Iso.dir_vector(dir)
	var keys: Array = layers.keys()
	keys.sort_custom(func(a, b): return _depth(a, f) < _depth(b, f))
	for i in keys.size():
		move_child(layers[keys[i]], i)
