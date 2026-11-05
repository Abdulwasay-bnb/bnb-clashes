// Shared body of the textured anime cel shader (included by generated variants in vrm_rig.gd).
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 shade : source_color = vec4(0.62, 0.58, 0.78, 1.0);
uniform vec4 rim_color : source_color = vec4(0.75, 0.88, 1.0, 1.0);
uniform float rim_amount = 0.18;
uniform float flash = 0.0;
uniform float emission_strength = 0.0;
uniform float saturation = 1.0;   // per-fighter recolor: 0 = greyscale
uniform float brightness = 1.0;
// Costume print, painted over the cloth in texture space while keeping the fabric's folds.
// 0 none, 1 plaid, 2 camo, 3 flames, 4 bands, 5 pinstripes, 6 diagonal, 7 dots, 8 tech grid, 9 scales, 10 gradient, 11 solid
uniform int pattern = 0;
uniform vec4 pat_a : source_color = vec4(1.0);
uniform vec4 pat_b : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float pat_scale = 1.0;
uniform float pat_o = 0.5;
uniform float dirt = 0.0;      // clothes: dust from knockdowns (0..1)
uniform float blood = 0.0;     // clothes: blood stains (0..1)
// Anime hair: strand streaks, a lifted (blue-black) shadow, and a glossy "angel ring" highlight round the crown.
uniform float hair_sheen = 0.0;
uniform vec4 sheen_color : source_color = vec4(0.78, 0.84, 1.0, 1.0);
varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}     // where flames / bands / gradients sit along the texture's height

float _h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float _vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(_h21(i), _h21(i + vec2(1.0, 0.0)), f.x), mix(_h21(i + vec2(0.0, 1.0)), _h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float _fbm(vec2 p) { float s = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { s += a * _vn(p); p *= 2.03; a *= 0.5; } return s; }
// anti-aliased step: crisp edges without shimmer at any distance
float _st(float e, float x) { float w = max(fwidth(x), 1e-4); return smoothstep(e - w, e + w, x); }

vec2 pattern_mask(vec2 uv) {
	vec2 p = uv * pat_scale;
	if (pattern == 1) {   // plaid: two woven bands + thin accent lines
		float bx = 1.0 - _st(0.5, fract(p.x * 8.0)); float by = 1.0 - _st(0.5, fract(p.y * 8.0));
		float tx = _st(0.9, fract(p.x * 8.0 + 0.3)); float ty = _st(0.9, fract(p.y * 8.0 + 0.3));
		return vec2((bx + by) * 0.4, clamp(tx + ty, 0.0, 1.0));
	}
	if (pattern == 2) {   // camo: two blotch layers
		float n1 = _fbm(p * 7.0); float n2 = _fbm(p * 7.0 + vec2(5.2, 1.3));
		float a = _st(0.52, n1);
		return vec2(a, _st(0.56, n2) * (1.0 - a));
	}
	if (pattern == 3) {   // flames licking up from pat_o downward (v grows toward the hem)
		float n = _fbm(vec2(p.x * 9.0, p.y * 4.0 - TIME * 0.0));
		float y = (uv.y - pat_o) * 4.0 + n * 1.2;
		return vec2(_st(0.6, y), _st(1.15, y));
	}
	if (pattern == 4) {   // bands
		float f = fract((uv.y - pat_o) * 10.0 * pat_scale);
		return vec2(1.0 - _st(0.22, f), _st(0.3, f) * (1.0 - _st(0.36, f)));
	}
	if (pattern == 5) {   // pinstripes
		float f = fract(p.x * 24.0);
		return vec2(1.0 - _st(0.1, f), 0.0);
	}
	if (pattern == 6) {   // diagonal stripes
		float f = fract((p.x + p.y) * 9.0);
		return vec2(1.0 - _st(0.42, f), _st(0.5, f) * (1.0 - _st(0.56, f)));
	}
	if (pattern == 7) {   // polka dots
		vec2 g = fract(p * 14.0 + vec2(0.0, step(0.5, fract(p.x * 7.0)) * 0.5)) - 0.5;
		return vec2(1.0 - _st(0.22, length(g)), 0.0);
	}
	if (pattern == 8) {   // tech grid: circuit lines with glowing nodes
		vec2 g = fract(p * 12.0); vec2 c = floor(p * 12.0);
		float r = _h21(c);
		float line = (r > 0.5 ? 1.0 - _st(0.06, abs(g.x - 0.5)) : 1.0 - _st(0.06, abs(g.y - 0.5)));
		float node = 1.0 - _st(0.13, length(g - 0.5));
		return vec2(line * step(0.25, r), node * step(0.7, r));
	}
	if (pattern == 9) {   // scales
		vec2 q = p * vec2(16.0, 22.0);
		q.x += step(1.0, mod(q.y, 2.0)) * 0.5;
		vec2 g = fract(q) - vec2(0.5, 0.0);
		float d = length(g);
		return vec2(_st(0.42, d) * (1.0 - _st(0.5, d)), 1.0 - _st(0.42, d));
	}
	if (pattern == 11) {  // solid repaint (keeps the folds)
		return vec2(1.0, 0.0);
	}
	if (pattern == 10) {  // two-tone gradient
		float t = smoothstep(pat_o - 0.25, pat_o + 0.25, uv.y);
		return vec2(t, 0.0);
	}
	return vec2(0.0);
}

void fragment() {
	vec4 c = texture(tex, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(lum), c.rgb, saturation) * brightness;
	c *= albedo;
	if (pattern > 0) {
		// keep the painted folds: compare each texel to its blurred neighbourhood
		vec3 loc = textureLod(tex, UV, 5.0).rgb;
		float fold = clamp(lum / max(dot(loc, vec3(0.299, 0.587, 0.114)), 0.03), 0.55, 1.3);
		vec2 m = pattern_mask(UV);
		c.rgb = mix(c.rgb, pat_a.rgb * fold, clamp(m.x, 0.0, 1.0) * pat_a.a);
		c.rgb = mix(c.rgb, pat_b.rgb * fold, clamp(m.y, 0.0, 1.0) * pat_b.a);
	}
	if (dirt > 0.001) {   // patchy dust, growing with every knockdown
		float n = _fbm(UV * 16.0 + vec2(3.1, 1.7));
		float d = smoothstep(1.0 - dirt * 0.75, 1.05 - dirt * 0.75, n);
		c.rgb = mix(c.rgb, c.rgb * vec3(0.6, 0.5, 0.38) + vec3(0.06, 0.045, 0.03), d * 0.85);
	}
	if (blood > 0.001) {
		float n2 = _fbm(UV * 10.0 + vec2(7.3, 2.2));
		float b = smoothstep(1.0 - blood * 0.55, 1.03 - blood * 0.55, n2);
		c.rgb = mix(c.rgb, vec3(0.42, 0.02, 0.03), b * 0.8);
	}
	float ring = 0.0;
	if (hair_sheen > 0.001) {
		vec3 q = v_obj * 30.0;
		float streak = 0.5 + 0.5 * sin(q.x * 3.1 + q.z * 1.7 + _vn(q.xy * 0.9) * 5.0);
		c.rgb *= 1.0 - 0.22 * hair_sheen * streak;                       // strands
		c.rgb += vec3(0.055, 0.06, 0.09) * hair_sheen;                  // never a flat black blob
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		ring = smoothstep(0.42, 0.58, wn.y) * (1.0 - smoothstep(0.7, 0.86, wn.y));
		ring *= smoothstep(0.05, 0.45, dot(NORMAL, VIEW)) * (0.55 + 0.45 * streak) * hair_sheen;
	}
	ALBEDO = c.rgb;
	#ifdef USE_ALPHA
	ALPHA = c.a;
	#endif
	#ifdef USE_SCISSOR
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	#endif
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = c.rgb * emission_strength + rim_color.rgb * fr * (rim_amount + hair_sheen * 0.16) + vec3(flash)
		+ sheen_color.rgb * ring * 0.55;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.05, ndl) * 0.75 + smoothstep(0.55, 0.6, ndl) * 0.25;
	lit *= mix(0.4, 1.0, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * mix(shade.rgb, vec3(1.0), lit) * LIGHT_COLOR * 0.42;
}
