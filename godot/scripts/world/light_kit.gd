class_name LightKit
extends RefCounted
## Fábrica de luzes 2D (textura radial compartilhada).

static var _tex: Texture2D


static func radial() -> Texture2D:
	if _tex == null:
		var g := Gradient.new()
		# borda preta e transparente: luz e partículas somem fora do círculo
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(0.35, Color(0.55, 0.55, 0.55, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 256
		t.height = 256
		_tex = t
	return _tex


static func make(color: Color, energy: float, scale: float, shadows := false, flicker := 0.0) -> PointLight2D:
	var l := FlickerLight.new()
	l.texture = radial()
	l.color = color
	l.energy = energy
	l.base_energy = energy
	l.flicker = flicker
	l.texture_scale = scale
	l.height = 40.0
	l.shadow_enabled = shadows
	if shadows:
		l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		l.shadow_filter_smooth = 3.0
		l.shadow_color = Color(0, 0, 0, 0.75)
	return l
