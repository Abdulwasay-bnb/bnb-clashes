class_name OpsGame
extends Node
## BNB Office Ops: first-person team deathmatch. Runs an OpsSim at 60 ticks/s with the player's controls,
## draws the office floor, the other soldiers (their own characters, animated), your gun, scope and HUD.

signal finished

const TEAM_COL := [Color(0.62, 0.38, 1.0), Color(0.13, 0.78, 0.92)]
const TEAM_NAME := ["TEAM BIT", "TEAM BYTE"]
const ENEMY_RED := Color(1.0, 0.12, 0.1)
const MATE_BLUE := Color(0.25, 0.65, 1.0)

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
var item_tags: Array = []       # [{it, tag}] on the loadout tables
var nade_nodes := {}            # thrown grenade uid -> node
var fire_nodes := {}            # fire uid -> node
var shake := 0.0
var white := 0.0                # flashbang white-out on screen


# multiplayer: the host runs the match and streams it; guests send their controls and aim
var net: Party = null
var guest := false
var pid_of := {}            # host: guest pid -> soldier id
var inputs := {}            # host: soldier id -> latest controls
var outbox: Array = []
var inbox: Array = []
var aim := Vector2.ZERO     # guest: own yaw / pitch


var map_id := "office"


func start(g, team_a: Array, team_b: Array, primary: String, skill: float, map := "office") -> void:
	map_id = map
	_begin(g, team_a, team_b, {0: 0}, {0: primary}, skill, randi())


## Online / Wi-Fi match. humans: soldier id -> player slot, loadouts: soldier id -> primary gun.
func start_net(g, team_a: Array, team_b: Array, humans: Dictionary, loadouts: Dictionary, skill: float, seed: int, my_id: int,
		party: Party, is_guest: bool, pids: Dictionary, map := "office") -> void:
	net = party; guest = is_guest; pid_of = pids; me = my_id; map_id = map
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
	sim.setup(team_a, team_b, humans, loadouts, seed, map_id)
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


## Floor material with a little noise (carpet, concrete, asphalt, gravel), reusing the race ground shader.
func _floor_mat(a: Color, b: Color, scale := 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/race_ground.gdshader")
	m.set_shader_parameter("col_a", a); m.set_shader_parameter("col_b", b); m.set_shader_parameter("scale", scale)
	return m


func _build_map() -> void:
	var id := sim.map_id
	var B := sim.bounds
	var W := B.size.x + 8.0
	var D := B.size.y + 8.0
	var mid := Vector3(B.get_center().x, 0, B.get_center().y)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true; env.glow_intensity = 0.3; env.glow_hdr_threshold = 1.2
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 50
	match id:
		"rooftop":
			var sky := Sky.new(); var sm := ProceduralSkyMaterial.new()
			sm.sky_top_color = Color(0.15, 0.2, 0.45); sm.sky_horizon_color = Color(1.0, 0.6, 0.4)
			sm.ground_bottom_color = Color(0.1, 0.08, 0.12); sm.ground_horizon_color = Color(0.5, 0.35, 0.35)
			sky.sky_material = sm; env.background_mode = Environment.BG_SKY; env.sky = sky
			sm.sky_top_color = Color(0.12, 0.22, 0.5); sm.sky_horizon_color = Color(0.85, 0.62, 0.5)
			env.ambient_light_color = Color(0.68, 0.7, 0.8); env.ambient_light_energy = 0.4
			env.fog_enabled = true; env.fog_density = 0.0012; env.fog_light_color = Color(0.6, 0.55, 0.6)
			env.tonemap_exposure = 0.9
			sun.rotation = Vector3(deg_to_rad(-32), deg_to_rad(55), 0); sun.light_energy = 0.95; sun.light_color = Color(1.0, 0.86, 0.72)
		"warehouse":
			env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.04, 0.04, 0.05)
			env.ambient_light_color = Color(0.7, 0.72, 0.8); env.ambient_light_energy = 0.35
			sun.rotation = Vector3(deg_to_rad(-70), deg_to_rad(20), 0); sun.light_energy = 0.55; sun.light_color = Color(1.0, 0.95, 0.85)
		"garage":
			env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.03, 0.03, 0.04)
			env.ambient_light_color = Color(0.6, 0.7, 0.75); env.ambient_light_energy = 0.32
			sun.light_energy = 0.0
		_:
			env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.05, 0.04, 0.08)
			env.ambient_light_color = Color(0.72, 0.72, 0.82); env.ambient_light_energy = 0.42
			sun.rotation = Vector3(deg_to_rad(-62), deg_to_rad(25), 0); sun.light_energy = 0.45
	we.environment = env
	world.add_child(we)
	if sun.light_energy > 0.0: world.add_child(sun)
	# floor
	var floor_m: Material = {"office": _floor_mat(Color(0.25, 0.22, 0.34), Color(0.2, 0.18, 0.28), 1.6),
		"warehouse": _floor_mat(Color(0.5, 0.5, 0.52), Color(0.42, 0.42, 0.44), 0.25),
		"garage": _floor_mat(Color(0.3, 0.3, 0.32), Color(0.24, 0.24, 0.26), 0.35),
		"rooftop": _floor_mat(Color(0.48, 0.46, 0.45), Color(0.38, 0.37, 0.37), 0.9)}.get(id)
	_box(Vector3(W, 0.1, D), floor_m, mid + Vector3(0, -0.05, 0))
	# floor markings
	match id:
		"warehouse":   # yellow lane lines along the aisles
			for z in [-10.0, 0.0, 10.0, -20.0, 20.0]:
				_box(Vector3(B.size.x, 0.012, 0.15), _mat(Color(0.95, 0.75, 0.1), 0.6), Vector3(mid.x, 0.01, z + 0.0))
		"garage":      # bay lines and arrows
			for z in [-18.0, -10.0, 10.0, 18.0]:
				for x in range(-22, 24, 3):
					_box(Vector3(0.1, 0.012, 4.6), _mat(Color(0.9, 0.9, 0.9), 0.6), Vector3(x - 1.5, 0.01, z))
			_box(Vector3(B.size.x, 0.012, 0.15), _mat(Color(0.95, 0.8, 0.2), 0.6), Vector3(mid.x, 0.01, -5.0))
			_box(Vector3(B.size.x, 0.012, 0.15), _mat(Color(0.95, 0.8, 0.2), 0.6), Vector3(mid.x, 0.01, 5.0))
		"rooftop":     # the helipad
			var hp := CylinderMesh.new(); hp.top_radius = 5.0; hp.bottom_radius = 5.0; hp.height = 0.04
			var hm := MeshInstance3D.new(); hm.mesh = hp; hm.material_override = _mat(Color(0.2, 0.22, 0.25), 0.7); hm.position = Vector3(0, 0.02, 0)
			world.add_child(hm)
			var ring := MeshInstance3D.new(); var tr := TorusMesh.new(); tr.inner_radius = 4.3; tr.outer_radius = 4.55; ring.mesh = tr
			ring.material_override = _mat(Color(0.95, 0.8, 0.2), 0.5); ring.position = Vector3(0, 0.03, 0); ring.scale = Vector3(1, 0.05, 1)
			world.add_child(ring)
			var hl := Label3D.new(); hl.text = "H"; hl.font = font; hl.font_size = 600; hl.modulate = Color(0.95, 0.95, 0.95)
			hl.rotation = Vector3(-PI / 2, 0, 0); hl.position = Vector3(0, 0.05, 0); hl.pixel_size = 0.01; hl.outline_size = 0
			world.add_child(hl)
	# ceiling and lights (indoor maps)
	if sim.ceiling > 0.0:
		_box(Vector3(W, 0.1, D), _mat(Color(0.8, 0.8, 0.83) if id == "office" else Color(0.3, 0.3, 0.32), 0.9), mid + Vector3(0, sim.ceiling + 0.05, 0))
		var step := 8 if id != "warehouse" else 10
		for x in range(int(B.position.x), int(B.end.x) + 1, step):
			for z in range(int(B.position.y) + 1, int(B.end.y), step):
				var lc := Color(1, 0.97, 0.92) if id != "garage" else Color(0.85, 0.95, 1.0)
				_box(Vector3(2.4 if id != "warehouse" else 1.2, 0.05, 0.6), _mat(lc, 0.3, 0.0, 2.4), Vector3(x, sim.ceiling - 0.02, z))
				var l := OmniLight3D.new(); l.position = Vector3(x, sim.ceiling - 0.4, z)
				l.omni_range = 9.0 if id != "warehouse" else 12.0; l.light_energy = 0.55 if id == "office" else 0.75; l.light_color = lc
				world.add_child(l)
		if id == "warehouse":   # skylight strips letting the daylight in
			for z in [-10.0, 10.0]:
				_box(Vector3(B.size.x, 0.06, 2.5), _mat(Color(0.8, 0.9, 1.0), 0.2, 0.0, 1.5), Vector3(mid.x, sim.ceiling + 0.02, z))
	else:   # rooftop: the city all around, down below
		var win := ShaderMaterial.new(); win.shader = load("res://shaders/windows.gdshader")
		var rng := RandomNumberGenerator.new(); rng.seed = 5
		for k in 40:
			var a := TAU * k / 40.0
			var r := rng.randf_range(70, 130)
			var h := rng.randf_range(20, 70)
			_box(Vector3(rng.randf_range(10, 20), h, rng.randf_range(10, 20)), win, Vector3(cos(a) * r, h / 2.0 - 30.0, sin(a) * r))
	_build_blocks(id)
	_build_tables()
	_decor(id)


## Every block of cover in the look of what it is.
func _build_blocks(id: String) -> void:
	var glass := _mat(Color(0.6, 0.75, 0.95), 0.05, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glass.albedo_color.a = 0.25
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	var wall_c: Color = {"office": Color(0.72, 0.7, 0.76), "warehouse": Color(0.55, 0.52, 0.48), "garage": Color(0.5, 0.5, 0.52), "rooftop": Color(0.55, 0.53, 0.52)}.get(id)
	for i in sim.boxes.size():
		var b: AABB = sim.boxes[i]
		var kind: String = sim.kinds[i] if i < sim.kinds.size() else "desk"
		var c: Vector3 = b.position + b.size / 2.0
		var h: float = b.size.y
		match kind:
			"loadout": pass   # drawn by _build_tables
			"wall":
				_box(b.size, _mat(wall_c, 0.9), c)
				_box(Vector3(b.size.x + 0.02, 0.15, b.size.z + 0.02), _mat(wall_c.darkened(0.4), 0.6), Vector3(c.x, 0.075, c.z))   # skirting
			"pillar":
				_box(b.size, _mat(Color(0.78, 0.78, 0.82) if id == "office" else Color(0.6, 0.6, 0.6), 0.7), c)
				if id == "garage":   # hazard stripes at the foot
					for k in 3: _box(b.size + Vector3(0.02, -b.size.y + 0.15, 0.02), _mat([Color(0.95, 0.8, 0.1), Color(0.1, 0.1, 0.1)][k % 2], 0.6), Vector3(c.x, 0.1 + k * 0.17, c.z))
			"glass": _box(b.size, glass, c)
			"rack":
				_box(b.size, _mat(Color(0.1, 0.1, 0.13), 0.4, 0.5), c)
				for k in 5:
					_box(Vector3(b.size.x + 0.02, 0.03, 0.3), _mat([Color(0.2, 1, 0.4), Color(0.2, 0.7, 1)][k % 2], 0.3, 0.0, 3.0), c + Vector3(0, -0.8 + k * 0.35, 0))
			"cubicle":
				_box(b.size, _mat(Color(0.45, 0.3, 0.62), 0.95), c)
				_box(Vector3(b.size.x + 0.02, 0.06, b.size.z + 0.04), _mat(Color(0.75, 0.75, 0.78), 0.4, 0.5), c + Vector3(0, h / 2.0, 0))   # top trim
			"desk":
				_box(Vector3(b.size.x, 0.06, b.size.z), _mat(Color(0.62, 0.48, 0.34), 0.5), c + Vector3(0, h / 2.0 - 0.03, 0))
				_box(Vector3(b.size.x - 0.1, h - 0.06, b.size.z - 0.1), _mat(Color(0.3, 0.3, 0.33), 0.6, 0.4), c - Vector3(0, 0.03, 0))
				if b.size.x > 1.5:   # monitor, keyboard, a chair
					_box(Vector3(0.6, 0.38, 0.04), _mat(Color(0.05, 0.05, 0.07), 0.4), c + Vector3(0, 0.6, 0))
					_box(Vector3(0.55, 0.32, 0.02), _mat(TEAM_COL[int(c.x > 0)], 0.3, 0.0, 1.2), c + Vector3(0, 0.6, 0.025))
					_box(Vector3(0.45, 0.02, 0.15), _mat(Color(0.15, 0.15, 0.17), 0.5), c + Vector3(0, 0.42, 0.25))
					_box(Vector3(0.5, 0.08, 0.5), _mat(Color(0.12, 0.12, 0.15), 0.7), c + Vector3(0.2, -0.05, 0.9))
					_box(Vector3(0.5, 0.55, 0.08), _mat(Color(0.12, 0.12, 0.15), 0.7), c + Vector3(0.2, 0.25, 1.12))
			"shelf":   # steel uprights, four shelves loaded with boxes
				var steel := _mat(Color(0.2, 0.35, 0.6), 0.5, 0.5)
				var orange := _mat(Color(0.95, 0.5, 0.15), 0.5, 0.4)
				var n := int(b.size.x / 2.5)
				for k in n + 1:
					var x := b.position.x + k * b.size.x / n
					for zz in [b.position.z + 0.05, b.end.z - 0.05]:
						_box(Vector3(0.1, h, 0.1), steel, Vector3(x, h / 2.0, zz))
				for lv in 4:
					var y := 0.15 + lv * 1.15
					_box(Vector3(b.size.x, 0.08, b.size.z), orange, Vector3(c.x, y, c.z))
					var bx := b.position.x + 0.3
					while bx < b.end.x - 0.4:
						var w := rng.randf_range(0.5, 1.1)
						if rng.randf() < 0.82:
							var bh := rng.randf_range(0.4, 0.9)
							_box(Vector3(w * 0.9, bh, b.size.z * 0.8), _mat(Color(0.7, 0.55, 0.35).lerp(Color(0.85, 0.75, 0.6), rng.randf()), 0.9), Vector3(bx + w / 2.0, y + 0.04 + bh / 2.0, c.z))
						bx += w
			"crate":
				var wood := _mat(Color(0.62, 0.45, 0.25), 0.85)
				_box(b.size, wood, c)
				for yy in range(int(h / 1.5)):   # dark plank bands and the stencil
					_box(Vector3(b.size.x + 0.02, 0.08, b.size.z + 0.02), _mat(Color(0.4, 0.28, 0.15), 0.85), Vector3(c.x, 0.1 + yy * 1.5, c.z))
					_box(Vector3(b.size.x + 0.02, 0.08, b.size.z + 0.02), _mat(Color(0.4, 0.28, 0.15), 0.85), Vector3(c.x, 1.4 + yy * 1.5, c.z))
			"pallet":
				_box(b.size, _mat(Color(0.7, 0.55, 0.32), 0.9), c)
				_box(Vector3(b.size.x * 0.9, 0.6, b.size.z * 0.9), _mat(Color(0.85, 0.85, 0.82), 0.6), c + Vector3(0, 0.55, 0))   # wrapped load
			"forklift":
				var yel := _mat(Color(0.95, 0.75, 0.1), 0.5, 0.3)
				_box(Vector3(b.size.x, 1.0, b.size.z), yel, Vector3(c.x, 0.5, c.z))
				_box(Vector3(b.size.x, 0.08, b.size.z * 0.6), _mat(Color(0.15, 0.15, 0.17), 0.5, 0.6), Vector3(c.x, h - 0.04, c.z - 0.3))   # roof
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						_box(Vector3(0.06, h - 1.0, 0.06), _mat(Color(0.15, 0.15, 0.17), 0.5, 0.6), Vector3(c.x + sx * b.size.x * 0.42, 1.0 + (h - 1.0) / 2.0, c.z - 0.3 + sz * b.size.z * 0.28))
				_box(Vector3(b.size.x * 0.8, 2.0, 0.12), _mat(Color(0.2, 0.2, 0.22), 0.5, 0.7), Vector3(c.x, 1.0, b.end.z + 0.05))   # mast
				_box(Vector3(0.12, 0.06, 1.0), _mat(Color(0.3, 0.3, 0.32), 0.5, 0.7), Vector3(c.x - 0.3, 0.1, b.end.z + 0.55))
				_box(Vector3(0.12, 0.06, 1.0), _mat(Color(0.3, 0.3, 0.32), 0.5, 0.7), Vector3(c.x + 0.3, 0.1, b.end.z + 0.55))
			"car":
				var col: Color = [Color(0.7, 0.1, 0.12), Color(0.15, 0.3, 0.65), Color(0.85, 0.85, 0.88), Color(0.1, 0.1, 0.12), Color(0.95, 0.75, 0.15), Color(0.2, 0.5, 0.3)][rng.randi() % 6]
				_box(Vector3(b.size.x, 0.75, b.size.z), _mat(col, 0.3, 0.5), Vector3(c.x, 0.55, c.z))
				_box(Vector3(b.size.x * 0.9, 0.55, b.size.z * 0.55), _mat(Color(0.2, 0.25, 0.3), 0.1, 0.4), Vector3(c.x, 1.18, c.z - 0.1))   # cabin glass
				for wx in [-1.0, 1.0]:
					for wz in [-1.0, 1.0]:
						var t := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = 0.33; cy.bottom_radius = 0.33; cy.height = 0.22
						t.mesh = cy; t.material_override = _mat(Color(0.05, 0.05, 0.06), 0.9); t.rotation = Vector3(0, 0, PI / 2)
						t.position = Vector3(c.x + wx * b.size.x * 0.48, 0.33, c.z + wz * b.size.z * 0.32)
						world.add_child(t)
				_box(Vector3(b.size.x * 0.8, 0.1, 0.04), _mat(Color(1, 0.95, 0.8), 0.3, 0.0, 1.5), Vector3(c.x, 0.65, b.end.z + 0.01))
				_box(Vector3(b.size.x * 0.8, 0.1, 0.04), _mat(Color(1, 0.15, 0.1), 0.3, 0.0, 1.5), Vector3(c.x, 0.7, b.position.z - 0.01))
			"barrier":
				_box(b.size, _mat(Color(0.65, 0.65, 0.63), 0.9), c)
				for k in int(b.size.z / 0.8):
					_box(Vector3(b.size.x + 0.02, 0.18, 0.4), _mat(Color(0.95, 0.75, 0.1), 0.6), Vector3(c.x, h - 0.2, b.position.z + 0.4 + k * 0.8))
			"booth":
				_box(Vector3(b.size.x, 1.1, b.size.z), _mat(Color(0.85, 0.85, 0.85), 0.6), Vector3(c.x, 0.55, c.z))
				_box(Vector3(b.size.x, h - 1.4, b.size.z), glass, Vector3(c.x, 1.1 + (h - 1.4) / 2.0, c.z))
				_box(Vector3(b.size.x + 0.3, 0.3, b.size.z + 0.3), _mat(Color(0.95, 0.75, 0.15), 0.5), Vector3(c.x, h - 0.15, c.z))
			"parapet": _box(b.size, _mat(Color(0.6, 0.58, 0.56), 0.9), c)
			"housing":
				_box(b.size, _mat(Color(0.62, 0.6, 0.58), 0.9), c)
				_box(Vector3(1.4, 2.2, 0.06), _mat(Color(0.3, 0.32, 0.38), 0.5, 0.5), Vector3(c.x, 1.1, b.end.z + 0.02))   # door
				var sign := Label3D.new(); sign.text = "STAIRS"; sign.font = font; sign.font_size = 80; sign.modulate = Color(0.9, 0.9, 0.9)
				sign.position = Vector3(c.x, 2.8, b.end.z + 0.05); sign.outline_size = 0
				world.add_child(sign)
			"tank":
				var tm := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = b.size.x * 0.48; cy.bottom_radius = b.size.x * 0.48; cy.height = h - 1.0
				tm.mesh = cy; tm.material_override = _mat(Color(0.82, 0.82, 0.8), 0.5, 0.3); tm.position = Vector3(c.x, 1.0 + (h - 1.0) / 2.0, c.z)
				world.add_child(tm)
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						_box(Vector3(0.12, 1.0, 0.12), _mat(Color(0.3, 0.3, 0.32), 0.5, 0.7), Vector3(c.x + sx * b.size.x * 0.35, 0.5, c.z + sz * b.size.z * 0.35))
			"ac":
				_box(b.size, _mat(Color(0.75, 0.77, 0.8), 0.4, 0.5), c)
				var fan := MeshInstance3D.new(); var fc := CylinderMesh.new(); fc.top_radius = 0.75; fc.bottom_radius = 0.75; fc.height = 0.04
				fan.mesh = fc; fan.material_override = _mat(Color(0.15, 0.15, 0.17), 0.6); fan.position = c + Vector3(0, h / 2.0 + 0.02, 0)
				world.add_child(fan)
			"solar":
				_box(Vector3(b.size.x, 0.4, b.size.z * 0.3), _mat(Color(0.5, 0.5, 0.52), 0.6, 0.6), Vector3(c.x, 0.2, c.z))
				var pm := _box(Vector3(b.size.x, 0.06, b.size.z), _mat(Color(0.1, 0.15, 0.35), 0.15, 0.5), Vector3(c.x, h - 0.15, c.z))
				pm.rotation.x = 0.35
			"vent":
				_box(b.size, _mat(Color(0.55, 0.57, 0.6), 0.4, 0.7), c)
				for k in 6: _box(Vector3(b.size.x + 0.02, 0.04, 0.3), _mat(Color(0.2, 0.2, 0.22), 0.5), Vector3(c.x, h - 0.3, b.position.z + 0.4 + k * 0.6))
			_:
				_box(b.size, _mat(Color(0.6, 0.6, 0.62), 0.7), c)


## Props that aren't cover: plants, whiteboards, logos, signs, cones.
func _decor(id: String) -> void:
	var mark: Texture2D = load("res://assets/brand/bnb_mark_trim.png")
	var B := sim.bounds
	for side in [-1.0, 1.0]:   # Bit & Bytes logos on the end walls
		var sp := Sprite3D.new(); sp.texture = mark; sp.pixel_size = 2.4 / mark.get_height(); sp.shaded = false
		var wx := (B.end.x + 3.4) if side > 0 else (B.position.x - 3.4)
		sp.position = Vector3(wx - side * 0.05, 2.4 if sim.ceiling == 0.0 or sim.ceiling > 3.5 else 1.9, 0); sp.rotation.y = -side * PI / 2
		sp.modulate = Color(1.3, 1.3, 1.3)
		if id != "rooftop": world.add_child(sp)
	match id:
		"office":
			for p in [[-30.5, -20], [-30.5, 20], [30.5, -20], [30.5, 20], [-18, -20.8], [18, 20.8], [-18, 20.8], [18, -20.8]]:
				_plant(Vector3(p[0], 0, p[1]))
			for z in [-21.9, 21.9]:   # whiteboards on the long walls
				_box(Vector3(4.0, 1.6, 0.06), _mat(Color(0.95, 0.95, 0.97), 0.3), Vector3(-6, 1.7, z * 0.995))
				_box(Vector3(4.0, 1.6, 0.06), _mat(Color(0.95, 0.95, 0.97), 0.3), Vector3(6, 1.7, z * 0.995))
				for k in 4:
					_box(Vector3(randf_range(0.8, 2.6), 0.06, 0.02), _mat([TEAM_COL[0], TEAM_COL[1], Color(0.9, 0.2, 0.2)][k % 3], 0.5), Vector3(-6.8 + k * 0.4, 1.4 + k * 0.25, z * 0.99))
		"warehouse":
			for p in [[-30, -22], [30, 22], [-6, -22], [6, 22]]:
				for k in 3:
					var cone := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.04; cm.bottom_radius = 0.22; cm.height = 0.6
					cone.mesh = cm; cone.material_override = _mat(Color(1, 0.45, 0.1), 0.6); cone.position = Vector3(p[0] + k * 0.7, 0.3, p[1])
					world.add_child(cone)
		"garage":
			for x in [-24.0, 24.0]:
				var sg := Label3D.new(); sg.text = "LEVEL B2"; sg.font = font; sg.font_size = 90; sg.modulate = Color(0.95, 0.8, 0.2)
				sg.position = Vector3(x, 2.4, -21.9); sg.outline_size = 0
				world.add_child(sg)


func _plant(at: Vector3) -> void:
	var pot := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = 0.32; cy.bottom_radius = 0.25; cy.height = 0.55
	pot.mesh = cy; pot.material_override = _mat(Color(0.9, 0.9, 0.9), 0.5); pot.position = at + Vector3(0, 0.27, 0)
	world.add_child(pot)
	for k in 3:
		var leaf := MeshInstance3D.new(); var sp := SphereMesh.new(); sp.radius = 0.4; sp.height = 0.9
		leaf.mesh = sp; leaf.material_override = _mat(Color(0.18, 0.5, 0.25).lerp(Color(0.3, 0.6, 0.2), k * 0.4), 0.8)
		leaf.position = at + Vector3(sin(k * 2.1) * 0.15, 0.95 + k * 0.25, cos(k * 2.1) * 0.15)
		world.add_child(leaf)


## Each team's loadout table: wood top on metal legs, a cloth runner in the team colour, every gun and
## throwable laid out with its name, and a sign over it.
func _build_tables() -> void:
	for t in sim.tables:
		var at: Vector3 = t.pos
		var yaw: float = t.yaw
		var root := Node3D.new(); root.position = at; root.rotation.y = yaw
		world.add_child(root)
		var col: Color = TEAM_COL[t.team]
		_box(Vector3(6.4, 0.08, 1.0), _mat(Color(0.42, 0.28, 0.18), 0.5), Vector3(0, 0.86, 0), root)
		_box(Vector3(6.4, 0.02, 0.5), _mat(col.darkened(0.2), 0.8), Vector3(0, 0.91, 0), root)
		for lx in [-3.0, 3.0]:
			for lz in [-0.4, 0.4]:
				_box(Vector3(0.08, 0.84, 0.08), _mat(Color(0.2, 0.2, 0.22), 0.4, 0.7), Vector3(lx, 0.42, lz), root)
		var sign := Label3D.new()
		sign.text = "LOADOUT  ·  E TO TAKE" if not _touch() else "LOADOUT  ·  TAP USE"
		sign.font = font; sign.font_size = 60; sign.outline_size = 10; sign.modulate = col.lightened(0.3)
		sign.position = at + Vector3(0, 2.3, 0); sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(sign)
		var lamp := OmniLight3D.new(); lamp.position = at + Vector3(0, 2.6, 0); lamp.omni_range = 5.0; lamp.light_energy = 1.2
		lamp.light_color = col.lightened(0.5)
		world.add_child(lamp)
		for it in t.items:
			var kind: String = it.kind
			var holder := Node3D.new()
			world.add_child(holder)
			holder.position = it.pos
			var nade := OpsSim.NADES.has(kind)
			var m := _gun_mesh(kind, holder, 1.0 if not nade else 2.2)
			# guns lie on their side across the table, pointing out to the map; throwables stand up
			if not nade:
				m.rotation = Vector3(0, 0, PI / 2)
				holder.rotation.y = yaw + PI
				m.position = Vector3(0, 0.03, GUN_LEN.get(kind, 0.5) * 0.45)
			var tag := Label3D.new()
			tag.text = String(OpsSim.GUNS[kind].name if not nade else OpsSim.NADES[kind].name).replace("STAPLER ", "")
			tag.font = small; tag.font_size = 30; tag.outline_size = 8; tag.modulate = Color(1.0, 0.88, 0.4)
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tag.position = it.pos + Vector3(0, 0.3, 0)
			tag.pixel_size = 0.0022; tag.visible = false
			world.add_child(tag)
			item_tags.append({it = it, tag = tag})


# ---------------------------------------------------------------- soldiers
const GUN_LEN := {"pistol": 0.2, "sheriff": 0.3, "mpistol": 0.24, "smg": 0.42, "rifle": 0.72, "shotgun": 0.8, "sniper": 1.05,
	"dmr": 0.85, "lmg": 0.9, "marshal": 0.95}


func _gun_mesh(kind: String, parent: Node3D, scale := 1.0) -> Node3D:
	if OpsSim.NADES.has(kind): return _nade_mesh(kind, parent, scale)
	var g := Node3D.new()
	parent.add_child(g)
	var metal := _mat(Color(0.12, 0.12, 0.14), 0.4, 0.7)
	var grip := _mat(Color(0.2, 0.18, 0.16), 0.8)
	var acc := _mat(Color(0.55, 0.32, 0.9), 0.4, 0.3)
	var wood := _mat(Color(0.45, 0.28, 0.15), 0.6)
	var L: float = GUN_LEN.get(kind, 0.6)
	var side: bool = OpsSim.GUNS[kind].get("side", false) or kind == "pistol"
	_box(Vector3(0.06, 0.09, L), metal if kind != "marshal" else wood, Vector3(0, 0, -L / 2.0), g)   # body
	_box(Vector3(0.035, 0.035, L * 0.5), metal, Vector3(0, 0.02, -L - L * 0.2), g)                  # barrel
	_box(Vector3(0.05, 0.14, 0.06), grip if kind != "sheriff" else wood, Vector3(0, -0.1, -0.06), g)  # grip
	match kind:
		"sheriff":   # revolver: a fat cylinder in front of the grip, long barrel
			var cy := CylinderMesh.new(); cy.top_radius = 0.045; cy.bottom_radius = 0.045; cy.height = 0.08
			var mi := MeshInstance3D.new(); mi.mesh = cy; mi.material_override = metal; mi.rotation = Vector3(PI / 2, 0, 0); mi.position = Vector3(0, 0.01, -0.09)
			g.add_child(mi)
			_box(Vector3(0.03, 0.03, 0.22), metal, Vector3(0, 0.03, -0.32), g)
		"mpistol":   # long magazine out of the grip
			_box(Vector3(0.04, 0.2, 0.045), metal, Vector3(0, -0.2, -0.06), g)
		"lmg":   # box magazine, bipod, carry handle
			_box(Vector3(0.12, 0.12, 0.14), _mat(Color(0.3, 0.32, 0.25), 0.7), Vector3(0.04, -0.09, -L * 0.42), g)
			_box(Vector3(0.02, 0.15, 0.02), metal, Vector3(0.04, -0.08, -L * 0.95), g)
			_box(Vector3(0.02, 0.15, 0.02), metal, Vector3(-0.04, -0.08, -L * 0.95), g)
			_box(Vector3(0.03, 0.05, 0.16), metal, Vector3(0, 0.08, -L * 0.3), g)
	if not side:
		if kind != "lmg": _box(Vector3(0.05, 0.12, 0.05), metal, Vector3(0, -0.1, -L * 0.45), g)   # magazine
		_box(Vector3(0.05, 0.08, 0.22), grip if kind != "marshal" else wood, Vector3(0, -0.01, 0.12), g)   # stock
		_box(Vector3(0.065, 0.02, L * 0.4), acc, Vector3(0, 0.055, -L * 0.45), g)          # rail in BNB purple
	if kind in ["sniper", "rifle", "dmr", "marshal"]:
		_box(Vector3(0.05, 0.06, 0.28 if kind != "rifle" else 0.18), metal, Vector3(0, 0.09, -L * 0.45), g)   # scope
	g.scale = Vector3.ONE * scale
	return g


## A throwable: frag (green, round), flashbang (grey can), molotov (bottle with a burning rag).
func _nade_mesh(kind: String, parent: Node3D, scale := 1.0) -> Node3D:
	var g := Node3D.new()
	parent.add_child(g)
	var add := func(mesh: Mesh, m: Material, pos: Vector3) -> void:
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = m; mi.position = pos; g.add_child(mi)
	match kind:
		"frag":
			var sp := SphereMesh.new(); sp.radius = 0.045; sp.height = 0.1
			add.call(sp, _mat(Color(0.25, 0.35, 0.2), 0.6, 0.3), Vector3.ZERO)
			add.call(_cyl(0.018, 0.03), _mat(Color(0.6, 0.6, 0.62), 0.3, 0.8), Vector3(0, 0.055, 0))
		"flash":
			add.call(_cyl(0.032, 0.11), _mat(Color(0.65, 0.66, 0.7), 0.3, 0.7), Vector3.ZERO)
			add.call(_cyl(0.034, 0.02), _mat(Color(0.95, 0.85, 0.2), 0.4), Vector3(0, 0.03, 0))
		_:
			add.call(_cyl(0.035, 0.12), _mat(Color(0.35, 0.55, 0.25, 0.85), 0.1, 0.0), Vector3.ZERO)
			add.call(_cyl(0.014, 0.06), _mat(Color(0.35, 0.55, 0.25), 0.1), Vector3(0, 0.085, 0))
			add.call(_cyl(0.012, 0.04), _mat(Color(1.0, 0.55, 0.15), 0.5, 0.0, 3.0), Vector3(0, 0.13, 0))
	g.scale = Vector3.ONE * scale
	return g


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r; c.height = h; c.radial_segments = 12
	return c


func _soldier_visual(s: OpsSim.Soldier) -> Dictionary:
	var rig := Main.make_rig(s.C, 0)
	world.add_child(rig)
	var gun := _gun_mesh(s.holding(), world, 1.6)
	var tag := Label3D.new()
	tag.text = String(s.C.person.get("short", s.C.name)) if s.C.has("person") else s.C.name
	tag.font = font; tag.font_size = 30; tag.outline_size = 8
	tag.modulate = TEAM_COL[s.team]; tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tag.no_depth_test = s.team == sim.soldiers[me].team
	world.add_child(tag)
	# enemies glow red, teammates glow in a calm blue: no friendly confusion
	var mine: bool = s.team == sim.soldiers[me].team
	if rig.has_method("set_team_glow"): rig.set_team_glow(ENEMY_RED if not mine else MATE_BLUE, 1.1 if not mine else 0.55)
	if not mine: tag.modulate = ENEMY_RED.lightened(0.2)
	if s.id == me:
		rig.visible = false; gun.visible = false; tag.visible = false
	return {rig = rig, gun = gun, gun_kind = s.holding(), tag = tag, dead_t = 0.0}


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
	var kind: String = s.holding()
	var g := _gun_mesh(kind, view_gun, 1.0 if not OpsSim.NADES.has(kind) else 1.4)
	g.name = "model"
	view_gun.set_meta("kind", kind)
	# a hand under the grip, in the person's skin tone
	var sk: Array = (s.C.get("person", {}) as Dictionary).get("skin", [0.86, 0.72, 0.62])
	_box(Vector3(0.09, 0.08, 0.16), _mat(Color(sk[0], sk[1], sk[2]), 0.8), Vector3(0, -0.12, -0.03), g)
	var L: float = GUN_LEN.get(kind, 0.1)
	if flash != null: flash.position = Vector3(0, 0.02, -L * 1.25)


# ---------------------------------------------------------------- loop
var hold_ads := false   # tests: keep aiming without a mouse
var test_inp := {}      # tests: the player's controls this tick


func _physics_process(_dt: float) -> void:
	if sim == null or (paused and not online_match()): return
	var inp: Dictionary = sim._bot(sim.soldiers[me]) if autopilot else ({} if (paused or G.comms_typing) else _controls())
	if not test_inp.is_empty(): inp = test_inp.duplicate()
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
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		wheel = 1
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
		swap = k.call([KEY_Q]) and not _held_swap() or _t_once("swap") or wheel != 0 or (not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_Y) and not _held_swap()),
		use = k.call([KEY_E, KEY_F]) or _t("use") or (not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_RIGHT_SHOULDER))}.merged(_slot_keys())


var wheel := 0
var _keys_was := {}
## 1 / 2 / 3 pick a slot, G (or the NADE button) cycles throwables: each on a fresh press.
func _slot_keys() -> Dictionary:
	var out := {}
	var fresh := func(key: int) -> bool:
		var now := Input.is_physical_key_pressed(key)
		var was: bool = _keys_was.get(key, false)
		_keys_was[key] = now
		return now and not was
	if fresh.call(KEY_1): out.slot = 0
	if fresh.call(KEY_2): out.slot = 1
	if fresh.call(KEY_3): out.slot = 2
	if fresh.call(KEY_G) or _t_once("nade"): out.cycle_nade = true
	wheel = 0
	return out


var _swap_was := false
func _held_swap() -> bool:
	var now := Input.is_physical_key_pressed(KEY_Q)
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
		"pickup":
			if e[2] == me:
				_rebuild_view_gun(); G.sfx("grab")
				var got := String(e[3])
				killfeed.push_front(["TOOK  " + String(OpsSim.GUNS[got].name if OpsSim.GUNS.has(got) else OpsSim.NADES[got].name), 2.0, -1])
		"throw":
			if e[2] == me: G.sfx("whoosh")
		"boom":
			_blast(e[1], Color(1.0, 0.6, 0.2, 0.9), 5.0, 0.6)
			var d: float = (e[1] as Vector3).distance_to(sim.soldiers[me].pos)
			shake = maxf(shake, clampf(1.0 - d / 18.0, 0.0, 1.0))
			G.sfx("heavy")
		"flash":
			_blast(e[1], Color(1, 1, 1, 0.95), 3.0, 0.4)
			G.sfx("surge")
		"fire": G.sfx("block")
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
		if v.gun_kind != s.holding():
			(v.gun as Node).queue_free()
			v.gun = _gun_mesh(s.holding(), world, 1.6); v.gun_kind = s.holding()
		var gn: Node3D = v.gun
		gn.visible = s.alive
		if s.alive:
			var hx: Transform3D = rig.hand_xform(true)
			gn.global_transform = Transform3D(Basis(Vector3.UP, rig.rotation.y), hx.origin)
		var tag: Label3D = v.tag
		tag.visible = s.alive
		tag.position = p + Vector3(0, 2.15 * s.C.scale, 0)
		tag.text = "%s  %d" % [_nm(s), roundi(s.hp)] if s.team == sim.soldiers[me].team else _nm(s)
	_sync_nades(dt)
	# loadout table: only the item you'd take shows its name
	var tgt := sim.pick_target(sim.soldiers[me])
	for t in item_tags: (t.tag as Label3D).visible = not tgt.is_empty() and t.it == tgt
	_camera(a, dt)
	white = maxf(0.0, white - dt * 0.6)
	var me_s: OpsSim.Soldier = sim.soldiers[me]
	if me_s.blind > 0: white = maxf(white, minf(1.0, me_s.blind / 80.0))
	for t in tracers.duplicate():
		t[1] -= dt
		if t[1] <= 0.0: (t[0] as Node).queue_free(); tracers.erase(t)
	for k in killfeed: k[1] -= dt
	killfeed = killfeed.filter(func(k): return k[1] > 0.0)
	hitmark = maxf(0.0, hitmark - dt)
	hud.queue_redraw()


func _sync_nades(dt: float) -> void:
	var alive := {}
	for n in sim.thrown:
		alive[n.uid] = true
		if not nade_nodes.has(n.uid):
			nade_nodes[n.uid] = _nade_mesh(String(n.kind), world, 2.0)
		var nd: Node3D = nade_nodes[n.uid]
		nd.position = nd.position.lerp(n.pos, 0.6) if nd.position != Vector3.ZERO else n.pos
		nd.rotation.x += dt * 9.0
	for k in nade_nodes.keys():
		if not alive.has(k): (nade_nodes[k] as Node).queue_free(); nade_nodes.erase(k)
	var lit := {}
	for f in sim.fires:
		lit[f.uid] = true
		if not fire_nodes.has(f.uid): fire_nodes[f.uid] = _fire_node(f.pos)
		var fn: Node3D = fire_nodes[f.uid]
		var life := clampf(float(f.t) / 60.0, 0.0, 1.0)
		fn.scale = Vector3.ONE * (0.3 + 0.7 * life)
	for k in fire_nodes.keys():
		if not lit.has(k): (fire_nodes[k] as Node).queue_free(); fire_nodes.erase(k)


## A molotov's fire: flickering flames, embers, a glow on the floor and an orange light.
func _fire_node(at: Vector3) -> Node3D:
	var n := Node3D.new(); n.position = at; world.add_child(n)
	var disc := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = OpsSim.NADES.molly.r; cy.bottom_radius = OpsSim.NADES.molly.r; cy.height = 0.02
	disc.mesh = cy; disc.material_override = _mat(Color(0.35, 0.12, 0.02), 0.9, 0.0, 0.6); disc.position.y = 0.02
	n.add_child(disc)
	var p := CPUParticles3D.new()
	p.amount = 90; p.lifetime = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = OpsSim.NADES.molly.r * 0.8
	p.direction = Vector3.UP; p.spread = 12; p.gravity = Vector3(0, 2.5, 0)
	p.initial_velocity_min = 0.8; p.initial_velocity_max = 2.0
	p.scale_amount_min = 0.6; p.scale_amount_max = 1.3
	var q := QuadMesh.new(); q.size = Vector2(0.55, 0.8)
	var qm := StandardMaterial3D.new(); qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true; qm.albedo_color = Color(1.6, 0.7, 0.2)
	q.material = qm
	p.mesh = q
	var grad := Gradient.new(); grad.set_color(0, Color(1.0, 0.85, 0.3, 0.95)); grad.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	p.color_ramp = grad
	p.position.y = 0.3
	n.add_child(p)
	var l := OmniLight3D.new(); l.light_color = Color(1.0, 0.55, 0.2); l.light_energy = 2.5; l.omni_range = 7.0; l.position.y = 1.0
	n.add_child(l)
	return n


## A short-lived ball of light: grenade explosions and flashbangs.
func _blast(at: Vector3, col: Color, size: float, life: float) -> void:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new(); sp.radius = 0.5; sp.height = 1.0
	mi.mesh = sp
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.position = at; mi.scale = Vector3.ONE * 0.3
	world.add_child(mi)
	var l := OmniLight3D.new(); l.light_color = Color(col.r, col.g, col.b); l.light_energy = 6.0; l.omni_range = size * 3.0
	mi.add_child(l)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size, life * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, life)
	tw.parallel().tween_property(l, "light_energy", 0.0, life)
	tw.tween_callback(mi.queue_free)


func _camera(a: float, dt: float) -> void:
	var s: OpsSim.Soldier = sim.soldiers[me]
	var p := s.prev_pos.lerp(s.pos, a)
	var eye := EYE_H(s)
	var spd := Vector2(s.vel.x, s.vel.z).length()
	bob += dt * spd * 1.6
	var bob_off := Vector3(sin(bob) * 0.02, absf(cos(bob)) * 0.03, 0) * clampf(spd / 6.0, 0.0, 1.0)
	cam.position = p + Vector3(0, eye, 0) + (bob_off if not s.ads else Vector3.ZERO)
	cam.rotation = Vector3(s.pitch, s.yaw + PI, 0) + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.03
	cam.rotation_order = EULER_ORDER_YXZ
	shake = maxf(0.0, shake - dt * 2.5)
	var target_fov: float = s.gun().fov if (s.ads and s.slot < 2) else (82.0 if s.sprint else 75.0)
	cam.fov = lerpf(cam.fov, target_fov, clampf(dt * 14.0, 0.0, 1.0))
	# the gun: hip position, or centred for aiming; recoil kick; hidden in a sniper scope
	kick = maxf(0.0, kick - dt * 9.0)
	var kind: String = s.holding()
	var scoped := s.slot < 2 and float(s.gun().fov) < 30.0
	var hip := Vector3(0.22, -0.2, -0.42)
	var aimp := Vector3(0.0, -0.12 if not scoped else -0.1, -0.32)
	var want := aimp if s.ads else hip
	if s.sprint: want = Vector3(0.18, -0.28, -0.38)
	if s.reload_t > 0: want += Vector3(0, -0.12, 0.05)
	view_gun.position = view_gun.position.lerp(want + Vector3(0, 0, kick * 0.06) + bob_off * 0.6, clampf(dt * 16.0, 0.0, 1.0))
	view_gun.rotation = Vector3(kick * 0.08 + (0.6 if s.reload_t > 0 else 0.0), 0.0 if s.ads else -0.04, 0.0 if s.ads else 0.03)
	view_gun.visible = s.alive and not (s.ads and scoped and cam.fov < 32.0)
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
	var kind: String = s.holding()
	var g: Dictionary = s.gun()
	var scoped := s.slot < 2 and float(g.fov) < 30.0
	# sniper scope
	if s.ads and scoped and cam.fov < 32.0:
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
	elif s.alive and s.slot == 2:   # throwable: a little arc marker
		hud.draw_arc(c, 10.0, PI * 1.1, PI * 1.9, 12, Color(1, 1, 1, 0.9), 2.0)
		hud.draw_circle(c, 2.0, Color(1, 1, 1, 0.9))
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
	var al := HORIZONTAL_ALIGNMENT_RIGHT if not _touch() else HORIZONTAL_ALIGNMENT_LEFT
	if s.slot == 2:
		hud.draw_string(font, ammo_at, "× %d" % int(s.nades[s.nade_sel]), al, 300, 40 if not _touch() else 30, ink)
		hud.draw_string(small, ammo_at + Vector2(0, -48 if not _touch() else -100), String(OpsSim.NADES[s.nade_sel].name) + "   ·   G next", al, 300, 20, Color(0.8, 0.82, 0.9))
	else:
		hud.draw_string(font, ammo_at, "%d / %d" % [s.mag[s.slot], s.reserve[s.slot]], al, 300, 40 if not _touch() else 30, ink)
		hud.draw_string(small, ammo_at + Vector2(0, -48 if not _touch() else -100), String(g.name) + ("   RELOADING…" if s.reload_t > 0 else ""), al, 300, 20, Color(0.8, 0.82, 0.9))
	_draw_slots(s, sz)
	# next to the loadout table: what E takes
	var it := sim.pick_target(s)
	if not it.is_empty():
		var nm := String(OpsSim.GUNS[it.kind].name if OpsSim.GUNS.has(it.kind) else OpsSim.NADES[it.kind].name)
		var full := OpsSim.NADES.has(it.kind) and int(s.nades[it.kind]) >= OpsSim.NADE_MAX
		var msg := ("%s  TAKE  %s" % ["E" if not _touch() else "USE", nm]) if not full else "%s  ·  FULL (%d)" % [nm, OpsSim.NADE_MAX]
		hud.draw_rect(Rect2(Vector2(c.x - 230, c.y + 60), Vector2(460, 40)), Color(0, 0, 0, 0.55))
		hud.draw_string(font, Vector2(c.x - 230, c.y + 90), msg, HORIZONTAL_ALIGNMENT_CENTER, 460, 24, Color(1.0, 0.85, 0.35))
	# spawn protection
	if s.alive and s.protect > 0 and sim.state != "warmup":
		hud.draw_string(font, Vector2(0, sz.y * 0.28), "SPAWN PROTECTION  %.1f" % (s.protect / 60.0), HORIZONTAL_ALIGNMENT_CENTER, sz.x, 30, Color(0.5, 0.85, 1.0))
		hud.draw_string(small, Vector2(0, sz.y * 0.28 + 28), "you can't be hit — and can't shoot yet", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 18, Color(0.75, 0.88, 1.0, 0.85))
		hud.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.3, 0.6, 1.0, 0.06 + 0.04 * sin(Time.get_ticks_msec() / 120.0)))
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
		hud.draw_string(small, Vector2(0, sz.y - 8), "WASD move · MOUSE aim · LMB fire / throw · RMB aim · SHIFT sprint · C crouch · SPACE jump · R reload · 1 2 3 / Q / wheel weapons · G throwables · E take · TAB scores", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 15, Color(0.8, 0.82, 0.9, 0.6))
	_draw_touch()
	# flashbanged: the screen goes white and slowly comes back
	if white > 0.0: hud.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, clampf(white, 0.0, 1.0) * 0.97))


## Weapon slots (PUBG style): primary, sidearm, throwables with their counts; the one in hand is lit.
func _draw_slots(s: OpsSim.Soldier, sz: Vector2) -> void:
	var w := 150.0
	var x0 := sz.x - 3 * (w + 8) - 22 if not _touch() else sz.x / 2.0 - 1.5 * (w + 8)
	var y := sz.y - 150 if not _touch() else 14.0 + 74.0
	var names := [String(OpsSim.GUNS[s.guns[0]].name), String(OpsSim.GUNS[s.guns[1]].name), ""]
	var parts := []
	for nk in OpsSim.NADE_KINDS:
		if int(s.nades[nk]) > 0: parts.append("%s %d" % [{"frag": "FRAG", "flash": "FLASH", "molly": "MOLLY"}[nk], s.nades[nk]])
	names[2] = "  ".join(parts) if not parts.is_empty() else "NO THROWABLES"
	for k in 3:
		var on := s.slot == k
		var r := Rect2(Vector2(x0 + k * (w + 8), y), Vector2(w, 40))
		hud.draw_rect(r, Color(0.62, 0.38, 1.0, 0.55) if on else Color(0, 0, 0, 0.45))
		if on: hud.draw_rect(r, Color(1, 1, 1, 0.9), false, 2.0)
		hud.draw_string(small, r.position + Vector2(6, 15), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
		hud.draw_string(small, r.position + Vector2(4, 33), String(names[k]).replace("STAPLER ", "").replace("BREAKROOM ", ""), HORIZONTAL_ALIGNMENT_CENTER, w - 8, 15 if k < 2 else 14, Color(1, 1, 1, 0.95 if on else 0.65))


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
		nade = {c = Vector2(s.x - r * 6.2, s.y - r * 5.1), r = r * 0.7, label = "NADE", held = false},
		use = {c = Vector2(s.x / 2.0, s.y * 0.66), r = r * 0.85, label = "USE", held = false},
		sprint = {c = Vector2(r * 1.4, s.y - r * 4.8), r = r * 0.7, label = "RUN", held = false},
		pause = {c = Vector2(s.x / 2 - 210, 40), r = 26.0, label = "II", held = false},
	}


func _input(e: InputEvent) -> void:
	if not _touch() or sim == null: return
	if e is InputEventScreenTouch:
		var vs: Vector2 = G.get_viewport().get_visible_rect().size
		if e.pressed:
			var hit := ""
			var near := not sim.pick_target(sim.soldiers[me]).is_empty()
			for n in touch_btn:
				if n == "use" and not near: continue
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
	var near := not sim.pick_target(sim.soldiers[me]).is_empty()
	for n in touch_btn:
		var b: Dictionary = touch_btn[n]
		if n == "use" and not near: continue   # only next to the loadout table
		var col := Color(1.0, 0.35, 0.35) if n == "fire" else (Color(1.0, 0.8, 0.3) if n == "use" else Color(0.62, 0.38, 1.0))
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
