shader_type spatial;
// BNB Rush Hour road: asphalt with a little grain, white edge lines and dashed lane lines.
// UV.x runs across the road (0..1), UV.y along it (in 6 m units).

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 asphalt = vec3(0.16, 0.16, 0.18) + (h21(floor(UV * vec2(80.0, 40.0))) - 0.5) * 0.03;
	float edge = step(UV.x, 0.035) + step(0.965, UV.x);
	float dash = step(0.5, fract(UV.y * 0.5));
	float lanes = (step(abs(UV.x - 0.333), 0.006) + step(abs(UV.x - 0.667), 0.006)) * dash;
	vec3 c = mix(asphalt, vec3(0.92), clamp(edge + lanes, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
