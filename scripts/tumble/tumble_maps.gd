extends RefCounted
## Tumble Tuesday courses. Every map is plain data built from boxes and a few moving-obstacle kinds;
## the sim works out where the moving parts are from the round's tick, so they never need syncing.
##
## Coordinates: x across, y up, z down the course (the start is at z ~ 0, the camera looks toward +z).
##
## Pieces
##   boxes     [centre, size, colour]                 static, solid, you can stand on them
##   movers    {c, s, axis, amp, period, phase, col}  sliding platforms (carry you)
##   pushers   {c, s, dir, amp, period, phase, col}   blocks that punch out of the side and shove you
##   drops     {c, s, period, off, phase, col}        paper sheets that tip away for `off` of each period
##   belts     {c, s, belt, col}                      conveyor belts (move you along `belt`)
##   spins     {c, len, y0, y1, speed, arms, th, accel, phase, col}  rotating bars (jump them)
##   balls     {a, b, r, period, phase, col}          things rolling from a to b, again and again
##   pends     {pivot, len, amp, period, phase, r}    swinging office chairs (swing across x)
##   tiles     [centre, size]                         desks that crumble after you stand on them
##   discs     [centre, radius]                       round floors
##   finish    AABB (race)  ·  crown (final race)  ·  goals / tubs (team)

const KIND_GOAL := {"race": "QUALIFY", "survive": "SURVIVE", "team": "TEAM GAME", "final_race": "FINAL", "final_survive": "FINAL"}

const LIST := {
	"elevator": {name = "ELEVATOR PITCH", kind = "race", sub = "Ride the sliding lifts, dodge the fans, beat the rolling water bottles"},
	"spincycle": {name = "SPIN CYCLE", kind = "race", sub = "Jump the server-room spinners, fight the belts, mind the punching racks"},
	"printer": {name = "PRINTER JAM", kind = "race", sub = "Paper bridges that tip, staplers that punch, chairs that swing"},
	"hotdesk": {name = "HOT DESK", kind = "survive", sub = "Desks crumble once you stand on them. Keep moving. Don't fall"},
	"mopup": {name = "MOP UP", kind = "survive", sub = "The cleaner's mops sweep the floor faster and faster. Jump!"},
	"mailroom": {name = "MAIL ROOM", kind = "team", sub = "Push the giant mail tubs into your team's sorting bay"},
	"crown": {name = "CROWN ON THE ROOF", kind = "final_race", sub = "Climb the tower to the roof. First to touch the crown wins it all"},
	"lastdesk": {name = "LAST DESK STANDING", kind = "final_survive", sub = "The floor falls away desk by desk. Be the last one up"},
}
const RACES := ["elevator", "spincycle", "printer"]
const SURVIVALS := ["hotdesk", "mopup"]
const FINALS := ["crown", "lastdesk"]

# BNB-ish toy palette
const PURPLE := Color(0.6, 0.36, 1.0)
const CYAN := Color(0.15, 0.8, 0.95)
const PINK := Color(1.0, 0.42, 0.72)
const YELLOW := Color(1.0, 0.82, 0.25)
const ORANGE := Color(1.0, 0.55, 0.2)
const GREEN := Color(0.35, 0.85, 0.45)
const WHITE := Color(0.95, 0.95, 0.97)
const GREY := Color(0.55, 0.58, 0.66)
const RED := Color(0.95, 0.28, 0.3)


static func _empty(id: String) -> Dictionary:
	var L: Dictionary = LIST[id]
	return {id = id, name = L.name, kind = L.kind, sub = L.sub, boxes = [], movers = [], pushers = [], drops = [], belts = [], spins = [],
		balls = [], pends = [], tiles = [], discs = [], checkpoints = [], waypoints = [], spawn = Vector3.ZERO, spread = Vector2(10, 5),
		fall_y = -6.0, dur = 120.0, finish = AABB(), crown = Vector3.ZERO, goals = [], tubs = [], sky = "day"}


static func _start(m: Dictionary, w := 14.0) -> void:
	m.boxes.append([Vector3(0, -0.5, 4), Vector3(w, 1, 8), PURPLE])
	m.spawn = Vector3(0, 0, 3.5)


static func build(id: String) -> Dictionary:
	var m := _empty(id)
	match id:
		"elevator":
			_start(m)
			# three rows of sliding lifts across the first pit
			for k in 3:
				for i in [-1, 0, 1]:
					m.movers.append({c = Vector3(i * 4.6, -0.3, 10 + k * 4), s = Vector3(3.8, 0.6, 4), axis = Vector3(1, 0, 0), amp = 1.5,
						period = 3.0 + 0.5 * k, phase = i * 1.3 + k * 0.9, col = [CYAN, PINK, YELLOW][k]})
			m.boxes.append([Vector3(0, -0.5, 27), Vector3(14, 1, 14), WHITE])
			m.spins.append({c = Vector3(-3.5, 0, 24), len = 3.0, y0 = 0.05, y1 = 0.6, speed = 1.9, arms = 2, th = 0.25, accel = 0.0, phase = 0.0, col = ORANGE})
			m.spins.append({c = Vector3(3.5, 0, 24), len = 3.0, y0 = 0.05, y1 = 0.6, speed = -2.1, arms = 2, th = 0.25, accel = 0.0, phase = 1.0, col = ORANGE})
			m.spins.append({c = Vector3(0, 0, 30.5), len = 5.2, y0 = 0.05, y1 = 0.6, speed = 1.3, arms = 2, th = 0.25, accel = 0.0, phase = 0.5, col = PINK})
			# the stairway up, with water-cooler bottles rolling down it
			for k in 18:
				var top := (k + 1) * 0.3
				m.boxes.append([Vector3(0, (top - 1.0) / 2.0, 34.5 + k), Vector3(14, top + 1.0, 1), [WHITE, Color(0.85, 0.88, 0.95)][k % 2]])
			for lane in 3:   # three bottle lanes: the gaps between them are the safe lines up
				var x := -4.5 + lane * 4.5
				m.balls.append({a = Vector3(x, 6.0, 52.5), b = Vector3(x, 0.6, 33.0), r = 0.65, period = 4.2, phase = lane * 0.31, col = CYAN})
			m.boxes.append([Vector3(0, 4.9, 56), Vector3(14, 1, 8), PURPLE])
			m.finish = AABB(Vector3(-7, 5.2, 56.5), Vector3(14, 3, 3.5))
			m.checkpoints = [[20.5, Vector3(0, 0, 21.5)], [34.0, Vector3(0, 0, 32.5)]]
			m.waypoints = [Vector3(0, 0, 7.5), Vector3(0, 0, 20.5), Vector3(0, 0, 33.5), Vector3(0, 5.4, 53.5), Vector3(0, 5.4, 58)]
		"spincycle":
			_start(m, 12.0)
			m.boxes.append([Vector3(0, -0.5, 16), Vector3(12, 1, 16), Color(0.25, 0.28, 0.4)])
			m.spins.append({c = Vector3(0, 0, 12), len = 6.2, y0 = 0.05, y1 = 0.55, speed = 2.0, arms = 2, th = 0.25, accel = 0.0, phase = 0.0, col = CYAN})
			m.spins.append({c = Vector3(0, 0, 19.5), len = 6.2, y0 = 0.05, y1 = 0.55, speed = -2.3, arms = 2, th = 0.25, accel = 0.0, phase = 0.8, col = PINK})
			m.belts.append({c = Vector3(0, -0.5, 32), s = Vector3(12, 1, 16), belt = Vector3(0, 0, -2.3), col = Color(0.2, 0.22, 0.26)})
			for p in [[-1.0, 27.0, 0.0], [1.0, 31.0, 0.35], [-1.0, 35.0, 0.7], [1.0, 39.0, 0.15]]:
				m.pushers.append({c = Vector3(-p[0] * 7.6, 0.7, p[1]), s = Vector3(3.2, 1.4, 1.8), dir = Vector3(p[0], 0, 0), amp = 4.6, period = 2.4, phase = p[2], col = Color(0.15, 0.17, 0.22)})
			m.boxes.append([Vector3(0, -0.5, 48), Vector3(12, 1, 16), Color(0.25, 0.28, 0.4)])
			m.spins.append({c = Vector3(0, 0, 46), len = 6.2, y0 = 0.05, y1 = 0.55, speed = 1.4, arms = 4, th = 0.25, accel = 0.0, phase = 0.0, col = YELLOW})
			m.finish = AABB(Vector3(-6, -0.2, 52.5), Vector3(12, 3, 3.5))
			m.checkpoints = [[24.0, Vector3(0, 0, 25)], [40.0, Vector3(0, 0, 41)]]
			m.waypoints = [Vector3(0, 0, 7.5), Vector3(0, 0, 23.5), Vector3(0, 0, 40.5), Vector3(0, 0, 54.5)]
			m.sky = "server"
		"printer":
			_start(m, 12.0)
			# three lanes of paper sheets that tip, each with its own pattern to learn:
			# left ripples, the middle tips in a wave that rolls forward (ride behind it), the right tips all at once
			for l in 3:
				for k in 6:
					var ph: float = [k * 0.09, -k * 0.16, 0.5][l]
					m.drops.append({c = Vector3(-3.6 + l * 3.6, -0.15, 9.5 + k * 3), s = Vector3(3.2, 0.3, 3), period = 3.0, off = 0.25, phase = ph,
						col = [WHITE, Color(1.0, 0.95, 0.75), Color(0.85, 0.95, 1.0)][l]})
			m.boxes.append([Vector3(0, -0.5, 35), Vector3(12, 1, 18), Color(0.92, 0.9, 0.82)])
			for p in [[1.0, 30.0, 0.0], [-1.0, 34.0, 0.5], [1.0, 38.0, 0.25], [-1.0, 42.0, 0.75]]:
				m.pushers.append({c = Vector3(-p[0] * 7.6, 0.6, p[1]), s = Vector3(3.2, 1.2, 2.0), dir = Vector3(p[0], 0, 0), amp = 5.0, period = 2.2, phase = p[2], col = RED})
			m.pends.append({pivot = Vector3(0, 6.5, 32), len = 5.6, amp = 1.05, period = 2.6, phase = 0.0, r = 0.9})
			m.pends.append({pivot = Vector3(0, 6.5, 39.5), len = 5.6, amp = 1.05, period = 2.6, phase = 0.5, r = 0.9})
			m.boxes.append([Vector3(0, -0.5, 48), Vector3(12, 1, 8), PURPLE])
			m.finish = AABB(Vector3(-6, -0.2, 48.5), Vector3(12, 3, 3.5))
			m.checkpoints = [[26.0, Vector3(0, 0, 27.5)]]
			m.waypoints = [Vector3(0, 0, 7.5), Vector3(0, 0, 26.5), Vector3(0, 0, 44.5), Vector3(0, 0, 50)]
		"hotdesk":
			for layer in 2:
				for i in 7:
					for j in 7:
						m.tiles.append([Vector3((i - 3) * 2.7, -0.25 - layer * 6.0, (j - 3) * 2.7), Vector3(2.5, 0.5, 2.5)])
			m.spawn = Vector3(0, 0, 0); m.spread = Vector2(14, 14)
			m.fall_y = -12.0; m.dur = 100.0
		"mopup":
			m.discs.append([Vector3(0, 0, 0), 11.0])
			m.spins.append({c = Vector3(0, 0, 0), len = 11.0, y0 = 0.05, y1 = 0.6, speed = 1.0, arms = 2, th = 0.3, accel = 0.032, phase = 0.0, col = YELLOW})
			# a second, higher mop joins later (you can't jump this one: dive under or get out of the way)
			m.spins.append({c = Vector3(0, 0, 0), len = 11.0, y0 = 1.25, y1 = 1.75, speed = -0.6, arms = 1, th = 0.3, accel = -0.012, phase = 1.6, col = PINK})
			m.spawn = Vector3(0, 0, 0); m.spread = Vector2(13, 13)
			m.fall_y = -6.0; m.dur = 100.0
		"mailroom":
			m.boxes.append([Vector3(0, -0.5, 0), Vector3(24, 1, 30), Color(0.85, 0.82, 0.72)])
			for sx in [-1.0, 1.0]:
				m.boxes.append([Vector3(sx * 12.25, 0.6, 0), Vector3(0.5, 1.2, 30), GREY])
				for sz in [-1.0, 1.0]:
					m.boxes.append([Vector3(sx * 8.5, 0.6, sz * 15.25), Vector3(7, 1.2, 0.5), GREY])
			for t in 2:
				var sz := 1.0 if t == 0 else -1.0
				m.boxes.append([Vector3(0, -0.5, sz * 17.25), Vector3(10, 1, 4), [CYAN, PINK][t]])
				m.boxes.append([Vector3(0, 0.6, sz * 19.5), Vector3(10, 1.2, 0.5), GREY])
				m.boxes.append([Vector3(-5.25, 0.6, sz * 17.25), Vector3(0.5, 1.2, 4.5), GREY])
				m.boxes.append([Vector3(5.25, 0.6, sz * 17.25), Vector3(0.5, 1.2, 4.5), GREY])
				m.goals.append({box = AABB(Vector3(-5, -0.5, (15.6 if t == 0 else -19.4)), Vector3(10, 4, 3.8)), team = t})
			m.tubs = [Vector3(-5, 1.3, 0), Vector3(0, 1.3, 0), Vector3(5, 1.3, 0)]
			m.spawn = Vector3(0, 0, 0); m.spread = Vector2(18, 20)
			m.dur = 70.0
		"crown":
			_start(m, 10.0)
			m.boxes.append([Vector3(0, 0.7, 10.5), Vector3(7, 1, 3), CYAN])
			m.movers.append({c = Vector3(0, 2.1, 14), s = Vector3(3, 0.6, 3), axis = Vector3(1, 0, 0), amp = 3.6, period = 3.2, phase = 0.0, col = PINK})
			m.boxes.append([Vector3(0, 3.1, 18.5), Vector3(8, 1, 4), YELLOW])
			m.boxes.append([Vector3(0, 4.3, 24.5), Vector3(10, 1, 7), WHITE])
			m.spins.append({c = Vector3(0, 4.8, 24.5), len = 4.8, y0 = 0.05, y1 = 0.6, speed = 1.7, arms = 2, th = 0.25, accel = 0.0, phase = 0.0, col = ORANGE})
			m.movers.append({c = Vector3(0, 5.7, 30), s = Vector3(3, 0.6, 3), axis = Vector3(1, 0, 0), amp = 3.8, period = 2.8, phase = 1.0, col = CYAN})
			m.boxes.append([Vector3(0, 6.7, 34), Vector3(8, 1, 4), PINK])
			m.pushers.append({c = Vector3(-5.6, 7.9, 34), s = Vector3(2.4, 1.2, 1.6), dir = Vector3(1, 0, 0), amp = 3.6, period = 2.4, phase = 0.0, col = RED})
			m.boxes.append([Vector3(0, 7.9, 38.5), Vector3(8, 1, 4), YELLOW])
			m.pushers.append({c = Vector3(5.4, 4.1, 18.5), s = Vector3(2.4, 1.2, 1.6), dir = Vector3(-1, 0, 0), amp = 3.4, period = 2.2, phase = 0.4, col = RED})
			m.pushers.append({c = Vector3(5.6, 9.1, 38.5), s = Vector3(2.4, 1.2, 1.6), dir = Vector3(-1, 0, 0), amp = 3.6, period = 2.0, phase = 0.6, col = RED})
			m.boxes.append([Vector3(0, 9.1, 44), Vector3(10, 1, 7), PURPLE])
			m.spins.append({c = Vector3(0, 9.6, 43.5), len = 3.6, y0 = 0.05, y1 = 0.6, speed = -2.2, arms = 2, th = 0.25, accel = 0.0, phase = 0.3, col = YELLOW})
			m.crown = Vector3(0, 10.4, 45.5)
			m.checkpoints = [[21.5, Vector3(0, 4.8, 22.5)]]
			m.waypoints = [Vector3(0, 0, 7.6), Vector3(0, 1.2, 10.5), Vector3(0, 2.4, 14), Vector3(0, 3.6, 18.5), Vector3(0, 4.8, 27.5),
				Vector3(0, 6.0, 30), Vector3(0, 7.2, 34), Vector3(0, 8.4, 38.5), Vector3(0, 9.6, 45)]
			m.sky = "dusk"
		"lastdesk":
			for layer in 2:
				for i in 7:
					for j in 7:
						m.tiles.append([Vector3((i - 3) * 2.7, -0.25 - layer * 6.0, (j - 3) * 2.7), Vector3(2.5, 0.5, 2.5)])
			m.spawn = Vector3(0, 0, 0); m.spread = Vector2(14, 14)
			m.fall_y = -12.0; m.dur = 150.0
			m.sky = "dusk"
	return m
