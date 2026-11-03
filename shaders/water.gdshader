// Night harbor water: rolling vertex waves, dark body, fresnel sky tint, moving moon glints.
shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;
uniform vec4 deep : source_color = vec4(0.02, 0.05, 0.09, 1.0);
uniform vec4 sky : source_color = vec4(0.12, 0.2, 0.35, 1.0);
uniform vec4 glint : source_color = vec4(0.75, 0.85, 1.0, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(w.x * 0.35 + TIME * 1.1) * 0.12 + sin(w.z * 0.5 + TIME * 0.8) * 0.08;
}
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float n = noise(w.xz * 0.8 + TIME * 0.3) * noise(w.xz * 1.7 - TIME * 0.4);
	ALBEDO = mix(deep.rgb, sky.rgb, fr * 0.8);
	EMISSION = glint.rgb * smoothstep(0.42, 0.55, n) * 0.6 + sky.rgb * fr * 0.15;
	ROUGHNESS = 0.15;
	METALLIC = 0.3;
}
