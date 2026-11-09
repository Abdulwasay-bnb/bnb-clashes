extends RefCounted
## Deadline Dash rules, no visuals: tile collision, the hero, enemies, pickups, bosses, lives and the run.
## Fixed 60 ticks/s. World units = tiles; x grows right, y grows up; tile (col, row) covers
## x in [col, col+1], y in [H-1-row, H-row].

const Levels = preload("res://scripts/dash/dash_levels.gd")

const DT := 1.0 / 60.0
const GRAV := 42.0
const JUMP_V := 14.2         # ~4.5 tiles with the button held, ~2.4 on a tap
const MAX_FALL := 22.0
const WALK := 5.5
const RUN := 8.5
const W := 0.7
const H_SMALL := 1.05
const H_BIG := 1.6
const SOLID := "#DWRGB?PHU"
const START_LIVES := 3
const LEVEL_TIME := 300.0

# run
var level := 0
var lives := START_LIVES
var coins := 0
var score := 0
var state := "play"         # play / dead / clear / done (all 10 levels) / over (no lives left)
var state_t := 0
var events: Array = []
var god := false            # tests: enemies can't hurt you (pits still do)

# level
var rows: Array = []        # Array of PackedByteArray-like strings (mutable copies)
var w := 0
var h := Levels.H
var time_left := LEVEL_TIME
var wind := 0.0
var wind_on := false
var start_pos := Vector2.ZERO
var checkpoint := Vector2.ZERO
var cp_taken: Array = []    # checkpoint positions already reached
var exit_cell := Vector2i(-1, -1)
var exit_open := true
var tick_n := 0

# hero
var pos := Vector2.ZERO     # centre-bottom
var vel := Vector2.ZERO
var on_ground := false
var coyote := 0
var jump_buf := 0
var jump_held := false
var facing := 1
var power := ""             # "" small, "coffee" caffeinated (big), "drink" big + can throw planes
var invuln := 0
var star := 0               # headphones: invincible
var throw_cool := 0
var ride: Dictionary = {}   # moving platform under the hero

var enemies: Array = []     # {kind, pos, vel, dir, alive, t, w, h, home, dead_t}
var items: Array = []       # {kind, pos, vel, t}
var planes: Array = []      # {pos, vel, t}
var hazards: Array = []     # boss shots / shockwaves: {kind, pos, vel, t, w, h, grav}
var plats: Array = []       # {pos, home, axis, range, speed, t, w, prev}
var boss: Dictionary = {}   # {kind, pos, vel, hp, max_hp, state, t, inv, dir, active, alive, l, r, phase, dead_t}
var bumps: Array = []       # [cell, t]: blocks bouncing after a head bump (view)


func height() -> float: return H_BIG if power != "" else H_SMALL


# ---------------------------------------------------------------- run / levels
func new_run() -> void:
	level = 0; lives = START_LIVES; coins = 0; score = 0
	load_level(0)


func load_level(i: int) -> void:
	level = i
	rows = Levels.build(i).duplicate()
	w = String(rows[0]).length()
	enemies.clear(); items.clear(); planes.clear(); hazards.clear(); plats.clear(); bumps.clear(); boss = {}
	cp_taken.clear()
	exit_open = true
	exit_cell = Vector2i(-1, -1)
	var L: Dictionary = Levels.LEVELS[i]
	wind_on = L.get("wind", false)
	for r in h:
		var line: String = rows[r]
		for c in w:
			var ch := line[c]
			var y := float(h - 1 - r)
			var spot := Vector2(c + 0.5, y)
			match ch:
				"S": start_pos = spot; _put(c, r, ".")
				"E":   # the exit is the lower cell of the E pair
					if r + 1 >= h or String(rows[r + 1])[c] != "E": exit_cell = Vector2i(c, r)
					_put(c, r, ".")
				"e": enemies.append(_enemy("walker", spot)); _put(c, r, ".")
				"f": enemies.append(_enemy("flyer", spot + Vector2(0, 0.5))); _put(c, r, ".")
				"h": enemies.append(_enemy("hopper", spot)); _put(c, r, ".")
				# moving platforms start at different phases so neighbours don't move in lockstep
				"m": plats.append({pos = Vector2(c + 1.5, y + 0.5), home = Vector2(c + 1.5, y + 0.5), axis = 0, range = 4.5, speed = 1.2, t = c * 0.37, w = 3.0, prev = Vector2(c + 1.5, y + 0.5)}); _put(c, r, ".")
				"v": plats.append({pos = Vector2(c + 1.5, y + 0.5), home = Vector2(c + 1.5, y + 0.5), axis = 1, range = 2.6, speed = 0.8, t = c * 0.37, w = 3.0, prev = Vector2(c + 1.5, y + 0.5)}); _put(c, r, ".")
				"K": boss = _boss(String(L.get("boss", "hr")), spot); _put(c, r, ".")
				"C": cp_taken.append(false)
	if not boss.is_empty(): exit_open = false
	checkpoint = start_pos
	time_left = LEVEL_TIME
	state = "play"; state_t = 0
	_spawn_hero(start_pos)
	events.append(["level", Vector2.ZERO, i])


func _spawn_hero(at: Vector2) -> void:
	pos = at; vel = Vector2.ZERO; on_ground = true; coyote = 0; jump_buf = 0
	invuln = 90; star = 0; facing = 1; ride = {}
	hazards.clear()
	if not boss.is_empty() and boss.alive:   # retry the boss from the top
		boss.active = false; boss.hp = boss.max_hp; boss.pos = boss.home; boss.vel = Vector2.ZERO; boss.state = "idle"; boss.t = 0
		enemies = enemies.filter(func(e): return not e.get("minion", false))


func _enemy(kind: String, at: Vector2) -> Dictionary:
	var sz: Vector2 = {"walker": Vector2(0.9, 0.8), "flyer": Vector2(0.9, 0.6), "hopper": Vector2(1.0, 1.0)}[kind]
	return {kind = kind, pos = at, vel = Vector2.ZERO, dir = -1, alive = true, t = 0, w = sz.x, h = sz.y, home = at, dead_t = 0}


func _boss(kind: String, at: Vector2) -> Dictionary:
	var hp: int = {"hr": 3, "admin": 4, "wizard": 5, "ceo": 6}.get(kind, 3)
	# arena: from the arena chunk's left edge (the boss stands 20 tiles in) to the right wall
	var l := at.x - 20.5
	return {kind = kind, pos = at, home = at, vel = Vector2.ZERO, hp = hp, max_hp = hp, state = "idle", t = 0, inv = 0, dir = -1,
		active = false, alive = true, l = l, r = at.x + 6.0, phase = 1, dead_t = 0, w = 1.3, h = 2.3, on_ground = true, att = 0}


func cell(c: int, r: int) -> String:
	if c < 0 or c >= w or r < 0 or r >= h: return "#" if (c < 0 or c >= w) else "."
	return String(rows[r])[c]


func _put(c: int, r: int, ch: String) -> void:
	var line: String = rows[r]
	rows[r] = line.substr(0, c) + ch + line.substr(c + 1)


static func row_of(y: float, hh: int) -> int: return hh - 1 - int(floor(y))


func solid_at(x: float, y: float) -> bool:
	var c := int(floor(x)); var r := row_of(y, h)
	if r >= h: return false   # below the floor: a pit
	return SOLID.contains(cell(c, r))


func _oneway_at(x: float, y: float) -> bool:
	return cell(int(floor(x)), row_of(y, h)) == "-"


## Lose a life: respawn at the checkpoint, or game over (the run starts again from level 1).
func lose_life() -> String:
	lives -= 1
	if lives <= 0:
		state = "over"; state_t = 0
		events.append(["over", pos, 0])
		return "game_over"
	power = ""
	_spawn_hero(checkpoint)
	time_left = maxf(time_left, 100.0)
	state = "play"
	return "respawn"


func add_coins(n: int) -> void:
	coins += n; score += 100 * n
	while coins >= 100:
		coins -= 100; lives += 1
		events.append(["life", pos, lives])


# ---------------------------------------------------------------- tick
## inp: {x: -1..1, jump: held, jump_press: pressed this tick, run: bool, action: pressed}
func tick(inp: Dictionary) -> void:
	tick_n += 1
	events.clear()
	for b in bumps: b[1] -= 1
	bumps = bumps.filter(func(b): return b[1] > 0)
	if state == "dead":
		state_t += 1
		vel.y -= GRAV * DT; pos.y += vel.y * DT
		return
	if state != "play": state_t += 1; return
	time_left -= DT
	if time_left <= 0.0: _die("time"); return
	wind = (sin(tick_n * DT * 0.7) * 0.5 + 0.5) * -3.5 if wind_on else 0.0   # gusts from the right
	_move_plats()
	_hero(inp)
	_tick_enemies()
	_tick_items()
	_tick_planes()
	if not boss.is_empty(): _tick_boss()
	_tick_hazards()
	if pos.y < -3.0: _die("pit")


func _die(why: String) -> void:
	if state != "play": return
	state = "dead"; state_t = 0
	vel = Vector2(0, 14.0)
	events.append(["die", pos, why])


func _hurt() -> void:
	if god or invuln > 0 or star > 0 or state != "play": return
	if power != "":
		power = ""; invuln = 120
		events.append(["shrink", pos, 0])
	else:
		_die("hit")


func _move_plats() -> void:
	for p in plats:
		p.prev = p.pos
		p.t += DT
		var off: float = sin(p.t * p.speed) * p.range
		if p.axis == 0: p.pos = p.home + Vector2(off, 0)
		else: p.pos = p.home + Vector2(0, off)


func _hero(inp: Dictionary) -> void:
	var hh := height()
	if invuln > 0: invuln -= 1
	if star > 0: star -= 1
	if throw_cool > 0: throw_cool -= 1
	# ride a moving platform
	if not ride.is_empty():
		pos += ride.pos - ride.prev
	# horizontal
	var ix: float = clampf(float(inp.get("x", 0.0)), -1.0, 1.0)
	var top := RUN if inp.get("run", false) else WALK
	var accel := 38.0 if on_ground else 24.0
	if absf(ix) > 0.1:
		vel.x = move_toward(vel.x, ix * top, accel * DT * (1.8 if signf(ix) != signf(vel.x) else 1.0))
		facing = 1 if ix > 0 else -1
	else:
		vel.x = move_toward(vel.x, 0.0, (30.0 if on_ground else 8.0) * DT)
	vel.x += wind * DT * (0.5 if on_ground else 1.0)
	# jump: buffer + coyote time, variable height
	if inp.get("jump_press", false): jump_buf = 7
	elif jump_buf > 0: jump_buf -= 1
	if on_ground: coyote = 6
	elif coyote > 0: coyote -= 1
	if jump_buf > 0 and coyote > 0:
		vel.y = JUMP_V + absf(vel.x) * 0.06
		jump_buf = 0; coyote = 0; on_ground = false; ride = {}
		events.append(["jump", pos, 0])
	jump_held = inp.get("jump", false)
	var g := GRAV * (0.55 if (jump_held and vel.y > 0.0) else 1.0)
	vel.y = maxf(vel.y - g * DT, -MAX_FALL)
	# throw paper planes (energy drink)
	if inp.get("action", false) and power == "drink" and throw_cool == 0 and planes.size() < 3:
		# thrown low with a slight downward glide, so it takes out crawlers as well as tall bots
		planes.append({pos = pos + Vector2(facing * 0.5, minf(hh * 0.45, 0.6)), vel = Vector2(facing * 14.0, -0.6), t = 0, low = pos.y + 0.25})
		throw_cool = 18
		events.append(["throw", pos, 0])
	# move x
	var nx := pos.x + vel.x * DT
	if _box_hits(nx, pos.y, W, hh):
		nx = (floor(nx + W / 2.0) - W / 2.0 - 0.001) if vel.x > 0 else (floor(nx - W / 2.0) + 1.0 + W / 2.0 + 0.001)
		if _box_hits(nx, pos.y, W, hh): nx = pos.x
		vel.x = 0.0
	if not boss.is_empty() and boss.active and boss.alive: nx = clampf(nx, boss.l + 0.5, boss.r)   # locked in the arena
	pos.x = clampf(nx, 0.4, w - 0.4)
	# move y
	var ny := pos.y + vel.y * DT
	var was_ground := on_ground
	on_ground = false
	ride = {}
	if vel.y <= 0.0:
		# land on solid tops, one-way ledges and moving platforms
		var land := -INF
		for sx in [pos.x - W / 2.0 + 0.05, pos.x + W / 2.0 - 0.05]:
			var ty := floor(pos.y + 0.001)   # tile row whose top we may land on is below our feet
			var cand := ty
			if ny < cand and (solid_at(sx, cand - 0.5) or _oneway_at(sx, cand - 0.5)) and pos.y >= cand - 0.05:
				land = maxf(land, cand)
		for p in plats:
			var top_y: float = p.pos.y + 0.15
			if absf(pos.x - p.pos.x) < p.w / 2.0 + W / 2.0 - 0.1 and pos.y >= top_y - 0.1 and ny <= top_y + 0.05:
				if top_y > land: land = top_y; ride = p
		if land > -INF:
			ny = land; vel.y = 0.0; on_ground = true
			if not was_ground and not ride.is_empty(): pass
		else:
			ride = {}
	else:
		# head bump
		var head := ny + hh
		for sx in [pos.x - W / 2.0 + 0.1, pos.x + W / 2.0 - 0.1]:
			if solid_at(sx, head):
				ny = floor(head) - hh - 0.001
				vel.y = -1.0
				_bump(int(floor(pos.x)) if solid_at(pos.x, head) else int(floor(sx)), row_of(head, h))
				break
	pos.y = ny
	if pos.y < -0.5: on_ground = false
	# coins
	for dy in [0.3, hh - 0.3]:
		var c := int(floor(pos.x)); var r := row_of(pos.y + dy, h)
		for cc in [c - 1, c, c + 1]:
			if cell(cc, r) == "o" and absf(cc + 0.5 - pos.x) < 0.75:
				_put(cc, r, "."); add_coins(1)
				events.append(["coin", Vector2(cc + 0.5, h - 1 - r + 0.5), 0])
	# spikes
	if cell(int(floor(pos.x)), row_of(pos.y + 0.2, h)) == "^" and star == 0 and not god: _die("shredder")
	# checkpoints / exit
	var hc := int(floor(pos.x)); var hr := row_of(pos.y + 0.5, h)
	for cc in [hc]:
		if cell(cc, hr) == "C" and Vector2(cc + 0.5, h - 1 - hr) != checkpoint:
			checkpoint = Vector2(cc + 0.5, h - 1 - hr)
			events.append(["checkpoint", checkpoint, 0])
	if exit_open and exit_cell.x >= 0 and absf(pos.x - (exit_cell.x + 0.5)) < 0.6 and absf(pos.y - (h - 1 - exit_cell.y)) < 1.0:
		_clear()


func _box_hits(x: float, y: float, bw: float, bh: float) -> bool:
	for sy in [y + 0.05, y + bh * 0.5, y + bh - 0.05]:
		for sx in [x - bw / 2.0, x + bw / 2.0]:
			if solid_at(sx, sy): return true
	return false


func _bump(c: int, r: int) -> void:
	var ch := cell(c, r)
	var at := Vector2(c + 0.5, h - r)
	match ch:
		"?":
			_put(c, r, "U"); add_coins(1)
			events.append(["coin", at + Vector2(0, 0.5), 1])
		"P", "H":
			_put(c, r, "U")
			var kind := "headphones" if ch == "H" else ("coffee" if power == "" else "drink")
			items.append({kind = kind, pos = at, vel = Vector2(2.0, 6.0), t = 0})
			events.append(["sprout", at, kind])
		"B":
			if power != "":
				_put(c, r, "."); score += 50
				events.append(["break", at - Vector2(0, 0.5), 0])
				return
		_:
			pass
	bumps.append([Vector2i(c, r), 10])
	events.append(["bump", at, 0])
	# knock out enemies standing on the bumped block
	for e in enemies:
		if e.alive and absf(e.pos.x - (c + 0.5)) < 0.9 and absf(e.pos.y - (h - r)) < 0.3: _kill(e, true)


func _clear() -> void:
	if state != "play": return
	var bonus := int(time_left) * 10
	score += bonus + 1000
	state = "clear" if level < Levels.LEVELS.size() - 1 else "done"
	state_t = 0
	events.append(["clear", pos, bonus])


## Next level (after the clear tally).
func next_level() -> void:
	if level + 1 < Levels.LEVELS.size(): load_level(level + 1)


# ---------------------------------------------------------------- enemies
func _tick_enemies() -> void:
	var hh := height()
	for e in enemies:
		if not e.alive:
			e.dead_t += 1
			continue
		e.t += 1
		match String(e.kind):
			"walker", "hopper":
				var sp := 1.7 if e.kind == "walker" else 1.4
				e.vel.x = e.dir * sp
				e.vel.y = maxf(e.vel.y - GRAV * DT, -MAX_FALL)
				if e.kind == "hopper" and e.get("ground", true) and e.t % 80 == 0: e.vel.y = 13.0
				var nx: float = e.pos.x + e.vel.x * DT
				var front: float = nx + e.dir * e.w / 2.0
				# turn at walls and ledges
				if solid_at(front, e.pos.y + 0.3) or (e.get("ground", true) and not solid_at(front, e.pos.y - 0.3) and not _oneway_at(front, e.pos.y - 0.3) and e.kind == "walker"):
					e.dir = -e.dir
				else:
					e.pos.x = nx
				var ny: float = e.pos.y + e.vel.y * DT
				e.ground = false
				if e.vel.y <= 0.0 and (solid_at(e.pos.x, ny) or _oneway_at(e.pos.x, ny)) and e.pos.y >= floor(e.pos.y + 0.001) - 0.05:
					ny = floor(e.pos.y + 0.001); e.vel.y = 0.0; e.ground = true
				e.pos.y = ny
				if e.pos.y < -3.0: e.alive = false
			"flyer":
				e.pos = e.home + Vector2(sin(e.t * DT * 0.9) * 2.5, sin(e.t * DT * 2.2) * 0.8)
				e.dir = 1 if cos(e.t * DT * 0.9) > 0 else -1
		# touch the hero
		if state == "play" and absf(e.pos.x - pos.x) < (e.w + W) / 2.0 - 0.05 and pos.y < e.pos.y + e.h and pos.y + hh > e.pos.y:
			if star > 0: _kill(e, true)
			elif vel.y < 0.0 and pos.y > e.pos.y + e.h * 0.45:
				_kill(e, false)
				vel.y = JUMP_V * (0.85 if jump_held else 0.55)
				events.append(["stomp", e.pos, 0])
			else:
				_hurt()


func _kill(e: Dictionary, flip: bool) -> void:
	if not e.alive: return
	e.alive = false; e.dead_t = 0; e.flip = flip
	score += 200
	events.append(["kill", e.pos, 0])


func _tick_items() -> void:
	var hh := height()
	for it in items.duplicate():
		it.t += 1
		if it.t < 30:   # rising out of the block
			it.pos.y += 1.0 / 30.0
		else:
			it.vel.y = maxf(it.vel.y - GRAV * 0.6 * DT, -12.0)
			var nx: float = it.pos.x + it.vel.x * DT
			if solid_at(nx + signf(it.vel.x) * 0.35, it.pos.y + 0.3): it.vel.x = -it.vel.x
			else: it.pos.x = nx
			var ny: float = it.pos.y + it.vel.y * DT
			if it.vel.y <= 0.0 and solid_at(it.pos.x, ny): ny = floor(it.pos.y + 0.001); it.vel.y = 0.0
			it.pos.y = ny
		if it.pos.y < -3.0: items.erase(it); continue
		if absf(it.pos.x - pos.x) < 0.8 and absf((it.pos.y + 0.4) - (pos.y + hh * 0.5)) < hh * 0.5 + 0.4:
			match String(it.kind):
				"coffee": if power == "": power = "coffee"
				"drink": power = "drink"
				"headphones": star = 600
			score += 1000
			events.append(["power", pos, it.kind])
			items.erase(it)


func _tick_planes() -> void:
	for p in planes.duplicate():
		p.t += 1
		p.pos += p.vel * DT
		if p.pos.y < float(p.get("low", -99.0)) and p.vel.y < 0.0: p.vel.y = 0.0   # then skims along at ankle height
		var gone: bool = p.t > 90 or solid_at(p.pos.x, p.pos.y)
		for e in enemies:
			if e.alive and absf(e.pos.x - p.pos.x) < e.w / 2.0 + 0.25 and p.pos.y > e.pos.y - 0.35 and p.pos.y < e.pos.y + e.h + 0.35:
				_kill(e, true); gone = true
		if not boss.is_empty() and boss.alive and boss.active and absf(boss.pos.x - p.pos.x) < boss.w / 2.0 + 0.2 and p.pos.y > boss.pos.y and p.pos.y < boss.pos.y + boss.h:
			_hit_boss(0.34); gone = true
		if gone: planes.erase(p)


# ---------------------------------------------------------------- bosses
## HR: charges and leaps. Admin: slams the floor (shockwaves) and throws. Wizard: throws, summons drones, slams.
## CEO: everything, faster as he loses health.
const BOSS_MOVES := {"hr": ["charge", "leap"], "admin": ["slam", "throw", "charge"], "wizard": ["throw", "summon", "slam"],
	"ceo": ["charge", "throw", "slam", "summon"]}


func _tick_boss() -> void:
	var b := boss
	if not b.alive:
		b.dead_t += 1
		return
	if not b.active:
		if pos.x > b.l + 3.0:
			b.active = true; b.state = "intro"; b.t = 0
			events.append(["boss", b.pos, b.kind])
		return
	b.t += 1
	if b.inv > 0: b.inv -= 1
	var speed_up: float = 1.0 + (1.0 - float(b.hp) / float(b.max_hp)) * 0.6
	var toward := signf(pos.x - b.pos.x)
	if toward == 0.0: toward = 1.0
	match String(b.state):
		"intro":
			if b.t > 70: _boss_next()
		"idle":
			b.vel.x = move_toward(b.vel.x, 0.0, 20.0 * DT)
			if b.t > int(55 / speed_up): _boss_next()
		"charge":
			if b.t < 25: b.vel.x = 0.0; b.dir = int(toward)   # wind-up
			else: b.vel.x = b.dir * 9.0 * speed_up
			if b.t > 25 and (b.pos.x <= b.l + 1.2 or b.pos.x >= b.r - 1.0 or b.t > 110):
				b.vel.x = 0.0; b.state = "idle"; b.t = 0
		"leap", "slam":
			if b.t == 1:
				b.vel = Vector2(clampf(pos.x - b.pos.x, -9.0, 9.0) * 0.9, 19.0)
				b.on_ground = false
			if b.on_ground and b.t > 8:
				b.vel.x = 0.0
				if b.state == "slam":   # shockwaves both ways along the floor
					for d in [-1.0, 1.0]:
						hazards.append({kind = "wave", pos = b.pos + Vector2(d * 0.8, 0), vel = Vector2(d * 8.0, 0), t = 0, w = 0.8, h = 0.7, grav = false})
					events.append(["slam", b.pos, 0])
				b.state = "idle"; b.t = 0
		"throw":
			b.vel.x = 0.0; b.dir = int(toward)
			if b.t in [20, 45, 70] or (b.phase > 1 and b.t == 95):
				var d: Vector2 = pos + Vector2(0, 0.8) - (b.pos + Vector2(0, b.h * 0.8))
				var tt: float = clampf(absf(d.x) / 9.0, 0.5, 1.4)
				hazards.append({kind = "prop", pos = b.pos + Vector2(b.dir * 0.6, b.h * 0.8), vel = Vector2(d.x / tt, d.y / tt + 0.5 * GRAV * 0.6 * tt), t = 0, w = 0.5, h = 0.5, grav = true})
				events.append(["throw_boss", b.pos, b.kind])
			if b.t > 100: b.state = "idle"; b.t = 0
		"summon":
			b.vel.x = 0.0
			if b.t == 30:
				for k in 2:
					var m := _enemy("flyer" if b.kind == "wizard" else "walker", Vector2(b.pos.x + (k * 2 - 1) * 3.0, b.pos.y + (3.0 if b.kind == "wizard" else 0.5)))
					m.minion = true; m.home = m.pos
					enemies.append(m)
				events.append(["summon", b.pos, 0])
			if b.t > 60: b.state = "idle"; b.t = 0
	# physics
	b.vel.y = maxf(b.vel.y - GRAV * DT, -MAX_FALL)
	var nx: float = clampf(b.pos.x + b.vel.x * DT, b.l + 1.0, b.r - 0.8)
	b.pos.x = nx
	var ny: float = b.pos.y + b.vel.y * DT
	b.on_ground = false
	if b.vel.y <= 0.0 and solid_at(b.pos.x, ny) and b.pos.y >= floor(b.pos.y + 0.001) - 0.05:
		ny = floor(b.pos.y + 0.001); b.vel.y = 0.0; b.on_ground = true
	b.pos.y = ny
	# touch: stomp on the head, else you get hurt
	var hh := height()
	if state == "play" and absf(b.pos.x - pos.x) < (b.w + W) / 2.0 - 0.1 and pos.y < b.pos.y + b.h and pos.y + hh > b.pos.y:
		if vel.y < 0.0 and pos.y > b.pos.y + b.h * 0.55:
			_hit_boss(1.0)
			vel.y = JUMP_V * 0.9; vel.x = -signf(b.pos.x - pos.x) * 6.0
		elif star > 0:
			_hit_boss(0.5)
		else:
			_hurt()
			vel.x = -signf(b.pos.x - pos.x) * 8.0


func _hit_boss(dmg: float) -> void:
	var b := boss
	if b.inv > 0 or not b.alive: return
	b.hp -= dmg
	b.inv = 70
	events.append(["boss_hit", b.pos, b.hp])
	if b.hp <= 0.0:
		b.alive = false; b.dead_t = 0; b.hp = 0
		hazards.clear()
		for e in enemies:
			if e.get("minion", false): _kill(e, true)
		exit_open = true
		score += 5000
		events.append(["boss_dead", b.pos, b.kind])
	elif b.hp <= b.max_hp * 0.5 and b.phase == 1:
		b.phase = 2
		events.append(["phase", b.pos, 2])


func _boss_next() -> void:
	var moves: Array = BOSS_MOVES.get(boss.kind, ["charge"])
	boss.att += 1
	boss.state = moves[boss.att % moves.size()]
	boss.t = 0


func _tick_hazards() -> void:
	var hh := height()
	for z in hazards.duplicate():
		z.t += 1
		if z.grav: z.vel.y -= GRAV * 0.6 * DT
		z.pos += z.vel * DT
		var gone: bool = z.t > 240 or z.pos.y < -2.0 or (z.kind == "wave" and solid_at(z.pos.x + signf(z.vel.x) * 0.4, z.pos.y + 0.3))
		if z.grav and solid_at(z.pos.x, z.pos.y): gone = true
		if absf(z.pos.x - pos.x) < (z.w + W) / 2.0 - 0.05 and z.pos.y < pos.y + hh and z.pos.y + z.h > pos.y:
			_hurt(); gone = true
		if gone: hazards.erase(z)


# ---------------------------------------------------------------- reachability (tests)
## Can the exit be reached from the start? Breadth-first over standable cells: walk to neighbours, or jump
## up to 4 tiles up / 6 across (down any height) when the straight line between the two heads is clear.
## Moving platforms count as standable anywhere along their track. Bosses are assumed beatable.
func reachable() -> bool:
	var stand := {}
	var ok_cell := func(c: int, r: int) -> bool:
		if c < 0 or c >= w or r < 1 or r >= h - 1: return false
		var here := cell(c, r)
		var up := cell(c, r - 1)
		if SOLID.contains(here) or SOLID.contains(up) or here == "^": return false
		var below := cell(c, r + 1)
		return SOLID.contains(below) or below == "-"
	for r in h:
		for c in w:
			if ok_cell.call(c, r): stand[Vector2i(c, r)] = true
	for p in plats:   # every cell a platform passes through (its top)
		var steps := 12
		for k in steps + 1:
			var off: float = -p.range + 2.0 * p.range * k / steps
			var at: Vector2 = p.home + (Vector2(off, 0) if p.axis == 0 else Vector2(0, off))
			for dx in [-1, 0, 1]:
				var cell_xy := Vector2i(int(floor(at.x)) + dx, row_of(at.y + 0.2, h))
				if cell_xy.y >= 0 and cell_xy.y < h: stand[cell_xy] = true
	var start := Vector2i(int(floor(start_pos.x)), row_of(start_pos.y + 0.1, h))
	var goal := Vector2i(exit_cell.x, exit_cell.y)
	var seen := {start: true}
	var q := [start]
	var keys: Array = stand.keys()
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if absi(cur.x - goal.x) <= 1 and cur.y == goal.y: return true
		for nb in keys:
			if seen.has(nb): continue
			var dx: int = nb.x - cur.x
			var up: int = cur.y - nb.y   # rows go down the screen
			if absi(dx) > 6 or up > 4: continue
			if absi(dx) <= 1 and up == 0 or _arc_clear(cur, nb):
				seen[nb] = true; q.append(nb)
	return false


func _arc_clear(a: Vector2i, b: Vector2i) -> bool:
	# headroom over the take-off, then a straight line between the heads
	var up := maxi(0, a.y - b.y)
	for k in range(1, up + 2):
		if SOLID.contains(cell(a.x, a.y - k)): return false
	var n := 12
	for k in n + 1:
		var t := float(k) / n
		var x := lerpf(a.x + 0.5, b.x + 0.5, t)
		var r := lerpf(a.y - up - 0.5, b.y - 0.5, t)   # travel at apex height, then drop
		if SOLID.contains(cell(int(floor(x)), int(round(r)))): return false
	return true


# ---------------------------------------------------------------- the test bot
## Runs right, jumps over gaps, walls, spikes and enemies, fights the boss by hopping and throwing.
var _bot_jump_t := 0
var _bot_last_x := 0.0
var _bot_stuck := 0


func _ground_near(x: float, y: float) -> bool:
	return solid_at(x, y - 0.5) or _oneway_at(x, y - 0.5)


## A place to land on between `from` and `to` tiles ahead (ground or a platform), not too high.
func _landing(from: float, to: float) -> bool:
	var d := from
	while d <= to:
		for dy in [0.0, 1.0, 2.0, 3.0, -1.0, -2.0, -3.0, -4.0]:
			if _ground_near(pos.x + d, pos.y + dy) and not _ground_near(pos.x + d, pos.y + dy + 1.0): return true
		d += 0.5
	for p in plats:
		var dx: float = p.pos.x - pos.x
		# a platform we can reach: in range, not above our jump, and (lifts) not about to drop away
		var dy: float = p.pos.y - pos.y
		var rising: bool = p.axis == 0 or cos(p.t * p.speed) >= -0.3
		if dx - p.w / 2.0 < to and dx + p.w / 2.0 > from and dy < 3.2 and dy > -3.0 and rising: return true
	return false


func bot_input() -> Dictionary:
	var inp := {x = 1.0, run = true, jump = false, jump_press = false, action = power == "drink" and tick_n % 20 == 0}
	var want_jump := false
	var ahead := pos.x + 0.9
	var fighting: bool = not boss.is_empty() and boss.active and boss.alive
	if on_ground:
		var gap := not (_ground_near(pos.x + 0.6, pos.y) and _ground_near(pos.x + 1.2, pos.y))
		if not ride.is_empty():
			# riding a platform: stay on it until there's somewhere to jump to
			var edge: float = ride.pos.x + ride.w / 2.0 - pos.x
			if edge < 0.9:
				if _landing(1.0, 4.0): want_jump = true
				else: inp.x = 0.0 if edge > 0.3 else -0.5
			else:
				inp.x = 0.6
				if _landing(1.0, 3.5) and edge < 1.4: want_jump = true
		elif gap:
			if _landing(1.5, 7.5): want_jump = true
			else: inp.x = 0.0   # wait for a platform to come round
		if solid_at(ahead, pos.y + 0.5) or solid_at(ahead + 0.5, pos.y + 0.5): want_jump = true   # wall / desk
		for d in [0.8, 1.5, 2.2]:
			if cell(int(floor(pos.x + d)), row_of(pos.y + 0.2, h)) == "^": want_jump = true
		for e in enemies:
			if e.alive and e.pos.x > pos.x and e.pos.x - pos.x < 2.6 and absf(e.pos.y - pos.y) < 2.0: want_jump = true
		for z in hazards:
			if absf(z.pos.x - pos.x) < 3.0: want_jump = true
		if fighting:
			var dxb: float = boss.pos.x - pos.x
			inp.x = signf(dxb)
			if absf(dxb) < 3.2 and boss.on_ground: want_jump = true
	elif fighting:
		inp.x = signf(boss.pos.x - pos.x) * (1.0 if pos.y > boss.pos.y + boss.h * 0.6 else 0.6)
	if absf(pos.x - _bot_last_x) < 0.01 and absf(inp.x) > 0.0: _bot_stuck += 1
	else: _bot_stuck = maxi(0, _bot_stuck - 2)
	_bot_last_x = pos.x
	if _bot_stuck > 40: want_jump = true
	if _bot_stuck > 120: inp.x = -1.0 if _bot_stuck % 60 < 20 else 1.0
	if want_jump and on_ground: inp.jump_press = true; _bot_jump_t = 26
	if _bot_jump_t > 0: inp.jump = true; _bot_jump_t -= 1
	return inp
