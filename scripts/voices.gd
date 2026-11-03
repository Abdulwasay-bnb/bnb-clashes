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
		f0 = (215.0 if female else 118.0) * (0.9 + float(h % 21) / 100.0),
		fs = (1.17 if female else 1.0) * (0.96 + float((h / 21) % 9) / 100.0),
		breath = 0.12, rasp = 0.05, wobble = 0.0, vol = 1.0,
	}
	var who := String(C.id)
	match who:   # a few people get a very particular voice
		"hamza_khan": v.f0 = 92.0; v.rasp = 0.16
		"ali": v.f0 = 152.0; v.rasp = 0.32; v.vol = 1.1                    # high, raspy, always annoyed
		"tuaha_aamir": v.breath = 0.32; v.vol = 0.6                          # rarely raises his voice
		"abdul_wasay_waqas": v.breath = 0.25; v.vol = 0.75
		"sarfraz_yousaf": v.wobble = 0.22                                    # comic sing-song
		"kashaf_ud_duja": v.f0 = 248.0; v.breath = 0.18                      # sweet-toned
		"amina_mughal", "aqsa_altaf": v.vol = 1.15; v.f0 *= 1.06              # loud and lively
		"faizan_ali": v.f0 *= 0.92; v.breath = 0.25                          # can't be bothered
		"zia_khan", "faisal_ahmed": v.f0 *= 0.9; v.rasp = 0.1
		"umar_farooq": v.wobble = 0.1; v.f0 *= 1.05                          # nervous shake
		"muhammad_mubarak": v.f0 *= 0.95; v.breath = 0.2                     # snake-like hiss
	return v


static func get_sound(C: Dictionary, kind: String) -> AudioStreamWAV:
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
	var res := [_reson(vowel[0] * v.fs, 90.0), _reson(vowel[1] * v.fs, 110.0), _reson(vowel[2] * v.fs, 150.0)]
	var amps := [1.0, 0.55, 0.25]
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	var breath_t: float = k[4]
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var f0: float = v.f0 * lerpf(k[2], k[3], u) * (1.0 + v.wobble * sin(t * 38.0)) * (1.0 + randf_range(-0.01, 0.01))
		ph += f0 / RATE
		var g := fposmod(ph, 1.0)
		var pulse: float = (g * 2.0 - 1.0) - (0.5 if g < 0.5 else -0.5) * 0.8          # bright glottal buzz
		pulse += randf_range(-1.0, 1.0) * v.rasp                                  # rasp
		var noise := randf_range(-1.0, 1.0)
		var voiced: float = 0.0 if t < breath_t else 1.0
		var src: float = pulse * voiced * (1.0 - v.breath) + noise * (v.breath + (0.8 if t < breath_t else 0.0))
		var out := 0.0
		for j in 3: out += _step(res[j], src) * float(amps[j])
		var env: float = minf(1.0, t / 0.012) * pow(1.0 - u, 1.6)
		data.encode_s16(i * 2, int(clampf(out * env * 2.6 * k[5] * v.vol, -1.0, 1.0) * 30000.0))
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
