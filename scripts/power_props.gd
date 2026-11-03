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
			var w := _mat(Color(0.92, 0.92, 1.0), 1.2, 0.75)   # a glowing goat spirit
			_mesh(n, _box(0.5, 0.25, 0.22), w)
			_mesh(n, _box(0.18, 0.18, 0.16), w, Vector3(0.32, 0.12, 0))
			for z in [-0.06, 0.06]:
				var horn := TorusMesh.new(); horn.inner_radius = 0.04; horn.outer_radius = 0.06
				_mesh(n, horn, _mat(Color(0.85, 0.75, 0.5), 0.6), Vector3(0.3, 0.25, z), Vector3(PI / 2, 0, 0.5))
			for lx in [-0.18, 0.18]:
				for z in [-0.08, 0.08]:
					_mesh(n, _box(0.05, 0.2, 0.05), w, Vector3(lx, -0.2, z))
			_mesh(n, _box(0.04, 0.1, 0.04), w, Vector3(0.38, -0.02, 0))   # beard
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
		_:
			_mesh(n, _sph(0.07), _mat(accent, 2.0))
	return n


## How many props and how they travel, per kind: [count, spin, arc height, scale].
const STYLE := {
	"banana": [5, 9.0, 0.5, 1.4], "chai": [3, 6.0, 0.7, 1.6], "cigarette": [4, 12.0, 0.2, 1.8], "ball": [1, 20.0, 0.1, 1.8],
	"snake": [1, 0.0, 0.0, 2.6], "goat": [1, 0.0, 0.0, 2.2], "cards": [7, 14.0, 0.3, 1.4], "notes": [8, 8.0, 0.6, 1.2],
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
		tw.tween_method(func(u: float):
			var q := start.lerp(end, u) + Vector3(0, sin(u * PI) * arc, 0)
			if wiggle: q += Vector3(sin(u * 18.0) * 0.12, 0, cos(u * 18.0) * 0.12)
			p.position = q
			p.rotate_object_local(Vector3(0, 0, 1), spin * 0.016), 0.0, 1.0, dur)
		# pop on impact
		tw.tween_property(p, "scale", p.scale * 1.8, 0.08)
		tw.parallel().tween_property(p, "scale:y", 0.01, 0.12).set_delay(0.06)
		tw.tween_callback(p.queue_free)
