class_name VrmRig
extends Node3D
## Anime fighter from a VRM 1.0 avatar. The game's poses drive an invisible joint proxy
## (same layout as ToonRig); each frame the proxy is retargeted onto the VRM humanoid skeleton.
## Same interface as ToonRig: build(), apply_pose(), set_flash(), set_glow(), head.

const OUTLINE := preload("res://shaders/outline.gdshader")
static var _shader_cache := {}
static var _file_cache := {}   # path -> PackedByteArray

var proxy: ToonRig
var model: Node3D
var skel: Skeleton3D
var head := Node3D.new()          # marker used by portraits / camera
var k := 1.0                      # model scale so the hips sit at 0.95
var bones := {}                   # humanoid name -> bone index
var rest_g := {}                  # bone index -> rest global Transform3D (skeleton space)
var rest_l := {}                  # bone index -> local Transform3D used for undriven bones
var order: Array[int] = []        # parents before children
var mats: Array[ShaderMaterial] = []
var expressions := {}             # preset -> [[MeshInstance3D, blend index, weight]]
var face := ""
var foot_rest := {}               # bone -> rest height
var arm_axis := {}                # limb -> rest hinge axis
var accent := Color.WHITE
var qb := Basis.IDENTITY          # model -> rig rotation (VRM 0.x models face -Z, so they are turned 180°)
var qi := Basis.IDENTITY
var springs: Array = []           # spring chains (hair, skirts, sleeves): Array of joint dicts, parents first
var colliders: Array = []         # {b, off, r, tail}: spheres / capsules attached to bones
var last_us := 0
var last_root := Vector3.INF
var costume := 0
# Mixamo clip layer (see ClipLib): current + previous clip for crossfades, and blend weight vs. keyframed poses
var clip_name := ""
var clip_t := 0.0
var clip_hip := true
var clip_mirror := false
var clip_pair := false
var head_scale := Vector3.ONE
var base_face := {}        # resting expression: preset -> weight, under the fight expressions
var cloth_mats: Array = []
var wear := Vector3(-1, -1, -1)   # bruise, dirt, blood last applied
var bruise_mat: StandardMaterial3D     # paired throw clip: keep its horizontal hip motion (both fighters share one origin)
var prev_mirror := false
var prev_name := ""
var prev_t := 0.0
var fade := 1.0
var clip_w := 0.0
var clip_target := 0.0
var accs: Array = []              # costume accessories: {node, b, off, basis}
var constraints: Array = []      # VRMC_node_constraint: rotation / roll / aim


static func has_model(C: Dictionary) -> bool:
	return not Models.spec(C.id, 0).is_empty()


func build(C: Dictionary) -> void:
	var spec: Dictionary = Models.spec(C.id, costume)
	accent = C.accent
	proxy = ToonRig.new()
	proxy.joints_only = true
	proxy.build_joints()
	proxy.visible = false
	add_child(proxy)
	add_child(head)
	_load(spec.file)
	_restyle(spec.get("tint", {}))
	_index_skeleton()
	# their own head shape and resting expression (everyone shares a few base models)
	var person: Dictionary = C.get("person", {})
	var hs: Array = person.get("head", [1, 1, 1])
	head_scale = Vector3(hs[0], hs[1], hs[2])
	if bones.has("head"): skel.set_bone_pose_scale(bones.head, head_scale)
	_measure_skull()
	base_face = person.get("face", {})
	set_face("neutral", true)
	_make_fists()
	_make_accessories(spec.get("acc", []))
	scale = Vector3.ONE * float(C.scale)


# ---------------------------------------------------------------- loading
func _load(path: String) -> void:
	if not _file_cache.has(path):
		_file_cache[path] = FileAccess.get_file_as_bytes(path)
	var bytes: PackedByteArray = _file_cache[path]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_buffer(bytes, path.get_base_dir(), state)
	model = doc.generate_scene(state)
	add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	# Read the VRM humanoid map and expressions straight from the glTF JSON chunk.
	var json_len := bytes.decode_u32(12)
	var j: Dictionary = JSON.parse_string(bytes.slice(20, 20 + json_len).get_string_from_utf8())
	var nodes := state.get_nodes()
	var bone_of := func(ni: int) -> int:
		var bi := skel.find_bone(nodes[ni].resource_name)
		return bi if bi >= 0 else skel.find_bone(String(nodes[ni].resource_name).validate_node_name())
	if not j.extensions.has("VRMC_vrm"):
		_load_vrm0(j, state, bone_of)
		return
	var vrm: Dictionary = j.extensions.VRMC_vrm
	for hb in vrm.humanoid.humanBones:
		var bi: int = bone_of.call(int(vrm.humanoid.humanBones[hb].node))
		if bi >= 0:
			bones[hb] = bi
	var axes := {"PositiveX": Vector3.RIGHT, "NegativeX": Vector3.LEFT, "PositiveY": Vector3.UP, "NegativeY": Vector3.DOWN,
		"PositiveZ": Vector3.BACK, "NegativeZ": Vector3.FORWARD, "X": Vector3.RIGHT, "Y": Vector3.UP, "Z": Vector3.BACK}
	for ni in j.nodes.size():
		var ext: Dictionary = j.nodes[ni].get("extensions", {})
		if not ext.has("VRMC_node_constraint"): continue
		var con: Dictionary = ext.VRMC_node_constraint.constraint
		var kind: String = con.keys()[0]
		var c: Dictionary = con[kind]
		var dst: int = bone_of.call(ni)
		var src: int = bone_of.call(int(c.source))
		if dst < 0 or src < 0: continue
		constraints.append({kind = kind, dst = dst, src = src, w = float(c.get("weight", 1.0)),
			axis = axes.get(c.get("aimAxis", c.get("rollAxis", "X")), Vector3.RIGHT)})
	if j.extensions.has("VRMC_springBone"):
		var sb: Dictionary = j.extensions.VRMC_springBone
		var cmap := []
		for c in sb.get("colliders", []):
			var sh: Dictionary = c.shape
			var d: Dictionary = sh.get("sphere", sh.get("capsule", {}))
			var bi: int = bone_of.call(int(c.node))
			cmap.append(colliders.size())
			colliders.append({b = bi, off = _v3(d.get("offset", [0, 0, 0])), r = float(d.get("radius", 0.0)),
				tail = _v3(d.tail) if sh.has("capsule") else null})
		var groups: Array = sb.get("colliderGroups", [])
		for sp in sb.get("springs", []):
			var cols := []
			for gi in sp.get("colliderGroups", []):
				for ci in groups[int(gi)].colliders:
					if colliders[cmap[int(ci)]].b >= 0: cols.append(cmap[int(ci)])
			var js: Array = sp.joints
			var chain := []
			for i in js.size() - 1:   # the last joint is only the tail of the one before it
				var b: int = bone_of.call(int(js[i].node))
				var tb: int = bone_of.call(int(js[i + 1].node))
				if b < 0 or tb < 0: continue
				var jt: Dictionary = js[i]
				chain.append({b = b, tail = tb, stiff = float(jt.get("stiffness", 1.0)), drag = float(jt.get("dragForce", 0.5)),
					grav = _v3(jt.get("gravityDir", [0, -1, 0])) * float(jt.get("gravityPower", 0.0)), hit = float(jt.get("hitRadius", 0.0)), cols = cols})
			if not chain.is_empty(): springs.append(chain)
	if vrm.has("expressions") and vrm.expressions.has("preset"):
		var by_name := _mesh_names()
		for name in vrm.expressions.preset:
			var binds: Array = []
			for b in vrm.expressions.preset[name].get("morphTargetBinds", []):
				var n = _mesh_for(by_name, nodes[int(b.node)].resource_name)
				if n != null:
					binds.append([n, int(b.index), float(b.weight)])
			expressions[name] = binds


## VRM 0.x: humanBones is a list, expressions are "blendShapeGroups", and the model faces -Z.
func _load_vrm0(j: Dictionary, state: GLTFState, bone_of: Callable) -> void:
	var vrm: Dictionary = j.extensions.VRM
	for hb in vrm.humanoid.humanBones:
		var bi: int = bone_of.call(int(hb.node))
		if bi >= 0:
			bones[hb.bone] = bi
	qb = Basis(Vector3.UP, PI)
	qi = qb.inverse()
	model.rotation.y = PI
	# Map glTF mesh index -> scene MeshInstance3D nodes that use it.
	var mesh_nodes := {}
	var gnodes := state.get_nodes()
	var by_name := _mesh_names()
	for ni in gnodes.size():
		if gnodes[ni].mesh >= 0:
			var n = _mesh_for(by_name, gnodes[ni].resource_name)
			if n != null:
				mesh_nodes[gnodes[ni].mesh] = mesh_nodes.get(gnodes[ni].mesh, []) + [n]
	var sa: Dictionary = vrm.get("secondaryAnimation", {})
	var flip := func(o) -> Vector3: return Vector3(-float(o.get("x", 0)), float(o.get("y", 0)), float(o.get("z", 0)))   # Unity -> glTF
	var group_cols := []
	for g in sa.get("colliderGroups", []):
		var ids := []
		var bi: int = bone_of.call(int(g.node))
		for c in g.get("colliders", []):
			ids.append(colliders.size())
			colliders.append({b = bi, off = flip.call(c.get("offset", {})), r = float(c.get("radius", 0.0)), tail = null})
		group_cols.append(ids)
	for g in sa.get("boneGroups", []):
		var cols := []
		for gi in g.get("colliderGroups", []):
			cols.append_array(group_cols[int(gi)])
		var params := {stiff = float(g.get("stiffiness", 1.0)), drag = float(g.get("dragForce", 0.4)), hit = float(g.get("hitRadius", 0.02)),
			grav = flip.call(g.get("gravityDir", {"x": 0, "y": -1, "z": 0})) * float(g.get("gravityPower", 0.0))}
		for root in g.get("bones", []):
			var chain := []
			var stack := [bone_of.call(int(root))]
			while not stack.is_empty():
				var b: int = stack.pop_front()
				if b < 0: continue
				var kids := skel.get_bone_children(b)
				var jd := params.duplicate()
				jd.b = b; jd.tail = kids[0] if kids.size() > 0 else -1; jd.cols = cols
				chain.append(jd)
				for kb in kids: stack.append(kb)
			if not chain.is_empty(): springs.append(chain)
	var rename := {"joy": "happy", "sorrow": "sad", "fun": "surprised", "angry": "angry", "neutral": "neutral",
		"blink_l": "blinkLeft", "blink_r": "blinkRight"}
	for g in vrm.get("blendShapeMaster", {}).get("blendShapeGroups", []):
		var preset: String = String(g.get("presetName", "")).to_lower()
		if not rename.has(preset): continue
		var binds: Array = []
		for b in g.get("binds", []):
			for n in mesh_nodes.get(int(b.mesh), []):
				binds.append([n, int(b.index), float(b.weight) / 100.0])
		expressions[rename[preset]] = binds


## The glTF importer swaps node objects while generating the scene, so look meshes up by name
## in the finished scene instead of keeping the importer's (possibly freed) node references.
func _mesh_names() -> Dictionary:
	var d := {}
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		d[String(mi.name)] = mi
	return d


static func _mesh_for(by_name: Dictionary, raw_name) -> MeshInstance3D:
	var n := String(raw_name)
	if by_name.has(n): return by_name[n]
	if by_name.has(n.validate_node_name()): return by_name[n.validate_node_name()]
	return null


static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _shader(key: String) -> Shader:
	if _shader_cache.has(key):
		return _shader_cache[key]
	var modes := "diffuse_toon, specular_disabled"
	var defs := ""
	if "nocull" in key: modes += ", cull_disabled"
	if "blend" in key:
		modes += ", depth_draw_opaque"
		defs += "#define USE_ALPHA\n"
	if "scissor" in key: defs += "#define USE_SCISSOR\n"
	var s := Shader.new()
	s.code = "shader_type spatial;\nrender_mode %s;\n%s#include \"res://shaders/toon_tex.gdshaderinc\"\n" % [modes, defs]
	_shader_cache[key] = s
	return s


## Replace imported PBR materials with the cel shader (+ outlines), applying per-fighter tints.
func _restyle(tint: Dictionary) -> void:
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE
	outline.set_shader_parameter("thickness", 0.0035)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in mi.mesh.get_surface_count():
			var src = mi.get_active_material(si)
			if not (src is BaseMaterial3D):
				continue
			var name := String(src.resource_name)
			var blend: bool = src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA or src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			var scissor: bool = src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
			var key := ("blend" if blend else "scissor" if scissor else "opaque") + ("_nocull" if src.cull_mode == BaseMaterial3D.CULL_DISABLED else "")
			var m := ShaderMaterial.new()
			m.shader = _shader(key)
			var hidden := false
			for pat in tint:
				if tint[pat] is String and tint[pat] == "hide" and pat.to_lower() in name.to_lower():
					hidden = true
			if hidden:
				# Remove this clothing piece (e.g. the base model's school tie).
				var inv := StandardMaterial3D.new()
				inv.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				inv.albedo_color = Color(0, 0, 0, 0)
				mi.set_surface_override_material(si, inv)
				continue
			var col: Color = src.albedo_color
			for pat in tint:
				if tint[pat] is String: continue
				if pat.to_lower() in name.to_lower():
					# A tint is a Color, or {c = Color, sat = 0..2, bright = 0..2} for full recolors.
					var t = tint[pat]
					if t is Dictionary:
						# VRoid stores much of its color in the material color, not the texture: recolor both.
						var sat: float = t.get("sat", 1.0)
						var l := col.get_luminance()
						col = Color(l, l, l, col.a).lerp(col, clampf(sat, 0.0, 1.0)) * t.get("c", Color.WHITE)
						m.set_shader_parameter("saturation", t.get("sat", 1.0))
						m.set_shader_parameter("brightness", t.get("bright", 1.0))
						if t.has("pat"): _set_pattern(m, t.pat)
					else:
						col *= t
			m.set_shader_parameter("albedo", col)
			m.set_shader_parameter("tex", src.albedo_texture if src.albedo_texture else PlaceholderTexture2D.new())
			m.set_shader_parameter("shade", col.darkened(0.3).lerp(Color(0.55, 0.5, 0.75), 0.4) if src.albedo_texture == null else Color(0.66, 0.6, 0.8))
			if src.emission_enabled:
				m.set_shader_parameter("emission_strength", 0.6)
			var lname := name.to_lower()
			if not blend and not ("eye" in lname or "mouth" in lname or "brow" in lname or "face" in lname and not "skin" in lname):
				m.next_pass = outline
			if src.albedo_texture == null and not blend:
				m.set_shader_parameter("tex", _white())
			mi.set_surface_override_material(si, m)
			mats.append(m)
			var low := name.to_lower()
			if "cloth" in low or "huku" in low or "wear" in low: cloth_mats.append(m)


const PATTERNS := ["none", "plaid", "camo", "flames", "bands", "pinstripes", "diagonal", "dots", "grid", "scales", "gradient", "solid"]


## pat = {kind = "plaid", a = Color, b = Color (optional), scale = 1.0, o = 0.5}; see toon_tex.gdshaderinc
static func _set_pattern(m: ShaderMaterial, pat: Dictionary) -> void:
	m.set_shader_parameter("pattern", maxi(0, PATTERNS.find(pat.get("kind", "none"))))
	m.set_shader_parameter("pat_a", pat.get("a", Color.WHITE))
	m.set_shader_parameter("pat_b", pat.get("b", Color(0, 0, 0, 0)))
	m.set_shader_parameter("pat_scale", pat.get("scale", 1.0))
	m.set_shader_parameter("pat_o", pat.get("o", 0.5))


static var _white_tex: ImageTexture
static func _white() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


# ---------------------------------------------------------------- skeleton
func _index_skeleton() -> void:
	for b in skel.get_bone_count():
		rest_g[b] = skel.get_bone_global_rest(b)
		rest_l[b] = skel.get_bone_rest(b)
	var roots: Array = []
	for b in skel.get_bone_count():
		if skel.get_bone_parent(b) < 0:
			roots.append(b)
	var stack: Array = roots.duplicate()
	while not stack.is_empty():
		var b: int = stack.pop_front()
		order.append(b)
		for c in skel.get_bone_children(b):
			stack.append(c)
	for chain in springs:
		for jn in chain:
			var tail_l: Vector3
			if jn.tail >= 0:
				tail_l = rest_l[jn.tail].origin
			else:   # VRM 0.x leaf: virtual 7 cm tail continuing the bone's direction
				var dir: Vector3 = rest_l[jn.b].origin.normalized()
				tail_l = rest_l[jn.b].basis.inverse() * dir * 0.07
			jn.axis = tail_l.normalized()
			jn.len = tail_l.length()
	var hip_y: float = rest_g[bones.hips].origin.y
	k = 0.95 / hip_y
	model.scale = Vector3.ONE * k
	for f in ["leftFoot", "rightFoot", "leftToes", "rightToes"]:
		if bones.has(f):
			foot_rest[bones[f]] = rest_g[bones[f]].origin.y
	# Hinge axes in the rest pose: the proxy's limbs hang straight down with the hinge along X.
	for limb in [["leftUpperArm", "leftLowerArm"], ["rightUpperArm", "rightLowerArm"], ["leftUpperLeg", "leftLowerLeg"], ["rightUpperLeg", "rightLowerLeg"]]:
		var d := _rest_dir(limb[0], limb[1])
		arm_axis[limb[0]] = Quaternion(Vector3.DOWN, d) * (qi * Vector3.RIGHT)


func _rest_dir(a: String, b: String) -> Vector3:
	return (rest_g[bones[b]].origin - rest_g[bones[a]].origin).normalized()


func _make_fists() -> void:
	for side in ["left", "right"]:
		if not bones.has(side + "Hand") or not bones.has(side + "MiddleProximal"):
			continue
		var fdir: Vector3 = (rest_g[bones[side + "MiddleProximal"]].origin - rest_g[bones[side + "Hand"]].origin).normalized()
		var axis_w: Vector3 = fdir.cross(Vector3.DOWN).normalized()
		for finger in ["Index", "Middle", "Ring", "Little", "Thumb"]:
			for seg in ["Proximal", "Intermediate", "Distal", "Metacarpal"]:
				var n: String = side + finger + seg
				if not bones.has(n): continue
				var b: int = bones[n]
				var ang := 1.25
				var aw := axis_w
				if finger == "Thumb":
					# Tuck the thumb across the curled fingers instead of curling it like a finger.
					ang = 0.85 if seg != "Metacarpal" else 0.5
					aw = qi * Vector3.RIGHT
				var axis_l: Vector3 = (rest_g[b].basis.inverse() * aw).normalized()
				var t: Transform3D = rest_l[b]
				t.basis = t.basis * Basis(axis_l, ang)
				rest_l[b] = t


# ---------------------------------------------------------------- posing
static func _frame(dir: Vector3, axis: Vector3) -> Basis:
	var y := dir.normalized()
	var x := (axis - y * axis.dot(y))
	if x.length() < 1e-4:
		x = Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	x = x.normalized()
	return Basis(x, y, x.cross(y))


func _rel(n: Node3D) -> Transform3D:
	return proxy.global_transform.affine_inverse() * n.global_transform


func apply_pose(p: PackedFloat32Array, ground := true) -> void:
	proxy.apply_pose(p, false)
	var hips_t := _rel(proxy.hips)
	var hips_d := hips_t.basis.orthonormalized()
	var torso_l := proxy.torso.basis
	var head_l := proxy.head.basis
	var spine_d := hips_d * Basis().slerp(torso_l, 0.5)
	var chest_d := hips_d * torso_l
	var neck_d := chest_d * Basis().slerp(head_l, 0.5)
	var head_d := chest_d * head_l
	var toS := func(b: Basis) -> Basis: return qi * b * qb   # rig-space rotation -> skeleton space
	hips_d = toS.call(hips_d); spine_d = toS.call(spine_d); chest_d = toS.call(chest_d)
	neck_d = toS.call(neck_d); head_d = toS.call(head_d)
	var want := {}   # bone -> desired global basis (skeleton space)
	var put := func(name: String, delta: Basis) -> void:
		if bones.has(name):
			want[bones[name]] = delta * rest_g[bones[name]].basis
	put.call("hips", hips_d)
	put.call("spine", spine_d)
	put.call("chest", chest_d)
	put.call("upperChest", chest_d)
	put.call("neck", neck_d)
	put.call("head", head_d)
	# Limbs: aim each segment along the proxy's segment, keeping the elbow/knee hinge aligned.
	for L in [["leftUpperArm", "leftLowerArm", "leftHand", proxy.l_s, proxy.l_e], ["rightUpperArm", "rightLowerArm", "rightHand", proxy.r_s, proxy.r_e],
			["leftUpperLeg", "leftLowerLeg", "leftFoot", proxy.l_h, proxy.l_k], ["rightUpperLeg", "rightLowerLeg", "rightFoot", proxy.r_h, proxy.r_k]]:
		if not (bones.has(L[0]) and bones.has(L[1]) and bones.has(L[2])):
			continue
		var up_b := qi * _rel(L[3]).basis
		var lo_b := qi * _rel(L[4]).basis
		var hinge := lo_b.x
		var ax_r: Vector3 = arm_axis[L[0]]
		var r_up := _frame(-up_b.y, hinge) * _frame(_rest_dir(L[0], L[1]), ax_r).inverse()
		var r_lo := _frame(-lo_b.y, hinge) * _frame(_rest_dir(L[1], L[2]), ax_r).inverse()
		want[bones[L[0]]] = r_up * rest_g[bones[L[0]]].basis
		want[bones[L[1]]] = r_lo * rest_g[bones[L[1]]].basis
		want[bones[L[2]]] = r_lo * rest_g[bones[L[2]]].basis
	# Hips translation (proxy units -> skeleton units).
	var hip_pos: Vector3 = rest_g[bones.hips].origin + qi * (hips_t.origin - Vector3(0, 0.95, 0)) / k
	# blend in/out a bit faster so turning a step into a block or an attack feels immediate
	clip_w = move_toward(clip_w, clip_target, 0.25)
	fade = minf(1.0, fade + 0.25)
	if clip_w > 0.001 and clip_name != "":
		hip_pos = _blend_clip(want, hip_pos)
	# Solve once, evaluate constraints from that result, then solve again with them applied.
	var first := _solve(want, hip_pos, {})
	var over := {}
	for c in constraints:
		over[c.dst] = _constraint_local(c, first[0], first[1])
	var res := _solve(want, hip_pos, over)
	var G: Dictionary = res[0]
	var Ls: Dictionary = res[1]
	# Keep feet on the floor: no foot may sink below its rest height.
	var lift := 0.0
	if ground and not foot_rest.is_empty():
		var low := INF
		for b in foot_rest:
			low = minf(low, G[b].origin.y - foot_rest[b])
		lift = -low * k
		if p[Pose.LIFT] > 0.001:
			lift = maxf(lift, 0.0)
	model.position.y = lift
	if not springs.is_empty():
		_springs(G, Ls)
	for b in order:
		skel.set_bone_pose_rotation(b, Ls[b].basis.get_rotation_quaternion())
		skel.set_bone_pose_position(b, Ls[b].origin)
	head.position = model.transform * G[bones.head].origin + Vector3(0, 0.06, 0)
	if not accs.is_empty():
		_place_accessories(G)


## VRM spring bones (hair, skirts, sleeves), simulated in world space so they react to movement.
func _springs(G: Dictionary, Ls: Dictionary) -> void:
	if not is_inside_tree(): return
	var SK := skel.global_transform
	var now := Time.get_ticks_usec()
	var dt := clampf((now - last_us) / 1000000.0, 0.001, 1.0 / 30.0)
	last_us = now
	var ws := SK.basis.get_scale().x   # world size of one skeleton unit
	var root: Vector3 = SK * G[bones.hips].origin
	var reset := last_root.distance_to(root) > 0.8   # teleported (new round): restart from rest
	last_root = root
	var cw := []
	for c in colliders:
		if c.b < 0:
			cw.append(null); continue
		var T: Transform3D = SK * G[c.b]
		cw.append([T * c.off, (T * c.tail) if c.tail != null else null, c.r * ws])
	for chain in springs:
		for jn in chain:
			var b: int = jn.b
			var par := skel.get_bone_parent(b)
			var pg: Transform3D = G[par] if par >= 0 else Transform3D.IDENTITY
			var PW := SK * pg
			var head_w: Vector3 = PW * Ls[b].origin
			var prot := PW.basis.orthonormalized()
			var rest_rot: Basis = prot * rest_l[b].basis.orthonormalized()
			var ln: float = jn.len * ws
			if reset or not jn.has("cur"):
				jn.cur = head_w + rest_rot * jn.axis * ln
				jn.prev = jn.cur
			var nxt: Vector3 = jn.cur + (jn.cur - jn.prev) * (1.0 - jn.drag) + rest_rot * jn.axis * jn.stiff * dt * ws + jn.grav * dt * ws
			nxt = head_w + (nxt - head_w).normalized() * ln
			for ci in jn.cols:
				var c = cw[ci]
				if c == null: continue
				var p: Vector3 = c[0]
				if c[1] != null:   # capsule: nearest point on its segment
					var seg: Vector3 = c[1] - c[0]
					p = c[0] + seg * clampf((nxt - c[0]).dot(seg) / maxf(seg.length_squared(), 1e-8), 0.0, 1.0)
				var r: float = c[2] + jn.hit * ws
				var d := nxt - p
				if d.length() < r and d.length() > 1e-6:
					nxt = head_w + ((p + d.normalized() * r) - head_w).normalized() * ln
			jn.prev = jn.cur
			jn.cur = nxt
			var from: Vector3 = rest_rot * jn.axis
			var to := (nxt - head_w).normalized()
			var wrot := rest_rot if from.dot(to) > 0.99999 else Basis(Quaternion(from, to)) * rest_rot
			Ls[b] = Transform3D(prot.inverse() * wrot, Ls[b].origin)
			G[b] = pg * Ls[b]


## Walk the hierarchy turning desired global rotations into local poses. Returns [globals, locals].
func _solve(want: Dictionary, hip_pos: Vector3, over: Dictionary) -> Array:
	var G := {}
	var Ls := {}
	for b in order:
		var par := skel.get_bone_parent(b)
		var pg: Transform3D = G[par] if par >= 0 else Transform3D.IDENTITY
		var gt: Transform3D
		if over.has(b):
			gt = pg * over[b]
		elif want.has(b):
			var origin: Vector3 = hip_pos if b == bones.hips else (pg * rest_l[b]).origin
			gt = Transform3D(want[b], origin)
		else:
			gt = pg * rest_l[b]
		G[b] = gt
		Ls[b] = pg.affine_inverse() * gt
	return [G, Ls]


func _constraint_local(c: Dictionary, G: Dictionary, Ls: Dictionary) -> Transform3D:
	var rest: Transform3D = rest_l[c.dst]
	var w: float = c.w
	if c.kind == "aim":
		var par := skel.get_bone_parent(c.dst)
		var pg: Transform3D = G[par] if par >= 0 else Transform3D.IDENTITY
		var base := pg * rest
		var from: Vector3 = (base.basis * c.axis).normalized()
		var to: Vector3 = (G[c.src].origin - base.origin).normalized()
		if from.length() < 0.5 or to.length() < 0.5 or from.dot(to) > 0.9999:
			return rest
		var q := Quaternion.IDENTITY.slerp(Quaternion(from, to), w)
		return Transform3D(pg.basis.inverse() * (Basis(q) * base.basis), rest.origin)
	var delta := Quaternion(rest_l[c.src].basis.orthonormalized().inverse() * Ls[c.src].basis.orthonormalized())
	if c.kind == "roll":
		var a: Vector3 = c.axis
		var proj := Vector3(delta.x, delta.y, delta.z).project(a)
		var tw := Quaternion(proj.x, proj.y, proj.z, delta.w)
		delta = tw.normalized() if tw.length() > 1e-5 else Quaternion.IDENTITY
	return Transform3D(rest.basis * Basis(Quaternion.IDENTITY.slerp(delta, w)), rest.origin)


# ---------------------------------------------------------------- costume accessories
const TOON_SHADER := preload("res://shaders/toon.gdshader")


## Parts per accessory kind: [humanoid bone, mesh, rest offset (rig space: +Y up, +Z front, +X fighter's left), euler, scale].
## The VRM rest pose is a T-pose, so arms point along +X (left) / -X (right).
func _acc_parts(kind: String) -> Array:
	var tor := func(r: float, th: float) -> TorusMesh:
		var t := TorusMesh.new(); t.inner_radius = r - th; t.outer_radius = r + th; t.rings = 24; t.ring_segments = 8
		return t
	var Z90 := Vector3(0, 0, PI / 2)
	match kind:
		"gloves":
			return [["leftHand", ToonRig.sph(0.075), Vector3(0.06, 0, 0), Vector3.ZERO, Vector3(1.3, 1.0, 1.05)],
				["rightHand", ToonRig.sph(0.075), Vector3(-0.06, 0, 0), Vector3.ZERO, Vector3(1.3, 1.0, 1.05)],
				["leftLowerArm", ToonRig.cyl(0.052, 0.05, 0.06), Vector3(0.21, 0, 0), Z90, Vector3.ONE],
				["rightLowerArm", ToonRig.cyl(0.052, 0.05, 0.06), Vector3(-0.21, 0, 0), Z90, Vector3.ONE]]
		"wraps":
			return [["leftLowerArm", ToonRig.cyl(0.046, 0.042, 0.15), Vector3(0.17, 0, 0), Z90, Vector3.ONE],
				["rightLowerArm", ToonRig.cyl(0.046, 0.042, 0.15), Vector3(-0.17, 0, 0), Z90, Vector3.ONE],
				["leftHand", ToonRig.cyl(0.044, 0.044, 0.05), Vector3(0.03, 0, 0), Z90, Vector3(1, 1, 1.15)],
				["rightHand", ToonRig.cyl(0.044, 0.044, 0.05), Vector3(-0.03, 0, 0), Z90, Vector3(1, 1, 1.15)]]
		"headband":
			return [["head", tor.call(0.118, 0.012), Vector3(0, 0.095, -0.005), Vector3(-0.2, 0, 0), Vector3(1, 1, 1.08)],
				["head", ToonRig.box(0.03, 0.17, 0.008), Vector3(0.03, 0.05, -0.13), Vector3(0.55, 0, 0.1), Vector3.ONE],
				["head", ToonRig.box(0.03, 0.14, 0.008), Vector3(-0.025, 0.06, -0.13), Vector3(0.45, 0, -0.15), Vector3.ONE]]
		"belt":
			return [["hips", tor.call(0.13, 0.02), Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(1.08, 1.0, 0.78)]]
		"sash":
			return _acc_parts("belt") + [["hips", ToonRig.box(0.06, 0.24, 0.015), Vector3(0.09, -0.07, 0.12), Vector3(0.1, 0, 0.1), Vector3.ONE],
				["hips", ToonRig.box(0.06, 0.2, 0.015), Vector3(0.15, -0.05, 0.08), Vector3(0.1, 0, 0.25), Vector3.ONE]]
		"armbands":
			return [["leftUpperArm", tor.call(0.046, 0.011), Vector3(0.11, 0, 0), Z90, Vector3.ONE],
				["rightUpperArm", tor.call(0.046, 0.011), Vector3(-0.11, 0, 0), Z90, Vector3.ONE]]
		"visor":
			return [["head", ToonRig.box(0.2, 0.04, 0.04), Vector3(0, 0.075, 0.105), Vector3.ZERO, Vector3.ONE]]
		"glasses":
			var X90 := Vector3(PI / 2, 0, 0)
			return [["head", tor.call(0.026, 0.0022), Vector3(0.034, 0.072, 0.108), X90, Vector3.ONE],
				["head", tor.call(0.026, 0.0022), Vector3(-0.034, 0.072, 0.108), X90, Vector3.ONE],
				["head", ToonRig.box(0.016, 0.005, 0.005), Vector3(0, 0.074, 0.11), Vector3.ZERO, Vector3.ONE],
				["head", ToonRig.box(0.005, 0.005, 0.1), Vector3(0.066, 0.074, 0.06), Vector3.ZERO, Vector3.ONE],
				["head", ToonRig.box(0.005, 0.005, 0.1), Vector3(-0.066, 0.074, 0.06), Vector3.ZERO, Vector3.ONE]]
		# ---- hair styles (BNB Clashes): replace the shared base hair with a per-person cut
		"hair_back", "hair_back_full", "hair_army", "hair_side", "hair_wolf", "hair_curl", "hair_thin", "hair_short", "hair_messy", "hair_spiky", \
		"hair_ponytail", "hair_bob", "hair_bun", "hair_long", "hair_braid":
			return _hair_parts(kind)
		# ---- garments (BNB Clashes): simple shapes on the bones, so modest outfits stay covered while fighting
		"hijab":
			return [["head", ToonRig.sph(0.128), Vector3(0, 0.078, -0.058), Vector3.ZERO, Vector3(1.0, 1.06, 1.0)],
				["head", tor.call(0.105, 0.02), Vector3(0, 0.05, 0.035), Vector3(PI / 2 + 0.2, 0, 0), Vector3(1.0, 1.25, 1.0)],
				["neck", ToonRig.cyl(0.085, 0.2, 0.2), Vector3(0, -0.02, -0.005), Vector3.ZERO, Vector3(1.0, 1.0, 0.85)]]
		"kameez":
			# a short skirt piece on the hips plus one long panel per thigh (a kameez has side slits),
			# so the hem moves with the legs instead of the knees poking through it
			return [["hips", ToonRig.cyl(0.17, 0.205, 0.2), Vector3(0, -0.04, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.9)],
				["leftUpperLeg", ToonRig.cyl(0.14, 0.17, 0.4), Vector3(0.012, -0.17, -0.01), Vector3.ZERO, Vector3(1.0, 1.0, 0.98)],
				["rightUpperLeg", ToonRig.cyl(0.14, 0.17, 0.4), Vector3(-0.012, -0.17, -0.01), Vector3.ZERO, Vector3(1.0, 1.0, 0.98)]]
		"shalwar":   # wide enough for thighs and calves, set a little back, with the knee covered
			return [["leftUpperLeg", ToonRig.cyl(0.125, 0.1, 0.47), Vector3(0, -0.21, -0.012), Vector3.ZERO, Vector3.ONE],
				["rightUpperLeg", ToonRig.cyl(0.125, 0.1, 0.47), Vector3(0, -0.21, -0.012), Vector3.ZERO, Vector3.ONE],
				["leftLowerLeg", ToonRig.sph(0.108), Vector3(0, 0.01, -0.022), Vector3.ZERO, Vector3(1.0, 1.15, 1.05)],
				["rightLowerLeg", ToonRig.sph(0.108), Vector3(0, 0.01, -0.022), Vector3.ZERO, Vector3(1.0, 1.15, 1.05)],
				["leftLowerLeg", ToonRig.cyl(0.102, 0.08, 0.42), Vector3(0, -0.2, -0.012), Vector3.ZERO, Vector3.ONE],
				["rightLowerLeg", ToonRig.cyl(0.102, 0.08, 0.42), Vector3(0, -0.2, -0.012), Vector3.ZERO, Vector3.ONE]]
		"sleeves":
			return [["leftUpperArm", ToonRig.cyl(0.05, 0.046, 0.27), Vector3(0.13, 0, 0), Z90, Vector3.ONE],
				["rightUpperArm", ToonRig.cyl(0.05, 0.046, 0.27), Vector3(-0.13, 0, 0), Z90, Vector3.ONE],
				["leftLowerArm", ToonRig.cyl(0.044, 0.038, 0.24), Vector3(0.12, 0, 0), Z90, Vector3.ONE],
				["rightLowerArm", ToonRig.cyl(0.044, 0.038, 0.24), Vector3(-0.12, 0, 0), Z90, Vector3.ONE]]
		"dupatta":
			return [["upperChest", tor.call(0.13, 0.03), Vector3(0, 0.1, 0), Vector3(0.25, 0, 0), Vector3(1.05, 1.0, 0.8)],
				["upperChest", ToonRig.box(0.11, 0.42, 0.02), Vector3(0.1, -0.1, -0.11), Vector3(0.1, 0, 0.15), Vector3.ONE],
				["upperChest", ToonRig.box(0.11, 0.38, 0.02), Vector3(-0.12, -0.08, 0.1), Vector3(-0.08, 0, -0.2), Vector3.ONE]]
		"beard":
			var tufts: Array = []
			var jaw_y := skull.position.y + 0.012            # just above the chin
			var front := skull.position.z + skull.size.z
			var hw := skull.size.x / 2.0
			for k in 13:
				var a := (k - 6) / 6.0 * 1.25                # ear to ear around the jaw, overlapping tufts
				var pos := Vector3(sin(a) * hw * 0.86, lerpf(jaw_y + 0.045, jaw_y, cos(a)), front - 0.03 - (1.0 - cos(a)) * 0.095)
				tufts.append(["head", ToonRig.sph(0.016), pos, Vector3(0, a, 0), Vector3(1.6, 1.3, 0.5)])
			return tufts + _acc_parts("mustache")
		"mustache":
			return [["head", ToonRig.sph(0.016), Vector3(0.016, 0.016, 0.103), Vector3(0, 0, -0.25), Vector3(1.7, 0.55, 0.6)],
				["head", ToonRig.sph(0.016), Vector3(-0.016, 0.016, 0.103), Vector3(0, 0, 0.25), Vector3(1.7, 0.55, 0.6)]]
		"kneepads":
			return [["leftLowerLeg", ToonRig.sph(0.06), Vector3(0, 0.0, 0.05), Vector3.ZERO, Vector3(1, 1, 0.6)],
				["rightLowerLeg", ToonRig.sph(0.06), Vector3(0, 0.0, 0.05), Vector3.ZERO, Vector3(1, 1, 0.6)]]
		"shoulders":
			return [["leftUpperArm", ToonRig.box(0.15, 0.06, 0.17), Vector3(0.03, 0.07, 0), Vector3(0, 0, -0.3), Vector3.ONE],
				["rightUpperArm", ToonRig.box(0.15, 0.06, 0.17), Vector3(-0.03, 0.07, 0), Vector3(0, 0, 0.3), Vector3.ONE]]
	return []


## Hair pieces, placed from the measured skull: A = (0, top of head, face front), sizes scale with head width.
## Every style starts from a cap that clears the scalp and sits back from the face (the forehead shows),
## plus volume at the back of the head; each style adds its own shapes.
func _hair_parts(kind: String) -> Array:
	var H := "head"
	var f := (skull.size.x / 2.0) / 0.105                       # 1.0 on the men's base, ~1.08 on the women's
	var A := Vector3(0, skull.position.y + skull.size.y, skull.position.z + skull.size.z)
	var at := func(x: float, y: float, z: float) -> Vector3: return A + Vector3(x, y, z) * f
	var blob := func(pos: Vector3, rx: float, ry: float, rz: float, rot := Vector3.ZERO) -> Array:
		return [H, ToonRig.sph(1.0), pos, rot, Vector3(rx, ry, rz) * f]
	var cone := func(r: float, h: float, pos: Vector3, rot: Vector3) -> Array: return [H, ToonRig.cyl(0.0, r * f, h * f), pos, rot, Vector3.ONE]
	# cap: centred well behind the face, so its front edge is a hairline high on the forehead
	var cap: Array = blob.call(at.call(0, -0.07, -0.172), 0.12, 0.1, 0.135)
	var back: Array = blob.call(at.call(0, -0.13, -0.23), 0.112, 0.105, 0.08)
	var out: Array = []
	if kind in ["hair_ponytail", "hair_bun", "hair_long", "hair_braid"]:
		# women's cuts: hairline further forward, with soft bangs over the forehead
		cap = blob.call(at.call(0, -0.07, -0.15), 0.122, 0.105, 0.135)
		out.append(blob.call(at.call(0, -0.035, -0.035), 0.1, 0.04, 0.055, Vector3(0.35, 0, 0)))
		for sx in [-1.0, 1.0]:
			out.append(blob.call(at.call(sx * 0.1, -0.12, -0.07), 0.03, 0.085, 0.06))
	match kind:
		"hair_back_full":   # swept back over a full cap (base hair hidden)
			out = [cap, back, blob.call(at.call(0, -0.03, -0.17), 0.09, 0.05, 0.1, Vector3(-0.3, 0, 0))]
		"hair_army", "hair_back":   # army cut: the base hair, kept short and neat
			out = []
		"hair_short":  # short with a little fringe at the front
			out = [blob.call(at.call(0, -0.012, -0.035), 0.075, 0.022, 0.035, Vector3(0.4, 0, 0))]
		"hair_thin":
			out = []
		"hair_side":   # side part: a sweep over one side
			out = [blob.call(at.call(0.045, 0.0, -0.06), 0.085, 0.032, 0.07, Vector3(0, 0, -0.3))]
		"hair_wolf":   # wolf cut: shaggy layers on top, longer flicks at the nape and sides
			for k in 5:
				var a := (k - 2) * 0.32
				out.append(cone.call(0.032, 0.13, at.call(sin(a) * 0.08, -0.2, -0.2 + absf(sin(a)) * 0.04), Vector3(0.55, a * 0.6, 0)))
			for k in 6:
				var a := (k - 2.5) * 0.45
				out.append(cone.call(0.035, 0.08, at.call(sin(a) * 0.07, 0.012, -0.09 + cos(a) * 0.02), Vector3(-0.9, 0, a * 0.5)))
			for sx in [-1.0, 1.0]:
				out.append(cone.call(0.03, 0.1, at.call(sx * 0.112, -0.12, -0.1), Vector3(0, 0, sx * -0.35)))
		"hair_curl":   # styled back, with low flat waves along the front hairline (nothing piled on top)
			for k in 5:
				var a := (k - 2) * 0.42
				out.append(blob.call(at.call(sin(a) * 0.07, -0.022, -0.06 + cos(a) * 0.012), 0.03, 0.014, 0.026, Vector3(0.5, a * 0.5, 0)))
		"hair_messy":  # relaxed and unbrushed
			for k in 7:
				var a := k * 0.9
				out.append(cone.call(0.032, 0.075, at.call(sin(a) * 0.065, 0.008, -0.09 + cos(a) * 0.05), Vector3(sin(a) * 0.8, 0, cos(a) * 0.8)))
		"hair_spiky":  # comic spikes
			for k in 7:
				var a := (k - 3) * 0.38
				out.append(cone.call(0.03, 0.13, at.call(sin(a) * 0.065, 0.025, -0.085), Vector3(-0.35, 0, a * 0.8)))
		"hair_ponytail":   # high ponytail with a band
			out += [cap, back, [H, ToonRig.cyl(0.03 * f, 0.03 * f, 0.035 * f), at.call(0, -0.04, -0.235), Vector3(-1.0, 0, 0), Vector3.ONE]]
			for k in 4:
				out.append(blob.call(at.call(0, -0.07 - k * 0.075, -0.27 - k * 0.012), 0.045 - k * 0.007, 0.07, 0.045 - k * 0.007))
		"hair_bob":    # chin-length bob with a fringe
			out = [cap, back, blob.call(at.call(0, -0.03, -0.03), 0.1, 0.03, 0.05)]
			for sx in [-1.0, 1.0]:
				out.append(blob.call(at.call(sx * 0.11, -0.16, -0.08), 0.038, 0.09, 0.085))
			out.append(blob.call(at.call(0, -0.18, -0.17), 0.12, 0.09, 0.09))
		"hair_bun":    # neat bun on the back of the head
			out += [cap, back, blob.call(at.call(0, -0.03, -0.25), 0.058, 0.058, 0.058)]
		"hair_long":   # long straight hair down the back
			out += [cap, back, [H, ToonRig.box(0.22 * f, 0.44 * f, 0.045 * f), at.call(0, -0.38, -0.21), Vector3(0.12, 0, 0), Vector3.ONE]]
			for sx in [-1.0, 1.0]:
				out.append([H, ToonRig.box(0.04 * f, 0.3 * f, 0.05 * f), at.call(sx * 0.112, -0.26, -0.1), Vector3.ZERO, Vector3.ONE])
		"hair_braid":  # side braid over the shoulder
			out += [cap, back]
			for k in 6:
				out.append(blob.call(at.call(0.095 + k * 0.006, -0.18 - k * 0.055, -0.09 + k * 0.012), 0.032, 0.04, 0.032))
	return out


func _make_accessories(list: Array) -> void:
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE
	outline.set_shader_parameter("thickness", 0.006)
	for a in list:
		var kind: String = a[0]
		var col: Color = a[1]
		var flat := kind in ["visor", "glasses", "mustache", "beard", "kameez", "shalwar", "sleeves", "hijab", "dupatta"]
		if kind != "visor":
			col = col * 0.72   # keep within the texture range of the models so accessories don't bloom
			col.a = 1.0
		# Same cel shader as the model so accessories are lit like the clothes they sit on.
		var m := ShaderMaterial.new()
		m.shader = _shader("opaque")
		m.set_shader_parameter("tex", _white())
		m.set_shader_parameter("albedo", col)
		m.set_shader_parameter("shade", col.darkened(0.3).lerp(Color(0.55, 0.5, 0.75), 0.4))
		if kind == "visor":
			m.set_shader_parameter("emission_strength", 1.1)
		elif not flat:
			m.next_pass = outline
		mats.append(m)
		for part in _acc_parts(kind):
			if not bones.has(part[0]): continue
			var mi := MeshInstance3D.new()
			mi.mesh = part[1]
			mi.material_override = m
			add_child(mi)
			var off: Vector3 = part[2]
			var bas := Basis.from_euler(part[3]).scaled(part[4])
			if part[0] == "head":   # follow the person's head shape
				off *= head_scale
				bas = Basis.from_scale(head_scale) * bas
			accs.append({node = mi, b = bones[part[0]], off = off, basis = bas})


func _place_accessories(G: Dictionary) -> void:
	for a in accs:
		var b: int = a.b
		var delta: Basis = (G[b].basis * rest_g[b].basis.inverse()).orthonormalized()
		var pos_s: Vector3 = G[b].origin + delta * (qi * a.off) / k
		a.node.transform = Transform3D(qb * delta * qi * a.basis, model.transform * pos_s)


# ---------------------------------------------------------------- Mixamo clip layer
## Request a clip for this frame ("" = keyframed poses only). t is the time into the clip in seconds.
func set_clip(name: String, t: float, use_hip := true, mirror := false, pair := false) -> void:
	clip_pair = pair
	if name == "" or not ClipLib.has(name):
		clip_target = 0.0
		return
	clip_target = 1.0
	if name != clip_name or mirror != clip_mirror:
		if clip_name != "" and clip_w > 0.01:
			prev_name = clip_name
			prev_t = clip_t
			prev_mirror = clip_mirror
			fade = 0.0
		clip_name = name
		clip_mirror = mirror
	clip_t = t
	clip_hip = use_hip


func _clip_sample() -> Array:
	var cur: ClipLib.Clip = ClipLib.get_clip(clip_name)
	if cur == null: return [{}, Vector3.ZERO]
	var s := cur.sample(clip_t, clip_mirror)
	if fade < 1.0 and prev_name != "":
		var pc: ClipLib.Clip = ClipLib.get_clip(prev_name)
		if pc != null:
			var ps := pc.sample(prev_t, prev_mirror)
			var mix := {}
			for kk in s[0]:
				mix[kk] = (ps[0][kk] as Quaternion).slerp(s[0][kk], fade) if ps[0].has(kk) else s[0][kk]
			s = [mix, (ps[1] as Vector3).lerp(s[1], fade)]
	return s


## Blend the clip's bone rotations into the desired globals; returns the blended hip position.
func _blend_clip(want: Dictionary, hip_pos: Vector3) -> Vector3:
	var s := _clip_sample()
	for hn in s[0]:
		if not bones.has(hn): continue
		var b: int = bones[hn]
		var target: Basis = (qi * Basis(s[0][hn]) * qb * rest_g[b].basis).orthonormalized()
		var from_q: Quaternion = Quaternion(want[b].orthonormalized()) if want.has(b) else rest_g[b].basis.get_rotation_quaternion()
		want[b] = Basis(from_q.slerp(Quaternion(target), clip_w))
	if not clip_hip:
		return hip_pos
	var hy: float = rest_g[bones.hips].origin.y
	var h: Vector3 = s[1]
	var clip_pos: Vector3 = rest_g[bones.hips].origin + qi * Vector3(h.x * hy if clip_pair else 0.0, h.y * hy, h.z * hy if clip_pair else 0.0)
	return hip_pos.lerp(clip_pos, clip_w)


## The head's real size and position (from the face mesh), in the head bone's rest frame, rig axes
## (+Y up, +Z front). Hair and beards are placed relative to this, so they fit every base model.
var skull := AABB(Vector3(-0.09, -0.02, -0.1), Vector3(0.18, 0.24, 0.2))


func _measure_skull() -> void:
	if not bones.has("head"): return
	var head_g: Transform3D = rest_g[bones.head]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var is_face := false
		for si in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(si)
			if m != null and "face" in String(m.resource_name).to_lower() and "skin" in String(m.resource_name).to_lower(): is_face = true
		if not is_face: continue
		# mesh AABB is in mesh space; walk up to the model (= skeleton space), then into the head
		# bone's frame in rig axes, the same space accessory offsets use (pos = origin + qi * off / k)
		var box: AABB = mi.get_aabb()
		var chain := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != model:
			if n is Node3D: chain = (n as Node3D).transform * chain
			n = n.get_parent()
		var pts := []
		for i in 8:
			var p: Vector3 = chain * box.get_endpoint(i)
			pts.append(qi.inverse() * (p - head_g.origin) * k)
		var out := AABB(pts[0], Vector3.ZERO)
		for p in pts: out = out.expand(p)
		skull = out
		return


## Match wear: bruising + a swelling eye, dusty and bloodied clothes.
func set_wear(bruise: float, dirt: float, blood: float) -> void:
	var w := Vector3(bruise, dirt, blood)
	if (w - wear).length() < 0.02: return
	wear = w
	for m in cloth_mats:
		m.set_shader_parameter("dirt", dirt)
		m.set_shader_parameter("blood", blood)
	if bones.has("head"):
		if bruise_mat == null:
			bruise_mat = StandardMaterial3D.new()
			bruise_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bruise_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bruise_mat.albedo_color = Color(0.42, 0.12, 0.32, 0.0)
			var front := skull.position.z + skull.size.z
			for spot in [[Vector3(-0.036, 0.062, front - 0.012), Vector3(0.03, 0.022, 0.012)], [Vector3(0.05, 0.02, front - 0.03), Vector3(0.024, 0.02, 0.012)]]:
				var mi := MeshInstance3D.new()
				mi.mesh = ToonRig.sph(1.0); mi.material_override = bruise_mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				accs.append({node = mi, b = bones.head, off = spot[0] * head_scale, basis = Basis.from_scale(spot[1] * head_scale)})
		bruise_mat.albedo_color.a = clampf(bruise - 0.15, 0.0, 1.0) * 0.6
	# the bruised eye swells shut a little as damage builds up
	var swell := clampf(bruise - 0.3, 0.0, 0.7) * 0.85
	if swell > 0.0:
		for pre in ["blinkRight", "blink_r", "blinkLeft"]:
			if expressions.has(pre):
				base_face[pre] = swell
				break
		set_face(face, true)


## World transform of a hand (for props held during intros).
func hand_xform(right := true) -> Transform3D:
	var hn := "rightHand" if right else "leftHand"
	if not bones.has(hn): return global_transform
	return skel.global_transform * skel.get_bone_global_pose(bones[hn])


func set_flash(v: float) -> void:
	for m in mats:
		m.set_shader_parameter("flash", v)


func set_glow(v: float) -> void:
	# Surge-ready glow: tint the rim light with the fighter's accent color.
	var strong := v > 1.0
	for m in mats:
		m.set_shader_parameter("rim_color", accent if strong else Color(0.75, 0.88, 1.0))
		m.set_shader_parameter("rim_amount", 0.25 + (v - 0.9) * 0.4 if strong else 0.18)


func set_face(name: String, force := false) -> void:
	if name == face and not force:
		return
	for e in expressions.values():
		for bind in e:
			bind[0].set_blend_shape_value(bind[1], 0.0)
	face = name
	# resting expression first, the moment's expression on top
	for pre in base_face:
		if expressions.has(pre) and pre != name:
			for bind in expressions[pre]:
				bind[0].set_blend_shape_value(bind[1], bind[2] * float(base_face[pre]))
	if expressions.has(name):
		for bind in expressions[name]:
			bind[0].set_blend_shape_value(bind[1], bind[2])
