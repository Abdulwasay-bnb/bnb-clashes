class_name OfficeParty
extends RefCounted
## Birthdays and work anniversaries in the BNB Virtual Office.
##
## On someone's day the hub sends {t:"init", party:[{name, kind:"birthday"|"anniversary", years}]} and
## each person's "party" flag. The office then decorates itself: a banner over reception, bunting, balloon
## bunches, a cake on the front desk and in the cafeteria, confetti; and whoever is celebrating walks
## round with balloons tied to them and a gold ring at their feet. Everything is built from plain shapes.

const BIRTHDAY_COLS := [Color(1.0, 0.45, 0.7), Color(0.149, 0.694, 0.808), Color(1.0, 0.82, 0.3), Color(0.55, 0.36, 0.95), Color(0.4, 0.88, 0.6)]
const ANNIV_COLS := [Color(1.0, 0.8, 0.3), Color(0.404, 0.204, 0.576), Color(0.97, 0.95, 1.0), Color(0.149, 0.694, 0.808)]
const GOLD := Color(1.0, 0.8, 0.3)
const INK := Color(0.082, 0.067, 0.114)

var world: Node3D
var mg                                  # MafiaGame: _mat / _box helpers
var font: Font
var root: Node3D
var bobs := []                          # [node, base position, phase]: balloons sway
var t := 0.0
var cols: Array = BIRTHDAY_COLS


static func banner_text(party: Array) -> String:
	var bday: Array = []
	var anniv: Array = []
	for p in party:
		var first := String(p.get("name", "")).split(" ", false)
		var nm: String = (first[0] if first.size() > 0 else "").to_upper()
		if nm == "": continue
		if String(p.get("kind", "")) == "birthday": bday.append(nm)
		else: anniv.append([nm, int(p.get("years", 0))])
	var lines: Array = []
	if bday.size() > 0: lines.append("HAPPY BIRTHDAY, " + _join(bday) + "!")
	if anniv.size() == 1 and int(anniv[0][1]) > 0:
		lines.append("HAPPY %s WORK ANNIVERSARY, %s!" % [_ordinal(int(anniv[0][1])), anniv[0][0]])
	elif anniv.size() > 0:
		lines.append("HAPPY WORK ANNIVERSARY, " + _join(anniv.map(func(a): return a[0])) + "!")
	return "\n".join(lines)


static func _join(names: Array) -> String:
	if names.size() <= 1: return "".join(names)
	if names.size() > 3: return ", ".join(names.slice(0, 3)) + " & %d MORE" % (names.size() - 3)
	return ", ".join(names.slice(0, names.size() - 1)) + " & " + String(names[-1])


static func _ordinal(n: int) -> String:
	var suf := "TH"
	if n % 100 < 11 or n % 100 > 13:
		suf = {1: "ST", 2: "ND", 3: "RD"}.get(n % 10, "TH")
	return str(n) + suf


func clear() -> void:
	if root != null: root.queue_free()
	root = null
	bobs.clear()


## Decorate the office for today's celebrations (nothing when the list is empty).
func build(party: Array) -> void:
	clear()
	if party.is_empty(): return
	var has_bday := party.any(func(p): return String(p.get("kind", "")) == "birthday")
	cols = BIRTHDAY_COLS if has_bday else ANNIV_COLS
	root = Node3D.new(); root.name = "party"
	world.add_child(root)
	_banner(banner_text(party), Vector3(0, 2.9, 12.35))
	# reception (x -8..8, z 12..20): bunting across the room, balloons in the corners, cake on the front desk
	for z in [13.2, 16.4, 19.4]: _bunting(Vector3(-7.6, 2.5, z), Vector3(7.6, 2.5, z))
	for p in [Vector2(-7.0, 12.9), Vector2(7.0, 12.9), Vector2(-7.0, 19.2), Vector2(7.0, 19.2), Vector2(-3.2, 15.0), Vector2(3.4, 15.0)]:
		_bunch(p, 5)
	_cake(Vector3(-0.2, 1.1, 15.2), has_bday)
	_confetti_floor(Rect2(-7.5, 12.5, 15.0, 7.0), 140)
	_confetti_fall(Vector3(0, 3.2, 16.0), Vector3(7.0, 0.2, 3.5))
	# cafeteria (x -30..-14, z -20..-8): bunting, balloons, a cake on the round table
	for z in [-17.5, -11.0]: _bunting(Vector3(-29.6, 2.5, z), Vector3(-14.4, 2.5, z))
	for p in [Vector2(-29.0, -9.0), Vector2(-15.0, -9.0), Vector2(-15.0, -19.0)]:
		_bunch(p, 4)
	_cake(Vector3(-24.0, 0.8, -13.6), has_bday)
	# the hallway into reception and the boardroom doors
	for p in [Vector2(-1.6, 11.2), Vector2(1.6, 11.2), Vector2(-8.6, 0.0), Vector2(8.6, 0.0)]:
		_bunch(p, 3)


## Balloons tied to a person who's celebrating, and a gold ring at their feet. Place it at the person each frame.
func dress(kind: String) -> Node3D:
	var n := Node3D.new(); n.name = "party_dress"
	var palette: Array = BIRTHDAY_COLS if kind == "birthday" else ANNIV_COLS
	var hand := Vector3(0.42, 1.05, 0.0)
	for i in 3:
		var top := Vector3(0.42 + (i - 1) * 0.26, 2.75 + 0.18 * (i % 2), (i - 1) * 0.1)
		_string(n, hand, top)
		var b := _balloon(palette[i % palette.size()], 0.2)
		b.position = top
		n.add_child(b)
		bobs.append([b, top, randf() * TAU])
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new(); tor.inner_radius = 0.5; tor.outer_radius = 0.6; tor.rings = 32; tor.ring_segments = 4
	ring.mesh = tor; ring.material_override = mg._mat(GOLD, 0.3, 1.4); ring.position = Vector3(0, 0.04, 0)
	n.add_child(ring)
	world.add_child(n)
	return n


func tick(dt: float) -> void:
	t += dt
	for i in range(bobs.size() - 1, -1, -1):
		var b = bobs[i]
		if not is_instance_valid(b[0]):
			bobs.remove_at(i); continue
		var base: Vector3 = b[1]
		var ph: float = b[2]
		(b[0] as Node3D).position = base + Vector3(sin(t * 0.9 + ph) * 0.05, sin(t * 1.4 + ph) * 0.07, cos(t * 0.7 + ph) * 0.04)


# ---------------------------------------------------------------- pieces
func _balloon(col: Color, r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.3; s.radial_segments = 16; s.rings = 8
	m.mesh = s
	var mat: StandardMaterial3D = mg._mat(col, 0.25, 0.25)
	mat.metallic = 0.1
	m.material_override = mat
	var knot := MeshInstance3D.new()
	var k := CylinderMesh.new(); k.top_radius = 0.0; k.bottom_radius = r * 0.22; k.height = r * 0.3
	knot.mesh = k; knot.material_override = mat; knot.rotation.x = PI; knot.position = Vector3(0, -r * 1.2, 0)
	m.add_child(knot)
	return m


func _string(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new(); c.top_radius = 0.006; c.bottom_radius = 0.006; c.height = a.distance_to(b); c.radial_segments = 4
	m.mesh = c; m.material_override = mg._mat(Color(0.95, 0.95, 0.95), 0.9)
	parent.add_child(m)
	m.position = (a + b) / 2.0
	var up := (b - a).normalized()
	if up.cross(Vector3.UP).length() > 0.001:
		m.basis = Basis(up.cross(Vector3.UP).normalized(), -acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))


func _bunch(p: Vector2, n: int) -> void:
	bunch_at(root, p, n, cols)


## A bunch of balloons tied to a little gold weight on the floor at p.
func bunch_at(parent: Node3D, p: Vector2, n: int, palette: Array) -> void:
	var anchor := Vector3(p.x, 0.05, p.y)
	var weight := MeshInstance3D.new()
	var w := CylinderMesh.new(); w.top_radius = 0.08; w.bottom_radius = 0.1; w.height = 0.1
	weight.mesh = w; weight.material_override = mg._mat(GOLD, 0.3, 0.4); weight.position = anchor
	parent.add_child(weight)
	for i in n:
		var ang := TAU * float(i) / n + randf() * 0.4
		var top := anchor + Vector3(cos(ang) * 0.28, 2.0 + randf() * 0.6, sin(ang) * 0.28)
		_string(parent, anchor + Vector3(0, 0.05, 0), top)
		var b := _balloon(palette[(i + int(absf(p.x))) % palette.size()], 0.24)
		b.position = top
		parent.add_child(b)
		bobs.append([b, top, randf() * TAU])


func _bunting(a: Vector3, b: Vector3) -> void:
	var flags := int(a.distance_to(b) / 0.55)
	_string(root, a, b + Vector3(0, -0.001, 0))
	for i in flags:
		var f := float(i + 0.5) / flags
		var pos := a.lerp(b, f) + Vector3(0, -sin(f * PI) * 0.35, 0)   # it sags in the middle
		var m := MeshInstance3D.new()
		var pr := PrismMesh.new(); pr.size = Vector3(0.32, 0.38, 0.02)
		m.mesh = pr; m.material_override = mg._mat(cols[i % cols.size()], 0.6, 0.2)
		m.rotation.z = PI                                              # point down
		m.position = pos + Vector3(0, -0.19, 0)
		root.add_child(m)


func _cake(pos: Vector3, birthday: bool) -> void:
	var sponge := Color(1.0, 0.93, 0.85) if birthday else Color(0.35, 0.22, 0.16)
	var icing := Color(1.0, 0.55, 0.78) if birthday else GOLD
	var plate := MeshInstance3D.new()
	var pl := CylinderMesh.new(); pl.top_radius = 0.36; pl.bottom_radius = 0.33; pl.height = 0.02
	plate.mesh = pl; plate.material_override = mg._mat(Color(0.97, 0.97, 1.0), 0.3); plate.position = pos + Vector3(0, 0.01, 0)
	root.add_child(plate)
	var y := pos.y + 0.02
	for tier in [[0.28, 0.16], [0.2, 0.13]]:
		var m := MeshInstance3D.new()
		var c := CylinderMesh.new(); c.top_radius = tier[0]; c.bottom_radius = tier[0]; c.height = tier[1]
		m.mesh = c; m.material_override = mg._mat(sponge, 0.7); m.position = Vector3(pos.x, y + tier[1] / 2.0, pos.z)
		root.add_child(m)
		var top := MeshInstance3D.new()
		var tc := CylinderMesh.new(); tc.top_radius = tier[0] + 0.01; tc.bottom_radius = tier[0] + 0.01; tc.height = 0.035
		top.mesh = tc; top.material_override = mg._mat(icing, 0.4, 0.15); top.position = Vector3(pos.x, y + tier[1] - 0.01, pos.z)
		root.add_child(top)
		y += tier[1]
	for i in 5:
		var ang := TAU * i / 5.0
		var cp := Vector3(pos.x + cos(ang) * 0.12, y, pos.z + sin(ang) * 0.12)
		var candle := MeshInstance3D.new()
		var cc := CylinderMesh.new(); cc.top_radius = 0.012; cc.bottom_radius = 0.012; cc.height = 0.1; cc.radial_segments = 6
		candle.mesh = cc; candle.material_override = mg._mat(cols[i % cols.size()], 0.5); candle.position = cp + Vector3(0, 0.05, 0)
		root.add_child(candle)
		var flame := MeshInstance3D.new()
		var fs := SphereMesh.new(); fs.radius = 0.018; fs.height = 0.05; fs.radial_segments = 6; fs.rings = 4
		flame.mesh = fs; flame.material_override = mg._mat(Color(1.0, 0.75, 0.3), 0.2, 4.0); flame.position = cp + Vector3(0, 0.125, 0)
		root.add_child(flame)
		bobs.append([flame, flame.position, randf() * TAU])
	var glow := OmniLight3D.new(); glow.position = Vector3(pos.x, y + 0.3, pos.z); glow.omni_range = 1.6
	glow.light_color = Color(1.0, 0.8, 0.5); glow.light_energy = 0.6
	root.add_child(glow)


func _banner(text: String, pos: Vector3) -> void:
	if text == "": return
	var lines := text.count("\n") + 1
	var cloth := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = Vector3(12.0, 0.42 * lines + 0.2, 0.03)
	cloth.mesh = b; cloth.material_override = mg._mat(INK.lightened(0.12), 0.8); cloth.position = pos + Vector3(0, 0, -0.03)
	root.add_child(cloth)
	var edge := MeshInstance3D.new()
	var e := BoxMesh.new(); e.size = Vector3(12.1, 0.42 * lines + 0.3, 0.02)
	edge.mesh = e; edge.material_override = mg._mat(cols[0], 0.4, 1.2); edge.position = pos + Vector3(0, 0, -0.05)
	root.add_child(edge)
	var l := Label3D.new()
	l.text = text; l.font = font; l.font_size = 64; l.pixel_size = 0.0055
	l.modulate = Color(1.0, 0.92, 0.6); l.outline_size = 12; l.outline_modulate = INK
	l.position = pos; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.width = 11.4 / 0.0055; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(l)
	for x in [-6.0, 6.0]:      # a balloon pair at each end of the banner
		for j in 2:
			var bb := _balloon(cols[(j + (1 if x > 0 else 0)) % cols.size()], 0.22)
			var bp := pos + Vector3(x + (j - 0.5) * 0.35, 0.25 + j * 0.15, 0.05)
			bb.position = bp
			root.add_child(bb)
			bobs.append([bb, bp, randf() * TAU])


func _confetti_floor(r: Rect2, n: int) -> void:
	var mats: Array = []
	for c in cols: mats.append(mg._mat(c, 0.6, 0.2))
	var bx := BoxMesh.new(); bx.size = Vector3(0.07, 0.004, 0.04)
	for i in n:
		var m := MeshInstance3D.new()
		m.mesh = bx; m.material_override = mats[i % mats.size()]
		m.position = Vector3(r.position.x + randf() * r.size.x, 0.09, r.position.y + randf() * r.size.y)
		m.rotation.y = randf() * TAU
		root.add_child(m)


func _confetti_fall(pos: Vector3, extent: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 90; p.lifetime = 5.0; p.preprocess = 5.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; p.emission_box_extents = extent
	p.direction = Vector3(0, -1, 0); p.spread = 25.0; p.gravity = Vector3(0, -0.6, 0)
	p.initial_velocity_min = 0.2; p.initial_velocity_max = 0.5
	p.angular_velocity_min = -180.0; p.angular_velocity_max = 180.0
	var q := QuadMesh.new(); q.size = Vector2(0.06, 0.035)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = mat
	p.mesh = q
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	g.colors = PackedColorArray([cols[0], cols[1 % cols.size()], cols[2 % cols.size()], cols[3 % cols.size()], cols[0]])
	p.color_initial_ramp = g
	p.position = pos
	root.add_child(p)
