extends RefCounted
## Tumble Tuesday rules, deterministic at 60 ticks/s with no physics engine: wobbly tumblers (capsules) on
## boxes and moving obstacles, a show of rounds (race / survive / team / final), eliminations, CPU tumblers.
## The host runs it; guests draw the host's snapshots. Moving obstacles depend only on the round tick.

const Maps = preload("res://scripts/tumble/tumble_maps.gd")

const DT := 1.0 / 60.0
const GRAV := 24.0
const JUMP_V := 8.6
const RUN := 6.8
const R := 0.42
const H := 1.6
const STEP := 0.45
const PH := {"intro": 150, "count": 180, "end": 150, "standings": 240}
const STATES := ["run", "air", "dive", "getup", "stumble", "out", "done"]

class P:
	var id := 0
	var C: Dictionary
	var human := -1
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var prev_pos := Vector3.ZERO
	var yaw := 0.0
	var state := "run"
	var t_state := 0
	var ground := false
	var alive := true         # still in the show
	var in_round := true      # playing this round (not yet qualified / out)
	var team := -1
	var cp := Vector3.ZERO
	var cp_z := -99.0
	var place := -1           # finishing order this round
	var on_plat := -1         # mover index under us
	var prev_jump := false
	var prev_dive := false
	var grab_t := 0
	var held_by := -1
	var slow := 0
	var landed := 0
	# bots
	var wp := 0
	var aim := Vector3.ZERO
	var skill := 1.0
	var lane := 0.0
	var think := 0
	var wait := 0
	var tile_goal := -1

var players: Array = []
var rng := RandomNumberGenerator.new()
var tick_n := 0
var rtick := 0
var rounds: Array = []         # map ids for the whole show (extended as the field shrinks)
var round_i := 0
var map: Dictionary = {}
var phase := "intro"
var phase_t := 0
var target := 0               # race: how many qualify  ·  survive: how many survive
var finished: Array = []      # ids in finishing order (this round)
var out_order: Array = []     # ids in elimination order (this round)
var tiles: Array = []         # crumble state per tile: 0 fine, >0 ticks to fall, -1 gone
var tubs: Array = []          # team round: [{pos, vel}]
var team_score := [0, 0]
var winner := -1
var history: Array = []       # [{map, qualified}]
var events: Array = []
var _sol_cache: Array = []
var _sol_t := -1.0
var _sol_valid := false


# ---------------------------------------------------------------- the show
func setup(people: Array, seed: int) -> void:
	rng.seed = seed
	for k in people.size():
		var p := P.new()
		p.id = k; p.C = people[k].C
		p.human = int(people[k].slot) if people[k].human else -1
		if p.human == -1 and people[k].human: p.human = -2
		p.skill = rng.randf_range(0.65, 1.15)
		players.append(p)
	_plan_next()
	_begin_round()


## The next round for the field that's left: races and survival while it's big, a team game when there
## are enough for two teams, then the final.
func _plan_next() -> void:
	var n := _alive_count()
	var used: Array = rounds.duplicate()
	var pick := func(pool: Array) -> String:
		var opts: Array = pool.filter(func(x): return not x in used)
		if opts.is_empty(): opts = pool.duplicate()
		return String(opts[rng.randi() % opts.size()])
	var r_count := rounds.size()
	if n <= 3 or (n <= 4 and r_count >= 2): rounds.append(pick.call(Maps.FINALS))
	elif r_count == 0 or (n > 9): rounds.append(pick.call(Maps.RACES))
	elif r_count == 1 and n > 6: rounds.append(pick.call(Maps.SURVIVALS))
	elif n >= 4 and not "mailroom" in used and n <= 8: rounds.append("mailroom")
	elif n > 4: rounds.append(pick.call(Maps.RACES + Maps.SURVIVALS))
	else: rounds.append(pick.call(Maps.FINALS))


func _alive_count() -> int:
	return players.filter(func(p): return p.alive).size()


func _begin_round() -> void:
	map = Maps.build(String(rounds[round_i]))
	rtick = 0
	_sol_valid = false
	phase = "intro"; phase_t = PH.intro
	finished.clear(); out_order.clear()
	tiles.clear()
	for t in map.tiles: tiles.append(0)
	tubs.clear()
	for t in map.tubs: tubs.append({pos = t, vel = Vector3.ZERO})
	team_score = [0, 0]
	var field: Array = players.filter(func(p): return p.alive)
	var n := field.size()
	match String(map.kind):
		"race": target = clampi(ceili(n * 0.72), 1, n - 1) if n > 1 else 1
		"survive": target = clampi(ceili(n * 0.62), 1, n - 1) if n > 1 else 1
		_: target = 1
	# teams: shuffle, then alternate
	var order: Array = field.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = order[i]; order[i] = order[j]; order[j] = tmp
	for k in order.size(): (order[k] as P).team = k % 2 if map.kind == "team" else -1
	# line up
	var cols := 4
	for k in order.size():
		var p: P = order[k]
		p.in_round = true; p.state = "run"; p.t_state = 0; p.place = -1; p.vel = Vector3.ZERO
		p.wp = 0; p.held_by = -1; p.grab_t = 0; p.slow = 0; p.tile_goal = -1; p.wait = 0; p.on_plat = -1; p.ground = true
		var sp: Vector3 = map.spawn
		var spread: Vector2 = map.spread
		if map.kind in ["survive", "final_survive"] and not map.tiles.is_empty():
			var ti: int = (k * 7 + rng.randi() % 3) % mini(map.tiles.size(), 49)
			sp = (map.tiles[ti][0] as Vector3) + Vector3(0, 0.25, 0)
		elif map.kind == "team":
			sp = Vector3(-7.5 + (k / 2) * 3.0, 0, (-6.0 if p.team == 1 else 6.0))
		elif map.id == "mopup":   # between the mop arms (which start along the x axis)
			var a := PI / 2.0 + PI * (k % 2) + (k / 2) * 0.42 - 1.0
			sp = Vector3(cos(a) * 6.0, 0, sin(a) * 6.0)
		else:
			sp += Vector3((k % cols - (cols - 1) / 2.0) * (spread.x / cols), 0, -(k / cols) * 1.6 + 1.6)
		p.pos = sp; p.prev_pos = sp
		p.cp = sp; p.cp_z = -99.0
		p.yaw = 0.0 if map.kind != "team" else (PI if p.team == 0 else 0.0)
		p.lane = rng.randf_range(-2.5, 2.5)
	for p in players:
		if not p.alive: p.in_round = false
	events.append(["round", Vector3.ZERO, round_i])


func _end_round() -> void:
	var field: Array = players.filter(func(p): return p.alive)
	var keep := {}
	match String(map.kind):
		"race":
			for id in finished: keep[id] = true
			if keep.is_empty():   # nobody made it: the furthest along go through
				var by: Array = field.duplicate()
				by.sort_custom(func(a, b): return a.pos.z > b.pos.z)
				for k in mini(target, by.size()): keep[by[k].id] = true
		"survive":
			for p in field:
				if p.state != "out": keep[p.id] = true
			# several fell at once: the last ones to go fill the remaining spots
			var k2 := out_order.size() - 1
			while keep.size() < target and k2 >= 0:
				keep[out_order[k2]] = true; k2 -= 1
		"team":
			var lose := 0 if team_score[0] < team_score[1] else (1 if team_score[1] < team_score[0] else rng.randi() % 2)
			for p in field:
				if p.team != lose: keep[p.id] = true
		"final_race", "final_survive":
			if winner < 0:
				var alive_now: Array = field.filter(func(p): return p.state != "out")
				if map.kind == "final_survive" and alive_now.size() >= 1: winner = alive_now[rng.randi() % alive_now.size()].id
				elif not out_order.is_empty(): winner = out_order[-1]
				else:
					var by: Array = field.duplicate()
					by.sort_custom(func(a, b): return a.pos.z + a.pos.y * 3.0 > b.pos.z + b.pos.y * 3.0)
					winner = by[0].id
			keep[winner] = true
	var q: Array = []
	for p in field:
		if keep.has(p.id): q.append(p.id)
		else:
			p.alive = false
			events.append(["elim", p.pos, p.id])
	history.append({map = map.id, qualified = q.size(), field = field.size()})
	events.append(["roundend", Vector3.ZERO, q.size()])


# ---------------------------------------------------------------- per tick
func tick(inputs: Dictionary) -> void:
	tick_n += 1
	events.clear()
	_sol_valid = false
	match phase:
		"intro", "count":
			phase_t -= 1
			for p in players:
				if p.in_round:
					p.prev_pos = p.pos
					_physics(p, {}, true)
			if phase_t <= 0:
				if phase == "intro":
					phase = "count"; phase_t = PH.count
				else:
					phase = "play"; phase_t = 0
					events.append(["go", Vector3.ZERO, 0])
		"play":
			rtick += 1
			phase_t += 1
			_tick_tiles()
			for p in players:
				p.prev_pos = p.pos
				if not p.in_round or p.state in ["out", "done"]: continue
				var inp: Dictionary = inputs.get(p.id, {}) if p.human != -1 else bot_input(p)
				_physics(p, inp, false)
				_rules(p)
			_push_players()
			if map.kind == "team": _tick_tubs()
			if _round_over():
				phase = "end"; phase_t = PH.end
				_end_round()
		"end":
			phase_t -= 1
			for p in players: p.prev_pos = p.pos
			if phase_t <= 0:
				if winner >= 0 or _alive_count() <= 1:
					if winner < 0:
						for p in players:
							if p.alive: winner = p.id
					phase = "over"; phase_t = 0
					events.append(["crowned", Vector3.ZERO, winner])
				else:
					phase = "standings"; phase_t = PH.standings
		"standings":
			phase_t -= 1
			if phase_t <= 0:
				round_i += 1
				if round_i >= rounds.size(): _plan_next()
				_begin_round()
		"over":
			phase_t += 1


func _round_over() -> bool:
	var playing: Array = players.filter(func(p): return p.in_round and not p.state in ["out", "done"])
	var secs := rtick * DT
	match String(map.kind):
		"race": return finished.size() >= target or playing.is_empty() or secs >= map.dur
		"survive":
			var standing: Array = players.filter(func(p): return p.in_round and p.state != "out")
			return standing.size() <= target or secs >= map.dur
		"team": return secs >= map.dur
		"final_race": return winner >= 0 or playing.is_empty() or secs >= map.dur
		"final_survive":
			var standing2: Array = players.filter(func(p): return p.in_round and p.state != "out")
			return standing2.size() <= 1 or secs >= map.dur
	return false


## Finish lines, checkpoints, falling out, the crown.
func _rules(p: P) -> void:
	if p.pos.y < map.fall_y:
		if map.kind in ["race", "final_race", "team"]:
			p.pos = p.cp + Vector3(rng.randf_range(-1.5, 1.5), 0.5, 0); p.vel = Vector3.ZERO; p.prev_pos = p.pos
			p.state = "getup"; p.t_state = 30
			events.append(["respawn", p.pos, p.id])
		else:
			p.state = "out"; out_order.append(p.id)
			events.append(["fall", p.pos, p.id])
		return
	if p.ground:
		for cp in map.checkpoints:
			if p.pos.z > float(cp[0]) and float(cp[0]) > p.cp_z:
				p.cp_z = float(cp[0]); p.cp = cp[1]
				events.append(["checkpoint", p.pos, p.id])
	if map.kind == "race" and (map.finish as AABB).has_point(p.pos + Vector3(0, 0.5, 0)):
		p.state = "done"; p.place = finished.size(); finished.append(p.id)
		events.append(["qual", p.pos, p.id])
	if map.kind == "final_race" and winner < 0 and p.pos.distance_to(map.crown) < 1.4:
		winner = p.id; p.state = "done"
		events.append(["crown", p.pos, p.id])


# ---------------------------------------------------------------- moving obstacles (pure functions of time)
static func wave(period: float, phase: float, t: float) -> float:
	return sin(TAU * (t / period + phase))


func mover_c(m: Dictionary, t: float) -> Vector3:
	return (m.c as Vector3) + (m.axis as Vector3) * float(m.amp) * wave(m.period, m.phase, t)


func pusher_c(m: Dictionary, t: float) -> Vector3:
	var out := maxf(0.0, wave(m.period, m.phase, t))
	out = minf(1.0, out * 1.6)
	return (m.c as Vector3) + (m.dir as Vector3) * float(m.amp) * out


func drop_open(d: Dictionary, t: float) -> float:   # 0 solid ... 1 fully tipped
	var f := fposmod(t / float(d.period) + float(d.phase), 1.0)
	var off: float = d.off
	if f < 1.0 - off: return 0.0
	return sin((f - (1.0 - off)) / off * PI)


func spin_angle(s: Dictionary, t: float) -> float:
	return float(s.phase) + float(s.speed) * t + 0.5 * float(s.accel) * t * t * signf(float(s.speed))


func ball_pos(b: Dictionary, t: float) -> Vector3:
	var f := fposmod(t / float(b.period) + float(b.phase), 1.0)
	return (b.a as Vector3).lerp(b.b, f)


func pend_pos(pd: Dictionary, t: float) -> Vector3:
	var a := float(pd.amp) * wave(pd.period, pd.phase, t)
	return (pd.pivot as Vector3) + Vector3(sin(a), -cos(a), 0) * float(pd.len)


func rt() -> float: return rtick * DT


## Everything you can stand on or bump into right now: [AABB, kind, index].
func solids(t: float) -> Array:
	if t == _sol_t and _sol_valid: return _sol_cache
	var out: Array = []
	for b in map.boxes: out.append([AABB((b[0] as Vector3) - (b[1] as Vector3) / 2.0, b[1]), "box", -1])
	for i in map.movers.size():
		var m: Dictionary = map.movers[i]
		out.append([AABB(mover_c(m, t) - (m.s as Vector3) / 2.0, m.s), "mover", i])
	for i in map.pushers.size():
		var m: Dictionary = map.pushers[i]
		out.append([AABB(pusher_c(m, t) - (m.s as Vector3) / 2.0, m.s), "pusher", i])
	for i in map.drops.size():
		var d: Dictionary = map.drops[i]
		if drop_open(d, t) < 0.25: out.append([AABB((d.c as Vector3) - (d.s as Vector3) / 2.0, d.s), "drop", i])
	for i in map.belts.size():
		var bl: Dictionary = map.belts[i]
		out.append([AABB((bl.c as Vector3) - (bl.s as Vector3) / 2.0, bl.s), "belt", i])
	for i in map.tiles.size():
		if tiles[i] >= 0: out.append([AABB((map.tiles[i][0] as Vector3) - (map.tiles[i][1] as Vector3) / 2.0, map.tiles[i][1]), "tile", i])
	_sol_cache = out; _sol_t = t; _sol_valid = true
	return out


# ---------------------------------------------------------------- tumbler physics
func _physics(p: P, inp: Dictionary, frozen: bool) -> void:
	var t := rt()
	var sol := solids(t)
	if p.t_state > 0: p.t_state -= 1
	if p.slow > 0: p.slow -= 1
	if p.landed > 0: p.landed -= 1
	if p.state in ["stumble", "getup"] and p.t_state <= 0: p.state = "run" if p.ground else "air"
	var mv := Vector3(float(inp.get("mx", 0.0)), 0, float(inp.get("mz", 0.0)))
	if mv.length() > 1.0: mv = mv.normalized()
	if frozen: mv = Vector3.ZERO
	var control := 1.0
	match p.state:
		"stumble": control = 0.0
		"dive": control = 0.15
		"getup": control = 0.25
	var speed := RUN * (0.45 if p.slow > 0 else 1.0)
	var want := mv * speed
	var acc := (30.0 if p.ground else 9.0) * control
	var hv := Vector3(p.vel.x, 0, p.vel.z)
	var diff := want - hv
	if p.state in ["stumble", "dive"]: diff = Vector3.ZERO if p.state == "dive" else -hv * 0.5   # sliding / slowing on their own
	hv += diff.limit_length(acc * DT) if p.state != "stumble" else diff * DT * 3.0
	p.vel.x = hv.x; p.vel.z = hv.z
	if mv.length() > 0.2 and control > 0.5: p.yaw = lerp_angle(p.yaw, atan2(mv.x, mv.z), 0.25)
	# jump / dive on a fresh press
	var j: bool = inp.get("j", false) and not frozen
	var d: bool = inp.get("d", false) and not frozen
	if j and not p.prev_jump and p.ground and p.state in ["run"]:
		p.vel.y = JUMP_V; p.ground = false; p.state = "air"
		events.append(["jump", p.pos, p.id])
	if d and not p.prev_dive and p.state in ["run", "air"]:
		var f := Vector3(sin(p.yaw), 0, cos(p.yaw))
		p.vel = f * 9.5 + Vector3(0, 3.5 if p.ground else maxf(p.vel.y, 1.5), 0)
		p.state = "dive"; p.ground = false
		events.append(["dive", p.pos, p.id])
	p.prev_jump = j; p.prev_dive = d
	# grab: slow whoever is right in front of you
	if inp.get("g", false) and not frozen and p.state == "run":
		var f2 := Vector3(sin(p.yaw), 0, cos(p.yaw))
		for o in players:
			if o == p or not o.in_round or o.state in ["out", "done"]: continue
			var dv: Vector3 = o.pos - p.pos
			if dv.length() < 1.2 and dv.normalized().dot(f2) > 0.4:
				o.slow = 6; p.slow = maxi(p.slow, 3)
	# ride a mover / belt
	if p.ground and p.on_plat >= 0 and p.on_plat < map.movers.size():
		var m: Dictionary = map.movers[p.on_plat]
		p.pos += mover_c(m, t) - mover_c(m, t - DT)
	var belt := Vector3.ZERO
	# horizontal move, one axis at a time, stepping up onto low ledges
	var dpos := Vector3(p.vel.x, 0, p.vel.z) * DT
	for axis in [0, 2]:
		var np := p.pos
		np[axis] += dpos[axis]
		var hit = _blocking(np, sol, p.ground)
		if hit == null:
			p.pos = np
		elif hit is float:
			p.pos = Vector3(np.x, hit, np.z)   # stepped up
		else:
			p.vel[axis] = 0.0
	# vertical
	p.vel.y -= GRAV * DT
	var feet0 := p.pos.y
	p.pos.y += p.vel.y * DT
	var was_ground := p.ground
	p.ground = false; p.on_plat = -1
	var best := -INF
	var best_s = null
	for s in sol:
		var bx: AABB = s[0]
		var top := bx.end.y
		if p.pos.x > bx.position.x - R * 0.5 and p.pos.x < bx.end.x + R * 0.5 and p.pos.z > bx.position.z - R * 0.5 and p.pos.z < bx.end.z + R * 0.5:
			if feet0 >= top - 0.25 and p.pos.y <= top + 0.02 and top > best:
				best = top; best_s = s
	for dc in map.discs:
		var c: Vector3 = dc[0]
		if Vector2(p.pos.x - c.x, p.pos.z - c.z).length() < float(dc[1]) and feet0 >= c.y - 0.25 and p.pos.y <= c.y + 0.02 and c.y > best:
			best = c.y; best_s = ["disc", "disc", 0]
	if best_s != null and p.vel.y <= 0.5:
		p.pos.y = best; p.vel.y = 0.0; p.ground = true
		if best_s[1] == "mover": p.on_plat = int(best_s[2])
		if best_s[1] == "belt": belt = map.belts[best_s[2]].belt
		if best_s[1] == "tile" and tiles[best_s[2]] == 0: tiles[best_s[2]] = 150 if map.id == "hotdesk" else 130
		if not was_ground:
			p.landed = 10
			if p.state in ["air"]: p.state = "run"
			if p.state == "dive": p.state = "getup"; p.t_state = 20
			if p.vel.length() > 0.1: events.append(["land", p.pos, p.id])
	elif p.pos.y > feet0 + 0.001 or p.vel.y < 0.0:
		if p.state == "run": p.state = "air"
	if belt != Vector3.ZERO: p.pos += belt * DT
	if not frozen: _hazards(p, t)


## null = free to move there, float = a low ledge we step up onto, true = blocked.
func _blocking(np: Vector3, sol: Array, ground: bool):
	var step_to = null
	for s in sol:
		var bx: AABB = s[0]
		if np.y >= bx.end.y - 0.02 or np.y + H <= bx.position.y: continue
		var cx := clampf(np.x, bx.position.x, bx.end.x)
		var cz := clampf(np.z, bx.position.z, bx.end.z)
		if Vector2(np.x - cx, np.z - cz).length() < R:
			if ground and bx.end.y - np.y <= STEP and s[1] != "pusher": step_to = maxf(float(step_to) if step_to != null else -INF, bx.end.y)
			else: return true
	return step_to


## Spinning bars, rolling bottles, swinging chairs, punching blocks: get knocked flying.
func _hazards(p: P, t: float) -> void:
	for s in map.spins:
		var c: Vector3 = s.c
		var y0: float = c.y + float(s.y0)
		var y1: float = c.y + float(s.y1)
		if p.pos.y > y1 or p.pos.y + H < y0: continue
		var arms: int = s.arms
		var ang := spin_angle(s, t)
		for k in arms:
			var a := ang + TAU * k / arms if arms != 2 else ang + PI * k
			var dir := Vector3(cos(a), 0, sin(a))
			var rel := p.pos - c; rel.y = 0
			var along := rel.dot(dir)
			if along < 0.0 or along > float(s.len): continue
			var perp := rel - dir * along
			if perp.length() < R + float(s.th):
				# pushed the way the bar is sweeping
				var sweep := Vector3(-dir.z, 0, dir.x) * signf(float(s.speed))
				_knock(p, sweep * (4.5 + absf(float(s.speed)) * along * 0.3) + Vector3(0, 4.5, 0))
				break
	for b in map.balls:
		var bp := ball_pos(b, t)
		var d: Vector3 = (p.pos + Vector3(0, 0.8, 0)) - bp
		if d.length() < R + float(b.r) + 0.3:
			_knock(p, Vector3(d.x, 0, d.z).normalized() * 4.0 + Vector3(0, 0, -2.5) + Vector3(0, 4.5, 0))
	for pd in map.pends:
		var q := pend_pos(pd, t)
		var d2: Vector3 = (p.pos + Vector3(0, 0.8, 0)) - q
		if d2.length() < R + float(pd.r) + 0.2:
			var swing := signf(cos(TAU * (t / float(pd.period) + float(pd.phase))))
			_knock(p, Vector3(swing * 11.0, 6.0, 0))
	for m in map.pushers:
		var bx := AABB(pusher_c(m, t) - (m.s as Vector3) / 2.0, m.s).grow(R)
		if bx.has_point(p.pos + Vector3(0, 0.5, 0)) and wave(m.period, m.phase, t) > 0.0:
			_knock(p, (m.dir as Vector3) * 12.0 + Vector3(0, 5.0, 0))


func _knock(p: P, v: Vector3) -> void:
	if p.state == "stumble" and p.t_state > 20: return
	p.vel = v; p.ground = false
	p.state = "stumble"; p.t_state = 45
	events.append(["bump", p.pos, p.id])


## Tumblers don't overlap: they shove each other apart (a fast one can knock a slow one over).
func _push_players() -> void:
	var act: Array = players.filter(func(p): return p.in_round and not p.state in ["out", "done"])
	for i in act.size():
		for j in range(i + 1, act.size()):
			var a: P = act[i]; var b: P = act[j]
			var d := b.pos - a.pos
			if absf(d.y) > H: continue
			d.y = 0
			var l := d.length()
			if l < R * 2.0 and l > 0.001:
				var n := d / l
				var push := (R * 2.0 - l) * 0.5
				a.pos -= n * push; b.pos += n * push
				var rel := (a.vel - b.vel).dot(n)
				if a.state == "dive" and rel > 4.0: _knock(b, n * 5.0 + Vector3(0, 3, 0))
				if b.state == "dive" and rel < -4.0: _knock(a, -n * 5.0 + Vector3(0, 3, 0))


func _tick_tiles() -> void:
	if tiles.is_empty(): return
	for i in tiles.size():
		if tiles[i] > 0:
			tiles[i] -= 1
			if tiles[i] == 0:
				tiles[i] = -1; _sol_valid = false
				events.append(["crumble", map.tiles[i][0], i])
	# after a while the floor starts to go by itself, faster and faster
	var secs := rt()
	var start := 40.0 if map.id == "hotdesk" else 12.0
	var every := 30 if map.id == "hotdesk" else maxi(20, 70 - int(secs))
	if secs > start and rtick % every == 0:
		var fine: Array = []
		for i in tiles.size():
			if tiles[i] == 0: fine.append(i)
		if not fine.is_empty(): tiles[fine[rng.randi() % fine.size()]] = 40


func _tick_tubs() -> void:
	for tb in tubs:
		var v: Vector3 = tb.vel
		for p in players:
			if not p.in_round or p.state in ["out", "done"]: continue
			var d: Vector3 = tb.pos - (p.pos + Vector3(0, 1.0, 0)); d.y = 0
			if d.length() < 1.3 + R + 0.1:
				var n := d.normalized()
				var push := maxf(0.0, Vector3(p.vel.x, 0, p.vel.z).dot(n))
				v += n * (push * 0.12 + 0.25)
				p.pos -= n * 0.04
		v *= 0.985
		v.y = 0
		var np: Vector3 = tb.pos + v * DT
		# bounce off the arena walls (the goal mouths are open)
		var in_mouth := absf(np.x) < 3.7
		if absf(np.x) > 10.7: v.x = -v.x * 0.6; np.x = signf(np.x) * 10.7
		if absf(np.z) > 13.7 and not in_mouth: v.z = -v.z * 0.6; np.z = signf(np.z) * 13.7
		if absf(np.z) > 18.0: np.z = signf(np.z) * 18.0; v.z = 0
		tb.pos = np; tb.vel = v
		for g in map.goals:
			if (g.box as AABB).has_point(np):
				team_score[g.team] += 1
				events.append(["score", np, g.team])
				tb.pos = Vector3(rng.randf_range(-4, 4), 1.3, 0); tb.vel = Vector3.ZERO
	# tubs bump each other
	for i in tubs.size():
		for j in range(i + 1, tubs.size()):
			var d: Vector3 = tubs[j].pos - tubs[i].pos
			if d.length() < 2.6 and d.length() > 0.01:
				var n := d.normalized() * (2.6 - d.length()) * 0.5
				tubs[i].pos -= n; tubs[j].pos += n


# ---------------------------------------------------------------- CPU tumblers
## Is there something to stand on at this spot (within `down` below and `up` above the given height)?
func support_at(at: Vector3, up := 1.4, down := 2.5, t := -1.0) -> float:
	if t < 0.0: t = rt()
	var best := -INF
	for s in solids(t):
		var bx: AABB = s[0]
		if at.x > bx.position.x and at.x < bx.end.x and at.z > bx.position.z and at.z < bx.end.z:
			var top := bx.end.y
			if top <= at.y + up and top >= at.y - down: best = maxf(best, top)
	for dc in map.discs:
		var c: Vector3 = dc[0]
		if Vector2(at.x - c.x, at.z - c.z).length() < float(dc[1]) - 0.3: best = maxf(best, c.y)
	return best


func _tile_under(p: P) -> int:
	for i in map.tiles.size():
		var tc: Vector3 = map.tiles[i][0]
		var hs: Vector3 = (map.tiles[i][1] as Vector3) / 2.0
		if absf(p.pos.x - tc.x) <= hs.x + 0.1 and absf(p.pos.z - tc.z) <= hs.z + 0.1 and absf(p.pos.y - (tc.y + hs.y)) < 0.4: return i
	return -1


func bot_input(p: P) -> Dictionary:
	var inp := {mx = 0.0, mz = 0.0, j = false, d = false, g = false}
	if p.state in ["stumble", "out", "done"]: return inp
	var t := rt()
	var goal := p.pos + Vector3(0, 0, 3)
	match String(map.kind):
		"race", "final_race":
			var wps: Array = map.waypoints
			while p.wp < wps.size() - 1 and p.pos.z > (wps[p.wp] as Vector3).z - 0.5: p.wp += 1
			goal = wps[p.wp]
			goal.x += p.lane * (0.6 if map.kind == "race" else 0.25)
			if map.id == "elevator" and p.wp >= 3: goal.x = 2.25 * signf(p.lane + 0.01)
			if map.id == "printer" and p.wp == 1: goal.x = [-3.6, 0.0, 3.6][(p.id + int(p.skill * 10.0)) % 3]
			if map.kind == "final_race" and p.wp == wps.size() - 1: goal = map.crown
		"survive", "final_survive":
			if not map.tiles.is_empty():
				var under := _tile_under(p)
				var shaky: bool = under < 0 or tiles[under] != 0
				if not shaky: p.tile_goal = under; p.think = 30   # a solid desk: stay put
				if shaky and (p.tile_goal < 0 or p.tile_goal == under or tiles[p.tile_goal] != 0): p.think = 0
				if p.tile_goal < 0 or tiles[p.tile_goal] != 0 or p.think <= 0:
					p.think = rng.randi_range(40, 90)
					var bestd := INF
					for i in tiles.size():
						if tiles[i] != 0: continue
						var tc: Vector3 = map.tiles[i][0]
						if absf(tc.y + 0.25 - p.pos.y) > 1.0: continue
						var crowd := 0
						for o in players:
							if o != p and o.in_round and o.state != "out" and o.pos.distance_to(tc) < 2.0: crowd += 1
						var dd := tc.distance_to(p.pos) + crowd * 3.0 + rng.randf() * (2.0 / p.skill)
						if (dd > 1.5 or tiles[i] == 0) and i != under and dd < bestd: bestd = dd; p.tile_goal = i
				p.think -= 1
				if p.tile_goal >= 0: goal = map.tiles[p.tile_goal][0]
			else:   # mop up: stay off the edge, jump the mops
				goal = Vector3(cos(p.lane) * 4.0, 0, sin(p.lane) * 4.0)
				for s in map.spins:
					var ang := spin_angle(s, t)
					var rel := p.pos - (s.c as Vector3); rel.y = 0
					var my := atan2(rel.z, rel.x)
					for k in int(s.arms):
						var a := ang + PI * k
						var ahead := wrapf((my - a) * signf(float(s.speed)), 0.0, TAU)
						var dist := ahead * rel.length()
						var spd := absf(float(s.speed) + float(s.accel) * t) * rel.length()
						if dist < spd * (0.18 + 0.12 / p.skill) and rng.randf() < 0.55 + 0.4 * p.skill: inp.j = true
		"team":
			var bestd2 := INF
			var tb = null
			for x in tubs:
				var dd2: float = (x.pos as Vector3).distance_to(p.pos)
				if dd2 < bestd2: bestd2 = dd2; tb = x
			if tb != null:
				var gz := 17.5 if p.team == 0 else -17.5
				var to_goal: Vector3 = (Vector3(0, 1.3, gz) - (tb.pos as Vector3)).normalized()
				var behind: Vector3 = (tb.pos as Vector3) - to_goal * 2.0
				behind.y = 0
				goal = behind if p.pos.distance_to(behind) > 1.2 else (tb.pos as Vector3) + to_goal * 2.0
	var to := goal - p.pos; to.y = 0
	var dist2 := to.length()
	var dir := to / maxf(0.001, dist2)
	if dist2 > 0.3:
		inp.mx = dir.x; inp.mz = dir.z
	# wobble: not a perfect line
	inp.mx += sin(tick_n * 0.05 + p.id) * 0.15
	if map.kind in ["race", "final_race"]:
		# gap ahead: wait for a platform; low wall ahead: jump it; spinner coming: jump it
		var ahead := p.pos + dir * 1.3
		var sup := support_at(ahead, 0.35, 1.5)
		var far := support_at(p.pos + dir * 2.8, 1.45, 2.0)
		if sup == -INF:
			if far == -INF:
				inp.mx = 0.0; inp.mz = 0.0; p.wait += 1
				if p.wait > 240: inp.mz = 1.0   # go for it
			elif p.ground and rng.randf() < 0.3 * p.skill: inp.j = true; p.wait = 0
		else: p.wait = 0
		var wall := support_at(p.pos + dir * 0.9, 1.45, -0.3)
		if wall > p.pos.y + STEP and p.ground: inp.j = true
		for s in map.spins:
			var c: Vector3 = s.c
			if absf(p.pos.y - c.y) > 1.0: continue
			var rel := p.pos - c; rel.y = 0
			if rel.length() > float(s.len) + 0.5: continue
			var ang2 := spin_angle(s, t)
			for k in int(s.arms):
				var a2 := ang2 + (PI * k if int(s.arms) == 2 else TAU * k / int(s.arms))
				var bdir := Vector3(cos(a2), 0, sin(a2))
				var along := rel.dot(bdir)
				if along < 0.0: continue
				var perp := (rel - bdir * along).length()
				if perp < 1.1 + 0.4 * p.skill and rng.randf() < 0.25 + 0.5 * p.skill: inp.j = true
		if map.id == "printer":   # paper bridges: hop to the next sheet only when it's solid
			var on_sheet := false
			for dr in map.drops:
				var dc2: Vector3 = dr.c
				if absf(dc2.x - p.pos.x) < 1.7 and absf(dc2.z - p.pos.z) < 1.6: on_sheet = true
			if not on_sheet:   # wait at the edge until the next sheet has just come back
				for dr in map.drops:
					var dc: Vector3 = dr.c
					if absf(dc.x - ahead.x) < 1.7 and absf(dc.z - ahead.z) < 1.6 and (drop_open(dr, t + 0.1) > 0.0 or drop_open(dr, t + 0.6) > 0.0) and rng.randf() < 0.3 + p.skill * 0.6:
						inp.mx = 0.0; inp.mz = 0.0
		if p.state == "run" and rng.randf() < 0.002: inp.d = true
		if (map.finish as AABB).size != Vector3.ZERO and p.pos.distance_to((map.finish as AABB).get_center()) < 4.0 and rng.randf() < 0.05: inp.d = true
	if map.kind == "final_race" and p.pos.distance_to(map.crown) < 3.2 and p.ground: inp.j = true
	if rng.randf() < 0.003: inp.g = true
	return inp


# ---------------------------------------------------------------- snapshots (multiplayer)
func snapshot() -> Dictionary:
	var ps := []
	for p in players:
		ps.append(Party.pack([p.pos.x, p.pos.y, p.pos.z, p.vel.x, p.vel.y, p.vel.z, p.yaw, STATES.find(p.state), p.t_state, p.alive, p.in_round, p.team, p.place, p.ground, p.landed]))
	var tb := []
	for x in tubs: tb.append(Party.pack([x.pos.x, x.pos.y, x.pos.z, x.vel.x, x.vel.z]))
	return {t = tick_n, rt = rtick, ri = round_i, rs = rounds, ph = phase, pt = phase_t, tg = target, f = finished, o = out_order, ts = team_score,
		w = winner, p = ps, tl = tiles, tb = tb, h = history}


func apply(sn: Dictionary) -> void:
	var rs: Array = sn.rs
	var new_round: bool = int(sn.ri) != round_i or map.is_empty() or rs.size() != rounds.size()
	rounds = rs.map(func(x): return String(x))
	if int(sn.ri) != round_i or map.is_empty():
		round_i = int(sn.ri)
		map = Maps.build(String(rounds[round_i]))
	tick_n = int(sn.t); rtick = int(sn.rt); phase = String(sn.ph); phase_t = int(sn.pt); target = int(sn.tg)
	finished = (sn.f as Array).map(func(x): return int(x)); out_order = (sn.o as Array).map(func(x): return int(x))
	team_score = [int(sn.ts[0]), int(sn.ts[1])]; winner = int(sn.w)
	tiles = (sn.tl as Array).map(func(x): return int(x))
	_sol_valid = false
	history = sn.get("h", [])
	var ps: Array = sn.p
	for k in mini(ps.size(), players.size()):
		var p: P = players[k]
		var a: Array = ps[k]
		p.prev_pos = p.pos if not new_round else Vector3(a[0], a[1], a[2])
		p.pos = Vector3(a[0], a[1], a[2]); p.vel = Vector3(a[3], a[4], a[5]); p.yaw = float(a[6])
		p.state = STATES[clampi(int(a[7]), 0, STATES.size() - 1)]; p.t_state = int(a[8]); p.alive = bool(a[9]); p.in_round = bool(a[10])
		p.team = int(a[11]); p.place = int(a[12]); p.ground = bool(a[13]); p.landed = int(a[14])
	var tb: Array = sn.get("tb", [])
	tubs.clear()
	for x in tb: tubs.append({pos = Vector3(x[0], x[1], x[2]), vel = Vector3(x[3], 0, x[4])})


## Guests between snapshots: keep everyone gliding the way they were going.
func coast() -> void:
	for p in players:
		p.prev_pos = p.pos
		if p.in_round and not p.state in ["out", "done"]:
			p.pos += p.vel * DT
	if phase == "play": rtick += 1
