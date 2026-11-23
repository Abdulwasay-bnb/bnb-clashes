class_name OfficeDesks
extends RefCounted
## Everyone's desk in the BNB Virtual Office.
##
## The department rooms have one desk per person. The hub owns who sits where: it sends
## {t:"desks", desks:[{desk:"dev:3", id, name, status, party}]} (in init and whenever something
## changes), and the office draws each desk's nameplate and what that person is up to, even when
## they aren't in the office: in today, working from home, on a break (a mug), on leave (a palm
## tree), in a call (a headset) or away. On someone's birthday or work anniversary their desk gets
## balloons and a banner, and people can walk over and sign the card.
##
## Desk ids are "<room>:<n>", counted in the order the desks are listed here (the CEO office's desk
## is "ceo:0"). The hub's DESKS counts (employees/office.py) must match.

## room, desk row z, chair row z, desk x positions, desk size
const ROWS := [
	["dev", -2.0, -0.9, [-28.2, -26.2, -24.2, -19.8, -17.8, -15.8], [1.8, 1.0, 0.76]],
	["dev", 3.5, 2.4, [-28.2, -26.2, -24.2, -19.8, -17.8, -15.8], [1.8, 1.0, 0.76]],
	["hr", 16.0, 17.3, [-27.6, -25.2, -22.8, -20.4, -18.0], [2.0, 1.0, 0.76]],
	["server", -16.5, -15.4, [17.0, 20.6, 24.2, 27.8], [2.0, 1.0, 0.76]],
	["server", -10.6, -11.7, [16.6, 19.0, 25.0, 27.4], [2.0, 1.0, 0.76]],   # second row, clear of the south door
	["print", 17.0, 15.9, [18.0, 22.0, 26.0], [2.2, 1.1, 0.76]],
]
const WORDS := {"in": "in today", "wfh": "working from home", "break": "on a break", "leave": "on leave",
	"call": "in a call", "off": "away", "here": "in the office", "focus": "focusing"}
const COLS := {"in": Color(0.3, 0.85, 0.5), "here": Color(0.3, 0.85, 0.5), "wfh": Color(0.35, 0.65, 1.0),
	"break": Color(1.0, 0.75, 0.3), "leave": Color(0.3, 0.85, 0.8), "call": Color(1.0, 0.4, 0.45),
	"focus": Color(0.7, 0.5, 1.0), "off": Color(0.6, 0.6, 0.65)}

var world: Node3D
var mg
var small: Font
var party: OfficeParty
var spots := {}          # desk id -> {p: desk centre, chair: Vector2, room, node, sig}
var seat_desk := {}      # seat index -> desk id
var by_owner := {}       # user id -> desk id
var rows := {}           # desk id -> the hub's row


## The desks, screens and chairs for the department rooms, in the office decor format.
static func decor() -> Array:
	var out: Array = []
	var k := 0
	for row in ROWS:
		var dz: float = row[1]; var cz: float = row[2]
		for x in row[3]:
			out.append({m = "desk", p = [x, dz], s = row[4], block = true})
			out.append({m = "computerScreen" if k % 3 != 2 else "laptop", p = [x, dz + 0.1 * signf(dz - cz)],
				s = [0.8, 0.2, 0.6] if k % 3 != 2 else [0.6, 0.45, 0.35], y = 0.76})
			out.append({m = "chairDesk", p = [x, cz], r = 0 if cz > dz else 180, s = [0.8, 0.8, 1.0], seat = "desk"})
			k += 1
	return out


## Number every desk seat ("dev:0", ...) and find the desk in front of it.
func map_seats(seats: Array, decor_list: Array) -> void:
	var n := {}
	for i in seats.size():
		var s: Dictionary = seats[i]
		if String(s.kind) != "desk": continue
		var room := String(s.room)
		var idx: int = n.get(room, 0); n[room] = idx + 1
		var id := "%s:%d" % [room, idx]
		var best := Vector2(s.p); var bd := 2.0
		for d in decor_list:
			if String(d.m) != "desk": continue
			var q := Vector2(float(d.p[0]), float(d.p[1]))
			if q.distance_to(s.p) < bd: bd = q.distance_to(s.p); best = q
		seat_desk[i] = id
		spots[id] = {p = best, chair = Vector2(s.p), room = room, node = null, sig = ""}


func desk_of_seat(i: int) -> String:
	return String(seat_desk.get(i, ""))


## Where to stand when you arrive: just behind your chair.
func arrival(desk_id: String) -> Vector2:
	if not spots.has(desk_id): return Vector2.INF
	var sp: Dictionary = spots[desk_id]
	var away: Vector2 = (sp.chair - sp.p).normalized()
	return sp.chair + away * 0.8


## Draw the hub's desk list. present: user ids in the office now -> their live status.
func show(list: Array, present: Dictionary) -> void:
	rows.clear(); by_owner.clear()
	for r in list:
		var id := String(r.get("desk", ""))
		if spots.has(id):
			rows[id] = r
			if r.get("id") != null: by_owner[int(r.id)] = id
	for id in spots:
		var r: Dictionary = rows.get(id, {})
		var st := String(r.get("status", ""))
		if r.get("id") != null and present.has(int(r.id)):
			var live := String(present[int(r.id)])
			st = live if live in ["call", "focus", "break"] else "here"
		var sig := "%s|%s|%s|%s" % [r.get("id"), r.get("name", ""), st, r.get("party", "")]
		var sp: Dictionary = spots[id]
		if sig == String(sp.sig): continue
		sp.sig = sig
		if sp.node != null: (sp.node as Node).queue_free()
		sp.node = _draw(sp, r, st)


func _draw(sp: Dictionary, r: Dictionary, st: String) -> Node3D:
	var n := Node3D.new()
	world.add_child(n)
	var p: Vector2 = sp.p
	var side := Vector3(0.62, 0, 0)
	var top := Vector3(p.x, 0.77, p.y)
	var l := Label3D.new()
	l.font = small; l.font_size = 48; l.outline_size = 9; l.pixel_size = 0.0045
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(p.x, 1.55, p.y)
	n.add_child(l)
	if r.is_empty() or r.get("id") == null:
		l.text = "free desk"; l.modulate = Color(1, 1, 1, 0.35)
		return n
	var first := String(r.get("name", "")).split(" ", false)
	var nm: String = " ".join(first.slice(0, 2)) if first.size() > 0 else "?"
	l.text = nm + "\n● " + String(WORDS.get(st, st))
	l.modulate = COLS.get(st, Color.WHITE).lerp(Color.WHITE, 0.3 if st != "off" else 0.1)
	if st == "off": l.modulate.a = 0.7
	# the status lamp on the desk's corner
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.045; sm.height = 0.09; sm.radial_segments = 8; sm.rings = 4
	lamp.mesh = sm; lamp.material_override = mg._mat(COLS.get(st, Color.GRAY), 0.3, 2.0 if st != "off" else 0.0)
	lamp.position = top - side + Vector3(0, 0.05, 0)
	n.add_child(lamp)
	match st:
		"leave": _palm(n, top + side)
		"break": _mug(n, top + side)
		"call": _headset(n, top + side)
	var pk := String(r.get("party", ""))
	if pk != "":
		var palette: Array = OfficeParty.BIRTHDAY_COLS if pk == "birthday" else OfficeParty.ANNIV_COLS
		party.bunch_at(n, p + Vector2(-0.95, 0.0), 4, palette)
		var b := Label3D.new()
		b.text = ("HAPPY BIRTHDAY!" if pk == "birthday" else "HAPPY WORK ANNIVERSARY!") + "\nwalk over and sign the card"
		b.font = small; b.font_size = 46; b.outline_size = 10; b.pixel_size = 0.0045
		b.modulate = Color(1.0, 0.85, 0.45); b.outline_modulate = Color(0.08, 0.07, 0.11)
		b.billboard = BaseMaterial3D.BILLBOARD_ENABLED; b.position = Vector3(p.x, 2.15, p.y)
		n.add_child(b)
	return n


func row_for(desk_id: String) -> Dictionary:
	return rows.get(desk_id, {})


func _palm(n: Node3D, at: Vector3) -> void:
	var pot := MeshInstance3D.new(); var pc := CylinderMesh.new(); pc.top_radius = 0.07; pc.bottom_radius = 0.05; pc.height = 0.08
	pot.mesh = pc; pot.material_override = mg._mat(Color(0.85, 0.5, 0.3), 0.8); pot.position = at + Vector3(0, 0.04, 0)
	n.add_child(pot)
	var trunk := MeshInstance3D.new(); var tc := CylinderMesh.new(); tc.top_radius = 0.015; tc.bottom_radius = 0.025; tc.height = 0.32
	trunk.mesh = tc; trunk.material_override = mg._mat(Color(0.55, 0.38, 0.22), 0.9); trunk.position = at + Vector3(0, 0.24, 0)
	trunk.rotation.z = 0.12
	n.add_child(trunk)
	var leaf_m: Material = mg._mat(Color(0.25, 0.7, 0.35), 0.7)
	for i in 6:
		var leaf := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = Vector3(0.24, 0.012, 0.06)
		leaf.mesh = b; leaf.material_override = leaf_m
		var a := TAU * i / 6.0
		leaf.position = at + Vector3(0.02 + cos(a) * 0.1, 0.4, sin(a) * 0.1)
		leaf.rotation = Vector3(0, -a, -0.45)
		n.add_child(leaf)


func _mug(n: Node3D, at: Vector3) -> void:
	var mug := MeshInstance3D.new(); var c := CylinderMesh.new(); c.top_radius = 0.05; c.bottom_radius = 0.045; c.height = 0.1
	mug.mesh = c; mug.material_override = mg._mat(Color(0.96, 0.95, 0.93), 0.3); mug.position = at + Vector3(0, 0.05, 0)
	n.add_child(mug)
	var handle := MeshInstance3D.new(); var t := TorusMesh.new(); t.inner_radius = 0.02; t.outer_radius = 0.035
	handle.mesh = t; handle.material_override = mug.material_override; handle.position = at + Vector3(0.055, 0.05, 0)
	handle.rotation.x = PI / 2
	n.add_child(handle)
	var tea := MeshInstance3D.new(); var tc := CylinderMesh.new(); tc.top_radius = 0.043; tc.bottom_radius = 0.043; tc.height = 0.005
	tea.mesh = tc; tea.material_override = mg._mat(Color(0.6, 0.38, 0.2), 0.3); tea.position = at + Vector3(0, 0.098, 0)
	n.add_child(tea)


func _headset(n: Node3D, at: Vector3) -> void:
	var m: Material = mg._mat(Color(0.12, 0.12, 0.15), 0.4)
	var band := MeshInstance3D.new(); var t := TorusMesh.new(); t.inner_radius = 0.085; t.outer_radius = 0.1; t.rings = 16; t.ring_segments = 6
	band.mesh = t; band.material_override = m; band.position = at + Vector3(0, 0.1, 0); band.rotation.x = PI / 2
	n.add_child(band)
	for s in [-1.0, 1.0]:
		var cup := MeshInstance3D.new(); var c := CylinderMesh.new(); c.top_radius = 0.04; c.bottom_radius = 0.04; c.height = 0.03
		cup.mesh = c; cup.material_override = mg._mat(Color(1.0, 0.4, 0.45), 0.4, 0.6); cup.position = at + Vector3(s * 0.095, 0.04, 0)
		cup.rotation.z = PI / 2
		n.add_child(cup)
