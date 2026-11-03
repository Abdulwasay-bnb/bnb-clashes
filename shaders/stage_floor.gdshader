// Procedural arena floors. mode: 0 neon grid, 1 wet concrete, 2 wood planks, 3 sand + stone ring, 4 steel deck.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform int mode = 0;
uniform float radius = 11.0;                        // half-size of the floor plane
uniform float ring_at = 7.6;                        // fight boundary marking
uniform vec4 ring_color : source_color = vec4(0.18, 0.9, 1.0, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
float ringline(float r, float at, float w) { return 1.0 - smoothstep(0.0, w, abs(r - at)); }

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * radius;
	float r = length(p);
	vec3 col = vec3(0.1);
	vec3 emit = vec3(0.0);
	float rough = 0.6, metal = 0.1;
	if (mode == 0) {
		col = mix(vec3(0.11, 0.15, 0.25), vec3(0.05, 0.07, 0.12), smoothstep(0.0, radius, r));
		vec2 g = abs(fract(p * 0.55) - 0.5);
		col += vec3(0.25, 0.4, 0.6) * (1.0 - smoothstep(0.0, 0.02, min(g.x, g.y))) * 0.18;
		float rings = ringline(r, ring_at, 0.06) * 1.2 + ringline(r, ring_at * 0.95, 0.02) * 0.35;
		col += ring_color.rgb * rings;
		col += vec3(1.0, 0.8, 0.35) * ringline(r, 1.7, 0.03) * 0.5;
		float a = atan(p.y, p.x);
		float tick = step(0.5, fract(a / 6.2831853 * 24.0)) * step(ring_at * 1.03, r) * step(r, ring_at * 1.08);
		col += mix(ring_color.rgb, vec3(1.0, 0.3, 0.42), step(0.5, fract(a / 6.2831853 * 12.0))) * tick * 0.5;
		emit = col * 0.22 + ring_color.rgb * ringline(r, ring_at, 0.06) * 0.8;
		rough = 0.32; metal = 0.25;
	} else if (mode == 1) {
		float n = fbm(p * 0.9);
		col = mix(vec3(0.16, 0.17, 0.19), vec3(0.26, 0.27, 0.29), n);
		vec2 tile = abs(fract(p * 0.4) - 0.5);
		col *= 1.0 - (1.0 - smoothstep(0.0, 0.015, min(tile.x, tile.y))) * 0.35;
		float puddle = smoothstep(0.52, 0.6, fbm(p * 0.28 + 3.0));
		col = mix(col, vec3(0.04, 0.05, 0.07), puddle * 0.85);
		rough = mix(0.85, 0.05, puddle); metal = puddle * 0.4;
		// rain ripples in the puddles
		vec2 cell = floor(p * 1.3);
		float ph = fract(TIME * 0.9 + hash(cell));
		float d = length(fract(p * 1.3) - 0.5 - (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.4);
		emit += vec3(0.5, 0.6, 0.8) * puddle * (1.0 - smoothstep(0.0, 0.03, abs(d - ph * 0.45))) * (1.0 - ph) * 0.25;
		emit += ring_color.rgb * ringline(r, ring_at, 0.05) * 0.5;
		col += ring_color.rgb * ringline(r, ring_at, 0.05) * 0.4;
	} else if (mode == 2) {
		float plank = floor(p.x * 1.4);
		float off = hash(vec2(plank, 0.0)) * 7.0;
		float grain = fbm(vec2(p.x * 9.0, p.y * 0.7 + off));
		col = mix(vec3(0.42, 0.25, 0.13), vec3(0.62, 0.4, 0.22), grain);
		col *= 0.85 + 0.25 * hash(vec2(plank, floor(p.y * 0.35 + off)));
		float seam = 1.0 - smoothstep(0.0, 0.03, abs(fract(p.x * 1.4) - 0.5) - 0.47);
		float joint = 1.0 - smoothstep(0.0, 0.02, abs(fract(p.y * 0.35 + off) - 0.5) - 0.485);
		col *= 1.0 - max(seam, joint) * 0.55;
		// painted circle like a training mat edge
		col = mix(col, vec3(0.75, 0.12, 0.1), ringline(r, ring_at, 0.09) * 0.85);
		col = mix(col, vec3(0.95, 0.9, 0.8), ringline(r, 0.9, 0.05) * 0.6);
		rough = 0.5; metal = 0.0;
	} else if (mode == 3) {
		float rip = sin(p.x * 3.0 + fbm(p * 0.6) * 6.0) * 0.5 + 0.5;
		col = mix(vec3(0.62, 0.48, 0.31), vec3(0.74, 0.6, 0.41), fbm(p * 0.5) * 0.7 + rip * 0.3);
		if (r < ring_at + 0.3) {
			vec2 q = p * 0.75;
			q.x += step(1.0, mod(floor(q.y), 2.0)) * 0.5;
			vec2 t = abs(fract(q) - 0.5);
			float stone = 0.8 + 0.25 * hash(floor(q));
			vec3 sc = vec3(0.52, 0.45, 0.38) * stone * (0.85 + 0.3 * fbm(p * 3.0));
			float gap = 1.0 - smoothstep(0.42, 0.47, max(t.x, t.y));
			col = mix(mix(vec3(0.7, 0.58, 0.42), col, 0.5), sc, gap);
			col *= 1.0 - fbm(p * 1.5 + 9.0) * 0.25 * smoothstep(ring_at - 2.0, ring_at, r);   // sand drifting over the edge
		}
		col = mix(col, vec3(0.45, 0.3, 0.18), ringline(r, ring_at + 0.3, 0.12) * 0.7);
		rough = 0.92; metal = 0.0;
	} else {
		vec2 q = p / 1.6;
		vec2 t = abs(fract(q) - 0.5);
		float plate = 0.85 + 0.2 * hash(floor(q));
		col = vec3(0.24, 0.27, 0.3) * plate;
		float rust = smoothstep(0.55, 0.75, fbm(p * 0.8 + 4.0));
		col = mix(col, vec3(0.35, 0.18, 0.1), rust * 0.7);
		col *= 1.0 - (1.0 - smoothstep(0.46, 0.48, max(t.x, t.y))) * 0.0 - smoothstep(0.47, 0.5, max(t.x, t.y)) * 0.5;
		vec2 rv = abs(fract(q * 4.0) - 0.5);
		col += vec3(0.12) * (1.0 - smoothstep(0.06, 0.1, length(rv))) * step(0.4, max(t.x, t.y));
		// yellow hazard boundary paint
		float stripe = step(0.5, fract((p.x + p.y) * 0.7));
		col = mix(col, mix(vec3(0.95, 0.75, 0.1), vec3(0.08), stripe), ringline(r, ring_at, 0.14) * 0.9);
		rough = mix(0.35, 0.8, rust); metal = 0.55;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
