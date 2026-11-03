class_name ClipLib
## Mixamo animation clips (characters/_anims/<slot>.fbx), baked for retargeting onto VRM fighters.
##
## Mixamo's Y Bot and VRM models both rest in a T-pose facing +Z, so a bone's motion can be transferred
## as a *global rotation delta*: delta = global_pose * global_rest⁻¹ (rig space). The VRM rig applies
## the same delta on top of its own rest pose. Horizontal root motion is removed (the engine moves fighters);
## vertical hip motion is kept, normalized by hip height.

const DIR := "res://characters/_anims/"
const FPS := 30.0
const MAP := {
	"Hips": "hips", "Spine": "spine", "Spine1": "chest", "Spine2": "upperChest", "Neck": "neck", "Head": "head",
	"LeftShoulder": "leftShoulder", "LeftArm": "leftUpperArm", "LeftForeArm": "leftLowerArm", "LeftHand": "leftHand",
	"RightShoulder": "rightShoulder", "RightArm": "rightUpperArm", "RightForeArm": "rightLowerArm", "RightHand": "rightHand",
	"LeftUpLeg": "leftUpperLeg", "LeftLeg": "leftLowerLeg", "LeftFoot": "leftFoot", "LeftToeBase": "leftToes",
	"RightUpLeg": "rightUpperLeg", "RightLeg": "rightLowerLeg", "RightFoot": "rightFoot", "RightToeBase": "rightToes",
}

class Clip:
	var name := ""
	var length := 0.0
	var frames: Array = []   # per frame: Dictionary humanoid -> Quaternion (global delta, rig space)
	var hip: Array = []      # per frame: Vector3 hip offset / hip height (x,z zeroed)
	var eff: Array = []      # per frame: Dictionary limb -> Vector3 position relative to the hips / hip height
	var hits: Array = []     # detected strikes: [{t, limb, reach, height}], sorted by time

	## mirror = play the move with the other side of the body (left <-> right), reflected across the YZ plane
	func sample(t: float, mirror := false) -> Array:
		var s := _sample(t)
		if not mirror: return s
		var out := {}
		for k in s[0]:
			var q: Quaternion = s[0][k]
			var mk: String = k.replace("left", "@").replace("right", "left").replace("@", "right")
			out[mk] = Quaternion(q.x, -q.y, -q.z, q.w)
		return [out, s[1]]

	func _sample(t: float) -> Array:
		var n := frames.size()
		if n == 0: return [{}, Vector3.ZERO]
		var f := clampf(t, 0.0, length) * FPS
		var i0 := clampi(int(f), 0, n - 1)
		var i1 := mini(i0 + 1, n - 1)
		var u := f - floorf(f)
		var a: Dictionary = frames[i0]
		var b: Dictionary = frames[i1]
		var out := {}
		for k in a:
			out[k] = (a[k] as Quaternion).slerp(b[k], u)
		return [out, (hip[i0] as Vector3).lerp(hip[i1], u)]


static var clips := {}
static var loaded := false


static func has(name: String) -> bool:
	return clips.has(name)


static func get_clip(name: String) -> Clip:
	return clips.get(name)


static func load_all() -> void:
	for f in _files():
		_load_one(f)
	loaded = true


## Same as load_all, one clip per frame; on_progress(fraction) after each.
static func load_all_async(tree: SceneTree, on_progress: Callable) -> void:
	var files := _files()
	for i in files.size():
		_load_one(files[i])
		on_progress.call(float(i + 1) / files.size())
		await tree.process_frame
	loaded = true


static func _files() -> Array:
	var out := []
	var d := DirAccess.open(DIR)
	if d == null: return out
	for f in d.get_files():
		# exported builds list "x.fbx.import" instead of the source file
		var file := f.trim_suffix(".import")
		if file.ends_with(".fbx") and not out.has(file): out.append(file)
	return out


static func _load_one(file: String) -> void:
	if clips.has(file.get_basename()): return
	var c := _bake(DIR + file)
	if c != null:
		clips[c.name] = c


const EFFECTORS := {"lh": "LeftHand", "rh": "RightHand", "le": "LeftForeArm", "re": "RightForeArm",
	"lk": "LeftLeg", "rk": "RightLeg", "lf": "LeftToeBase", "rf": "RightToeBase", "hd": "Head"}


static func _bake(path: String) -> Clip:
	var ps = load(path)
	if not (ps is PackedScene): return null
	var scn: Node = ps.instantiate()
	var sks := scn.find_children("*", "Skeleton3D", true, false)
	var aps := scn.find_children("*", "AnimationPlayer", true, false)
	if sks.is_empty() or aps.is_empty():
		scn.free(); return null
	var sk: Skeleton3D = sks[0]
	var ap: AnimationPlayer = aps[0]
	var anim: Animation = null
	for lib in ap.get_animation_library_list():
		for an in ap.get_animation_library(lib).get_animation_list():
			var a: Animation = ap.get_animation_library(lib).get_animation(an)
			if a.get_track_count() > 0 and (anim == null or a.length > anim.length):
				anim = a
	if anim == null:
		scn.free(); return null
	var skel_path := String(scn.get_path_to(sk)) if scn != sk else "."
	var bones := {}     # bone index -> humanoid name
	var rot_tr := {}    # bone index -> track
	var hips_b := -1
	var hips_pos_tr := -1
	for b in sk.get_bone_count():
		var bn := sk.get_bone_name(b)
		var short := bn.trim_prefix("mixamorig_").trim_prefix("mixamorig:")
		var np := NodePath("%s:%s" % [skel_path, bn])
		var tr := anim.find_track(np, Animation.TYPE_ROTATION_3D)
		if tr < 0: tr = anim.find_track(NodePath("Skeleton3D:" + bn), Animation.TYPE_ROTATION_3D)
		if tr >= 0: rot_tr[b] = tr
		if MAP.has(short): bones[b] = MAP[short]
		if short == "Hips":
			hips_b = b
			hips_pos_tr = anim.find_track(np, Animation.TYPE_POSITION_3D)
			if hips_pos_tr < 0: hips_pos_tr = anim.find_track(NodePath("Skeleton3D:" + bn), Animation.TYPE_POSITION_3D)
	var rest_g := {}
	var eff_b := {}
	for b in sk.get_bone_count():
		rest_g[b] = sk.get_bone_global_rest(b).basis.get_rotation_quaternion()
		var short := sk.get_bone_name(b).trim_prefix("mixamorig_").trim_prefix("mixamorig:")
		for e in EFFECTORS:
			if EFFECTORS[e] == short: eff_b[e] = b
	var hip_rest: Vector3 = sk.get_bone_rest(hips_b).origin if hips_b >= 0 else Vector3(0, 1, 0)
	var hip_h := maxf(hip_rest.y, 0.1)
	var c := Clip.new()
	c.name = path.get_file().get_basename()
	c.length = anim.length
	var n := int(ceil(anim.length * FPS)) + 1
	for i in n:
		var t := minf(i / FPS, anim.length)
		var g := {}
		var gp := {}   # global positions, to locate hands / feet
		for b in sk.get_bone_count():
			var lq: Quaternion = anim.rotation_track_interpolate(rot_tr[b], t) if rot_tr.has(b) else sk.get_bone_rest(b).basis.get_rotation_quaternion()
			var par := sk.get_bone_parent(b)
			g[b] = (g[par] * lq) if par >= 0 else lq
			var lp: Vector3 = sk.get_bone_rest(b).origin
			if b == hips_b and hips_pos_tr >= 0:
				lp = anim.position_track_interpolate(hips_pos_tr, t)
			gp[b] = (gp[par] + (g[par] as Quaternion) * lp) if par >= 0 else lp
		var fr := {}
		for b in bones:
			fr[bones[b]] = (g[b] * (rest_g[b] as Quaternion).inverse()).normalized()
		c.frames.append(fr)
		var off := Vector3.ZERO
		if hips_pos_tr >= 0:
			var hp: Vector3 = anim.position_track_interpolate(hips_pos_tr, t)
			off = Vector3(0, (hp.y - hip_rest.y) / hip_h, 0)
		c.hip.append(off)
		var ef := {}
		for e in eff_b:
			ef[e] = ((gp[eff_b[e]] as Vector3) - (gp[hips_b] as Vector3)) / hip_h if hips_b >= 0 else Vector3.ZERO
		c.eff.append(ef)
	scn.free()
	c.hits = _find_hits(c)
	return c


## Strikes = moments where a hand / elbow / knee / foot reaches a clear forward peak.
## Reach is measured forward (+Z) from the hips in hip-heights; height is how high the limb is.
static func _find_hits(c: Clip) -> Array:
	var out := []
	if c.eff.is_empty(): return out
	for limb in ["lh", "rh", "lk", "rk", "lf", "rf", "le", "re", "hd"]:
		if not c.eff[0].has(limb): continue
		var n := c.eff.size()
		var z := []
		for i in n: z.append((c.eff[i][limb] as Vector3).z)
		var lo: float = z[0]
		var thresh := 0.28 if limb in ["lh", "rh", "lf", "rf"] else (0.12 if limb == "hd" else 0.22)
		for i in range(1, n - 1):
			lo = minf(lo, z[i])
			var hgt: float = (c.eff[i][limb] as Vector3).y
			var grounded: bool = limb in ["lf", "rf"] and hgt < -0.55   # a forward step, not a kick
			if not grounded and z[i] >= z[i - 1] and z[i] > z[i + 1] and z[i] - lo > thresh and z[i] > (0.1 if limb == "hd" else 0.25):
				out.append({t = i / FPS, limb = limb, reach = z[i], height = (c.eff[i][limb] as Vector3).y})
				lo = z[i]
	# elbows / knees only count when the hand / foot isn't the one striking at that moment
	out = out.filter(func(h):
		if h.limb in ["le", "re", "lk", "rk"]:
			var tip: String = {"le": "lh", "re": "rh", "lk": "lf", "rk": "rf"}[h.limb]
			for o in out:
				if o.limb == tip and absf(o.t - h.t) < 0.1 and o.reach > h.reach + 0.05: return false
		return true)
	out.sort_custom(func(a, b): return a.t < b.t)
	return out
