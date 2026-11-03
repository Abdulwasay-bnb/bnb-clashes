class_name ToonRig
extends Node3D
## Procedural anime-style fighter built from primitives, cel-shaded with outlines.
## Joint layout matches the pose keys in pose.gd.

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")
static var outline_mat: ShaderMaterial

var lift_n := Node3D.new()
var spin := Node3D.new()
var hips := Node3D.new()
var torso := Node3D.new()
var head := Node3D.new()
var l_s: Node3D; var l_e: Node3D; var r_s: Node3D; var r_e: Node3D
var l_h: Node3D; var l_k: Node3D; var r_h: Node3D; var r_k: Node3D
var mats := {}
var joints_only := false
var feet: Array[Node3D] = []   # heel/toe markers used to keep feet on the floor
var acc_mat: ShaderMaterial


static func col(v) -> Color:
	return Color.hex((int(v) << 8) | 0xff)


func mat(key: String, c: Color, emissive := false) -> ShaderMaterial:
	if mats.has(key):
		return mats[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("shade", c.darkened(0.45).lerp(Color(0.35, 0.3, 0.55), 0.35))
	if emissive:
		m.set_shader_parameter("emission", c)
		m.set_shader_parameter("emission_strength", 0.9)
	if outline_mat == null:
		outline_mat = ShaderMaterial.new()
		outline_mat.shader = OUTLINE
	m.next_pass = outline_mat
	mats[key] = m
	return m


func _flat(key: String, c: Color) -> StandardMaterial3D:
	# Eyes and small details: no outline, unshaded so they stay crisp.
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	mats[key] = m
	return m


func add(mesh: Mesh, m: Material, parent: Node3D, pos := Vector3.ZERO, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func sph(r: float, hemi := false) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = r * (1.0 if hemi else 2.0); s.radial_segments = 20; s.rings = 12; s.is_hemisphere = hemi
	return s


static func cap(r: float, l: float) -> CapsuleMesh:
	var c := CapsuleMesh.new(); c.radius = r; c.height = l + 2.0 * r; c.radial_segments = 14; c.rings = 4
	return c


static func cyl(r1: float, r2: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = r1; c.bottom_radius = r2; c.height = h; c.radial_segments = 16
	return c


static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z)
	return b


static func torus(r: float, t: float) -> TorusMesh:
	var m := TorusMesh.new(); m.inner_radius = r - t; m.outer_radius = r + t; m.rings = 24; m.ring_segments = 8
	return m


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.rotation_order = EULER_ORDER_XYZ
	n.position = pos
	parent.add_child(n)
	return n


func build(C: Dictionary) -> void:
	var L: Dictionary = C.look
	var B := {w = 1.0, chest = 1.0, arm = 1.0, leg = 1.0, head = 1.0, fem = false, fist = 1.0}
	if L.has("body"):
		B.merge(L.body, true)
	var w: float = B.w
	var fw := 0.9 if B.fem else 1.0
	var skin := mat("skin", col(L.skin))
	var acc := mat("acc", col(L.accent), true)
	acc_mat = acc
	var top := mat("top", col(L.top.color))
	var top2 := mat("top2", col(L.top.get("color2", L.top.color)))
	var bot := mat("bot", col(L.bottom.color))
	var bot2 := mat("bot2", col(L.bottom.get("color2", L.bottom.color)))
	var hair := mat("hair", col(L.get("hair", 0x111111)))
	var gl: Dictionary = L.get("gloves", {})
	var ft: Dictionary = L.get("feet", {})
	var glove := mat("glove", col(gl.get("color", L.skin)))
	var shoe := mat("shoe", col(ft.get("color", L.skin)))
	var white := mat("white", Color(0.96, 0.96, 0.96))
	var top_t: String = L.top.type
	var bot_t: String = L.bottom.type
	var glove_t: String = gl.get("type", "none")
	var feet_t: String = ft.get("type", "bare")
	var extras: Array = L.get("extras", [])
	var hs: float = B.head * 1.12   # slightly larger anime heads

	add_child(lift_n)
	lift_n.add_child(spin)
	hips.rotation_order = EULER_ORDER_XYZ
	hips.position.y = 0.95
	spin.add_child(hips)

	add(sph(0.15), bot, hips, Vector3.ZERO, Vector3(1.15 * w * (1.08 if B.fem else 1.0), 0.8, 0.85))
	torso.rotation_order = EULER_ORDER_XYZ
	torso.position.y = 0.06
	hips.add_child(torso)
	var bare_abs := top_t == "shirtless" or top_t == "bra"
	add(sph(0.14), skin if bare_abs else top, torso, Vector3(0, 0.12, 0), Vector3(1.05 * w * (0.9 if B.fem else 1.0), 1.0, 0.85))
	var chest_m := skin if top_t == "shirtless" else top
	add(sph(0.2), chest_m, torso, Vector3(0, 0.34, 0), Vector3(1.3 * w * B.chest * fw, 1.0, 0.82 * B.chest))
	if B.fem:
		for s in [1, -1]:
			add(sph(0.068), chest_m, torso, Vector3(s * 0.07, 0.32, 0.1), Vector3(1, 0.9, 0.9))
	if top_t == "gi":
		add(box(0.05, 0.3, 0.02), top2, torso, Vector3(0.04, 0.33, 0.16), Vector3.ONE, Vector3(0, 0, 0.35))
		add(box(0.05, 0.3, 0.02), top2, torso, Vector3(-0.04, 0.33, 0.16), Vector3.ONE, Vector3(0, 0, -0.35))
	if top_t == "armor":
		add(box(0.3 * w, 0.14, 0.06), top2, torso, Vector3(0, 0.38, 0.14))
		for s in [1, -1]:
			add(box(0.17, 0.07, 0.2), top2, torso, Vector3(s * 0.29 * w, 0.53, 0), Vector3.ONE, Vector3(0, 0, s * -0.35))
	if "belt" in extras or top_t == "gi":
		var bm := mat("belt", col(L.get("beltColor", 0x111111))) if top_t == "gi" else acc
		add(torus(0.142 * w, 0.022), bm, torso, Vector3(0, 0.04, 0), Vector3(1.08, 1, 0.78))
	if "core" in extras:
		add(cyl(0.055, 0.055, 0.03), acc, torso, Vector3(0, 0.36, 0.17), Vector3.ONE, Vector3(PI / 2, 0, 0))
	add(cap(0.055, 0.06), skin, torso, Vector3(0, 0.56, 0))

	# ---- head (anime proportions: big eyes, colored irises, bangs) ----
	head.rotation_order = EULER_ORDER_XYZ
	head.position.y = 0.6
	torso.add_child(head)
	var helmet := "helmet" in extras
	var masked := "mask" in extras
	var mask_m := mat("mask", col(L.get("maskColor", L.top.color)))
	var head_m := top2 if helmet else (mask_m if masked else skin)
	add(sph(0.118 * hs), head_m, head, Vector3(0, 0.13, 0), Vector3(0.92, 1.04, 0.98))
	add(sph(0.084 * hs), mask_m if masked else skin, head, Vector3(0, 0.068, 0.03), Vector3(0.95, 0.74, 1.0))
	var iris_c := col(L.get("eye", L.accent)).darkened(0.15)
	if not helmet:
		for s in [1, -1]:
			add(sph(0.026), _flat("eyew", Color(0.98, 0.98, 1.0)), head, Vector3(s * 0.046 * hs, 0.128, 0.097 * hs), Vector3(0.9, 1.25, 0.5))
			add(sph(0.017), _flat("iris", iris_c), head, Vector3(s * 0.045 * hs, 0.125, 0.107 * hs), Vector3(0.9, 1.25, 0.5))
			add(sph(0.009), _flat("pupil", Color(0.05, 0.05, 0.08)), head, Vector3(s * 0.045 * hs, 0.124, 0.112 * hs), Vector3(1, 1.2, 0.5))
			add(sph(0.005), _flat("shine", Color.WHITE), head, Vector3(s * 0.04 * hs, 0.135, 0.116 * hs))
			if not masked:
				add(box(0.05, 0.009, 0.012), _flat("brow", col(L.get("hair", 0x111111))), head, Vector3(s * 0.047 * hs, 0.168, 0.104 * hs), Vector3.ONE, Vector3(0, 0, s * -0.18))
		if not masked:
			add(box(0.03, 0.005, 0.01), _flat("lip", Color(0.45, 0.2, 0.2)), head, Vector3(0, 0.068, 0.1 * hs))
		else:
			for s in [1, -1]:
				add(box(0.075, 0.022, 0.02), acc, head, Vector3(s * 0.052, 0.155, 0.1), Vector3.ONE, Vector3(0, 0, s * -0.35))
			add(box(0.02, 0.07, 0.22), acc, head, Vector3(0, 0.24, -0.01))
	else:
		add(box(0.21, 0.05, 0.05), acc, head, Vector3(0, 0.14, 0.1))
		add(box(0.025, 0.09, 0.2), acc, head, Vector3(0, 0.24, -0.02))
	var style: String = L.get("hairStyle", "none")
	if style in ["buzz", "bun", "ponytail", "long", "braids", "topknot", "spiky", "locs"]:
		add(sph(0.126 * hs), hair, head, Vector3(0, 0.185, -0.035), Vector3(0.98, 0.78, 0.97), Vector3(-0.25, 0, 0))
		if style != "buzz":
			# anime bangs
			for i in 5:
				var x := (i - 2) * 0.034 * hs
				add(_spike(0.03, 0.09), hair, head, Vector3(x, 0.2 - absf(i - 2) * 0.006, 0.085 * hs),
					Vector3(1, 1, 0.5), Vector3(2.7 + absf(i - 2) * 0.06, 0, (i - 2) * 0.22))
	if style == "bun":
		add(sph(0.055), hair, head, Vector3(0, 0.2, -0.1))
	if style == "topknot":
		add(sph(0.045), hair, head, Vector3(0, 0.27, -0.02))
		add(cyl(0.012, 0.012, 0.08), mat("pin", Color(0.83, 0.65, 0.25)), head, Vector3(0, 0.27, -0.02), Vector3.ONE, Vector3(0, 0, PI / 2))
	if style == "ponytail":
		add(sph(0.05), hair, head, Vector3(0, 0.17, -0.12))
		add(cap(0.035, 0.18), hair, head, Vector3(0, 0.05, -0.16), Vector3.ONE, Vector3(0.35, 0, 0))
	if style == "long":
		add(box(0.22, 0.3, 0.07), hair, head, Vector3(0, 0.02, -0.08))
	if style == "braids" or style == "locs":
		for i in range(-2, 3):
			add(cap(0.018, 0.22 if style == "locs" else 0.16), hair, head, Vector3(i * 0.035, 0.0 if style == "locs" else 0.03, -0.1), Vector3.ONE, Vector3(0.25, 0, 0))
	if style == "spiky":
		for i in 7:
			var a := i / 7.0 * TAU
			add(_spike(0.035, 0.1), hair, head, Vector3(sin(a) * 0.07, 0.22, cos(a) * 0.06 - 0.02), Vector3.ONE, Vector3(cos(a) * 0.6, 0, -sin(a) * 0.6))
	if "beard" in extras:
		add(sph(0.075), hair, head, Vector3(0, 0.055, 0.05), Vector3(1.1, 0.8, 0.8))
	if "mustache" in extras:
		add(box(0.07, 0.014, 0.02), hair, head, Vector3(0, 0.088, 0.108))
	if "longbeard" in extras:
		add(cap(0.035, 0.12), hair, head, Vector3(0, -0.02, 0.08), Vector3(1, 1, 0.7))
	if "headband" in extras:
		add(torus(0.124 * hs, 0.014), acc, head, Vector3(0, 0.19, 0), Vector3.ONE, Vector3(-0.12, 0, 0))
		add(box(0.03, 0.2, 0.008), acc, head, Vector3(0.03, 0.1, -0.14), Vector3.ONE, Vector3(0.5, 0, 0))
	if "mongkol" in extras:
		add(torus(0.128 * hs, 0.02), acc, head, Vector3(0, 0.2, 0), Vector3.ONE, Vector3(-0.15, 0, 0))

	# ---- arms ----
	var sleeve := top_t == "gi" or top_t == "armor" or top_t == "jacket"
	var arm := func(sx: float) -> Array:
		var S := _joint(torso, Vector3(sx * 0.25 * w * fw, 0.47, 0))
		add(sph(0.078 * B.arm), top if (sleeve or top_t == "") else (skin if top_t in ["shirtless", "bra", "leotard", "tank"] else top), S)
		add(cap(0.054 * B.arm, 0.19), top if sleeve else skin, S, Vector3(0, -0.15, 0))
		if "armbands" in extras:
			add(torus(0.06 * B.arm, 0.016), acc, S, Vector3(0, -0.1, 0))
		var E := _joint(S, Vector3(0, -0.3, 0))
		add(cap(0.046 * B.arm, 0.17), top2 if top_t == "armor" else skin, E, Vector3(0, -0.13, 0))
		if glove_t == "wraps":
			add(cyl(0.05 * B.arm, 0.052 * B.arm, 0.1), glove, E, Vector3(0, -0.2, 0))
		if glove_t == "boxing":
			add(sph(0.085), glove, E, Vector3(0, -0.3, 0.01), Vector3(1, 1, 1.22))
			add(cyl(0.055, 0.058, 0.07), white, E, Vector3(0, -0.23, 0))
		else:
			add(sph(0.06 * B.fist), skin if glove_t == "none" else glove, E, Vector3(0, -0.29, 0.005), Vector3(1, 0.95, 1.15))
		if glove_t == "mma" or glove_t == "metal":
			add(cyl(0.052, 0.055, 0.05), acc if glove_t == "metal" else glove, E, Vector3(0, -0.24, 0))
		if "forearmLines" in extras:
			add(box(0.012, 0.16, 0.012), acc, E, Vector3(0, -0.13, 0.045))
		return [S, E]
	var la: Array = arm.call(1.0)
	var ra: Array = arm.call(-1.0)
	l_s = la[0]; l_e = la[1]; r_s = ra[0]; r_e = ra[1]

	# ---- legs ----
	var leg := func(sx: float) -> Array:
		var H := _joint(hips, Vector3(sx * 0.1 * w * (1.08 if B.fem else 1.0), -0.03, 0))
		var shorts := bot_t == "shorts"
		add(cap(0.078 * B.leg, 0.27), skin if shorts else bot, H, Vector3(0, -0.22, 0))
		if shorts:
			add(cyl(0.098 * B.leg, 0.092 * B.leg, 0.2), bot, H, Vector3(0, -0.09, 0))
		if L.bottom.get("stripe", 0):
			add(box(0.015, 0.42, 0.015), bot2, H, Vector3(sx * 0.075 * B.leg, -0.22, 0))
		var K := _joint(H, Vector3(0, -0.45, 0))
		add(cap(0.058 * B.leg, 0.3), skin if (shorts or bot_t == "none") else bot, K, Vector3(0, -0.2, 0))
		if "kneepads" in extras:
			add(sph(0.07), acc, K, Vector3(0, 0, 0.03), Vector3(1, 1, 0.8))
		if feet_t == "boots":
			add(cyl(0.068, 0.07, 0.2), shoe, K, Vector3(0, -0.34, 0))
		if feet_t == "wraps":
			add(cyl(0.06, 0.062, 0.08), white, K, Vector3(0, -0.4, 0))
		add(cap(0.045, 0.12), skin if feet_t in ["bare", "wraps"] else shoe, K, Vector3(0, -0.455, 0.045), Vector3(1, 1, 0.9), Vector3(PI / 2, 0, 0))
		for z in [-0.04, 0.13]:
			feet.append(_joint(K, Vector3(0, -0.5, z)))
		return [H, K]
	var ll: Array = leg.call(1.0)
	var rl: Array = leg.call(-1.0)
	l_h = ll[0]; l_k = ll[1]; r_h = rl[0]; r_k = rl[1]
	if "sash" in extras:
		add(box(0.06, 0.22, 0.015), acc, hips, Vector3(0.09, -0.12, 0.14))
		add(box(0.06, 0.18, 0.015), acc, hips, Vector3(0.16, -0.1, 0.1))
	scale = Vector3.ONE * float(C.scale)


## Joint hierarchy only (no meshes): used as the invisible animation proxy for VRM models.
func build_joints() -> void:
	add_child(lift_n)
	lift_n.add_child(spin)
	hips.rotation_order = EULER_ORDER_XYZ
	hips.position.y = 0.95
	spin.add_child(hips)
	torso.rotation_order = EULER_ORDER_XYZ
	torso.position.y = 0.06
	hips.add_child(torso)
	head.rotation_order = EULER_ORDER_XYZ
	head.position.y = 0.6
	torso.add_child(head)
	l_s = _joint(torso, Vector3(0.25, 0.47, 0)); l_e = _joint(l_s, Vector3(0, -0.3, 0))
	r_s = _joint(torso, Vector3(-0.25, 0.47, 0)); r_e = _joint(r_s, Vector3(0, -0.3, 0))
	l_h = _joint(hips, Vector3(0.1, -0.03, 0)); l_k = _joint(l_h, Vector3(0, -0.45, 0))
	r_h = _joint(hips, Vector3(-0.1, -0.03, 0)); r_k = _joint(r_h, Vector3(0, -0.45, 0))


func set_face(_name: String) -> void:
	pass


func set_clip(_name: String, _t: float, _use_hip := true, _mirror := false) -> void:
	pass   # procedural fighters don't use Mixamo clips


func _spike(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = 0.0; c.bottom_radius = r; c.height = h; c.radial_segments = 6
	return c


func apply_pose(p: PackedFloat32Array, ground := true) -> void:
	lift_n.position.y = p[Pose.LIFT]
	spin.rotation.y = p[Pose.YAW]
	hips.position.y = 0.95 + p[Pose.HIP_Y]
	hips.rotation = Vector3(p[Pose.ROOT_RX], p[Pose.HIP_YAW], p[Pose.ROOT_RZ])
	torso.rotation = Vector3(p[Pose.TORSO_X], p[Pose.TORSO_Y], p[Pose.TORSO_Z])
	head.rotation = Vector3(p[Pose.HEAD_X], p[Pose.HEAD_Y], 0)
	l_s.rotation = Vector3(p[Pose.LSX], p[Pose.LSY], p[Pose.LSZ]); l_e.rotation.x = p[Pose.LE]
	r_s.rotation = Vector3(p[Pose.RSX], p[Pose.RSY], p[Pose.RSZ]); r_e.rotation.x = p[Pose.RE]
	l_h.rotation = Vector3(p[Pose.LHX], 0, p[Pose.LHZ]); l_k.rotation.x = p[Pose.LK]
	r_h.rotation = Vector3(p[Pose.RHX], 0, p[Pose.RHZ]); r_k.rotation.x = p[Pose.RK]
	if ground and is_inside_tree() and absf(p[Pose.ROOT_RX]) < 1.0 and absf(p[Pose.ROOT_RZ]) < 1.0:
		# Plant the lowest foot on the floor; jumps (lift > 0) may only be pushed up, never sunk.
		var low := INF
		for m in feet:
			low = minf(low, to_local(m.global_position).y)
		if p[Pose.LIFT] <= 0.001:
			lift_n.position.y -= low
		elif low < 0.0:
			lift_n.position.y -= low


func set_flash(v: float) -> void:
	for k in mats:
		var m = mats[k]
		if m is ShaderMaterial and m != acc_mat and m.shader == TOON:
			m.set_shader_parameter("flash", v)


func set_glow(v: float) -> void:
	if acc_mat: acc_mat.set_shader_parameter("emission_strength", v)
