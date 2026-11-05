class_name MafiaSim
extends RefCounted
## BNB Mafia: the rules with no visuals. Runs on the host (or locally vs bots).
## Staff do their office tasks; the Mafia hide among them and take them out one by one.
## Finding a body (REPORT) or pressing the ALERT button in the boardroom calls everyone to the table:
## they talk, vote, and the most-voted person is fired. Staff win when every task is done or the Mafia are gone;
## the Mafia win once they match the staff in number.

const DT := 1.0 / 60.0
const SPEED := 4.6
const GHOST_SPEED := 6.0
const RADIUS := 0.38
const KILL_RANGE := 1.9
const USE_RANGE := 1.7
const REPORT_RANGE := 3.2
const VISION := 9.5
const VISION_MAFIA := 12.0
const VISION_DARK := 3.6
const SABOTAGE_COOL := 40.0

## Rooms: name, rect [x0, z0, x1, z1], door sides (n / s / e / w).
const ROOMS := [
	{id = "cafe", name = "CAFETERIA", r = [-30, -20, -14, -8], doors = "es"},
	{id = "dev", name = "DEV PIT", r = [-30, -4, -14, 6], doors = "en"},
	{id = "hr", name = "HR", r = [-30, 10, -14, 20], doors = "en"},
	{id = "server", name = "SERVER ROOM", r = [14, -20, 30, -8], doors = "ws"},
	{id = "storage", name = "STORAGE", r = [14, -4, 30, 6], doors = "wn"},
	{id = "print", name = "PRINT ROOM", r = [14, 10, 30, 20], doors = "wn"},
	{id = "board", name = "BOARDROOM", r = [-8, -7, 8, 7], doors = "nsew"},
	{id = "reception", name = "RECEPTION", r = [-8, 12, 8, 20], doors = "n"},
]
## Task stations: id, kind (minigame), room, position, title.
const STATIONS := [
	{id = "coffee", kind = "coffee", room = "cafe", p = [-27, -17], title = "Brew the coffee"},
	{id = "plant", kind = "plant", room = "cafe", p = [-17, -11], title = "Water the plant"},
	{id = "code", kind = "code", room = "dev", p = [-27, 0], title = "Find the bug"},
	{id = "deploy", kind = "keypad", room = "dev", p = [-18, 3], title = "Approve the deploy"},
	{id = "timesheet", kind = "sign", room = "hr", p = [-27, 17], title = "Sign the timesheet"},
	{id = "files", kind = "shred", room = "hr", p = [-17, 13], title = "Shred old files"},
	{id = "cables", kind = "cables", room = "server", p = [27, -17], title = "Patch the cables"},
	{id = "router", kind = "keypad", room = "server", p = [17, -11], title = "Reboot the router"},
	{id = "boxes", kind = "shred", room = "storage", p = [27, 3], title = "Stack the boxes"},
	{id = "printer", kind = "printer", room = "print", p = [27, 17], title = "Clear the paper jam"},
	{id = "toner", kind = "coffee", room = "print", p = [17, 13], title = "Refill the toner"},
	{id = "mail", kind = "mail", room = "reception", p = [-5, 17], title = "Sort the mail"},
	{id = "visitors", kind = "sign", room = "reception", p = [5, 17], title = "Sign in the visitors"},
]
## Furniture (Kenney Furniture Kit, CC0): model, centre [x, z], turn (degrees), size [w, d, h] in metres
## (model-local, before turning), height off the floor, and whether it blocks walking.
## "rack" is drawn by the game itself (server racks with blinking lights).
const DECOR := [
	# cafeteria
	{m = "kitchenFridgeLarge", p = [-29.0, -19.1], s = [1.2, 0.8, 2.0], block = true},
	{m = "kitchenBar", p = [-25.0, -19.3], s = [3.6, 0.9, 1.0], block = true},
	{m = "kitchenMicrowave", p = [-24.0, -19.3], s = [0.6, 0.45, 0.4], y = 1.0},
	{m = "tableRound", p = [-24.0, -14.0], s = [2.4, 1.6, 0.8], block = true},
	{m = "tableRound", p = [-20.0, -16.0], s = [2.4, 1.6, 0.8], block = true},
	{m = "chair", p = [-25.6, -14.0], r = 90, s = [0.5, 0.5, 0.95]}, {m = "chair", p = [-22.4, -14.0], r = 270, s = [0.5, 0.5, 0.95]},
	{m = "chair", p = [-21.6, -16.0], r = 90, s = [0.5, 0.5, 0.95]}, {m = "chair", p = [-18.4, -16.0], r = 270, s = [0.5, 0.5, 0.95]},
	{m = "trashcan", p = [-14.8, -19.2], s = [0.6, 0.55, 0.9]},
	{m = "pottedPlant", p = [-29.2, -9.0], s = [0.7, 0.7, 1.6]},
	# dev pit: two rows of desks with screens and chairs
	{m = "desk", p = [-25.0, 3.5], s = [2.0, 1.0, 0.76], block = true}, {m = "desk", p = [-21.5, 3.5], s = [2.0, 1.0, 0.76], block = true},
	{m = "desk", p = [-25.0, -2.0], s = [2.0, 1.0, 0.76], block = true}, {m = "desk", p = [-21.5, -2.0], s = [2.0, 1.0, 0.76], block = true},
	{m = "computerScreen", p = [-25.0, 3.6], r = 180, s = [0.8, 0.2, 0.6], y = 0.76}, {m = "computerScreen", p = [-21.5, 3.6], r = 180, s = [0.8, 0.2, 0.6], y = 0.76},
	{m = "computerScreen", p = [-25.0, -2.1], s = [0.8, 0.2, 0.6], y = 0.76}, {m = "computerScreen", p = [-21.5, -2.1], s = [0.8, 0.2, 0.6], y = 0.76},
	{m = "chairDesk", p = [-25.0, 2.4], r = 180, s = [0.8, 0.8, 1.0]}, {m = "chairDesk", p = [-21.5, 2.4], r = 180, s = [0.8, 0.8, 1.0]},
	{m = "chairDesk", p = [-25.0, -0.9], s = [0.8, 0.8, 1.0]}, {m = "chairDesk", p = [-21.5, -0.9], s = [0.8, 0.8, 1.0]},
	{m = "bookcaseOpen", p = [-29.4, 4.0], r = 90, s = [1.6, 0.6, 1.8], block = true},
	{m = "plantSmall1", p = [-15.0, 5.3], s = [0.5, 0.5, 0.7]},
	# HR
	{m = "desk", p = [-23.0, 16.0], s = [2.2, 1.1, 0.76], block = true},
	{m = "laptop", p = [-23.0, 16.1], r = 180, s = [0.6, 0.45, 0.35], y = 0.76},
	{m = "chairDesk", p = [-23.0, 17.3], r = 180, s = [0.8, 0.8, 1.0]},
	{m = "bookcaseClosedWide", p = [-27.5, 10.6], s = [1.8, 0.6, 1.8], block = true},
	{m = "kitchenCabinet", p = [-29.4, 13.5], r = 90, s = [1.0, 0.7, 1.1], block = true},
	{m = "coatRack", p = [-29.3, 19.4], s = [0.6, 0.3, 1.8]},
	{m = "pottedPlant", p = [-14.8, 19.2], s = [0.7, 0.7, 1.6]},
	# server room: racks (blinking lights)
	{m = "rack", p = [20.5, -14.0], s = [1.0, 3.0, 2.2], block = true}, {m = "rack", p = [22.7, -14.0], s = [1.0, 3.0, 2.2], block = true},
	{m = "rack", p = [24.9, -14.0], s = [1.0, 3.0, 2.2], block = true}, {m = "rack", p = [27.1, -14.0], s = [1.0, 3.0, 2.2], block = true},
	{m = "cardboardBoxClosed", p = [29.2, -9.0], s = [0.7, 0.7, 0.7]}, {m = "cardboardBoxOpen", p = [15.0, -19.3], s = [0.9, 0.6, 0.6]},
	# storage: boxes and shelves
	{m = "cardboardBoxClosed", p = [24.0, 0.5], s = [1.3, 1.3, 1.3], block = true},
	{m = "cardboardBoxClosed", p = [24.0, 0.5], s = [0.9, 0.9, 0.9], y = 1.3},
	{m = "cardboardBoxClosed", p = [28.6, -2.6], s = [1.2, 1.2, 1.2], block = true},
	{m = "cardboardBoxOpen", p = [21.0, 4.8], s = [1.4, 0.9, 0.9], block = true},
	{m = "bookcaseClosedWide", p = [29.4, 1.0], r = 270, s = [2.0, 0.6, 1.9], block = true},
	# print room
	{m = "washer", p = [29.2, 12.0], r = 270, s = [1.1, 0.9, 1.2], block = true},
	{m = "table", p = [21.0, 18.8], s = [2.4, 1.0, 0.8], block = true},
	{m = "cardboardBoxOpen", p = [21.0, 18.8], s = [0.6, 0.4, 0.3], y = 0.8},
	{m = "trashcan", p = [15.0, 19.3], s = [0.6, 0.55, 0.9]},
	# boardroom: the long table and plants
	{m = "table", p = [0.0, 0.0], s = [9.0, 4.0, 0.8], block = true},
	{m = "pottedPlant", p = [-7.3, -6.3], s = [0.7, 0.7, 1.6]}, {m = "pottedPlant", p = [7.3, 6.3], s = [0.7, 0.7, 1.6]},
	{m = "pottedPlant", p = [7.3, -6.3], s = [0.7, 0.7, 1.6]},
	# reception: front desk, sofas, rug
	{m = "kitchenBar", p = [0.0, 15.2], s = [5.0, 1.1, 1.05], block = true},
	{m = "laptop", p = [1.5, 15.2], s = [0.6, 0.45, 0.35], y = 1.05},
	{m = "rugRectangle", p = [0.0, 17.6], s = [4.0, 2.0, 0.02]},
	{m = "loungeSofa", p = [-1.6, 19.4], r = 180, s = [2.4, 0.9, 0.9], block = true},
	{m = "loungeChair", p = [1.8, 19.4], r = 180, s = [1.1, 0.9, 0.9], block = true},
	{m = "pottedPlant", p = [-7.4, 12.6], s = [0.7, 0.7, 1.6]}, {m = "pottedPlant", p = [7.4, 12.6], s = [0.7, 0.7, 1.6]},
	# task stations: what each task looks like
	{m = "kitchenCabinet", p = [-27.0, -18.0], s = [1.0, 0.8, 0.95]}, {m = "kitchenCoffeeMachine", p = [-27.0, -18.0], s = [0.5, 0.5, 0.55], y = 0.95},
	{m = "pottedPlant", p = [-16.6, -10.0], s = [0.9, 0.9, 1.8]},
	{m = "deskCorner", p = [-27.8, 0.0], s = [1.4, 1.4, 0.76]}, {m = "computerScreen", p = [-28.0, 0.0], r = 270, s = [0.8, 0.2, 0.6], y = 0.76},
	{m = "laptop", p = [-18.0, 3.6], r = 180, s = [0.6, 0.45, 0.35], y = 0.76},
	{m = "desk", p = [-27.0, 18.2], s = [1.6, 0.8, 0.76]}, {m = "computerKeyboard", p = [-27.0, 18.2], r = 180, s = [0.5, 0.2, 0.05], y = 0.76},
	{m = "cardboardBoxOpen", p = [-16.5, 12.2], s = [0.9, 0.6, 0.6]},
	{m = "speaker", p = [16.2, -11.5], s = [0.4, 0.4, 1.3]},
	{m = "cardboardBoxClosed", p = [28.0, 4.0], s = [0.8, 0.8, 0.8]},
	{m = "washer", p = [28.0, 18.0], s = [1.1, 0.9, 1.2]},
	{m = "kitchenCabinet", p = [16.2, 12.2], s = [0.9, 0.7, 1.0]},
	{m = "bookcaseOpen", p = [-5.0, 18.4], s = [1.4, 0.5, 1.4]},
	{m = "sideTable", p = [5.0, 18.2], s = [1.0, 0.6, 0.8]},
]
const ALERT_POS := Vector2(0, 0)          # the big red button on the boardroom table
const FUSE_POS := Vector2(18, -1)         # power cut gets fixed here (storage)
const SEATS := 10

class Agent:
	var id := 0
	var C: Dictionary
	var human := false
	var slot := -1               # online player index / local player 0
	var mafia := false
	var alive := true
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var dir := Vector2(0, 1)     # facing
	var moving := false
	var tasks: Array = []        # [{st, done}]
	var cool := 0.0              # kill cooldown
	var alerts := 1              # emergency meetings left
	var voted := -2              # -2 = not yet, -1 = skip, else agent id
	var busy := 0.0              # doing a task (bots) / stab animation
	var act := ""                # "task" / "stab" / ""
	var ejected := false
	# bots
	var goal := Vector2.ZERO
	var path_t := 0.0
	var step := Vector2.ZERO
	var think := 0.0
	var seen: Dictionary = {}    # agent id -> [time, pos] last time seen
	var witnessed := -1          # saw this agent kill
	var target := -1             # mafia: who they're stalking
	var said := false

var agents: Array = []
var bodies: Array = []           # [{id, pos}]
var walls: Array = []            # Rect2 (x, z)
var waypoints: Array = []
var links: Array = []
var phase := "play"              # play / meeting / vote / result / done
var phase_t := 0.0
var time := 0.0
var winner := ""                 # "staff" / "mafia"
var win_why := ""
var power_cut := false
var sab_cool := 20.0
var fuse_fix := 0.0
var meeting_by := -1
var meeting_body := -1           # victim id, -1 = alert button
var meeting_room := ""
var ejected := -2                # result: -1 nobody, else id
var tie := false
var chat: Array = []             # [{from, text, ghost}] this meeting
var events: Array = []
var rng := RandomNumberGenerator.new()
var cfg := {mafia = 1, cool = 30.0, talk = 20.0, vote = 40.0, tasks = 5, reveal = true}
var tasks_total := 0
var tasks_done := 0


# ---------------------------------------------------------------- map
func build_map() -> void:
	var T := 0.4
	# outer walls
	walls.append(Rect2(-31, -21, 62, T)); walls.append(Rect2(-31, 20.6, 62, T))
	walls.append(Rect2(-31, -21, T, 42)); walls.append(Rect2(30.6, -21, T, 42))
	for rm in ROOMS:
		var r: Array = rm.r
		var x0: float = r[0]; var z0: float = r[1]; var x1: float = r[2]; var z1: float = r[3]
		var d: String = rm.doors
		_wall_side(x0, z0, x1, z0, "n" in d)   # north edge (low z)
		_wall_side(x0, z1, x1, z1, "s" in d)
		_wall_side(x0, z0, x0, z1, "w" in d)
		_wall_side(x1, z0, x1, z1, "e" in d)
	# furniture that blocks (the view draws the matching models from the same list)
	for d in DECOR:
		if d.get("block", false):
			var sz: Array = d.s
			var r: float = d.get("r", 0.0)
			var w: float = sz[0] if int(r) % 180 == 0 else sz[1]
			var dd: float = sz[1] if int(r) % 180 == 0 else sz[0]
			walls.append(Rect2(float(d.p[0]) - w / 2.0, float(d.p[1]) - dd / 2.0, w, dd))
	for x in range(-29, 30, 2):
		for z in range(-19, 20, 2):
			var p := Vector2(x, z)
			if not blocked(p, 0.6): waypoints.append(p)
	for i in waypoints.size():
		var ln := []
		for j in waypoints.size():
			if i != j and waypoints[i].distance_to(waypoints[j]) < 2.9 and clear(waypoints[i], waypoints[j], 0.35): ln.append(j)
		links.append(ln)


func _wall_side(ax: float, az: float, bx: float, bz: float, door: bool) -> void:
	var T := 0.4
	var gap := 3.2
	if az == bz:   # horizontal
		var mid := (ax + bx) / 2.0
		if door:
			walls.append(Rect2(ax, az - T / 2, mid - gap / 2 - ax, T))
			walls.append(Rect2(mid + gap / 2, az - T / 2, bx - mid - gap / 2, T))
		else:
			walls.append(Rect2(ax, az - T / 2, bx - ax, T))
	else:
		var mid := (az + bz) / 2.0
		if door:
			walls.append(Rect2(ax - T / 2, az, T, mid - gap / 2 - az))
			walls.append(Rect2(ax - T / 2, mid + gap / 2, T, bz - mid - gap / 2))
		else:
			walls.append(Rect2(ax - T / 2, az, T, bz - az))


func blocked(p: Vector2, r: float) -> bool:
	for w in walls:
		if p.x > w.position.x - r and p.x < w.end.x + r and p.y > w.position.y - r and p.y < w.end.y + r: return true
	return false


func clear(a: Vector2, b: Vector2, r := 0.0) -> bool:
	var n := int(a.distance_to(b) / 0.4) + 1
	for k in n + 1:
		if blocked(a.lerp(b, float(k) / n), r): return false
	return true


## Line of sight (walls only, furniture is low enough to see over).
func sees(a: Vector2, b: Vector2) -> bool:
	var n := int(a.distance_to(b) / 0.5) + 1
	for k in range(1, n):
		var p := a.lerp(b, float(k) / n)
		for w in walls:
			if w.size.x * w.size.y < 30.0 and (w.size.x < 0.5 or w.size.y < 0.5) and w.has_point(p): return false
	return true


func room_at(p: Vector2) -> String:
	for rm in ROOMS:
		var r: Array = rm.r
		if p.x >= r[0] and p.x <= r[2] and p.y >= r[1] and p.y <= r[3]: return rm.name
	return "HALLWAY"


func station(id: String) -> Dictionary:
	for s in STATIONS:
		if s.id == id: return s
	return {}


static func st_pos(s: Dictionary) -> Vector2:
	return Vector2(s.p[0], s.p[1])


func _nearest_wp(p: Vector2) -> int:
	var best := 0
	var bd := INF
	for i in waypoints.size():
		var d: float = waypoints[i].distance_squared_to(p)
		if d < bd: bd = d; best = i
	return best


func next_step(a: Vector2, b: Vector2) -> Vector2:
	if clear(a, b, 0.3): return b
	var start := _nearest_wp(a)
	var goal_i := _nearest_wp(b)
	if start == goal_i: return b
	var prev := {start: -1}
	var q := [start]
	while not q.is_empty():
		var c: int = q.pop_front()
		if c == goal_i: break
		for nb in links[c]:
			if not prev.has(nb): prev[nb] = c; q.append(nb)
	if not prev.has(goal_i): return waypoints[links[start][rng.randi() % links[start].size()]] if not links[start].is_empty() else b
	var stp := goal_i
	while prev[stp] != start and prev[stp] != -1: stp = prev[stp]
	# skip ahead while the way is clear
	return waypoints[stp]


# ---------------------------------------------------------------- setup
## people: [{C, human, slot}]. Roles are dealt here (seeded), tasks too.
func setup(people: Array, config: Dictionary, seed := 1) -> void:
	rng.seed = seed
	for k in config: cfg[k] = config[k]
	build_map()
	for k in people.size():
		var a := Agent.new()
		a.id = k; a.C = people[k].C; a.human = people[k].human; a.slot = int(people[k].get("slot", -1))
		agents.append(a)
	var n_mafia := clampi(int(cfg.mafia), 1, maxi(1, (agents.size() - 1) / 2))
	var order := range(agents.size())
	for i in order.size():
		var j := rng.randi_range(i, order.size() - 1)
		var t = order[i]; order[i] = order[j]; order[j] = t
	if cfg.has("force"):   # tests: this agent is (one of) the Mafia
		order.erase(int(cfg.force)); order.push_front(int(cfg.force))
	for k in n_mafia: (agents[order[k]] as Agent).mafia = true
	for a in agents:
		var pool := STATIONS.duplicate()
		for i in pool.size():
			var j := rng.randi_range(i, pool.size() - 1)
			var t = pool[i]; pool[i] = pool[j]; pool[j] = t
		for s in pool.slice(0, int(cfg.tasks)): a.tasks.append({st = String(s.id), done = false})
		a.cool = 12.0
		if not a.mafia: tasks_total += a.tasks.size()
	_gather()
	phase = "play"
	events.append(["start", -1])


## Everyone around the boardroom table (start of game, after each meeting).
func _gather() -> void:
	for k in agents.size():
		var a: Agent = agents[k]
		var ang := TAU * k / maxf(1.0, agents.size())
		a.pos = Vector2(cos(ang) * 6.0, sin(ang) * 3.6)
		if blocked(a.pos, RADIUS): a.pos = Vector2(cos(ang) * 6.5, sin(ang) * 4.6)
		a.prev_pos = a.pos
		a.dir = -a.pos.normalized()
		a.busy = 0.0; a.act = ""; a.voted = -2
		a.step = a.pos; a.path_t = 0.0


func alive_count(mafia: bool) -> int:
	return agents.filter(func(a): return a.alive and a.mafia == mafia).size()


# ---------------------------------------------------------------- tick
## inputs: agent id -> {mx, mz}; actions go through act().
func tick(inputs: Dictionary) -> void:
	events.clear()
	time += DT
	phase_t -= DT
	match phase:
		"play": _play(inputs)
		"meeting":
			for a in agents: a.prev_pos = a.pos
			_bot_chat()
			if phase_t <= 0.0: phase = "vote"; phase_t = float(cfg.vote); events.append(["vote", -1])
		"vote":
			for a in agents: a.prev_pos = a.pos
			_bot_chat()
			_bot_votes()
			var waiting := agents.filter(func(a): return a.alive and a.voted == -2).size()
			if phase_t <= 0.0 or waiting == 0: _count_votes()
		"result":
			for a in agents: a.prev_pos = a.pos
			if phase_t <= 0.0 and winner != "":
				phase = "done"; return
			if phase_t <= 0.0:
				bodies.clear()
				_gather()
				phase = "play"
				for a in agents: a.cool = maxf(a.cool, float(cfg.cool) * 0.6); a.alerts = a.alerts
				sab_cool = maxf(sab_cool, 15.0)
				events.append(["resume", -1])
				_check_win()


func _play(inputs: Dictionary) -> void:
	if sab_cool > 0.0: sab_cool -= DT
	for a in agents:
		a.prev_pos = a.pos
		if a.cool > 0.0 and a.alive: a.cool -= DT
		var inp: Dictionary = inputs.get(a.id, {}) if a.human else _bot(a)
		if a.busy > 0.0:
			a.busy -= DT
			a.moving = false
			if a.busy <= 0.0 and a.act == "task" and not a.human: _bot_finish_task(a)
			if a.busy <= 0.0: a.act = ""
			continue
		var mv := Vector2(float(inp.get("mx", 0.0)), float(inp.get("mz", 0.0)))
		if mv.length() > 1.0: mv = mv.normalized()
		a.moving = mv.length() > 0.1
		if a.moving:
			a.dir = mv.normalized()
			var d := mv * (SPEED if a.alive else GHOST_SPEED) * DT
			for axis in 2:
				var np: Vector2 = a.pos
				np[axis] += d[axis]
				if not blocked(np, RADIUS) or not a.alive and absf(np.x) < 30.5 and absf(np.y) < 20.5: a.pos = np
		if a.alive: _look(a)
	if power_cut: _sab_tick()


## Who can each living agent see right now (bots remember it).
func _look(a: Agent) -> void:
	if a.human: return
	var vis := vision(a)
	for o in agents:
		if o == a or not o.alive: continue
		if a.pos.distance_to(o.pos) < vis and sees(a.pos, o.pos):
			a.seen[o.id] = [time, o.pos]


func vision(a: Agent) -> float:
	if not a.alive: return 40.0
	if a.mafia: return VISION_MAFIA
	return VISION_DARK if power_cut else VISION


func _sab_tick() -> void:
	pass


# ---------------------------------------------------------------- actions (humans and bots)
## a: use / kill / report / alert / sabotage / task_done(st) / vote(target) / chat(text)
func act(id: int, a: String, arg = null) -> bool:
	if id < 0 or id >= agents.size(): return false
	var me: Agent = agents[id]
	match a:
		"kill":
			if phase != "play" or not me.alive or not me.mafia or me.cool > 0.0 or me.busy > 0.0: return false
			var t := kill_target(me)
			if t == null: return false
			t.alive = false
			bodies.append({id = t.id, pos = t.pos})
			me.cool = float(cfg.cool)
			me.pos = t.pos.lerp(me.pos, 0.6)
			me.busy = 0.6; me.act = "stab"
			me.dir = (t.pos - me.pos).normalized() if t.pos != me.pos else me.dir
			events.append(["kill", me.id, t.id])
			# anyone looking saw it
			for o in agents:
				if o.alive and o != me and not o.mafia and o.pos.distance_to(me.pos) < vision(o) and sees(o.pos, me.pos):
					o.witnessed = me.id
			_check_win()
			return true
		"report":
			if phase != "play" or not me.alive: return false
			var b := body_near(me)
			if b.is_empty(): return false
			_meeting(me.id, int(b.id))
			return true
		"alert":
			if phase != "play" or not me.alive or me.alerts <= 0 or me.pos.distance_to(ALERT_POS) > USE_RANGE + 2.5: return false
			me.alerts -= 1
			_meeting(me.id, -1)
			return true
		"sabotage":
			if phase != "play" or not me.alive or not me.mafia or power_cut or sab_cool > 0.0: return false
			power_cut = true; fuse_fix = 0.0
			events.append(["power_cut", me.id])
			return true
		"fix":
			if phase != "play" or not power_cut or not me.alive or me.pos.distance_to(FUSE_POS) > USE_RANGE + 0.6: return false
			power_cut = false; sab_cool = SABOTAGE_COOL
			events.append(["power_on", me.id])
			return true
		"task_done":
			if phase != "play": return false
			var st := String(arg)
			var s := station(st)
			if s.is_empty() or me.pos.distance_to(st_pos(s)) > USE_RANGE + 1.0: return false
			for t in me.tasks:
				if t.st == st and not t.done:
					t.done = true
					if not me.mafia: tasks_done += 1
					events.append(["task", me.id, st])
					_check_win()
					return true
			return false
		"vote":
			if phase != "vote" or not me.alive or me.voted != -2: return false
			var target := int(arg)
			if target != -1 and (target < 0 or target >= agents.size() or not (agents[target] as Agent).alive): return false
			me.voted = target
			events.append(["voted", me.id])
			return true
		"chat":
			if not (phase in ["meeting", "vote", "result"]) and me.alive: return false
			var text := String(arg).strip_edges().left(120)
			if text == "": return false
			var line := {from = me.id, text = text, ghost = not me.alive}
			chat.append(line)
			events.append(["chat", me.id, text, not me.alive])
			return true
	return false


func kill_target(me: Agent) -> Agent:
	var best: Agent = null
	var bd := KILL_RANGE
	for o in agents:
		if o.alive and not o.mafia and o != me and o.pos.distance_to(me.pos) < bd and sees(me.pos, o.pos):
			bd = o.pos.distance_to(me.pos); best = o
	return best


func body_near(me: Agent) -> Dictionary:
	for b in bodies:
		if (b.pos as Vector2).distance_to(me.pos) < REPORT_RANGE and sees(me.pos, b.pos): return b
	return {}


## The task the agent is standing at (not done yet), or {}.
func task_here(me: Agent) -> Dictionary:
	for t in me.tasks:
		if t.done: continue
		var s := station(t.st)
		if me.pos.distance_to(st_pos(s)) < USE_RANGE: return s
	return {}


func _meeting(by: int, body: int) -> void:
	phase = "meeting"; phase_t = float(cfg.talk)
	meeting_by = by; meeting_body = body
	meeting_room = room_at((agents[by] as Agent).pos) if body < 0 else room_at(_body_pos(body))
	power_cut = false
	chat.clear()
	for a in agents: a.voted = -2; a.said = false; a.busy = 0.0; a.act = ""
	events.append(["meeting", by, body])


func _body_pos(id: int) -> Vector2:
	for b in bodies:
		if int(b.id) == id: return b.pos
	return Vector2.ZERO


func _count_votes() -> void:
	var tally := {}
	for a in agents:
		if a.alive and a.voted != -2: tally[a.voted] = tally.get(a.voted, 0) + 1
	var best := -1
	var bn := 0
	tie = false
	for k in tally:
		if tally[k] > bn: bn = tally[k]; best = k; tie = false
		elif tally[k] == bn: tie = true
	ejected = -1 if tie or best == -1 else best
	if ejected >= 0:
		var e: Agent = agents[ejected]
		e.alive = false; e.ejected = true
	phase = "result"; phase_t = 6.0
	events.append(["result", ejected, ejected >= 0 and (agents[ejected] as Agent).mafia])
	_check_win()


func votes_for(id: int) -> int:
	return agents.filter(func(a): return a.alive and a.voted == id or (a.ejected and a.voted == id)).size()


func _check_win() -> void:
	if winner != "": return
	var m := alive_count(true)
	var s := alive_count(false)
	if m == 0: _win("staff", "THE MAFIA ARE GONE")
	elif tasks_total > 0 and tasks_done >= tasks_total: _win("staff", "EVERY TASK DONE")
	elif m >= s: _win("mafia", "THE MAFIA TOOK OVER")


func _win(w: String, why: String) -> void:
	winner = w; win_why = why
	if phase != "result": phase = "done"
	events.append(["win", -1, w, why])


## After the result screen the game ends if someone won during it.
func finished() -> bool:
	return winner != "" and phase != "result"


# ---------------------------------------------------------------- bots
func _bot(a: Agent) -> Dictionary:
	if a.busy > 0.0: return {}
	a.think -= DT
	var target_pos := a.goal
	if not a.alive:
		# ghosts float to their unfinished tasks
		var todo := a.tasks.filter(func(t): return not t.done)
		if a.mafia or todo.is_empty(): return {}
		var s := station(todo[0].st)
		if a.pos.distance_to(st_pos(s)) < 1.0:
			a.busy = rng.randf_range(3.0, 5.0); a.act = "task"; return {}
		return _toward(a, st_pos(s))
	# staff: report bodies they see
	if not a.mafia or rng.randf() < 0.004:
		for b in bodies:
			if (b.pos as Vector2).distance_to(a.pos) < vision(a) and sees(a.pos, b.pos):
				if (b.pos as Vector2).distance_to(a.pos) < REPORT_RANGE - 0.4:
					act(a.id, "report")
					return {}
				else:
					return _toward(a, b.pos)
	if power_cut and not a.mafia and _fixer(a):
		if a.pos.distance_to(FUSE_POS) < USE_RANGE: act(a.id, "fix"); return {}
		return _toward(a, FUSE_POS)
	if a.mafia:
		return _mafia_bot(a)
	return _task_bot(a)


## During a power cut: is this one of the two living staff nearest the fuse box?
func _fixer(a: Agent) -> bool:
	var d := a.pos.distance_to(FUSE_POS)
	var closer := 0
	for o in agents:
		if o != a and o.alive and not o.mafia and o.pos.distance_to(FUSE_POS) < d: closer += 1
	return closer < 2


func _task_bot(a: Agent) -> Dictionary:
	var todo := a.tasks.filter(func(t): return not t.done)
	if todo.is_empty():
		if a.think <= 0.0 or a.pos.distance_to(a.goal) < 1.2:
			a.think = rng.randf_range(4.0, 9.0)
			a.goal = st_pos(STATIONS[rng.randi() % STATIONS.size()]) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		return _toward(a, a.goal)
	var s := station(todo[0].st)
	var sp := st_pos(s)
	if a.pos.distance_to(sp) < 1.0:
		a.busy = rng.randf_range(3.5, 7.0); a.act = "task"
		return {}
	return _toward(a, sp)


func _bot_finish_task(a: Agent) -> void:
	var s := task_here(a)
	if not s.is_empty(): act(a.id, "task_done", s.id)
	elif a.mafia:
		# fake task: tick one off their pretend list so they move on
		for t in a.tasks:
			if not t.done and a.pos.distance_to(st_pos(station(t.st))) < USE_RANGE + 1.0:
				t.done = true; break


func _mafia_bot(a: Agent) -> Dictionary:
	if sab_cool <= 0.0 and not power_cut and rng.randf() < 0.0015: act(a.id, "sabotage")
	if a.cool <= 0.0:
		# a lone victim nobody else can see
		var t := kill_target(a)
		if t != null and _unwatched(a, t):
			act(a.id, "kill"); return {}
		if a.target < 0 or not (agents[a.target] as Agent).alive or a.think <= 0.0:
			a.think = rng.randf_range(2.0, 4.0)
			a.target = -1
			var bd := 24.0
			for o in agents:
				if o.alive and not o.mafia and o.pos.distance_to(a.pos) < bd and _unwatched(a, o):
					bd = o.pos.distance_to(a.pos); a.target = o.id
		if a.target >= 0:
			return _toward(a, (agents[a.target] as Agent).pos)
	# blend in: wander between task stations and pretend
	if a.pos.distance_to(a.goal) < 1.0 and a.busy <= 0.0:
		if rng.randf() < 0.5: a.busy = rng.randf_range(2.5, 5.0); a.act = "task"
		a.goal = st_pos(STATIONS[rng.randi() % STATIONS.size()])
	if a.goal == Vector2.ZERO: a.goal = st_pos(STATIONS[rng.randi() % STATIONS.size()])
	return _toward(a, a.goal)


## Nobody else (alive, not mafia) could see the killer or the victim.
func _unwatched(k: Agent, v: Agent) -> bool:
	for o in agents:
		if o == k or o == v or not o.alive or o.mafia: continue
		if o.pos.distance_to(v.pos) < vision(o) + 1.0 and (sees(o.pos, v.pos) or sees(o.pos, k.pos)): return false
	return true


func _toward(a: Agent, p: Vector2) -> Dictionary:
	a.path_t -= DT
	if a.path_t <= 0.0 or a.pos.distance_to(a.step) < 0.5:
		a.path_t = 0.5
		a.step = next_step(a.pos, p)
	var d := a.step - a.pos
	if d.length() < 0.05: return {}
	d = d.normalized()
	return {mx = d.x, mz = d.y}


# meeting bots: a few lines each, then a vote
func _bot_chat() -> void:
	for a in agents:
		if a.human or a.said or not a.alive or rng.randf() > (0.05 if a.witnessed >= 0 else 0.012): continue
		a.said = true
		var line := ""
		if a.witnessed >= 0 and (agents[a.witnessed] as Agent).alive:
			line = ["I SAW %s DO IT!", "it was %s, i watched it happen", "%s. 100%%. i saw them."].pick_random() % _nm(agents[a.witnessed])
		elif a.id == meeting_by and meeting_body >= 0:
			line = "found %s in %s" % [_nm(agents[meeting_body]), meeting_room.to_lower()]
		elif a.id == meeting_by:
			line = ["someone's acting weird", "who's been near %s?" % meeting_room.to_lower(), "quick check, where is everyone?"].pick_random()
		elif a.mafia and rng.randf() < 0.5:
			var o := _random_staff(a)
			line = ["i was doing tasks in %s" % ["the cafeteria", "hr", "the print room", "storage"].pick_random(),
				"%s was following me earlier..." % _nm(o) if o != null else "skip?", "skip, not enough info"].pick_random()
		else:
			var s := _suspect(a)
			if s >= 0 and rng.randf() < 0.6: line = ["%s was near there", "sus: %s", "where was %s?"].pick_random() % _nm(agents[s])
			else: line = ["i was in %s" % room_at(a.pos).to_lower(), "i was doing my tasks", "skip?", "no idea, skip", "anyone see anything?"].pick_random()
		act(a.id, "chat", line)


func _nm(a: Agent) -> String:
	return String(a.C.person.get("short", a.C.name)) if a.C.has("person") else String(a.C.name)


func _random_staff(me: Agent) -> Agent:
	var o := agents.filter(func(x): return x.alive and not x.mafia and x != me)
	return null if o.is_empty() else o[rng.randi() % o.size()]


## Who this bot thinks it was: a witness knows; otherwise whoever they last saw near the body.
func _suspect(a: Agent) -> int:
	if a.witnessed >= 0 and (agents[a.witnessed] as Agent).alive: return a.witnessed
	if meeting_body >= 0:
		var bp := _body_pos(meeting_body)
		var best := -1
		var bt := -INF
		for id in a.seen:
			var s: Array = a.seen[id]
			var o: Agent = agents[id]
			if o.alive and o != a and (s[1] as Vector2).distance_to(bp) < 8.0 and time - float(s[0]) < 25.0 and float(s[0]) > bt:
				bt = float(s[0]); best = id
		return best
	# what the others in chat said
	for c in chat:
		for o in agents:
			if o.alive and o != a and String(c.text).to_upper().find(_nm(o).to_upper()) >= 0 and rng.randf() < 0.5: return o.id
	return -1


## Someone said they SAW a name (or "it was X"): who, and who said it.
func _accusation() -> Array:
	for c in chat:
		var t := String(c.text).to_upper()
		if c.ghost or not (t.find("SAW") >= 0 or t.find("IT WAS") >= 0 or t.find("100%") >= 0): continue
		for o in agents:
			if o.alive and o.id != int(c.from) and t.find(_nm(o).to_upper()) >= 0: return [o.id, int(c.from)]
	return []


func _bot_votes() -> void:
	var acc := _accusation()
	for a in agents:
		if a.human or not a.alive or a.voted != -2 or rng.randf() > 0.02: continue
		var v := -1
		if a.mafia:
			# accused? push back on the accuser. otherwise vote with the crowd against staff, or skip
			if not acc.is_empty() and (agents[acc[0]] as Agent).mafia and not (agents[acc[1]] as Agent).mafia:
				v = acc[1]
			else:
				var counts := {}
				for o in agents: if o.alive and o.voted >= 0 and not (agents[o.voted] as Agent).mafia: counts[o.voted] = counts.get(o.voted, 0) + 1
				for k in counts: v = k
				if v < 0 and rng.randf() < 0.3:
					var o := _random_staff(a)
					if o != null: v = o.id
		elif a.witnessed >= 0 and (agents[a.witnessed] as Agent).alive:
			v = a.witnessed
		elif not acc.is_empty() and acc[0] != a.id and rng.randf() < 0.75:
			v = acc[0]                       # believe the witness
		else:
			v = _suspect(a)
			if v >= 0 and rng.randf() < 0.45: v = -1
		act(a.id, "vote", v)
		# mafia defend themselves once
		if a.mafia and not acc.is_empty() and acc[0] == a.id and not a.said:
			a.said = true
			act(a.id, "chat", ["%s is lying!", "what? i was nowhere near. %s is sus", "no way, %s is framing me"].pick_random() % _nm(agents[acc[1]]))


# ---------------------------------------------------------------- multiplayer
## Public state everyone can know (no roles, no tasks).
func snapshot() -> Dictionary:
	var ag := []
	for a in agents:
		ag.append(Party.pack([a.pos.x, a.pos.y, a.dir.x, a.dir.y, a.moving, a.alive, a.act, a.voted != -2, a.ejected]))
	var bs := []
	for b in bodies: bs.append(Party.pack([b.id, b.pos.x, b.pos.y]))
	return {ph = phase, pt = snappedf(phase_t, 0.1), a = ag, b = bs, pc = power_cut, td = tasks_done, tt = tasks_total,
		mb = meeting_by, mbody = meeting_body, mr = meeting_room, ej = ejected, tie = tie, win = winner, why = win_why, t = snappedf(time, 0.01)}


## Private state for one player: role, mafia team-mates (if mafia), their tasks, cooldowns.
func private_for(id: int) -> Dictionary:
	var a: Agent = agents[id]
	var team := []
	if a.mafia:
		for o in agents: if o.mafia: team.append(o.id)
	var ts := []
	for t in a.tasks: ts.append([t.st, t.done])
	return {mafia = a.mafia, team = team, tasks = ts, cool = snappedf(a.cool, 0.1), alerts = a.alerts, sab = snappedf(sab_cool, 0.1), voted = a.voted}


## Final reveal (results screen): every role.
func roles() -> Array:
	return agents.map(func(a): return a.mafia)


func apply(s: Dictionary) -> void:
	phase = String(s.ph); phase_t = float(s.pt); power_cut = bool(s.pc); tasks_done = int(s.td); tasks_total = int(s.tt)
	meeting_by = int(s.mb); meeting_body = int(s.mbody); meeting_room = String(s.mr); ejected = int(s.ej); tie = bool(s.tie)
	winner = String(s.win); win_why = String(s.why); time = float(s.t)
	for k in mini(agents.size(), s.a.size()):
		var a: Agent = agents[k]
		var v: Array = s.a[k]
		a.prev_pos = a.pos
		a.pos = Vector2(v[0], v[1]); a.dir = Vector2(v[2], v[3]); a.moving = bool(v[4]); a.alive = bool(v[5]); a.act = String(v[6])
		a.voted = (a.voted if a.voted != -2 else -3) if bool(v[7]) else -2
		a.ejected = bool(v[8])
	bodies.clear()
	for b in s.b: bodies.append({id = int(b[0]), pos = Vector2(b[1], b[2])})


func apply_private(p: Dictionary, id: int) -> void:
	var a: Agent = agents[id]
	a.mafia = bool(p.mafia)
	for o in agents: if o != a: o.mafia = false
	for t in p.team: (agents[int(t)] as Agent).mafia = true
	a.tasks = []
	for t in p.tasks: a.tasks.append({st = String(t[0]), done = bool(t[1])})
	a.cool = float(p.cool); a.alerts = int(p.alerts); sab_cool = float(p.sab); a.voted = int(p.voted)


func coast() -> void:
	for a in agents:
		a.prev_pos = a.pos
		if a.moving and phase == "play": a.pos += a.dir * (SPEED if a.alive else GHOST_SPEED) * DT
