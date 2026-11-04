class_name OpsGame
extends Node
## BNB Office Ops: first-person team deathmatch. Runs an OpsSim at 60 ticks/s with the player's controls,
## draws the office floor, the other soldiers (their own characters, animated), your gun, scope and HUD.

signal finished

const TEAM_COL := [Color(0.62, 0.38, 1.0), Color(0.13, 0.78, 0.92)]
const TEAM_NAME := ["TEAM BIT", "TEAM BYTE"]

var G
var sim: OpsSim
var me := 0
var world: Node3D
var cam: Camera3D
var layer: CanvasLayer
var hud: Control
var font: Font
var small: Font
var rigs: Array = []            # per soldier: {rig, gun, tag}
var view_gun: Node3D            # first-person gun
var flash: MeshInstance3D
var look := Vector2.ZERO        # mouse movement since the last tick
var sens := 0.0025
var paused := false
var killfeed: Array = []        # [text, time]
var hitmark := 0.0
var hit_head := false
var bob := 0.0
var kick := 0.0
var tracers: Array = []         # [node, time]
var results_shown := false
var autopilot := false          # autotest: a bot plays for the player
var stats := {}
var touch_move := Vector2.ZERO
var touch_look := {}
var touch_btn := {}
var touches := {}
var move_id := -1
var move_origin := Vector2.ZERO
var look_id := -1
var look_last := Vector2.ZERO
var scoreboard := false


# multiplayer: the host runs the match and streams it; guests send their controls and aim
var net: Party = null
var guest := false
var pid_of := {}            # host: guest pid -> soldier id
var inputs := {}            # host: soldier id -> latest controls
var outbox: Array = []
var inbox: Array = []
var aim := Vector2.ZERO     # guest: own yaw / pitch


func start(g, team_a: Array, team_b: Array, primary: String, skill: float) -> void:
	_begin(g, team_a, team_b, {0: 0}, {0: primary}, skill, randi())


## Online / Wi-Fi match. humans: soldier id -> player slot, loadouts: soldier id -> primary gun.
func start_net(g, team_a: Array, team_b: Array, humans: Dictionary, loadouts: Dictionary, skill: float, seed: int, my_id: int,
		party: Party, is_guest: bool, pids: Dictionary) -> void:
	net = party; guest = is_guest; pid_of = pids; me = my_id
	net.message.connect(_net_message)
	if not guest: net.left.connect(_net_left)
	_begin(g, team_a, team_b, humans, loadouts, skill, seed)
	var s: OpsSim.Soldier = sim.soldiers[me]
	aim = Vector2(s.yaw, s.pitch)


func _begin(g, team_a: Array, team_b: Array, humans: Dictionary, loadouts: Dictionary, skill: float, seed: int) -> void:
	G = g
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	sim = OpsSim.new()
	sim.bot_skill = skill
	sim.setup(team_a, team_b, humans, loadouts, seed)
	world = Node3D.new()
	G.add_child(world)
	_build_map()
	for s in sim.soldiers: rigs.append(_soldier_visual(s))
	cam = Camera3D.new()
	cam.fov = 75; cam.near = 0.05; cam.far = 200
	world.add_child(cam)
	cam.current = true
	_view_gun()
	layer = CanvasLayer.new(); layer.layer = 5
	G.add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	_layout_touch()
	if not _touch(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func stop() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if net != null:
		if net.message.is_connected(_net_message): net.message.disconnect(_net_message)
		if net.left.is_connected(_net_left): net.left.disconnect(_net_left)
	if world != null: world.queue_free()
	if layer != null: layer.queue_free()
	world = null; layer = null


# ---------------------------------------------------------------- map
func _mat(c: Color, rough := 0.8, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	if emit > 0.0: m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	return m


func _box(size: Vector3, m: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b; mi.material_override = m; mi.position = pos
	(parent if parent != null else world).add_child(mi)
	return mi


func _build_map() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.05, 0.04, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.74, 0.82); env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true; env.glow_intensity = 0.3; env.glow_hdr_threshold = 1.3
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-62), deg_to_rad(25), 0); sun.light_energy = 0.65; sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 50
	world.add_child(sun)
	_box(Vector3(66, 0.1, 46), _mat(Color(0.22, 0.2, 0.3), 0.95), Vector3(0, -0.05, 0))               # carpet
	_box(Vector3(66, 0.1, 46), _mat(Color(0.85, 0.85, 0.88), 0.9), Vector3(0, 4.05, 0))               # ceiling
	for x in range(-28, 29, 8):
		for z in range(-18, 19, 8):
			_box(Vector3(2.4, 0.05, 0.8), _mat(Color(1, 0.98, 0.94), 0.3, 0.0, 2.2), Vector3(x, 4.0, z))
			var l := OmniLight3D.new(); l.position = Vector3(x, 3.6, z); l.omni_range = 9.0; l.light_energy = 0.5
			world.add_child(l)
	var mark: Texture2D = load("res://assets/brand/bnb_mark_trim.png")
	var glass := _mat(Color(0.6, 0.75, 0.95), 0.05, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glass.albedo_color.a = 0.25
	for b in sim.boxes:
		var c: Vector3 = b.position + b.size / 2.0
		var h: float = b.size.y
		var m: Material
		if h >= 4.0 and (absf(c.x) > 30.0 or absf(c.z) > 21.0): m = _mat(Color(0.72, 0.7, 0.76), 0.9)   # outer walls
		elif h >= 3.5: m = _mat(Color(0.78, 0.78, 0.82), 0.6)                                        # pillars
		elif h >= 2.9: m = glass                                                                     # meeting rooms
		elif h >= 2.2: m = _mat(Color(0.1, 0.1, 0.13), 0.4, 0.5)                                      # server racks
		elif h >= 1.4: m = _mat(Color(0.45, 0.3, 0.62), 0.95)                                        # cubicle walls (BNB purple)
		else: m = _mat(Color(0.62, 0.48, 0.34), 0.6)                                                 # desks / tables
		_box(b.size, m, c)
		if h >= 2.2 and h < 2.9:   # rack lights
			for k in 5:
				_box(Vector3(b.size.x + 0.02, 0.03, 0.3), _mat([Color(0.2, 1, 0.4), Color(0.2, 0.7, 1)][k % 2], 0.3, 0.0, 3.0), c + Vector3(0, -0.8 + k * 0.35, 0))
		if h < 1.0 and b.size.x > 1.5:   # monitors on desks
			_box(Vector3(0.6, 0.38, 0.04), _mat(Color(0.05, 0.05, 0.07), 0.4), c + Vector3(0, 0.6, 0))
			_box(Vector3(0.55, 0.32, 0.02), _mat(TEAM_COL[int(c.x > 0)], 0.3, 0.0, 1.2), c + Vector3(0, 0.6, 0.025))
	for side in [-1.0, 1.0]:   # logos on the end walls
		var sp := Sprite3D.new(); sp.texture = mark; sp.pixel_size = 2.4 / mark.get_height(); sp.shaded = false
		sp.position = Vector3(side * 31.9, 2.4, 0); sp.rotation.y = -side * PI / 2
		sp.modulate = Color(1.3, 1.3, 1.3)
		world.add_child(sp)


# ---------------------------------------------------------------- soldiers
func _gun_mesh(kind: String, parent: Node3D, scale := 1.0) -> Node3D:
	var g := Node3D.new()
	parent.add_child(g)
	var metal := _mat(Color(0.12, 0.12, 0.14), 0.4, 0.7)
	var grip := _mat(Color(0.2, 0.18, 0.16), 0.8)
	var acc := _mat(Color(0.55, 0.32, 0.9), 0.4, 0.3)
	var L: float = {"pistol": 0.2, "smg": 0.42, "rifle": 0.72, "shotgun": 0.8, "sniper": 1.05}.get(kind, 0.6)
	_box(Vector3(0.06, 0.09, L), metal, Vector3(0, 0, -L / 2.0), g)                       # body
	_box(Vector3(0.035, 0.035, L * 0.5), metal, Vector3(0, 0.02, -L - L * 0.2), g)        # barrel
	_box(Vector3(0.05, 0.14, 0.06), grip, Vector3(0, -0.1, -0.06), g)                     # grip
	if kind != "pistol":
		_box(Vector3(0.05, 0.12, 0.05), metal, Vector3(0, -0.1, -L * 0.45), g)            # magazine
		_box(Vector3(0.05, 0.08, 0.22), grip, Vector3(0, -0.01, 0.12), g)                 # stock
		_box(Vector3(0.065, 0.02, L * 0.4), acc, Vector3(0, 0.055, -L * 0.45), g)          # rail in BNB purple
	if kind == "sniper" or kind == "rifle":
		_box(Vector3(0.05, 0.06, 0.28), metal, Vector3(0, 0.09, -L * 0.45), g)            # scope
	g.scale = Vector3.ONE * scale
	return g


func _soldier_visual(s: OpsSim.Soldier) -> Dictionary:
	var rig := Main.make_rig(s.C, 0)
	world.add_child(rig)
	var gun := _gun_mesh(s.guns[0], world, 1.6)
	var tag := Label3D.new()
	tag.text = String(s.C.person.get("short", s.C.name)) if s.C.has("person") else s.C.name
	tag.font = font; tag.font_size = 30; tag.outline_size = 8
	tag.modulate = TEAM_COL[s.team]; tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tag.no_depth_test = s.team == sim.soldiers[me].team
	world.add_child(tag)
	if s.id == me:
		rig.visible = false; gun.visible = false; tag.visible = false
	return {rig = rig, gun = gun, gun_kind = s.guns[0], tag = tag, dead_t = 0.0}


func _clip_for(s: OpsSim.Soldier, anim_t: float, dead_t: float) -> Array:
	var has := func(n: String) -> bool: return ClipLib.has(n)
	if not s.alive:
		var d := "gun_death" if has.call("gun_death") else "ko"
		return [d, minf(dead_t, Fighter._len(d) - 0.05)]
	var hv := Vector3(s.vel.x, 0, s.vel.z)
	var spd := hv.length()
	var fwd := Vector3(sin(s.yaw), 0, cos(s.yaw))
	var right := Vector3(-cos(s.yaw), 0, sin(s.yaw))
	if not s.on_floor and has.call("gun_jump"): return ["gun_jump", fmod(anim_t, Fighter._len("gun_jump"))]
	var name := ""
	if s.crouch:
		name = "gun_crouch_walk" if spd > 0.6 else "gun_crouch"
		if not has.call(name): name = "crouch_idle"
	elif spd < 0.6:
		name = "gun_idle" if has.call("gun_idle") else "idle_fight"
	else:
		var f := hv.dot(fwd); var r := hv.dot(right)
		if absf(r) > absf(f):
			name = "gun_strafe_r" if r > 0.0 else "gun_strafe_l"
			if not has.call(name): name = "strafe_right" if r > 0.0 else "strafe_left"
		elif f < 0.0:
			name = "gun_back" if has.call("gun_back") else "step_back"
		else:
			name = ("gun_run" if s.sprint else "gun_walk")
			if not has.call(name): name = "step_forward"
	return [name, fmod(anim_t * (1.3 if s.sprint else 1.0), Fighter._len(name))]


# ---------------------------------------------------------------- first-person gun
func _view_gun() -> void:
	view_gun = Node3D.new()
	cam.add_child(view_gun)
	_rebuild_view_gun()
	flash = MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(0.25, 0.25)
	flash.mesh = q
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.8, 0.4); fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash.material_override = fm
	view_gun.add_child(flash)
	flash.visible = false


func _rebuild_view_gun() -> void:
	for c in view_gun.get_children():
		if c != flash: c.queue_free()
	var s: OpsSim.Soldier = sim.soldiers[me]
	var kind: String = s.guns[s.slot]
	var g := _gun_mesh(kind, view_gun, 1.0)
	g.name = "model"
	view_gun.set_meta("kind", kind)
	# a hand under the grip, in the person's skin tone
	var sk: Array = (s.C.get("person", {}) as Dictionary).get("skin", [0.86, 0.72, 0.62])
	_box(Vector3(0.09, 0.08, 0.16), _mat(Color(sk[0], sk[1], sk[2]), 0.8), Vector3(0, -0.12, -0.03), g)
	var L: float = {"pistol": 0.2, "smg": 0.42, "rifle": 0.72, "shotgun": 0.8, "sniper": 1.05}.get(kind, 0.6)
	if flash != null: flash.position = Vector3(0, 0.02, -L * 1.25)


# ---------------------------------------------------------------- loop
var hold_ads := false   # tests: keep aiming without a mouse


func _physics_process(_dt: float) -> void:
	if sim == null or (paused and not online_match()): return
	var inp: Dictionary = sim._bot(sim.soldiers[me]) if autopilot else ({} if paused else _controls())
	look = Vector2.ZERO
	if guest:
		_guest_tick(inp)
	else:
		inputs[me] = inp
		sim.tick(inputs)
		for e in sim.events:
			stats[e[0]] = stats.get(e[0], 0) + 1
			_event(e)
		if net != null:
			outbox.append_array(sim.events)
			if sim.tick_n % 2 == 0 or sim.state == "done":
				var ev := []
				for e in outbox: ev.append(Party.pack(e))
				net.broadcast({t = "os", s = sim.snapshot(), e = ev})
				outbox.clear()
	if sim.state == "done" and not results_shown:
		results_shown = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await get_tree().create_timer(1.0).timeout
		_show_results()


func _guest_tick(inp: Dictionary) -> void:
	var s: OpsSim.Soldier = sim.soldiers[me]
	# aim locally (no waiting for the host), send where we look
	if autopilot:
		aim = Vector2(s.yaw + float(inp.get("look_x", 0.0)), s.pitch + float(inp.get("look_y", 0.0)))
	else:
		aim.x = wrapf(aim.x + float(inp.get("look_x", 0.0)), -PI, PI)
		aim.y = clampf(aim.y + float(inp.get("look_y", 0.0)), -1.35, 1.35)
	inp.erase("look_x"); inp.erase("look_y")
	inp.yaw = snappedf(aim.x, 0.0001); inp.pitch = snappedf(aim.y, 0.0001)
	net.send({t = "oi", i = inp})
	var got := false
	for m in inbox:
		var mine: Array = m.s.s[me]
		if bool(mine[7]) and not s.alive: aim = Vector2(float(mine[3]), float(mine[4]))   # respawned: face the way the spawn faces
		sim.apply(m.s, me)
		got = true
		for e in m.e:
			var ev := Party.unpack_event(e)
			stats[ev[0]] = stats.get(ev[0], 0) + 1
			if ev[0] == "shot" and ev[2] == me: aim.y = minf(1.35, aim.y + float(s.gun().recoil) * 0.35)   # our own kick
			_event(ev)
	inbox.clear()
	if not got: sim.coast()
	s.yaw = aim.x; s.pitch = aim.y


func _net_message(pid: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"oi":
			if not guest and pid_of.has(pid) and d.i is Dictionary: inputs[pid_of[pid]] = d.i
		"os":
			if guest: inbox.append(d)


## A guest dropped out: a bot takes over their soldier.
func _net_left(pid: int) -> void:
	if not pid_of.has(pid): return
	var s: OpsSim.Soldier = sim.soldiers[pid_of[pid]]
	s.human = -1
	inputs.erase(s.id)
	killfeed.push_front(["%s LEFT · A BOT TAKES OVER" % _nm(s).to_upper(), 3.0, -1])


func _unhandled_input(e: InputEvent) -> void:
	if sim == null: return
	if paused:
		if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_P, KEY_ESCAPE]: toggle_pause()
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look += e.relative
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		if e.physical_keycode == KEY_TAB: scoreboard = true
	if e is InputEventKey and not e.pressed and e.physical_keycode == KEY_TAB: scoreboard = false
	if e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _touch() and not results_shown and not paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _controls() -> Dictionary:
	var s: OpsSim.Soldier = sim.soldiers[me]
	var k := func(keys: Array) -> bool:
		for key in keys:
			if Input.is_physical_key_pressed(key): return true
		return false
	var zoom: float = (s.gun().fov / 75.0) if s.ads else 1.0   # slower look while scoped
	var lx := -look.x * sens * zoom
	var ly := -look.y * sens * zoom
	var mx := (1.0 if k.call([KEY_D]) else 0.0) - (1.0 if k.call([KEY_A]) else 0.0)
	var mz := (1.0 if k.call([KEY_W]) else 0.0) - (1.0 if k.call([KEY_S]) else 0.0)
	var fire := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var ads := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var d: int = pads[0]
		var ax := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		if ax.length() > 0.2: mx = ax.x; mz = -ax.y
		var rx := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
		if rx.length() > 0.15: lx = -rx.x * 0.05 * zoom; ly = -rx.y * 0.035 * zoom
		fire = fire or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		ads = ads or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.5
	# touch: stick to move, drag the right side to look
	if _touch():
		if touch_move.length() > 0.1: mx = touch_move.x; mz = -touch_move.y
		lx += -float(touch_look.get("x", 0.0)) * sens * 1.6 * zoom
		ly += -float(touch_look.get("y", 0.0)) * sens * 1.6 * zoom
		touch_look = {}
		fire = fire or _t("fire")
		ads = ads or _t("ads")
	ads = ads or hold_ads
	return {move_x = mx, move_z = mz, look_x = lx, look_y = ly, fire = fire, ads = ads,
		sprint = k.call([KEY_SHIFT]) or _t("sprint") or (not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_LEFT_STICK)),
		crouch = k.call([KEY_C, KEY_CTRL]) or _t("crouch") or (not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_B)),
		jump = k.call([KEY_SPACE]) or _t("jump") or (not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_A)),
		reload = k.call([KEY_R]) or _t("reload") or (not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_X)),
		swap = k.call([KEY_Q, KEY_1, KEY_2]) and not _held_swap() or _t_once("swap") or (not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_Y) and not _held_swap())}


var _swap_was := false
func _held_swap() -> bool:
	var now := Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_1) or Input.is_physical_key_pressed(KEY_2)
	var was := _swap_was
	_swap_was = now
	return was


var _once := {}
func _t_once(name: String) -> bool:
	var now := _t(name)
	var was: bool = _once.get(name, false)
	_once[name] = now
	return now and not was


func _event(e: Array) -> void:
	var kind: String = e[0]
	match kind:
		"shot":
			if e[2] == me:
				kick = 1.0; flash.visible = true
				G.sfx("hit")
			elif (e[1] as Vector3).distance_to(sim.soldiers[me].pos) < 40.0:
				G.sfx("block")
		"tracer": _tracer(e[1], e[3])
		"hit":
			if e[3] == me:
				hitmark = 0.25; hit_head = e[4] if e.size() > 4 else false
				G.sfx("heavy" if hit_head else "ok")
			if e[2] == me: G.sfx("thud")
			if e[2] != me and randf() < 0.5: _voice(e[2], "hurt")
		"kill":
			var a: OpsSim.Soldier = sim.soldiers[e[2]]
			var v: OpsSim.Soldier = sim.soldiers[e[3]]
			killfeed.push_front(["%s  %s  %s" % [_nm(a), "◎" if (e.size() > 4 and e[4]) else "▸", _nm(v)], 4.0, a.team])
			killfeed = killfeed.slice(0, 5)
			_voice(e[3], "ko")
			if e[2] == me: G.sfx("surge")
		"reload": if e[2] == me: G.sfx("grab")
		"swap": if e[2] == me: _rebuild_view_gun()
		"respawn": if e[2] == me: _rebuild_view_gun()
		"go": G.sfx("vs")
		"done": G.sfx("ko")
		"vest_break": if e[2] == me: killfeed.push_front(["YOUR VEST IS BROKEN", 2.5, -1])


func _nm(s: OpsSim.Soldier) -> String:
	return String(s.C.person.get("short", s.C.name)) if s.C.has("person") else String(s.C.name)


func _voice(who: int, kind: String) -> void:
	var s := Voices.get_sound((sim.soldiers[who] as OpsSim.Soldier).C, kind)
	if s == null: return
	var p := AudioStreamPlayer.new(); p.stream = s; p.volume_db = -8.0
	add_child(p); p.play(); p.finished.connect(p.queue_free)


func _tracer(from: Vector3, to: Vector3) -> void:
	if world == null or not is_instance_valid(world): return
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new(); c.top_radius = 0.008; c.bottom_radius = 0.008; c.height = 1.0
	mi.mesh = c
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.5, 0.55); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	var start := from + (to - from).normalized() * 0.8
	mi.position = (start + to) / 2.0
	mi.look_at_from_position(mi.position, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2)
	mi.scale = Vector3(1, start.distance_to(to), 1)
	tracers.append([mi, 0.06])


func _process(dt: float) -> void:
	if sim == null or world == null: return
	var a := Engine.get_physics_interpolation_fraction()
	for i in sim.soldiers.size():
		var s: OpsSim.Soldier = sim.soldiers[i]
		var v: Dictionary = rigs[i]
		if i == me: continue
		var rig = v.rig
		var p := s.prev_pos.lerp(s.pos, a)
		rig.position = p
		rig.rotation.y = lerp_angle(s.prev_yaw, s.yaw, a)
		v.dead_t = 0.0 if s.alive else v.dead_t + dt
		var anim: float = rig.get_meta("t", 0.0) + dt
		rig.set_meta("t", anim)
		var cl := _clip_for(s, anim, v.dead_t)
		rig.set_clip(cl[0], cl[1], true, false)
		rig.apply_pose(s.C.pose.guard, true)
		rig.visible = s.alive or v.dead_t < 4.0
		if v.gun_kind != s.guns[s.slot]:
			(v.gun as Node).queue_free()
			v.gun = _gun_mesh(s.guns[s.slot], world, 1.6); v.gun_kind = s.guns[s.slot]
		var gn: Node3D = v.gun
		gn.visible = s.alive
		if s.alive:
			var hx: Transform3D = rig.hand_xform(true)
			gn.global_transform = Transform3D(Basis(Vector3.UP, rig.rotation.y), hx.origin)
		var tag: Label3D = v.tag
		tag.visible = s.alive
		tag.position = p + Vector3(0, 2.15 * s.C.scale, 0)
		tag.text = "%s  %d" % [_nm(s), roundi(s.hp)] if s.team == sim.soldiers[me].team else _nm(s)
	_camera(a, dt)
	for t in tracers.duplicate():
		t[1] -= dt
		if t[1] <= 0.0: (t[0] as Node).queue_free(); tracers.erase(t)
	for k in killfeed: k[1] -= dt
	killfeed = killfeed.filter(func(k): return k[1] > 0.0)
	hitmark = maxf(0.0, hitmark - dt)
	hud.queue_redraw()


func _camera(a: float, dt: float) -> void:
	var s: OpsSim.Soldier = sim.soldiers[me]
	var p := s.prev_pos.lerp(s.pos, a)
	var eye := EYE_H(s)
	var spd := Vector2(s.vel.x, s.vel.z).length()
	bob += dt * spd * 1.6
	var bob_off := Vector3(sin(bob) * 0.02, absf(cos(bob)) * 0.03, 0) * clampf(spd / 6.0, 0.0, 1.0)
	cam.position = p + Vector3(0, eye, 0) + (bob_off if not s.ads else Vector3.ZERO)
	cam.rotation = Vector3(s.pitch, s.yaw + PI, 0)
	cam.rotation_order = EULER_ORDER_YXZ
	var target_fov: float = s.gun().fov if s.ads else (82.0 if s.sprint else 75.0)
	cam.fov = lerpf(cam.fov, target_fov, clampf(dt * 14.0, 0.0, 1.0))
	# the gun: hip position, or centred for aiming; recoil kick; hidden in a sniper scope
	kick = maxf(0.0, kick - dt * 9.0)
	var kind: String = s.guns[s.slot]
	var hip := Vector3(0.22, -0.2, -0.42)
	var aimp := Vector3(0.0, -0.12 if kind != "sniper" else -0.1, -0.32)
	var want := aimp if s.ads else hip
	if s.sprint: want = Vector3(0.18, -0.28, -0.38)
	if s.reload_t > 0: want += Vector3(0, -0.12, 0.05)
	view_gun.position = view_gun.position.lerp(want + Vector3(0, 0, kick * 0.06) + bob_off * 0.6, clampf(dt * 16.0, 0.0, 1.0))
	view_gun.rotation = Vector3(kick * 0.08 + (0.6 if s.reload_t > 0 else 0.0), 0.0 if s.ads else -0.04, 0.0 if s.ads else 0.03)
	view_gun.visible = s.alive and not (s.ads and kind == "sniper" and cam.fov < 30.0)
	flash.visible = flash.visible and kick > 0.6
	if not s.alive:   # death cam: look at the floor where you fell, from above
		cam.position = p + Vector3(0, 3.5, 0); cam.rotation = Vector3(-1.2, s.yaw + PI, 0)


static func EYE_H(s: OpsSim.Soldier) -> float:
	return OpsSim.EYE_CROUCH if s.crouch else OpsSim.EYE


# ---------------------------------------------------------------- HUD
func _draw_hud() -> void:
	var sz := hud.size
	var s: OpsSim.Soldier = sim.soldiers[me]
	var c := sz / 2.0
	var ink := Color(0.95, 0.96, 1.0)
	var kind: String = s.guns[s.slot]
	var g: Dictionary = s.gun()
	# sniper scope
	if s.ads and kind == "sniper" and cam.fov < 30.0:
		var r := sz.y * 0.42
		var black := Color(0, 0, 0, 1)
		hud.draw_rect(Rect2(Vector2.ZERO, Vector2(c.x - r, sz.y)), black)
		hud.draw_rect(Rect2(Vector2(c.x + r, 0), Vector2(sz.x - c.x - r, sz.y)), black)
		for k in 64:   # round mask
			var y0 := c.y - r + k * r * 2.0 / 64.0
			var half := sqrt(maxf(0.0, r * r - pow(y0 + r / 64.0 - c.y, 2.0)))
			hud.draw_rect(Rect2(Vector2(c.x - r, y0), Vector2(r - half, r * 2.0 / 64.0 + 1)), black)
			hud.draw_rect(Rect2(Vector2(c.x + half, y0), Vector2(r - half, r * 2.0 / 64.0 + 1)), black)
		hud.draw_arc(c, r, 0, TAU, 96, Color(0.1, 0.1, 0.1), 6.0)
		hud.draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), Color(0, 0, 0, 0.9), 1.5)
		hud.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), Color(0, 0, 0, 0.9), 1.5)
		hud.draw_circle(c, 2.0, Color(1, 0.2, 0.2))
	elif s.alive:
		# crosshair: the gap shows how steady the aim is
		var spread: float = (g.ads_spread if s.ads else g.spread) + s.recoil
		var gap := 6.0 + spread * 700.0 * (0.5 if s.ads else 1.0)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			hud.draw_line(c + d * gap, c + d * (gap + 9.0), Color(1, 1, 1, 0.9), 2.0)
		hud.draw_circle(c, 1.5, Color(1, 1, 1, 0.9))
	if hitmark > 0.0:
		var hc := Color(1.0, 0.3, 0.3) if hit_head else Color(1, 1, 1)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			hud.draw_line(c + d * 7.0, c + d * 15.0, hc, 2.5)
	# damage direction
	if s.hurt_t > 0:
		var rel := s.hurt_dir.rotated(Vector3.UP, -s.yaw)
		var ang := atan2(rel.x, rel.z)
		hud.draw_arc(c, 120.0, -PI / 2 - ang - 0.35, -PI / 2 - ang + 0.35, 16, Color(1, 0.2, 0.2, s.hurt_t / 40.0), 8.0)
	# health + vest
	var hb := Rect2(Vector2(30, sz.y - 70), Vector2(260, 16))
	hud.draw_rect(hb, Color(0, 0, 0, 0.5))
	hud.draw_rect(Rect2(hb.position, Vector2(hb.size.x * clampf(s.hp / 100.0, 0.0, 1.0), hb.size.y)), Color(0.35, 0.9, 0.45) if s.hp > 35 else Color(1, 0.3, 0.3))
	var ab := Rect2(Vector2(30, sz.y - 96), Vector2(260, 10))
	hud.draw_rect(ab, Color(0, 0, 0, 0.5))
	hud.draw_rect(Rect2(ab.position, Vector2(ab.size.x * clampf(s.armor / maxf(1.0, s.max_armor), 0.0, 1.0), ab.size.y)), Color(0.3, 0.65, 1.0))
	hud.draw_string(small, Vector2(30, sz.y - 102), "VEST %d / %d" % [roundi(s.armor), roundi(s.max_armor)], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
	hud.draw_string(font, Vector2(30, sz.y - 28), "%d" % maxi(0, roundi(s.hp)), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	# ammo + gun
	# (on phones the fire button lives bottom-right, so the ammo goes above the health bar)
	var ammo_at := Vector2(sz.x - 330, sz.y - 30) if not _touch() else Vector2(300, sz.y - 28)
	hud.draw_string(font, ammo_at, "%d / %d" % [s.mag[s.slot], s.reserve[s.slot]], HORIZONTAL_ALIGNMENT_RIGHT if not _touch() else HORIZONTAL_ALIGNMENT_LEFT, 300, 40 if not _touch() else 30, ink)
	hud.draw_string(small, ammo_at + Vector2(0, -48 if not _touch() else -100), String(g.name) + ("   RELOADING…" if s.reload_t > 0 else ""), HORIZONTAL_ALIGNMENT_RIGHT if not _touch() else HORIZONTAL_ALIGNMENT_LEFT, 300, 20, Color(0.8, 0.82, 0.9))
	# score + time
	var mid := sz.x / 2.0
	hud.draw_rect(Rect2(Vector2(mid - 170, 14), Vector2(340, 50)), Color(0, 0, 0, 0.5))
	hud.draw_string(font, Vector2(mid - 165, 52), "%d" % sim.score[0], HORIZONTAL_ALIGNMENT_LEFT, 80, 34, TEAM_COL[0])
	hud.draw_string(font, Vector2(mid + 85, 52), "%d" % sim.score[1], HORIZONTAL_ALIGNMENT_RIGHT, 80, 34, TEAM_COL[1])
	var left := maxf(0.0, sim.time_limit - sim.time)
	hud.draw_string(font, Vector2(mid - 80, 46), "%d:%02d" % [int(left) / 60, int(left) % 60], HORIZONTAL_ALIGNMENT_CENTER, 160, 26, ink)
	hud.draw_string(small, Vector2(mid - 80, 78), "FIRST TO %d" % sim.goal, HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color(0.75, 0.78, 0.88))
	if sim.state == "warmup":
		hud.draw_string(font, Vector2(0, sz.y * 0.32), "GET READY  %d" % ceili(sim.warm / 60.0), HORIZONTAL_ALIGNMENT_CENTER, sz.x, 54, ink)
	# kill feed
	var y := 110.0
	for k in killfeed:
		var col: Color = TEAM_COL[k[2]] if k[2] >= 0 else Color(1, 0.5, 0.4)
		hud.draw_string(small, Vector2(sz.x - 440, y), k[0], HORIZONTAL_ALIGNMENT_RIGHT, 420, 22, Color(col, clampf(k[1], 0.0, 1.0)))
		y += 26.0
	# dead
	if not s.alive and sim.state != "done":
		hud.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.3, 0, 0, 0.25))
		hud.draw_string(font, Vector2(0, sz.y * 0.4), "YOU WERE TAKEN OUT", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 46, ink)
		hud.draw_string(small, Vector2(0, sz.y * 0.4 + 40), "Back in %d" % ceili(s.respawn / 60.0), HORIZONTAL_ALIGNMENT_CENTER, sz.x, 26, ink)
	if scoreboard: _draw_scoreboard(Rect2(sz * 0.2, sz * 0.6))
	if not _touch() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not results_shown:
		hud.draw_string(font, Vector2(0, sz.y * 0.6), "CLICK TO PLAY   ·   ESC frees the mouse", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 26, Color(1, 1, 1, 0.85))
	if not _touch():
		hud.draw_string(small, Vector2(0, sz.y - 8), "WASD move · MOUSE aim · LMB fire · RMB aim / scope · SHIFT sprint · C crouch · SPACE jump · R reload · Q swap · TAB scores", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 15, Color(0.8, 0.82, 0.9, 0.6))
	_draw_touch()


func _draw_scoreboard(r: Rect2) -> void:
	hud.draw_rect(r, Color(0.03, 0.02, 0.06, 0.88))
	for t in 2:
		var x := r.position.x + 20.0 + t * r.size.x / 2.0
		hud.draw_string(font, Vector2(x, r.position.y + 40), "%s   %d" % [TEAM_NAME[t], sim.score[t]], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, TEAM_COL[t])
		var y := r.position.y + 76.0
		var team := sim.soldiers.filter(func(o): return o.team == t)
		team.sort_custom(func(a, b): return a.kills > b.kills)
		for o in team:
			hud.draw_string(small, Vector2(x, y), "%s%s" % [_nm(o), "  (YOU)" if o.id == me else ""], HORIZONTAL_ALIGNMENT_LEFT, 220, 22, Color.WHITE)
			hud.draw_string(small, Vector2(x + 230, y), "%d / %d" % [o.kills, o.deaths], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.8, 0.85, 0.95))
			y += 28.0


# ---------------------------------------------------------------- touch
func _touch() -> bool:
	return G.ui.touch_enabled


func _t(name: String) -> bool:
	return touch_btn.has(name) and touch_btn[name].held


func _layout_touch() -> void:
	if not _touch(): return
	var s: Vector2 = G.get_viewport().get_visible_rect().size
	var r := clampf(s.y * 0.085, 38.0, 66.0)
	touch_btn = {
		fire = {c = Vector2(s.x - r * 1.7, s.y - r * 2.0), r = r * 1.25, label = "FIRE", held = false},
		ads = {c = Vector2(s.x - r * 4.2, s.y - r * 1.4), r = r * 0.85, label = "AIM", held = false},
		jump = {c = Vector2(s.x - r * 1.6, s.y - r * 4.6), r = r * 0.75, label = "JUMP", held = false},
		crouch = {c = Vector2(s.x - r * 4.0, s.y - r * 3.6), r = r * 0.7, label = "DUCK", held = false},
		reload = {c = Vector2(s.x - r * 6.3, s.y - r * 1.3), r = r * 0.7, label = "R", held = false},
		swap = {c = Vector2(s.x - r * 6.4, s.y - r * 3.2), r = r * 0.7, label = "SWAP", held = false},
		sprint = {c = Vector2(r * 1.4, s.y - r * 4.8), r = r * 0.7, label = "RUN", held = false},
		pause = {c = Vector2(s.x / 2 - 210, 40), r = 26.0, label = "II", held = false},
	}


func _input(e: InputEvent) -> void:
	if not _touch() or sim == null: return
	if e is InputEventScreenTouch:
		var vs: Vector2 = G.get_viewport().get_visible_rect().size
		if e.pressed:
			var hit := ""
			for n in touch_btn:
				if e.position.distance_to(touch_btn[n].c) <= touch_btn[n].r * 1.15: hit = n
			if hit != "": touches[e.index] = hit
			elif e.position.x < vs.x * 0.4 and move_id < 0: move_id = e.index; move_origin = e.position
			elif look_id < 0: look_id = e.index; look_last = e.position
		else:
			touches.erase(e.index)
			if e.index == move_id: move_id = -1; touch_move = Vector2.ZERO
			if e.index == look_id: look_id = -1
		for n in touch_btn: touch_btn[n].held = touches.values().has(n)
	elif e is InputEventScreenDrag:
		if e.index == move_id:
			touch_move = ((e.position - move_origin) / 70.0).limit_length(1.0)
		elif e.index == look_id:
			var d: Vector2 = e.position - look_last
			look_last = e.position
			touch_look = {x = float(touch_look.get("x", 0.0)) + d.x, y = float(touch_look.get("y", 0.0)) + d.y}
		elif touches.has(e.index) and touches[e.index] == "fire":
			# drag the fire button to aim while shooting
			touch_look = {x = float(touch_look.get("x", 0.0)) + e.relative.x, y = float(touch_look.get("y", 0.0)) + e.relative.y}


func _draw_touch() -> void:
	if not _touch(): return
	if move_id >= 0:
		hud.draw_arc(move_origin, 70.0, 0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
		hud.draw_circle(move_origin + touch_move * 70.0, 28.0, Color(0.62, 0.38, 1.0, 0.5))
	for n in touch_btn:
		var b: Dictionary = touch_btn[n]
		var col := Color(1.0, 0.35, 0.35) if n == "fire" else Color(0.62, 0.38, 1.0)
		hud.draw_circle(b.c, b.r, Color(col, 0.5 if b.held else 0.18))
		hud.draw_arc(b.c, b.r, 0, TAU, 40, Color(col, 0.9), 3.0)
		var fs := int(b.r * (0.55 if String(b.label).length() <= 2 else 0.36))
		hud.draw_string(font, b.c + Vector2(-b.r, fs * 0.36), b.label, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, Color.WHITE)


# ---------------------------------------------------------------- results
func _show_results() -> void:
	var ui = G.ui
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.03, 0.1, 0.92); sb.border_color = Color(0.58, 0.3, 0.85); sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var mine: int = (sim.soldiers[me] as OpsSim.Soldier).team
	var win := 0 if sim.score[0] > sim.score[1] else (1 if sim.score[1] > sim.score[0] else -1)
	v.add_child(ui.lbl("VICTORY" if win == mine else ("DRAW" if win < 0 else "DEFEAT"), 52, font, Color(1.0, 0.8, 0.3) if win == mine else Color(0.85, 0.85, 0.95), 10))
	v.add_child(ui.lbl("%s %d  —  %d %s" % [TEAM_NAME[0], sim.score[0], sim.score[1], TEAM_NAME[1]], 24, font, Color.WHITE))
	for t in 2:
		var team := sim.soldiers.filter(func(o): return o.team == t)
		team.sort_custom(func(a, b): return a.kills > b.kills)
		for o in team:
			v.add_child(ui.lbl("%s%s    %d kills  ·  %d deaths" % [_nm(o), " (YOU)" if o.id == me else "", o.kills, o.deaths], 20, small, TEAM_COL[t]))
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	var C: Dictionary = (sim.soldiers[me] as OpsSim.Soldier).C
	if net != null:
		btns.add_child(ui.big_btn("BACK TO LOBBY", Color(0.13, 0.78, 0.92), func(): finished.emit(); G.lobby.back_to_lobby()))
		btns.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), func(): finished.emit(); G.lobby.leave()))
	else:
		btns.add_child(ui.big_btn("PLAY AGAIN", Color(0.13, 0.78, 0.92), func(): finished.emit(); ui.show_ops_setup(C)))
		btns.add_child(ui.big_btn("MAIN MENU", Color(0.55, 0.62, 0.75), func(): finished.emit(); ui.show_title()))
	v.add_child(btns)
	panel.reset_size()
	panel.position = (G.get_viewport().get_visible_rect().size - panel.size) / 2.0


# ---------------------------------------------------------------- pause (P / Esc, or the II button on phones)
var pause_panel: Control = null


func toggle_pause() -> void:
	if results_shown or layer == null: return
	paused = not paused
	if pause_panel != null: pause_panel.queue_free(); pause_panel = null
	if not _touch(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if not paused: return
	var ui = G.ui
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.03, 0.1, 0.92); sb.border_color = Color(0.58, 0.3, 0.85); sb.set_border_width_all(2)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(ui.lbl("PAUSED" if not online_match() else "MENU", 44, font, Color(1.0, 0.8, 0.3), 8))
	if online_match(): v.add_child(ui.lbl("The match keeps going for everyone else.", 18, small, Color(0.8, 0.82, 0.9)))
	var resume: Button = ui.big_btn("RESUME", Color(0.13, 0.78, 0.92), toggle_pause)
	v.add_child(resume)
	v.add_child(ui.big_btn("QUIT TO MENU", Color(0.55, 0.62, 0.75), func(): paused = false; quit_match()))
	panel.reset_size()
	panel.position = (G.get_viewport().get_visible_rect().size - panel.size) / 2.0
	pause_panel = panel
	resume.call_deferred("grab_focus")


func online_match() -> bool:
	return net != null


func quit_match() -> void:
	finished.emit()
	if net != null: G.lobby.leave()
	else: G.ui.show_title()
