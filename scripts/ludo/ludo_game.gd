class_name LudoGame
extends Node
## BNB Ludo: a 3D board on the boardroom table. Pawns hop square by square, a real die tumbles,
## and each player's character stands at their corner and reacts (cheers on a capture, sulks when sent home).
## Solo vs CPU, pass & play on one device, or online / Wi-Fi (the host runs LudoSim, guests mirror it).

signal finished

var G
var sim: LudoSim
var world: Node3D
var cam: Camera3D
var layer: CanvasLayer
var hud: Control
var font: Font
var small: Font
var pawns: Array = []          # [player][k] -> Node3D
var disp: Array = []           # [player][k] -> displayed step (animates toward the sim)
var hop: Array = []            # [player][k] -> 0..1 progress of the current hop
var rings: Array = []          # [player][k] -> highlight ring
var rigs: Array = []           # per player: character at their corner
var react: Array = []          # per player: [clip, time left]
var die: Node3D
var die_spin := 0.0
var die_show := 1
var my_slot := 0               # online: lobby index; local: 0
var local_all := false         # pass & play: every human seat is played here
var toast := ""
var toast_t := 0.0
var results_shown := false
var cam_angle := 0.0
var autoplay := false          # tests: the CPU plays our seat too
var stats := {}
var paused := false
var roll_btn := Rect2()
var _single_t := 0.0
# online
var net: Party = null
var guest := false
var pid_slot := {}             # host: pid -> lobby slot
var last_rev := -1


## people: [{C, human, slot}] in seat order.
func start(g, people: Array, seed: int, slot := 0, pass_play := false) -> void:
	G = g
	my_slot = slot; local_all = pass_play
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	sim = LudoSim.new()
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
	cam_angle = _seat_angle(_view_seat())


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


# ---------------------------------------------------------------- 3D board
func _mat(c: Color, rough := 0.6, emit := 0.0) -> StandardMaterial3D:
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


static func W(c: Vector2, y := 0.0) -> Vector3:
	return Vector3(c.x - 7.0, y, c.y - 7.0)


func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.04, 0.03, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.68, 0.8); env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true; env.glow_intensity = 0.25
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-60), deg_to_rad(30), 0); sun.light_energy = 1.0; sun.shadow_enabled = true
	world.add_child(sun)
	var lamp := OmniLight3D.new(); lamp.position = Vector3(0, 9, 0); lamp.omni_range = 22; lamp.light_energy = 0.8
	lamp.light_color = Color(1.0, 0.95, 0.85)
	world.add_child(lamp)
	# boardroom: carpet, the long table, chairs, glass walls with the city behind
	_box(Vector3(60, 0.1, 60), _mat(Color(0.16, 0.13, 0.22), 0.95), Vector3(0, -2.05, 0))
	_box(Vector3(19, 0.5, 19), _mat(Color(0.32, 0.2, 0.13), 0.4), Vector3(0, -0.3, 0))     # table top
	for c in [Vector3(-8, -1.2, -8), Vector3(8, -1.2, -8), Vector3(-8, -1.2, 8), Vector3(8, -1.2, 8)]:
		_box(Vector3(0.6, 1.6, 0.6), _mat(Color(0.12, 0.1, 0.1), 0.5), c)
	var glass := _mat(Color(0.5, 0.65, 0.9), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glass.albedo_color.a = 0.18
	for s in [-1.0, 1.0]:
		_box(Vector3(60, 12, 0.2), glass, Vector3(0, 4, s * 22))
		_box(Vector3(0.2, 12, 60), glass, Vector3(s * 22, 4, 0))
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for k in 70:   # city lights outside
		var a := rng.randf() * TAU
		var r := rng.randf_range(30, 55)
		var h := rng.randf_range(4, 26)
		_box(Vector3(rng.randf_range(3, 7), h, rng.randf_range(3, 7)), _mat(Color(0.06, 0.05, 0.1), 0.9), Vector3(cos(a) * r, h / 2 - 2, sin(a) * r))
		for w in 3:
			_box(Vector3(1.2, 0.5, 0.05), _mat([Color(1, 0.85, 0.5), Color(0.4, 0.8, 1.0), Color(0.75, 0.5, 1.0)][w], 0.5, 2.0),
				Vector3(cos(a) * (r - 3.6), rng.randf_range(0, h - 2), sin(a) * (r - 3.6)))
	# the board
	_box(Vector3(15.6, 0.3, 15.6), _mat(Color(0.95, 0.93, 0.88), 0.7), Vector3(0, -0.12, 0))
	_box(Vector3(16.2, 0.32, 16.2), _mat(Color(0.35, 0.18, 0.6), 0.5), Vector3(0, -0.16, 0))   # BNB purple rim
	var white := _mat(Color(0.98, 0.97, 0.94), 0.7)
	var line := _mat(Color(0.2, 0.2, 0.25), 0.8)
	var t := LudoSim.track()
	for i in 52:
		var c := Vector2(t[i][0], t[i][1])
		var start_of := [1, 14, 27, 40].find(i)
		var m: Material = _mat(LudoSim.COLORS[start_of], 0.6) if start_of >= 0 else white
		_box(Vector3(0.98, 0.06, 0.98), line, W(c, 0.03))
		_box(Vector3(0.9, 0.08, 0.9), m, W(c, 0.05))
		if i in LudoSim.SAFE and start_of < 0: _star(W(c, 0.1), Color(0.55, 0.32, 0.9))
		if start_of >= 0: _star(W(c, 0.1), Color(1, 1, 1))
	for s in 4:
		var col: Color = LudoSim.COLORS[s]
		for i in range(1, 6):
			var c: Vector2 = LudoSim.cell(s, 50 + i, 0)
			_box(Vector3(0.98, 0.06, 0.98), line, W(c, 0.03))
			_box(Vector3(0.9, 0.08, 0.9), _mat(col, 0.6), W(c, 0.05))
		# base: coloured square, white yard, four spots
		var corner: Vector2 = [Vector2(2.5, 2.5), Vector2(11.5, 2.5), Vector2(11.5, 11.5), Vector2(2.5, 11.5)][s]
		_box(Vector3(5.9, 0.07, 5.9), _mat(col, 0.6), W(corner, 0.04))
		_box(Vector3(4.0, 0.09, 4.0), white, W(corner, 0.06))
		for k in 4:
			var spot := MeshInstance3D.new()
			var cy := CylinderMesh.new(); cy.top_radius = 0.42; cy.bottom_radius = 0.42; cy.height = 0.04
			spot.mesh = cy; spot.material_override = _mat(col.lightened(0.25), 0.5)
			spot.position = W(LudoSim.cell(s, -1, k), 0.12)
			world.add_child(spot)
		# home triangle in the centre
		_triangle(s, col)
	_box(Vector3(0.6, 0.2, 0.6), _mat(Color(1.0, 0.82, 0.35), 0.3, 0.6), Vector3(0, 0.2, 0))
	# pawns
	for pi in sim.players.size():
		var p: LudoSim.Player = sim.players[pi]
		var row := []; var d := []; var h := []; var rr := []
		for k in 4:
			var n := _pawn(LudoSim.COLORS[p.seat])
			n.position = W(LudoSim.cell(p.seat, -1, k), 0.12)
			row.append(n); d.append(-1); h.append(0.0)
			var ring := MeshInstance3D.new()
			var tor := TorusMesh.new(); tor.inner_radius = 0.36; tor.outer_radius = 0.46
			ring.mesh = tor; ring.material_override = _mat(Color(1, 1, 1), 0.3, 2.5)
			ring.visible = false
			world.add_child(ring)
			rr.append(ring)
		pawns.append(row); disp.append(d); hop.append(h); rings.append(rr)
		# their character at the corner, outside the board
		var rig := Main.make_rig(p.C, 0)
		world.add_child(rig)
		var corner: Vector2 = [Vector2(-1.8, -1.8), Vector2(15.8, -1.8), Vector2(15.8, 15.8), Vector2(-1.8, 15.8)][p.seat]
		rig.position = W(corner, -0.05)
		rig.rotation.y = atan2(-(corner.x - 7.0), -(corner.y - 7.0))
		rig.scale = Vector3.ONE * 1.25
		rigs.append(rig); react.append(["", 0.0])
		var tag := Label3D.new()
		tag.text = _nm(p); tag.font = font; tag.font_size = 64; tag.outline_size = 12
		tag.modulate = LudoSim.COLORS[p.seat]; tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = W(corner, 2.9)
		world.add_child(tag)
	_build_die()
	cam = Camera3D.new(); cam.fov = 46; cam.far = 200
	world.add_child(cam); cam.current = true


func _star(pos: Vector3, c: Color) -> void:
	var l := Label3D.new()
	l.text = "★"; l.font_size = 120; l.modulate = c; l.outline_size = 0
	l.rotation.x = -PI / 2; l.position = pos; l.pixel_size = 0.005
	world.add_child(l)


func _triangle(seat: int, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(0, 0.1, 0)
	var corners: Array = [[Vector3(-1.5, 0.1, -1.5), Vector3(-1.5, 0.1, 1.5)], [Vector3(1.5, 0.1, -1.5), Vector3(-1.5, 0.1, -1.5)],
		[Vector3(1.5, 0.1, 1.5), Vector3(1.5, 0.1, -1.5)], [Vector3(-1.5, 0.1, 1.5), Vector3(1.5, 0.1, 1.5)]][seat]
	st.set_normal(Vector3.UP)
	st.add_vertex(c); st.add_vertex(corners[1]); st.add_vertex(corners[0])
	var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = _mat(col, 0.5)
	world.add_child(mi)


func _pawn(col: Color) -> Node3D:
	var n := Node3D.new()
	world.add_child(n)
	var m := _mat(col, 0.25)
	m.metallic = 0.2
	var base := MeshInstance3D.new()
	var b := CylinderMesh.new(); b.top_radius = 0.24; b.bottom_radius = 0.34; b.height = 0.18
	base.mesh = b; base.material_override = m; base.position.y = 0.09
	n.add_child(base)
	var body := MeshInstance3D.new()
	var bd := CylinderMesh.new(); bd.top_radius = 0.1; bd.bottom_radius = 0.22; bd.height = 0.45
	body.mesh = bd; body.material_override = m; body.position.y = 0.4
	n.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new(); hs.radius = 0.17; hs.height = 0.34
	head.mesh = hs; head.material_override = m; head.position.y = 0.72
	n.add_child(head)
	return n


func _die_face(v: int) -> ImageTexture:
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.98, 0.97, 0.95))
	var pips: Dictionary = {1: [[0.5, 0.5]], 2: [[0.27, 0.27], [0.73, 0.73]], 3: [[0.25, 0.25], [0.5, 0.5], [0.75, 0.75]],
		4: [[0.27, 0.27], [0.73, 0.27], [0.27, 0.73], [0.73, 0.73]], 5: [[0.25, 0.25], [0.75, 0.25], [0.5, 0.5], [0.25, 0.75], [0.75, 0.75]],
		6: [[0.27, 0.22], [0.73, 0.22], [0.27, 0.5], [0.73, 0.5], [0.27, 0.78], [0.73, 0.78]]}
	var col := Color(0.55, 0.25, 0.85) if v != 1 else Color(0.9, 0.2, 0.3)
	for p in pips[v]:
		var cx: float = p[0] * 96.0
		var cy: float = p[1] * 96.0
		for y in 96:
			for x in 96:
				if Vector2(x - cx, y - cy).length() < 9.5: img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _build_die() -> void:
	die = Node3D.new()
	world.add_child(die)
	# faces: 1 up (+Y), 6 down, 2 +X, 5 -X, 3 +Z, 4 -Z
	var faces := {1: [Vector3.UP, Vector3(0, 0, 0)], 6: [Vector3.DOWN, Vector3(PI, 0, 0)], 2: [Vector3.RIGHT, Vector3(0, 0, -PI / 2)],
		5: [Vector3.LEFT, Vector3(0, 0, PI / 2)], 3: [Vector3.BACK, Vector3(PI / 2, 0, 0)], 4: [Vector3.FORWARD, Vector3(-PI / 2, 0, 0)]}
	for v in faces:
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(0.9, 0.9)
		q.mesh = pm
		var m := StandardMaterial3D.new(); m.albedo_texture = _die_face(v); m.roughness = 0.4
		q.material_override = m
		q.rotation = faces[v][1]
		q.position = (faces[v][0] as Vector3) * 0.45
		die.add_child(q)
	var core := _box(Vector3(0.88, 0.88, 0.88), _mat(Color(0.98, 0.97, 0.95), 0.4), Vector3.ZERO, die)
	core.scale = Vector3.ONE
	die.position = Vector3(0, 1.4, 0)


static func _face_rot(v: int) -> Vector3:
	return {1: Vector3.ZERO, 6: Vector3(PI, 0, 0), 2: Vector3(0, 0, PI / 2), 5: Vector3(0, 0, -PI / 2), 3: Vector3(-PI / 2, 0, 0), 4: Vector3(PI / 2, 0, 0)}.get(v, Vector3.ZERO)


# ---------------------------------------------------------------- loop
func _process(dt: float) -> void:
	if sim == null or world == null: return
	if not guest and not paused:
		sim.update(dt)
		_drain()
	_control(dt)
	_animate(dt)
	toast_t = maxf(0.0, toast_t - dt)
	hud.queue_redraw()


## Host / local: read the sim's events, show them, and stream the new state to guests.
func _drain() -> void:
	var ev := sim.events.duplicate()
	sim.events.clear()
	for e in ev: _event(e)
	if net != null and (sim.rev != last_rev or not ev.is_empty()):
		last_rev = sim.rev
		var pe := []
		for e in ev: pe.append(Party.pack(e))
		net.broadcast({t = "ls", s = sim.snapshot(), e = pe})


func _net_message(pid: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"ls":
			if not guest: return
			sim.apply(d.s)
			for e in d.e: _event(Party.unpack_event(e))
		"li":
			if guest or not pid_slot.has(pid): return
			var p: LudoSim.Player = sim.cur()
			if not p.human or p.slot != int(pid_slot[pid]): return
			if String(d.a) == "roll": sim.roll()
			elif String(d.a) == "move": sim.move(int(d.k))


func _net_left(pid: int) -> void:
	if not pid_slot.has(pid): return
	for p in sim.players:
		if p.slot == int(pid_slot[pid]):
			p.human = false
			_toast("%s LEFT · CPU PLAYS ON" % _nm(p))


## Is it this device's turn to act?
func _my_turn() -> bool:
	var p: LudoSim.Player = sim.cur()
	if not p.human or sim.phase == "done": return false
	return local_all or p.slot == my_slot


func _act(a: String, k := -1) -> void:
	if not _my_turn(): return
	if guest:
		net.send({t = "li", a = a, k = k})
	elif a == "roll": sim.roll()
	elif a == "move": sim.move(k)


func _control(dt: float) -> void:
	if paused or not _my_turn(): return
	if autoplay:
		_single_t += dt
		if _single_t < 0.4: return
		_single_t = 0.0
		if sim.phase == "roll": _act("roll")
		elif sim.phase == "move": _act("move", sim.best_move())
		return
	# only one pawn can move: move it for them after a moment
	if sim.phase == "move":
		var opts := sim.movable()
		if opts.size() == 1:
			_single_t += dt
			if _single_t > 0.55: _single_t = 0.0; _act("move", opts[0])
		else:
			_single_t = 0.0


func _unhandled_input(e: InputEvent) -> void:
	if sim == null: return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode in [KEY_P, KEY_ESCAPE]: toggle_pause(); return
		if paused: return
		if e.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_R] and sim.phase == "roll": _act("roll")
		var n: int = [KEY_1, KEY_2, KEY_3, KEY_4].find(e.physical_keycode)
		if n >= 0 and sim.phase == "move": _act("move", n)
	if e is InputEventJoypadButton and e.pressed:
		if e.button_index == JOY_BUTTON_START: toggle_pause()
		elif e.button_index == JOY_BUTTON_A and sim.phase == "roll": _act("roll")
		elif sim.phase == "move" and e.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]:
			_act("move", [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y].find(e.button_index))
	var click: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if click and not paused and not results_shown:
		var pos: Vector2 = e.position
		if sim.phase == "roll" and (roll_btn.has_point(pos) or pos.distance_to(cam.unproject_position(die.position)) < 90.0):
			_act("roll"); return
		if sim.phase == "move":
			var best := -1
			var bd := 70.0
			var pl: Array = pawns[sim.turn]
			for k in sim.movable():
				var sp := cam.unproject_position((pl[k] as Node3D).position + Vector3(0, 0.4, 0))
				if sp.distance_to(pos) < bd: bd = sp.distance_to(pos); best = k
			if best >= 0: _act("move", best)


# ---------------------------------------------------------------- events + animation
func _event(e: Array) -> void:
	var kind: String = e[0]
	stats[kind] = stats.get(kind, 0) + 1
	var pi := _player_of(int(e[1])) if e.size() > 1 and (e[1] is int) else -1
	match kind:
		"roll":
			die_spin = 0.55; die_show = int(e[2])
			G.sfx("block")
		"turn":
			_single_t = 0.0
			if _my_turn() and not autoplay: G.sfx("ui"); _toast("YOUR TURN" if not local_all else "%s'S TURN" % _nm(sim.cur()))
		"stuck": if pi >= 0 and _mine(pi): _toast("NO MOVES")
		"three6": _toast("THREE 6s — TURN LOST"); G.sfx("thud")
		"capture":
			var vi := _player_of(int(e[2]))
			G.sfx("heavy")
			_react(pi, ["win_cheer", "in_laughing", "win_fistpump", "taunt_angry"].pick_random())
			_react(vi, ["hit_heavy", "in_shrug", "taunt_angry"].pick_random())
			if pi >= 0: _voice(pi, "power")
			if vi >= 0: _voice(vi, "hurt")
			_toast("%s CAPTURED %s!" % [_nm(sim.players[pi]), _nm(sim.players[vi])])
		"home":
			G.sfx("ok"); _react(pi, "in_clap")
		"win":
			G.sfx("ko"); _react(pi, "win_celebrate"); _voice(pi, "win")
			_toast("%s FINISHED %s" % [_nm(sim.players[pi]), RaceGame._ord(int(e[2]))])
		"move":
			G.sfx("ui")
		"done":
			if not results_shown:
				results_shown = true
				get_tree().create_timer(1.6).timeout.connect(_show_results)


func _player_of(seat: int) -> int:
	for i in sim.players.size():
		if (sim.players[i] as LudoSim.Player).seat == seat: return i
	return -1


func _mine(pi: int) -> bool:
	var p: LudoSim.Player = sim.players[pi]
	return p.human and (local_all or p.slot == my_slot)


func _react(pi: int, clip: String) -> void:
	if pi < 0 or not ClipLib.has(clip): return
	react[pi] = [clip, Fighter._len(clip)]
	rigs[pi].set_meta("t", 0.0)


func _voice(pi: int, kind: String) -> void:
	var s := Voices.get_sound((sim.players[pi] as LudoSim.Player).C, kind)
	if s == null: return
	var p := AudioStreamPlayer.new(); p.stream = s; p.volume_db = -6.0
	add_child(p); p.play(); p.finished.connect(p.queue_free)


func _animate(dt: float) -> void:
	var movable: Array = sim.movable() if _my_turn() else []
	for pi in sim.players.size():
		var p: LudoSim.Player = sim.players[pi]
		for k in 4:
			var want: int = p.tokens[k]
			var cur: int = disp[pi][k]
			var n: Node3D = pawns[pi][k]
			if cur != want:
				if want < 0:
					disp[pi][k] = -1; hop[pi][k] = 0.0   # captured: straight back to base
				else:
					hop[pi][k] += dt / 0.13
					if hop[pi][k] >= 1.0:
						hop[pi][k] = 0.0
						disp[pi][k] = 0 if cur < 0 else cur + 1
						if disp[pi][k] > want: disp[pi][k] = want
			cur = disp[pi][k]
			var at := W(LudoSim.cell(p.seat, cur, k), 0.12)
			if cur != want and want >= 0:
				var nxt := W(LudoSim.cell(p.seat, 0 if cur < 0 else cur + 1, k), 0.12)
				var f: float = hop[pi][k]
				at = at.lerp(nxt, f) + Vector3(0, sin(f * PI) * 0.45, 0)
			# pawns sharing a square sit side by side
			var share := 0
			for pj in sim.players.size():
				for j in 4:
					if (pj != pi or j != k) and disp[pj][j] == cur and cur >= 0 and cur < LudoSim.HOME and \
						LudoSim.abs_square((sim.players[pj] as LudoSim.Player).seat, disp[pj][j]) == LudoSim.abs_square(p.seat, cur) and (pj * 4 + j) < (pi * 4 + k):
						share += 1
			at += Vector3(share * 0.22, 0, share * 0.22)
			n.position = n.position.lerp(at, clampf(dt * 18.0, 0.0, 1.0)) if cur == want else at
			var ring: MeshInstance3D = rings[pi][k]
			ring.visible = pi == sim.turn and k in movable
			if ring.visible:
				ring.position = n.position + Vector3(0, 0.05, 0)
				ring.scale = Vector3.ONE * (1.0 + 0.12 * sin(Time.get_ticks_msec() / 120.0))
				n.position.y += 0.08 + 0.08 * sin(Time.get_ticks_msec() / 150.0)
	# die: tumble, then settle on the rolled face
	if die_spin > 0.0:
		die_spin -= dt
		die.rotation += Vector3(11.0, 7.0, 9.0) * dt
		die.position.y = 1.4 + absf(sin(die_spin * 14.0)) * 0.6
	else:
		die.rotation = die.rotation.lerp(_face_rot(die_show), clampf(dt * 14.0, 0.0, 1.0))
		die.position.y = lerpf(die.position.y, 1.0 if sim.phase != "roll" or not _my_turn() else 1.2 + 0.1 * sin(Time.get_ticks_msec() / 200.0), dt * 8.0)
	# characters at the corners
	for pi in rigs.size():
		var rig = rigs[pi]
		var t: float = rig.get_meta("t", 0.0) + dt
		rig.set_meta("t", t)
		var clip := "idle_relaxed"
		var r: Array = react[pi]
		if r[1] > 0.0:
			r[1] -= dt; clip = r[0]
		elif pi == sim.turn and sim.phase != "done":
			clip = "in_thinking" if ClipLib.has("in_thinking") else "idle_fight"
		elif (sim.players[pi] as LudoSim.Player).place == 1:
			clip = "win_victory_idle" if ClipLib.has("win_victory_idle") else "idle_relaxed"
		if not ClipLib.has(clip): clip = "idle_fight"
		rig.set_clip(clip, fmod(t, Fighter._len(clip)), false, false)
		rig.apply_pose((sim.players[pi] as LudoSim.Player).C.pose.guard, true)
	# camera: your corner nearest you (pass & play: turns to whoever's playing)
	cam_angle = lerp_angle(cam_angle, _seat_angle(_view_seat()), clampf(dt * 2.5, 0.0, 1.0))
	var d := Vector3(sin(cam_angle), 0, cos(cam_angle))
	cam.position = d * 15.5 + Vector3(0, 16.0, 0)
	cam.look_at(Vector3(0, -1.2, 0) + d * 0.4, Vector3.UP)


func _view_seat() -> int:
	if local_all: return (sim.cur() as LudoSim.Player).seat
	for p in sim.players:
		if p.slot == my_slot and p.human: return p.seat
	return (sim.players[0] as LudoSim.Player).seat


static func _seat_angle(seat: int) -> float:
	# camera direction from the centre: seat 0 views from -X, 1 from -Z, 2 from +X, 3 from +Z
	return [-PI / 2, PI, PI / 2, 0.0][seat]


# ---------------------------------------------------------------- HUD
func _nm(p: LudoSim.Player) -> String:
	return (String(p.C.person.get("short", p.C.name)) if p.C.has("person") else String(p.C.name)).to_upper()


func _toast(t: String) -> void:
	toast = t; toast_t = 1.8


func _touch() -> bool:
	return G.ui.touch_enabled


func _draw_hud() -> void:
	var s := hud.size
	var ink := Color(0.95, 0.96, 1.0)
	# players
	var y := 30.0
	for pi in sim.players.size():
		var p: LudoSim.Player = sim.players[pi]
		var col: Color = LudoSim.COLORS[p.seat]
		var box := Rect2(Vector2(20, y), Vector2(300, 54))
		hud.draw_rect(box, Color(0, 0, 0, 0.5 if pi != sim.turn else 0.75))
		hud.draw_rect(Rect2(box.position, Vector2(8, box.size.y)), col)
		if pi == sim.turn and sim.phase != "done": hud.draw_rect(box, col, false, 3.0)
		var home := p.tokens.filter(func(r): return r == LudoSim.HOME).size()
		var who := _nm(p) + ("  (YOU)" if _mine(pi) and not local_all else ("" if p.human else "  · CPU"))
		hud.draw_string(font, box.position + Vector2(20, 24), who, HORIZONTAL_ALIGNMENT_LEFT, 270, 20, ink)
		var info := "HOME %d / 4" % home if p.place == 0 else "FINISHED %s" % RaceGame._ord(p.place)
		hud.draw_string(small, box.position + Vector2(20, 46), info, HORIZONTAL_ALIGNMENT_LEFT, 270, 18, col.lightened(0.3))
		y += 62.0
	# whose turn / what to do
	var cur: LudoSim.Player = sim.cur()
	var msg := ""
	if sim.phase == "done": msg = "GAME OVER"
	elif _my_turn():
		msg = ("ROLL THE DIE" if sim.phase == "roll" else ("PICK A PAWN" if sim.movable().size() > 1 else "")) if not autoplay else ""
		if local_all: msg = _nm(cur) + ":  " + msg
	else:
		msg = "%s IS %s" % [_nm(cur), "ROLLING" if sim.phase == "roll" else "MOVING"]
	hud.draw_string(font, Vector2(0, 54), msg, HORIZONTAL_ALIGNMENT_CENTER, s.x, 34, LudoSim.COLORS[cur.seat].lightened(0.35))
	if sim.dice > 0:
		hud.draw_string(small, Vector2(0, 84), "ROLLED %d" % sim.dice, HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, ink)
	if net != null and cur.human and not _my_turn() and sim.idle > LudoSim.TURN_TIME - 8.0:
		hud.draw_string(small, Vector2(0, 108), "auto-move in %d" % ceili(LudoSim.TURN_TIME - sim.idle), HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(1, 0.7, 0.5))
	# roll button
	var r := clampf(s.y * 0.09, 46.0, 72.0)
	roll_btn = Rect2(Vector2(s.x - r * 3.6, s.y - r * 2.2), Vector2(r * 3.0, r * 1.5))
	if _my_turn() and sim.phase == "roll" and not autoplay:
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 180.0)
		hud.draw_rect(roll_btn, Color(1.0, 0.81, 0.35, pulse))
		hud.draw_string(font, roll_btn.position + Vector2(0, roll_btn.size.y * 0.64), "ROLL", HORIZONTAL_ALIGNMENT_CENTER, roll_btn.size.x, int(r * 0.6), Color(0.05, 0.04, 0.1))
	if toast_t > 0.0:
		hud.draw_string(font, Vector2(0, s.y * 0.3), toast, HORIZONTAL_ALIGNMENT_CENTER, s.x, 46, Color(1, 1, 1, clampf(toast_t / 0.4, 0.0, 1.0)))
	if not _touch():
		hud.draw_string(small, Vector2(0, s.y - 12), "SPACE / click  roll   ·   click a glowing pawn or 1-4  move   ·   P  pause", HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(0.8, 0.82, 0.9, 0.7))
	else:
		var pb := Vector2(s.x - 50, 40)
		hud.draw_circle(pb, 26, Color(0.58, 0.3, 0.85, 0.3)); hud.draw_arc(pb, 26, 0, TAU, 32, Color(0.58, 0.3, 0.85), 3)
		hud.draw_string(font, pb + Vector2(-26, 8), "II", HORIZONTAL_ALIGNMENT_CENTER, 52, 20, Color.WHITE)


func _input(e: InputEvent) -> void:
	if sim == null or not _touch(): return
	if e is InputEventScreenTouch and e.pressed:
		var s: Vector2 = hud.size
		if e.position.distance_to(Vector2(s.x - 50, 40)) < 34: toggle_pause(); get_viewport().set_input_as_handled()


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
	var ui = G.ui
	var panel := _panel()
	var v: VBoxContainer = panel.get_child(0)
	var order := sim.players.duplicate()
	order.sort_custom(func(a, b): return a.place < b.place)
	var first: LudoSim.Player = order[0]
	v.add_child(ui.lbl("%s WINS!" % _nm(first), 44, font, LudoSim.COLORS[first.seat], 8))
	for p in order:
		v.add_child(ui.lbl("%s   %s%s" % [RaceGame._ord(p.place), _nm(p), "" if p.human else "  · CPU"], 24, font, LudoSim.COLORS[p.seat].lightened(0.3)))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 14)
	if net != null:
		btns.add_child(ui.big_btn("BACK TO LOBBY", Color(0.13, 0.78, 0.92), func(): finished.emit(); G.lobby.back_to_lobby()))
		btns.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), func(): finished.emit(); G.lobby.leave()))
	else:
		var C: Dictionary = (sim.players[0] as LudoSim.Player).C
		btns.add_child(ui.big_btn("PLAY AGAIN", Color(0.13, 0.78, 0.92), func(): finished.emit(); ui.show_ludo_menu(C)))
		btns.add_child(ui.big_btn("MAIN MENU", Color(0.55, 0.62, 0.75), func(): finished.emit(); ui.show_title()))
	v.add_child(btns)
	_center(panel)
