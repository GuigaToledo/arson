class_name EquipLayer
extends Node2D
## Uma camada visual do personagem (corpo-base ou um slot de equipamento).
## Com SpriteFrames no item, toca o sprite certo para direção/animação;
## sem SpriteFrames, usa a arte provisória.

var slot := -1  ## -1 = corpo-base
var item: EquipmentItem
var body_colors: Dictionary = {}
var _pose: Dictionary = {}
var _sprite: AnimatedSprite2D
var _light: PointLight2D


## Personagens ficam na máscara de luz 2: só as luzes grandes (aura do herói, lampiões, fogueira)
## os iluminam. As luzes pequenas (portas, cajados, efeitos) iluminam só o chão (mais leve).
func _enter_tree() -> void:
	light_mask = 2


func set_item(it: EquipmentItem) -> void:
	item = it
	if _sprite:
		_sprite.queue_free()
		_sprite = null
	if _light:
		_light.queue_free()
		_light = null
	if item and item.sprite_frames and slot != CharacterVisual.CAPE_FRONT:
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = item.sprite_frames
		_sprite.centered = true
		_sprite.offset = item.anchor
		_sprite.scale = Vector2.ONE * item.sprite_scale
		add_child(_sprite)
	if slot == -1 and item and item.sprite_frames:
		body_colors["sprite_body"] = true
	if item and item.glow > 0.0 and slot != CharacterVisual.CAPE_FRONT:
		_light = LightKit.make(item.placeholder_accent, item.glow, 0.35, false, 0.15)
		add_child(_light)
	visible = slot == -1 or item != null
	queue_redraw()


func update_pose(dir: String, anim: String, frame: int, pose: Dictionary) -> void:
	_pose = pose
	if _sprite:
		var r := item.resolve(anim, dir)
		var anim_name: String = r.name
		if anim_name != "" and _sprite.sprite_frames.has_animation(anim_name):
			_sprite.visible = true
			if _sprite.animation != anim_name:
				_sprite.animation = anim_name
			_sprite.flip_h = r.flip
			_sprite.frame = frame % maxi(1, _sprite.sprite_frames.get_frame_count(anim_name))
		else:
			_sprite.visible = false
		position = item.dir_offsets.get(dir, Vector2.ZERO)
	else:
		queue_redraw()
	if _light:
		_light.position = PlaceholderPainter.glow_point(item, pose)
		_light.energy = item.glow * (1.8 if pose.get("casting", false) and slot == EquipSlot.Slot.MAIN_HAND else 1.0)
		_light.base_energy = _light.energy


func _draw() -> void:
	var t0 := Prof.t()
	_draw_inner()
	Prof.add("desenho_personagens", t0)


func _draw_inner() -> void:
	if _sprite or _pose.is_empty():
		return
	if slot == -1:
		PlaceholderPainter.draw_body(self, _pose, body_colors)
	elif item and not body_colors.get("sprite_body", false):
		if slot == CharacterVisual.CAPE_FRONT:
			if item.placeholder_style == &"wolfcape":
				PlaceholderPainter.draw_wolfcape_front(self, _pose, item)
		else:
			PlaceholderPainter.draw_item(self, _pose, item)
