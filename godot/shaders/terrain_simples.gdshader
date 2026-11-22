shader_type canvas_item;
// Chão de segurança (app Android depois de fechar sozinho): só cores por terreno, sem texturas.
uniform vec2 map_size = vec2(56.0, 56.0);
uniform sampler2D w0 : filter_linear, repeat_disable;
uniform sampler2D w1 : filter_linear, repeat_disable;
varying vec2 grid;

void vertex() {
	grid = vec2(VERTEX.x / 64.0 + VERTEX.y / 32.0, VERTEX.y / 32.0 - VERTEX.x / 64.0) * 0.5;
}

void fragment() {
	vec2 wuv = grid / map_size;
	vec4 a = texture(w0, wuv);
	vec4 b = texture(w1, wuv);
	float s = a.r + a.g + a.b + a.a + b.r + b.g + b.b + b.a + 0.0001;
	vec3 col = vec3(0.24, 0.3, 0.15) * a.r + vec3(0.33, 0.26, 0.18) * a.g + vec3(0.6, 0.53, 0.38) * a.b
		+ vec3(0.38, 0.36, 0.33) * a.a + vec3(0.16, 0.22, 0.12) * b.r + vec3(0.32, 0.31, 0.3) * b.g
		+ vec3(0.06, 0.15, 0.17) * b.b + vec3(0.2, 0.2, 0.17) * b.a;
	COLOR = vec4(col / s, 1.0);
}
