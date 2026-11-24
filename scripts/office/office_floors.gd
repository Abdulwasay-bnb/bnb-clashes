class_name OfficeFloors
extends RefCounted
## The building in the BNB Virtual Office: the company's two floors, the rooftop and the parking.
##
## The company has the 3rd floor (Sales and Management), the 4th floor (Development and every other
## department), rooftop access and the parking by the road. Each level is its own area of the map,
## side by side X apart (far enough that you never see or hear another level), and every level has
## the same lift lobby: lifts and stairs on its east wall. Take the lift to any level, or the stairs
## one level up or down (the 1st and 2nd floors aren't ours, so the stairs skip them).
##
## Rooms are in map coordinates. The hub (employees/office.py FIXED_ROOMS, ROOM_CENTRES, FLOOR_X)
## must match them.

const LEVELS := [0, 3, 4, 5]                     # in building order: parking, 3rd, 4th, rooftop
const X := {0: -120.0, 3: 120.0, 4: 0.0, 5: 240.0}
const NAMES := {0: "Parking", 3: "3rd floor", 4: "4th floor", 5: "Rooftop"}
const SHORT := {0: "P", 3: "3", 4: "4", 5: "R"}
const OPEN := [0, 5]                             # outdoors: a railing round the edge, rooms without walls
## In every lobby (local to the level, before LOBBY_SHIFT): where you call the lift / take the stairs,
## and where you come out. The lobby is [-8, 12, 8, 20] with lifts and stairs on its east wall; on the
## ground floor it's at the back of the building on the right, next to the banks.
const LIFT := Vector2(6.8, 15.0)
const LIFT_OUT := Vector2(5.4, 15.0)
const STAIRS := Vector2(4.4, 18.9)
const STAIRS_OUT := Vector2(3.4, 17.6)
const LOBBY_SHIFT := {0: Vector2(16.0, -32.0)}

const ROOMS := [
	# 4th floor: Development and every other department
	{id = "cafe", r = [-30, -20, -14, -8], doors = "es"},
	{id = "dev", r = [-30, -4, -14, 6], doors = "en"},
	{id = "lounge", r = [-30, 10, -14, 20], doors = "en"},
	{id = "wash4", r = [-7, -20, 7, -11], doors = "s", wash = true},
	{id = "pray4", r = [14, -20, 30, -8], doors = "s"},
	{id = "storage", r = [14, -4, 30, 6], doors = "wn"},
	{id = "print", r = [14, 10, 30, 20], doors = "wn"},
	{id = "board", r = [-8, -7, 8, 7], doors = "nsew"},
	{id = "reception", r = [-8, 12, 8, 20], doors = "n"},
	# 3rd floor: Sales (Business Development) and Management
	{id = "pantry", r = [90, -20, 106, -8], doors = "es"},
	{id = "booths", r = [90, -4, 106, 6], doors = "en"},
	{id = "hr", r = [90, 10, 106, 20], doors = "en"},
	{id = "ceo", r = [113, -20, 127, -11], doors = "s"},
	{id = "conf", r = [112, -7, 128, 7], doors = "nsew"},
	{id = "server", r = [134, -20, 150, -8], doors = "ws"},
	{id = "wash3", r = [134, -4, 150, 6], doors = "n", wash = true},
	{id = "pray3", r = [134, 10, 150, 20], doors = "n"},
	{id = "lobby3", r = [112, 12, 128, 20], doors = "n"},
	# rooftop
	{id = "bbq", r = [210, -20, 236, -2], open = true},
	{id = "smoke", r = [254, -20, 270, -4], open = true},
	{id = "sunset", r = [210, 4, 228, 20], open = true},
	{id = "garden", r = [254, 4, 270, 20], open = true},
	{id = "lobby5", r = [232, 12, 248, 20], doors = "n"},
	# parking, beside the road
	{id = "parking", r = [-150, -6, -90, 8], open = true},
	{id = "psmoke", r = [-129, -12, -115, -6], open = true},
	{id = "lobby0", r = [-112, -20, -96, -12], doors = "s"},
]
const ROOM_NAMES := {"cafe": "CAFETERIA", "dev": "DEVELOPMENT", "lounge": "FOCUS LOUNGE", "wash4": "WASHROOMS",
	"pray4": "PRAYER ROOM", "storage": "GAME ROOM", "print": "CREATIVE & QA", "board": "MEETING ROOM", "reception": "RECEPTION",
	"pantry": "PANTRY", "booths": "CALL BOOTHS", "hr": "MANAGEMENT", "ceo": "CEO OFFICE", "conf": "CONFERENCE ROOM",
	"server": "BUSINESS DEVELOPMENT", "wash3": "WASHROOMS", "pray3": "PRAYER ROOM", "lobby3": "LIFT LOBBY",
	"bbq": "BBQ TERRACE", "smoke": "SMOKING & VAPE AREA", "sunset": "SUNSET LOUNGE", "garden": "ROOF GARDEN", "lobby5": "ROOFTOP LIFTS",
	"parking": "PARKING", "psmoke": "SMOKING CORNER", "lobby0": "GROUND LOBBY"}
## Floor texture, tint and scale per room (textures in assets/textures).
const FLOOR := {
	"cafe": ["floor_tiles_06", Color(1.0, 0.93, 0.85), 0.35], "print": ["floor_tiles_06", Color(0.85, 0.88, 0.95), 0.35],
	"reception": ["floor_tiles_06", Color(0.95, 0.92, 1.0), 0.3], "storage": ["laminate_floor_02", Color(0.85, 0.8, 0.7), 0.3],
	"dev": ["laminate_floor_02", Color(0.95, 0.9, 0.85), 0.25], "board": ["laminate_floor_02", Color(0.8, 0.65, 0.6), 0.25],
	"conf": ["laminate_floor_02", Color(0.7, 0.62, 0.72), 0.25], "hr": ["dirty_carpet", Color(0.75, 0.6, 0.85), 0.4],
	"server": ["concrete_tiles_02", Color(0.6, 0.66, 0.74), 0.3], "lounge": ["dirty_carpet", Color(0.55, 0.7, 0.75), 0.4],
	"wash4": ["floor_tiles_06", Color(0.8, 0.9, 0.98), 0.5], "wash3": ["floor_tiles_06", Color(0.8, 0.9, 0.98), 0.5],
	"pray4": ["dirty_carpet", Color(0.45, 0.72, 0.55), 0.35], "pray3": ["dirty_carpet", Color(0.45, 0.72, 0.55), 0.35],
	"pantry": ["floor_tiles_06", Color(1.0, 0.9, 0.8), 0.35], "booths": ["dirty_carpet", Color(0.6, 0.6, 0.8), 0.4],
	"ceo": ["laminate_floor_02", Color(0.7, 0.55, 0.45), 0.25], "lobby3": ["floor_tiles_06", Color(0.95, 0.92, 1.0), 0.3],
	"lobby5": ["floor_tiles_06", Color(0.9, 0.9, 0.95), 0.3], "lobby0": ["floor_tiles_06", Color(0.9, 0.88, 0.85), 0.3],
	"bbq": ["laminate_floor_02", Color(0.62, 0.45, 0.32), 0.2], "sunset": ["laminate_floor_02", Color(0.7, 0.52, 0.38), 0.2],
	"smoke": ["concrete_tiles_02", Color(0.6, 0.6, 0.62), 0.3], "garden": ["dirty_carpet", Color(0.35, 0.6, 0.3), 0.5],
	"psmoke": ["concrete_tiles_02", Color(0.72, 0.68, 0.62), 0.3],
}
## The whole level's floor (under the rooms and halls).
const GROUND := {0: ["concrete_tiles_02", Color(0.3, 0.3, 0.33), 0.25], 3: ["concrete_tiles_02", Color(0.72, 0.7, 0.78), 0.35],
	4: ["concrete_tiles_02", Color(0.74, 0.7, 0.8), 0.35], 5: ["concrete_tiles_02", Color(0.55, 0.53, 0.55), 0.3]}

const INK := Color(0.082, 0.067, 0.114)
const BRAND := Color(0.404, 0.204, 0.576)
const CYAN := Color(0.149, 0.694, 0.808)
const CAR_COLS := [Color(0.92, 0.92, 0.94), Color(0.1, 0.1, 0.12), Color(0.6, 0.62, 0.66), Color(0.65, 0.1, 0.12),
	Color(0.15, 0.25, 0.55), Color(0.85, 0.85, 0.82), Color(0.3, 0.32, 0.3), Color(0.75, 0.6, 0.2)]

var main: OfficeMain            # OfficeMain
var mg: MafiaGame               # MafiaGame (box, material and furniture helpers)
var font: Font
var lights := {}               # level -> [lights]; only your level's are on (the web renderer draws a limited number)
var puffs := {}                # station index -> CPUParticles3D (smoke from whoever is smoking or vaping there)
var traffic: Array = []        # [{node, speed, lane}] on the road past the parking
var flames: Array = []         # [{light, base}] grill fires
var _t := 0.0
var always_puff := false       # desktop demo: keep the smoke coming (for pictures)


static func level_of(x: float) -> int:
	var best := 4; var bd := INF
	for l in LEVELS:
		var d := absf(float(X[l]) - x)
		if d < bd: bd = d; best = l
	return best


static func at(level: int, local: Vector2) -> Vector2:
	return local + Vector2(float(X[level]), 0.0)


## A point in a level's lobby (local lobby coordinates) on the map.
static func lobby(level: int, local: Vector2) -> Vector2:
	return at(level, local + LOBBY_SHIFT.get(level, Vector2.ZERO))


static func room(id: String) -> Dictionary:
	for rm in ROOMS:
		if rm.id == id: return rm
	return {}


## Where the stairs go from a level: one level down and one up.
static func stairs_to(level: int) -> Array:
	var i := LEVELS.find(level)
	var out := []
	if i > 0: out.append(LEVELS[i - 1])
	if i < LEVELS.size() - 1: out.append(LEVELS[i + 1])
	return out


# ---------------------------------------------------------------- furniture (office decor format)
## The new rooms' furniture, in map coordinates (OfficeMain.OFFICE_DECOR format).
static func decor() -> Array:
	var out: Array = []
	# --- 4th floor focus lounge: sofas, bean bags, books, lamps
	out += [
		{m = "bookcaseOpen", p = [-29.4, 13.6], r = 90, s = [2.0, 0.6, 1.9], block = true},
		{m = "bookcaseOpen", p = [-29.4, 16.6], r = 90, s = [2.0, 0.6, 1.9], block = true},
		{m = "loungeDesignSofa", p = [-24.0, 19.3], r = 180, s = [2.6, 1.0, 0.9], block = true, seat = "sofa", seats = 2},
		{m = "tableCoffeeGlass", p = [-24.0, 17.2], s = [1.4, 0.8, 0.4], block = true},
		{m = "loungeChairRelax", p = [-26.6, 16.2], r = 90, s = [1.0, 1.1, 0.9], block = true, seat = "sofa"},
		{m = "loungeChairRelax", p = [-21.4, 16.2], r = 270, s = [1.0, 1.1, 0.9], block = true, seat = "sofa"},
		{m = "loungeSofa", p = [-15.0, 15.0], r = 270, s = [2.4, 0.9, 0.9], block = true, seat = "sofa", seats = 2},
		{m = "rugRound", p = [-24.0, 16.8], s = [4.2, 4.2, 0.02]},
		{m = "lampRoundFloor", p = [-28.6, 19.2], s = [0.5, 0.5, 1.7]}, {m = "lampRoundFloor", p = [-19.4, 19.2], s = [0.5, 0.5, 1.7]},
		{m = "pottedPlant", p = [-29.2, 10.8], s = [0.7, 0.7, 1.6]}, {m = "plantSmall2", p = [-15.0, 19.3], s = [0.5, 0.5, 0.7]},
	]
	# --- prayer rooms: a shoe rack by the door (the prayer mats are drawn by _prayer_signs)
	for rid in ["pray4", "pray3"]:
		var r: Array = room(rid).r
		var z1 := float(r[3])
		var door_z := z1 if String(room(rid).doors).contains("s") else float(r[1])
		var side := -1.0 if door_z == z1 else 1.0
		out.append({m = "bookcaseOpenLow", p = [float(r[2]) - 1.2, door_z + side * 0.45], s = [1.8, 0.5, 0.6], block = true})   # shoes
		out.append({m = "pottedPlant", p = [float(r[2]) - 0.6, float(r[1]) + (float(r[3]) - float(r[1])) / 2.0], s = [0.7, 0.7, 1.6]})
	# --- washrooms: two stalls a side with a toilet each, sinks and mirrors along the outer walls
	for rid in ["wash4", "wash3"]:
		var rm := room(rid)
		var r: Array = rm.r
		var door_south := String(rm.doors).contains("s")
		var far_z := float(r[1]) if door_south else float(r[3])      # the wall away from the doors
		var inward := 1.0 if door_south else -1.0
		var mid := (float(r[0]) + float(r[2])) / 2.0
		for half in [-1.0, 1.0]:
			var outer := float(r[0]) if half < 0 else float(r[2])
			for k in 2:
				var cx: float = mid + half * (1.0 + k * 1.6)
				out.append({m = "toilet", p = [cx, far_z + inward * 0.55], r = 0 if door_south else 180, s = [0.5, 0.7, 0.8], block = true})
			out.append({m = "bathroomSink", p = [outer - half * 0.4, far_z + inward * 4.0], r = 90 if half < 0 else 270, s = [0.6, 0.5, 0.9], block = true})
			out.append({m = "bathroomSink", p = [outer - half * 0.4, far_z + inward * 5.4], r = 90 if half < 0 else 270, s = [0.6, 0.5, 0.9], block = true})
			out.append({m = "bathroomMirror", p = [outer - half * 0.22, far_z + inward * 4.7], r = 90 if half < 0 else 270, s = [0.05, 1.6, 0.7], y = 1.0})
			out.append({m = "trashcan", p = [outer - half * 0.4, far_z + inward * 6.6], s = [0.4, 0.4, 0.6]})
	# --- 3rd floor pantry: tea bar, two tables, a sofa
	out += [
		{m = "kitchenFridgeLarge", p = [91.0, -19.1], s = [1.2, 0.8, 2.0], block = true},
		{m = "kitchenBar", p = [95.0, -19.3], s = [3.6, 0.9, 1.0], block = true},
		{m = "kitchenCoffeeMachine", p = [93.8, -19.3], s = [0.5, 0.45, 0.55], y = 1.0},
		{m = "kitchenCoffeeMachine", p = [96.2, -19.3], s = [0.5, 0.45, 0.55], y = 1.0},
		{m = "kitchenCabinet", p = [98.4, -19.3], s = [1.2, 0.8, 1.0], block = true},
		{m = "kitchenMicrowave", p = [98.4, -19.3], s = [0.6, 0.45, 0.4], y = 1.0},
		{m = "tableRound", p = [96.0, -13.6], s = [2.4, 1.6, 0.8], block = true},
		{m = "chair", p = [94.35, -13.6], r = 90, s = [0.5, 0.5, 0.95], seat = "cafe"}, {m = "chair", p = [97.65, -13.6], r = 270, s = [0.5, 0.5, 0.95], seat = "cafe"},
		{m = "tableRound", p = [100.5, -15.8], s = [2.4, 1.6, 0.8], block = true},
		{m = "chair", p = [98.85, -15.8], r = 90, s = [0.5, 0.5, 0.95], seat = "cafe"}, {m = "chair", p = [102.15, -15.8], r = 270, s = [0.5, 0.5, 0.95], seat = "cafe"},
		{m = "loungeSofa", p = [91.1, -12.5], r = 90, s = [2.4, 0.9, 0.9], block = true, seat = "sofa", seats = 2},
		{m = "tableCoffee", p = [92.5, -12.5], s = [0.8, 1.4, 0.4], block = true},
		{m = "pottedPlant", p = [105.2, -19.2], s = [0.7, 0.7, 1.6]},
	]
	# --- 3rd floor call booths: four booths along the west wall, a sofa to wait on
	for k in 4:
		var z := -2.8 + k * 2.4
		out.append({m = "desk", p = [91.0, z], r = 90, s = [1.1, 1.6, 0.76], block = true})
		out.append({m = "laptop", p = [91.1, z], r = 90, s = [0.55, 0.42, 0.33], y = 0.76})
		out.append({m = "chairDesk", p = [92.3, z], r = 270, s = [0.8, 0.8, 1.0], seat = "booth"})
	out += [
		{m = "loungeSofa", p = [100.0, 5.4], r = 180, s = [2.4, 0.9, 0.9], block = true, seat = "sofa", seats = 2},
		{m = "pottedPlant", p = [105.2, -3.3], s = [0.7, 0.7, 1.6]}, {m = "plantSmall1", p = [97.0, 5.5], s = [0.5, 0.5, 0.7]},
	]
	# --- 3rd floor: management, business development and the CEO office (moved down from the 4th)
	out += [
		{m = "bookcaseClosedWide", p = [92.5, 10.6], s = [1.8, 0.6, 1.8], block = true},
		{m = "coatRack", p = [90.7, 19.4], s = [0.6, 0.3, 1.8]},
		{m = "pottedPlant", p = [105.2, 19.2], s = [0.7, 0.7, 1.6]},
		{m = "bookcaseOpen", p = [149.4, -11.0], r = 270, s = [1.6, 0.6, 1.8], block = true},
		{m = "pottedPlant", p = [135.0, -19.2], s = [0.7, 0.7, 1.6]},
		{m = "desk", p = [120.0, -16.6], s = [3.0, 1.3, 0.78], block = true},
		{m = "computerScreen", p = [119.4, -16.75], s = [0.9, 0.2, 0.62], y = 0.78}, {m = "laptop", p = [120.8, -16.5], s = [0.6, 0.45, 0.35], y = 0.78},
		{m = "chairDesk", p = [120.0, -17.9], s = [0.9, 0.9, 1.15], seat = "desk"},
		{m = "chair", p = [119.2, -15.2], r = 180, s = [0.55, 0.55, 0.95], seat = "visit"}, {m = "chair", p = [120.8, -15.2], r = 180, s = [0.55, 0.55, 0.95], seat = "visit"},
		{m = "loungeSofa", p = [114.1, -15.8], r = 90, s = [2.4, 0.9, 0.9], block = true, seat = "sofa", seats = 2},
		{m = "tableCoffee", p = [115.4, -15.8], s = [0.8, 1.4, 0.4], block = true},
		{m = "bookcaseClosedWide", p = [124.6, -19.4], s = [2.4, 0.6, 2.0], block = true},
		{m = "pottedPlant", p = [113.7, -19.3], s = [0.8, 0.8, 1.8]}, {m = "pottedPlant", p = [126.3, -12.0], s = [0.7, 0.7, 1.6]},
		# conference room: the long table (chairs are added round it), plants
		{m = "table", p = [120.0, 0.0], s = [9.0, 4.0, 0.8], block = true},
		{m = "pottedPlant", p = [112.7, 6.3], s = [0.7, 0.7, 1.6]}, {m = "pottedPlant", p = [127.3, 6.3], s = [0.7, 0.7, 1.6]},
		{m = "pottedPlant", p = [127.3, -6.3], s = [0.7, 0.7, 1.6]},
	]
	# --- lobbies (3rd floor, rooftop, ground): a sofa and plants; the lifts and stairs are drawn by build()
	for l in [3, 5]:
		var ox := float(X[l])
		out += [
			{m = "loungeSofa", p = [ox - 3.0, 19.5], r = 180, s = [2.4, 0.9, 0.9], block = true, seat = "sofa", seats = 2},
			{m = "pottedPlant", p = [ox - 7.4, 12.6], s = [0.7, 0.7, 1.6]}, {m = "pottedPlant", p = [ox - 7.4, 19.4], s = [0.7, 0.7, 1.6]},
		]
	# the ground floor lobby (door on the south, to the parking): the guard's desk, a bench, plants
	out += [
		{m = "kitchenBar", p = [-109.0, -17.0], r = 90, s = [2.6, 0.9, 1.05], block = true},
		{m = "chairDesk", p = [-110.2, -17.0], r = 90, s = [0.8, 0.8, 1.0], seat = "visit"},
		{m = "bench", p = [-104.0, -19.5], s = [2.4, 0.6, 0.5], block = true, seat = "sofa", seats = 2},
		{m = "pottedPlant", p = [-111.4, -12.6], s = [0.7, 0.7, 1.6]},
	]
	# --- rooftop: BBQ terrace (long tables with benches), sunset lounge, garden benches, smoking benches
	for tz in [-11.5, -6.0]:
		out.append({m = "table", p = [222.0, tz], s = [7.0, 1.4, 0.76], block = true})
		out.append({m = "benchCushion", p = [222.0, tz - 1.15], s = [6.0, 0.5, 0.48], block = true, seat = "cafe", seats = 6})
		out.append({m = "benchCushion", p = [222.0, tz + 1.15], r = 180, s = [6.0, 0.5, 0.48], block = true, seat = "cafe", seats = 6})
	out += [
		{m = "kitchenFridgeSmall", p = [231.0, -19.3], s = [0.8, 0.7, 0.9], block = true},
		{m = "pottedPlant", p = [211.0, -3.0], s = [0.9, 0.9, 1.8]}, {m = "pottedPlant", p = [235.0, -3.0], s = [0.9, 0.9, 1.8]},
		{m = "loungeSofaLong", p = [219.0, 19.0], r = 180, s = [4.0, 1.0, 0.9], block = true, seat = "sofa", seats = 4},
		{m = "loungeSofaCorner", p = [211.2, 15.0], r = 90, s = [2.4, 2.4, 0.9], block = true, seat = "sofa", seats = 2},
		{m = "tableCoffeeGlassSquare", p = [219.0, 15.6], s = [2.0, 1.2, 0.4], block = true},
		{m = "loungeChairRelax", p = [223.6, 13.6], r = 270, s = [1.0, 1.1, 0.9], block = true, seat = "sofa"},
		{m = "loungeChairRelax", p = [214.6, 11.0], r = 0, s = [1.0, 1.1, 0.9], block = true, seat = "sofa"},
		{m = "rugRectangle", p = [218.0, 15.4], s = [8.0, 6.0, 0.02]},
		{m = "lampSquareFloor", p = [226.8, 19.2], s = [0.5, 0.5, 1.6]}, {m = "lampSquareFloor", p = [211.0, 19.4], s = [0.5, 0.5, 1.6]},
		{m = "bench", p = [262.0, 8.0], s = [2.2, 0.6, 0.5], block = true, seat = "sofa", seats = 2},
		{m = "bench", p = [262.0, 16.0], r = 180, s = [2.2, 0.6, 0.5], block = true, seat = "sofa", seats = 2},
		{m = "bench", p = [258.0, -6.2], r = 180, s = [2.4, 0.6, 0.5], block = true, seat = "sofa", seats = 2},
		{m = "bench", p = [265.0, -6.2], r = 180, s = [2.4, 0.6, 0.5], block = true, seat = "sofa", seats = 2},
		{m = "trashcan", p = [269.2, -19.0], s = [0.5, 0.5, 0.8]},
	]
	for p in [[255.0, 5.0], [255.0, 19.0], [269.0, 5.0], [269.0, 19.0], [255.0, 12.0], [269.0, 12.0], [258.5, 12.0], [265.5, 12.0]]:
		out.append({m = "pottedPlant", p = p, s = [1.0, 1.0, 2.0], block = true})
	# --- parking: a bench by the banks where everyone has a smoke
	out += [
		{m = "bench", p = [-122.0, -11.3], s = [2.6, 0.6, 0.5], block = true, seat = "sofa", seats = 2},
		{m = "pottedPlant", p = [-128.4, -11.4], s = [0.8, 0.8, 1.6]}, {m = "pottedPlant", p = [-115.6, -11.4], s = [0.8, 0.8, 1.6]},
	]
	return out


## Parked cars and bikes: [{p, r, kind}] (map coordinates). Cars block the way; you can't drive them.
static func vehicles() -> Array:
	var out: Array = []
	# one row nose-in to the footpath in front of the building, like the real one; bikes along the front
	var k := 0
	for x in range(-147, -130, 3) + range(-98, -90, 3):
		if k % 5 != 3: out.append({p = Vector2(float(x) + 0.5, -3.6), kind = "car", col = k % CAR_COLS.size()})
		k += 1
	for b in 9:
		out.append({p = Vector2(-129.0 + b * 1.1, 5.6), kind = "bike", col = b % 4})
	return out


## Collision for the parked vehicles.
static func vehicle_walls() -> Array:
	var out: Array = []
	for v in vehicles():
		var p: Vector2 = v.p
		if v.kind == "car": out.append(Rect2(p.x - 0.95, p.y - 2.15, 1.9, 4.3))
		else: out.append(Rect2(p.x - 0.2, p.y - 0.95, 0.4, 1.9))
	# the banks on the ground floor (you can't go in), and the railing between the parking and the road
	out.append(Rect2(-150.6, -21.0, 38.4, 9.0))
	out.append(Rect2(-95.8, -21.0, 5.6, 9.0))
	out.append(Rect2(-151.0, 8.0, 62.0, 0.3))
	return out


## Places to stand and do something (OfficeMain stations format).
static func stations() -> Array:
	var out: Array = []
	for l in LEVELS:
		out.append({p = lobby(l, LIFT), face = Vector2(1, 0), kind = "lift", name = "Take the lift", solo = false, game = "", level = l})
		out.append({p = lobby(l, STAIRS), face = Vector2(1, 0), kind = "stairs", name = "Take the stairs", solo = false, game = "", level = l})
	for x in [93.8, 96.2]:
		out.append({p = Vector2(x, -18.15), face = Vector2(0, -1), kind = "tea", name = "Have some tea", solo = true, game = ""})
	out.append({p = Vector2(115.5, -5.6), face = Vector2(0, 1), kind = "present", name = "Present", solo = true, game = ""})
	for x in [213.0, 218.0]:
		out.append({p = Vector2(x, -17.6), face = Vector2(0, -1), kind = "grill", name = "Grill some tikka", solo = true, game = ""})
	for s in [[256.6, "smoke"], [259.4, "smoke"], [264.6, "vape"], [267.4, "vape"]]:
		out.append({p = Vector2(s[0], -16.6), face = Vector2(0, -1), kind = s[1], name = "Have a smoke" if s[1] == "smoke" else "Vape", solo = true, game = ""})
	for s2 in [[-127.0, "smoke"], [-125.0, "smoke"], [-119.0, "smoke"], [-117.0, "vape"]]:
		out.append({p = Vector2(s2[0], -8.2), face = Vector2(0, 1), kind = s2[1], name = "Have a smoke" if s2[1] == "smoke" else "Vape", solo = true, game = ""})
	return out


# ---------------------------------------------------------------- walls
## Walls for the levels: indoor floors have their outer walls, outdoor ones a railing (rails).
static func outer_walls(level: int) -> Array:
	var ox := float(X[level]); var T := 0.4
	return [Rect2(ox - 31, -21, 62, T), Rect2(ox - 31, 20.6, 62, T), Rect2(ox - 31, -21, T, 42), Rect2(ox + 30.6, -21, T, 42)]


## A washroom's walls: men on the west, women on the east, each with its own door.
static func wash_walls(rm: Dictionary) -> Array:
	var r: Array = rm.r; var T := 0.4; var gap := 1.6
	var x0 := float(r[0]); var z0 := float(r[1]); var x1 := float(r[2]); var z1 := float(r[3])
	var mid := (x0 + x1) / 2.0
	var door_z := z1 if String(rm.doors).contains("s") else z0
	var far_z := z0 if door_z == z1 else z1
	var out := [Rect2(x0 - T / 2, z0, T, z1 - z0), Rect2(x1 - T / 2, z0, T, z1 - z0), Rect2(x0, far_z - T / 2, x1 - x0, T),
		Rect2(mid - 0.1, z0, 0.2, z1 - z0)]                         # the divider
	var d1 := (x0 + mid) / 2.0; var d2 := (mid + x1) / 2.0
	out.append(Rect2(x0, door_z - T / 2, d1 - gap / 2 - x0, T))
	out.append(Rect2(d1 + gap / 2, door_z - T / 2, d2 - gap / 2 - d1 - gap / 2, T))
	out.append(Rect2(d2 + gap / 2, door_z - T / 2, x1 - d2 - gap / 2, T))
	return out


# ---------------------------------------------------------------- drawing
func light(pos: Vector3, rng: float, energy: float, col := Color(1.0, 0.96, 0.92)) -> OmniLight3D:
	var om := OmniLight3D.new(); om.position = pos; om.omni_range = rng; om.light_energy = energy; om.light_color = col
	main.world.add_child(om)
	var l := level_of(pos.x)
	if not lights.has(l): lights[l] = []
	lights[l].append(om)
	return om


## Only your level's lights are on.
func show_level(level: int) -> void:
	for l in lights:
		for om in lights[l]: (om as Light3D).visible = l == level


func build() -> void:
	for l in LEVELS: _lobby(l)
	_prayer_signs()
	_wash_signs()
	_booth_walls()
	_rooftop()
	_parking()


func _label(text: String, size: int, pos: Vector3, col: Color, px := 0.006, outline := 10) -> Label3D:
	var l := Label3D.new()
	l.text = text; l.font = font; l.font_size = size; l.modulate = col; l.pixel_size = px
	l.outline_size = outline; l.outline_modulate = INK; l.position = pos
	main.world.add_child(l)
	return l


func _lobby(level: int) -> void:
	var L := func(x: float, z: float, y: float) -> Vector3:
		var q := lobby(level, Vector2(x, z))
		return Vector3(q.x, y, q.y)
	var steel := mg._mat(Color(0.72, 0.74, 0.78), 0.25)
	steel.metallic = 0.8
	var frame := mg._mat(Color(0.2, 0.2, 0.24), 0.4)
	# two lift doors on the east wall, a call panel between them, the floor shown above
	for z in [13.9, 16.1]:
		mg._box(Vector3(0.12, 2.3, 1.8), frame, L.call(7.74, z, 1.15))
		mg._box(Vector3(0.06, 2.1, 0.74), steel, L.call(7.66, z - 0.38, 1.05))
		mg._box(Vector3(0.06, 2.1, 0.74), steel, L.call(7.66, z + 0.38, 1.05))
		mg._box(Vector3(0.05, 0.3, 0.6), mg._mat(Color(0.05, 0.05, 0.06), 0.3), L.call(7.65, z, 2.45))
		var disp := _label(String(SHORT[level]), 48, L.call(7.62, z, 2.45), Color(1.0, 0.45, 0.25), 0.005, 0)
		disp.rotation.y = -PI / 2
	mg._box(Vector3(0.05, 0.36, 0.16), mg._mat(Color(0.15, 0.15, 0.18), 0.4), L.call(7.66, 15.0, 1.2))
	mg._box(Vector3(0.05, 0.07, 0.07), mg._mat(CYAN, 0.3, 2.5), L.call(7.62, 15.0, 1.28))
	mg._box(Vector3(0.05, 0.07, 0.07), mg._mat(CYAN, 0.3, 2.5), L.call(7.62, 15.0, 1.12))
	var lift_sign := _label("LIFTS", 44, L.call(7.6, 15.0, 2.85), CYAN.lightened(0.3), 0.007, 8)
	lift_sign.rotation.y = -PI / 2
	# the stairs: a flight going up into the south-east corner, with a rail
	var sp := lobby(level, Vector2(6.4, 18.9))
	mg._decor({m = "stairs", p = [sp.x, sp.y], r = 270, s = [2.4, 1.5, 1.6], block = true})
	mg._box(Vector3(2.4, 0.06, 0.06), frame, L.call(6.4, 18.1, 1.1))
	var st := _label("STAIRS  ·  " + _stairs_text(level), 36, L.call(6.0, 18.2, 2.2), Color(1, 1, 1, 0.9), 0.006, 8)
	st.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# which level this is, big on the floor by the lifts
	var big := _label(String(NAMES[level]).to_upper(), 110, L.call(1.5, 15.0, 0.05), Color(1, 1, 1, 0.16), 0.01, 0)
	big.rotation.x = -PI / 2
	if level != 4:     # the BNB mark in every lobby (the 4th floor's reception has its own)
		main._sprite("res://assets/brand/bnb_mark_trim.png", 1.6, L.call(-4.0, 15.5, 0.06), true, 0.6)
	light(L.call(0.0, 16.0, 3.0), 10.0, 0.8)


func _stairs_text(level: int) -> String:
	var parts := []
	for to in stairs_to(level):
		parts.append(("up to " if LEVELS.find(to) > LEVELS.find(level) else "down to ") + String(NAMES[to]).to_lower())
	return " · ".join(parts).to_upper()


func _prayer_signs() -> void:
	for rid in ["pray4", "pray3"]:
		var r: Array = room(rid).r
		var cz := (float(r[1]) + float(r[3])) / 2.0
		var q := _label("◄  QIBLA", 44, Vector3(float(r[0]) + 0.3, 1.6, cz), Color(0.75, 1.0, 0.8), 0.007, 8)
		q.rotation.y = PI / 2
		var shoes := _label("PLEASE LEAVE YOUR SHOES HERE", 28, Vector3(float(r[2]) - 1.2, 1.0, float(r[3]) - 0.6 if String(room(rid).doors).contains("s") else float(r[1]) + 0.9), Color(1, 1, 1, 0.85), 0.005, 6)
		shoes.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		light(Vector3((float(r[0]) + float(r[2])) / 2.0, 2.6, cz), 10.0, 0.5, Color(0.8, 1.0, 0.85))
		# rows of prayer mats facing the qibla (west): a coloured mat with a lighter border each
		var cols := [Color(0.55, 0.1, 0.14), Color(0.1, 0.38, 0.25), Color(0.12, 0.2, 0.45)]
		for row in 4:
			for k in 5:
				var mp := Vector3(float(r[0]) + 2.4 + row * 2.6, 0.035, float(r[1]) + 1.8 + k * ((float(r[3]) - float(r[1]) - 3.4) / 4.0))
				mg._box(Vector3(1.25, 0.02, 0.78), mg._mat(Color(0.85, 0.75, 0.5), 0.9), mp)
				mg._box(Vector3(1.12, 0.025, 0.66), mg._mat(cols[(row + k) % cols.size()], 0.9), mp + Vector3(0, 0.004, 0))
				mg._box(Vector3(0.22, 0.027, 0.4), mg._mat(Color(0.85, 0.75, 0.5), 0.9), mp + Vector3(-0.42, 0.006, 0))   # the arch end, towards the qibla


func _wash_signs() -> void:
	for rid in ["wash4", "wash3"]:
		var rm := room(rid); var r: Array = rm.r
		var mid := (float(r[0]) + float(r[2])) / 2.0
		var door_z := float(r[3]) if String(rm.doors).contains("s") else float(r[1])
		var off := 0.6 if door_z == float(r[3]) else 0.9
		for half in [[-1.0, "MEN", Color(0.45, 0.7, 1.0)], [1.0, "WOMEN", Color(1.0, 0.55, 0.75)]]:
			var dx: float = (mid - float(r[0])) / 2.0 * half[0]
			var lab := _label(half[1], 46, Vector3(mid + dx, 1.9, door_z + (0.0 if door_z == float(r[3]) else 0.0) - 0.1), half[2], 0.007, 10)
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# stall partitions (between and beside the toilets)
		var far_z := float(r[1]) if String(rm.doors).contains("s") else float(r[3])
		var inward := 1.0 if far_z == float(r[1]) else -1.0
		var part := mg._mat(Color(0.55, 0.62, 0.72), 0.5)
		for half in [-1.0, 1.0]:
			for k in 3:
				var px: float = mid + half * (0.2 + k * 1.6)
				mg._box(Vector3(0.06, 1.7, 1.6), part, Vector3(px, 0.95, far_z + inward * 0.85))
		light(Vector3(mid, 2.6, (float(r[1]) + float(r[3])) / 2.0), 9.0, 0.55, Color(0.92, 0.97, 1.0))


func _booth_walls() -> void:
	var glass := mg._mat(Color(0.55, 0.8, 0.95, 0.35), 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for k in 5:
		var z := -4.0 + k * 2.4
		mg._box(Vector3(2.6, 1.9, 0.06), glass, Vector3(91.4, 0.95, z))
	var s := _label("QUIET PLEASE · CLIENT CALLS", 30, Vector3(98.0, 1.4, -3.7), Color(1, 1, 1, 0.8), 0.006, 6)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED


# ---------------------------------------------------------------- rooftop
func _rooftop() -> void:
	var ox := float(X[5])
	# grills: a dark body with glowing coals, flames and smoke
	for x in [213.0, 218.0]:
		var body := mg._mat(Color(0.12, 0.12, 0.13), 0.4)
		mg._box(Vector3(1.8, 0.8, 0.9), body, Vector3(x, 0.55, -18.9))
		for lx in [-0.8, 0.8]:
			mg._box(Vector3(0.08, 0.5, 0.08), body, Vector3(x + lx, 0.15, -18.9))
		mg._box(Vector3(1.6, 0.04, 0.7), mg._mat(Color(1.0, 0.35, 0.08), 0.6, 3.5), Vector3(x, 0.97, -18.9))
		for k in 6:
			mg._box(Vector3(0.22, 0.05, 0.07), mg._mat(Color(0.55, 0.25, 0.12), 0.7), Vector3(x - 0.55 + k * 0.22, 1.01, -18.9 + (k % 2) * 0.12))
		var fire := _particles(Color(1.0, 0.55, 0.15, 0.9), 0.05, 24, 0.6, Vector3(0, 0.9, 0), 2.2)
		fire.position = Vector3(x, 1.0, -18.9); fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; fire.emission_box_extents = Vector3(0.7, 0.02, 0.25)
		fire.emitting = true
		var smoke := _particles(Color(0.75, 0.75, 0.78, 0.35), 0.18, 18, 3.0, Vector3(0, 0.6, 0), 0.0)
		smoke.position = Vector3(x, 1.2, -18.9); smoke.emitting = true
		var fl := light(Vector3(x, 1.6, -18.4), 5.0, 1.2, Color(1.0, 0.6, 0.3))
		flames.append({light = fl, base = 1.2})
	_label("BBQ", 120, Vector3(215.5, 2.4, -19.6), Color(1.0, 0.7, 0.3), 0.007, 16)
	# string lights over the terrace and the lounge
	for line in [[Vector3(210.5, 3.0, -19.5), Vector3(235.5, 3.0, -19.5)], [Vector3(210.5, 3.0, -2.5), Vector3(235.5, 3.0, -2.5)],
			[Vector3(210.5, 3.0, -19.5), Vector3(235.5, 3.0, -2.5)], [Vector3(210.5, 3.0, 4.5), Vector3(227.5, 3.0, 19.5)]]:
		_string_lights(line[0], line[1])
	for p in [Vector2(210.5, -19.5), Vector2(235.5, -19.5), Vector2(210.5, -2.5), Vector2(235.5, -2.5), Vector2(210.5, 4.5), Vector2(227.5, 19.5)]:
		mg._box(Vector3(0.1, 3.0, 0.1), mg._mat(Color(0.2, 0.2, 0.22), 0.5), Vector3(p.x, 1.5, p.y))
	light(Vector3(222.0, 3.2, -10.0), 16.0, 0.9, Color(1.0, 0.85, 0.6))
	light(Vector3(219.0, 3.2, 13.0), 13.0, 0.8, Color(1.0, 0.75, 0.55))
	light(Vector3(262.0, 3.2, -12.0), 13.0, 0.7)
	light(Vector3(262.0, 3.2, 12.0), 13.0, 0.6, Color(0.85, 1.0, 0.85))
	light(Vector3(240.0, 3.2, 16.0), 10.0, 0.8)
	# a parasol in the lounge's far corner (over the middle it hid the lounge from the camera),
	# solar panels and water tanks on the roof
	mg._box(Vector3(0.08, 2.0, 0.08), mg._mat(Color(0.9, 0.9, 0.9), 0.5), Vector3(225.8, 1.0, 6.4))
	var shade := MeshInstance3D.new(); var cone := CylinderMesh.new(); cone.top_radius = 0.05; cone.bottom_radius = 1.3; cone.height = 0.4
	shade.mesh = cone; shade.material_override = mg._mat(Color(0.95, 0.5, 0.25), 0.8); shade.position = Vector3(225.8, 2.1, 6.4)
	main.world.add_child(shade)
	var panel := mg._mat(Color(0.1, 0.16, 0.35), 0.2)
	panel.metallic = 0.5
	for row in 3:
		for k in 4:
			var pnl := mg._box(Vector3(2.2, 0.06, 1.3), panel, Vector3(ox + 1.5 + k * 2.5, 0.75, -19.0 + row * 2.4))
			pnl.rotation.x = -0.35
			mg._box(Vector3(0.08, 0.7, 0.08), mg._mat(Color(0.5, 0.5, 0.52), 0.5), Vector3(ox + 1.5 + k * 2.5, 0.35, -18.6 + row * 2.4))
	for k in 2:
		var tank := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.9; cm.bottom_radius = 0.9; cm.height = 1.8
		tank.mesh = cm; tank.material_override = mg._mat(Color(0.15, 0.15, 0.17), 0.6); tank.position = Vector3(ox + 11.0, 1.1, 14.0 + k * 3.0)
		main.world.add_child(tank)
		mg._box(Vector3(1.8, 0.2, 1.8), mg._mat(Color(0.5, 0.5, 0.5), 0.8), Vector3(ox + 11.0, 0.1, 14.0 + k * 3.0))
	# the smoking area: ashtray stands by each spot, a sign
	for x in [256.6, 259.4, 264.6, 267.4]:
		_ashtray(Vector2(x + 0.7, -17.5))
	# grass in the garden
	mg._box(Vector3(15.0, 0.05, 15.0), mg._mat(Color(0.25, 0.5, 0.22), 0.95), Vector3(262.0, 0.035, 12.0))


func _string_lights(a: Vector3, b: Vector3) -> void:
	var n := int(a.distance_to(b) / 0.9)
	var cols := [Color(1.0, 0.85, 0.45), Color(1.0, 0.6, 0.35), Color(0.95, 0.95, 0.8)]
	var mats := []
	for c in cols: mats.append(mg._mat(c, 0.3, 3.0))
	for i in n + 1:
		var f := float(i) / n
		var p := a.lerp(b, f) + Vector3(0, -sin(f * PI) * 0.5, 0)
		var bulb := MeshInstance3D.new(); var s := SphereMesh.new(); s.radius = 0.06; s.height = 0.12; s.radial_segments = 8; s.rings = 4
		bulb.mesh = s; bulb.material_override = mats[i % mats.size()]; bulb.position = p
		main.world.add_child(bulb)


func _ashtray(p: Vector2) -> void:
	var m := mg._mat(Color(0.3, 0.3, 0.32), 0.3)
	m.metallic = 0.7
	mg._box(Vector3(0.06, 0.9, 0.06), m, Vector3(p.x, 0.45, p.y))
	var dish := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.18; cm.bottom_radius = 0.14; cm.height = 0.08
	dish.mesh = cm; dish.material_override = m; dish.position = Vector3(p.x, 0.92, p.y)
	main.world.add_child(dish)


# ---------------------------------------------------------------- parking
func _parking() -> void:
	var ox := float(X[0])
	# the building's ground floor across the back: Askari Bank and Meezan Bank, our entrance on the right
	var wallm := mg._tex_mat("grey_plaster", Color(0.85, 0.8, 0.68), 0.4)
	var glass := mg._mat(Color(0.2, 0.28, 0.34), 0.1); glass.metallic = 0.3
	mg._box(Vector3(38.4, 3.4, 9.0), wallm, Vector3(ox - 11.4, 1.7, -16.5))
	mg._box(Vector3(5.6, 3.4, 9.0), wallm, Vector3(ox + 27.0, 1.7, -16.5))
	for b in [[-21.0, "ASKARI BANK", Color(0.05, 0.45, 0.7), Color(0.15, 0.65, 0.45)], [-3.0, "MEEZAN BANK", Color(0.42, 0.16, 0.5), Color(0.9, 0.75, 0.3)]]:
		var bx: float = ox + b[0]
		mg._box(Vector3(14.0, 2.4, 0.08), glass, Vector3(bx, 1.2, -11.98))                 # the glass shop front
		for k in 5: mg._box(Vector3(0.12, 2.4, 0.12), mg._mat(Color(0.75, 0.75, 0.78), 0.3), Vector3(bx - 7.0 + k * 3.5, 1.2, -11.95))
		mg._box(Vector3(15.0, 0.9, 0.2), mg._mat(b[2], 0.4, 0.5), Vector3(bx, 2.95, -11.9))   # the sign board
		mg._box(Vector3(15.0, 0.08, 0.22), mg._mat(b[3], 0.3, 1.5), Vector3(bx, 2.48, -11.89))
		var name := _label(b[1], 70, Vector3(bx, 2.95, -11.78), Color(1, 1, 1), 0.007, 0)
		name.outline_size = 0
		var atm := mg._box(Vector3(0.8, 1.6, 0.5), mg._mat(Color(0.25, 0.25, 0.28), 0.4), Vector3(bx + 5.6, 0.8, -11.6))
		atm.set_meta("atm", true)
		_label("ATM", 30, Vector3(bx + 5.6, 1.45, -11.33), CYAN.lightened(0.3), 0.005, 0)
		light(Vector3(bx, 3.0, -10.5), 9.0, 0.6, Color(1.0, 0.95, 0.85))
	_label("BIT & BYTES  ·  3RD, 4TH & ROOFTOP", 44, Vector3(ox + 16.0, 3.0, -11.78), Color(1, 1, 1, 0.95), 0.006, 10)
	# the footpath in front of the building, a kerb, the parking
	mg._box(Vector3(62.0, 0.1, 6.0), mg._tex_mat("concrete_tiles_02", Color(0.5, 0.48, 0.45), 0.5), Vector3(ox, 0.05, -9.0))
	var line := mg._mat(Color(0.92, 0.92, 0.9), 0.6)
	for v in vehicles():
		if v.kind == "car":
			_car(v.p, CAR_COLS[v.col], false)
			mg._box(Vector3(0.1, 0.012, 4.6), line, Vector3(v.p.x - 1.5, 0.012, v.p.y))
			mg._box(Vector3(0.1, 0.012, 4.6), line, Vector3(v.p.x + 1.5, 0.012, v.p.y))
		else: _bike(v.p, v.col)
	# the railing at the edge of the parking, then the road: a service lane, a green median with palms
	# and yellow-and-black kerbs, and the main road (just to look at)
	var rail := mg._mat(Color(0.3, 0.3, 0.32), 0.4)
	mg._box(Vector3(62.0, 0.08, 0.08), rail, Vector3(ox, 0.9, 8.15))
	for k in 32: mg._box(Vector3(0.08, 0.9, 0.08), rail, Vector3(ox - 31.0 + k * 2.0, 0.45, 8.15))
	mg._box(Vector3(100.0, 0.04, 4.0), mg._mat(Color(0.18, 0.18, 0.2), 0.9), Vector3(ox, 0.0, 10.4))
	mg._box(Vector3(62.0, 0.2, 2.6), mg._mat(Color(0.22, 0.4, 0.18), 0.95), Vector3(ox, 0.1, 13.7))
	# the neighbourhood round the plot: grass and trees, so the edges aren't empty
	mg._box(Vector3(140.0, 0.1, 110.0), mg._mat(Color(0.2, 0.32, 0.16), 0.95), Vector3(ox, -0.12, -5.0))
	for k in 14:
		var tz := -40.0 + (k % 7) * 9.0
		var tx := ox - 40.0 if k < 7 else ox + 40.0
		mg._box(Vector3(0.3, 2.0, 0.3), mg._mat(Color(0.35, 0.22, 0.12), 0.9), Vector3(tx + (k % 3), 1.0, tz))
		var crown := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 2.0; sm.height = 3.4
		crown.mesh = sm; crown.material_override = mg._mat(Color(0.18, 0.38, 0.17), 0.9); crown.position = Vector3(tx + (k % 3), 3.2, tz)
		main.world.add_child(crown)
	for side in [12.35, 15.05]:
		for k in 62:
			mg._box(Vector3(1.0, 0.22, 0.25), mg._mat([Color(0.95, 0.78, 0.1), Color(0.08, 0.08, 0.08)][k % 2], 0.7), Vector3(ox - 30.5 + k, 0.11, side))
	mg._box(Vector3(100.0, 0.04, 9.0), mg._mat(Color(0.16, 0.16, 0.18), 0.9), Vector3(ox, 0.0, 19.6))
	for k in 16: mg._box(Vector3(1.8, 0.02, 0.14), mg._mat(Color(0.95, 0.95, 0.9), 0.6), Vector3(ox - 30.0 + k * 4.0, 0.03, 18.2))
	for k in 7: _palm(Vector3(ox - 27.0 + k * 9.0, 0.2, 13.7))
	for k in 4:
		var lx := ox - 24.0 + k * 16.0
		mg._box(Vector3(0.14, 5.5, 0.14), rail, Vector3(lx, 2.75, 12.9))
		mg._box(Vector3(0.12, 0.12, 1.4), rail, Vector3(lx, 5.5, 12.3))
		mg._box(Vector3(0.4, 0.1, 0.6), mg._mat(Color(1.0, 0.9, 0.6), 0.3, 4.0), Vector3(lx, 5.42, 11.7))
	light(Vector3(ox - 10.0, 5.0, 2.0), 22.0, 0.7, Color(1.0, 0.9, 0.75))
	light(Vector3(ox + 14.0, 5.0, 2.0), 18.0, 0.6, Color(1.0, 0.9, 0.75))
	# where we smoke: beside the banks
	for x in [-126.0, -124.0, -118.0]: _ashtray(Vector2(x, -7.0))
	var ps := _label("SMOKING CORNER", 40, Vector3(-122.0, 2.0, -6.4), Color(0.95, 0.9, 0.8), 0.007, 10)
	ps.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# traffic going by
	for k in 8:
		var kind: String = ["car", "bike", "car", "rickshaw", "car", "bike", "car", "car"][k]
		var lane := 16.8 if k % 2 == 0 else 19.6
		var n := Node3D.new(); main.world.add_child(n)
		if kind == "car": _car(Vector2.ZERO, CAR_COLS[(k * 3) % CAR_COLS.size()], false, n)
		elif kind == "bike": _bike(Vector2.ZERO, k % 4, n, true)
		else: _rickshaw(n)
		n.rotation.y = -PI / 2 if lane < 18.0 else PI / 2
		n.position = Vector3(ox - 40.0 + k * 10.0, 0.0, lane)
		traffic.append({node = n, speed = (7.0 + k % 3 * 2.0) * (1.0 if lane < 18.0 else -1.0)})


func _palm(base: Vector3) -> void:
	var trunk_m := mg._mat(Color(0.45, 0.33, 0.2), 0.9)
	var top := base
	for k in 6:     # a slightly bent trunk, in segments
		var seg := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.16 - k * 0.01; cm.bottom_radius = 0.2 - k * 0.01; cm.height = 0.8
		seg.mesh = cm; seg.material_override = trunk_m; seg.position = top + Vector3(0.05 * k, 0.4, 0)
		main.world.add_child(seg)
		top += Vector3(0.05 * k, 0.78, 0)
	var leaf := mg._mat(Color(0.2, 0.48, 0.2), 0.8)
	for k in 9:
		var a := TAU * k / 9.0
		var f := mg._box(Vector3(0.35, 0.04, 2.2), leaf, top + Vector3(cos(a) * 0.9, -0.3, sin(a) * 0.9))
		f.rotation.y = -a + PI / 2; f.rotation.x = 0.45


func _car(p: Vector2, col: Color, flip: bool, parent: Node3D = null) -> void:
	var root := Node3D.new(); root.position = Vector3(p.x, 0, p.y)
	if flip: root.rotation.y = PI
	(parent if parent != null else main.world).add_child(root)
	var paint := mg._mat(col, 0.25); paint.metallic = 0.4
	var glass := mg._mat(Color(0.12, 0.16, 0.22), 0.1)
	mg._box(Vector3(1.8, 0.62, 4.1), paint, Vector3(0, 0.55, 0), root)
	mg._box(Vector3(1.6, 0.55, 2.1), paint, Vector3(0, 1.12, 0.25), root)
	mg._box(Vector3(1.62, 0.42, 1.9), glass, Vector3(0, 1.13, 0.25), root)
	mg._box(Vector3(1.4, 0.4, 0.05), glass, Vector3(0, 1.1, -0.83), root)
	mg._box(Vector3(0.36, 0.14, 0.04), mg._mat(Color(1.0, 0.95, 0.8), 0.3, 2.0), Vector3(-0.6, 0.62, -2.06), root)
	mg._box(Vector3(0.36, 0.14, 0.04), mg._mat(Color(1.0, 0.95, 0.8), 0.3, 2.0), Vector3(0.6, 0.62, -2.06), root)
	mg._box(Vector3(0.36, 0.12, 0.04), mg._mat(Color(0.9, 0.1, 0.1), 0.3, 1.5), Vector3(-0.6, 0.66, 2.06), root)
	mg._box(Vector3(0.36, 0.12, 0.04), mg._mat(Color(0.9, 0.1, 0.1), 0.3, 1.5), Vector3(0.6, 0.66, 2.06), root)
	var tyre := mg._mat(Color(0.05, 0.05, 0.05), 0.9)
	for w in [Vector3(-0.85, 0.32, -1.3), Vector3(0.85, 0.32, -1.3), Vector3(-0.85, 0.32, 1.3), Vector3(0.85, 0.32, 1.3)]:
		var wheel := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.32; cm.bottom_radius = 0.32; cm.height = 0.24
		wheel.mesh = cm; wheel.material_override = tyre; wheel.position = w; wheel.rotation.z = PI / 2
		root.add_child(wheel)


func _bike(p: Vector2, col: int, parent: Node3D = null, riding := false) -> void:
	var root := Node3D.new(); root.position = Vector3(p.x, 0, p.y)
	(parent if parent != null else main.world).add_child(root)
	var cols := [Color(0.8, 0.1, 0.1), Color(0.1, 0.1, 0.12), Color(0.15, 0.3, 0.7), Color(0.85, 0.85, 0.85)]
	var tyre := mg._mat(Color(0.05, 0.05, 0.05), 0.9)
	for z in [-0.65, 0.65]:
		var wheel := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 0.2; tm.outer_radius = 0.32
		wheel.mesh = tm; wheel.material_override = tyre; wheel.position = Vector3(0, 0.32, z); wheel.rotation.z = PI / 2
		root.add_child(wheel)
	mg._box(Vector3(0.22, 0.32, 0.9), mg._mat(cols[col], 0.3), Vector3(0, 0.62, 0.0), root)
	mg._box(Vector3(0.24, 0.1, 0.6), mg._mat(Color(0.08, 0.08, 0.08), 0.8), Vector3(0, 0.83, 0.2), root)
	mg._box(Vector3(0.7, 0.05, 0.05), mg._mat(Color(0.6, 0.6, 0.62), 0.3), Vector3(0, 1.0, -0.55), root)
	mg._box(Vector3(0.05, 0.4, 0.05), mg._mat(Color(0.6, 0.6, 0.62), 0.3), Vector3(0, 0.8, -0.55), root)
	mg._box(Vector3(0.14, 0.12, 0.04), mg._mat(Color(1.0, 0.95, 0.8), 0.3, 2.0), Vector3(0, 0.85, -0.7), root)
	if riding:     # someone riding it: a simple figure in a helmet
		mg._box(Vector3(0.4, 0.55, 0.3), mg._mat(Color(0.3, 0.35, 0.45), 0.8), Vector3(0, 1.2, 0.15), root)
		var head := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.15; sm.height = 0.3
		head.mesh = sm; head.material_override = mg._mat(Color(0.9, 0.85, 0.2), 0.4); head.position = Vector3(0, 1.6, 0.1)
		root.add_child(head)


func _rickshaw(root: Node3D) -> void:
	var body := mg._mat(Color(0.15, 0.55, 0.25), 0.4)
	mg._box(Vector3(1.3, 0.7, 2.4), body, Vector3(0, 0.75, 0), root)
	mg._box(Vector3(1.3, 0.12, 2.4), mg._mat(Color(0.1, 0.1, 0.1), 0.6), Vector3(0, 1.75, 0), root)
	for x in [-0.62, 0.62]:
		mg._box(Vector3(0.06, 0.95, 0.06), mg._mat(Color(0.2, 0.2, 0.2), 0.5), Vector3(x, 1.25, 0.9), root)
		mg._box(Vector3(0.06, 0.95, 0.06), mg._mat(Color(0.2, 0.2, 0.2), 0.5), Vector3(x, 1.25, -0.6), root)
	mg._box(Vector3(0.9, 0.5, 0.06), mg._mat(Color(0.12, 0.16, 0.22), 0.1), Vector3(0, 1.4, -0.95), root)
	var tyre := mg._mat(Color(0.05, 0.05, 0.05), 0.9)
	for w in [Vector3(0, 0.28, -1.0), Vector3(-0.6, 0.28, 0.8), Vector3(0.6, 0.28, 0.8)]:
		var wheel := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.28; cm.bottom_radius = 0.28; cm.height = 0.18
		wheel.mesh = cm; wheel.material_override = tyre; wheel.position = w; wheel.rotation.z = PI / 2
		root.add_child(wheel)


# ---------------------------------------------------------------- smoke
func _particles(col: Color, size: float, amount: int, life: float, vel: Vector3, spread := 25.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount; p.lifetime = life; p.emitting = false
	var m := SphereMesh.new(); m.radius = size; m.height = size * 2.0; m.radial_segments = 8; m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	m.material = mat
	p.mesh = m
	p.direction = vel.normalized() if vel.length() > 0.0 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vel.length() * 0.6; p.initial_velocity_max = vel.length()
	p.gravity = Vector3(0, 0.25, 0)
	p.damping_min = 0.2; p.damping_max = 0.6
	var curve := Curve.new(); curve.add_point(Vector2(0, 0.4)); curve.add_point(Vector2(1, 1.8))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, col); g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	main.world.add_child(p)
	return p


## Each frame: smoke from whoever is smoking or vaping, traffic on the road, the grill fires flicker.
func tick(dt: float, occupied: Dictionary) -> void:
	_t += dt
	for i in main.stations.size():
		var st: Dictionary = main.stations[i]
		if not (st.kind in ["smoke", "vape"]): continue
		var on: bool = occupied.has(i)
		if on and not puffs.has(i):
			var vape: bool = st.kind == "vape"
			var pf := _particles(Color(0.92, 0.92, 0.95, 0.8 if vape else 0.65), 0.17 if vape else 0.09, 40 if vape else 18, 2.6 if vape else 2.0,
				Vector3(st.face.x, 0.5, st.face.y) * (1.0 if vape else 0.6), 22.0)
			pf.position = Vector3(st.p.x + st.face.x * 0.28, 1.55, st.p.y + st.face.y * 0.28)
			pf.set_meta("phase", randf() * 3.0)
			puffs[i] = pf
		if puffs.has(i):
			var pf: CPUParticles3D = puffs[i]
			var cycle := fmod(_t + float(pf.get_meta("phase")), 3.4)
			pf.emitting = on and (always_puff or (cycle > 2.3 and cycle < 3.1))      # breathe in (hand to mouth), then breathe out a cloud
	for car in traffic:
		var n: Node3D = car.node
		n.position.x += float(car.speed) * dt
		var ox := float(X[0])
		if n.position.x > ox + 42.0: n.position.x = ox - 42.0
		elif n.position.x < ox - 42.0: n.position.x = ox + 42.0
	for f in flames:
		(f.light as OmniLight3D).light_energy = float(f.base) * (0.85 + 0.15 * sin(_t * 13.0) + 0.1 * sin(_t * 7.3))
