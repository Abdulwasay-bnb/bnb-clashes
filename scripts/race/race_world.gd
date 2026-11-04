class_name RaceWorld
extends Node3D
## BNB Rush Hour visuals: draws a RaceSim (or a host's snapshots) — road, scenery, cars with their drivers,
## items, effects and the chase camera. Holds no race rules.

const BV := Color(0.58, 0.3, 0.85)
const CY := Color(0.13, 0.78, 0.92)

var sim: RaceSim
var cam: Camera3D
var follow := 0                   # racer the camera chases
var cars: Array = []              # per racer: {root, body, rig, wheels, flame}
var shot_nodes := {}              # Shot / snapshot entry -> node
var hazard_nodes := {}
var traffic_nodes: Array = []
var box_nodes: Array = []
var cone_nodes: Array = []
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var env: Environment


func build(s: RaceSim, people: Array, me: int) -> void:
	sim = s
	follow = me
	_environment(String(sim.track.theme))
	_road()
	_scenery(String(sim.track.theme))
	for k in sim.racers.size():
		cars.append(_car(sim.racers[k]))
	for t in sim.traffic: traffic_nodes.append(_traffic_car(t.color))
	for b in sim.boxes:
		var n := _box()
		n.position = b.pos
		box_nodes.append(n)
	for c in sim.cones:
		var n := _cone()
		n.position = c.pos
		cone_nodes.append(n)
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 900
	add_child(cam)
	cam.current = true
	var r: RaceSim.Racer = sim.racers[follow]
	cam_pos = r.pos + Vector3(0, 5, 0) - Vector3(sin(r.heading), 0, cos(r.heading)) * 10.0
	cam_look = r.pos


# ---------------------------------------------------------------- world
func _environment(theme: String) -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	match theme:
		"city":
			sm.sky_top_color = Color(0.05, 0.03, 0.12); sm.sky_horizon_color = Color(0.35, 0.18, 0.4)
		"park":
			sm.sky_top_color = Color(0.25, 0.45, 0.8); sm.sky_horizon_color = Color(0.85, 0.82, 0.75)
		_:
			sm.sky_top_color = Color(0.12, 0.08, 0.3); sm.sky_horizon_color = Color(1.0, 0.55, 0.35)
	sm.ground_bottom_color = sm.sky_horizon_color.darkened(0.6); sm.ground_horizon_color = sm.sky_horizon_color.darkened(0.2)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.68, 0.8) if theme != "park" else Color(0.85, 0.85, 0.8)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true; env.glow_intensity = 0.35; env.glow_hdr_threshold = 1.4
	env.fog_enabled = true; env.fog_density = 0.0025; env.fog_light_color = sm.sky_horizon_color.darkened(0.3)
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1, 0.95, 0.88) if theme != "rooftop" else Color(1.0, 0.75, 0.55)
	sun.light_energy = 1.1 if theme == "park" else 0.85
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60
	add_child(sun)


func _mat(c: Color, rough := 0.8, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	return m


func _mesh(mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = m; mi.position = pos; mi.rotation = rot
	(parent if parent != null else self).add_child(mi)
	return mi


func _box_mesh(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z); return b


## The road: a strip along the centre line, with lane markings in its texture, kerbs and barriers.
func _road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := sim.P.size()
	var hw := sim.width / 2.0
	for i in n + 1:
		var a := i % n
		var b := (i + 1) % n
		var ra := sim._right(a); var rb := sim._right(b)
		var pa: Vector3 = sim.P[a] + Vector3(0, 0.02, 0); var pb: Vector3 = sim.P[b] + Vector3(0, 0.02, 0)
		var va := sim.S[a] / 6.0; var vb := (sim.S[a] + pa.distance_to(pb)) / 6.0
		_quad(st, pa - ra * hw, pa + ra * hw, pb + rb * hw, pb - rb * hw, Vector2(0, va), Vector2(1, va), Vector2(1, vb), Vector2(0, vb))
		# low barriers on both edges
		for side in [-1.0, 1.0]:
			var ea: Vector3 = pa + ra * side * (hw + 0.3); var eb: Vector3 = pb + rb * side * (hw + 0.3)
			_quad(walls, ea, eb, eb + Vector3(0, 1.1, 0), ea + Vector3(0, 1.1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	st.generate_normals()
	var road_m := ShaderMaterial.new()
	road_m.shader = load("res://shaders/race_road.gdshader")
	var road := MeshInstance3D.new(); road.mesh = st.commit(); road.material_override = road_m
	add_child(road)
	walls.generate_normals()
	var wm := _mat(Color(0.75, 0.75, 0.8), 0.6)
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var w := MeshInstance3D.new(); w.mesh = walls.commit(); w.material_override = wm
	add_child(w)
	# barrier stripes (purple / cyan) every few metres
	for i in range(0, n, 6):
		for side in [-1.0, 1.0]:
			var p: Vector3 = sim.P[i] + sim._right(i) * side * (hw + 0.32) + Vector3(0, 0.75, 0)
			_mesh(_box_mesh(0.08, 0.35, 1.2), _mat(BV if (i / 6) % 2 == 0 else CY, 0.5, 0.0, 0.8), p, Vector3(0, atan2(sim.T[i].x, sim.T[i].z), 0))
	# start / finish arch
	var s0: Vector3 = sim.P[0]
	var r0 := sim._right(0)
	for side in [-1.0, 1.0]:
		_mesh(_box_mesh(0.6, 7.0, 0.6), _mat(Color(0.12, 0.1, 0.16), 0.4, 0.6), s0 + r0 * side * (hw + 1.0) + Vector3(0, 3.5, 0))
	var beam := _mesh(_box_mesh(sim.width + 3.0, 1.4, 0.5), _mat(BV, 0.5, 0.0, 0.6), s0 + Vector3(0, 7.0, 0), Vector3(0, atan2(sim.T[0].x, sim.T[0].z) + PI / 2, 0))
	var l := Label3D.new()
	l.text = "BNB RUSH HOUR"; l.font_size = 160; l.outline_size = 0; l.modulate = Color(1.6, 1.6, 1.8)
	l.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	l.position = s0 + Vector3(0, 7.0, 0) - sim.T[0] * 0.3
	l.rotation = Vector3(0, atan2(sim.T[0].x, sim.T[0].z) + PI, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(l)
	var _unused := beam
	# chequered start line
	for k in 12:
		var p: Vector3 = s0 + r0 * (-hw + (k + 0.5) * sim.width / 12.0) + Vector3(0, 0.04, 0)
		_mesh(_box_mesh(sim.width / 12.0, 0.02, 1.2), _mat(Color.WHITE if k % 2 == 0 else Color(0.05, 0.05, 0.05)), p, Vector3(0, atan2(sim.T[0].x, sim.T[0].z), 0))
	# jumps: a ramp on the road
	for ri in sim.ramps:
		var p: Vector3 = sim.P[ri]
		var ramp := _mesh(_box_mesh(sim.width * 0.9, 0.15, 6.0), _mat(Color(1.0, 0.75, 0.2), 0.6, 0.0, 0.3), p + Vector3(0, 0.35, 0), Vector3(-0.12, atan2(sim.T[ri].x, sim.T[ri].z), 0))
		ramp.rotation_order = EULER_ORDER_YXZ


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(ub); st.add_vertex(b)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ud); st.add_vertex(d)


func _scenery(theme: String) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var ground_c: Color = {"city": Color(0.12, 0.11, 0.14), "park": Color(0.3, 0.5, 0.25), "rooftop": Color(0.2, 0.18, 0.22)}[theme]
	var plane := PlaneMesh.new(); plane.size = Vector2(900, 900)
	var gy := -0.05 if theme != "rooftop" else 0.0
	_mesh(plane, _mat(ground_c, 0.95), Vector3(0, gy, 80))
	var n := sim.P.size()
	var hw := sim.width / 2.0
	var win := ShaderMaterial.new()
	win.shader = load("res://shaders/windows.gdshader")
	var mark: Texture2D = load("res://assets/brand/bnb_mark_trim.png")
	for i in range(0, n, 9):
		for side in [-1.0, 1.0]:
			var p: Vector3 = sim.P[i]
			var out: Vector3 = sim._right(i) * side
			match theme:
				"city":   # towers with lit windows
					var h := rng.randf_range(14.0, 60.0)
					var d := hw + rng.randf_range(10.0, 26.0)
					var b := _mesh(_box_mesh(rng.randf_range(8, 14), h, rng.randf_range(8, 14)), win, p + out * d + Vector3(0, h / 2.0 - 0.1, 0))
					b.rotation.y = atan2(sim.T[i].x, sim.T[i].z)
					if i % 36 == 0:   # street lights
						_mesh(_box_mesh(0.2, 7.0, 0.2), _mat(Color(0.2, 0.2, 0.22), 0.4, 0.7), p + out * (hw + 2.0) + Vector3(0, 3.5, 0))
						_mesh(_box_mesh(0.8, 0.2, 0.4), _mat(Color(1, 0.95, 0.8), 0.3, 0.0, 2.5), p + out * (hw + 1.4) + Vector3(0, 7.0, 0))
				"park":   # trees and low offices
					if rng.randf() < 0.65:
						var tp: Vector3 = p + out * (hw + rng.randf_range(4.0, 16.0))
						_mesh(_box_mesh(0.4, 2.2, 0.4), _mat(Color(0.35, 0.22, 0.12)), tp + Vector3(0, 1.1, 0))
						var crown := SphereMesh.new(); crown.radius = rng.randf_range(1.6, 2.6); crown.height = crown.radius * 2.2
						_mesh(crown, _mat(Color(0.18, 0.45, 0.2).lerp(Color(0.35, 0.55, 0.2), rng.randf())), tp + Vector3(0, 3.6, 0))
					elif i % 18 == 0:
						var d := hw + rng.randf_range(18.0, 30.0)
						_mesh(_box_mesh(20, 8, 12), _mat(Color(0.85, 0.85, 0.88), 0.4), p + out * d + Vector3(0, 4, 0))
						_mesh(_box_mesh(20.2, 3, 12.2), _mat(Color(0.3, 0.55, 0.8), 0.1, 0.4), p + out * d + Vector3(0, 5, 0))
				_:        # rooftop: the road runs over buildings, the city far below
					var d := hw + rng.randf_range(2.0, 10.0)
					_mesh(_box_mesh(rng.randf_range(2, 4), rng.randf_range(1, 3), rng.randf_range(2, 4)), _mat(Color(0.55, 0.57, 0.6), 0.5, 0.4), p + out * d + Vector3(0, 0.8, 0))
					var h := rng.randf_range(10.0, 40.0)
					var tw := _mesh(_box_mesh(14, h, 14), win, p + out * (hw + rng.randf_range(40.0, 80.0)) + Vector3(0, h / 2.0 - 25.0, 0))
					tw.rotation.y = rng.randf() * PI
			if i % 45 == 0 and side > 0:   # Bit & Bytes billboards
				var sp := Sprite3D.new()
				sp.texture = mark; sp.pixel_size = 6.0 / mark.get_height(); sp.shaded = false
				sp.modulate = Color(1.4, 1.4, 1.4)
				sp.position = p + out * (hw + 4.0) + Vector3(0, 6.0, 0)
				sp.rotation.y = atan2(sim.T[i].x, sim.T[i].z) + PI / 2
				add_child(sp)
	if theme == "rooftop":   # the support under the road
		for i in range(0, n, 12):
			_mesh(_box_mesh(sim.width + 2.0, 30.0, 8.0), win, sim.P[i] + Vector3(0, -15.2, 0), Vector3(0, atan2(sim.T[i].x, sim.T[i].z), 0))


# ---------------------------------------------------------------- cars
## Open-top car in the racer's colour, with them in the driver's seat.
func _car(r: RaceSim.Racer) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var col: Color = r.C.accent
	var body := Node3D.new()
	root.add_child(body)
	var paint := _mat(col, 0.35, 0.4)
	# open cockpit: a low floor, side panels, bonnet and boot, so the driver is in plain view
	_mesh(_box_mesh(2.0, 0.28, 4.3), paint, Vector3(0, 0.42, 0), Vector3.ZERO, body)                   # floor pan
	for sx in [-0.92, 0.92]:
		_mesh(_box_mesh(0.16, 0.38, 2.0), paint, Vector3(sx, 0.72, -0.25), Vector3.ZERO, body)        # door panels
	_mesh(_box_mesh(1.9, 0.4, 1.6), paint, Vector3(0, 0.72, 1.35), Vector3(0.1, 0, 0), body)          # bonnet
	_mesh(_box_mesh(1.9, 0.42, 0.9), paint, Vector3(0, 0.74, -1.7), Vector3.ZERO, body)               # boot
	_mesh(_box_mesh(0.5, 0.5, 0.12), _mat(Color(0.1, 0.1, 0.12), 0.6), Vector3(0, 0.8, -0.75), Vector3(-0.15, 0, 0), body)   # seat back
	var wheel_t := TorusMesh.new(); wheel_t.inner_radius = 0.14; wheel_t.outer_radius = 0.18
	_mesh(wheel_t, _mat(Color(0.08, 0.08, 0.1), 0.5), Vector3(0, 1.05, 0.45), Vector3(PI / 2 - 0.5, 0, 0), body)            # steering wheel
	var glass := _mat(Color(0.6, 0.8, 1.0), 0.05, 0.3); glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glass.albedo_color.a = 0.35
	_mesh(_box_mesh(1.8, 0.42, 0.05), glass, Vector3(0, 1.12, 0.62), Vector3(-0.55, 0, 0), body)       # windscreen
	_mesh(_box_mesh(1.95, 0.08, 0.5), _mat(Color(0.1, 0.1, 0.12), 0.4, 0.5), Vector3(0, 1.0, -2.2), Vector3.ZERO, body)   # spoiler
	for side in [-0.6, 0.6]:
		_mesh(_box_mesh(0.35, 0.15, 0.05), _mat(Color(1, 1, 0.9), 0.3, 0.0, 2.0), Vector3(side, 0.7, 2.16), Vector3.ZERO, body)
		_mesh(_box_mesh(0.35, 0.12, 0.05), _mat(Color(1, 0.15, 0.1), 0.3, 0.0, 1.5), Vector3(side, 0.75, -2.16), Vector3.ZERO, body)
	var wheels: Array = []
	var tyre := CylinderMesh.new(); tyre.top_radius = 0.42; tyre.bottom_radius = 0.42; tyre.height = 0.32
	for wx in [-1.0, 1.0]:
		for wz in [-1.4, 1.4]:
			var w := _mesh(tyre, _mat(Color(0.06, 0.06, 0.07), 0.9), Vector3(wx * 1.02, 0.42, wz), Vector3(0, 0, PI / 2), body)
			wheels.append(w)
	var flame := _mesh(_box_mesh(0.5, 0.3, 1.2), _mat(Color(0.3, 0.8, 1.0), 0.2, 0.0, 3.0), Vector3(0, 0.6, -2.8), Vector3.ZERO, body)
	flame.visible = false
	# the driver, seated
	var rig := Main.make_rig(r.C, 0)
	root.add_child(rig)
	rig.scale = Vector3.ONE * 0.8
	rig.position = Vector3(0, 0.22, -0.5)
	var name_tag := Label3D.new()
	name_tag.text = String(r.C.person.get("short", r.C.name)) if r.C.has("person") else String(r.C.name)
	name_tag.font_size = 64; name_tag.outline_size = 10; name_tag.modulate = col.lightened(0.4)
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; name_tag.no_depth_test = true
	name_tag.position = Vector3(0, 2.7, 0)
	name_tag.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	root.add_child(name_tag)
	return {root = root, body = body, rig = rig, wheels = wheels, flame = flame, seat = _seated_pose(r.C)}


func _seated_pose(C: Dictionary) -> PackedFloat32Array:
	return Pose.with(C.pose.guard, {hipY = -0.36, torsoX = -0.1, lhx = -1.45, rhx = -1.45, lk = 1.2, rk = 1.2,
		lsx = -1.05, rsx = -1.05, lsz = 0.2, rsz = -0.2, le = -0.5, re = -0.5, headX = 0.0})


func _traffic_car(c: Color) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var m := _mat(c, 0.4, 0.3)
	_mesh(_box_mesh(2.1, 1.1, 4.6), m, Vector3(0, 0.85, 0), Vector3.ZERO, root)
	_mesh(_box_mesh(1.9, 0.8, 2.4), _mat(Color(0.25, 0.3, 0.38), 0.1, 0.4), Vector3(0, 1.7, -0.2), Vector3.ZERO, root)
	return root


func _box() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	_mesh(_box_mesh(1.2, 1.2, 1.2), _mat(CY, 0.3, 0.0, 1.2), Vector3.ZERO, Vector3(0.6, 0.6, 0), n)
	var q := Label3D.new(); q.text = "?"; q.font_size = 120; q.outline_size = 14; q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	q.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	n.add_child(q)
	return n


func _cone() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var c := CylinderMesh.new(); c.top_radius = 0.05; c.bottom_radius = 0.35; c.height = 0.8
	_mesh(c, _mat(Color(1.0, 0.45, 0.1)), Vector3(0, 0.4, 0), Vector3.ZERO, n)
	return n


func _shot_node(prop: String, big: bool) -> Node3D:
	var kind: String = {"stapler": "contract", "plane": "letters"}.get(prop, prop)
	var p := PowerProps.build(kind, CY)
	p.scale = Vector3.ONE * (6.0 if big else 2.4)
	add_child(p)
	return p


# ---------------------------------------------------------------- per frame
## Draw the race. a = 0..1 between the last two ticks (smooth movement on fast screens).
func draw(a: float, dt: float) -> void:
	for k in sim.racers.size():
		var r: RaceSim.Racer = sim.racers[k]
		var c: Dictionary = cars[k]
		var root: Node3D = c.root
		root.position = r.prev_pos.lerp(r.pos, a)
		root.rotation.y = lerp_angle(r.prev_heading, r.heading, a)
		var body: Node3D = c.body
		body.rotation.z = lerpf(body.rotation.z, (0.08 if r.drifting else 0.0) * signf(r.vel.cross(Vector3(sin(r.heading), 0, cos(r.heading))).y), 0.2)
		body.rotation.x = lerpf(body.rotation.x, -0.12 if r.air and r.vy > 0 else 0.0, 0.15)
		for w in c.wheels: (w as Node3D).rotate_object_local(Vector3.UP, r.speed * dt * 2.4)
		(c.flame as Node3D).visible = r.boost > 0
		var rig = c.rig
		if r.flash > 0 and rig.has_method("set_flash"): rig.set_flash(0.6)
		elif rig.has_method("set_flash"): rig.set_flash(0.0)
		rig.apply_pose(c.seat, false)
		if rig.has_method("set_face"): rig.set_face("angry" if r.stun > 0 else ("happy" if r.place == 1 else "neutral"))
	for i in sim.traffic.size():
		var t: RaceSim.Traffic = sim.traffic[i]
		var n: Node3D = traffic_nodes[i]
		n.position = n.position.lerp(t.pos, 0.5); n.rotation.y = t.heading
	for i in sim.boxes.size():
		var b: Dictionary = sim.boxes[i]
		var n: Node3D = box_nodes[i]
		n.visible = b.respawn <= 0
		n.rotation.y += dt * 1.5
	for i in sim.cones.size():
		(cone_nodes[i] as Node3D).visible = sim.cones[i].knocked <= 0
	_sync(sim.shots, shot_nodes, func(s): return _shot_node(s.prop, s.big), func(s, n):
		n.position = s.pos; n.rotation.y += dt * 8.0)
	_sync(sim.hazards, hazard_nodes, func(h): return _hazard_node(h.prop), func(h, n): n.position = h.pos)
	_camera(a, dt)


func _hazard_node(prop: String) -> Node3D:
	if prop == "coffee":
		var n := Node3D.new(); add_child(n)
		var c := CylinderMesh.new(); c.top_radius = 1.4; c.bottom_radius = 1.4; c.height = 0.03
		_mesh(c, _mat(Color(0.35, 0.2, 0.1), 0.1, 0.2), Vector3(0, 0.05, 0), Vector3.ZERO, n)
		return n
	var p := PowerProps.build("banana" if prop == "peel" else prop, CY)
	p.scale = Vector3.ONE * 2.6
	add_child(p)
	return p


func _sync(list: Array, nodes: Dictionary, make: Callable, update: Callable) -> void:
	var alive := {}
	for o in list:
		alive[o] = true
		if not nodes.has(o): nodes[o] = make.call(o)
		update.call(o, nodes[o])
	for o in nodes.keys():
		if not alive.has(o):
			(nodes[o] as Node).queue_free(); nodes.erase(o)


func _camera(a: float, dt: float) -> void:
	var r: RaceSim.Racer = sim.racers[follow]
	var p := r.prev_pos.lerp(r.pos, a)
	var h := lerp_angle(r.prev_heading, r.heading, a)
	var fwd := Vector3(sin(h), 0, cos(h))
	var want := p - fwd * (9.5 + r.speed * 0.06) + Vector3(0, 4.2, 0)
	cam_pos = cam_pos.lerp(want, clampf(dt * 6.0, 0.0, 1.0))
	cam_look = cam_look.lerp(p + fwd * 7.0 + Vector3(0, 1.2, 0), clampf(dt * 8.0, 0.0, 1.0))
	cam.position = cam_pos
	cam.look_at(cam_look, Vector3.UP)
	cam.fov = lerpf(cam.fov, 70.0 + (12.0 if r.boost > 0 else 0.0), dt * 3.0)
