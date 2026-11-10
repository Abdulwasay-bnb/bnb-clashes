extends "res://scripts/cards/room_sim.gd"
## SEEP (Sweep), 2 players or 4 in partnerships (seats 0 & 2 against 1 & 3). Card values: A = 1, 2–10 face value,
## J = 11, Q = 12, K = 13. Points: every spade is worth its value, the other three aces 1 each, the 10♦ 6: 100 a deal.
##
## The player after the dealer is dealt 4 cards and BIDS a value 9–13 that they hold; 4 cards go face up on the
## table, the rest is dealt (12 each; with 2 players a second 12 each when the hands run out). On your turn play
## one card to:
##   CAPTURE  table cards that add up to its value (several groups at once) and any house of that value,
##   BUILD    a house: the card plus table cards adding up to 9–13, when you hold another card of that value,
##   CEMENT   an existing house of a value you hold (it can't be broken any more),
##   THROW    it face up on the table.
## The bidder's first card must be one of the bid value (or build a house of it). Clearing the whole table is a
## SEEP: +50 (not on the last play of the deal). At the end the last player to capture takes what's left.
## Simplifications: houses can't be raised to a higher value; a match is 2 deals and the higher total wins.

const DEALS := 2

var table: Array = []              # loose cards face up
var houses: Array = []             # {id, v, cards, team, pakka}
var next_house := 1
var bidder := 0
var bid := 0
var bid_pending := false           # the bidder's first move must use the bid value
var deck: Array = []
var deal_n := 0
var team_pts := [0, 0]             # match totals
var deal_pts := [0, 0]
var seeps := [0, 0]
var captured: Array = [[], []]     # this deal, per team
var last_capture := -1             # seat
var last_move := {}


static func val(c: int) -> int:
	var r := rank_of(c)
	return 1 if r == 12 else r + 2


static func points(c: int) -> int:
	if suit_of(c) == 0: return val(c)
	if rank_of(c) == 12: return 1
	if c == 2 * 13 + 8: return 6       # 10♦
	return 0


func team_of(seat: int) -> int:
	return seat % 2


func _begin() -> void:
	variant = "seep"
	_new_deal()


func _new_deal() -> void:
	deal_n += 1
	dealer = (dealer + 1) % n
	bidder = (dealer + 1) % n
	table = []; houses = []; captured = [[], []]; deal_pts = [0, 0]; last_capture = -1; last_move = {}
	for p in players: p.hand = []
	# deal the bidder 4; they need a card of 9..13 to bid with (otherwise it's dealt again)
	for tries in 20:
		deck = shuffled(full_deck())
		var four: Array = []
		for k in 4: four.append(deck.pop_back())
		if four.any(func(c): return val(c) >= 9):
			(players[bidder] as Player).hand = four
			break
	sort_hand((players[bidder] as Player).hand)
	phase = "deal"; wait = 1.0; turn = bidder
	emit(["deal", dealer, bidder, deal_n])


func actor() -> int:
	if phase == "bid": return bidder
	return turn if phase == "play" else -1


func bids(seat: int) -> Array:
	var out := []
	for c in (players[seat] as Player).hand:
		var v := val(c)
		if v >= 9 and not (v in out): out.append(v)
	out.sort()
	return out


func _after_bid() -> void:
	for k in 4: table.append(deck.pop_back())
	_deal_hands()
	bid_pending = true
	phase = "play"; turn = bidder; wait = think; idle = 0.0
	emit(["turn", turn])


func _deal_hands() -> void:
	for k in n:
		var p: Player = players[(bidder + k) % n]
		while p.hand.size() < 12 and not deck.is_empty(): p.hand.append(deck.pop_back())
		sort_hand(p.hand)


# ---------------------------------------------------------------- moves
## Groups of table cards that each add up to v, picked greedily (most cards first). Returns the cards.
static func capture_set(loose: Array, v: int) -> Array:
	var pool := loose.duplicate()
	var got := []
	while true:
		var best: Array = []
		var m := mini(pool.size(), 12)
		for mask in range(1, 1 << m):
			var sum := 0
			var pick := []
			for i in m:
				if mask & (1 << i): sum += val(pool[i]); pick.append(pool[i])
			if sum == v and pick.size() > best.size(): best = pick
		if best.is_empty(): break
		for c in best: pool.erase(c); got.append(c)
	return got


## The smallest-sum-first subset of loose cards adding up to exactly `need` (most cards), or null.
static func subset_sum(loose: Array, need: int):
	if need == 0: return []
	var best = null
	var m := mini(loose.size(), 12)
	for mask in range(1, 1 << m):
		var sum := 0
		var pick := []
		for i in m:
			if mask & (1 << i): sum += val(loose[i]); pick.append(loose[i])
		if sum == need and (best == null or pick.size() > (best as Array).size()): best = pick
	return best


func _holds_other(seat: int, c: int, v: int) -> bool:
	for h in (players[seat] as Player).hand:
		if h != c and val(h) == v: return true
	return false


static func move_key(m: Dictionary) -> String:
	var t: Array = (m.get("take", []) as Array).map(func(x): return int(x)); t.sort()
	var hs: Array = (m.get("hs", []) as Array).map(func(x): return int(x)); hs.sort()
	return "%d|%s|%s|%s|%d" % [int(m.c), String(m.k), str(t), str(hs), int(m.get("h", 0))]


func moves(seat: int) -> Array:
	if phase != "play" or seat != turn: return []
	var out := []
	var hand: Array = (players[seat] as Player).hand
	var done := {}
	for c in hand:
		var v := val(c)
		if done.has(v * 4 + suit_of(c)): continue
		done[v * 4 + suit_of(c)] = true
		# capture
		var take := capture_set(table, v)
		var hs := houses.filter(func(h): return int(h.v) == v).map(func(h): return int(h.id))
		if not take.is_empty() or not hs.is_empty():
			out.append({c = c, k = "capture", take = take, hs = hs})
		# build a new house of H (no house of that value on the table yet)
		for H in range(maxi(9, v + 1), 14):
			if houses.any(func(h): return int(h.v) == H): continue
			if not _holds_other(seat, c, H): continue
			var sub = subset_sum(table, H - v)
			if sub != null and not (sub as Array).is_empty(): out.append({c = c, k = "build", take = sub, h = H})
		# cement onto a house of a value we hold
		for h in houses:
			var H := int(h.v)
			if v > H or not _holds_other(seat, c, H): continue
			var sub = subset_sum(table, H - v)
			if sub != null: out.append({c = c, k = "cement", take = sub, hs = [int(h.id)], h = H})
		out.append({c = c, k = "throw"})
	if bid_pending and seat == bidder:
		out = out.filter(func(m): return val(int(m.c)) == bid or (String(m.k) in ["build", "cement"] and int(m.get("h", 0)) == bid))
	return out


func legal(seat: int) -> Array:
	var cs := []
	for m in moves(seat):
		if not (int(m.c) in cs): cs.append(int(m.c))
	return cs


func act(seat: int, a: Dictionary) -> bool:
	var kind := String(a.get("a", ""))
	if kind == "bid":
		var v := int(a.get("v", 0))
		if phase != "bid" or seat != bidder or not (v in bids(seat)): return false
		bid = v
		emit(["bid", seat, v])
		_after_bid()
		return true
	if kind != "move": return false
	var want: Dictionary = a.get("m", {})
	if want.is_empty(): return false
	var key := move_key(want)
	var m: Dictionary = {}
	for x in moves(seat):
		if move_key(x) == key: m = x; break
	if m.is_empty(): return false
	_do(seat, m)
	return true


func _do(seat: int, m: Dictionary) -> void:
	var p: Player = players[seat]
	var c := int(m.c)
	var tm := team_of(seat)
	p.hand.erase(c)
	bid_pending = false
	idle = 0.0; steps += 1
	last_move = {s = seat, c = c, k = m.k}
	match String(m.k):
		"capture":
			var got := [c]
			for t in m.take: table.erase(int(t)); got.append(int(t))
			for hid in m.get("hs", []):
				for h in houses.duplicate():
					if int(h.id) == int(hid): got.append_array(h.cards); houses.erase(h)
			captured[tm].append_array(got)
			last_capture = seat
			var seep: bool = table.is_empty() and houses.is_empty() and not _deal_over_after()
			if seep: seeps[tm] += 1; deal_pts[tm] += 50
			emit(["capture", seat, c, got.size(), seep])
		"build":
			var cards := [c]
			for t in m.take: table.erase(int(t)); cards.append(int(t))
			houses.append({id = next_house, v = int(m.h), cards = cards, team = tm, pakka = false})
			next_house += 1
			emit(["build", seat, c, int(m.h)])
		"cement":
			var hid := int(m.hs[0])
			for h in houses:
				if int(h.id) == hid:
					h.cards.append(c)
					for t in m.take: table.erase(int(t)); h.cards.append(int(t))
					h.pakka = true; h.team = tm
			emit(["cement", seat, c, int(m.h)])
		_:
			table.append(c)
			emit(["throw", seat, c])
	_next()


func _deal_over_after() -> bool:
	if not deck.is_empty(): return false
	for p in players:
		if not p.hand.is_empty(): return false
	return true


func _next() -> void:
	if players.all(func(p): return p.hand.is_empty()):
		if not deck.is_empty():
			_deal_hands()
			emit(["redeal"])
		else:
			_end_deal()
			return
	turn = (turn + 1) % n
	wait = think
	emit(["turn", turn])


func _end_deal() -> void:
	# the last player to capture sweeps up what's left
	var rest := table.duplicate()
	for h in houses: rest.append_array(h.cards)
	if last_capture >= 0: captured[team_of(last_capture)].append_array(rest)
	table = []; houses = []
	for t in 2:
		for c in captured[t]: deal_pts[t] += points(c)
		team_pts[t] += deal_pts[t]
	for p in players: p.pts = team_pts[team_of(p.seat)]
	emit(["deal_end", deal_pts[0], deal_pts[1], team_pts[0], team_pts[1]])
	phase = "deal_end"; wait = 3.0


func _timed(dt: float) -> bool:
	match phase:
		"deal":
			wait -= dt
			if wait <= 0.0: phase = "bid"; wait = think; idle = 0.0; emit(["choose", bidder])
			return true
		"deal_end":
			wait -= dt
			if wait <= 0.0:
				if deal_n >= DEALS:
					phase = "done"; emit(["done", 0 if team_pts[0] >= team_pts[1] else 1])
				else:
					_new_deal()
			return true
	return false


# ---------------------------------------------------------------- CPU
func cpu(seat: int) -> Dictionary:
	if phase == "bid":
		var b := bids(seat)
		return {a = "bid", v = b[b.size() - 1] if not b.is_empty() else 13}
	var best: Dictionary = {}
	var bs := -INF
	for m in moves(seat):
		var c := int(m.c)
		var v := 0.0
		match String(m.k):
			"capture":
				var got: Array = [c] + (m.take as Array)
				for hid in m.get("hs", []):
					for h in houses: if int(h.id) == int(hid): got.append_array(h.cards)
				for x in got: v += points(x) + 0.6
				var left := table.size() - (m.take as Array).size()
				if left == 0 and houses.size() == (m.get("hs", []) as Array).size(): v += 50.0
			"build": v = 4.0 + float(points(c))
			"cement": v = 5.0 + float(points(c))
			_:
				v = -float(points(c)) * 1.5 - val(c) * 0.05
				# a throw that hands the next player an easy seep
				var sum := val(c)
				for t in table: sum += val(t)
				if houses.is_empty() and sum <= 13: v -= 12.0
		v += rng.randf() * 0.3
		if v > bs: bs = v; best = m
	return {a = "move", m = best}


func _stuck(seat: int) -> void:
	var ms := moves(seat)
	if not ms.is_empty(): _do(seat, ms[ms.size() - 1])


func _snap(_seat: int) -> Dictionary:
	var hs := []
	for h in houses: hs.append([int(h.id), int(h.v), (h.cards as Array).duplicate(), int(h.team), bool(h.pakka)])
	return {tb = table.duplicate(), hs = hs, bd = bidder, bv = bid, bp = bid_pending, dn = deal_n, tp = team_pts.duplicate(),
		dp = deal_pts.duplicate(), se = seeps.duplicate(), cn = [captured[0].size(), captured[1].size()], lc = last_capture, dk = deck.size(), nh = next_house}


func _unsnap(s: Dictionary) -> void:
	table = cards_of(s.tb)
	houses = []
	for h in s.hs: houses.append({id = int(h[0]), v = int(h[1]), cards = cards_of(h[2]), team = int(h[3]), pakka = bool(h[4])})
	bidder = int(s.bd); bid = int(s.bv); bid_pending = bool(s.bp); deal_n = int(s.dn)
	team_pts = [int(s.tp[0]), int(s.tp[1])]; deal_pts = [int(s.dp[0]), int(s.dp[1])]; seeps = [int(s.se[0]), int(s.se[1])]
	last_capture = int(s.lc); next_house = int(s.nh)
	captured = [[], []]
	for t in 2:
		for i in int(s.cn[t]): captured[t].append(-1)
	deck = []
	for i in int(s.dk): deck.append(-1)


func result_lines() -> Array:
	return []


func winner_seats() -> Array:
	var w := 0 if team_pts[0] >= team_pts[1] else 1
	return players.filter(func(p): return team_of(p.seat) == w).map(func(p): return p.seat)
