class_name OfficeRides
extends RefCounted
## Rides in the BNB Virtual Office: driving a parked car or bike round the parking, and the rooftop
## parachute jump down to the parking.
##
## Driving: stand at the back of a parked car (or bike) and press E. W / S (or up / down) drive and
## reverse, A / D steer; a click or tap drives towards that spot. You can drive round the parking and,
## through the gate at its east end, along the service road. E again
## parks it back in its bay and you get out. Your act is "drive:N" (N = OfficeFloors.vehicles() index),
## so everyone sees you driving it and the bay standing empty.
##
## The jump: on the rooftop's west edge, press E. "jump" (a run-up, over the railing, the chute opens
## and you drop out of sight), then you come down over the parking under the chute ("chute") and land.
## Both are played from the act's clock, so everyone on either level sees the same thing.

const CAR_MAX := 9.0
const BIKE_MAX := 7.5
const REVERSE_MAX := 3.5
const AREA := Rect2(-150.0, -6.0, 60.0, 14.0)      # the parking
const LANE := Rect2(-150.0, 8.35, 60.0, 3.85)       # the service road in front of it (to the median's kerb)
const GATE := Vector2(-97.0, -90.5)                 # the gap in the railing between them (x from, to)
const JUMP_T := 2.4
const CHUTE_T := 3.4
const CHUTE_FROM := 14.0                            # how high over the parking you come in
const LAND := Vector2(-108.0, 2.0)                  # where you land: the open lane in the middle

var main
var floors: OfficeFloors
var mg
var rides := {}               # person key -> the vehicle node they're driving
var chutes := {}              # person key -> their parachute node
var speed := 0.0              # yours, while driving
var backing := false          # driving to a tapped spot: backing up to turn round
var bumped := false
var back_t := 0.0            # back up at least this long (out of a bay) before turning to drive on


func setup(m) -> void:
	main = m; floors = m.floors; mg = m.mg


static func vehicle_of(act: String) -> int:
	return int(act.substr(6)) if act.begins_with("drive:") else -1


static func is_car(i: int) -> bool:
	var vs := OfficeFloors.vehicles()
	return i >= 0 and i < vs.size() and String(vs[i].kind) == "car"


static func busy_act(act: String) -> bool:
	return act.begins_with("drive:") or act == "jump" or act == "chute"


# ---------------------------------------------------------------- driving
## Can a vehicle stand at p heading h? Inside the parking, clear of the other parked ones.
func ok(p: Vector2, h: Vector2, i: int, driven: Dictionary) -> bool:
	var car := is_car(i)
	var half := 1.25 if car else 0.55
	var r := 0.85 if car else 0.32
	var vs := OfficeFloors.vehicles()
	for q in [p + h * half, p - h * half, p]:
		if not (_inside(q, r, AREA) or _inside(q, r, LANE) or _inside(q, r, Rect2(GATE.x, AREA.position.y, GATE.y - GATE.x, LANE.end.y - AREA.position.y))): return false
		for j in vs.size():
			if j == i or driven.has(j): continue
			if not car and String(vs[j].kind) == "bike": continue     # a bike squeezes past the parked bikes
			var vp: Vector2 = vs[j].p
			var rect := Rect2(vp.x - 0.95, vp.y - 2.15, 1.9, 4.3) if String(vs[j].kind) == "car" else Rect2(vp.x - 0.2, vp.y - 0.95, 0.4, 1.9)
			if q.x > rect.position.x - r and q.x < rect.end.x + r and q.y > rect.position.y - r and q.y < rect.end.y + r: return false
	return true


static func _inside(q: Vector2, r: float, a: Rect2) -> bool:
	return q.x - r >= a.position.x and q.x + r <= a.end.x and q.y - r >= a.position.y and q.y + r <= a.end.y


## One frame of your driving. keys: like OfficeMain._keys() (x right, y down). Returns [pos, heading].
func drive(dt: float, i: int, pos: Vector2, h: Vector2, keys: Vector2, target: Vector2, driven: Dictionary) -> Array:
	dt = minf(dt, 0.05)
	var top := CAR_MAX if is_car(i) else BIKE_MAX
	var thr := -keys.y; var steer := keys.x
	if keys == Vector2.ZERO and target != Vector2.INF:      # clicked / tapped somewhere: drive there
		# between the parking and the service road, head for the gate first
		var goal := target; var gx := (GATE.x + GATE.y) / 2.0
		if (pos.y > AREA.end.y) != (target.y > AREA.end.y) and absf(pos.x - gx) > 1.0:
			goal = Vector2(gx, AREA.end.y - 2.2 if pos.y <= AREA.end.y else LANE.get_center().y)
		var to := goal - pos
		if to.length() > 1.2 or goal != target:
			var a := h.angle_to(to)
			# facing away (or nosed into a bay): back up, turning towards it, then drive on
			back_t -= dt
			if not backing and ((absf(a) > 1.6 and speed < 2.5) or bumped): backing = true; back_t = 1.5
			elif backing and ((back_t <= 0.0 and absf(a) < 1.0) or (bumped and back_t < 1.3)): backing = false
			if backing: thr = -1.0; steer = -signf(a) if back_t < 0.6 else 0.0     # straight out of the bay first, then turn
			else: thr = 1.0 if absf(a) < 1.4 or speed > 2.0 else 0.5; steer = clampf(a * 2.0, -1.0, 1.0)
			if goal == target and not backing and speed > 0.5 and to.length() < speed * speed / 24.0 + 1.0: thr = -1.0     # brake to stop there
			elif goal != target and speed > 4.0: thr = 0.0     # ease off for the gate
		else:
			backing = false
			thr = -1.0 if speed > 0.3 else (1.0 if speed < -0.3 else 0.0)
	else: backing = false
	if thr > 0.0: speed = minf(speed + (6.0 if speed >= 0.0 else 12.0) * dt * thr, top)
	elif thr < 0.0: speed = maxf(speed + (12.0 if speed > 0.0 else 5.0) * dt * thr, -REVERSE_MAX)
	else: speed = move_toward(speed, 0.0, 4.0 * dt)
	var turn := steer * 2.2 * clampf(absf(speed) / 3.0, 0.0, 1.0) * signf(speed) * dt
	var nh := h.rotated(turn)
	if turn != 0.0 and ok(pos, nh, i, driven): h = nh
	var np := pos + h * speed * dt
	if speed != 0.0:
		bumped = not ok(np, h, i, driven)
		if not bumped: pos = np
		else: speed = 0.0          # bumped into something
	return [pos, h]


## Where to step out of a vehicle at p (heading h): beside it, else behind or in front.
func get_out_spot(p: Vector2, h: Vector2, car: bool) -> Vector2:
	if p.y > AREA.end.y - 1.2: return Vector2((GATE.x + GATE.y) / 2.0, AREA.end.y - 1.6)   # out on the road: back inside the gate
	var side := Vector2(-h.y, h.x)
	var off := 1.5 if car else 0.9
	for q in [p - side * off, p + side * off, p - h * (off + 1.4), p + h * (off + 1.4), p - side * (off + 1.2), p + side * (off + 1.2)]:
		if not main._blocked(q): return q
	return p - side * off


func _vehicle(i: int) -> Node3D:
	var v: Dictionary = OfficeFloors.vehicles()[i]
	var n := Node3D.new()
	main.world.add_child(n)
	if String(v.kind) == "car": floors._car(Vector2.ZERO, v.paint, false, n, v.style, v.roof)
	else: floors._bike(Vector2.ZERO, int(v.col), n)
	return n


# ---------------------------------------------------------------- the jump
func _chute() -> Node3D:
	var n := Node3D.new()
	var canopy := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = 1.4; s.height = 1.2; s.is_hemisphere = true; s.radial_segments = 16; s.rings = 6
	canopy.mesh = s; canopy.material_override = mg._mat(Color(0.149, 0.694, 0.808), 0.6, 0.15)
	canopy.position = Vector3(0, 4.0, 0); canopy.scale = Vector3(1, 0.55, 1)
	n.add_child(canopy)
	for k in 4:      # stripes round the canopy
		var st := MeshInstance3D.new()
		var b := BoxMesh.new(); b.size = Vector3(0.24, 0.02, 2.82)
		st.mesh = b; st.material_override = mg._mat([Color(1.0, 0.45, 0.7), Color(1.0, 0.82, 0.3)][k % 2], 0.6, 0.2)
		st.position = Vector3(0, 4.0 + 0.67, 0); st.rotation.y = PI / 4.0 * k
		n.add_child(st)
	var line: StandardMaterial3D = mg._mat(Color(0.95, 0.95, 0.95), 0.9)
	for k in 6:
		var a := TAU * k / 6.0
		var top := Vector3(cos(a) * 1.35, 4.0, sin(a) * 1.35); var hand := Vector3(cos(a) * 0.2, 1.55, sin(a) * 0.15)
		var m := MeshInstance3D.new()
		var c := CylinderMesh.new(); c.top_radius = 0.008; c.bottom_radius = 0.008; c.height = top.distance_to(hand); c.radial_segments = 4
		m.mesh = c; m.material_override = line; m.position = (top + hand) / 2.0
		var up := (top - hand).normalized()
		m.basis = Basis(up.cross(Vector3.UP).normalized(), -acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
		n.add_child(m)
	main.world.add_child(n)
	return n


## The jump off the roof at time t: [forward, up, chute open 0..1, clip].
static func jump_at(t: float) -> Array:
	if t < 0.5: return [t / 0.5 * 0.7, 0.0, 0.0, "m_run"]
	if t < 1.1:
		var u := (t - 0.5) / 0.6
		return [0.7 + u * 1.8, sin(u * PI * 0.85) * 1.3, 0.0, "win_jump"]
	var u2 := (t - 1.1) / (JUMP_T - 1.1)
	return [2.5 + u2 * 1.2, 1.3 * (1.0 - u2) - 14.0 * u2 * u2, clampf((t - 1.4) / 0.4, 0.0, 1.0), "win_cheer"]


## Coming down over the parking at time t: [sideways sway, up, chute open 0..1, clip].
static func chute_at(t: float) -> Array:
	var fall := 2.8
	if t < fall:
		var u := t / fall
		return [sin(t * 2.2) * 0.4 * (1.0 - u), CHUTE_FROM * pow(1.0 - u, 1.6), 1.0, "win_cheer"]
	return [0.0, 0.0, clampf(1.0 - (t - fall) / 0.35, 0.0, 1.0), "intro_hard_landing"]


# ---------------------------------------------------------------- each frame
## Place a person who's driving / jumping. key: their id (-1 for you). Returns the clip to play
## ("" = not riding, leave them as they are), and how high they are (for the camera).
func pose(key: int, act: String, rig: Node3D, dir: Vector2, t: float) -> Array:
	var vi := vehicle_of(act)
	if vi >= 0:
		if not rides.has(key) or int(rides[key].get_meta("i")) != vi:
			_drop_ride(key)
			rides[key] = _vehicle(vi); rides[key].set_meta("i", vi)
		var n: Node3D = rides[key]
		n.position = rig.position; n.rotation.y = rig.rotation.y + PI
		_drop_chute(key)
		if is_car(vi):
			rig.visible = false
			return ["m_sit", 0.0]
		rig.visible = true
		rig.position.y = 0.32
		return ["m_sit", 0.0]
	_drop_ride(key)
	rig.visible = true
	if act == "jump" or act == "chute":
		var s: Array = jump_at(t) if act == "jump" else chute_at(t)
		var fwd := Vector3(dir.x, 0, dir.y)
		var side := Vector3(-dir.y, 0, dir.x)
		rig.position += (fwd * float(s[0]) if act == "jump" else side * float(s[0])) + Vector3(0, float(s[1]), 0)
		if float(s[2]) > 0.0:
			if not chutes.has(key): chutes[key] = _chute()
			var c: Node3D = chutes[key]
			c.position = rig.position; c.rotation.y = rig.rotation.y
			c.scale = Vector3(0.3 + 0.7 * float(s[2]), float(s[2]), 0.3 + 0.7 * float(s[2]))
			c.visible = true
		else: _drop_chute(key)
		return [String(s[3]), float(s[1])]
	_drop_chute(key)
	return ["", 0.0]


func _drop_ride(key: int) -> void:
	if rides.has(key):
		(rides[key] as Node3D).queue_free(); rides.erase(key)


func _drop_chute(key: int) -> void:
	if chutes.has(key):
		(chutes[key] as Node3D).queue_free(); chutes.erase(key)


## Someone left: take away their car / chute.
func forget(key: int) -> void:
	_drop_ride(key); _drop_chute(key)


## The bays stand empty while their car or bike is out.
func show_parked(driven: Dictionary) -> void:
	for i in floors.parked.size():
		(floors.parked[i] as Node3D).visible = not driven.has(i)
