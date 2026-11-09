class_name CarromGame
extends Node
## BNB Carrom: a carrom board on the boardroom table, players seated round it. Place the striker on your baseline,
## aim, pull back for power and flick. Solo vs CPU, pass & play, or online / Wi-Fi (the host runs CarromSim and
## streams it; the guest whose turn it is sends their shot).

signal finished

const CarromSim = preload("res://scripts/carrom/carrom_sim.gd")
const S := 0.01                 # board centimetres -> metres
const TOP := 0.78               # height of the playfield
const TEAM_COL := [Color(0.96, 0.92, 0.8), Color(0.16, 0.14, 0.16)]
const TEAM_INK := [Color(1.0, 0.95, 0.82), Color(0.62, 0.66, 0.78)]
const SIDE_COL := [Color(0.62, 0.38, 1.0), Color(0.13, 0.78, 0.92), Color(1.0, 0.75, 0.3), Color(0.95, 0.4, 0.55)]

var G
var sim
var world: Node3D
var env: Environment
var cam: Camera3D
var layer: CanvasLayer
var hud: Control
var font: Font
var small: Font
var discs: Array = []           # 20 nodes (19 coins + striker)
var disp: Array = []            # displayed positions (guests smooth toward the sim)
var sink: Array = []            # pocketed: time since it dropped
var rigs: Array = []            # per player: character on a chair at their side
var tags: Array = []            # per player: name over their chair
var react: Array = []           # per player: [clip, time left]
var guide: MeshInstance3D
var guide_mesh: ImmediateMesh
var my_slot := 0
var local_all := false
var need_release := false   # pass & play: wait for the key / click that closed the hand-off to be let go
var toast := ""
var toast_t := 0.0
var results_shown := false
var cam_angle := 0.0
var autoplay := false
var stats := {}
var paused := false
var handoff := false            # pass & play: hide the board until the next player is ready
# aiming (this device's turn)
var aim_u := 0.0
var aim_ang := 0.0
var power := 0.0
var charging := false
var power_dir := 1.0
var drag_mode := ""             # touch: "striker" / "sling"
var drag_from := Vector2.ZERO
var drag_id := -1
var _auto_t := 0.0
var _auto_shot: Array = []
var _aim_sent := 0.0
var _click_t := 0.0
var _frame := 0
# online
var net: Party = null
var guest := false
var pid_slot := {}
var last_rev := -1


## people: [{C, human, slot}] in seat order.
func start(g, people: Array, seed: int, slot := 0, pass_play := false) -> void:
	G = g
	my_slot = slot; local_all = pass_play
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	sim = CarromSim.new()
	sim.setup(people, seed)
	world = Node3D.new()
	G.add_child(world)
	_build_world()
	layer = CanvasLayer.new(); layer.layer = 5
	G.add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	cam_angle = _side_angle(_view_side())
	_reset_aim()


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


# ---------------------------------------------------------------- world
func _mat(c: Color, rough := 0.6, emit := 0.0, metal := 0.0) -> StandardMaterial3D:
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


static func W(p: Vector2, y := TOP) -> Vector3:
	return Vector3(p.x * S, y, p.y * S)


func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.05, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.55, 0.7); env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = 1.0
	env.glow_enabled = true; env.glow_intensity = 0.18; env.glow_hdr_threshold = 1.3
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-62), deg_to_rad(35), 0); key.light_energy = 0.25; key.light_color = Color(1.0, 0.9, 0.8)
	key.shadow_enabled = true; key.directional_shadow_max_distance = 6.0
	world.add_child(key)
	# the pendant lamp over the board: warm pool of light
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 2.3, 0); lamp.rotation.x = -PI / 2
	lamp.spot_range = 3.2; lamp.spot_angle = 40.0; lamp.light_energy = 1.15; lamp.spot_attenuation = 0.6; lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.shadow_enabled = true
	world.add_child(lamp)
	var shade := MeshInstance3D.new(); var sc := CylinderMesh.new(); sc.top_radius = 0.08; sc.bottom_radius = 0.28; sc.height = 0.22
	shade.mesh = sc; shade.material_override = _mat(Color(0.18, 0.12, 0.3), 0.5); shade.position = Vector3(0, 2.35, 0)
	world.add_child(shade)
	_box(Vector3(0.012, 0.8, 0.012), _mat(Color(0.1, 0.1, 0.1)), Vector3(0, 2.85, 0))
	var bulb := MeshInstance3D.new(); var bs := SphereMesh.new(); bs.radius = 0.06; bs.height = 0.12
	bulb.mesh = bs; bulb.material_override = _mat(Color(1, 0.9, 0.7), 0.3, 3.0); bulb.position = Vector3(0, 2.26, 0)
	world.add_child(bulb)
	var fill := OmniLight3D.new(); fill.position = Vector3(0, 1.6, 0); fill.omni_range = 3.5; fill.light_energy = 0.15; fill.light_color = Color(0.8, 0.75, 1.0)
	world.add_child(fill)
	# room: floor, a round rug, walls with the city through the glass, the BNB mark
	_box(Vector3(14, 0.05, 14), _mat(Color(0.2, 0.14, 0.12), 0.9), Vector3(0, -0.025, 0))
	var rug := MeshInstance3D.new(); var rc := CylinderMesh.new(); rc.top_radius = 1.9; rc.bottom_radius = 1.9; rc.height = 0.01
	rug.mesh = rc; rug.material_override = _mat(Color(0.42, 0.16, 0.2), 0.95); rug.position.y = 0.006
	world.add_child(rug)
	var rug2 := MeshInstance3D.new(); var rc2 := TorusMesh.new(); rc2.inner_radius = 1.7; rc2.outer_radius = 1.78
	rug2.mesh = rc2; rug2.material_override = _mat(Color(0.85, 0.65, 0.3), 0.9); rug2.position.y = 0.012; rug2.scale = Vector3(1, 0.05, 1)
	world.add_child(rug2)
	var wall := _mat(Color(0.26, 0.2, 0.28), 0.9)
	for k in 4:
		var a := k * PI / 2.0
		var wm := _box(Vector3(10, 3.2, 0.1), wall, Vector3(sin(a), 0, cos(a)) * 5.0 + Vector3(0, 1.6, 0))
		wm.rotation.y = a
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	for k in 18:
		_box(Vector3(rng.randf_range(0.3, 0.7), rng.randf_range(0.2, 0.4), 0.02), _mat([Color(1, 0.8, 0.45), Color(0.4, 0.8, 1.0), Color(0.75, 0.5, 1.0)][k % 3], 0.5, 1.6),
			Vector3(rng.randf_range(-4, 4), rng.randf_range(1.0, 2.8), -4.93))
	var mark: Texture2D = load("res://assets/brand/bnb_mark_trim.png")
	var sp := Sprite3D.new(); sp.texture = mark; sp.pixel_size = 0.9 / mark.get_height(); sp.shaded = false
	sp.position = Vector3(0, 2.0, 4.93); sp.rotation.y = PI; sp.modulate = Color(1.2, 1.2, 1.2)
	world.add_child(sp)
	# table
	var tw := _mat(Color(0.3, 0.17, 0.09), 0.45)
	_box(Vector3(1.25, 0.05, 1.25), tw, Vector3(0, 0.695, 0))
	for lx in [-0.55, 0.55]:
		for lz in [-0.55, 0.55]:
			_box(Vector3(0.06, 0.68, 0.06), tw, Vector3(lx, 0.34, lz))
	# the board: base, playfield (procedural markings), frame with a lighter inner edge, pocket nets
	_box(Vector3(0.9, 0.03, 0.9), _mat(Color(0.2, 0.1, 0.05), 0.5), Vector3(0, TOP - 0.016, 0))
	var pf := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(0.74, 0.74)
	pf.mesh = pm
	var bm := ShaderMaterial.new(); bm.shader = load("res://shaders/carrom_board.gdshader")
	pf.material_override = bm; pf.position = Vector3(0, TOP, 0)
	world.add_child(pf)
	var frame := _mat(Color(0.22, 0.1, 0.04), 0.35)
	var edge := _mat(Color(0.55, 0.32, 0.14), 0.4)
	for k in 4:
		var holder := Node3D.new(); holder.rotation.y = k * PI / 2.0
		world.add_child(holder)
		_box(Vector3(0.88, 0.035, 0.07), frame, Vector3(0, TOP + 0.006, 0.405), holder)
		_box(Vector3(0.74, 0.012, 0.006), edge, Vector3(0, TOP + 0.017, 0.372), holder)
	for pk in CarromSim.pockets():
		var net_m := MeshInstance3D.new(); var ns := SphereMesh.new(); ns.radius = 0.03; ns.height = 0.05
		net_m.mesh = ns; net_m.material_override = _mat(Color(0.05, 0.04, 0.03), 0.9)
		net_m.position = W(pk, TOP - 0.03)
		world.add_child(net_m)
	# coins and striker
	for i in 20:
		discs.append(_disc(i)); disp.append(sim.pos[i]); sink.append(-1.0)
	guide_mesh = ImmediateMesh.new()
	guide = MeshInstance3D.new(); guide.mesh = guide_mesh
	var gm := StandardMaterial3D.new(); gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.vertex_color_use_as_albedo = true; gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	guide.material_override = gm
	guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(guide)
	# players on chairs round the table
	for pi in sim.players.size():
		var p = sim.players[pi]
		var dir: Vector2 = (CarromSim.side_axes(p.side)[0] as Vector2).normalized()
		var seat := W(dir * 72.0, 0.0)
		var ang := atan2(-dir.x, -dir.y)
		_chair(seat, ang)
		var rig := Main.make_rig(p.C, 0)
		world.add_child(rig)
		if OS.has_feature("mobile"):   # phones: the seated players cast no shadows
			for gi in rig.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.position = seat + Vector3(0, 0.05, 0)
		rig.rotation.y = ang
		rigs.append(rig); react.append(["", 0.0])
		var tag := Label3D.new()
		tag.text = _nm(p); tag.font = font; tag.font_size = 48; tag.outline_size = 10
		tag.modulate = SIDE_COL[p.side]; tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.0011; tag.position = seat + Vector3(0, 1.5, 0)
		world.add_child(tag)
		tags.append(tag)
	cam = Camera3D.new(); cam.fov = 50; cam.near = 0.02; cam.far = 40
	cam.environment = env   # the camera's own environment wins over any other in the scene
	world.add_child(cam); cam.current = true


func _disc(i: int) -> Node3D:
	var n := Node3D.new()
	world.add_child(n)
	var k: int = sim.kind[i]
	var r: float = CarromSim.radius(i) * S
	var h := 0.008 if i != CarromSim.STRIKER else 0.009
	var col: Color = [Color(0.95, 0.9, 0.76), Color(0.12, 0.1, 0.11), Color(0.82, 0.07, 0.1), Color(0.93, 0.93, 0.97)][k]
	var body := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = r; cy.bottom_radius = r; cy.height = h; cy.radial_segments = 28
	body.mesh = cy; body.material_override = _mat(col, 0.28 if k != 1 else 0.35); body.position.y = h / 2.0
	n.add_child(body)
	# engraved ring on top
	var ring := MeshInstance3D.new(); var tr := TorusMesh.new(); tr.inner_radius = r * 0.55; tr.outer_radius = r * 0.66; tr.rings = 24; tr.ring_segments = 6
	var rc: Color = [Color(0.7, 0.6, 0.42), Color(0.35, 0.32, 0.34), Color(1.0, 0.75, 0.3), Color(0.55, 0.32, 0.9)][k]
	ring.mesh = tr; ring.material_override = _mat(rc, 0.4); ring.position.y = h; ring.scale = Vector3(1, 0.15, 1)
	n.add_child(ring)
	if i == CarromSim.STRIKER:   # the BNB striker: purple ring and a cyan dot
		var dot := MeshInstance3D.new(); var dc := CylinderMesh.new(); dc.top_radius = r * 0.22; dc.bottom_radius = r * 0.22; dc.height = 0.001
		dot.mesh = dc; dot.material_override = _mat(Color(0.13, 0.78, 0.92), 0.3, 0.6); dot.position.y = h + 0.0006
		n.add_child(dot)
	n.position = W(sim.pos[i])
	return n


func _chair(at: Vector3, ang: float) -> void:
	var ps: PackedScene = load("res://assets/kenney/furniture/chairDesk.glb")
	if ps == null: return
	var holder := Node3D.new(); holder.position = at; holder.rotation.y = ang
	world.add_child(holder)
	var model: Node3D = ps.instantiate()
	holder.add_child(model)
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first: return
	var k := Vector3(0.8 / box.size.x, 1.0 / maxf(box.size.y, 0.01), 0.8 / maxf(box.size.z, 0.01))
	model.scale = k
	model.position = -Vector3(box.get_center().x * k.x, box.position.y * k.y, box.get_center().z * k.z)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null: continue
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s)
			if src is BaseMaterial3D:
				var m: BaseMaterial3D = src.duplicate()
				var c: Color = m.albedo_color
				m.albedo_color = Color.from_hsv(c.h, minf(1.0, c.s * 1.25), c.v * 0.6, c.a)
				(mi as MeshInstance3D).set_surface_override_material(s, m)


# ---------------------------------------------------------------- loop
func _process(dt: float) -> void:
	if sim == null or world == null: return
	_frame += 1
	if not guest and not paused:
		sim.update(dt)
		_drain()
	_control(dt)
	_animate(dt)
	toast_t = maxf(0.0, toast_t - dt)
	_click_t = maxf(0.0, _click_t - dt)
	hud.queue_redraw()


## Host / local: read the sim's events, show them, and stream the state to guests (every other frame while rolling).
func _drain() -> void:
	var ev: Array = sim.events.duplicate()
	sim.events.clear()
	for e in ev: _event(e)
	# while someone aims, the striker / aim line only needs ~10 updates a second
	var aiming_only: bool = ev.is_empty() and sim.phase == "aim" and _frame % 6 != 0
	if net != null and not aiming_only and (sim.rev != last_rev or not ev.is_empty() or (sim.phase == "roll" and _frame % 2 == 0)):
		last_rev = sim.rev
		var pe := []
		for e in ev: pe.append(Party.pack(e))
		net.broadcast({t = "cs", s = sim.snapshot(), e = pe})


func _net_message(pid: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"cs":
			if not guest: return
			sim.apply(d.s)
			for e in d.e: _event(Party.unpack_event(e))
		"ci":
			if guest or not pid_slot.has(pid): return
			var p = sim.cur()
			if not p.human or p.slot != int(pid_slot[pid]) or sim.phase != "aim": return
			if String(d.a) == "shoot": sim.shoot(float(d.u), float(d.g), float(d.w))
			elif String(d.a) == "aim": sim.set_aim(float(d.u), float(d.g), float(d.w))


func _net_left(pid: int) -> void:
	if not pid_slot.has(pid): return
	for p in sim.players:
		if p.slot == int(pid_slot[pid]):
			p.human = false
			_toast("%s LEFT · CPU PLAYS ON" % _nm(p))


## Is it this device's shot?
func _my_turn() -> bool:
	var p = sim.cur()
	if not p.human or sim.phase != "aim": return false
	return local_all or p.slot == my_slot


func _send_aim(force := false) -> void:
	if guest:
		_aim_sent -= get_process_delta_time()
		if force or _aim_sent <= 0.0:
			_aim_sent = 0.1
			net.send({t = "ci", a = "aim", u = snappedf(aim_u, 0.01), g = snappedf(aim_ang, 0.001), w = snappedf(power, 0.01)})
		sim.aim = [aim_u, aim_ang, power]   # show it locally straight away
		sim.pos[CarromSim.STRIKER] = CarromSim.base_point(sim.cur().side, aim_u)
	else:
		sim.set_aim(aim_u, aim_ang, power)


func _shoot() -> void:
	if not _my_turn(): return
	charging = false
	var pw := clampf(power, 0.05, 1.0)
	if guest: net.send({t = "ci", a = "shoot", u = snappedf(aim_u, 0.01), g = snappedf(aim_ang, 0.001), w = snappedf(pw, 0.01)})
	else: sim.shoot(aim_u, aim_ang, pw)
	power = 0.0


func _reset_aim() -> void:
	var p = sim.cur()
	aim_u = sim.free_u(p.side, 0.0)
	aim_ang = CarromSim._fwd_angle(p.side)
	power = 0.0; charging = false; drag_mode = ""
	_auto_t = 0.0; _auto_shot = []


func _control(dt: float) -> void:
	if paused or handoff or results_shown or not _my_turn(): return
	if autoplay:
		_auto_t += dt
		if _auto_shot.is_empty() and _auto_t > 0.3:
			_auto_shot = sim.cpu_shot()
			aim_u = _auto_shot[0]; aim_ang = _auto_shot[1]; power = 0.0
			_send_aim(true)
		elif not _auto_shot.is_empty():
			power = clampf((_auto_t - 0.3) / 0.9, 0.0, 1.0) * float(_auto_shot[2])
			_send_aim()
			if _auto_t > 1.4: power = float(_auto_shot[2]); _shoot()
		return
	var changed := false
	var k := func(keys: Array) -> bool:
		for key in keys:
			if Input.is_physical_key_pressed(key): return true
		return false
	var mv := (1.0 if k.call([KEY_D]) else 0.0) - (1.0 if k.call([KEY_A]) else 0.0)
	var rot := (1.0 if k.call([KEY_RIGHT, KEY_E]) else 0.0) - (1.0 if k.call([KEY_LEFT, KEY_Q]) else 0.0)
	var pads := Input.get_connected_joypads()
	var pad_fire := false
	if not pads.is_empty():
		var d: int = pads[0]
		var lx := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
		if absf(lx) > 0.2: mv = lx
		var rx := Input.get_joy_axis(d, JOY_AXIS_RIGHT_X)
		if absf(rx) > 0.2: rot = rx
		pad_fire = Input.is_joy_button_pressed(d, JOY_BUTTON_A) or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	if mv != 0.0:
		aim_u = clampf(aim_u + mv * dt * 22.0, -CarromSim.U_MAX, CarromSim.U_MAX); changed = true
	if rot != 0.0:
		aim_ang += rot * dt * 0.9; changed = true
	if _touch():
		if changed: _send_aim()
		return
	var want_charge: bool = k.call([KEY_SPACE]) or pad_fire or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# the press that closed the PASS TO screen must be let go before it can start charging a shot
	if need_release:
		if want_charge: return
		need_release = false
	if want_charge:
		if not charging: charging = true; power = 0.0; power_dir = 1.0
		power += power_dir * dt / 1.1
		if power >= 1.0: power = 1.0; power_dir = -1.0
		elif power <= 0.05 and power_dir < 0.0: power = 0.05; power_dir = 1.0
		changed = true
	elif charging:
		_shoot(); return
	if changed: _send_aim()


func _unhandled_input(e: InputEvent) -> void:
	if sim == null: return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode in [KEY_P, KEY_ESCAPE]: toggle_pause(); return
		if handoff and e.physical_keycode in [KEY_SPACE, KEY_ENTER]: handoff = false; need_release = true; return
	if e is InputEventJoypadButton and e.pressed:
		if e.button_index == JOY_BUTTON_START: toggle_pause(); return
		if handoff and e.button_index == JOY_BUTTON_A: handoff = false; need_release = true; return
	if paused or results_shown: return
	if handoff:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed): handoff = false; need_release = true
		return
	if not _my_turn() or autoplay or _touch(): return
	# mouse: point at the board to aim; right drag or the wheel slides the striker
	if e is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			aim_u = clampf(aim_u + _screen_along(e.relative) * 0.08, -CarromSim.U_MAX, CarromSim.U_MAX)
		else:
			var bp = _board_point(e.position)
			if bp != null:
				var sp: Vector2 = CarromSim.base_point(sim.cur().side, aim_u)
				if (bp as Vector2).distance_to(sp) > 1.0: aim_ang = ((bp as Vector2) - sp).angle()
		_send_aim()
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		aim_u = clampf(aim_u + (1.5 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1.5), -CarromSim.U_MAX, CarromSim.U_MAX)
		_send_aim()


## Touch: drag the striker along your line, or pull back anywhere else like a slingshot and let go.
func _input(e: InputEvent) -> void:
	if sim == null or not _touch(): return
	if e is InputEventScreenTouch and e.pressed:
		var s: Vector2 = hud.size
		if e.position.distance_to(Vector2(s.x - 50, 40)) < 34: toggle_pause(); get_viewport().set_input_as_handled(); return
	if paused or handoff or results_shown or not _my_turn() or autoplay: return
	if e is InputEventScreenTouch:
		if e.pressed and drag_id < 0:
			drag_id = e.index; drag_from = e.position
			var sp := cam.unproject_position(W(CarromSim.base_point(sim.cur().side, aim_u)))
			drag_mode = "striker" if e.position.distance_to(sp) < 60.0 else "sling"
		elif not e.pressed and e.index == drag_id:
			drag_id = -1
			if drag_mode == "sling" and power > 0.06: _shoot()
			drag_mode = ""; charging = false
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and e.index == drag_id:
		if drag_mode == "striker":
			var bp = _board_point(e.position)
			if bp != null:
				var ax: Array = CarromSim.side_axes(sim.cur().side)
				aim_u = clampf(((bp as Vector2) - (ax[0] as Vector2)).dot(ax[1]), -CarromSim.U_MAX, CarromSim.U_MAX)
		else:
			var a = _board_point(drag_from)
			var b = _board_point(e.position)
			if a != null and b != null and (a as Vector2).distance_to(b) > 0.5:
				aim_ang = ((a as Vector2) - (b as Vector2)).angle()   # pull back: it flies the other way
			power = clampf(e.position.distance_to(drag_from) / 240.0, 0.0, 1.0)
			charging = power > 0.0
		_send_aim()


func _board_point(screen: Vector2):
	if cam == null: return null
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 1e-4: return null
	var t := (TOP - o.y) / d.y
	if t < 0.0: return null
	var hit := o + d * t
	return Vector2(hit.x / S, hit.z / S)


func _screen_along(rel: Vector2) -> float:
	var ax: Array = CarromSim.side_axes(sim.cur().side)
	var a := cam.unproject_position(W(ax[0]))
	var b := cam.unproject_position(W((ax[0] as Vector2) + (ax[1] as Vector2) * 10.0))
	return rel.dot((b - a).normalized())


# ---------------------------------------------------------------- events + animation
func _event(e: Array) -> void:
	var kind: String = e[0]
	stats[kind] = stats.get(kind, 0) + 1
	var pi := _player_at(int(e[1])) if e.size() > 1 and (e[1] is int) else -1
	match kind:
		"shot": G.sfx("whoosh"); power = 0.0
		"click":
			if _click_t <= 0.0: G.sfx("ok"); _click_t = 0.07
		"pot":
			G.sfx("grab")
			if pi >= 0 and int(e[2]) == sim.players[pi].team: _react(pi, "m_sit_talk")
		"again": _toast("SHOOT AGAIN!"); _reset_aim()
		"foul":
			G.sfx("ko"); _toast("FOUL — STRIKER POCKETED")
			_react(pi, "m_sit_talk")
		"return": _toast("FOUL — A COIN GOES BACK")
		"queen_pot": G.sfx("surge"); _toast("QUEEN POCKETED — COVER HER!")
		"queen_cover":
			G.sfx("surge"); _toast("QUEEN COVERED!")
			if pi >= 0: _voice(pi, "power")
		"queen_back": _toast("QUEEN BACK TO THE CENTRE")
		"queen_lost": _toast("%s FINISHED BEFORE THE QUEEN!" % CarromSim.TEAM_NAMES[int(e[2])])
		"turn":
			_reset_aim()
			if local_all and sim.cur().human: handoff = true
			elif _my_turn() and not autoplay: G.sfx("ui"); _toast("YOUR TURN")
		"win":
			G.sfx("vs")
			var t := int(e[2])
			for j in sim.players.size():
				if sim.players[j].team == t:
					_react(j, ["win_cheer", "win_celebrate", "win_fist_pump2"].pick_random(), 6.0); _voice(j, "power")
				else: _react(j, "in_shrug", 6.0)
			_toast("%s WIN!" % _team_name(t))
		"done":
			if not results_shown:
				results_shown = true
				get_tree().create_timer(2.0).timeout.connect(_show_results)


func _player_at(side: int) -> int:
	for i in sim.players.size():
		if sim.players[i].side == side: return i
	return -1


func _react(pi: int, clip: String, t := -1.0) -> void:
	if pi < 0 or not ClipLib.has(clip): return
	react[pi] = [clip, t if t > 0.0 else Fighter._len(clip)]
	rigs[pi].set_meta("t", 0.0)


func _voice(pi: int, kind: String) -> void:
	var s := Voices.get_sound(sim.players[pi].C, kind)
	if s == null: return
	var p := AudioStreamPlayer.new(); p.stream = s; p.volume_db = -6.0
	add_child(p); p.play(); p.finished.connect(p.queue_free)


func _animate(dt: float) -> void:
	for i in 20:
		var n: Node3D = discs[i]
		var target: Vector2 = sim.pos[i]
		if guest and (disp[i] as Vector2).distance_to(target) < 20.0: disp[i] = (disp[i] as Vector2).lerp(target, clampf(dt * 22.0, 0.0, 1.0))
		else: disp[i] = target
		if sim.live[i]:
			sink[i] = -1.0
			n.visible = true
			n.position = W(disp[i])
		else:
			if sink[i] < 0.0: sink[i] = 0.0
			sink[i] += dt
			n.visible = sink[i] < 0.3
			n.position.y = TOP - sink[i] * 0.12
	_draw_guide()
	# characters: seated at their side, standing up to celebrate
	for pi in rigs.size():
		var rig = rigs[pi]
		var t: float = rig.get_meta("t", 0.0) + dt
		rig.set_meta("t", t)
		var clip := "m_sit"
		var r: Array = react[pi]
		if r[1] > 0.0:
			r[1] -= dt; clip = r[0]
		elif sim.phase == "done" and sim.players[pi].team == sim.winner:
			clip = "win_victory_idle"
		if not ClipLib.has(clip): clip = "m_sit" if ClipLib.has("m_sit") else "idle_relaxed"
		var seated := clip.begins_with("m_sit")
		rig.set_clip(clip, fmod(t, Fighter._len(clip)), seated, false)
		rig.apply_pose(sim.players[pi].C.pose.guard, not seated)
		var dir: Vector2 = (CarromSim.side_axes(sim.players[pi].side)[0] as Vector2).normalized()
		rig.position = W(dir * (72.0 if seated else 100.0), 0.05 if seated else 0.0)
		# the camera sits in the shooter's seat: hide them (and their tag) while the view is from their side
		var behind: bool = absf(angle_difference(cam_angle, _side_angle(sim.players[pi].side))) < 0.9
		rig.visible = not behind
		(tags[pi] as Label3D).visible = not behind
	# camera: behind the shooter, looking down over their shoulder
	cam_angle = lerp_angle(cam_angle, _side_angle(_view_side()), clampf(dt * 2.2, 0.0, 1.0))
	var d := Vector3(sin(cam_angle), 0, cos(cam_angle))
	cam.position = d * 0.74 + Vector3(0, TOP + 0.78, 0)
	cam.look_at(Vector3(0, TOP, 0) - d * 0.05, Vector3.UP)


## Aim guide: dashes from the striker to the first thing it would hit, a ghost striker there, and where that coin goes.
func _draw_guide() -> void:
	guide_mesh.clear_surfaces()
	if sim.phase != "aim" or results_shown or handoff: return
	var side: int = sim.cur().side
	var mine := _my_turn()
	var u: float = aim_u if mine else float(sim.aim[0])
	var ang: float = aim_ang if mine else float(sim.aim[1])
	var s0 := CarromSim.base_point(side, u)
	var dir := Vector2.from_angle(ang)
	var t_hit := 200.0
	var hit := -1
	for i in 19:
		if not sim.live[i]: continue
		var oc: Vector2 = s0 - sim.pos[i]
		var rr := CarromSim.RS + CarromSim.RC
		var b := oc.dot(dir)
		var disc := b * b - (oc.length_squared() - rr * rr)
		if disc < 0.0: continue
		var t := -b - sqrt(disc)
		if t > 0.0 and t < t_hit: t_hit = t; hit = i
	for a in 2:   # cushions
		if absf(dir[a]) > 1e-4:
			var lim := (CarromSim.H - CarromSim.RS) * signf(dir[a])
			var t := (lim - s0[a]) / dir[a]
			if t > 0.0 and t < t_hit: t_hit = t; hit = -1
	var col := Color(0.1, 0.85, 1.0, 0.95) if mine else Color(0.55, 0.35, 1.0, 0.8)
	var y := TOP + 0.003
	# dashes as thin strips (lines are one pixel wide)
	guide_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var side_v := dir.orthogonal() * 0.22
	var segs := int(t_hit / 1.6) + 1
	for k in segs:
		if k % 2 == 1: continue
		var a0 := s0 + dir * minf(k * 1.6 + (CarromSim.RS if k == 0 else 0.0), t_hit)
		var a1 := s0 + dir * minf((k + 1) * 1.6, t_hit)
		for v in [a0 - side_v, a0 + side_v, a1 + side_v, a0 - side_v, a1 + side_v, a1 - side_v]:
			guide_mesh.surface_set_color(col); guide_mesh.surface_add_vertex(W(v, y))
	guide_mesh.surface_end()
	guide_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var ghost := s0 + dir * t_hit
	for rr in [CarromSim.RS, CarromSim.RS - 0.15, CarromSim.RS - 0.3]:
		for k in 24:
			var a0 := k * TAU / 24.0
			var a1 := (k + 1) * TAU / 24.0
			guide_mesh.surface_set_color(col); guide_mesh.surface_add_vertex(W(ghost + Vector2.from_angle(a0) * rr, y))
			guide_mesh.surface_set_color(col); guide_mesh.surface_add_vertex(W(ghost + Vector2.from_angle(a1) * rr, y))
	if hit >= 0:
		var cdir: Vector2 = ((sim.pos[hit] as Vector2) - ghost).normalized()
		var c2 := Color(0.4, 1.0, 0.6, 0.85)
		for off in [-0.12, 0.0, 0.12]:
			var o: Vector2 = cdir.orthogonal() * float(off)
			guide_mesh.surface_set_color(c2); guide_mesh.surface_add_vertex(W((sim.pos[hit] as Vector2) + o, y))
			guide_mesh.surface_set_color(c2); guide_mesh.surface_add_vertex(W((sim.pos[hit] as Vector2) + cdir * 9.0 + o, y))
	guide_mesh.surface_end()


func _view_side() -> int:
	return sim.cur().side


static func _side_angle(side: int) -> float:
	var c: Vector2 = CarromSim.side_axes(side)[0]
	return atan2(c.x, c.y)


# ---------------------------------------------------------------- HUD
func _nm(p) -> String:
	return (String(p.C.person.get("short", p.C.name)) if p.C.has("person") else String(p.C.name)).to_upper()


func _team_name(t: int) -> String:
	var names := []
	for p in sim.players:
		if p.team == t: names.append(_nm(p))
	return " & ".join(names) if not names.is_empty() else CarromSim.TEAM_NAMES[t]


func _mine(pi: int) -> bool:
	var p = sim.players[pi]
	return p.human and (local_all or p.slot == my_slot)


func _toast(t: String) -> void:
	toast = t; toast_t = 2.0


func _touch() -> bool:
	return G.ui.touch_enabled


func _draw_hud() -> void:
	var s := hud.size
	var ink := Color(0.95, 0.96, 1.0)
	var y := 30.0
	for pi in sim.players.size():
		var p = sim.players[pi]
		var col: Color = SIDE_COL[p.side]
		var box := Rect2(Vector2(20, y), Vector2(330, 58))
		var on: bool = pi == sim.turn and sim.phase != "done"
		hud.draw_rect(box, Color(0, 0, 0, 0.75 if on else 0.5))
		hud.draw_rect(Rect2(box.position, Vector2(8, box.size.y)), col)
		if on: hud.draw_rect(box, col, false, 3.0)
		hud.draw_circle(box.position + Vector2(30, 29), 11, TEAM_COL[p.team])
		hud.draw_arc(box.position + Vector2(30, 29), 11, 0, TAU, 20, Color(0.55, 0.32, 0.9), 2.0)
		var who := _nm(p) + ("  (YOU)" if _mine(pi) and not local_all else ("" if p.human else "  · CPU"))
		hud.draw_string(font, box.position + Vector2(50, 25), who, HORIZONTAL_ALIGNMENT_LEFT, 270, 20, ink)
		var left: int = sim.coins_left(p.team)
		hud.draw_string(small, box.position + Vector2(50, 48), "%s  %d LEFT" % [CarromSim.TEAM_NAMES[p.team], left], HORIZONTAL_ALIGNMENT_LEFT, 150, 18, TEAM_INK[p.team])
		for k in 9:
			hud.draw_circle(box.position + Vector2(200 + k * 13, 43), 5, TEAM_COL[p.team] if k < left else Color(1, 1, 1, 0.12))
		y += 66.0
	var qtxt: String = {"board": "QUEEN ON THE BOARD", "pending": "QUEEN POCKETED BY %s — COVER HER" % CarromSim.TEAM_NAMES[maxi(0, sim.queen_team)],
		"covered": "QUEEN COVERED BY %s" % CarromSim.TEAM_NAMES[maxi(0, sim.queen_team)]}.get(sim.queen, "")
	hud.draw_circle(Vector2(30, y + 14), 9, Color(0.85, 0.08, 0.1))
	hud.draw_string(small, Vector2(48, y + 21), qtxt, HORIZONTAL_ALIGNMENT_LEFT, 330, 18, Color(1.0, 0.65, 0.6))
	var cur = sim.cur()
	var msg := ""
	if sim.phase == "done": msg = "GAME OVER"
	elif _my_turn() and not autoplay: msg = ("YOUR SHOT" if not local_all else _nm(cur) + ":  YOUR SHOT")
	else: msg = "%s IS %s" % [_nm(cur), "AIMING" if sim.phase == "aim" else "SHOOTING"]
	hud.draw_string(font, Vector2(0, 54), msg, HORIZONTAL_ALIGNMENT_CENTER, s.x, 32, SIDE_COL[cur.side].lightened(0.35))
	if net != null and cur.human and not _my_turn() and sim.phase == "aim" and sim.idle > CarromSim.TURN_TIME - 8.0:
		hud.draw_string(small, Vector2(0, 80), "auto-shot in %d" % ceili(CarromSim.TURN_TIME - sim.idle), HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(1, 0.7, 0.5))
	if sim.phase == "aim" and not handoff:
		var pw: float = power if _my_turn() else float(sim.aim[2])
		var bw := 360.0
		var pb := Rect2(Vector2((s.x - bw) / 2.0, s.y - 70), Vector2(bw, 18))
		hud.draw_rect(pb, Color(0, 0, 0, 0.55))
		hud.draw_rect(Rect2(pb.position, Vector2(bw * pw, pb.size.y)), Color(0.3, 0.9, 0.5).lerp(Color(1.0, 0.3, 0.25), pw))
		hud.draw_rect(pb, Color(1, 1, 1, 0.6), false, 2.0)
		hud.draw_string(small, pb.position + Vector2(0, -6), "POWER", HORIZONTAL_ALIGNMENT_CENTER, bw, 16, ink)
	if toast_t > 0.0:
		hud.draw_string(font, Vector2(0, s.y * 0.3), toast, HORIZONTAL_ALIGNMENT_CENTER, s.x, 44, Color(1, 1, 1, clampf(toast_t / 0.4, 0.0, 1.0)))
	if not _touch():
		hud.draw_string(small, Vector2(0, s.y - 14), "A / D, wheel or right-drag  move striker   ·   mouse or ← →  aim   ·   hold SPACE / left click, release  shoot   ·   P  pause",
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 17, Color(0.8, 0.82, 0.9, 0.7))
	else:
		hud.draw_string(small, Vector2(0, s.y - 14), "drag the striker along your line   ·   pull back anywhere and let go to shoot", HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(0.8, 0.82, 0.9, 0.75))
		var pbn := Vector2(s.x - 50, 40)
		hud.draw_circle(pbn, 26, Color(0.58, 0.3, 0.85, 0.3)); hud.draw_arc(pbn, 26, 0, TAU, 32, Color(0.58, 0.3, 0.85), 3)
		hud.draw_string(font, pbn + Vector2(-26, 8), "II", HORIZONTAL_ALIGNMENT_CENTER, 52, 20, Color.WHITE)
		if drag_mode == "sling" and drag_id >= 0:   # the pull-back band
			hud.draw_circle(drag_from, 10, Color(1, 1, 1, 0.35))
	if handoff:
		hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.02, 0.06, 0.94))
		hud.draw_string(font, Vector2(0, s.y * 0.45), "PASS TO %s" % _nm(cur), HORIZONTAL_ALIGNMENT_CENTER, s.x, 54, SIDE_COL[cur.side].lightened(0.3))
		hud.draw_string(small, Vector2(0, s.y * 0.45 + 46), "tap or press SPACE when ready", HORIZONTAL_ALIGNMENT_CENTER, s.x, 24, ink)


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
	v.add_child(ui.lbl("PAUSED" if net == null else "MENU", 44, font, Color(1.0, 0.8, 0.3), 8))
	if net != null: v.add_child(ui.lbl("The game keeps going for everyone else.", 18, small, Color(0.8, 0.82, 0.9)))
	var resume: Button = ui.big_btn("RESUME", Color(0.13, 0.78, 0.92), toggle_pause)
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
	v.add_child(ui.lbl("%s WIN!" % _team_name(w), 44, font, Color(1.0, 0.8, 0.3), 8))
	for t in 2:
		var line := "%s   %s   ·   %d / 9 POCKETED%s" % [CarromSim.TEAM_NAMES[t], _team_name(t), sim.pocketed[t],
			"   ·   QUEEN" if sim.queen == "covered" and sim.queen_team == t else ""]
		v.add_child(ui.lbl(line, 22, small, TEAM_INK[t]))
	v.add_child(ui.lbl("%d shots" % sim.shots, 18, small, Color(0.75, 0.78, 0.88)))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 14)
	if net != null:
		btns.add_child(ui.big_btn("BACK TO LOBBY", Color(0.13, 0.78, 0.92), func(): finished.emit(); G.lobby.back_to_lobby()))
		btns.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), func(): finished.emit(); G.lobby.leave()))
	else:
		var C: Dictionary = sim.players[0].C
		btns.add_child(ui.big_btn("PLAY AGAIN", Color(0.13, 0.78, 0.92), func(): finished.emit(); ui.show_game_menu("carrom", C)))
		btns.add_child(ui.big_btn("MAIN MENU", Color(0.55, 0.62, 0.75), func(): finished.emit(); ui.show_title()))
	v.add_child(btns)
	_center(panel)


# ---------------------------------------------------------------- tests
## --autotest=carrom: the CPU plays every seat; screenshots of the aim, the break, a pocket, mid-game and the result.
func autotest(shot: Callable) -> void:
	var tree: SceneTree = G.get_tree()
	await tree.create_timer(0.9).timeout
	await shot.call("carrom_aim")
	await tree.create_timer(0.75).timeout
	await shot.call("carrom_break")
	var t0 := Time.get_ticks_msec()
	while stats.get("pot", 0) == 0 and Time.get_ticks_msec() - t0 < 60000:
		await tree.process_frame
	await tree.create_timer(0.05).timeout
	await shot.call("carrom_pot")
	await tree.create_timer(6.0).timeout
	await shot.call("carrom_mid")
	print("AUTOTEST carrom mid shots=%d pocketed=%s queen=%s events=%s" % [sim.shots, sim.pocketed, sim.queen, stats])
	# fast-forward the rest of the game in the sim, then show the result
	while sim.phase == "roll": sim.step()
	var res: Array = sim.play_out()
	sim.events.clear()
	sim.events.append(["win", sim.cur().side, sim.winner]); sim.events.append(["done", 0])
	_drain()
	await tree.create_timer(2.6).timeout
	await shot.call("carrom_results")
	print("AUTOTEST carrom done winner=%s shots=%d pocketed=%s" % [CarromSim.TEAM_NAMES[maxi(0, res[0])], res[1], sim.pocketed])


## --autotest=carromsim: whole CPU games in the sim (2 and 4 players), determinism and snapshot round trips.
func selftest(main) -> void:
	var ok := true
	for n in [2, 4]:
		var ppl := []
		for k in n: ppl.append({C = Data.ROSTER[k], human = false, slot = -1})
		var t0 := Time.get_ticks_msec()
		var a = CarromSim.new(); a.setup(ppl, 42)
		var ra: Array = a.play_out()
		var b = CarromSim.new(); b.setup(ppl, 42)
		var rb: Array = b.play_out()
		var same: bool = ra == rb and a.pocketed == b.pocketed
		ok = ok and same and int(ra[0]) >= 0
		print("AUTOTEST carromsim %dp winner=%s shots=%d pocketed=%s queen=%s deterministic=%s (%.1fs)" % [n, CarromSim.TEAM_NAMES[maxi(0, ra[0])], ra[1], a.pocketed, a.queen, same, (Time.get_ticks_msec() - t0) / 1000.0])
		var c = CarromSim.new(); c.setup(ppl, 7)
		var guard := 0
		while c.shots < 6 and guard < 20000:
			guard += 1
			if c.phase == "roll": c.step()
			else:
				var s: Array = c.cpu_shot(); c.shoot(s[0], s[1], s[2])
		var snap: Dictionary = c.snapshot()
		var d = CarromSim.new(); d.setup(ppl, 99)
		d.apply(JSON.parse_string(JSON.stringify(snap)))
		var same2: bool = JSON.stringify(d.snapshot()) == JSON.stringify(snap)
		ok = ok and same2
		print("AUTOTEST carromsim %dp snapshot round trip=%s" % [n, same2])
	print("AUTOTEST carromsim %s" % ("PASS" if ok else "FAIL"))
	var _m = main
