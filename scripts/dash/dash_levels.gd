extends RefCounted
## Deadline Dash levels: hand-authored ASCII chunks (bottom-aligned, the last two rows are the floor),
## strung together per level. Rows are written top to bottom; missing top rows are empty air.
##
## Tiles
##   #  floor / wall          D  desk (solid, 1 high)     W  water cooler (solid)    R  server rack (solid)
##   G  steel girder          B  cubicle panel (breaks when caffeinated, else just bumps)
##   ?  sticky-note block (a BNB coin)      P  sticky note with a power-up      H  sticky note with headphones
##   -  one-way ledge (jump up through it)  ^  shredder (spikes)                 o  BNB coin
##   m  moving platform, sideways (3 wide)  v  cable lift, up and down (3 wide)
##   e  stapler bot (walks)   f  drone (hovers)   h  printer bot (hops)
##   S  start   C  checkpoint   E  elevator exit (2 high)   K  boss

const H := 14

const CHUNKS := {
	# ---------------------------------------------------------------- office floor
	"o_start": [
		"............",
		"............",
		".S..........",
		"############",
		"############"],
	"o_blocks": [
		"..................",
		".......ooo........",
		"..................",
		"....?.P.?.........",
		"..................",
		"..................",
		"...........e......",
		"##################",
		"##################"],
	"o_desks": [
		"....................",
		"..........ooo.......",
		"....................",
		"........D...........",
		"....D...D....e..D...",
		"####################",
		"####################"],
	"o_gap": [
		"..................",
		"........ooo.......",
		"..................",
		"..................",
		"..............e...",
		"######....########",
		"######....########"],
	"o_steps": [
		"....................",
		"..............ooo...",
		"............-----...",
		"........###.........",
		"......#####.........",
		"....#######...h.....",
		"####################",
		"####################"],
	"o_cooler": [
		"......................",
		"....o.o.o.............",
		"...BB?BB..............",
		"......................",
		"......................",
		"..........W.....W.....",
		".....e....W..e..W.....",
		"######################",
		"######################"],
	"o_ledges": [
		"......................",
		"............ooo.......",
		"...........-----......",
		"......ooo.............",
		".....-----............",
		"......................",
		"...................f..",
		"..........e...........",
		"######....#####...####",
		"######....#####...####"],
	"o_shred": [   # the note blocks sit over the safe floor between the shredders, never over them
		"....................",
		"...........o........",
		"..........?P?.......",
		"....................",
		"....................",
		"....................",
		"......^^^....^^^....",
		"####################",
		"####################"],
	# ---------------------------------------------------------------- server room
	"s_start": [
		"............",
		"............",
		".S..........",
		"############",
		"############"],
	"s_racks": [
		"......................",
		"......ooo.............",
		".....RRRRR......o.o...",
		"......................",
		"......................",
		"....R.........R.......",
		"....R...e.....R...h...",
		"######################",
		"######################"],
	"s_lift": [
		"......................",
		"........ooo...........",
		"......................",
		"......................",
		"......................",
		"......................",
		"........v.............",
		"......................",
		"#####...##...#########",
		"#####...##...#########"],
	"s_sparks": [
		"........................",
		"..........ooooo.........",
		"..........-----.........",
		"........................",
		"....?..P..........?.....",
		"........................",
		"........................",
		".........^^^^^^.....f...",
		"########################",
		"########################"],
	"s_maze": [
		"........................",
		"...........ooo..........",
		"......RRRRRRRRRRRR......",
		"........................",
		"........................",
		"..............h.........",
		"....RRRRRR....RRRRRR....",
		"........................",
		"..e.....................",
		"########################",
		"########################"],
	"s_lifts2": [
		"..........................",
		".......o.....o.....o......",
		"..........................",
		"..........................",
		"..........................",
		"......v.....v.....v.......",
		"..........................",
		"..........................",
		"####..###...###...###..###",
		"####..###...###...###..###"],
	# ---------------------------------------------------------------- rooftop & city
	"r_start": [
		"............",
		"............",
		".S..........",
		"GGGGGGGGGGGG",
		"GGGGGGGGGGGG"],
	"r_crane": [
		"..........................",
		"...........ooo............",
		"..........................",
		"..........................",
		"..........................",
		"..........m...............",
		"..........................",
		"..........................",
		"GGGGG....GG....GG....GGGGG",
		"GGGGG....GG....GG....GGGGG"],
	"r_vents": [
		"......................",
		"............ooo.......",
		"...........?.H........",
		"......................",
		"......................",
		"......................",
		"...W.......^^.....W...",
		"...W...e..GGGG..f.W...",
		"GGGGGGGGGGGGGGGGGGGGGG",
		"GGGGGGGGGGGGGGGGGGGGGG"],
	"r_gaps": [
		"..........................",
		"....ooo.......ooo.........",
		"..........................",
		"..........................",
		"...........h..............",
		"GGGGG....GGGGG....GGGGGGGG",
		"GGGGG....GGGGG....GGGGGGGG"],
	"r_towers": [
		"........................",
		"..........ooo...........",
		".........GGGGG..........",
		"........................",
		"..o.o..............o.o..",
		"........................",
		"........................",
		"........f...........e...",
		"GGGGGG....GGGG....GGGGGG",
		"GGGGGG....GGGG....GGGGGG"],
	# ---------------------------------------------------------------- penthouse
	"p_start": [
		"............",
		"............",
		".S..........",
		"############",
		"############"],
	"p_gallery": [
		"........................",
		"......ooo.......ooo.....",
		".....-----.....-----....",
		"........................",
		"...?P?..................",
		"........................",
		"..........h.......e.....",
		"########################",
		"########################"],
	"p_gauntlet": [
		"..........................",
		"........o..o..o..o........",
		"..........................",
		"..........................",
		"..........................",
		"......m...........m.......",
		"..........................",
		".....^^^^^^^^^^^^^^^^.....",
		"####################......",
		"####################......"],
	# ---------------------------------------------------------------- shared pieces
	"cp": [
		"........",
		"........",
		"...C....",
		"########",
		"########"],
	"cp_g": [
		"........",
		"........",
		"...C....",
		"GGGGGGGG",
		"GGGGGGGG"],
	"exit": [
		"..........",
		"..........",
		"......E..#",
		"......E..#",
		"##########",
		"##########"],
	"exit_g": [
		"..........",
		"..........",
		"......E..G",
		"......E..G",
		"GGGGGGGGGG",
		"GGGGGGGGGG"],
	# boss arena: walls close behind you once the fight starts; the exit opens when the boss falls
	"arena": [
		"............................",
		"............................",
		"............................",
		".......---..........---.....",
		"............................",
		"............................",
		"............................",
		"....................K...E..#",
		"........................E..#",
		"############################",
		"############################"],
	"arena_g": [
		"............................",
		"............................",
		"............................",
		".......---..........---.....",
		"............................",
		"............................",
		"............................",
		"....................K...E..G",
		"........................E..G",
		"GGGGGGGGGGGGGGGGGGGGGGGGGGGG",
		"GGGGGGGGGGGGGGGGGGGGGGGGGGGG"],
}

## Lifts and cranes are the bonus route (coins up there); stepping stones below keep every gap jumpable (4 tiles max).
## world: office / server / roof / penthouse. boss: who waits at the end ("" = none).
const LEVELS := [
	{name = "MONDAY MORNING", world = "office", chunks = ["o_start", "o_blocks", "o_desks", "o_gap", "o_steps", "cp", "o_cooler", "o_blocks", "o_gap", "o_ledges", "exit"]},
	{name = "OPEN PLAN PANIC", world = "office", chunks = ["o_start", "o_desks", "o_cooler", "o_ledges", "o_shred", "cp", "o_steps", "o_gap", "o_blocks", "o_shred", "o_ledges", "exit"]},
	{name = "HR ON THE LINE", world = "office", boss = "hr", chunks = ["o_start", "o_blocks", "o_shred", "o_ledges", "cp", "o_cooler", "o_gap", "arena"]},
	{name = "THE SERVER ROOM", world = "server", chunks = ["s_start", "s_racks", "s_sparks", "s_lift", "s_maze", "cp", "s_racks", "s_lift", "s_sparks", "exit"]},
	{name = "COLD AISLE", world = "server", chunks = ["s_start", "s_maze", "s_lifts2", "s_sparks", "cp", "s_racks", "s_lift", "s_maze", "s_lifts2", "exit"]},
	{name = "THE MAINFRAME", world = "server", boss = "admin", chunks = ["s_start", "s_racks", "s_lifts2", "cp", "s_sparks", "s_maze", "arena"]},
	{name = "ROOFTOP RUN", world = "roof", wind = true, chunks = ["r_start", "r_gaps", "r_vents", "r_crane", "cp_g", "r_towers", "r_gaps", "r_vents", "exit_g"]},
	{name = "CRANE SEASON", world = "roof", wind = true, chunks = ["r_start", "r_crane", "r_towers", "r_gaps", "cp_g", "r_crane", "r_vents", "r_towers", "r_crane", "exit_g"]},
	{name = "STORM OVER THE CITY", world = "roof", wind = true, boss = "wizard", chunks = ["r_start", "r_towers", "r_crane", "cp_g", "r_gaps", "r_vents", "arena_g"]},
	{name = "THE CEO'S PENTHOUSE", world = "penthouse", boss = "ceo", chunks = ["p_start", "p_gallery", "p_gauntlet", "o_shred", "cp", "p_gallery", "s_sparks", "arena"]},
]

const WORLD_NAME := {"office": "OFFICE FLOOR", "server": "SERVER ROOM", "roof": "ROOFTOP", "penthouse": "PENTHOUSE"}


## The level as rows of equal width (top row first), H rows tall.
static func build(i: int) -> Array:
	var rows: Array = []
	for r in H: rows.append("")
	for name in LEVELS[i].chunks:
		var c: Array = CHUNKS[name]
		var w := 0
		for line in c: w = maxi(w, String(line).length())
		for r in H:
			var src := r - (H - c.size())
			var line := String(c[src]) if src >= 0 else ""
			rows[r] += line.rpad(w, ".").substr(0, w)
	return rows
