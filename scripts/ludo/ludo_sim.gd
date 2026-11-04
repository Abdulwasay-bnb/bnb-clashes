class_name LudoSim
extends RefCounted
## BNB Ludo: the rules, no visuals. Runs on the host (or locally); guests mirror its state.
## Board: a 15 x 15 cross. 52 track squares around it; each colour starts on its own square and walks 50 steps
## round, then 5 squares up its home column to the centre (step 56 = home).
## Rules: a 6 brings a pawn out; landing on a rival (not on a safe square) sends it back to base;
## a 6, a capture or getting a pawn home gives another roll; three 6s in a row lose the turn; exact roll to finish.

const HOME := 56
const COLORS := [Color(0.92, 0.26, 0.3), Color(0.25, 0.78, 0.4), Color(1.0, 0.8, 0.22), Color(0.25, 0.55, 0.95)]
const COLOR_NAMES := ["RED", "GREEN", "YELLOW", "BLUE"]
const SAFE := [1, 9, 14, 22, 27, 35, 40, 48]   # start squares and stars
const TURN_TIME := 20.0                       # online: an idle player's move is made for them

static var TRACK: Array = []                  # 52 grid cells [x, z], clockwise from the left arm

class Player:
	var seat := 0                  # colour 0..3
	var C: Dictionary
	var human := false
	var slot := -1                 # online player index (0 = host); local pass & play: -2
	var tokens: Array = [-1, -1, -1, -1]
	var place := 0                 # finishing place (0 = still playing)

var players: Array = []
var turn := 0                      # index into players
var dice := 0
var phase := "roll"                # roll / move / anim / done
var sixes := 0
var wait := 0.0                    # anim / CPU think / auto-move timer
var idle := 0.0
var finished := 0
var events: Array = []             # new since the last read: [kind, seat, ...]
var rng := RandomNumberGenerator.new()
var rev := 0                       # bumps on every change (guests redraw on new revs)


static func track() -> Array:
	if not TRACK.is_empty(): return TRACK
	var t := []
	for x in range(0, 6): t.append([x, 6])
	for z in range(5, -1, -1): t.append([6, z])
	t.append([7, 0])
	for z in range(0, 6): t.append([8, z])
	for x in range(9, 15): t.append([x, 6])
	t.append([14, 7])
	for x in range(14, 8, -1): t.append([x, 8])
	for z in range(9, 15): t.append([8, z])
	t.append([7, 14])
	for z in range(14, 8, -1): t.append([6, z])
	for x in range(5, -1, -1): t.append([x, 8])
	t.append([0, 7])
	TRACK = t
	return t


## Grid cell of a pawn: base spots, track, home column, centre.
static func cell(seat: int, rel: int, k: int) -> Vector2:
	if rel < 0:
		var corner: Vector2 = [Vector2(2.5, 2.5), Vector2(11.5, 2.5), Vector2(11.5, 11.5), Vector2(2.5, 11.5)][seat]
		return corner + [Vector2(-0.9, -0.9), Vector2(0.9, -0.9), Vector2(-0.9, 0.9), Vector2(0.9, 0.9)][k]
	if rel <= 50:
		var a: Array = track()[(1 + seat * 13 + rel) % 52]
		return Vector2(a[0], a[1])
	if rel < HOME:
		var i := rel - 50   # 1..5
		return [Vector2(i, 7), Vector2(7, i), Vector2(14 - i, 7), Vector2(7, 14 - i)][seat]
	return Vector2(7, 7) + [Vector2(-0.6, 0), Vector2(0, -0.6), Vector2(0.6, 0), Vector2(0, 0.6)][seat] + [Vector2(-0.15, -0.15), Vector2(0.15, -0.15), Vector2(-0.15, 0.15), Vector2(0.15, 0.15)][k]


static func abs_square(seat: int, rel: int) -> int:
	return (1 + seat * 13 + rel) % 52 if rel >= 0 and rel <= 50 else -1


## people: [{C, human, slot}] in seat order; seats: which colours (2 players sit opposite).
func setup(people: Array, seed := 1) -> void:
	rng.seed = seed
	track()
	var seats: Array = [[0], [0, 2], [0, 1, 2], [0, 1, 2, 3]][clampi(people.size(), 1, 4) - 1]
	for k in people.size():
		var p := Player.new()
		p.seat = seats[k]; p.C = people[k].C; p.human = people[k].human; p.slot = int(people[k].get("slot", -1))
		players.append(p)
	turn = 0
	phase = "roll"
	events.append(["turn", players[0].seat])
	rev += 1


func cur() -> Player:
	return players[turn]


func movable() -> Array:
	var p := cur()
	var out := []
	if phase != "move": return out
	for k in 4:
		var r: int = p.tokens[k]
		if r < 0:
			if dice == 6: out.append(k)
		elif r + dice <= HOME:
			out.append(k)
	return out


func roll(forced := 0) -> void:
	if phase != "roll": return
	dice = forced if forced > 0 else rng.randi_range(1, 6)
	idle = 0.0
	events.append(["roll", cur().seat, dice])
	if dice == 6:
		sixes += 1
		if sixes >= 3:
			events.append(["three6", cur().seat])
			_next(false, 0.9); rev += 1; return
	else:
		sixes = sixes
	phase = "move"
	if movable().is_empty():
		events.append(["stuck", cur().seat])
		_next(dice == 6, 0.9)
	rev += 1


func move(k: int) -> void:
	if not (k in movable()): return
	var p := cur()
	var from: int = p.tokens[k]
	var to: int = 0 if from < 0 else from + dice
	p.tokens[k] = to
	idle = 0.0
	events.append(["move", p.seat, k, from, to])
	var again := dice == 6
	# capture
	var sq := abs_square(p.seat, to)
	if sq >= 0 and not (sq in SAFE):
		for o in players:
			if o == p: continue
			for j in 4:
				if abs_square(o.seat, o.tokens[j]) == sq:
					o.tokens[j] = -1
					events.append(["capture", p.seat, o.seat, j])
					again = true
	if to == HOME:
		events.append(["home", p.seat, k])
		again = true
		if p.tokens.all(func(r): return r == HOME):
			finished += 1; p.place = finished
			events.append(["win", p.seat, finished])
			again = false
	var steps := 1 if from < 0 else to - from
	_next(again, 0.25 + steps * 0.14)
	rev += 1


func _next(again: bool, delay: float) -> void:
	phase = "anim"; wait = delay
	if not again:
		sixes = 0
		_advance()
	set_meta("again", again)


func _advance() -> void:
	var n := players.size()
	for i in range(1, n + 1):
		var j := (turn + i) % n
		if (players[j] as Player).place == 0:
			turn = j; return


## Time passes: animations finish, CPU players think, idle online players get moved for.
func update(dt: float) -> void:
	if phase == "done": return
	var left := players.filter(func(p): return p.place == 0).size()
	if left <= 1 and players.size() > 1 or (players.size() == 1 and left == 0):
		if phase != "done":
			for p in players: if p.place == 0: finished += 1; p.place = finished
			phase = "done"; events.append(["done", 0]); rev += 1
		return
	if phase == "anim":
		wait -= dt
		if wait <= 0.0:
			if (cur() as Player).place != 0: _advance()
			phase = "roll"; dice = dice
			events.append(["turn", cur().seat]); rev += 1
		return
	var p := cur()
	if not p.human:
		wait -= dt
		if wait > 0.0: return
		wait = 0.55
		if phase == "roll": roll()
		elif phase == "move": move(best_move())
		return
	idle += dt
	if idle > TURN_TIME and p.slot >= 0:   # online players who wander off
		if phase == "roll": roll()
		elif phase == "move": move(best_move())


## CPU: capture > get home > bring out on a 6 > reach safety > escape danger > furthest along.
func best_move() -> int:
	var opts := movable()
	if opts.is_empty(): return -1
	var p := cur()
	var best: int = opts[0]
	var bs := -INF
	for k in opts:
		var from: int = p.tokens[k]
		var to: int = 0 if from < 0 else from + dice
		var s := 0.0
		var sq := abs_square(p.seat, to)
		if sq >= 0 and not (sq in SAFE):
			for o in players:
				if o != p:
					for j in 4:
						if abs_square(o.seat, o.tokens[j]) == sq: s += 100.0 + o.tokens[j]
		if to == HOME: s += 80.0
		if from < 0: s += 60.0
		if sq in SAFE: s += 25.0
		if to > 50: s += 20.0
		if _danger(p, from) > 0 and from >= 0: s += 30.0
		s -= _danger(p, to) * 35.0
		s += to * 0.3 + rng.randf() * 2.0
		if s > bs: bs = s; best = k
	return best


## How many rival pawns could land on this spot next roll (1..6 behind it).
func _danger(p: Player, rel: int) -> int:
	var sq := abs_square(p.seat, rel)
	if sq < 0 or sq in SAFE: return 0
	var n := 0
	for o in players:
		if o == p: continue
		for j in 4:
			var osq := abs_square(o.seat, o.tokens[j])
			if osq < 0: continue
			var gap := (sq - osq + 52) % 52
			if gap >= 1 and gap <= 6: n += 1
	return n


# ---------------------------------------------------------------- multiplayer
func snapshot() -> Dictionary:
	var ts := []
	var pl := []
	for p in players: ts.append(p.tokens.duplicate()); pl.append(p.place)
	return {tk = ts, pl = pl, turn = turn, dice = dice, ph = phase, rev = rev, idle = snappedf(idle, 0.1)}


func apply(s: Dictionary) -> void:
	for k in mini(players.size(), s.tk.size()):
		var p: Player = players[k]
		for j in 4: p.tokens[j] = int(s.tk[k][j])
		p.place = int(s.pl[k])
	turn = int(s.turn); dice = int(s.dice); phase = String(s.ph); rev = int(s.rev); idle = float(s.get("idle", 0.0))
