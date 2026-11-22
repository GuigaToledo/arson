shader_type canvas_item;
// Pós-processamento do mundo (antes da interface): cor de cinema no tom das referências
// (sombras frias, luz quente, dessaturado), brilho (bloom) nas luzes, neblina baixa se movendo,
// vinheta e granulação fina. "full" = 0 no celular / níveis baixos (só cor e vinheta).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 cam = vec2(0.0);
uniform float full = 1.0;
uniform float fog_amount = 0.10;
uniform float fog_on = 1.0;
uniform vec3 fog_col = vec3(0.42, 0.44, 0.48);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	if (full > 0.5) {
		// brilho: média borrada das áreas claras ao redor
		vec2 px = SCREEN_PIXEL_SIZE * 6.0;
		vec3 b = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785;
			vec2 o = vec2(cos(a), sin(a));
			vec3 s1 = textureLod(screen_tex, uv + o * px, 2.0).rgb;
			vec3 s2 = textureLod(screen_tex, uv + o * px * 2.5, 3.0).rgb;
			b += max(s1 - 0.55, 0.0) + max(s2 - 0.55, 0.0) * 0.8;
		}
		c += b * 0.16;
	}
	if (fog_on > 0.5) {
		// neblina baixa, presa ao mundo (anda com a câmera) e se movendo devagar
		vec2 wp = (uv / SCREEN_PIXEL_SIZE + cam) * 0.0025;
		float n = vnoise(wp + vec2(TIME * 0.02, TIME * 0.008)) * 0.6 + vnoise(wp * 2.3 - vec2(TIME * 0.03, 0.0)) * 0.4;
		c = mix(c, fog_col, n * fog_amount);
	}
	// cor: contraste, um pouco menos saturado, sombras azuladas e luzes quentes
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 0.86);
	c = (c - 0.5) * 1.12 + 0.5;
	c += vec3(-0.012, 0.0, 0.025) * (1.0 - smoothstep(0.0, 0.35, l));
	c += vec3(0.035, 0.015, -0.02) * smoothstep(0.45, 0.9, l);
	// vinheta
	vec2 d = uv - 0.5;
	c *= 1.0 - dot(d, d) * 0.9;
	// granulação fina
	if (full > 0.5) {
		c += (hash(uv * 1000.0 + TIME) - 0.5) * 0.025;
	}
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
