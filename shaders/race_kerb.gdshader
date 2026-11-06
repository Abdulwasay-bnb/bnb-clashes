shader_type spatial;
render_mode cull_disabled;
// Rumble kerbs along the road edges: alternating stripes. UV.y runs along the road in metres / 6.

uniform vec4 col_a : source_color = vec4(0.85, 0.12, 0.12, 1.0);
uniform vec4 col_b : source_color = vec4(0.95, 0.95, 0.95, 1.0);

void fragment() {
	float s = step(0.5, fract(UV.y * 3.0));
	ALBEDO = mix(col_a.rgb, col_b.rgb, s);
	ROUGHNESS = 0.6;
}
