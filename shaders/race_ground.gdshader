shader_type spatial;
render_mode cull_disabled;
// BNB Rush Hour ground: two tones broken up by world-space noise, so big flat planes don't look like plastic.
// Used for grass, sand, snow, pavement and the verges beside the road.

uniform vec4 col_a : source_color = vec4(0.3, 0.5, 0.25, 1.0);
uniform vec4 col_b : source_color = vec4(0.22, 0.4, 0.2, 1.0);
uniform float scale = 0.08;
uniform float rough = 0.95;
uniform float sparkle = 0.0;   // snow / sand glints

varying vec3 wpos;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz * scale;
	float n = noise(p) * 0.6 + noise(p * 3.1) * 0.3 + noise(p * 9.7) * 0.1;
	vec3 c = mix(col_a.rgb, col_b.rgb, smoothstep(0.3, 0.7, n));
	c *= 0.94 + h21(floor(wpos.xz * 6.0)) * 0.08;
	ALBEDO = c;
	ROUGHNESS = rough;
	if (sparkle > 0.0) {
		float g = step(0.996, h21(floor(wpos.xz * 14.0)));
		EMISSION = vec3(g * sparkle);
	}
}
