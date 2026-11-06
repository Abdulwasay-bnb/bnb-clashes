class_name BlastGame
extends Node
## BNB Office Blast: drop coffee-mug bombs on an office floor grid, break the cover, trap your rivals.
## Last one standing wins the round, first to 3 rounds wins. Draws a BlastSim (or a host's snapshots) with the
## players' own characters, flames, power-ups, HUD, touch / keyboard / gamepad controls and online play.

signal finished

const BlastSim = preload("res://scripts/blast/blast_sim.gd")
const TILE := 1.2
const COLORS := [Color(0.62, 0.38, 1.0), Color(0.13, 0.78, 0.92), Color(1.0, 0.81, 0.35), Color(1.0, 0.36, 0.54)]
const POWER_LOOK := {"bomb": ["BOMB +1", Color(0.62, 0.38, 1.0)], "fire": ["FIRE +1", Color(1.0, 0.5, 0.15)],
	"speed": ["SPEED", Color(0.13, 0.78, 0.92)], "kick": ["KICK", Color(0.35, 0.9, 0.45)]}
const CAM_POS := Vector3(0, 20.5, 9.8)

var G
var sim
var me := 0                     # my player index
var my_slot := 0
var autoplay := false
var stats := {}
var world: Node3D
var env: Environment
var cam: Camera3D
var layer: CanvasLayer
var hud: Control
var font: Font
var small: Font
var rigs: Array = []            # per player: {rig, tag, ring}
var box_nodes := {}             # cell index -> node
var block_nodes := {}           # sudden-death blocks: cell index -> node
var bomb_nodes := {}            # uid -> node
var flame_nodes := {}           # cell index -> node
var power_nodes := {}           # cell index -> node
var debris: Array = []          # [node, vel, life]
var shake := 0.0
var flash_l: OmniLight3D
var toast := ""
var toast_sub := ""
var toast_t := 0.0
var toast_col := Color.WHITE
var paused := false
var results_shown := false
var anim_t := 0.0
var rng := RandomNumberGenerator.new()
# input
var key_dirs: Array = []        # held direction keys, most recent last
var touch_move := Vector2.ZERO
var move_id := -1
var move_origin := Vector2.ZERO
var bomb_touch := -1
var touch_btn := {}
# multiplayer
var net: Party = null
var guest := false
var pid_slot := {}              # host: pid -> lobby slot
var inputs := {}                # host: player id -> controls
var outbox: Array = []
var inbox: Array = []


func start(g, people: Array, seed: int, slot := 0, pass_play := false) -> void:
	G = g
	my_slot = slot
	rng.seed = seed + 7
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	sim = BlastSim.new()
	sim.setup(people, seed)
	for p in sim.players:
		if p.human and p.slot == slot: me = p.id
	world = Node3D.new()
	G.add_child(world)
	_build_world()
	for p in sim.players: rigs.append(_player_visual(p))
	layer = CanvasLayer.new(); layer.layer = 5
	G.add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	_layout_touch()
	_sync_cells()


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
static func W(c: Vector2, y := 0.0) -> Vector3:
	return Vector3((c.x - 7.0) * TILE, y, (c.y - 6.0) * TILE)


func _mat(c: Color, rough := 0.7, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
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


func _cyl(r1: float, r2: float, h: float, m: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new(); c.top_radius = r1; c.bottom_radius = r2; c.height = h; c.radial_segments = 16
	mi.mesh = c; mi.material_override = m; mi.position = pos
	parent.add_child(mi)
	return mi


func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.05, 0.04, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.75); env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = 0.95
	env.glow_enabled = true; env.glow_intensity = 0.3; env.glow_hdr_threshold = 1.3
	env.adjustment_enabled = true; env.adjustment_saturation = 1.15
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-58), deg_to_rad(28), 0); sun.light_energy = 0.75; sun.light_color = Color(1.0, 0.92, 0.82)
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 40
	world.add_child(sun)
	for k in 4:   # warm office lamps over the floor
		var l := OmniLight3D.new(); l.light_color = Color(1.0, 0.85, 0.65); l.light_energy = 0.9; l.omni_range = 11.0
		l.position = Vector3((-1 if k % 2 == 0 else 1) * 5.0, 5.5, (-1 if k < 2 else 1) * 4.0)
		world.add_child(l)
	flash_l = OmniLight3D.new(); flash_l.light_color = Color(1.0, 0.6, 0.25); flash_l.omni_range = 9.0; flash_l.light_energy = 0.0
	world.add_child(flash_l)
	# carpet floor with a subtle tile pattern
	var fm := ShaderMaterial.new(); fm.shader = load("res://shaders/race_ground.gdshader")
	fm.set_shader_parameter("col_a", Color(0.3, 0.24, 0.42)); fm.set_shader_parameter("col_b", Color(0.24, 0.19, 0.34)); fm.set_shader_parameter("scale", 1.4)
	_box(Vector3(BlastSim.W * TILE, 0.1, BlastSim.H * TILE), fm, Vector3(0, -0.05, 0))
	var dark := _mat(Color(0.2, 0.16, 0.3), 0.95)
	for y in BlastSim.H:   # checker of darker carpet tiles
		for x in BlastSim.W:
			if (x + y) % 2 == 0: _box(Vector3(TILE * 0.96, 0.012, TILE * 0.96), dark, W(Vector2(x, y), 0.006))
	# floor beyond the arena + walls round it
	_box(Vector3(60, 0.1, 50), _mat(Color(0.1, 0.08, 0.14), 0.95), Vector3(0, -0.12, 0))
	var wall := _mat(Color(0.32, 0.3, 0.4), 0.8)
	var trim := _mat(Color(0.62, 0.38, 1.0), 0.4, 0.0, 0.7)
	var cyan := _mat(Color(0.13, 0.78, 0.92), 0.4, 0.0, 0.7)
	var hw := BlastSim.W * TILE / 2.0 + 0.35
	var hd := BlastSim.H * TILE / 2.0 + 0.35
	_box(Vector3(hw * 2.0 + 0.7, 1.4, 0.7), wall, Vector3(0, 0.7, -hd))
	_box(Vector3(hw * 2.0 + 0.7, 0.7, 0.7), wall, Vector3(0, 0.35, hd))
	_box(Vector3(0.7, 1.0, hd * 2.0), wall, Vector3(-hw, 0.5, 0))
	_box(Vector3(0.7, 1.0, hd * 2.0), wall, Vector3(hw, 0.5, 0))
	_box(Vector3(hw * 2.0 + 0.72, 0.06, 0.12), trim, Vector3(0, 1.42, -hd + 0.34))
	_box(Vector3(hw * 2.0 + 0.72, 0.06, 0.12), cyan, Vector3(0, 0.72, hd - 0.34))
	_box(Vector3(0.12, 0.06, hd * 2.0), trim, Vector3(-hw + 0.34, 1.02, 0))
	_box(Vector3(0.12, 0.06, hd * 2.0), cyan, Vector3(hw - 0.34, 1.02, 0))
	var mark: Texture2D = load("res://assets/brand/bnb_mark_trim.png")
	_box(Vector3(9.0, 3.2, 0.3), _mat(Color(0.12, 0.1, 0.18), 0.6), Vector3(0, 2.6, -hd - 0.6))
	var sp := Sprite3D.new(); sp.texture = mark; sp.pixel_size = 2.6 / mark.get_height(); sp.shaded = false
	sp.modulate = Color(1.3, 1.3, 1.3); sp.position = Vector3(0, 2.6, -hd - 0.43)
	world.add_child(sp)
	var title := Label3D.new(); title.text = "OFFICE BLAST"; title.font = font; title.font_size = 120; title.outline_size = 16
	title.modulate = Color(1.0, 0.81, 0.35); title.position = Vector3(0, 4.6, -hd - 0.5); title.pixel_size = 0.01
	world.add_child(title)
	# pillars: filing cabinets and server racks
	for y in BlastSim.H:
		for x in BlastSim.W:
			if x % 2 == 1 and y % 2 == 1: _pillar(Vector2i(x, y), (x + y) % 4 == 2)
	cam = Camera3D.new(); cam.fov = 45; cam.far = 120
	cam.environment = env
	world.add_child(cam)
	cam.position = CAM_POS
	cam.look_at(Vector3(0, 0, 0.1), Vector3.UP)
	cam.current = true


func _pillar(c: Vector2i, rack: bool) -> Node3D:
	var n := Node3D.new(); n.position = W(Vector2(c)); world.add_child(n)
	var s := TILE * 0.94
	if rack:
		_box(Vector3(s, 1.15, s), _mat(Color(0.16, 0.16, 0.22), 0.4, 0.5), Vector3(0, 0.575, 0), n)
		_box(Vector3(s * 1.02, 0.05, s * 1.02), _mat(Color(0.3, 0.3, 0.38), 0.4, 0.6), Vector3(0, 1.17, 0), n)
		for k in 3:
			_box(Vector3(s * 0.8, 0.04, 0.02), _mat([Color(0.2, 1, 0.4), Color(0.2, 0.7, 1)][k % 2], 0.3, 0.0, 2.0), Vector3(0, 0.3 + k * 0.28, s / 2.0 + 0.01), n)
	else:
		_box(Vector3(s, 1.05, s), _mat(Color(0.48, 0.5, 0.56), 0.45, 0.6), Vector3(0, 0.525, 0), n)
		for k in 3:   # drawers with handles
			_box(Vector3(s * 0.86, 0.02, 0.02), _mat(Color(0.3, 0.32, 0.36), 0.4, 0.7), Vector3(0, 0.33 + k * 0.32, s / 2.0 + 0.01), n)
			_box(Vector3(0.22, 0.05, 0.04), _mat(Color(0.85, 0.85, 0.9), 0.3, 0.8), Vector3(0, 0.22 + k * 0.32, s / 2.0 + 0.02), n)
	return n


## Breakable cover in three looks: a cardboard box stack, a cubicle panel, a water cooler.
func _breakable(c: Vector2i) -> Node3D:
	var n := Node3D.new(); n.position = W(Vector2(c)); world.add_child(n)
	var s := TILE * 0.9
	match (c.x * 7 + c.y * 13) % 5:
		0, 1, 2:
			var tan := _mat(Color(0.72, 0.53, 0.32).lerp(Color(0.82, 0.66, 0.42), float((c.x + c.y) % 3) / 3.0), 0.9)
			_box(Vector3(s, s * 0.5, s), tan, Vector3(0, s * 0.25, 0), n)
			_box(Vector3(s * 0.6, s * 0.3, s * 0.6), tan, Vector3(0.05, s * 0.5 + s * 0.15, -0.03), n).rotation.y = 0.3
			_box(Vector3(s * 0.12, 0.01, s + 0.01), _mat(Color(0.55, 0.42, 0.25), 0.6), Vector3(0, s * 0.5 + 0.005, 0), n)
		3:
			_box(Vector3(s, s * 0.75, s * 0.22), _mat(Color(0.45, 0.3, 0.62), 0.95), Vector3(0, s * 0.375, 0), n)
			_box(Vector3(s + 0.02, 0.05, s * 0.26), _mat(Color(0.7, 0.7, 0.74), 0.4, 0.5), Vector3(0, s * 0.75, 0), n)
			_box(Vector3(s * 0.5, s * 0.4, s * 0.4), _mat(Color(0.72, 0.53, 0.32), 0.9), Vector3(0.1, s * 0.2, s * 0.3), n)
		_:
			_box(Vector3(s * 0.6, s * 0.5, s * 0.6), _mat(Color(0.8, 0.8, 0.84), 0.5), Vector3(0, s * 0.25, 0), n)
			var bottle := _mat(Color(0.3, 0.55, 0.95), 0.15, 0.0)
			_cyl(s * 0.22, s * 0.25, s * 0.42, bottle, Vector3(0, s * 0.71, 0), n)
	return n


func _player_visual(p) -> Dictionary:
	var rig := Main.make_rig(p.C, 0)
	world.add_child(rig)
	rig.scale = Vector3.ONE * 1.0
	var col: Color = COLORS[p.id % 4]
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new(); tor.inner_radius = 0.38; tor.outer_radius = 0.46; tor.rings = 24
	ring.mesh = tor; ring.material_override = _mat(col, 0.4, 0.0, 2.0); ring.scale = Vector3(1, 0.3, 1)
	world.add_child(ring)
	var tag := Label3D.new()
	tag.text = _nm(p); tag.font = font; tag.font_size = 44; tag.outline_size = 10
	tag.modulate = col.lightened(0.25); tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tag.no_depth_test = true
	tag.pixel_size = 0.0065
	world.add_child(tag)
	return {rig = rig, tag = tag, ring = ring}


func _bomb_node() -> Node3D:
	# a BNB coffee mug packed with trouble: mug, purple band, handle, fuse with a spark
	var n := Node3D.new(); world.add_child(n)
	var body := _mat(Color(0.1, 0.09, 0.12), 0.35, 0.3)
	_cyl(0.3, 0.26, 0.5, body, Vector3(0, 0.27, 0), n)
	_cyl(0.305, 0.305, 0.1, _mat(Color(0.62, 0.38, 1.0), 0.4, 0.0, 0.8), Vector3(0, 0.3, 0), n)
	var h := MeshInstance3D.new(); var t := TorusMesh.new(); t.inner_radius = 0.09; t.outer_radius = 0.14
	h.mesh = t; h.material_override = body; h.rotation = Vector3(PI / 2, 0, 0); h.position = Vector3(0.32, 0.3, 0)
	n.add_child(h)
	_cyl(0.025, 0.025, 0.2, _mat(Color(0.75, 0.65, 0.45), 0.8), Vector3(0, 0.6, 0), n)
	var spark := _cyl(0.06, 0.06, 0.06, _mat(Color(1.0, 0.75, 0.2), 0.3, 0.0, 6.0), Vector3(0, 0.72, 0), n)
	spark.name = "spark"
	return n


func _flame_node() -> Node3D:
	var n := Node3D.new(); world.add_child(n)
	var outer := StandardMaterial3D.new()   # orange flame body, see-through at the edges
	outer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; outer.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer.albedo_color = Color(1.0, 0.38, 0.05, 0.85)
	var core := _box(Vector3(TILE * 0.92, 0.45, TILE * 0.92), outer, Vector3(0, 0.25, 0), n)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner := StandardMaterial3D.new()
	inner.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; inner.albedo_color = Color(1.0, 0.78, 0.25)
	var hot := _box(Vector3(TILE * 0.5, 0.62, TILE * 0.5), inner, Vector3(0, 0.33, 0), n)
	hot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tip := StandardMaterial3D.new()
	tip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; tip.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tip.albedo_color = Color(0.95, 0.15, 0.05, 0.6)
	var top := _box(Vector3(TILE * 0.7, 0.3, TILE * 0.7), tip, Vector3(0, 0.62, 0), n)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func _power_node(kind: String) -> Node3D:
	var n := Node3D.new(); world.add_child(n)
	var look: Array = POWER_LOOK[kind]
	var col: Color = look[1]
	_cyl(0.4, 0.4, 0.06, _mat(col.darkened(0.3), 0.4, 0.0, 0.6), Vector3(0, 0.08, 0), n)
	var icon := Node3D.new(); icon.name = "icon"; icon.position.y = 0.55; n.add_child(icon)
	match kind:
		"bomb":
			_cyl(0.16, 0.14, 0.26, _mat(Color(0.1, 0.09, 0.12), 0.35), Vector3.ZERO, icon)
			_cyl(0.165, 0.165, 0.06, _mat(col, 0.4, 0.0, 1.5), Vector3.ZERO, icon)
		"fire":
			_cyl(0.0, 0.2, 0.42, _mat(Color(1.0, 0.55, 0.15), 0.3, 0.0, 2.5), Vector3.ZERO, icon)
		"speed":
			_box(Vector3(0.36, 0.14, 0.18), _mat(col, 0.4, 0.0, 1.5), Vector3.ZERO, icon)
			_box(Vector3(0.12, 0.2, 0.18), _mat(col, 0.4, 0.0, 1.5), Vector3(-0.12, 0.14, 0), icon)
		_:
			_box(Vector3(0.38, 0.16, 0.2), _mat(col, 0.4, 0.0, 1.5), Vector3(0.05, -0.05, 0), icon)
			_box(Vector3(0.16, 0.3, 0.2), _mat(col, 0.4, 0.0, 1.5), Vector3(-0.07, 0.12, 0), icon)
	var l := Label3D.new(); l.text = String(look[0]); l.font = font; l.font_size = 40; l.outline_size = 8
	l.modulate = col.lightened(0.3); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.pixel_size = 0.005; l.position.y = 1.0
	n.add_child(l)
	return n


## Match the 3D floor to the sim's cells: boxes broken / rebuilt, sudden-death blocks dropping in.
func _sync_cells() -> void:
	for y in BlastSim.H:
		for x in BlastSim.W:
			var i := y * BlastSim.W + x
			var v: int = sim.cells[i]
			if v == BlastSim.BOX and not box_nodes.has(i): box_nodes[i] = _breakable(Vector2i(x, y))
			elif v != BlastSim.BOX and box_nodes.has(i):
				_burst(W(Vector2(x, y), 0.4), Color(0.75, 0.56, 0.34), 8)
				(box_nodes[i] as Node).queue_free(); box_nodes.erase(i)
			var pillar_spot := x % 2 == 1 and y % 2 == 1
			if v == BlastSim.PILLAR and not pillar_spot and not block_nodes.has(i):
				var b := _box(Vector3(TILE * 0.96, 1.2, TILE * 0.96), _mat(Color(0.36, 0.33, 0.44), 0.6, 0.3), W(Vector2(x, y), 9.0))
				_box(Vector3(TILE * 0.98, 0.06, TILE * 0.98), _mat(Color(0.75, 0.22, 0.4), 0.5), Vector3(0, 0.62, 0), b)   # hazard-red lid
				var tw := b.create_tween()
				tw.tween_property(b, "position:y", 0.6, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				block_nodes[i] = b
			elif v != BlastSim.PILLAR and block_nodes.has(i):
				(block_nodes[i] as Node).queue_free(); block_nodes.erase(i)


func _burst(at: Vector3, col: Color, n: int) -> void:
	for k in n:
		var d := _box(Vector3(0.14, 0.14, 0.14), _mat(col.lerp(Color.WHITE, rng.randf() * 0.2), 0.8), at)
		d.rotation = Vector3(rng.randf() * 3, rng.randf() * 3, 0)
		debris.append([d, Vector3(rng.randf_range(-3, 3), rng.randf_range(3, 6), rng.randf_range(-3, 3)), 0.9])


# ---------------------------------------------------------------- loop
func _physics_process(_dt: float) -> void:
	if sim == null or world == null: return
	if paused and net == null: return
	var mine: Dictionary = sim.ai(sim.players[me]) if autoplay else ({} if paused else _controls())
	if guest:
		net.send({t = "bi", i = mine})
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
	else:
		inputs[me] = mine
		sim.tick(inputs)
		var evs: Array = sim.events.duplicate()
		sim.events.clear()
		for e in evs:
			stats[e[0]] = stats.get(e[0], 0) + 1
			_event(e)
		if net != null:
			outbox.append_array(evs)
			if sim.tick_n % 2 == 0 or sim.state == "done":
				var pe := []
				for e in outbox: pe.append(Party.pack(e))
				net.broadcast({t = "bs", s = sim.snapshot(), e = pe})
				outbox.clear()
	if sim.state == "done" and not results_shown:
		results_shown = true
		await get_tree().create_timer(1.6).timeout
		if world != null: _show_results()


func _process(dt: float) -> void:
	if sim == null or world == null: return
	anim_t += dt
	_sync_cells()
	_draw_players(dt)
	_draw_bombs()
	_draw_flames()
	_draw_powers(dt)
	for d in debris.duplicate():
		var n: Node3D = d[0]
		d[1] += Vector3(0, -14.0, 0) * dt
		n.position += d[1] * dt
		n.rotation += Vector3(4, 3, 0) * dt
		d[2] -= dt
		if d[2] <= 0.0 or n.position.y < -0.2: n.queue_free(); debris.erase(d)
	shake = maxf(0.0, shake - dt * 2.4)
	cam.position = CAM_POS + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.25
	flash_l.light_energy = maxf(0.0, flash_l.light_energy - dt * 14.0)
	toast_t = maxf(0.0, toast_t - dt)
	hud.queue_redraw()


func _draw_players(dt: float) -> void:
	var a: float = Engine.get_physics_interpolation_fraction()
	for p in sim.players:
		var v: Dictionary = rigs[p.id]
		var rig = v.rig
		var pos: Vector2 = p.prev_pos.lerp(p.pos, a)
		rig.position = W(pos)
		var d: Vector2i = BlastSim.DIRS[p.facing]
		if d != Vector2i.ZERO: rig.rotation.y = lerp_angle(rig.rotation.y, atan2(float(d.x), float(d.y)), clampf(dt * 14.0, 0.0, 1.0))
		var t: float = rig.get_meta("t", 0.0) + dt
		rig.set_meta("t", t)
		var clip := ""
		var ct := 0.0
		var winner: bool = sim.state in ["roundend", "done"] and p.alive and (sim.round_winner == p.id or sim.match_winner == p.id)
		if not p.alive:
			clip = "ko" if ClipLib.has("ko") else "gun_death"
			ct = minf(p.dead_t / 60.0, Fighter._len(clip) - 0.05)
		elif winner:
			clip = Fighter.own_clip(p.C, "win", "win_fist_pump2")
			ct = fmod(t, Fighter._len(clip))
		elif p.moving:
			clip = "m_run" if ClipLib.has("m_run") else "step_forward"
			ct = fmod(t * (1.0 + p.speed * 0.15), Fighter._len(clip))
		else:
			clip = Fighter.own_clip(p.C, "idle", "idle_fight")
			ct = fmod(t, Fighter._len(clip))
		rig.set_clip(clip, ct, false, false)
		rig.apply_pose(p.C.pose.guard, true)
		rig.visible = p.alive or p.dead_t < 150
		var ring: Node3D = v.ring
		ring.visible = p.alive
		ring.position = W(pos, 0.04)
		var tag: Label3D = v.tag
		tag.position = W(pos, 2.25)
		tag.text = _nm(p) if p.alive else _nm(p) + "  · OUT"
		tag.modulate.a = 1.0 if p.alive else 0.5


func _draw_bombs() -> void:
	var alive := {}
	for b in sim.bombs:
		alive[b.uid] = true
		if not bomb_nodes.has(b.uid): bomb_nodes[b.uid] = _bomb_node()
		var n: Node3D = bomb_nodes[b.uid]
		var at: Vector2 = Vector2(b.cell) + Vector2(b.slide) * b.slide_p
		n.position = W(at)
		var hurry: float = 1.0 - float(b.t) / BlastSim.FUSE   # swells and pulses faster as the fuse burns down
		var pulse: float = 1.0 + sin(anim_t * (8.0 + hurry * 22.0)) * (0.05 + hurry * 0.1)
		n.scale = Vector3.ONE * pulse
		var spark: Node3D = n.get_node("spark")
		spark.scale = Vector3.ONE * (0.7 + randf() * 0.8)
		spark.position.y = 0.72 - hurry * 0.12
	for k in bomb_nodes.keys():
		if not alive.has(k): (bomb_nodes[k] as Node).queue_free(); bomb_nodes.erase(k)


func _draw_flames() -> void:
	for i in sim.flames:
		if not flame_nodes.has(i): flame_nodes[i] = _flame_node()
		var n: Node3D = flame_nodes[i]
		n.position = W(Vector2(i % BlastSim.W, i / BlastSim.W))
		var life: float = float(sim.flames[i]) / BlastSim.FLAME
		n.scale = Vector3(0.6 + life * 0.45, 0.4 + life * 1.0 + randf() * 0.15, 0.6 + life * 0.45)
	for k in flame_nodes.keys():
		if not sim.flames.has(k): (flame_nodes[k] as Node).queue_free(); flame_nodes.erase(k)


func _draw_powers(dt: float) -> void:
	for i in sim.powerups:
		if not power_nodes.has(i):
			power_nodes[i] = _power_node(String(sim.powerups[i]))
			(power_nodes[i] as Node3D).position = W(Vector2(i % BlastSim.W, i / BlastSim.W))
		var icon: Node3D = (power_nodes[i] as Node3D).get_node("icon")
		icon.rotation.y += dt * 2.5
		icon.position.y = 0.55 + sin(anim_t * 3.0 + i) * 0.08
	for k in power_nodes.keys():
		if not sim.powerups.has(k): (power_nodes[k] as Node).queue_free(); power_nodes.erase(k)


func _event(e: Array) -> void:
	match String(e[0]):
		"round":
			_toast("ROUND %d" % int(e[3]), "Last one standing wins it", Color(1.0, 0.81, 0.35), 2.0)
		"count": _toast(str(int(e[3])), "", Color.WHITE, 0.9); G.sfx("ui")
		"go": _toast("GO!", "", Color(0.35, 1.0, 0.5), 0.9); G.sfx("vs")
		"bomb": G.sfx("grab")
		"kick": G.sfx("whoosh")
		"boom":
			flash_l.position = W(Vector2(int(e[1]), int(e[2])), 1.2); flash_l.light_energy = 6.0
			shake = minf(1.0, shake + 0.55)
			G.sfx("heavy")
		"power": G.sfx("ok")
		"out":
			var who = sim.players[int(e[3])]
			var by: int = int(e[4])
			var how: String = "blew themselves up" if by == int(e[3]) else ("was flattened" if by == -2 else "got blasted")
			if by >= 0 and by != int(e[3]): how = "got blasted by " + _nm(sim.players[by])
			_toast("", "%s %s" % [_nm(who), how], COLORS[int(e[3]) % 4], 1.6)
			G.sfx("ko")
			var s: AudioStream = Voices.get_sound(who.C, "ko")
			if s != null:
				var ap := AudioStreamPlayer.new(); ap.stream = s; ap.volume_db = -6.0
				add_child(ap); ap.play(); ap.finished.connect(ap.queue_free)
		"roundwin":
			var w: int = int(e[3])
			if w < 0: _toast("DRAW!", "Nobody made it out", Color(0.85, 0.85, 0.95), 3.0)
			else: _toast("%s WINS THE ROUND!" % _nm(sim.players[w]), "%d / %d" % [sim.players[w].wins, BlastSim.WINS], COLORS[w % 4], 3.0)
			G.sfx("surge")
		"drop": shake = minf(1.0, shake + 0.15); G.sfx("thud")
		"done": G.sfx("ko")


func _toast(t: String, sub: String, col: Color, dur: float) -> void:
	if t != "" or toast_t <= 0.0: toast = t
	toast_sub = sub; toast_col = col; toast_t = dur


func _nm(p) -> String:
	return String(p.C.person.get("short", p.C.name)).to_upper() if p.C.has("person") else String(p.C.name)


# ---------------------------------------------------------------- input
const KEY_DIR := {KEY_W: 1, KEY_UP: 1, KEY_S: 2, KEY_DOWN: 2, KEY_A: 3, KEY_LEFT: 3, KEY_D: 4, KEY_RIGHT: 4}


func _unhandled_input(e: InputEvent) -> void:
	if sim == null: return
	if e is InputEventKey and not e.echo:
		var d: int = KEY_DIR.get(e.physical_keycode, 0)
		if d != 0:
			key_dirs.erase(d)
			if e.pressed: key_dirs.append(d)
		if e.pressed and e.physical_keycode in [KEY_P, KEY_ESCAPE]: toggle_pause()


func _controls() -> Dictionary:
	var still := []   # drop keys released while the window lost focus
	for k in key_dirs:
		var keys: Array = {1: [KEY_W, KEY_UP], 2: [KEY_S, KEY_DOWN], 3: [KEY_A, KEY_LEFT], 4: [KEY_D, KEY_RIGHT]}[k]
		if Input.is_physical_key_pressed(keys[0]) or Input.is_physical_key_pressed(keys[1]): still.append(k)
	key_dirs = still
	var d: int = int(key_dirs[-1]) if not key_dirs.is_empty() else 0
	var bomb: bool = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_J)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var pd: int = pads[0]
		var ax := Vector2(Input.get_joy_axis(pd, JOY_AXIS_LEFT_X), Input.get_joy_axis(pd, JOY_AXIS_LEFT_Y))
		if Input.is_joy_button_pressed(pd, JOY_BUTTON_DPAD_UP): ax = Vector2(0, -1)
		elif Input.is_joy_button_pressed(pd, JOY_BUTTON_DPAD_DOWN): ax = Vector2(0, 1)
		elif Input.is_joy_button_pressed(pd, JOY_BUTTON_DPAD_LEFT): ax = Vector2(-1, 0)
		elif Input.is_joy_button_pressed(pd, JOY_BUTTON_DPAD_RIGHT): ax = Vector2(1, 0)
		if ax.length() > 0.4: d = _dir_of(ax)
		bomb = bomb or Input.is_joy_button_pressed(pd, JOY_BUTTON_A) or Input.is_joy_button_pressed(pd, JOY_BUTTON_B)
		if Input.is_joy_button_pressed(pd, JOY_BUTTON_START) and not paused: toggle_pause()
	if _touch():
		if touch_move.length() > 0.3: d = _dir_of(touch_move)
		bomb = bomb or bomb_touch >= 0
	return {d = d, b = bomb}


static func _dir_of(v: Vector2) -> int:
	if absf(v.x) > absf(v.y): return 4 if v.x > 0 else 3
	return 2 if v.y > 0 else 1


func _touch() -> bool:
	return G.ui.touch_enabled


func _layout_touch() -> void:
	var s: Vector2 = G.get_viewport().get_visible_rect().size
	var r := clampf(s.y * 0.1, 44.0, 80.0)
	touch_btn = {bomb = {c = Vector2(s.x - r * 1.9, s.y - r * 1.9), r = r * 1.15}, pause = {c = Vector2(s.x - 50, 116), r = 30.0}}


func _input(e: InputEvent) -> void:
	if sim == null or not _touch(): return
	if e is InputEventScreenTouch:
		var vs: Vector2 = G.get_viewport().get_visible_rect().size
		if e.pressed:
			if e.position.distance_to(touch_btn.pause.c) < touch_btn.pause.r * 1.2: toggle_pause(); return
			if e.position.distance_to(touch_btn.bomb.c) < touch_btn.bomb.r * 1.2: bomb_touch = e.index; return
			if e.position.x < vs.x * 0.5 and move_id < 0: move_id = e.index; move_origin = e.position; touch_move = Vector2.ZERO
		else:
			if e.index == move_id: move_id = -1; touch_move = Vector2.ZERO
			if e.index == bomb_touch: bomb_touch = -1
	elif e is InputEventScreenDrag and e.index == move_id:
		touch_move = ((e.position - move_origin) / 70.0).limit_length(1.0)


# ---------------------------------------------------------------- HUD
func _draw_hud() -> void:
	var sz := hud.size
	var ink := Color(0.95, 0.96, 1.0)
	# player cards: two on the left of the clock, two on the right
	var n: int = sim.players.size()
	var cw := 230.0
	for k in n:
		var p = sim.players[k]
		var col: Color = COLORS[k % 4]
		# cards sit on the side of the arena where the player started (left corners left, right corners right)
		var sp: Vector2i = BlastSim.SPAWNS[k % 4]
		var row := 0 if sp.y == 0 else 1
		var x: float = 20.0 + row * (cw + 10.0) if sp.x == 0 else sz.x - 20.0 - cw - row * (cw + 10.0)
		var r := Rect2(Vector2(x, 14), Vector2(cw, 70))
		hud.draw_rect(r, Color(0.04, 0.03, 0.08, 0.78))
		hud.draw_rect(Rect2(r.position, Vector2(6, r.size.y)), col)
		if k == me and not autoplay: hud.draw_rect(r, Color(col, 0.9), false, 2.0)
		var nm: String = _nm(p) + ("  (YOU)" if k == me and not autoplay else ("" if p.human else "  · CPU"))
		hud.draw_string(font, r.position + Vector2(16, 27), nm, HORIZONTAL_ALIGNMENT_LEFT, cw - (84 if not p.alive else 24), 19, ink if p.alive else Color(ink, 0.45))
		for w in BlastSim.WINS:   # round wins
			hud.draw_circle(r.position + Vector2(24 + w * 20, 48), 7.0, col if w < p.wins else Color(1, 1, 1, 0.15))
		var st: String = "B%d  F%d  S%d%s" % [p.bombs, p.fire, p.speed, "  KICK" if p.kick else ""]
		hud.draw_string(small, r.position + Vector2(24 + BlastSim.WINS * 20, 54), st, HORIZONTAL_ALIGNMENT_LEFT, cw - 90, 17, Color(0.82, 0.85, 0.95))
		if not p.alive:
			hud.draw_rect(Rect2(r.position + Vector2(cw - 58, 6), Vector2(50, 22)), Color(0.6, 0.1, 0.15, 0.9))
			hud.draw_string(font, r.position + Vector2(cw - 58, 23), "OUT", HORIZONTAL_ALIGNMENT_CENTER, 50, 15, Color.WHITE)
	# round + clock
	var mid := sz.x / 2.0
	hud.draw_rect(Rect2(Vector2(mid - 110, 14), Vector2(220, 60)), Color(0.04, 0.03, 0.08, 0.78))
	var left: float = maxf(0.0, BlastSim.ROUND_TIME - sim.time)
	var sd: bool = sim.time >= BlastSim.ROUND_TIME
	hud.draw_string(font, Vector2(mid - 110, 48), ("%d:%02d" % [int(left) / 60, int(left) % 60]) if not sd else "SUDDEN DEATH", HORIZONTAL_ALIGNMENT_CENTER, 220, 26 if not sd else 20, ink if not sd else Color(1, 0.4, 0.5))
	hud.draw_string(small, Vector2(mid - 110, 68), "ROUND %d  ·  FIRST TO %d" % [sim.round_n, BlastSim.WINS], HORIZONTAL_ALIGNMENT_CENTER, 220, 16, Color(0.78, 0.8, 0.9))
	# big centre message
	if toast_t > 0.0:
		var a := clampf(toast_t * 2.0, 0.0, 1.0)
		var y := sz.y * 0.42
		if toast != "":
			hud.draw_string(font, Vector2(3, y + 3), toast, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 72, Color(0, 0, 0, 0.6 * a))
			hud.draw_string(font, Vector2(0, y), toast, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 72, Color(toast_col, a))
		if toast_sub != "":
			var sy := y + (46.0 if toast != "" else 0.0)
			hud.draw_string(font, Vector2(2, sy + 2), toast_sub, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 28, Color(0, 0, 0, 0.6 * a))
			hud.draw_string(font, Vector2(0, sy), toast_sub, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 28, Color(toast_col.lightened(0.3), a))
	var mp = sim.players[me]
	if not mp.alive and sim.state == "play" and not autoplay:
		hud.draw_string(font, Vector2(0, sz.y - 70), "YOU'RE OUT  ·  WATCHING", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 26, Color(1, 0.6, 0.6))
	if not _touch():
		hud.draw_string(small, Vector2(0, sz.y - 10), "WASD / ARROWS move  ·  SPACE / E drop a bomb  ·  P pause   ·   pad: stick / d-pad + A", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 17, Color(0.8, 0.82, 0.9, 0.65))
	else:
		if move_id >= 0:
			hud.draw_arc(move_origin, 70.0, 0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
			hud.draw_circle(move_origin + touch_move * 70.0, 28.0, Color(0.62, 0.38, 1.0, 0.5))
		var b: Dictionary = touch_btn.bomb
		hud.draw_circle(b.c, b.r, Color(1.0, 0.45, 0.2, 0.55 if bomb_touch >= 0 else 0.25))
		hud.draw_arc(b.c, b.r, 0, TAU, 40, Color(1.0, 0.6, 0.3, 0.95), 3.0)
		hud.draw_string(font, b.c + Vector2(-b.r, 10), "BOMB", HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, 26, Color.WHITE)
		var pz: Dictionary = touch_btn.pause
		hud.draw_circle(pz.c, pz.r, Color(0, 0, 0, 0.4))
		hud.draw_string(font, pz.c + Vector2(-pz.r, 9), "II", HORIZONTAL_ALIGNMENT_CENTER, pz.r * 2.0, 24, Color.WHITE)


# ---------------------------------------------------------------- multiplayer
func _net_message(pid: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"bi":
			if guest or not pid_slot.has(pid) or not (d.get("i") is Dictionary): return
			for p in sim.players:
				if p.human and p.slot == int(pid_slot[pid]): inputs[p.id] = d.i
		"bs":
			if guest: inbox.append(d)


func _net_left(pid: int) -> void:
	if not pid_slot.has(pid): return
	for p in sim.players:
		if p.slot == int(pid_slot[pid]) and p.human:
			p.human = false
			inputs.erase(p.id)
			_toast("", "%s LEFT · A CPU PLAYS ON" % _nm(p), Color(1, 0.6, 0.4), 2.5)


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
	var w: int = sim.match_winner
	if w >= 0: v.add_child(ui.lbl("%s WINS!" % _nm(sim.players[w]), 48, font, COLORS[w % 4], 8))
	else: v.add_child(ui.lbl("NO WINNER", 48, font, Color(0.85, 0.85, 0.95), 8))
	var order: Array = sim.players.duplicate()
	order.sort_custom(func(a, b): return a.wins > b.wins)
	for p in order:
		v.add_child(ui.lbl("%s   %d round%s%s" % [_nm(p), p.wins, "" if p.wins == 1 else "s", "" if p.human else "  · CPU"], 24, font, (COLORS[p.id % 4] as Color).lightened(0.3)))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 14)
	var gg = G
	if net != null:
		btns.add_child(ui.big_btn("BACK TO LOBBY", Color(0.13, 0.78, 0.92), func(): finished.emit(); gg.lobby.back_to_lobby()))
		btns.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), func(): finished.emit(); gg.lobby.leave()))
	else:
		var C: Dictionary = sim.players[me].C
		var others: int = sim.players.size() - 1
		btns.add_child(ui.big_btn("PLAY AGAIN", Color(0.13, 0.78, 0.92), func(): finished.emit(); gg.start_party("blast", C, others, false)))
		btns.add_child(ui.big_btn("MAIN MENU", Color(0.55, 0.62, 0.75), func(): finished.emit(); gg.ui.show_title()))
	v.add_child(btns)
	_center(panel)
	(btns.get_child(0) as Button).call_deferred("grab_focus")


# ---------------------------------------------------------------- tests
## --autotest=blast: a CPU-only match; screenshots at the start, mid-blast, late round and the result.
func autotest(shot: Callable) -> void:
	var tree: SceneTree = G.get_tree()
	var wait_ticks := func(cond: Callable, cap: int) -> void:   # game ticks, not wall time: works on slow machines
		var n := 0
		while not cond.call() and n < cap:
			await tree.physics_frame; n += 1
	await wait_ticks.call(func(): return sim.state != "count", 600)
	for k in 60: await tree.physics_frame
	await shot.call("blast_0_start")
	var booms: int = stats.get("boom", 0)
	await wait_ticks.call(func(): return stats.get("boom", 0) > booms, 2400)
	for k in 3: await tree.physics_frame
	await shot.call("blast_1_boom")
	await wait_ticks.call(func(): return sim.state != "play" or sim.time > 28.0, 4000)
	await shot.call("blast_2_late")
	Engine.max_physics_steps_per_frame = 64; Engine.time_scale = 8.0   # fast-forward to the end of the round
	await wait_ticks.call(func(): return sim.state == "roundend" or sim.state == "done", 9000)
	Engine.time_scale = 1.0; Engine.max_physics_steps_per_frame = 8
	for k in 50: await tree.physics_frame
	await shot.call("blast_3_round")
	print("AUTOTEST blast round=%d state=%s wins=%s simstats=%s" % [sim.round_n, sim.state, sim.players.map(func(p): return p.wins), sim.stats])


## --autotest=blastsim: whole matches between CPUs on the sim alone, determinism, snapshot round trip.
func selftest(_main) -> void:
	var roster: Array = Data.ROSTER
	var ok := true
	var winners := []
	var rounds := 0
	var round_ticks := 0
	var suicides := 0
	var kills := 0
	var matches := 0
	for setup in [[4, 11], [4, 23], [2, 5], [2, 9], [3, 31]]:
		var n: int = setup[0]
		var people := []
		for k in n: people.append({C = roster[k], human = false, slot = -1})
		var s = BlastSim.new()
		s.setup(people, setup[1])
		var guard := 0
		while s.state != "done" and guard < 60 * 60 * 30:
			s.tick({}); guard += 1
		matches += 1
		if s.state != "done": ok = false; print("AUTOTEST blastsim match did not finish (n=%d seed=%d round=%d)" % [n, setup[1], s.round_n])
		winners.append(s.match_winner)
		rounds += s.stats.rounds; round_ticks += s.stats.round_ticks; suicides += s.stats.suicides; kills += s.stats.kills
	# determinism: the same seed plays out the same
	var snaps := []
	for rep in 2:
		var people := []
		for k in 4: people.append({C = roster[k], human = false, slot = -1})
		var s = BlastSim.new()
		s.setup(people, 77)
		for t in 60 * 40: s.tick({})
		snaps.append(JSON.stringify(s.snapshot()))
	var det: bool = snaps[0] == snaps[1]
	# snapshot -> apply on a guest copy gives the same state
	var people2 := []
	for k in 4: people2.append({C = roster[k], human = false, slot = -1})
	var host = BlastSim.new(); host.setup(people2, 13)
	for t in 60 * 25: host.tick({})
	var gc = BlastSim.new(); gc.setup(people2, 999)
	var sn: Dictionary = JSON.parse_string(JSON.stringify(host.snapshot()))
	gc.apply(sn)
	var rt: bool = JSON.stringify(gc.snapshot()) == JSON.stringify(host.snapshot())
	ok = ok and det and rt
	print("AUTOTEST blastsim matches=%d winners=%s rounds=%d avg_round_s=%.1f kills=%d suicides=%d deterministic=%s roundtrip=%s  %s" % [
		matches, winners, rounds, float(round_ticks) / maxf(1.0, rounds) / 60.0, kills, suicides, det, rt, "PASS" if ok else "FAIL"])
