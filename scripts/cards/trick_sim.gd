extends "res://scripts/cards/room_sim.gd"
## DEHLA PAKAD and KADI PATTA (Mendikot): trick-taking with two teams sitting alternately (team = seat % 2),
## where what counts is the four 10s (dehlas): a team wins the hand by capturing 3 or 4 of them; at 2–2 the team
## with more tricks wins. All four 10s is a MENDIKOT, worth 2 points. First team to 5 points wins the match.
##
## DEHLA PAKAD (4 players): as in Rung, the player after the dealer gets 5 cards, names the trump, then everyone
##   is dealt up to 13.
## KADI PATTA (4 or 6 players): the trump is hidden — nobody names it. The first time a player can't follow the
##   led suit, the suit of the card they throw becomes the trump (the kadi) for the rest of the hand, starting
##   with that very card. With 6 players the four 2s are taken out: 48 cards, 8 each.
## Every hand is played out to the last trick (no early stop).

const TARGET := 5

var mode := "dehla"
var trump := -1
var chooser := 0
var trick: Array = []
var lead := 0
var last_trick: Array = []
var last_winner := -1
var tricks := [0, 0]
var tens := [0, 0]
var score := [0, 0]
var hand_n := 0
var per_hand := 13
var deck: Array = []
var played: Array = []
var voids: Array = []
var mendikots := 0


func _begin() -> void:
	variant = mode
	_new_hand()


func _new_hand() -> void:
	hand_n += 1
	dealer = (dealer + 1) % n
	chooser = (dealer + 1) % n
	trump = -1
	tricks = [0, 0]; tens = [0, 0]; trick = []; last_trick = []; last_winner = -1
	played = []; voids = []
	for s in n: voids.append([false, false, false, false])
	var cards := full_deck()
	if n == 6: cards = cards.filter(func(c): return rank_of(c) != 0)   # take the 2s out: 48 cards
	per_hand = cards.size() / n
	deck = shuffled(cards)
	for p in players: p.hand = []
	if mode == "dehla":
		for k in 5: (players[chooser] as Player).hand.append(deck.pop_back())
		sort_hand((players[chooser] as Player).hand)
		phase = "deal5"
	else:
		_deal_rest()
		phase = "deal"
	wait = 0.9; turn = chooser; idle = 0.0
	emit(["deal", dealer, chooser, hand_n])


func _deal_rest() -> void:
	for k in n:
		var p: Player = players[(chooser + k) % n]
		while p.hand.size() < per_hand: p.hand.append(deck.pop_back())
		sort_hand(p.hand, trump)


static func team_of(seat: int) -> int: return seat % 2


func actor() -> int:
	if phase == "trump": return chooser
	return turn if phase == "play" else -1


func led_suit() -> int:
	return -1 if trick.is_empty() else suit_of(int(trick[0][1]))


func legal(seat: int) -> Array:
	if phase != "play" or seat != turn: return []
	var p: Player = players[seat]
	var ls := led_suit()
	if ls < 0: return p.hand.duplicate()
	var f := p.hand.filter(func(c): return suit_of(c) == ls)
	return f if not f.is_empty() else p.hand.duplicate()


func act(seat: int, a: Dictionary) -> bool:
	var kind := String(a.get("a", ""))
	if kind == "trump":
		var s := int(a.get("s", -1))
		if phase != "trump" or seat != chooser or s < 0 or s > 3: return false
		trump = s
		emit(["trump", seat, s])
		phase = "deal"; wait = 0.9; idle = 0.0
		return true
	if kind != "play": return false
	var card := int(a.get("c", -1))
	if not (card in legal(seat)): return false
	var p: Player = players[seat]
	var ls := led_suit()
	if ls >= 0 and suit_of(card) != ls:
		voids[seat][ls] = true
		if mode == "kadi" and trump < 0:   # the hidden trump is set by the first player who can't follow
			trump = suit_of(card)
			emit(["kadi", seat, trump])
			for q in players: sort_hand(q.hand, trump)
	p.hand.erase(card)
	if trick.is_empty(): lead = seat
	trick.append([seat, card])
	played.append(card)
	idle = 0.0; steps += 1
	emit(["play", seat, card])
	if trick.size() == n:
		var w := winner_of(trick, trump)
		last_trick = trick.duplicate(true); last_winner = w
		var tm := team_of(w)
		tricks[tm] += 1
		var got := 0
		for e in trick: if rank_of(int(e[1])) == 8: got += 1   # 10s are rank 8
		tens[tm] += got
		emit(["trick", w, got])
		phase = "trick_end"; wait = 1.1; turn = w
	else:
		turn = (seat + 1) % n
		emit(["turn", turn])
	return true


static func winner_of(t: Array, trump_suit: int) -> int:
	var best: Array = t[0]
	for e in t:
		if beats(int(e[1]), int(best[1]), suit_of(int(t[0][1])), trump_suit): best = e
	return int(best[0])


static func beats(a: int, b: int, led: int, trump_suit: int) -> bool:
	var sa := suit_of(a); var sb := suit_of(b)
	if sa == sb: return rank_of(a) > rank_of(b)
	if sa == trump_suit: return true
	if sb == trump_suit: return false
	return sa == led and sb != led


## Who wins the hand on the 10s (and tricks at 2–2).
static func hand_winner(tn: Array, tk: Array) -> int:
	if tn[0] >= 3: return 0
	if tn[1] >= 3: return 1
	return 0 if tk[0] > tk[1] else 1


func _timed(dt: float) -> bool:
	match phase:
		"deal5":
			wait -= dt
			if wait <= 0.0: phase = "trump"; wait = think; idle = 0.0; emit(["choose", chooser])
			return true
		"deal":
			wait -= dt
			if wait <= 0.0:
				if mode == "dehla": _deal_rest()
				phase = "play"; turn = chooser; lead = chooser; wait = think; idle = 0.0
				emit(["turn", turn])
			return true
		"trick_end":
			wait -= dt
			if wait <= 0.0: _after_trick()
			return true
		"hand_end":
			wait -= dt
			if wait <= 0.0:
				if score[0] >= TARGET or score[1] >= TARGET:
					phase = "done"; emit(["done", 0 if score[0] >= TARGET else 1])
				else:
					_new_hand()
			return true
	return false


func _after_trick() -> void:
	trick = []
	if tricks[0] + tricks[1] < per_hand:
		phase = "play"; turn = last_winner; lead = turn; wait = think
		emit(["turn", turn])
		return
	var w := hand_winner(tens, tricks)
	var mendi: bool = tens[w] == 4
	score[w] += 2 if mendi else 1
	if mendi: mendikots += 1
	emit(["hand", w, 2 if mendi else 1, mendi, score[0], score[1]])
	phase = "hand_end"; wait = 2.6


# ---------------------------------------------------------------- CPU
func cpu(seat: int) -> Dictionary:
	if phase == "trump": return {a = "trump", s = best_trump(seat)}
	return {a = "play", c = best_card(seat)}


func best_trump(seat: int) -> int:
	var p: Player = players[seat]
	var best := 0
	var bs := -1.0
	for s in 4:
		var v := 0.0
		for c in p.hand:
			if suit_of(c) == s: v += 10.0 + maxf(0.0, rank_of(c) - 7) * 1.5
		if v > bs: bs = v; best = s
	return best


func _master(seat: int, card: int) -> bool:
	var s := suit_of(card)
	var mine: Array = (players[seat] as Player).hand
	for r in range(rank_of(card) + 1, 13):
		var c := s * 13 + r
		if n == 6 and r == 0: continue
		if not (c in played) and not (c in mine): return false
	return true


## Like Rung's CPU, with a taste for 10s: cash a 10 when it's safe, feed one to a partner who's winning,
## never throw one on a trick the other team will take if it can be helped.
func best_card(seat: int) -> int:
	var opts := legal(seat)
	if opts.is_empty(): return -1
	if opts.size() == 1: return opts[0]
	var p: Player = players[seat]
	var is_ten := func(c: int) -> bool: return rank_of(c) == 8
	var low := func(cards: Array) -> int:
		var b: int = cards[0]
		for c in cards:
			var bt: bool = suit_of(b) == trump; var ct: bool = suit_of(c) == trump
			var bten: bool = is_ten.call(b); var cten: bool = is_ten.call(c)
			# lowest; never a 10 or a trump unless there's nothing else
			if (bten and not cten) or (bt and not ct and not cten) or (bten == cten and bt == ct and rank_of(c) < rank_of(b)): b = c
		return b
	var high := func(cards: Array) -> int:
		var b: int = cards[0]
		for c in cards: if rank_of(c) > rank_of(b): b = c
		return b
	if trick.is_empty():
		var masters := p.hand.filter(func(c): return suit_of(c) != trump and _master(seat, c))
		if not masters.is_empty(): return high.call(masters)
		var side := p.hand.filter(func(c): return suit_of(c) != trump and not is_ten.call(c))
		if side.is_empty(): return low.call(p.hand)
		return low.call(side)
	var ls := led_suit()
	var w := winner_of(trick, trump)
	var wc := -1
	for e in trick: if int(e[0]) == w: wc = int(e[1])
	var partner_winning := team_of(w) == team_of(seat)
	var last := trick.size() == n - 1
	var winners := opts.filter(func(c): return beats(c, wc, ls, trump))
	var tens_here := opts.filter(func(c): return is_ten.call(c))
	if partner_winning and (last or _master(seat, wc) or (trump >= 0 and suit_of(wc) == trump and ls != trump)):
		if not tens_here.is_empty(): return tens_here[0]     # feed the partner a 10
		return low.call(opts)
	if winners.is_empty(): return low.call(opts)
	if not last:
		var safe := winners.filter(func(c): return suit_of(c) == ls and _master(seat, c))
		if not safe.is_empty(): return high.call(safe)
	var cheapest: int = winners[0]
	for c in winners:
		var ct: bool = suit_of(c) == trump; var bt: bool = suit_of(cheapest) == trump
		if (bt and not ct) or (bt == ct and rank_of(c) < rank_of(cheapest)): cheapest = c
	# taking a trick with a 10 in it: worth winning even with a trump
	return cheapest


func _snap(_seat: int) -> Dictionary:
	var tr := []
	for e in trick: tr.append([int(e[0]), int(e[1])])
	var lt := []
	for e in last_trick: lt.append([int(e[0]), int(e[1])])
	return {md = mode, tp = trump, ch = chooser, tr = tr, ld = lead, lt = lt, lw = last_winner, tk = tricks.duplicate(), tn = tens.duplicate(),
		sc = score.duplicate(), hn = hand_n, phd = per_hand}


func _unsnap(s: Dictionary) -> void:
	mode = String(s.md); trump = int(s.tp); chooser = int(s.ch); lead = int(s.ld); last_winner = int(s.lw)
	trick = []
	for e in s.tr: trick.append([int(e[0]), int(e[1])])
	last_trick = []
	for e in s.lt: last_trick.append([int(e[0]), int(e[1])])
	tricks = [int(s.tk[0]), int(s.tk[1])]; tens = [int(s.tn[0]), int(s.tn[1])]; score = [int(s.sc[0]), int(s.sc[1])]
	hand_n = int(s.hn); per_hand = int(s.phd)


func result_lines() -> Array:
	return []


func winner_seats() -> Array:
	var w := 0 if score[0] >= score[1] else 1
	return players.filter(func(p): return team_of(p.seat) == w).map(func(p): return p.seat)
