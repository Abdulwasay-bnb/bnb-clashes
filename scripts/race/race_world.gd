class_name RaceWorld
extends Node3D
## BNB Rush Hour visuals: draws a RaceSim (or a host's snapshots) — road, scenery, cars with their drivers,
## items, effects and the chase camera. Holds no race rules.

const BV := Color(0.58, 0.3, 0.85)
const CY := Color(0.13, 0.78, 0.92)

var sim: RaceSim
var cam: Camera3D
var follow := 0                   # racer the camera chases
var cars: Array = []              # per racer: {root, body, rig, wheels, flame}
var shot_nodes := {}              # Shot / snapshot entry -> node
var hazard_nodes := {}
var traffic_nodes: Array = []
var box_nodes: Array = []
var cone_nodes: Array = []
var cam_pos := Vector3.ZERO
var punch := 0.0                    # power used: the camera kicks back and widens
var cam_look := Vector3.ZERO
var env: Environment
var snow: CPUParticles3D
var crowd: Array = []


func build(s: RaceSim, people: Array, me: int) -> void:
	sim = s
	follow = me
	_environment(String(sim.track.theme))
	_road()
	_scenery(String(sim.track.theme))
	for k in sim.racers.size():
		cars.append(_car(sim.racers[k]))
	for t in sim.traffic: traffic_nodes.append(_traffic_car(t.color))
	for b in sim.boxes:
		var n := _box()
		n.position = b.pos
		box_nodes.append(n)
	for c in sim.cones:
		var n := _cone()
		n.position = c.pos
		cone_nodes.append(n)
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 900
	add_child(cam)
	cam.current = true
	var r: RaceSim.Racer = sim.racers[follow]
	cam_pos = r.pos + Vector3(0, 5, 0) - Vector3(sin(r.heading), 0, cos(r.heading)) * 10.0
	cam_look = r.pos


# ---------------------------------------------------------------- world
## Look of each theme: sky, light, fog, ground and verge colours, road tint.
const THEMES := {
	"city": {top = Color(0.04, 0.03, 0.12), hor = Color(0.38, 0.2, 0.45), amb = Color(0.55, 0.52, 0.75), amb_e = 0.55, sun = Color(0.75, 0.75, 1.0), sun_e = 0.45,
		sun_rot = Vector2(-40, 35), fog = 0.003, g_a = Color(0.13, 0.12, 0.15), g_b = Color(0.1, 0.1, 0.12), verge = Color(0.42, 0.42, 0.46), road_wet = 0.7},
	"park": {top = Color(0.18, 0.4, 0.82), hor = Color(0.62, 0.74, 0.88), amb = Color(0.7, 0.75, 0.85), amb_e = 0.45, sun = Color(1.0, 0.96, 0.88), sun_e = 1.0,
		sun_rot = Vector2(-50, 35), fog = 0.0012, hill = Color(0.25, 0.42, 0.3), g_a = Color(0.3, 0.52, 0.22), g_b = Color(0.22, 0.42, 0.17), verge = Color(0.68, 0.66, 0.62)},
	"rooftop": {top = Color(0.12, 0.08, 0.3), hor = Color(1.0, 0.55, 0.35), amb = Color(0.75, 0.6, 0.7), amb_e = 0.5, sun = Color(1.0, 0.72, 0.5), sun_e = 0.95,
		sun_rot = Vector2(-18, 60), fog = 0.0022, g_a = Color(0.22, 0.2, 0.25), g_b = Color(0.18, 0.16, 0.2), verge = Color(0.5, 0.48, 0.52)},
	"seaside": {top = Color(0.1, 0.38, 0.85), hor = Color(0.55, 0.75, 0.92), amb = Color(0.72, 0.78, 0.85), amb_e = 0.42, sun = Color(1.0, 0.95, 0.85), sun_e = 1.0,
		sun_rot = Vector2(-45, 20), fog = 0.0007, g_a = Color(0.84, 0.7, 0.46), g_b = Color(0.74, 0.6, 0.38), verge = Color(0.55, 0.55, 0.56), sparkle = 0.25,
		hill = Color(0.28, 0.48, 0.3)},
	"desert": {top = Color(0.2, 0.25, 0.55), hor = Color(1.0, 0.62, 0.38), amb = Color(0.9, 0.7, 0.6), amb_e = 0.5, sun = Color(1.0, 0.75, 0.5), sun_e = 1.05,
		sun_rot = Vector2(-22, -40), fog = 0.0025, g_a = Color(0.78, 0.5, 0.3), g_b = Color(0.66, 0.4, 0.24), verge = Color(0.72, 0.55, 0.38), dust = 0.7,
		dust_col = Color(0.78, 0.55, 0.35)},
	"snow": {top = Color(0.2, 0.38, 0.7), hor = Color(0.62, 0.7, 0.82), amb = Color(0.62, 0.68, 0.82), amb_e = 0.45, sun = Color(1.0, 0.92, 0.82), sun_e = 0.75,
		sun_rot = Vector2(-22, 30), fog = 0.0035, g_a = Color(0.78, 0.82, 0.9), g_b = Color(0.66, 0.72, 0.84), verge = Color(0.5, 0.52, 0.56), dust = 0.8,
		dust_col = Color(0.85, 0.88, 0.94), sparkle = 0.35, hill = Color(0.36, 0.42, 0.52)},
}


func _environment(theme: String) -> void:
	var T: Dictionary = THEMES.get(theme, THEMES.city)
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = T.top; sm.sky_horizon_color = T.hor
	sm.ground_bottom_color = T.hor.darkened(0.6); sm.ground_horizon_color = T.hor.darkened(0.2)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = T.amb
	env.ambient_light_energy = T.amb_e
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = 0.92
	env.glow_enabled = true; env.glow_intensity = 0.35; env.glow_hdr_threshold = 1.2
	env.fog_enabled = true; env.fog_density = T.fog; env.fog_light_color = T.hor.darkened(0.15)
	env.adjustment_enabled = true; env.adjustment_saturation = 1.15; env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = T.sun
	sun.light_energy = T.sun_e
	sun.rotation = Vector3(deg_to_rad(T.sun_rot.x), deg_to_rad(T.sun_rot.y), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70
	add_child(sun)
	if theme == "snow":   # falling snow that follows the camera
		snow = CPUParticles3D.new()
		snow.amount = 600; snow.lifetime = 6.0; snow.preprocess = 6.0
		snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; snow.emission_box_extents = Vector3(40, 1, 40)
		snow.direction = Vector3(0.2, -1, 0); snow.spread = 15; snow.gravity = Vector3(0, -1.5, 0)
		snow.initial_velocity_min = 3.0; snow.initial_velocity_max = 5.0
		var q := QuadMesh.new(); q.size = Vector2(0.12, 0.12)
		var qm := _mat(Color(1, 1, 1), 1.0, 0.0, 0.8); qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		q.material = qm
		snow.mesh = q
		add_child(snow)


func _ground_mat(a: Color, b: Color, scale := 0.08, sparkle := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/race_ground.gdshader")
	m.set_shader_parameter("col_a", a); m.set_shader_parameter("col_b", b)
	m.set_shader_parameter("scale", scale); m.set_shader_parameter("sparkle", sparkle)
	return m


## Many copies of one mesh in a single draw call (trees, crowd, rocks): xforms = Array of Transform3D, cols optional.
func _multi(mesh: Mesh, m: Material, xforms: Array, cols: Array = []) -> void:
	if xforms.is_empty(): return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		if mm.use_colors: mm.set_instance_color(k, cols[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if mm.use_colors:
		var sm := m as StandardMaterial3D
		if sm != null: sm.vertex_color_use_as_albedo = true
	mi.material_override = m
	add_child(mi)


func _mat(c: Color, rough := 0.8, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	return m


func _mesh(mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = m; mi.position = pos; mi.rotation = rot
	(parent if parent != null else self).add_child(mi)
	return mi


func _box_mesh(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z); return b


## The road: a strip along the centre line, with lane markings in its texture, kerbs and barriers.
func _road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerbs := SurfaceTool.new(); kerbs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verges := SurfaceTool.new(); verges.begin(Mesh.PRIMITIVE_TRIANGLES)
	var theme := String(sim.track.theme)
	var T: Dictionary = THEMES.get(theme, THEMES.city)
	var raised := theme != "rooftop"   # verges and banked sides down to the ground (the rooftop keeps its towers)
	var n := sim.P.size()
	var hw := sim.width / 2.0
	for i in n + 1:
		var a := i % n
		var b := (i + 1) % n
		var ra := sim._right(a); var rb := sim._right(b)
		var pa: Vector3 = sim.P[a] + Vector3(0, 0.02, 0); var pb: Vector3 = sim.P[b] + Vector3(0, 0.02, 0)
		var va := sim.S[a] / 6.0; var vb := (sim.S[a] + pa.distance_to(pb)) / 6.0
		_quad(st, pa - ra * hw, pa + ra * hw, pb + rb * hw, pb - rb * hw, Vector2(0, va), Vector2(1, va), Vector2(1, vb), Vector2(0, vb))
		# low barriers on both edges
		for side in [-1.0, 1.0]:
			var ea: Vector3 = pa + ra * side * (hw + 0.3); var eb: Vector3 = pb + rb * side * (hw + 0.3)
			_quad(walls, ea, eb, eb + Vector3(0, 1.1, 0), ea + Vector3(0, 1.1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
			# red / white rumble kerb just inside the barrier
			var ka: Vector3 = pa + ra * side * (hw - 0.6) + Vector3(0, 0.025, 0); var kb: Vector3 = pb + rb * side * (hw - 0.6) + Vector3(0, 0.025, 0)
			var kc: Vector3 = pb + rb * side * (hw + 0.3) + Vector3(0, 0.025, 0); var kd: Vector3 = pa + ra * side * (hw + 0.3) + Vector3(0, 0.025, 0)
			if side > 0: _quad(kerbs, ka, kd, kc, kb, Vector2(0, va), Vector2(1, va), Vector2(1, vb), Vector2(0, vb))
			else: _quad(kerbs, kd, ka, kb, kc, Vector2(0, va), Vector2(1, va), Vector2(1, vb), Vector2(0, vb))
			if raised:
				# verge (pavement / sand / snow) out from the barrier, then a banked side down to the ground
				var oa: Vector3 = pa + ra * side * (hw + 0.3); var ob: Vector3 = pb + rb * side * (hw + 0.3)
				var fa: Vector3 = pa + ra * side * (hw + 7.0) - Vector3(0, 0.02, 0); var fb: Vector3 = pb + rb * side * (hw + 7.0) - Vector3(0, 0.02, 0)
				var ga: Vector3 = fa + ra * side * maxf(0.0, fa.y + 0.1) * 1.6; ga.y = -0.1
				var gb: Vector3 = fb + rb * side * maxf(0.0, fb.y + 0.1) * 1.6; gb.y = -0.1
				if side > 0:
					_quad(verges, oa, fa, fb, ob, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
					_quad(verges, fa, ga, gb, fb, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				else:
					_quad(verges, fa, oa, ob, fb, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
					_quad(verges, ga, fa, fb, gb, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	st.generate_normals()
	var road_m := ShaderMaterial.new()
	road_m.shader = load("res://shaders/race_road.gdshader")
	road_m.set_shader_parameter("wet", float(T.get("road_wet", 0.0)))
	road_m.set_shader_parameter("dust", float(T.get("dust", 0.0)))
	road_m.set_shader_parameter("dust_col", T.get("dust_col", Color(0.8, 0.7, 0.5)))
	kerbs.generate_normals()
	var km := ShaderMaterial.new(); km.shader = load("res://shaders/race_kerb.gdshader")
	if theme == "city": km.set_shader_parameter("col_a", Color(0.55, 0.25, 0.85))   # BNB purple kerbs downtown
	var kmi := MeshInstance3D.new(); kmi.mesh = kerbs.commit(); kmi.material_override = km
	add_child(kmi)
	if raised:
		verges.generate_normals()
		var vm := _ground_mat(T.verge, T.verge.darkened(0.12), 0.3, float(T.get("sparkle", 0.0)))
		vm.set_shader_parameter("rough", 0.9)
		var vmi := MeshInstance3D.new(); vmi.mesh = verges.commit(); vmi.material_override = vm
		add_child(vmi)
	var road := MeshInstance3D.new(); road.mesh = st.commit(); road.material_override = road_m
	add_child(road)
	walls.generate_normals()
	var wm := _mat(Color(0.75, 0.75, 0.8), 0.6)
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var w := MeshInstance3D.new(); w.mesh = walls.commit(); w.material_override = wm
	add_child(w)
	# barrier stripes (purple / cyan) every few metres
	for i in range(0, n, 6):
		for side in [-1.0, 1.0]:
			var p: Vector3 = sim.P[i] + sim._right(i) * side * (hw + 0.32) + Vector3(0, 0.75, 0)
			_mesh(_box_mesh(0.08, 0.35, 1.2), _mat(BV if (i / 6) % 2 == 0 else CY, 0.5, 0.0, 0.8), p, Vector3(0, atan2(sim.T[i].x, sim.T[i].z), 0))
	# start / finish arch
	var s0: Vector3 = sim.P[0]
	var r0 := sim._right(0)
	for side in [-1.0, 1.0]:
		_mesh(_box_mesh(0.6, 7.0, 0.6), _mat(Color(0.12, 0.1, 0.16), 0.4, 0.6), s0 + r0 * side * (hw + 1.0) + Vector3(0, 3.5, 0))
	var beam := _mesh(_box_mesh(sim.width + 3.0, 1.4, 0.5), _mat(BV, 0.5, 0.0, 0.6), s0 + Vector3(0, 7.0, 0), Vector3(0, atan2(sim.T[0].x, sim.T[0].z) + PI / 2, 0))
	var l := Label3D.new()
	l.text = "BNB RUSH HOUR"; l.font_size = 160; l.outline_size = 0; l.modulate = Color(1.6, 1.6, 1.8)
	l.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	l.position = s0 + Vector3(0, 7.0, 0) - sim.T[0] * 0.3
	l.rotation = Vector3(0, atan2(sim.T[0].x, sim.T[0].z) + PI, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(l)
	var _unused := beam
	# chequered start line
	for k in 12:
		var p: Vector3 = s0 + r0 * (-hw + (k + 0.5) * sim.width / 12.0) + Vector3(0, 0.04, 0)
		_mesh(_box_mesh(sim.width / 12.0, 0.02, 1.2), _mat(Color.WHITE if k % 2 == 0 else Color(0.05, 0.05, 0.05)), p, Vector3(0, atan2(sim.T[0].x, sim.T[0].z), 0))
	# jumps: a ramp on the road
	for ri in sim.ramps:
		var p: Vector3 = sim.P[ri]
		var ramp := _mesh(_box_mesh(sim.width * 0.9, 0.15, 6.0), _mat(Color(1.0, 0.75, 0.2), 0.6, 0.0, 0.3), p + Vector3(0, 0.35, 0), Vector3(-0.12, atan2(sim.T[ri].x, sim.T[ri].z), 0))
		ramp.rotation_order = EULER_ORDER_YXZ


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(ub); st.add_vertex(b)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ud); st.add_vertex(d)


func _scenery(theme: String) -> void:
	var T: Dictionary = THEMES.get(theme, THEMES.city)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var n := sim.P.size()
	var hw := sim.width / 2.0
	var gy := -0.1 if theme != "rooftop" else -25.0
	# ground: a big plane with a noisy two-tone material
	var plane := PlaneMesh.new(); plane.size = Vector2(1200, 1200)
	_mesh(plane, _ground_mat(T.g_a, T.g_b, 0.05, float(T.get("sparkle", 0.0))), Vector3(30, gy, 80))
	var win := ShaderMaterial.new()
	win.shader = load("res://shaders/windows.gdshader")
	var mark: Texture2D = load("res://assets/brand/bnb_mark_trim.png")
	var center := Vector3(30, 0, 80)
	# keep scenery off the road: is a point near any part of the track?
	var clear := func(q: Vector3, gap: float) -> bool:
		for k in range(0, n, 3):
			if Vector2(sim.P[k].x - q.x, sim.P[k].z - q.z).length() < hw + gap: return false
		return true
	var yaw_at := func(i: int) -> float: return atan2(sim.T[i].x, sim.T[i].z)
	# distant hills / mountains / mesas / skyline round the whole map
	var far_m := _mat(T.get("hill", T.hor.darkened(0.45).lerp(T.g_b, 0.3)), 1.0)
	var far_x := []
	for k in 40:
		var a := TAU * k / 40.0 + rng.randf_range(-0.05, 0.05)
		var r := rng.randf_range(430.0, 520.0)
		var h := rng.randf_range(40.0, 120.0) * (1.6 if theme == "snow" else (0.7 if theme in ["seaside", "park"] else 1.0))
		var w := rng.randf_range(70.0, 130.0) * (1.5 if theme in ["seaside", "park"] else 1.0)
		var xf := Transform3D(Basis.from_scale(Vector3(w, h, w)), center + Vector3(cos(a) * r, gy + h * 0.5 - 2.0, sin(a) * r))
		far_x.append(xf)
	var far_mesh: Mesh
	if theme == "desert":
		far_mesh = CylinderMesh.new(); (far_mesh as CylinderMesh).top_radius = 0.38; (far_mesh as CylinderMesh).bottom_radius = 0.5; (far_mesh as CylinderMesh).height = 1.0
		(far_mesh as CylinderMesh).radial_segments = 8
	elif theme in ["seaside", "park"]:   # rolling hills: squashed domes
		far_mesh = SphereMesh.new(); (far_mesh as SphereMesh).radius = 0.5; (far_mesh as SphereMesh).height = 1.0; (far_mesh as SphereMesh).radial_segments = 16; (far_mesh as SphereMesh).rings = 8
	elif theme in ["city", "rooftop"]:
		far_mesh = _box_mesh(0.25, 1.0, 0.25)
	else:
		far_mesh = CylinderMesh.new(); (far_mesh as CylinderMesh).top_radius = 0.0; (far_mesh as CylinderMesh).bottom_radius = 0.5; (far_mesh as CylinderMesh).height = 1.0
	_multi(far_mesh, far_m if not theme in ["city", "rooftop"] else win, far_x)
	if theme == "snow":   # snow caps on the peaks
		var caps := []
		for xf in far_x:
			var t3: Transform3D = xf
			caps.append(Transform3D(t3.basis.scaled(Vector3(0.42, 0.3, 0.42)), t3.origin + Vector3(0, t3.basis.get_scale().y * 0.36, 0)))
		var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.5; cone.height = 1.0
		_multi(cone, _mat(Color(0.97, 0.98, 1.0), 0.7), caps)
	# per theme: things along the road (both sides, a bit back from the verge)
	var trees := []; var trunks := []; var rocks := []; var tall := []; var props := []
	for i in range(0, n, 4):
		for side in [-1.0, 1.0]:
			var p: Vector3 = sim.P[i]
			var out: Vector3 = sim._right(i) * side
			var ground_at := func(d: float) -> Vector3: var q: Vector3 = p + out * d; q.y = gy; return q
			match theme:
				"city":
					if i % 8 == 0:   # towers with lit windows, set back behind the pavement
						var h := rng.randf_range(16.0, 70.0)
						var d := hw + rng.randf_range(14.0, 30.0)
						var q: Vector3 = ground_at.call(d)
						if clear.call(q, 11.0):
							var b := _mesh(_box_mesh(rng.randf_range(9, 15), h, rng.randf_range(9, 15)), win, q + Vector3(0, h / 2.0, 0))
							b.rotation.y = yaw_at.call(i)
							if rng.randf() < 0.4:   # rooftop antenna or water tank
								_mesh(_box_mesh(0.3, rng.randf_range(4, 9), 0.3), _mat(Color(0.3, 0.3, 0.35), 0.4, 0.6), q + Vector3(0, h + 3.0, 0))
								_mesh(_box_mesh(0.5, 0.5, 0.5), _mat(Color(1, 0.2, 0.2), 0.3, 0.0, 4.0), q + Vector3(0, h + 7.5, 0))
					if i % 24 == 0:   # street lights with a real light every other one
						var lp: Vector3 = p + out * (hw + 1.4)
						_mesh(_box_mesh(0.2, 7.0, 0.2), _mat(Color(0.2, 0.2, 0.22), 0.4, 0.7), lp + Vector3(0, 3.5, 0))
						_mesh(_box_mesh(0.9, 0.2, 0.45), _mat(Color(1, 0.9, 0.7), 0.3, 0.0, 3.0), lp - out * 0.6 + Vector3(0, 7.0, 0))
						if i % 48 == 0 and side > 0:
							var ol := OmniLight3D.new(); ol.position = lp - out * 1.5 + Vector3(0, 6.0, 0); ol.omni_range = 16; ol.light_energy = 1.4
							ol.light_color = Color(1.0, 0.85, 0.65); add_child(ol)
					if i % 32 == 16:   # neon signs on poles
						var col: Color = [BV, CY, Color(1, 0.3, 0.6), Color(1, 0.75, 0.2)][(i / 32) % 4]
						var sp: Vector3 = p + out * (hw + 5.0)
						_mesh(_box_mesh(0.25, 5.0, 0.25), _mat(Color(0.15, 0.15, 0.18)), sp + Vector3(0, 2.5, 0))
						_mesh(_box_mesh(3.5, 1.2, 0.2), _mat(col, 0.3, 0.0, 2.2), sp + Vector3(0, 5.6, 0), Vector3(0, yaw_at.call(i) + PI / 2, 0))
					if rng.randf() < 0.12:   # parked cars on the pavement
						props.append([p + out * (hw + 3.5) + Vector3(0, 0.0, 0), yaw_at.call(i)])
				"park":
					var d := hw + rng.randf_range(8.0, 24.0)
					var q: Vector3 = ground_at.call(d)
					if rng.randf() < 0.8 and clear.call(q, 6.0):
						var s := rng.randf_range(0.8, 1.3)
						trunks.append(Transform3D(Basis.from_scale(Vector3(0.45, 2.4, 0.45) * s), q + Vector3(0, 1.2 * s, 0)))
						trees.append(Transform3D(Basis.from_scale(Vector3(3.2, 3.6, 3.2) * s), q + Vector3(0, 3.6 * s, 0)))
					if i % 20 == 0:
						var q2: Vector3 = ground_at.call(hw + rng.randf_range(26.0, 40.0))
						if clear.call(q2, 16.0):
							_mesh(_box_mesh(22, 9, 13), _mat(Color(0.88, 0.88, 0.9), 0.4), q2 + Vector3(0, 4.5, 0), Vector3(0, yaw_at.call(i), 0))
							_mesh(_box_mesh(22.2, 3.4, 13.2), _mat(Color(0.3, 0.55, 0.8), 0.1, 0.4), q2 + Vector3(0, 5.5, 0), Vector3(0, yaw_at.call(i), 0))
					if rng.randf() < 0.25: rocks.append(Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.6, 1.4)), ground_at.call(hw + rng.randf_range(7.5, 12.0))))
				"seaside":
					var d := hw + rng.randf_range(8.0, 20.0)
					var q: Vector3 = ground_at.call(d)
					if rng.randf() < 0.55 and clear.call(q, 5.0):   # palm trees: a leaning trunk and a fan of fronds
						var s := rng.randf_range(0.9, 1.3)
						var lean := Basis(Vector3(0, 0, 1), rng.randf_range(-0.15, 0.15))
						trunks.append(Transform3D(lean.scaled(Vector3(0.55, 7.0, 0.55) * s), q + Vector3(0, 3.5 * s, 0)))
						for f in 6:
							var fb := Basis(Vector3.UP, f * TAU / 6.0 + rng.randf()) * Basis(Vector3.RIGHT, -0.4)   # fronds droop outward
							trees.append(Transform3D(fb.scaled(Vector3(1.1, 0.12, 3.8) * s), q + lean * Vector3(0, 7.0 * s, 0) + fb * Vector3(0, 0, 1.7 * s)))
					if rng.randf() < 0.18 and side > 0:   # beach umbrellas and towels
						var u: Vector3 = ground_at.call(hw + rng.randf_range(9.0, 18.0))
						if clear.call(u, 5.0): props.append([u, rng.randf() * TAU])
				"desert":
					var d := hw + rng.randf_range(9.0, 30.0)
					var q: Vector3 = ground_at.call(d)
					if rng.randf() < 0.45 and clear.call(q, 6.0):   # cacti
						var s := rng.randf_range(0.8, 1.4)
						tall.append(Transform3D(Basis.from_scale(Vector3(0.7, 4.5, 0.7) * s), q + Vector3(0, 2.25 * s, 0)))
						for arm in [-1.0, 1.0]:
							if rng.randf() < 0.7:
								tall.append(Transform3D(Basis.from_scale(Vector3(0.45, 1.8, 0.45) * s), q + Vector3(arm * 0.9 * s, 3.0 * s, 0)))
								tall.append(Transform3D(Basis(Vector3(0, 0, 1), PI / 2).scaled(Vector3(0.4, 0.9, 0.4) * s), q + Vector3(arm * 0.5 * s, 2.2 * s, 0)))
					if rng.randf() < 0.5: rocks.append(Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf() * 3, 0)).scaled(Vector3.ONE * rng.randf_range(0.8, 3.0)), ground_at.call(hw + rng.randf_range(8.0, 30.0))))
					if i % 16 == 0:   # canyon walls / mesas closer in
						var m: Vector3 = ground_at.call(hw + rng.randf_range(40.0, 70.0))
						if clear.call(m, 30.0):
							var h := rng.randf_range(18.0, 45.0)
							var w := rng.randf_range(16.0, 30.0)
							var mc := CylinderMesh.new(); mc.top_radius = w * 0.4; mc.bottom_radius = w * 0.55; mc.height = h; mc.radial_segments = 7
							_mesh(mc, _ground_mat(Color(0.75, 0.4, 0.25), Color(0.6, 0.3, 0.2), 0.15), m + Vector3(0, h / 2.0, 0), Vector3(0, rng.randf() * 3, 0))
				"snow":
					var d := hw + rng.randf_range(8.0, 28.0)
					var q: Vector3 = ground_at.call(d)
					if rng.randf() < 0.85 and clear.call(q, 5.0):   # pines: dark cone with a snowy top
						var s := rng.randf_range(0.8, 1.6)
						trunks.append(Transform3D(Basis.from_scale(Vector3(0.35, 1.4, 0.35) * s), q + Vector3(0, 0.7 * s, 0)))
						trees.append(Transform3D(Basis.from_scale(Vector3(3.2, 6.5, 3.2) * s), q + Vector3(0, 4.4 * s, 0)))
						tall.append(Transform3D(Basis.from_scale(Vector3(1.4, 2.4, 1.4) * s), q + Vector3(0, 6.9 * s, 0)))
					if rng.randf() < 0.3: rocks.append(Transform3D(Basis.from_scale(Vector3(1.6, 0.7, 1.4) * rng.randf_range(0.8, 2.0)), ground_at.call(hw + rng.randf_range(7.5, 14.0))))
				_:        # rooftop: the road runs over buildings, the city far below
					var d := hw + rng.randf_range(2.0, 10.0)
					if i % 8 == 0:
						_mesh(_box_mesh(rng.randf_range(2, 4), rng.randf_range(1, 3), rng.randf_range(2, 4)), _mat(Color(0.55, 0.57, 0.6), 0.5, 0.4), p + out * d + Vector3(0, 0.8, 0))
						var h := rng.randf_range(10.0, 40.0)
						var tw := _mesh(_box_mesh(14, h, 14), win, p + out * (hw + rng.randf_range(40.0, 80.0)) + Vector3(0, h / 2.0 - 25.0, 0))
						tw.rotation.y = rng.randf() * PI
					if i % 20 == 0:   # aviation lights on the edge
						_mesh(_box_mesh(0.3, 0.3, 0.3), _mat(Color(1, 0.2, 0.15), 0.3, 0.0, 4.0), p + out * (hw + 1.0) + Vector3(0, 1.4, 0))
			if i % 44 == 0 and side > 0:   # Bit & Bytes billboards on posts
				var bp: Vector3 = p + out * (hw + 5.0)
				_mesh(_box_mesh(0.3, 6.0, 0.3), _mat(Color(0.2, 0.2, 0.22), 0.5, 0.5), bp + Vector3(0, 3.0, 0))
				_mesh(_box_mesh(7.4, 4.4, 0.25), _mat(Color(0.08, 0.06, 0.12), 0.5), bp + Vector3(0, 7.6, 0), Vector3(0, yaw_at.call(i) + PI / 2, 0))
				var sp := Sprite3D.new()
				sp.texture = mark; sp.pixel_size = 3.6 / mark.get_height(); sp.shaded = false
				sp.modulate = Color(1.4, 1.4, 1.4)
				sp.position = bp + Vector3(0, 7.6, 0) - out * 0.15
				sp.rotation.y = yaw_at.call(i) + PI / 2 + (PI if side < 0 else 0.0)
				add_child(sp)
	# batched vegetation and rocks
	var leaf_c: Color = {"park": Color(0.22, 0.48, 0.22), "seaside": Color(0.25, 0.55, 0.2), "snow": Color(0.12, 0.3, 0.2)}.get(theme, Color(0.3, 0.5, 0.25))
	var trunk_m := _mat(Color(0.4, 0.27, 0.15) if theme != "seaside" else Color(0.6, 0.48, 0.32), 0.9)
	_multi(CylinderMesh.new(), trunk_m, trunks)
	if theme == "snow":
		var pine := CylinderMesh.new(); pine.top_radius = 0.0; pine.bottom_radius = 0.5; pine.height = 1.0; pine.radial_segments = 8
		_multi(pine, _mat(leaf_c, 0.9), trees)
		var cap := CylinderMesh.new(); cap.top_radius = 0.0; cap.bottom_radius = 0.5; cap.height = 1.0; cap.radial_segments = 8
		_multi(cap, _mat(Color(0.95, 0.97, 1.0), 0.8), tall)
	elif theme == "seaside":
		_multi(_box_mesh(1, 1, 1), _mat(leaf_c, 0.8), trees)
	elif theme == "desert":
		var cac := CapsuleMesh.new(); cac.radius = 0.5; cac.height = 1.0
		_multi(cac, _mat(Color(0.3, 0.55, 0.3), 0.8), tall)
	else:
		var crown := SphereMesh.new(); crown.radius = 0.5; crown.height = 1.0; crown.radial_segments = 10; crown.rings = 6
		var cols := []
		for k in trees.size(): cols.append(leaf_c.lerp(Color(0.4, 0.58, 0.2), rng.randf() * 0.6))
		_multi(crown, _mat(Color.WHITE, 0.85), trees, cols)
	var rock := SphereMesh.new(); rock.radius = 0.6; rock.height = 0.9; rock.radial_segments = 6; rock.rings = 3
	_multi(rock, _mat(Color(0.5, 0.48, 0.45) if theme != "desert" else Color(0.62, 0.38, 0.25), 1.0), rocks)
	# theme extras
	match theme:
		"city":
			for pr in props:   # parked cars
				var c := _traffic_car([Color(0.2, 0.2, 0.25), Color(0.8, 0.8, 0.82), Color(0.6, 0.12, 0.12), Color(0.15, 0.3, 0.6)][rng.randi() % 4])
				c.position = pr[0]; c.rotation.y = pr[1]
		"seaside":
			# the sea to the north with a sandy beach before it
			var sea := PlaneMesh.new(); sea.size = Vector2(1400, 700)
			var sm := _mat(Color(0.1, 0.45, 0.65), 0.08, 0.2); sm.albedo_color.a = 0.92; sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_mesh(sea, sm, Vector3(30, -0.4, 600))
			for pr in props:
				var u: Vector3 = pr[0]
				_mesh(_box_mesh(0.1, 2.6, 0.1), _mat(Color(0.9, 0.9, 0.9)), u + Vector3(0, 1.3, 0))
				var um := CylinderMesh.new(); um.top_radius = 0.05; um.bottom_radius = 1.6; um.height = 0.6
				_mesh(um, _mat([Color(1, 0.3, 0.3), Color(1, 0.85, 0.2), Color(0.2, 0.6, 1.0)][rng.randi() % 3], 0.6), u + Vector3(0, 2.7, 0))
				_mesh(_box_mesh(1.0, 0.04, 2.0), _mat([Color(0.3, 0.8, 0.9), Color(1, 0.6, 0.3)][rng.randi() % 2], 0.8), u + Vector3(1.5, 0.03, 0), Vector3(0, pr[1], 0))
		"desert":
			pass
	if theme == "rooftop":   # the support under the road
		for i in range(0, n, 12):
			_mesh(_box_mesh(sim.width + 2.0, 30.0, 8.0), win, sim.P[i] + Vector3(0, -15.2, 0), Vector3(0, atan2(sim.T[i].x, sim.T[i].z), 0))
	_grandstand(theme)


## Grandstand with a cheering crowd and flags beside the start line.
func _grandstand(theme: String) -> void:
	var i := 6
	var p: Vector3 = sim.P[i]
	var out := sim._right(i)
	var yaw := atan2(sim.T[i].x, sim.T[i].z)
	var hw := sim.width / 2.0
	var base: Vector3 = p + out * (hw + 8.0)
	var rows := 5
	var seat_m := _mat(Color(0.25, 0.22, 0.32), 0.6)
	var bas := Basis(Vector3.UP, yaw)
	for r in rows:
		_mesh(_box_mesh(24.0, 0.6, 1.4), seat_m, base + out * (r * 1.3) + Vector3(0, 0.3 + r * 0.7, 0), Vector3(0, yaw, 0))
	_mesh(_box_mesh(24.0, 0.3, rows * 1.3 + 1.0), _mat(Color(0.55, 0.3, 0.85), 0.5), base + out * (rows * 0.65) + Vector3(0, rows * 0.7 + 3.2, 0), Vector3(0, yaw, 0))   # roof
	var people := []; var cols := []
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	var shirt := [BV, CY, Color(1, 0.85, 0.3), Color(0.95, 0.35, 0.4), Color(0.95, 0.95, 0.95), Color(0.3, 0.8, 0.45)]
	for r in rows:
		for k in 30:
			var lx := -11.4 + k * 0.78 + rng.randf_range(-0.1, 0.1)
			var q: Vector3 = base + out * (r * 1.3) + bas * Vector3(lx, 0, 0) + Vector3(0, 0.6 + r * 0.7 + 0.45, 0)
			people.append(Transform3D(Basis.from_scale(Vector3(0.45, 0.9, 0.4)), q))
			cols.append(shirt[rng.randi() % shirt.size()])
	var body := CapsuleMesh.new(); body.radius = 0.5; body.height = 1.0; body.radial_segments = 6; body.rings = 2
	_multi(body, _mat(Color.WHITE, 0.8), people, cols)
	crowd = people
	for k in 6:   # flags on poles in front
		var fp: Vector3 = p + out * (hw + 2.0) + bas * Vector3(-10.0 + k * 4.0, 0, 0)
		_mesh(_box_mesh(0.12, 6.0, 0.12), _mat(Color(0.85, 0.85, 0.9), 0.3, 0.8), fp + Vector3(0, 3.0, 0))
		_mesh(_box_mesh(0.05, 1.2, 2.0), _mat([BV, CY][k % 2], 0.6, 0.0, 0.4), fp + Vector3(0, 5.3, 0) + bas * Vector3(0, 0, 1.0), Vector3(0, yaw, 0))


# ---------------------------------------------------------------- cars
## Open-top car in the racer's colour, with them in the driver's seat. Three body styles (sports / muscle /
## hatch, by fighting style), racing stripes, the Bit & Bytes logo, spoke rims, light strips, underglow.
func _car(r: RaceSim.Racer) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var col: Color = r.C.accent
	var stripe := Color(1, 1, 1) if col.get_luminance() < 0.55 else Color(0.08, 0.06, 0.12)
	var style: String = {"bastion": "muscle", "kael": "muscle", "ember": "muscle", "sora": "sports", "lio": "sports", "vex": "sports"}.get(String(r.C.get("arch", "")), "hatch")
	var body := Node3D.new()
	root.add_child(body)
	var paint := _mat(col, 0.28, 0.55)
	var dark := _mat(Color(0.07, 0.07, 0.09), 0.5, 0.3)
	var chrome := _mat(Color(0.85, 0.86, 0.9), 0.15, 1.0)
	var W := 2.1 if style == "muscle" else (1.95 if style == "sports" else 1.85)
	var L := 4.4 if style == "sports" else (4.3 if style == "muscle" else 3.8)
	var nose := L / 2.0
	# hull
	_mesh(_box_mesh(W, 0.3, L), paint, Vector3(0, 0.42, 0), Vector3.ZERO, body)                              # floor pan
	for sx in [-1.0, 1.0]:
		_mesh(_box_mesh(0.14, 0.36, L * 0.46), paint, Vector3(sx * (W / 2 - 0.07), 0.72, -0.25), Vector3.ZERO, body)   # doors
		_mesh(_box_mesh(0.12, 0.12, L * 0.6), dark, Vector3(sx * (W / 2 + 0.02), 0.3, 0), Vector3.ZERO, body)         # side skirts
		for wz in [-1.0, 1.0]:   # wheel arches
			var arch := CylinderMesh.new(); arch.top_radius = 0.56; arch.bottom_radius = 0.56; arch.height = 0.3; arch.radial_segments = 14
			_mesh(arch, paint, Vector3(sx * (W / 2 - 0.12), 0.55, wz * (L / 2 - 0.85)), Vector3(0, 0, PI / 2), body)
		_mesh(_box_mesh(0.1, 0.08, 0.16), chrome, Vector3(sx * (W / 2 + 0.06), 1.0, 0.45), Vector3.ZERO, body)          # mirrors
	var hood_len := L * (0.42 if style == "sports" else 0.36)
	var hood_h := 0.32 if style == "sports" else 0.4
	_mesh(_box_mesh(W - 0.1, hood_h, hood_len), paint, Vector3(0, 0.6 + hood_h / 2, nose - hood_len / 2 - 0.05), Vector3(0.08 if style == "sports" else 0.03, 0, 0), body)
	_mesh(_box_mesh(W - 0.2, 0.18, 0.5), paint, Vector3(0, 0.5, nose - 0.1), Vector3(0.5, 0, 0), body)           # sloped nose
	if style == "muscle":
		_mesh(_box_mesh(0.6, 0.18, 0.9), dark, Vector3(0, 1.08, nose - hood_len / 2), Vector3(0.05, 0, 0), body)    # hood scoop
	var boot_len := L * (0.22 if style != "hatch" else 0.16)
	_mesh(_box_mesh(W - 0.1, 0.42 if style != "hatch" else 0.7, boot_len), paint, Vector3(0, 0.78 if style != "hatch" else 0.92, -nose + boot_len / 2 + 0.05), Vector3.ZERO, body)
	# racing stripes over bonnet and boot
	for sx in [-0.22, 0.22]:
		_mesh(_box_mesh(0.16, 0.02, hood_len), _mat(stripe, 0.3), Vector3(sx, 0.6 + hood_h + 0.02, nose - hood_len / 2 - 0.05), Vector3(0.08 if style == "sports" else 0.03, 0, 0), body)
	# cockpit: seats, steering wheel, roll bar, windscreen
	_mesh(_box_mesh(0.55, 0.55, 0.14), _mat(Color(0.12, 0.1, 0.14), 0.7), Vector3(0, 0.82, -0.75), Vector3(-0.15, 0, 0), body)
	var wheel_t := TorusMesh.new(); wheel_t.inner_radius = 0.14; wheel_t.outer_radius = 0.18
	_mesh(wheel_t, dark, Vector3(0, 1.05, 0.45), Vector3(PI / 2 - 0.5, 0, 0), body)
	var bar := TorusMesh.new(); bar.inner_radius = 0.62; bar.outer_radius = 0.7; bar.rings = 24
	_mesh(bar, chrome, Vector3(0, 0.9, -1.05), Vector3(0, 0, 0), body).scale = Vector3(1.0, 1.0, 0.25)
	var glass := _mat(Color(0.6, 0.8, 1.0), 0.05, 0.3); glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glass.albedo_color.a = 0.35
	_mesh(_box_mesh(W - 0.25, 0.42, 0.05), glass, Vector3(0, 1.12, 0.62), Vector3(-0.55, 0, 0), body)
	# spoiler on struts
	var sp_y := 1.25 if style == "sports" else 1.15
	_mesh(_box_mesh(W - 0.1, 0.06, 0.45), paint if style != "muscle" else dark, Vector3(0, sp_y, -nose + 0.25), Vector3(-0.08, 0, 0), body)
	for sx in [-0.6, 0.6]:
		_mesh(_box_mesh(0.06, sp_y - 0.9, 0.08), dark, Vector3(sx, (sp_y + 0.9) / 2, -nose + 0.3), Vector3.ZERO, body)
	# lights: headlight strips, taillight bar
	for sx in [-1.0, 1.0]:
		_mesh(_box_mesh(0.5, 0.08, 0.05), _mat(Color(1, 1, 0.92), 0.2, 0.0, 3.0), Vector3(sx * (W / 2 - 0.38), 0.68, nose + 0.01), Vector3.ZERO, body)
	_mesh(_box_mesh(W - 0.3, 0.07, 0.05), _mat(Color(1, 0.12, 0.08), 0.2, 0.0, 2.5), Vector3(0, 0.82 if style != "hatch" else 1.05, -nose - 0.01), Vector3.ZERO, body)
	# diffuser + exhausts
	_mesh(_box_mesh(W - 0.4, 0.14, 0.3), dark, Vector3(0, 0.32, -nose + 0.1), Vector3.ZERO, body)
	for sx in ([-0.35, 0.35] if style == "muscle" else [0.45]):
		var ex := CylinderMesh.new(); ex.top_radius = 0.07; ex.bottom_radius = 0.07; ex.height = 0.25
		_mesh(ex, chrome, Vector3(sx, 0.38, -nose - 0.05), Vector3(PI / 2, 0, 0), body)
	# Bit & Bytes logo on the bonnet and doors; number plate with the driver's name
	var mark: Texture2D = load("res://assets/brand/bnb_mark_trim.png")
	var decal := func(pos: Vector3, rot: Vector3, h: float):
		var d := Sprite3D.new(); d.texture = mark; d.pixel_size = h / mark.get_height(); d.shaded = true
		d.position = pos; d.rotation = rot; body.add_child(d)
	decal.call(Vector3(0, 0.6 + hood_h + 0.035, nose - hood_len / 2 - 0.1), Vector3(-PI / 2 + (0.08 if style == "sports" else 0.03), 0, 0), 0.55)
	for sx in [-1.0, 1.0]:
		decal.call(Vector3(sx * (W / 2 + 0.005), 0.72, -0.25), Vector3(0, sx * PI / 2, 0), 0.3)
	var plate := Label3D.new()
	plate.text = String(r.C.person.get("short", "BNB")) if r.C.has("person") else "BNB"
	plate.font_size = 40; plate.outline_size = 0; plate.modulate = Color(0.1, 0.1, 0.12)
	plate.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	plate.position = Vector3(0, 0.55, -nose - 0.04); plate.rotation = Vector3(0, PI, 0)
	body.add_child(plate)
	_mesh(_box_mesh(0.6, 0.18, 0.02), _mat(Color(0.95, 0.95, 0.9), 0.6), Vector3(0, 0.55, -nose - 0.025), Vector3.ZERO, body)
	# underglow in their colour
	var glow := _mesh(_box_mesh(W - 0.3, 0.02, L - 0.6), _mat(col.lightened(0.2), 0.2, 0.0, 2.5), Vector3(0, 0.12, 0), Vector3.ZERO, body)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# wheels with spoke rims
	var wheels: Array = []
	var tyre := CylinderMesh.new(); tyre.top_radius = 0.44; tyre.bottom_radius = 0.44; tyre.height = 0.34; tyre.radial_segments = 18
	var rim := CylinderMesh.new(); rim.top_radius = 0.27; rim.bottom_radius = 0.27; rim.height = 0.36; rim.radial_segments = 14
	for wx in [-1.0, 1.0]:
		for wz in [-1.0, 1.0]:
			var w := _mesh(tyre, _mat(Color(0.05, 0.05, 0.06), 0.9), Vector3(wx * (W / 2 - 0.12), 0.44, wz * (L / 2 - 0.85)), Vector3(0, 0, PI / 2), body)
			_mesh(rim, chrome, Vector3.ZERO, Vector3.ZERO, w)
			for k in 5:
				_mesh(_box_mesh(0.05, 0.38, 0.06), dark, Vector3(0, 0, 0), Vector3(0, k * TAU / 5.0, 0), w).rotation = Vector3(k * TAU / 5.0, 0, 0)
			wheels.append(w)
	var flame := _mesh(_box_mesh(0.5, 0.3, 1.4), _mat(Color(0.3, 0.8, 1.0), 0.2, 0.0, 4.0), Vector3(0, 0.45, -nose - 0.8), Vector3.ZERO, body)
	flame.visible = false
	# the driver, seated
	var rig := Main.make_rig(r.C, 0)
	root.add_child(rig)
	rig.scale = Vector3.ONE * 0.8
	rig.position = Vector3(0, 0.22, -0.5)
	var name_tag := Label3D.new()
	name_tag.text = String(r.C.person.get("short", r.C.name)) if r.C.has("person") else String(r.C.name)
	name_tag.font_size = 64; name_tag.outline_size = 10; name_tag.modulate = col.lightened(0.4)
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; name_tag.no_depth_test = true
	name_tag.position = Vector3(0, 2.7, 0)
	name_tag.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	root.add_child(name_tag)
	return {root = root, body = body, rig = rig, wheels = wheels, flame = flame, seat = _seated_pose(r.C)}


func _seated_pose(C: Dictionary) -> PackedFloat32Array:
	return Pose.with(C.pose.guard, {hipY = -0.36, torsoX = -0.1, lhx = -1.45, rhx = -1.45, lk = 1.2, rk = 1.2,
		lsx = -1.05, rsx = -1.05, lsz = 0.2, rsz = -0.2, le = -0.5, re = -0.5, headX = 0.0})


func _traffic_car(c: Color) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var m := _mat(c, 0.4, 0.3)
	_mesh(_box_mesh(2.1, 1.1, 4.6), m, Vector3(0, 0.85, 0), Vector3.ZERO, root)
	_mesh(_box_mesh(1.9, 0.8, 2.4), _mat(Color(0.25, 0.3, 0.38), 0.1, 0.4), Vector3(0, 1.7, -0.2), Vector3.ZERO, root)
	return root


func _box() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	_mesh(_box_mesh(1.2, 1.2, 1.2), _mat(CY, 0.3, 0.0, 1.2), Vector3.ZERO, Vector3(0.6, 0.6, 0), n)
	var q := Label3D.new(); q.text = "?"; q.font_size = 120; q.outline_size = 14; q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	q.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	n.add_child(q)
	return n


func _cone() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var c := CylinderMesh.new(); c.top_radius = 0.05; c.bottom_radius = 0.35; c.height = 0.8
	_mesh(c, _mat(Color(1.0, 0.45, 0.1)), Vector3(0, 0.4, 0), Vector3.ZERO, n)
	return n


func _shot_node(prop: String, big: bool) -> Node3D:
	var kind: String = {"stapler": "contract", "plane": "letters"}.get(prop, prop)
	var p := PowerProps.build(kind, CY)
	p.scale = Vector3.ONE * (6.0 if big else 2.4)
	add_child(p)
	return p


# ---------------------------------------------------------------- per frame
## Draw the race. a = 0..1 between the last two ticks (smooth movement on fast screens).
func draw(a: float, dt: float) -> void:
	for k in sim.racers.size():
		var r: RaceSim.Racer = sim.racers[k]
		var c: Dictionary = cars[k]
		var root: Node3D = c.root
		root.position = r.prev_pos.lerp(r.pos, a)
		root.rotation.y = lerp_angle(r.prev_heading, r.heading, a)
		var body: Node3D = c.body
		body.rotation.z = lerpf(body.rotation.z, (0.08 if r.drifting else 0.0) * signf(r.vel.cross(Vector3(sin(r.heading), 0, cos(r.heading))).y), 0.2)
		body.rotation.x = lerpf(body.rotation.x, -0.12 if r.air and r.vy > 0 else 0.0, 0.15)
		for w in c.wheels: (w as Node3D).rotate_object_local(Vector3.UP, r.speed * dt * 2.4)
		var fl: Node3D = c.flame
		fl.visible = r.boost > 0 or r.nitro_on
		if fl.visible: fl.scale = Vector3(1.0, 1.0, 0.8 + randf() * 0.6)
		var rig = c.rig
		if r.flash > 0 and rig.has_method("set_flash"): rig.set_flash(0.6)
		elif rig.has_method("set_flash"): rig.set_flash(0.0)
		rig.apply_pose(c.seat, false)
		if rig.has_method("set_face"): rig.set_face("angry" if r.stun > 0 else ("happy" if r.place == 1 else "neutral"))
	for i in sim.traffic.size():
		var t: RaceSim.Traffic = sim.traffic[i]
		var n: Node3D = traffic_nodes[i]
		n.position = n.position.lerp(t.pos, 0.5); n.rotation.y = t.heading
	for i in sim.boxes.size():
		var b: Dictionary = sim.boxes[i]
		var n: Node3D = box_nodes[i]
		n.visible = b.respawn <= 0
		n.rotation.y += dt * 1.5
	for i in sim.cones.size():
		(cone_nodes[i] as Node3D).visible = sim.cones[i].knocked <= 0
	_sync(sim.shots, shot_nodes, func(s): return _shot_node(s.prop, s.big), func(s, n):
		n.position = s.pos; n.rotation.y += dt * 8.0)
	_sync(sim.hazards, hazard_nodes, func(h): return _hazard_node(h.prop), func(h, n): n.position = h.pos)
	_camera(a, dt)


func _hazard_node(prop: String) -> Node3D:
	if prop == "coffee":
		var n := Node3D.new(); add_child(n)
		var c := CylinderMesh.new(); c.top_radius = 1.4; c.bottom_radius = 1.4; c.height = 0.03
		_mesh(c, _mat(Color(0.35, 0.2, 0.1), 0.1, 0.2), Vector3(0, 0.05, 0), Vector3.ZERO, n)
		return n
	var p := PowerProps.build("banana" if prop == "peel" else prop, CY)
	p.scale = Vector3.ONE * 2.6
	add_child(p)
	return p


func _sync(list: Array, nodes: Dictionary, make: Callable, update: Callable) -> void:
	var alive := {}
	for o in list:
		alive[o] = true
		if not nodes.has(o): nodes[o] = make.call(o)
		update.call(o, nodes[o])
	for o in nodes.keys():
		if not alive.has(o):
			(nodes[o] as Node).queue_free(); nodes.erase(o)


func _camera(a: float, dt: float) -> void:
	var r: RaceSim.Racer = sim.racers[follow]
	var p := r.prev_pos.lerp(r.pos, a)
	var h := lerp_angle(r.prev_heading, r.heading, a)
	var fwd := Vector3(sin(h), 0, cos(h))
	var want := p - fwd * (9.5 + r.speed * 0.06) + Vector3(0, 4.2, 0)
	cam_pos = cam_pos.lerp(want, clampf(dt * 6.0, 0.0, 1.0))
	cam_look = cam_look.lerp(p + fwd * 7.0 + Vector3(0, 1.2, 0), clampf(dt * 8.0, 0.0, 1.0))
	cam.position = cam_pos
	cam.look_at(cam_look, Vector3.UP)
	cam.fov = lerpf(cam.fov, 70.0 + (14.0 if (r.boost > 0 or r.nitro_on) else 0.0) + punch * 18.0, dt * 3.0 + punch * 0.2)
	punch = maxf(0.0, punch - dt * 1.2)
