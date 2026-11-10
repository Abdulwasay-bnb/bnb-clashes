extends "res://scripts/cards/room_sim.gd"
## THULLA (Bhabhi / Getaway), 3–6 players. All 52 cards are dealt. Whoever holds the A♠ leads it.
## Everyone must follow the led suit; if all follow, the trick is thrown away and the highest card leads next.
## A player who can't follow plays any card: THULLA! The trick stops at once and the player with the highest
## card of the led suit picks up every card of that trick and leads next. Empty your hand to escape; the last
## player still holding cards is the BHABHI.
## Simplifications: no special first-round rule; a player who plays their last card escapes when the trick ends
## (unless they're the one picking up). If a game somehow runs past 600 tricks, whoever holds most cards loses.

var trick: Array = []              # [[seat, card], ...]
var trick_players: Array = []      # seats still to play this trick, in order
var leader := 0
var last_trick: Array = []
var last_pickup := -1              # seat that picked up the last trick (-1 = it was thrown away)
var bhabhi := -1
var tricks_n := 0
var first := true                  # the A♠ must start


func _begin() -> void:
	variant = "thulla"
	var d := shuffled(full_deck())
	var k := 0
	for c in d:
		(players[k % n] as Player).hand.append(c)
		k += 1
	for p in players: sort_hand(p.hand)
	for p in players:
		if 12 in p.hand: leader = p.seat
	turn = leader
	_start_trick(leader)
	phase = "deal"; wait = 1.0
	emit(["deal", leader])


func _start_trick(lead: int) -> void:
	trick = []
	trick_players = []
	var s := lead
	for k in n:
		var p: Player = players[s]
		if not p.out: trick_players.append(s)
		s = (s + 1) % n
	turn = lead


func actor() -> int:
	return turn if phase == "play" else -1


func led_suit() -> int:
	return -1 if trick.is_empty() else suit_of(int(trick[0][1]))


func legal(seat: int) -> Array:
	if phase != "play" or seat != turn: return []
	var p: Player = players[seat]
	if trick.is_empty():
		if first and 12 in p.hand: return [12]
		return p.hand.duplicate()
	var ls := led_suit()
	var f := p.hand.filter(func(c): return suit_of(c) == ls)
	return f if not f.is_empty() else p.hand.duplicate()


func act(seat: int, a: Dictionary) -> bool:
	if String(a.get("a", "")) != "play": return false
	var card := int(a.get("c", -1))
	if not (card in legal(seat)): return false
	var p: Player = players[seat]
	var ls := led_suit()
	p.hand.erase(card)
	trick.append([seat, card])
	trick_players.erase(seat)
	first = false
	idle = 0.0; steps += 1
	emit(["play", seat, card])
	if ls >= 0 and suit_of(card) != ls:
		# THULLA: the highest card of the led suit picks the whole trick up
		var hi := _highest_of(ls)
		last_trick = trick.duplicate(true); last_pickup = hi
		for e in trick: (players[hi] as Player).hand.append(int(e[1]))
		sort_hand((players[hi] as Player).hand)
		emit(["thulla", seat, hi, trick.size()])
		phase = "trick_end"; wait = 1.6; turn = hi
		return true
	if trick_players.is_empty():
		var hi := _highest_of(suit_of(int(trick[0][1])))
		last_trick = trick.duplicate(true); last_pickup = -1
		emit(["clear", hi])
		phase = "trick_end"; wait = 1.0; turn = hi
		return true
	turn = int(trick_players[0])
	emit(["turn", turn])
	return true


func _highest_of(suit: int) -> int:
	var best := -1
	var br := -1
	for e in trick:
		var c := int(e[1])
		if suit_of(c) == suit and rank_of(c) > br: br = rank_of(c); best = int(e[0])
	return best


func _timed(dt: float) -> bool:
	match phase:
		"deal":
			wait -= dt
			if wait <= 0.0: phase = "play"; wait = think; emit(["turn", turn])
			return true
		"trick_end":
			wait -= dt
			if wait <= 0.0: _after_trick()
			return true
	return false


func _after_trick() -> void:
	tricks_n += 1
	var next := turn
	trick = []
	# escapes: everyone with an empty hand (the one who just picked up never has one)
	var placed := 0
	for p in players: if p.out: placed += 1
	for p in players:
		if not p.out and p.hand.is_empty():
			p.out = true; placed += 1; p.place = placed
			emit(["escape", p.seat, p.place])
	var left := players.filter(func(p): return not p.out)
	if left.size() <= 1 or tricks_n > 600:
		if left.size() == 1: bhabhi = (left[0] as Player).seat
		elif not left.is_empty():
			var most: Player = left[0]
			for p in left: if p.hand.size() > most.hand.size(): most = p
			bhabhi = most.seat
		for p in players:
			if not p.out: p.out = true; placed += 1; p.place = placed
		phase = "done"
		emit(["done", bhabhi])
		return
	if (players[next] as Player).out: next = next_seat(next)
	_start_trick(next)
	phase = "play"; wait = think; idle = 0.0
	emit(["turn", turn])


# ---------------------------------------------------------------- CPU
func cpu(seat: int) -> Dictionary:
	var opts := legal(seat)
	if opts.is_empty(): return {}
	var p: Player = players[seat]
	if opts.size() == 1: return {a = "play", c = opts[0]}
	if trick.is_empty():
		# lead the lowest card of the suit we hold most of (others are likelier to follow, so it's thrown away)
		var count := [0, 0, 0, 0]
		for c in p.hand: count[suit_of(c)] += 1
		var best: int = opts[0]
		for c in opts:
			var better: bool = count[suit_of(c)] > count[suit_of(best)] or (count[suit_of(c)] == count[suit_of(best)] and rank_of(c) < rank_of(best))
			if better: best = c
		return {a = "play", c = best}
	var ls := led_suit()
	if suit_of(int(opts[0])) == ls:
		# following: play the highest card that stays under the current top, so a thulla won't land on us
		var top := -1
		for e in trick:
			if suit_of(int(e[1])) == ls: top = maxi(top, rank_of(int(e[1])))
		var under := opts.filter(func(c): return rank_of(c) < top)
		var pick: int = opts[0]
		if not under.is_empty():
			for c in under: if rank_of(c) > rank_of(pick) or rank_of(pick) >= top: pick = c
		else:
			for c in opts: if rank_of(c) < rank_of(pick): pick = c
		return {a = "play", c = pick}
	# THULLA: dump our most dangerous card (the highest one)
	var hi: int = opts[0]
	for c in opts: if rank_of(c) > rank_of(hi): hi = c
	return {a = "play", c = hi}


# ---------------------------------------------------------------- multiplayer
func _snap(_seat: int) -> Dictionary:
	var tr := []
	for e in trick: tr.append([int(e[0]), int(e[1])])
	var lt := []
	for e in last_trick: lt.append([int(e[0]), int(e[1])])
	return {tr = tr, tp = trick_players.duplicate(), lt = lt, lp = last_pickup, bh = bhabhi, fi = first, tn = tricks_n}


func _unsnap(s: Dictionary) -> void:
	trick = []
	for e in s.tr: trick.append([int(e[0]), int(e[1])])
	trick_players = cards_of(s.tp)
	last_trick = []
	for e in s.lt: last_trick.append([int(e[0]), int(e[1])])
	last_pickup = int(s.lp); bhabhi = int(s.bh); first = bool(s.fi); tricks_n = int(s.tn)


func result_lines() -> Array:
	var order := players.duplicate()
	order.sort_custom(func(a, b): return a.place < b.place)
	var out := []
	for p in order:
		out.append([("BHABHI!" if p.seat == bhabhi else "%d. ESCAPED" % p.place), p.seat])
	return out


func winner_seats() -> Array:
	return players.filter(func(p): return p.seat != bhabhi).map(func(p): return p.seat)
