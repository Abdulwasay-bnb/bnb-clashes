// Inverted-hull outline: pushes back faces out along the normal and draws them dark.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform float thickness = 0.008;
uniform vec4 color : source_color = vec4(0.03, 0.03, 0.06, 1.0);

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = color.rgb;
}
