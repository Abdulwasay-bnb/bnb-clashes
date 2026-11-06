class_name OpsSim
extends RefCounted
## BNB Office Ops: team deathmatch rules with no visuals. Soldiers, guns, vests, hits, bots, score.
## Runs at 60 ticks/s on the host; in multiplayer, guests send controls and draw the host's snapshots.

const DT := 1.0 / 60.0
const EYE := 1.6
const EYE_CROUCH := 1.1
const RADIUS := 0.4
const WALK := 5.2
const SPRINT := 7.6
const CROUCH_SPEED := 2.6
const GRAVITY := 22.0

## Guns: damage per bullet, rounds per minute, magazine, spread (radians, hip / aimed), pellets, range
## where damage starts to fall off, zoom (camera FOV when aiming), reload time, headshot multiplier.
const GUNS := {
	"pistol": {name = "P-9 PISTOL", dmg = 24.0, rpm = 330.0, mag = 12, spread = 0.035, ads_spread = 0.008, pellets = 1, falloff = 25.0, fov = 60.0, reload = 1.3, head = 2.0, auto = false, recoil = 0.018},
	"smg": {name = "SPRINT SMG", dmg = 17.0, rpm = 820.0, mag = 30, spread = 0.05, ads_spread = 0.018, pellets = 1, falloff = 20.0, fov = 56.0, reload = 1.8, head = 1.6, auto = true, recoil = 0.012},
	"rifle": {name = "KPI-47 RIFLE", dmg = 27.0, rpm = 600.0, mag = 30, spread = 0.04, ads_spread = 0.006, pellets = 1, falloff = 45.0, fov = 48.0, reload = 2.1, head = 1.9, auto = true, recoil = 0.016},
	"shotgun": {name = "BREAKROOM SHOTGUN", dmg = 13.0, rpm = 75.0, mag = 6, spread = 0.11, ads_spread = 0.075, pellets = 9, falloff = 9.0, fov = 62.0, reload = 2.6, head = 1.4, auto = false, recoil = 0.05},
	"sniper": {name = "DEADLINE SNIPER", dmg = 92.0, rpm = 45.0, mag = 5, spread = 0.09, ads_spread = 0.0008, pellets = 1, falloff = 120.0, fov = 15.0, reload = 2.8, head = 2.5, auto = false, recoil = 0.06},
	"dmr": {name = "AUDIT DMR", dmg = 44.0, rpm = 260.0, mag = 15, spread = 0.035, ads_spread = 0.002, pellets = 1, falloff = 70.0, fov = 38.0, reload = 2.3, head = 2.2, auto = false, recoil = 0.03},
	"lmg": {name = "BOARDROOM LMG", dmg = 24.0, rpm = 700.0, mag = 100, spread = 0.065, ads_spread = 0.022, pellets = 1, falloff = 35.0, fov = 54.0, reload = 4.2, head = 1.6, auto = true, recoil = 0.013, slow = 0.85},
	"marshal": {name = "MARSHAL SCOUT", dmg = 74.0, rpm = 75.0, mag = 6, spread = 0.07, ads_spread = 0.0015, pellets = 1, falloff = 90.0, fov = 26.0, reload = 2.4, head = 2.0, auto = false, recoil = 0.045},
	# sidearms
	"sheriff": {name = "SHERIFF .44", dmg = 52.0, rpm = 140.0, mag = 6, spread = 0.03, ads_spread = 0.004, pellets = 1, falloff = 30.0, fov = 58.0, reload = 2.0, head = 2.6, auto = false, recoil = 0.05, side = true},
	"mpistol": {name = "STAPLER MACHINE PISTOL", dmg = 14.0, rpm = 950.0, mag = 22, spread = 0.06, ads_spread = 0.026, pellets = 1, falloff = 14.0, fov = 62.0, reload = 1.5, head = 1.5, auto = true, recoil = 0.011, side = true},
}
const PRIMARIES := ["rifle", "smg", "shotgun", "sniper", "dmr", "lmg", "marshal"]
const SIDEARMS := ["pistol", "sheriff", "mpistol"]
## Throwables: fuse (ticks), radius, and what they do.
const NADES := {"frag": {name = "FRAG GRENADE", fuse = 110, r = 6.0, dmg = 115.0},
	"flash": {name = "FLASHBANG", fuse = 80, r = 24.0},
	"molly": {name = "MOLOTOV", fuse = 150, r = 3.4, burn = 360, dps = 32.0}}
const NADE_KINDS := ["frag", "flash", "molly"]
const NADE_MAX := 2
const PROTECT := 150          # 2.5 s after spawning: can't be hurt and can't shoot
## What lies on each team's loadout table (guns and throwables, taken with E; the table never runs out).
const TABLE_ITEMS := ["rifle", "smg", "shotgun", "dmr", "lmg", "sniper", "marshal", "sheriff", "mpistol", "frag", "flash", "molly"]

class Soldier:
	var id := 0
	var team := 0
	var C: Dictionary
	var human := -1
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var yaw := 0.0            # 0 = looking toward +Z
	var pitch := 0.0
	var on_floor := true
	var crouch := false
	var sprint := false
	var ads := false
	var hp := 100.0
	var armor := 50.0
	var max_armor := 50.0
	var guns: Array = ["rifle", "pistol"]
	var slot := 0              # 0 primary, 1 sidearm, 2 throwable
	var nades := {"frag": 0, "flash": 0, "molly": 0}
	var nade_sel := "frag"
	var blind := 0             # flashbanged: ticks left
	var held_use := false
	var mag: Array = [30, 12]
	var reserve: Array = [120, 48]
	var reload_t := 0
	var cool := 0
	var recoil := 0.0
	var alive := true
	var respawn := 0
	var protect := 0           # spawn protection ticks
	var kills := 0
	var deaths := 0
	var held_fire := false     # semi-auto guns need a fresh press
	var hurt_dir := Vector3.ZERO
	var hurt_t := 0
	# bots
	var target := -1
	var react := 0
	var wander := Vector3.ZERO
	var goal_pos := Vector3.ZERO
	var stuck_at := Vector3.ZERO
	var stuck_t := 0
	var strafe_dir := 1.0
	var think := 0
	var prev_pos := Vector3.ZERO
	var prev_yaw := 0.0

	func gun() -> Dictionary: return OpsSim.GUNS[guns[mini(slot, 1)]]
	func holding() -> String: return nade_sel if slot == 2 else String(guns[slot])
	func eye() -> Vector3: return pos + Vector3(0, OpsSim.EYE_CROUCH if crouch else OpsSim.EYE, 0)
	func aim_dir() -> Vector3: return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))

var boxes: Array = []          # cover / walls: AABB (position = min corner)
var spawns: Array = [[], []]   # team -> spawn points
var waypoints: Array = []      # where bots roam
var links: Array = []          # waypoint index -> neighbour indices (clear straight paths)
var soldiers: Array = []
var score := [0, 0]
var goal := 20
var time := 0.0
var time_limit := 300.0
var state := "warmup"          # warmup / play / done
var warm := 120
var tick_n := 0
var events: Array = []         # [kind, pos, a, b]: shot / hit / kill / reload / respawn / tracer
var tables: Array = []         # per team: {pos, yaw, items: [{kind, pos}]}
var thrown: Array = []         # grenades in flight: {uid, kind, pos, vel, t, by}
var fires: Array = []          # molotov fires burning: {uid, pos, t, by}
var next_uid := 1
var map_id := "office"
var kinds: Array = []          # per box: what it is (the view picks the look): wall, pillar, glass, rack, cubicle, desk, crate, shelf, car...
var bounds := Rect2(-28, -19, 56, 38)   # where bots may roam
var ceiling := 4.0             # 0 = open sky

const MAPS := {
	"office": {name = "OFFICE FLOOR", sub = "Cubicles, meeting rooms and server racks"},
	"warehouse": {name = "WAREHOUSE", sub = "Tall shelving aisles, crates and forklifts"},
	"garage": {name = "PARKING GARAGE", sub = "Low ceiling, pillars and parked cars"},
	"rooftop": {name = "ROOFTOP", sub = "Open sky: AC units, water tanks and a helipad"},
}
var rng := RandomNumberGenerator.new()
var bot_skill := 1.0


func _box(x: float, z: float, sx: float, sz: float, h: float, kind: String) -> void:
	boxes.append(AABB(Vector3(x - sx / 2.0, 0.0, z - sz / 2.0), Vector3(sx, h, sz)))
	kinds.append(kind)


func build_map() -> void:
	match map_id:
		"warehouse": _map_warehouse()
		"garage": _map_garage()
		"rooftop": _map_rooftop()
		_: _map_office()
	_add_table(0, Vector3(bounds.position.x + 3.5, 0, 0), PI / 2.0)
	_add_table(1, Vector3(bounds.end.x - 3.5, 0, 0), -PI / 2.0)
	_build_waypoints()


## Warehouse: 70 x 50 m, four rows of tall shelving with aisles through them, crates and forklifts in the lanes.
func _map_warehouse() -> void:
	ceiling = 7.0
	bounds = Rect2(-33, -23, 66, 46)
	_box(0, -25.5, 72, 1, 7, "wall"); _box(0, 25.5, 72, 1, 7, "wall"); _box(-35.5, 0, 1, 52, 7, "wall"); _box(35.5, 0, 1, 52, 7, "wall")
	for z in [-15.0, -5.0, 5.0, 15.0]:
		for seg in [[-25.0, 10.0], [-9.0, 14.0], [9.0, 14.0], [25.0, 10.0]]:   # gaps make cross aisles
			_box(seg[0], z, seg[1], 1.4, 4.5, "shelf")
	var crates := [[-14, -10, 1.5], [-12.4, -10, 3.0], [12, 10, 1.5], [13.6, 10, 3.0], [0, -20, 1.5], [0, 20, 1.5], [-22, 0, 1.5], [22, 0, 1.5],
		[-4, 0, 3.0], [4, 0, 1.5], [-17, 20, 1.5], [17, -20, 1.5], [0, 10, 1.5], [0, -10, 1.5]]
	for c in crates: _box(c[0], c[1], 1.5, 1.5, c[2], "crate")
	for f in [[-8, 10], [8, -10], [-26, -20], [26, 20]]: _box(f[0], f[1], 1.4, 2.6, 2.2, "forklift")
	for pl in [[-18, -10], [18, 10], [-6, 20], [6, -20]]: _box(pl[0], pl[1], 2.4, 2.0, 0.5, "pallet")
	for i in 6:
		spawns[0].append(Vector3(-32.0 + (i % 2) * 1.6, 0, -8.0 + i * 3.2))
		spawns[1].append(Vector3(32.0 - (i % 2) * 1.6, 0, -8.0 + i * 3.2))


## Parking garage: 60 x 44 m under a low ceiling, a grid of pillars, rows of parked cars, barriers and a booth.
func _map_garage() -> void:
	ceiling = 3.2
	bounds = Rect2(-28, -19, 56, 38)
	_box(0, -22.5, 62, 1, 3.2, "wall"); _box(0, 22.5, 62, 1, 3.2, "wall"); _box(-30.5, 0, 1, 46, 3.2, "wall"); _box(30.5, 0, 1, 46, 3.2, "wall")
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		for z in [-14.0, -6.0, 6.0, 14.0]:
			_box(x, z, 0.9, 0.9, 3.2, "pillar")
	var rng2 := RandomNumberGenerator.new(); rng2.seed = 3
	for z in [-18.0, -10.0, 10.0, 18.0]:   # parking bays: cars nose-in, some bays empty
		for x in range(-22, 23, 3):
			if rng2.randf() < 0.62 and absf(float(x)) > 2.0: _box(float(x), z, 1.9, 4.2, 1.45, "car")
	for b in [[-12, 0, 3.2], [12, 0, 3.2], [0, -2.5, 3.2], [0, 2.5, 3.2]]: _box(b[0], b[1], 0.6, b[2], 1.0, "barrier")
	_box(-20, 0, 2.6, 2.6, 2.6, "booth"); _box(20, 0, 2.6, 2.6, 2.6, "booth")
	for x in [-8.0, 8.0]: _box(x, 0, 1.9, 4.2, 1.45, "car")
	for i in 6:
		spawns[0].append(Vector3(-27.6 + (i % 2) * 1.2, 0, -6.0 + i * 2.4))
		spawns[1].append(Vector3(27.6 - (i % 2) * 1.2, 0, -6.0 + i * 2.4))


## Rooftop: 60 x 44 m in the open, a low parapet round the edge, AC units, water tanks, the stair housing,
## rows of solar panels (low: you can stand on them) and a helipad in the middle.
func _map_rooftop() -> void:
	ceiling = 0.0
	bounds = Rect2(-28, -19, 56, 38)
	_box(0, -22.2, 62, 0.6, 1.2, "parapet"); _box(0, 22.2, 62, 0.6, 1.2, "parapet"); _box(-30.2, 0, 0.6, 45, 1.2, "parapet"); _box(30.2, 0, 0.6, 45, 1.2, "parapet")
	_box(0, -14, 8, 5, 3.6, "housing")
	for t in [[-16, 12], [16, -12], [-6, 16]]: _box(t[0], t[1], 3.2, 3.2, 4.2, "tank")
	for a in [[-12, -6], [-12, -3.6], [12, 6], [12, 3.6], [-20, 15], [20, -15], [4, 8], [-4, -8], [22, 10], [-22, -10]]: _box(a[0], a[1], 2.2, 2.2, 1.7, "ac")
	for z in [-18.0, 18.0]:
		for x in [-12.0, -4.0, 4.0]:
			_box(x if z < 0 else -x, z, 6.0, 1.6, 0.9, "solar")
	for v in [[-8, 4], [8, -4]]: _box(v[0], v[1], 0.8, 4.0, 1.3, "vent")
	for i in 6:
		spawns[0].append(Vector3(-27.6 + (i % 2) * 1.2, 0, -6.0 + i * 2.4))
		spawns[1].append(Vector3(27.6 - (i % 2) * 1.2, 0, -6.0 + i * 2.4))


## Office floor: 64 x 44 m, cubicles and desks in the middle, server racks and meeting rooms at the ends.
func _map_office() -> void:
	var add := func(x: float, z: float, sx: float, sz: float, h := 1.2):
		var k := "desk"
		if h >= 4.0: k = "wall" if (absf(x) > 30.0 or absf(z) > 21.0) else "pillar"
		elif h >= 2.9: k = "glass"
		elif h >= 2.2: k = "rack"
		elif h >= 1.4: k = "cubicle"
		_box(x, z, sx, sz, h, k)
	# outer walls
	add.call(0, -22.5, 66, 1, 4); add.call(0, 22.5, 66, 1, 4); add.call(-32.5, 0, 1, 46, 4); add.call(32.5, 0, 1, 46, 4)
	# meeting rooms (glass walls) at both ends with doors
	for side in [-1.0, 1.0]:
		add.call(side * 22.0, -12.0, 1.0, 10.0, 3.0); add.call(side * 22.0, 12.0, 1.0, 10.0, 3.0)
		add.call(side * 27.0, -7.0, 10.0, 1.0, 3.0); add.call(side * 27.0, 7.0, 10.0, 1.0, 3.0)
	# cubicle rows: low walls, desks
	for row in [-14.0, -6.0, 6.0, 14.0]:
		for col in [-12.0, -4.0, 4.0, 12.0]:
			add.call(col, row, 5.0, 0.3, 1.5)          # cubicle wall
			add.call(col - 1.2, row + 1.0, 1.8, 0.9, 0.8)   # desk
	# pillars and server racks in the centre
	for p in [[-8.0, 0.0], [8.0, 0.0], [0.0, -10.0], [0.0, 10.0]]:
		add.call(p[0], p[1], 1.4, 1.4, 4.0)
	add.call(0, 0, 1.2, 6.0, 2.3)
	add.call(-16.0, 0.0, 1.2, 4.0, 2.3); add.call(16.0, 0.0, 1.2, 4.0, 2.3)
	for i in 6:
		spawns[0].append(Vector3(-29.0 + (i % 2) * 2.0, 0, -9.0 + i * 3.6))
		spawns[1].append(Vector3(29.0 - (i % 2) * 2.0, 0, -9.0 + i * 3.6))



func _build_waypoints() -> void:
	for x in range(int(bounds.position.x), int(bounds.end.x) + 1, 4):
		for z in range(int(bounds.position.y), int(bounds.end.y) + 1, 4):
			var p := Vector3(x, 0, z)
			if not _blocked(p, 0.7): waypoints.append(p)
	# connect neighbours that have a clear walk between them
	for i in waypoints.size():
		var ln := []
		for j in waypoints.size():
			if i != j and waypoints[i].distance_to(waypoints[j]) < 6.0 and _clear(waypoints[i], waypoints[j]): ln.append(j)
		links.append(ln)


## A loadout table in a team's spawn: a long low table (solid cover) with every gun and throwable on it.
## yaw = the way the table faces (toward the map); items are spread along it.
func _add_table(team: int, at: Vector3, yaw: float) -> void:
	var along := Vector3(cos(yaw), 0, -sin(yaw))   # the table runs across the facing direction
	var length := 6.4
	var half := (along * length / 2.0).abs() + (Vector3(sin(yaw), 0, cos(yaw)) * 0.5).abs()
	boxes.append(AABB(Vector3(at.x - half.x, 0.0, at.z - half.z), Vector3(half.x * 2.0, 0.9, half.z * 2.0)))
	kinds.append("loadout")
	var items := []
	for k in TABLE_ITEMS.size():
		var u := (k + 0.5) / TABLE_ITEMS.size() - 0.5
		items.append({kind = TABLE_ITEMS[k], pos = at + along * u * (length - 0.4) + Vector3(0, 0.95, 0)})
	tables.append({team = team, pos = at, yaw = yaw, items = items})


## The table item a soldier would take now: within reach, the one closest to where they look (empty = none).
func pick_target(s: Soldier) -> Dictionary:
	if not s.alive: return {}
	var best := {}
	var bs := -INF
	var look := s.aim_dir()
	for t in tables:
		if t.team != s.team: continue
		for it in t.items:
			var d: Vector3 = it.pos - s.eye()
			var flat := Vector2(d.x, d.z).length()
			if flat > 2.1: continue
			var score: float = look.dot(d.normalized()) - flat * 0.02   # where you look matters most
			if score > bs: bs = score; best = it
	return best


func _take(s: Soldier, it: Dictionary) -> void:
	var kind: String = it.kind
	if NADES.has(kind):
		if int(s.nades[kind]) >= NADE_MAX: return
		s.nades[kind] = int(s.nades[kind]) + 1
		s.nade_sel = kind
	else:
		var i := 1 if GUNS[kind].get("side", false) else 0
		s.guns[i] = kind
		s.mag[i] = GUNS[kind].mag; s.reserve[i] = int(GUNS[kind].mag) * 4
		s.slot = i; s.reload_t = 0; s.cool = 20; s.ads = false
	events.append(["pickup", s.pos, s.id, kind])


func _clear(a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 0.5) + 1
	for k in n + 1:
		if _blocked(a.lerp(b, float(k) / n), 0.45): return false
	return true


func _nearest_wp(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in waypoints.size():
		var d: float = waypoints[i].distance_squared_to(p)
		if d < bd: bd = d; best = i
	return best


## Next waypoint on the shortest walk from a to b (breadth-first over the waypoint links).
func _next_step(a: Vector3, b: Vector3) -> Vector3:
	var start := _nearest_wp(a)
	var goal := _nearest_wp(b)
	if start == goal: return b
	var prev := {start: -1}
	var q := [start]
	while not q.is_empty():
		var c: int = q.pop_front()
		if c == goal: break
		for nb in links[c]:
			if not prev.has(nb): prev[nb] = c; q.append(nb)
	if not prev.has(goal): return b
	var step := goal
	while prev[step] != start and prev[step] != -1: step = prev[step]
	return waypoints[step]


func setup(team_a: Array, team_b: Array, humans: Dictionary, loadouts: Dictionary, seed := 1, map := "office") -> void:
	rng.seed = seed
	map_id = map if MAPS.has(map) else "office"
	build_map()
	var sizes := maxi(team_a.size(), team_b.size())
	goal = 10 + sizes * 5
	var k := 0
	for t in 2:
		for C in (team_a if t == 0 else team_b):
			var s := Soldier.new()
			s.id = k; s.team = t; s.C = C
			s.human = humans.get(k, -1)
			# vests differ per person: heavier fighters carry more plating
			var arch := String(C.get("arch", ""))
			s.max_armor = {"bastion": 100.0, "kael": 75.0, "ember": 75.0, "tao": 60.0, "vex": 60.0, "mara": 50.0, "sora": 40.0, "lio": 40.0}.get(arch, 50.0)
			if C.get("boss", "") != "": s.max_armor += 25.0
			# humans start with an SMG and the P-9 and grab the rest at their table; bots arm themselves at random
			var prim: String = loadouts.get(k, "smg" if s.human >= 0 else PRIMARIES[rng.randi() % PRIMARIES.size()])
			if not GUNS.has(prim) or GUNS[prim].get("side", false): prim = "smg"
			s.guns = [prim, "pistol" if s.human >= 0 else SIDEARMS[rng.randi() % SIDEARMS.size()]]
			soldiers.append(s)
			_spawn(s)
			k += 1


func _spawn(s: Soldier) -> void:
	var pts: Array = spawns[s.team]
	s.pos = pts[s.id % pts.size()] + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
	s.prev_pos = s.pos
	s.yaw = PI / 2.0 if s.team == 0 else -PI / 2.0
	s.prev_yaw = s.yaw
	s.pitch = 0.0
	s.hp = 100.0; s.armor = s.max_armor; s.alive = true
	s.slot = 0
	s.blind = 0
	if s.human < 0:   # bots: a throwable or two from the table
		for kk in NADE_KINDS: s.nades[kk] = 1 if rng.randf() < 0.45 else 0
	else:
		for kk in NADE_KINDS: s.nades[kk] = 0
	for i in 2:
		var g: Dictionary = GUNS[s.guns[i]]
		s.mag[i] = g.mag; s.reserve[i] = g.mag * 4
	s.reload_t = 0; s.cool = 0; s.protect = PROTECT
	s.target = -1


func _blocked(p: Vector3, r: float) -> bool:
	for b in boxes:
		if p.x > b.position.x - r and p.x < b.end.x + r and p.z > b.position.z - r and p.z < b.end.z + r and p.y < b.end.y - 0.3:
			return true
	return false


## Move with collisions: slide along boxes (and step over the low ones like desks when jumping).
func _move(s: Soldier, d: Vector3) -> void:
	for axis in [0, 2]:
		var np := s.pos
		np[axis] += d[axis]
		if not _blocked(np, RADIUS):
			s.pos = np


func tick(inputs: Dictionary) -> void:
	tick_n += 1
	events.clear()
	if state == "warmup":
		warm -= 1
		if warm <= 0: state = "play"; events.append(["go", Vector3.ZERO, 0, 0])
	elif state == "play":
		time += DT
		if time >= time_limit or score[0] >= goal or score[1] >= goal:
			state = "done"; events.append(["done", Vector3.ZERO, 0, 0])
	_tick_thrown()
	for s in soldiers:
		s.prev_pos = s.pos; s.prev_yaw = s.yaw
		if s.blind > 0: s.blind -= 1
		if not s.alive:
			s.respawn -= 1
			if s.respawn <= 0 and state != "done":
				_spawn(s); events.append(["respawn", s.pos, s.id, 0])
			continue
		var inp: Dictionary = inputs.get(s.id, {}) if s.human >= 0 else _bot(s)
		_control(s, inp)


func _control(s: Soldier, inp: Dictionary) -> void:
	if s.protect > 0: s.protect -= 1
	if s.hurt_t > 0: s.hurt_t -= 1
	if inp.has("yaw"):   # online players aim on their own screen and send where they're looking
		s.yaw = wrapf(float(inp.yaw), -PI, PI); s.pitch = clampf(float(inp.get("pitch", 0.0)), -1.35, 1.35)
	else:
		s.yaw = wrapf(s.yaw + float(inp.get("look_x", 0.0)), -PI, PI)
		s.pitch = clampf(s.pitch + float(inp.get("look_y", 0.0)), -1.35, 1.35)
	s.crouch = bool(inp.get("crouch", false))
	s.ads = bool(inp.get("ads", false)) and s.reload_t == 0
	var mx: float = clampf(float(inp.get("move_x", 0.0)), -1.0, 1.0)
	var mz: float = clampf(float(inp.get("move_z", 0.0)), -1.0, 1.0)
	s.sprint = bool(inp.get("sprint", false)) and mz > 0.3 and not s.crouch and not s.ads
	var speed := CROUCH_SPEED if s.crouch else (SPRINT if s.sprint else WALK)
	if s.ads: speed *= 0.6
	if s.slot < 2: speed *= float(s.gun().get("slow", 1.0))
	var fwd := Vector3(sin(s.yaw), 0, cos(s.yaw))
	var right := Vector3(-cos(s.yaw), 0, sin(s.yaw))
	var wish := (fwd * mz + right * mx)
	if wish.length() > 1.0: wish = wish.normalized()
	var hv := Vector3(s.vel.x, 0, s.vel.z).lerp(wish * speed, 0.25 if s.on_floor else 0.05)
	s.vel.x = hv.x; s.vel.z = hv.z
	if s.on_floor and inp.get("jump", false) and not s.crouch:
		s.vel.y = 7.0; s.on_floor = false
		events.append(["jump", s.pos, s.id, 0])
	if not s.on_floor:
		s.vel.y -= GRAVITY * DT
	_move(s, Vector3(s.vel.x, 0, s.vel.z) * DT)
	s.pos.y += s.vel.y * DT
	# stand on the floor, or on top of desks / low cover
	var floor_y := 0.0
	for b in boxes:
		if b.end.y <= 1.6 and s.pos.x > b.position.x - 0.2 and s.pos.x < b.end.x + 0.2 and s.pos.z > b.position.z - 0.2 and s.pos.z < b.end.z + 0.2 and s.pos.y >= b.end.y - 0.35:
			floor_y = maxf(floor_y, b.end.y)
	if s.pos.y <= floor_y:
		if not s.on_floor and s.vel.y < -8.0: events.append(["land", s.pos, s.id, 0])
		s.pos.y = floor_y; s.vel.y = 0.0; s.on_floor = true
	elif s.pos.y > floor_y + 0.05:
		s.on_floor = false
	# weapons: 1 / 2 / 3 pick a slot, Q / wheel swap guns, G cycles throwables
	var want := s.slot
	if inp.get("swap", false): want = (1 - s.slot) if s.slot < 2 else 0
	if inp.has("slot"): want = int(inp.slot)
	if inp.get("cycle_nade", false):
		if s.slot == 2:
			var k0 := NADE_KINDS.find(s.nade_sel)
			for d in range(1, 4):
				var nk: String = NADE_KINDS[(k0 + d) % 3]
				if int(s.nades[nk]) > 0: s.nade_sel = nk; break
		want = 2
	if want == 2 and not _has_nades(s): want = s.slot if s.slot != 2 else 0
	if want == 2 and int(s.nades[s.nade_sel]) <= 0:
		for nk in NADE_KINDS:
			if int(s.nades[nk]) > 0: s.nade_sel = nk; break
	if want != s.slot and (s.reload_t == 0 or want == 2):
		s.slot = want; s.cool = 18; s.ads = false; s.reload_t = 0
		events.append(["swap", s.pos, s.id, 0])
	# take from the table
	var use: bool = inp.get("use", false)
	if use and not s.held_use:
		var it := pick_target(s)
		if not it.is_empty(): _take(s, it)
	s.held_use = use
	if inp.has("throw_now") and s.protect == 0 and s.cool == 0:   # bots throw straight from the belt
		var tk := String(inp.throw_now)
		if int(s.nades.get(tk, 0)) > 0: _throw(s, tk)
	if s.slot == 2:
		if s.cool > 0: s.cool -= 1
		var tf: bool = inp.get("fire", false)
		if tf and not s.held_fire and s.cool == 0 and s.protect == 0 and int(s.nades[s.nade_sel]) > 0:
			_throw(s, s.nade_sel)
			if int(s.nades[s.nade_sel]) <= 0:
				if _has_nades(s):
					for nk in NADE_KINDS:
						if int(s.nades[nk]) > 0: s.nade_sel = nk; break
				else:
					s.slot = 0; events.append(["swap", s.pos, s.id, 0])
		s.held_fire = tf
		return
	var g := s.gun()
	if s.reload_t > 0:
		s.reload_t -= 1
		if s.reload_t == 0:
			var need: int = int(g.mag) - int(s.mag[s.slot])
			var take := mini(need, s.reserve[s.slot])
			s.mag[s.slot] += take; s.reserve[s.slot] -= take
	elif (inp.get("reload", false) and s.mag[s.slot] < g.mag and s.reserve[s.slot] > 0) or (s.mag[s.slot] == 0 and s.reserve[s.slot] > 0):
		s.reload_t = int(g.reload * 60.0)
		events.append(["reload", s.pos, s.id, 0])
	if s.cool > 0: s.cool -= 1
	s.recoil = maxf(0.0, s.recoil - DT * 0.5)
	var fire: bool = inp.get("fire", false)
	if fire and s.cool == 0 and s.reload_t == 0 and s.mag[s.slot] > 0 and (g.auto or not s.held_fire) and not s.sprint and s.protect == 0:
		_shoot(s)
	s.held_fire = fire


func _has_nades(s: Soldier) -> bool:
	for nk in NADE_KINDS:
		if int(s.nades[nk]) > 0: return true
	return false


func _throw(s: Soldier, kind: String) -> void:
	s.nades[kind] = int(s.nades[kind]) - 1
	s.cool = 40
	var d := s.aim_dir()
	var v := d * 15.0 + Vector3(0, 3.0, 0) + Vector3(s.vel.x, 0, s.vel.z) * 0.5
	thrown.append({uid = next_uid, kind = kind, pos = s.eye() + d * 0.5, vel = v, t = 0, by = s.id})
	next_uid += 1
	events.append(["throw", s.pos, s.id, kind])


func _tick_thrown() -> void:
	for n in thrown.duplicate():
		n.t += 1
		var v: Vector3 = n.vel
		v.y -= GRAVITY * 0.75 * DT
		var np: Vector3 = n.pos + v * DT
		# bounce off walls and cover, one axis at a time
		for axis in [0, 2]:
			var tp: Vector3 = n.pos; tp[axis] = np[axis]
			if _solid_at(tp): v[axis] = -v[axis] * 0.45; np[axis] = n.pos[axis]
		var floor_y := _floor_under(np)
		var landed := false
		if np.y <= floor_y + 0.06:
			np.y = floor_y + 0.06
			if v.y < -1.5: v.y = -v.y * 0.35
			else: v.y = 0.0
			v.x *= 0.82; v.z *= 0.82
			landed = true
		if ceiling > 0.0 and np.y > ceiling - 0.1: np.y = ceiling - 0.1; v.y = -absf(v.y) * 0.3   # the ceiling
		n.pos = np; n.vel = v
		var kind: String = n.kind
		if (kind == "molly" and landed and n.t > 8) or n.t >= int(NADES[kind].fuse):
			_detonate(n)
			thrown.erase(n)
	for f in fires.duplicate():
		f.t -= 1
		if f.t <= 0: fires.erase(f); continue
		if f.t % 6 == 0:
			for v in soldiers:
				if v.alive and Vector2(v.pos.x - f.pos.x, v.pos.z - f.pos.z).length() < NADES.molly.r and absf(v.pos.y - f.pos.y) < 1.2:
					var by: Soldier = soldiers[f.by]
					if v.team != by.team or v.id == by.id: _damage(v, by, NADES.molly.dps / 10.0, false, f.pos)


func _solid_at(p: Vector3) -> bool:
	for b in boxes:
		if b.has_point(p): return true
	return false


func _floor_under(p: Vector3) -> float:
	var y := 0.0
	for b in boxes:
		if p.x > b.position.x and p.x < b.end.x and p.z > b.position.z and p.z < b.end.z and p.y >= b.end.y - 0.3:
			y = maxf(y, b.end.y)
	return y


func _los(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var dist := d.length()
	if dist < 0.01: return true
	d /= dist
	for box in boxes:
		var t := _ray_aabb(a, d, box)
		if t >= 0.0 and t < dist - 0.05: return false
	return true


func _detonate(n: Dictionary) -> void:
	var by: Soldier = soldiers[n.by]
	var p: Vector3 = n.pos
	match String(n.kind):
		"frag":
			events.append(["boom", p, n.by, 0])
			for v in soldiers:
				if not v.alive: continue
				var c: Vector3 = v.pos + Vector3(0, 0.9, 0)
				var d: float = c.distance_to(p)
				if d < NADES.frag.r and _los(p + Vector3(0, 0.2, 0), c) and (v.team != by.team or v.id == by.id):
					_damage(v, by, NADES.frag.dmg * clampf(1.0 - d / NADES.frag.r, 0.15, 1.0), false, p)
		"flash":
			events.append(["flash", p, n.by, 0])
			for v in soldiers:
				if not v.alive: continue
				var e: Vector3 = v.eye()
				var d: float = e.distance_to(p)
				if d > NADES.flash.r or not _los(p, e): continue
				var facing: float = v.aim_dir().dot((p - e).normalized())   # looking right at it: full white-out
				var amt: float = clampf(0.35 + facing * 0.65, 0.15, 1.0) * clampf(1.2 - d / NADES.flash.r, 0.2, 1.0)
				v.blind = maxi(v.blind, int(amt * 210.0))
				if v.human < 0: v.target = -1
		"molly":
			fires.append({uid = next_uid, pos = Vector3(p.x, _floor_under(p), p.z), t = int(NADES.molly.burn), by = n.by})
			next_uid += 1
			events.append(["fire", p, n.by, 0])


func _shoot(s: Soldier) -> void:
	var g := s.gun()
	s.mag[s.slot] -= 1
	s.cool = maxi(1, int(3600.0 / g.rpm))
	var spread: float = (g.ads_spread if s.ads else g.spread) * (1.6 if not s.on_floor else (0.7 if s.crouch else 1.0)) + s.recoil
	s.recoil = minf(0.08, s.recoil + float(g.recoil) * (0.5 if s.ads else 1.0))
	s.pitch = minf(1.35, s.pitch + float(g.recoil) * 0.35)   # the gun kicks up a little
	var eye := s.eye()
	events.append(["shot", eye, s.id, 0])
	for p in g.pellets:
		var d := s.aim_dir()
		d = (d + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spread).normalized()
		var hit := _raycast(eye, d, 150.0, s.id)
		events.append(["tracer", eye, s.id, eye + d * hit.t])
		if hit.who >= 0:
			var v: Soldier = soldiers[hit.who]
			if v.team == s.team: continue   # no friendly fire
			var dmg: float = g.dmg * (g.head if hit.head else 1.0)
			if hit.t > g.falloff: dmg *= clampf(1.0 - (hit.t - g.falloff) / (g.falloff * 2.0), 0.4, 1.0)
			_damage(v, s, dmg, hit.head, eye)
		elif hit.t < 150.0:
			events.append(["impact", eye + d * hit.t, s.id, 0])


## Hitscan: walls and cover first, then soldiers (a body cylinder and a head sphere).
func _raycast(from: Vector3, d: Vector3, max_t: float, ignore: int) -> Dictionary:
	var best := {t = max_t, who = -1, head = false}
	for b in boxes:
		var t := _ray_aabb(from, d, b)
		if t >= 0.0 and t < best.t: best = {t = t, who = -1, head = false}
	for v in soldiers:
		if v.id == ignore or not v.alive: continue
		var top := EYE_CROUCH if v.crouch else EYE
		# head
		var hc: Vector3 = v.pos + Vector3(0, top + 0.05, 0)
		var th := _ray_sphere(from, d, hc, 0.2)
		if th >= 0.0 and th < best.t: best = {t = th, who = v.id, head = true}
		# body
		var tb := _ray_cylinder(from, d, v.pos, RADIUS, top - 0.15)
		if tb >= 0.0 and tb < best.t: best = {t = tb, who = v.id, head = false}
	return best


static func _ray_aabb(o: Vector3, d: Vector3, b: AABB) -> float:
	var tmin := -INF
	var tmax := INF
	for a in 3:
		if absf(d[a]) < 1e-6:
			if o[a] < b.position[a] or o[a] > b.end[a]: return -1.0
		else:
			var t1 := (b.position[a] - o[a]) / d[a]
			var t2 := (b.end[a] - o[a]) / d[a]
			tmin = maxf(tmin, minf(t1, t2)); tmax = minf(tmax, maxf(t1, t2))
	if tmax < maxf(tmin, 0.0): return -1.0
	return tmin if tmin >= 0.0 else -1.0


static func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var disc := b * b - (oc.length_squared() - r * r)
	if disc < 0.0: return -1.0
	var t := -b - sqrt(disc)
	return t if t >= 0.0 else -1.0


static func _ray_cylinder(o: Vector3, d: Vector3, base: Vector3, r: float, h: float) -> float:
	var ox := o.x - base.x
	var oz := o.z - base.z
	var a := d.x * d.x + d.z * d.z
	if a < 1e-8: return -1.0
	var b := 2.0 * (ox * d.x + oz * d.z)
	var c := ox * ox + oz * oz - r * r
	var disc := b * b - 4.0 * a * c
	if disc < 0.0: return -1.0
	var t := (-b - sqrt(disc)) / (2.0 * a)
	if t < 0.0: return -1.0
	var y := o.y + d.y * t
	return t if y >= base.y and y <= base.y + h else -1.0


func _damage(v: Soldier, by: Soldier, dmg: float, head: bool, from: Vector3) -> void:
	if v.protect > 0 or not v.alive: return
	# the vest soaks up 60% of the damage until it's used up (not on headshots)
	if v.armor > 0.0 and not head:
		var soak := minf(v.armor, dmg * 0.6)
		v.armor -= soak; dmg -= soak
		if v.armor <= 0.0: events.append(["vest_break", v.pos, v.id, by.id])
	v.hp -= dmg
	v.hurt_dir = (from - v.pos).normalized(); v.hurt_t = 40
	events.append(["hit", v.pos + Vector3(0, 1.2, 0), v.id, by.id, head])
	if v.hp <= 0.0:
		v.alive = false; v.respawn = 180; v.deaths += 1
		by.kills += 1
		if state == "play": score[by.team] += 1
		events.append(["kill", v.pos, by.id, v.id, head])


# ---------------------------------------------------------------- bots
func _visible(a: Soldier, b: Soldier) -> bool:
	var from := a.eye()
	var to := b.pos + Vector3(0, 1.2, 0)
	var d := to - from
	var dist := d.length()
	d /= dist
	for box in boxes:
		var t := _ray_aabb(from, d, box)
		if t >= 0.0 and t < dist: return false
	return true


func _bot(s: Soldier) -> Dictionary:
	var inp := {}
	s.think -= 1
	if s.think <= 0:
		s.think = rng.randi_range(10, 24)
		# nearest visible enemy
		var best := -1
		var bd := INF
		for o in soldiers:
			if o.team == s.team or not o.alive: continue
			var dist := s.pos.distance_to(o.pos)
			if dist < bd and dist < 60.0 and s.blind == 0 and _visible(s, o): bd = dist; best = o.id
		if best != s.target:
			if best >= 0: s.react = int(rng.randf_range(10, 22) / bot_skill)   # human-like reaction time
			s.target = best
		# where to go: toward the closest enemy (bots hear the fight), with a bit of spread
		var hunt := -1
		var hd := INF
		for o in soldiers:
			if o.team != s.team and o.alive and s.pos.distance_to(o.pos) < hd: hd = s.pos.distance_to(o.pos); hunt = o.id
		if hunt >= 0:
			s.goal_pos = (soldiers[hunt] as Soldier).pos + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		elif s.goal_pos == Vector3.ZERO or s.pos.distance_to(s.goal_pos) < 2.0:
			s.goal_pos = waypoints[rng.randi() % waypoints.size()]
		s.wander = _next_step(s.pos, s.goal_pos)
		if rng.randf() < 0.35: s.strafe_dir = -s.strafe_dir
		# unstick: if barely moved for a while, hop and pick a different route
		if s.pos.distance_to(s.stuck_at) < 0.4:
			s.stuck_t += 1
			if s.stuck_t > 3:
				inp.jump = true; s.stuck_t = 0
				s.wander = waypoints[rng.randi() % waypoints.size()]
		else:
			s.stuck_t = 0
		s.stuck_at = s.pos
	if s.target >= 0:
		var t: Soldier = soldiers[s.target]
		if not t.alive:
			s.target = -1; return inp
		var aim := t.pos + Vector3(0, (EYE_CROUCH if t.crouch else EYE) - 0.3, 0) - s.eye()
		var dist := aim.length()
		var want_yaw := atan2(aim.x, aim.z)
		var want_pitch := atan2(aim.y, Vector2(aim.x, aim.z).length())
		var dy := wrapf(want_yaw - s.yaw, -PI, PI)
		var dp := want_pitch - s.pitch
		var err := 0.012 / bot_skill
		inp.look_x = dy * 0.3 + rng.randf_range(-err, err)
		inp.look_y = dp * 0.3 + rng.randf_range(-err, err) * 0.5
		var g: Dictionary = s.gun()
		var ideal: float = {"shotgun": 6.0, "smg": 12.0, "pistol": 14.0, "rifle": 20.0, "sniper": 30.0}.get(s.guns[s.slot], 18.0)
		inp.move_z = 1.0 if dist > ideal + 4.0 else (-0.6 if dist < ideal - 4.0 else 0.0)
		inp.move_x = s.strafe_dir * 0.8
		inp.ads = s.guns[s.slot] in ["sniper", "rifle"] and dist > 12.0
		inp.crouch = s.guns[s.slot] == "sniper" and dist > 22.0
		# fire once lined up: the tolerance is about half a body width at that distance
		var tol := maxf(0.04, atan(0.35 / maxf(1.0, dist)) * 1.6)
		if s.react > 0: s.react -= 1
		elif absf(dy) < tol and absf(dp) < tol * 1.5:
			inp.fire = g.auto or (tick_n % 10 < 3)
		# now and then lob a grenade at someone in mid range
		if dist > 7.0 and dist < 24.0 and s.protect == 0 and rng.randf() < 0.005 * bot_skill:
			for nk in NADE_KINDS:
				if int(s.nades[nk]) > 0: inp.throw_now = nk; break
		if s.mag[s.slot] == 0 and s.reserve[s.slot] == 0: inp.swap = s.slot == 0
		return inp
	# moving between fights: follow the waypoint route toward the enemy
	var to: Vector3 = s.wander - s.pos
	var want := atan2(to.x, to.z)
	inp.look_x = wrapf(want - s.yaw, -PI, PI) * 0.15
	inp.look_y = -s.pitch * 0.1
	inp.move_z = 1.0
	inp.sprint = true
	if s.pos.distance_to(s.wander) < 1.2: s.think = 0
	if s.mag[s.slot] < (s.gun().mag as int) / 2 and s.reserve[s.slot] > 0: inp.reload = true
	return inp


# ---------------------------------------------------------------- snapshot (multiplayer)
func snapshot() -> Dictionary:
	var ss := []
	for o in soldiers:
		ss.append(Party.pack([o.pos.x, o.pos.y, o.pos.z, o.yaw, o.pitch, o.hp, o.armor, o.alive, o.crouch, o.slot, o.mag[0], o.mag[1], o.reserve[0], o.reserve[1],
			o.kills, o.deaths, o.ads, o.reload_t, o.vel.x, o.vel.y, o.vel.z, o.on_floor, o.sprint, o.guns[0], o.respawn, o.protect, o.hurt_t, o.hurt_dir.x, o.hurt_dir.z, o.recoil,
			o.guns[1], o.nades.frag, o.nades.flash, o.nades.molly, o.nade_sel, o.blind]))
	var th := []
	for n in thrown: th.append(Party.pack([n.uid, n.kind, n.pos.x, n.pos.y, n.pos.z]))
	var fs := []
	for f in fires: fs.append(Party.pack([f.uid, f.pos.x, f.pos.y, f.pos.z, f.t]))
	return {t = tick_n, st = state, time = snappedf(time, 0.001), warm = warm, sc = score, s = ss, th = th, fi = fs}


## Guests: take the host's state. keep_aim: this player's own soldier keeps the aim from their screen.
func apply(sn: Dictionary, keep_aim := -1) -> void:
	tick_n = int(sn.t); state = String(sn.st); time = float(sn.time); warm = int(sn.warm)
	score = [int(sn.sc[0]), int(sn.sc[1])]
	var ss: Array = sn.s
	for k in mini(ss.size(), soldiers.size()):
		var o: Soldier = soldiers[k]
		var a: Array = ss[k]
		o.prev_pos = o.pos; o.prev_yaw = o.yaw
		o.pos = Vector3(a[0], a[1], a[2])
		if k != keep_aim: o.yaw = float(a[3]); o.pitch = float(a[4])
		o.hp = float(a[5]); o.armor = float(a[6]); o.alive = bool(a[7]); o.crouch = bool(a[8]); o.slot = int(a[9])
		o.mag = [int(a[10]), int(a[11])]; o.reserve = [int(a[12]), int(a[13])]
		o.kills = int(a[14]); o.deaths = int(a[15]); o.ads = bool(a[16]); o.reload_t = int(a[17])
		o.vel = Vector3(a[18], a[19], a[20]); o.on_floor = bool(a[21]); o.sprint = bool(a[22])
		o.guns = [String(a[23]), String(a[30]) if a.size() > 30 else "pistol"]; o.respawn = int(a[24]); o.protect = int(a[25]); o.hurt_t = int(a[26])
		o.hurt_dir = Vector3(a[27], 0, a[28]); o.recoil = float(a[29])
		if a.size() > 35:
			o.nades = {"frag": int(a[31]), "flash": int(a[32]), "molly": int(a[33])}; o.nade_sel = String(a[34]); o.blind = int(a[35])
	# grenades in flight and fires: rebuilt from the host's lists (the view matches them up by uid)
	thrown.clear()
	for t in sn.get("th", []):
		var ta: Array = t
		thrown.append({uid = int(ta[0]), kind = String(ta[1]), pos = Vector3(ta[2], ta[3], ta[4]), vel = Vector3.ZERO, t = 0, by = 0})
	fires.clear()
	for f in sn.get("fi", []):
		var fa: Array = f
		fires.append({uid = int(fa[0]), pos = Vector3(fa[1], fa[2], fa[3]), t = int(fa[4]), by = 0})


## Guests, between snapshots: keep everyone moving the way they were going.
func coast() -> void:
	for o in soldiers:
		o.prev_pos = o.pos; o.prev_yaw = o.yaw
		if o.alive: o.pos += Vector3(o.vel.x, 0, o.vel.z) * DT
