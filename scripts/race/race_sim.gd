class_name RaceSim
extends RefCounted
## BNB Rush Hour: the race itself, with no visuals. Cars, items, traffic, CPU drivers, laps and places.
## Runs at 60 ticks/s on the host; in multiplayer, guests just send their controls and draw the host's snapshots.

const DT := 1.0 / 60.0
const LAPS := 3
const MAX_SPEED := 36.0
const BOOST_SPEED := 48.0
const CAR_R := 1.25

## ---- tracks: closed loops of control points [x, y, z] (y = height), plus where the jumps are
const TRACKS := {
	"city": {name = "Downtown Loop", width = 15.0, theme = "city",
		pts = [[0, 0, 0], [60, 0, -10], [120, 0, 0], [170, 2, 40], [180, 4, 100], [150, 4, 150], [90, 2, 160],
			[40, 0, 200], [-20, 0, 210], [-80, 0, 180], [-110, 1, 120], [-100, 3, 60], [-60, 1, 20]],
		jumps = [0.31, 0.72]},
	"park": {name = "Office Park", width = 14.0, theme = "park",
		pts = [[0, 0, 0], [50, 0, 20], [90, 1, 70], [80, 3, 130], [30, 5, 160], [-30, 5, 150], [-60, 3, 110],
			[-40, 1, 60], [-90, 0, 30], [-110, 0, -30], [-60, 0, -60], [-10, 0, -40]],
		jumps = [0.45]},
	"rooftop": {name = "Rooftop Circuit", width = 13.0, theme = "rooftop",
		pts = [[0, 30, 0], [70, 30, 0], [110, 32, 40], [110, 36, 100], [60, 38, 130], [0, 38, 110],
			[-40, 34, 140], [-90, 30, 110], [-90, 30, 40], [-50, 30, 10]],
		jumps = [0.2, 0.62]},
	"seaside": {name = "Seaside Boulevard", width = 15.0, theme = "seaside",
		pts = [[0, 0, 0], [80, 0, -20], [150, 1, 10], [190, 2, 70], [170, 3, 140], [110, 2, 175], [40, 1, 160],
			[-10, 0, 195], [-80, 0, 180], [-125, 1, 115], [-105, 0, 45], [-55, 0, 5]],
		jumps = [0.5]},
	"desert": {name = "Canyon Run", width = 14.0, theme = "desert",
		pts = [[0, 0, 0], [70, 1, -30], [140, 3, 0], [175, 5, 60], [145, 6, 120], [85, 4, 130], [55, 2, 185],
			[-20, 1, 195], [-90, 2, 155], [-125, 4, 85], [-95, 3, 20], [-45, 1, -15]],
		jumps = [0.25, 0.66]},
	"snow": {name = "Snowy Pass", width = 14.0, theme = "snow",
		pts = [[0, 0, 0], [60, 1, 20], [105, 3, 70], [95, 5, 130], [45, 6, 155], [-5, 4, 125], [-40, 3, 165],
			[-100, 2, 145], [-125, 1, 85], [-85, 0, 30], [-40, 0, -10]],
		jumps = [0.4]},
}

## ---- pickups
const ITEMS := ["stapler", "coffee", "planes", "peel", "energy", "stapler", "planes", "coffee"]

class Racer:
	var id := 0
	var C: Dictionary
	var human := -1            # player slot (-1 = CPU)
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var heading := 0.0         # yaw, radians (0 = +Z)
	var speed := 0.0
	var vy := 0.0
	var air := false
	var idx := 0               # nearest track sample
	var lat := 0.0             # lateral offset from the centre line
	var lap := 0
	var dist := 0.0            # distance along the lap
	var progress := 0.0        # lap * length + dist
	var place := 1
	var finished := -1.0       # race time when they crossed the line
	var item := ""
	var power := 0.0           # signature meter 0..100
	var stun := 0              # ticks spun out
	var boost := 0             # ticks of boost (drift release)
	var nitro := 60.0          # nitro tank 0..100: hold the nitro button to burn it
	var nitro_on := false
	var drift := 0.0           # drift charge
	var drifting := false
	var lane_pref := 0.0       # CPU: preferred lateral position
	var think := 0             # CPU: ticks until next decision
	var flash := 0
	var hits := 0
	var prev_pos := Vector3.ZERO
	var prev_heading := 0.0

class Shot:
	var uid := 0
	var kind := ""             # stapler / plane / homing (signature props) / goat / logo
	var prop := ""             # what it looks like
	var owner := 0
	var target := -1
	var pos := Vector3.ZERO
	var dir := Vector3.FORWARD
	var speed := 60.0
	var life := 180
	var big := false
	var idx := 0               # nearest track sample (charges follow the road)

class Hazard:
	var uid := 0
	var kind := ""             # coffee / peel / prop spill
	var prop := ""
	var owner := 0
	var pos := Vector3.ZERO
	var life := 900

class Traffic:
	var pos := Vector3.ZERO
	var heading := 0.0
	var dist := 0.0
	var lat := 0.0
	var speed := 17.0
	var color := Color.WHITE
	var stun := 0

var track: Dictionary
var P: PackedVector3Array      # samples along the centre line, every ~2 m
var T: PackedVector3Array      # tangents
var S: PackedFloat32Array      # cumulative distance
var length := 0.0
var width := 14.0
var racers: Array = []
var shots: Array = []
var hazards: Array = []
var traffic: Array = []
var boxes: Array = []          # [{pos, dist, lat, respawn}]
var cones: Array = []          # [{pos, knocked}]
var ramps: Array = []          # track sample index where a jump is
var tick_n := 0
var time := 0.0
var state := "countdown"       # countdown / race / done
var countdown := 3 * 60
var events: Array = []         # things the view should show this tick: [kind, pos, extra]
var rng := RandomNumberGenerator.new()
var next_uid := 1


## Build the track samples and line up racers on the grid. people = Array of roster dicts (first = player 0 ...).
func setup(track_id: String, people: Array, humans: int, seed := 1) -> void:
	rng.seed = seed
	track = TRACKS.get(track_id, TRACKS.city)
	width = float(track.width)
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	var pts: Array = track.pts
	for i in pts.size() + 1:
		var p: Array = pts[i % pts.size()]
		var prv: Array = pts[(i - 1 + pts.size()) % pts.size()]
		var nxt: Array = pts[(i + 1) % pts.size()]
		var tang := (Vector3(nxt[0], nxt[1], nxt[2]) - Vector3(prv[0], prv[1], prv[2])) * 0.22
		curve.add_point(Vector3(p[0], p[1], p[2]), -tang, tang)
	P = curve.get_baked_points()
	length = curve.get_baked_length()
	S = PackedFloat32Array(); S.resize(P.size())
	T = PackedVector3Array(); T.resize(P.size())
	var acc := 0.0
	for i in P.size():
		if i > 0: acc += P[i].distance_to(P[i - 1])
		S[i] = acc
		T[i] = (P[(i + 1) % P.size()] - P[(i - 1 + P.size()) % P.size()]).normalized()
	length = acc + P[P.size() - 1].distance_to(P[0])
	for j in track.jumps: ramps.append(int(float(j) * P.size()))
	# racers on a 2-wide grid behind the line
	for k in people.size():
		var r := Racer.new()
		r.id = k
		r.C = people[k]
		r.human = k if k < humans else -1
		var back := 6.0 + k / 2 * 7.0
		var i0 := _index_at(length - back)
		r.idx = i0
		r.lat = -3.0 if k % 2 == 0 else 3.0
		r.pos = P[i0] + _right(i0) * r.lat
		r.heading = atan2(T[i0].x, T[i0].z)
		r.dist = S[i0]
		r.lap = -1          # they start behind the line: crossing it starts lap 1
		r.lane_pref = rng.randf_range(-0.22, 0.22) * width
		r.prev_pos = r.pos; r.prev_heading = r.heading
		racers.append(r)
	# item boxes in rows of four, traffic, cones
	for f in [0.12, 0.38, 0.6, 0.85]:
		var i := int(f * P.size())
		for l in [-0.3, -0.1, 0.1, 0.3]:
			boxes.append({pos = P[i] + _right(i) * l * width + Vector3(0, 1.0, 0), idx = i, respawn = 0})
	var n_traffic := 7 if width >= 14.0 else 4   # the narrow rooftop gets less traffic
	for t in n_traffic:
		var tr := Traffic.new()
		tr.dist = (t + 0.5) / float(n_traffic) * length
		tr.lat = (-0.22 if t % 2 else 0.22) * width
		tr.speed = rng.randf_range(13.0, 19.0)
		tr.color = [Color(0.85, 0.75, 0.2), Color(0.9, 0.9, 0.92), Color(0.2, 0.3, 0.6), Color(0.65, 0.15, 0.15)][t % 4]
		traffic.append(tr)
	for c in 14:
		var i := int(rng.randf_range(0.05, 0.98) * P.size())
		cones.append({pos = P[i] + _right(i) * rng.randf_range(-0.42, 0.42) * width, knocked = 0})


func _right(i: int) -> Vector3:
	return T[i].cross(Vector3.UP).normalized() * -1.0


func _index_at(d: float) -> int:
	d = fposmod(d, length)
	var lo := 0
	var hi := S.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if S[mid] <= d: lo = mid
		else: hi = mid - 1
	return lo


## Nearest track sample, searching around the last one (cars move a few samples per tick at most).
func _nearest(p: Vector3, start: int) -> int:
	var best := start
	var bd := INF
	for o in range(-12, 13):
		var i := (start + o + P.size()) % P.size()
		var d := Vector2(p.x - P[i].x, p.z - P[i].z).length_squared()
		if d < bd: bd = d; best = i
	return best


## One tick. inputs: racer id -> {steer -1..1, gas 0..1, brake 0..1, drift bool, item bool, power bool}
func tick(inputs: Dictionary) -> void:
	tick_n += 1
	events.clear()
	if state == "countdown":
		countdown -= 1
		if countdown % 60 == 0 and countdown > 0: events.append(["count", Vector3.ZERO, countdown / 60])
		if countdown <= 0:
			state = "race"; events.append(["go", Vector3.ZERO, 0])
		for r in racers: r.prev_pos = r.pos; r.prev_heading = r.heading
		return
	if state == "race": time += DT
	for r in racers:
		r.prev_pos = r.pos; r.prev_heading = r.heading
		var inp: Dictionary = inputs.get(r.id, {}) if r.human >= 0 and r.finished < 0.0 else _cpu(r)
		_drive(r, inp)
	_collide_cars()
	_update_traffic()
	_update_shots()
	_update_hazards()
	_update_boxes()
	_rank()
	for o in shots + hazards:
		if o.uid == 0: o.uid = next_uid; next_uid += 1


func _drive(r: Racer, inp: Dictionary) -> void:
	var steer: float = clampf(float(inp.get("steer", 0.0)), -1.0, 1.0)
	var gas: float = float(inp.get("gas", 0.0))
	var brake: float = float(inp.get("brake", 0.0))
	var slowed := r.stun > 0
	if slowed:
		r.stun -= 1   # after a hit: no spin, the car just can't get back to full speed for a moment
	var top := BOOST_SPEED if r.boost > 0 else MAX_SPEED * (0.92 + float(r.C.get("speed", 1.0)) * 0.08)
	if r.human < 0: top *= _cpu_pace(r)
	# nitro: hold to burn the tank for a big push (refills slowly, faster from drifts and pickups)
	r.nitro_on = bool(inp.get("nitro", false)) and r.nitro > 0.0 and r.stun == 0
	if r.nitro_on:
		r.nitro = maxf(0.0, r.nitro - 28.0 * DT)
		top = BOOST_SPEED * 1.08
		gas = 1.0
		r.speed += 22.0 * DT
	else:
		r.nitro = minf(100.0, r.nitro + 4.0 * DT)
	if r.boost > 0: r.boost -= 1; gas = 1.0; r.speed += 10.0 * DT
	if slowed: top *= 0.55
	var accel := 26.0 if r.speed < top else -18.0
	r.speed += (gas * accel - brake * 40.0 - r.speed * 0.25) * DT
	r.speed = clampf(r.speed, -10.0, BOOST_SPEED)
	# steering: tighter at low speed, a drift tightens it more and charges a boost
	var grip := 1.0
	var want_drift: bool = inp.get("drift", false) and absf(steer) > 0.3 and r.speed > 18.0 and not r.air
	if want_drift:
		r.drifting = true
		r.drift = minf(r.drift + DT, 2.0)
		grip = 0.55
	elif r.drifting:
		r.drifting = false
		if r.drift > 0.6:
			r.boost = int(r.drift * 50)
			r.nitro = minf(100.0, r.nitro + r.drift * 10.0)
			events.append(["boost", r.pos, r.id])
		r.drift = 0.0
	var turn := steer * (1.9 if r.drifting else 1.45) * clampf(r.speed / 14.0, 0.0, 1.0) * (1.0 - clampf(r.speed / 70.0, 0.0, 0.4))
	if not r.air: r.heading -= turn * DT
	var fwd := Vector3(sin(r.heading), 0, cos(r.heading))
	var v_target := fwd * r.speed
	r.vel = r.vel.lerp(v_target, clampf(grip * 8.0 * DT, 0.0, 1.0)) if not r.air else r.vel
	r.pos += r.vel * DT
	# stay on the road: walls on both sides
	r.idx = _nearest(r.pos, r.idx)
	var right := _right(r.idx)
	var c: Vector3 = P[r.idx]
	r.lat = (r.pos - c).dot(right)
	var lim := width / 2.0 - CAR_R
	if absf(r.lat) > lim:
		r.pos -= right * (r.lat - signf(r.lat) * lim)
		r.speed *= 0.93
		r.vel -= right * r.vel.dot(right) * 1.2
		r.lat = signf(r.lat) * lim
		if tick_n % 6 == 0: events.append(["scrape", r.pos, r.id])
	# height: follow the road, fly off the jumps
	var ground := c.y
	if not r.air:
		r.pos.y = ground
		for ri in ramps:
			if absi(r.idx - ri) <= 1 and r.speed > 20.0:
				r.air = true; r.vy = r.speed * 0.32
				events.append(["jump", r.pos, r.id])
	else:
		r.vy -= 30.0 * DT
		r.pos.y += r.vy * DT
		if r.pos.y <= ground:
			r.pos.y = ground; r.air = false; r.vy = 0.0
			events.append(["land", r.pos, r.id])
	# laps
	var nd: float = S[r.idx]
	if r.dist > length * 0.8 and nd < length * 0.2:
		r.lap += 1
		if r.lap >= LAPS and r.finished < 0.0:
			r.finished = time
			events.append(["finish", r.pos, r.id])
		elif r.lap >= 1:
			events.append(["lap", r.pos, r.id])
	elif r.dist < length * 0.2 and nd > length * 0.8:
		r.lap -= 1   # drove back over the line
	r.dist = nd
	r.progress = r.lap * length + r.dist
	# the signature meter fills slowly while racing (faster when behind)
	r.power = minf(100.0, r.power + DT * (5.0 + (r.place - 1) * 0.6))
	if r.flash > 0: r.flash -= 1
	if inp.get("item", false) and r.item != "": _use_item(r)
	if inp.get("power", false) and r.power >= 100.0: _use_power(r)


func _collide_cars() -> void:
	for a in racers.size():
		for b in range(a + 1, racers.size()):
			var A: Racer = racers[a]
			var B: Racer = racers[b]
			var d := Vector2(B.pos.x - A.pos.x, B.pos.z - A.pos.z)
			var l := d.length()
			if l < CAR_R * 2.0 and l > 0.001 and absf(A.pos.y - B.pos.y) < 1.5:
				var n := Vector3(d.x / l, 0, d.y / l)
				var push := (CAR_R * 2.0 - l) * 0.5
				A.pos -= n * push; B.pos += n * push
				var dv := (B.vel - A.vel).dot(n)
				if dv < 0.0:
					A.vel += n * dv * 0.5; B.vel -= n * dv * 0.5
					if absf(dv) > 6.0: events.append(["bump", (A.pos + B.pos) / 2.0, 0])


func _update_traffic() -> void:
	for t in traffic:
		if t.stun > 0: t.stun -= 1
		else: t.dist = fposmod(t.dist + t.speed * DT, length)
		var i := _index_at(t.dist)
		t.pos = P[i] + _right(i) * t.lat
		t.heading = atan2(T[i].x, T[i].z)
		for r in racers:
			if r.stun == 0 and r.pos.distance_to(t.pos) < 2.6:
				r.speed *= 0.55; r.stun = 14
				r.pos += (r.pos - t.pos).normalized() * 0.8
				t.stun = 40
				events.append(["crash", r.pos, r.id])
	for c in cones:
		if c.knocked > 0:
			c.knocked -= 1; continue
		for r in racers:
			if r.pos.distance_to(c.pos) < 1.6:
				c.knocked = 600; r.speed *= 0.85
				events.append(["cone", c.pos, r.id])


func _update_boxes() -> void:
	for b in boxes:
		if b.respawn > 0:
			b.respawn -= 1; continue
		for r in racers:
			if r.pos.distance_to(b.pos - Vector3(0, 1.0, 0)) < 2.2:
				b.respawn = 240
				if r.item == "":
					# the further behind, the better the odds of something strong
					r.item = ITEMS[rng.randi() % ITEMS.size()] if r.place <= 3 else ["stapler", "planes", "energy", "stapler"][rng.randi() % 4]
					events.append(["pickup", b.pos, r.id])
				break


func _ahead_of(r: Racer, max_gap := 160.0) -> Racer:
	var best: Racer = null
	var bg := INF
	for o in racers:
		if o == r: continue
		var gap: float = o.progress - r.progress
		if gap > 0.0 and gap < max_gap and gap < bg: bg = gap; best = o
	return best


func _use_item(r: Racer) -> void:
	var it := r.item
	r.item = ""
	var fwd := Vector3(sin(r.heading), 0, cos(r.heading))
	match it:
		"stapler":   # homes in on the car ahead
			var s := Shot.new(); s.kind = "homing"; s.prop = "stapler"; s.owner = r.id
			var t := _ahead_of(r); s.target = t.id if t != null else -1
			s.pos = r.pos + fwd * 3.0 + Vector3(0, 0.8, 0); s.dir = fwd; s.speed = 62.0
			shots.append(s)
		"planes":    # three paper planes straight ahead
			for k in 3:
				var s := Shot.new(); s.kind = "straight"; s.prop = "plane"; s.owner = r.id
				var d := fwd.rotated(Vector3.UP, (k - 1) * 0.08)
				s.pos = r.pos + d * 3.0 + Vector3(0, 0.8, 0); s.dir = d; s.speed = 70.0; s.life = 90
				shots.append(s)
		"coffee", "peel":   # dropped behind
			var h := Hazard.new(); h.kind = it; h.prop = it; h.owner = r.id
			h.pos = r.pos - fwd * 3.5
			hazards.append(h)
		"energy":
			r.boost = 120
			r.nitro = 100.0
	events.append(["use", r.pos, r.id])


## Each person's power becomes their signature race attack (from design/fighters.json "prop" / "fx").
func _use_power(r: Racer) -> void:
	r.power = 0.0
	var prop: String = (r.C.get("person", {}) as Dictionary).get("prop", "code")
	var fwd := Vector3(sin(r.heading), 0, cos(r.heading))
	events.append(["power", r.pos, r.id])
	match prop:
		"logo", "goat", "snake":   # a giant charge down the road: hits everyone in front within range
			var s := Shot.new(); s.kind = "charge"; s.prop = prop; s.owner = r.id; s.big = true
			s.pos = r.pos + fwd * 4.0; s.dir = fwd; s.speed = 75.0; s.life = 150; s.idx = r.idx
			shots.append(s)
		"smoke", "paint", "clock", "pixels", "letters", "bubble":   # a spill across the road behind
			for k in 5:
				var h := Hazard.new(); h.kind = "spill"; h.prop = prop; h.owner = r.id
				h.pos = r.pos - fwd * (5.0 + k * 3.0) + Vector3(sin(r.heading + PI / 2), 0, cos(r.heading + PI / 2)) * (k - 2) * 2.2
				hazards.append(h)
		_:   # homing volley of their prop at the cars ahead (bananas, chai, cards, staplers...)
			var targets: Array = []
			var t := _ahead_of(r, 220.0)
			while t != null and targets.size() < 3:
				targets.append(t)
				var nxt: Racer = null
				var bg := INF
				for o in racers:
					var gap: float = o.progress - t.progress
					if o != r and gap > 0.0 and gap < bg: bg = gap; nxt = o
				t = nxt
			if targets.is_empty(): targets = [null]
			for k in maxi(3, targets.size()):
				var s := Shot.new(); s.kind = "homing"; s.prop = prop; s.owner = r.id
				var tg = targets[k % targets.size()]
				s.target = tg.id if tg != null else -1
				s.pos = r.pos + fwd * 3.0 + Vector3(0, 1.0 + k * 0.4, 0); s.dir = fwd.rotated(Vector3.UP, (k - 1) * 0.2); s.speed = 58.0
				shots.append(s)


func _hit(r: Racer, by: int, kind: String) -> void:
	if r.stun > 0: return
	r.stun = 55 if kind != "spill" else 35
	r.speed *= 0.5
	r.item = ""
	r.hits += 1
	r.flash = 20
	if by >= 0 and by < racers.size(): (racers[by] as Racer).power = minf(100.0, (racers[by] as Racer).power + 12.0)
	events.append(["hit", r.pos, r.id])


func _update_shots() -> void:
	for s in shots.duplicate():
		s.life -= 1
		if s.kind == "homing" and s.target >= 0:
			var t: Racer = racers[s.target]
			var to: Vector3 = (t.pos + Vector3(0, 0.8, 0) - s.pos).normalized()
			s.dir = s.dir.slerp(to, 0.12).normalized()
		elif s.kind == "charge":
			# follows the road
			s.idx = _nearest(s.pos, s.idx)
			s.dir = s.dir.slerp(T[s.idx], 0.2).normalized()
			s.pos.y = P[s.idx].y + 1.5
		s.pos += s.dir * s.speed * DT
		var done: bool = s.life <= 0
		for r in racers:
			if r.id == s.owner: continue
			if r.pos.distance_to(s.pos) < (4.0 if s.big else 2.0):
				_hit(r, s.owner, s.kind)
				if not s.big: done = true
		for t in traffic:
			if t.pos.distance_to(s.pos) < 2.5 and not s.big: done = true; t.stun = 60
		if done:
			if s.life > 0: events.append(["boom", s.pos, s.owner])
			shots.erase(s)


func _update_hazards() -> void:
	for h in hazards.duplicate():
		h.life -= 1
		var gone: bool = h.life <= 0
		for r in racers:
			if r.pos.distance_to(h.pos) < (2.2 if h.kind == "spill" else 1.7) and not r.air:
				if r.id == h.owner and h.life > 840: continue   # can't hit your own drop straight away
				_hit(r, h.owner, h.kind)
				gone = true
		if gone: hazards.erase(h)


func _rank() -> void:
	var order := racers.duplicate()
	order.sort_custom(func(a, b):
		if a.finished >= 0.0 and b.finished >= 0.0: return a.finished < b.finished
		if a.finished >= 0.0: return true
		if b.finished >= 0.0: return false
		return a.progress > b.progress)
	for k in order.size(): (order[k] as Racer).place = k + 1
	# the race ends when every human has finished (everyone, if it's all CPU),
	# or 45 s after the winner crossed the line
	var any_human := false
	var waiting := false
	for r in racers:
		if r.human >= 0: any_human = true
	for r in racers:
		if (r.human >= 0 or not any_human) and r.finished < 0.0: waiting = true
	var leader: Racer = order[0]
	if state == "race" and (not waiting or (leader.finished >= 0.0 and time - leader.finished > 45.0)):
		state = "done"
		events.append(["done", Vector3.ZERO, 0])


# ---------------------------------------------------------------- CPU drivers
func _cpu_pace(r: Racer) -> float:
	# a little rubber band so races stay close
	var lead: Racer = null
	for o in racers:
		if o.human >= 0 and (lead == null or o.progress > lead.progress): lead = o
	if lead == null: return 0.97
	var gap: float = lead.progress - r.progress
	return clampf(0.94 + gap / 600.0, 0.88, 1.04)


func _cpu(r: Racer) -> Dictionary:
	var look := 12.0 + r.speed * 0.9
	var i := _index_at(r.dist + look)
	# weave around traffic, cones and hazards ahead
	var aim_lat := r.lane_pref
	for t in traffic:
		var ahead: float = fposmod(t.dist - r.dist, length)
		if ahead > 0.0 and ahead < 60.0 and absf(t.lat - aim_lat) < 4.5:
			aim_lat = t.lat - signf(t.lat + 0.01) * 6.2
	for h in hazards:
		var to: Vector3 = h.pos - r.pos
		var fwd := Vector3(sin(r.heading), 0, cos(r.heading))
		if to.dot(fwd) > 0.0 and to.length() < 30.0:
			aim_lat += -signf(to.dot(fwd.cross(Vector3.UP))) * 4.0
	aim_lat = clampf(aim_lat, -width * 0.3, width * 0.3)
	var target: Vector3 = P[i] + _right(i) * aim_lat
	var to_t := target - r.pos
	var want := atan2(to_t.x, to_t.z)
	var diff := wrapf(want - r.heading, -PI, PI)
	var steer := clampf(-diff * 2.6, -1.0, 1.0)
	# drift back toward the middle when a wall is close
	if absf(r.lat) > width * 0.36: steer += signf(r.lat) * 0.35
	# brake into tight corners
	var j := _index_at(r.dist + look * 2.0)
	var bend := absf(wrapf(atan2(T[j].x, T[j].z) - atan2(T[r.idx].x, T[r.idx].z), -PI, PI))
	var inp := {steer = clampf(steer, -1.0, 1.0), gas = 0.0 if bend > 0.9 and r.speed > 30.0 else 1.0,
		nitro = bend < 0.25 and r.nitro > 40.0 and (r.place > 3 or r.nitro > 90.0),
		brake = 0.8 if bend > 0.75 and r.speed > 26.0 else 0.0, drift = bend > 0.55 and r.speed > 22.0}
	r.think -= 1
	if r.think <= 0:
		r.think = rng.randi_range(20, 60)
		if r.item != "":
			var ahead := _ahead_of(r, 80.0)
			var behind := false
			for o in racers:
				var gap: float = r.progress - o.progress
				if o != r and gap > 0.0 and gap < 25.0: behind = true
			if (r.item in ["stapler", "planes"] and ahead != null) or (r.item in ["coffee", "peel"] and behind) or r.item == "energy":
				inp.item = true
		if r.power >= 100.0 and _ahead_of(r, 120.0) != null:
			inp.power = true
	return inp


# ---------------------------------------------------------------- snapshot (multiplayer)
## Compact state for guests to draw: racer transforms + race info, shots, hazards, traffic, boxes, cones.
func snapshot() -> Dictionary:
	var rs := []
	for r in racers:
		rs.append(Party.pack([r.pos.x, r.pos.y, r.pos.z, r.heading, r.speed, r.lap, r.place, r.item, roundi(r.power), r.stun, r.boost, r.finished,
			r.drifting, r.flash, roundi(r.nitro), r.nitro_on, r.vel.x, r.vel.z, r.air, r.progress, r.vy, r.hits, r.idx]))
	var ss := []
	for o in shots: ss.append(Party.pack([o.uid, o.prop, o.pos.x, o.pos.y, o.pos.z, o.big, o.dir.x, o.dir.z, o.speed]))
	var hs := []
	for h in hazards: hs.append(Party.pack([h.uid, h.prop, h.pos.x, h.pos.y, h.pos.z]))
	var ts := []
	for t in traffic: ts.append(Party.pack([t.pos.x, t.pos.y, t.pos.z, t.heading]))
	var bx := ""
	for b in boxes: bx += "1" if b.respawn > 0 else "0"
	var cn := ""
	for c in cones: cn += "1" if c.knocked > 0 else "0"
	return {t = tick_n, st = state, cd = countdown, time = snappedf(time, 0.001), r = rs, s = ss, h = hs, tr = ts, bx = bx, cn = cn}


## Guests: take the host's state. The racers' previous positions are kept so the view can smooth between ticks.
func apply(sn: Dictionary) -> void:
	tick_n = int(sn.t); state = String(sn.st); countdown = int(sn.cd); time = float(sn.time)
	var rs: Array = sn.r
	for k in mini(rs.size(), racers.size()):
		var r: Racer = racers[k]
		var a: Array = rs[k]
		r.prev_pos = r.pos; r.prev_heading = r.heading
		r.pos = Vector3(a[0], a[1], a[2]); r.heading = float(a[3]); r.speed = float(a[4])
		r.lap = int(a[5]); r.place = int(a[6]); r.item = String(a[7]); r.power = float(a[8]); r.stun = int(a[9]); r.boost = int(a[10])
		r.finished = float(a[11]); r.drifting = bool(a[12]); r.flash = int(a[13]); r.nitro = float(a[14]); r.nitro_on = bool(a[15])
		r.vel = Vector3(a[16], 0, a[17]); r.air = bool(a[18]); r.progress = float(a[19]); r.vy = float(a[20]); r.hits = int(a[21]); r.idx = int(a[22])
		r.dist = r.progress - r.lap * length
	var by_uid := {}
	for o in shots: by_uid[o.uid] = o
	var ns := []
	for a in sn.s:
		var o: Shot = by_uid.get(int(a[0]), null)
		if o == null:
			o = Shot.new(); o.uid = int(a[0])
		o.prop = String(a[1]); o.pos = Vector3(a[2], a[3], a[4]); o.big = bool(a[5]); o.dir = Vector3(a[6], 0, a[7]); o.speed = float(a[8])
		ns.append(o)
	shots = ns
	var hu := {}
	for h in hazards: hu[h.uid] = h
	var nh := []
	for a in sn.h:
		var h: Hazard = hu.get(int(a[0]), null)
		if h == null:
			h = Hazard.new(); h.uid = int(a[0])
		h.prop = String(a[1]); h.pos = Vector3(a[2], a[3], a[4])
		nh.append(h)
	hazards = nh
	var ts: Array = sn.tr
	for k in mini(ts.size(), traffic.size()):
		var t: Traffic = traffic[k]
		t.pos = Vector3(ts[k][0], ts[k][1], ts[k][2]); t.heading = float(ts[k][3])
	var bx: String = sn.get("bx", "")
	for k in mini(bx.length(), boxes.size()): boxes[k].respawn = 1 if bx[k] == "1" else 0
	var cn: String = sn.get("cn", "")
	for k in mini(cn.length(), cones.size()): cones[k].knocked = 1 if cn[k] == "1" else 0


## Guests, between snapshots: keep things moving the way they were going.
func coast() -> void:
	for r in racers:
		r.prev_pos = r.pos; r.prev_heading = r.heading
		if state == "race":
			r.pos += r.vel * DT
			if r.air:
				r.vy -= 30.0 * DT; r.pos.y += r.vy * DT
	for o in shots: o.pos += o.dir.normalized() * o.speed * DT
