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
}
const PRIMARIES := ["rifle", "smg", "shotgun", "sniper"]

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
	var slot := 0
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

	func gun() -> Dictionary: return OpsSim.GUNS[guns[slot]]
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
var rng := RandomNumberGenerator.new()
var bot_skill := 1.0


## Office floor: 64 x 44 m, cubicles and desks in the middle, server racks and meeting rooms at the ends.
func build_map() -> void:
	var add := func(x: float, z: float, sx: float, sz: float, h := 1.2):
		boxes.append(AABB(Vector3(x - sx / 2.0, 0.0, z - sz / 2.0), Vector3(sx, h, sz)))
	# outer walls
	add.call(0, -22.5, 66, 1, 4); add.call(0, 22.5, 66, 1, 4); add.call(-32.5, 0, 1, 46, 4); add.call(32.5, 0, 1, 46, 4)
	# meeting rooms (glass walls) at both ends with doors
	for side in [-1.0, 1.0]:
		add.call(side * 22.0, -12.0, 1.0, 10.0, 3.0); add.call(side * 22.0, 12.0, 1.0, 10.0, 3.0)
		add.call(side * 27.0, -7.0, 10.0, 1.0, 3.0); add.call(side * 27.0, 7.0, 10.0, 1.0, 3.0)
		add.call(side * 27.5, 0.0, 3.0, 2.0, 1.0)   # table
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
	for x in range(-28, 29, 4):
		for z in range(-19, 20, 4):
			var p := Vector3(x, 0, z)
			if not _blocked(p, 0.7): waypoints.append(p)
	# connect neighbours that have a clear walk between them
	for i in waypoints.size():
		var ln := []
		for j in waypoints.size():
			if i != j and waypoints[i].distance_to(waypoints[j]) < 6.0 and _clear(waypoints[i], waypoints[j]): ln.append(j)
		links.append(ln)


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


func setup(team_a: Array, team_b: Array, humans: Dictionary, loadouts: Dictionary, seed := 1) -> void:
	rng.seed = seed
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
			var prim: String = loadouts.get(k, PRIMARIES[rng.randi() % PRIMARIES.size()])
			s.guns = [prim, "pistol"]
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
	for i in 2:
		var g: Dictionary = GUNS[s.guns[i]]
		s.mag[i] = g.mag; s.reserve[i] = g.mag * 4
	s.reload_t = 0; s.cool = 0; s.protect = 120
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
	for s in soldiers:
		s.prev_pos = s.pos; s.prev_yaw = s.yaw
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
	s.yaw = wrapf(s.yaw + float(inp.get("look_x", 0.0)), -PI, PI)
	s.pitch = clampf(s.pitch + float(inp.get("look_y", 0.0)) - s.recoil * 0.0, -1.35, 1.35)
	s.crouch = bool(inp.get("crouch", false))
	s.ads = bool(inp.get("ads", false)) and s.reload_t == 0
	var mx: float = clampf(float(inp.get("move_x", 0.0)), -1.0, 1.0)
	var mz: float = clampf(float(inp.get("move_z", 0.0)), -1.0, 1.0)
	s.sprint = bool(inp.get("sprint", false)) and mz > 0.3 and not s.crouch and not s.ads
	var speed := CROUCH_SPEED if s.crouch else (SPRINT if s.sprint else WALK)
	if s.ads: speed *= 0.6
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
	# weapons
	if inp.get("swap", false) and s.reload_t == 0:
		s.slot = 1 - s.slot; s.cool = 18; s.ads = false
		events.append(["swap", s.pos, s.id, 0])
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
	if fire and s.cool == 0 and s.reload_t == 0 and s.mag[s.slot] > 0 and (g.auto or not s.held_fire) and not s.sprint:
		_shoot(s)
	s.held_fire = fire


func _shoot(s: Soldier) -> void:
	var g := s.gun()
	s.mag[s.slot] -= 1
	s.cool = maxi(1, int(3600.0 / g.rpm))
	s.protect = 0
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
			if dist < bd and dist < 60.0 and _visible(s, o): bd = dist; best = o.id
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
	for s in soldiers:
		ss.append([s.pos.x, s.pos.y, s.pos.z, s.yaw, s.pitch, s.hp, s.armor, s.alive, s.crouch, s.slot, s.mag[s.slot], s.reserve[s.slot], s.kills, s.deaths, s.ads, s.reload_t])
	return {t = tick_n, st = state, time = time, sc = score, s = ss}
