extends RefCounted
## Card room: the shared base of the rules engines for Thulla, Seep, Dehla Pakad, Kadi Patta, Teen Patti and
## Satte Pe Satta (Rung keeps its own cards_sim.gd). No visuals. The host (or a local game) runs it; guests mirror
## a filtered snapshot that holds ONLY their own cards.
##
## Cards are ints: suit * 13 + rank, rank 0..12 = 2..A. Suits: 0 spades, 1 hearts, 2 diamonds, 3 clubs.
## Every action is a Dictionary {a = "..."} so the same call serves the local player, a guest's message and the CPU.
## A subclass fills in: _begin(), actor(), cpu(seat), act(seat, a), _timed(dt), _snap(seat), _unsnap(s), result_lines().

const SUITS := ["♠", "♥", "♦", "♣"]
const SUIT_NAMES := ["SPADES", "HEARTS", "DIAMONDS", "CLUBS"]
const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const TURN_TIME := 25.0            # online: an idle player is played for after this long

class Player:
	var seat := 0
	var C: Dictionary
	var human := false
	var slot := -1                 # online lobby seat (0 = host); pass & play: -2; CPU: -1
	var hand: Array = []           # card ints (a guest only knows its own; others are -1 placeholders)
	var out := false               # escaped / packed / finished
	var place := 0                 # finishing place (1 = first), 0 = still playing
	var chips := 0                 # Teen Patti
	var seen := false              # Teen Patti: has looked at their cards
	var pts := 0                   # per-game score (Seep points etc.)

var variant := ""
var players: Array = []
var n := 4
var phase := "start"
var turn := 0
var dealer := 0
var events: Array = []             # new since the last read: [kind, ...]
var rev := 0
var rng := RandomNumberGenerator.new()
var think := 0.7                   # CPU thinking time (tests set it to 0)
var wait := 0.0
var idle := 0.0
var illegal := 0                   # rejected actions (tests)
var steps := 0                     # actions taken (safety cap)


static func suit_of(c: int) -> int: return c / 13
static func rank_of(c: int) -> int: return c % 13
static func is_red(c: int) -> bool: return suit_of(c) in [1, 2]
static func label(c: int) -> String: return RANKS[rank_of(c)] + SUITS[suit_of(c)]


## people: [{C, human, slot}] in seat order.
func setup(people: Array, seed := 1) -> void:
	rng.seed = seed
	n = people.size()
	for k in n:
		var p := Player.new()
		var src: Dictionary = people[k]
		p.seat = k; p.C = src.C; p.human = bool(src.get("human", false)); p.slot = int(src.get("slot", -1))
		players.append(p)
	dealer = rng.randi() % n
	_begin()


## A shuffled deck with our own rng, so a seed always deals the same cards.
func shuffled(cards: Array) -> Array:
	var d := cards.duplicate()
	for i in range(d.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = d[i]; d[i] = d[j]; d[j] = t
	return d


func full_deck() -> Array:
	var d := []
	for c in 52: d.append(c)
	return d


static func sort_hand(h: Array, trump := -1) -> void:
	h.sort_custom(func(a, b):
		if a < 0 or b < 0: return a > b
		var sa: int = suit_of(a); var sb: int = suit_of(b)
		var ka: int = -1 if sa == trump else sa
		var kb: int = -1 if sb == trump else sb
		if ka != kb: return ka < kb
		return rank_of(a) > rank_of(b))


func emit(e: Array) -> void:
	events.append(e)
	rev += 1


func cur() -> Player:
	var a := actor()
	return players[a] if a >= 0 else null


func next_seat(from: int, skip_out := true) -> int:
	for k in range(1, n + 1):
		var s := (from + k) % n
		if not skip_out or not (players[s] as Player).out: return s
	return from


# ---------------------------------------------------------------- to override
func _begin() -> void: pass
## Seat that must act now, or -1 (dealing, pauses, done).
func actor() -> int: return -1
func cpu(_seat: int) -> Dictionary: return {}
func act(_seat: int, _a: Dictionary) -> bool: return false
## Timed phases (dealing, pauses between tricks): return true while time is being spent there.
func _timed(_dt: float) -> bool: return false
func _snap(_seat: int) -> Dictionary: return {}
func _unsnap(_s: Dictionary) -> void: pass
func result_lines() -> Array: return []
func winner_seats() -> Array: return []


## Time passes: timed phases tick, CPU players think, idle online players get played for.
func update(dt: float) -> void:
	if phase == "done": return
	if _timed(dt): return
	var a := actor()
	if a < 0: return
	var p: Player = players[a]
	if not p.human:
		wait -= dt
		if wait > 0.0: return
		wait = think
		var mv := cpu(a)
		if not act(a, mv): illegal += 1; _stuck(a)
		return
	idle += dt
	if idle > TURN_TIME and p.slot >= 0:
		idle = 0.0
		if not act(a, cpu(a)): _stuck(a)


## A CPU move was refused (shouldn't happen): don't hang the table.
func _stuck(_seat: int) -> void: pass


# ---------------------------------------------------------------- multiplayer
## What one seat may see: their own cards, everyone's card counts and public state. seat -1 = spectator.
func snapshot_for(seat: int) -> Dictionary:
	var ps := []
	for p in players:
		var h = p.hand.duplicate() if (p.seat == seat and _hand_visible(p)) else p.hand.size()
		ps.append([h, p.out, p.place, p.chips, p.seen, p.pts])
	var s := {v = variant, p = ps, ph = phase, tu = turn, dl = dealer, rev = rev, idle = snappedf(idle, 0.1), w = snappedf(wait, 0.05)}
	s.merge(_snap(seat))
	return s


## Teen Patti hides your own cards until you look; everyone else always sees their own.
func _hand_visible(_p: Player) -> bool: return true


func apply(s: Dictionary) -> void:
	var ps: Array = s.p
	for k in mini(ps.size(), players.size()):
		var p: Player = players[k]
		var e: Array = ps[k]
		var h = e[0]
		p.hand = []
		if h is Array:
			for c in h: p.hand.append(int(c))
		else:
			for i in int(h): p.hand.append(-1)
		p.out = bool(e[1]); p.place = int(e[2]); p.chips = int(e[3]); p.seen = bool(e[4]); p.pts = int(e[5])
	phase = String(s.ph); turn = int(s.tu); dealer = int(s.dl); rev = int(s.rev)
	idle = float(s.get("idle", 0.0)); wait = float(s.get("w", 0.0))
	_unsnap(s)


static func cards_of(a) -> Array:
	var out := []
	for c in a: out.append(int(c))
	return out
