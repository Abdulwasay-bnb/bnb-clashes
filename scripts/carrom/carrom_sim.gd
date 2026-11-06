extends RefCounted
## BNB Carrom: the rules and the physics, no visuals. Runs on the host (or locally); guests mirror its state.
## Board units are centimetres, origin at the centre, playfield 74 x 74. Discs slide with friction, bounce off
## each other (striker heavier) and the cushions, and drop when their centre reaches a corner pocket.
##
## Seats: 2 players sit opposite (sides 0 and 2: white v black); 4 players: sides 0 & 2 are team WHITE,
## 1 & 3 team BLACK; 3 players: sides 0 & 2 are WHITE (a team of two), side 1 plays BLACK alone.
## Rules (simplified standard): pocket your own coin (or the queen) -> shoot again; pocket the striker -> foul:
## one of your pocketed coins goes back to the centre and the turn passes; an opponent's coin you pocket counts
## for them; the queen must be covered by pocketing one of your coins in the same or the next shot, else she
## goes back to the centre. A team wins when all 9 of its coins are pocketed and the queen is covered (by
## anyone); finish your coins while the queen is still uncovered and you lose the board.

const H := 37.0                 # half the playfield
const RC := 1.6                 # coin radius
const RS := 2.1                 # striker radius
const MC := 1.0                 # coin mass
const MS := 2.6                 # striker mass
const POCKET := Vector2(34.6, 34.6)
const POCKET_R := 2.3
const B := 25.3                 # distance from the centre to a baseline
const U_MAX := 23.5             # striker slides along the baseline in [-U_MAX, U_MAX]
const MAXV := 420.0             # full-power striker speed, cm/s
const FRICTION := 150.0         # cm/s^2
const E_DISC := 0.9
const E_WALL := 0.68
const SUB := 8
const DT := 1.0 / 60.0
const STRIKER := 19
const WHITE := 0
const BLACK := 1
const QUEEN := 2
const TURN_TIME := 25.0         # online: an idle player's shot is taken for them
const TEAM_NAMES := ["WHITE", "BLACK"]

class Player:
	var side := 0                # 0..3 round the board
	var team := 0                # 0 white, 1 black
	var C: Dictionary
	var human := false
	var slot := -1               # online seat (0 = host); local pass & play: -2

var players: Array = []
var turn := 0
var phase := "aim"              # aim / roll / done
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var kind := PackedInt32Array()  # 0 white, 1 black, 2 queen, 3 striker
var live: Array = []
var pocketed := [0, 0]          # own coins pocketed per team
var queen := "board"            # board / pending / covered
var queen_team := -1
var winner := -1
var aim := [0.0, 0.0, 0.0]      # current shooter: [u along the baseline, absolute angle, power 0..1]
var shots := 0
var wait := 0.0                 # CPU think time
var idle := 0.0
var roll_t := 0.0
var shot_pots: Array = []       # kinds pocketed this shot
var striker_pot := false
var first_shot := true
var events: Array = []          # [kind, side, ...]
var rev := 0
var rng := RandomNumberGenerator.new()
var skill := 1.0                # CPU accuracy


## people: [{C, human, slot}] in seat order.
func setup(people: Array, seed := 1) -> void:
	rng.seed = seed
	var n := clampi(people.size(), 2, 4)
	var sides: Array = [[0, 2], [0, 1, 2], [0, 1, 2, 3]][n - 2]
	for k in n:
		var p := Player.new()
		p.side = sides[k]
		p.team = k if n == 2 else p.side % 2
		p.C = people[k].C; p.human = people[k].human; p.slot = int(people[k].slot)
		players.append(p)
	_rack()
	turn = 0
	aim = [0.0, _fwd_angle(cur().side), 0.0]
	wait = 1.0


func _rack() -> void:
	pos.resize(20); vel.resize(20); kind.resize(20); live.resize(20)
	var spots := [Vector2.ZERO]
	for k in 6: spots.append(Vector2.from_angle(k * PI / 3.0) * RC * 2.04)
	for k in 6: spots.append(Vector2.from_angle(k * PI / 3.0) * RC * 4.08)
	for k in 6: spots.append(Vector2.from_angle(PI / 6.0 + k * PI / 3.0) * RC * 2.0 * sqrt(3.0) * 1.02)
	var kinds := [QUEEN]
	for k in 6: kinds.append(WHITE if k % 2 == 0 else BLACK)
	for k in 12: kinds.append(WHITE if k % 2 == 0 else BLACK)
	for i in 19:
		pos[i] = spots[i]; vel[i] = Vector2.ZERO; kind[i] = kinds[i]; live[i] = true
	kind[STRIKER] = 3; live[STRIKER] = true; vel[STRIKER] = Vector2.ZERO
	pos[STRIKER] = base_point(0, 0.0)


func cur() -> Player:
	return players[turn]


static func radius(i: int) -> float:
	return RS if i == STRIKER else RC


## Where a side's baseline is: centre point, the direction along it (u), and "forward" (toward the middle).
static func side_axes(side: int) -> Array:
	var c := Vector2(0, B).rotated(side * PI / 2.0)
	var along := Vector2(1, 0).rotated(side * PI / 2.0)
	return [c, along, -c.normalized()]


static func base_point(side: int, u: float) -> Vector2:
	var ax := side_axes(side)
	return (ax[0] as Vector2) + (ax[1] as Vector2) * clampf(u, -U_MAX, U_MAX)


static func _fwd_angle(side: int) -> float:
	return (side_axes(side)[2] as Vector2).angle()


static func pockets() -> Array:
	return [Vector2(-POCKET.x, -POCKET.y), Vector2(POCKET.x, -POCKET.y), Vector2(POCKET.x, POCKET.y), Vector2(-POCKET.x, POCKET.y)]


## The striker can't sit on a coin: slide to the nearest free spot along the baseline.
func free_u(side: int, u: float) -> float:
	for d in range(0, 120):
		for sgn in [1.0, -1.0]:
			var t := clampf(u + sgn * d * 0.4, -U_MAX, U_MAX)
			var p := base_point(side, t)
			var ok := true
			for i in 19:
				if live[i] and p.distance_to(pos[i]) < RC + RS + 0.05: ok = false; break
			if ok: return t
	return u


# ---------------------------------------------------------------- turns
## The current shooter takes their shot: striker at u on the baseline, fired at angle (absolute) with power 0..1.
func shoot(u: float, ang: float, power: float) -> void:
	if phase != "aim": return
	var p := cur()
	u = free_u(p.side, u)
	pos[STRIKER] = base_point(p.side, u); live[STRIKER] = true
	vel[STRIKER] = Vector2.from_angle(ang) * clampf(power, 0.05, 1.0) * MAXV
	aim = [u, ang, power]
	phase = "roll"; roll_t = 0.0; idle = 0.0
	shot_pots.clear(); striker_pot = false
	shots += 1
	events.append(["shot", p.side, snappedf(power, 0.01)])
	rev += 1


func set_aim(u: float, ang: float, power: float) -> void:
	if phase != "aim": return
	aim = [clampf(u, -U_MAX, U_MAX), ang, clampf(power, 0.0, 1.0)]
	pos[STRIKER] = base_point(cur().side, aim[0])
	rev += 1


## Time passes: the discs roll (fixed 60 Hz steps), CPUs think, idle online players get a shot taken for them.
var _acc := 0.0
func update(dt: float) -> void:
	if phase == "done": return
	if phase == "roll":
		_acc += dt
		var n := 0
		while _acc >= DT and n < 8:
			_acc -= DT; n += 1
			step()
			if phase != "roll": break
		return
	_acc = 0.0
	var p := cur()
	if not p.human:
		wait -= dt
		if wait <= 0.0:
			var s := cpu_shot()
			shoot(s[0], s[1], s[2])
		return
	idle += dt
	if idle > TURN_TIME and p.slot >= 0:
		var s := cpu_shot()
		shoot(s[0], s[1], s[2])


## One 60 Hz physics tick. Returns when everything has stopped (then the shot is resolved).
func step() -> void:
	var h := DT / SUB
	for _s in SUB:
		_substep(h)
	roll_t += DT
	var moving := false
	for i in 20:
		if live[i] and vel[i].length_squared() > 0.09: moving = true; break
	if not moving or roll_t > 14.0:
		for i in 20: vel[i] = Vector2.ZERO
		_resolve()


var _mv: Array = []
func _substep(h: float) -> void:
	if _mv.size() != 20: _mv.resize(20)
	for i in 20:
		_mv[i] = false
		if not live[i]: continue
		var v: Vector2 = vel[i]
		var sp := v.length()
		if sp > 0.0:
			_mv[i] = true
			var ns := maxf(0.0, sp - FRICTION * h)
			if ns < 0.3: ns = 0.0
			v = v * (ns / sp)
			vel[i] = v
			pos[i] = pos[i] + v * h
		# pockets
		for pk in pockets():
			if pos[i].distance_to(pk) < POCKET_R:
				live[i] = false; vel[i] = Vector2.ZERO
				if i == STRIKER:
					striker_pot = true
				else:
					shot_pots.append(kind[i])
				events.append(["pot", cur().side, kind[i], i])
				break
		if not live[i]: continue
		# cushions
		var r := radius(i)
		var p: Vector2 = pos[i]
		for a in 2:
			if p[a] > H - r:
				p[a] = H - r
				if v[a] > 0.0: v[a] = -v[a] * E_WALL; _click(absf(v[a]))
			elif p[a] < -H + r:
				p[a] = -H + r
				if v[a] < 0.0: v[a] = -v[a] * E_WALL; _click(absf(v[a]))
		pos[i] = p; vel[i] = v
	# disc on disc
	for i in 20:
		if not live[i]: continue
		var mi_moving: bool = _mv[i]
		for j in range(i + 1, 20):
			if not live[j] or (not mi_moving and not _mv[j]): continue   # two resting discs can't collide
			var d: Vector2 = pos[j] - pos[i]
			var rr := radius(i) + radius(j)
			var dist2 := d.length_squared()
			if dist2 >= rr * rr or dist2 < 1e-8: continue
			var dist := sqrt(dist2)
			var nrm := d / dist
			var mi := MS if i == STRIKER else MC
			var mj := MS if j == STRIKER else MC
			var over := rr - dist
			pos[i] = pos[i] - nrm * over * (mj / (mi + mj))
			pos[j] = pos[j] + nrm * over * (mi / (mi + mj))
			var rv: float = (vel[j] - vel[i]).dot(nrm)
			if rv < 0.0:
				var jimp := -(1.0 + E_DISC) * rv / (1.0 / mi + 1.0 / mj)
				vel[i] = vel[i] - nrm * (jimp / mi)
				vel[j] = vel[j] + nrm * (jimp / mj)
				_click(-rv)


var _last_click := -1.0
func _click(strength: float) -> void:
	if strength < 20.0 or roll_t - _last_click < 0.06: return
	_last_click = roll_t
	events.append(["click", cur().side, snappedf(minf(strength / 300.0, 1.0), 0.01)])


## Everything stopped: apply the rules and decide who shoots next.
func _resolve() -> void:
	var p := cur()
	var own := p.team
	var again := false
	var foul := striker_pot
	var own_pots := 0
	var queen_now := shot_pots.has(QUEEN)
	for k in shot_pots:
		if k == QUEEN: continue
		pocketed[k] += 1            # coins always count for their owners
		if k == own: own_pots += 1
	if foul:
		events.append(["foul", p.side])
		_return_coin(own)
		if queen_now: _queen_back()
		elif queen == "pending" and queen_team == own: _queen_back()
	else:
		if queen == "pending" and queen_team == own:
			if own_pots > 0:
				queen = "covered"; events.append(["queen_cover", p.side, own])
			else:
				_queen_back()
		if queen_now:
			if own_pots > 0:
				queen = "covered"; queen_team = own; events.append(["queen_cover", p.side, own])
			else:
				queen = "pending"; queen_team = own; events.append(["queen_pot", p.side, own])
		again = own_pots > 0 or queen_now
	first_shot = false
	# a team that has pocketed all nine
	for t in 2:
		if pocketed[t] >= 9 and winner < 0:
			winner = t if queen == "covered" else 1 - t
			if queen != "covered": events.append(["queen_lost", p.side, t])
	if shots >= 500 and winner < 0:
		winner = 0 if pocketed[0] >= pocketed[1] else 1
	if winner >= 0:
		phase = "done"
		events.append(["win", p.side, winner])
		events.append(["done", 0])
		rev += 1
		return
	if again:
		events.append(["again", p.side])
	else:
		turn = (turn + 1) % players.size()
		events.append(["turn", cur().side])
	phase = "aim"; idle = 0.0
	wait = 0.9
	var u := free_u(cur().side, 0.0)
	aim = [u, _fwd_angle(cur().side), 0.0]
	pos[STRIKER] = base_point(cur().side, u); live[STRIKER] = true; vel[STRIKER] = Vector2.ZERO
	rev += 1


func _return_coin(team: int) -> void:
	if pocketed[team] <= 0: return
	for i in 19:
		if kind[i] == team and not live[i]:
			pocketed[team] -= 1
			_place_centre(i)
			events.append(["return", 0, team])
			return


func _queen_back() -> void:
	queen = "board"; queen_team = -1
	for i in 19:
		if kind[i] == QUEEN and not live[i]: _place_centre(i)
	events.append(["queen_back", 0])


func _place_centre(i: int) -> void:
	for ring in 30:
		for k in 12:
			var p := Vector2.from_angle(k * TAU / 12.0) * ring * RC * 1.1 if ring > 0 else Vector2.ZERO
			var ok := true
			for j in 20:
				if j != i and live[j] and p.distance_to(pos[j]) < RC + radius(j) + 0.1: ok = false; break
			if ok:
				pos[i] = p; vel[i] = Vector2.ZERO; live[i] = true
				return


func coins_left(team: int) -> int:
	return 9 - int(pocketed[team])


# ---------------------------------------------------------------- CPU
## The best shot for the current player: [u, angle, power]. Ghost-ball cuts of their coins into each pocket from
## a few striker spots on the baseline; the top few are checked with a quick rollout. A break on the first shot.
func cpu_shot() -> Array:
	var p := cur()
	var ax := side_axes(p.side)
	var fwd: Vector2 = ax[2]
	if first_shot:
		var u0 := rng.randf_range(-1.0, 1.0)
		var s0 := base_point(p.side, u0)
		return [u0, (Vector2.ZERO - s0).angle() + rng.randf_range(-0.01, 0.01), 1.0]
	var cands := []
	var targets := []
	for i in 19:
		if not live[i]: continue
		if kind[i] == p.team or (kind[i] == QUEEN and pocketed[p.team] > 0 and queen == "board"): targets.append(i)
	for i in targets:
		var c: Vector2 = pos[i]
		for pk in pockets():
			var to_pk: Vector2 = (pk - c)
			var dist_cp := to_pk.length()
			var dir_cp := to_pk / dist_cp
			if not _path_clear(c, pk, RC * 2.0, [i]): continue
			var ghost: Vector2 = c - dir_cp * (RC + RS)
			for k in 13:
				var u := -U_MAX + k * (U_MAX * 2.0 / 12.0)
				var s := base_point(p.side, u)
				if not _spot_free(s): continue
				var d: Vector2 = ghost - s
				var dl := d.length()
				if dl < 1.0: continue
				var dn := d / dl
				if dn.dot(fwd) < -0.2: continue   # no shooting backwards
				var cut := dn.dot(dir_cp)
				if cut < 0.3: continue
				if not _path_clear(s, ghost, RC + RS, [i]): continue
				var power := clampf(0.22 + (dl + dist_cp * 1.8 / maxf(cut, 0.4)) / 170.0, 0.2, 0.95)
				var score := cut * 2.0 - dl / 90.0 - dist_cp / 120.0 + (0.6 if kind[i] == QUEEN else 0.0)
				cands.append([score, u, dn.angle(), power])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var best: Array = []
	var best_val := -INF
	for c in cands.slice(0, 4):
		var val := _rollout(c[1], c[2], c[3])
		if val > best_val: best_val = val; best = c
	if best.is_empty():
		# nothing clean: smash into the nearest own coin to spread them
		var tgt := Vector2.ZERO
		var bd := INF
		for i in targets:
			if pos[i].length() < bd: bd = pos[i].length(); tgt = pos[i]
		var u1 := rng.randf_range(-12.0, 12.0)
		var s1 := base_point(p.side, u1)
		return [u1, (tgt - s1).angle(), 0.75]
	var err := 0.045 / skill   # human-ish: thin cuts often miss
	return [best[1], best[2] + rng.randf_range(-err, err) * 0.5, clampf(best[3] * rng.randf_range(0.9, 1.1), 0.15, 1.0)]


func _spot_free(s: Vector2) -> bool:
	for i in 19:
		if live[i] and s.distance_to(pos[i]) < RC + RS + 0.05: return false
	return true


func _path_clear(a: Vector2, b: Vector2, width: float, ignore: Array) -> bool:
	var ab := b - a
	var L := ab.length()
	if L < 0.01: return true
	var dn := ab / L
	for j in 19:
		if not live[j] or j in ignore: continue
		var t := clampf((pos[j] - a).dot(dn), 0.0, L)
		if (a + dn * t).distance_to(pos[j]) < width: return false
	return true


## Simulate a shot on a copy and score it: own coins pocketed good, striker in the pocket bad.
func _rollout(u: float, ang: float, power: float) -> float:
	var c = get_script().new()
	c.players = players; c.turn = turn; c.phase = "aim"
	c.pos = pos.duplicate(); c.vel = vel.duplicate(); c.kind = kind.duplicate(); c.live = live.duplicate()
	c.pocketed = pocketed.duplicate(); c.queen = queen; c.queen_team = queen_team; c.first_shot = false
	c.shoot(u, ang, power)
	var n := 0
	while c.phase == "roll" and n < 300:
		c._quick_step(); n += 1
	var val := 0.0
	var own: int = cur().team
	for k in c.shot_pots:
		if k == own: val += 1.0
		elif k == QUEEN: val += 0.7
		else: val -= 0.6
	if c.striker_pot: val -= 1.5
	return val


## Rollouts: a coarser step (3 substeps) and no rule resolution.
func _quick_step() -> void:
	var h := DT / 3.0
	for _s in 3: _substep(h)
	roll_t += DT
	var moving := false
	for i in 20:
		if live[i] and vel[i].length_squared() > 0.25: moving = true; break
	if not moving: phase = "aim"


# ---------------------------------------------------------------- snapshot (multiplayer)
func snapshot() -> Dictionary:
	var ps := []
	var lv := 0
	for i in 20:
		ps.append(snappedf(pos[i].x, 0.01)); ps.append(snappedf(pos[i].y, 0.01))
		if live[i]: lv |= 1 << i
	return {p = ps, lv = lv, pk = pocketed, q = queen, qt = queen_team, turn = turn, ph = phase, w = winner, rev = rev,
		aim = [snappedf(aim[0], 0.01), snappedf(aim[1], 0.001), snappedf(aim[2], 0.01)], idle = snappedf(idle, 0.1), sh = shots, fs = first_shot}


func apply(s: Dictionary) -> void:
	var ps: Array = s.p
	var lv := int(s.lv)
	for i in 20:
		pos[i] = Vector2(float(ps[i * 2]), float(ps[i * 2 + 1]))
		live[i] = (lv & (1 << i)) != 0
	pocketed = [int(s.pk[0]), int(s.pk[1])]
	queen = String(s.q); queen_team = int(s.qt); turn = int(s.turn); phase = String(s.ph); winner = int(s.w); rev = int(s.rev)
	aim = [float(s.aim[0]), float(s.aim[1]), float(s.aim[2])]
	idle = float(s.get("idle", 0.0)); shots = int(s.get("sh", 0)); first_shot = bool(s.get("fs", false))


## Headless: CPU v CPU to the end. Returns [winner, shots].
func play_out(max_shots := 600) -> Array:
	for p in players: p.human = false
	var guard := 0
	while phase != "done" and guard < 400000:
		guard += 1
		if phase == "roll": step()
		else:
			var s := cpu_shot()
			shoot(s[0], s[1], s[2])
			if shots > max_shots: break
		events.clear()
	return [winner, shots]
