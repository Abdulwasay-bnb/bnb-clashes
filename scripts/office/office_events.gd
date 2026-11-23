class_name OfficeEvents
extends RefCounted
## Friday tournaments in the BNB Virtual Office.
##
## The hub's init carries trophies:[{name, title, game, date}] (the latest winners) and
## event:{title, game, when} (the next tournament, or null). Winners get a gold cup with their name
## on the trophy cabinet in reception; the next tournament is announced under the game room sign.

const GOLD := Color(1.0, 0.8, 0.3)
const INK := Color(0.082, 0.067, 0.114)
const SHELF_TOP := 1.22
const SHELF_Z := [15.2, 17.0]

var world: Node3D
var mg
var font: Font
var root: Node3D


static func sign_text(ev) -> String:
	if typeof(ev) != TYPE_DICTIONARY or String(ev.get("title", "")) == "": return ""
	return "%s\n%s" % [String(ev.title).to_upper(), String(ev.get("when", ""))]


func build(trophies: Array, ev) -> void:
	if root != null: root.queue_free()
	root = Node3D.new()
	world.add_child(root)
	var plaque := _label("TROPHY CABINET", 34, GOLD, Vector3(-6.3, 0.35, 18.0))
	plaque.outline_size = 10
	var n := mini(trophies.size(), 6)
	if n == 0:
		_label("WIN A FRIDAY TOURNAMENT\nTO PUT YOUR NAME HERE", 18, Color(1, 1, 1, 0.85), Vector3(-7.3, SHELF_TOP + 0.5, 16.1))
	for i in n:
		var z: float = lerpf(SHELF_Z[0], SHELF_Z[1], 0.5 if n == 1 else float(i) / (n - 1))
		_cup(Vector3(-7.5, SHELF_TOP, z), 1.0 if i == 0 else 0.8)
		var t: Dictionary = trophies[i]
		var first := String(t.get("name", "")).split(" ", false)
		_label("%s · %s" % [(first[0] if first.size() > 0 else "").to_upper(), String(t.get("date", "")).to_upper()], 24, Color(1, 1, 1),
			Vector3(-7.3, SHELF_TOP + 0.62, z))
	var txt := sign_text(ev)
	if txt != "":    # a notice board inside the game room, by the door
		var board := Node3D.new(); board.position = Vector3(25.6, 0, -3.45)
		root.add_child(board)
		for x in [-0.95, 0.95]:
			var leg := MeshInstance3D.new(); var lm := BoxMesh.new(); lm.size = Vector3(0.06, 1.2, 0.06)
			leg.mesh = lm; leg.material_override = mg._mat(INK.lightened(0.15), 0.6); leg.position = Vector3(x, 0.6, 0)
			board.add_child(leg)
		var panel := MeshInstance3D.new(); var pm := BoxMesh.new(); pm.size = Vector3(2.2, 0.9, 0.05)
		panel.mesh = pm; panel.material_override = mg._mat(INK.lightened(0.08), 0.5); panel.position = Vector3(0, 1.55, 0)
		board.add_child(panel)
		var trim := MeshInstance3D.new(); var tm := BoxMesh.new(); tm.size = Vector3(2.3, 1.0, 0.03)
		trim.mesh = tm; trim.material_override = mg._mat(GOLD, 0.4, 0.8); trim.position = Vector3(0, 1.55, -0.03)
		board.add_child(trim)
		var s := Label3D.new()
		s.text = "TOURNAMENT\n" + txt; s.font = font; s.font_size = 30; s.pixel_size = 0.0055; s.modulate = Color(1.0, 0.92, 0.6)
		s.outline_size = 8; s.outline_modulate = INK; s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.width = 2.0 / 0.0055; s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.position = Vector3(0, 1.55, 0.03)
		board.add_child(s)


func _cup(at: Vector3, scale: float) -> Node3D:
	var n := Node3D.new()
	n.position = at; n.scale = Vector3.ONE * scale
	var gold: Material = mg._mat(GOLD, 0.25, 0.25)
	var base := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = Vector3(0.22, 0.08, 0.22)
	base.mesh = b; base.material_override = mg._mat(INK.lightened(0.2), 0.5); base.position.y = 0.04
	n.add_child(base)
	var stem := MeshInstance3D.new(); var s := CylinderMesh.new(); s.top_radius = 0.025; s.bottom_radius = 0.05; s.height = 0.14
	stem.mesh = s; stem.material_override = gold; stem.position.y = 0.15
	n.add_child(stem)
	var bowl := MeshInstance3D.new(); var c := CylinderMesh.new(); c.top_radius = 0.12; c.bottom_radius = 0.05; c.height = 0.18
	bowl.mesh = c; bowl.material_override = gold; bowl.position.y = 0.31
	n.add_child(bowl)
	for side in [-1, 1]:    # handles
		var h := MeshInstance3D.new(); var t := TorusMesh.new(); t.inner_radius = 0.035; t.outer_radius = 0.055
		h.mesh = t; h.material_override = gold; h.position = Vector3(0, 0.33, side * 0.12); h.rotation.y = PI / 2; h.rotation.z = PI / 2
		n.add_child(h)
	root.add_child(n)
	return n


func _label(text: String, size: int, col: Color, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text; l.font = font; l.font_size = size; l.pixel_size = 0.006; l.modulate = col
	l.outline_size = 8; l.outline_modulate = INK; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = at; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = false
	root.add_child(l)
	return l
