class_name Pose
## A pose is a fixed-size array of joint angles / offsets (radians, meters).
## Partial poses from the data file are dictionaries layered on top of a base pose.

const KEYS: Array[String] = ["hipY", "lift", "rootRx", "rootRz", "yaw", "hipYaw", "torsoX", "torsoY", "torsoZ", "headX", "headY",
	"lsx", "lsy", "lsz", "le", "rsx", "rsy", "rsz", "re", "lhx", "lhz", "lk", "rhx", "rhz", "rk"]
const N := 25
enum { HIP_Y, LIFT, ROOT_RX, ROOT_RZ, YAW, HIP_YAW, TORSO_X, TORSO_Y, TORSO_Z, HEAD_X, HEAD_Y,
	LSX, LSY, LSZ, LE, RSX, RSY, RSZ, RE, LHX, LHZ, LK, RHX, RHZ, RK }


static func zero() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(N)
	return a


static func with(base: PackedFloat32Array, over) -> PackedFloat32Array:
	var a := base.duplicate()
	if over is Dictionary:
		for k in over:
			var i := KEYS.find(String(k))
			if i >= 0:
				a[i] = float(over[k])
	return a


static func lerp_p(a: PackedFloat32Array, b: PackedFloat32Array, t: float) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(N)
	for i in N:
		o[i] = a[i] + (b[i] - a[i]) * t
	return o


static func ease_io(t: float) -> float:
	return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
