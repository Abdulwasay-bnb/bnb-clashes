shader_type spatial;
// BNB Rush Hour road: asphalt with grain, repair patches and tyre marks, white edge lines and dashed lane lines.
// UV.x runs across the road (0..1), UV.y along it (in 6 m units).

uniform vec3 tint = vec3(0.16, 0.16, 0.18);
uniform float wet = 0.0;      // night city: a slick, slightly reflective road
uniform float dust = 0.0;     // desert sand / snow blown over the edges
uniform vec3 dust_col = vec3(0.8, 0.7, 0.5);

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec3 asphalt = tint + (h21(floor(UV * vec2(80.0, 40.0))) - 0.5) * 0.035;
	// patches of newer / older asphalt
	float patch = noise(vec2(UV.x * 3.0, UV.y * 0.7));
	asphalt *= 0.9 + patch * 0.2;
	// tyre marks: two darker bands in each lane, fading in and out along the road
	float lane = fract(UV.x * 3.0);
	float marks = (smoothstep(0.08, 0.0, abs(lane - 0.3)) + smoothstep(0.08, 0.0, abs(lane - 0.7))) * noise(vec2(UV.x * 9.0, UV.y * 0.35));
	asphalt *= 1.0 - marks * 0.35;
	float edge = step(UV.x, 0.035) + step(0.965, UV.x);
	float dash = step(0.5, fract(UV.y * 0.5));
	float lanes = (step(abs(UV.x - 0.333), 0.006) + step(abs(UV.x - 0.667), 0.006)) * dash;
	vec3 c = mix(asphalt, vec3(0.9), clamp(edge + lanes, 0.0, 1.0) * (0.85 + 0.15 * noise(UV * vec2(40.0, 4.0))));
	// sand or snow drifting in from the edges
	float drift = smoothstep(0.12, 0.0, min(UV.x, 1.0 - UV.x)) * noise(vec2(UV.x * 12.0, UV.y * 2.0));
	c = mix(c, dust_col, clamp(drift * dust * 1.6, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.25, wet);
	METALLIC = wet * 0.15;
	SPECULAR = 0.5 + wet * 0.3;
}
