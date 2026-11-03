// Arena floor: radial gradient, grid, glowing rings and edge markers.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform float radius = 9.0;

float ringline(float r, float at, float w) { return 1.0 - smoothstep(0.0, w, abs(r - at)); }

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * radius;
	float r = length(p);
	vec3 col = mix(vec3(0.11, 0.15, 0.25), vec3(0.05, 0.07, 0.12), smoothstep(0.0, radius, r));
	vec2 g = abs(fract(p * 0.55) - 0.5);
	col += vec3(0.25, 0.4, 0.6) * (1.0 - smoothstep(0.0, 0.02, min(g.x, g.y))) * 0.18;
	col += vec3(0.18, 0.9, 1.0) * ringline(r, radius * 0.83, 0.06) * 1.2;
	col += vec3(0.18, 0.9, 1.0) * ringline(r, radius * 0.79, 0.02) * 0.35;
	col += vec3(1.0, 0.8, 0.35) * ringline(r, radius * 0.22, 0.03) * 0.5;
	float a = atan(p.y, p.x);
	float tick = step(0.5, fract(a / 6.2831853 * 24.0)) * step(radius * 0.86, r) * step(r, radius * 0.9);
	col += mix(vec3(0.18, 0.9, 1.0), vec3(1.0, 0.3, 0.42), step(0.5, fract(a / 6.2831853 * 12.0))) * tick * 0.5;
	ALBEDO = col;
	ROUGHNESS = 0.6;
	METALLIC = 0.15;
	EMISSION = col * 0.25 + vec3(0.18, 0.9, 1.0) * ringline(r, radius * 0.83, 0.06) * 0.8;
}
