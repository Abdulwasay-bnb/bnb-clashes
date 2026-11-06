class_name PowerProps
## Each fighter's power (Surge Art) sends their themed props at the opponent: bananas, chai, a cricket ball,
## a snake, a goat spirit... Purely visual (no effect on the fight itself), so online play stays in sync.
## Props are built from simple shapes, fly from the attacker's hands and land on the hit frame.

const BV := Color(0.58, 0.3, 0.85)
const CY := Color(0.13, 0.78, 0.92)


static func _mat(c: Color, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	if alpha < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = glow
	m.roughness = 0.6
	return m


static func _mesh(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = m
	mi.position = pos; mi.rotation = rot; mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2; s.radial_segments = 12; s.rings = 6
	return s


static func _tor(r: float, th: float) -> TorusMesh:
	var t := TorusMesh.new(); t.inner_radius = r - th; t.outer_radius = r + th; t.rings = 24; t.ring_segments = 8
	return t


static func _cyl(r1: float, r2: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = r1; c.bottom_radius = r2; c.height = h; c.radial_segments = 12
	return c


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z)
	return b


static func _text(parent: Node3D, t: String, c: Color, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = t; l.font_size = size; l.outline_size = 8; l.modulate = c * 1.6; l.shaded = false
	l.pixel_size = 0.0022   # ~15-20 cm tall: a thrown glyph, not a billboard
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	parent.add_child(l)
	return l


## One prop of the given kind, centered on its own origin, roughly 0.2-0.4 m across.
static func build(kind: String, accent: Color) -> Node3D:
	var n := Node3D.new()
	match kind:
		"banana":
			var y := _mat(Color(1.0, 0.85, 0.2))
			for k in 3:   # a curved banana from three tilted segments
				_mesh(n, _cyl(0.035, 0.035, 0.1), y, Vector3((k - 1) * 0.07, -absf(k - 1) * 0.02, 0), Vector3(0, 0, PI / 2 + (k - 1) * 0.5))
			_mesh(n, _sph(0.02), _mat(Color(0.35, 0.22, 0.1)), Vector3(0.12, -0.03, 0))
		"chai":
			_mesh(n, _cyl(0.06, 0.045, 0.1), _mat(Color(0.75, 0.4, 0.25)))
			_mesh(n, _cyl(0.055, 0.055, 0.01), _mat(Color(0.6, 0.38, 0.2), 0.3), Vector3(0, 0.046, 0))
			var tor := TorusMesh.new(); tor.inner_radius = 0.02; tor.outer_radius = 0.032
			_mesh(n, tor, _mat(Color(0.75, 0.4, 0.25)), Vector3(0.065, 0, 0), Vector3(PI / 2, 0, 0))
			_mesh(n, _sph(0.04), _mat(Color(1, 1, 1), 0.0, 0.35), Vector3(0, 0.11, 0), Vector3.ZERO, Vector3(1, 1.6, 1))
		"cigarette":
			_mesh(n, _cyl(0.012, 0.012, 0.16), _mat(Color(0.96, 0.95, 0.92)), Vector3.ZERO, Vector3(0, 0, PI / 2))
			_mesh(n, _cyl(0.0125, 0.0125, 0.05), _mat(Color(0.85, 0.55, 0.25)), Vector3(-0.08, 0, 0), Vector3(0, 0, PI / 2))
			_mesh(n, _sph(0.016), _mat(Color(1.0, 0.4, 0.1), 3.0), Vector3(0.085, 0, 0))
		"ball":
			_mesh(n, _sph(0.06), _mat(Color(0.7, 0.08, 0.08)))
			var seam := TorusMesh.new(); seam.inner_radius = 0.058; seam.outer_radius = 0.064
			_mesh(n, seam, _mat(Color(0.95, 0.95, 0.9)), Vector3.ZERO, Vector3(0, 0, PI / 2))
		"snake":
			var g := _mat(Color(0.2, 0.7, 0.3), 0.4)
			for k in 7:
				_mesh(n, _sph(0.05 - k * 0.004), g, Vector3(-k * 0.07, sin(k * 1.1) * 0.05, cos(k * 1.1) * 0.04))
			_mesh(n, _sph(0.06), g, Vector3(0.07, 0, 0), Vector3.ZERO, Vector3(1.4, 0.8, 1))
			_mesh(n, _box(0.06, 0.005, 0.01), _mat(Color(0.9, 0.1, 0.2), 1.5), Vector3(0.15, 0, 0))
		"goat":
			# a glowing goat spirit, built facing -Z (the direction props travel)
			var w := _mat(Color(0.95, 0.95, 1.0), 0.9, 0.9)
			var horn_m := _mat(Color(0.8, 0.68, 0.45), 0.4)
			_mesh(n, _sph(0.2), w, Vector3(0, 0.36, 0), Vector3.ZERO, Vector3(0.75, 0.7, 1.45))          # body
			_mesh(n, _cyl(0.06, 0.08, 0.2), w, Vector3(0, 0.5, -0.26), Vector3(-0.7, 0, 0))               # neck
			_mesh(n, _sph(0.1), w, Vector3(0, 0.62, -0.38), Vector3(0.25, 0, 0), Vector3(0.8, 0.85, 1.3))  # head
			_mesh(n, _sph(0.055), _mat(Color(0.85, 0.82, 0.86), 0.5), Vector3(0, 0.57, -0.49))            # snout
			for sx in [-1.0, 1.0]:
				_mesh(n, _cyl(0.0, 0.026, 0.2), horn_m, Vector3(sx * 0.05, 0.75, -0.31), Vector3(-1.0, 0, sx * 0.25))  # horns sweep back
				_mesh(n, _sph(0.035), w, Vector3(sx * 0.1, 0.66, -0.35), Vector3.ZERO, Vector3(1.6, 0.5, 0.8))         # ears
				for lz in [-0.2, 0.2]:
					_mesh(n, _cyl(0.024, 0.02, 0.3), w, Vector3(sx * 0.09, 0.14, lz))                                # legs
			_mesh(n, _cyl(0.0, 0.03, 0.1), w, Vector3(0, 0.49, -0.45), Vector3(PI, 0, 0))                  # beard
			_mesh(n, _sph(0.04), w, Vector3(0, 0.46, 0.3))                                                  # tail
		"bull":
			# a glowing red spirit bull, built facing -Z (the direction props travel), head down to charge
			var w := _mat(Color(0.75, 0.12, 0.08), 0.7, 0.92)
			var horn_m := _mat(Color(1.0, 0.92, 0.75), 0.6)
			_mesh(n, _sph(0.22), w, Vector3(0, 0.38, 0.02), Vector3.ZERO, Vector3(0.9, 0.8, 1.5))            # body
			_mesh(n, _sph(0.2), w, Vector3(0, 0.46, -0.18), Vector3.ZERO, Vector3(0.95, 0.85, 0.8))          # hump
			_mesh(n, _sph(0.11), w, Vector3(0, 0.38, -0.42), Vector3(0.5, 0, 0), Vector3(0.85, 0.8, 1.2))     # head, lowered
			_mesh(n, _sph(0.06), _mat(Color(0.95, 0.6, 0.55), 0.8), Vector3(0, 0.32, -0.53))                  # snout
			_mesh(n, _tor(0.03, 0.007), _mat(Color(1.0, 0.8, 0.3), 1.2), Vector3(0, 0.28, -0.56), Vector3(0.3, 0, 0))  # nose ring
			for sx in [-1.0, 1.0]:
				_mesh(n, _cyl(0.022, 0.03, 0.14), horn_m, Vector3(sx * 0.12, 0.46, -0.4), Vector3(0, 0, sx * -1.3))   # horns out...
				_mesh(n, _cyl(0.0, 0.022, 0.12), horn_m, Vector3(sx * 0.19, 0.51, -0.43), Vector3(-0.6, 0, sx * -0.2))  # ...and forward
				for lz in [-0.22, 0.22]:
					_mesh(n, _cyl(0.035, 0.03, 0.3), w, Vector3(sx * 0.11, 0.14, lz))                                  # legs
			_mesh(n, _cyl(0.012, 0.012, 0.25), w, Vector3(0, 0.4, 0.36), Vector3(-0.8, 0, 0))                 # tail
		"horseshoe":
			var m := _mat(Color(0.85, 0.85, 0.9), 1.2)
			_mesh(n, _tor(0.08, 0.016), m, Vector3.ZERO, Vector3(PI / 2, 0, 0))
		"agents":
			# one AI agent: a glowing core with an orbiting ring
			_mesh(n, _sph(0.05), _mat(CY, 2.4))
			var ring := TorusMesh.new(); ring.inner_radius = 0.075; ring.outer_radius = 0.085
			_mesh(n, ring, _mat(BV, 2.0), Vector3.ZERO, Vector3(PI / 2, 0, 0))
		"cards":
			var c := _mat(Color(1, 1, 1))
			_mesh(n, _box(0.12, 0.17, 0.004), c)
			_mesh(n, _sph(0.025), _mat(Color(0.85, 0.1, 0.15), 0.8), Vector3(0, 0, 0.006), Vector3.ZERO, Vector3(1, 1.2, 0.2))
		"notes":
			_mesh(n, _box(0.14, 0.14, 0.004), _mat([Color(1, 0.9, 0.3), Color(1, 0.5, 0.7), Color(0.5, 0.85, 1.0)][randi() % 3], 0.3))
		"letters":
			_mesh(n, _box(0.18, 0.11, 0.01), _mat(Color(0.97, 0.95, 0.9)))
			_mesh(n, _cyl(0.022, 0.022, 0.012), _mat(Color(0.85, 0.1, 0.15), 0.6), Vector3(0, 0, 0.008), Vector3(PI / 2, 0, 0))
		"contract":
			_mesh(n, _box(0.2, 0.27, 0.005), _mat(Color(0.97, 0.97, 0.95)))
			_text(n, "SIGNED", Color(0.1, 0.4, 0.9), 40).position = Vector3(0, 0, 0.01)
		"phone":
			_mesh(n, _box(0.08, 0.15, 0.012), _mat(Color(0.08, 0.08, 0.1)))
			_mesh(n, _box(0.07, 0.13, 0.002), _mat(accent, 2.0), Vector3(0, 0, 0.007))
			var wave := TorusMesh.new(); wave.inner_radius = 0.12; wave.outer_radius = 0.13
			_mesh(n, wave, _mat(accent, 2.0, 0.6), Vector3.ZERO, Vector3(PI / 2, 0, 0))
		"briefcase":
			_mesh(n, _box(0.32, 0.22, 0.09), _mat(Color(0.35, 0.2, 0.1)))
			var h := TorusMesh.new(); h.inner_radius = 0.03; h.outer_radius = 0.045
			_mesh(n, h, _mat(Color(0.2, 0.12, 0.06)), Vector3(0, 0.13, 0), Vector3(PI / 2, 0, 0))
		"snack":
			_mesh(n, _cyl(0.05, 0.04, 0.09), _mat(Color(0.96, 0.96, 0.98)))
			_mesh(n, _cyl(0.051, 0.051, 0.01), _mat(Color(0.3, 0.6, 1.0)), Vector3(0, 0.05, 0))
			_mesh(n, _box(0.08, 0.004, 0.06), _mat(Color(1.0, 0.75, 0.25)), Vector3(0.09, 0.02, 0), Vector3(0.4, 0.3, 0))
		"gem":
			_mesh(n, _sph(0.07), _mat(Color(0.9, 0.08, 0.25), 2.2), Vector3.ZERO, Vector3(0, 0.6, 0.6), Vector3(1, 1.3, 1))
		"paint":
			_mesh(n, _sph(0.06), _mat([Color(1, 0.3, 0.3), Color(0.3, 0.6, 1), Color(1, 0.85, 0.2), Color(0.4, 0.9, 0.4)][randi() % 4], 0.6))
		"pixels":
			_mesh(n, _box(0.07, 0.07, 0.07), _mat([CY, BV, Color(1, 1, 1)][randi() % 3], 1.5))
		"smoke":
			for k in 4:
				_mesh(n, _sph(0.09 + k * 0.02), _mat(Color(0.85, 0.88, 0.9), 0.2, 0.35), Vector3(k * 0.05, sin(k) * 0.04, 0))
		"clock":
			_mesh(n, _cyl(0.1, 0.1, 0.025), _mat(Color(0.97, 0.97, 0.97)), Vector3.ZERO, Vector3(PI / 2, 0, 0))
			_mesh(n, _box(0.012, 0.08, 0.005), _mat(Color(0.1, 0.1, 0.1)), Vector3(0, 0.035, 0.015))
			_mesh(n, _box(0.06, 0.012, 0.005), _mat(Color(0.85, 0.1, 0.1)), Vector3(0.025, 0, 0.015))
		"code":
			_text(n, "</>", accent, 90)
		"py":
			_text(n, "import", Color(0.3, 0.55, 1.0), 64)
		"keys":
			_text(n, "sudo", CY, 72)
		"runes":
			_text(n, ["{ }", "0x1F", "λ", "//"][randi() % 4], Color(1.0, 0.82, 0.3), 80)
		"logo":
			var sp := Sprite3D.new()
			sp.texture = load("res://assets/brand/bnb_mark_trim.png")
			sp.pixel_size = 0.5 / sp.texture.get_height()
			sp.shaded = false; sp.modulate = Color(1.8, 1.8, 1.8)
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			n.add_child(sp)
		"heart":
			var pk := _mat(Color(1.0, 0.4, 0.62), 1.6)
			_mesh(n, _sph(0.045), pk, Vector3(-0.032, 0.02, 0))
			_mesh(n, _sph(0.045), pk, Vector3(0.032, 0.02, 0))
			_mesh(n, _cyl(0.0, 0.06, 0.08), pk, Vector3(0, -0.035, 0), Vector3(PI, 0, 0))
		"bubble":
			_mesh(n, _box(0.22, 0.09, 0.02), _mat(Color(0.97, 0.97, 1.0), 0.4))
			_mesh(n, _sph(0.022), _mat(Color(1.0, 0.25, 0.3), 1.5), Vector3(0.1, 0.045, 0.012))
			_mesh(n, _box(0.05, 0.05, 0.022), _mat(Color(0.3, 0.55, 1.0), 1.2), Vector3(-0.07, 0, 0.002))
		"coin":
			_mesh(n, _cyl(0.04, 0.04, 0.01), _mat(Color(1.0, 0.8, 0.25), 1.4), Vector3.ZERO, Vector3(PI / 2, 0, 0))
		"terminal":
			_mesh(n, _box(0.36, 0.24, 0.015), _mat(Color(0.03, 0.05, 0.04), 0.0, 0.9))
			var t := _text(n, ">_ sudo", Color(0.2, 1.0, 0.45), 48)
			t.position = Vector3(0, 0.02, 0.012); t.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		"tablet":
			_mesh(n, _box(0.2, 0.14, 0.012), _mat(Color(0.08, 0.08, 0.1)))
			_mesh(n, _box(0.18, 0.12, 0.002), _mat(CY, 1.2), Vector3(0, 0, 0.007))
		"stump":
			_mesh(n, _cyl(0.012, 0.012, 0.7), _mat(Color(0.92, 0.85, 0.65)), Vector3(0, 0.35, 0))
		_:
			_mesh(n, _sph(0.07), _mat(accent, 2.0))
	return n


## How many props and how they travel, per kind: [count, spin, arc height, scale].
static var STYLE := {
	"banana": [5, 9.0, 0.5, 1.4], "chai": [3, 6.0, 0.7, 1.6], "cigarette": [4, 12.0, 0.2, 1.8], "ball": [1, 20.0, 0.1, 1.8],
	"snake": [1, 0.0, 0.0, 2.6], "goat": [1, 0.0, 0.0, 1.7], "bull": [1, 0.0, 0.0, 1.7], "horseshoe": [5, 10.0, 0.4, 1.4], "agents": [10, 0.0, 0.5, 1.3], "cards": [7, 14.0, 0.3, 1.4], "notes": [8, 8.0, 0.6, 1.2],
	"letters": [6, 7.0, 0.4, 1.4], "contract": [3, 5.0, 0.5, 1.5], "phone": [3, 4.0, 0.3, 1.6], "briefcase": [1, 10.0, 0.5, 1.6],
	"snack": [4, 8.0, 0.6, 1.4], "gem": [3, 6.0, 0.2, 1.4], "paint": [8, 0.0, 0.5, 1.3], "pixels": [10, 6.0, 0.4, 1.2],
	"smoke": [3, 1.0, 0.2, 2.2], "clock": [4, 6.0, 0.4, 1.4], "code": [4, 0.0, 0.3, 1.0], "py": [3, 0.0, 0.3, 1.0],
	"keys": [3, 0.0, 0.3, 1.0], "runes": [6, 0.0, 0.5, 1.0], "logo": [1, 0.0, 0.0, 2.2],
}


## Launch the attacker's props at the defender; they arrive after `travel` seconds.
static func launch(G: Node, att, def, kind: String, travel: float) -> void:
	if kind == "" or G.get("resim"): return
	var st: Array = STYLE.get(kind, [3, 6.0, 0.3, 1.4])
	var from: Vector3 = att.pos + Vector3(0, 1.3 * att.C.scale, 0)
	var to: Vector3 = def.pos + Vector3(0, 1.05 * def.C.scale, 0)
	if kind == "goat":   # the goat charges along the ground
		from = att.pos; to = def.pos
	var count: int = st[0]
	for k in count:
		var p := build(kind, att.C.accent)
		p.scale = Vector3.ONE * float(st[3])
		G.add_child(p)
		var spread := Vector3(randf_range(-0.25, 0.25), randf_range(-0.2, 0.3), randf_range(-0.25, 0.25)) if count > 1 else Vector3.ZERO
		var delay := k * minf(0.06, travel / maxf(1.0, count) * 0.5)
		var dur := maxf(0.15, travel - delay)
		var dir := (to - from)
		p.position = from + spread * 0.3
		p.look_at_from_position(p.position, p.position + Vector3(dir.x, 0, dir.z).normalized() + Vector3(0.001, 0, 0), Vector3.UP)
		p.visible = delay <= 0.0
		var tw := p.create_tween()
		if delay > 0.0:
			tw.tween_interval(delay)
			tw.tween_callback(func(): p.visible = true)
		var spin: float = st[1]
		var arc: float = st[2]
		var start := p.position
		var end := to + spread
		var wiggle := kind == "snake"
		var gallop := kind == "goat"
		var swarm := kind == "agents"
		var ph := k * TAU / maxf(1.0, count)
		tw.tween_method(func(u: float):
			var q := start.lerp(end, u) + Vector3(0, sin(u * PI) * arc, 0)
			if wiggle: q += Vector3(sin(u * 18.0) * 0.12, 0, cos(u * 18.0) * 0.12)
			if gallop: q.y = start.y + absf(sin(u * 22.0)) * 0.12
			if swarm:   # spiral in toward the target, tightening as they close
				var r := 0.45 * (1.0 - u)
				q += Vector3(cos(u * 14.0 + ph) * r, sin(u * 14.0 + ph) * r, 0)
			p.position = q
			p.rotate_object_local(Vector3(0, 0, 1), spin * 0.016), 0.0, 1.0, dur)
		# pop on impact
		tw.tween_property(p, "scale", p.scale * 1.8, 0.08)
		tw.parallel().tween_property(p, "scale:y", 0.01, 0.12).set_delay(0.06)
		tw.tween_callback(p.queue_free)


# ---------------------------------------------------------------- choreographed powers
## Play a fighter's power: a list of effects [effect, prop or text, start (fraction of travel), param].
## travel = seconds until the first active frame; everything is visual only.
static func play(G: Node, att, def, fx: Array, travel: float) -> void:
	if G.get("resim"): return
	travel = maxf(travel, 0.3)
	for e in fx:
		var kind: String = e[0]
		var what: String = String(e[1])
		var at := float(e[2]) * travel
		var param = e[3] if e.size() > 3 else null
		var run := func(): _effect(G, att, def, kind, what, param, maxf(0.12, travel - at))
		if at <= 0.0: run.call()
		else: G.get_tree().create_timer(at).timeout.connect(run)


static func _col(param, fallback: Color) -> Color:
	return Color(param[0], param[1], param[2]) if param is Array and param.size() >= 3 else fallback


static func _chest(f) -> Vector3:
	return f.pos + Vector3(0, 1.15 * f.C.scale, 0)


static func _effect(G: Node, att, def, kind: String, what: String, param, left: float) -> void:
	if G == null or not is_instance_valid(G) or not G.is_inside_tree(): return   # the race / fight ended mid-show
	var a: Vector3 = _chest(att)
	var d: Vector3 = _chest(def)
	match kind:
		"volley":
			var st: Array = STYLE.get(what, [3, 6.0, 0.3, 1.4]).duplicate()
			if param != null: st[0] = int(param)
			_volley(G, att, def, what, left, st)
		"rain":
			for k in int(param if param != null else 8):
				var p := _spawn(G, what, att.C.accent, 1.4)
				var start: Vector3 = def.pos + Vector3(randf_range(-0.7, 0.7), randf_range(3.0, 4.2), randf_range(-0.7, 0.7))
				p.position = start
				var tw := p.create_tween()
				tw.tween_interval(k * 0.04)
				tw.tween_property(p, "position", Vector3(start.x, d.y - 0.3, start.z), maxf(0.2, left)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.parallel().tween_property(p, "rotation", Vector3(randf() * 6, randf() * 6, 0), maxf(0.2, left))
				_pop(tw, p)
		"geyser":
			for k in int(param if param != null else 8):
				var p := _spawn(G, what, att.C.accent, 1.4)
				var base: Vector3 = def.pos + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))
				p.position = base
				var tw := p.create_tween()
				tw.tween_interval(k * 0.03)
				tw.tween_property(p, "position", base + Vector3(0, randf_range(1.8, 3.0), 0), left + 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				_pop(tw, p)
		"ring":
			var n := int(param if param != null else 8)
			for k in n:
				var p := _spawn(G, what, att.C.accent, 1.3)
				var ph := k * TAU / n
				var orbit := left * 0.6
				var tw := p.create_tween()
				tw.tween_method(func(u: float):
					var ang := ph + u * TAU * 1.5
					p.position = a + Vector3(cos(ang) * 0.9, sin(u * PI) * 0.3, sin(ang) * 0.9), 0.0, 1.0, maxf(0.1, orbit))
				tw.tween_method(func(u: float):
					var ang := ph + TAU * 1.5
					var from := a + Vector3(cos(ang) * 0.9, 0, sin(ang) * 0.9)
					p.position = from.lerp(d, u), 0.0, 1.0, maxf(0.1, left - orbit))
				_pop(tw, p)
		"beam":
			var c := _col(param, att.C.accent)
			var beam := MeshInstance3D.new()
			beam.mesh = _cyl(0.06, 0.06, 1.0)
			beam.material_override = _mat(c, 3.0, 0.7)
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			G.add_child(beam)
			var mid := (a + d) / 2.0
			var length := a.distance_to(d)
			beam.position = mid
			beam.look_at_from_position(mid, d, Vector3.UP)
			beam.rotate_object_local(Vector3.RIGHT, PI / 2)
			beam.scale = Vector3(0.2, 0.01, 0.2)
			var tw := beam.create_tween()
			tw.tween_property(beam, "scale", Vector3(1.0, length, 1.0), left).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tw.tween_property(beam, "scale", Vector3(2.2, length, 2.2), 0.12)
			tw.tween_property(beam, "scale", Vector3(0.01, length, 0.01), 0.35)
			tw.tween_callback(beam.queue_free)
			if what != "":
				_volley(G, att, def, what, left, [4, 0.0, 0.0, 1.2])
		"summon":
			var big := float(param if param != null else 2.5)
			var p := _spawn(G, what, att.C.accent, big)
			var behind: Vector3 = att.pos + (att.pos - def.pos).normalized() * 1.2
			var tw := p.create_tween()
			match what:
				"goat", "bull":   # charges along the floor
					p.position = behind
					p.look_at_from_position(behind, Vector3(def.pos.x, behind.y, def.pos.z), Vector3.UP)
					tw.tween_method(func(u: float):
						p.position = behind.lerp(def.pos, u) + Vector3(0, absf(sin(u * 20.0)) * 0.15, 0), 0.0, 1.0, left + 0.1)
				"snake":  # rises behind, then strikes
					p.position = behind + Vector3(0, -1.0, 0)
					p.look_at_from_position(p.position, d, Vector3.UP)
					tw.tween_property(p, "position", behind + Vector3(0, 2.2, 0), left * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					tw.tween_property(p, "position", d, left * 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
				"clock":  # appears over the opponent and drops
					p.position = def.pos + Vector3(0, 4.0, 0)
					tw.tween_property(p, "position", d + Vector3(0, 0.4, 0), left).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
				_:        # the giant logo: rises behind, then slams down on the opponent
					p.position = behind + Vector3(0, 0.5, 0)
					tw.tween_property(p, "position", behind + Vector3(0, 3.2, 0), left * 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					tw.tween_property(p, "position", def.pos + Vector3(0, 1.0, 0), left * 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
			tw.tween_interval(0.25)
			_pop(tw, p)
		"shock":
			var c := _col(param, att.C.accent)
			for k in 3:
				var ring := MeshInstance3D.new()
				var tor := TorusMesh.new(); tor.inner_radius = 0.9; tor.outer_radius = 1.0; tor.rings = 48
				ring.mesh = tor
				ring.material_override = _mat(c, 3.0, 0.75)
				ring.position = att.pos + Vector3(0, 0.05, 0)
				ring.scale = Vector3(0.2, 1, 0.2)
				G.add_child(ring)
				var reach: float = att.pos.distance_to(def.pos) + 0.6
				var tw := ring.create_tween()
				tw.tween_interval(k * 0.09)
				tw.tween_property(ring, "scale", Vector3(reach, 1, reach), left + 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.parallel().tween_property(ring.material_override, "albedo_color:a", 0.0, left + 0.3)
				tw.tween_callback(ring.queue_free)
			if what != "":
				_volley(G, att, def, what, left, [3, 1.0, 0.1, 2.0])
		"cage":
			var n := int(param if param != null else 6)
			for k in n:
				var p := _spawn(G, what, att.C.accent, 1.4)
				var ang := k * TAU / n
				var at := d + Vector3(cos(ang) * 1.1, sin(k * 1.7) * 0.25, sin(ang) * 1.1)
				p.position = at
				p.look_at_from_position(at, d, Vector3.UP)
				p.scale = Vector3.ONE * 0.01
				var tw := p.create_tween()
				tw.tween_property(p, "scale", Vector3.ONE * 1.4, left * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(p, "position", d, left * 0.4 + 0.05).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
				_pop(tw, p)
		"stamp":
			var c := _col(param, Color(1, 0.3, 0.3))
			var l := _label(G, what, c, 150)
			l.position = d + Vector3(0, 0.9, 0)
			l.scale = Vector3.ONE * 3.5
			l.modulate.a = 0.0
			var tw := l.create_tween()
			tw.tween_interval(maxf(0.0, left - 0.12))
			tw.tween_property(l, "modulate:a", 1.0, 0.04)
			tw.parallel().tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_interval(0.9)
			tw.tween_property(l, "modulate:a", 0.0, 0.3)
			tw.tween_callback(l.queue_free)
		"text":
			var l := _label(G, what, _col(param, att.C.accent), 120)
			l.position = a + Vector3(0, 0.9, 0)
			var tw := l.create_tween()
			tw.tween_property(l, "position", l.position + Vector3(0, 0.6, 0), 1.4)
			tw.parallel().tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.6)
			tw.tween_callback(l.queue_free)
		"burst":
			for k in int(param if param != null else 10):
				var p := _spawn(G, what, att.C.accent, 1.4)
				p.position = d
				var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.4), randf_range(-1, 1)).normalized()
				var tw := p.create_tween()
				tw.tween_interval(maxf(0.0, left - 0.05))
				tw.tween_property(p, "position", d + dir * randf_range(0.8, 1.6), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.parallel().tween_property(p, "rotation", Vector3(randf() * 8, randf() * 8, 0), 0.5)
				_pop(tw, p)
		"peels":   # banana peels left on the floor around the opponent
			for k in int(param if param != null else 4):
				var p := _spawn(G, "banana", att.C.accent, 1.5)
				p.position = def.pos + Vector3(randf_range(-0.8, 0.8), 0.04, randf_range(-0.8, 0.8))
				p.scale = Vector3(1.5, 0.35, 1.5)
				var tw := p.create_tween()
				tw.tween_interval(2.2)
				tw.tween_property(p, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
				tw.tween_callback(p.queue_free)
		"laughs":
			for k in int(param if param != null else 5):
				var l := _label(G, what, Color(1.0, 0.85, 0.3).lerp(att.C.accent, randf()), randi_range(80, 140))
				l.position = a + Vector3(randf_range(-1.2, 1.2), randf_range(0.2, 1.3), randf_range(-0.4, 0.4))
				l.modulate.a = 0.0
				var tw := l.create_tween()
				tw.tween_interval(k * 0.08)
				tw.tween_property(l, "modulate:a", 1.0, 0.05)
				tw.tween_property(l, "position", l.position + Vector3(0, 0.5, 0), 0.8)
				tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.3)
				tw.tween_callback(l.queue_free)
		"stumps":  # three stumps behind the opponent that scatter on impact
			var behind: Vector3 = def.pos + (def.pos - att.pos).normalized() * 0.5
			var side: Vector3 = (def.pos - att.pos).normalized().cross(Vector3.UP)
			for k in 3:
				var p := _spawn(G, "stump", att.C.accent, 1.0)
				p.position = behind + side * (k - 1) * 0.11
				var tw := p.create_tween()
				tw.tween_interval(maxf(0.0, left))
				tw.tween_property(p, "rotation", Vector3(randf_range(-1.4, -0.6), 0, (k - 1) * 0.8), 0.25)
				tw.parallel().tween_property(p, "position", p.position + (def.pos - att.pos).normalized() * 0.8 + side * (k - 1) * 0.4, 0.3)
				tw.tween_interval(1.2)
				_pop(tw, p)


static func _spawn(G: Node, what: String, accent: Color, s: float) -> Node3D:
	var p := build(what, accent)
	p.scale = Vector3.ONE * s
	G.add_child(p)
	return p


static func _pop(tw: Tween, p: Node3D) -> void:
	tw.tween_property(p, "scale", p.scale * 1.6, 0.07)
	tw.tween_property(p, "scale", Vector3.ONE * 0.01, 0.12)
	tw.tween_callback(p.queue_free)


static func _label(G: Node, t: String, c: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = t; l.font_size = size; l.outline_size = 18; l.shaded = false
	l.modulate = c * 1.5; l.outline_modulate = Color(0.02, 0.02, 0.04)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.0028
	l.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	G.add_child(l)
	return l


static func _volley(G: Node, att, def, kind: String, travel: float, st: Array) -> void:
	var saved = STYLE.get(kind)
	STYLE[kind] = st
	launch(G, att, def, kind, travel)
	if saved != null: STYLE[kind] = saved
