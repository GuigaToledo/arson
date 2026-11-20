class_name Iso
extends RefCounted
## Conversões da grade isométrica (losango 128x64) e das 8 direções.

const TW := 128.0
const TH := 64.0
const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]


static func to_screen(g: Vector2) -> Vector2:
	return Vector2((g.x - g.y) * TW * 0.5, (g.x + g.y) * TH * 0.5)


static func to_grid(p: Vector2) -> Vector2:
	return Vector2(p.x / (TW * 0.5) + p.y / (TH * 0.5), p.y / (TH * 0.5) - p.x / (TW * 0.5)) * 0.5


## Direção da tela (S = em direção à câmera).
static func dir_from_vector(v: Vector2) -> String:
	var i := posmod(int(round(v.angle() / (PI / 4.0))), 8)
	return DIRS[i]


static func dir_vector(d: String) -> Vector2:
	return Vector2.RIGHT.rotated(DIRS.find(d) * PI / 4.0)


## Velocidade na tela para andar com velocidade constante no chão isométrico.
static func ground_velocity(d: Vector2, speed: float) -> Vector2:
	if d.length_squared() < 0.0001:
		return Vector2.ZERO
	d = d.normalized()
	return d * speed / sqrt(d.x * d.x + 4.0 * d.y * d.y)
