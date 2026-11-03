// Skyline buildings with randomly lit windows.
shader_type spatial;
render_mode unshaded;
uniform vec2 repeat = vec2(4.0, 10.0);
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
void fragment() {
	vec2 uv = UV * repeat * vec2(3.0, 4.0);
	vec2 id = floor(uv), f = fract(uv);
	float win = step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.7);
	float on = step(0.66, hash(id));
	vec3 lit = mix(vec3(1.0, 0.82, 0.5), vec3(0.5, 0.85, 1.0), step(0.5, hash(id + 7.0)));
	ALBEDO = mix(vec3(0.04, 0.05, 0.09), lit * 0.8, win * on);
}
