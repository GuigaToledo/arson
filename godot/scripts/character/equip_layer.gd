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
## Item vestido num corpo renderizado: camada 3D do estilo do item (parte principal pintada com a
## cor do item e detalhe com a cor de destaque), tocando o mesmo quadro do corpo.
var _lay: EquipmentItem
var _lay_spr: AnimatedSprite2D
var _lay_ac: EquipmentItem
var _lay_ac_spr: AnimatedSprite2D


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
	for sp in [_lay_spr, _lay_ac_spr]:
		if sp:
			sp.queue_free()
	_lay_spr = null
	_lay_ac_spr = null
	_lay = null
	_lay_ac = null
	if item and item.sprite_frames and slot != CharacterVisual.CAPE_FRONT:
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = item.sprite_frames
		_sprite.centered = true
		_sprite.offset = item.anchor
		_sprite.scale = Vector2.ONE * item.sprite_scale
		add_child(_sprite)
	if slot == -1 and item and item.sprite_frames:
		body_colors["sprite_body"] = true
	if slot >= 0 and slot != CharacterVisual.CAPE_FRONT and item and body_colors.get("sprite_body", false):
		var lp := "res://assets/equip/%s/sprites.json" % String(item.placeholder_style)
		if FileAccess.file_exists(lp):
			_lay = Actor.sprite_body(lp)
			_lay_ac = Actor.sprite_body(lp, "_ac")
			_lay_spr = _layer_sprite(_lay, _tint(item.placeholder_color, 0.8))
			_lay_ac_spr = _layer_sprite(_lay_ac, _tint(item.placeholder_accent, 0.85))
	if item and item.glow > 0.0 and slot != CharacterVisual.CAPE_FRONT:
		_light = LightKit.make(item.placeholder_accent, item.glow, 0.35, false, 0.15)
		add_child(_light)
	visible = slot == -1 or item != null
	queue_redraw()


func _tint(c: Color, ref: float) -> Color:
	return Color(c.r / ref, c.g / ref, c.b / ref, 1.0)


func _layer_sprite(it: EquipmentItem, col: Color) -> AnimatedSprite2D:
	if it == null:
		return null
	var sp := AnimatedSprite2D.new()
	sp.sprite_frames = it.sprite_frames
	sp.centered = true
	sp.offset = it.anchor
	sp.scale = Vector2.ONE * it.sprite_scale
	sp.modulate = col
	add_child(sp)
	return sp


func _play(sp: AnimatedSprite2D, it: EquipmentItem, anim: String, dir: String, frame: int) -> void:
	if sp == null or it == null:
		return
	var r := it.resolve(anim, dir)
	var nm: String = r.name
	if nm != "" and sp.sprite_frames.has_animation(nm):
		sp.visible = true
		if sp.animation != nm:
			sp.animation = nm
		sp.flip_h = r.flip
		sp.frame = frame % maxi(1, sp.sprite_frames.get_frame_count(nm))
	else:
		sp.visible = false


func update_pose(dir: String, anim: String, frame: int, pose: Dictionary) -> void:
	_pose = pose
	_play(_lay_spr, _lay, anim, dir, frame)
	_play(_lay_ac_spr, _lay_ac, anim, dir, frame)
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
	if _sprite and slot == -1:
		# corpo renderizado: sombra no chão (o desenho por código fazia a dele)
		var sb: Vector2 = item.get_meta("sombra", Vector2(16, 6.5)) if item else Vector2(16, 6.5)
		PlaceholderPainter.ellipse(self, Vector2(2, 0), sb.x, sb.y, Color(0, 0, 0, 0.45))
		return
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
