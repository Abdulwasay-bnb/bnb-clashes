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
						if t.has("sheen"): m.set_shader_parameter("hair_sheen", float(t.sheen))   # fur
					else:
						col *= t
			m.set_shader_parameter("albedo", col)
			m.set_shader_parameter("tex", src.albedo_texture if src.albedo_texture else PlaceholderTexture2D.new())
			m.set_shader_parameter("shade", col.darkened(0.3).lerp(Color(0.55, 0.5, 0.75), 0.4) if src.albedo_texture == null else Color(0.66, 0.6, 0.8))
			if src.emission_enabled:
				m.set_shader_parameter("emission_strength", 0.6)
			var lname := name.to_lower()
			if "hair" in lname:
				m.set_shader_parameter("hair_sheen", 1.0)
				m.set_shader_parameter("sheen_color", col.lightened(0.6).lerp(Color(0.8, 0.86, 1.0), 0.6))
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
		"hair_ponytail", "hair_bob", "hair_bun", "hair_long", "hair_braid", "hair_silky":
			return _hair_parts(kind)
		# ---- garments (BNB Clashes): simple shapes on the bones, so modest outfits stay covered while fighting
		"hijab":
			return [["head", ToonRig.sph(0.128), Vector3(0, 0.078, -0.058), Vector3.ZERO, Vector3(1.0, 1.06, 1.0)],
				["head", tor.call(0.105, 0.02), Vector3(0, 0.05, 0.035), Vector3(PI / 2 + 0.2, 0, 0), Vector3(1.0, 1.25, 1.0)],
				["neck", ToonRig.cyl(0.085, 0.2, 0.2), Vector3(0, -0.02, -0.005), Vector3.ZERO, Vector3(1.0, 1.0, 0.85)]]
		"kameez":
			# a short skirt piece on the hips plus one long panel per thigh (a kameez has side slits),
			# so the hem moves with the legs instead of the knees poking through it
			# a closed A-line kameez from the waist to the knee, plus a slim layer of the same cloth fitted
			# on each thigh: complete when standing, and a lifted leg carries the cloth close instead of a wide tube
			return [["hips", ToonRig.cyl(0.165, 0.235, 0.44), Vector3(0, -0.17, -0.005), Vector3.ZERO, Vector3(1.0, 1.0, 0.88)],
				["leftUpperLeg", ToonRig.cyl(0.128, 0.135, 0.36), Vector3(0.01, -0.15, -0.01), Vector3.ZERO, Vector3.ONE],
				["rightUpperLeg", ToonRig.cyl(0.128, 0.135, 0.36), Vector3(-0.01, -0.15, -0.01), Vector3.ZERO, Vector3.ONE]]
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
			# hugs the jawline: two rows of small tufts rising toward the cheeks, plus a fuller chin
			var tufts: Array = []
			var jaw_y := skull.position.y + 0.014            # just above the chin
			var front := skull.position.z + skull.size.z
			var hw := skull.size.x / 2.0
			for row in 2:
				var n := 11 if row == 0 else 9
				for k in n:
					var a := (k - (n - 1) / 2.0) / ((n - 1) / 2.0) * 1.05
					var pos := Vector3(sin(a) * hw * (0.8 - row * 0.06), lerpf(jaw_y + 0.075, jaw_y + row * 0.014, cos(a)) , front - 0.018 - (1.0 - cos(a)) * 0.08 - row * 0.008)
					tufts.append(["head", ToonRig.sph(0.0125 - row * 0.002), pos, Vector3(0, a, 0), Vector3(1.5, 1.25, 0.42)])
			tufts.append(["head", ToonRig.sph(0.018), Vector3(0, jaw_y - 0.006, front - 0.012), Vector3(0.2, 0, 0), Vector3(1.35, 1.1, 0.55)])
			return tufts + _acc_parts("mustache")
		"mustache":
			# two tapering strokes from the middle out over the lip corners
			return [["head", ToonRig.sph(0.012), Vector3(0.012, 0.017, 0.104), Vector3(0, 0.25, -0.22), Vector3(1.7, 0.42, 0.45)],
				["head", ToonRig.sph(0.009), Vector3(0.027, 0.012, 0.099), Vector3(0, 0.5, -0.45), Vector3(1.5, 0.4, 0.45)],
				["head", ToonRig.sph(0.012), Vector3(-0.012, 0.017, 0.104), Vector3(0, -0.25, 0.22), Vector3(1.7, 0.42, 0.45)],
				["head", ToonRig.sph(0.009), Vector3(-0.027, 0.012, 0.099), Vector3(0, -0.5, 0.45), Vector3(1.5, 0.4, 0.45)]]
		"headphones":   # band over the top of the head, cups over the ears
			return [["head", tor.call(0.112, 0.008), Vector3(0, 0.075, -0.005), Vector3(PI / 2, 0, 0), Vector3(1.0, 1.0, 1.0)],
				["head", ToonRig.cyl(0.036, 0.036, 0.028), Vector3(0.1, 0.035, -0.005), Z90, Vector3.ONE],
				["head", ToonRig.cyl(0.036, 0.036, 0.028), Vector3(-0.1, 0.035, -0.005), Z90, Vector3.ONE]]
		"lanyard":      # BNB ID badge on a cord round the neck
			return [["upperChest", tor.call(0.085, 0.004), Vector3(0, 0.1, 0.03), Vector3(1.0, 0, 0), Vector3(1.0, 1.0, 1.3)],
				["upperChest", ToonRig.box(0.045, 0.065, 0.006), Vector3(0, -0.035, 0.125), Vector3(-0.15, 0, 0), Vector3.ONE]]
		"hood":         # a hoodie's hood bunched behind the neck
			return [["upperChest", tor.call(0.1, 0.035), Vector3(0, 0.16, -0.05), Vector3(0.5, 0, 0), Vector3(1.1, 1.0, 0.95)]]
		# ---- signature-outfit gear
		"cap_back":     # baseball cap worn backwards
			return [["head", ToonRig.sph(0.12), Vector3(0, 0.112, -0.012), Vector3(-0.15, 0, 0), Vector3(1.0, 0.56, 1.06)],
				["head", ToonRig.box(0.11, 0.008, 0.075), Vector3(0, 0.1, -0.14), Vector3(-0.25, 0, 0), Vector3.ONE]]
		"beanie":
			return [["head", ToonRig.sph(0.124), Vector3(0, 0.118, -0.012), Vector3(-0.1, 0, 0), Vector3(1.0, 0.72, 1.06)],
				["head", tor.call(0.118, 0.014), Vector3(0, 0.078, -0.01), Vector3(-0.12, 0, 0), Vector3(1.0, 1.0, 1.08)]]
		"bandana":      # headband with knot tails at the back
			return [["head", tor.call(0.118, 0.012), Vector3(0, 0.1, -0.008), Vector3(-0.2, 0, 0), Vector3(1, 1, 1.08)],
				["head", ToonRig.box(0.025, 0.09, 0.006), Vector3(0.02, 0.04, -0.13), Vector3(0.4, 0, 0.25), Vector3.ONE],
				["head", ToonRig.box(0.025, 0.08, 0.006), Vector3(-0.02, 0.045, -0.13), Vector3(0.35, 0, -0.3), Vector3.ONE]]
		"shades":       # sunglasses
			return [["head", ToonRig.box(0.046, 0.022, 0.006), Vector3(0.034, 0.072, 0.111), Vector3.ZERO, Vector3.ONE],
				["head", ToonRig.box(0.046, 0.022, 0.006), Vector3(-0.034, 0.072, 0.111), Vector3.ZERO, Vector3.ONE],
				["head", ToonRig.box(0.024, 0.005, 0.005), Vector3(0, 0.077, 0.112), Vector3.ZERO, Vector3.ONE],
				["head", ToonRig.box(0.005, 0.005, 0.1), Vector3(0.066, 0.074, 0.062), Vector3.ZERO, Vector3.ONE],
				["head", ToonRig.box(0.005, 0.005, 0.1), Vector3(-0.066, 0.074, 0.062), Vector3.ZERO, Vector3.ONE]]
		"scarf":
			return [["upperChest", tor.call(0.1, 0.03), Vector3(0, 0.135, 0.005), Vector3(0.15, 0, 0), Vector3(1.05, 1.0, 0.92)],
				["upperChest", ToonRig.box(0.06, 0.24, 0.016), Vector3(0.06, -0.03, 0.125), Vector3(0.05, 0, 0.05), Vector3.ONE]]
		"cape":         # drapes from the shoulders: a collar and upper panel on the back, the rest hangs from the hips
			return [["upperChest", tor.call(0.11, 0.022), Vector3(0, 0.13, -0.02), Vector3(0.35, 0, 0), Vector3(1.15, 1.0, 0.85)],
				["upperChest", ToonRig.sph(0.022), Vector3(0.075, 0.12, 0.085), Vector3.ZERO, Vector3.ONE],
				["upperChest", ToonRig.sph(0.022), Vector3(-0.075, 0.12, 0.085), Vector3.ZERO, Vector3.ONE],
				["upperChest", ToonRig.box(0.36, 0.36, 0.016), Vector3(0, -0.07, -0.135), Vector3(0.05, 0, 0), Vector3.ONE],
				["hips", ToonRig.box(0.4, 0.62, 0.016), Vector3(0, -0.16, -0.17), Vector3(0.06, 0, 0), Vector3.ONE],
				["hips", ToonRig.box(0.12, 0.6, 0.016), Vector3(0.2, -0.15, -0.13), Vector3(0.06, -0.5, 0), Vector3.ONE],
				["hips", ToonRig.box(0.12, 0.6, 0.016), Vector3(-0.2, -0.15, -0.13), Vector3(0.06, 0.5, 0), Vector3.ONE]]
		"coat":         # long coat tails below the jacket
			return [["hips", ToonRig.box(0.36, 0.5, 0.03), Vector3(0, -0.2, -0.12), Vector3(0.08, 0, 0), Vector3.ONE],
				["hips", ToonRig.box(0.15, 0.48, 0.03), Vector3(0.1, -0.19, 0.12), Vector3(-0.08, 0, 0.04), Vector3.ONE],
				["hips", ToonRig.box(0.15, 0.48, 0.03), Vector3(-0.1, -0.19, 0.12), Vector3(-0.08, 0, -0.04), Vector3.ONE]]
		"apron":
			return [["hips", ToonRig.box(0.3, 0.44, 0.012), Vector3(0, -0.13, 0.135), Vector3(-0.05, 0, 0), Vector3.ONE],
				["upperChest", ToonRig.box(0.22, 0.2, 0.012), Vector3(0, -0.03, 0.125), Vector3.ZERO, Vector3.ONE]]
		"chain":        # gold chain round the neck
			return [["upperChest", tor.call(0.09, 0.006), Vector3(0, 0.07, 0.04), Vector3(1.15, 0, 0), Vector3(1.0, 1.0, 1.25)]]
		"bowtie":
			return [["upperChest", ToonRig.sph(0.02), Vector3(0.02, 0.125, 0.105), Vector3(0, 0, 0.3), Vector3(1.2, 0.8, 0.5)],
				["upperChest", ToonRig.sph(0.02), Vector3(-0.02, 0.125, 0.105), Vector3(0, 0, -0.3), Vector3(1.2, 0.8, 0.5)],
				["upperChest", ToonRig.sph(0.01), Vector3(0, 0.125, 0.11), Vector3.ZERO, Vector3.ONE]]
		"backpack":
			return [["upperChest", ToonRig.box(0.26, 0.32, 0.12), Vector3(0, -0.07, -0.17), Vector3(0.08, 0, 0), Vector3.ONE],
				["upperChest", ToonRig.box(0.2, 0.1, 0.05), Vector3(0, -0.17, -0.245), Vector3(0.08, 0, 0), Vector3.ONE]]
		"pads":         # cricket leg pads
			return [["leftLowerLeg", ToonRig.box(0.13, 0.42, 0.06), Vector3(0, -0.17, 0.07), Vector3.ZERO, Vector3.ONE],
				["rightLowerLeg", ToonRig.box(0.13, 0.42, 0.06), Vector3(0, -0.17, 0.07), Vector3.ZERO, Vector3.ONE]]
		"watch":
			return [["leftLowerArm", ToonRig.cyl(0.033, 0.033, 0.03), Vector3(0.21, 0, 0), Z90, Vector3.ONE],
				["leftLowerArm", ToonRig.box(0.024, 0.008, 0.024), Vector3(0.21, 0.034, 0), Vector3.ZERO, Vector3.ONE]]
		# ---- G.O.A.T. form: an anime goat head built round the measured skull (it encloses the human head)
		"goat_head", "goat_horns", "goat_nose", "goat_eyes", "goat_pupils":
			return _goat_parts(kind)
		"kig_hood", "suit_body", "vape_body", "vape_tank", "vape_screen", "vape_button", "vape_tip", "vape_cloud", "vape_trim", "tail", "banana_tip", "banana_body", "banana_ridges", "banana_end", "phone_body", "phone_screen", "app0", "app1", "app2", "app3", "phone_cam", "phone_back", "cig_body", "cig_filter", "cig_band", "cig_ash", "cig_ember", "cig_smoke", "waistcoat", "gamcha", "gamcha_check", "suit_arms", "suit_legs", "suit_paws", "lion_mane", "ears_round", "tail_tuft", "bull_horns", "bull_snout", "nose_ring", "ears_side", "wool_head", "wool_body", "ram_horns", "snake_hood", "snake_eyes", "snake_fangs", "snake_tail", "banana_peel", "banana_stem", "bun_top", "sesame", "lettuce", "cheese", "patty", "bun_bottom", "smoke_body", "smoke_head", "cricket_helmet", "helmet_grille", "batting_gloves", "cricket_bat", "thigh_pad", "beret", "palette", "dab0", "dab1", "dab2", "dab3", "dab4", "dab5", "paint_brush":
			return _mascot_parts(kind)
		"fur_arms":     # shaggy fur over the forearms and the backs of the hands
			return [["leftLowerArm", ToonRig.cyl(0.05, 0.042, 0.25), Vector3(0.12, 0, 0), Z90, Vector3.ONE],
				["rightLowerArm", ToonRig.cyl(0.05, 0.042, 0.25), Vector3(-0.12, 0, 0), Z90, Vector3.ONE],
				["leftUpperArm", ToonRig.cyl(0.054, 0.05, 0.14), Vector3(0.2, 0, 0), Z90, Vector3.ONE],
				["rightUpperArm", ToonRig.cyl(0.054, 0.05, 0.14), Vector3(-0.2, 0, 0), Z90, Vector3.ONE],
				["leftHand", ToonRig.sph(0.05), Vector3(0.045, 0.012, 0), Vector3.ZERO, Vector3(1.2, 0.6, 1.0)],
				["rightHand", ToonRig.sph(0.05), Vector3(-0.045, 0.012, 0), Vector3.ZERO, Vector3(1.2, 0.6, 1.0)]]
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
	if kind in ["hair_ponytail", "hair_bun", "hair_long", "hair_braid", "hair_silky"]:
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
			# nape: layered flicks hanging down the back of the neck
			for k in 5:
				var a := (k - 2) * 0.32
				out.append(cone.call(0.032, 0.12, at.call(sin(a) * 0.08, -0.2, -0.2 + absf(sin(a)) * 0.04), Vector3(PI - 0.35, a * 0.6, 0)))
			# top: shaggy layers lying back over the crown (low, not standing up)
			for k in 5:
				var a := (k - 2) * 0.42
				out.append(blob.call(at.call(sin(a) * 0.06, -0.012, -0.1 + cos(a) * 0.02), 0.032, 0.016, 0.06, Vector3(0.3, a * 0.5, 0)))
			# sides: flicks hanging down past the ears
			for sx in [-1.0, 1.0]:
				out.append(cone.call(0.028, 0.09, at.call(sx * 0.108, -0.13, -0.1), Vector3(PI, 0, sx * 0.25)))
		"hair_curl":   # styled back, with low flat waves along the front hairline (nothing piled on top)
			for k in 5:
				var a := (k - 2) * 0.42
				out.append(blob.call(at.call(sin(a) * 0.07, -0.022, -0.06 + cos(a) * 0.012), 0.03, 0.014, 0.026, Vector3(0.5, a * 0.5, 0)))
		"hair_messy":  # relaxed and unbrushed
			for k in 7:
				var a := k * 0.9
				out.append(cone.call(0.032, 0.075, at.call(sin(a) * 0.065, 0.008, -0.09 + cos(a) * 0.05), Vector3(sin(a) * 0.8, 0, cos(a) * 0.8)))
		"hair_spiky":  # comic spikes
			# a crown of short spikes swept up and back (not a hat of cones)
			for k in 11:
				var a := (k - 5) * 0.24
				var row := k % 2
				out.append(cone.call(0.024, 0.06 - absf(a) * 0.015, at.call(sin(a) * 0.065, -0.004 - row * 0.012, -0.11 - row * 0.05 + absf(a) * 0.01), Vector3(-1.05 - row * 0.3, 0, a * 0.5)))
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
		"hair_silky":  # long, loose and silky: full crown, centre part, straight curtain down the back, framing the face
			cap = blob.call(at.call(0, -0.058, -0.158), 0.128, 0.112, 0.138)   # front edge stays a hairline above the face
			out = [cap, blob.call(at.call(0, -0.12, -0.21), 0.122, 0.11, 0.09)]
			for sx in [-1.0, 1.0]:
				# soft parted bangs sweeping to each side
				out.append(blob.call(at.call(sx * 0.05, -0.022, -0.05), 0.065, 0.026, 0.045, Vector3(0.4, 0, sx * -0.35)))
				# side curtains past the cheeks to the collarbone
				out.append(blob.call(at.call(sx * 0.115, -0.25, -0.1), 0.03, 0.2, 0.05, Vector3(0.05, 0, sx * 0.06)))
				out.append(blob.call(at.call(sx * 0.12, -0.27, -0.15), 0.03, 0.21, 0.045, Vector3(0.05, 0, sx * 0.08)))
			# the long straight back, tapering at the ends
			for k in 7:   # loose strands side by side, falling straight down the back, ends a little uneven
				var u := (k - 3) / 3.0
				var ln := 0.27 - absf(u) * 0.05 + (0.015 if k % 2 == 0 else 0.0)
				out.append(blob.call(at.call(u * 0.1, -0.2 - ln, -0.215 - (1.0 - absf(u)) * 0.025 + absf(u) * 0.03), 0.034, ln, 0.03, Vector3(0.08, 0, -u * 0.08)))
		"hair_braid":  # side braid over the shoulder
			out += [cap, back]
			for k in 6:
				out.append(blob.call(at.call(0.095 + k * 0.006, -0.18 - k * 0.055, -0.09 + k * 0.012), 0.032, 0.04, 0.032))
	return out


## A point along a mascot tail (hips space), t from base (0) to tip (1).
static func _tail_pt(t: float) -> Vector3:
	return Vector3(0.05 * sin(t * 3.0), -0.04 - 0.42 * t + 0.3 * t * t, -0.14 - 0.2 * t - 0.06 * t * t)


## Full-body mascot suits (kigurumi style: the face shows through the hood) and props worn with them.
func _mascot_parts(kind: String) -> Array:
	var H := "head"
	var c: Vector3 = skull.position + skull.size / 2.0
	var r: float = skull.size.x / 2.0
	var front: float = skull.position.z + skull.size.z
	var top: float = skull.position.y + skull.size.y
	var Z90 := Vector3(0, 0, PI / 2)
	var S := func(bone: String, pos: Vector3, sx: float, sy: float, sz: float, rot := Vector3.ZERO) -> Array:
		return [bone, ToonRig.sph(1.0), pos, rot, Vector3(sx, sy, sz)]
	var tor := func(rr: float, th: float) -> TorusMesh:
		var t := TorusMesh.new(); t.inner_radius = rr - th; t.outer_radius = rr + th; t.rings = 28; t.ring_segments = 10
		return t
	var rng := RandomNumberGenerator.new(); rng.seed = hash(kind)
	match kind:
		# ---- the suit itself
		"kig_hood":     # covers the top, sides and back of the head; the face shows through the round opening
			var zr: float = front - c.z - 0.005
			return [S.call(H, Vector3(c.x, c.y + 0.03, c.z - 0.055), r * 1.26, skull.size.y * 0.64, zr),
				S.call(H, Vector3(c.x, c.y + 0.02, c.z - 0.1), r * 1.22, skull.size.y * 0.62, r * 1.05),   # the back of the hood
				[H, tor.call(r * 1.02, 0.018), Vector3(0, c.y - 0.0, front - 0.06), Vector3(PI / 2, 0, 0), Vector3(1.0, 1.0, 1.2)]]
		"suit_body":
			return [S.call("upperChest", Vector3(0, -0.01, 0.0), 0.2, 0.2, 0.155), S.call("chest", Vector3(0, 0, 0.01), 0.185, 0.16, 0.15),
				S.call("hips", Vector3(0, 0.02, 0.0), 0.185, 0.15, 0.15)]
		"suit_arms":
			return [["leftUpperArm", ToonRig.cyl(0.066, 0.06, 0.29), Vector3(0.13, 0, 0), Z90, Vector3.ONE],
				["rightUpperArm", ToonRig.cyl(0.066, 0.06, 0.29), Vector3(-0.13, 0, 0), Z90, Vector3.ONE],
				["leftLowerArm", ToonRig.cyl(0.058, 0.05, 0.25), Vector3(0.12, 0, 0), Z90, Vector3.ONE],
				["rightLowerArm", ToonRig.cyl(0.058, 0.05, 0.25), Vector3(-0.12, 0, 0), Z90, Vector3.ONE]]
		"suit_legs":
			return [["leftUpperLeg", ToonRig.cyl(0.105, 0.088, 0.45), Vector3(0, -0.21, 0), Vector3.ZERO, Vector3.ONE],
				["rightUpperLeg", ToonRig.cyl(0.105, 0.088, 0.45), Vector3(0, -0.21, 0), Vector3.ZERO, Vector3.ONE],
				["leftLowerLeg", ToonRig.cyl(0.088, 0.072, 0.42), Vector3(0, -0.2, 0), Vector3.ZERO, Vector3.ONE],
				["rightLowerLeg", ToonRig.cyl(0.088, 0.072, 0.42), Vector3(0, -0.2, 0), Vector3.ZERO, Vector3.ONE]]
		"suit_paws":
			return [S.call("leftHand", Vector3(0.05, 0, 0), 0.06, 0.045, 0.055), S.call("rightHand", Vector3(-0.05, 0, 0), 0.06, 0.045, 0.055),
				S.call("leftFoot", Vector3(0, -0.02, 0.05), 0.065, 0.05, 0.12), S.call("rightFoot", Vector3(0, -0.02, 0.05), 0.065, 0.05, 0.12)]
		"tail":         # hangs from the base of the back, sways down and curls up at the end
			var out := []
			for k in 12:
				var t := k / 11.0
				out.append(S.call("hips", _tail_pt(t), 0.034 - t * 0.01, 0.034 - t * 0.01, 0.034 - t * 0.01))
			return out
		"tail_tuft":    # the tassel on the tail's end
			var e := _tail_pt(1.0)
			return [S.call("hips", e + Vector3(0, 0.03, -0.015), 0.045, 0.06, 0.045, Vector3(0.5, 0, 0)),
				S.call("hips", e + Vector3(0, 0.07, -0.03), 0.03, 0.04, 0.03, Vector3(0.5, 0, 0))]
		# ---- banana: a long curved yellow fruit from the head down to the thighs, brown tip on top
		"banana_tip":   # the hood rises into the banana's narrow top, leaning forward
			return [[H, ToonRig.cyl(0.035, r * 1.12, 0.2), Vector3(0, top + 0.06, c.z - 0.04), Vector3(0.22, 0, 0), Vector3(1.0, 1.0, 0.92)]]
		"banana_end":   # brown stalk at the top and the dark tip at the bottom
			return [[H, ToonRig.cyl(0.02, 0.03, 0.07), Vector3(0, top + 0.19, c.z + 0.0), Vector3(0.3, 0, 0), Vector3.ONE],
				S.call("hips", Vector3(0, -0.5, 0.06), 0.06, 0.045, 0.055)]
		"banana_body":  # one long smooth curved fruit: chest piece and hip piece overlap into a gentle bend
			var cap1 := CapsuleMesh.new(); cap1.radius = 0.25; cap1.height = 0.66
			var cap2 := CapsuleMesh.new(); cap2.radius = 0.23; cap2.height = 0.62
			return [["chest", cap1, Vector3(0, -0.07, -0.01), Vector3(-0.06, 0, 0), Vector3(1.0, 1.0, 0.85)],
				["hips", cap2, Vector3(0, -0.2, 0.03), Vector3(0.14, 0, 0), Vector3(1.0, 1.0, 0.85)]]
		"banana_ridges":   # the darker ridges running down a banana's sides
			var out := []
			for sx in [-1.0, 1.0]:
				out.append(["chest", ToonRig.box(0.012, 0.5, 0.012), Vector3(sx * 0.16, 0.0, 0.165), Vector3(-0.06, 0, 0), Vector3.ONE])
				out.append(["hips", ToonRig.box(0.012, 0.42, 0.012), Vector3(sx * 0.15, -0.2, 0.17), Vector3(0.14, 0, 0), Vector3.ONE])
			return out
		# ---- mobile phone: a big phone around the body, head out through the top
		"phone_body":
			return [["chest", ToonRig.box(0.5, 0.72, 0.3), Vector3(0, -0.17, 0.01), Vector3.ZERO, Vector3.ONE]]
		"phone_screen":
			return [["chest", ToonRig.box(0.44, 0.6, 0.01), Vector3(0, -0.17, 0.162), Vector3.ZERO, Vector3.ONE]]
		"app0", "app1", "app2", "app3":   # a column of app icons each
			var i := int(kind.substr(3))
			var out := []
			for row in 4:
				out.append(["chest", ToonRig.box(0.07, 0.07, 0.008), Vector3(-0.15 + i * 0.1, 0.03 - row * 0.1, 0.168), Vector3.ZERO, Vector3.ONE])
			return out
		"phone_cam":    # front camera, speaker and home bar
			return [["chest", ToonRig.box(0.08, 0.014, 0.006), Vector3(0, 0.1, 0.168), Vector3.ZERO, Vector3.ONE],
				S.call("chest", Vector3(0.07, 0.1, 0.168), 0.012, 0.012, 0.004),
				["chest", ToonRig.box(0.12, 0.012, 0.006), Vector3(0, -0.43, 0.168), Vector3.ZERO, Vector3.ONE],
			]
		"phone_back":   # rear camera block with three lenses
			return [["chest", ToonRig.box(0.16, 0.16, 0.02), Vector3(-0.12, 0.06, -0.16), Vector3.ZERO, Vector3.ONE],
				S.call("chest", Vector3(-0.09, 0.09, -0.172), 0.03, 0.03, 0.01), S.call("chest", Vector3(-0.15, 0.09, -0.172), 0.03, 0.03, 0.01),
				S.call("chest", Vector3(-0.09, 0.03, -0.172), 0.03, 0.03, 0.01)]
		# ---- vape: a box-mod vape around the body, glowing tank and screen, drip tip on the hood, big clouds
		"vape_body":
			return [["chest", ToonRig.box(0.46, 0.74, 0.3), Vector3(0, -0.16, 0.01), Vector3.ZERO, Vector3.ONE],
				S.call("chest", Vector3(0, 0.21, 0.01), 0.23, 0.04, 0.15), S.call("chest", Vector3(0, -0.53, 0.01), 0.23, 0.04, 0.15)]   # rounded ends
		"vape_trim":    # metal edges down the sides
			return [["chest", ToonRig.box(0.02, 0.74, 0.31), Vector3(0.23, -0.16, 0.01), Vector3.ZERO, Vector3.ONE],
				["chest", ToonRig.box(0.02, 0.74, 0.31), Vector3(-0.23, -0.16, 0.01), Vector3.ZERO, Vector3.ONE]]
		"vape_tank":    # the e-liquid window across the top of the front
			return [["chest", ToonRig.box(0.34, 0.16, 0.012), Vector3(0, 0.08, 0.163), Vector3.ZERO, Vector3.ONE]]
		"vape_screen":  # little OLED readout
			return [["chest", ToonRig.box(0.16, 0.07, 0.01), Vector3(0, -0.13, 0.164), Vector3.ZERO, Vector3.ONE]]
		"vape_button":  # fire button and the two adjust buttons
			return [[ "chest", ToonRig.cyl(0.04, 0.04, 0.02), Vector3(0, -0.28, 0.165), Vector3(PI / 2, 0, 0), Vector3.ONE],
				["chest", ToonRig.box(0.05, 0.025, 0.012), Vector3(-0.045, -0.37, 0.164), Vector3.ZERO, Vector3.ONE],
				["chest", ToonRig.box(0.05, 0.025, 0.012), Vector3(0.045, -0.37, 0.164), Vector3.ZERO, Vector3.ONE]]
		"vape_tip":     # drip tip on top of the hood
			return [[H, ToonRig.cyl(r * 0.55, r * 0.7, 0.05), Vector3(0, top + 0.01, c.z - 0.03), Vector3.ZERO, Vector3.ONE],
				[H, ToonRig.cyl(0.03, 0.04, 0.09), Vector3(0, top + 0.08, c.z - 0.03), Vector3.ZERO, Vector3.ONE]]
		"vape_cloud":   # big billowing vapour clouds over the head and round the shoulders
			var out := []
			for k in 9:
				var a := TAU * k / 9.0
				var rr := 0.06 + (k % 3) * 0.015
				out.append(S.call(H, Vector3(cos(a) * 0.11, top + 0.17 + sin(a * 2.0) * 0.03 + (k % 2) * 0.04, c.z - 0.03 + sin(a) * 0.09), rr, rr * 0.8, rr))
			for k in 3:
				out.append(S.call(H, Vector3((k - 1) * 0.07, top + 0.27 + (k % 2) * 0.03, c.z - 0.04), 0.07, 0.055, 0.07))
			for sx in [-1.0, 1.0]:
				out.append(S.call("upperChest", Vector3(sx * 0.27, 0.16, -0.03), 0.08, 0.06, 0.08))
				out.append(S.call("upperChest", Vector3(sx * 0.32, 0.1, 0.03), 0.06, 0.05, 0.06))
			return out
		# ---- cigarette: white paper tube, orange filter at the bottom, glowing tip on the head
		"cig_body":
			return [["chest", ToonRig.cyl(0.215, 0.215, 0.62), Vector3(0, 0.0, 0.01), Vector3.ZERO, Vector3.ONE]]
		"cig_filter":
			return [["hips", ToonRig.cyl(0.218, 0.218, 0.34), Vector3(0, -0.12, 0.01), Vector3.ZERO, Vector3.ONE]]
		"cig_band":
			return [["hips", ToonRig.cyl(0.222, 0.222, 0.02), Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3.ONE]]
		"cig_ash":      # grey ash ring round the top of the hood
			return [[H, ToonRig.cyl(r * 1.05, r * 1.15, 0.05), Vector3(0, top + 0.015, c.z - 0.03), Vector3.ZERO, Vector3.ONE]]
		"cig_ember":
			return [[H, ToonRig.cyl(r * 0.8, r * 1.0, 0.03), Vector3(0, top + 0.05, c.z - 0.03), Vector3.ZERO, Vector3.ONE]]
		"cig_smoke":    # a wisp rising off the tip
			var out := []
			for k in 6:
				out.append(S.call(H, Vector3(sin(k * 1.3) * 0.04, top + 0.1 + k * 0.06, c.z - 0.03 - k * 0.01), 0.035 + k * 0.006, 0.03, 0.035 + k * 0.006))
			return out
		# ---- chai wala
		"waistcoat":    # open-front waistcoat over the kurta
			var out := []
			for sx in [-1.0, 1.0]:
				out.append(["upperChest", ToonRig.box(0.13, 0.24, 0.02), Vector3(sx * 0.09, -0.02, 0.13), Vector3(0, sx * 0.15, 0), Vector3.ONE])
				out.append(["chest", ToonRig.box(0.12, 0.2, 0.02), Vector3(sx * 0.085, -0.06, 0.135), Vector3(0, sx * 0.15, 0), Vector3.ONE])
			out.append(["upperChest", ToonRig.box(0.32, 0.26, 0.02), Vector3(0, -0.02, -0.13), Vector3.ZERO, Vector3.ONE])
			out.append(["chest", ToonRig.box(0.3, 0.22, 0.02), Vector3(0, -0.06, -0.13), Vector3.ZERO, Vector3.ONE])
			return out
		"gamcha":       # checked cotton towel over the left shoulder
			return [["upperChest", ToonRig.box(0.09, 0.012, 0.3), Vector3(0.12, 0.14, 0.0), Vector3.ZERO, Vector3.ONE],
				["upperChest", ToonRig.box(0.09, 0.26, 0.012), Vector3(0.12, 0.02, 0.15), Vector3(0.1, 0, 0), Vector3.ONE],
				["upperChest", ToonRig.box(0.09, 0.3, 0.012), Vector3(0.12, 0.0, -0.15), Vector3(-0.1, 0, 0), Vector3.ONE]]
		"gamcha_check":   # the towel's checks
			var out := []
			for k in 3:
				out.append(["upperChest", ToonRig.box(0.094, 0.018, 0.016), Vector3(0.12, 0.1 - k * 0.08, 0.152), Vector3(0.1, 0, 0), Vector3.ONE])
			out.append(["upperChest", ToonRig.box(0.02, 0.26, 0.016), Vector3(0.12, 0.02, 0.153), Vector3(0.1, 0, 0), Vector3.ONE])
			return out
		"ears_round":
			return [S.call(H, Vector3(r * 0.85, top - 0.005, c.z - 0.02), 0.045, 0.045, 0.02), S.call(H, Vector3(-r * 0.85, top - 0.005, c.z - 0.02), 0.045, 0.045, 0.02)]
		"ears_side":
			return [S.call(H, Vector3(r * 1.3, c.y + 0.03, c.z - 0.02), 0.07, 0.022, 0.032, Vector3(0, 0, -0.35)),
				S.call(H, Vector3(-r * 1.3, c.y + 0.03, c.z - 0.02), 0.07, 0.022, 0.032, Vector3(0, 0, 0.35))]
		# ---- lion
		"lion_mane":    # a big shaggy mane all round the face
			var out := [[H, tor.call(r * 1.15, 0.05), Vector3(0, c.y - 0.01, front - 0.04), Vector3(PI / 2, 0, 0), Vector3(1.05, 1.0, 1.0)]]
			for k in 14:
				var a := TAU * k / 14.0
				out.append(S.call(H, Vector3(cos(a) * r * 1.45, c.y - 0.01 + sin(a) * r * 1.45, front - 0.07), 0.05, 0.05, 0.045))
			out.append(S.call("upperChest", Vector3(0, 0.1, 0.07), 0.13, 0.08, 0.06))   # mane spilling onto the chest
			return out
		# ---- bull
		"bull_horns":   # out to the sides, then curving up
			var out := []
			for sx in [-1.0, 1.0]:
				out.append([H, ToonRig.cyl(0.022, 0.03, 0.11), Vector3(sx * (r + 0.06), top - 0.02, c.z), Vector3(0, 0, sx * -1.35), Vector3.ONE])
				out.append([H, ToonRig.cyl(0.0, 0.022, 0.09), Vector3(sx * (r + 0.12), top + 0.03, c.z), Vector3(0, 0, sx * -0.35), Vector3.ONE])
			return out
		"bull_snout":   # the hood's snout over the forehead
			return [S.call(H, Vector3(0, top - 0.02, front - 0.005), 0.065, 0.04, 0.045, Vector3(0.3, 0, 0))]
		"nose_ring":
			return [[H, tor.call(0.022, 0.004), Vector3(0, top - 0.06, front + 0.03), Vector3(0.2, 0, 0), Vector3.ONE]]
		# ---- sheep
		"wool_head":    # a cloud of wool puffs over the hood
			var out := []
			for k in 16:
				var a := TAU * k / 16.0
				out.append(S.call(H, c + Vector3(cos(a) * r * 1.15, 0.03 + absf(sin(a)) * r * 0.9, -0.03 + sin(a) * r * 0.2), 0.045, 0.045, 0.045))
			for k in 6:
				out.append(S.call(H, c + Vector3(rng.randf_range(-0.07, 0.07), r * 1.12, rng.randf_range(-0.09, 0.03)), 0.05, 0.04, 0.05))
			return out
		"wool_body":
			var out := []
			for k in 22:
				var bone: String = ["upperChest", "chest", "hips"][k % 3]
				var a := TAU * k / 22.0 * 3.0
				out.append(S.call(bone, Vector3(cos(a) * 0.17, rng.randf_range(-0.07, 0.08), sin(a) * 0.13), 0.06, 0.055, 0.06))
			return out
		"ram_horns":    # curled horns beside the head
			var out := []
			for sx in [-1.0, 1.0]:
				out.append([H, tor.call(0.04, 0.014), Vector3(sx * (r + 0.03), c.y + 0.02, c.z - 0.01), Vector3(0, PI / 2, 0), Vector3.ONE])
			return out
		# ---- snake
		"snake_hood":   # a cobra's hood flaring behind the head
			return [S.call(H, Vector3(0, c.y - 0.01, c.z - 0.09), r * 1.9, r * 1.55, 0.03, Vector3(0.1, 0, 0))]
		"snake_eyes":
			return [S.call(H, Vector3(0.04, top + 0.008, front - 0.05), 0.022, 0.018, 0.02), S.call(H, Vector3(-0.04, top + 0.008, front - 0.05), 0.022, 0.018, 0.02)]
		"snake_fangs":
			return [[H, ToonRig.cyl(0.0, 0.008, 0.03), Vector3(0.025, c.y + 0.075, front + 0.012), Vector3(PI, 0, 0), Vector3.ONE],
				[H, ToonRig.cyl(0.0, 0.008, 0.03), Vector3(-0.025, c.y + 0.075, front + 0.012), Vector3(PI, 0, 0), Vector3.ONE]]
		"snake_tail":   # tapering coils trailing behind
			var out := []
			for k in 7:
				var rr := 0.07 - k * 0.008
				out.append(S.call("hips", Vector3(sin(k * 0.9) * 0.08, -0.12 - k * 0.07, -0.18 - k * 0.07), rr, rr, rr * 1.3))
			return out
		# ---- banana
		"banana_peel":  # peel flaps hanging from the top of the head
			var out := []
			for a in [0.15, PI - 0.15, -PI / 2, -PI / 4, -3.0 * PI / 4]:   # sides and back only: the face stays clear
				var d := Vector3(cos(a), 0, sin(a))
				var yaw := atan2(d.x, d.z)
				out.append([H, ToonRig.box(0.08, 0.22, 0.014), c + Vector3(0, r * 0.75, -0.04) + d * (r * 1.25),
					Vector3(-0.5, yaw, 0), Vector3.ONE])   # bottoms splay outward
			return out
		"banana_stem":
			return [[H, ToonRig.cyl(0.014, 0.02, 0.07), Vector3(0, top + 0.06, c.z - 0.01), Vector3(0.3, 0, 0), Vector3.ONE]]
		# ---- burger
		"bun_top":      # a big sesame bun for a hat
			return [S.call(H, Vector3(0, top + 0.02, c.z - 0.01), r * 1.45, r * 0.75, r * 1.45)]
		"sesame":
			var out := []
			for k in 12:
				var a := rng.randf() * TAU
				var rr := rng.randf_range(0.0, r * 0.95)
				var y := top + 0.02 + r * 0.75 * sqrt(maxf(0.0, 1.0 - pow(rr / (r * 1.45), 2.0)))
				out.append(S.call(H, Vector3(cos(a) * rr, y, c.z - 0.01 + sin(a) * rr), 0.01, 0.004, 0.006, Vector3(0, a, 0)))
			return out
		"lettuce":      # frilly green collar
			var out := [["upperChest", tor.call(0.17, 0.03), Vector3(0, 0.13, 0), Vector3(0.1, 0, 0), Vector3(1.1, 1.0, 0.95)]]
			for k in 12:
				var a := TAU * k / 12.0
				out.append(S.call("upperChest", Vector3(cos(a) * 0.19, 0.11, sin(a) * 0.17), 0.045, 0.02, 0.04, Vector3(0, -a, 0.4)))
			return out
		"cheese":       # a cheese slice drooping over the chest and back
			return [["chest", ToonRig.box(0.42, 0.012, 0.36), Vector3(0, 0.1, 0.0), Vector3(0, PI / 4, 0), Vector3.ONE],
				["chest", ToonRig.box(0.06, 0.12, 0.012), Vector3(0.12, 0.04, 0.17), Vector3(0, 0, 0), Vector3.ONE],
				["chest", ToonRig.box(0.05, 0.09, 0.012), Vector3(-0.1, 0.05, 0.17), Vector3(0, 0, 0), Vector3.ONE]]
		"patty":
			return [["hips", tor.call(0.2, 0.05), Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1.05, 1.0, 0.9)]]
		"bun_bottom":
			return [["hips", tor.call(0.2, 0.055), Vector3(0, -0.01, 0), Vector3.ZERO, Vector3(1.05, 1.0, 0.9)]]
		# ---- smoke
		"smoke_body":   # drifting smoke round the shoulders, waist and legs
			var out := []
			for k in 24:
				var bone: String = ["upperChest", "hips", "leftUpperLeg", "rightUpperLeg", "leftUpperArm", "rightUpperArm"][k % 6]
				var rr := rng.randf_range(0.05, 0.09)
				out.append(S.call(bone, Vector3(rng.randf_range(-0.16, 0.16), rng.randf_range(-0.15, 0.1), rng.randf_range(-0.16, 0.12)), rr, rr * 0.85, rr))
			return out
		"smoke_head":
			var out := []
			for k in 9:
				var a := TAU * k / 9.0
				out.append(S.call(H, c + Vector3(cos(a) * r * 1.1, r * 0.95 + absf(sin(a * 2.0)) * 0.03, sin(a) * r * 0.9 - 0.03), 0.05, 0.045, 0.05))
			return out
		# ---- cricket
		"cricket_helmet":
			return [S.call(H, Vector3(c.x, c.y + 0.04, c.z - 0.04), r * 1.2, skull.size.y * 0.58, front - c.z + 0.03),
				[H, ToonRig.box(r * 1.9, 0.01, 0.07), Vector3(0, top - 0.035, front + 0.02), Vector3(-0.15, 0, 0), Vector3.ONE]]   # peak
		"helmet_grille":   # face guard: three horizontal bars below the peak and a centre stay
			var out := []
			for k in 3:
				out.append([H, ToonRig.cyl(0.005, 0.005, r * 1.7), Vector3(0, c.y - 0.01 - k * 0.032, front + 0.03 - k * 0.004), Vector3(0, 0, PI / 2), Vector3.ONE])
			out.append([H, ToonRig.box(0.006, 0.075, 0.006), Vector3(0, c.y - 0.042, front + 0.032), Vector3.ZERO, Vector3.ONE])
			for sx in [-1.0, 1.0]:
				out.append([H, ToonRig.box(0.006, 0.08, 0.05), Vector3(sx * r * 0.85, c.y - 0.04, front + 0.0), Vector3.ZERO, Vector3.ONE])
			return out
		"batting_gloves":
			return [S.call("leftHand", Vector3(0.045, 0, 0), 0.06, 0.045, 0.055), S.call("rightHand", Vector3(-0.045, 0, 0), 0.06, 0.045, 0.055),
				["leftLowerArm", ToonRig.cyl(0.045, 0.045, 0.06), Vector3(0.21, 0, 0), Z90, Vector3.ONE],
				["rightLowerArm", ToonRig.cyl(0.045, 0.045, 0.06), Vector3(-0.21, 0, 0), Z90, Vector3.ONE]]
		"cricket_bat":  # slung across the back, handle over the right shoulder
			return [["upperChest", ToonRig.cyl(0.016, 0.016, 0.22), Vector3(-0.17, 0.2, -0.17), Vector3(0, 0, 0.5), Vector3.ONE],
				["upperChest", ToonRig.box(0.1, 0.52, 0.035), Vector3(-0.0, -0.14, -0.17), Vector3(0, 0, 0.5), Vector3.ONE]]
		"thigh_pad":
			return [["leftUpperLeg", ToonRig.box(0.15, 0.26, 0.05), Vector3(0.02, -0.2, 0.08), Vector3.ZERO, Vector3.ONE]]
		# ---- painter
		"beret":
			return [S.call(H, Vector3(0.015, top + 0.005, c.z - 0.005), r * 1.15, 0.025, r * 1.1, Vector3(0, 0, -0.25)),
				[H, ToonRig.cyl(0.004, 0.006, 0.02), Vector3(0.0, top + 0.035, c.z), Vector3(0, 0, -0.25), Vector3.ONE]]
		"palette":      # held in the left hand
			return [S.call("leftHand", Vector3(0.12, -0.02, 0.04), 0.16, 0.01, 0.11, Vector3(0, 0, 0.3))]
		"dab0", "dab1", "dab2", "dab3", "dab4", "dab5":   # one paint blob each, round the palette
			var a := TAU * int(kind.substr(3)) / 6.0
			return [S.call("leftHand", Vector3(0.12 + cos(a) * 0.075, -0.004 + cos(a) * 0.022, 0.04 + sin(a) * 0.055), 0.018, 0.008, 0.018, Vector3(0, 0, 0.3))]
		"paint_brush":
			return [["rightHand", ToonRig.cyl(0.006, 0.006, 0.22), Vector3(-0.08, 0.04, 0.0), Vector3(0, 0, 0.9), Vector3.ONE],
				["rightHand", ToonRig.cyl(0.0, 0.012, 0.04), Vector3(-0.17, 0.11, 0.0), Vector3(0, 0, 0.9), Vector3.ONE]]
	return []


func _goat_parts(kind: String) -> Array:
	var H := "head"
	var c: Vector3 = skull.position + skull.size / 2.0
	var r: float = skull.size.x / 2.0
	var front: float = skull.position.z + skull.size.z
	var top: float = skull.position.y + skull.size.y
	var blob := func(pos: Vector3, sx: float, sy: float, sz: float, rot := Vector3.ZERO) -> Array:
		return [H, ToonRig.sph(1.0), pos, rot, Vector3(sx, sy, sz)]
	# the goat skull (encloses the human head) and a long muzzle pointing forward, tipped slightly down
	var cc := c + Vector3(0, 0.018, -0.012)
	var cr := Vector3(r * 1.12, skull.size.y * 0.56, r * 1.22)
	var mrot := Vector3(0.28, 0, 0)
	var mc := Vector3(0, c.y - 0.03, front + 0.02)
	var mr := Vector3(r * 0.5, r * 0.46, r * 1.0)
	var tip := mc + Basis.from_euler(mrot) * Vector3(0, 0, mr.z * 0.96)
	# eyes on the sides of the head, on the skull's surface
	var ex := cr.x * 0.78
	var ez := cc.z + cr.z * sqrt(1.0 - 0.78 * 0.78) - 0.004
	var ey := c.y + 0.03
	match kind:
		"goat_head":
			var out := [blob.call(cc, cr.x, cr.y, cr.z),
				blob.call(mc, mr.x, mr.y, mr.z, mrot),
				blob.call(Vector3(0, c.y + 0.035, front - 0.005), r * 0.55, r * 0.35, r * 0.6, Vector3(0.6, 0, 0)),       # bridge of the nose
				[H, ToonRig.cyl(0.0, 0.024, 0.09), tip + Vector3(0, -0.055, -0.045), Vector3(PI + 0.3, 0, 0), Vector3.ONE]]   # beard under the chin
			for sx in [-1.0, 1.0]:   # long ears drooping out to the sides
				out.append(blob.call(Vector3(sx * (cr.x + 0.035), c.y + 0.02, cc.z - 0.015), 0.075, 0.019, 0.033, Vector3(0, -sx * 0.25, -sx * 0.5)))
			out.append(blob.call(Vector3(0, skull.position.y - 0.012, cc.z - 0.01), r * 1.02, 0.045, r * 1.02))   # ruff at the neck
			return out
		"goat_horns":   # curved, ridged horns sweeping back over the head
			var out := []
			for sx in [-1.0, 1.0]:
				var p := Vector3(sx * 0.045, top - 0.01, cc.z + 0.04)
				var pitch := -0.3
				for k in 5:
					var seg := 0.04 - k * 0.003
					var rad := 0.021 - k * 0.0033
					var rot := Vector3(pitch, 0, sx * -0.16)
					out.append([H, ToonRig.cyl(rad * 0.85, rad, seg), p + Basis.from_euler(rot) * Vector3(0, seg * 0.5, 0), rot, Vector3.ONE])
					p += Basis.from_euler(rot) * Vector3(0, seg, 0)
					pitch -= 0.42
			return out
		"goat_nose":
			return [blob.call(tip + Vector3(0, 0.008, 0.004), 0.03, 0.02, 0.014, mrot),
				blob.call(tip + Vector3(0, -0.032, -0.012), 0.024, 0.005, 0.01, mrot)]   # mouth line
		"goat_eyes":
			return [blob.call(Vector3(ex, ey, ez), 0.021, 0.019, 0.011, Vector3(0, 0.75, 0)),
				blob.call(Vector3(-ex, ey, ez), 0.021, 0.019, 0.011, Vector3(0, -0.75, 0))]
		"goat_pupils":   # goats have horizontal, bar-shaped pupils
			return [[H, ToonRig.box(0.02, 0.006, 0.004), Vector3(ex + 0.007, ey, ez + 0.009), Vector3(0, 0.75, 0), Vector3.ONE],
				[H, ToonRig.box(0.02, 0.006, 0.004), Vector3(-ex - 0.007, ey, ez + 0.009), Vector3(0, -0.75, 0), Vector3.ONE]]
	return []


func _make_accessories(list: Array) -> void:
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE
	outline.set_shader_parameter("thickness", 0.006)
	for a in list:
		var kind: String = a[0]
		var col: Color = a[1]
		var flat := kind in ["visor", "glasses", "mustache", "beard", "kameez", "shalwar", "sleeves", "hijab", "dupatta", "lanyard", "goat_eyes", "goat_pupils", "goat_nose", "phone_screen", "app0", "app1", "app2", "app3", "gamcha_check", "banana_ridges", "phone_cam", "vape_tank", "vape_screen"]
		if kind != "visor":
			col = col * 0.72   # keep within the texture range of the models so accessories don't bloom
			col.a = 1.0
		# Same cel shader as the model so accessories are lit like the clothes they sit on.
		var m := ShaderMaterial.new()
		m.shader = _shader("opaque")
		m.set_shader_parameter("tex", _white())
		m.set_shader_parameter("albedo", col)
		m.set_shader_parameter("shade", col.darkened(0.3).lerp(Color(0.55, 0.5, 0.75), 0.4))
		if kind.begins_with("hair_") or kind in ["beard", "mustache", "goat_head", "fur_arms", "lion_mane", "tail", "wool_head", "wool_body", "tail_tuft", "smoke_body", "smoke_head"]:
			m.set_shader_parameter("hair_sheen", 1.0 if kind.begins_with("hair_") else 0.6)
			m.set_shader_parameter("sheen_color", col.lightened(0.6).lerp(Color(0.8, 0.86, 1.0), 0.6))
			m.set_shader_parameter("shade", col.lightened(0.15).lerp(Color(0.5, 0.48, 0.7), 0.45))
		if kind in ["visor", "cig_ember", "phone_screen", "vape_tank", "vape_screen"]:
			m.set_shader_parameter("emission_strength", 1.1 if kind == "visor" else 0.6)
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


## Team glow (Office Ops): a strong rim light and a thicker outline in the team colour, so friend and foe
## read at a glance even far away or in the dark.
func set_team_glow(col: Color, amount := 0.7) -> void:
	for m in mats:
		m.set_shader_parameter("rim_color", col * 1.6)
		m.set_shader_parameter("rim_amount", amount)
		if m.next_pass is ShaderMaterial:
			var o := m.next_pass as ShaderMaterial
			o.set_shader_parameter("color", Color(col.r, col.g, col.b, 1.0))
			o.set_shader_parameter("thickness", 0.011 if amount > 0.8 else 0.008)


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
