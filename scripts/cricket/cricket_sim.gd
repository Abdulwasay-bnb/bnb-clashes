extends RefCounted
## BNB Office Cricket: the rules, no visuals. A Super Over: each side bats one over (6 legal balls or 2 wickets),
## then they swap; most runs wins, a tie means another super over. Runs on the host (or locally); guests mirror it.
##
## A ball: the bowler picks a delivery (pace / spin / yorker / bouncer), a line and stops an accuracy meter.
## The batter presses at the moment the ball reaches them (timing = press time - arrival time, measured on the
## batter's own screen so online lag doesn't matter), with a direction (off / straight / leg) and ground or loft.
## Timing quality x delivery x shot -> dot, 1, 2, 4, 6, bowled, caught, caught behind.
##
## Pitch coordinates: the batter's crease at z = -10, the bowler releases at z = +9.8; x is across the pitch
## (+x = the batter's off side).

const DELIVERIES := {
	"pace": {name = "PACE", t = 0.78, zb = -3.6, h = 0.95, drift = 0.0},
	"spin": {name = "SPIN", t = 1.06, zb = -5.6, h = 0.7, drift = 0.28},
	"yorker": {name = "YORKER", t = 0.8, zb = -9.4, h = 0.16, drift = 0.0},
	"bouncer": {name = "BOUNCER", t = 0.82, zb = 1.4, h = 1.75, drift = 0.0},
}
const KINDS := ["pace", "spin", "yorker", "bouncer"]
const BALLS := 6
const WICKETS := 2
const CREASE_Z := -10.0
const RELEASE := Vector3(0.0, 2.15, 9.8)
const WAIT_BAT := 0.55        # how long after the ball arrives the host waits for the batter's press
const ONLINE_GRACE := 0.45    # plus this for a batter on another device
const TURN_TIME := 25.0       # online: an idle bowler's ball is bowled for them

class Team:
	var C: Dictionary
	var human := false
	var slot := -1             # online player index (0 = host); local pass & play: -2
	var runs := 0
	var wkts := 0
	var balls := 0             # legal balls faced this innings
	var log: Array = []        # this innings, ball by ball: "0" "1" "2" "4" "6" "W" "wd"
	var total := 0             # across super overs (for ties)

var sides: Array = []
var innings := 0              # 0, 1 = the first super over; 2, 3 = a tie-break super over...
var bat_first := 0
var phase := "toss"           # toss / setup / runup / flight / result / break / done
var t := 0.0                  # time in this phase
var ball_no := 0              # bumps every delivery (guests restart their flight clock on a new one)
var d: Dictionary = {}        # this delivery: kind, line, q, T, zb, h, drift, bad, wide
var res: Dictionary = {}      # this ball's result: runs, out, how, dir, loft, timing, text
var press: Dictionary = {}    # the batter's press: off (s), dir (-1 / 0 / 1), loft
var target := -1              # runs needed to win in the second innings of an over (-1 = first innings)
var winner := -1
var events: Array = []
var rng := RandomNumberGenerator.new()
var rev := 0
var remote_bat := false       # the batter plays on another device (host waits a little longer)
var skill := 1.0


func setup(people: Array, seed: int) -> void:
	rng.seed = seed
	for k in 2:
		var p: Dictionary = people[k] if k < people.size() else people[0]
		var s := Team.new()
		s.C = p.C; s.human = bool(p.get("human", false)); s.slot = int(p.get("slot", -1))
		sides.append(s)
	bat_first = rng.randi() % 2
	phase = "toss"; t = 0.0
	events.append(["toss", bat_first])
	rev += 1


func batting() -> int: return (bat_first + innings) % 2
func bowling() -> int: return 1 - batting()
func bat_side() -> Team: return sides[batting()]
func bowl_side() -> Team: return sides[bowling()]


func update(dt: float) -> void:
	t += dt
	match phase:
		"toss":
			if t > 2.2: _to("setup")
		"setup":
			if not bowl_side().human and t > 0.9: bowl(_cpu_kind(), rng.randf_range(-0.35, 0.35), _cpu_meter())
			elif bowl_side().human and bowl_side().slot >= 0 and t > TURN_TIME: bowl(_cpu_kind(), 0.0, 0.5)
		"runup":
			if t > 1.25:
				_to("flight")
				events.append(["release", ball_no])
				if not bat_side().human: press = _cpu_press()
		"flight":
			var T: float = d.T
			var limit := T + WAIT_BAT + (ONLINE_GRACE if remote_bat else 0.0)
			if not press.is_empty() and (t >= T + float(press.off) or t >= limit):
				_resolve()
			elif t >= limit:
				_resolve()
		"result":
			if t > (3.4 if res.get("runs", 0) == 6 or res.get("out", false) else 2.6): _next_ball()
		"break":
			# pass & play waits for the next batter to tap; otherwise a short pause
			var local_both: bool = sides[0].human and sides[1].human and sides[0].slot == -2
			if not local_both and t > 4.0: cont()


func _to(p: String) -> void:
	phase = p; t = 0.0; rev += 1


## Pass & play: the next batter is ready.
func cont() -> void:
	if phase != "break": return
	_to("setup")


# ---------------------------------------------------------------- bowling
## The bowler's choice: delivery kind, line (-1 .. 1 across the stumps), meter (0 .. 1, 0.5 = perfect).
func bowl(kind: String, line: float, meter: float) -> void:
	if phase != "setup" or not DELIVERIES.has(kind): return
	var D: Dictionary = DELIVERIES[kind]
	var q := clampf(1.0 - absf(meter - 0.5) * 2.0, 0.0, 1.0)
	var L := clampf(line, -1.0, 1.0) * 0.55 + (1.0 - q) * rng.randf_range(-0.45, 0.45)
	d = {kind = kind, line = L, q = q, T = float(D.t), zb = float(D.zb), h = float(D.h), drift = float(D.drift) * (1.0 if rng.randf() < 0.5 else -1.0),
		bad = q < 0.32, wide = false}
	if d.bad:
		match kind:
			"yorker": d.zb = -10.6; d.h = 0.95          # full toss
			"bouncer": d.h = 2.35                        # sails over the head
			"pace": d.zb = -1.5; d.line = L + 0.45 * signf(L if L != 0.0 else 1.0)   # short and wide
			"spin": d.zb = -7.8                          # half-volley
	if absf(float(d.line)) > 0.95 or float(d.h) > 2.25: d.wide = true
	# the speed gun: quick ones 130-150 km/h, spin in the 80s; a well-timed release adds a few
	d.kmh = int({"pace": 134, "spin": 82, "yorker": 138, "bouncer": 140}[kind] + q * 10.0 + rng.randf_range(-3.0, 3.0))
	ball_no += 1
	press = {}
	res = {}
	_to("runup")
	events.append(["bowl", ball_no, kind])


func _cpu_kind() -> String:
	var r := rng.randf()
	return "pace" if r < 0.38 else ("spin" if r < 0.6 else ("yorker" if r < 0.8 else "bouncer"))


func _cpu_meter() -> float:
	return 0.5 + rng.randf_range(-0.28, 0.28) / skill


## Where the ball is t seconds after release (it carries on past the batter toward the keeper).
static func ball_pos(dv: Dictionary, tt: float) -> Vector3:
	if dv.is_empty(): return RELEASE
	var T: float = dv.T
	var line: float = dv.line
	var zb: float = dv.zb
	var drift: float = dv.drift
	var Tb := T * (RELEASE.z - zb) / (RELEASE.z - CREASE_Z)
	var bounce := Vector3(line * 0.6, 0.0, zb)
	if tt <= Tb:
		var s := clampf(tt / maxf(0.01, Tb), 0.0, 1.0)
		var p := RELEASE.lerp(bounce, s)
		p.y = RELEASE.y * (1.0 - s) + 0.35 * s * (1.0 - s)
		return p
	var s2 := (tt - Tb) / maxf(0.01, T - Tb)
	var arrive := Vector3(line * 0.6 + drift, float(dv.h), CREASE_Z)
	var p2 := bounce.lerp(arrive, s2)
	p2.y = float(dv.h) * minf(s2, 1.0) + 0.5 * s2 * (1.0 - s2) * (2.0 if dv.kind == "bouncer" else 1.0)
	if s2 > 1.0: p2.y = maxf(0.05, float(dv.h) - (s2 - 1.0) * 0.6)
	return p2


# ---------------------------------------------------------------- batting
## The batter's press: off = press time - arrival time (s, negative = early), dir -1 off / 0 straight / 1 leg, loft.
func bat(off: float, dir: int, loft: bool) -> void:
	if phase != "flight" or not press.is_empty(): return
	press = {off = clampf(off, -1.5, 1.5), dir = clampi(dir, -1, 1), loft = loft}


func _cpu_press() -> Dictionary:
	if rng.randf() < 0.1: return {}   # leaves it
	var spread := 0.11 / skill
	var line: float = d.line
	var dir := 0 if absf(line) < 0.2 else (-1 if line > 0.0 else 1)
	if rng.randf() < 0.25: dir = [-1, 0, 1][rng.randi() % 3]
	return {off = rng.randf_range(-spread, spread) + rng.randf_range(-0.03, 0.03), dir = dir, loft = rng.randf() < (0.5 if d.bad else 0.3)}


static func timing_of(off: float) -> int:
	var a := absf(off)
	if a < 0.045: return 0   # perfect
	if a < 0.11: return 1    # good
	if a < 0.19: return 2    # edge
	return 3                 # miss


const TIMING_NAMES := ["PERFECT", "GOOD", "EDGED", "MISSED"]


func _resolve() -> void:
	var s := bat_side()
	var line: float = d.line
	var kind: String = d.kind
	var r := {runs = 0, out = false, how = "", dir = 0, loft = false, timing = 3, text = ""}
	if d.wide:
		r.runs = 1; r.how = "wide"; r.text = "WIDE"
	elif press.is_empty():
		# no shot: straight ones can hit the stumps
		var straight := absf(line) < 0.3 and kind != "bouncer"
		var p_bowled := {"yorker": 0.6, "pace": 0.4, "spin": 0.3}.get(kind, 0.0) if straight else 0.0
		if rng.randf() < p_bowled: r.out = true; r.how = "bowled"
	else:
		var tq := timing_of(float(press.off))
		var dir: int = press.dir
		var loft: bool = press.loft
		r.dir = dir; r.loft = loft
		# a bad ball is easier, a good yorker harder to get under, the wrong direction makes it harder
		if d.bad and tq > 0: tq -= 1
		if kind == "yorker" and not d.bad and loft and tq < 3: tq += 1
		var side_of := 0 if absf(line) < 0.2 else (-1 if line > 0.0 else 1)
		if side_of != 0 and dir == -side_of and tq < 3: tq += 1
		r.timing = tq
		var x := rng.randf()
		match tq:
			0:
				if loft: r.runs = 6 if x < (0.82 if kind == "bouncer" else 0.72) else 4
				else: r.runs = 4 if x < 0.65 else (3 if x < 0.75 else 2)
			1:
				if loft:
					if x < 0.22: r.runs = 6
					elif x < 0.6: r.runs = 4
					elif x < 0.8: r.out = true; r.how = "caught"
					else: r.runs = 2
				else: r.runs = 4 if x < 0.22 else (2 if x < 0.55 else 1)
			2:
				if loft:
					if x < 0.55: r.out = true; r.how = "caught"
					else: r.runs = 1 if x < 0.85 else 2
				else:
					if x < 0.2: r.out = true; r.how = "caught behind"
					else: r.runs = 0 if x < 0.55 else 1
			_:
				var straight := absf(line) < 0.3 and kind != "bouncer"
				if straight and rng.randf() < {"yorker": 0.65, "pace": 0.45, "spin": 0.35}.get(kind, 0.3): r.out = true; r.how = "bowled"
	# score it
	if r.how == "wide":
		s.runs += 1; s.log.append("wd")
	else:
		s.balls += 1
		if r.out: s.wkts += 1; s.log.append("W")
		else: s.runs += int(r.runs); s.log.append(str(r.runs))
	r.text = _comment(r)
	res = r
	_to("result")
	events.append(["result", ball_no, int(r.runs), bool(r.out), String(r.how), int(r.timing), int(r.dir), bool(r.loft)])


func _comment(r: Dictionary) -> String:
	var kind: String = d.kind
	var del: String = {"pace": "Quick and on a length", "spin": "Tossed up, spinning", "yorker": "Full and fast at the toes",
		"bouncer": "Short, climbing at the throat"}[kind]
	if d.bad: del = {"pace": "Short and wide", "spin": "A juicy half-volley", "yorker": "A full toss!", "bouncer": "Way over the head"}[kind]
	var where: String = ["through the covers", "straight down the ground", "over midwicket"][int(r.dir) + 1]
	if r.how == "wide": return del + "... called WIDE. A free run."
	if r.out:
		match String(r.how):
			"bowled": return del + "... and it's crashed into the stumps! BOWLED!"
			"caught": return del + "... skied it... and it's taken! CAUGHT!"
			_: return del + "... a thin edge, and the keeper holds on!"
	match int(r.runs):
		6: return del + "... launched %s for a massive SIX!" % where.replace("through", "over")
		4: return del + "... cracked %s for FOUR!" % where
		3, 2: return del + "... worked %s, they come back for %d." % [where, r.runs]
		1: return del + "... nudged %s for a single." % where
	return del + "... defended. Dot ball." if not press.is_empty() else del + "... left alone. Dot ball."


func _next_ball() -> void:
	var s := bat_side()
	var chase_won := target >= 0 and s.runs >= target
	if s.balls >= BALLS or s.wkts >= WICKETS or chase_won:
		_end_innings()
	else:
		_to("setup")


func _end_innings() -> void:
	var s := bat_side()
	s.total += s.runs
	events.append(["innings", batting(), s.runs, s.wkts])
	if innings % 2 == 0:
		target = s.runs + 1
		innings += 1
		_reset_side(bat_side())
		_to("break")
		return
	# both have batted this over
	var a: Team = sides[bat_first]
	var b: Team = sides[1 - bat_first]
	if a.runs == b.runs:
		events.append(["tie"])
		innings += 1
		target = -1
		_reset_side(bat_side())
		_to("break")
		return
	winner = bat_first if a.runs > b.runs else 1 - bat_first
	events.append(["done", winner])
	_to("done")


func _reset_side(s: Team) -> void:
	s.runs = 0; s.wkts = 0; s.balls = 0; s.log = []


## For the HUD: runs still needed and balls left (chase only).
func need() -> Array:
	if target < 0: return []
	var s := bat_side()
	return [maxi(0, target - s.runs), BALLS - s.balls]


# ---------------------------------------------------------------- snapshot (multiplayer)
func snapshot() -> Dictionary:
	var ss := []
	for s in sides: ss.append([s.runs, s.wkts, s.balls, s.log.duplicate(), s.total])
	return {ss = ss, inn = innings, bf = bat_first, ph = phase, t = snappedf(t, 0.01), bn = ball_no, d = d.duplicate(), r = res.duplicate(),
		tg = target, w = winner, rev = rev}


func apply(sn: Dictionary) -> void:
	var ss: Array = sn.ss
	for k in mini(sides.size(), ss.size()):
		var s: Team = sides[k]
		var a: Array = ss[k]
		s.runs = int(a[0]); s.wkts = int(a[1]); s.balls = int(a[2]); s.log = (a[3] as Array).duplicate(); s.total = int(a[4])
	innings = int(sn.inn); bat_first = int(sn.bf); phase = String(sn.ph); t = float(sn.t); ball_no = int(sn.bn)
	d = (sn.d as Dictionary).duplicate(); res = (sn.r as Dictionary).duplicate()
	if d.has("T"):   # JSON turns numbers into floats; keep bools as bools
		d.wide = bool(d.get("wide", false)); d.bad = bool(d.get("bad", false))
	target = int(sn.tg); winner = int(sn.w); rev = int(sn.rev)
