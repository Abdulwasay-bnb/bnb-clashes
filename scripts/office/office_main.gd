class_name OfficeMain
extends Node
## BNB Virtual Office: the whole team in a 3D copy of the office, walking between rooms.
##
## Built for the web and embedded in BNB Hub (/office/). This scene draws the office, moves you
## around and lets you do things in it (sit down, have tea, present, play in the game room, wave);
## the hub page around it does the rest: who you are, everyone else's positions and actions (its
## /ws/office/ socket), and voice/video with whoever is near you. The two talk with postMessage:
##
##   hub -> office  {t:"init", me, spawn, rooms, people}  {t:"state", p:[[id,x,z,dx,dz,moving,room,act],...]}
##                  {t:"join", person}  {t:"leave", id}  {t:"status", id, status}  {t:"look", id, costume}
##                  {t:"talk", levels:{id:0..1}}  {t:"linked", ids:[...]}  {t:"goto", x, z}
##                  {t:"act"} (do what the prompt says)  init.party / person.party: birthdays, anniversaries (office_party.gd)
##                  {t:"desks", desks} (office_desks.gd)  {t:"let_in"} (the CEO office let you in)
##   office -> hub  {t:"desk", desk, owner, name, party} (sat at a desk)  {t:"knock"} (at the CEO office door)
##
## The CEO office is closed while someone is in it: others knock, and anyone inside can let them in.
## Admins walk straight in, and an empty office is open.  {t:"emote", e}  {t:"costume", i}
##   office -> hub  {t:"boot", p}  {t:"ready"}  {t:"pos", x, z, dx, dz, m, room, a}  {t:"person", id}
##                  {t:"prompt", text, act}  {t:"costumes", names, current}  {t:"look", costume}
##
## An action ("a") is "" or "sit:<seat>", "st:<station>" (standing at the tea bar, an arcade, the
## presentation screen) or "e:<emote>". Everyone draws everyone else's action from it.
##
## The rooms are the BNB office floor plan (MafiaSim.ROOMS, shared with BNB Mafia); the furniture
## here is the office's own (OFFICE_DECOR). Outside a browser it runs a demo with wandering colleagues.

const CLIPS := ["idle_relaxed", "m_walk", "m_run", "in_wave", "m_sit", "m_sit_talk", "m_type", "in_phone",
	"in_drinking", "in_clap", "in_dance", "in_laughing", "win_cheer", "in_thinking", "in_stretch", "in_tablet", "in_point"]
const WALK := 3.6
const RUN := 6.4
const RADIUS := 0.35
const HEAR := 4.5                      # the hub connects voice inside this distance (drawn round you)
const REACH := 1.5                     # how close you must be to sit / use something
const STATUS_COL := {"working": Color(0.3, 0.85, 0.5), "break": Color(1.0, 0.75, 0.3), "focus": Color(0.7, 0.5, 1.0),
	"call": Color(1.0, 0.4, 0.45), "away": Color(0.6, 0.6, 0.65), "off": Color(0.6, 0.6, 0.65)}
## Default room names; the hub sends the real ones (departments are given rooms by headcount).
const ROOM_NAMES := {"cafe": "CAFETERIA", "dev": "DEVELOPMENT", "hr": "MANAGEMENT", "server": "BUSINESS DEVELOPMENT",
	"storage": "GAME ROOM", "print": "CREATIVE & QA", "board": "MEETING ROOM", "reception": "RECEPTION", "ceo": "CEO OFFICE"}
## Rooms the office adds to the BNB floor plan: the CEO's office, in the hall north of the meeting room.
const EXTRA_ROOMS := [{id = "ceo", name = "CEO OFFICE", r = [-7, -20, 7, -11], doors = "s"}]
## Rooms where only the people inside hear each other.
const PRIVATE_ROOMS := ["board", "ceo"]
const EMOTES := {"wave": "in_wave", "clap": "in_clap", "dance": "in_dance", "laugh": "in_laughing",
	"cheer": "win_cheer", "think": "in_thinking", "stretch": "in_stretch"}
const EMOTE_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7]
const EMOTE_ORDER := ["wave", "clap", "dance", "laugh", "cheer", "think", "stretch"]

# BNB Hub "classic" theme
const INK := Color(0.082, 0.067, 0.114)        # #15111d
const BRAND := Color(0.404, 0.204, 0.576)      # #673493
const CYAN := Color(0.149, 0.694, 0.808)       # #26b1ce

## Games in the game room: tables you sit at, arcade machines you stand at.
const GAMES := {
	"carrom": {name = "CARROM", col = Color(0.85, 0.62, 0.35)},
	"ludo": {name = "LUDO", col = Color(0.95, 0.3, 0.3)},
	"cards": {name = "CARDS", col = Color(0.25, 0.7, 0.4)},
	"cricket": {name = "CRICKET", col = Color(0.3, 0.75, 0.35)},
	"race": {name = "RACE", col = Color(1.0, 0.45, 0.2)},
	"dash": {name = "DASH", col = Color(0.3, 0.6, 1.0)},
	"tumble": {name = "TUMBLE", col = Color(0.95, 0.8, 0.25)},
	"blast": {name = "BLAST", col = Color(1.0, 0.3, 0.6)},
	"mafia": {name = "MAFIA", col = Color(0.6, 0.35, 0.95)},
}

## The office's furniture. block = people can't walk through it; seat = people can sit on it
## (kind: desk / meet / cafe / sofa / game); game = which game a game-room table is for.
const OFFICE_DECOR := [
	# cafeteria: tea bar along the back wall, two tables
	{m = "kitchenFridgeLarge", p = [-29.0, -19.1], s = [1.2, 0.8, 2.0], block = true},
	{m = "kitchenBar", p = [-25.0, -19.3], s = [3.6, 0.9, 1.0], block = true},
	{m = "kitchenCoffeeMachine", p = [-26.2, -19.3], s = [0.5, 0.45, 0.55], y = 1.0},
	{m = "kitchenCoffeeMachine", p = [-23.8, -19.3], s = [0.5, 0.45, 0.55], y = 1.0},
	{m = "kitchenMicrowave", p = [-21.6, -19.3], s = [0.6, 0.45, 0.4], y = 1.0},
	{m = "kitchenCabinet", p = [-21.6, -19.3], s = [1.2, 0.8, 1.0], block = true},
	{m = "tableRound", p = [-24.0, -13.6], s = [2.4, 1.6, 0.8], block = true},
	{m = "tableRound", p = [-19.5, -15.8], s = [2.4, 1.6, 0.8], block = true},
	{m = "chair", p = [-25.65, -13.6], r = 90, s = [0.5, 0.5, 0.95], seat = "cafe"}, {m = "chair", p = [-22.35, -13.6], r = 270, s = [0.5, 0.5, 0.95], seat = "cafe"},
	{m = "chair", p = [-21.15, -15.8], r = 90, s = [0.5, 0.5, 0.95], seat = "cafe"}, {m = "chair", p = [-17.85, -15.8], r = 270, s = [0.5, 0.5, 0.95], seat = "cafe"},
	{m = "loungeSofa", p = [-28.9, -12.5], r = 90, s = [2.4, 0.9, 0.9], block = true, seat = "sofa", seats = 2},
	{m = "tableCoffee", p = [-27.5, -12.5], s = [0.8, 1.4, 0.4], block = true},
	{m = "trashcan", p = [-14.8, -19.2], s = [0.6, 0.55, 0.9]},
	{m = "pottedPlant", p = [-29.2, -9.0], s = [0.7, 0.7, 1.6]},
	# development (the desks in the department rooms come from office_desks.gd)
	{m = "bookcaseOpen", p = [-29.4, 0.8], r = 90, s = [1.6, 0.6, 1.8], block = true},
	{m = "plantSmall1", p = [-15.0, 5.3], s = [0.5, 0.5, 0.7]},
	# management
	{m = "bookcaseClosedWide", p = [-27.5, 10.6], s = [1.8, 0.6, 1.8], block = true},
	{m = "coatRack", p = [-29.3, 19.4], s = [0.6, 0.3, 1.8]},
	{m = "pottedPlant", p = [-14.8, 19.2], s = [0.7, 0.7, 1.6]},
	# business development
	{m = "bookcaseOpen", p = [29.4, -11.0], r = 270, s = [1.6, 0.6, 1.8], block = true},
	{m = "pottedPlant", p = [15.0, -19.2], s = [0.7, 0.7, 1.6]},
	# creative & QA
	{m = "kitchenCabinet", p = [29.3, 12.0], r = 270, s = [1.0, 0.7, 1.0], block = true},
	{m = "pottedPlant", p = [15.0, 19.2], s = [0.7, 0.7, 1.6]},
	# meeting room: the long table (chairs are added round it), plants
	{m = "table", p = [0.0, 0.0], s = [9.0, 4.0, 0.8], block = true},
	{m = "pottedPlant", p = [-7.3, 6.3], s = [0.7, 0.7, 1.6]}, {m = "pottedPlant", p = [7.3, 6.3], s = [0.7, 0.7, 1.6]},
	{m = "pottedPlant", p = [7.3, -6.3], s = [0.7, 0.7, 1.6]},
	# CEO office: an executive desk facing the door, two visitor chairs, a sofa corner, books
	{m = "desk", p = [0.0, -16.6], s = [3.0, 1.3, 0.78], block = true},
	{m = "computerScreen", p = [-0.6, -16.75], s = [0.9, 0.2, 0.62], y = 0.78}, {m = "laptop", p = [0.8, -16.5], s = [0.6, 0.45, 0.35], y = 0.78},
	{m = "chairDesk", p = [0.0, -17.9], s = [0.9, 0.9, 1.15], seat = "desk"},
	{m = "chair", p = [-0.8, -15.2], r = 180, s = [0.55, 0.55, 0.95], seat = "visit"}, {m = "chair", p = [0.8, -15.2], r = 180, s = [0.55, 0.55, 0.95], seat = "visit"},
	{m = "loungeSofa", p = [-5.9, -15.8], r = 90, s = [2.4, 0.9, 0.9], block = true, seat = "sofa", seats = 2},
	{m = "tableCoffee", p = [-4.6, -15.8], s = [0.8, 1.4, 0.4], block = true},
	{m = "bookcaseClosedWide", p = [4.6, -19.4], s = [2.4, 0.6, 2.0], block = true},
	{m = "pottedPlant", p = [-6.3, -19.3], s = [0.8, 0.8, 1.8]}, {m = "pottedPlant", p = [6.3, -12.0], s = [0.7, 0.7, 1.6]},
	# reception: front desk, sofas (the rug is the BNB logo, drawn separately)
	{m = "kitchenBar", p = [0.0, 15.2], s = [5.0, 1.1, 1.05], block = true},
	{m = "laptop", p = [1.5, 15.2], s = [0.6, 0.45, 0.35], y = 1.05},
	{m = "loungeSofa", p = [-1.6, 19.5], r = 180, s = [2.4, 0.9, 0.9], block = true, seat = "sofa", seats = 2},
	{m = "loungeChair", p = [2.0, 19.5], r = 180, s = [1.1, 0.9, 0.9], block = true, seat = "sofa"},
	{m = "pottedPlant", p = [-7.4, 12.6], s = [0.7, 0.7, 1.6]}, {m = "pottedPlant", p = [7.4, 12.6], s = [0.7, 0.7, 1.6]},
	{m = "sideTable", p = [5.0, 18.6], s = [1.0, 0.6, 0.8]},
	# game room: three tables, a sofa, the arcade machines are drawn separately
	{m = "tableCoffeeSquare", p = [18.0, -1.2], s = [1.5, 1.5, 0.7], block = true, game = "carrom"},
	{m = "table", p = [18.0, 3.8], s = [1.6, 1.6, 0.75], block = true, game = "ludo"},
	{m = "tableRound", p = [23.0, 1.2], s = [1.8, 1.8, 0.75], block = true, game = "cards"},
	{m = "chair", p = [16.75, -1.2], r = 90, s = [0.5, 0.5, 0.95], seat = "game", game = "carrom"},
	{m = "chair", p = [19.25, -1.2], r = 270, s = [0.5, 0.5, 0.95], seat = "game", game = "carrom"},
	{m = "chair", p = [18.0, -2.45], r = 0, s = [0.5, 0.5, 0.95], seat = "game", game = "carrom"},
	{m = "chair", p = [18.0, 0.05], r = 180, s = [0.5, 0.5, 0.95], seat = "game", game = "carrom"},
	{m = "chair", p = [16.7, 3.8], r = 90, s = [0.5, 0.5, 0.95], seat = "game", game = "ludo"},
	{m = "chair", p = [19.3, 3.8], r = 270, s = [0.5, 0.5, 0.95], seat = "game", game = "ludo"},
	{m = "chair", p = [18.0, 2.5], r = 0, s = [0.5, 0.5, 0.95], seat = "game", game = "ludo"},
	{m = "chair", p = [18.0, 5.1], r = 180, s = [0.5, 0.5, 0.95], seat = "game", game = "ludo"},
	{m = "chair", p = [21.6, 1.2], r = 90, s = [0.5, 0.5, 0.95], seat = "game", game = "cards"},
	{m = "chair", p = [24.4, 1.2], r = 270, s = [0.5, 0.5, 0.95], seat = "game", game = "cards"},
	{m = "chair", p = [23.0, -0.2], r = 0, s = [0.5, 0.5, 0.95], seat = "game", game = "cards"},
	{m = "chair", p = [23.0, 2.6], r = 180, s = [0.5, 0.5, 0.95], seat = "game", game = "cards"},
	{m = "pottedPlant", p = [15.0, -3.3], s = [0.7, 0.7, 1.6]},
]
## Arcade machines along the game room's east wall: one player stands at each.
const ARCADES := [["cricket", -2.6], ["race", -1.0], ["dash", 0.6], ["tumble", 2.2], ["blast", 3.8], ["mafia", 5.3]]
var decor: Array = []                   # OFFICE_DECOR plus everyone's desks (office_desks.gd)
const SEAT_TABLES := ["desk", "table", "tableRound", "tableCoffeeSquare", "tableCoffee"]

var sim: MafiaSim
var mg: MafiaGame                      # borrowed for its floor and furniture builders (never added to the tree)
var world: Node3D
var cam: Camera3D
var font: Font
var small: Font
var layer: CanvasLayer
var loading: Label
var ready_done := false
var zoom := 1.0

var me := {}                            # {id, u, name, costume}
var my_rig: Node3D
var my_tag: Label3D
var party: OfficeParty                  # birthday / work anniversary decorations
var desks: OfficeDesks                  # everyone's desk and what they're up to
var desk_list: Array = []
var my_desk := ""                       # the desk you're sitting at ("" if none)
var ceo_let_in := false                 # someone in the CEO office let you in
const CEO_DOOR := Vector2(0.0, -10.3)   # just outside the CEO office door
var my_dress: Node3D
var my_ring: MeshInstance3D
var my_pos := Vector2(0, 16)
var my_dir := Vector2(0, -1)
var my_moving := false
var my_room := ""
var route_step := Vector2.ZERO          # next point on the way to target
var route_t := 0.0
var stuck_t := 0.0
var my_act := ""                        # see the header
var my_act_t := 0.0
var my_costume := 0
var pending := ""                       # walk there, then do this ("sit:3")
var target := Vector2.INF               # click / tap to walk here
var pointer_down := false
var _anim_t := 0.0
var _sent := {}
var _send_t := 0.0
var _prompt := ""

var people := {}                        # id -> {rig, tag, foot, pos, goal, dir, moving, name, status, talk, t, C, act, act_t, costume}
var rooms := {}                         # room id -> {name, kind}
var linked := {}                        # ids I'm in voice with
var room_labels := {}
var room_signs := {}
var seats: Array = []                   # [{p, face, kind, room, game}]
var stations: Array = []                # [{p, face, kind, name, game, solo}]

var js_cb = null
var web := false
var origin := ""
var demo := false
var demo_t := 0.0


func _ready() -> void:
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	layer = CanvasLayer.new(); add_child(layer)
	var bg := ColorRect.new(); bg.color = INK; bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.name = "bg"
	layer.add_child(bg)
	loading = Label.new(); loading.add_theme_font_override("font", small); loading.add_theme_font_size_override("font_size", 26)
	loading.add_theme_color_override("font_color", CYAN)
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading.text = "Setting up the office"
	layer.add_child(loading)
	web = OS.has_feature("web")
	if web:
		origin = str(JavaScriptBridge.eval("location.origin", true))
		js_cb = JavaScriptBridge.create_callback(_on_js)
		JavaScriptBridge.get_interface("window").addEventListener("message", js_cb)
	await get_tree().process_frame
	Data.load_all()
	_post({t = "boot", p = 0.05})
	for i in CLIPS.size():
		ClipLib._load_one(CLIPS[i] + ".fbx")
		var f := 0.05 + 0.8 * float(i + 1) / CLIPS.size()
		loading.text = "Setting up the office  %d%%" % int(f * 100.0)
		_post({t = "boot", p = f})
		await get_tree().process_frame
	sim = MafiaSim.new()
	decor = OFFICE_DECOR + OfficeDesks.decor()
	_build_collision()
	world = Node3D.new(); add_child(world)
	mg = MafiaGame.new(); mg.world = world; mg.font = font; mg.small = small
	party = OfficeParty.new(); party.world = world; party.mg = mg; party.font = font
	desks = OfficeDesks.new(); desks.world = world; desks.mg = mg; desks.small = small; desks.party = party
	desks.map_seats(seats, decor)
	for id in ROOM_NAMES: rooms[id] = {name = ROOM_NAMES[id], kind = "room"}
	_build_world()
	_post({t = "boot", p = 0.95})
	cam = Camera3D.new(); cam.fov = 50; cam.near = 0.25; cam.far = 160;   # a sane near plane keeps the thin floor layers from flickering
	world.add_child(cam); cam.current = true
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().scaling_3d_scale = 0.8
	ready_done = true
	if web:
		_post({t = "ready"})
		loading.text = "Signing you in"
	else:
		_start_demo()


# ---------------------------------------------------------------- map
func _build_collision() -> void:
	# the BNB floor plan's walls with the office's own furniture (MafiaSim.build_map would add BNB Mafia's)
	sim.walls.clear()
	var T := 0.4
	sim.walls.append(Rect2(-31, -21, 62, T)); sim.walls.append(Rect2(-31, 20.6, 62, T))
	sim.walls.append(Rect2(-31, -21, T, 42)); sim.walls.append(Rect2(30.6, -21, T, 42))
	for rm in all_rooms():
		var r: Array = rm.r
		var d: String = rm.doors
		sim._wall_side(r[0], r[1], r[2], r[1], "n" in d)
		sim._wall_side(r[0], r[3], r[2], r[3], "s" in d)
		sim._wall_side(r[0], r[1], r[0], r[3], "w" in d)
		sim._wall_side(r[2], r[1], r[2], r[3], "e" in d)
	for d in decor:
		if d.get("block", false):
			var sz: Array = d.s
			var rot: float = d.get("r", 0.0)
			var w: float = sz[0] if int(rot) % 180 == 0 else sz[1]
			var dd: float = sz[1] if int(rot) % 180 == 0 else sz[0]
			sim.walls.append(Rect2(float(d.p[0]) - w / 2.0, float(d.p[1]) - dd / 2.0, w, dd))
	for a in ARCADES:   # arcade cabinets against the game room's east wall
		sim.walls.append(Rect2(28.9, float(a[1]) - 0.55, 1.5, 1.1))
	# a walking graph (2 m grid, linked to its 8 neighbours) so click-to-walk goes round walls and
	# through doors instead of pushing into them
	# (1 m apart: a 2 m grid can't fit between the cafeteria tables)
	sim.waypoints.clear(); sim.links.clear()
	var index := {}
	for x in range(-30, 31):
		for z in range(-20, 21):
			var wp := Vector2(x, z)
			if not sim.blocked(wp, RADIUS + 0.1): index[wp] = sim.waypoints.size(); sim.waypoints.append(wp)
	for wp in sim.waypoints: sim.links.append([])
	for i in sim.waypoints.size():   # each pair checked once
		var wp: Vector2 = sim.waypoints[i]
		for off in [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, -1)]:
			var nb: Vector2 = wp + off
			if index.has(nb) and sim.clear(wp, nb, RADIUS):
				var j: int = index[nb]; sim.links[i].append(j); sim.links[j].append(i)
	# where people can sit and what they can use
	for d in decor:
		if not d.has("seat"): continue
		var p := Vector2(float(d.p[0]), float(d.p[1]))
		var rot := deg_to_rad(float(d.get("r", 0.0)))
		var fwd := Vector2(sin(rot), cos(rot))   # a chair's front at r=0 is +z
		var n := int(d.get("seats", 1))
		if n == 1:
			seats.append({p = p, face = _seat_face(p, fwd), kind = d.seat, room = room_at(p), game = d.get("game", "")})
		else:
			var side := Vector2(fwd.y, -fwd.x)
			for k in n:
				var sp := p + side * ((k - (n - 1) / 2.0) * 0.8) + fwd * 0.1
				seats.append({p = sp, face = fwd, kind = d.seat, room = room_at(sp), game = ""})
	for k in MafiaSim.SEATS:   # meeting room chairs round the table, facing it
		var a := TAU * k / MafiaSim.SEATS
		var cp := Vector2(cos(a) * 5.6, sin(a) * 3.0)
		seats.append({p = cp, face = -cp.normalized(), kind = "meet", room = "board", game = "", chair = true})
	for x in [-26.2, -25.0, -23.8]:
		stations.append({p = Vector2(x, -18.15), face = Vector2(0, -1), kind = "tea", name = "Have some tea", solo = true, game = ""})
	stations.append({p = Vector2(-4.5, -5.6), face = Vector2(0, 1), kind = "present", name = "Present", solo = true, game = ""})
	for a in ARCADES:
		stations.append({p = Vector2(28.1, float(a[1])), face = Vector2(1, 0), kind = "arcade", name = "Play " + String(GAMES[a[0]].name).capitalize(), solo = true, game = a[0]})


## Desk chairs face their desk, and screens/laptops on a desk face that desk's chair, whatever
## rotation the list gives them (models face +z at r=0, like the meeting room chairs).
func _oriented(d: Dictionary) -> Dictionary:
	var m := String(d.m)
	var p := Vector2(float(d.p[0]), float(d.p[1]))
	var face := Vector2.ZERO
	if m.begins_with("chair") and d.has("seat"):
		face = _seat_face(p, Vector2(sin(deg_to_rad(float(d.get("r", 0.0)))), cos(deg_to_rad(float(d.get("r", 0.0))))))
	elif m in ["computerScreen", "laptop"]:
		var best := 2.2
		for c in decor:
			if String(c.m).begins_with("chair") and c.has("seat"):
				var q := Vector2(float(c.p[0]), float(c.p[1]))
				if p.distance_to(q) < best: best = p.distance_to(q); face = (q - p).normalized()
		if face != Vector2.ZERO:
			face = Vector2(signf(face.x), 0) if absf(face.x) > absf(face.y) else Vector2(0, signf(face.y))
	if face == Vector2.ZERO: return d
	var out := d.duplicate()
	out.r = rad_to_deg(atan2(face.x, face.y))
	return out


func _seat_face(p: Vector2, fwd: Vector2) -> Vector2:
	# face the nearest table or desk; a chair on its own faces the way it points
	var best := INF; var face := fwd
	for d in decor:
		if not (String(d.m) in SEAT_TABLES): continue
		var q := Vector2(float(d.p[0]), float(d.p[1]))
		var dist := p.distance_to(q)
		if dist < best and dist < 2.2: best = dist; face = (q - p).normalized()
	if absf(face.x) > absf(face.y) * 2.0: face = Vector2(signf(face.x), 0)
	elif absf(face.y) > absf(face.x) * 2.0: face = Vector2(0, signf(face.y))
	return face


func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = INK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.88, 0.85, 0.95); env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true; env.glow_intensity = 0.35
	we.environment = env; world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-62), deg_to_rad(25), 0); sun.light_energy = 0.75; sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40
	world.add_child(sun)
	mg._box(Vector3(62, 0.1, 42), mg._tex_mat("concrete_tiles_02", Color(0.74, 0.7, 0.8), 0.35), Vector3(0, -0.05, 0))
	for rm in all_rooms():
		var r: Array = rm.r
		var c := Vector2((r[0] + r[2]) / 2.0, (r[1] + r[3]) / 2.0)
		var tex: String = MafiaGame.ROOM_TEX.get(rm.id, "laminate_floor_02")
		if rm.id == "storage": tex = "laminate_floor_02"
		mg._box(Vector3(r[2] - r[0], 0.02, r[3] - r[1]), mg._tex_mat(tex, MafiaGame.FLOOR_TINT.get(rm.id, Color.WHITE), MafiaGame.ROOM_SCALE.get(rm.id, 0.3)), V(c, 0.01))
		var l := Label3D.new()
		l.text = ROOM_NAMES.get(rm.id, rm.name); l.font = font; l.font_size = 120; l.outline_size = 0
		l.modulate = Color(1, 1, 1, 0.12); l.rotation.x = -PI / 2; l.pixel_size = 0.01; l.position = V(c, 0.045)
		l.width = (r[2] - r[0] - 1.0) * 100.0; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		world.add_child(l)
		room_labels[rm.id] = l
		# a lit sign on the room's back wall (the camera looks north, so the north wall faces it)
		var sign := Label3D.new()
		sign.text = ROOM_NAMES.get(rm.id, rm.name); sign.font = font; sign.font_size = 64
		sign.modulate = CYAN.lightened(0.25); sign.outline_modulate = BRAND.darkened(0.2); sign.outline_size = 14
		sign.pixel_size = 0.0075; sign.position = Vector3(c.x, 1.75, float(r[1]) + 0.25)
		sign.width = (r[2] - r[0] - 2.0) / 0.0075; sign.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		world.add_child(sign)
		room_signs[rm.id] = sign
		var om := OmniLight3D.new(); om.position = V(c, 3.2); om.omni_range = 13.0; om.light_energy = 0.8
		om.light_color = Color(1.0, 0.96, 0.92); world.add_child(om)
	var wall_m := mg._tex_mat("grey_plaster", Color(0.94, 0.92, 0.98), 0.5)
	var top_m := mg._mat(BRAND, 0.5, 0.9)
	var glow_m := mg._mat(CYAN, 0.3, 2.2)
	for w in sim.walls:
		if not (w.size.x < 0.5 or w.size.y < 0.5): continue   # furniture: drawn from the decor list
		var c: Vector2 = w.get_center()
		mg._box(Vector3(w.size.x, 1.35, w.size.y), wall_m, V(c, 0.675))
		mg._box(Vector3(w.size.x + 0.02, 0.06, w.size.y + 0.02), top_m, V(c, 1.35))
		mg._box(Vector3(w.size.x + 0.03, 0.02, w.size.y + 0.03), glow_m, V(c, 1.39))   # a thin cyan light along every wall top
	for d in decor: mg._decor(_oriented(d))
	for s in seats:
		if s.get("chair", false):
			mg._decor({m = "chairDesk", p = [s.p.x, s.p.y], r = rad_to_deg(atan2(-s.p.x, -s.p.y)), s = [0.8, 0.8, 1.0]})
	for p in [[-13, -19], [13, -19], [-13, 19], [13, 19], [-13, -6.5], [13, 8.5]]:
		mg._decor({m = "pottedPlant", p = p, s = [0.7, 0.7, 1.6]})
	_build_brand()
	_build_ceo_office()
	_build_game_room()
	_build_tea_bar()
	_build_meeting_screen()
	# the hearing circle round you: people inside it hear you
	my_ring = MeshInstance3D.new()
	var tor := TorusMesh.new(); tor.inner_radius = HEAR - 0.06; tor.outer_radius = HEAR; tor.rings = 64; tor.ring_segments = 4
	my_ring.mesh = tor
	var rm := mg._mat(CYAN, 0.5, 1.2); rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; rm.albedo_color.a = 0.35
	my_ring.material_override = rm
	world.add_child(my_ring)


func _sprite(tex_path: String, size_m: float, pos: Vector3, flat := false, alpha := 1.0) -> Sprite3D:
	var tex: Texture2D = load(tex_path)
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = size_m / maxf(float(tex.get_width()), 1.0)
	s.position = pos
	s.modulate = Color(1, 1, 1, alpha)
	s.shaded = false; s.double_sided = false
	if flat: s.rotation.x = -PI / 2
	world.add_child(s)
	return s


func _build_ceo_office() -> void:
	# the BNB mark on the wall behind the desk, a nameplate and a dark rug
	_sprite("res://assets/brand/bnb_mark_trim.png", 1.3, Vector3(-2.2, 1.85, -19.74))
	var plate := Label3D.new()
	plate.text = "CHIEF EXECUTIVE"; plate.font = font; plate.font_size = 40; plate.modulate = Color(1.0, 0.86, 0.55)
	plate.outline_size = 8; plate.outline_modulate = INK; plate.pixel_size = 0.005; plate.position = Vector3(0.0, 0.84, -15.94)
	world.add_child(plate)
	mg._box(Vector3(5.2, 0.04, 4.2), mg._mat(BRAND.darkened(0.45), 0.85), Vector3(0, 0.06, -16.2))
	mg._box(Vector3(5.4, 0.04, 4.4), mg._mat(Color(1.0, 0.82, 0.45), 0.4, 0.6), Vector3(0, 0.03, -16.2))


func _build_brand() -> void:
	# the BNB mark: big in the reception floor, on the front desk, and the wordmark in the hallway
	var rug := mg._mat(INK.lightened(0.08), 0.8)
	mg._box(Vector3(4.6, 0.04, 3.2), rug, Vector3(0, 0.06, 17.6))   # floor top is 0.02: keep clear gaps between layers
	mg._box(Vector3(4.8, 0.04, 3.4), mg._mat(CYAN, 0.4, 1.6), Vector3(0, 0.03, 17.6))
	_sprite("res://assets/brand/bnb_mark_trim.png", 2.4, Vector3(0, 0.1, 17.6), true)
	_sprite("res://assets/brand/bnb_mark_trim.png", 0.75, Vector3(-1.2, 0.62, 15.78))
	var w := Label3D.new()
	w.text = "BIT & BYTES"; w.font = font; w.font_size = 48; w.modulate = Color(1, 1, 1, 0.95)
	w.outline_size = 0; w.pixel_size = 0.006; w.position = Vector3(0.9, 0.62, 15.78)
	world.add_child(w)
	_sprite("res://assets/brand/bnb_wordmark_light.png", 7.0, Vector3(0, 0.06, 9.6), true, 0.55)
	_sprite("res://assets/brand/bnb_mark_trim.png", 1.6, Vector3(0, 0.06, -9.6), true, 0.5)


func _build_tea_bar() -> void:
	var sign := Label3D.new()
	sign.text = "TEA  ·  CHAI  ·  COFFEE"; sign.font = font; sign.font_size = 44; sign.modulate = Color(1.0, 0.85, 0.55)
	sign.outline_modulate = BRAND.darkened(0.3); sign.outline_size = 12; sign.pixel_size = 0.007
	sign.position = Vector3(-25.0, 1.95, -19.75)
	world.add_child(sign)
	for x in [-26.6, -25.6, -24.4, -23.4]:   # cups waiting on the bar
		var cup := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.06; cm.bottom_radius = 0.05; cm.height = 0.11
		cup.mesh = cm; cup.material_override = mg._mat(Color(0.98, 0.97, 0.95), 0.3); cup.position = Vector3(x, 1.06, -18.95)
		world.add_child(cup)


func _build_meeting_screen() -> void:
	# a big screen on the meeting room's north wall, showing the BNB wordmark
	mg._box(Vector3(3.2, 1.8, 0.08), mg._mat(Color(0.05, 0.05, 0.07), 0.3), Vector3(-4.5, 1.55, -6.72))
	mg._box(Vector3(3.0, 1.62, 0.02), mg._mat(INK.lightened(0.05), 0.5, 0.6), Vector3(-4.5, 1.55, -6.66))
	_sprite("res://assets/brand/bnb_wordmark_light.png", 2.6, Vector3(-4.5, 1.55, -6.64))


func _build_game_room() -> void:
	var g := Label3D.new()
	g.text = "GAME ROOM"; g.font = font; g.font_size = 90; g.modulate = Color(1.0, 0.9, 0.4)
	g.outline_modulate = BRAND.darkened(0.3); g.outline_size = 16; g.pixel_size = 0.006
	g.position = Vector3(22.0, 2.15, -3.75)
	world.add_child(g)
	for d in decor:
		if not d.has("game") or d.has("seat"): continue
		var p := Vector2(float(d.p[0]), float(d.p[1]))
		var top := float(d.s[2]) + 0.01
		match String(d.game):
			"carrom":
				mg._box(Vector3(1.2, 0.04, 1.2), mg._mat(Color(0.25, 0.14, 0.07), 0.6), V(p, top))
				mg._box(Vector3(1.04, 0.045, 1.04), mg._mat(Color(0.93, 0.8, 0.58), 0.7), V(p, top + 0.012))
				for k in 4:
					var ang := TAU * k / 4.0 + PI / 4
					_disc(p + Vector2(cos(ang), sin(ang)) * 0.68, top + 0.042, 0.05, Color(0.05, 0.05, 0.05))
				for k in 9:
					var ang2 := TAU * k / 9.0
					_disc(p + Vector2(cos(ang2), sin(ang2)) * 0.12, top + 0.046, 0.03, [Color(0.95, 0.93, 0.88), Color(0.1, 0.1, 0.1)][k % 2])
				_disc(p, top + 0.046, 0.03, Color(0.85, 0.15, 0.2))
			"ludo":
				var cols := [Color(0.9, 0.2, 0.2), Color(0.2, 0.7, 0.3), Color(0.95, 0.8, 0.15), Color(0.2, 0.45, 0.9)]
				mg._box(Vector3(1.2, 0.03, 1.2), mg._mat(Color(0.97, 0.96, 0.93), 0.7), V(p, top))
				for k in 4:
					var off := Vector2(-0.3 if k % 2 == 0 else 0.3, -0.3 if k < 2 else 0.3)
					mg._box(Vector3(0.5, 0.035, 0.5), mg._mat(cols[k], 0.6), V(p + off, top + 0.012))
			"cards":
				mg._box(Vector3(1.3, 0.02, 1.3), mg._mat(Color(0.1, 0.42, 0.24), 0.9), V(p, top))
				for k in 5:
					var cardp := p + Vector2(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35))
					var card := mg._box(Vector3(0.12, 0.01, 0.17), mg._mat(Color(0.98, 0.98, 0.98), 0.4), V(cardp, top + 0.02 + k * 0.012))
					card.rotation.y = randf() * TAU
		var lab := Label3D.new()
		lab.text = String(GAMES[d.game].name); lab.font = font; lab.font_size = 52; lab.modulate = GAMES[d.game].col.lightened(0.2)
		lab.outline_size = 12; lab.outline_modulate = Color(0, 0, 0, 0.8); lab.pixel_size = 0.006
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lab.position = V(p, 1.9)
		world.add_child(lab)
	for a in ARCADES:
		var z: float = a[1]
		var info: Dictionary = GAMES[a[0]]
		mg._box(Vector3(1.0, 1.75, 1.0), mg._mat(Color(0.09, 0.07, 0.14), 0.4), Vector3(29.6, 0.875, z))
		mg._box(Vector3(1.02, 0.1, 1.02), mg._mat(info.col, 0.3, 2.4), Vector3(29.6, 1.78, z))
		mg._box(Vector3(0.04, 0.6, 0.78), mg._mat(info.col.darkened(0.35), 0.2, 1.6), Vector3(29.08, 1.25, z))
		mg._box(Vector3(0.3, 0.06, 0.8), mg._mat(Color(0.2, 0.18, 0.26), 0.5), Vector3(28.95, 0.92, z))
		var lab := Label3D.new()
		lab.text = String(info.name); lab.font = font; lab.font_size = 40; lab.modulate = Color.WHITE
		lab.outline_size = 10; lab.outline_modulate = info.col.darkened(0.5); lab.pixel_size = 0.005
		lab.position = Vector3(29.05, 1.25, z); lab.rotation.y = -PI / 2
		world.add_child(lab)


func _disc(p: Vector2, y: float, r: float, col: Color) -> void:
	var m := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = r; cm.bottom_radius = r; cm.height = 0.012
	m.mesh = cm; m.material_override = mg._mat(col, 0.5); m.position = V(p, y)
	world.add_child(m)


static func V(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


func set_rooms(r: Dictionary) -> void:
	for id in r:
		rooms[id] = r[id]
		var nm := String(r[id].get("name", id)).to_upper()
		if room_labels.has(id): (room_labels[id] as Label3D).text = nm
		if room_signs.has(id): (room_signs[id] as Label3D).text = nm


func all_rooms() -> Array:
	return MafiaSim.ROOMS + EXTRA_ROOMS


func room_at(p: Vector2) -> String:
	for rm in all_rooms():
		var r: Array = rm.r
		if p.x >= r[0] and p.x <= r[2] and p.y >= r[1] and p.y <= r[3]: return rm.id
	return "hall"


# ---------------------------------------------------------------- people
## Hub usernames that differ from the character ids in data/bnb_roster.json.
const ALIASES := {"abdulwasay_waqas": "abdul_wasay_waqas", "kashaf_duja": "kashaf_ud_duja", "nauman_nawaz": "muhammad_nauman_nawaz",
	"saad_shafqat": "muhammad_saad", "sabir_din": "sabir_ud_din", "sarfaraz_yousaf": "sarfraz_yousaf"}


## The character for a hub user: their own (by username, alias or exact name); an admin without
## one plays Hamza Khan, anyone else Ali (real roster bodies, so they walk and sit like everyone).
func character_for(u: String, name: String, admin := false) -> Dictionary:
	var want: String = ALIASES.get(u, u)
	var n := _norm(name)
	for C in Data.ROSTER:
		if String(C.id) == want: return C
	for C in Data.ROSTER:
		if n != "" and _norm(C.name) == n: return C
	return _stand_in("hamza_khan" if admin else "ali")


func _stand_in(id: String) -> Dictionary:
	return Data.by_id(id)


static func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or ch == " " else " "
	return " ".join(out.split(" ", false))


func _costume_count(C: Dictionary) -> int:
	return maxi(1, Models.costume_names(String(C.id)).size())


func _add_person(p: Dictionary) -> void:
	var id := int(p.id)
	if id == int(me.get("id", -1)) or people.has(id): return
	var C := character_for(String(p.get("u", "")), String(p.get("name", "")), bool(p.get("admin", false)))
	var costume := clampi(int(p.get("costume", 0)), 0, _costume_count(C) - 1)
	var rig := Main.make_rig(C, costume)
	world.add_child(rig)
	var pos := Vector2(float(p.get("x", 0.0)), float(p.get("z", 16.0)))
	rig.position = V(pos)
	var tag := _tag(String(p.get("name", "?")))
	var foot := MeshInstance3D.new()
	var cyl := CylinderMesh.new(); cyl.top_radius = 0.55; cyl.bottom_radius = 0.55; cyl.height = 0.02
	foot.mesh = cyl; foot.material_override = mg._mat(CYAN, 0.4, 1.5); foot.visible = false
	world.add_child(foot)
	people[id] = {rig = rig, tag = tag, foot = foot, pos = pos, goal = pos, dir = Vector2(float(p.get("dx", 0.0)), float(p.get("dz", 1.0))),
		moving = false, name = String(p.get("name", "")), status = String(p.get("status", "working")), talk = 0.0, t = randf() * 5.0, C = C,
		act = String(p.get("act", "")), act_t = 0.0, costume = costume, party = String(p.get("party", "")), room = String(p.get("room", "")),
		dress = party.dress(String(p.get("party", ""))) if String(p.get("party", "")) != "" else null}
	_restatus(id)


func _set_look(id: int, costume: int) -> void:
	if not people.has(id): return
	var v: Dictionary = people[id]
	costume = clampi(costume, 0, _costume_count(v.C) - 1)
	if costume == int(v.costume): return
	(v.rig as Node).queue_free()
	var rig := Main.make_rig(v.C, costume)
	world.add_child(rig)
	rig.position = V(v.pos)
	v.rig = rig; v.costume = costume


func _tag(text: String) -> Label3D:
	var tag := Label3D.new()
	tag.text = text; tag.font = small; tag.font_size = 54; tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tag.no_depth_test = true; tag.pixel_size = 0.006
	world.add_child(tag)
	return tag


func _act_label(act: String) -> String:
	if act.begins_with("sit:"):
		var s: Dictionary = seats[clampi(int(act.substr(4)), 0, seats.size() - 1)]
		if s.kind == "game": return "playing " + String(GAMES[s.game].name).capitalize()
		if s.kind == "cafe": return "on a tea break"
		return ""
	if act.begins_with("st:"):
		var st: Dictionary = stations[clampi(int(act.substr(3)), 0, stations.size() - 1)]
		match String(st.kind):
			"tea": return "having tea"
			"present": return "presenting"
			"arcade": return "playing " + String(GAMES[st.game].name).capitalize()
	return ""


func _restatus(id: int) -> void:
	var v: Dictionary = people[id]
	var st: String = v.status
	var doing := _act_label(String(v.act))
	var extra := {"break": "on a break", "focus": "focusing", "call": "in a call", "away": "away", "off": "off today"}.get(st, "") if st != "working" else ""
	if doing != "" and st != "call" and st != "focus": extra = doing
	var pk := String(v.get("party", ""))
	if pk != "": extra = ("birthday today!" if pk == "birthday" else "work anniversary!") + ("" if extra == "" else "  · " + extra)
	(v.tag as Label3D).text = "● " + _first_two(v.name) + ("" if extra == "" else "  · " + extra)
	(v.tag as Label3D).modulate = STATUS_COL.get(st, Color.WHITE).lerp(Color.WHITE, 0.35)


static func _first_two(n: String) -> String:
	var w := n.split(" ", false)
	return " ".join(w.slice(0, 2)) if w.size() > 2 else n


func _remove_person(id: int) -> void:
	if not people.has(id): return
	var v: Dictionary = people[id]
	(v.rig as Node).queue_free(); (v.tag as Node).queue_free(); (v.foot as Node).queue_free()
	if v.get("dress") != null: (v.dress as Node).queue_free()
	people.erase(id)


func _init_me(m: Dictionary, spawn: Array) -> void:
	me = m
	if my_rig != null: my_rig.queue_free()
	if my_tag != null: my_tag.queue_free()
	var C := character_for(String(m.get("u", "")), String(m.get("name", "")), bool(m.get("admin", false)))
	my_costume = clampi(int(m.get("costume", 0)), 0, _costume_count(C) - 1)
	my_rig = Main.make_rig(C, my_costume)
	my_rig.set_meta("C", C)
	world.add_child(my_rig)
	my_tag = _tag("YOU")
	my_tag.modulate = CYAN.lightened(0.3)
	if my_dress != null: my_dress.queue_free()
	my_dress = null
	var pk := String(m.get("party", ""))
	if pk != "":
		my_tag.text = "YOU  · happy birthday!" if pk == "birthday" else "YOU  · happy work anniversary!"
		my_tag.modulate = Color(1.0, 0.85, 0.45)
		my_dress = party.dress(pk)
	if spawn.size() == 2: my_pos = Vector2(float(spawn[0]), float(spawn[1]))
	var tries := 0
	while sim.blocked(my_pos, RADIUS) and tries < 40:   # never start inside a desk
		my_pos += Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)); tries += 1
	cam.position = Vector3.ZERO
	(layer.get_node("bg") as Control).visible = false
	loading.visible = false
	_post({t = "costumes", names = Models.costume_names(String(C.id)), current = my_costume})


func _set_my_costume(i: int) -> void:
	if my_rig == null: return
	var C: Dictionary = my_rig.get_meta("C")
	i = clampi(i, 0, _costume_count(C) - 1)
	if i == my_costume: return
	my_costume = i
	var old := my_rig
	my_rig = Main.make_rig(C, my_costume)
	my_rig.set_meta("C", C)
	world.add_child(my_rig)
	my_rig.position = old.position; my_rig.rotation = old.rotation
	old.queue_free()
	_post({t = "look", costume = my_costume})


# ---------------------------------------------------------------- what you can do here
func _taken(act: String) -> bool:
	for id in people:
		if String(people[id].act) == act: return true
	return false


## The nearest thing within reach you could do: ["sit:3", "Sit down"] or ["", ""].
func _nearby() -> Array:
	var best := REACH; var out := ["", ""]
	if _ceo_closed() and my_pos.distance_to(CEO_DOOR) < 3.0:
		return ["knock", "Knock on the CEO office door"]
	for i in seats.size():
		var s: Dictionary = seats[i]
		var d := my_pos.distance_to(s.p)
		if d < best and not _taken("sit:%d" % i):
			best = d
			out = ["sit:%d" % i, ("Play " + String(GAMES[s.game].name).capitalize()) if s.kind == "game" else ("Sit down" if s.kind != "cafe" else "Sit with a cup of tea")]
	for i in stations.size():
		var st: Dictionary = stations[i]
		var d := my_pos.distance_to(st.p)
		if d < best and not (st.solo and _taken("st:%d" % i)):
			best = d; out = ["st:%d" % i, String(st.name)]
	return out


func _do(act: String) -> void:
	if act == "": return
	if act == "knock":
		_post({t = "knock"}); _emote("wave"); return
	var p := Vector2.INF; var face := my_dir
	if act.begins_with("sit:"):
		var s: Dictionary = seats[int(act.substr(4))]; p = s.p; face = s.face
	elif act.begins_with("st:"):
		var st: Dictionary = stations[int(act.substr(3))]; p = st.p; face = st.face
	if p != Vector2.INF:
		my_pos = p; my_dir = face
	target = Vector2.INF; pending = ""
	_set_act(act)


func _set_act(act: String) -> void:
	var was := _game_of(my_act)
	my_act = act; my_act_t = 0.0
	var dk := desks.desk_of_seat(int(act.substr(4))) if act.begins_with("sit:") else ""
	if dk != my_desk:
		my_desk = dk
		var row := desks.row_for(dk)
		_post({t = "desk", desk = dk, owner = row.get("id"), name = row.get("name", ""), party = row.get("party", "")})
	var now := _game_of(act)
	if now != was:   # at a game table / arcade: the hub offers to open the real game (create or join a room)
		var C: Dictionary = my_rig.get_meta("C", {}) if my_rig != null else {}
		_post({t = "play", game = now, name = String(GAMES[now].name).capitalize() if now != "" else "",
			table = (("arcade:" if act.begins_with("st:") else "table:") + now) if now != "" else "",
			char = String(C.get("id", ""))})


## The game this action plays ("" if none): a seat at a game table or an arcade machine.
func _game_of(act: String) -> String:
	if act.begins_with("sit:"):
		var i := int(act.substr(4))
		return String(seats[i].get("game", "")) if i < seats.size() else ""
	if act.begins_with("st:"):
		var j := int(act.substr(3))
		return String(stations[j].get("game", "")) if j < stations.size() else ""
	return ""


func _stand_up() -> void:
	if not my_act.begins_with("sit:") and not my_act.begins_with("st:"):
		_set_act(""); return
	# step off the chair (it may be tucked under a table) onto the nearest free spot
	var back := -my_dir
	for r in [0.7, 1.0, 1.3, 1.7]:
		for a in [0.0, 0.6, -0.6, 1.3, -1.3, PI]:
			var q: Vector2 = my_pos + back.rotated(a) * r
			if not sim.blocked(q, RADIUS):
				my_pos = q; _set_act(""); return
	_set_act("")


func _act_key() -> void:
	if my_act.begins_with("sit:") or my_act.begins_with("st:"): _stand_up(); return
	var n := _nearby()
	if n[0] != "": _do(n[0])


func _emote(e: String) -> void:
	if not EMOTES.has(e) or my_rig == null: return
	if my_act.begins_with("sit:"): return      # emotes are standing moves
	if my_act.begins_with("st:"): _stand_up()
	target = Vector2.INF
	_set_act("e:" + e)


func _update_prompt() -> void:
	var text := ""; var can := false
	if my_act.begins_with("sit:") or my_act.begins_with("st:"):
		var lab := _act_label(my_act)
		text = "Stand up" if lab == "" else "Stand up · you're " + lab
		can = true
	elif not my_moving:
		var n := _nearby()
		if n[0] != "": text = n[1]; can = true
	if text != _prompt:
		_prompt = text
		_post({t = "prompt", text = text, act = can})


# ---------------------------------------------------------------- hub messages
func _on_js(args) -> void:
	var ev = args[0]
	if str(ev.origin) != origin: return
	var raw = ev.data
	if typeof(raw) != TYPE_STRING: return
	var d = JSON.parse_string(raw)
	if typeof(d) != TYPE_DICTIONARY: return
	_message(d)


func _message(d: Dictionary) -> void:
	if not ready_done: return
	match String(d.get("t", "")):
		"init":
			for id in people.keys(): _remove_person(id)
			if d.has("rooms"): set_rooms(d.rooms)
			party.build(d.get("party", []))
			_init_me(d.me, d.get("spawn", []))
			for p in d.get("people", []): _add_person(p)
			desk_list = d.get("desks", [])
			_show_desks()
			if d.get("arrive", false):        # a fresh arrival starts at their own desk
				var at := desks.arrival(String(desks.by_owner.get(int(me.get("id", -1)), "")))
				if at != Vector2.INF and not sim.blocked(at, RADIUS): my_pos = at
		"join": _add_person(d.person); _show_desks()
		"leave": _remove_person(int(d.id)); _show_desks()
		"desks": desk_list = d.get("desks", []); _show_desks()
		"state":
			for row in d.get("p", []):
				var id := int(row[0])
				if not people.has(id): continue
				var v: Dictionary = people[id]
				v.goal = Vector2(float(row[1]), float(row[2]))
				var dir := Vector2(float(row[3]), float(row[4]))
				if dir.length() > 0.1: v.dir = dir
				v.moving = int(row[5]) != 0
				if row.size() > 6: v.room = String(row[6])
				var act := String(row[7]) if row.size() > 7 else ""
				if act != String(v.act):
					v.act = act; v.act_t = 0.0; _restatus(id)
		"status":
			var id := int(d.id)
			if people.has(id):
				people[id].status = String(d.status); _restatus(id); _show_desks()
		"look": _set_look(int(d.id), int(d.costume))
		"talk":
			var lv: Dictionary = d.get("levels", {})
			for k in lv:
				if people.has(int(k)): people[int(k)].talk = float(lv[k])
		"linked":
			linked.clear()
			for id in d.get("ids", []): linked[int(id)] = true
		"goto":
			if my_act != "": _stand_up()
			target = Vector2(float(d.x), float(d.z)); route_t = 0.0
		"rooms": set_rooms(d.rooms)
		"act": _act_key()
		"let_in": ceo_let_in = true
		"emote": _emote(String(d.get("e", "")))
		"costume": _set_my_costume(int(d.get("i", 0)))


## The CEO office is closed to you while someone else is in it, unless you're an admin or were let in.
func _ceo_closed() -> bool:
	if ceo_let_in or bool(me.get("admin", false)) or room_at(my_pos) == "ceo": return false
	for id in people:
		if String(people[id].get("room", "")) == "ceo": return true
	return false


func _blocked(p: Vector2) -> bool:
	return sim.blocked(p, RADIUS) or (room_at(p) == "ceo" and _ceo_closed())


## Desks, with the live status of whoever is in the office right now.
func _show_desks() -> void:
	var present := {}
	for id in people: present[id] = String(people[id].status)
	if me.has("id"): present[int(me.id)] = "here"
	desks.show(desk_list, present)


func _post(d: Dictionary) -> void:
	if not web: return
	JavaScriptBridge.get_interface("parent").postMessage(JSON.stringify(d), origin)


# ---------------------------------------------------------------- input and movement
func _unhandled_input(e: InputEvent) -> void:
	if my_rig == null: return
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		if k == KEY_E or k == KEY_ENTER: _act_key(); return
		var ei := EMOTE_KEYS.find(k)
		if ei >= 0: _emote(EMOTE_ORDER[ei]); return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed: zoom = clampf(zoom - 0.1, 0.55, 1.8); return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed: zoom = clampf(zoom + 0.1, 0.55, 1.8); return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pointer_down = mb.pressed
			if mb.pressed:
				var hit := _person_at(mb.position)
				if hit >= 0: _post({t = "person", id = hit}); pointer_down = false; return
				if _click_thing(mb.position): pointer_down = false; return
				_aim(mb.position)
	elif e is InputEventMouseMotion and pointer_down:
		_aim((e as InputEventMouseMotion).position)
	elif e is InputEventMagnifyGesture:
		zoom = clampf(zoom / (e as InputEventMagnifyGesture).factor, 0.55, 1.8)


func _ground(screen: Vector2) -> Vector2:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.001: return Vector2.INF
	var t := -from.y / dir.y
	if t <= 0: return Vector2.INF
	var hit := from + dir * t
	return Vector2(hit.x, hit.z)


## Clicked on a chair / the tea bar / an arcade: walk there and use it.
func _click_thing(screen: Vector2) -> bool:
	var g := _ground(screen)
	if g == Vector2.INF: return false
	var best := 0.75; var act := ""
	for i in seats.size():
		var d := g.distance_to(seats[i].p)
		if d < best and not _taken("sit:%d" % i): best = d; act = "sit:%d" % i
	for i in stations.size():
		var d := g.distance_to(stations[i].p)
		if d < best and not (stations[i].solo and _taken("st:%d" % i)): best = d; act = "st:%d" % i
	if act == "": return false
	if my_act != "": _stand_up()
	pending = act
	var spot: Vector2 = seats[int(act.substr(4))].p if act.begins_with("sit:") else stations[int(act.substr(3))].p
	target = spot; route_t = 0.0
	return true


## The next point to head for on the way from a to b: b itself when the way is clear, otherwise a
## waypoint along the shortest way round (waypoints you can actually reach, not ones behind a wall).
func _route_next(a: Vector2, b: Vector2) -> Vector2:
	if sim.clear(a, b, RADIUS): return b
	var start := _reach_wp(a); var goal := _reach_wp(b)
	if start < 0 or goal < 0 or start == goal: return b if start == goal else a
	var prev := {start: -1}; var q := [start]; var head := 0
	while head < q.size():
		var c: int = q[head]; head += 1
		if c == goal: break
		for nb in sim.links[c]:
			if not prev.has(nb): prev[nb] = c; q.append(nb)
	if not prev.has(goal): return b
	var path := [goal]
	while prev[path[0]] != -1: path.push_front(prev[path[0]])
	# skip ahead to the furthest waypoint we can walk straight to
	var best: Vector2 = sim.waypoints[path[0]]
	for i in range(1, mini(path.size(), 10)):
		var wp: Vector2 = sim.waypoints[path[i]]
		if sim.clear(a, wp, RADIUS): best = wp
		else: break
	return best


func _reach_wp(p: Vector2) -> int:
	var cand := []
	for i in sim.waypoints.size():
		var d: float = sim.waypoints[i].distance_squared_to(p)
		if d < 9.0: cand.append([d, i])
	cand.sort_custom(func(x, y): return x[0] < y[0])
	for c in cand:
		if sim.clear(p, sim.waypoints[c[1]], RADIUS - 0.05): return c[1]
	return cand[0][1] if not cand.is_empty() else -1


func _aim(screen: Vector2) -> void:
	var g := _ground(screen)
	if g == Vector2.INF: return
	if my_act.begins_with("sit:") or my_act.begins_with("st:"): _stand_up()
	pending = ""
	target = g; route_t = 0.0


func _person_at(screen: Vector2) -> int:
	var best := -1; var best_d := 40.0
	for id in people:
		var v: Dictionary = people[id]
		var sp := cam.unproject_position(V(v.pos, 1.0))
		var dd := sp.distance_to(screen)
		if dd < best_d and not cam.is_position_behind(V(v.pos, 1.0)): best = id; best_d = dd
	return best


func _keys() -> Vector2:
	if not get_window().has_focus(): return Vector2.ZERO
	var k := func(keys: Array) -> bool:
		for key in keys:
			if Input.is_physical_key_pressed(key): return true
		return false
	return Vector2((1.0 if k.call([KEY_D, KEY_RIGHT]) else 0.0) - (1.0 if k.call([KEY_A, KEY_LEFT]) else 0.0),
		(1.0 if k.call([KEY_S, KEY_DOWN]) else 0.0) - (1.0 if k.call([KEY_W, KEY_UP]) else 0.0))


func _physics_process(dt: float) -> void:
	if my_rig == null: return
	var mv := _keys()
	if mv != Vector2.ZERO:
		target = Vector2.INF; pending = ""
		if my_act != "" and not my_act.begins_with("e:"): _stand_up()
		elif my_act.begins_with("e:"): _set_act("")
	elif target != Vector2.INF:
		if room_at(target) == "ceo" and _ceo_closed():     # someone's in: walk to the door and knock
			target = CEO_DOOR; pending = ""
		var to := target - my_pos
		if to.length() < 0.25 or (pending != "" and to.length() < 0.9):
			target = Vector2.INF
			if pending != "": _do(pending)
		else:
			# head for the next waypoint on the way (re-planned a few times a second, not every frame)
			route_t -= dt
			if route_t <= 0.0 or my_pos.distance_to(route_step) < 0.4:
				route_t = 0.3; route_step = _route_next(my_pos, target)
			mv = (route_step - my_pos).normalized() if my_pos.distance_to(route_step) > 0.05 else to.normalized()
	var seated := my_act.begins_with("sit:") or my_act.begins_with("st:")
	var running := Input.is_physical_key_pressed(KEY_SHIFT) or (target != Vector2.INF and my_pos.distance_to(target) > 8.0)
	my_moving = mv.length() > 0.1 and not seated
	if my_moving:
		mv = mv.normalized()
		my_dir = mv
		var step := mv * (RUN if running else WALK) * dt
		var np := my_pos + step
		if not _blocked(np): my_pos = np
		elif not _blocked(my_pos + Vector2(step.x, 0)): my_pos += Vector2(step.x, 0)
		elif not _blocked(my_pos + Vector2(0, step.y)): my_pos += Vector2(0, step.y)
		elif pending != "" and my_pos.distance_to(target) < 1.8: target = Vector2.INF; _do(pending)
		else:
			# bumped into something: re-plan right away, and only give up after a second of being stuck
			stuck_t += dt; route_t = 0.0
			if stuck_t > 1.0: target = Vector2.INF; my_moving = false; pending = ""; stuck_t = 0.0
	if not my_moving or mv == Vector2.ZERO: stuck_t = 0.0
	# an emote plays once (a dance twice), then you're back to standing
	if my_act.begins_with("e:"):
		my_act_t += dt
		var clip: String = EMOTES.get(my_act.substr(2), "in_wave")
		if my_act_t > Fighter._len(clip) * (2.0 if clip == "in_dance" else 1.0): _set_act("")
	else:
		my_act_t += dt
	_update_prompt()
	var room := room_at(my_pos)
	if my_room == "ceo" and room != "ceo": ceo_let_in = false     # leaving: next time you knock again
	_send_t -= dt
	var now := {x = snappedf(my_pos.x, 0.01), z = snappedf(my_pos.y, 0.01), dx = snappedf(my_dir.x, 0.01), dz = snappedf(my_dir.y, 0.01), m = 1 if my_moving else 0, room = room, a = my_act}
	if _send_t <= 0.0 and (now != _sent or room != my_room):
		_send_t = 0.1
		_sent = now; my_room = room
		_post({t = "pos", x = now.x, z = now.z, dx = now.dx, dz = now.dz, m = now.m, room = room, a = my_act})


## What someone doing `act` looks like (plus whether they're talking, for the meeting room).
func _act_clip(act: String, talking: bool, status: String, moving: bool) -> String:
	if act.begins_with("sit:"):
		var s: Dictionary = seats[clampi(int(act.substr(4)), 0, seats.size() - 1)]
		match String(s.kind):
			"desk": return "m_type"
			"game": return "m_type"
			"meet", "visit": return "m_sit_talk" if talking else "m_sit"
			"cafe": return "m_sit_talk" if talking else "m_sit"
			_: return "m_sit"
	if act.begins_with("st:"):
		var st: Dictionary = stations[clampi(int(act.substr(3)), 0, stations.size() - 1)]
		match String(st.kind):
			"tea": return "in_drinking"
			"present": return "in_point" if talking else "in_thinking"
			"arcade": return "in_tablet"
	if act.begins_with("e:"): return EMOTES.get(act.substr(2), "idle_relaxed")
	if moving: return "m_walk"
	if status == "call": return "in_phone"
	if status == "focus": return "m_type"
	return "idle_relaxed"


func _act_place(act: String) -> Array:
	# [position, facing] while sitting or standing at something, else []
	if act.begins_with("sit:"):
		var s: Dictionary = seats[clampi(int(act.substr(4)), 0, seats.size() - 1)]
		return [s.p, s.face]
	if act.begins_with("st:"):
		var st: Dictionary = stations[clampi(int(act.substr(3)), 0, stations.size() - 1)]
		return [st.p, st.face]
	return []


func _process(dt: float) -> void:
	if my_rig == null: return
	if demo: _demo_tick(dt)
	_anim_t += dt
	my_rig.position = V(my_pos)
	my_rig.rotation.y = lerp_angle(my_rig.rotation.y, atan2(my_dir.x, my_dir.y), clampf(dt * 12.0, 0.0, 1.0))
	var C: Dictionary = my_rig.get_meta("C")
	var running := Input.is_physical_key_pressed(KEY_SHIFT) or (target != Vector2.INF and my_pos.distance_to(target) > 8.0)
	var my_clip := ("m_run" if running else "m_walk") if my_moving else _act_clip(my_act, false, "working", false)
	_animate(my_rig, C, my_clip, my_act_t if my_act != "" else _anim_t)
	my_tag.position = V(my_pos, 2.35 * float(C.get("scale", 1.0)))
	party.tick(dt)
	if my_dress != null:
		my_dress.position = my_rig.position; my_dress.rotation.y = my_rig.rotation.y
	my_ring.position = V(my_pos, 0.05)
	my_ring.visible = not (my_room in PRIVATE_ROOMS)   # a private room is one conversation, whatever the distance
	for id in people:
		var v: Dictionary = people[id]
		var goal: Vector2 = v.goal
		var pos: Vector2 = v.pos
		pos = goal if pos.distance_to(goal) > 8.0 else pos.lerp(goal, clampf(dt * 8.0, 0.0, 1.0))
		v.pos = pos
		var moving: bool = v.moving or pos.distance_to(goal) > 0.15
		var rig: Node3D = v.rig
		var place := _act_place(String(v.act))
		var dir: Vector2 = v.dir
		if place.size() == 2 and not moving:
			rig.position = V(place[0]); dir = place[1]
		else:
			rig.position = V(pos)
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(dir.x, dir.y), clampf(dt * 10.0, 0.0, 1.0))
		v.t += dt; v.act_t += dt
		var talking: bool = float(v.talk) > 0.08
		var clip := _act_clip(String(v.act), talking, String(v.status), moving)
		_animate(rig, v.C, clip, v.act_t if String(v.act) != "" else v.t)
		var tag: Label3D = v.tag
		tag.position = Vector3(rig.position.x, 2.35 * float(v.C.get("scale", 1.0)), rig.position.z)
		if v.dress != null:
			(v.dress as Node3D).position = rig.position; (v.dress as Node3D).rotation.y = rig.rotation.y
		var talk: float = v.talk
		tag.scale = Vector3.ONE * (1.0 + 0.12 * clampf(talk * 3.0, 0.0, 1.0))
		var foot: MeshInstance3D = v.foot
		foot.position = Vector3(rig.position.x, 0.03, rig.position.z)
		foot.visible = linked.has(id)
		foot.scale = Vector3.ONE * (1.0 + 0.35 * clampf(talk * 3.0, 0.0, 1.0))
	var focus := V(my_pos)
	var want := focus + Vector3(0, 11.0, 7.5) * zoom
	cam.position = cam.position.lerp(want, clampf(dt * 6.0, 0.0, 1.0)) if cam.position != Vector3.ZERO else want
	cam.look_at(focus + Vector3(0, 0.8, 0), Vector3.UP)


func _animate(rig, C: Dictionary, clip: String, t: float) -> void:
	if not ClipLib.has(clip): clip = "idle_relaxed"
	rig.set_clip(clip, fmod(t, Fighter._len(clip)), true, false)
	rig.apply_pose(C.pose.guard, true)


# ---------------------------------------------------------------- demo (outside a browser)
func _start_demo() -> void:
	demo = true
	set_rooms({})
	_init_me({id = 1, u = "abdul_wasay", name = "Abdul Wasay"}, [0, 16])
	var names := [["tuaha_aamir", "Tuaha Aamir"], ["sabir_din", "Sabir ud Din"], ["zia_khan", "Zia Khan"], ["kiran_fazal", "Kiran Fazal"]]
	for i in names.size():
		_add_person({id = 10 + i, u = names[i][0], name = names[i][1], x = -3.0 + i * 2.0, z = 13.0, status = ["working", "break", "focus", "working"][i]})
	linked[10] = true
	# show off the actions: one at tea, one at a game table, one presenting
	people[11].act = "st:0"
	people[12].act = "sit:%d" % _first_seat("game")
	people[13].act = "st:3"
	# desktop checks: `-- --party` shows the birthday decorations, `--at=x,z` moves you, `--shot=file.png` saves a picture
	var args := OS.get_cmdline_user_args()
	desk_list = [{desk = "dev:0", id = 10, name = "Tuaha Aamir", status = "in"}, {desk = "dev:1", id = 20, name = "Hira Ali", status = "leave"},
		{desk = "dev:2", id = 21, name = "Omar Farooq", status = "break"}, {desk = "dev:3", id = 22, name = "Sana Iqbal", status = "call"},
		{desk = "dev:4", id = 23, name = "Bilal Ahmed", status = "off"}, {desk = "dev:5", id = 24, name = "Ayesha Khan", status = "wfh", party = "birthday"},
		{desk = "dev:6", id = 1, name = "Abdul Wasay", status = "in"}]
	_show_desks()
	if args.has("--party"):
		party.build([{name = "Kiran Fazal", kind = "birthday", years = 0}, {name = "Zia Khan", kind = "anniversary", years = 3}])
		people[13].party = "birthday"; people[13].dress = party.dress("birthday"); people[13].act = ""; _restatus(13)
		people[12].party = "anniversary"; people[12].dress = party.dress("anniversary"); _restatus(12)
	for a in args:
		if a.begins_with("--at="):
			var xz := a.substr(5).split(",")
			my_pos = Vector2(float(xz[0]), float(xz[1]))
			for id in people: people[id].pos = my_pos + Vector2(id - 11.5, -1.5); people[id].goal = people[id].pos
		if a.begins_with("--shot="): _shot_later(a.substr(7))
		if a == "--knock":       # someone in the CEO office: you can't walk in, the prompt offers a knock
			people[13].room = "ceo"; people[13].pos = Vector2(0, -15); people[13].goal = people[13].pos
			my_pos = Vector2(0, -9.5); target = Vector2(0, -15)


func _shot_later(path: String) -> void:
	await get_tree().create_timer(4.0).timeout
	print("prompt: ", _prompt, " at ", my_pos, " closed ", _ceo_closed(), " moving ", my_moving, " target ", target, " act ", my_act)
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _first_seat(kind: String) -> int:
	for i in seats.size():
		if seats[i].kind == kind: return i
	return 0


func _demo_tick(dt: float) -> void:
	demo_t -= dt
	if demo_t > 0.0: return
	demo_t = 2.5
	for id in people:
		var v: Dictionary = people[id]
		if String(v.act) == "" and randf() < 0.5:
			var g: Vector2 = v.goal + Vector2(randf_range(-4, 4), randf_range(-4, 4))
			if not sim.blocked(g, RADIUS): v.goal = g; v.dir = (g - v.pos).normalized()
		people[id].talk = randf() if id == 10 else 0.0
