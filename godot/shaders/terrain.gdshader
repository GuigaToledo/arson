shader_type canvas_item;
// Chão da ilha: mistura texturas reais (ambientCG, CC0) conforme o mapa em texto.
// w0 = grama, terra, areia, calçamento | w1 = floresta, rocha, água, -

uniform vec2 map_size = vec2(56.0, 56.0);
uniform sampler2D w0 : filter_linear, repeat_disable;
uniform sampler2D w1 : filter_linear, repeat_disable;
// Poucas unidades de textura (celulares e muitas placas só têm 16 no total):
// cores = [grama, caminho, areia, pedra, floresta, rocha]; normais = [grama, caminho, pedra]
uniform sampler2DArray cores : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normais : filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.5;

varying vec2 grid;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	grid = vec2(VERTEX.x / 64.0 + VERTEX.y / 32.0, VERTEX.y / 32.0 - VERTEX.x / 64.0) * 0.5;
}

void fragment() {
	vec2 g = grid;
	vec2 jit = vec2(vnoise(g * 1.3), vnoise(g * 1.3 + 17.3)) - 0.5;
	vec2 wuv = (g + jit * 0.7) / map_size;
	float n = vnoise(g * 2.7) * 0.6 + vnoise(g * 8.0) * 0.4;
	vec4 a = pow(texture(w0, wuv) * (0.7 + n * 0.6), vec4(3.0));
	vec4 b = pow(texture(w1, wuv) * (0.7 + n * 0.6), vec4(3.0));
	float sum = a.r + a.g + a.b + a.a + b.r + b.g + b.b + 0.0001;
	a /= sum;
	b /= sum;

	vec2 uv = g * tex_scale;
	vec3 col = texture(cores, vec3(uv, 0.0)).rgb * a.r
		+ texture(cores, vec3(uv, 1.0)).rgb * a.g
		+ texture(cores, vec3(uv, 2.0)).rgb * a.b
		+ texture(cores, vec3(uv, 3.0)).rgb * a.a
		+ texture(cores, vec3(uv, 4.0)).rgb * b.r
		+ texture(cores, vec3(uv * 0.7, 5.0)).rgb * b.g;

	float t = TIME;
	vec3 water = mix(vec3(0.04, 0.11, 0.13), vec3(0.10, 0.22, 0.23), vnoise(g * 1.6 + vec2(t * 0.25, t * 0.15)));
	water += vec3(0.55, 0.62, 0.6) * smoothstep(0.78, 0.95, vnoise(g * 4.5 + vec2(-t * 0.5, t * 0.35))) * 0.22;
	col += water * b.b;
	// beira molhada da areia perto da água
	col *= 1.0 - 0.35 * smoothstep(0.05, 0.5, b.b) * (1.0 - b.b);

	vec3 nm = texture(normais, vec3(uv, 0.0)).rgb * (a.r + b.r)
		+ texture(normais, vec3(uv, 1.0)).rgb * (a.g + a.b)
		+ texture(normais, vec3(uv, 2.0)).rgb * (a.a + b.g)
		+ vec3(0.5, 0.5, 1.0) * b.b;
	COLOR = vec4(col, 1.0);
	NORMAL_MAP = nm;
}
