extends RefCounted
## BNB Office Blast: the rules with no visuals. A 15 x 13 office floor grid, players walking tile to tile,
## coffee-mug bombs, flame crosses, breakable cover with power-ups, rounds, sudden death and the CPU players.
## Runs at 60 ticks/s on the host; online guests send controls and draw the host's snapshots.

const W := 15
const H := 13
const DT := 1.0 / 60.0
const FUSE := 150               # 2.5 s
const FLAME := 32               # ticks a flame tile burns
const ROUND_TIME := 90.0        # then sudden death: the room closes in
const WINS := 3                 # round wins for the match
const MAX_ROUNDS := 9
const COUNT := 200              # 3-2-1-GO
const ROUND_END := 200
const EMPTY := 0
const PILLAR := 1
const BOX := 2
const POWERS := ["bomb", "fire", "speed", "kick"]
const DIRS := [Vector2i.ZERO, Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]   # none, up, down, left, right
const SPAWNS := [Vector2i(0, 0), Vector2i(14, 12), Vector2i(14, 0), Vector2i(0, 12)]


class Player:
	var id := 0
	var C: Dictionary
	var human := false
	var slot := -1
	var pos := Vector2.ZERO       # tile coordinates (tile centres are whole numbers)
	var prev_pos := Vector2.ZERO
	var tgt := Vector2i.ZERO
	var moving := false
	var facing := 2               # index into DIRS
	var alive := true
	var bombs := 1                # how many at once
	var fire := 2                 # flame reach in tiles
	var speed := 0                # speed-ups taken
	var kick := false
	var wins := 0
	var dead_t := 0               # ticks since being blasted
	var held_bomb := false
	var placed := 0               # bombs placed this match (stats)
	# CPU
	var plan: Array = []          # route of tiles
	var goal_kind := ""
	var think := 0

	func tile() -> Vector2i: return Vector2i(roundi(pos.x), roundi(pos.y))
	func tiles_per_s() -> float: return 3.6 + speed * 0.55


class Bomb:
	var uid := 0
	var cell := Vector2i.ZERO
	var t := FUSE
	var fire := 2
	var owner := 0
	var slide := Vector2i.ZERO    # kicked: sliding this way
	var slide_p := 0.0            # 0..1 toward the next tile


var players: Array = []
var cells := PackedByteArray()     # EMPTY / PILLAR / BOX
var hidden := {}                   # box index -> power-up underneath
var powerups := {}                 # floor index -> kind
var bombs: Array = []
var flames := {}                   # index -> ticks left
var state := "count"               # count / play / roundend / done
var state_t := COUNT
var round_n := 1
var time := 0.0
var sd_i := 0                      # sudden death: how many tiles have closed in
var sd_order: Array = []
var round_winner := -2             # -1 draw, >= 0 player id
var match_winner := -1
var events: Array = []             # [kind, x, y, a, b]
var rng := RandomNumberGenerator.new()
var next_uid := 1
var tick_n := 0
var stats := {"suicides": 0, "kills": 0, "rounds": 0, "round_ticks": 0}


static func idx(c: Vector2i) -> int: return c.y * W + c.x
static func inside(c: Vector2i) -> bool: return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func setup(people: Array, seed: int) -> void:
	rng.seed = seed
	for k in people.size():
		var p := Player.new()
		p.id = k
		p.C = people[k].C
		p.human = bool(people[k].human)
		p.slot = int(people[k].get("slot", -1))
		players.append(p)
	_new_round()
	sd_order = _spiral()


## Fresh arena: pillars on the odd tiles, boxes on most of the rest (spawn corners kept clear), players home.
func _new_round() -> void:
	cells = PackedByteArray(); cells.resize(W * H)
	hidden.clear(); powerups.clear(); bombs.clear(); flames.clear()
	var clear := {}
	for s in SPAWNS:
		clear[idx(s)] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			if inside(s + d): clear[idx(s + d)] = true
	var power_bag := []
	for k in 6: power_bag.append("bomb")
	for k in 6: power_bag.append("fire")
	for k in 4: power_bag.append("speed")
	for k in 2: power_bag.append("kick")
	var box_ids := []
	for y in H:
		for x in W:
			var i := y * W + x
			if x % 2 == 1 and y % 2 == 1: cells[i] = PILLAR
			elif not clear.has(i) and rng.randf() < 0.7:
				cells[i] = BOX; box_ids.append(i)
	# shuffle power-ups under random boxes
	for k in range(box_ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = box_ids[k]; box_ids[k] = box_ids[j]; box_ids[j] = tmp
	for k in mini(power_bag.size(), box_ids.size()): hidden[box_ids[k]] = power_bag[k]
	for p in players:
		var s: Vector2i = SPAWNS[p.id % 4]
		p.pos = Vector2(s); p.prev_pos = p.pos; p.tgt = s; p.moving = false
		p.alive = true; p.bombs = 1; p.fire = 2; p.speed = 0; p.kick = false; p.dead_t = 0
		p.plan = []; p.think = 0
		p.facing = 2 if s.y == 0 else 1
	state = "count"; state_t = COUNT; time = 0.0; sd_i = 0; round_winner = -2
	events.append(["round", 0, 0, round_n, 0])


## Sudden death order: tiles from the outside ring spiralling in.
func _spiral() -> Array:
	var out := []
	var x0 := 0; var y0 := 0; var x1 := W - 1; var y1 := H - 1
	while x0 <= x1 and y0 <= y1:
		for x in range(x0, x1 + 1): out.append(Vector2i(x, y0))
		for y in range(y0 + 1, y1 + 1): out.append(Vector2i(x1, y))
		if y1 > y0:
			for x in range(x1 - 1, x0 - 1, -1): out.append(Vector2i(x, y1))
		if x1 > x0:
			for y in range(y1 - 1, y0, -1): out.append(Vector2i(x0, y))
		x0 += 1; y0 += 1; x1 -= 1; y1 -= 1
	return out


func bomb_at(c: Vector2i) -> Bomb:
	for b in bombs:
		if b.cell == c: return b
	return null


func walkable(c: Vector2i) -> bool:
	return inside(c) and cells[idx(c)] == EMPTY and bomb_at(c) == null


func alive_count() -> int:
	var n := 0
	for p in players: if p.alive: n += 1
	return n


# ---------------------------------------------------------------- tick
## inputs: player id -> {d: 0..4 direction, b: bomb button held}
func tick(inputs: Dictionary) -> void:
	tick_n += 1
	for p in players: p.prev_pos = p.pos
	match state:
		"count":
			state_t -= 1
			if state_t % 60 == 0 and state_t > 0: events.append(["count", 0, 0, state_t / 60, 0])
			if state_t <= 0: state = "play"; events.append(["go", 0, 0, 0, 0])
			return
		"roundend":
			state_t -= 1
			for p in players: if not p.alive: p.dead_t += 1
			_tick_flames()
			if state_t <= 0:
				if match_winner >= 0:
					state = "done"; events.append(["done", 0, 0, match_winner, 0])
				else:
					round_n += 1
					_new_round()
			return
		"done":
			return
	time += DT
	for p in players:
		if not p.alive: p.dead_t += 1; continue
		var inp: Dictionary = inputs.get(p.id, {}) if p.human else ai(p)
		_control(p, inp)
	_tick_bombs()
	_tick_flames()
	if time >= ROUND_TIME: _sudden_death()
	for p in players:   # safety: nobody survives inside solid cover
		if p.alive and cells[idx(p.tile())] != EMPTY:
			p.alive = false; p.dead_t = 0; p.moving = false
			events.append(["out", p.tile().x, p.tile().y, p.id, -2])
	_check_round()


func _control(p: Player, inp: Dictionary) -> void:
	var d: int = clampi(int(inp.get("d", 0)), 0, 4)
	var bomb_btn: bool = bool(inp.get("b", false))
	if bomb_btn and not p.held_bomb: _place(p)
	p.held_bomb = bomb_btn
	var step: float = p.tiles_per_s() * DT
	if p.moving and d != 0 and DIRS[d] == -DIRS[p.facing]:   # turn back mid-tile
		p.tgt = p.tgt - DIRS[p.facing]; p.facing = d
	if not p.moving and d != 0: _start_move(p, d)
	while p.moving and step > 0.0:
		var to: Vector2 = Vector2(p.tgt)
		var dist: float = p.pos.distance_to(to)
		if dist <= step:
			p.pos = to; step -= dist; p.moving = false
			_pickup(p)
			if d != 0: _start_move(p, d)
		else:
			p.pos += (to - p.pos) / dist * step; step = 0.0


func _start_move(p: Player, d: int) -> void:
	p.facing = d
	var nxt: Vector2i = p.tile() + DIRS[d]
	if walkable(nxt):
		p.tgt = nxt; p.moving = true
	elif p.kick and inside(nxt):
		var b := bomb_at(nxt)
		if b != null and b.slide == Vector2i.ZERO and walkable(nxt + DIRS[d]):
			b.slide = DIRS[d]; b.slide_p = 0.0
			events.append(["kick", nxt.x, nxt.y, p.id, 0])


func _place(p: Player) -> void:
	var c: Vector2i = p.tile()
	if bomb_at(c) != null or cells[idx(c)] != EMPTY: return
	var mine := 0
	for b in bombs: if b.owner == p.id: mine += 1
	if mine >= p.bombs: return
	var b := Bomb.new()
	b.uid = next_uid; next_uid += 1
	b.cell = c; b.fire = p.fire; b.owner = p.id
	bombs.append(b)
	p.placed += 1
	events.append(["bomb", c.x, c.y, p.id, b.uid])


func _pickup(p: Player) -> void:
	var i: int = idx(p.tile())
	if not powerups.has(i): return
	var k: String = String(powerups[i])
	powerups.erase(i)
	match k:
		"bomb": p.bombs = mini(p.bombs + 1, 8)
		"fire": p.fire = mini(p.fire + 1, 8)
		"speed": p.speed = mini(p.speed + 1, 5)
		"kick": p.kick = true
	events.append(["power", p.tile().x, p.tile().y, p.id, POWERS.find(k)])


func _tick_bombs() -> void:
	for b in bombs.duplicate():
		if b.slide != Vector2i.ZERO:
			b.slide_p += 8.0 * DT
			if b.slide_p >= 1.0:
				var nxt: Vector2i = b.cell + b.slide
				var blocked := not walkable(nxt)
				for p in players:
					if p.alive and p.tile() == nxt: blocked = true
				if blocked: b.slide = Vector2i.ZERO; b.slide_p = 0.0
				else: b.cell = nxt; b.slide_p = 0.0
		b.t -= 1
		if b.t <= 0 and bombs.has(b): _explode(b)


func _explode(b: Bomb) -> void:
	bombs.erase(b)
	var burnt := [b.cell]
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		for r in range(1, b.fire + 1):
			var c: Vector2i = b.cell + d * r
			if not inside(c) or cells[idx(c)] == PILLAR: break
			if cells[idx(c)] == BOX:
				cells[idx(c)] = EMPTY
				var i := idx(c)
				if hidden.has(i): powerups[i] = hidden[i]; hidden.erase(i)
				events.append(["break", c.x, c.y, powerups.get(i, ""), 0])
				flames[i] = FLAME
				break
			burnt.append(c)
	for c in burnt:
		var i := idx(c)
		flames[i] = FLAME
		if powerups.has(i) and c != b.cell: powerups.erase(i); events.append(["burn", c.x, c.y, 0, 0])
	var cells_out := []
	for c in burnt: cells_out.append(idx(c))
	events.append(["boom", b.cell.x, b.cell.y, b.owner, cells_out])
	# chain: bombs in the blast go off now
	for o in bombs.duplicate():
		if flames.has(idx(o.cell)) and bombs.has(o): _explode(o)
	_burn_players(b.owner)


func _burn_players(by: int) -> void:
	for p in players:
		if p.alive and flames.has(idx(p.tile())):
			p.alive = false; p.dead_t = 0; p.moving = false
			if by == p.id: stats.suicides += 1
			else: stats.kills += 1
			events.append(["out", p.tile().x, p.tile().y, p.id, by])


func _tick_flames() -> void:
	for i in flames.keys():
		flames[i] -= 1
		if flames[i] <= 0: flames.erase(i)
	if state == "play" and not flames.is_empty(): _burn_players(-1)


func _sudden_death() -> void:
	if tick_n % 6 != 0 or sd_i >= sd_order.size(): return
	var c: Vector2i = sd_order[sd_i]
	sd_i += 1
	var i := idx(c)
	if cells[i] == PILLAR: return
	cells[i] = PILLAR
	powerups.erase(i)
	var b := bomb_at(c)
	if b != null: bombs.erase(b)
	events.append(["drop", c.x, c.y, 0, 0])
	for p in players:
		if p.alive and (p.tile() == c or (p.moving and p.tgt == c)):
			p.alive = false; p.dead_t = 0; p.moving = false
			events.append(["out", c.x, c.y, p.id, -2])


func _check_round() -> void:
	var n := alive_count()
	if n > 1: return
	state = "roundend"; state_t = ROUND_END
	stats.rounds += 1; stats.round_ticks += int(time * 60.0)
	round_winner = -1
	for p in players:
		if p.alive:
			round_winner = p.id; p.wins += 1
			if p.wins >= WINS: match_winner = p.id
	if match_winner < 0 and round_n >= MAX_ROUNDS:   # long match: most round wins takes it
		var best: Player = players[0]
		for p in players: if p.wins > best.wins: best = p
		match_winner = best.id
	events.append(["roundwin", 0, 0, round_winner, round_n])


# ---------------------------------------------------------------- CPU
## Danger map: tiles that will burn, with ticks until they do (0 = burning now).
func danger() -> Dictionary:
	var out := {}
	for i in flames: out[i] = 0
	var timed := []
	for b in bombs: timed.append([b.cell, b.t, b.fire])
	timed.sort_custom(func(a, c): return a[1] < c[1])
	for e in timed:
		var c0: Vector2i = e[0]
		var t: int = mini(int(e[1]), int(out.get(idx(c0), 9999)))   # set off sooner by a chain
		for c in _blast_cells(c0, int(e[2])):
			out[idx(c)] = mini(int(out.get(idx(c), 9999)), t)
	return out


func _blast_cells(c0: Vector2i, fire: int) -> Array:
	var out := [c0]
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		for r in range(1, fire + 1):
			var c: Vector2i = c0 + d * r
			if not inside(c) or cells[idx(c)] == PILLAR: break
			out.append(c)
			if cells[idx(c)] == BOX: break
	return out


## Breadth-first walk from a tile: returns {index: [dist, first step dir]} over walkable tiles.
func _reach(from: Vector2i, dmap: Dictionary, tpt: int, limit := 40) -> Dictionary:
	var seen := {idx(from): [0, 0]}
	var q := [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		var e: Array = seen[idx(c)]
		if e[0] >= limit: continue
		for d in range(1, 5):
			var n: Vector2i = c + DIRS[d]
			if seen.has(idx(n)) or not walkable(n): continue
			var arrive: int = (e[0] + 1) * tpt
			# don't walk through a tile that is burning when we'd be on it
			if dmap.has(idx(n)) and absi(int(dmap[idx(n)]) - arrive) < 22 + tpt: continue
			if dmap.has(idx(n)) and int(dmap[idx(n)]) == 0: continue
			seen[idx(n)] = [e[0] + 1, d if e[1] == 0 else e[1]]
			q.append(n)
	return seen


func ai(p: Player) -> Dictionary:
	if p.moving: return {}   # finish the step; decide again at the next tile centre
	var tpt: int = int(ceil(60.0 / p.tiles_per_s()))   # ticks per tile
	var dmap := danger()
	var here: Vector2i = p.tile()
	var reach: Dictionary = _reach(here, dmap, tpt)
	var in_danger: bool = dmap.has(idx(here))
	var safe := func(i: int) -> bool: return not dmap.has(i)
	# 1) standing in a blast path: run to the nearest safe tile
	if in_danger:
		var best := -1; var bd := 999
		for i in reach:
			if safe.call(i) and reach[i][0] < bd: bd = reach[i][0]; best = i
		if best >= 0: return {d = int(reach[best][1])}
		return {}
	p.think -= 1
	# 2) bomb now? next to a box, or an enemy in line within reach — only if there's a way out
	var mine := 0
	for b in bombs: if b.owner == p.id: mine += 1
	if mine < p.bombs and bomb_at(here) == null:
		var worth := false
		for d in range(1, 5):
			var n: Vector2i = here + DIRS[d]
			if inside(n) and cells[idx(n)] == BOX: worth = true
		for o in players:
			if o != p and o.alive:
				var ot: Vector2i = o.tile()
				if (ot.x == here.x and absi(ot.y - here.y) <= p.fire) or (ot.y == here.y and absi(ot.x - here.x) <= p.fire):
					if ot.distance_to(here) <= p.fire and _clear_line(here, ot): worth = true
				if absi(ot.x - here.x) + absi(ot.y - here.y) <= 2: worth = true   # close by: box them in
		if worth and rng.randf() < 0.8:
			# would we get away from our own bomb?
			var dm2: Dictionary = dmap.duplicate()
			for c in _blast_cells(here, p.fire): dm2[idx(c)] = mini(int(dm2.get(idx(c), 9999)), FUSE)
			var esc: Dictionary = _reach(here, dmap, tpt, 8)   # the way out must avoid everyone else's bombs too
			for i in esc:
				if not dm2.has(i) and esc[i][0] * tpt < FUSE - 45:
					return {b = true}
	# 3) a power-up nearby
	var target := -1; var td := 999
	for i in powerups:
		if reach.has(i) and reach[i][0] < td and reach[i][0] <= 8: td = reach[i][0]; target = i
	# 4) otherwise go next to a box or toward the nearest enemy
	if target < 0:
		for i in reach:
			var c: Vector2i = Vector2i(i % W, i / W)
			var near_box := false
			for d in range(1, 5):
				var n: Vector2i = c + DIRS[d]
				if inside(n) and cells[idx(n)] == BOX: near_box = true
			var score: int = reach[i][0] + (0 if near_box else 30)
			var hunt := 4 if time < 30.0 else 0   # the longer the round, the harder they hunt
			for o in players:
				if o != p and o.alive: score = mini(score, reach[i][0] + int(o.tile().distance_to(c) * 1.5) + hunt)
			score += rng.randi_range(0, 2)
			if score < td and not dmap.has(i): td = score; target = i
	if target >= 0 and target != idx(here):
		var d: int = int(reach[target][1])
		var n: Vector2i = here + DIRS[d]
		if not dmap.has(idx(n)): return {d = d}
	return {}


func _clear_line(a: Vector2i, b: Vector2i) -> bool:
	var d: Vector2i = Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var c: Vector2i = a + d
	while c != b:
		if cells[idx(c)] != EMPTY: return false
		c += d
	return true


# ---------------------------------------------------------------- snapshot (multiplayer)
func snapshot() -> Dictionary:
	var ps := []
	for p in players:
		ps.append([snappedf(p.pos.x, 0.001), snappedf(p.pos.y, 0.001), p.alive, p.bombs, p.fire, p.speed, p.kick, p.wins, p.facing, p.moving, p.dead_t])
	var bs := []
	for b in bombs: bs.append([b.uid, b.cell.x, b.cell.y, b.t, b.slide.x, b.slide.y, snappedf(b.slide_p, 0.01), b.owner])
	var fl := []
	for i in flames: fl.append([i, flames[i]])
	var pw := []
	for i in powerups: pw.append([i, POWERS.find(powerups[i])])
	var cs := ""
	for c in cells: cs += str(c)
	return {t = tick_n, st = state, stt = state_t, rn = round_n, tm = snappedf(time, 0.01), sd = sd_i, rw = round_winner, mw = match_winner,
		p = ps, b = bs, f = fl, pw = pw, c = cs}


func apply(s: Dictionary) -> void:
	tick_n = int(s.t); state = String(s.st); state_t = int(s.stt); round_n = int(s.rn); time = float(s.tm); sd_i = int(s.sd)
	round_winner = int(s.rw); match_winner = int(s.mw)
	var ps: Array = s.p
	for k in mini(ps.size(), players.size()):
		var p: Player = players[k]
		var a: Array = ps[k]
		p.prev_pos = p.pos
		p.pos = Vector2(float(a[0]), float(a[1]))
		p.alive = bool(a[2]); p.bombs = int(a[3]); p.fire = int(a[4]); p.speed = int(a[5]); p.kick = bool(a[6])
		p.wins = int(a[7]); p.facing = int(a[8]); p.moving = bool(a[9]); p.dead_t = int(a[10])
	bombs.clear()
	for e in s.b:
		var b := Bomb.new()
		b.uid = int(e[0]); b.cell = Vector2i(int(e[1]), int(e[2])); b.t = int(e[3]); b.slide = Vector2i(int(e[4]), int(e[5])); b.slide_p = float(e[6]); b.owner = int(e[7])
		bombs.append(b)
	flames.clear()
	for e in s.f: flames[int(e[0])] = int(e[1])
	powerups.clear()
	for e in s.pw: powerups[int(e[0])] = POWERS[int(e[1])]
	var cs: String = s.c
	for i in mini(cs.length(), cells.size()): cells[i] = int(cs[i])


## Guests between snapshots: keep walkers going the way they were heading.
func coast() -> void:
	for p in players:
		p.prev_pos = p.pos
		if p.alive and p.moving:
			var to: Vector2 = Vector2(p.tile() + DIRS[p.facing])
			p.pos = p.pos.move_toward(to, p.tiles_per_s() * DT)
