class_name MoveClips
## Maps a fighter's moves to Mixamo attack clips and time-warps them onto the move's frame data:
## the clip's detected impact lands exactly on the move's first active frame.
##
## Each clip lists its natural striking limb; a move on the other side plays it mirrored.

const CLIPS := {
	"jab": [["atk_jab_b", "lh"], ["atk_punching", "lh"]],
	"cross": [["atk_cross_a", "rh"], ["atk_cross", "rh"]],
	"hook": [["atk_hook_a", "lh"], ["atk_hook_b", "rh"]],
	"body": [["atk_hook", "lh"]],
	"upper": [["atk_upper_b", "rh"], ["atk_upper_a", "lh"]],
	"elbow": [["atk_elbow", "rh"], ["atk_elbow_b", "rh"]],
	"knee": [["atk_knee", "rk"]],
	"flyknee": [["atk_flyknee_combo", "rk"]],
	"palm": [["atk_palm_combo", "lh"]],
	"headbutt": [["atk_headbutt", "hd"]],
	"kick": [["atk_kick", "lf"]],                     # front / snap kick
	"push": [["atk_side_kick", "lf"]],                # teep, side kick, big boot
	"round_high": [["atk_round_high", "rf"]],
	"round_mid": [["atk_round_mid", "rf"], ["atk_round_high", "rf"]],
	"low_kick": [["atk_low_kick", "rf"]],
	"spin": [["atk_spin_back", "rf"]],
	"tornado": [["atk_hurricane", "lf"]],
	"sweep": [["atk_sweep", "rf"]],
	"jump": [["atk_jump_kick_a", "lf"]],
	"crescent": [["atk_crescent", "rf"]],
	"dropkick": [["atk_dropkick", "rf"]],
}

const LEG_KINDS := ["knee", "flyknee", "kick", "push", "round_high", "round_mid", "low_kick", "spin", "tornado", "sweep", "jump", "crescent", "dropkick"]

## Clips whose strike the analyzer can't see (a sweep stays on the floor).
const IMPACT := {"atk_sweep": 0.87, "atk_crescent": 1.33, "atk_dropkick": 1.40}

## Name keywords -> clip kind. Order matters: the first match wins. "round" resolves by the move's height.
const KINDS := [
	["flying knee", "flyknee"], ["knee", "knee"], ["elbow", "elbow"], ["forearm", "elbow"],
	["headbutt", "headbutt"],
	["sweep", "sweep"], ["rasteira", "sweep"], ["ground spin", "sweep"],
	["jump kick", "jump"], ["aú kick", "jump"], ["voador", "jump"],
	["dropkick", "dropkick"], ["crescent", "crescent"], ["gale", "tornado"], ["tornado", "tornado"], ["butterfly", "tornado"], ["triple", "tornado"],
	["backfist", "hook"], ["spin", "spin"], ["pivot", "spin"], ["compasso", "spin"], ["queixada", "spin"], ["armada", "spin"], ["meia lua", "spin"],
	["body hook", "body"], ["body shovel", "body"], ["gut", "body"], ["liver", "body"], ["body blow", "body"],
	["low", "low_kick"], ["shin", "low_kick"], ["leg kick", "low_kick"],
	["side kick", "push"], ["push kick", "push"], ["teep", "push"], ["big boot", "push"], ["boot kick", "push"], ["bênção", "push"],
	["uppercut", "upper"], ["upper", "upper"], ["rising coil", "upper"], ["rising hammer", "upper"], ["rising brick", "upper"],
	["hook", "hook"], ["haymaker", "hook"], ["backhand", "hook"], ["backfist", "hook"],
	["palm", "palm"],
	["cross", "cross"], ["straight", "cross"], ["one-two", "cross"], ["chain", "cross"], ["lunge", "cross"],
	["jab", "jab"], ["beak", "jab"], ["snake", "jab"], ["diagnostic", "jab"],
	["roundhouse", "round"], ["martelo", "round"], ["whip", "round"], ["phoenix", "round"], ["arc", "round"], ["round", "round"],
	["snap", "kick"], ["toe kick", "kick"], ["crane kick", "kick"], ["calibration", "kick"], ["lift kick", "kick"],
	["rising boot", "kick"], ["heel", "kick"], ["kick", "kick"],
]
## Moves that keep their keyframed animation until a fitting clip exists.
const SKIP := ["enzuigiri", "axe", "tesoura", "stomp", "dig", "lariat", "chop",
	"double axe", "twin", "throw", "suplex", "slam", "clinch", "surge", "freight", "iron mountain", "bolo",
	"anvil", "skyhook", "overhand", "bananeira", "sway back", "hammer servo", "smash"]


static func kind_of(m: Data.Move) -> String:
	var nm := m.name.to_lower()
	for sk in SKIP:
		if sk in nm: return ""
	for kw in KINDS:
		if kw[0] in nm:
			var k: String = kw[1]
			if k == "round":
				k = "round_high" if m.lvl == "high" else ("low_kick" if m.lvl == "low" else "round_mid")
			return k
	return ""


static func info(m: Data.Move):
	if m.clip_info != null:
		return m.clip_info if m.clip_info is Dictionary else null
	m.clip_info = false
	if m.trans or m.is_throw or m.surge: return null
	var kind := kind_of(m)
	if kind == "" or not CLIPS.has(kind): return null
	var limb := m.limb
	if limb == "": limb = CLIPS[kind][0][1]
	# a hand move must not borrow a kick clip and vice versa ("Low Mantis" is a low punch)
	if (kind in LEG_KINDS) != (limb.right(1) in ["f", "k"]) and limb != "hd": return null
	# prefer a clip whose natural limb matches the move's; otherwise mirror one from the other side
	var pick = null
	for c in CLIPS[kind]:
		if ClipLib.has(c[0]) and c[1] == limb:
			pick = c; break
	if pick == null:
		for c in CLIPS[kind]:
			if ClipLib.has(c[0]):
				pick = c; break
	if pick == null: return null
	var natural: String = pick[1]
	var mirror := natural != "hd" and _side(natural) != _side(limb)
	var clip: ClipLib.Clip = ClipLib.get_clip(pick[0])
	# impact = the clip's first strike with its natural limb (fallback: first strike of any limb)
	var impact: float = IMPACT.get(pick[0], -1.0)
	if impact < 0.0:
		for h in clip.hits:
			if h.limb == natural: impact = h.t; break
	if impact < 0.0 and not clip.hits.is_empty(): impact = clip.hits[0].t
	if impact < 0.0: return null
	# play out the follow-through, but stop before the clip's next strike (combo clips)
	var stop := minf(clip.length, impact + 0.65)
	for h in clip.hits:
		if h.t > impact + 0.2 and h.limb in ["lh", "rh", "lf", "rf"] and h.reach > 0.45:
			stop = minf(stop, h.t - 0.2); break
	var d := {clip = pick[0], mirror = mirror, impact = impact, start = maxf(0.0, impact - 0.5), stop = stop}
	m.clip_info = d
	return d


static func _side(limb: String) -> String: return limb.left(1)


## Clip time for the move at frame sf: wind-up compressed into startup, impact on the first active
## frame, follow-through and return stretched over active + recovery.
static func time_at(d: Dictionary, m: Data.Move, sf: int) -> float:
	if sf < m.s:
		return lerpf(d.start, d.impact, float(sf) / maxf(1.0, m.s))
	return lerpf(d.impact, d.stop, clampf(float(sf - m.s) / maxf(1.0, m.end - m.s), 0.0, 1.0))
