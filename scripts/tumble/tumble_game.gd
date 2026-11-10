extends Node
## Tumble Tuesday: an obstacle-course knockout for up to 12 tumblers. A show of rounds (races, survival,
## a team game, a final) on office-themed courses; the field shrinks until one tumbler takes the BNB crown.
## Runs a TumbleSim (rules) on the host or locally and draws it: courses, moving obstacles, wobbly people,
## a follow camera and the show's HUD. Same contract as the other party games.

signal finished

const TumbleSim = preload("res://scripts/tumble/tumble_sim.gd")
const Maps = preload("res://scripts/tumble/tumble_maps.gd")
const BV := Color(0.62, 0.38, 1.0)
const CY := Color(0.13, 0.78, 0.92)
const GOLD := Color(1.0, 0.81, 0.35)
const TEAM_COL := [Color(0.15, 0.8, 0.95), Color(1.0, 0.42, 0.72)]
const TEAM_NAME := ["TEAM BIT", "TEAM BYTE"]

var G
var sim
var me := 0
var variant := ""
var autoplay := false
var stats := {}
var world: Node3D
var map_node: Node3D
var cam: Camera3D
var env: Environment
var layer: CanvasLayer
var hud: Control
var font: Font
var small: Font
var rigs: Array = []            # per player: {rig, tag, t}
var built_round := -1
var dyn := {}                   # obstacle kind -> Array of nodes
var crown_node: Node3D
var confetti: CPUParticles3D
var cam_yaw := 0.0
var cam_pitch := -0.32
var look := Vector2.ZERO
var paused := false
var pause_panel: Control
var results_shown := false
var banner := ""
var banner_col := Color.WHITE
var banner_t := 0.0
var feed: Array = []             # [text, time]
var spectate := -1
var mats := {}
var _go_t := 0.0
# touch
var touch_btn := {}
var touches := {}
var move_id := -1
var move_origin := Vector2.ZERO
var touch_move := Vector2.ZERO
var look_id := -1
var look_last := Vector2.ZERO
# multiplayer
var net: Party = null
var guest := false
var pid_player := {}            # host: guest pid -> player index
var inputs := {}
var inbox: Array = []
var outbox: Array = []


func start(g, people: Array, seed: int, slot := 0, pass_play := false) -> void:
	G = g
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	me = 0
	for k in people.size():
		if people[k].human and int(people[k].slot) == slot: me = k; break
	sim = TumbleSim.new()
	sim.setup(people, seed)
	world = Node3D.new()
	G.add_child(world)
	_build_env()
	for p in sim.players: rigs.append(_tumbler(p))
	cam = Camera3D.new(); cam.fov = 62; cam.far = 400; cam.environment = env
	world.add_child(cam); cam.current = true
	layer = CanvasLayer.new(); layer.layer = 5
	G.add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	_layout_touch()
	_build_round()


func start_net(g, people: Array, seed: int, slot: int, party: Party, is_guest: bool, pids: Dictionary) -> void:
	net = party; guest = is_guest
	for pid in pids:
		for k in people.size():
			if people[k].human and int(people[k].slot) == int(pids[pid]): pid_player[pid] = k
	net.message.connect(_net_message)
	if not guest: net.left.connect(_net_left)
	start(g, people, seed, slot, false)


func stop() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if net != null:
		if net.message.is_connected(_net_message): net.message.disconnect(_net_message)
		if net.left.is_connected(_net_left): net.left.disconnect(_net_left)
	if world != null: world.queue_free()
	if layer != null: layer.queue_free()
	world = null; layer = null


## The tutorial overlay's steps for this game.
static func tutorial_steps(_variant: String) -> Array:
	return [
		{title = "WELCOME TO TUMBLE TUESDAY", text = "Twelve tumblers, a show of wobbly rounds. Qualify from each round: the field shrinks until one of you takes the BNB crown.",
			keys = "", touch = ""},
		{title = "RUN, JUMP, DIVE", text = "Run with momentum, jump the spinning bars and gaps, dive to lunge forward (or bowl someone over).",
			keys = "WASD move  ·  mouse turns the camera  ·  SPACE jump  ·  SHIFT dive", touch = "left stick to move  ·  drag the right side to look  ·  JUMP  ·  DIVE"},
		{title = "RACES", text = "Reach the finish arch before the qualifying spots run out. Fall off and you go back to the last checkpoint.",
			keys = "the counter at the top shows QUALIFIED 5 / 9", touch = "the counter at the top shows QUALIFIED 5 / 9"},
		{title = "SURVIVAL AND TEAMS", text = "Stay on the crumbling desks or jump the mops until enough are out. In the Mail Room, push tubs into your team's bay.",
			keys = "hold E to grab and slow a rival", touch = "hold GRAB to slow a rival"},
		{title = "THE FINAL", text = "Climb to the roof and touch the crown first, or be the last one standing on the desks.",
			keys = "P / Esc pauses", touch = "II pauses"},
	]


# ---------------------------------------------------------------- materials / helpers
func _mat(c: Color, rough := 0.55, emit := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [c.to_html(), rough, emit]
	if mats.has(key): return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough
	if emit > 0.0: m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	mats[key] = m
	return m


func _box(size: Vector3, m: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b; mi.material_override = m; mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(r1: float, r2: float, h: float, m: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new(); c.top_radius = r1; c.bottom_radius = r2; c.height = h; c.radial_segments = 20
	mi.mesh = c; mi.material_override = m; mi.position = pos
	parent.add_child(mi)
	return mi


func _sph(r: float, m: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0; s.radial_segments = 18; s.rings = 10
	mi.mesh = s; mi.material_override = m; mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- the world
func _build_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY; env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = 0.95
	env.glow_enabled = true; env.glow_intensity = 0.3; env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true; env.adjustment_saturation = 1.2
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "sun"
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(30), 0)
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 60
	world.add_child(sun)
	# the city all around, far below (one batched draw)
	var win := ShaderMaterial.new(); win.shader = load("res://shaders/windows.gdshader")
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new(); bm.size = Vector3(1, 1, 1); mm.mesh = bm
	mm.instance_count = 60
	var rng := RandomNumberGenerator.new(); rng.seed = 21
	for k in 60:
		var a := TAU * k / 60.0
		var r := rng.randf_range(90, 150)
		var h := rng.randf_range(30, 90)
		var w := rng.randf_range(12, 24)
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(w, h, w)), Vector3(cos(a) * r, h / 2.0 - 40.0, sin(a) * r + 25.0)))
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = win
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)


func _set_sky(kind: String) -> void:
	var sm: ProceduralSkyMaterial = env.sky.sky_material
	var sun: DirectionalLight3D = world.get_node("sun")
	sm.ground_bottom_color = Color(0.1, 0.15, 0.35); sm.ground_horizon_color = Color(0.35, 0.5, 0.8)
	match kind:
		"server":
			sm.sky_top_color = Color(0.05, 0.06, 0.2); sm.sky_horizon_color = Color(0.25, 0.35, 0.7)
			env.ambient_light_color = Color(0.6, 0.68, 0.95); env.ambient_light_energy = 0.6; sun.light_energy = 0.8; sun.light_color = Color(0.85, 0.9, 1.0)
		"dusk":
			sm.sky_top_color = Color(0.2, 0.15, 0.5); sm.sky_horizon_color = Color(1.0, 0.6, 0.45)
			env.ambient_light_color = Color(0.85, 0.72, 0.8); env.ambient_light_energy = 0.5; sun.light_energy = 0.95; sun.light_color = Color(1.0, 0.8, 0.65)
		_:
			sm.sky_top_color = Color(0.12, 0.35, 0.9); sm.sky_horizon_color = Color(0.45, 0.65, 0.95)
			env.ambient_light_color = Color(0.75, 0.75, 0.9); env.ambient_light_energy = 0.5; sun.light_energy = 1.0; sun.light_color = Color(1, 0.97, 0.9)


## Build the current round's course.
func _build_round() -> void:
	built_round = sim.round_i
	if map_node != null: map_node.queue_free()
	map_node = Node3D.new()
	world.add_child(map_node)
	dyn = {movers = [], pushers = [], drops = [], belts = [], spins = [], balls = [], pends = [], tiles = [], tubs = []}
	crown_node = null
	var M: Dictionary = sim.map
	_set_sky(String(M.sky))
	for b in M.boxes:
		var c: Color = b[2]
		var sz: Vector3 = b[1]
		_box(sz, _mat(c), b[0], map_node)
		if sz.y <= 1.2:   # a darker lip along the top edge so platforms read clearly
			_box(Vector3(sz.x + 0.04, 0.12, sz.z + 0.04), _mat(c.darkened(0.3)), (b[0] as Vector3) + Vector3(0, sz.y / 2.0 - 0.06, 0), map_node)
	for m in M.movers:
		var n := Node3D.new(); map_node.add_child(n)
		_box(m.s, _mat(m.col), Vector3.ZERO, n)
		_box(Vector3((m.s as Vector3).x * 0.9, 0.04, 0.25), _mat(Color.WHITE, 0.4, 0.8), Vector3(0, (m.s as Vector3).y / 2.0 + 0.02, -(m.s as Vector3).z * 0.42), n)
		dyn.movers.append(n)
	for m in M.pushers:
		var n := Node3D.new(); map_node.add_child(n)
		_box(m.s, _mat(m.col), Vector3.ZERO, n)
		_box(Vector3(0.14, (m.s as Vector3).y * 0.8, (m.s as Vector3).z * 0.9), _mat(GOLD, 0.4, 0.6), (m.dir as Vector3) * ((m.s as Vector3).x / 2.0), n)   # the punching face
		dyn.pushers.append(n)
	for d in M.drops:
		var n := Node3D.new(); n.position = d.c; map_node.add_child(n)
		var sheet := _box(d.s, _mat(d.col, 0.8), Vector3.ZERO, n)
		for k in 4:   # printed lines on the paper
			_box(Vector3((d.s as Vector3).x * 0.7, 0.02, 0.06), _mat(Color(0.35, 0.35, 0.5)), Vector3(0, (d.s as Vector3).y / 2.0 + 0.01, -0.9 + k * 0.6), sheet)
		dyn.drops.append(n)
	for bl in M.belts:
		var n := Node3D.new(); n.position = bl.c; map_node.add_child(n)
		_box(bl.s, _mat(bl.col, 0.7), Vector3.ZERO, n)
		var stripes := Node3D.new(); n.add_child(stripes)
		for k in 12:
			_box(Vector3((bl.s as Vector3).x * 0.9, 0.04, 0.35), _mat(GOLD, 0.5, 0.5), Vector3(0, (bl.s as Vector3).y / 2.0 + 0.02, -(bl.s as Vector3).z / 2.0 + k * (bl.s as Vector3).z / 12.0), stripes)
		dyn.belts.append(stripes)
	for s in M.spins:
		var n := Node3D.new(); n.position = s.c; map_node.add_child(n)
		_cyl(0.45, 0.55, float(s.y1) + 0.5, _mat(Color(0.2, 0.2, 0.25), 0.4), Vector3(0, (float(s.y1) + 0.5) / 2.0, 0), n)
		var arms: int = s.arms
		for k in arms:
			var a := PI * k if arms == 2 else TAU * k / arms
			var arm := Node3D.new(); arm.rotation.y = -a; n.add_child(arm)
			var hgt: float = float(s.y1) - float(s.y0)
			_box(Vector3(float(s.len), hgt, float(s.th) * 2.0), _mat(s.col, 0.35), Vector3(float(s.len) / 2.0, float(s.y0) + hgt / 2.0, 0), arm)
			for st in 4:   # hazard stripes
				_box(Vector3(0.3, hgt + 0.02, float(s.th) * 2.0 + 0.02), _mat(Color(0.1, 0.1, 0.12)), Vector3(float(s.len) * (0.2 + st * 0.22), float(s.y0) + hgt / 2.0, 0), arm)
		dyn.spins.append(n)
	for b in M.balls:
		var n := Node3D.new(); map_node.add_child(n)
		_sph(float(b.r), _mat(Color(0.55, 0.82, 1.0), 0.15, 0.15), Vector3.ZERO, n)   # water-cooler bottle
		_cyl(float(b.r) * 0.35, float(b.r) * 0.35, float(b.r) * 0.6, _mat(Color(0.2, 0.4, 0.9)), Vector3(0, float(b.r) * 0.9, 0), n)
		dyn.balls.append(n)
	for pd in M.pends:
		var n := Node3D.new(); n.position = pd.pivot; map_node.add_child(n)
		_box(Vector3(0.6, 0.3, 0.6), _mat(Color(0.2, 0.2, 0.25)), pd.pivot, map_node)
		_cyl(0.05, 0.05, float(pd.len), _mat(Color(0.25, 0.25, 0.3)), Vector3(0, -float(pd.len) / 2.0, 0), n)
		var chair := Node3D.new(); chair.position = Vector3(0, -float(pd.len), 0); n.add_child(chair)
		_box(Vector3(1.3, 0.25, 1.3), _mat(Color(0.95, 0.3, 0.35)), Vector3(0, 0, 0), chair)
		_box(Vector3(1.3, 1.1, 0.22), _mat(Color(0.95, 0.3, 0.35)), Vector3(0, 0.6, -0.55), chair)
		_cyl(0.08, 0.08, 0.6, _mat(Color(0.7, 0.7, 0.75), 0.3), Vector3(0, -0.4, 0), chair)
		dyn.pends.append(n)
	for i in M.tiles.size():
		var t: Array = M.tiles[i]
		var n := Node3D.new(); n.position = t[0]; map_node.add_child(n)
		var col: Color = [BV, CY, GOLD, Color(1.0, 0.45, 0.72)][(i + int(i / 7)) % 4]
		_box(t[1], _mat(col.lightened(0.1)), Vector3.ZERO, n)                                         # desk top
		_box(Vector3(0.14, 1.2, 0.14), _mat(Color(0.3, 0.3, 0.35)), Vector3(0, -0.85, 0), n)          # leg
		_box(Vector3(0.7, 0.42, 0.06), _mat(Color(0.08, 0.08, 0.1)), Vector3(0, 0.46, -0.75), n)        # monitor
		dyn.tiles.append(n)
	for dc in M.discs:
		_cyl(float(dc[1]), float(dc[1]) * 0.85, 1.0, _mat(Color(0.95, 0.95, 0.97)), (dc[0] as Vector3) + Vector3(0, -0.5, 0), map_node)
		for ring in 3:
			_cyl(float(dc[1]) * (0.3 + ring * 0.25), float(dc[1]) * (0.3 + ring * 0.25), 0.02, _mat([BV, CY, Color(1.0, 0.45, 0.72)][ring]), (dc[0] as Vector3) + Vector3(0, 0.005 - ring * 0.001, 0), map_node)
	for g in M.goals:
		var gb: AABB = g.box
		var lab := Label3D.new(); lab.text = TEAM_NAME[g.team] + " BAY"; lab.font = font; lab.font_size = 64; lab.outline_size = 10
		lab.modulate = TEAM_COL[g.team]; lab.position = gb.get_center() + Vector3(0, 3.5, 0); lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		map_node.add_child(lab)
	for tb in sim.tubs:
		var n := Node3D.new(); n.position = tb.pos; map_node.add_child(n)
		_sph(1.3, _mat(Color(0.95, 0.75, 0.25), 0.5), Vector3.ZERO, n)
		_cyl(1.32, 1.32, 0.3, _mat(Color(0.25, 0.25, 0.3)), Vector3.ZERO, n)
		var ml := Label3D.new(); ml.text = "MAIL"; ml.font = font; ml.font_size = 70; ml.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ml.position = Vector3(0, 1.9, 0); ml.outline_size = 10; n.add_child(ml)
		dyn.tubs.append(n)
	# finish arch
	var fb: AABB = M.finish
	if fb.size != Vector3.ZERO:
		var fc := fb.get_center()
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.6, 4.2, 0.6), _mat(GOLD, 0.3, 0.3), Vector3(fc.x + sx * (fb.size.x / 2.0 - 0.3), fb.position.y + 2.1, fb.position.z), map_node)
		_box(Vector3(fb.size.x, 0.9, 0.6), _mat(BV, 0.4, 0.4), Vector3(fc.x, fb.position.y + 4.3, fb.position.z), map_node)
		var fl := Label3D.new(); fl.text = "FINISH"; fl.font = font; fl.font_size = 180; fl.outline_size = 0; fl.modulate = Color(1.4, 1.4, 1.4)
		fl.position = Vector3(fc.x, fb.position.y + 4.3, fb.position.z - 0.35); fl.rotation.y = PI
		map_node.add_child(fl)
		for k in 8:   # chequered strip on the floor
			_box(Vector3(fb.size.x / 8.0, 0.03, 0.8), _mat(Color.WHITE if k % 2 == 0 else Color(0.08, 0.08, 0.1)), Vector3(fb.position.x + (k + 0.5) * fb.size.x / 8.0, fb.position.y + 0.21, fb.position.z + 0.4), map_node)
	if M.crown != Vector3.ZERO:
		crown_node = _crown()
		crown_node.position = M.crown
		map_node.add_child(crown_node)
	# what's below: a coffee lake for the survival rounds, soft sky-blue elsewhere
	var lake := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(400, 400); lake.mesh = pm
	var surv := String(M.kind) in ["survive", "final_survive"]
	lake.material_override = _mat(Color(0.3, 0.16, 0.07) if surv else Color(0.12, 0.28, 0.6), 0.15)
	lake.position = Vector3(0, float(M.fall_y) - 2.0, 25)
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_node.add_child(lake)
	# the round's name on a big sign behind the start
	var sign := Label3D.new(); sign.text = String(M.name); sign.font = font; sign.font_size = 260; sign.outline_size = 24
	sign.modulate = GOLD; sign.position = Vector3(0, 9, -10 if not surv else -20); sign.rotation.y = PI
	map_node.add_child(sign)
	spectate = -1


## The BNB crown: a gold band with purple gems and the BNB mark, turning slowly over the roof.
func _crown() -> Node3D:
	var n := Node3D.new()
	var gold := StandardMaterial3D.new(); gold.albedo_color = Color(1.0, 0.78, 0.2); gold.metallic = 0.8; gold.roughness = 0.25
	gold.emission_enabled = true; gold.emission = Color(1.0, 0.7, 0.2); gold.emission_energy_multiplier = 0.4
	_cyl(0.55, 0.62, 0.4, gold, Vector3.ZERO, n)
	for k in 6:
		var a := TAU * k / 6.0
		_cyl(0.0, 0.16, 0.55, gold, Vector3(cos(a) * 0.55, 0.45, sin(a) * 0.55), n)
		_sph(0.1, _mat(BV, 0.2, 1.2), Vector3(cos(a) * 0.62, 0.05, sin(a) * 0.62), n)
	var mark: Texture2D = load("res://assets/brand/bnb_mark_trim.png")
	var sp := Sprite3D.new(); sp.texture = mark; sp.pixel_size = 0.6 / mark.get_height(); sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.position = Vector3(0, 1.0, 0); sp.shaded = false
	n.add_child(sp)
	var l := OmniLight3D.new(); l.light_color = GOLD; l.light_energy = 2.0; l.omni_range = 6.0
	n.add_child(l)
	return n


func _tumbler(p) -> Dictionary:
	var rig := Main.make_rig(p.C, 0)
	world.add_child(rig)
	if OS.has_feature("mobile") and p.id != me:
		for gi in rig.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tag := Label3D.new()
	tag.text = String(p.C.person.get("short", p.C.name)) if p.C.has("person") else String(p.C.name)
	tag.font = font; tag.font_size = 44 if p.id == me else 30; tag.outline_size = 8
	tag.modulate = GOLD if p.id == me else (p.C.accent as Color).lightened(0.35)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tag.no_depth_test = p.id == me
	world.add_child(tag)
	return {rig = rig, tag = tag, t = randf() * 3.0}


# ---------------------------------------------------------------- loop
func _physics_process(_dt: float) -> void:
	if sim == null or world == null: return
	if paused and net == null: return
	var inp: Dictionary = sim.bot_input(sim.players[me]) if autoplay else ({} if paused else _controls())
	if guest:
		net.send({t = "ti", i = inp})
		var got := false
		for m in inbox:
			sim.apply(m.s)
			got = true
			for e in m.e: _event(Party.unpack_event(e))
		inbox.clear()
		if not got: sim.coast()
	else:
		inputs[me] = inp
		sim.tick(inputs)
		for e in sim.events: _event(e)
		if net != null:
			outbox.append_array(sim.events)
			if sim.tick_n % 2 == 0:
				var ev := []
				for e in outbox: ev.append(Party.pack(e))
				net.broadcast({t = "ts", s = sim.snapshot(), e = ev})
				outbox.clear()
	if sim.round_i != built_round and sim.phase in ["intro", "count", "play"]: _build_round()
	if sim.phase == "over" and not results_shown and sim.phase_t > 200: _show_results()


func _net_message(pid: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"ti":
			if not guest and pid_player.has(pid) and d.get("i") is Dictionary: inputs[pid_player[pid]] = d.i
		"ts":
			if guest: inbox.append(d)


func _net_left(pid: int) -> void:
	if not pid_player.has(pid): return
	var p = sim.players[pid_player[pid]]
	p.human = -1
	inputs.erase(p.id)
	feed.push_front(["%s LEFT · A BOT TAKES OVER" % _nm(p.id), 3.0])


func _nm(id: int) -> String:
	if id < 0 or id >= sim.players.size(): return "?"
	var C: Dictionary = sim.players[id].C
	return String(C.person.get("short", C.name)) if C.has("person") else String(C.name)


func _event(e: Array) -> void:
	var kind: String = e[0]
	stats[kind] = stats.get(kind, 0) + 1
	var who: int = int(e[2]) if e.size() > 2 and (e[2] is int or e[2] is float) else -1
	match kind:
		"jump", "dive": if who == me: G.sfx("whoosh")
		"bump":
			if who >= 0 and who < rigs.size(): rigs[who].t = 0.0
			if who == me: G.sfx("hit")
		"checkpoint": if who == me: G.sfx("ok"); _banner("CHECKPOINT", CY, 1.0)
		"qual":
			if who == me: G.sfx("vs"); _banner("QUALIFIED!", Color(0.4, 1.0, 0.55), 2.5)
			else: feed.push_front(["%s QUALIFIED" % _nm(who), 2.5])
		"fall":
			if who == me: G.sfx("ko"); _banner("YOU FELL!", Color(1.0, 0.4, 0.4), 2.5)
			else: feed.push_front(["%s FELL OUT" % _nm(who), 2.5])
		"elim":
			if who == me: G.sfx("ko"); _banner("ELIMINATED", Color(1.0, 0.35, 0.35), 3.0)
		"crown": G.sfx("surge"); _banner("%s GRABS THE CROWN!" % _nm(who), GOLD, 4.0)
		"crowned": _celebrate()
		"score": G.sfx("ok"); feed.push_front(["%s SCORES!" % TEAM_NAME[clampi(who, 0, 1)], 2.0])
		"go": G.sfx("vs"); _go_t = 1.0
		"round": G.sfx("ui")


func _banner(t: String, c: Color, secs: float) -> void:
	banner = t; banner_col = c; banner_t = secs


func _celebrate() -> void:
	if world == null or confetti != null: return
	confetti = CPUParticles3D.new()
	confetti.amount = 220; confetti.lifetime = 4.0
	confetti.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; confetti.emission_box_extents = Vector3(6, 0.5, 6)
	confetti.direction = Vector3(0, -1, 0); confetti.gravity = Vector3(0, -3, 0); confetti.initial_velocity_min = 1.0; confetti.initial_velocity_max = 3.0
	confetti.angular_velocity_min = -300; confetti.angular_velocity_max = 300
	var q := QuadMesh.new(); q.size = Vector2(0.15, 0.25)
	var qm := StandardMaterial3D.new(); qm.vertex_color_use_as_albedo = true; qm.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = qm; confetti.mesh = q
	var grad := Gradient.new()
	grad.set_color(0, GOLD); grad.set_color(1, BV); grad.add_point(0.5, CY)
	confetti.color_initial_ramp = grad
	world.add_child(confetti)
	G.sfx("surge")


func _process(dt: float) -> void:
	if sim == null or world == null: return
	var a := Engine.get_physics_interpolation_fraction()
	var t: float = (sim.rtick + (a if sim.phase == "play" else 0.0)) * sim.DT
	_draw_obstacles(t)
	for i in sim.players.size(): _draw_tumbler(i, a, dt)
	_camera(a, dt)
	if crown_node != null:
		crown_node.rotation.y += dt * 1.5
		crown_node.position.y = (sim.map.crown as Vector3).y + sin(Time.get_ticks_msec() / 400.0) * 0.15
	if confetti != null and sim.winner >= 0:
		confetti.position = (sim.players[sim.winner].pos as Vector3) + Vector3(0, 7, 0)
	banner_t = maxf(0.0, banner_t - dt)
	_go_t = maxf(0.0, _go_t - dt)
	for f in feed: f[1] -= dt
	feed = feed.filter(func(f): return f[1] > 0.0).slice(0, 5)
	hud.queue_redraw()


func _draw_obstacles(t: float) -> void:
	var M: Dictionary = sim.map
	for i in mini(dyn.movers.size(), M.movers.size()): (dyn.movers[i] as Node3D).position = sim.mover_c(M.movers[i], t)
	for i in mini(dyn.pushers.size(), M.pushers.size()): (dyn.pushers[i] as Node3D).position = sim.pusher_c(M.pushers[i], t)
	for i in mini(dyn.drops.size(), M.drops.size()):
		var open: float = sim.drop_open(M.drops[i], t)
		var n: Node3D = dyn.drops[i]
		n.rotation.x = open * 1.2   # the sheet tips away
		n.position = (M.drops[i].c as Vector3) + Vector3(0, -open * 0.8, 0)
	for i in mini(dyn.belts.size(), M.belts.size()):
		var bl: Dictionary = M.belts[i]
		var bl_len: float = (bl.s as Vector3).z
		(dyn.belts[i] as Node3D).position.z = fposmod(t * (bl.belt as Vector3).z, bl_len / 12.0)
	for i in mini(dyn.spins.size(), M.spins.size()): (dyn.spins[i] as Node3D).rotation.y = -sim.spin_angle(M.spins[i], t)
	for i in mini(dyn.balls.size(), M.balls.size()):
		var n2: Node3D = dyn.balls[i]
		n2.position = sim.ball_pos(M.balls[i], t)
		n2.rotation.x = -t * 4.0
	for i in mini(dyn.pends.size(), M.pends.size()):
		var pd: Dictionary = M.pends[i]
		(dyn.pends[i] as Node3D).rotation.z = float(pd.amp) * sim.wave(pd.period, pd.phase, t)
	for i in mini(dyn.tiles.size(), sim.tiles.size()):
		var tn: Node3D = dyn.tiles[i]
		var st: int = sim.tiles[i]
		var base: Vector3 = M.tiles[i][0]
		if st < 0:
			tn.position.y = lerpf(tn.position.y, base.y - 30.0, 0.04)
			tn.visible = tn.position.y > base.y - 25.0
		elif st > 0:   # shaking (and blushing red) before it goes
			tn.position = base + Vector3(sin(t * 60.0) * 0.06, 0, cos(t * 53.0) * 0.06)
			(tn.get_child(0) as MeshInstance3D).material_override = _mat(Color(1.0, 0.35, 0.3))
		else:
			tn.position = base; tn.visible = true
	for i in mini(dyn.tubs.size(), sim.tubs.size()):
		var tb: Node3D = dyn.tubs[i]
		tb.position = tb.position.lerp(sim.tubs[i].pos, 0.5)
		tb.rotation.y += (sim.tubs[i].vel as Vector3).length() * 0.02


func _draw_tumbler(i: int, a: float, dt: float) -> void:
	var p = sim.players[i]
	var v: Dictionary = rigs[i]
	var rig = v.rig
	var tag: Label3D = v.tag
	var show: bool = p.alive and p.in_round
	if p.state == "out": show = (p.pos as Vector3).y > float(sim.map.fall_y) - 10.0
	if sim.phase == "over": show = p.id == sim.winner or p.alive
	rig.visible = show; tag.visible = show and p.state != "out"
	if not show: return
	var pos: Vector3 = (p.prev_pos as Vector3).lerp(p.pos, a)
	rig.position = pos
	rig.rotation.y = lerp_angle(rig.rotation.y, float(p.yaw), clampf(dt * 14.0, 0.0, 1.0))
	v.t = float(v.t) + dt
	var hv := Vector2((p.vel as Vector3).x, (p.vel as Vector3).z).length()
	var clip := "idle_cheerful"
	var ct := float(v.t)
	match String(p.state):
		"run": clip = "m_run" if hv > 1.0 else "idle_cheerful"
		"air": clip = "gun_jump"
		"dive": clip = "fall_forward"
		"stumble", "out": clip = "fall_fly"
		"getup": clip = "getup"
		"done": clip = Fighter.own_clip(p.C, "win", "win_cheer")
	if sim.phase == "over" and i == sim.winner: clip = Fighter.own_clip(p.C, "win", "win_cheer")
	if not ClipLib.has(clip): clip = "idle_cheerful"
	var L := Fighter._len(clip)
	var tt := fmod(ct * (hv / 5.0 if clip == "m_run" else 1.0), L)
	if clip in ["fall_forward", "fall_fly", "getup"]: tt = minf(ct, L - 0.05)
	if clip == "gun_jump": tt = clampf(0.35 - (p.vel as Vector3).y * 0.04, 0.05, L - 0.05)
	rig.set_clip(clip, tt, true, false)
	rig.apply_pose(p.C.pose.guard, true)
	# wobble: lean into the run, squash on landing, wobble while stumbling
	var lean := clampf(hv / 7.0, 0.0, 1.0) * 0.18
	var sq := float(p.landed) / 10.0 * 0.14
	rig.rotation.x = lerpf(rig.rotation.x, lean if p.state == "run" else 0.0, clampf(dt * 10.0, 0.0, 1.0))
	rig.rotation.z = sin(ct * 18.0) * 0.25 if p.state == "stumble" else lerpf(rig.rotation.z, 0.0, 0.2)
	rig.scale = Vector3(1.0 + sq * 0.6, 1.0 - sq, 1.0 + sq * 0.6)
	tag.position = pos + Vector3(0, 2.25, 0)


func _camera(a: float, dt: float) -> void:
	var follow: int = me
	var mine = sim.players[me]
	if not mine.alive or mine.state in ["out", "done"] or not mine.in_round:
		# spectate: the leader of those still going
		var best := -1
		var bz := -INF
		for p in sim.players:
			if p.alive and p.in_round and not p.state in ["out", "done"] and p.pos.z > bz: bz = p.pos.z; best = p.id
		if best >= 0: follow = best
		spectate = follow if follow != me else -1
	else:
		spectate = -1
	if sim.phase == "over" and sim.winner >= 0: follow = sim.winner
	var fp: Vector3 = (sim.players[follow].prev_pos as Vector3).lerp(sim.players[follow].pos, a)
	cam_yaw -= look.x * 0.0035
	cam_pitch = clampf(cam_pitch - look.y * 0.0025, -1.1, 0.15)
	look = Vector2.ZERO
	var kind := String(sim.map.kind)
	var dist := 7.5 if kind in ["race", "final_race"] else 10.0
	if sim.phase == "intro": dist = 14.0
	if sim.phase == "over": dist = 6.0; cam_pitch = -0.55
	var f := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var want := fp - f * dist * cos(cam_pitch) + Vector3(0, 2.2 - sin(cam_pitch) * dist, 0)
	cam.position = want if cam.position == Vector3.ZERO else cam.position.lerp(want, clampf(dt * 6.0, 0.0, 1.0))
	cam.look_at(fp + Vector3(0, 1.4, 0), Vector3.UP)


# ---------------------------------------------------------------- controls
func _touch() -> bool:
	return G.ui.touch_enabled


func _t(n: String) -> bool:
	return touch_btn.has(n) and touch_btn[n].held


func _controls() -> Dictionary:
	if G.get("comms_typing"): return {}
	var k := func(keys: Array) -> bool:
		for key in keys:
			if Input.is_physical_key_pressed(key): return true
		return false
	var mx := (1.0 if k.call([KEY_D, KEY_RIGHT]) else 0.0) - (1.0 if k.call([KEY_A, KEY_LEFT]) else 0.0)
	var mz := (1.0 if k.call([KEY_W, KEY_UP]) else 0.0) - (1.0 if k.call([KEY_S, KEY_DOWN]) else 0.0)
	var j: bool = k.call([KEY_SPACE])
	var d: bool = k.call([KEY_SHIFT])
	var g: bool = k.call([KEY_E])
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var p: int = pads[0]
		var ax := Vector2(Input.get_joy_axis(p, JOY_AXIS_LEFT_X), Input.get_joy_axis(p, JOY_AXIS_LEFT_Y))
		if ax.length() > 0.2: mx = ax.x; mz = -ax.y
		var rx := Vector2(Input.get_joy_axis(p, JOY_AXIS_RIGHT_X), Input.get_joy_axis(p, JOY_AXIS_RIGHT_Y))
		if rx.length() > 0.15: look += rx * 9.0
		j = j or Input.is_joy_button_pressed(p, JOY_BUTTON_A)
		d = d or Input.is_joy_button_pressed(p, JOY_BUTTON_X) or Input.is_joy_button_pressed(p, JOY_BUTTON_B)
		g = g or Input.get_joy_axis(p, JOY_AXIS_TRIGGER_RIGHT) > 0.5 or Input.is_joy_button_pressed(p, JOY_BUTTON_RIGHT_SHOULDER)
	if _touch():
		if touch_move.length() > 0.1: mx = touch_move.x; mz = -touch_move.y
		j = j or _t("jump"); d = d or _t("dive"); g = g or _t("grab")
	# camera-relative: forward is where the camera looks
	var f := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var r := f.cross(Vector3.UP)
	var w := f * mz + r * mx
	return {mx = snappedf(w.x, 0.01), mz = snappedf(w.z, 0.01), j = j, d = d, g = g}


func _unhandled_input(e: InputEvent) -> void:
	if sim == null: return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_P, KEY_ESCAPE]:
		if e.physical_keycode == KEY_ESCAPE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else: toggle_pause()
		return
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START: toggle_pause(); return
	if paused or _touch(): return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: look += e.relative
	if e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not results_shown and not autoplay:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _layout_touch() -> void:
	if not _touch(): return
	var s: Vector2 = G.get_viewport().get_visible_rect().size
	var r := clampf(s.y * 0.085, 38.0, 64.0)
	touch_btn = {
		jump = {c = Vector2(s.x - r * 1.6, s.y - r * 1.8), r = r * 1.15, label = "JUMP", held = false},
		dive = {c = Vector2(s.x - r * 4.0, s.y - r * 1.3), r = r * 0.85, label = "DIVE", held = false},
		grab = {c = Vector2(s.x - r * 1.7, s.y - r * 4.4), r = r * 0.8, label = "GRAB", held = false},
		pause = {c = Vector2(s.x - 50, 40), r = 26.0, label = "II", held = false},
	}


func _input(e: InputEvent) -> void:
	if not _touch() or sim == null: return
	if e is InputEventScreenTouch:
		var vs: Vector2 = G.get_viewport().get_visible_rect().size
		if e.pressed:
			var hit := ""
			for n in touch_btn:
				if e.position.distance_to(touch_btn[n].c) <= touch_btn[n].r * 1.15: hit = n
			if hit == "pause": toggle_pause(); return
			if hit != "": touches[e.index] = hit
			elif e.position.x < vs.x * 0.4 and move_id < 0: move_id = e.index; move_origin = e.position
			elif look_id < 0: look_id = e.index; look_last = e.position
		else:
			touches.erase(e.index)
			if e.index == move_id: move_id = -1; touch_move = Vector2.ZERO
			if e.index == look_id: look_id = -1
		for n in touch_btn: touch_btn[n].held = touches.values().has(n)
	elif e is InputEventScreenDrag:
		if e.index == move_id: touch_move = ((e.position - move_origin) / 70.0).limit_length(1.0)
		elif e.index == look_id:
			look += (e.position - look_last) * 1.4
			look_last = e.position


# ---------------------------------------------------------------- HUD
func _draw_hud() -> void:
	var s := hud.size
	var ink := Color(0.96, 0.97, 1.0)
	var M: Dictionary = sim.map
	var kind := String(M.kind)
	var mid := s.x / 2.0
	var shade := Color(0.03, 0.02, 0.07, 0.75)
	var playing: Array = sim.players.filter(func(p): return p.in_round)
	# top bar: round, goal counter, clock
	if sim.phase in ["count", "play", "end"]:
		hud.draw_rect(Rect2(Vector2(mid - 270, 12), Vector2(540, 64)), shade)
		hud.draw_rect(Rect2(Vector2(mid - 270, 12), Vector2(540, 4)), BV)
		hud.draw_string(small, Vector2(mid - 258, 36), "ROUND %d  ·  %s" % [sim.round_i + 1, String(M.name)], HORIZONTAL_ALIGNMENT_LEFT, 380, 18, GOLD)
		var line := ""
		match kind:
			"race": line = "QUALIFIED  %d / %d" % [sim.finished.size(), sim.target]
			"survive": line = "STANDING  %d  ·  SURVIVE TO %d" % [playing.filter(func(p): return p.state != "out").size(), sim.target]
			"team": line = "%s  %d  —  %d  %s" % [TEAM_NAME[0], sim.team_score[0], sim.team_score[1], TEAM_NAME[1]]
			"final_race": line = "FIRST TO THE CROWN WINS"
			"final_survive": line = "LAST ONE STANDING  ·  %d LEFT" % playing.filter(func(p): return p.state != "out").size()
		hud.draw_string(font, Vector2(mid - 258, 66), line, HORIZONTAL_ALIGNMENT_LEFT, 400, 24, ink)
		var left := maxf(0.0, float(M.dur) - sim.rtick * sim.DT)
		hud.draw_string(font, Vector2(mid + 120, 66), "%d:%02d" % [int(left) / 60, int(left) % 60], HORIZONTAL_ALIGNMENT_RIGHT, 140, 28, ink)
		var mine = sim.players[me]
		if kind == "team" and mine.team >= 0 and mine.in_round:
			hud.draw_string(font, Vector2(0, 104), "YOU'RE ON %s  ·  PUSH THE MAIL TUBS INTO YOUR BAY" % TEAM_NAME[mine.team], HORIZONTAL_ALIGNMENT_CENTER, s.x, 20, TEAM_COL[mine.team])
	# intro card
	if sim.phase == "intro":
		var r := Rect2(Vector2(mid - 390, s.y * 0.2), Vector2(780, 270))
		hud.draw_rect(r, Color(0.04, 0.02, 0.1, 0.9))
		hud.draw_rect(Rect2(r.position, Vector2(r.size.x, 8)), BV)
		hud.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 8), Vector2(r.size.x, 8)), GOLD)
		hud.draw_string(small, r.position + Vector2(0, 50), "ROUND %d  ·  %s" % [sim.round_i + 1, Maps.KIND_GOAL.get(kind, "")], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, GOLD)
		hud.draw_string(font, r.position + Vector2(0, 122), String(M.name), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 58, ink)
		var goal := ""
		match kind:
			"race": goal = "FIRST %d TO THE FINISH QUALIFY" % sim.target
			"survive": goal = "SURVIVE UNTIL ONLY %d ARE LEFT" % sim.target
			"team": goal = "TEAM BIT vs TEAM BYTE  ·  THE LOSING TEAM GOES HOME"
			"final_race": goal = "THE FINAL  ·  FIRST TO TOUCH THE CROWN WINS"
			"final_survive": goal = "THE FINAL  ·  LAST ONE STANDING WINS THE CROWN"
		hud.draw_string(font, r.position + Vector2(0, 172), goal, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, CY)
		hud.draw_string(small, r.position + Vector2(20, 220), String(M.sub), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 40, 20, Color(0.85, 0.87, 0.95))
		hud.draw_string(small, r.position + Vector2(0, 252), "%d TUMBLERS IN THIS ROUND" % playing.size(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, Color(0.7, 0.72, 0.85))
	if sim.phase == "count":
		hud.draw_string(font, Vector2(0, s.y * 0.47), str(ceili(sim.phase_t / 60.0)), HORIZONTAL_ALIGNMENT_CENTER, s.x, 150, GOLD)
	if _go_t > 0.0:
		hud.draw_string(font, Vector2(0, s.y * 0.47), "GO!", HORIZONTAL_ALIGNMENT_CENTER, s.x, 160, Color(0.4, 1.0, 0.55, _go_t))
	# banners and feed
	if banner_t > 0.0:
		hud.draw_string(font, Vector2(0, s.y * 0.33), banner, HORIZONTAL_ALIGNMENT_CENTER, s.x, 64, Color(banner_col, clampf(banner_t * 2.0, 0.0, 1.0)))
	var y := 112.0
	for f in feed:
		hud.draw_string(small, Vector2(s.x - 440, y), String(f[0]), HORIZONTAL_ALIGNMENT_RIGHT, 420, 20, Color(1, 1, 1, clampf(float(f[1]), 0.0, 1.0)))
		y += 24.0
	if spectate >= 0 and sim.phase == "play":
		hud.draw_string(small, Vector2(0, s.y - 60), "SPECTATING  %s" % _nm(spectate), HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color(0.85, 0.87, 0.95))
	if sim.phase == "end": hud.draw_string(font, Vector2(0, s.y * 0.22), "ROUND OVER", HORIZONTAL_ALIGNMENT_CENTER, s.x, 60, GOLD)
	if sim.phase == "standings": _draw_standings(s)
	if sim.phase == "over" and sim.winner >= 0:
		hud.draw_string(font, Vector2(0, s.y * 0.14), "CROWN WINNER", HORIZONTAL_ALIGNMENT_CENTER, s.x, 40, GOLD)
		hud.draw_string(font, Vector2(0, s.y * 0.14 + 72), _nm(sim.winner), HORIZONTAL_ALIGNMENT_CENTER, s.x, 80, ink)
	if not _touch() and sim.phase == "play":
		hud.draw_string(small, Vector2(0, s.y - 10), "WASD move  ·  mouse camera  ·  SPACE jump  ·  SHIFT dive  ·  E grab  ·  P pause", HORIZONTAL_ALIGNMENT_CENTER, s.x, 16, Color(0.85, 0.87, 0.95, 0.65))
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not paused and not autoplay:
			hud.draw_string(small, Vector2(0, s.y * 0.62), "click to steer the camera with the mouse", HORIZONTAL_ALIGNMENT_CENTER, s.x, 20, Color(1, 1, 1, 0.7))
	_draw_touch()


func _draw_standings(s: Vector2) -> void:
	var r := Rect2(Vector2(s.x / 2.0 - 370, s.y * 0.14), Vector2(740, s.y * 0.7))
	hud.draw_rect(r, Color(0.04, 0.02, 0.1, 0.9))
	hud.draw_rect(Rect2(r.position, Vector2(r.size.x, 8)), GOLD)
	var still: Array = sim.players.filter(func(p): return p.alive)
	hud.draw_string(font, r.position + Vector2(0, 54), "THROUGH TO ROUND %d" % (sim.round_i + 2), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 34, GOLD)
	for k in still.size():
		var p = still[k]
		var at := r.position + Vector2(48 + (k % 2) * 340, 104 + (k / 2) * 34)
		hud.draw_string(small, at, ("★  " if p.id == me else "✓  ") + _nm(p.id), HORIZONTAL_ALIGNMENT_LEFT, 320, 24, GOLD if p.id == me else Color(0.4, 1.0, 0.55))
	var gone: Array = sim.players.filter(func(p): return not p.alive)
	var yy := r.position.y + 112 + ceili(still.size() / 2.0) * 34 + 10
	if not gone.is_empty():
		var names := ", ".join(gone.map(func(p): return _nm(p.id)))
		hud.draw_string(small, Vector2(r.position.x + 48, yy), "OUT:  " + names, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 96, 18, Color(1.0, 0.5, 0.5, 0.85))
	if not sim.players[me].alive:
		hud.draw_string(font, Vector2(r.position.x, r.end.y - 30), "YOU'RE OUT  ·  STAY TO SEE WHO TAKES THE CROWN", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, Color(1.0, 0.55, 0.5))


func _draw_touch() -> void:
	if not _touch(): return
	if move_id >= 0:
		hud.draw_arc(move_origin, 70.0, 0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
		hud.draw_circle(move_origin + touch_move * 70.0, 28.0, Color(BV, 0.5))
	for n in touch_btn:
		var b: Dictionary = touch_btn[n]
		var col := Color(1.0, 0.42, 0.72) if n == "jump" else BV
		hud.draw_circle(b.c, b.r, Color(col, 0.5 if b.held else 0.2))
		hud.draw_arc(b.c, b.r, 0, TAU, 40, Color(col, 0.9), 3.0)
		var fs := int(b.r * (0.55 if String(b.label).length() <= 2 else 0.36))
		hud.draw_string(font, b.c + Vector2(-b.r, fs * 0.36), b.label, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, Color.WHITE)


# ---------------------------------------------------------------- pause + results
func toggle_pause() -> void:
	if results_shown or layer == null: return
	paused = not paused
	if pause_panel != null: pause_panel.queue_free(); pause_panel = null
	if not _touch(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if not paused: return
	var ui = G.ui
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.03, 0.1, 0.92); sb.border_color = BV; sb.set_border_width_all(2)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(ui.lbl("PAUSED" if net == null else "MENU", 44, font, GOLD, 8))
	if net != null: v.add_child(ui.lbl("The show goes on for everyone else.", 18, small, Color(0.8, 0.82, 0.9)))
	var resume: Button = ui.big_btn("RESUME", CY, toggle_pause)
	v.add_child(resume)
	v.add_child(ui.big_btn("QUIT TO MENU", Color(0.55, 0.62, 0.75), func(): paused = false; _quit()))
	panel.reset_size()
	panel.position = (G.get_viewport().get_visible_rect().size - panel.size) / 2.0
	pause_panel = panel
	resume.call_deferred("grab_focus")


func _quit() -> void:
	finished.emit()
	if net != null: G.lobby.leave()
	else: G.ui.show_title()


func _show_results() -> void:
	results_shown = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var ui = G.ui
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.03, 0.1, 0.9); sb.border_color = GOLD; sb.set_border_width_all(2)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var won: bool = sim.winner == me
	v.add_child(ui.lbl("YOU WON THE CROWN!" if won else "%s WINS THE CROWN" % _nm(sim.winner), 40, font, GOLD, 8))
	var rounds_txt := "  ›  ".join(sim.rounds.map(func(x): return String(Maps.LIST[x].name)))
	var rl: Label = ui.lbl(rounds_txt, 18, small, Color(0.85, 0.87, 0.95))
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD; rl.custom_minimum_size = Vector2(640, 0)
	v.add_child(rl)
	if not won:
		var n_ok := _rounds_survived()
		v.add_child(ui.lbl("You got through %d round%s." % [n_ok, "" if n_ok == 1 else "s"], 20, small, CY))
	var btns := HBoxContainer.new(); btns.alignment = BoxContainer.ALIGNMENT_CENTER; btns.add_theme_constant_override("separation", 16)
	var C: Dictionary = sim.players[me].C
	var n: int = sim.players.size()
	if net != null:
		btns.add_child(ui.big_btn("BACK TO LOBBY", CY, func(): finished.emit(); G.lobby.back_to_lobby()))
		btns.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), func(): finished.emit(); G.lobby.leave()))
	else:
		btns.add_child(ui.big_btn("PLAY AGAIN", CY, func(): finished.emit(); G.start_party("tumble", C, n - 1, false)))
		btns.add_child(ui.big_btn("MAIN MENU", Color(0.55, 0.62, 0.75), func(): finished.emit(); ui.show_title()))
	v.add_child(btns)
	panel.reset_size()
	var vs: Vector2 = G.get_viewport().get_visible_rect().size
	panel.position = Vector2((vs.x - panel.size.x) / 2.0, vs.y - panel.size.y - 40)
	(btns.get_child(0) as Control).call_deferred("grab_focus")


## Rounds this player qualified from.
func _rounds_survived() -> int:
	var mine = sim.players[me]
	if mine.alive: return sim.history.size()
	return maxi(0, sim.history.size() - 1)


# ---------------------------------------------------------------- tests
## --autotest=tumble: every map once (a few seconds of CPU play each, screenshots), then a whole show
## fast-forwarded to the crown.
func autotest(shot: Callable) -> void:
	for mid in Maps.LIST.keys():
		_force_round(String(mid))
		var ff := 240 if String(Maps.LIST[mid].kind) in ["race", "final_race"] else 900
		if mid == "mailroom": ff = 600
		for k in ff: sim.tick(_all_bots())
		for k in 30: await G.get_tree().physics_frame
		await shot.call("tumble_%s" % mid)
		print("AUTOTEST tumble map %s kind=%s t=%.1fs finished=%d out=%d tiles_gone=%d team=%s" % [mid, sim.map.kind, sim.rtick * sim.DT, sim.finished.size(), sim.out_order.size(),
			sim.tiles.filter(func(x): return x < 0).size(), sim.team_score])
	# a fresh show, fast-forwarded with peeks at the intro card, the standings and the crown
	var people: Array = []
	for p in sim.players: people.append({C = p.C, human = false, slot = -1})
	var s2 = TumbleSim.new(); s2.setup(people, 77)
	sim = s2
	_build_round()
	for k in 40: await G.get_tree().physics_frame
	await shot.call("tumble_intro")
	var guard := 0
	while sim.phase != "standings" and guard < 30000:
		sim.tick(_all_bots()); guard += 1
	for k in 20: await G.get_tree().physics_frame
	await shot.call("tumble_standings")
	while sim.phase != "over" and guard < 150000:
		sim.tick(_all_bots()); guard += 1
		for e in sim.events: _event(e)
	_build_round()
	_celebrate()
	for k in 260: await G.get_tree().physics_frame
	await shot.call("tumble_winner")
	print("AUTOTEST tumble show rounds=%s history=%s winner=%s phase=%s results=%s stats=%s" % [sim.rounds, sim.history, _nm(sim.winner) if sim.winner >= 0 else "-", sim.phase, results_shown, stats])


func _all_bots() -> Dictionary:
	var d := {}
	for p in sim.players: d[p.id] = sim.bot_input(p)
	return d


func _force_round(mid: String) -> void:
	for p in sim.players: p.alive = true
	sim.winner = -1
	sim.rounds = [mid]; sim.round_i = 0
	sim._begin_round()
	sim.phase = "play"; sim.phase_t = 0
	_build_round()


## --autotest=tumblesim: whole shows between 12 CPUs, every map on its own, determinism and the snapshot round trip.
func selftest(_main) -> void:
	var ok := true
	var people: Array = []
	var pool: Array = Data.ROSTER.duplicate()
	for k in 12: people.append({C = pool[k % pool.size()], human = false, slot = -1})
	var t0 := Time.get_ticks_msec()
	var maps_seen := {}
	var round_secs: Array = []
	for seed in [1, 2, 3, 4, 5]:
		var s = TumbleSim.new(); s.setup(people, seed)
		var guard := 0
		var last_round := -1
		while s.phase != "over" and guard < 200000:
			var d := {}
			for p in s.players: d[p.id] = s.bot_input(p)
			s.tick(d); guard += 1
			if s.phase == "end" and last_round != s.round_i:
				last_round = s.round_i
				round_secs.append(s.rtick * s.DT)
		for m in s.rounds: maps_seen[m] = true
		var q: Array = s.history.map(func(h): return "%d/%d" % [h.qualified, h.field])
		var won: String = String(s.players[s.winner].C.name) if s.winner >= 0 else "-"
		print("AUTOTEST tumblesim show seed=%d rounds=%s qualified_per_round=%s winner=%s ticks=%d" % [seed, s.rounds, q, won, guard])
		if s.phase != "over" or s.winner < 0: ok = false; print("AUTOTEST tumblesim FAIL: show %d didn't finish" % seed)
	# every map on its own with 12
	for mid in Maps.LIST.keys():
		var s = TumbleSim.new(); s.setup(people, 9)
		s.rounds = [mid]; s.round_i = 0; s._begin_round(); s.phase = "play"
		var guard2 := 0
		while s.phase == "play" and guard2 < 20000:
			var d2 := {}
			for p in s.players: d2[p.id] = s.bot_input(p)
			s.tick(d2); guard2 += 1
		maps_seen[mid] = true
		var qn: int = s.history[-1].qualified if not s.history.is_empty() else -1
		print("AUTOTEST tumblesim map %-10s kind=%-13s secs=%5.1f qualified=%d target=%d falls=%d team=%s winner=%d" % [mid, s.map.kind, guard2 / 60.0,
			qn, s.target, s.out_order.size(), s.team_score, s.winner])
		if s.phase == "play": ok = false; print("AUTOTEST tumblesim FAIL: %s never ended" % mid)
	# determinism + snapshot round trip
	var a = TumbleSim.new(); a.setup(people, 42)
	var b = TumbleSim.new(); b.setup(people, 42)
	for k in 2400:
		var da := {}
		for p in a.players: da[p.id] = a.bot_input(p)
		a.tick(da)
		var db := {}
		for p in b.players: db[p.id] = b.bot_input(p)
		b.tick(db)
	var same := JSON.stringify(a.snapshot()) == JSON.stringify(b.snapshot())
	var c = TumbleSim.new(); c.setup(people, 7)
	c.apply(JSON.parse_string(JSON.stringify(a.snapshot())))
	# compare as the wire sees it (JSON turns every number into a float)
	var wire := func(x) -> String: return JSON.stringify(JSON.parse_string(JSON.stringify(x)))
	var trip: bool = wire.call(c.snapshot()) == wire.call(a.snapshot())
	if not same or not trip: ok = false
	var avg := 0.0
	for x in round_secs: avg += x
	avg /= maxf(1.0, round_secs.size())
	print("AUTOTEST tumblesim shows=5 maps_seen=%s avg_round_s=%.1f deterministic=%s roundtrip=%s (%.1fs)" % [maps_seen.keys(), avg, same, trip, (Time.get_ticks_msec() - t0) / 1000.0])
	print("AUTOTEST tumblesim %s" % ("PASS" if ok else "FAIL"))
