class_name PostFx
extends CanvasLayer
## Pós-processamento do mundo (fica entre o mundo e a interface) + poeira flutuando no ar.

var _rect: ColorRect
var _mat: ShaderMaterial
var _dust: CPUParticles2D
var player: Node2D


func _ready() -> void:
	layer = 1
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/post.gdshader")
	_rect.material = _mat
	add_child(_rect)


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


func _process(_d: float) -> void:
	var full := Settings.level_now >= 4 and not Settings.is_mobile()
	_mat.set_shader_parameter("full", 1.0 if full else 0.0)
	var ct := get_viewport().get_canvas_transform()
	_mat.set_shader_parameter("cam", -ct.origin / ct.get_scale())
	if _dust and is_instance_valid(player):
		_dust.global_position = player.global_position + Vector2(0, -60)
