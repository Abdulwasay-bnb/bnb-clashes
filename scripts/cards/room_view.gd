extends Node
## Card room table for Thulla, Seep, Dehla Pakad, Kadi Patta, Teen Patti and Satte Pe Satta (Rung has its own view in
## cards_game.gd). 2–8 colleagues seated round a felt table in the break room; your seat holds the camera; your
## cards are a fan along the bottom of the screen. Runs one of the room sims locally or on the host; guests get a
## snapshot with only their own cards and send the action they pick.

signal finished

const SIMS := {
	"thulla": preload("res://scripts/cards/thulla_sim.gd"), "satte": preload("res://scripts/cards/satte_sim.gd"),
	"dehla": preload("res://scripts/cards/trick_sim.gd"), "kadi": preload("res://scripts/cards/trick_sim.gd"),
	"teenpatti": preload("res://scripts/cards/teenpatti_sim.gd"), "seep": preload("res://scripts/cards/seep_sim.gd"),
}
const TITLES := {"thulla": "THULLA", "satte": "SATTE PE SATTA", "dehla": "DEHLA PAKAD", "kadi": "KADI PATTA", "teenpatti": "TEEN PATTI", "seep": "SEEP"}
const TEAM_COL := [Color(0.62, 0.38, 1.0), Color(0.13, 0.78, 0.92)]
const TEAM_NAME := ["TEAM BIT", "TEAM BYTE"]
const SEAT_COL := [Color(0.62, 0.38, 1.0), Color(0.13, 0.78, 0.92), Color(1.0, 0.6, 0.25), Color(0.4, 0.85, 0.45),
	Color(1.0, 0.4, 0.55), Color(1.0, 0.85, 0.3), Color(0.55, 0.65, 1.0), Color(0.85, 0.85, 0.9)]
const RED_INK := Color(0.85, 0.1, 0.17)
const BLACK_INK := Color(0.08, 0.08, 0.13)
const GOLD := Color(1.0, 0.82, 0.35)
const TABLE_Y := 0.76

var G
var variant := "thulla"
var sim
var world: Node3D
var env: Environment
var cam: Camera3D
var layer: CanvasLayer
var hud: Control
var font: Font
var small: Font
var suitf: Font
var mark: Texture2D
var R := 0.9                        # table radius
var rigs: Array = []
var tags: Array = []
var react: Array = []
var backs: Array = []
var items := {}                     # key -> Node3D on the table
var center_lbl: Label3D
var turn_ring: MeshInstance3D
var chip_nodes: Array = []
var my_slot := 0
var local_all := false
var reveal_seat := -1
var autoplay := false
var stats := {}
var paused := false
var results_shown := false
var toast := ""
var toast_t := 0.0
var sel := -1
var hover := -1
var hand_rects: Array = []
var btn_rects: Array = []           # [Rect2, action Dictionary]
var seep_card := -1                 # Seep: the card whose moves are being offered
var cam_angle := 0.0
var _act_t := 0.0
var _sb := {}
var net: Party = null
var guest := false
var pid_slot := {}
var last_rev := -1
var pause_btn := Vector2.ZERO


func start(g, people: Array, seed: int, slot := 0, pass_play := false) -> void:
	G = g
	my_slot = slot; local_all = pass_play and variant != "teenpatti"
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	suitf = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	mark = load("res://assets/brand/bnb_mark_trim.png")
	sim = SIMS[variant].new()
	if variant in ["dehla", "kadi"]: sim.mode = variant
	sim.setup(people, seed)
	R = 1.25 if (sim.n > 4 or variant in ["satte", "seep"]) else 0.95
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


# ---------------------------------------------------------------- 3D
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


func _cyl(r: float, h: float, m: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r; c.height = h; c.radial_segments = 32
	mi.mesh = c; mi.material_override = m; mi.position = pos
	(parent if parent != null else world).add_child(mi)
	return mi


func seat_dir(seat: int) -> Vector3:
	var a: float = -seat * TAU / sim.n
	return Vector3(sin(a), 0, cos(a))


func _seat_angle(seat: int) -> float:
	return -seat * TAU / sim.n


func _model(name: String, pos: Vector3, yaw: float, size: Vector3) -> void:
	var ps: PackedScene = load("res://assets/kenney/furniture/%s.glb" % name)
	if ps == null: return
	var holder := Node3D.new(); holder.position = pos; holder.rotation.y = yaw
	world.add_child(holder)
	var model: Node3D = ps.instantiate()
	holder.add_child(model)
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			if src is BaseMaterial3D:
				var m: BaseMaterial3D = src.duplicate()
				var c: Color = m.albedo_color
				m.albedo_color = Color.from_hsv(c.h, minf(1.0, c.s * 1.25), c.v * 0.62, c.a)
				(mi as MeshInstance3D).set_surface_override_material(i, m)
	if first or box.size.x <= 0.0: return
	var k := Vector3(size.x / box.size.x, size.y / maxf(box.size.y, 0.01), size.z / maxf(box.size.z, 0.01))
	model.scale = k
	model.position = -Vector3(box.get_center().x * k.x, box.position.y * k.y, box.get_center().z * k.z)


func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.05, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.55, 0.62); env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true; env.glow_intensity = 0.25; env.glow_hdr_threshold = 1.3
	we.environment = env
	world.add_child(we)
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 3.1, 0); lamp.rotation.x = -PI / 2
	lamp.spot_range = 6.5; lamp.spot_angle = 48.0 if R > 1.0 else 42.0; lamp.light_energy = 3.4; lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.shadow_enabled = true
	world.add_child(lamp)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-40), deg_to_rad(140), 0); fill.light_energy = 0.35; fill.light_color = Color(0.7, 0.8, 1.0)
	world.add_child(fill)
	_box(Vector3(0.5, 0.25, 0.5), _mat(Color(0.12, 0.1, 0.1), 0.4), Vector3(0, 2.85, 0))
	_box(Vector3(0.42, 0.02, 0.42), _mat(Color(1.0, 0.85, 0.6), 0.3, 2.5), Vector3(0, 2.72, 0))
	_box(Vector3(0.02, 1.2, 0.02), _mat(Color(0.1, 0.1, 0.1)), Vector3(0, 3.5, 0))
	_box(Vector3(14, 0.1, 14), _mat(Color(0.34, 0.24, 0.17), 0.7), Vector3(0, -0.05, 0))
	for k in 9: _box(Vector3(14, 0.005, 0.02), _mat(Color(0.22, 0.15, 0.1), 0.8), Vector3(0, 0.001, -6 + k * 1.5 + 0.75))
	var wall := _mat(Color(0.22, 0.16, 0.3), 0.85)
	_box(Vector3(14, 4, 0.2), wall, Vector3(0, 2, -6.0)); _box(Vector3(14, 4, 0.2), wall, Vector3(0, 2, 6.0))
	_box(Vector3(0.2, 4, 14), wall, Vector3(-6.0, 2, 0)); _box(Vector3(0.2, 4, 14), wall, Vector3(6.0, 2, 0))
	for side in [Vector3(0, 1.0, -5.88), Vector3(0, 1.0, 5.88)]:
		_box(Vector3(14, 0.08, 0.06), _mat(Color(0.55, 0.32, 0.9), 0.4, 0.8), side)
	_model("kitchenBar", Vector3(-2.2, 0, -5.4), 0.0, Vector3(3.2, 0.95, 0.8))
	_model("kitchenCoffeeMachine", Vector3(-2.8, 0.95, -5.5), 0.0, Vector3(0.4, 0.45, 0.35))
	_model("kitchenFridge", Vector3(0.2, 0, -5.4), 0.0, Vector3(0.9, 2.0, 0.8))
	_model("plantSmall1", Vector3(5.2, 0, -5.2), 0.0, Vector3(0.6, 1.2, 0.6))
	_model("plantSmall2", Vector3(-5.2, 0, 5.2), 0.0, Vector3(0.6, 1.2, 0.6))
	var sp := Sprite3D.new(); sp.texture = mark; sp.pixel_size = 1.4 / mark.get_height(); sp.shaded = false
	sp.position = Vector3(2.4, 2.2, -5.88); sp.modulate = Color(1.3, 1.3, 1.3)
	world.add_child(sp)
	# round card table: green felt in a wooden rim on a pedestal
	var felt := Color(0.06, 0.34, 0.2) if variant != "teenpatti" else Color(0.32, 0.06, 0.1)
	_cyl(R, 0.05, _mat(felt, 0.95), Vector3(0, TABLE_Y - 0.025, 0))
	var rim := MeshInstance3D.new(); var tor := TorusMesh.new(); tor.inner_radius = R - 0.02; tor.outer_radius = R + 0.07; tor.rings = 48
	rim.mesh = tor; rim.material_override = _mat(Color(0.3, 0.17, 0.08), 0.45); rim.position = Vector3(0, TABLE_Y, 0); rim.scale = Vector3(1, 0.6, 1)
	world.add_child(rim)
	_cyl(0.12, TABLE_Y - 0.05, _mat(Color(0.25, 0.14, 0.07), 0.5), Vector3(0, (TABLE_Y - 0.05) / 2.0, 0))
	_cyl(0.45, 0.04, _mat(Color(0.25, 0.14, 0.07), 0.5), Vector3(0, 0.02, 0))
	var felt_mark := Sprite3D.new(); felt_mark.texture = mark; felt_mark.pixel_size = 0.45 / mark.get_height()
	felt_mark.rotation.x = -PI / 2; felt_mark.position = Vector3(0, TABLE_Y + 0.002, 0); felt_mark.modulate = Color(1, 1, 1, 0.12)
	world.add_child(felt_mark)
	center_lbl = Label3D.new(); center_lbl.font = suitf; center_lbl.font_size = 160; center_lbl.outline_size = 0
	center_lbl.rotation.x = -PI / 2; center_lbl.position = Vector3(0, TABLE_Y + 0.004, 0); center_lbl.pixel_size = 0.0016
	center_lbl.modulate = Color(1, 1, 1, 0.0)
	world.add_child(center_lbl)
	turn_ring = MeshInstance3D.new()
	var tr := TorusMesh.new(); tr.inner_radius = 0.12; tr.outer_radius = 0.145
	turn_ring.mesh = tr; turn_ring.material_override = _mat(Color(1.0, 0.75, 0.25), 0.3, 1.1)
	world.add_child(turn_ring)
	for s in sim.n:
		var p = sim.players[s]
		var d := seat_dir(s)
		_model("chairCushion", d * (R + 0.3), atan2(d.x, d.z) + PI, Vector3(0.55, 0.95, 0.55))
		var rig := Main.make_rig(p.C, 0)
		world.add_child(rig)
		rig.position = d * (R + 0.24) + Vector3(0, 0.05, 0)
		rig.rotation.y = atan2(-d.x, -d.z)
		rig.set_meta("t", randf() * 3.0)
		if OS.has_feature("mobile"):
			for gi in rig.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rigs.append(rig); react.append(["", 0.0])
		var tag := Label3D.new()
		tag.text = _nm(p); tag.font = font; tag.font_size = 40; tag.outline_size = 8
		tag.modulate = _col(s).lightened(0.25); tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = d * (R + 0.27) + Vector3(0, 1.5 * float(p.C.get("scale", 1.0)), 0); tag.pixel_size = 0.0018
		world.add_child(tag)
		tags.append(tag)
		var row := []
		for k in 13:
			var b := _card3d(-1)
			b.visible = false
			row.append(b)
		backs.append(row)
	cam = Camera3D.new(); cam.fov = 54; cam.far = 60
	cam.environment = env
	world.add_child(cam); cam.current = true


func _card3d(card: int) -> Node3D:
	var n := Node3D.new()
	world.add_child(n)
	var back := card < 0
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.2, 0.004, 0.28)
	body.mesh = bm
	body.material_override = _mat(Color(0.97, 0.96, 0.92) if not back else Color(0.36, 0.18, 0.6), 0.5)
	n.add_child(body)
	if back:
		var inner := _box(Vector3(0.17, 0.0045, 0.25), _mat(Color(0.48, 0.26, 0.8), 0.5), Vector3.ZERO, n)
		inner.position.y = 0.0004
		var s := Sprite3D.new(); s.texture = mark; s.pixel_size = 0.11 / mark.get_height(); s.shaded = true
		s.rotation.x = -PI / 2; s.position.y = 0.003
		n.add_child(s)
		return n
	var ink := RED_INK if sim.is_red(card) else BLACK_INK
	var big := Label3D.new(); big.font = suitf; big.text = sim.SUITS[sim.suit_of(card)]; big.font_size = 110
	big.modulate = ink; big.outline_size = 0; big.pixel_size = 0.0011; big.rotation.x = -PI / 2; big.position = Vector3(0, 0.003, 0.02)
	big.shaded = true
	n.add_child(big)
	for corner in [Vector3(-0.064, 0.003, -0.108), Vector3(0.064, 0.003, 0.108)]:
		var r := Label3D.new(); r.font = font; r.text = sim.RANKS[sim.rank_of(card)]; r.font_size = 60
		r.modulate = ink; r.outline_size = 0; r.pixel_size = 0.0009; r.rotation.x = -PI / 2; r.position = corner
		r.shaded = true
		if corner.z > 0: r.rotation.y = PI
		n.add_child(r)
	return n


# ---------------------------------------------------------------- teams / helpers
func _teams() -> bool:
	return variant in ["dehla", "kadi"] or (variant == "seep" and sim.n == 4)


func _col(seat: int) -> Color:
	if _teams(): return TEAM_COL[seat % 2]
	return SEAT_COL[seat % SEAT_COL.size()]


func _nm(p) -> String:
	return (String(p.C.person.get("short", p.C.name)) if p.C.has("person") else String(p.C.get("name", "?"))).to_upper()


func _toast(t: String) -> void:
	toast = t; toast_t = 2.0


func _touch() -> bool:
	return G.ui.touch_enabled


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


func _drain() -> void:
	var ev: Array = sim.events.duplicate()
	sim.events.clear()
	for e in ev: _event(e)
	if net != null and (sim.rev != last_rev or not ev.is_empty()):
		last_rev = sim.rev
		var pe := []
		for e in ev: pe.append(Party.pack(e))
		for pid in pid_slot:
			net.send_to(int(pid), {t = "cs", s = sim.snapshot_for(_seat_of_slot(int(pid_slot[pid]))), e = pe})


func _seat_of_slot(slot: int) -> int:
	for p in sim.players:
		if p.slot == slot and p.human: return p.seat
	return -1


func _net_message(pid: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"cs":
			if not guest: return
			sim.apply(d.s)
			for e in d.e: _event(Party.unpack_event(e))
		"ci":
			if guest or not pid_slot.has(pid) or not (d.get("d") is Dictionary): return
			var seat := _seat_of_slot(int(pid_slot[pid]))
			if seat < 0 or seat != sim.actor(): return
			sim.act(seat, d.d)


func _net_left(pid: int) -> void:
	if not pid_slot.has(pid): return
	for p in sim.players:
		if p.slot == int(pid_slot[pid]):
			p.human = false
			_toast("%s LEFT · CPU PLAYS ON" % _nm(p))


func _is_mine(seat: int) -> bool:
	if seat < 0: return false
	var p = sim.players[seat]
	return p.human and (local_all or p.slot == my_slot)


func _my_turn() -> bool:
	var a: int = sim.actor()
	if a < 0 or not _is_mine(a): return false
	return not local_all or reveal_seat == a


func _send(a: Dictionary) -> void:
	if not _my_turn(): return
	sel = -1; seep_card = -1
	if guest: net.send({t = "ci", d = a})
	elif not sim.act(sim.actor(), a): G.sfx("thud")


func _control(dt: float) -> void:
	if paused: return
	var a: int = sim.actor()
	if local_all and _is_mine(a) and reveal_seat != a and autoplay: reveal_seat = a
	if not _my_turn() or not autoplay: return
	_act_t += dt
	if _act_t < 0.3: return
	_act_t = 0.0
	_send(sim.cpu(a))


func _shown_seat() -> int:
	if local_all: return reveal_seat
	for p in sim.players:
		if p.slot == my_slot and p.human: return p.seat
	return -1


func _view_seat() -> int:
	if local_all: return reveal_seat if reveal_seat >= 0 else maxi(0, sim.actor())
	var s := _shown_seat()
	return s if s >= 0 else 0


func _curtain() -> bool:
	var a: int = sim.actor()
	return local_all and _is_mine(a) and reveal_seat != a and sim.phase != "done" and not results_shown


## Play this card (games where a card is the whole move; Seep opens its move list instead).
func _play_card(card: int) -> void:
	if not _my_turn(): return
	var seat: int = sim.actor()
	if variant == "seep":
		if card in sim.legal(seat):
			seep_card = card if seep_card != card else -1
			G.sfx("ui")
		return
	if variant == "teenpatti": return
	if not (card in sim.legal(seat)): G.sfx("thud"); return
	_send({a = "play", c = card})


func _seep_moves() -> Array:
	if seep_card < 0 or not _my_turn(): return []
	return sim.moves(sim.actor()).filter(func(m): return int(m.c) == seep_card)


static func _move_label(m: Dictionary) -> String:
	match String(m.k):
		"capture": return "CAPTURE %d" % ((m.take as Array).size() + (m.get("hs", []) as Array).size())
		"build": return "BUILD HOUSE %d" % int(m.h)
		"cement": return "CEMENT HOUSE %d" % int(m.h)
	return "THROW"


## The buttons on screen right now: [label, action, enabled].
func _actions() -> Array:
	if not _my_turn(): return []
	var seat: int = sim.actor()
	var out := []
	match variant:
		"teenpatti":
			var o: Array = sim.options(seat)
			for k in ["see", "chaal", "raise", "show", "pack"]:
				if k in o:
					var cost: int = sim.price(seat, k) if k in ["chaal", "show"] else (sim.stake * (2 if sim.players[seat].seen else 1) * 2 if k == "raise" else 0)
					out.append([k.to_upper() + ("  %d" % cost if cost > 0 else ""), {a = k}, true])
		"satte":
			if sim.legal(seat).is_empty(): out.append(["PASS", {a = "pass"}, true])
		"seep":
			if sim.phase == "bid":
				for v in sim.bids(seat): out.append(["BID %d" % v, {a = "bid", v = v}, true])
			else:
				for m in _seep_moves(): out.append([_move_label(m), {a = "move", m = m}, true])
		"dehla":
			if sim.phase == "trump":
				for s in 4: out.append([sim.SUITS[s] + "  " + sim.SUIT_NAMES[s], {a = "trump", s = s}, true])
	return out


func _unhandled_input(e: InputEvent) -> void:
	if sim == null: return
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.physical_keycode
		if k in [KEY_P, KEY_ESCAPE]: toggle_pause(); return
		if paused or results_shown: return
		if _curtain() and k in [KEY_SPACE, KEY_ENTER]: reveal_seat = sim.actor(); return
		var acts := _actions()
		var num: int = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9].find(k)
		if num >= 0 and num < acts.size(): _send(acts[num][1]); return
		if variant == "teenpatti" and _my_turn():
			var map := {KEY_S: "see", KEY_C: "chaal", KEY_R: "raise", KEY_W: "show", KEY_F: "pack"}
			if map.has(k):
				for x in acts: if String(x[1].a) == map[k]: _send(x[1])
			return
		if k == KEY_X and variant == "satte" and not acts.is_empty(): _send(acts[0][1]); return
		if _my_turn(): _key_nav(k)
	if e is InputEventJoypadButton and e.pressed:
		if e.button_index == JOY_BUTTON_START: toggle_pause(); return
		if paused or results_shown: return
		if _curtain() and e.button_index == JOY_BUTTON_A: reveal_seat = sim.actor(); return
		var acts := _actions()
		if e.button_index == JOY_BUTTON_Y and not acts.is_empty(): _send(acts[0][1]); return
		var map := {JOY_BUTTON_DPAD_LEFT: KEY_LEFT, JOY_BUTTON_DPAD_RIGHT: KEY_RIGHT, JOY_BUTTON_A: KEY_ENTER}
		if map.has(e.button_index) and _my_turn(): _key_nav(map[e.button_index])
	if e is InputEventMouseMotion: hover = _card_at(e.position)
	var click: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if click and not paused and not results_shown:
		var pos: Vector2 = e.position
		if _curtain(): reveal_seat = sim.actor(); return
		for b in btn_rects:
			if (b[0] as Rect2).has_point(pos): _send(b[1]); return
		var i := _card_at(pos)
		if i < 0: return
		var card: int = hand_rects[i][1]
		if e is InputEventScreenTouch and sel != i and variant != "seep":
			sel = i; G.sfx("ui"); return
		_play_card(card)


func _key_nav(k: int) -> void:
	var seat := _shown_seat()
	if seat < 0: return
	var hand: Array = sim.players[seat].hand
	if hand.is_empty(): return
	if sel < 0 or sel >= hand.size():
		var leg: Array = sim.legal(seat) if variant != "teenpatti" else []
		sel = hand.find(leg[0]) if not leg.is_empty() else 0
		if k in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D]: return
	if k in [KEY_LEFT, KEY_A]: sel = (sel + hand.size() - 1) % hand.size(); G.sfx("ui")
	elif k in [KEY_RIGHT, KEY_D]: sel = (sel + 1) % hand.size(); G.sfx("ui")
	elif k in [KEY_ENTER, KEY_SPACE, KEY_UP, KEY_W]: _play_card(int(hand[sel]))


func _card_at(pos: Vector2) -> int:
	for i in range(hand_rects.size() - 1, -1, -1):
		if (hand_rects[i][0] as Rect2).has_point(pos): return i
	return -1


func _input(e: InputEvent) -> void:
	if sim == null or not _touch(): return
	if e is InputEventScreenTouch and e.pressed and e.position.distance_to(pause_btn) < 34:
		toggle_pause(); get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- events
func _event(e: Array) -> void:
	var kind: String = e[0]
	stats[kind] = stats.get(kind, 0) + 1
	var P := func(i) -> String: return _nm(sim.players[int(i)])
	match kind:
		"deal": G.sfx("ui")
		"play": G.sfx("ui")
		"thulla":
			G.sfx("heavy")
			_toast("THULLA!  %s PICKS UP %d" % [P.call(e[2]), int(e[3])])
			_react(int(e[1]), "in_laughing", 2.0)
		"escape":
			G.sfx("ok")
			_toast("%s ESCAPES!  #%d" % [P.call(e[1]), int(e[2])])
			_react(int(e[1]), "win_clap", 2.5)
		"trump": G.sfx("ok"); _toast("TRUMP:  %s  %s" % [sim.SUIT_NAMES[int(e[2])], sim.SUITS[int(e[2])]])
		"kadi": G.sfx("surge"); _toast("KADI!  %s %s IS TRUMP" % [sim.SUITS[int(e[2])], sim.SUIT_NAMES[int(e[2])]]); _react(int(e[1]), "m_sit_talk", 2.0)
		"trick":
			G.sfx("ok")
			_toast("%s TAKES THE TRICK%s" % [P.call(e[1]), ("  ·  %d × 10!" % int(e[2])) if int(e[2]) > 0 else ""])
		"hand":
			G.sfx("surge" if bool(e[3]) else "vs")
			_toast(("MENDIKOT!!  " if bool(e[3]) else "") + "%s WINS THE HAND" % TEAM_NAME[int(e[1])])
		"bid": G.sfx("ok"); _toast("%s BIDS %d" % [P.call(e[1]), int(e[2])])
		"capture":
			G.sfx("surge" if bool(e[4]) else "ok")
			_toast(("SEEP!!  +50  " if bool(e[4]) else "") + "%s CAPTURES %d" % [P.call(e[1]), int(e[3])])
			if bool(e[4]): _react(int(e[1]), "win_cheer", 2.5)
		"build": G.sfx("ok"); _toast("%s BUILDS A HOUSE OF %d" % [P.call(e[1]), int(e[3])])
		"cement": G.sfx("ok"); _toast("%s CEMENTS THE HOUSE OF %d" % [P.call(e[1]), int(e[3])])
		"deal_end": G.sfx("vs"); _toast("DEAL:  %d — %d    MATCH:  %d — %d" % [int(e[1]), int(e[2]), int(e[3]), int(e[4])])
		"see": _toast("%s LOOKS AT THEIR CARDS" % P.call(e[1]))
		"pack": G.sfx("thud"); _toast("%s PACKS" % P.call(e[1]))
		"bet":
			G.sfx("grab")
			_toast("%s:  %s  %d" % [P.call(e[1]), String(e[2]).to_upper(), int(e[3])])
		"show": G.sfx("surge"); _toast("SHOW!")
		"pot":
			G.sfx("vs")
			var ws: Array = e[1]
			_toast("%s WINS THE POT  %d%s" % [P.call(ws[0]), int(e[2]), ("  ·  " + String(e[3])) if String(e[3]) != "" else ""])
			for w in ws: _react(int(w), "win_excited", 2.5)
		"pass": _toast("%s PASSES" % P.call(e[1]))
		"done":
			if not results_shown:
				results_shown = true
				for s in sim.winner_seats(): _react(int(s), ["win_cheer", "win_clap", "win_excited"][int(s) % 3], 99.0); _voice(int(s), "win")
				get_tree().create_timer(2.2).timeout.connect(_show_results)


func _react(seat: int, clip: String, t: float) -> void:
	if seat < 0 or seat >= rigs.size() or not ClipLib.has(clip): return
	react[seat] = [clip, t]
	rigs[seat].set_meta("t", 0.0)


func _voice(seat: int, kind: String) -> void:
	var s := Voices.get_sound(sim.players[seat].C, kind)
	if s == null: return
	var p := AudioStreamPlayer.new(); p.stream = s; p.volume_db = -6.0
	add_child(p); p.play(); p.finished.connect(p.queue_free)


# ---------------------------------------------------------------- table layout
## Everything lying on the felt now: [key, card (-1 back), local position (x across, z toward you), from seat].
func _layout() -> Array:
	var out := []
	var view := _view_seat()
	var toward := func(seat: int) -> Vector3:   # a seat's direction in the "your view" frame
		var a: float = -(seat - view) * TAU / sim.n
		return Vector3(sin(a), 0, cos(a))
	match variant:
		"thulla", "dehla", "kadi":
			var trick: Array = sim.trick
			var gather: bool = sim.phase == "trick_end"
			if gather: trick = sim.last_trick
			for e in trick:
				var spot: Vector3 = toward.call(int(e[0])) * R * 0.4
				if gather and sim.wait < 0.6:
					var to := -1
					if variant == "thulla": to = sim.last_pickup
					else: to = sim.last_winner
					spot = toward.call(to) * R * 0.75 if to >= 0 else Vector3(0, 0, 0)
				out.append(["t%d" % int(e[1]), int(e[1]), spot, int(e[0])])
		"satte":
			for s in 4:
				var row: Array = sim.rows[s]
				if int(row[0]) < 0: continue
				for r in range(int(row[0]), int(row[1]) + 1):
					out.append(["r%d" % (s * 13 + r), s * 13 + r, Vector3((r - 5) * 0.115, 0, (s - 1.5) * 0.34), -1])
		"seep":
			var loose: Array = sim.table
			var per := 7
			for i in loose.size():
				var row := i / per
				var col := i % per
				var cnt := mini(per, loose.size() - row * per)
				out.append(["s%d" % int(loose[i]), int(loose[i]), Vector3((col - (cnt - 1) / 2.0) * 0.23, 0, -0.25 + row * 0.33), -1])
			var hx := 0
			for h in sim.houses:
				var k := 0
				for c in h.cards:
					out.append(["h%d" % int(c), int(c), Vector3(-0.5 + hx * 0.35 + k * 0.02, k * 0.004, 0.55 + k * 0.03), -1])
					k += 1
				hx += 1
		"teenpatti":
			for s in sim.in_hand:
				var p = sim.players[s]
				var d: Vector3 = toward.call(int(s))
				var across := Vector3(d.z, 0, -d.x)
				var showing: bool = int(s) in sim.reveal
				for k in p.hand.size():
					var c: int = p.hand[k] if showing else -1
					out.append(["p%d_%d_%d" % [int(s), k, int(showing)], c, d * R * 0.55 + across * (k - 1) * 0.14, int(s)])
	return out


func _animate(dt: float) -> void:
	var view := _view_seat()
	var face := _seat_angle(view)
	var rot := Basis(Vector3.UP, face)
	var want := {}
	for it in _layout():
		var key: String = it[0]
		want[key] = true
		var pos: Vector3 = rot * (it[2] as Vector3) + Vector3(0, TABLE_Y + 0.004, 0)
		if not items.has(key):
			var n := _card3d(int(it[1]))
			var from := int(it[3])
			n.position = (seat_dir(from) * (R + 0.1) + Vector3(0, TABLE_Y + 0.35, 0)) if from >= 0 else pos + Vector3(0, 0.3, 0)
			n.rotation.y = face
			items[key] = n
		var node: Node3D = items[key]
		node.position = node.position.lerp(pos, clampf(dt * 9.0, 0.0, 1.0))
		node.rotation.y = lerp_angle(node.rotation.y, face, clampf(dt * 9.0, 0.0, 1.0))
	for key in items.keys():
		if not want.has(key): (items[key] as Node).queue_free(); items.erase(key)
	# the other players' hands, fanned face down in front of them
	var shown := _shown_seat()
	var cur := _curtain()
	for s in sim.n:
		var cnt: int = sim.players[s].hand.size() if variant != "teenpatti" else 0
		var d := seat_dir(s)
		var across := Vector3(d.z, 0, -d.x)
		var row: Array = backs[s]
		var vis := mini(cnt, 13)
		for k in 13:
			var b: Node3D = row[k]
			b.visible = k < vis and (s != shown or cur)
			if b.visible:
				var u := (k - (vis - 1) / 2.0) * 0.035
				b.position = d * (R * 0.8) + across * u + Vector3(0, TABLE_Y + 0.003 + k * 0.0006, 0)
				b.rotation.y = atan2(d.x, d.z) + u * 1.2
	# Teen Patti: the pot as a stack of chips
	if variant == "teenpatti":
		var want_chips := clampi(sim.pot / 25, 0, 40)
		while chip_nodes.size() < want_chips:
			var k := chip_nodes.size()
			var c := _cyl(0.035, 0.012, _mat([Color(0.9, 0.2, 0.25), Color(0.2, 0.5, 0.95), GOLD, Color(0.95, 0.95, 0.95)][k % 4], 0.4), Vector3.ZERO)
			c.position = Vector3(cos(k * 2.4) * 0.09 * (k % 3), TABLE_Y + 0.008 + (k / 3) * 0.013, sin(k * 2.4) * 0.09 * (k % 3))
			chip_nodes.append(c)
		while chip_nodes.size() > want_chips: (chip_nodes.pop_back() as Node).queue_free()
	# whose turn
	var a: int = sim.actor()
	turn_ring.visible = a >= 0
	if a >= 0:
		turn_ring.position = seat_dir(a) * (R * 0.62) + Vector3(0, TABLE_Y + 0.004, 0)
		turn_ring.scale = Vector3(1, 0.2, 1) * (1.0 + 0.1 * sin(Time.get_ticks_msec() / 140.0))
	# the trump suit printed big on the felt
	var tr := -1
	if variant in ["dehla", "kadi"]: tr = sim.trump
	if tr >= 0:
		center_lbl.text = sim.SUITS[tr]
		center_lbl.modulate = Color(Color(0.75, 0.12, 0.15) if tr in [1, 2] else Color(0.02, 0.1, 0.06), 0.55)
		center_lbl.rotation.y = face
	else:
		center_lbl.modulate.a = 0.0
	# seated players
	for s in sim.n:
		var rig = rigs[s]
		rig.visible = s != view
		(tags[s] as Label3D).visible = s != view
		var t: float = rig.get_meta("t", 0.0) + dt
		rig.set_meta("t", t)
		var r: Array = react[s]
		var clip := "m_sit"
		if r[1] > 0.0:
			r[1] -= dt; clip = r[0]
		elif s == a and fmod(t, 5.0) < 2.0:
			clip = "m_sit_talk"
		if not ClipLib.has(clip): clip = "idle_relaxed"
		var seated := clip.begins_with("m_sit")
		rig.set_clip(clip, fmod(t, Fighter._len(clip)), true, false)
		rig.apply_pose(sim.players[s].C.pose.guard, not seated)
		var d := seat_dir(s)
		rig.position = d * ((R + 0.24) if seated else (R + 0.7)) + Vector3(0, 0.05 if seated else 0.0, 0)
	cam_angle = lerp_angle(cam_angle, face, clampf(dt * 3.0, 0.0, 1.0))
	var cd := Vector3(sin(cam_angle), 0, cos(cam_angle))
	cam.position = cd * (R + 1.0) + Vector3(0, 2.15 + R * 0.25, 0)
	cam.look_at(Vector3(0, TABLE_Y + 0.05, 0) - cd * 0.3, Vector3.UP)


# ---------------------------------------------------------------- HUD
func _style(kind: String) -> StyleBoxFlat:
	if _sb.has(kind): return _sb[kind]
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(9)
	match kind:
		"face": sb.bg_color = Color(0.98, 0.97, 0.93); sb.border_color = Color(0.7, 0.68, 0.64); sb.set_border_width_all(1)
		"back": sb.bg_color = Color(0.42, 0.22, 0.72); sb.border_color = Color(0.95, 0.95, 1.0); sb.set_border_width_all(3)
		"hl": sb.bg_color = Color(0, 0, 0, 0); sb.border_color = GOLD; sb.set_border_width_all(4)
		"dim": sb.bg_color = Color(0.05, 0.03, 0.1, 0.5)
		"panel": sb.bg_color = Color(0.04, 0.03, 0.08, 0.82); sb.border_color = Color(0.58, 0.3, 0.85); sb.set_border_width_all(2); sb.set_corner_radius_all(12)
		"btn": sb.bg_color = Color(0.13, 0.55, 0.7, 0.95); sb.border_color = Color(0.85, 0.95, 1.0); sb.set_border_width_all(2); sb.set_corner_radius_all(10)
		"btn2": sb.bg_color = Color(0.55, 0.2, 0.25, 0.95); sb.border_color = Color(1.0, 0.85, 0.85); sb.set_border_width_all(2); sb.set_corner_radius_all(10)
	if kind in ["face", "back"]:
		sb.shadow_color = Color(0, 0, 0, 0.35); sb.shadow_size = 6
	_sb[kind] = sb
	return sb


func _draw_card(r: Rect2, card: int, dim := false, hl := false) -> void:
	if card < 0:
		hud.draw_style_box(_style("back"), r)
		var m := r.grow(-r.size.x * 0.18)
		var asp := float(mark.get_width()) / mark.get_height()
		var mw := minf(m.size.x, m.size.y * asp)
		hud.draw_texture_rect(mark, Rect2(m.get_center() - Vector2(mw, mw / asp) / 2.0, Vector2(mw, mw / asp)), false, Color(1, 1, 1, 0.9))
		if hl: hud.draw_style_box(_style("hl"), r.grow(2))
		return
	hud.draw_style_box(_style("face"), r)
	var ink := RED_INK if sim.is_red(card) else BLACK_INK
	var w := r.size.x
	var rank: String = sim.RANKS[sim.rank_of(card)]
	var suit: String = sim.SUITS[sim.suit_of(card)]
	var fs := int(w * 0.27)
	hud.draw_string(font, r.position + Vector2(w * 0.07, fs * 1.05), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	hud.draw_string(suitf, r.position + Vector2(w * 0.08, fs * 2.0), suit, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.85), ink)
	var court: bool = sim.rank_of(card) >= 9
	var big := int(w * (0.62 if not court else 0.5))
	hud.draw_string(suitf, Vector2(r.position.x, r.get_center().y + big * 0.36), suit, HORIZONTAL_ALIGNMENT_CENTER, w, big, Color(ink, 0.92))
	if court: hud.draw_string(font, Vector2(r.position.x, r.end.y - w * 0.1), rank, HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.22), Color(ink, 0.55))
	if dim: hud.draw_style_box(_style("dim"), r)
	if hl: hud.draw_style_box(_style("hl"), r.grow(2))


func _status(p) -> String:
	match variant:
		"teenpatti":
			if not (p.seat in sim.in_hand): return "PACKED" if not p.out else "OUT"
			return "%d CHIPS · %s" % [p.chips, "SEEN" if p.seen else "BLIND"]
		"thulla", "satte":
			if p.place > 0: return ("BHABHI" if variant == "thulla" and p.seat == sim.bhabhi else "#%d  OUT" % p.place)
			return "%d CARDS" % p.hand.size()
	return "%d CARDS" % p.hand.size()


func _draw_hud() -> void:
	var s := hud.size
	var ink := Color(0.95, 0.96, 1.0)
	hand_rects = []; btn_rects = []
	var a: int = sim.actor()
	# players, top left
	var ph := 32.0 if sim.n > 5 else 38.0
	for i in sim.n:
		var p = sim.players[i]
		var box := Rect2(Vector2(16, 16 + i * (ph + 4)), Vector2(300, ph))
		hud.draw_style_box(_style("panel"), box)
		hud.draw_rect(Rect2(box.position, Vector2(7, box.size.y)), _col(i))
		var on: bool = i == a
		hud.draw_string(font, box.position + Vector2(16, ph * 0.68), _nm(p) + ("  ◂" if on else ""), HORIZONTAL_ALIGNMENT_LEFT, 150, int(ph * 0.46), _col(i).lightened(0.35) if not on else GOLD)
		hud.draw_string(small, box.position + Vector2(160, ph * 0.68), _status(p), HORIZONTAL_ALIGNMENT_RIGHT, 130, int(ph * 0.44), ink)
	# the game's badge, top right
	_draw_badge(s, ink)
	# what's happening
	var msg := ""
	if sim.phase == "done": msg = TITLES[variant] + "  ·  GAME OVER"
	elif a < 0: msg = ""
	elif _my_turn() and not autoplay:
		msg = "YOUR TURN"
		if variant == "seep" and sim.phase == "bid": msg = "BID A VALUE YOU HOLD (9–13)"
		elif variant == "dehla" and sim.phase == "trump": msg = "PICK THE TRUMP"
		elif variant == "seep" and seep_card < 0: msg = "PICK A CARD, THEN WHAT TO DO WITH IT"
		if local_all: msg = _nm(sim.players[a]) + ":  " + msg
	else:
		msg = "%s IS PLAYING" % _nm(sim.players[a])
	hud.draw_string(font, Vector2(0, 50), msg, HORIZONTAL_ALIGNMENT_CENTER, s.x, 30, _col(maxi(a, 0)).lightened(0.35))
	if net != null and a >= 0 and sim.players[a].human and not _my_turn() and sim.idle > sim.TURN_TIME - 8.0:
		hud.draw_string(small, Vector2(0, 76), "auto-play in %d" % ceili(sim.TURN_TIME - sim.idle), HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(1, 0.7, 0.5))
	# your hand
	var seat := _shown_seat()
	var ch := clampf(s.y * 0.24, 104.0, 190.0)
	if seat >= 0 and not _curtain():
		var hand: Array = sim.players[seat].hand
		var n := hand.size()
		var cw := ch * 0.7
		if variant == "teenpatti": cw *= 1.15; ch *= 1.15
		var step := minf(cw * 0.66, (s.x * 0.8 - cw) / maxf(1.0, n - 1))
		var x0 := (s.x - (cw + step * (n - 1))) / 2.0
		var playing: bool = _my_turn() and variant != "teenpatti"
		var legal: Array = sim.legal(seat) if playing and sim.has_method("legal") else []
		if sel >= n: sel = -1
		for i in n:
			var card: int = hand[i]
			var off := (i - (n - 1) / 2.0)
			var on: bool = ((i == hover and not _touch()) or i == sel or card == seep_card) and card in legal
			var lift := 26.0 if on else 0.0
			var r := Rect2(Vector2(x0 + i * step, s.y - ch - 30 + off * off * (1.6 if n < 16 else 0.4) - lift), Vector2(cw, ch))
			hand_rects.append([r, card])
			# Teen Patti: blind until you look (the cards stay face down)
			var face := card
			if variant == "teenpatti" and not sim.players[seat].seen and not (seat in sim.reveal): face = -1
			_draw_card(r, face, playing and not (card in legal), on)
		if variant == "teenpatti" and seat in sim.in_hand and not sim.players[seat].seen:
			hud.draw_string(font, Vector2(0, s.y - ch - 46), "BLIND — you haven't looked yet", HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, GOLD)
	# buttons for the moves that aren't "play a card"
	var acts := _actions()
	if not acts.is_empty() and not autoplay:
		var bw := 210.0 if variant != "teenpatti" else 170.0
		var bh := 52.0
		var cols := mini(acts.size(), 5)
		var total := cols * bw + (cols - 1) * 12.0
		var y0 := s.y - ch - 46 - bh * ceili(acts.size() / float(cols)) - 20.0
		for i in acts.size():
			var r := Rect2(Vector2((s.x - total) / 2.0 + (i % cols) * (bw + 12.0), y0 + (i / cols) * (bh + 10.0)), Vector2(bw, bh))
			btn_rects.append([r, acts[i][1]])
			var danger := String(acts[i][1].get("a", "")) in ["pack", "pass"]
			hud.draw_style_box(_style("btn2" if danger else "btn"), r)
			var label: String = acts[i][0]
			if not _touch() and acts.size() <= 9: label = "%d  %s" % [i + 1, label]
			hud.draw_string(font if variant != "dehla" else suitf, Vector2(r.position.x, r.position.y + bh * 0.66), label, HORIZONTAL_ALIGNMENT_CENTER, bw, 20, Color.WHITE)
	if toast_t > 0.0:
		hud.draw_string(font, Vector2(0, s.y * 0.2), toast, HORIZONTAL_ALIGNMENT_CENTER, s.x, 38, Color(1, 1, 1, clampf(toast_t / 0.4, 0.0, 1.0)))
	if _curtain():
		hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.02, 0.08, 0.97))
		var who = sim.players[sim.actor()]
		hud.draw_string(font, Vector2(0, s.y * 0.42), "PASS TO %s" % _nm(who), HORIZONTAL_ALIGNMENT_CENTER, s.x, 56, _col(sim.actor()).lightened(0.3))
		hud.draw_string(small, Vector2(0, s.y * 0.42 + 50), "tap (or press ENTER) to show your cards", HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, ink)
	if not _touch():
		var help: String = {"thulla": "click / ← → ENTER  play a card", "satte": "click / ← → ENTER  play   ·   X  pass",
			"dehla": "click / ← → ENTER  play   ·   1-4  trump", "kadi": "click / ← → ENTER  play",
			"seep": "click a card, then 1-9 / click what to do with it", "teenpatti": "S see  ·  C chaal  ·  R raise  ·  W show  ·  F pack"}[variant]
		hud.draw_string(small, Vector2(0, s.y - 6), help + "   ·   P  pause", HORIZONTAL_ALIGNMENT_CENTER, s.x, 15, Color(0.8, 0.82, 0.9, 0.6))
	else:
		pause_btn = Vector2(s.x - 170, 40)
		hud.draw_circle(pause_btn, 26, Color(0.58, 0.3, 0.85, 0.3)); hud.draw_arc(pause_btn, 26, 0, TAU, 32, Color(0.58, 0.3, 0.85), 3)
		hud.draw_string(font, pause_btn + Vector2(-26, 8), "II", HORIZONTAL_ALIGNMENT_CENTER, 52, 20, Color.WHITE)


func _draw_badge(s: Vector2, ink: Color) -> void:
	var bc := Vector2(s.x - 82, 74)
	hud.draw_circle(bc, 54, Color(0.04, 0.03, 0.08, 0.85))
	hud.draw_arc(bc, 54, 0, TAU, 48, GOLD, 3.0)
	var big := ""
	var big_col := GOLD
	var line := ""
	var big_font := font
	match variant:
		"dehla", "kadi":
			if sim.trump >= 0:
				big = sim.SUITS[sim.trump]; big_font = suitf
				big_col = Color(1.0, 0.3, 0.35) if sim.trump in [1, 2] else ink
				line = ("KADI  ·  " if variant == "kadi" else "TRUMP  ·  ") + sim.SUIT_NAMES[sim.trump]
			else:
				big = "?"; line = "TRUMP HIDDEN" if variant == "kadi" else "NO TRUMP YET"
		"seep": big = str(sim.bid) if sim.bid > 0 else "?"; line = "BID  ·  DEAL %d / %d" % [sim.deal_n, sim.DEALS]
		"teenpatti": big = str(sim.pot); line = "POT  ·  STAKE %d  ·  HAND %d / %d" % [sim.stake, sim.hand_n, sim.HANDS]
		"satte": big = "7"; big_col = RED_INK.lightened(0.3); line = "SEVENS"
		"thulla": big = "♠"; big_font = suitf; big_col = ink; line = "A♠ STARTS"
	hud.draw_string(big_font, bc + Vector2(-54, 18), big, HORIZONTAL_ALIGNMENT_CENTER, 108, 46 if big.length() < 3 else 30, big_col)
	hud.draw_string(small, Vector2(s.x - 330, bc.y + 76), line, HORIZONTAL_ALIGNMENT_RIGHT, 310, 16, GOLD)
	# team scores
	if variant in ["dehla", "kadi"] or variant == "seep":
		for t in 2:
			var box := Rect2(Vector2(s.x - 330, 150 + t * 60), Vector2(310, 52))
			hud.draw_style_box(_style("panel"), box)
			hud.draw_rect(Rect2(box.position, Vector2(7, box.size.y)), TEAM_COL[t] if _teams() else _col(t))
			var nm: String = TEAM_NAME[t] if _teams() else _nm(sim.players[t])
			hud.draw_string(font, box.position + Vector2(16, 33), nm, HORIZONTAL_ALIGNMENT_LEFT, 120, 18, (TEAM_COL[t] if _teams() else _col(t)).lightened(0.3))
			var txt := ""
			if variant == "seep":
				var live: int = sim.deal_pts[t] if sim.phase in ["deal", "bid", "play"] else 0   # already banked at the end of a deal
				txt = "%d PTS  ·  %d SEEP" % [sim.team_pts[t] + live, sim.seeps[t]]
			else: txt = "10s %d  ·  TRICKS %d  ·  %d/%d" % [sim.tens[t], sim.tricks[t], sim.score[t], sim.TARGET]
			hud.draw_string(small, box.position + Vector2(120, 33), txt, HORIZONTAL_ALIGNMENT_RIGHT, 180, 17, ink)


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
	if net != null: v.add_child(ui.lbl("The game keeps going for everyone else.", 18, small, Color(0.8, 0.82, 0.9)))
	var resume: Button = ui.big_btn("RESUME", Color(0.13, 0.78, 0.92), toggle_pause)
	v.add_child(resume)
	if ui.has_method("tutorial_toggle_btn"): v.add_child(ui.tutorial_toggle_btn())
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
	v.add_theme_constant_override("separation", 8)
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
	var mine := _shown_seat()
	var ws: Array = sim.winner_seats()
	var title := ""
	match variant:
		"thulla": title = ("%s IS THE BHABHI!" % _nm(sim.players[sim.bhabhi])) if sim.bhabhi >= 0 else "EVERYONE GOT AWAY!"
		"dehla", "kadi", "seep":
			var w := int(ws[0]) % 2 if not ws.is_empty() else 0
			title = "%s WINS!" % (TEAM_NAME[w] if _teams() else _nm(sim.players[w]))
		_: title = "%s WINS!" % _nm(sim.players[int(ws[0])]) if not ws.is_empty() else "GAME OVER"
	if not local_all and mine >= 0 and variant != "thulla": title = ("YOU WIN!  ·  " if mine in ws else "YOU LOSE  ·  ") + title
	if not local_all and mine >= 0 and variant == "thulla":
		title = "YOU'RE THE BHABHI!" if mine == sim.bhabhi else ("YOU GOT AWAY!  ·  " + title)
	v.add_child(ui.lbl(title, 40, font, GOLD, 8))
	match variant:
		"dehla", "kadi":
			v.add_child(ui.lbl("%d  —  %d   ·   %d HANDS" % [sim.score[0], sim.score[1], sim.hand_n], 26, font, Color.WHITE))
		"seep":
			v.add_child(ui.lbl("%d  —  %d   ·   SEEPS %d — %d" % [sim.team_pts[0], sim.team_pts[1], sim.seeps[0], sim.seeps[1]], 26, font, Color.WHITE))
	for line in sim.result_lines():
		v.add_child(ui.lbl("%s   %s" % [line[0], _nm(sim.players[int(line[1])])], 22, small, _col(int(line[1])).lightened(0.3)))
	if variant == "teenpatti": v.add_child(ui.lbl("Office chips only — just for fun.", 16, small, Color(0.75, 0.78, 0.88)))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 14)
	if net != null:
		btns.add_child(ui.big_btn("BACK TO LOBBY", Color(0.13, 0.78, 0.92), func(): finished.emit(); G.lobby.back_to_lobby()))
		btns.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), func(): finished.emit(); G.lobby.leave()))
	else:
		var C: Dictionary = sim.players[0].C
		var vr := variant
		btns.add_child(ui.big_btn("PLAY AGAIN", Color(0.13, 0.78, 0.92), func():
			finished.emit()
			if ui.has_method("show_card_options"): ui.show_card_options(vr, C)
			else: ui.show_title()))
		btns.add_child(ui.big_btn("MAIN MENU", Color(0.55, 0.62, 0.75), func(): finished.emit(); ui.show_title()))
	v.add_child(btns)
	_center(panel)


# ---------------------------------------------------------------- tests
## --autotest=cards --variant=X: CPUs play every seat. Shots: the opening, our turn (with any move buttons),
## mid-game, a late moment, the result.
func autotest(shot: Callable) -> void:
	var tree: SceneTree = G.get_tree()
	sim.think = 0.35
	var t := 0
	while sim.actor() < 0 and t < 800:
		await tree.process_frame; t += 1
	for k in 20: await tree.process_frame
	await shot.call("cards_%s_start" % variant)
	# our own turn, held for a look at the hand and the buttons
	autoplay = false
	t = 0
	while not _my_turn() and t < 6000 and sim.phase != "done":
		await tree.process_frame; t += 1
	if variant == "seep" and sim.phase == "play":
		var leg: Array = sim.legal(sim.actor())
		if not leg.is_empty(): seep_card = int(leg[0])
	hover = -1; sel = 0
	for k in 15: await tree.process_frame
	await shot.call("cards_%s_myturn" % variant)
	seep_card = -1
	autoplay = true
	Engine.time_scale = 3.0
	for k in 240: await tree.process_frame
	Engine.time_scale = 1.0
	for k in 10: await tree.process_frame
	await shot.call("cards_%s_mid" % variant)
	Engine.time_scale = 8.0
	sim.think = 0.15
	t = 0
	while sim.phase != "done" and t < 60000:
		await tree.process_frame; t += 1
	Engine.time_scale = 1.0
	await tree.create_timer(3.2).timeout
	await shot.call("cards_%s_result" % variant)
	print("AUTOTEST cards %s players=%d phase=%s steps=%d illegal=%d winners=%s events=%d" % [variant, sim.n, sim.phase, sim.steps, sim.illegal, sim.winner_seats(), stats.size()])
