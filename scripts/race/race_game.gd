class_name RaceGame
extends Node
## BNB Rush Hour: runs a RaceSim at 60 ticks/s, feeds it the player's controls, draws it with RaceWorld,
## and shows the HUD, countdown and results. (Multiplayer will swap the local sim for the host's snapshots.)

signal finished

const ITEM_NAMES := {"stapler": "STAPLER", "coffee": "COFFEE SPILL", "planes": "PAPER PLANES", "peel": "BANANA PEEL", "energy": "ENERGY DRINK"}

var G                      # Main
var sim: RaceSim
var world: RaceWorld
var hud: Control
var layer: CanvasLayer
var me := 0
var steer_s := 0.0         # smoothed steering
var toast := ""
var toast_t := 0.0
var results_shown := false
var font: Font
var small: Font
var touch_btn := {}        # touch buttons: name -> {rect, held}
var touches := {}          # touch index -> button name
var minimap: PackedVector2Array
var mm_scale := 1.0
var mm_min := Vector2.ZERO
var autopilot := false     # autotest: the CPU drives the player's car too
var stats := {}            # autotest: event counts
var cutin := {}            # power cut-in banner: {C, t, mine}
var paused := false


# multiplayer: the host runs the race and streams it; guests send their controls and draw what arrives
var net: Party = null
var guest := false
var pid_of := {}           # host: guest pid -> racer id
var inputs := {}           # host: racer id -> latest controls
var outbox: Array = []     # host: events since the last snapshot
var inbox: Array = []      # guest: snapshots / events waiting to be shown
var track := ""


var gp_field: Array = []   # Grand Prix: the same nine rivals every race


func start(g, track_id: String, player: Dictionary) -> void:
	# ten racers: the player plus nine colleagues (bosses included)
	var others := Data.ROSTER.filter(func(c): return c.id != player.id)
	others.shuffle()
	if not gp_field.is_empty(): others = gp_field
	_begin(g, track_id, [player] + others.slice(0, 9), 1, randi())


## Online / Wi-Fi race. people: every racer (humans first), me: this player's racer.
func start_net(g, track_id: String, people: Array, humans: int, seed: int, my_id: int, party: Party, is_guest: bool, pids: Dictionary) -> void:
	net = party; guest = is_guest; pid_of = pids; me = my_id
	net.message.connect(_net_message)
	if not guest: net.left.connect(_net_left)
	_begin(g, track_id, people, humans, seed)


func _begin(g, track_id: String, people: Array, humans: int, seed: int) -> void:
	G = g
	track = track_id
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	sim = RaceSim.new()
	sim.setup(track_id, people, humans, seed)
	world = RaceWorld.new()
	G.add_child(world)
	world.build(sim, people, me)
	layer = CanvasLayer.new()
	layer.layer = 5
	G.add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	_build_minimap()
	_layout_touch()


func stop() -> void:
	if net != null:
		if net.message.is_connected(_net_message): net.message.disconnect(_net_message)
		if net.left.is_connected(_net_left): net.left.disconnect(_net_left)
	if world != null: world.queue_free()
	if layer != null: layer.queue_free()
	world = null; layer = null


# ---------------------------------------------------------------- loop
func _physics_process(_dt: float) -> void:
	if sim == null or (paused and not online_match()): return
	var mine: Dictionary = sim._cpu(sim.racers[me]) if autopilot else _controls()
	if guest:
		_guest_tick(mine)
	else:
		inputs[me] = mine
		sim.tick(inputs)
		for e in sim.events:
			stats[e[0]] = stats.get(e[0], 0) + 1
			_event(e)
		if net != null:
			outbox.append_array(sim.events)
			if sim.tick_n % 2 == 0 or sim.state == "done":
				var ev := []
				for e in outbox: ev.append(Party.pack(e))
				net.broadcast({t = "rs", s = sim.snapshot(), e = ev})
				outbox.clear()
	if sim.state == "done" and not results_shown:
		results_shown = true
		await get_tree().create_timer(1.2).timeout
		_show_results()


func _process(dt: float) -> void:
	if sim == null or world == null: return
	world.draw(Engine.get_physics_interpolation_fraction(), dt)
	toast_t = maxf(0.0, toast_t - dt)
	if not cutin.is_empty():
		cutin.t -= dt
		if cutin.t <= 0.0: cutin = {}
	hud.queue_redraw()


func _guest_tick(mine: Dictionary) -> void:
	if sim.tick_n % 1 == 0: net.send({t = "ri", i = mine})
	var got := false
	for m in inbox:
		sim.apply(m.s)
		got = true
		for e in m.e:
			var ev := Party.unpack_event(e)
			stats[ev[0]] = stats.get(ev[0], 0) + 1
			_event(ev)
	inbox.clear()
	if not got: sim.coast()


func _net_message(pid: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"ri":
			if not guest and pid_of.has(pid) and d.i is Dictionary: inputs[pid_of[pid]] = d.i
		"rs":
			if guest: inbox.append(d)


## A guest dropped out: a CPU takes over their car.
func _net_left(pid: int) -> void:
	if not pid_of.has(pid): return
	var r: RaceSim.Racer = sim.racers[pid_of[pid]]
	r.human = -1
	inputs.erase(r.id)
	_toast("%s LEFT" % String(r.C.person.get("short", r.C.name) if r.C.has("person") else r.C.name).to_upper())


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_P, KEY_ESCAPE]: toggle_pause()
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START: toggle_pause()


func _controls() -> Dictionary:
	if paused: return {}
	var k := func(keys: Array) -> bool:
		for key in keys:
			if Input.is_physical_key_pressed(key): return true
		return false
	var left: bool = k.call([KEY_A, KEY_LEFT]) or _t("left")
	var right: bool = k.call([KEY_D, KEY_RIGHT]) or _t("right")
	var target := (1.0 if right else 0.0) - (1.0 if left else 0.0)
	var pads := Input.get_connected_joypads()
	var pad_gas := 0.0
	var pad_brake := 0.0
	var pad_drift := false
	var pad_item := false
	var pad_power := false
	if not pads.is_empty():
		var d: int = pads[0]
		var ax := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
		if absf(ax) > 0.2: target = ax
		pad_gas = maxf(Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT), 1.0 if Input.is_joy_button_pressed(d, JOY_BUTTON_A) else 0.0)
		pad_brake = maxf(Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT), 1.0 if Input.is_joy_button_pressed(d, JOY_BUTTON_B) else 0.0)
		pad_drift = Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER)
		pad_item = Input.is_joy_button_pressed(d, JOY_BUTTON_X)
		pad_power = Input.is_joy_button_pressed(d, JOY_BUTTON_Y)
	steer_s = move_toward(steer_s, target, 0.12)
	return {
		steer = steer_s,
		gas = maxf(pad_gas, 1.0 if (k.call([KEY_W, KEY_UP]) or _t("gas")) else 0.0),
		brake = maxf(pad_brake, 1.0 if (k.call([KEY_S, KEY_DOWN]) or _t("brake")) else 0.0),
		drift = pad_drift or k.call([KEY_SPACE]) or _t("drift"),
		nitro = (not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_LEFT_SHOULDER)) or k.call([KEY_SHIFT, KEY_N, KEY_L]) or _t("nitro"),
		item = pad_item or k.call([KEY_J, KEY_E]) or _t("item"),
		power = pad_power or k.call([KEY_K, KEY_Q]) or _t("power"),
	}


func _t(name: String) -> bool:
	return touch_btn.has(name) and touch_btn[name].held


func _event(e: Array) -> void:
	var kind: String = e[0]
	var who: int = int(e[2]) if e[2] is int else -1
	var mine := who == me
	match kind:
		"count": G.sfx("ui"); _toast(str(e[2]))
		"go": G.sfx("ok"); _toast("GO!")
		"boost": if mine: G.sfx("whoosh"); _toast("BOOST!")
		"hit":
			G.sfx("heavy")
			if who >= 0: _voice(who, "hurt")
			if mine: _toast("HIT!")
		"crash": G.sfx("thud"); if mine: _toast("CRASH!")
		"pickup": if mine: G.sfx("ok")
		"power":
			G.sfx("surge")
			_voice(who, "power")
			var pr: RaceSim.Racer = sim.racers[who]
			var fx: Array = (pr.C.get("person", {}) as Dictionary).get("fx", [])
			# their fighting-game power show, around the car (visual only)
			var tgt: RaceSim.Racer = sim._ahead_of(pr, 200.0)
			if not fx.is_empty() and tgt != null:
				PowerProps.play(world, _proxy(pr), _proxy(tgt), fx, 0.6)
			var r: RaceSim.Racer = sim.racers[who]
			# Tekken-style cut-in: their portrait and power name sweep across the screen
			var near: bool = mine or (sim.racers[me] as RaceSim.Racer).pos.distance_to(r.pos) < 60.0
			if near:
				cutin = {C = r.C, t = 1.6, mine = mine}
				world.punch = 0.4 if mine else 0.0
			if not near: _toast(String(r.C.get("surge_name", "POWER")) if mine else "%s: %s" % [r.C.person.get("short", r.C.name) if r.C.has("person") else r.C.name, r.C.get("surge_name", "")])
		"use": if mine: G.sfx("whoosh")
		"lap": if mine: G.sfx("vs"); _toast("LAP %d / %d" % [mini((sim.racers[me] as RaceSim.Racer).lap + 1, RaceSim.LAPS), RaceSim.LAPS])
		"finish":
			if mine: G.sfx("ko"); _toast("FINISH!  %s" % _ord((sim.racers[me] as RaceSim.Racer).place))
			if who >= 0 and (sim.racers[who] as RaceSim.Racer).place == 1: _voice(who, "win")
		"boom": G.sfx("hit")
		"scrape": if mine: G.sfx("block")
		"jump": if mine: G.sfx("whoosh")
		"bump": G.sfx("thud")


## PowerProps expects fighters (pos, C); racers have both.
func _proxy(r: RaceSim.Racer) -> Dictionary:
	return {pos = r.pos, C = r.C}


func _voice(who: int, kind: String) -> void:
	var r: RaceSim.Racer = sim.racers[who]
	var s := Voices.get_sound(r.C, kind)
	if s == null: return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = -2.0 if who == me else -9.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _toast(t: String) -> void:
	toast = t; toast_t = 1.4


static func _ord(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		suf = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suf]


# ---------------------------------------------------------------- HUD
func _build_minimap() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in sim.P:
		lo = lo.min(Vector2(p.x, p.z)); hi = hi.max(Vector2(p.x, p.z))
	mm_min = lo
	mm_scale = 170.0 / maxf(hi.x - lo.x, hi.y - lo.y)
	minimap = PackedVector2Array()
	for i in range(0, sim.P.size(), 4):
		minimap.append((Vector2(sim.P[i].x, sim.P[i].z) - lo) * mm_scale)


func _draw_hud() -> void:
	var s := hud.size
	var r: RaceSim.Racer = sim.racers[me]
	var ink := Color(0.95, 0.95, 1.0)
	# place
	hud.draw_string(font, Vector2(30, 92), _ord(r.place), HORIZONTAL_ALIGNMENT_LEFT, -1, 80, Color(1.0, 0.8, 0.3))
	hud.draw_string(small, Vector2(34, 122), "OF %d" % sim.racers.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)
	hud.draw_string(font, Vector2(30, 165), "LAP %d / %d" % [clampi(r.lap + 1, 1, RaceSim.LAPS), RaceSim.LAPS], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	hud.draw_string(small, Vector2(30, 195), "%02d:%05.2f" % [int(sim.time) / 60, fmod(sim.time, 60.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.75, 0.8, 0.9))
	# item + power
	var ib := Rect2(Vector2(s.x / 2 - 110, 20), Vector2(220, 64))
	hud.draw_rect(ib, Color(0, 0, 0, 0.45))
	hud.draw_rect(ib, Color(0.13, 0.78, 0.92, 0.9), false, 3.0)
	hud.draw_string(font, ib.position + Vector2(0, 42), ITEM_NAMES.get(r.item, "—"), HORIZONTAL_ALIGNMENT_CENTER, ib.size.x, 22, ink)
	var pw := Rect2(Vector2(s.x / 2 - 110, 92), Vector2(220, 14))
	hud.draw_rect(pw, Color(0, 0, 0, 0.45))
	var full := r.power >= 100.0
	hud.draw_rect(Rect2(pw.position, Vector2(pw.size.x * r.power / 100.0, pw.size.y)), Color(0.58, 0.3, 0.85) if not full else Color(1.0, 0.8, 0.3).lerp(Color.WHITE, 0.5 + 0.5 * sin(sim.time * 10.0)))
	hud.draw_string(small, pw.position + Vector2(0, 34), ("POWER READY  [K]" if full else "POWER") if not _touch() else ("POWER READY" if full else "POWER"), HORIZONTAL_ALIGNMENT_CENTER, pw.size.x, 18, ink)
	# nitro tank
	var nb := Rect2(Vector2(s.x / 2 - 110, 136), Vector2(220, 12))
	hud.draw_rect(nb, Color(0, 0, 0, 0.45))
	hud.draw_rect(Rect2(nb.position, Vector2(nb.size.x * r.nitro / 100.0, nb.size.y)), Color(0.2, 0.75, 1.0) if not r.nitro_on else Color(1.0, 0.55, 0.2))
	hud.draw_string(small, nb.position + Vector2(0, 30), "NITRO  [SHIFT]" if not _touch() else "NITRO", HORIZONTAL_ALIGNMENT_CENTER, nb.size.x, 16, ink)
	# speed
	# (on phones the controls fill the bottom corners: the speed goes under the minimap)
	hud.draw_string(font, Vector2(s.x - 240, s.y - 40 if not _touch() else 240), "%d km/h" % roundi(absf(r.speed) * 3.6), HORIZONTAL_ALIGNMENT_RIGHT, 200, 34 if not _touch() else 28, ink)
	# minimap
	var mo := Vector2(s.x - 210, 20)
	hud.draw_rect(Rect2(mo - Vector2(10, 10), Vector2(190, 190)), Color(0, 0, 0, 0.35))
	if minimap.size() > 1:
		var pts := PackedVector2Array()
		for p in minimap: pts.append(mo + p)
		pts.append(pts[0])
		hud.draw_polyline(pts, Color(1, 1, 1, 0.6), 3.0)
	for o in sim.racers:
		var d := mo + (Vector2(o.pos.x, o.pos.z) - mm_min) * mm_scale
		hud.draw_circle(d, 6.0 if o.id == me else 4.0, (o.C.accent as Color) if o.id != me else Color(1, 0.8, 0.3))
	_draw_cutin(s)
	# countdown / toasts
	if toast_t > 0.0:
		var a := clampf(toast_t / 0.4, 0.0, 1.0)
		hud.draw_string(font, Vector2(0, s.y * 0.38), toast, HORIZONTAL_ALIGNMENT_CENTER, s.x, 72, Color(1, 1, 1, a))
	if not _touch():
		hud.draw_string(small, Vector2(0, s.y - 14), "W / S  gas / brake   ·   A / D  steer   ·   SHIFT  nitro   ·   SPACE  drift   ·   J  item   ·   K  power", HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(0.8, 0.82, 0.9, 0.75))
	_draw_touch()


## Power cut-in: a compact strip on the left (under the lap / time), so the road stays clear.
func _draw_cutin(s: Vector2) -> void:
	if cutin.is_empty(): return
	var C: Dictionary = cutin.C
	var t: float = 1.6 - cutin.t
	var slide := clampf(t / 0.15, 0.0, 1.0) * (1.0 - clampf((t - 1.3) / 0.3, 0.0, 1.0))
	var acc: Color = C.get("accent", Color(0.6, 0.3, 0.9))
	var w := 360.0
	var h := 64.0
	var x := -w + slide * (w + 24.0)
	var y := 215.0 if not _touch() else s.y * 0.3
	var box := PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w - 18, y + h), Vector2(x, y + h)])
	hud.draw_colored_polygon(box, Color(0.04, 0.02, 0.08, 0.78))
	hud.draw_rect(Rect2(Vector2(x, y), Vector2(6, h)), acc)
	hud.draw_line(Vector2(x, y + h), Vector2(x + w - 18, y + h), Color(acc, 0.9), 2.0)
	var tex: Texture2D = G.portraits.get(C.id)
	if tex != null: hud.draw_texture_rect(tex, Rect2(Vector2(x + 10, y + 4), Vector2(h - 8, h - 8)), false)
	var name: String = String(C.person.get("short", C.name)).to_upper() if C.has("person") else String(C.name).to_upper()
	hud.draw_string(small, Vector2(x + h + 12, y + 24), name + ("  (YOU)" if cutin.mine else ""), HORIZONTAL_ALIGNMENT_LEFT, w - h - 30, 18, Color(0.85, 0.88, 0.95))
	hud.draw_string(font, Vector2(x + h + 12, y + 52), String(C.get("surge_name", "POWER")).to_upper() + "!", HORIZONTAL_ALIGNMENT_LEFT, w - h - 30, 24, acc.lightened(0.4))


# ---------------------------------------------------------------- touch controls
func _touch() -> bool:
	return G.ui.touch_enabled


func _layout_touch() -> void:
	if not _touch(): return
	var s: Vector2 = G.get_viewport().get_visible_rect().size
	var r := clampf(s.y * 0.09, 40.0, 70.0)
	touch_btn = {
		left = {c = Vector2(r * 1.6, s.y - r * 1.8), r = r * 1.1, label = "◀", held = false},
		right = {c = Vector2(r * 4.2, s.y - r * 1.8), r = r * 1.1, label = "▶", held = false},
		gas = {c = Vector2(s.x - r * 1.6, s.y - r * 1.8), r = r * 1.2, label = "GAS", held = false},
		brake = {c = Vector2(s.x - r * 4.1, s.y - r * 1.4), r = r * 0.85, label = "BRAKE", held = false},
		drift = {c = Vector2(s.x - r * 4.1, s.y - r * 3.6), r = r * 0.8, label = "DRIFT", held = false},
		nitro = {c = Vector2(s.x - r * 6.3, s.y - r * 3.4), r = r * 0.8, label = "NITRO", held = false},
		item = {c = Vector2(s.x - r * 1.6, s.y - r * 4.4), r = r * 0.85, label = "ITEM", held = false},
		power = {c = Vector2(s.x - r * 6.2, s.y - r * 1.4), r = r * 0.8, label = "POWER", held = false},
		pause = {c = Vector2(s.x / 2 - 150, 52), r = 26.0, label = "II", held = false},
	}


func _input(e: InputEvent) -> void:
	if not _touch() or touch_btn.is_empty(): return
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		var hit := ""
		for n in touch_btn:
			if e.position.distance_to(touch_btn[n].c) <= touch_btn[n].r * 1.15: hit = n
		if e is InputEventScreenTouch and not e.pressed:
			touches.erase(e.index)
		elif hit != "":
			touches[e.index] = hit
		for n in touch_btn: touch_btn[n].held = touches.values().has(n)


func _draw_touch() -> void:
	for n in touch_btn:
		var b: Dictionary = touch_btn[n]
		var col := Color(0.13, 0.78, 0.92) if n in ["gas", "left", "right"] else Color(0.58, 0.3, 0.85)
		hud.draw_circle(b.c, b.r, Color(col, 0.5 if b.held else 0.18))
		hud.draw_arc(b.c, b.r, 0, TAU, 40, Color(col, 0.9), 3.0)
		var fs := int(b.r * (0.55 if String(b.label).length() <= 2 else 0.36))
		hud.draw_string(font, b.c + Vector2(-b.r, fs * 0.36), b.label, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, Color.WHITE)


# ---------------------------------------------------------------- results
func _show_results() -> void:
	var ui = G.ui
	var order := sim.racers.duplicate()
	order.sort_custom(func(a, b): return a.place < b.place)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.03, 0.1, 0.92); sb.border_color = Color(0.58, 0.3, 0.85); sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(ui.lbl("RACE RESULTS", 40, font, Color(1.0, 0.8, 0.3), 8))
	for r in order:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var nm: String = r.C.name
		var t := ("%02d:%05.2f" % [int(r.finished) / 60, fmod(r.finished, 60.0)]) if r.finished >= 0.0 else "—"
		row.add_child(ui.lbl(_ord(r.place), 24, font, Color(1.0, 0.8, 0.3) if r.place <= 3 else Color(0.8, 0.82, 0.9)))
		var n: Label = ui.lbl(nm + ("  (YOU)" if r.id == me else ""), 22, font, r.C.accent.lightened(0.3) if r.id != me else Color.WHITE)
		n.custom_minimum_size = Vector2(420, 0)
		row.add_child(n)
		row.add_child(ui.lbl(t, 22, small, Color(0.85, 0.88, 0.95)))
		v.add_child(row)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	if net != null:
		btns.add_child(ui.big_btn("BACK TO LOBBY", Color(0.13, 0.78, 0.92), func(): finished.emit(); G.lobby.back_to_lobby()))
		btns.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), func(): finished.emit(); G.lobby.leave()))
	elif G.gp != null:
		var mine: RaceSim.Racer = sim.racers[me]
		var won := mine.place == 1
		var C: Dictionary = mine.C
		var t_me: float = maxf(0.0, mine.finished)
		var n: int = G.gp.tracks.size()
		var k: int = G.gp.idx + 1
		if won:
			v.add_child(ui.lbl("GRAND PRIX  ·  RACE %d / %d WON" % [k, n], 26, font, Color(0.4, 1.0, 0.55), 6))
			btns.add_child(ui.big_btn("CLAIM YOUR TROPHY" if k == n else "NEXT RACE  ›", Color(1.0, 0.81, 0.35), func(): finished.emit(); G.grand_prix_next(true, t_me)))
		else:
			v.add_child(ui.lbl("GRAND PRIX OVER  ·  YOU NEEDED 1ST (RACE %d / %d)" % [k, n], 26, font, Color(1.0, 0.4, 0.4), 6))
			btns.add_child(ui.big_btn("START OVER", Color(0.13, 0.78, 0.92), func(): finished.emit(); G.grand_prix_next(false, 0.0); G.start_grand_prix(C)))
			btns.add_child(ui.big_btn("MAIN MENU", Color(0.55, 0.62, 0.75), func(): finished.emit(); G.grand_prix_next(false, 0.0); ui.show_title()))
	else:
		btns.add_child(ui.big_btn("RACE AGAIN", Color(0.13, 0.78, 0.92), func(): finished.emit(); ui.show_race_tracks(sim.racers[me].C)))
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
	pass
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
