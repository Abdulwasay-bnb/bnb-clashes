shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float alpha = 1.0;
void fragment() { ALBEDO = color.rgb * alpha; ALPHA = alpha; }
