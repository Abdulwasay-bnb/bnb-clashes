extends Node
## Deadline Dash: the single-player platformer. Ten levels across the office floor, the server room, the
## rooftops and the CEO's penthouse, bosses at the end of levels 3, 6, 9 and 10, three lives — lose them all
## and the run starts again from level 1. Draws a DashSim (scripts/dash/dash_sim.gd) in 2.5D.

signal finished

const DashSim = preload("res://scripts/dash/dash_sim.gd")
const Levels = preload("res://scripts/dash/dash_levels.gd")
const BV := Color(0.62, 0.38, 1.0)
const CY := Color(0.13, 0.78, 0.92)
const GOLD := Color(1.0, 0.8, 0.25)
const BOSS_WHO := {"hr": "kashaf_ud_duja", "admin": "muhammad_mubarak", "wizard": "zia_khan", "ceo": "hamza_khan"}
const BOSS_ALT := {"hr": "amina_mughal", "admin": "faisal_ahmed", "wizard": "usman_najeeb", "ceo": "abdul_wasay"}
const BOSS_TITLE := {"hr": "HR · THE FINAL WARNING", "admin": "THE SYSADMIN", "wizard": "THE LEGACY WIZARD", "ceo": "THE CEO"}

var G
var C: Dictionary
var sim
var autoplay := false
var stats := {}
var world: Node3D
var level_root: Node3D
var env: Environment
var cam: Camera3D
var layer: CanvasLayer
var hud: Control
var font: Font
var small: Font
var hero
var hero_anim := 0.0
var hero_scale := 0.62
var boss_rig = null
var boss_C: Dictionary = {}
var boss_anim := 0.0
var blocks := {}            # Vector2i -> {node, ch}
var coin_nodes := {}        # Vector2i -> node
var enemy_nodes: Array = []
var item_nodes := {}
var plane_nodes := {}
var hazard_nodes := {}
var plat_nodes: Array = []
var flag_nodes := {}        # checkpoint pos -> node
var exit_node: Node3D
var cam_x := 0.0
var cam_y := 6.0
var shake := 0.0
var flow := "intro"         # intro / play / clear / over / victory
var flow_t := 0.0
var toast := ""
var toast_t := 0.0
var paused := false
var panel: Control = null
var touch_btn := {}
var touches := {}
var _jump_was := false
var _act_was := false
var _next_id := 1
var particles: Array = []   # [node, vel, life]


# ---------------------------------------------------------------- start / stop
func start(g, c: Dictionary) -> void:
	G = g; C = c
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	sim = DashSim.new()
	sim.new_run()
	world = Node3D.new()
	G.add_child(world)
	cam = Camera3D.new(); cam.fov = 42.0; cam.far = 400.0
	world.add_child(cam); cam.current = true
	layer = CanvasLayer.new(); layer.layer = 5
	G.add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	_layout_touch()
	_build_level()
	_intro()


func stop() -> void:
	if world != null: world.queue_free()
	if layer != null: layer.queue_free()
	world = null; layer = null


func _person(id: String) -> Dictionary:
	var p: Dictionary = Data.by_id(id)
	return p if not p.is_empty() else Data.ROSTER[0]


# ---------------------------------------------------------------- materials / meshes
func _mat(c: Color, rough := 0.7, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	if c.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0: m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	return m


func _box(size: Vector3, m: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b; mi.material_override = m; mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(r: float, h: float, m: Material, pos: Vector3, parent: Node3D, rot := Vector3.ZERO, r2 := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r if r2 < 0.0 else r2; c.height = h; c.radial_segments = 16
	mi.mesh = c; mi.material_override = m; mi.position = pos; mi.rotation = rot
	parent.add_child(mi)
	return mi


func _sph(r: float, m: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0; s.radial_segments = 14; s.rings = 8
	mi.mesh = s; mi.material_override = m; mi.position = pos
	parent.add_child(mi)
	return mi


func _label(text: String, size: int, col: Color, pos: Vector3, parent: Node3D) -> Label3D:
	var l := Label3D.new()
	l.text = text; l.font = font; l.font_size = size; l.modulate = col; l.outline_size = 8; l.position = pos
	parent.add_child(l)
	return l


func _multi(mesh: Mesh, m: Material, xforms: Array, parent: Node3D) -> void:
	if xforms.is_empty(): return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size(): mm.set_instance_transform(k, xforms[k])
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = m
	parent.add_child(mi)


func _world() -> String: return String(Levels.LEVELS[sim.level].world)


## Per world: background colour, floor colours, ambient, light.
func _palette() -> Dictionary:
	match _world():
		"server": return {bg = Color(0.02, 0.03, 0.07), top = Color(0.2, 0.55, 0.75), body = Color(0.12, 0.14, 0.2), amb = Color(0.45, 0.55, 0.85), amb_e = 0.6, sun = 0.6, sun_c = Color(0.6, 0.8, 1.0)}
		"roof": return {bg = Color(0.95, 0.5, 0.35), top = Color(0.85, 0.3, 0.15), body = Color(0.55, 0.2, 0.12), amb = Color(0.85, 0.7, 0.75), amb_e = 0.55, sun = 1.0, sun_c = Color(1.0, 0.82, 0.62)}
		"penthouse": return {bg = Color(0.05, 0.03, 0.1), top = Color(0.85, 0.65, 0.25), body = Color(0.3, 0.15, 0.22), amb = Color(0.75, 0.62, 0.8), amb_e = 0.55, sun = 0.8, sun_c = Color(1.0, 0.85, 0.65)}
		_: return {bg = Color(0.1, 0.08, 0.2), top = Color(0.42, 0.24, 0.72), body = Color(0.36, 0.26, 0.2), amb = Color(0.72, 0.72, 0.85), amb_e = 0.45, sun = 0.8, sun_c = Color(1.0, 0.94, 0.85)}


# ---------------------------------------------------------------- level
func _build_level() -> void:
	if level_root != null: level_root.queue_free()
	level_root = Node3D.new()
	world.add_child(level_root)
	blocks.clear(); coin_nodes.clear(); enemy_nodes.clear(); item_nodes.clear(); plane_nodes.clear(); hazard_nodes.clear()
	plat_nodes.clear(); flag_nodes.clear(); particles.clear()
	boss_rig = null; exit_node = null
	toast_t = 0.0
	var P := _palette()
	# light and environment (set on the camera too, so no other environment in the scene wins)
	var we := WorldEnvironment.new()
	env = Environment.new()
	if _world() == "roof":
		var sky := Sky.new(); var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.18, 0.28, 0.68); sm.sky_horizon_color = Color(1.0, 0.6, 0.4)
		sm.ground_bottom_color = Color(0.2, 0.15, 0.2); sm.ground_horizon_color = Color(0.7, 0.45, 0.4)
		sky.sky_material = sm; env.background_mode = Environment.BG_SKY; env.sky = sky
	else:
		env.background_mode = Environment.BG_COLOR; env.background_color = P.bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = P.amb; env.ambient_light_energy = P.amb_e
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = 0.95
	env.glow_enabled = true; env.glow_intensity = 0.35; env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true; env.adjustment_saturation = 1.15
	we.environment = env
	level_root.add_child(we)
	cam.environment = env
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-25), 0); sun.light_energy = P.sun; sun.light_color = P.sun_c
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 40
	level_root.add_child(sun)
	_background()
	_tiles(P)
	# moving platforms
	for p in sim.plats:
		var n := Node3D.new(); level_root.add_child(n)
		var col := Color(0.25, 0.6, 0.8) if _world() == "server" else (Color(0.95, 0.65, 0.1) if _world() == "roof" else BV)
		_box(Vector3(p.w, 0.3, 1.4), _mat(col, 0.4, 0.4), Vector3(0, 0, 0), n)
		_box(Vector3(p.w + 0.05, 0.06, 1.45), _mat(Color(1, 1, 1), 0.3, 0.0, 1.2), Vector3(0, 0.16, 0), n)
		if p.axis == 1:   # cable lift: cables up into the dark
			for sx in [-1.2, 1.2]: _box(Vector3(0.04, 14.0, 0.04), _mat(Color(0.2, 0.2, 0.22), 0.4, 0.8), Vector3(sx, 7.0, 0), n)
		else:   # crane hook
			_box(Vector3(0.06, 9.0, 0.06), _mat(Color(0.15, 0.15, 0.16), 0.4, 0.8), Vector3(0, 4.6, 0), n)
		plat_nodes.append(n)
	# hero
	hero = Main.make_rig(C, 0)
	level_root.add_child(hero)
	hero.scale = Vector3.ONE * hero_scale
	# boss
	if not sim.boss.is_empty():
		var kind := String(sim.boss.kind)
		var bid: String = BOSS_WHO[kind] if BOSS_WHO[kind] != String(C.id) else BOSS_ALT[kind]
		boss_C = _person(bid)
		boss_rig = Main.make_rig(boss_C, 0)
		boss_rig.scale = Vector3.ONE * 1.25
		level_root.add_child(boss_rig)
	cam_x = sim.pos.x + 2.5
	_sync(0.0)


func _background() -> void:
	var lw: float = sim.w
	var mid := lw / 2.0
	var win := ShaderMaterial.new(); win.shader = load("res://shaders/windows.gdshader")
	var mark: Texture2D = load("res://assets/brand/bnb_mark_trim.png")
	match _world():
		"office":
			_box(Vector3(lw + 40, 16, 0.2), _mat(Color(0.5, 0.42, 0.58), 0.9), Vector3(mid, 8, -3.2), level_root)          # back wall
			for x in range(0, int(lw) + 20, 12):
				var wpane := _box(Vector3(8, 5, 0.05), _mat(Color(0.2, 0.42, 0.85), 0.1, 0.0, 0.45), Vector3(x, 7.5, -3.05), level_root)   # windows
				for k in 3:   # towers outside
					_box(Vector3(1.6, 2.0 + k * 0.8, 0.02), _mat(Color(0.1, 0.12, 0.25), 0.5), Vector3(x - 2.6 + k * 2.6, 5.0 + (2.0 + k * 0.8) / 2.0, -3.02), level_root)
				wpane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_box(Vector3(8.4, 0.25, 0.1), _mat(Color(0.3, 0.3, 0.33), 0.4, 0.6), Vector3(x, 4.95, -3.0), level_root)
				_box(Vector3(8.4, 0.25, 0.1), _mat(Color(0.3, 0.3, 0.33), 0.4, 0.6), Vector3(x, 10.05, -3.0), level_root)
				_box(Vector3(0.25, 5.4, 0.1), _mat(Color(0.3, 0.3, 0.33), 0.4, 0.6), Vector3(x, 7.5, -3.0), level_root)
				_box(Vector3(2.0, 1.4, 0.1), _mat(BV if (x / 12) % 2 == 0 else CY, 0.5), Vector3(x + 6, 3.4, -3.05), level_root)   # posters
		"server":
			_box(Vector3(lw + 40, 16, 0.2), _mat(Color(0.06, 0.07, 0.11), 0.6), Vector3(mid, 8, -4.2), level_root)
			for x in range(0, int(lw) + 20, 3):
				_box(Vector3(2.2, 7.0, 1.0), _mat(Color(0.05, 0.05, 0.07), 0.4, 0.5), Vector3(x, 5.5, -3.4), level_root)
				for k in 6:
					var c: Color = [Color(0.2, 1.0, 0.4), CY, Color(1.0, 0.3, 0.3)][(x + k) % 3]
					_box(Vector3(1.8, 0.06, 0.05), _mat(c, 0.3, 0.0, 3.0), Vector3(x, 2.6 + k * 1.1, -2.88), level_root)
			for x in range(0, int(lw) + 20, 14):
				var l := OmniLight3D.new(); l.position = Vector3(x, 9, 2); l.omni_range = 14; l.light_energy = 1.2; l.light_color = Color(0.4, 0.7, 1.0)
				level_root.add_child(l)
		"roof":
			for x in range(-20, int(lw) + 40, 7):   # skyline far behind
				var hh := 8.0 + fmod(x * 5.17, 22.0)
				_box(Vector3(6, hh, 5), win, Vector3(x, hh / 2.0 - 8.0, -26), level_root)
			for x in range(10, int(lw), 45):   # cranes
				var cm := _mat(Color(0.95, 0.65, 0.1), 0.5, 0.4)
				_box(Vector3(0.6, 26, 0.6), cm, Vector3(x, 9, -9), level_root)
				_box(Vector3(18, 0.6, 0.6), cm, Vector3(x + 6, 21.5, -9), level_root)
		_:
			_box(Vector3(lw + 40, 16, 0.2), _mat(Color(0.25, 0.13, 0.18), 0.5), Vector3(mid, 8, -3.2), level_root)
			for x in range(0, int(lw) + 20, 10):
				var wpane := _box(Vector3(7, 7, 0.05), _mat(Color(0.06, 0.1, 0.25), 0.1, 0.0, 0.3), Vector3(x, 8, -3.05), level_root)
				wpane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_box(Vector3(7.4, 0.2, 0.1), _mat(GOLD, 0.3, 0.8), Vector3(x, 4.4, -3.0), level_root)
				_box(Vector3(7.4, 0.2, 0.1), _mat(GOLD, 0.3, 0.8), Vector3(x, 11.6, -3.0), level_root)
				for k in 4:   # city lights through the window
					_box(Vector3(0.3, 0.3, 0.02), _mat([GOLD, CY, BV][k % 3], 0.3, 0.0, 2.0), Vector3(x - 2.5 + k * 1.6, 6.0 + fmod(x * 1.7 + k, 4.0), -3.0), level_root)
	# BNB logos along the back
	if _world() != "roof":
		for x in range(20, int(lw), 40):
			var sp := Sprite3D.new(); sp.texture = mark; sp.pixel_size = 2.4 / mark.get_height(); sp.shaded = false
			sp.position = Vector3(x, 11.6 if _world() == "office" else 10.5, -2.9 if _world() != "server" else -2.7); sp.modulate = Color(1.3, 1.3, 1.3)
			level_root.add_child(sp)


func _tiles(P: Dictionary) -> void:
	var tops := []; var bodies := []; var girders := []; var ledges := []; var spikes := []
	var D := 1.4
	for r in sim.h:
		for c in sim.w:
			var ch: String = sim.cell(c, r)
			var p := Vector3(c + 0.5, sim.h - 1 - r + 0.5, 0)
			match ch:
				"#":
					var top: bool = not DashSim.SOLID.contains(sim.cell(c, r - 1))
					(tops if top else bodies).append(Transform3D(Basis.from_scale(Vector3(1.0, 1.0, D)), p))
				"G": girders.append(Transform3D(Basis.from_scale(Vector3(1.0, 1.0, D)), p))
				"-": ledges.append(Transform3D(Basis.from_scale(Vector3(1.0, 0.18, D * 0.9)), p + Vector3(0, 0.41, 0)))
				"^": spikes.append(p)
				"D": _desk(p)
				"W": _cooler(p, c, r)
				"R": _rack(p)
				"o": coin_nodes[Vector2i(c, r)] = _coin(p)
				"?", "P", "H", "B", "U":
					var n := Node3D.new(); n.position = p; level_root.add_child(n)
					_block_look(n, ch)
					blocks[Vector2i(c, r)] = {node = n, ch = ch}
				"C": flag_nodes[Vector2(c + 0.5, sim.h - 1 - r)] = _flag(p - Vector3(0, 0.5, 0))
	var bm := BoxMesh.new()
	var found := []   # foundations: the floor goes down below the screen instead of floating
	for c in sim.w:
		var ch: String = sim.cell(c, sim.h - 1)
		if ch == "#" or ch == "G": found.append(Transform3D(Basis.from_scale(Vector3(1.0, 8.0, D)), Vector3(c + 0.5, -4.0, 0)))
	_multi(bm, _mat(P.body.darkened(0.25), 0.9), found, level_root)
	_multi(bm, _mat(P.top, 0.8), tops, level_root)
	_multi(bm, _mat(P.body, 0.9), bodies, level_root)
	var trims := []   # a strip of carpet / trim along the walkable tops
	for t in tops:
		var tt: Transform3D = t
		trims.append(Transform3D(Basis.from_scale(Vector3(1.0, 0.12, D + 0.04)), tt.origin + Vector3(0, 0.47, 0)))
	_multi(bm, _mat(P.top.lightened(0.25), 0.6), trims, level_root)
	_multi(bm, _mat(Color(0.85, 0.32, 0.12), 0.5, 0.5), girders, level_root)
	var gtrim := []
	for t in girders:
		var tt: Transform3D = t
		gtrim.append(Transform3D(Basis.from_scale(Vector3(1.02, 0.1, D + 0.06)), tt.origin + Vector3(0, 0.45, 0)))
		gtrim.append(Transform3D(Basis.from_scale(Vector3(1.02, 0.1, D + 0.06)), tt.origin + Vector3(0, -0.45, 0)))
	_multi(bm, _mat(Color(0.35, 0.12, 0.06), 0.5, 0.6), gtrim, level_root)
	_multi(bm, _mat(CY if _world() == "server" else BV, 0.4, 0.2, 0.3), ledges, level_root)
	for p in spikes:   # shredders: a metal base with teeth
		_box(Vector3(1.0, 0.3, D), _mat(Color(0.35, 0.36, 0.4), 0.3, 0.8), p + Vector3(0, -0.35, 0), level_root)
		for k in 3:
			_cyl(0.0, 0.5, _mat(Color(0.85, 0.85, 0.9), 0.2, 0.9), p + Vector3(-0.33 + k * 0.33, 0.05, 0), level_root, Vector3.ZERO, 0.14)
	# exit lift
	if sim.exit_cell.x >= 0:
		var ep := Vector3(sim.exit_cell.x + 0.5, sim.h - 1 - sim.exit_cell.y, 0)
		exit_node = Node3D.new(); exit_node.position = ep; level_root.add_child(exit_node)
		_box(Vector3(2.2, 2.6, 0.3), _mat(Color(0.75, 0.76, 0.8), 0.25, 0.9), Vector3(0, 1.3, -0.6), exit_node)
		var dl := _box(Vector3(0.78, 2.2, 0.1), _mat(Color(0.55, 0.57, 0.62), 0.2, 0.9), Vector3(-0.4, 1.1, -0.42), exit_node); dl.name = "dl"
		var dr := _box(Vector3(0.78, 2.2, 0.1), _mat(Color(0.55, 0.57, 0.62), 0.2, 0.9), Vector3(0.4, 1.1, -0.42), exit_node); dr.name = "dr"
		_box(Vector3(1.4, 0.4, 0.1), _mat(Color(0.1, 0.1, 0.12), 0.4), Vector3(0, 2.85, -0.45), exit_node)
		var el := _label("EXIT", 48, Color(0.3, 1.0, 0.5), Vector3(0, 2.85, -0.38), exit_node); el.name = "sign"
		_box(Vector3(2.4, 0.06, 1.0), _mat(GOLD, 0.3, 0.6, 0.8), Vector3(0, 0.03, 0), exit_node)


func _desk(p: Vector3) -> void:
	_box(Vector3(1.0, 0.1, 1.2), _mat(Color(0.62, 0.45, 0.28), 0.5), p + Vector3(0, 0.45, 0), level_root)
	_box(Vector3(0.9, 0.85, 1.0), _mat(Color(0.3, 0.3, 0.34), 0.5, 0.4), p + Vector3(0, -0.05, 0), level_root)
	_box(Vector3(0.5, 0.35, 0.05), _mat(Color(0.05, 0.05, 0.07), 0.4), p + Vector3(0, 0.75, -0.25), level_root)
	_box(Vector3(0.45, 0.28, 0.02), _mat(CY, 0.3, 0.0, 1.4), p + Vector3(0, 0.75, -0.22), level_root)


func _cooler(p: Vector3, c: int, r: int) -> void:
	if sim.cell(c, r - 1) != "W": _cyl(0.32, 0.8, _mat(Color(0.35, 0.65, 0.95, 0.8), 0.1), p + Vector3(0, 0.1, 0), level_root)
	else: _box(Vector3(0.8, 1.0, 0.8), _mat(Color(0.92, 0.92, 0.95), 0.4), p, level_root)


func _rack(p: Vector3) -> void:
	_box(Vector3(1.0, 1.0, 1.2), _mat(Color(0.06, 0.06, 0.09), 0.4, 0.5), p, level_root)
	for k in 3:
		_box(Vector3(0.8, 0.05, 0.02), _mat([Color(0.2, 1.0, 0.4), CY, Color(1, 0.3, 0.3)][k], 0.3, 0.0, 3.0), p + Vector3(0, -0.3 + k * 0.3, 0.61), level_root)


func _coin(p: Vector3) -> Node3D:
	var n := Node3D.new(); n.position = p; level_root.add_child(n)
	_cyl(0.32, 0.08, _mat(GOLD, 0.25, 0.9, 0.4), Vector3.ZERO, n, Vector3(PI / 2, 0, 0))
	_cyl(0.2, 0.09, _mat(BV, 0.4, 0.2, 0.5), Vector3.ZERO, n, Vector3(PI / 2, 0, 0))
	_label("B", 40, Color(1, 1, 1), Vector3(0, 0, 0.06), n).outline_size = 0
	return n


func _flag(p: Vector3) -> Node3D:
	var n := Node3D.new(); n.position = p; level_root.add_child(n)
	_cyl(0.05, 3.0, _mat(Color(0.8, 0.8, 0.85), 0.3, 0.8), Vector3(0, 1.5, -0.3), n)
	var f := _box(Vector3(1.0, 0.6, 0.05), _mat(Color(0.5, 0.5, 0.55), 0.6), Vector3(0.5, 2.6, -0.3), n)
	f.name = "flag"
	return n


## Sticky-note blocks (yellow "+" coin notes, pink / cyan "!" power notes), cubicle panels, used notes.
func _block_look(n: Node3D, ch: String) -> void:
	for k in n.get_children(): k.queue_free()
	match ch:
		"?":
			_box(Vector3(0.96, 0.96, 1.0), _mat(Color(1.0, 0.82, 0.18), 0.7, 0.0, 0.15), Vector3.ZERO, n)
			_box(Vector3(0.96, 0.2, 1.02), _mat(Color(0.95, 0.68, 0.1), 0.7), Vector3(0, 0.38, 0), n)
			_label("+", 120, Color(0.5, 0.25, 0.85), Vector3(0, -0.05, 0.52), n)
		"P", "H":
			_box(Vector3(0.96, 0.96, 1.0), _mat(Color(1.0, 0.42, 0.68) if ch == "P" else CY, 0.7, 0.0, 0.2), Vector3.ZERO, n)
			_box(Vector3(0.96, 0.2, 1.02), _mat(Color(0.85, 0.25, 0.5) if ch == "P" else Color(0.1, 0.5, 0.65), 0.7), Vector3(0, 0.38, 0), n)
			_label("!", 120, Color(1, 1, 1), Vector3(0, -0.05, 0.52), n)
		"B":
			_box(Vector3(1.0, 1.0, 1.1), _mat(Color(0.45, 0.32, 0.65), 0.95), Vector3.ZERO, n)
			_box(Vector3(1.02, 0.08, 1.12), _mat(Color(0.75, 0.75, 0.78), 0.4, 0.6), Vector3(0, 0.46, 0), n)
			_box(Vector3(1.02, 0.08, 1.12), _mat(Color(0.75, 0.75, 0.78), 0.4, 0.6), Vector3(0, -0.46, 0), n)
		"U":
			_box(Vector3(0.96, 0.96, 1.0), _mat(Color(0.5, 0.47, 0.45), 0.9), Vector3.ZERO, n)


# ---------------------------------------------------------------- enemies, items, props
func _enemy_look(kind: String) -> Node3D:
	var n := Node3D.new(); level_root.add_child(n)
	var body := Node3D.new(); body.name = "body"; n.add_child(body)
	var eye := _mat(Color(1.0, 0.2, 0.2), 0.3, 0.0, 3.0)
	match kind:
		"walker":   # stapler bot: a big stapler on little wheels
			_box(Vector3(0.9, 0.3, 0.45), _mat(Color(0.15, 0.15, 0.18), 0.4, 0.5), Vector3(0, 0.3, 0), body)
			var jaw := _box(Vector3(0.95, 0.18, 0.4), _mat(Color(0.85, 0.15, 0.2), 0.4, 0.3), Vector3(0.0, 0.53, 0), body); jaw.name = "jaw"
			for sx in [-0.3, 0.3]: _cyl(0.13, 0.1, _mat(Color(0.05, 0.05, 0.05), 0.8), Vector3(sx, 0.13, 0.24), body, Vector3(PI / 2, 0, 0))
			_sph(0.07, eye, Vector3(0.35, 0.58, 0.18), body)
		"flyer":   # deadline drone: a disc with rotors and a red clock face
			_cyl(0.42, 0.18, _mat(Color(0.2, 0.22, 0.28), 0.3, 0.6), Vector3(0, 0.3, 0), body)
			_cyl(0.22, 0.05, _mat(Color(1.0, 0.25, 0.25), 0.3, 0.0, 2.0), Vector3(0, 0.3, 0.2), body, Vector3(PI / 2, 0, 0))
			for k in 2:
				var rot := _box(Vector3(0.6, 0.02, 0.08), _mat(Color(0.8, 0.8, 0.85), 0.3, 0.6), Vector3(-0.45 + k * 0.9, 0.48, 0), body); rot.name = "rotor%d" % k
		_:   # printer bot: a printer on springy legs with a paper tongue
			_box(Vector3(0.95, 0.6, 0.7), _mat(Color(0.9, 0.9, 0.92), 0.5), Vector3(0, 0.55, 0), body)
			_box(Vector3(0.7, 0.04, 0.4), _mat(Color(1, 1, 1), 0.6), Vector3(0.45, 0.5, 0), body)
			_box(Vector3(0.6, 0.06, 0.05), _mat(Color(0.2, 1.0, 0.4), 0.3, 0.0, 2.5), Vector3(0, 0.75, 0.36), body)
			for sx in [-0.3, 0.3]: _box(Vector3(0.08, 0.3, 0.08), _mat(Color(0.3, 0.3, 0.33), 0.4, 0.7), Vector3(sx, 0.12, 0), body)
			_sph(0.07, eye, Vector3(0.3, 0.7, 0.36), body)
	return n


func _item_look(kind: String) -> Node3D:
	var n := Node3D.new(); level_root.add_child(n)
	match kind:
		"coffee":
			_cyl(0.28, 0.5, _mat(Color(0.97, 0.97, 0.95), 0.5), Vector3(0, 0.3, 0), n, Vector3.ZERO, 0.22)
			_cyl(0.25, 0.03, _mat(Color(0.35, 0.2, 0.1), 0.3), Vector3(0, 0.55, 0), n)
			_box(Vector3(0.6, 0.12, 0.05), _mat(BV, 0.5), Vector3(0, 0.3, 0.26), n)
			for k in 3: _sph(0.07, _mat(Color(1, 1, 1, 0.6), 0.5, 0.0, 0.5), Vector3(-0.1 + k * 0.1, 0.75 + k * 0.08, 0), n)
		"drink":
			_cyl(0.18, 0.6, _mat(CY, 0.3, 0.7, 0.4), Vector3(0, 0.35, 0), n)
			_cyl(0.16, 0.04, _mat(Color(0.8, 0.8, 0.85), 0.2, 0.9), Vector3(0, 0.66, 0), n)
			_box(Vector3(0.3, 0.12, 0.02), _mat(GOLD, 0.4, 0.0, 1.0), Vector3(0, 0.38, 0.18), n)
		_:
			var t := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 0.28; tm.outer_radius = 0.34; t.mesh = tm
			t.material_override = _mat(Color(0.15, 0.15, 0.18), 0.4); t.rotation = Vector3(PI / 2, 0, 0); t.position = Vector3(0, 0.4, 0)
			n.add_child(t)
			for sx in [-0.32, 0.32]: _cyl(0.14, 0.12, _mat(BV, 0.4, 0.2, 0.6), Vector3(sx, 0.32, 0), n, Vector3(0, 0, PI / 2))
	return n


func _spark(at: Vector3, col: Color, n := 6, spd := 4.0) -> void:
	for k in n:
		var p := _box(Vector3(0.12, 0.12, 0.12), _mat(col, 0.3, 0.0, 2.0), at, level_root)
		var a := TAU * k / n
		particles.append([p, Vector3(cos(a) * spd, sin(a) * spd + 3.0, randf_range(-1, 1)), 0.6])


# ---------------------------------------------------------------- flow
func _intro() -> void:
	flow = "intro"; flow_t = 2.4 if not autoplay else 1.2
	_close_panel()


func _physics_process(_dt: float) -> void:
	if sim == null or world == null or paused: return
	match flow:
		"intro":
			flow_t -= 1.0 / 60.0
			if flow_t <= 0.0: flow = "play"
		"play":
			var inp: Dictionary = sim.bot_input() if autoplay else _controls()
			sim.tick(inp)
			for e in sim.events: _event(e)
			if sim.state == "dead" and sim.state_t > 100:
				if sim.lose_life() == "game_over": _game_over()
			elif sim.state == "clear":
				flow = "clear"; flow_t = 3.6 if not autoplay else 1.5
			elif sim.state == "done":
				_victory()
		"clear":
			flow_t -= 1.0 / 60.0
			if flow_t <= 0.0:
				sim.next_level(); _build_level(); _intro()
		"over":
			flow_t += 1.0 / 60.0
			if autoplay and flow_t > 2.5: _restart_run()


func _event(e: Array) -> void:
	stats[e[0]] = stats.get(e[0], 0) + 1
	var at3 := Vector3(e[1].x, e[1].y, 0) if e[1] is Vector2 else Vector3.ZERO
	match String(e[0]):
		"jump": G.sfx("whoosh")
		"coin":
			G.sfx("ok")
			if e[2] == 1: _spark(at3 + Vector3(0, 0.6, 0), GOLD, 5, 3.0)
		"stomp": G.sfx("hit"); _spark(at3 + Vector3(0, 0.4, 0), Color(1, 1, 1), 6, 3.0)
		"kill": _spark(at3 + Vector3(0, 0.4, 0), Color(1.0, 0.6, 0.2), 4, 3.0)
		"bump": G.sfx("block")
		"break":
			G.sfx("heavy")
			for k in 4: particles.append([_box(Vector3(0.4, 0.4, 0.5), _mat(Color(0.45, 0.32, 0.65), 0.9), at3 + Vector3(0, 0.5, 0), level_root), Vector3((k % 2 - 0.5) * 6, 8 + k, 0), 1.2])
		"sprout": G.sfx("grab")
		"power":
			G.sfx("surge")
			_toast({"coffee": "CAFFEINATED!", "drink": "ENERGY DRINK · J TO THROW", "headphones": "HEADPHONES ON · INVINCIBLE"}.get(String(e[2]), ""))
		"shrink": G.sfx("thud"); _toast("CAFFEINE CRASH")
		"die": G.sfx("ko"); shake = 0.6
		"checkpoint":
			G.sfx("ok"); _toast("CHECKPOINT")
			if flag_nodes.has(e[1]):
				var f: MeshInstance3D = (flag_nodes[e[1]] as Node3D).get_node("flag")
				f.material_override = _mat(CY, 0.5, 0.0, 0.8)
		"clear": G.sfx("vs")
		"life": G.sfx("surge"); _toast("1-UP!  100 COINS")
		"boss": G.sfx("vs"); _toast(BOSS_TITLE.get(String(e[2]), "BOSS"))
		"boss_hit": G.sfx("heavy"); shake = 0.4
		"phase": _toast("IT'S PERSONAL NOW!")
		"boss_dead": G.sfx("ko"); _toast("BOSS BEATEN!  THE LIFT IS OPEN"); shake = 0.8
		"slam": shake = 0.5; G.sfx("thud")
		"throw", "throw_boss": G.sfx("whoosh")


func _toast(t: String) -> void:
	if t == "": return
	toast = t; toast_t = 2.2


func _game_over() -> void:
	flow = "over"; flow_t = 0.0
	stats["game_over"] = stats.get("game_over", 0) + 1
	_panel("GAME OVER", "Out of lives: the deadline won. Back to level 1 with 3 lives.", [["START AGAIN", _restart_run], ["MAIN MENU", _quit]])


func _restart_run() -> void:
	sim.new_run(); _build_level(); _intro()


func _victory() -> void:
	flow = "victory"; flow_t = 0.0
	stats["victory"] = 1
	_panel("YOU BEAT THE DEADLINE!", "All 10 levels cleared  ·  score %d" % sim.score, [["PLAY AGAIN", _restart_run], ["MAIN MENU", _quit]])


func _quit() -> void:
	paused = false
	finished.emit()
	G.ui.show_title()


func _panel(title: String, sub: String, buttons: Array) -> void:
	_close_panel()
	var ui = G.ui
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.03, 0.1, 0.92); sb.border_color = BV; sb.set_border_width_all(2)
	sb.set_content_margin_all(24)
	p.add_theme_stylebox_override("panel", sb)
	layer.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(ui.lbl(title, 48, font, GOLD, 10))
	v.add_child(ui.lbl(sub, 20, small, Color(0.85, 0.87, 0.95)))
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var first: Button = null
	for b in buttons:
		var btn: Button = ui.big_btn(String(b[0]), CY if first == null else Color(0.55, 0.62, 0.75), b[1])
		row.add_child(btn)
		if first == null: first = btn
	p.reset_size()
	p.position = (G.get_viewport().get_visible_rect().size - p.size) / 2.0
	panel = p
	if first != null: first.call_deferred("grab_focus")


func _close_panel() -> void:
	if panel != null: panel.queue_free(); panel = null


func toggle_pause() -> void:
	if flow in ["over", "victory"]: return
	paused = not paused
	if paused: _panel("PAUSED", "Level %d · %s" % [sim.level + 1, Levels.LEVELS[sim.level].name], [["RESUME", toggle_pause], ["QUIT TO MENU", _quit]])
	else: _close_panel()


# ---------------------------------------------------------------- input
func _controls() -> Dictionary:
	var k := func(keys: Array) -> bool:
		for key in keys:
			if Input.is_physical_key_pressed(key): return true
		return false
	var x := (1.0 if k.call([KEY_D, KEY_RIGHT]) else 0.0) - (1.0 if k.call([KEY_A, KEY_LEFT]) else 0.0)
	var jump: bool = k.call([KEY_SPACE, KEY_W, KEY_UP])
	var act: bool = k.call([KEY_J, KEY_X])
	var run: bool = k.call([KEY_SHIFT, KEY_K]) or act
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var d: int = pads[0]
		var ax := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
		if absf(ax) > 0.25: x = signf(ax)
		if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT): x = -1.0
		if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT): x = 1.0
		jump = jump or Input.is_joy_button_pressed(d, JOY_BUTTON_A)
		act = act or Input.is_joy_button_pressed(d, JOY_BUTTON_X)
		run = run or Input.is_joy_button_pressed(d, JOY_BUTTON_X) or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	if _touch():
		if _t("left"): x = -1.0
		if _t("right"): x = 1.0
		jump = jump or _t("jump")
		act = act or _t("action")
		run = true
	var out := {x = x, jump = jump, jump_press = jump and not _jump_was, run = run, action = act and not _act_was}
	_jump_was = jump; _act_was = act
	return out


func _unhandled_input(e: InputEvent) -> void:
	if sim == null: return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_P, KEY_ESCAPE]: toggle_pause()
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START: toggle_pause()


func _touch() -> bool: return G != null and G.ui.touch_enabled


func _t(n: String) -> bool: return touch_btn.has(n) and touch_btn[n].held


func _layout_touch() -> void:
	if not _touch(): return
	var s: Vector2 = G.get_viewport().get_visible_rect().size
	var r := clampf(s.y * 0.09, 40.0, 70.0)
	touch_btn = {
		left = {c = Vector2(r * 1.5, s.y - r * 1.6), r = r, label = "<", held = false},
		right = {c = Vector2(r * 4.0, s.y - r * 1.6), r = r, label = ">", held = false},
		jump = {c = Vector2(s.x - r * 1.6, s.y - r * 1.8), r = r * 1.15, label = "JUMP", held = false},
		action = {c = Vector2(s.x - r * 4.0, s.y - r * 1.3), r = r * 0.85, label = "THROW", held = false},
		pause = {c = Vector2(s.x / 2.0, 100), r = 26.0, label = "II", held = false},
	}


func _input(e: InputEvent) -> void:
	if not _touch() or sim == null: return
	if e is InputEventScreenTouch:
		if e.pressed:
			for n in touch_btn:
				if e.position.distance_to(touch_btn[n].c) <= touch_btn[n].r * 1.2:
					touches[e.index] = n
					if n == "pause": toggle_pause()
		else:
			touches.erase(e.index)
		for n in touch_btn: touch_btn[n].held = touches.values().has(n)
	elif e is InputEventScreenDrag and touches.has(e.index):
		for n in ["left", "right"]:   # slide between left and right
			if e.position.distance_to(touch_btn[n].c) <= touch_btn[n].r * 1.2: touches[e.index] = n
		for n in touch_btn: touch_btn[n].held = touches.values().has(n)


# ---------------------------------------------------------------- drawing
func _process(dt: float) -> void:
	if sim == null or world == null: return
	_sync(dt)
	toast_t = maxf(0.0, toast_t - dt)
	hud.queue_redraw()


func _sync(dt: float) -> void:
	var k := clampf(dt, 0.0, 0.1)
	# hero
	var big: bool = sim.power != ""
	hero_scale = lerpf(hero_scale, 0.92 if big else 0.62, clampf(k * 10.0, 0.0, 1.0)) if dt > 0.0 else (0.92 if big else 0.62)
	hero.scale = Vector3.ONE * hero_scale
	hero.position = Vector3(sim.pos.x, sim.pos.y, 0.1)
	hero.rotation.y = lerp_angle(hero.rotation.y, (PI / 2.0 - 0.45) * sim.facing, clampf(k * 14.0, 0.0, 1.0)) if dt > 0.0 else (PI / 2.0 - 0.45)
	hero_anim += dt
	var clip := "idle_cheerful"
	var t := fmod(hero_anim, 2.0)
	var loop := true
	if sim.state == "dead":
		clip = "fall_back"; t = minf(sim.state_t / 60.0, 1.4); loop = false
	elif flow == "clear" or flow == "victory":
		clip = Fighter.own_clip(C, "win", "win_cheer"); t = minf((3.6 - flow_t) if flow == "clear" else hero_anim, 3.0); loop = false
	elif not sim.on_ground:
		clip = "gun_jump"; t = 0.35 if sim.vel.y > 0 else 0.6; loop = false
	elif absf(sim.vel.x) > 0.4:
		clip = "m_run" if absf(sim.vel.x) > 6.0 else "m_walk"
		t = hero_anim * absf(sim.vel.x) / (8.0 if clip == "m_run" else 4.0)
	if ClipLib.has(clip):
		hero.set_clip(clip, fmod(t, Fighter._len(clip)) if loop else minf(t, Fighter._len(clip) - 0.02), false, false)
	hero.apply_pose(C.pose.guard, true)
	var blink: bool = (sim.invuln > 0 and sim.state == "play" and int(sim.invuln / 5) % 2 == 0)
	hero.visible = not blink
	if hero.has_method("set_flash"): hero.set_flash(0.5 * (0.5 + 0.5 * sin(hero_anim * 20.0)) if sim.star > 0 else 0.0)
	# camera: follows with look-ahead, a little above; frames the whole arena in a boss fight
	var want_x: float = sim.pos.x + sim.facing * 2.0
	if not sim.boss.is_empty() and sim.boss.active and sim.boss.alive: want_x = sim.boss.l + 14.0
	cam_x = lerpf(cam_x, want_x, clampf(k * 3.5, 0.0, 1.0)) if dt > 0.0 else want_x
	var want_y := clampf(sim.pos.y + 1.6, 4.6, 9.0)
	cam_y = lerpf(cam_y, want_y, clampf(k * 3.0, 0.0, 1.0)) if dt > 0.0 else want_y
	if boss_fight_now(): cam_y = maxf(cam_y, 6.0)
	shake = maxf(0.0, shake - k * 2.0)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.25
	var boss_fight: bool = not sim.boss.is_empty() and sim.boss.active
	cam.position = Vector3(cam_x, cam_y + 1.0, 17.0 if boss_fight else 12.5) + sh
	cam.look_at(Vector3(cam_x, cam_y, 0) + sh, Vector3.UP)
	# blocks and coins
	for key in blocks:
		var b: Dictionary = blocks[key]
		var ch: String = sim.cell(key.x, key.y)
		if ch != b.ch:
			if ch == ".": (b.node as Node3D).visible = false
			else: _block_look(b.node, ch)
			b.ch = ch
		var bump := 0.0
		for bb in sim.bumps:
			if bb[0] == key: bump = sin(bb[1] / 10.0 * PI) * 0.25
		(b.node as Node3D).position.y = sim.h - 1 - key.y + 0.5 + bump
	for key in coin_nodes:
		var cn: Node3D = coin_nodes[key]
		cn.visible = sim.cell(key.x, key.y) == "o"
		if cn.visible: cn.rotation.y = hero_anim * 2.5 + key.x * 0.4
	# enemies
	while enemy_nodes.size() < sim.enemies.size(): enemy_nodes.append(_enemy_look(String(sim.enemies[enemy_nodes.size()].kind)))
	for i in sim.enemies.size():
		var e: Dictionary = sim.enemies[i]
		var n: Node3D = enemy_nodes[i]
		n.position = Vector3(e.pos.x, e.pos.y, 0)
		n.rotation.y = 0.0 if e.dir > 0 else PI
		var body: Node3D = n.get_node("body")
		if not e.alive:
			if e.get("flip", false):
				body.rotation.z = PI
				n.position.y += e.dead_t * 0.06 - pow(e.dead_t * 0.03, 2.0) * 3.0
			else:
				body.scale = Vector3(1.2, 0.25, 1.0)
			n.visible = e.dead_t < 40
		else:
			body.rotation = Vector3.ZERO; body.scale = Vector3.ONE; n.visible = true
			for c in body.get_children():
				if String(c.name).begins_with("rotor"): (c as Node3D).rotation.y = hero_anim * 30.0
			if body.has_node("jaw"): (body.get_node("jaw") as Node3D).rotation.z = 0.1 + absf(sin(hero_anim * 6.0)) * 0.25
	# items, planes, boss shots
	_sync_list(sim.items, item_nodes, func(it): return _item_look(String(it.kind)), func(it, n):
		n.position = Vector3(it.pos.x, it.pos.y, 0.2); n.rotation.y = hero_anim * 2.0)
	_sync_list(sim.planes, plane_nodes, _plane_node, func(p, n):
		n.position = Vector3(p.pos.x, p.pos.y, 0.2); n.rotation = Vector3(0, PI / 2.0 * signf(p.vel.x), 0))
	_sync_list(sim.hazards, hazard_nodes, _hazard_node, func(z, n):
		n.position = Vector3(z.pos.x, z.pos.y, 0.2)
		if z.kind != "wave": n.rotation.z += 0.2)
	for i in sim.plats.size():
		(plat_nodes[i] as Node3D).position = Vector3(sim.plats[i].pos.x, sim.plats[i].pos.y, 0)
	# the lift doors open when you can leave
	if exit_node != null:
		var open: bool = sim.exit_open
		var dl: Node3D = exit_node.get_node("dl"); var dr: Node3D = exit_node.get_node("dr")
		dl.position.x = lerpf(dl.position.x, -0.95 if open else -0.4, clampf(k * 3.0, 0.0, 1.0))
		dr.position.x = lerpf(dr.position.x, 0.95 if open else 0.4, clampf(k * 3.0, 0.0, 1.0))
		(exit_node.get_node("sign") as Label3D).modulate = Color(0.3, 1.0, 0.5) if open else Color(1.0, 0.3, 0.3)
	# boss
	if boss_rig != null and not sim.boss.is_empty():
		var b: Dictionary = sim.boss
		boss_rig.position = Vector3(b.pos.x, b.pos.y, 0.0)
		boss_rig.visible = b.alive or b.dead_t < 240
		var face: float = signf(sim.pos.x - b.pos.x) if b.state != "charge" else float(b.dir)
		if face == 0.0: face = -1.0
		boss_rig.rotation.y = lerp_angle(boss_rig.rotation.y, (PI / 2.0 - 0.35) * face, clampf(k * 8.0, 0.0, 1.0))
		boss_anim += dt
		var bc := "idle_boss"
		var bt := fmod(boss_anim, 2.0)
		if not b.alive: bc = "ko"; bt = minf(b.dead_t / 60.0, 2.0)
		elif not b.on_ground: bc = "gun_jump"; bt = 0.4
		elif b.state == "charge" and b.t > 25: bc = "m_run"; bt = boss_anim * 1.3
		elif b.state == "throw": bc = "pw_throw"; bt = b.t / 60.0 * 1.5
		elif b.state == "summon": bc = "pw_magic"; bt = b.t / 60.0
		elif b.state == "intro": bc = "taunt_angry"; bt = b.t / 60.0
		if ClipLib.has(bc): boss_rig.set_clip(bc, fmod(bt, Fighter._len(bc)), false, false)
		boss_rig.apply_pose(boss_C.pose.guard, true)
		if boss_rig.has_method("set_flash"): boss_rig.set_flash(0.6 if (b.inv > 0 and int(b.inv / 4) % 2 == 0) else 0.0)
	# particles
	for p in particles.duplicate():
		var pn: Node3D = p[0]
		p[1].y -= 20.0 * k
		pn.position += p[1] * k
		pn.rotation += Vector3(3, 4, 0) * k
		p[2] -= k
		if p[2] <= 0.0: pn.queue_free(); particles.erase(p)


func boss_fight_now() -> bool: return not sim.boss.is_empty() and sim.boss.active


func _plane_node(_p) -> Node3D:
	var pp := PowerProps.build("letters", CY)
	pp.scale = Vector3.ONE * 3.0
	level_root.add_child(pp)
	return pp


func _hazard_node(z) -> Node3D:
	if z.kind == "wave":   # a floor shockwave
		var wn := Node3D.new(); level_root.add_child(wn)
		_box(Vector3(0.8, 0.7, 1.2), _mat(Color(1.0, 0.45, 0.1, 0.85), 0.3, 0.0, 2.5), Vector3(0, 0.35, 0), wn)
		return wn
	var kind: String = {"hr": "contract", "admin": "keys", "wizard": "runes", "ceo": "briefcase"}.get(String(sim.boss.get("kind", "")), "contract")
	var pp := PowerProps.build(kind, BV)
	pp.scale = Vector3.ONE * 2.2
	level_root.add_child(pp)
	return pp


## Dictionaries from the sim matched to nodes by a hidden id we tag them with.
func _sync_list(list: Array, nodes: Dictionary, make: Callable, update: Callable) -> void:
	var alive := {}
	for o in list:
		if not o.has("_id"): o["_id"] = _next_id; _next_id += 1
		alive[o._id] = true
		if not nodes.has(o._id): nodes[o._id] = make.call(o)
		update.call(o, nodes[o._id])
	for key in nodes.keys():
		if not alive.has(key): (nodes[key] as Node).queue_free(); nodes.erase(key)


func _draw_hud() -> void:
	var sz := hud.size
	var ink := Color(0.97, 0.97, 1.0)
	# top bar
	hud.draw_rect(Rect2(Vector2.ZERO, Vector2(sz.x, 64)), Color(0.03, 0.02, 0.08, 0.55))
	var acc: Color = C.accent
	hud.draw_circle(Vector2(34, 32), 18, acc)
	hud.draw_string(font, Vector2(16, 40), String(C.name).left(1), HORIZONTAL_ALIGNMENT_CENTER, 36, 22, Color.WHITE)
	hud.draw_string(font, Vector2(60, 42), "× %d" % sim.lives, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	hud.draw_circle(Vector2(170, 32), 14, GOLD)
	hud.draw_string(font, Vector2(156, 39), "B", HORIZONTAL_ALIGNMENT_CENTER, 28, 18, BV)
	hud.draw_string(font, Vector2(192, 42), "%02d" % sim.coins, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	hud.draw_string(font, Vector2(260, 42), "%07d" % sim.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.8, 0.85, 1.0))
	var L: Dictionary = Levels.LEVELS[sim.level]
	hud.draw_string(font, Vector2(0, 30), "LEVEL %d  ·  %s" % [sim.level + 1, L.name], HORIZONTAL_ALIGNMENT_CENTER, sz.x, 22, ink)
	hud.draw_string(small, Vector2(0, 54), String(Levels.WORLD_NAME[L.world]) + ("   ·   WIND <<" if sim.wind_on and sim.wind < -3.0 else ""), HORIZONTAL_ALIGNMENT_CENTER, sz.x, 18, Color(0.75, 0.8, 0.95))
	var tl := maxi(0, int(ceil(sim.time_left)))
	hud.draw_string(font, Vector2(sz.x - 200, 42), "TIME %d" % tl, HORIZONTAL_ALIGNMENT_RIGHT, 180, 26, Color(1.0, 0.4, 0.4) if tl < 60 else ink)
	# power
	if sim.power != "" or sim.star > 0:
		var pw := ("HEADPHONES  %d" % ceili(sim.star / 60.0)) if sim.star > 0 else ("CAFFEINATED" if sim.power == "coffee" else "ENERGY DRINK · J THROW")
		hud.draw_string(small, Vector2(24, 92), pw, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, CY)
	# boss bar
	if not sim.boss.is_empty() and sim.boss.active and sim.boss.alive:
		var b: Dictionary = sim.boss
		var bw := minf(600.0, sz.x * 0.6)
		var r := Rect2(Vector2((sz.x - bw) / 2.0, sz.y - 80), Vector2(bw, 22))
		hud.draw_rect(r.grow(3), Color(0, 0, 0, 0.6))
		hud.draw_rect(Rect2(r.position, Vector2(bw * float(b.hp) / float(b.max_hp), 22)), Color(0.95, 0.25, 0.3))
		hud.draw_string(font, r.position + Vector2(0, -8), "%s  ·  %s" % [BOSS_TITLE.get(String(b.kind), "BOSS"), String(boss_C.get("name", ""))], HORIZONTAL_ALIGNMENT_CENTER, bw, 22, ink)
	if toast_t > 0.0:
		hud.draw_string(font, Vector2(0, sz.y * 0.3), toast, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 40, Color(1.0, 0.85, 0.3, clampf(toast_t, 0.0, 1.0)))
	# level intro card / clear tally
	if flow == "intro":
		hud.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.02, 0.08, 0.85))
		hud.draw_string(font, Vector2(0, sz.y * 0.4), "LEVEL %d" % (sim.level + 1), HORIZONTAL_ALIGNMENT_CENTER, sz.x, 64, GOLD)
		hud.draw_string(font, Vector2(0, sz.y * 0.4 + 56), "%s  ·  %s" % [Levels.WORLD_NAME[L.world], L.name], HORIZONTAL_ALIGNMENT_CENTER, sz.x, 30, ink)
		hud.draw_string(small, Vector2(0, sz.y * 0.4 + 100), "LIVES × %d%s" % [sim.lives, "   ·   BOSS AHEAD" if L.has("boss") else ""], HORIZONTAL_ALIGNMENT_CENTER, sz.x, 24, CY)
	elif flow == "clear":
		hud.draw_rect(Rect2(Vector2(sz.x / 2.0 - 280, sz.y * 0.3), Vector2(560, 180)), Color(0.03, 0.02, 0.08, 0.85))
		hud.draw_string(font, Vector2(0, sz.y * 0.3 + 60), "LEVEL CLEAR!", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 48, GOLD)
		hud.draw_string(small, Vector2(0, sz.y * 0.3 + 110), "TIME BONUS %d   ·   COINS %d   ·   SCORE %d" % [int(sim.time_left) * 10, sim.coins, sim.score], HORIZONTAL_ALIGNMENT_CENTER, sz.x, 24, ink)
		hud.draw_string(small, Vector2(0, sz.y * 0.3 + 145), "NEXT: LEVEL %d · %s" % [sim.level + 2, Levels.LEVELS[mini(sim.level + 1, 9)].name], HORIZONTAL_ALIGNMENT_CENTER, sz.x, 20, CY)
	if not _touch() and flow == "play":
		hud.draw_string(small, Vector2(0, sz.y - 10), "A/D move · SHIFT run · SPACE jump (hold = higher) · J throw · P pause", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 16, Color(1, 1, 1, 0.55))
	_draw_touch()


func _draw_touch() -> void:
	if not _touch(): return
	for n in touch_btn:
		var b: Dictionary = touch_btn[n]
		if n == "action" and sim.power != "drink": continue
		var col := Color(1.0, 0.8, 0.3) if n == "jump" else BV
		hud.draw_circle(b.c, b.r, Color(col, 0.5 if b.held else 0.2))
		hud.draw_arc(b.c, b.r, 0, TAU, 40, Color(col, 0.9), 3.0)
		var fs := int(b.r * (0.6 if String(b.label).length() <= 2 else 0.34))
		hud.draw_string(font, b.c + Vector2(-b.r, fs * 0.36), b.label, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, Color.WHITE)


# ---------------------------------------------------------------- tests
func _goto_level(i: int) -> void:
	sim.load_level(i); _build_level(); _intro()


func _wait(sec: float) -> void:
	await G.get_tree().create_timer(sec).timeout


func _into_arena() -> void:
	flow = "play"
	sim.pos = Vector2(sim.boss.l + 4.0, 2.0); sim.checkpoint = sim.pos
	cam_x = sim.boss.l + 14.0


## --autotest=dash: the bot plays level 1; a server level; two boss fights; the clear tally, game over and victory.
func autotest(shot: Callable) -> void:
	await _wait(1.6)
	await shot.call("dash_l1_start")
	await _wait(7.0)
	await shot.call("dash_l1_mid")
	var l1 := {x = sim.pos.x, coins = sim.coins, score = sim.score, lives = sim.lives}
	_goto_level(3)
	await _wait(6.0)
	await shot.call("dash_l4_server")
	var l4x: float = sim.pos.x
	# boss of level 3, straight into the arena
	_goto_level(2)
	sim.god = true
	_into_arena()
	await _wait(5.0)
	await shot.call("dash_boss_hr")
	var hr_hp := float(sim.boss.hp)
	_goto_level(9)
	_into_arena()
	await _wait(6.0)
	await shot.call("dash_boss_ceo")
	var ceo_hp := float(sim.boss.hp)
	sim.god = false
	# level clear tally
	_goto_level(6)
	flow = "play"
	await _wait(0.3)
	sim._clear()
	await _wait(0.6)
	await shot.call("dash_clear")
	# game over: last life gone
	_goto_level(0)
	flow = "play"
	sim.lives = 1
	autoplay = false
	sim._die("test")
	await _wait(2.4)
	await shot.call("dash_gameover")
	var over_ok: bool = flow == "over"
	_restart_run()
	var restart_ok: bool = sim.level == 0 and sim.lives == 3
	# victory after the last level
	_goto_level(9)
	flow = "play"
	await _wait(0.3)
	sim._clear()
	await _wait(1.5)
	await shot.call("dash_victory")
	print("AUTOTEST dash level1 bot x=%.1f coins=%d score=%d lives=%d  level4 x=%.1f  hr boss hp=%.1f  ceo boss hp=%.1f  game_over=%s restart_l1_3lives=%s victory=%s" % [
		l1.x, l1.coins, l1.score, l1.lives, l4x, hr_hp, ceo_hp, over_ok, restart_ok, flow == "victory"])


## --autotest=dashsim: every level loads and the bot (enemies can't hurt it, pits and shredders still do)
## reaches each exit; lives / restart / 1-up / checkpoint rules.
func selftest(_main) -> void:
	var all_ok := true
	for i in Levels.LEVELS.size():
		var s = DashSim.new()
		s.load_level(i)
		s.god = true
		var ticks := 0
		var deaths := 0
		while ticks < 60 * 360 and s.state in ["play", "dead"]:
			s.tick(s.bot_input())
			ticks += 1
			if s.state == "dead" and s.state_t > 30:
				deaths += 1; s.lives = 3; s.lose_life()
		var bot_ok: bool = s.state in ["clear", "done"]
		var s2 = DashSim.new(); s2.load_level(i)
		var reach: bool = s2.reachable()
		all_ok = all_ok and reach
		print("AUTOTEST dashsim level %d %s width=%d enemies=%d boss=%s exit_reachable=%s  bot_reached_exit=%s (%.0fs, %d falls, last x=%.1f)" % [i + 1, Levels.LEVELS[i].name, s.w, s2.enemies.size(),
			s2.boss.get("kind", "-"), "PASS" if reach else "FAIL", bot_ok, ticks / 60.0, deaths, s.pos.x])
	var r = DashSim.new()
	r.new_run()
	r.load_level(4)
	var res := ""
	for k in 3:
		r.state = "play"; r._die("test"); res = r.lose_life()
	var over_ok: bool = res == "game_over" and r.state == "over"
	r.new_run()
	var restart_ok: bool = r.level == 0 and r.lives == 3 and r.state == "play"
	print("AUTOTEST dashsim game over after 3 lives: %s   restart at level 1 with 3 lives: %s" % ["PASS" if over_ok else "FAIL", "PASS" if restart_ok else "FAIL"])
	var lv: int = r.lives
	r.add_coins(100)
	var oneup: bool = r.lives == lv + 1 and r.coins == 0
	print("AUTOTEST dashsim 100 coins = 1 life: %s" % ("PASS" if oneup else "FAIL"))
	var c = DashSim.new(); c.new_run()
	c.checkpoint = Vector2(40.5, 2.0); c._die("test")
	var rr: String = c.lose_life()
	var cp_ok: bool = rr == "respawn" and c.pos.distance_to(Vector2(40.5, 2.0)) < 0.01 and c.lives == 2
	print("AUTOTEST dashsim respawn at checkpoint: %s" % ("PASS" if cp_ok else "FAIL"))
	print("AUTOTEST dashsim %s" % ("PASS" if all_ok and over_ok and restart_ok and oneup and cp_ok else "FAIL (see above)"))
