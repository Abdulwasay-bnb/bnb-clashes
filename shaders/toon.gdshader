// Anime cel shading: two hard light bands, cool shadow tint, fresnel rim light.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shade : source_color = vec4(0.55, 0.52, 0.72, 1.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength = 0.0;
uniform vec4 rim_color : source_color = vec4(0.7, 0.85, 1.0, 1.0);
uniform float rim_amount = 0.35;
uniform float flash = 0.0;

void fragment() {
	ALBEDO = albedo.rgb;
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = emission.rgb * emission_strength + rim_color.rgb * fr * rim_amount + vec3(flash);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.04, ndl) * 0.7 + smoothstep(0.55, 0.6, ndl) * 0.3;
	lit *= mix(0.35, 1.0, ATTENUATION);
	vec3 band = mix(shade.rgb, vec3(1.0), lit);
	DIFFUSE_LIGHT += ALBEDO * band * LIGHT_COLOR * 0.6;
}
