class_name Voices
## Fighter voices, synthesized like the rest of the game's audio: a glottal pulse at the speaker's pitch,
## shaped by vowel formants, plus breath noise. Each person gets their own pitch / timbre / rasp,
## and each moment its own sound: attack shouts, heavy yells, hurt grunts, KO cry, power cry, victory laugh.

const RATE := 22050
const VOWELS := {   # formant frequencies (Hz) for an adult male voice; scaled up for higher voices
	"a": [730.0, 1090.0, 2440.0], "e": [530.0, 1840.0, 2480.0], "u": [300.0, 870.0, 2240.0],
	"o": [570.0, 840.0, 2410.0], "i": [270.0, 2290.0, 3010.0],
}
## [duration s, vowel, pitch start x, pitch end x, onset breath s, loudness]
const KINDS := {
	"attack": [[0.17, "a", 1.15, 0.9, 0.035, 0.9], [0.2, "e", 1.25, 0.95, 0.05, 0.9], [0.15, "u", 1.1, 0.85, 0.03, 0.85]],
	"heavy": [[0.34, "a", 1.35, 0.95, 0.06, 1.0], [0.3, "e", 1.4, 1.0, 0.05, 1.0]],
	"hurt": [[0.2, "u", 1.05, 0.75, 0.0, 0.85], [0.18, "o", 1.15, 0.8, 0.0, 0.85], [0.24, "a", 1.3, 0.7, 0.0, 0.9]],
	"ko": [[0.95, "a", 1.45, 0.55, 0.0, 1.0]],
	"power": [[0.62, "a", 1.0, 1.55, 0.08, 1.0]],
}

static var cache := {}   # "id:kind:variant" -> AudioStreamWAV


## Voice settings for a fighter: pitch, formant scale, breathiness, rasp, wobble, volume.
static func profile(C: Dictionary) -> Dictionary:
	var p: Dictionary = C.get("person", {})
	var female := String(p.get("model", "")) == "female"
	var h := hash(String(C.id))
	var v := {
		f0 = (198.0 if female else 104.0) * (0.92 + float(h % 17) / 100.0),
		fs = (1.17 if female else 1.0) * (0.96 + float((h / 21) % 9) / 100.0),
		breath = 0.12, rasp = 0.05, wobble = 0.0, vol = 1.0,
	}
	var who := String(C.id)
	match who:   # a few people get a very particular voice
		"hamza_khan": v.f0 = 86.0; v.rasp = 0.12
		"ali": v.f0 = 128.0; v.rasp = 0.25; v.vol = 1.1                    # high, raspy, always annoyed
		"tuaha_aamir": v.breath = 0.32; v.vol = 0.6                          # rarely raises his voice
		"abdul_wasay_waqas": v.breath = 0.25; v.vol = 0.75
		"sarfraz_yousaf": v.wobble = 0.22                                    # comic sing-song
		"kashaf_ud_duja": v.f0 = 220.0; v.breath = 0.18                      # sweet-toned
		"amina_mughal", "aqsa_altaf": v.vol = 1.15; v.f0 *= 1.06              # loud and lively
		"faizan_ali": v.f0 *= 0.92; v.breath = 0.25                          # can't be bothered
		"zia_khan", "faisal_ahmed": v.f0 *= 0.9; v.rasp = 0.1
		"umar_farooq": v.wobble = 0.1; v.f0 *= 1.05                          # nervous shake
		"muhammad_mubarak": v.f0 *= 0.95; v.breath = 0.2                     # snake-like hiss
	return v


## Recorded voices win when present: assets/audio/voices/<male|female>/<kind>_N.ogg (attack / heavy / hurt / ko / power / win).
static var recorded := {}   # "male:hurt" -> [AudioStream]


static func _recorded(C: Dictionary, kind: String) -> AudioStream:
	var p: Dictionary = C.get("person", {})
	var g := "female" if String(p.get("model", "")) == "female" else "male"
	var key := g + ":" + kind
	if not recorded.has(key):
		var set := []
		for i in 12:
			var path := "res://assets/audio/voices/%s/%s_%d.ogg" % [g, kind, i]
			if ResourceLoader.exists(path): set.append(load(path))
		recorded[key] = set
	var arr: Array = recorded[key]
	return null if arr.is_empty() else arr[randi() % arr.size()]


static func get_sound(C: Dictionary, kind: String) -> AudioStream:
	var rec := _recorded(C, kind)
	if rec != null: return rec
	if kind == "win":
		return _cached(C, "win", 0, func(): return _laugh(profile(C)))
	var opts: Array = KINDS.get(kind, [])
	if opts.is_empty(): return null
	var variant := randi() % opts.size()
	return _cached(C, kind, variant, func(): return _make(profile(C), opts[variant]))


static func _cached(C: Dictionary, kind: String, variant: int, make: Callable) -> AudioStreamWAV:
	var key := "%s:%s:%d" % [C.id, kind, variant]
	if not cache.has(key): cache[key] = make.call()
	return cache[key]


## Two-pole resonator (band-pass) state: [y1, y2, a1, a2, gain]
static func _reson(f: float, bw: float) -> Array:
	var r := exp(-PI * bw / RATE)
	return [0.0, 0.0, 2.0 * r * cos(TAU * f / RATE), -r * r, 1.0 - r]


static func _step(st: Array, x: float) -> float:
	var y: float = st[4] * x + st[2] * st[0] + st[3] * st[1]
	st[1] = st[0]; st[0] = y
	return y


static func _make(v: Dictionary, k: Array) -> AudioStreamWAV:
	var dur: float = k[0]
	var vowel: Array = VOWELS[k[1]]
	var n := int(dur * RATE)
	# wider formant bandwidths and a quieter top end sound like a person, not a buzzer
	var res := [_reson(vowel[0] * v.fs, 110.0), _reson(vowel[1] * v.fs, 140.0), _reson(vowel[2] * v.fs, 220.0)]
	var amps := [1.0, 0.42, 0.12]
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	var prev_g := 0.0
	var lp := 0.0
	var shim := 1.0
	var jit := 1.0
	var breath_t: float = k[4]
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		# natural pitch: contour + slow vibrato + per-cycle jitter
		var f0: float = v.f0 * lerpf(k[2], k[3], u) * (1.0 + v.wobble * sin(t * 38.0)) * (1.0 + 0.012 * sin(t * 31.0)) * jit
		var prev_ph := ph
		ph += f0 / RATE
		if floorf(ph) != floorf(prev_ph):   # new glottal cycle: a little jitter and shimmer, like a real voice
			jit = 1.0 + randf_range(-0.03, 0.03)     # strained voices wobble more
			shim = 1.0 + randf_range(-0.16, 0.16)
		var x := fposmod(ph, 1.0)
		# Rosenberg glottal pulse (smooth opening, quicker closing, closed phase), then its slope (lip radiation)
		var g := 0.0
		if x < 0.42: g = 0.5 * (1.0 - cos(PI * x / 0.42))
		elif x < 0.58: g = cos(PI * 0.5 * (x - 0.42) / 0.16)
		g *= shim
		var pulse: float = (g - prev_g) * 9.0
		prev_g = g
		pulse += randf_range(-1.0, 1.0) * v.rasp * 0.35
		var noise := randf_range(-1.0, 1.0)
		var voiced: float = 0.0 if t < breath_t else 1.0
		# effort: breath runs through the whole sound, a creaky (fry) onset, a shaky tremor
		var air := maxf(v.breath, 0.28)
		var fry: float = 1.0 - smoothstep(0.0, 0.06, t)
		var trem := 1.0 + 0.12 * sin(t * 47.0 + randf() * 0.3)
		var src: float = pulse * voiced * (1.0 - air * 0.55) * trem * (1.0 - fry * 0.5) \
			+ noise * (air * 0.5 + (0.55 if t < breath_t else 0.0) + fry * 0.25)
		var out := 0.0
		for j in 3: out += _step(res[j], src) * float(amps[j])
		lp += (out - lp) * 0.45            # gentle low-pass: takes the hiss / buzz off the top
		var env: float = minf(1.0, t / 0.02) * pow(1.0 - u, 1.3)
		data.encode_s16(i * 2, int(clampf(lp * env * 3.2 * k[5] * v.vol, -1.0, 1.0) * 21000.0))
	return _wav(data)


## "ha-ha-ha": three short bursts with a rising pitch.
static func _laugh(v: Dictionary) -> AudioStreamWAV:
	var parts := PackedByteArray()
	for b in 3:
		var s := _make(v, [0.13, "a", 1.25 + b * 0.08, 1.05, 0.03, 0.9])
		parts.append_array(s.data)
		var gap := PackedByteArray(); gap.resize(int(0.06 * RATE) * 2)
		parts.append_array(gap)
	return _wav(parts)


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
