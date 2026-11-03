// Floating ad screens: scanlines, scrolling bars and a pulsing frame, additive.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 color : source_color = vec4(0.18, 0.9, 1.0, 1.0);
uniform float seed = 0.0;
void fragment() {
	vec2 uv = UV;
	float scan = 0.65 + 0.35 * sin(uv.y * 160.0 + TIME * 8.0);
	float bars = step(0.55, fract(uv.x * 6.0 - TIME * 0.4 + seed)) * step(0.3, uv.y) * step(uv.y, 0.7);
	float frame = step(uv.x, 0.03) + step(0.97, uv.x) + step(uv.y, 0.05) + step(0.95, uv.y);
	float flick = 0.85 + 0.15 * sin(TIME * 23.0 + seed * 10.0);
	vec3 c = color.rgb * (0.12 + bars * 0.5 + clamp(frame, 0.0, 1.0) * 0.9) * scan * flick;
	ALBEDO = c;
	ALPHA = 1.0;
}
