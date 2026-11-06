shader_type spatial;
// BNB Carrom playfield: lacquered plywood with the classic markings drawn procedurally.
// UV 0..1 across the 74 x 74 cm playfield (x -> board x, y -> board y), so p is in centimetres from the centre.

const float H = 37.0;
const float B = 25.3;      // baseline (striker line) distance from the centre
const float U = 23.5;      // baseline half length
const float RC = 1.6;
const float PK = 34.6;     // pocket centre
const float PR = 2.3;      // pocket radius

uniform vec3 wood = vec3(0.86, 0.68, 0.44);
uniform vec3 ink = vec3(0.1, 0.06, 0.04);
uniform vec3 red = vec3(0.78, 0.1, 0.1);

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	float d = length(pa - ba * h);
	return 1.0 - smoothstep(w * 0.6, w, d);
}

float ring(vec2 p, vec2 c, float r, float w) {
	return 1.0 - smoothstep(w * 0.6, w, abs(length(p - c) - r));
}

float disc(vec2 p, vec2 c, float r) {
	return 1.0 - smoothstep(r - 0.08, r, length(p - c));
}

vec2 rot(vec2 p, float a) { return vec2(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y); }

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * H;
	// plywood: long grain plus a little figure
	float grain = noise(vec2(p.x * 0.08, p.y * 1.6)) * 0.6 + noise(vec2(p.x * 0.3, p.y * 6.0)) * 0.25;
	vec3 c = wood * (0.9 + grain * 0.18);
	float lines = 0.0;
	float reds = 0.0;
	// four baselines: double line with red circles at the ends
	for (int k = 0; k < 4; k++) {
		vec2 q = rot(p, -float(k) * 1.5707963);
		lines += seg(q, vec2(-U, B - RC), vec2(U, B - RC), 0.16);
		lines += seg(q, vec2(-U, B + RC), vec2(U, B + RC), 0.16);
		for (int e = 0; e < 2; e++) {
			vec2 cc = vec2(e == 0 ? -U : U, B);
			reds += disc(q, cc, RC - 0.3);
			lines += ring(q, cc, RC, 0.16);
		}
	}
	// diagonal arrows from near each pocket toward the middle
	for (int k = 0; k < 4; k++) {
		vec2 d = normalize(rot(vec2(1.0, 1.0), float(k) * 1.5707963));
		vec2 tail = d * 44.5;
		vec2 tip = d * 22.0;
		lines += seg(p, tail, tip, 0.16);
		vec2 side = vec2(-d.y, d.x);
		lines += seg(p, tip, tip + d * 2.2 + side * 1.4, 0.16);
		lines += seg(p, tip, tip + d * 2.2 - side * 1.4, 0.16);
		lines += ring(p, d * 46.0, 1.2, 0.14);
	}
	// centre: queen spot, rings and a star of petals
	reds += disc(p, vec2(0.0), 1.6);
	lines += ring(p, vec2(0.0), 3.4, 0.14);
	lines += ring(p, vec2(0.0), 8.6, 0.16);
	lines += ring(p, vec2(0.0), 15.6, 0.14);
	lines += ring(p, vec2(0.0), 16.2, 0.14);
	for (int k = 0; k < 8; k++) {
		vec2 d = rot(vec2(1.0, 0.0), float(k) * 0.7853982);
		lines += seg(p, d * 8.6, d * 15.6, 0.12);
	}
	c = mix(c, red, clamp(reds, 0.0, 1.0));
	c = mix(c, ink, clamp(lines, 0.0, 1.0));
	// pockets: dark holes with a worn rim
	float hole = 0.0;
	float rim = 0.0;
	for (int k = 0; k < 4; k++) {
		vec2 pk = vec2(k == 0 || k == 3 ? -PK : PK, k < 2 ? -PK : PK);
		hole = max(hole, disc(p, pk, PR));
		rim = max(rim, ring(p, pk, PR + 0.35, 0.45));
	}
	c = mix(c, c * 0.55, rim);
	c = mix(c, vec3(0.02, 0.015, 0.01), hole);
	ALBEDO = c;
	ROUGHNESS = mix(0.32, 0.9, hole);
	SPECULAR = 0.6;
}
