class_name CricketGame
extends Node
## BNB Office Cricket: a Super Over on the lawn behind the office at golden hour. Draws the ground, the players
## (batter, bowler, keeper, fielders), bat and ball, and the HUD; runs a CricketSim (rules) on the host or locally.
## Online: the host runs the sim and streams snapshots + events; the guest who bowls sends their delivery,
## the guest who bats sends their press timing (measured on their own screen), direction and shot.

signal finished

const CricketSim = preload("res://scripts/cricket/cricket_sim.gd")
const BV := Color(0.62, 0.38, 1.0)
const CY := Color(0.13, 0.78, 0.92)
const GOLD := Color(1.0, 0.81, 0.35)
const BATTER_AT := Vector3(-0.32, 0, -10.55)
const KEEPER_AT := Vector3(0.1, 0, -13.2)
const FIELD := [Vector3(9, 0, -3), Vector3(13, 0, -10.5), Vector3(-9, 0, -2.5), Vector3(-13, 0, -11), Vector3(17, 0, 15), Vector3(-17, 0, 15)]
const BOUNDARY := 33.0

var G
var sim
var world: Node3D
var env: Environment
var cam: Camera3D
var layer: CanvasLayer
var hud: Control
var font: Font
var small: Font
var my_slot := 0
var local_all := false
var autoplay := false
var stats := {}
var paused := false
var results_shown := false

# visuals
var side_rigs: Array = []       # the two sides' characters (batter / bowler by innings)
var keeper
var keeper_C: Dictionary
var fielders: Array = []        # [{rig, home, C, t}]
var bat: Node3D
var ball: Node3D
var trail: Array = []
var trail_pos: Array = []
var stumps_far: Array = []      # batter's end: [stump x3, bail x2]
var bails_v: Array = []         # flying bails: [node, vel, spin]
var fly_t := -1.0               # local flight clock (s since release), -1 = no ball in flight
var hit := {}                   # the ball after the shot: {from, to, peak, t, dur, kind, who}
var swing_t := -10.0            # when the swing makes contact (on the flight clock)
var swing_loft := false
var run_t := -1.0               # batter running between the wickets
var run_n := 0
var toast := ""
var toast_t := 0.0
var toast_col := Color.WHITE
var comment := ""
var cam_pos := Vector3(0, 3.3, 22.0)
var cam_look := Vector3(0, 0.9, -9.5)
var crowd: MultiMeshInstance3D
var umpire
var umpire_C: Dictionary
var signal_kind := ""           # the umpire's signal: six / four / out / wide
var signal_t := 0.0
var board: Label3D              # the big scoreboard by the stand
var wagon: Array = []           # this innings' scoring shots: [angle, runs]
var stump_cam := 0.0            # bowled: a low look from behind the stumps
var catcher := -1               # the fielder who took the catch celebrates

# controls
var pick := 0                   # delivery kind index (bowler)
var aim := 0.0                  # line -1 .. 1
var meter_t := 0.0
var bat_dir := 0                # -1 off / 0 straight / 1 leg
var pressed := false            # batter already pressed for this ball
var btns := {}                  # touch / click buttons: name -> Rect2
var drag_x := -1.0

# multiplayer
var net: Party = null
var guest := false
var pid_slot := {}
var last_rev := -1


func start(g, people: Array, seed: int, slot := 0, pass_play := false) -> void:
	G = g
	my_slot = slot; local_all = pass_play
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	sim = CricketSim.new()
	sim.setup(people, seed)
	world = Node3D.new()
	G.add_child(world)
	_build_world()
	_build_players()
	layer = CanvasLayer.new(); layer.layer = 5
	G.add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	if net != null and not guest:
		for s in sim.sides:
			if s.human and s.slot > 0: sim.remote_bat = true


func start_net(g, people: Array, seed: int, slot: int, party: Party, is_guest: bool, pids: Dictionary) -> void:
	net = party; guest = is_guest; pid_slot = pids
	net.message.connect(_net_message)
	if not guest: net.left.connect(_net_left)
	start(g, people, seed, slot, false)


func stop() -> void:
	if net != null:
		if net.message.is_connected(_net_message): net.message.disconnect(_net_message)
		if net.left.is_connected(_net_left): net.left.disconnect(_net_left)
	if world != null: world.queue_free()
	if layer != null: layer.queue_free()
	world = null; layer = null


# ---------------------------------------------------------------- the ground
func _mat(c: Color, rough := 0.8, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough
	if emit > 0.0: m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	return m


func _box(size: Vector3, m: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b; mi.material_override = m; mi.position = pos
	(parent if parent != null else world).add_child(mi)
	return mi


func _cyl(r1: float, r2: float, h: float, m: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new(); c.top_radius = r1; c.bottom_radius = r2; c.height = h
	mi.mesh = c; mi.material_override = m; mi.position = pos
	(parent if parent != null else world).add_child(mi)
	return mi


func _ground_mat(a: Color, b: Color, scale: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/race_ground.gdshader")
	m.set_shader_parameter("col_a", a); m.set_shader_parameter("col_b", b); m.set_shader_parameter("scale", scale)
	return m


func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new(); var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.1, 0.3, 0.7); sm.sky_horizon_color = Color(0.66, 0.74, 0.86)
	sm.sky_curve = 0.25
	sm.ground_bottom_color = Color(0.15, 0.2, 0.12); sm.ground_horizon_color = Color(0.55, 0.5, 0.4)
	sm.sun_angle_max = 25.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY; env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.85); env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = 0.95
	env.glow_enabled = true; env.glow_intensity = 0.25; env.glow_hdr_threshold = 1.2
	env.fog_enabled = true; env.fog_density = 0.0012; env.fog_light_color = Color(0.7, 0.66, 0.68)
	env.adjustment_enabled = true; env.adjustment_saturation = 1.12
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-24), deg_to_rad(-35), 0)
	sun.light_energy = 1.05; sun.light_color = Color(1.0, 0.82, 0.62)
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 60
	world.add_child(sun)
	# the outfield, mown stripes inside the rope
	var plane := PlaneMesh.new(); plane.size = Vector2(260, 260)
	var g := MeshInstance3D.new(); g.mesh = plane; g.material_override = _ground_mat(Color(0.22, 0.42, 0.16), Color(0.18, 0.34, 0.13), 0.06)
	world.add_child(g)
	for k in 12:
		_box(Vector3(BOUNDARY * 2.0 - 2.0, 0.005, 5.4), _mat(Color(0.27, 0.5, 0.2) if k % 2 == 0 else Color(0.23, 0.44, 0.17), 0.95),
			Vector3(0, 0.004, -BOUNDARY + 3.0 + k * 5.4))
	# the pitch: a worn strip with white creases
	_box(Vector3(3.2, 0.02, 22.5), _ground_mat(Color(0.74, 0.62, 0.42), Color(0.64, 0.52, 0.34), 1.2), Vector3(0, 0.012, 0))
	var white := _mat(Color(0.95, 0.95, 0.92), 0.6)
	for e in [-1.0, 1.0]:
		_box(Vector3(3.2, 0.012, 0.06), white, Vector3(0, 0.025, e * 10.0))
		_box(Vector3(2.64, 0.012, 0.06), white, Vector3(0, 0.025, e * 11.22))
		for sx in [-1.32, 1.32]:
			_box(Vector3(0.06, 0.012, 2.0), white, Vector3(sx, 0.025, e * 10.6))
	stumps_far = _stumps(Vector3(0, 0, -11.22))
	_stumps(Vector3(0, 0, 11.22))
	# boundary rope with BNB boards
	var rope := MeshInstance3D.new(); var tor := TorusMesh.new(); tor.inner_radius = BOUNDARY - 0.12; tor.outer_radius = BOUNDARY + 0.12; tor.rings = 96
	rope.mesh = tor; rope.material_override = _mat(Color(0.95, 0.95, 0.95), 0.5); rope.position = Vector3(0, 0.05, 0); rope.scale = Vector3(1, 0.4, 1)
	world.add_child(rope)
	for k in 24:
		var a := TAU * k / 24.0
		var board := _box(Vector3(1.8, 0.7, 0.08), _mat([BV, CY][k % 2], 0.5, 0.25), Vector3(cos(a) * (BOUNDARY + 1.2), 0.35, sin(a) * (BOUNDARY + 1.2)))
		board.rotation.y = -a + PI / 2
	_stand()
	_office()
	# the scoreboard by the stand, and the BNB logo painted on the grass either side of the pitch
	var sb_at := Vector3(-BOUNDARY - 6.0, 0, 20.0)
	_box(Vector3(0.6, 8.0, 0.6), _mat(Color(0.25, 0.25, 0.3), 0.5), sb_at + Vector3(0, 4, -3.5))
	_box(Vector3(0.6, 8.0, 0.6), _mat(Color(0.25, 0.25, 0.3), 0.5), sb_at + Vector3(0, 4, 3.5))
	_box(Vector3(0.5, 4.6, 9.0), _mat(Color(0.04, 0.04, 0.07), 0.4), sb_at + Vector3(0, 7.6, 0))
	board = Label3D.new(); board.font = font; board.font_size = 120; board.outline_size = 0; board.pixel_size = 0.012
	board.modulate = Color(1.4, 1.2, 0.5); board.position = sb_at + Vector3(0.3, 7.6, 0); board.rotation.y = PI / 2
	world.add_child(board)
	for side in [-1.0, 1.0]:
		var gl := Label3D.new(); gl.text = "BIT & BYTES"; gl.font = font; gl.font_size = 260; gl.outline_size = 0; gl.pixel_size = 0.012
		gl.modulate = Color(0.85, 0.9, 1.0, 0.16); gl.rotation = Vector3(-PI / 2, 0, PI / 2 * side); gl.position = Vector3(side * 9.0, 0.03, 4.0)
		world.add_child(gl)
	# sight-screens: a white one behind the bowler's arm, a dark one behind the batter
	for z in [-BOUNDARY - 3.0, BOUNDARY + 3.0]:
		_box(Vector3(10, 5, 0.3), _mat(Color(0.85, 0.85, 0.82) if z > 0 else Color(0.12, 0.12, 0.16), 0.8), Vector3(0, 2.6, z))
	# trees beyond the rope
	var rng := RandomNumberGenerator.new(); rng.seed = 4
	for k in 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(46, 64)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.z > 30 and absf(p.x - 14) < 30: continue   # the office is there
		if p.x < -36 and absf(p.z + 4) < 16: continue    # the stand
		_cyl(0.3, 0.4, 3.0, _mat(Color(0.35, 0.24, 0.14)), p + Vector3(0, 1.5, 0))
		var crown := MeshInstance3D.new(); var sp := SphereMesh.new(); sp.radius = rng.randf_range(2.4, 3.6); sp.height = sp.radius * 2.0
		crown.mesh = sp; crown.material_override = _mat(Color(0.16, 0.34, 0.15).lerp(Color(0.32, 0.45, 0.16), rng.randf()), 0.9)
		crown.position = p + Vector3(0, 4.6, 0)
		world.add_child(crown)
	# bat and ball
	bat = _make_bat()
	ball = Node3D.new(); world.add_child(ball)
	var bs := SphereMesh.new(); bs.radius = 0.06; bs.height = 0.12
	var bm := MeshInstance3D.new(); bm.mesh = bs; bm.material_override = _mat(Color(0.8, 0.06, 0.08), 0.35, 0.4)
	ball.add_child(bm)
	for k in 7:   # a fading trail
		var tm := MeshInstance3D.new(); var ts := SphereMesh.new(); ts.radius = 0.05 - k * 0.005; ts.height = ts.radius * 2.0
		tm.mesh = ts
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.85, 0.6, 0.45 - k * 0.055)
		tm.material_override = m; tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(tm); trail.append(tm)
	ball.visible = false
	cam = Camera3D.new(); cam.fov = 28; cam.far = 400
	cam.environment = env   # our sky and light win over the hidden fight stage
	world.add_child(cam); cam.current = true


## Three stumps and two bails: [stump x3, bail x2].
func _stumps(at: Vector3) -> Array:
	var out := []
	var wood := _mat(Color(0.93, 0.88, 0.75), 0.5)
	for x in [-0.115, 0.0, 0.115]:
		out.append(_cyl(0.019, 0.019, 0.71, wood, at + Vector3(x, 0.355, 0)))
	for x in [-0.058, 0.058]:
		out.append(_box(Vector3(0.11, 0.025, 0.025), _mat(Color(0.95, 0.8, 0.35), 0.5), at + Vector3(x, 0.725, 0)))
	return out


func _stand() -> void:
	# a small stand on the leg side with a cheering crowd (one batched draw)
	var at := Vector3(-BOUNDARY - 9.0, 0, -4.0)
	for r in 5:
		_box(Vector3(2.0, 0.5, 26.0), _mat(Color(0.32, 0.26, 0.4), 0.7), at + Vector3(-r * 1.6, 0.25 + r * 0.7, 0))
	_box(Vector3(9.0, 0.3, 27.0), _mat(BV.darkened(0.2), 0.5), at + Vector3(-3.4, 6.4, 0))
	for z in [-13.0, 13.0]: _box(Vector3(0.25, 6.4, 0.25), _mat(Color(0.8, 0.8, 0.85), 0.4), at + Vector3(0.5, 3.2, z))
	var xf := []; var cols := []
	var rng := RandomNumberGenerator.new(); rng.seed = 2
	var shirts := [BV, CY, GOLD, Color(0.95, 0.35, 0.4), Color(0.95, 0.95, 0.95), Color(0.3, 0.8, 0.45), Color(0.2, 0.25, 0.4)]
	for r in 5:
		for k in 30:
			xf.append(Transform3D(Basis.from_scale(Vector3(0.42, 0.9, 0.4)), at + Vector3(-r * 1.6, 0.5 + r * 0.7 + 0.45, -12.0 + k * 0.82 + rng.randf_range(-0.12, 0.12))))
			cols.append(shirts[rng.randi() % shirts.size()])
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
	var cap := CapsuleMesh.new(); cap.radius = 0.5; cap.height = 1.0; cap.radial_segments = 6; cap.rings = 2
	mm.mesh = cap; mm.instance_count = xf.size()
	for k in xf.size():
		mm.set_instance_transform(k, xf[k]); mm.set_instance_color(k, cols[k])
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm
	var cm := _mat(Color.WHITE, 0.8); cm.vertex_color_use_as_albedo = true
	mi.material_override = cm
	world.add_child(mi)
	crowd = mi


func _office() -> void:
	# the Bit & Bytes office beyond the bowler's end, windows lit, the logo on the roof, the car park in front
	var win := ShaderMaterial.new(); win.shader = load("res://shaders/windows.gdshader")
	var at := Vector3(14, 0, BOUNDARY + 24)
	_box(Vector3(40, 18, 14), win, at + Vector3(0, 9, 0))
	_box(Vector3(40.4, 0.6, 14.4), _mat(Color(0.2, 0.2, 0.25), 0.5), at + Vector3(0, 18.3, 0))
	var mark: Texture2D = load("res://assets/brand/bnb_mark_trim.png")
	var sp := Sprite3D.new(); sp.texture = mark; sp.pixel_size = 7.0 / mark.get_height(); sp.shaded = false
	sp.modulate = Color(1.4, 1.4, 1.4); sp.position = at + Vector3(0, 23.0, -6.0)
	world.add_child(sp)
	var cars := [Color(0.7, 0.1, 0.12), Color(0.85, 0.85, 0.88), Color(0.15, 0.3, 0.65), Color(0.1, 0.1, 0.12), Color(0.95, 0.75, 0.15)]
	for k in 7:
		var cp := Vector3(-8 + k * 4.2, 0, BOUNDARY + 11)
		_box(Vector3(1.9, 0.75, 4.2), _mat(cars[k % cars.size()], 0.3), cp + Vector3(0, 0.55, 0))
		_box(Vector3(1.7, 0.5, 2.2), _mat(Color(0.2, 0.25, 0.3), 0.15), cp + Vector3(0, 1.15, -0.2))


func _make_bat() -> Node3D:
	var n := Node3D.new(); world.add_child(n)
	var willow := _mat(Color(0.9, 0.78, 0.55), 0.6)
	var grip := _mat(Color(0.15, 0.15, 0.18), 0.8)
	_cyl(0.018, 0.018, 0.3, grip, Vector3(0, 0.15, 0), n)                       # handle (grip end at the origin)
	_box(Vector3(0.11, 0.56, 0.035), willow, Vector3(0, 0.58, 0), n)            # blade
	_box(Vector3(0.112, 0.04, 0.037), _mat(BV, 0.5), Vector3(0, 0.5, 0), n)    # BNB band
	return n


# ---------------------------------------------------------------- players
func _build_players() -> void:
	for k in 2:
		var rig := Main.make_rig(sim.sides[k].C, 0)
		world.add_child(rig)
		side_rigs.append(rig)
		var tag := Label3D.new()
		tag.text = _nm(k); tag.font = font; tag.font_size = 48; tag.outline_size = 10
		tag.modulate = [BV, CY][k].lightened(0.35); tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tag.pixel_size = 0.006
		tag.no_depth_test = true
		rig.add_child(tag); tag.position = Vector3(0, 2.3, 0)
		rig.set_meta("tag", tag)
	var pool := Data.ROSTER.filter(func(c): return c.id != sim.sides[0].C.id and c.id != sim.sides[1].C.id)
	pool.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	var picks := []
	while picks.size() < FIELD.size() + 2 and not pool.is_empty():
		picks.append(pool.pop_at(rng.randi() % pool.size()))
	umpire_C = picks[picks.size() - 1] if picks.size() > FIELD.size() + 1 else picks[0]
	keeper_C = picks[0]
	keeper = Main.make_rig(keeper_C, 0); world.add_child(keeper)
	keeper.position = KEEPER_AT
	umpire = Main.make_rig(umpire_C, 0); world.add_child(umpire)
	umpire.position = Vector3(-1.3, 0, 12.6)
	var hat := _cyl(0.2, 0.24, 0.12, _mat(Color(0.95, 0.95, 0.92), 0.7), Vector3.ZERO)   # the umpire's white hat
	hat.set_meta("umpire_hat", true)
	umpire.set_meta("hat", hat)
	# phones: three fielders instead of six, and the extra people cast no shadows (the GPU thanks you)
	var phone := OS.has_feature("mobile")
	for k in (3 if phone else FIELD.size()):
		var C: Dictionary = picks[(k + 1) % picks.size()]
		var f = Main.make_rig(C, 0)
		world.add_child(f)
		f.position = FIELD[k * (2 if phone else 1)]
		fielders.append({rig = f, home = FIELD[k * (2 if phone else 1)], C = C, t = randf() * 3.0})
		if phone: _no_shadows(f)
	if phone:
		_no_shadows(keeper); _no_shadows(umpire)


static func _no_shadows(n: Node) -> void:
	for mi in n.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _nm(k: int) -> String:
	var C: Dictionary = sim.sides[k].C
	return (String(C.person.get("short", C.name)) if C.has("person") else String(C.name)).to_upper()


func _face(rig: Node3D, dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01: return
	rig.rotation.y = atan2(dir.x, dir.z)


# ---------------------------------------------------------------- loop
var test_dt := 0.0          # tests on a slow renderer: a fixed game step per frame


func _process(dt: float) -> void:
	if sim == null or world == null: return
	if test_dt > 0.0: dt = test_dt
	if autoplay and not guest:
		for s in sim.sides: s.human = false
	if not guest and not paused:
		sim.update(dt)
		_drain()
	elif guest:
		sim.t += dt
	if fly_t >= 0.0: fly_t += dt
	_control(dt)
	_animate(dt)
	toast_t = maxf(0.0, toast_t - dt)
	hud.queue_redraw()


func _drain() -> void:
	var ev: Array = sim.events.duplicate()
	sim.events.clear()
	for e in ev: _event(e)
	if net != null and (sim.rev != last_rev or not ev.is_empty()):
		last_rev = sim.rev
		var pe := []
		for e in ev: pe.append(Party.pack(e))
		net.broadcast({t = "cs", s = sim.snapshot(), e = pe})


func _net_message(pid: int, m: Dictionary) -> void:
	match String(m.get("t", "")):
		"cs":
			if not guest: return
			sim.apply(m.s)
			for e in m.e: _event(Party.unpack_event(e))
		"ci":
			if guest or not pid_slot.has(pid): return
			var slot := int(pid_slot[pid])
			match String(m.get("a", "")):
				"bowl":
					if sim.bowl_side().human and sim.bowl_side().slot == slot: sim.bowl(String(m.k), float(m.l), float(m.m))
				"bat":
					if sim.bat_side().human and sim.bat_side().slot == slot: sim.bat(float(m.o), int(m.dir), bool(m.loft))
				"cont":
					sim.cont()


func _net_left(pid: int) -> void:
	if not pid_slot.has(pid): return
	for s in sim.sides:
		if s.slot == int(pid_slot[pid]):
			s.human = false
			_toast("PLAYER LEFT · CPU PLAYS ON", Color(1, 0.6, 0.5))
	sim.remote_bat = false


## Does this device play side k?
func _mine(k: int) -> bool:
	var s = sim.sides[k]
	return s.human and not autoplay and (local_all or s.slot == my_slot)


func _my_bowl() -> bool: return sim.phase == "setup" and _mine(sim.bowling())
func _my_bat() -> bool: return sim.phase in ["runup", "flight"] and _mine(sim.batting())


func _do_bowl() -> void:
	if not _my_bowl(): return
	var kind: String = CricketSim.KINDS[pick]
	var m := _meter()
	if guest: net.send({t = "ci", a = "bowl", k = kind, l = aim, m = m})
	else: sim.bowl(kind, aim, m)
	G.sfx("ui")


func _do_bat(loft: bool) -> void:
	if not _my_bat() or pressed or fly_t < 0.0: return
	pressed = true
	var off: float = fly_t - float(sim.d.get("T", 0.8))
	swing_t = fly_t; swing_loft = loft
	if guest: net.send({t = "ci", a = "bat", o = off, dir = bat_dir, loft = loft})
	else: sim.bat(off, bat_dir, loft)
	var tq := CricketSim.timing_of(off)
	if tq == 0: _toast("PERFECT!", GOLD, 0.8)
	elif tq == 1: _toast("GOOD TIMING", CY, 0.8)
	elif off < 0.0: _toast("TOO EARLY", Color(1, 0.6, 0.5), 0.8)
	else: _toast("TOO LATE", Color(1, 0.6, 0.5), 0.8)


func _do_cont() -> void:
	if sim.phase != "break": return
	if guest: net.send({t = "ci", a = "cont"})
	else: sim.cont()


func _meter() -> float:
	return 0.5 + 0.5 * sin(meter_t * 3.4)


func _control(dt: float) -> void:
	meter_t += dt
	if paused: return
	var pads := Input.get_connected_joypads()
	if _my_bowl():
		var ax := 0.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): ax -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): ax += 1.0
		if not pads.is_empty():
			var jx := Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_X)
			if absf(jx) > 0.25: ax = jx
		# on screen the off side (+x) is to the right: D moves the line toward off
		aim = clampf(aim + ax * dt * 1.4, -1.0, 1.0)
	if _my_bat() and not _touch():
		var dx := 0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): dx = 1    # leg side is on the left
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): dx = -1  # off side on the right
		if not pads.is_empty():
			var jx2 := Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_X)
			if absf(jx2) > 0.35: dx = -1 if jx2 > 0.0 else 1
		bat_dir = dx


func _unhandled_input(e: InputEvent) -> void:
	if sim == null: return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode in [KEY_P, KEY_ESCAPE]: toggle_pause(); return
		if paused: return
		var n: int = [KEY_1, KEY_2, KEY_3, KEY_4].find(e.physical_keycode)
		if n >= 0 and _my_bowl(): pick = n; G.sfx("ui")
		if e.physical_keycode in [KEY_SPACE, KEY_ENTER]:
			if _my_bowl(): _do_bowl()
			elif _my_bat(): _do_bat(Input.is_physical_key_pressed(KEY_SHIFT))
			elif sim.phase == "break" and local_all: _do_cont()
		if e.physical_keycode in [KEY_SHIFT, KEY_W, KEY_UP] and _my_bat(): _do_bat(true)
		if e.physical_keycode in [KEY_S, KEY_DOWN] and _my_bat(): _do_bat(false)
	if e is InputEventJoypadButton and e.pressed:
		if e.button_index == JOY_BUTTON_START: toggle_pause(); return
		if _my_bowl():
			if e.button_index == JOY_BUTTON_A: _do_bowl()
			elif e.button_index == JOY_BUTTON_LEFT_SHOULDER: pick = (pick + 3) % 4
			elif e.button_index == JOY_BUTTON_RIGHT_SHOULDER: pick = (pick + 1) % 4
		elif _my_bat():
			if e.button_index == JOY_BUTTON_A: _do_bat(false)
			elif e.button_index in [JOY_BUTTON_B, JOY_BUTTON_Y]: _do_bat(true)
		elif sim.phase == "break" and e.button_index == JOY_BUTTON_A: _do_cont()
	var click: bool = e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT
	if click and not paused and not results_shown and not _touch(): _tap(e.position)


func _input(e: InputEvent) -> void:
	if sim == null or not _touch(): return
	if e is InputEventScreenTouch and e.pressed:
		if e.position.distance_to(Vector2(hud.size.x - 50, 40)) < 34: toggle_pause(); get_viewport().set_input_as_handled(); return
		if not paused and not results_shown and _tap(e.position): get_viewport().set_input_as_handled()
		drag_x = e.position.x
	elif e is InputEventScreenTouch and not e.pressed:
		drag_x = -1.0
	elif e is InputEventScreenDrag and _my_bowl() and drag_x >= 0.0:
		aim = clampf(aim + e.relative.x / 260.0, -1.0, 1.0)


## A click / tap on one of the HUD buttons. True if it hit one.
func _tap(pos: Vector2) -> bool:
	for name in btns:
		if (btns[name] as Rect2).has_point(pos):
			match String(name):
				"pace", "spin", "yorker", "bouncer": pick = CricketSim.KINDS.find(name); G.sfx("ui")
				"bowl": _do_bowl()
				"ground": _do_bat(false)
				"loft": _do_bat(true)
				"off": bat_dir = -1
				"straight": bat_dir = 0
				"leg": bat_dir = 1
				"cont": _do_cont()
			return true
	return false


# ---------------------------------------------------------------- events
func _event(e: Array) -> void:
	var kind: String = e[0]
	stats[kind] = stats.get(kind, 0) + 1
	match kind:
		"toss":
			_toast("%s WON THE TOSS  ·  BATS FIRST" % _nm(int(e[1])), GOLD, 2.2)
			G.announce_voice("ready")
		"bowl":
			hit = {}; pressed = false; swing_t = -10.0; run_t = -1.0; fly_t = -1.0
			_reset_bails()
		"release":
			fly_t = 0.0
			# the CPU batter's swing starts on time (the host knows their press)
			if not guest and not sim.press.is_empty() and not _mine(sim.batting()):
				swing_t = float(sim.d.T) + float(sim.press.off); swing_loft = bool(sim.press.loft)
		"result":
			var runs: int = e[2]
			var out: bool = e[3]
			var how: String = e[4]
			var tq: int = e[5]
			if swing_t < -5.0 and tq < 3: swing_t = maxf(0.0, fly_t); swing_loft = bool(e[7])
			comment = String(sim.res.get("text", ""))
			_shot_path(runs, out, how, int(e[6]), bool(e[7]), int(e[1]))
			signal_kind = "six" if runs == 6 else ("four" if runs == 4 else ("out" if out else ("wide" if how == "wide" else "")))
			signal_t = 0.0
			catcher = int(hit.get("who", -1)) if how == "caught" else -1
			if how == "bowled": stump_cam = 1.6
			if runs > 0 and not out and not hit.is_empty():
				var dv: Vector3 = (hit.to as Vector3) - (hit.from as Vector3)
				wagon.append([atan2(dv.x, dv.z), runs])
			if runs == 6: get_tree().create_timer(2.3).timeout.connect(func(): if world != null and not hit.is_empty(): _confetti(hit.to))
			if how == "wide": _toast("WIDE  +1", Color(0.9, 0.9, 1.0), 1.6)
			elif out:
				_toast("OUT!  " + how.to_upper(), Color(1.0, 0.35, 0.3), 2.6)
				G.sfx("ko")
				if how == "bowled": _fly_bails()
			elif runs == 6:
				_toast("SIX!", GOLD, 2.6); G.sfx("heavy"); G.sfx("surge"); G.announce_voice("combo_breaker")
			elif runs == 4: _toast("FOUR!", CY, 2.2); G.sfx("heavy")
			elif runs > 0:
				_toast("%d RUN%s" % [runs, "S" if runs > 1 else ""], Color.WHITE, 1.4)
				run_t = 0.0; run_n = runs
			else: _toast("DOT BALL", Color(0.8, 0.82, 0.9), 1.2)
			if tq < 3 and how != "wide": G.sfx("hit")
		"innings":
			wagon.clear()
			_toast("%s: %d / %d" % [_nm(int(e[1])), int(e[2]), int(e[3])], GOLD, 2.6)
		"tie":
			_toast("TIED!  ANOTHER SUPER OVER", GOLD, 3.0)
			G.announce_voice("its_a_tie")
		"done":
			G.announce_voice("winner")
			if not results_shown:
				results_shown = true
				get_tree().create_timer(2.6).timeout.connect(_show_results)


## A burst of BNB-coloured confetti where a six lands.
func _confetti(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true; p.amount = 140; p.lifetime = 2.2; p.explosiveness = 0.95
	p.direction = Vector3.UP; p.spread = 60; p.initial_velocity_min = 6.0; p.initial_velocity_max = 13.0; p.gravity = Vector3(0, -7, 0)
	p.angular_velocity_min = -400; p.angular_velocity_max = 400
	var q := QuadMesh.new(); q.size = Vector2(0.22, 0.12)
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m; p.mesh = q
	var g := Gradient.new(); g.set_color(0, BV); g.set_color(1, CY); g.add_point(0.5, GOLD)
	p.color_initial_ramp = g
	p.position = Vector3(at.x, 0.5, at.z)
	world.add_child(p); p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


func _toast(t: String, col := Color.WHITE, dur := 1.8) -> void:
	toast = t; toast_col = col; toast_t = dur


func _reset_bails() -> void:
	bails_v.clear()
	for k in [3, 4]:
		var b: Node3D = stumps_far[k]
		b.position = Vector3(-0.058 if k == 3 else 0.058, 0.725, -11.22); b.rotation = Vector3.ZERO
	for k in 3: (stumps_far[k] as Node3D).rotation = Vector3.ZERO


func _fly_bails() -> void:
	for k in [3, 4]:
		bails_v.append([stumps_far[k], Vector3(randf_range(-1.5, 1.5), randf_range(3.0, 4.5), randf_range(-3.0, -1.5)), Vector3(randf() * 12, randf() * 12, 0)])
	(stumps_far[1] as Node3D).rotation.x = -0.35
	(stumps_far[0] as Node3D).rotation.z = 0.15


## Where the ball goes after the shot (visual only, the same on every screen: seeded by the ball number).
func _shot_path(runs: int, out: bool, how: String, dir: int, loft: bool, bn: int) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = bn * 7919 + 3
	var from := Vector3(BATTER_AT.x + 0.6, 0.85, -9.9)
	# off side is +x, straight is +z (back past the bowler), leg side is -x
	var ang: float = [0.8, 0.0, -0.85][dir + 1] + rng.randf_range(-0.35, 0.35)
	var flat := Vector3(sin(ang), 0, cos(ang))
	if how == "wide" or (runs == 0 and not out) or how == "bowled":
		hit = {}   # the ball carries on along its flight
		return
	if how == "caught behind":
		hit = {from = from, to = KEEPER_AT + Vector3(0, 0.8, 0.3), peak = 0.3, t = 0.0, dur = 0.35, kind = "catch", who = -1}
		return
	if how == "caught":
		var best := 0
		var bd := -INF
		for k in FIELD.size():
			var fp: Vector3 = FIELD[k]
			var dd := (fp - from).normalized().dot(flat)
			if dd > bd: bd = dd; best = k
		hit = {from = from, to = (FIELD[best] as Vector3) + Vector3(0, 1.6, 0), peak = 12.0, t = 0.0, dur = 2.0, kind = "catch", who = best}
		return
	var dist: float = {1: 13.0, 2: 21.0, 3: 26.0, 4: BOUNDARY + 2.0, 6: BOUNDARY + 16.0}.get(runs, 15.0)
	var to := from + flat * dist; to.y = 0.05
	var peak := 18.0 if runs == 6 else (0.4 if not loft else 3.0)
	var dur := 2.6 if runs == 6 else (1.5 if runs == 4 else 1.2 + runs * 0.2)
	var chaser := 0
	var cd := INF
	for k in FIELD.size():
		var d: float = (FIELD[k] as Vector3).distance_to(to)
		if d < cd: cd = d; chaser = k
	hit = {from = from, to = to, peak = peak, t = 0.0, dur = dur, kind = "six" if runs == 6 else "ground", who = chaser}


# ---------------------------------------------------------------- animation
const STANCE := {torsoX = 0.3, torsoY = 0.25, lsx = -0.55, rsx = -0.5, lsz = 0.35, rsz = -0.2, le = -0.45, re = -0.5,
	lk = 0.4, rk = 0.4, lhx = -0.25, rhx = -0.2, hipY = -0.06, headY = -0.9}
const BACKLIFT := {torsoX = 0.2, torsoY = 0.75, lsx = -1.25, rsx = -1.55, lsz = 0.15, rsz = -0.55, le = -1.0, re = -1.3,
	lk = 0.35, rk = 0.35, lhx = -0.2, rhx = -0.2, hipY = -0.05, headY = -1.0}
const FOLLOW := {torsoX = 0.2, torsoY = -0.95, lsx = -1.5, rsx = -1.25, lsz = -0.35, rsz = 0.25, le = -0.5, re = -0.55,
	lk = 0.3, rk = 0.25, lhx = -0.3, rhx = -0.1, hipY = -0.04, headY = -0.4}
const LOFT := {torsoX = -0.15, torsoY = -1.05, lsx = -2.4, rsx = -2.2, lsz = -0.25, rsz = 0.2, le = -0.6, re = -0.7,
	lk = 0.2, rk = 0.15, lhx = -0.2, rhx = -0.1, hipY = -0.02, headY = -0.3}


func _batter_pose(C: Dictionary) -> PackedFloat32Array:
	var g: PackedFloat32Array = C.pose.guard
	var st := Pose.with(g, STANCE)
	var bk := Pose.with(g, BACKLIFT)
	var fo := Pose.with(g, LOFT if swing_loft else FOLLOW)
	var T: float = float(sim.d.get("T", 0.8))
	if fly_t < 0.0:
		return st if sim.phase != "runup" else Pose.lerp_p(st, bk, clampf(sim.t / 1.25, 0.0, 1.0) * 0.4)
	if swing_t > -5.0:
		var u := fly_t - swing_t   # 0 = contact
		if u < -0.12: return Pose.lerp_p(st, bk, clampf(0.4 + (fly_t / maxf(0.1, swing_t - 0.12)) * 0.6, 0.0, 1.0))
		if u < 0.1: return Pose.lerp_p(bk, fo, Pose.ease_io(clampf((u + 0.12) / 0.22, 0.0, 1.0)))
		if u < 0.9: return fo
		return Pose.lerp_p(fo, st, clampf((u - 0.9) / 0.4, 0.0, 1.0))
	# waiting for the ball: the backlift rises as it comes
	return Pose.lerp_p(st, bk, clampf(0.4 + fly_t / T * 0.6, 0.0, 1.0))


func _animate(dt: float) -> void:
	var bi: int = sim.batting()
	var wi: int = sim.bowling()
	var batter = side_rigs[bi]
	var bowler = side_rigs[wi]
	var bC: Dictionary = sim.sides[bi].C
	var wC: Dictionary = sim.sides[wi].C
	# batter: side-on at the crease; swings with the shot; runs for singles
	var bt: float = batter.get_meta("t", 0.0) + dt
	batter.set_meta("t", bt)
	if run_t >= 0.0:
		run_t += dt
		var leg := 2.2
		var k := int(run_t / leg)
		if k >= run_n: run_t = -1.0
		else:
			var f := fmod(run_t, leg) / leg
			var z0 := -10.4 if k % 2 == 0 else 10.4
			batter.position = Vector3(-1.0, 0, lerpf(z0, -z0, f))
			_face(batter, Vector3(0, 0, 1) if k % 2 == 0 else Vector3(0, 0, -1))
			_clip(batter, bC, "m_run", bt)
	if run_t < 0.0:
		batter.position = batter.position.lerp(BATTER_AT, clampf(dt * 10.0, 0.0, 1.0))
		if sim.phase == "done" and sim.winner == bi:
			_face(batter, Vector3(0, 0, 1)); _celebrate(batter, bC, bt)
		elif sim.phase == "done":
			_face(batter, Vector3(0, 0, 1)); _clip(batter, bC, "in_shrug", bt)
		else:
			_face(batter, Vector3(sin(1.2), 0, cos(1.2)))
			batter.set_clip("", 0.0)
			batter.apply_pose(_batter_pose(bC), true)
	_place_bat(batter)
	# bowler: back to the mark, runs in, delivers
	var wt: float = bowler.get_meta("t", 0.0) + dt
	bowler.set_meta("t", wt)
	var pitch_clip := "pw_pitch" if ClipLib.has("pw_pitch") else "throw"
	if sim.phase == "done":
		bowler.position = Vector3(1.5, 0, 9.0)
		_face(bowler, Vector3(0, 0, -1))
		if sim.winner == wi: _celebrate(bowler, wC, wt)
		else: _clip(bowler, wC, "in_shrug", wt)
	elif sim.phase == "runup":
		var f := clampf(sim.t / 1.25, 0.0, 1.0)
		bowler.position = Vector3(0.6, 0, lerpf(18.5, 11.4, f))
		_face(bowler, Vector3(0, 0, -1))
		if f < 0.78: _clip(bowler, wC, "m_run", sim.t * 1.3)
		else: _clip(bowler, wC, pitch_clip, (f - 0.78) / 0.22 * _release_t())
	elif sim.phase == "flight":
		bowler.position = bowler.position.lerp(Vector3(0.9, 0, 10.4), clampf(dt * 3.0, 0.0, 1.0))
		_face(bowler, Vector3(0, 0, -1))
		_clip(bowler, wC, pitch_clip, _release_t() + maxf(0.0, fly_t))
	else:
		bowler.position = bowler.position.lerp(Vector3(0.9, 0, 15.0), clampf(dt * 1.5, 0.0, 1.0))
		_face(bowler, Vector3(0, 0, -1))
		_clip(bowler, wC, "idle_relaxed", wt)
	# keeper crouches, fielders watch the ball and chase the shot
	var kt: float = keeper.get_meta("t", 0.0) + dt
	keeper.set_meta("t", kt)
	_face(keeper, Vector3(0, 0, 1))
	_clip(keeper, keeper_C, "crouch_idle" if sim.phase in ["runup", "flight"] else "idle_fight", kt)
	var bp := ball.global_position
	for i in fielders.size():
		var fd: Dictionary = fielders[i]
		var f = fd.rig
		fd.t = float(fd.t) + dt
		var chase: bool = not hit.is_empty() and int(hit.get("who", -1)) == i and sim.phase == "result"
		var want: Vector3 = fd.home
		if chase:
			var tgt: Vector3 = hit.to
			var u := clampf(float(hit.t) / float(hit.dur), 0.0, 1.0)
			want = (fd.home as Vector3).lerp(Vector3(tgt.x, 0, tgt.z), u * (0.9 if hit.kind != "catch" else 1.0))
		var moving: bool = f.position.distance_to(want) > 0.3
		f.position = f.position.move_toward(want, dt * 7.0)
		_face(f, (want - f.position) if moving else (Vector3(bp.x, 0, bp.z) - f.position))
		_clip(f, fd.C, "m_run" if moving else ("crouch_idle" if sim.phase == "flight" else "idle_relaxed"), fd.t)
	# the umpire at the bowler's end: hands behind the back, then the signal
	signal_t += dt
	var uC: Dictionary = umpire_C
	_face(umpire, Vector3(0, 0, -1))
	var hat: Node3D = umpire.get_meta("hat")
	if sim.phase == "result" and signal_kind != "" and signal_t > 0.6:
		umpire.set_clip("", 0.0)
		var sig: Dictionary = {"six": {lsx = -3.0, rsx = -3.0, lsz = 0.2, rsz = -0.2, le = 0.0, re = 0.0},
			"four": {rsx = -1.6, rsz = -0.2, re = -0.2, rsy = sin(signal_t * 9.0) * 0.6, lsx = 0.0},
			"out": {rsx = -2.9, rsz = -0.1, re = 0.0, lsx = 0.0},
			"wide": {lsz = 1.5, rsz = -1.5, le = 0.0, re = 0.0}}[signal_kind]
		umpire.apply_pose(Pose.with(uC.pose.guard, sig), true)
	else:
		_clip(umpire, uC, "idle_relaxed", Time.get_ticks_msec() / 1000.0)
	var uh = umpire.get("head")
	hat.global_position = (uh.global_position + Vector3(0, 0.13, 0)) if uh is Node3D else umpire.global_position + Vector3(0, 1.82 * float(uC.scale), 0)
	# only the batter wears a name tag (the bowler runs right past the camera)
	(batter.get_meta("tag") as Label3D).visible = true
	(bowler.get_meta("tag") as Label3D).visible = false
	if catcher >= 0 and sim.phase == "result" and float(hit.get("t", 0.0)) > float(hit.get("dur", 1.0)):
		var fd: Dictionary = fielders[catcher]
		_clip(fd.rig, fd.C, Fighter.own_clip(fd.C, "win", "win_cheer"), float(hit.t) - float(hit.dur))
	if board != null:
		var bs = sim.sides[bi]
		var nd: Array = sim.need()
		board.text = "%s  %d/%d\n%s" % [_nm(bi), bs.runs, bs.wkts, ("NEED %d OFF %d" % [nd[0], nd[1]]) if not nd.is_empty() else "OVER  0.%d" % bs.balls]
	_animate_ball(dt)
	for b in bails_v:   # bails flying off
		var n: Node3D = b[0]
		b[1].y -= 9.8 * dt
		n.position += b[1] * dt
		n.rotation += b[2] * dt
		if n.position.y < 0.02: n.position.y = 0.02; b[1] = Vector3.ZERO; b[2] = Vector3.ZERO
	if crowd != null:   # the crowd jumps for the big moments
		var j := 0.0
		if toast_t > 0.0 and (toast.begins_with("SIX") or toast.begins_with("FOUR") or toast.begins_with("OUT")): j = absf(sin(Time.get_ticks_msec() / 90.0)) * 0.25
		crowd.position.y = lerpf(crowd.position.y, j, clampf(dt * 12.0, 0.0, 1.0))
	_camera(dt)


func _release_t() -> float:
	return Fighter._len("pw_pitch") * 0.52 if ClipLib.has("pw_pitch") else 0.4


func _clip(rig, C: Dictionary, clip: String, t: float) -> void:
	if not ClipLib.has(clip): clip = "idle_fight"
	var L := Fighter._len(clip)
	rig.set_clip(clip, fmod(t, L) if clip != "pw_pitch" else clampf(t, 0.0, L - 0.02), false, false)
	rig.apply_pose(C.pose.guard, true)


func _celebrate(rig, C: Dictionary, t: float) -> void:
	_clip(rig, C, Fighter.own_clip(C, "win", "win_cheer"), t)


## The bat sits in both hands: the grip at the top (left) hand, the blade out past the bottom (right) hand.
func _place_bat(batter) -> void:
	bat.visible = run_t < 0.0 and sim.phase != "done" and batter.has_method("hand_xform")
	if not bat.visible: return
	var lh: Vector3 = batter.hand_xform(false).origin
	var rh: Vector3 = batter.hand_xform(true).origin
	var dir := rh - lh
	if dir.length() < 0.04: dir = Vector3(0, -1, 0)
	dir = (dir.normalized() + Vector3(0, -0.35, 0)).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01: side = Vector3.RIGHT
	side = side.normalized()
	var fwd := side.cross(dir).normalized()
	bat.global_transform = Transform3D(Basis(side, dir, fwd), lh - dir * 0.05)


func _animate_ball(dt: float) -> void:
	var p := Vector3.ZERO
	var show := false
	if not hit.is_empty() and sim.phase == "result" and fly_t >= swing_t:
		hit.t = float(hit.t) + dt
		var u := clampf(float(hit.t) / float(hit.dur), 0.0, 1.0)
		var a: Vector3 = hit.from
		var b: Vector3 = hit.to
		p = a.lerp(b, u)
		p.y = lerpf(a.y, b.y, u) + float(hit.peak) * 4.0 * u * (1.0 - u)
		if hit.kind == "ground" and u > 0.15: p.y = maxf(0.06, p.y * (1.0 - u))
		show = true
	elif fly_t >= 0.0 and sim.d.has("T"):
		var T: float = sim.d.T
		var tt := fly_t
		if String(sim.res.get("how", "")) == "bowled": tt = minf(fly_t, T + 0.1)
		p = CricketSim.ball_pos(sim.d, minf(tt, T))
		if tt > T:   # past the batter: on into the keeper's gloves
			p = p.lerp(KEEPER_AT + Vector3(0, 0.7, 0.4), clampf((tt - T) / 0.3, 0.0, 1.0))
		show = sim.phase in ["flight", "result"]
	elif sim.phase == "runup" and sim.t > 0.9:
		var bw = side_rigs[sim.bowling()]
		p = bw.hand_xform(true).origin if bw.has_method("hand_xform") else Vector3(0.6, 2, 11)
		show = true
	ball.visible = show
	if show:
		ball.global_position = p
		trail_pos.push_front(p)
		if trail_pos.size() > 8: trail_pos.pop_back()
	else:
		trail_pos.clear()
	for k in trail.size():
		var tm: MeshInstance3D = trail[k]
		tm.visible = show and k + 1 < trail_pos.size()
		if tm.visible: tm.global_position = trail_pos[k + 1]


func _camera(dt: float) -> void:
	var want_pos := Vector3(0.0, 3.3, 22.0)
	var want_look := Vector3(0.0, 0.9, -9.5)
	var fov := 28.0
	stump_cam = maxf(0.0, stump_cam - dt)
	if stump_cam > 0.0 and sim.phase == "result":
		cam_pos = Vector3(0.05, 0.35, -12.6); cam_look = Vector3(0, 0.5, -10.0)
		cam.position = cam_pos; cam.look_at(cam_look, Vector3.UP); cam.fov = 60.0
		return
	if sim.phase == "result" and not hit.is_empty() and fly_t >= swing_t:
		# follow the shot from up high
		var bp := ball.global_position
		want_pos = Vector3(bp.x * 0.35, 10.0 + bp.y * 0.3, -1.0 + bp.z * 0.25)
		want_look = bp
		fov = 55.0
	elif sim.phase in ["toss", "break", "done"]:
		var a := Time.get_ticks_msec() / 6000.0
		want_pos = Vector3(sin(a) * 24.0, 9.0, cos(a) * 24.0)
		want_look = Vector3(0, 1.0, -2.0)
		fov = 50.0
	cam_pos = cam_pos.lerp(want_pos, clampf(dt * 3.5, 0.0, 1.0))
	cam_look = cam_look.lerp(want_look, clampf(dt * 5.0, 0.0, 1.0))
	cam.position = cam_pos
	cam.look_at(cam_look, Vector3.UP)
	cam.fov = lerpf(cam.fov, fov, clampf(dt * 3.0, 0.0, 1.0))


# ---------------------------------------------------------------- HUD
func _touch() -> bool:
	return G.ui.touch_enabled


func _draw_hud() -> void:
	var s := hud.size
	var ink := Color(0.95, 0.96, 1.0)
	btns.clear()
	# scoreboard (top left)
	var bi: int = sim.batting()
	var bs = sim.sides[bi]
	var col: Color = [BV, CY][bi]
	var box := Rect2(Vector2(20, 20), Vector2(380, 118))
	hud.draw_rect(box, Color(0.03, 0.02, 0.07, 0.78))
	hud.draw_rect(Rect2(box.position, Vector2(8, box.size.y)), col)
	hud.draw_string(small, box.position + Vector2(22, 24), "BATTING  ·  " + _nm(bi) + ("  (YOU)" if _mine(bi) and not local_all else ""), HORIZONTAL_ALIGNMENT_LEFT, 350, 18, col.lightened(0.4))
	hud.draw_string(font, box.position + Vector2(22, 66), "%d / %d" % [bs.runs, bs.wkts], HORIZONTAL_ALIGNMENT_LEFT, -1, 40, ink)
	hud.draw_string(small, box.position + Vector2(170, 64), ("0.%d OVERS" % bs.balls) if bs.balls < 6 else "1.0 OVERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.82, 0.9))
	var nd: Array = sim.need()
	var line2 := ("TARGET %d  ·  NEED %d OFF %d" % [sim.target, nd[0], nd[1]]) if not nd.is_empty() else ("BOWLING  ·  " + _nm(sim.bowling()))
	hud.draw_string(small, box.position + Vector2(22, 100), line2, HORIZONTAL_ALIGNMENT_LEFT, 350, 20, GOLD if not nd.is_empty() else Color(0.8, 0.82, 0.9))
	# this over, ball by ball
	var ox := 430.0
	var log: Array = bs.log
	var legal := 0
	for k in log.size():
		var v: String = log[k]
		var c := Vector2(ox + k * 40.0, 44)
		var bc := Color(0.45, 0.42, 0.6)
		match v:
			"4": bc = CY
			"6": bc = GOLD
			"W": bc = Color(0.95, 0.25, 0.25)
			"wd": bc = Color(0.55, 0.55, 0.7)
			"0": bc = Color(0.25, 0.25, 0.3)
		hud.draw_circle(c, 16, bc)
		hud.draw_string(font, c + Vector2(-16, 6), "•" if v == "0" else v.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 32, 15 if v != "wd" else 12, Color.WHITE)
		if v != "wd": legal += 1
	for k in range(legal, CricketSim.BALLS):
		hud.draw_arc(Vector2(ox + (log.size() + k - legal) * 40.0, 44), 15, 0, TAU, 24, Color(1, 1, 1, 0.3), 2.0)
	# status line
	var msg := ""
	match sim.phase:
		"setup": msg = "YOUR BALL: PICK A DELIVERY, AIM, BOWL" if _mine(sim.bowling()) else "%s IS AT THE TOP OF THE MARK" % _nm(sim.bowling())
		"runup", "flight": msg = "YOU'RE BATTING: SWING WHEN THE RING CLOSES" if _mine(bi) else ""
		"break": msg = ("INNINGS BREAK  ·  %s NEEDS %d" % [_nm(bi), sim.target]) if sim.target > 0 else "SUPER OVER AGAIN"
	if local_all and sim.phase in ["setup", "runup", "flight"]:
		msg = ("%s, BOWL!" % _nm(sim.bowling())) if sim.phase == "setup" else ("%s, BAT!" % _nm(bi))
	if autoplay and sim.phase != "break": msg = ""
	hud.draw_string(font, Vector2(0, 186), msg, HORIZONTAL_ALIGNMENT_CENTER, s.x, 24, ink)
	if _my_bowl(): _draw_bowl_ui(s)
	if _my_bat(): _draw_bat_ui(s)
	# speed gun once it's let go
	if sim.phase in ["flight", "result"] and sim.d.has("kmh"):
		var sp := Rect2(Vector2(s.x - 230, 20), Vector2(210, 70))
		hud.draw_rect(sp, Color(0.03, 0.02, 0.07, 0.78))
		hud.draw_rect(Rect2(sp.position, Vector2(sp.size.x, 4)), GOLD)
		hud.draw_string(small, sp.position + Vector2(14, 24), String(CricketSim.DELIVERIES[sim.d.kind].name) + ("  ·  BAD BALL" if sim.d.get("bad", false) else ""), HORIZONTAL_ALIGNMENT_LEFT, 190, 16, Color(0.8, 0.82, 0.9))
		hud.draw_string(font, sp.position + Vector2(14, 60), "%d km/h" % int(sim.d.kmh), HORIZONTAL_ALIGNMENT_LEFT, 190, 30, ink)
	if sim.phase in ["result", "setup"] and not wagon.is_empty() and not _my_bowl(): _draw_wagon(Vector2(s.x - 110, s.y - 190 if not _touch() else 300.0))
	# pass & play: hand the device over
	if sim.phase == "break" and local_all:
		hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.02, 0.07, 0.75))
		hud.draw_string(font, Vector2(0, s.y * 0.42), "PASS TO %s" % _nm(bi), HORIZONTAL_ALIGNMENT_CENTER, s.x, 54, GOLD)
		hud.draw_string(small, Vector2(0, s.y * 0.42 + 44), "%s bats, %s bowls  ·  target %d" % [_nm(bi), _nm(sim.bowling()), maxi(0, sim.target)], HORIZONTAL_ALIGNMENT_CENTER, s.x, 24, ink)
		_button("cont", Rect2(Vector2(s.x / 2 - 150, s.y * 0.42 + 80), Vector2(300, 64)), "READY", true, Color(0.9, 0.65, 0.15))
	if toast_t > 0.0:
		var a := clampf(toast_t / 0.4, 0.0, 1.0)
		var big := 80 if toast in ["SIX!", "FOUR!"] else 50
		hud.draw_string(font, Vector2(4, s.y * 0.36 + 4), toast, HORIZONTAL_ALIGNMENT_CENTER, s.x, big, Color(0, 0, 0, a * 0.6))
		hud.draw_string(font, Vector2(0, s.y * 0.36), toast, HORIZONTAL_ALIGNMENT_CENTER, s.x, big, Color(toast_col, a))
	if comment != "" and sim.phase in ["result", "setup"] and not _my_bowl():
		hud.draw_rect(Rect2(Vector2(s.x * 0.12, s.y - 76), Vector2(s.x * 0.76, 40)), Color(0, 0, 0, 0.55))
		hud.draw_string(small, Vector2(s.x * 0.12, s.y - 49), comment, HORIZONTAL_ALIGNMENT_CENTER, s.x * 0.76, 22, ink)
	if not _touch():
		var help := "1-4 delivery  ·  A / D aim  ·  SPACE bowl (stop the meter in the green)" if _my_bowl() else \
			("A / D direction  ·  SPACE ground shot  ·  SHIFT / W loft  ·  P pause" if _my_bat() else "P pause")
		hud.draw_string(small, Vector2(0, s.y - 10), help, HORIZONTAL_ALIGNMENT_CENTER, s.x, 17, Color(0.8, 0.82, 0.9, 0.7))
	else:
		var pb := Vector2(s.x - 50, 40)
		hud.draw_circle(pb, 26, Color(0.58, 0.3, 0.85, 0.3)); hud.draw_arc(pb, 26, 0, TAU, 32, Color(0.58, 0.3, 0.85), 3)
		hud.draw_string(font, pb + Vector2(-26, 8), "II", HORIZONTAL_ALIGNMENT_CENTER, 52, 20, Color.WHITE)


func _button(name: String, r: Rect2, label: String, on: bool, col: Color) -> void:
	hud.draw_rect(r, Color(col, 0.85 if on else 0.3))
	hud.draw_rect(r, Color(1, 1, 1, 0.8 if on else 0.3), false, 2.0)
	hud.draw_string(font, r.position + Vector2(0, r.size.y * 0.64), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(r.size.y * 0.36), Color.WHITE)
	btns[name] = r


## Wagon wheel: every scoring shot this innings from the batter's crease (gold sixes, cyan fours).
func _draw_wagon(c: Vector2) -> void:
	var r := 80.0
	hud.draw_circle(c, r + 6, Color(0.03, 0.02, 0.07, 0.75))
	hud.draw_circle(c, r, Color(0.16, 0.36, 0.14, 0.9))
	hud.draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.8), 2.0)
	hud.draw_rect(Rect2(c + Vector2(-3, -14), Vector2(6, 28)), Color(0.74, 0.62, 0.42))
	var base := c + Vector2(0, 12)
	for w in wagon:
		var ang: float = w[0]
		var runs: int = w[1]
		var len: float = r * (0.95 if runs >= 4 else 0.35 + runs * 0.15)
		# straight (+z, back past the bowler) points up; off side (+x) to the right
		var tip := base + Vector2(sin(ang), -cos(ang)) * len
		hud.draw_line(base, tip, GOLD if runs == 6 else (CY if runs == 4 else Color(1, 1, 1, 0.8)), 3.0 if runs >= 4 else 2.0)
	hud.draw_string(small, c + Vector2(-r, r + 22), "WAGON WHEEL", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 15, Color(0.8, 0.82, 0.9))


func _draw_bowl_ui(s: Vector2) -> void:
	# pitch map: where each delivery lands, with your aim
	var pm := Rect2(Vector2(s.x - 150, 120), Vector2(110, 260))
	hud.draw_rect(pm.grow(6), Color(0.03, 0.02, 0.07, 0.8))
	hud.draw_rect(pm, Color(0.74, 0.62, 0.42))
	var zone_y := func(z: float) -> float: return pm.position.y + (z - CricketSim.CREASE_Z) / (CricketSim.RELEASE.z - CricketSim.CREASE_Z) * pm.size.y
	for zz in [[-10.0, -8.0, Color(0.9, 0.3, 0.3, 0.35), "FULL"], [-8.0, -2.0, Color(0.3, 0.9, 0.4, 0.3), "GOOD"], [-2.0, 3.0, Color(0.3, 0.5, 1.0, 0.3), "SHORT"]]:
		var y0: float = zone_y.call(zz[0]); var y1: float = zone_y.call(zz[1])
		hud.draw_rect(Rect2(Vector2(pm.position.x, minf(y0, y1)), Vector2(pm.size.x, absf(y1 - y0))), zz[2])
		hud.draw_string(small, Vector2(pm.position.x, (y0 + y1) / 2.0 + 5), zz[3], HORIZONTAL_ALIGNMENT_CENTER, pm.size.x, 13, Color(0, 0, 0, 0.6))
	hud.draw_rect(Rect2(Vector2(pm.get_center().x - 10, pm.position.y + 2), Vector2(20, 4)), Color.WHITE)   # stumps
	var zb2: float = CricketSim.DELIVERIES[CricketSim.KINDS[pick]].zb
	var dot := Vector2(pm.get_center().x + aim * pm.size.x * 0.4, zone_y.call(zb2))
	hud.draw_circle(dot, 7, GOLD); hud.draw_arc(dot, 11, 0, TAU, 20, Color.WHITE, 2.0)
	hud.draw_string(small, pm.position + Vector2(0, -10), "PITCH MAP", HORIZONTAL_ALIGNMENT_CENTER, pm.size.x, 15, Color(0.8, 0.82, 0.9))
	var w := 150.0
	var x0 := s.x / 2.0 - 2.0 * (w + 10.0)
	for k in 4:
		var kind: String = CricketSim.KINDS[k]
		_button(kind, Rect2(Vector2(x0 + k * (w + 10.0), s.y - 190), Vector2(w, 54)), "%d  %s" % [k + 1, CricketSim.DELIVERIES[kind].name], pick == k, BV)
	# accuracy meter: stop it in the green
	var mr := Rect2(Vector2(s.x / 2 - 220, s.y - 118), Vector2(440, 26))
	hud.draw_rect(mr, Color(0, 0, 0, 0.6))
	hud.draw_rect(Rect2(mr.position + Vector2(mr.size.x * 0.34, 0), Vector2(mr.size.x * 0.32, mr.size.y)), Color(0.95, 0.75, 0.2, 0.55))
	hud.draw_rect(Rect2(mr.position + Vector2(mr.size.x * 0.44, 0), Vector2(mr.size.x * 0.12, mr.size.y)), Color(0.3, 0.9, 0.4, 0.85))
	var mx := mr.position.x + _meter() * mr.size.x
	hud.draw_rect(Rect2(Vector2(mx - 3, mr.position.y - 6), Vector2(6, mr.size.y + 12)), Color.WHITE)
	_button("bowl", Rect2(Vector2(s.x / 2 - 110, s.y - 82), Vector2(220, 50)), "BOWL", true, Color(0.9, 0.3, 0.3))
	# where it will pitch
	var zb: float = CricketSim.DELIVERIES[CricketSim.KINDS[pick]].zb
	var mp := cam.unproject_position(Vector3(aim * 0.55 * 0.6, 0.02, zb))
	hud.draw_arc(mp, 14, 0, TAU, 24, GOLD, 3.0)
	hud.draw_circle(mp, 4, GOLD)
	hud.draw_string(small, mp + Vector2(-70, 34), "AIM  ◀ A    D ▶" if not _touch() else "DRAG TO AIM", HORIZONTAL_ALIGNMENT_CENTER, 140, 16, GOLD)


func _draw_bat_ui(s: Vector2) -> void:
	# the timing ring at the hitting zone: it closes as the ball arrives
	var T: float = float(sim.d.get("T", 0.8))
	var zone := cam.unproject_position(Vector3(BATTER_AT.x + 0.5, 0.9, -9.9))
	hud.draw_arc(zone, 18, 0, TAU, 32, Color(1, 1, 1, 0.9), 3.0)
	if fly_t >= 0.0 and not pressed:
		var left := T - fly_t
		var r := 18.0 + maxf(0.0, left) * 150.0
		var rc := Color(0.3, 1.0, 0.45) if absf(left) < 0.05 else (GOLD if absf(left) < 0.11 else Color(1, 1, 1, 0.75))
		hud.draw_arc(zone, r, 0, TAU, 48, rc, 4.0)
	# direction (the off side is on the right, as we watch from behind the bowler)
	var names := ["OFF", "STRAIGHT", "LEG"]
	var keys := ["off", "straight", "leg"]
	var w := 130.0
	for k in 3:
		var slot := 2 - k
		_button(keys[k], Rect2(Vector2(s.x / 2.0 - 1.5 * w - 10 + slot * (w + 10), s.y - 160), Vector2(w, 46)), names[k], bat_dir == k - 1, CY)
	_button("ground", Rect2(Vector2(s.x / 2.0 - 230, s.y - 104), Vector2(220, 56)), "GROUND", true, Color(0.25, 0.6, 0.35))
	_button("loft", Rect2(Vector2(s.x / 2.0 + 10, s.y - 104), Vector2(220, 56)), "LOFT", true, Color(0.9, 0.55, 0.15))


# ---------------------------------------------------------------- pause + results
var pause_panel: Control = null


func toggle_pause() -> void:
	if results_shown or layer == null: return
	paused = not paused
	if pause_panel != null: pause_panel.queue_free(); pause_panel = null
	if not paused: return
	var ui = G.ui
	var panel := _panel()
	var v: VBoxContainer = panel.get_child(0)
	v.add_child(ui.lbl("PAUSED" if net == null else "MENU", 44, font, GOLD, 8))
	if net != null: v.add_child(ui.lbl("The match keeps going for everyone else.", 18, small, Color(0.8, 0.82, 0.9)))
	var resume: Button = ui.big_btn("RESUME", CY, toggle_pause)
	v.add_child(resume)
	v.add_child(ui.big_btn("QUIT TO MENU", Color(0.55, 0.62, 0.75), func(): paused = false; _quit()))
	_center(panel)
	pause_panel = panel
	resume.call_deferred("grab_focus")


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.03, 0.1, 0.92); sb.border_color = Color(0.58, 0.3, 0.85); sb.set_border_width_all(2)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	return panel


func _center(panel: Control) -> void:
	panel.reset_size()
	panel.position = (G.get_viewport().get_visible_rect().size - panel.size) / 2.0


func _quit() -> void:
	finished.emit()
	if net != null: G.lobby.leave()
	else: G.ui.show_title()


func _show_results() -> void:
	if layer == null: return
	var ui = G.ui
	var panel := _panel()
	var v: VBoxContainer = panel.get_child(0)
	var w: int = maxi(0, sim.winner)
	v.add_child(ui.lbl("%s WINS!" % _nm(w), 48, font, ([BV, CY][w] as Color).lightened(0.3), 8))
	for k in 2:
		var sd = sim.sides[k]
		var balls: Array = (sd.log as Array).map(func(x): return "•" if x == "0" else String(x).to_upper())
		v.add_child(ui.lbl("%s   %d / %d    %s" % [_nm(k), sd.runs, sd.wkts, "  ".join(balls)], 22, small, ([BV, CY][k] as Color).lightened(0.35)))
	var bx := HBoxContainer.new()
	bx.add_theme_constant_override("separation", 14)
	if net != null:
		bx.add_child(ui.big_btn("BACK TO LOBBY", CY, func(): finished.emit(); G.lobby.back_to_lobby()))
		bx.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), func(): finished.emit(); G.lobby.leave()))
	else:
		var C: Dictionary = sim.sides[0].C
		bx.add_child(ui.big_btn("PLAY AGAIN", CY, func(): finished.emit(); ui.show_game_menu("cricket", C)))
		bx.add_child(ui.big_btn("MAIN MENU", Color(0.55, 0.62, 0.75), func(): finished.emit(); ui.show_title()))
	v.add_child(bx)
	_center(panel)


# ---------------------------------------------------------------- tests
## --autotest=cricket: the CPU plays both sides; screenshots of the key moments.
func autotest(shot: Callable) -> void:
	var slow := DisplayServer.get_name() != "headless" and RenderingServer.get_video_adapter_name().to_lower().contains("llvmpipe")
	if slow:   # software rendering: step the game at a fixed rate, and only draw the fielders for the screenshots
		test_dt = 1.0 / 12.0
		for fd in fielders: fd.rig.visible = false
	var crowd_on := func(on: bool) -> void:
		for fd in fielders: fd.rig.visible = on or not slow
		keeper.visible = on or not slow
		umpire.visible = on or not slow
		if crowd != null: crowd.visible = on or not slow
	crowd_on.call(false)
	var snap := func(name: String) -> void:
		crowd_on.call(true)
		for k in 2: await get_tree().process_frame
		await shot.call(name)
		crowd_on.call(false)
	# the human controls first: bowling (deliveries, meter, pitch map), then batting (timing ring, shots)
	while sim.phase != "setup": await get_tree().process_frame
	autoplay = false
	var w: int = sim.bowling()
	sim.sides[w].human = true; sim.sides[w].slot = my_slot
	sim.sides[1 - w].human = false
	pick = 1; aim = 0.4
	for k in 6: await get_tree().process_frame
	await snap.call("cricket_ui_bowl")
	sim.bowl("pace", 0.0, 0.5)
	sim.sides[w].human = false
	sim.sides[1 - w].human = true; sim.sides[1 - w].slot = my_slot
	sim.press = {}
	while not (sim.phase == "flight" and fly_t > float(sim.d.T) * 0.55): await get_tree().process_frame
	await snap.call("cricket_ui_bat")
	autoplay = true
	var taken := {}
	var t0 := Time.get_ticks_msec()
	while sim.phase != "done" and Time.get_ticks_msec() - t0 < 900000:
		await get_tree().process_frame
		if slow:   # fast-forward through the moments we already have pictures of
			var want: bool = (sim.phase == "runup" and not taken.has("runup")) or (sim.phase == "flight" and not taken.has("flight")) \
				or (sim.phase == "result" and (not taken.has("hit") or not taken.has("out"))) or (sim.phase == "break" and not taken.has("break"))
			test_dt = 1.0 / 12.0 if want else 0.5
		if sim.phase == "runup" and sim.t > 0.95 and not taken.has("runup"):
			taken.runup = true; await snap.call("cricket_runup")
		elif sim.phase == "flight" and fly_t > float(sim.d.T) - 0.1 and not taken.has("flight"):
			taken.flight = true; await snap.call("cricket_flight")
		elif sim.phase == "result" and not hit.is_empty() and float(hit.t) > float(hit.dur) * 0.45 and not taken.has("hit"):
			taken.hit = true; await snap.call("cricket_hit")
		elif sim.phase == "result" and bool(sim.res.get("out", false)) and sim.t > 0.7 and not taken.has("out"):
			taken.out = true; await snap.call("cricket_out")
		elif sim.phase == "break" and sim.t > 0.5 and not taken.has("break"):
			taken.break = true; await snap.call("cricket_break")
	for k in 40: await get_tree().process_frame
	await snap.call("cricket_results")
	print("AUTOTEST cricket phase=%s winner=%d runs=[%d, %d] shots=%s" % [sim.phase, sim.winner, sim.sides[0].total, sim.sides[1].total, taken.keys()])


## --autotest=cricketsim: full matches between CPUs on the rules alone, plus snapshot -> apply round trips.
func selftest(_main) -> void:
	var ok := true
	for m in 6:
		var people := [{C = Data.ROSTER[m], human = false, slot = -1}, {C = Data.ROSTER[m + 1], human = false, slot = -1}]
		var a = CricketSim.new(); a.setup(people, 100 + m)
		var b = CricketSim.new(); b.setup(people, 999)
		var steps := 0
		var balls := 0
		while a.phase != "done" and steps < 80000:
			a.update(1.0 / 60.0)
			for e in a.events:
				if e[0] == "result": balls += 1
			a.events.clear()
			steps += 1
			if steps % 97 == 0:
				var sn: Dictionary = JSON.parse_string(JSON.stringify(a.snapshot()))   # as it travels over the wire
				b.apply(sn)
				var back: Dictionary = JSON.parse_string(JSON.stringify(b.snapshot()))
				if JSON.stringify(back) != JSON.stringify(sn): ok = false; print("MISMATCH ", sn, " vs ", back)
		if a.phase != "done": ok = false
		print("AUTOTEST cricketsim result=%s winner=%d balls=%d innings=%d runs=[%d, %d]" % [a.phase, a.winner, balls, a.innings + 1, a.sides[0].total, a.sides[1].total])
	print("AUTOTEST cricketsim %s" % ("PASS" if ok else "FAIL"))
