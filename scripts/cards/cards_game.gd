class_name CardsGame
extends Node
## BNB Rung (Court Piece): four colleagues round a card table in the break room, two teams of two.
## Runs a CardsSim (the rules) and draws it: seated players, cards played onto the felt, your hand as a fan
## at the bottom of the screen, trump picker, scores. Online: the host runs the sim and sends each guest a
## snapshot with ONLY their own hand; guests send the card (or trump) they pick.

signal finished

const CardsSim = preload("res://scripts/cards/cards_sim.gd")
const TEAM_COL := [Color(0.62, 0.38, 1.0), Color(0.13, 0.78, 0.92)]
const TEAM_NAME := ["TEAM BIT", "TEAM BYTE"]
const RED_INK := Color(0.85, 0.1, 0.17)
const BLACK_INK := Color(0.08, 0.08, 0.13)
const TABLE_Y := 0.76

var G
var sim                            # CardsSim
var world: Node3D
var env: Environment
var cam: Camera3D
var layer: CanvasLayer
var hud: Control
var font: Font
var small: Font
var suitf: Font                    # DejaVu: has the ♠ ♥ ♦ ♣ glyphs
var mark: Texture2D
var rigs: Array = []
var tags: Array = []
var react: Array = []              # per seat: [clip, time left]
var backs: Array = []              # per seat: card-back nodes lying in front of them
var table_nodes := {}              # card -> {node, seat, yaw}
var turn_ring: MeshInstance3D
var trump_lbl: Label3D
var my_slot := 0
var local_all := false             # pass & play: all four seats are played on this device
var reveal_seat := -1              # pass & play: whose cards are showing (curtain otherwise)
var autoplay := false
var stats := {}
var paused := false
var results_shown := false
var toast := ""
var toast_t := 0.0
var peek := false                  # showing the last trick
var sel := -1                      # keyboard / gamepad / touch selected card index
var hover := -1
var hand_rects: Array = []         # [Rect2, card] for the fan, drawn order
var trump_rects: Array = []        # [Rect2, suit]
var peek_btn := Rect2()
var trump_sel := 0
var cam_angle := 0.0
var _act_t := 0.0
var _sb := {}

# multiplayer
var net: Party = null
var guest := false
var pid_slot := {}                 # host: pid -> lobby slot
var last_rev := -1


func start(g, people: Array, seed: int, slot := 0, pass_play := false) -> void:
	G = g
	my_slot = slot; local_all = pass_play
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	suitf = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	mark = load("res://assets/brand/bnb_mark_trim.png")
	sim = CardsSim.new()
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


# ---------------------------------------------------------------- 3D break room
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


static func seat_dir(seat: int) -> Vector3:
	var a := -seat * PI / 2.0
	return Vector3(sin(a), 0, cos(a))


static func _seat_angle(seat: int) -> float:
	return -seat * PI / 2.0


## A Kenney furniture model stretched to a footprint (x, z) and height, standing on the floor.
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
		for i in mesh.get_surface_count():   # Kenney pastels, toned down to read under warm light
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
	env.ambient_light_color = Color(0.62, 0.55, 0.62); env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = 1.0
	env.glow_enabled = true; env.glow_intensity = 0.25; env.glow_hdr_threshold = 1.3
	we.environment = env
	world.add_child(we)
	# a warm pendant lamp over the table, a cooler fill from the window
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 3.0, 0); lamp.rotation.x = -PI / 2
	lamp.spot_range = 6.0; lamp.spot_angle = 42.0; lamp.light_energy = 3.2; lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.shadow_enabled = true
	world.add_child(lamp)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-40), deg_to_rad(140), 0); fill.light_energy = 0.35; fill.light_color = Color(0.7, 0.8, 1.0)
	world.add_child(fill)
	_box(Vector3(0.5, 0.25, 0.5), _mat(Color(0.12, 0.1, 0.1), 0.4), Vector3(0, 2.75, 0))            # lamp shade
	_box(Vector3(0.42, 0.02, 0.42), _mat(Color(1.0, 0.85, 0.6), 0.3, 2.5), Vector3(0, 2.62, 0))     # its glowing bulb disc
	_box(Vector3(0.02, 1.2, 0.02), _mat(Color(0.1, 0.1, 0.1)), Vector3(0, 3.45, 0))
	# room: floor, walls in BNB purple, a kitchen counter, fridge, coffee machine, plants
	_box(Vector3(12, 0.1, 12), _mat(Color(0.34, 0.24, 0.17), 0.7), Vector3(0, -0.05, 0))
	for k in 8:   # floorboards
		_box(Vector3(12, 0.005, 0.02), _mat(Color(0.22, 0.15, 0.1), 0.8), Vector3(0, 0.001, -6 + k * 1.5 + 0.75))
	var wall := _mat(Color(0.22, 0.16, 0.3), 0.85)
	_box(Vector3(12, 4, 0.2), wall, Vector3(0, 2, -5.0)); _box(Vector3(12, 4, 0.2), wall, Vector3(0, 2, 5.0))
	_box(Vector3(0.2, 4, 12), wall, Vector3(-5.0, 2, 0)); _box(Vector3(0.2, 4, 12), wall, Vector3(5.0, 2, 0))
	for side in [Vector3(0, 1.0, -4.88), Vector3(0, 1.0, 4.88)]:
		_box(Vector3(12, 0.08, 0.06), _mat(Color(0.55, 0.32, 0.9), 0.4, 0.8), side)                   # neon strip
	_model("kitchenBar", Vector3(-2.2, 0, -4.4), 0.0, Vector3(3.2, 0.95, 0.8))
	_model("kitchenCoffeeMachine", Vector3(-2.8, 0.95, -4.5), 0.0, Vector3(0.4, 0.45, 0.35))
	_model("kitchenFridge", Vector3(0.2, 0, -4.4), 0.0, Vector3(0.9, 2.0, 0.8))
	_model("plantSmall1", Vector3(4.2, 0, -4.2), 0.0, Vector3(0.6, 1.2, 0.6))
	_model("plantSmall2", Vector3(-4.2, 0, 4.2), 0.0, Vector3(0.6, 1.2, 0.6))
	_model("loungeSofa", Vector3(3.2, 0, 4.2), PI, Vector3(2.4, 0.9, 0.95))
	var sp := Sprite3D.new(); sp.texture = mark; sp.pixel_size = 1.4 / mark.get_height(); sp.shaded = false
	sp.position = Vector3(2.4, 2.2, -4.88); sp.modulate = Color(1.3, 1.3, 1.3)
	world.add_child(sp)
	# the card table: green felt in a wooden rim on four legs
	_box(Vector3(1.8, 0.05, 1.8), _mat(Color(0.06, 0.34, 0.2), 0.95), Vector3(0, TABLE_Y - 0.025, 0))
	var wood := _mat(Color(0.3, 0.17, 0.08), 0.45)
	for s in [-1.0, 1.0]:
		_box(Vector3(1.96, 0.07, 0.08), wood, Vector3(0, TABLE_Y - 0.01, s * 0.94))
		_box(Vector3(0.08, 0.07, 1.96), wood, Vector3(s * 0.94, TABLE_Y - 0.01, 0))
		for t in [-1.0, 1.0]:
			_box(Vector3(0.07, TABLE_Y - 0.05, 0.07), wood, Vector3(s * 0.8, (TABLE_Y - 0.05) / 2.0, t * 0.8))
	var felt_mark := Sprite3D.new(); felt_mark.texture = mark; felt_mark.pixel_size = 0.5 / mark.get_height()
	felt_mark.rotation.x = -PI / 2; felt_mark.position = Vector3(0, TABLE_Y + 0.002, 0); felt_mark.modulate = Color(1, 1, 1, 0.16)
	world.add_child(felt_mark)
	trump_lbl = Label3D.new(); trump_lbl.font = suitf; trump_lbl.font_size = 200; trump_lbl.outline_size = 0
	trump_lbl.rotation.x = -PI / 2; trump_lbl.position = Vector3(0, TABLE_Y + 0.004, 0); trump_lbl.pixel_size = 0.0016
	trump_lbl.modulate = Color(1, 1, 1, 0.0)
	world.add_child(trump_lbl)
	turn_ring = MeshInstance3D.new()
	var tor := TorusMesh.new(); tor.inner_radius = 0.13; tor.outer_radius = 0.155
	turn_ring.mesh = tor; turn_ring.material_override = _mat(Color(1.0, 0.75, 0.25), 0.3, 1.1)
	world.add_child(turn_ring)
	# players, chairs, name tags, the backs of their cards
	for s in 4:
		var p = sim.players[s]
		var d := seat_dir(s)
		_model("chairCushion", d * 1.18, atan2(d.x, d.z) + PI, Vector3(0.55, 0.95, 0.55))
		var rig := Main.make_rig(p.C, 0)
		world.add_child(rig)
		rig.position = d * 1.12 + Vector3(0, 0.05, 0)
		rig.rotation.y = atan2(-d.x, -d.z)
		rig.set_meta("t", randf() * 3.0)
		rigs.append(rig); react.append(["", 0.0])
		var tag := Label3D.new()
		tag.text = _nm(p); tag.font = font; tag.font_size = 40; tag.outline_size = 8
		tag.modulate = TEAM_COL[CardsSim.team_of(s)].lightened(0.25); tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = d * 1.15 + Vector3(0, 1.5 * float(p.C.get("scale", 1.0)), 0); tag.pixel_size = 0.0018
		world.add_child(tag)
		tags.append(tag)
		var row := []
		for k in 13:
			var b := _card3d(-1)
			b.visible = false
			row.append(b)
		backs.append(row)
	cam = Camera3D.new(); cam.fov = 52; cam.far = 60
	cam.environment = env   # the camera's own environment wins over any other in the scene
	world.add_child(cam); cam.current = true


## A card on the table: a thin white slab with its rank and suit, or the BNB back. card -1 = back.
func _card3d(card: int) -> Node3D:
	var n := Node3D.new()
	world.add_child(n)
	var back := card < 0
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.22, 0.004, 0.31)
	body.mesh = bm
	body.material_override = _mat(Color(0.97, 0.96, 0.92) if not back else Color(0.36, 0.18, 0.6), 0.5)
	n.add_child(body)
	if back:
		var inner := _box(Vector3(0.19, 0.0045, 0.28), _mat(Color(0.48, 0.26, 0.8), 0.5), Vector3.ZERO, n)
		inner.position.y = 0.0004
		var s := Sprite3D.new(); s.texture = mark; s.pixel_size = 0.12 / mark.get_height(); s.shaded = true
		s.rotation.x = -PI / 2; s.position.y = 0.003
		n.add_child(s)
		return n
	var ink := RED_INK if CardsSim.is_red(card) else BLACK_INK
	var big := Label3D.new(); big.font = suitf; big.text = CardsSim.SUITS[CardsSim.suit_of(card)]; big.font_size = 120
	big.modulate = ink; big.outline_size = 0; big.pixel_size = 0.0011; big.rotation.x = -PI / 2; big.position = Vector3(0, 0.003, 0.02)
	big.shaded = true
	n.add_child(big)
	for corner in [Vector3(-0.072, 0.003, -0.12), Vector3(0.072, 0.003, 0.12)]:
		var r := Label3D.new(); r.font = font; r.text = CardsSim.RANKS[CardsSim.rank_of(card)]; r.font_size = 64
		r.modulate = ink; r.outline_size = 0; r.pixel_size = 0.0009; r.rotation.x = -PI / 2; r.position = corner
		r.shaded = true
		if corner.z > 0: r.rotation.y = PI
		n.add_child(r)
	return n


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


## Host / local: show the sim's new events and send each guest the state they're allowed to see.
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
			if guest or not pid_slot.has(pid): return
			var seat := _seat_of_slot(int(pid_slot[pid]))
			if seat < 0 or seat != _actor(): return   # not their turn: ignore
			if String(d.a) == "trump": sim.choose_trump(seat, int(d.s))
			elif String(d.a) == "play": sim.play(seat, int(d.c))


func _net_left(pid: int) -> void:
	if not pid_slot.has(pid): return
	for p in sim.players:
		if p.slot == int(pid_slot[pid]):
			p.human = false
			_toast("%s LEFT · CPU PLAYS ON" % _nm(p))


## The seat that has to act now (trump chooser, or whose turn it is).
func _actor() -> int:
	return sim.chooser if sim.phase in ["deal5", "trump"] else sim.turn


func _is_mine(seat: int) -> bool:
	var p = sim.players[seat]
	return p.human and (local_all or p.slot == my_slot)


## Is it this device's turn to act (and, in pass & play, has the curtain been lifted)?
func _my_turn() -> bool:
	if sim.phase not in ["trump", "play"]: return false
	var a := _actor()
	if not _is_mine(a): return false
	return not local_all or reveal_seat == a


func _act_trump(suit: int) -> void:
	if not _my_turn() or sim.phase != "trump": return
	if guest: net.send({t = "ci", a = "trump", s = suit})
	else: sim.choose_trump(_actor(), suit)


func _act_play(card: int) -> void:
	if not _my_turn() or sim.phase != "play": return
	if not (card in sim.legal(_actor())): G.sfx("thud"); return
	sel = -1
	if guest: net.send({t = "ci", a = "play", c = card})
	else: sim.play(_actor(), card)


func _control(dt: float) -> void:
	if paused: return
	if local_all and _is_mine(_actor()) and reveal_seat != _actor() and autoplay: reveal_seat = _actor()
	if not _my_turn() or not autoplay: return
	_act_t += dt
	if _act_t < 0.35: return
	_act_t = 0.0
	if sim.phase == "trump": _act_trump(sim.best_trump(_actor()))
	else: _act_play(sim.best_card(_actor()))


## Whose hand the fan shows.
func _shown_seat() -> int:
	if local_all: return reveal_seat
	for p in sim.players:
		if p.slot == my_slot and p.human: return p.seat
	return -1


func _view_seat() -> int:
	if local_all: return reveal_seat if reveal_seat >= 0 else _actor()
	var s := _shown_seat()
	return s if s >= 0 else 0


func _curtain() -> bool:
	return local_all and _is_mine(_actor()) and reveal_seat != _actor() and sim.phase in ["deal5", "trump", "play", "trick_end"] and not results_shown


func _unhandled_input(e: InputEvent) -> void:
	if sim == null: return
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.physical_keycode
		if k in [KEY_P, KEY_ESCAPE]: toggle_pause(); return
		if paused or results_shown: return
		if _curtain() and k in [KEY_SPACE, KEY_ENTER]: reveal_seat = _actor(); return
		if k == KEY_L: peek = not peek
		if sim.phase == "trump" and _my_turn():
			var n: int = [KEY_1, KEY_2, KEY_3, KEY_4].find(k)
			if n >= 0: _act_trump(n)
			if k in [KEY_LEFT, KEY_A]: trump_sel = (trump_sel + 3) % 4
			if k in [KEY_RIGHT, KEY_D]: trump_sel = (trump_sel + 1) % 4
			if k in [KEY_ENTER, KEY_SPACE]: _act_trump(trump_sel)
		elif sim.phase == "play" and _my_turn():
			_key_nav(k)
	if e is InputEventJoypadButton and e.pressed:
		if e.button_index == JOY_BUTTON_START: toggle_pause(); return
		if paused or results_shown: return
		if _curtain() and e.button_index == JOY_BUTTON_A: reveal_seat = _actor(); return
		if e.button_index == JOY_BUTTON_Y: peek = not peek
		var map := {JOY_BUTTON_DPAD_LEFT: KEY_LEFT, JOY_BUTTON_DPAD_RIGHT: KEY_RIGHT, JOY_BUTTON_A: KEY_ENTER}
		if map.has(e.button_index):
			var kk: int = map[e.button_index]
			if sim.phase == "trump" and _my_turn():
				if kk == KEY_LEFT: trump_sel = (trump_sel + 3) % 4
				elif kk == KEY_RIGHT: trump_sel = (trump_sel + 1) % 4
				else: _act_trump(trump_sel)
			elif sim.phase == "play" and _my_turn():
				_key_nav(kk)
	if e is InputEventMouseMotion:
		hover = _card_at(e.position)
	var click: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if click and not paused and not results_shown:
		var pos: Vector2 = e.position
		if _curtain(): reveal_seat = _actor(); return
		if peek_btn.has_point(pos): peek = not peek; return
		if sim.phase == "trump" and _my_turn():
			for r in trump_rects:
				if (r[0] as Rect2).has_point(pos): _act_trump(int(r[1])); return
		if sim.phase == "play" and _my_turn():
			var i := _card_at(pos)
			if i < 0: return
			var card: int = hand_rects[i][1]
			if e is InputEventScreenTouch and sel != i:   # touch: first tap lifts the card, second tap plays it
				sel = i; G.sfx("ui"); return
			_act_play(card)


func _key_nav(k: int) -> void:
	var seat := _shown_seat()
	if seat < 0: return
	var hand: Array = sim.players[seat].hand
	if hand.is_empty(): return
	if sel < 0 or sel >= hand.size():
		var leg: Array = sim.legal(seat)
		sel = hand.find(leg[0]) if not leg.is_empty() else 0
		if k in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D]: return
	if k in [KEY_LEFT, KEY_A]: sel = (sel + hand.size() - 1) % hand.size(); G.sfx("ui")
	elif k in [KEY_RIGHT, KEY_D]: sel = (sel + 1) % hand.size(); G.sfx("ui")
	elif k in [KEY_ENTER, KEY_SPACE, KEY_UP, KEY_W]: _act_play(int(hand[sel]))


func _card_at(pos: Vector2) -> int:
	# last drawn = on top
	for i in range(hand_rects.size() - 1, -1, -1):
		if (hand_rects[i][0] as Rect2).has_point(pos): return i
	return -1


# ---------------------------------------------------------------- events + animation
func _event(e: Array) -> void:
	var kind: String = e[0]
	stats[kind] = stats.get(kind, 0) + 1
	match kind:
		"deal":
			G.sfx("ui")
			peek = false
			_toast("HAND %d  ·  %s DEALS" % [int(e[3]), _nm(sim.players[int(e[1])])])
		"choose":
			if not _is_mine(int(e[1])) or local_all: _toast("%s PICKS THE RUNG" % _nm(sim.players[int(e[1])]))
		"trump":
			G.sfx("ok")
			_toast("RUNG:  %s  %s" % [CardsSim.SUIT_NAMES[int(e[2])], CardsSim.SUITS[int(e[2])]])
			_react(int(e[1]), "m_sit_talk", 2.0)
		"play":
			G.sfx("ui")
			var seat := int(e[1])
			var card := int(e[2])
			if not table_nodes.has(card):
				var n := _card3d(card)
				n.position = seat_dir(seat) * 0.95 + Vector3(0, TABLE_Y + 0.35, 0)
				table_nodes[card] = {node = n, seat = seat, yaw = randf_range(-0.25, 0.25)}
		"trick":
			var w := int(e[1])
			G.sfx("ok")
			_toast("%s TAKES THE TRICK" % _nm(sim.players[w]))
			_react(w, "m_sit_talk", 1.4)
		"hand":
			var team := int(e[1])
			var kot: bool = e[3]
			G.sfx("surge" if kot else "vs")
			_toast(("KOT!!  " if kot else "") + "%s WINS THE HAND" % TEAM_NAME[team])
			for s in 4:
				if CardsSim.team_of(s) == team:
					_react(s, "m_sit_talk", 2.4)
					if kot: _voice(s, "power")
		"done":
			if not results_shown:
				results_shown = true
				for s in 4:
					if CardsSim.team_of(s) == int(e[1]):
						_react(s, ["win_cheer", "win_clap", "win_excited"][s % 3], 99.0); _voice(s, "win")
				get_tree().create_timer(2.0).timeout.connect(_show_results)


func _react(seat: int, clip: String, t: float) -> void:
	if seat < 0 or not ClipLib.has(clip): return
	react[seat] = [clip, t]
	rigs[seat].set_meta("t", 0.0)


func _voice(seat: int, kind: String) -> void:
	var s := Voices.get_sound(sim.players[seat].C, kind)
	if s == null: return
	var p := AudioStreamPlayer.new(); p.stream = s; p.volume_db = -6.0
	add_child(p); p.play(); p.finished.connect(p.queue_free)


func _animate(dt: float) -> void:
	var view := _view_seat()
	var vd := seat_dir(view)
	var face_yaw := atan2(vd.x, vd.z)
	# cards on the table: fly in from the player, sit in front of them, then sweep to the trick's winner
	var on_table := {}
	for e in sim.trick: on_table[int(e[1])] = int(e[0])
	var gather: bool = sim.phase == "trick_end"
	if gather:
		for e in sim.last_trick: on_table[int(e[1])] = int(e[0])
	for card in table_nodes.keys():
		var t: Dictionary = table_nodes[card]
		var n: Node3D = t.node
		if not on_table.has(card):
			n.queue_free(); table_nodes.erase(card); continue
		var spot: Vector3 = seat_dir(int(t.seat)) * 0.34 + Vector3(0, TABLE_Y + 0.006 + 0.002 * int(t.seat), 0)
		if gather and sim.wait < 0.55 and sim.last_winner >= 0:
			spot = seat_dir(sim.last_winner) * 0.7 + Vector3(0, TABLE_Y + 0.02, 0)
		n.position = n.position.lerp(spot, clampf(dt * 9.0, 0.0, 1.0))
		n.rotation.y = lerp_angle(n.rotation.y, face_yaw + float(t.yaw), clampf(dt * 9.0, 0.0, 1.0))
	# the backs of the other players' hands, fanned in front of them
	var shown := _shown_seat()
	var cur := _curtain()
	for s in 4:
		var cnt: int = sim.players[s].hand.size()
		var d := seat_dir(s)
		var across := Vector3(d.z, 0, -d.x)
		var row: Array = backs[s]
		for k in 13:
			var b: Node3D = row[k]
			b.visible = k < cnt and (s != shown or cur)
			if b.visible:
				var u := (k - (cnt - 1) / 2.0) * 0.045
				b.position = d * 0.7 + across * u + Vector3(0, TABLE_Y + 0.003 + k * 0.0006, 0)
				b.rotation.y = atan2(d.x, d.z) + u * 1.2
	# whose turn: a pulsing ring in front of them
	var a := _actor()
	turn_ring.visible = sim.phase in ["trump", "play"]
	turn_ring.position = seat_dir(a) * 0.55 + Vector3(0, TABLE_Y + 0.004, 0)
	turn_ring.scale = Vector3(1, 0.2, 1) * (1.0 + 0.1 * sin(Time.get_ticks_msec() / 140.0))
	# the trump suit printed big in the middle of the felt
	if sim.trump >= 0:
		trump_lbl.text = CardsSim.SUITS[sim.trump]
		trump_lbl.modulate = Color(Color(0.75, 0.12, 0.15) if sim.trump in [1, 2] else Color(0.02, 0.1, 0.06), 0.6)
		trump_lbl.rotation.y = face_yaw
	else:
		trump_lbl.modulate.a = 0.0
	# players: seated, talking now and then, reacting
	for s in 4:
		var rig = rigs[s]
		rig.visible = s != view   # the camera sits where you sit
		(tags[s] as Label3D).visible = s != view
		var t: float = rig.get_meta("t", 0.0) + dt
		rig.set_meta("t", t)
		var r: Array = react[s]
		var clip := "m_sit"
		if r[1] > 0.0:
			r[1] -= dt; clip = r[0]
		elif s == a and sim.phase in ["trump", "play"] and fmod(t, 5.0) < 2.0:
			clip = "m_sit_talk"
		if not ClipLib.has(clip): clip = "idle_relaxed"
		var seated := clip.begins_with("m_sit")
		rig.set_clip(clip, fmod(t, Fighter._len(clip)), true, false)
		rig.apply_pose(sim.players[s].C.pose.guard, not seated)
		var d := seat_dir(s)
		rig.position = d * (1.12 if seated else 1.6) + Vector3(0, 0.05 if seated else 0.0, 0)
	# camera: just above your own seat, looking across the felt
	cam_angle = lerp_angle(cam_angle, _seat_angle(view), clampf(dt * 3.0, 0.0, 1.0))
	var cd := Vector3(sin(cam_angle), 0, cos(cam_angle))
	cam.position = cd * 1.9 + Vector3(0, 2.3, 0)
	cam.look_at(Vector3(0, TABLE_Y + 0.05, 0) - cd * 0.35, Vector3.UP)


# ---------------------------------------------------------------- HUD
func _nm(p) -> String:
	return (String(p.C.person.get("short", p.C.name)) if p.C.has("person") else String(p.C.name)).to_upper()


func _toast(t: String) -> void:
	toast = t; toast_t = 1.9


func _touch() -> bool:
	return G.ui.touch_enabled


func _style(kind: String) -> StyleBoxFlat:
	if _sb.has(kind): return _sb[kind]
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(9)
	match kind:
		"face": sb.bg_color = Color(0.98, 0.97, 0.93); sb.border_color = Color(0.7, 0.68, 0.64); sb.set_border_width_all(1)
		"back": sb.bg_color = Color(0.42, 0.22, 0.72); sb.border_color = Color(0.95, 0.95, 1.0); sb.set_border_width_all(3)
		"hl": sb.bg_color = Color(0, 0, 0, 0); sb.border_color = Color(1.0, 0.82, 0.3); sb.set_border_width_all(4)
		"dim": sb.bg_color = Color(0.05, 0.03, 0.1, 0.5)
		"panel": sb.bg_color = Color(0.04, 0.03, 0.08, 0.82); sb.border_color = Color(0.58, 0.3, 0.85); sb.set_border_width_all(2); sb.set_corner_radius_all(12)
	if kind in ["face", "back"]:
		sb.shadow_color = Color(0, 0, 0, 0.35); sb.shadow_size = 6
	_sb[kind] = sb
	return sb


## One card in 2D: rank and suit in the corner, a big suit in the middle (or the BNB back).
func _draw_card(r: Rect2, card: int, dim := false, hl := false) -> void:
	if card < 0:
		hud.draw_style_box(_style("back"), r)
		var m := r.grow(-r.size.x * 0.18)
		var asp := float(mark.get_width()) / mark.get_height()
		var mw := minf(m.size.x, m.size.y * asp)
		hud.draw_texture_rect(mark, Rect2(m.get_center() - Vector2(mw, mw / asp) / 2.0, Vector2(mw, mw / asp)), false, Color(1, 1, 1, 0.9))
		return
	hud.draw_style_box(_style("face"), r)
	var ink := RED_INK if CardsSim.is_red(card) else BLACK_INK
	var w := r.size.x
	var rank: String = CardsSim.RANKS[CardsSim.rank_of(card)]
	var suit: String = CardsSim.SUITS[CardsSim.suit_of(card)]
	var fs := int(w * 0.27)
	hud.draw_string(font, r.position + Vector2(w * 0.07, fs * 1.05), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	hud.draw_string(suitf, r.position + Vector2(w * 0.08, fs * 2.0), suit, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.85), ink)
	var court := CardsSim.rank_of(card) >= 9
	var big := int(w * (0.62 if not court else 0.5))
	hud.draw_string(suitf, Vector2(r.position.x, r.get_center().y + big * 0.36), suit, HORIZONTAL_ALIGNMENT_CENTER, w, big, Color(ink, 0.92))
	if court:   # court cards and aces: the letter under the big suit
		hud.draw_string(font, Vector2(r.position.x, r.end.y - w * 0.1), rank, HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.22), Color(ink, 0.55))
	if dim: hud.draw_style_box(_style("dim"), r)
	if hl: hud.draw_style_box(_style("hl"), r.grow(2))


func _draw_hud() -> void:
	var s := hud.size
	var ink := Color(0.95, 0.96, 1.0)
	hand_rects = []; trump_rects = []
	# teams: names, tricks this hand, hand points
	for t in 2:
		var box := Rect2(Vector2(20, 20 + t * 74), Vector2(330, 66))
		hud.draw_style_box(_style("panel"), box)
		hud.draw_rect(Rect2(box.position, Vector2(8, box.size.y)), TEAM_COL[t])
		var names := "%s  &  %s" % [_nm(sim.players[t]), _nm(sim.players[t + 2])]
		hud.draw_string(font, box.position + Vector2(20, 26), TEAM_NAME[t], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEAM_COL[t].lightened(0.3))
		hud.draw_string(small, box.position + Vector2(20, 52), names, HORIZONTAL_ALIGNMENT_LEFT, 200, 18, ink)
		hud.draw_string(font, box.position + Vector2(220, 46), str(sim.tricks[t]), HORIZONTAL_ALIGNMENT_CENTER, 50, 36, ink)
		hud.draw_string(small, box.position + Vector2(220, 62), "TRICKS", HORIZONTAL_ALIGNMENT_CENTER, 50, 13, Color(0.75, 0.78, 0.88))
		hud.draw_string(font, box.position + Vector2(272, 46), "%d" % sim.score[t], HORIZONTAL_ALIGNMENT_CENTER, 50, 36, Color(1.0, 0.82, 0.35))
		hud.draw_string(small, box.position + Vector2(272, 62), "/ %d PTS" % CardsSim.TARGET, HORIZONTAL_ALIGNMENT_CENTER, 50, 13, Color(0.75, 0.78, 0.88))
	# the rung (trump) badge, top right
	var bc := Vector2(s.x - 80, 72)
	hud.draw_circle(bc, 52, Color(0.04, 0.03, 0.08, 0.85))
	hud.draw_arc(bc, 52, 0, TAU, 48, Color(1.0, 0.82, 0.35), 3.0)
	if sim.trump >= 0:
		var tc := Color(1.0, 0.3, 0.35) if sim.trump in [1, 2] else Color(0.95, 0.96, 1.0)
		hud.draw_string(suitf, bc + Vector2(-52, 22), CardsSim.SUITS[sim.trump], HORIZONTAL_ALIGNMENT_CENTER, 104, 58, tc)
		hud.draw_string(small, bc + Vector2(-80, 74), "RUNG  ·  " + CardsSim.SUIT_NAMES[sim.trump], HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color(1.0, 0.82, 0.35))
	else:
		hud.draw_string(font, bc + Vector2(-52, 14), "?", HORIZONTAL_ALIGNMENT_CENTER, 104, 40, Color(1.0, 0.82, 0.35))
		hud.draw_string(small, bc + Vector2(-80, 74), "NO RUNG YET", HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color(1.0, 0.82, 0.35))
	# what's happening
	var a := _actor()
	var msg := ""
	if sim.phase == "done": msg = "MATCH OVER"
	elif sim.phase in ["deal5", "deal"]: msg = "DEALING…"
	elif sim.phase == "hand_end": msg = ""
	elif _my_turn() and not autoplay:
		msg = "PICK THE RUNG" if sim.phase == "trump" else "YOUR TURN"
		if local_all: msg = _nm(sim.players[a]) + ":  " + msg
	elif sim.phase in ["trump", "play"]:
		msg = "%s IS %s" % [_nm(sim.players[a]), "PICKING THE RUNG" if sim.phase == "trump" else "PLAYING"]
	hud.draw_string(font, Vector2(0, 50), msg, HORIZONTAL_ALIGNMENT_CENTER, s.x, 32, TEAM_COL[CardsSim.team_of(a)].lightened(0.35))
	if net != null and sim.players[a].human and not _my_turn() and sim.idle > CardsSim.TURN_TIME - 8.0 and sim.phase in ["trump", "play"]:
		hud.draw_string(small, Vector2(0, 78), "auto-play in %d" % ceili(CardsSim.TURN_TIME - sim.idle), HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(1, 0.7, 0.5))
	# your hand: a fan along the bottom
	var seat := _shown_seat()
	if seat >= 0 and not _curtain():
		var hand: Array = sim.players[seat].hand
		var n := hand.size()
		var ch := clampf(s.y * 0.25, 110.0, 200.0)
		var cw := ch * 0.7
		var step := minf(cw * 0.66, (s.x * 0.86 - cw) / maxf(1.0, n - 1))
		var x0 := (s.x - (cw + step * (n - 1))) / 2.0
		var playing: bool = _my_turn() and sim.phase == "play"
		var legal: Array = sim.legal(seat) if playing else []
		if sel >= n: sel = -1
		for i in n:
			var card: int = hand[i]
			var off := (i - (n - 1) / 2.0)
			var on := (i == hover and not _touch()) or i == sel
			var lift := 26.0 if on and card in legal else 0.0
			var r := Rect2(Vector2(x0 + i * step, s.y - ch - 30 + off * off * 1.6 - lift), Vector2(cw, ch))
			hand_rects.append([r, card])
			_draw_card(r, card, playing and not (card in legal), on and card in legal)
		if playing and not autoplay and not _touch():
			hud.draw_string(small, Vector2(0, s.y - ch - 62), "click a card  ·  ← → and ENTER", HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(1, 1, 1, 0.75))
	# picking the rung: four suit buttons over the table
	if sim.phase == "trump" and _my_turn():
		var pw := 520.0
		var panel := Rect2(Vector2((s.x - pw) / 2.0, s.y * 0.24), Vector2(pw, 190))
		hud.draw_style_box(_style("panel"), panel)
		hud.draw_string(font, panel.position + Vector2(0, 42), "PICK THE RUNG (TRUMPS)", HORIZONTAL_ALIGNMENT_CENTER, pw, 26, Color(1.0, 0.82, 0.35))
		for k in 4:
			var r := Rect2(panel.position + Vector2(24 + k * 120, 64), Vector2(108, 104))
			trump_rects.append([r, k])
			var on := k == trump_sel and not _touch()
			hud.draw_rect(r, Color(0.98, 0.97, 0.93) if not on else Color(1.0, 0.92, 0.7))
			if on: hud.draw_rect(r, Color(1.0, 0.82, 0.35), false, 4.0)
			hud.draw_string(suitf, Vector2(r.position.x, r.position.y + 70), CardsSim.SUITS[k], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 62, RED_INK if k in [1, 2] else BLACK_INK)
			hud.draw_string(small, Vector2(r.position.x, r.end.y - 8), "%d  %s" % [k + 1, CardsSim.SUIT_NAMES[k]], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, BLACK_INK)
	# end of a hand: the summary
	if sim.phase == "hand_end":
		var pw := 460.0
		var panel := Rect2(Vector2((s.x - pw) / 2.0, s.y * 0.22), Vector2(pw, 170))
		hud.draw_style_box(_style("panel"), panel)
		var w := 0 if sim.tricks[0] > sim.tricks[1] else 1
		hud.draw_string(font, panel.position + Vector2(0, 44), "HAND %d  ·  %s" % [sim.hand_n, TEAM_NAME[w]], HORIZONTAL_ALIGNMENT_CENTER, pw, 26, TEAM_COL[w].lightened(0.3))
		hud.draw_string(font, panel.position + Vector2(0, 100), "%d  —  %d" % [sim.tricks[0], sim.tricks[1]], HORIZONTAL_ALIGNMENT_CENTER, pw, 46, ink)
		var kot: bool = sim.tricks[w] == 13
		hud.draw_string(small, panel.position + Vector2(0, 140), ("KOT!  +2 POINTS" if kot else "+1 POINT") + "     MATCH  %d — %d" % [sim.score[0], sim.score[1]], HORIZONTAL_ALIGNMENT_CENTER, pw, 22, Color(1.0, 0.82, 0.35))
	# last trick peek
	peek_btn = Rect2(Vector2(20, 176), Vector2(150, 40))
	if not sim.last_trick.is_empty():
		hud.draw_style_box(_style("panel"), peek_btn)
		hud.draw_string(small, peek_btn.position + Vector2(0, 27), "LAST TRICK" + ("" if _touch() else "  (L)"), HORIZONTAL_ALIGNMENT_CENTER, peek_btn.size.x, 18, ink)
		if peek:
			var pr := Rect2(Vector2(20, 224), Vector2(330, 160))
			hud.draw_style_box(_style("panel"), pr)
			for k in sim.last_trick.size():
				var e: Array = sim.last_trick[k]
				var r := Rect2(pr.position + Vector2(14 + k * 78, 14), Vector2(70, 100))
				_draw_card(r, int(e[1]), false, int(e[0]) == sim.last_winner)
				hud.draw_string(small, Vector2(r.position.x, r.end.y + 22), _nm(sim.players[int(e[0])]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, TEAM_COL[CardsSim.team_of(int(e[0]))].lightened(0.3))
	if toast_t > 0.0:
		hud.draw_string(font, Vector2(0, s.y * 0.2), toast, HORIZONTAL_ALIGNMENT_CENTER, s.x, 40, Color(1, 1, 1, clampf(toast_t / 0.4, 0.0, 1.0)))
	# pass & play: hide the hand until the right person has the device
	if _curtain():
		hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.02, 0.08, 0.97))
		var who = sim.players[_actor()]
		hud.draw_string(font, Vector2(0, s.y * 0.42), "PASS TO %s" % _nm(who), HORIZONTAL_ALIGNMENT_CENTER, s.x, 56, TEAM_COL[CardsSim.team_of(_actor())].lightened(0.3))
		hud.draw_string(small, Vector2(0, s.y * 0.42 + 50), "tap (or press ENTER) to show your cards", HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, ink)
	if not _touch():
		hud.draw_string(small, Vector2(0, s.y - 6), "click / ← → ENTER  play   ·   1-4  pick the rung   ·   L  last trick   ·   P  pause", HORIZONTAL_ALIGNMENT_CENTER, s.x, 15, Color(0.8, 0.82, 0.9, 0.6))
	else:
		var pb := Vector2(s.x - 170, 40)
		hud.draw_circle(pb, 26, Color(0.58, 0.3, 0.85, 0.3)); hud.draw_arc(pb, 26, 0, TAU, 32, Color(0.58, 0.3, 0.85), 3)
		hud.draw_string(font, pb + Vector2(-26, 8), "II", HORIZONTAL_ALIGNMENT_CENTER, 52, 20, Color.WHITE)


func _input(e: InputEvent) -> void:
	if sim == null or not _touch(): return
	if e is InputEventScreenTouch and e.pressed:
		var s: Vector2 = hud.size
		if e.position.distance_to(Vector2(s.x - 170, 40)) < 34: toggle_pause(); get_viewport().set_input_as_handled()


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
	var w := 0 if sim.score[0] > sim.score[1] else 1
	var mine := _shown_seat()
	var title := "%s WINS!" % TEAM_NAME[w]
	if not local_all and mine >= 0: title = ("YOU WIN!" if CardsSim.team_of(mine) == w else "YOU LOSE") + "   ·   " + TEAM_NAME[w]
	v.add_child(ui.lbl(title, 44, font, TEAM_COL[w].lightened(0.2), 8))
	v.add_child(ui.lbl("%d  —  %d   ·   %d HANDS" % [sim.score[0], sim.score[1], sim.hand_n], 26, font, Color.WHITE))
	for t in 2:
		v.add_child(ui.lbl("%s:  %s & %s" % [TEAM_NAME[t], _nm(sim.players[t]), _nm(sim.players[t + 2])], 22, small, TEAM_COL[t].lightened(0.3)))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 14)
	if net != null:
		btns.add_child(ui.big_btn("BACK TO LOBBY", Color(0.13, 0.78, 0.92), func(): finished.emit(); G.lobby.back_to_lobby()))
		btns.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), func(): finished.emit(); G.lobby.leave()))
	else:
		var C: Dictionary = sim.players[0].C
		btns.add_child(ui.big_btn("PLAY AGAIN", Color(0.13, 0.78, 0.92), func(): finished.emit(); ui.show_game_menu("cards", C)))
		btns.add_child(ui.big_btn("MAIN MENU", Color(0.55, 0.62, 0.75), func(): finished.emit(); ui.show_title()))
	v.add_child(btns)
	_center(panel)


# ---------------------------------------------------------------- tests
## --autotest=cards: the CPU plays every seat. Shots: picking the rung, your turn, a trick on the felt,
## the hand summary, the match result.
func autotest(shot: Callable) -> void:
	var tree: SceneTree = G.get_tree()
	sim.think = 0.3
	# re-deal so that we pick the rung, and look at the picker before the CPU picks for us
	sim.dealer = 2; sim.hand_n = 0; sim.events.clear(); sim._new_hand()
	autoplay = false
	var t := 0
	while sim.phase != "trump" and t < 600:
		await tree.process_frame; t += 1
	for k in 10: await tree.process_frame
	await shot.call("cards_trump")
	autoplay = true
	# our turn with cards already on the table (the ones we can't play dimmed)
	t = 0
	while not (sim.phase == "play" and sim.turn == _shown_seat() and sim.trick.size() >= 2) and t < 4000:
		await tree.process_frame; t += 1
	autoplay = false
	hover = -1; sel = 0
	for k in 20: await tree.process_frame
	await shot.call("cards_myturn")
	autoplay = true
	t = 0
	while sim.trick.size() < 3 and t < 3000:
		await tree.process_frame; t += 1
	for k in 25: await tree.process_frame
	peek = true
	await shot.call("cards_trick")
	peek = false
	Engine.time_scale = 4.0   # fast-forward the rest of the hand
	t = 0
	while sim.phase != "hand_end" and t < 15000:
		await tree.process_frame; t += 1
	Engine.time_scale = 1.0
	for k in 12: await tree.process_frame
	await shot.call("cards_hand")
	Engine.time_scale = 4.0
	# jump to match point and play it out
	sim.score = [CardsSim.TARGET - 1, CardsSim.TARGET - 1]
	t = 0
	while sim.phase != "done" and t < 20000:
		await tree.process_frame; t += 1
	Engine.time_scale = 1.0
	await tree.create_timer(3.0).timeout
	await shot.call("cards_result")
	print("AUTOTEST cards hands=%d score=%s tricks=%s illegal=%d" % [sim.hand_n, sim.score, stats.get("trick", 0), sim.illegal])


## --autotest=cardssim: rules checks, many CPU matches, determinism and the hidden-info snapshot.
func selftest(_main) -> void:
	var fails := []
	var C := func(s: int, r: int) -> int: return s * 13 + r
	# trick winner: a low trump beats a high card of the led suit; off-suit cards never win
	if CardsSim.winner_of([[0, C.call(0, 5)], [1, C.call(0, 12)], [2, C.call(1, 0)], [3, C.call(0, 3)]], 1) != 2: fails.append("low trump should win")
	if CardsSim.winner_of([[0, C.call(0, 5)], [1, C.call(0, 12)], [2, C.call(2, 12)], [3, C.call(0, 3)]], 1) != 1: fails.append("highest of led suit should win")
	if CardsSim.winner_of([[0, C.call(1, 2)], [1, C.call(1, 11)], [2, C.call(1, 12)], [3, C.call(1, 0)]], 1) != 2: fails.append("highest trump should win")
	var people := []
	for k in 4: people.append({C = Data.ROSTER[k], human = false, slot = -1})
	# follow suit: with a spade led, a player holding spades may not play a heart
	var s0 = CardsSim.new()
	s0.setup(people, 7)
	s0.trump = 1; s0.phase = "play"; s0.turn = 1; s0.trick = [[0, C.call(0, 4)]]
	s0.players[1].hand = [C.call(0, 9), C.call(1, 12), C.call(2, 3)]
	if s0.play(1, C.call(1, 12)): fails.append("revoke accepted")
	if not s0.play(1, C.call(0, 9)): fails.append("legal follow rejected")
	s0.players[2].hand = [C.call(1, 1), C.call(3, 5)]   # void in spades: anything goes
	if not s0.play(2, C.call(3, 5)): fails.append("discard when void rejected")
	# hand end and kot: 7-0 plays on, 7-1 ends at 1 point, 13-0 is a kot worth 2
	var k0 = CardsSim.new(); k0.setup(people, 3)
	k0.tricks = [7, 0]; k0.last_winner = 0; k0.score = [0, 0]; k0._after_trick()
	if k0.phase != "play": fails.append("7-0 should play on for the kot")
	k0.tricks = [7, 1]; k0._after_trick()
	if k0.phase != "hand_end" or k0.score != [1, 0]: fails.append("7-1 should end the hand at 1 point")
	k0.tricks = [13, 0]; k0.score = [0, 0]; k0._after_trick()
	if k0.score != [2, 0] or k0.kots != 1: fails.append("13-0 should be a kot worth 2")
	# many full matches between CPUs
	var matches := 150
	var hands := 0
	var illegal := 0
	var kots := 0
	var wins := [0, 0]
	var dup := 0
	for m in matches:
		var s = CardsSim.new()
		s.think = 0.0
		s.setup(people, 1000 + m)
		var steps := 0
		var checked := -1
		while s.phase != "done" and steps < 40000:
			s.update(3.0); steps += 1
			if s.phase == "play" and s.hand_n != checked and s.trick.is_empty() and s.tricks[0] + s.tricks[1] == 0:
				checked = s.hand_n
				var seen := {}
				for p in s.players:
					for c in p.hand: seen[c] = true
				if seen.size() != 52: dup += 1
			s.events.clear()
		if s.phase != "done": fails.append("match %d stuck in %s" % [m, s.phase])
		hands += s.hand_n; illegal += s.illegal; kots += s.kots
		wins[0 if s.score[0] >= CardsSim.TARGET else 1] += 1
	if illegal > 0: fails.append("%d illegal CPU moves" % illegal)
	if dup > 0: fails.append("%d deals without 52 distinct cards" % dup)
	# determinism: the same seed plays the same match
	var runs := []
	for r in 2:
		var s = CardsSim.new(); s.think = 0.0; s.setup(people, 4242)
		var plays := []
		while s.phase != "done":
			s.update(3.0)
			for e in s.events: if e[0] == "play": plays.append(e[2])
			s.events.clear()
		runs.append([s.score.duplicate(), plays])
	if runs[0] != runs[1]: fails.append("not deterministic")
	# hidden info: a guest's snapshot has only their own hand, and survives the wire
	var h = CardsSim.new(); h.think = 0.0; h.setup(people, 99)
	while h.phase != "play": h.update(3.0)
	h.turn = 1
	var sn: Dictionary = h.snapshot_for(1)
	for k in 4:
		if (k == 1) != (sn.h[k] is Array): fails.append("snapshot leaks seat %d's hand" % k)
	var wire: Dictionary = JSON.parse_string(JSON.stringify(sn))
	var g = CardsSim.new(); g.setup(people, 1)
	g.apply(wire)
	if g.players[1].hand != h.players[1].hand: fails.append("own hand lost on the wire")
	if g.players[0].hand.any(func(c): return c >= 0): fails.append("guest knows another hand")
	if g.legal(1) != h.legal(1): fails.append("guest legal moves differ")
	print("AUTOTEST cardssim matches=%d avg_hands=%.1f illegal_moves=%d kots=%d wins=%s" % [matches, float(hands) / matches, illegal, kots, wins])
	print("AUTOTEST cardssim %s %s" % ["PASS" if fails.is_empty() else "FAIL", fails])
