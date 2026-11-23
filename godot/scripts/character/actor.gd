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
	if body_path.ends_with(".json"):
		visual.body_item = sprite_body(body_path)
	elif body_path != "" and ResourceLoader.exists(body_path):
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


## Corpo em sprites renderizados em 3D (ferramentas/sprites3d): folhas por animação (uma linha por
## direção) + sprites.json (tamanho do quadro, ponto do pé). Monta as animações "<anim>_<direção>".
static var _bodies := {}
const SPRITE_DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
## Animações do jogo que usam outra animação renderizada.
const SPRITE_ALIAS := {"spell": "cast", "attack": "cast", "punch": "cast", "kick": "cast", "headbutt": "cast", "grab": "cast", "spin": "cast"}


static func sprite_body(json_path: String) -> EquipmentItem:
	if _bodies.has(json_path):
		return _bodies[json_path]
	var txt := FileAccess.get_file_as_string(json_path)
	var d = JSON.parse_string(txt) if txt != "" else null
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var dir := json_path.get_base_dir()
	# celular: folhas em meia resolução (um quarto da memória de vídeo)
	var half: bool = Settings.is_mobile()
	var k_res := 0.5 if half else 1.0
	# quadro virtual comum (256x256, pé em 128,200.5): cada animação tem o seu recorte, a margem
	# da AtlasTexture coloca o recorte no lugar certo, e todas as animações ficam com o pé no mesmo ponto
	const VW := 256.0
	const VH := 256.0
	const PX := 128.0
	const PY := 200.5
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var anims := PackedStringArray()
	for anim in d.anims:
		var info: Dictionary = d.anims[anim]
		var n := int(info.n)
		var fw := float(info.quadro[0])
		var fh := float(info.quadro[1])
		var tex: Texture2D = load(dir + "/" + anim + ".png")
		if tex == null:
			continue
		if half:
			var img := tex.get_image()
			if img.is_compressed():
				img.decompress()
			img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(img)
		var off := Vector2(PX - float(info.pe[0]), PY - float(info.pe[1]))
		for di in SPRITE_DIRS.size():
			var nm := "%s_%s" % [anim, SPRITE_DIRS[di]]
			sf.add_animation(nm)
			sf.set_animation_loop(nm, anim != "death")
			for q in n:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(q * fw * k_res, di * fh * k_res, fw * k_res, fh * k_res)
				at.margin = Rect2(off.x * k_res, off.y * k_res, (VW - fw) * k_res, (VH - fh) * k_res)
				sf.add_frame(nm, at)
		anims.append(anim)
	for a in SPRITE_ALIAS:
		var src: String = SPRITE_ALIAS[a]
		if anims.has(src) and not anims.has(a):
			for dd in SPRITE_DIRS:
				var nm2 := "%s_%s" % [a, dd]
				sf.add_animation(nm2)
				for k in sf.get_frame_count("%s_%s" % [src, dd]):
					sf.add_frame(nm2, sf.get_frame_texture("%s_%s" % [src, dd], k))
			anims.append(a)
	var it := EquipmentItem.new()
	it.id = &"corpo_sprite"
	it.sprite_frames = sf
	it.directions = PackedStringArray(SPRITE_DIRS)
	it.animations = anims
	it.sprite_scale = float(d.get("escala", 0.47)) / k_res
	# o sprite é centralizado no quadro virtual: desloca para o pé ficar na origem do personagem
	it.anchor = Vector2(VW * 0.5 - PX, VH * 0.5 - PY) * k_res
	_bodies[json_path] = it
	return it
