class_name Stage
extends Node3D
## A fight stage: sky, lighting, fog, floor, set pieces, weather particles and per-frame animation.
## Build with Stage.make(id). All stages share the same fighting ring (radius Main.ARENA_R).

const LIST := [
	{id = "open_office", name = "Open Office", sub = "Bit & Bytes HQ · after hours", accent = Color(0.62, 0.42, 1.0)},
	{id = "server_room", name = "Server Room", sub = "Cold aisle · blinking racks", accent = Color(0.25, 0.75, 1.0)},
	{id = "boardroom", name = "Boardroom", sub = "Quarterly review · sunset", accent = Color(1.0, 0.7, 0.35)},
	{id = "cafeteria", name = "Cafeteria", sub = "Chai break · lunch rush", accent = Color(1.0, 0.55, 0.4)},
	{id = "rooftop", name = "HQ Rooftop", sub = "Storm over the city", accent = Color(0.75, 0.5, 1.0)},
]
const FLOOR := preload("res://shaders/stage_floor.gdshader")
const ADDITIVE := preload("res://shaders/additive.gdshader")

var id := "open_office"
var t := 0.0
var env: Environment
var sun: DirectionalLight3D
var sun_energy := 1.0
var ambient_energy := 0.5
var anims: Array[Callable] = []
var flash := 0.0
var next_flash := 3.0


static func info(sid: String) -> Dictionary:
	for s in LIST:
		if s.id == sid: return s
	return LIST[0]


static func make(sid: String) -> Stage:
	var s := Stage.new()
	s.id = sid
	s.call("_build_" + sid)
	return s


func _process(dt: float) -> void:
	t += dt
	for a in anims:
		a.call(dt)


# ---------------------------------------------------------------- helpers
func mat(c: Color, rough := 0.7, metal := 0.0, emit := Color.BLACK, emit_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	if emit_e > 0.0:
		m.emission_enabled = true; m.emission = emit; m.emission_energy_multiplier = emit_e
	return m


func glow(c: Color, e := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * e
	return m


func add(mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = m; mi.position = pos; mi.rotation = rot; mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z); return b


static func cyl(r1: float, r2: float, h: float, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = r1; c.bottom_radius = r2; c.height = h; c.radial_segments = seg; return c


static func sph(r: float, h := -1.0) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0 if h < 0 else h; s.radial_segments = 16; s.rings = 10; return s


func setup_env(top: Color, horizon: Color, ground: Color, amb: Color, amb_e: float, fog_c: Color, fog_d: float, glow_i := 0.45) -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = top; sm.sky_horizon_color = horizon
	sm.ground_bottom_color = ground; sm.ground_horizon_color = horizon.darkened(0.3)
	sm.sun_angle_max = 8.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	ambient_energy = amb_e
	env.fog_enabled = fog_d > 0.0
	env.fog_light_color = fog_c
	env.fog_density = fog_d
	env.glow_enabled = true
	env.glow_intensity = glow_i
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)


func setup_sun(c: Color, energy: float, pitch: float, yaw: float, rims: Array) -> void:
	sun = DirectionalLight3D.new()
	sun.light_color = c; sun.light_energy = energy; sun_energy = energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 25
	sun.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0)
	add_child(sun)
	for r in rims:   # [color, yaw, energy]: colored back lights that outline the fighters
		var l := DirectionalLight3D.new()
		l.light_color = r[0]; l.light_energy = r[2]
		l.rotation = Vector3(deg_to_rad(-20), deg_to_rad(r[1]), 0)
		add_child(l)


func floor_plane(mode: int, ring: Color) -> void:
	var fm := ShaderMaterial.new()
	fm.shader = FLOOR
	fm.set_shader_parameter("mode", mode)
	fm.set_shader_parameter("ring_color", ring)
	var plane := PlaneMesh.new(); plane.size = Vector2(22, 22); plane.subdivide_width = 2; plane.subdivide_depth = 2
	add(plane, fm, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)


func particles(amount: int, mesh: Mesh, m: Material, box_size: Vector3, center: Vector3, vel: Vector3, spread: float, life: float, spin := 0.0, gravity := Vector3.ZERO) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount; p.lifetime = life; p.preprocess = life
	p.mesh = mesh; p.material_override = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box_size
	p.position = center
	p.direction = vel.normalized(); p.spread = spread
	p.initial_velocity_min = vel.length() * 0.8; p.initial_velocity_max = vel.length() * 1.2
	p.gravity = gravity
	if spin > 0.0:
		p.angular_velocity_min = -spin; p.angular_velocity_max = spin
		p.particle_flag_rotate_y = true
		p.angle_min = 0; p.angle_max = 360
	p.local_coords = false
	add_child(p)
	return p


func skyline(count: int, rmin: float, rmax: float, hmin: float, hmax: float, _base: Color, _lit: float) -> void:
	var wsh := preload("res://shaders/windows.gdshader")
	for i in count:
		var a := randf() * TAU
		var r := randf_range(rmin, rmax)
		var h := randf_range(hmin, hmax)
		var w := randf_range(2.0, 6.0)
		var sm := ShaderMaterial.new(); sm.shader = wsh
		sm.set_shader_parameter("repeat", Vector2(w * 1.2, h * 0.9)); sm.set_shader_parameter("seed", randf() * 100.0)
		add(box(w, h, w), sm, Vector3(sin(a) * r, h / 2.0 - 0.5, cos(a) * r), Vector3(0, a, 0), Vector3.ONE, false)


func crowd(rows: int, per_row: int, r0: float, colors: Array, bob := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cm := CapsuleMesh.new(); cm.radius = 0.22; cm.height = 0.95
	mm.mesh = cm
	mm.instance_count = rows * per_row
	var base: Array[Transform3D] = []
	var phase: Array[float] = []
	for i in mm.instance_count:
		var row := i % rows
		var a := randf() * TAU
		var r := r0 + row * 1.4
		var tr := Transform3D(Basis().scaled(Vector3.ONE * randf_range(0.9, 1.2)), Vector3(sin(a) * r, 0.6 + row * 0.7, cos(a) * r))
		mm.set_instance_transform(i, tr)
		mm.set_instance_color(i, colors.pick_random())
		base.append(tr); phase.append(randf() * TAU)
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	var m := StandardMaterial3D.new(); m.vertex_color_use_as_albedo = true; m.roughness = 1.0
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	if bob:
		anims.append(func(_dt):
			for i in range(0, mm.instance_count):
				var tr: Transform3D = base[i]
				tr.origin.y += absf(sin(t * 3.0 + phase[i])) * 0.12
				mm.set_instance_transform(i, tr))


func lantern(pos: Vector3, c: Color, e := 1.6, light_range := 4.0) -> void:
	add(sph(0.18, 0.4), glow(c, e), pos, Vector3.ZERO, Vector3.ONE, false)
	var l := OmniLight3D.new()
	l.light_color = c; l.light_energy = 1.2; l.omni_range = light_range; l.position = pos
	add_child(l)


# ---------------------------------------------------------------- stages
func _build_neon() -> void:
	setup_env(Color(0.02, 0.02, 0.08), Color(0.12, 0.06, 0.2), Color(0.02, 0.02, 0.04), Color(0.55, 0.6, 0.8), 0.55, Color(0.03, 0.045, 0.09), 0.012)
	setup_sun(Color(1, 0.96, 0.9), 1.05, -55, 30, [[Color(0.18, 0.9, 1.0), -130, 0.45], [Color(1, 0.3, 0.42), 130, 0.35]])
	floor_plane(0, Color(0.18, 0.9, 1.0))
	add(cyl(9.6, 9.9, 0.25, 64), mat(Color(0.07, 0.09, 0.15), 0.6, 0.3), Vector3(0, -0.13, 0), Vector3.ZERO, Vector3.ONE, false)
	var pm := mat(Color(0.09, 0.12, 0.2), 0.5, 0.5)
	for i in 8:
		var a := i / 8.0 * TAU + PI / 8
		var x := sin(a) * 12.5
		var z := cos(a) * 12.5
		add(cyl(0.35, 0.5, 8), pm, Vector3(x, 4, z))
		for k in 3:
			var tor := TorusMesh.new(); tor.inner_radius = 0.38; tor.outer_radius = 0.46
			add(tor, glow(Color(1, 0.3, 0.42) if i % 2 else Color(0.18, 0.9, 1.0), 1.5), Vector3(x, 2.2 + k * 2.2, z), Vector3.ZERO, Vector3.ONE, false)
	crowd(4, 65, 15.0, [Color(0.06, 0.07, 0.12), Color(0.09, 0.06, 0.12), Color(0.05, 0.08, 0.11)])
	skyline(70, 26, 44, 8, 30, Color(0.05, 0.06, 0.1), 0.33)
	# hologram ad screens hovering over the stands
	var holo := preload("res://shaders/hologram.gdshader")
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4
		var hm := ShaderMaterial.new(); hm.shader = holo
		hm.set_shader_parameter("color", [Color(0.18, 0.9, 1.0), Color(1, 0.3, 0.42), Color(1, 0.8, 0.3), Color(0.6, 0.4, 1.0)][i])
		hm.set_shader_parameter("seed", i * 1.7)
		var q := QuadMesh.new(); q.size = Vector2(5, 2.4)
		var mi := add(q, hm, Vector3(sin(a) * 17, 7.5, cos(a) * 17), Vector3(0, a + PI, 0), Vector3.ONE, false)
		var base_y := mi.position.y
		anims.append(func(_dt): mi.position.y = base_y + sin(t * 0.8 + i) * 0.25)
	# sweeping spotlights with visible beams
	for i in 4:
		var a := i * TAU / 4.0
		var pivot := Node3D.new()
		pivot.position = Vector3(sin(a) * 11, 9, cos(a) * 11)
		add_child(pivot)
		var sl := SpotLight3D.new()
		var c: Color = [Color(0.18, 0.9, 1.0), Color(1, 0.3, 0.42)][i % 2]
		sl.light_color = c; sl.light_energy = 3.0; sl.spot_range = 20; sl.spot_angle = 14
		pivot.add_child(sl)
		var beam := MeshInstance3D.new()
		var cone := cyl(0.15, 2.4, 10, 20)
		cone.cap_top = false; cone.cap_bottom = false
		beam.mesh = cone
		var bm := ShaderMaterial.new(); bm.shader = ADDITIVE
		bm.set_shader_parameter("color", c); bm.set_shader_parameter("alpha", 0.06)
		beam.material_override = bm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(0, 0, -5); beam.rotation = Vector3(PI / 2, 0, 0)
		sl.add_child(beam)
		anims.append(func(_dt):
			pivot.look_at(Vector3(sin(t * 0.5 + i * 1.7) * 4.0, 0, cos(t * 0.37 + i) * 4.0)))


func _build_rooftop() -> void:
	setup_env(Color(0.04, 0.05, 0.08), Color(0.12, 0.14, 0.2), Color(0.03, 0.03, 0.04), Color(0.45, 0.5, 0.65), 0.5, Color(0.08, 0.09, 0.12), 0.03, 0.4)
	setup_sun(Color(0.7, 0.78, 1.0), 0.75, -60, -20, [[Color(1.0, 0.25, 0.55), 120, 0.5], [Color(0.3, 0.6, 1.0), -120, 0.4]])
	floor_plane(1, Color(1.0, 0.3, 0.6))
	var concrete := mat(Color(0.2, 0.21, 0.23), 0.9)
	# parapet walls around a square roof
	for i in 4:
		var a := i * PI / 2
		add(box(22, 0.9, 0.5), concrete, Vector3(sin(a) * 11, 0.45, cos(a) * 11), Vector3(0, a, 0))
	# water tower
	var wood := mat(Color(0.35, 0.24, 0.16), 0.85)
	var tower := Vector3(-8.5, 0, -8.5)
	for lx in [-0.9, 0.9]:
		for lz in [-0.9, 0.9]:
			add(cyl(0.08, 0.08, 4), mat(Color(0.15, 0.15, 0.17), 0.6, 0.6), tower + Vector3(lx, 2, lz))
	add(cyl(1.4, 1.4, 2.6, 24), wood, tower + Vector3(0, 5.3, 0))
	var roof := CylinderMesh.new(); roof.top_radius = 0.05; roof.bottom_radius = 1.55; roof.height = 1.0
	add(roof, mat(Color(0.18, 0.18, 0.2), 0.7), tower + Vector3(0, 7.1, 0))
	# AC units with spinning fans
	for p in [Vector3(8.5, 0, -7), Vector3(-9, 0, 6.5), Vector3(7.5, 0, 8.5)]:
		add(box(1.8, 1.2, 1.4), mat(Color(0.55, 0.57, 0.6), 0.5, 0.4), p + Vector3(0, 0.6, 0))
		var fan := add(box(1.0, 0.04, 0.12), mat(Color(0.1, 0.1, 0.1), 0.5), p + Vector3(0, 1.24, 0))
		anims.append(func(dt): fan.rotation.y += dt * 9.0)
	# neon sign on a frame
	logo_sprite(MARK, Vector3(-4.6, 2.7, -13.5), 0.0, 1.9, 1.8)
	var sign := Label3D.new()
	sign.text = "BIT & BYTES"; sign.font_size = 150; sign.outline_size = 0
	sign.modulate = Color(0.7, 0.45, 1.0) * 2.0
	sign.position = Vector3(0, 2.6, -13.5); sign.shaded = false
	add_child(sign)
	add(box(7, 0.15, 0.15), mat(Color(0.12, 0.12, 0.14), 0.5, 0.7), Vector3(0, 1.9, -13.6))
	anims.append(func(_dt): sign.modulate = Color(0.7, 0.45, 1.0) * (2.0 if fmod(t, 7.0) > 0.25 or fmod(t * 13.0, 1.0) > 0.5 else 0.6))
	skyline(80, 20, 45, 4, 26, Color(0.05, 0.06, 0.1), 0.3)
	# rain: thin streaks falling fast
	var streak := QuadMesh.new(); streak.size = Vector2(0.015, 0.5)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.7, 0.8, 1.0, 0.35)
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	particles(1400, streak, rm, Vector3(14, 1, 14), Vector3(0, 12, 0), Vector3(0.6, -16, 0), 2.0, 0.85)
	# lightning: brief flashes of sky and sun
	anims.append(func(dt):
		next_flash -= dt
		if next_flash <= 0.0:
			flash = 1.0
			next_flash = randf_range(4.0, 9.0)
		flash = maxf(0.0, flash - dt * 4.0)
		var f := flash * (0.6 + 0.4 * sin(t * 60.0))
		sun.light_energy = sun_energy + f * 3.0
		env.ambient_light_energy = ambient_energy + f * 1.5)


func _build_dojo() -> void:
	setup_env(Color(0.25, 0.3, 0.6), Color(1.0, 0.55, 0.35), Color(0.2, 0.12, 0.1), Color(1.0, 0.75, 0.6), 0.55, Color(0.9, 0.55, 0.4), 0.01, 0.35)
	setup_sun(Color(1.0, 0.72, 0.45), 0.95, -18, 60, [[Color(1.0, 0.45, 0.6), -120, 0.35], [Color(0.5, 0.6, 1.0), 170, 0.25]])
	floor_plane(2, Color(0.75, 0.12, 0.1))
	var wood := mat(Color(0.32, 0.16, 0.09), 0.8)
	var plaster := mat(Color(0.78, 0.72, 0.64), 0.9)
	# low courtyard walls with roof caps
	for i in 4:
		var a := i * PI / 2 + PI / 4
		var c := Vector3(sin(a) * 13, 0, cos(a) * 13)
		add(box(13, 1.6, 0.4), plaster, c + Vector3(0, 0.8, 0), Vector3(0, a, 0))
		add(box(13.6, 0.25, 1.0), mat(Color(0.2, 0.22, 0.26), 0.6), c + Vector3(0, 1.75, 0), Vector3(0, a, 0))
	# gate: two posts and two crossbeams
	var gate := Vector3(0, 0, -11)
	var red := mat(Color(0.75, 0.15, 0.1), 0.6)
	for x in [-2.6, 2.6]:
		add(cyl(0.28, 0.32, 6), red, gate + Vector3(x, 3, 0))
	add(box(7.4, 0.4, 0.5), red, gate + Vector3(0, 5.4, 0))
	add(box(8.6, 0.35, 0.7), mat(Color(0.12, 0.1, 0.1), 0.6), gate + Vector3(0, 6.0, 0))
	add(box(6.0, 0.25, 0.35), red, gate + Vector3(0, 4.6, 0))
	# cherry trees
	var blossom := mat(Color(1.0, 0.72, 0.82), 0.9, 0.0, Color(1.0, 0.6, 0.75), 0.15)
	for p in [Vector3(-10, 0, -6), Vector3(10, 0, -5), Vector3(-9.5, 0, 7.5), Vector3(9.5, 0, 8)]:
		add(cyl(0.18, 0.3, 3.2), wood, p + Vector3(0, 1.6, 0), Vector3(0, 0, randf_range(-0.15, 0.15)))
		for k in 7:
			add(sph(randf_range(0.9, 1.4)), blossom, p + Vector3(randf_range(-1.4, 1.4), randf_range(3.2, 4.4), randf_range(-1.4, 1.4)))
	# stone lanterns glowing warm
	for p in [Vector3(-7, 0, -9.5), Vector3(7, 0, -9.5), Vector3(-10.5, 0, 0), Vector3(10.5, 0, 0)]:
		add(cyl(0.25, 0.35, 1.2), mat(Color(0.5, 0.5, 0.48), 0.9), p + Vector3(0, 0.6, 0))
		add(box(0.8, 0.12, 0.8), mat(Color(0.45, 0.45, 0.43), 0.9), p + Vector3(0, 1.75, 0))
		lantern(p + Vector3(0, 1.45, 0), Color(1.0, 0.7, 0.35))
	# distant mountains
	for i in 9:
		var a := -PI * 0.6 + i * 0.16 * PI
		var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = randf_range(8, 14); cone.height = randf_range(8, 15); cone.radial_segments = 6
		add(cone, mat(Color(0.35, 0.3, 0.45), 1.0), Vector3(sin(a) * 50, cone.height / 2 - 1, cos(a) * 50), Vector3.ZERO, Vector3.ONE, false)
	# falling petals
	var petal := QuadMesh.new(); petal.size = Vector2(0.07, 0.05)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(1.0, 0.75, 0.85)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	particles(260, petal, pm, Vector3(12, 1, 12), Vector3(0, 6, 0), Vector3(0.6, -0.5, 0.2), 30.0, 9.0, 3.0, Vector3(0.15, -0.25, 0.05))


func _build_harbor() -> void:
	setup_env(Color(0.02, 0.03, 0.07), Color(0.08, 0.12, 0.2), Color(0.01, 0.02, 0.04), Color(0.45, 0.55, 0.75), 0.5, Color(0.05, 0.08, 0.13), 0.022, 0.5)
	setup_sun(Color(0.7, 0.8, 1.0), 0.8, -35, -150, [[Color(1.0, 0.65, 0.3), 40, 0.5], [Color(0.4, 0.6, 1.0), -60, 0.35]])
	floor_plane(4, Color(0.95, 0.75, 0.1))
	# pier deck beyond the ring + water all around
	add(box(26, 0.6, 26), mat(Color(0.18, 0.2, 0.22), 0.7, 0.4), Vector3(0, -0.31, 0), Vector3.ZERO, Vector3.ONE, false)
	var wm := ShaderMaterial.new(); wm.shader = preload("res://shaders/water.gdshader")
	var wp := PlaneMesh.new(); wp.size = Vector2(160, 160); wp.subdivide_width = 80; wp.subdivide_depth = 80
	add(wp, wm, Vector3(0, -0.9, 0), Vector3.ZERO, Vector3.ONE, false)
	# container stacks
	var cols := [Color(0.75, 0.2, 0.15), Color(0.15, 0.35, 0.6), Color(0.85, 0.6, 0.15), Color(0.2, 0.5, 0.35), Color(0.55, 0.55, 0.58)]
	for s in [[Vector3(-11, 0, -7), 0.2], [Vector3(11, 0, -8), -0.3], [Vector3(-10.5, 0, 8), 1.4], [Vector3(10, 0, 9), 1.7]]:
		var base: Vector3 = s[0]
		for lvl in randi_range(2, 3):
			for k in 2:
				var c: Color = cols.pick_random()
				var cm := mat(c, 0.6, 0.35)
				add(box(6.0, 2.5, 2.4), cm, base + Vector3(0, 1.25 + lvl * 2.5, k * 2.5 - 1.25).rotated(Vector3.UP, s[1]), Vector3(0, s[1], 0))
	# gantry crane with a sweeping arm
	var steel := mat(Color(0.9, 0.55, 0.15), 0.5, 0.6)
	var crane := Vector3(0, 0, -16)
	for x in [-4.0, 4.0]:
		add(box(0.6, 18, 0.6), steel, crane + Vector3(x, 9, 0))
	add(box(9, 0.8, 0.8), steel, crane + Vector3(0, 17.5, 0))
	var arm := Node3D.new(); arm.position = crane + Vector3(0, 18, 0); add_child(arm)
	var arm_mesh := MeshInstance3D.new(); arm_mesh.mesh = box(24, 0.7, 0.9); arm_mesh.material_override = steel; arm_mesh.position = Vector3(6, 0, 0)
	arm.add_child(arm_mesh)
	var beacon := MeshInstance3D.new(); beacon.mesh = sph(0.25); beacon.material_override = glow(Color(1, 0.2, 0.15), 3.0); beacon.position = Vector3(18, 0.5, 0)
	arm.add_child(beacon)
	anims.append(func(_dt):
		arm.rotation.y = sin(t * 0.08) * 0.6
		beacon.visible = fmod(t, 1.4) < 0.7)
	# lamp posts
	for p in [Vector3(-12, 0, 0), Vector3(12, 0, 0), Vector3(0, 0, 12.5)]:
		add(cyl(0.08, 0.1, 5), mat(Color(0.12, 0.12, 0.14), 0.5, 0.7), p + Vector3(0, 2.5, 0))
		lantern(p + Vector3(0, 5.1, 0), Color(1.0, 0.72, 0.4), 2.2, 9.0)
	# mooring bollards
	for i in 10:
		var a := i * TAU / 10.0
		add(cyl(0.22, 0.28, 0.6), mat(Color(0.12, 0.12, 0.13), 0.5, 0.6), Vector3(sin(a) * 12.4, 0.3, cos(a) * 12.4))
	skyline(40, 55, 75, 5, 22, Color(0.05, 0.06, 0.1), 0.25)
	# a big moon
	add(sph(4.0), glow(Color(0.9, 0.93, 1.0), 1.6), Vector3(-30, 32, -70), Vector3.ZERO, Vector3.ONE, false)


func _build_ruins() -> void:
	setup_env(Color(0.22, 0.45, 0.8), Color(0.85, 0.72, 0.55), Color(0.5, 0.4, 0.28), Color(0.95, 0.85, 0.72), 0.38, Color(0.85, 0.72, 0.55), 0.004, 0.2)
	setup_sun(Color(1.0, 0.93, 0.8), 0.9, -62, 25, [[Color(1.0, 0.7, 0.4), -140, 0.3], [Color(0.6, 0.75, 1.0), 140, 0.2]])
	floor_plane(3, Color(0.45, 0.3, 0.18))
	var stone := mat(Color(0.66, 0.56, 0.44), 0.95)
	var dark_stone := mat(Color(0.5, 0.42, 0.33), 0.95)
	# ring of columns, some broken
	for i in 12:
		var a := i * TAU / 12.0
		var p := Vector3(sin(a) * 11, 0, cos(a) * 11)
		var h: float = [6.5, 4.0, 6.5, 2.2, 6.5, 5.0][i % 6] + randf_range(-0.3, 0.3)
		add(cyl(0.55, 0.65, h, 12), stone, p + Vector3(0, h / 2, 0))
		add(box(1.6, 0.4, 1.6), dark_stone, p + Vector3(0, 0.2, 0))
		if h > 6.0:
			add(box(1.5, 0.4, 1.5), dark_stone, p + Vector3(0, h + 0.2, 0))
	# fallen column drums
	for p in [Vector3(-8.5, 0.5, 4), Vector3(7.8, 0.5, -5.5), Vector3(4, 0.5, 9.3)]:
		add(cyl(0.6, 0.6, 2.2, 12), stone, p, Vector3(PI / 2, randf() * PI, 0))
	# an arch
	var arch := Vector3(0, 0, -14)
	for x in [-3.0, 3.0]:
		add(box(1.4, 7, 1.4), stone, arch + Vector3(x, 3.5, 0))
	add(box(7.4, 1.4, 1.6), stone, arch + Vector3(0, 7.6, 0))
	# dunes on the horizon
	for i in 14:
		var a := randf() * TAU
		var r := randf_range(30, 55)
		add(sph(randf_range(8, 16)), mat(Color(0.72, 0.56, 0.36), 1.0), Vector3(sin(a) * r, -4, cos(a) * r), Vector3.ZERO, Vector3(1.6, 0.45, 1.0), false)
	# drifting dust
	var mote := QuadMesh.new(); mote.size = Vector2(0.05, 0.05)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(1.0, 0.9, 0.7, 0.5)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particles(300, mote, dm, Vector3(13, 2, 13), Vector3(0, 1.5, 0), Vector3(1.2, 0.05, 0.3), 25.0, 8.0)


# ---------------------------------------------------------------- BNB office stages
const BV := Color(0.58, 0.3, 0.85)     # Bit & Bytes purple
const BGOLD := Color(0.13, 0.78, 0.92)  # Bit & Bytes cyan (the brand's second color)
const MARK := preload("res://assets/brand/bnb_mark_trim.png")
const WORDMARK := preload("res://assets/brand/bnb_wordmark_light.png")


## A desk with a monitor (screen glows in the given color), chair and a little clutter.
func desk(pos: Vector3, yaw: float, screen: Color) -> void:
	var rot := Basis(Vector3.UP, yaw)
	var top := mat(Color(0.82, 0.8, 0.76), 0.6)
	var leg := mat(Color(0.18, 0.18, 0.2), 0.5, 0.6)
	add(box(1.6, 0.05, 0.8), top, pos + rot * Vector3(0, 0.74, 0), Vector3(0, yaw, 0))
	for lx in [-0.74, 0.74]:
		add(box(0.05, 0.72, 0.7), leg, pos + rot * Vector3(lx, 0.36, 0), Vector3(0, yaw, 0))
	add(box(0.62, 0.38, 0.03), mat(Color(0.06, 0.06, 0.08), 0.4), pos + rot * Vector3(0, 1.08, -0.22), Vector3(0, yaw, 0))
	add(box(0.56, 0.32, 0.01), glow(screen, 1.2), pos + rot * Vector3(0, 1.08, -0.2), Vector3(0, yaw, 0), Vector3.ONE, false)
	add(box(0.06, 0.18, 0.06), leg, pos + rot * Vector3(0, 0.85, -0.22), Vector3(0, yaw, 0))
	add(box(0.4, 0.02, 0.14), mat(Color(0.15, 0.15, 0.17), 0.5), pos + rot * Vector3(0, 0.78, 0.12), Vector3(0, yaw, 0))
	add(cyl(0.045, 0.04, 0.1, 10), mat(BV if int(pos.x * 7) % 2 == 0 else Color(0.9, 0.9, 0.92), 0.5), pos + rot * Vector3(0.55, 0.82, 0.1))
	# office chair
	var seat := pos + rot * Vector3(0, 0, 0.75)
	add(box(0.5, 0.08, 0.5), mat(Color(0.12, 0.12, 0.15), 0.8), seat + Vector3(0, 0.48, 0), Vector3(0, yaw, 0))
	add(box(0.5, 0.55, 0.07), mat(Color(0.12, 0.12, 0.15), 0.8), seat + rot * Vector3(0, 0.8, 0.24), Vector3(0, yaw, 0))
	add(cyl(0.03, 0.03, 0.42, 8), leg, seat + Vector3(0, 0.24, 0))
	add(cyl(0.28, 0.28, 0.04, 10), leg, seat + Vector3(0, 0.03, 0))


func plant(pos: Vector3, h := 1.2) -> void:
	add(cyl(0.22, 0.17, 0.42, 12), mat(Color(0.9, 0.9, 0.88), 0.6), pos + Vector3(0, 0.21, 0))
	var leaf := mat(Color(0.2, 0.5, 0.28), 0.8)
	for k in 5:
		var a := k * TAU / 5.0
		add(sph(0.22), leaf, pos + Vector3(sin(a) * 0.14, 0.5 + h * 0.5 + (k % 2) * 0.15, cos(a) * 0.14), Vector3.ZERO, Vector3(1, 1.6, 1))


func ceiling_lights(y: float, half: float, step: float, c := Color(1, 0.98, 0.94)) -> void:
	var lm := glow(c, 1.6)
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			if Vector2(x, z).length() > 3.0:
				add(box(1.2, 0.04, 0.6), lm, Vector3(x, y, z), Vector3.ZERO, Vector3.ONE, false)
			z += step
		x += step


## The company logo as a glowing wall sign; height in meters.
func logo_sprite(tex: Texture2D, pos: Vector3, yaw: float, height: float, glow_k := 1.6) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.pixel_size = height / tex.get_height()
	sp.shaded = false
	sp.modulate = Color(glow_k, glow_k, glow_k)
	sp.position = pos; sp.rotation = Vector3(0, yaw, 0)
	add_child(sp)
	return sp


func logo_sign(text: String, pos: Vector3, yaw: float, c: Color, size := 140) -> Label3D:
	var l := Label3D.new()
	l.text = text; l.font_size = size; l.outline_size = 0; l.shaded = false
	l.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	l.modulate = c * 2.0
	l.position = pos; l.rotation = Vector3(0, yaw, 0)
	add_child(l)
	return l


func _build_open_office() -> void:
	setup_env(Color(0.05, 0.03, 0.1), Color(0.2, 0.12, 0.3), Color(0.03, 0.02, 0.05), Color(0.62, 0.58, 0.75), 0.6, Color(0.08, 0.05, 0.12), 0.01)
	setup_sun(Color(1, 0.96, 0.92), 0.95, -58, 25, [[BV, -130, 0.5], [BGOLD, 130, 0.3]])
	floor_plane(2, BV)
	# carpet ring around the fighting area
	add(cyl(9.6, 9.9, 0.06, 64), mat(Color(0.16, 0.13, 0.22), 0.95), Vector3(0, -0.02, 0), Vector3.ZERO, Vector3.ONE, false)
	# desk clusters all around (the open floor)
	var screens := [BV, Color(0.3, 0.75, 1.0), Color(0.35, 0.9, 0.55), BGOLD]
	for i in 10:
		var a := i * TAU / 10.0 + 0.2
		for row in 2:
			var r := 11.0 + row * 2.6
			desk(Vector3(sin(a) * r, 0, cos(a) * r), a + PI, screens[(i + row) % 4])
	for i in 8:
		var a := i * TAU / 8.0
		plant(Vector3(sin(a) * 9.4, 0, cos(a) * 9.4))
	# glass walls with the city behind
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.5, 0.45, 0.7, 0.12); glass.metallic = 0.6; glass.roughness = 0.1
	for i in 12:
		var a := i * TAU / 12.0
		add(box(9.4, 5.5, 0.05), glass, Vector3(sin(a) * 18, 2.75, cos(a) * 18), Vector3(0, a, 0), Vector3.ONE, false)
		add(box(0.12, 5.5, 0.12), mat(Color(0.2, 0.2, 0.24), 0.4, 0.7), Vector3(sin(a + 0.26) * 18.1, 2.75, cos(a + 0.26) * 18.1))
	ceiling_lights(5.6, 16.0, 3.2)
	skyline(60, 26, 44, 8, 30, Color(0.05, 0.04, 0.09), 0.33)
	logo_sprite(MARK, Vector3(-4.2, 4.0, -17.8), 0.0, 2.6)
	var sign := logo_sprite(WORDMARK, Vector3(1.6, 4.0, -17.8), 0.0, 1.5)
	anims.append(func(_dt): var k := 1.4 + 0.2 * sin(t * 2.0); sign.modulate = Color(k, k, k))
	logo_sprite(MARK, Vector3(0, 4.0, 17.8), PI, 3.0)


func _build_server_room() -> void:
	setup_env(Color(0.01, 0.02, 0.05), Color(0.03, 0.06, 0.12), Color(0.01, 0.02, 0.03), Color(0.45, 0.6, 0.85), 0.5, Color(0.03, 0.06, 0.1), 0.035, 0.6)
	setup_sun(Color(0.75, 0.88, 1.0), 0.8, -62, -15, [[Color(0.25, 0.75, 1.0), -120, 0.55], [BV, 120, 0.45]])
	floor_plane(0, Color(0.25, 0.75, 1.0))
	var rack := mat(Color(0.07, 0.08, 0.1), 0.4, 0.6)
	var led_cols := [Color(0.2, 1.0, 0.45), Color(0.25, 0.75, 1.0), Color(1.0, 0.65, 0.2), BV]
	var blinkers: Array = []
	# two aisles of racks on each side + a back row
	for side in [-1, 1]:
		for k in 8:
			for row in 2:
				var p := Vector3(side * (9.0 + row * 3.2), 0, -10.5 + k * 3.0)
				add(box(1.0, 2.6, 1.6), rack, p + Vector3(0, 1.3, 0))
				for u in 6:
					var lm := glow(led_cols[(k + u + row) % 4], 2.4)
					var led := add(box(0.04, 0.03, 0.9), lm, p + Vector3(-side * 0.51, 0.45 + u * 0.36, 0), Vector3.ZERO, Vector3.ONE, false)
					blinkers.append([led, randf() * TAU, randf_range(1.0, 5.0)])
	for k in 7:
		add(box(1.6, 2.6, 1.0), rack, Vector3(-9 + k * 3.0, 1.3, -14))
	# cable trays overhead
	for side in [-1, 1]:
		add(box(0.6, 0.08, 24), mat(Color(0.25, 0.26, 0.3), 0.5, 0.7), Vector3(side * 10.6, 3.2, 0))
	anims.append(func(_dt):
		for b in blinkers:
			b[0].visible = sin(t * b[2] + b[1]) > -0.3)
	# cold air haze
	var dust := sph(0.02)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.6, 0.85, 1.0, 0.25)
	particles(260, dust, dm, Vector3(18, 3, 18), Vector3(0, 1.6, 0), Vector3(0, 0.15, 0.2), 1.0, 8.0)
	logo_sprite(MARK, Vector3(-3.4, 3.7, -14.6), 0.0, 1.6)
	logo_sign("DATA CENTER", Vector3(1.4, 3.7, -14.6), 0.0, Color(0.25, 0.75, 1.0), 110)


func _build_boardroom() -> void:
	setup_env(Color(0.25, 0.18, 0.3), Color(1.0, 0.6, 0.35), Color(0.08, 0.05, 0.05), Color(0.85, 0.72, 0.65), 0.6, Color(0.35, 0.22, 0.2), 0.008, 0.5)
	setup_sun(Color(1.0, 0.8, 0.6), 1.15, -18, 60, [[BGOLD, -120, 0.4], [BV, 120, 0.35]])
	floor_plane(2, BGOLD)
	var wood := mat(Color(0.32, 0.2, 0.13), 0.45)
	# the long table, pushed back so the fight happens in front of it
	add(box(9.0, 0.12, 2.4), wood, Vector3(0, 0.78, -9.5))
	for x in [-4.0, 4.0]:
		add(box(0.3, 0.76, 1.8), wood, Vector3(x, 0.38, -9.5))
	for k in 8:
		var x := -3.9 + k * 1.1
		for side in [-1, 1]:
			var cp := Vector3(x, 0, -9.5 + side * 1.6)
			add(box(0.55, 0.08, 0.55), mat(Color(0.1, 0.1, 0.12), 0.7), cp + Vector3(0, 0.5, 0))
			add(box(0.55, 0.75, 0.08), mat(Color(0.1, 0.1, 0.12), 0.7), cp + Vector3(0, 0.9, side * 0.26))
	# presentation screen with a rising chart
	add(box(6.0, 3.0, 0.1), mat(Color(0.05, 0.05, 0.07), 0.4), Vector3(0, 3.0, -14.5))
	add(box(5.6, 2.6, 0.02), glow(Color(0.12, 0.1, 0.2), 0.8), Vector3(0, 3.0, -14.43), Vector3.ZERO, Vector3.ONE, false)
	for k in 6:
		var hgt := 0.4 + k * 0.35
		add(box(0.55, hgt, 0.02), glow(BGOLD if k == 5 else BV, 1.6), Vector3(-2.2 + k * 0.85, 1.9 + hgt / 2, -14.4), Vector3.ZERO, Vector3.ONE, false)
	logo_sign("Q4 TARGETS", Vector3(0, 4.15, -14.38), 0.0, Color(1, 1, 1), 70)
	# floor-to-ceiling windows on the sunset side
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(1.0, 0.7, 0.45, 0.08); glass.roughness = 0.05
	for k in 6:
		add(box(0.1, 6, 0.1), mat(Color(0.15, 0.14, 0.15), 0.4, 0.7), Vector3(15, 3, -12 + k * 4.8))
	add(box(0.05, 6, 24), glass, Vector3(15, 3, 0), Vector3.ZERO, Vector3.ONE, false)
	# walls
	var wall := mat(Color(0.55, 0.5, 0.48), 0.9)
	add(box(30, 6, 0.3), wall, Vector3(0, 3, -15))
	add(box(0.3, 6, 30), wall, Vector3(-15, 3, 0))
	add(box(30, 6, 0.3), wall, Vector3(0, 3, 15))
	for z in [-6.0, 6.0]:
		plant(Vector3(-13.5, 0, z), 1.6)
	skyline(50, 24, 42, 6, 26, Color(0.3, 0.18, 0.18), 0.1)
	ceiling_lights(6.0, 12.0, 4.0, Color(1, 0.92, 0.82))
	logo_sprite(WORDMARK, Vector3(-14.8, 4.4, 0), PI / 2, 1.6, 1.2)


func _build_cafeteria() -> void:
	setup_env(Color(0.3, 0.42, 0.6), Color(0.9, 0.8, 0.7), Color(0.2, 0.15, 0.1), Color(0.9, 0.82, 0.72), 0.7, Color(0.6, 0.5, 0.4), 0.006, 0.4)
	setup_sun(Color(1.0, 0.93, 0.82), 1.2, -50, 140, [[Color(1.0, 0.55, 0.4), -120, 0.35], [BV, 120, 0.3]])
	floor_plane(2, Color(1.0, 0.55, 0.4))
	# round tables with stools
	var tabletop := mat(Color(0.92, 0.88, 0.8), 0.5)
	var metal := mat(Color(0.3, 0.3, 0.32), 0.4, 0.7)
	for i in 9:
		var a := i * TAU / 9.0 + 0.3
		var p := Vector3(sin(a) * 11.5, 0, cos(a) * 11.5)
		add(cyl(0.7, 0.7, 0.05, 20), tabletop, p + Vector3(0, 0.75, 0))
		add(cyl(0.05, 0.05, 0.72, 8), metal, p + Vector3(0, 0.37, 0))
		for k in 3:
			var b := a + k * TAU / 3.0
			add(cyl(0.2, 0.2, 0.06, 12), mat([BV, Color(1.0, 0.55, 0.4), BGOLD][k], 0.6), p + Vector3(sin(b) * 1.05, 0.48, cos(b) * 1.05))
			add(cyl(0.03, 0.03, 0.46, 6), metal, p + Vector3(sin(b) * 1.05, 0.23, cos(b) * 1.05))
		add(cyl(0.05, 0.045, 0.1, 10), mat(Color(0.95, 0.95, 0.95), 0.5), p + Vector3(0.2, 0.83, 0.1))
	# coffee / chai counter
	add(box(8, 1.05, 1.0), mat(Color(0.35, 0.22, 0.15), 0.5), Vector3(0, 0.52, -14))
	add(box(8.2, 0.08, 1.2), tabletop, Vector3(0, 1.08, -14))
	add(box(0.9, 0.9, 0.6), mat(Color(0.15, 0.15, 0.16), 0.3, 0.8), Vector3(-2.5, 1.55, -14.1))
	add(box(0.5, 0.35, 0.02), glow(Color(1.0, 0.55, 0.4), 1.4), Vector3(-2.5, 1.6, -13.78), Vector3.ZERO, Vector3.ONE, false)
	var steam := sph(0.06)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(1, 1, 1, 0.25)
	particles(30, steam, sm, Vector3(0.2, 0.1, 0.2), Vector3(-2.5, 2.1, -14.1), Vector3(0, 0.5, 0), 0.4, 2.0)
	logo_sign("CHAI & CODE", Vector3(0, 3.0, -14.8), 0.0, Color(1.0, 0.55, 0.4), 120)
	# bean bags and plants in the lounge corner
	for i in 4:
		add(sph(0.55), mat([BV, BGOLD, Color(0.3, 0.75, 1.0), Color(1.0, 0.55, 0.4)][i], 0.9), Vector3(10 + (i % 2) * 1.4, 0.35, 8 + (i / 2) * 1.5), Vector3.ZERO, Vector3(1.1, 0.65, 1.1))
	for i in 6:
		var a := i * TAU / 6.0 + 0.5
		plant(Vector3(sin(a) * 14.5, 0, cos(a) * 14.5), 1.8)
	var wall := mat(Color(0.86, 0.8, 0.7), 0.9)
	for i in 4:
		var a := i * PI / 2
		add(box(32, 5, 0.3), wall, Vector3(sin(a) * 16, 2.5, cos(a) * 16), Vector3(0, a, 0))
	ceiling_lights(5.0, 13.0, 3.5, Color(1.0, 0.92, 0.8))
	logo_sprite(MARK, Vector3(15.8, 3.0, 0), -PI / 2, 2.4, 1.3)
