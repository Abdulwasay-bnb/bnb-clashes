class_name Idle
## Per-fighter idle motion layered on the guard pose (t in seconds).

static func apply(id: String, p: PackedFloat32Array, t: float) -> void:
	var ms := t * 1000.0
	match id:
		"vex":
			p[Pose.HEAD_Y] += sin(ms * 0.0013) * 0.15
			p[Pose.HIP_Y] += sin(ms * 0.004) * 0.006
		"bastion":
			var b := sin(ms * 0.0025)
			p[Pose.TORSO_X] += b * 0.03; p[Pose.LSZ] += b * 0.04; p[Pose.RSZ] -= b * 0.04
		"sora":
			var b := absf(sin(ms * 0.0075))
			p[Pose.HIP_Y] += b * 0.03 - 0.015; p[Pose.LK] += b * 0.08; p[Pose.RK] += b * 0.08
		"ember":
			var s := sin(ms * 0.003)
			p[Pose.TORSO_Z] += s * 0.06; p[Pose.HIP_YAW] += s * 0.08
		"mara":
			p[Pose.TORSO_Z] += sin(ms * 0.005) * 0.18
			p[Pose.HIP_Y] += sin(ms * 0.01) * 0.02
			p[Pose.HEAD_X] += sin(ms * 0.005) * 0.05
		"lio":
			var s := sin(ms * 0.0035)
			p[Pose.TORSO_Y] += s * 0.5; p[Pose.HIP_YAW] += s * 0.35; p[Pose.LHX] += s * 0.3; p[Pose.RHX] -= s * 0.35
			p[Pose.LSX] -= s * 0.3; p[Pose.RSX] += s * 0.5
		"tao":
			var s := sin(ms * 0.002)
			p[Pose.LSZ] += s * 0.08; p[Pose.LE] += s * 0.1; p[Pose.RSX] += s * 0.06; p[Pose.TORSO_X] += s * 0.02
		"kael":
			var b := maxf(0.0, sin(ms * 0.006))
			p[Pose.LHX] -= b * 0.3; p[Pose.LK] += b * 0.35; p[Pose.TORSO_X] -= b * 0.05; p[Pose.HIP_Y] += b * 0.01
