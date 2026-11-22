class_name PostFx
extends CanvasLayer
## Pós-processamento do mundo (fica entre o mundo e a interface) + poeira flutuando no ar.

var _rect: ColorRect
var _mat: ShaderMaterial
var _dust: CPUParticles2D
var player: Node2D
var map: WorldMap
var _fog := 0.1
var _fog_goal := 0.1
var _fog_c := Vector3(0.42, 0.44, 0.48)
var _fog_cg := Vector3(0.42, 0.44, 0.48)
var _fog_t := 0.0


func _ready() -> void:
	layer = 1
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_rect.material = _mat
	add_child(_rect)
	add_to_group("qualidade")
	on_quality(Settings.level_now)


## Níveis 1-2: sem pós-processamento nem poeira (economiza uma cópia da tela inteira por quadro).
## 3: versão leve (cor, vinheta e neblina). 4+ no PC: completa (brilho e granulação).
func on_quality(lv: int) -> void:
	_rect.visible = lv >= 3
	var full := lv >= 4 and not Settings.is_mobile()
	var sh: Shader = load("res://shaders/post.gdshader" if full else "res://shaders/post_leve.gdshader")
	if _mat.shader != sh:
		_mat.shader = sh
	if _dust:
		_dust.visible = lv >= 3
		_dust.emitting = lv >= 3


## Poeira e brasinhas no ar, sempre em volta da câmera (fica no mundo, não na tela).
func setup_dust(world: Node2D) -> void:
	_dust = CPUParticles2D.new()
	_dust.amount = 40 if not Settings.is_mobile() else 16
	_dust.lifetime = 9.0
	_dust.preprocess = 9.0
	_dust.local_coords = false
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(700, 400)
	_dust.direction = Vector2(1, -0.3)
	_dust.spread = 40.0
	_dust.initial_velocity_min = 4.0
	_dust.initial_velocity_max = 14.0
	_dust.gravity = Vector2(3, -2)
	_dust.scale_amount_min = 0.012
	_dust.scale_amount_max = 0.03
	_dust.texture = LightKit.radial()
	_dust.material = SpellFx._add_mat()
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.85, 0.6, 0.0))
	g.add_point(0.3, Color(1, 0.85, 0.6, 0.35))
	g.add_point(0.7, Color(1, 0.8, 0.55, 0.3))
	g.set_color(g.get_point_count() - 1, Color(1, 0.8, 0.5, 0.0))
	_dust.color_ramp = g
	_dust.z_index = 50
	world.add_child(_dust)
	on_quality(Settings.level_now)


## Neblina por região (Visual Factory etapa 8): olha o chão em volta do jogador.
## Cemitério = neblina densa esverdeada, floresta/selva = úmida, campo aberto = leve; à noite engrossa.
func _sample_fog() -> void:
	if map == null or not is_instance_valid(player):
		return
	var g := Iso.to_grid(player.global_position)
	var cem := 0
	var mata := 0
	var tot := 0
	for dy in range(-4, 5, 2):
		for dx in range(-4, 5, 2):
			var ch := map.at(int(g.x) + dx, int(g.y) + dy)
			tot += 1
			if ch == "g":
				cem += 1
			elif ch == "f" or ch == "j":
				mata += 1
	var fc := float(cem) / tot
	var fm := float(mata) / tot
	_fog_goal = 0.07 + fc * 0.24 + fm * 0.1 + (0.06 if DayNight.is_night_now() else 0.0)
	var base := Vector3(0.42, 0.44, 0.48)
	_fog_cg = base.lerp(Vector3(0.38, 0.45, 0.4), fc).lerp(Vector3(0.36, 0.42, 0.36), fm * 0.6)


func _process(d: float) -> void:
	if not _rect.visible:
		return
	var full := Settings.level_now >= 4 and not Settings.is_mobile()
	_mat.set_shader_parameter("full", 1.0 if full else 0.0)
	_mat.set_shader_parameter("fog_on", 1.0 if Settings.level_now >= 3 else 0.0)
	_fog_t -= d
	if _fog_t <= 0.0:
		_fog_t = 0.5
		_sample_fog()
	_fog = lerpf(_fog, _fog_goal, minf(1.0, d * 0.6))
	_fog_c = _fog_c.lerp(_fog_cg, minf(1.0, d * 0.6))
	_mat.set_shader_parameter("fog_amount", _fog)
	_mat.set_shader_parameter("fog_col", _fog_c)
	var ct := get_viewport().get_canvas_transform()
	_mat.set_shader_parameter("cam", -ct.origin / ct.get_scale())
	if _dust and is_instance_valid(player):
		_dust.global_position = player.global_position + Vector2(0, -60)
