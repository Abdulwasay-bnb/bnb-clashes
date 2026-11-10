extends "res://scripts/cards/room_sim.gd"
## TEEN PATTI (three cards), 3–6 players, played with OFFICE CHIPS only — they're pretend, worth nothing.
## Each hand: everyone puts the boot in the pot and gets three cards face down. In turn a player plays BLIND
## (without looking: half price) or SEEN (after looking): CHAAL (call the current stake), RAISE (double it) or
## PACK (fold). When two players are left, either may ask for a SHOW: the hands are compared and the best takes
## the pot. The last player standing takes it too.
## Hand ranks: trail (three of a kind) > pure sequence (straight flush) > sequence > colour (flush) > pair > high
## card. A-K-Q is the top sequence, A-2-3 the next one down.
## Simplifications: no side-show; the stake is capped at 16 × boot; once the pot passes 40 × boot everyone left
## goes to a show. A match is 5 hands (or until someone runs out of chips); most chips wins.

const START_CHIPS := 1000
const BOOT := 10
const MAX_STAKE := 160
const POT_LIMIT := 400
const HANDS := 5

var pot := 0
var stake := BOOT                  # what a BLIND player pays to chaal (seen players pay double)
var hand_n := 0
var in_hand: Array = []            # seats still in this hand
var acted := 0                     # bets made this hand (a show needs everyone to have had a go)
var reveal: Array = []             # seats whose cards are public (show)
var last_winner := -1
var last_rank := ""
var cards_out: Array = []          # every hand's cards (host only), for the show


func _begin() -> void:
	variant = "teenpatti"
	for p in players: p.chips = START_CHIPS
	_new_hand()


func _new_hand() -> void:
	hand_n += 1
	dealer = next_seat(dealer, false)
	pot = 0; stake = BOOT; acted = 0; reveal = []; last_rank = ""
	in_hand = []
	var d := shuffled(full_deck())
	for p in players:
		p.hand = []; p.seen = false
		if p.chips >= BOOT:
			p.chips -= BOOT; pot += BOOT
			p.out = false
			in_hand.append(p.seat)
			for k in 3: p.hand.append(d.pop_back())
			sort_hand(p.hand)
		else:
			p.out = true
	turn = _next_in(dealer)
	phase = "deal"; wait = 1.2
	emit(["deal", dealer, hand_n, pot])


func _next_in(from: int) -> int:
	for k in range(1, n + 1):
		var s := (from + k) % n
		if s in in_hand: return s
	return from


func _hand_visible(p: Player) -> bool:
	return p.seen or p.seat in reveal


func actor() -> int:
	return turn if phase == "bet" else -1


func price(seat: int, kind: String) -> int:
	var p: Player = players[seat]
	var base := stake * (2 if p.seen else 1)
	match kind:
		"chaal", "show": return base
		"raise": return base * 2
	return 0


## What this player may do now.
func options(seat: int) -> Array:
	if phase != "bet" or seat != turn: return []
	var p: Player = players[seat]
	var o := ["pack"]
	if not p.seen: o.append("see")
	if p.chips >= price(seat, "chaal"): o.append("chaal")
	if stake < MAX_STAKE and p.chips >= price(seat, "raise"): o.append("raise")
	if in_hand.size() == 2 and acted >= 2 and p.chips >= price(seat, "show"): o.append("show")
	return o


func act(seat: int, a: Dictionary) -> bool:
	var kind := String(a.get("a", ""))
	if not (kind in options(seat)): return false
	var p: Player = players[seat]
	idle = 0.0; steps += 1
	match kind:
		"see":
			p.seen = true
			emit(["see", seat])
			return true   # still their turn
		"pack":
			in_hand.erase(seat)
			emit(["pack", seat])
		"chaal", "raise", "show":
			if kind == "raise": stake = mini(stake * 2, MAX_STAKE)
			var cost := price(seat, "chaal") if kind != "raise" else stake * (2 if p.seen else 1)
			p.chips -= cost; pot += cost; acted += 1
			emit(["bet", seat, kind, cost, pot])
			if kind == "show":
				_show(in_hand.duplicate(), seat)
				return true
	if in_hand.size() == 1:
		_award([in_hand[0]], "")
		return true
	if pot >= POT_LIMIT and in_hand.size() >= 2 and acted >= in_hand.size():
		_show(in_hand.duplicate(), -1)
		return true
	turn = _next_in(seat)
	wait = think
	emit(["turn", turn])
	return true


func _show(seats: Array, asker: int) -> void:
	reveal = seats.duplicate()
	var bv: Array = []
	for s in seats:
		var v := hand_value((players[s] as Player).hand)
		if bv.is_empty() or compare(v, bv) > 0: bv = v
	var best: Array = seats.filter(func(s): return compare(hand_value((players[s] as Player).hand), bv) == 0)
	if asker in best and best.size() > 1: best.erase(asker)   # a tie goes against whoever asked for the show
	emit(["show", seats, best])
	_award(best, rank_name(bv))


func _award(winners: Array, rank: String) -> void:
	var share := pot / maxi(1, winners.size())
	for s in winners: (players[s] as Player).chips += share
	last_winner = int(winners[0]); last_rank = rank
	emit(["pot", winners, pot, rank])
	pot = 0
	phase = "hand_end"; wait = 3.0


func _timed(dt: float) -> bool:
	match phase:
		"deal":
			wait -= dt
			if wait <= 0.0: phase = "bet"; wait = think; emit(["turn", turn])
			return true
		"hand_end":
			wait -= dt
			if wait <= 0.0:
				var alive := players.filter(func(p): return p.chips >= BOOT)
				if hand_n >= HANDS or alive.size() <= 1:
					_finish()
				else:
					_new_hand()
			return true
	return false


func _finish() -> void:
	var order := players.duplicate()
	order.sort_custom(func(a, b): return a.chips > b.chips)
	for i in order.size(): (order[i] as Player).place = i + 1
	phase = "done"
	emit(["done", (order[0] as Player).seat])


func _stuck(seat: int) -> void:
	act(seat, {a = "pack"})


# ---------------------------------------------------------------- hand ranking
## A comparable value: [category, ranks high to low...]. 5 trail, 4 pure sequence, 3 sequence, 2 colour, 1 pair, 0 high.
static func hand_value(h: Array) -> Array:
	var r := h.map(func(c): return rank_of(c))
	r.sort(); r.reverse()
	var flush := suit_of(h[0]) == suit_of(h[1]) and suit_of(h[1]) == suit_of(h[2])
	var seq := false
	var top: int = r[0]
	if r[0] - r[1] == 1 and r[1] - r[2] == 1: seq = true
	if r == [12, 1, 0]: seq = true; top = 12   # A-2-3: just under A-K-Q (13), above K-Q-J (11)
	if r[0] == r[1] and r[1] == r[2]: return [5, r[0]]
	if seq and flush: return [4, 13 if r == [12, 11, 10] else top]
	if seq: return [3, 13 if r == [12, 11, 10] else top]
	if flush: return [2, r[0], r[1], r[2]]
	if r[0] == r[1]: return [1, r[0], r[2]]
	if r[1] == r[2]: return [1, r[1], r[0]]
	return [0, r[0], r[1], r[2]]


static func compare(a: Array, b: Array) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]: return 1 if a[i] > b[i] else -1
	return 0


static func rank_name(v: Array) -> String:
	if v.is_empty(): return ""
	return ["HIGH CARD", "PAIR", "COLOUR", "SEQUENCE", "PURE SEQUENCE", "TRAIL"][int(v[0])]


# ---------------------------------------------------------------- CPU
## Strength 0..1 from the hand; blind players bet a couple of rounds before looking; now and then a bluff.
func cpu(seat: int) -> Dictionary:
	var o := options(seat)
	if o.is_empty(): return {}
	var p: Player = players[seat]
	if not p.seen and (acted >= 2 * in_hand.size() or rng.randf() < 0.35) and "see" in o: return {a = "see"}
	var v := hand_value(p.hand)
	var st: float = [0.15, 0.45, 0.6, 0.72, 0.9, 1.0][int(v[0])] + (float(v[1]) / 12.0) * 0.12
	if not p.seen: st = 0.5   # betting blind: no idea
	var bluff := rng.randf() < 0.12
	var cost := price(seat, "chaal")
	var risk := float(cost) / maxf(1.0, p.chips)
	if "show" in o and (st > 0.55 or risk > 0.3): return {a = "show"}
	if st < 0.3 and not bluff and (acted > in_hand.size() or risk > 0.05): return {a = "pack"}
	if "raise" in o and (st > 0.75 or bluff) and rng.randf() < 0.5: return {a = "raise"}
	if "chaal" in o and (st >= 0.3 or bluff or risk < 0.03): return {a = "chaal"}
	if "show" in o: return {a = "show"}
	return {a = "pack"}


func _snap(seat: int) -> Dictionary:
	var rv := {}
	for s in reveal: rv[str(s)] = (players[s] as Player).hand.duplicate()
	return {pot = pot, st = stake, hn = hand_n, ih = in_hand.duplicate(), ac = acted, rv = rv, lw = last_winner, lr = last_rank}


func _unsnap(s: Dictionary) -> void:
	pot = int(s.pot); stake = int(s.st); hand_n = int(s.hn); in_hand = cards_of(s.ih); acted = int(s.ac)
	last_winner = int(s.lw); last_rank = String(s.lr)
	reveal = []
	for k in s.rv:
		var seat := int(k)
		reveal.append(seat)
		(players[seat] as Player).hand = cards_of(s.rv[k])


func result_lines() -> Array:
	var order := players.duplicate()
	order.sort_custom(func(a, b): return a.chips > b.chips)
	return order.map(func(p): return ["%d.  %d CHIPS" % [p.place, p.chips], p.seat])


func winner_seats() -> Array:
	return players.filter(func(p): return p.place == 1).map(func(p): return p.seat)
