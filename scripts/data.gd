class_name Data
## Loads data/roster.json and compiles each fighter: full poses, keyframe tracks, AI move groups.

class Move:
	var key := ""
	var name := ""
	var s := 0
	var a := 0
	var r := 0
	var dmg := 0.0
	var lvl := "mid"
	var hit = null
	var blk = null
	var range := 1.02
	var push := 0.0
	var move := 0.0
	var back := 0.0
	var next := {}
	var auto := ""
	var launch := false
	var kd := false
	var homing := false
	var armor := false
	var low := false
	var jump := false
	var is_throw := false
	var cmd_throw := false
	var throw_type := "over"
	var to_stance := ""
	var trans := false
	var sig := false
	var surge := false
	var ch_launch := false
	var hidden := false
	var final := false      # FINAL POWER opener (connects -> cinematic)
	var track: Array = []   # [[frame, PackedFloat32Array], ...]
	var limb := ""          # striking limb from the strike pose: lh rh lf rf lk rk
	var clip_info = null    # cached Mixamo mapping (MoveClips)
	var end := 0


static var GG := PackedFloat32Array()
static var SYS := {}
static var Z := {}
static var ROSTER: Array = []


static func load_all() -> void:
	var f := FileAccess.open("res://data/roster.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	GG = Pose.with(Pose.zero(), d.GG)
	SYS = d.SYS
	Z = d.Z
	ROSTER.clear()
	# The 8 base fighting styles (move sets) live in roster.json; the playable roster is the BNB team
	# (data/bnb_roster.json, generated from CHARACTER_SHEET.csv by tools/gen_roster.py).
	var styles := {}
	for raw in d.RAW_ROSTER:
		styles[raw.id] = raw
	var team: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/bnb_roster.json"))
	for p in team.people:
		var raw: Dictionary = (styles[p.base] as Dictionary).duplicate(true)
		raw.id = p.id; raw.name = p.name; raw.title = p.title; raw.origin = p.origin; raw.style = p.style
		raw.quote = p.quote
		raw.scale = float(p.scale)   # the person's real height only (not the base style's size)
		raw.hp = float(raw.hp) * float(p.get("hp_mult", 1.0))
		raw.power = float(raw.power) * float(p.get("power_mult", 1.0))
		var a: Array = p.accent
		raw.look.accent = (roundi(a[0] * 255) << 16) | (roundi(a[1] * 255) << 8) | roundi(a[2] * 255)
		if String(p.surge) != "": raw.surge.n = p.surge
		var C := compile(raw)
		C.arch = p.base
		# their own grapple
		if (C.moves as Dictionary).has("12") and Fighter.PERSON_THROW.has(String(p.id)):
			(C.moves["12"] as Move).throw_type = Fighter.PERSON_THROW[String(p.id)]
		# their own names for moves (the Mixamo clip is picked from the name, so names can change the animation too)
		var mn: Dictionary = p.get("move_names", {})
		for k in mn:
			if (C.moves as Dictionary).has(k): (C.moves[k] as Move).name = String(mn[k])
		C.boss = p.boss
		C.person = p
		Models.register(p)
		ROSTER.append(C)


static func _b(raw: Dictionary, k: String) -> bool:
	var v = raw.get(k)
	if v == null: return false
	if v is bool: return v
	if v is float or v is int: return v != 0
	return true


static func _is_kick(p) -> bool:
	if not (p is Dictionary):
		return false
	return (p.get("lhx", 0.0) < -1.2) or (p.get("rhx", 0.0) < -1.2) or absf(p.get("lhz", 0.0)) > 1.0 or absf(p.get("rhz", 0.0)) > 1.0


static func compile(d: Dictionary) -> Dictionary:
	var g := Pose.with(GG, d.guard)
	var P := func(o) -> PackedFloat32Array: return Pose.with(g, o)
	var crouch: PackedFloat32Array = P.call(SYS.crouch)
	var pose := {
		guard = g, crouch = crouch, block = P.call(SYS.block), cblock = Pose.with(crouch, SYS.cblockArms),
		hitH = P.call(SYS.hitH), hitM = P.call(SYS.hitM), hitC = Pose.with(crouch, SYS.hitCArms),
		side = P.call(SYS.side), dash = P.call(SYS.dash), bdash = P.call(SYS.bdash), grab = P.call(SYS.grab), lift = P.call(SYS.lift),
		knee = P.call(Z.kneeR), air = Pose.with(GG, SYS.air), down = Pose.with(GG, SYS.down),
		win = Pose.with(g, d.win if d.has("win") else SYS.win),
	}
	var all: Dictionary = d.moves.duplicate()
	var th := {n = d.throwName, s = 12, a = 2, r = 26, d = 30, l = "throw", throw = 1, rg = 0.9, p = SYS.grab}
	if d.has("throwOpts"):
		th.merge(d.throwOpts, true)
	all["12"] = th
	all["34"] = {n = d.surge.n, s = 16, a = 4, r = 40, d = 45, l = "mid", kd = 1, surge = 1, armor = 1, blk = -20, rg = 1.3, mv = 0.03,
		w = d.surge.get("w", SYS.surgeW), p = d.surge.p}
	var moves := {}
	for k in all:
		var s: Dictionary = all[k]
		var m := Move.new()
		m.key = k
		m.name = s.get("n", k)
		m.s = int(s.get("s", 0)); m.a = int(s.get("a", 0)); m.r = int(s.get("r", 0))
		m.dmg = float(s.get("d", 0))
		m.lvl = s.get("l", "mid")
		m.hit = s.get("hit", null)
		m.blk = s.get("blk", null)
		m.range = float(s.get("rg", 1.15 if _is_kick(s.get("p")) else 1.02))
		m.push = float(s.get("push", 0.0))
		m.move = float(s.get("mv", 0.012 if "," in k else 0.0))
		m.back = float(s.get("bk", 0.0))
		m.next = s.get("next", {}) if s.get("next") != null else {}
		m.auto = s.get("auto", "")
		m.launch = _b(s, "launch"); m.kd = _b(s, "kd"); m.homing = _b(s, "hom"); m.armor = _b(s, "armor")
		m.low = _b(s, "low"); m.jump = _b(s, "jump"); m.is_throw = _b(s, "throw"); m.cmd_throw = _b(s, "cmd")
		m.throw_type = s.get("tt", "over")
		m.to_stance = s.get("st", "")
		m.trans = _b(s, "trans"); m.sig = _b(s, "sig"); m.surge = _b(s, "surge"); m.ch_launch = _b(s, "chl"); m.hidden = _b(s, "hidden")
		if s.has("keys"):
			for kf in s.keys:
				m.track.append([int(kf[0]), P.call(kf[1]), 0])
		else:
			# Curves: 0 = ease in-out, 1 = ease out (snappy strike), 2 = ease in.
			var strike: PackedFloat32Array = P.call(s.p)
			if s.has("w"):
				m.track.append([maxi(1, roundi(m.s * 0.55)), P.call(s.w), 0])
			elif m.s >= 6:
				# Automatic anticipation: pull slightly away from the strike before it fires.
				m.track.append([maxi(1, roundi(m.s * 0.45)), Pose.lerp_p(g, strike, -0.22), 0])
			m.track.append([maxi(1, m.s), strike, 1])
			if m.a > 1:
				m.track.append([m.s + m.a - 1, strike, 0])
			if m.r >= 8 and not m.is_throw:
				# Follow-through: carry a little past the strike, then settle back.
				m.track.append([m.s + m.a + maxi(2, roundi(m.r * 0.22)), Pose.lerp_p(g, strike, 1.1), 1])
		m.end = m.s + m.a + m.r
		m.limb = _strike_limb(s.get("p"))
		moves[k] = m
	_add_move_set_extras(moves)
	var stances := {}
	if d.has("stances"):
		for k in d.stances:
			var st: Dictionary = d.stances[k]
			stances[k] = {name = st.name, pose = P.call(st.p), dur = int(st.dur), low = _b(st, "low")}
	var C := {
		id = d.id, name = d.name, title = d.title, origin = d.origin, style = d.style, diff = int(d.diff),
		scale = float(d.scale), speed = float(d.speed), power = float(d.power), hp = float(d.hp),
		side_bonus = float(d.get("sideBonus", 1.0)), quote = d.quote, look = d.look,
		surge_name = d.surge.n, pose = pose, moves = moves, stances = stances,
		accent = Color.hex((int(d.look.accent) << 8) | 0xff),
	}
	C.ai = ai_profile(C)
	return C


## Everyone gets running attacks (dash, keep holding forward, then a button) and jump attacks (hold up, then a button).
## They borrow a keyframed track from the fighter's own moves as a fallback; the Mixamo clip (picked by name) does the rest.
static func _add_move_set_extras(moves: Dictionary) -> void:
	var punch: Move = moves.get("2", moves.get("1"))
	var kick: Move = moves.get("4", moves.get("3", punch))
	var add := func(key: String, ref: Move, o: Dictionary) -> void:
		if moves.has(key) or ref == null: return
		var m := Move.new()
		m.key = key; m.name = o.n
		m.s = o.s; m.a = o.a; m.r = o.r; m.dmg = o.d; m.lvl = o.get("l", "mid")
		m.range = o.get("rg", 1.1); m.move = o.get("mv", 0.0); m.push = o.get("push", 0.0)
		m.kd = o.get("kd", false); m.launch = o.get("launch", false); m.jump = o.get("jump", false)
		m.is_throw = o.get("throw", false); m.throw_type = o.get("tt", "over")
		m.blk = o.get("blk", null); m.limb = o.get("limb", ref.limb)
		for k in ref.track: m.track.append([int(k[0] * float(m.s) / maxf(1.0, ref.s)), k[1], k[2] if k.size() > 2 else 0])
		m.end = m.s + m.a + m.r
		moves[key] = m
	# powers: BLUE = 1+3 (the Surge Art, also 3+4), FINAL = 2+4 (only at low health)
	if moves.has("34") and not moves.has("13"): moves["13"] = moves["34"]
	add.call("24", punch, {n = "FINAL POWER", s = 10, a = 4, r = 44, d = 0, rg = 1.35, mv = 0.05, blk = -24, limb = "rh"})
	if moves.has("24"):
		(moves["24"] as Move).final = true; (moves["24"] as Move).armor = true
	# running
	add.call("run1", punch, {n = "Running Elbow", s = 12, a = 3, r = 20, d = 15, kd = true, rg = 1.15, mv = 0.05, blk = -10, limb = "rh"})
	add.call("run2", punch, {n = "Spear Tackle", s = 13, a = 3, r = 28, d = 24, rg = 1.05, mv = 0.06, throw = true, tt = "takedown"})
	add.call("run3", kick, {n = "Running Dropkick", s = 15, a = 4, r = 30, d = 22, kd = true, jump = true, rg = 1.45, mv = 0.05, blk = -16, limb = "rf"})
	add.call("run4", kick, {n = "Running Flying Knee", s = 13, a = 4, r = 22, d = 17, launch = true, rg = 1.15, mv = 0.06, blk = -14, limb = "rk"})
	# in the air
	add.call("j1", punch, {n = "Diving Elbow", s = 8, a = 5, r = 12, d = 13, l = "mid", rg = 1.1, limb = "rh"})
	add.call("j2", punch, {n = "Diving Elbow", s = 8, a = 5, r = 12, d = 14, l = "mid", rg = 1.1, limb = "rh"})
	add.call("j3", kick, {n = "Jump Kick", s = 9, a = 6, r = 14, d = 16, l = "mid", rg = 1.3, limb = "lf"})
	add.call("j4", kick, {n = "Jump Kick", s = 10, a = 6, r = 16, d = 18, l = "mid", kd = true, rg = 1.35, limb = "lf"})


static func _strike_limb(p) -> String:
	if not (p is Dictionary): return ""
	var g := func(k: String) -> float: return float(p.get(k, 0.0))
	var legs := {"lk": g.call("lk") > 1.9 and g.call("lhx") < -1.5, "rk": g.call("rk") > 1.9 and g.call("rhx") < -1.5}
	if legs.lk: return "lk"
	if legs.rk: return "rk"
	var lleg := maxf(-g.call("lhx"), absf(g.call("lhz")))
	var rleg := maxf(-g.call("rhx"), absf(g.call("rhz")))
	if maxf(lleg, rleg) > 1.2:
		return "lf" if lleg > rleg else "rf"
	var larm := maxf(-g.call("lsx"), absf(g.call("lsz")))
	var rarm := maxf(-g.call("rsx"), absf(g.call("rsz")))
	if maxf(larm, rarm) > 1.0:
		return "lh" if larm > rarm else "rh"
	return ""


static func ai_profile(C: Dictionary) -> Dictionary:
	var roots: Array = []
	for m in C.moves.values():
		if not m.hidden and not m.trans and not ("," in m.key) and not (":" in m.key) and m.key != "34":
			roots.append(m)
	var ok := func(m) -> bool: return not m.key.begins_with("ws")
	return {
		pokes = roots.filter(func(m): return ok.call(m) and m.s <= 13 and (m.blk == null or m.blk >= -4) and m.lvl != "low" and not m.is_throw),
		mids = roots.filter(func(m): return ok.call(m) and m.lvl == "mid" and not m.launch and not m.is_throw),
		lows = roots.filter(func(m): return ok.call(m) and m.lvl == "low"),
		launch = roots.filter(func(m): return m.launch),
		heavy = roots.filter(func(m): return ok.call(m) and (m.kd or m.dmg >= 18) and not m.is_throw),
		throws = roots.filter(func(m): return m.is_throw),
		juggle = roots.filter(func(m): return ok.call(m) and not m.key.begins_with("ff") and m.s <= 16 and m.lvl != "low" and not m.is_throw and not m.jump),
		stance = roots.filter(func(m): return m.to_stance != ""),
		sig = roots.filter(func(m): return m.sig),
	}


## Combo trials built from the fighter's own moves: their longest string, a launcher juggle,
## and a while-standing (or signature) juggle.
static func trials(C: Dictionary) -> Array:
	var M: Dictionary = C.moves
	var out: Array = []
	var best: Array = []
	for m in M.values():
		if m.hidden or "," in m.key or ":" in m.key or m.next.is_empty(): continue
		var chain := [m.key]
		var cur: Move = m
		while not cur.next.is_empty():
			var nk: String = cur.next.values()[cur.next.size() - 1]
			cur = M[nk]
			chain.append(nk)
		if chain.size() > best.size(): best = chain
	if best.size() >= 2:
		out.append({name = "String", keys = best})
	# Juggle follow-up = the fighter's own jab string (1 -> 1,x -> 1,x,y), up to three hits.
	var follow := ["1"]
	var cur: Move = M["1"]
	while not cur.next.is_empty() and follow.size() < 3:
		var nk: String = cur.next.values()[cur.next.size() - 1]
		follow.append(nk)
		cur = M[nk]
	if follow.size() == 1:
		follow.append("2")
	var launcher: Move = M.get("df2") if M.has("df2") and M["df2"].launch else null
	if launcher == null:
		for m in M.values():
			if m.launch and not m.hidden and not ":" in m.key and not m.key.begins_with("ws") and not m.key.begins_with("ff"):
				launcher = m; break
	if launcher != null:
		out.append({name = "Launcher Juggle", keys = [launcher.key] + follow})
	var opener: Move = null
	for m in M.values():
		if m.launch and m.key.begins_with("ws"): opener = m
	if opener == null:
		for m in M.values():
			if m.launch and m.sig: opener = m
	if opener != null:
		out.append({name = "While-Standing Juggle" if opener.key.begins_with("ws") else "Signature Juggle", keys = [opener.key] + follow.slice(0, 2)})
	return out


## Arcade bosses fight in a stronger form: more health, harder hits, the boss-level CPU and a pulsing aura.
const BOSS_FORM := {
	"mini": {hp = 1.2, power = 1.1, lv = 2, banner = "MINI BOSS"},
	"bonus": {hp = 1.3, power = 1.15, lv = 2, banner = "BONUS BOSS"},
	"final": {hp = 1.6, power = 1.3, lv = 3, banner = "FINAL BOSS"},
}


static func boss_form(C: Dictionary) -> Dictionary:
	var f: Dictionary = BOSS_FORM.get(C.get("boss", ""), {})
	if f.is_empty(): return C
	var B := C.duplicate()   # moves are shared; only the numbers change
	B.hp = C.hp * f.hp
	B.power = C.power * f.power
	B.boss_form = f.banner
	return B


static func boss_of(kind: String) -> Dictionary:
	for C in ROSTER:
		if C.get("boss", "") == kind: return C
	return {}


static func by_id(id: String) -> Dictionary:
	for C in ROSTER:
		if C.id == id:
			return C
	# a base style name ("kael", "bastion", ...) means the first fighter built on that style
	for C in ROSTER:
		if C.arch == id:
			return C
	return ROSTER[0]
