shader_type canvas_item;
// Chão da ilha: mistura texturas reais (ambientCG, CC0) conforme o mapa em texto.
// w0 = grama, terra, areia, calçamento | w1 = floresta, rocha, água, terra amaldiçoada (cemitério)

uniform vec2 map_size = vec2(56.0, 56.0);
uniform sampler2D w0 : filter_linear, repeat_disable;
uniform sampler2D w1 : filter_linear, repeat_disable;
// Poucas unidades de textura (celulares e muitas placas só têm 16 no total):
// cores/normais = [grama_a, terra, areia, calçamento, floresta_a, rocha, grama_b, floresta_b, cemitério] (ambientCG CC0)
uniform sampler2DArray cores : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normais : filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.3;
// qualidade (Perf): 0 = leve (sem anti-repetição nem relevo), 1 = média (sem relevo), 2 = completa
uniform int q = 2;

varying vec2 grid;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
vec3 at(float L, vec2 uv, float m) {
	vec3 c = texture(cores, vec3(uv, L)).rgb;
	if (m < 0.01) return c;
	return mix(c, texture(cores, vec3(ROT * uv * 0.71 + vec2(0.37, 0.11), L)).rgb, m);
}
vec3 atn(float L, vec2 uv, float m) {
	vec3 c = texture(normais, vec3(uv, L)).rgb;
	if (m < 0.01) return c;
	return mix(c, texture(normais, vec3(ROT * uv * 0.71 + vec2(0.37, 0.11), L)).rgb, m);
}

void vertex() {
	grid = vec2(VERTEX.x / 64.0 + VERTEX.y / 32.0, VERTEX.y / 32.0 - VERTEX.x / 64.0) * 0.5;
}

void fragment() {
	vec2 g = grid;
	vec2 jit = q > 0 ? vec2(vnoise(g * 1.3), vnoise(g * 1.3 + 17.3)) - 0.5 : vec2(0.0);
	vec2 wuv = (g + jit * 0.7) / map_size;
	float n = q > 0 ? vnoise(g * 2.7) * 0.6 + vnoise(g * 8.0) * 0.4 : vnoise(g * 2.7);
	vec4 a = pow(texture(w0, wuv) * (0.7 + n * 0.6), vec4(3.0));
	vec4 b = pow(texture(w1, wuv) * (0.7 + n * 0.6), vec4(3.0));
	float sum = a.r + a.g + a.b + a.a + b.r + b.g + b.b + b.a + 0.0001;
	a /= sum;
	b /= sum;

	vec2 uv = g * tex_scale;
	// contra repetição: cada camada mistura a textura com ela mesma girada e em outra escala,
	// por manchas grandes de ruído; grama e floresta ainda alternam entre duas texturas
	float m = q > 0 ? smoothstep(0.3, 0.7, vnoise(g * 0.31 + 5.1)) : 0.0;
	bool rel = q > 1;
	float vg = smoothstep(0.35, 0.65, vnoise(g * 0.17 + 11.0));
	vec3 col = vec3(0.0);
	vec3 nm = vec3(0.0);
	if (a.r + b.r > 0.003) {
		float m2 = q > 0 ? 1.0 - m : 0.0;
		vec3 ga = mix(at(0.0, uv, m), at(6.0, uv, m2), vg);
		col += ga * a.r;
		if (rel) nm += mix(atn(0.0, uv, m), atn(6.0, uv, m2), vg) * (a.r);
		vec3 fo = q > 0 ? mix(at(4.0, uv, m), at(7.0, uv, m2), smoothstep(0.3, 0.7, vnoise(g * 0.23 + 3.0))) : at(4.0, uv, 0.0);
		col += fo * b.r;
		if (rel) nm += atn(4.0, uv, m) * b.r;
	}
	if (a.g > 0.003) { col += at(1.0, uv, m) * a.g; if (rel) nm += atn(1.0, uv, m) * a.g; }
	if (a.b > 0.003) { col += at(2.0, uv, m) * a.b; if (rel) nm += atn(2.0, uv, m) * a.b; }
	if (a.a > 0.003) { col += at(3.0, uv * 1.25, 0.0) * a.a; if (rel) nm += atn(3.0, uv * 1.25, 0.0) * a.a; }
	if (b.g > 0.003) { col += at(5.0, uv * 0.8, m) * b.g; if (rel) nm += atn(5.0, uv * 0.8, m) * b.g; }
	if (b.a > 0.003) { col += at(8.0, uv, m) * b.a * 0.85; if (rel) nm += atn(8.0, uv, m) * b.a; }
	nm += vec3(0.5, 0.5, 1.0) * (rel ? b.b : 1.0);
	// sujeira e manchas grandes (quebra a uniformidade) e cor do dark fantasy (menos saturada)
	col *= 0.86 + 0.28 * vnoise(g * 0.6 + 2.0);
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(lum), col, 0.78);

	float t = TIME;
	vec3 water = mix(vec3(0.04, 0.11, 0.13), vec3(0.10, 0.22, 0.23), vnoise(g * 1.6 + vec2(t * 0.25, t * 0.15)));
	water += vec3(0.55, 0.62, 0.6) * smoothstep(0.78, 0.95, vnoise(g * 4.5 + vec2(-t * 0.5, t * 0.35))) * 0.22;
	col += water * b.b;
	// beira molhada da areia perto da água
	col *= 1.0 - 0.35 * smoothstep(0.05, 0.5, b.b) * (1.0 - b.b);

	COLOR = vec4(col, 1.0);
	NORMAL_MAP = nm;
}
