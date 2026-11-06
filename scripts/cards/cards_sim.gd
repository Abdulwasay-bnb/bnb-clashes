extends RefCounted
## BNB Rung (Court Piece): the rules, no visuals. Runs on the host (or locally); guests mirror a filtered copy.
##
## Cards are ints: suit * 13 + rank, rank 0..12 = 2..A (ace high). Suits: 0 spades, 1 hearts, 2 diamonds, 3 clubs.
## Seats 0..3 round the table in play order; seats 0 & 2 are team 0, seats 1 & 3 team 1.
##
## A hand: the player after the dealer is dealt 5 cards and names the trump suit (the "rung") from them; then
## everyone is dealt up to 13. That player leads. Follow the led suit if you can, otherwise play anything.
## Highest trump wins the trick, else the highest card of the led suit; the winner leads next.
## A team that takes 7 tricks wins the hand (1 point). Simplification of the kot rule: if one team takes the first
## 7 tricks in a row the hand plays on; taking all 13 is a KOT, worth 2 points (losing any trick after that ends
## the hand at 1 point). The dealer moves one seat round each hand. First team to 5 points wins the match.

const SUITS := ["♠", "♥", "♦", "♣"]
const SUIT_NAMES := ["SPADES", "HEARTS", "DIAMONDS", "CLUBS"]
const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const TARGET := 5                  # hand points to win the match
const TURN_TIME := 25.0            # online: an idle player's card is played for them

class Player:
	var seat := 0
	var C: Dictionary
	var human := false
	var slot := -1                 # online lobby seat (0 = host); pass & play: -2; CPU: -1
	var hand: Array = []           # card ints (a guest only knows its own; others are -1 placeholders)

var players: Array = []
var dealer := 3
var chooser := 0                   # names the trump this hand
var trump := -1
var phase := "deal5"               # deal5 / trump / deal / play / trick_end / hand_end / done
var turn := 0                      # seat to act
var lead := 0                      # seat that led this trick
var trick: Array = []              # [[seat, card], ...] in play order
var last_trick: Array = []
var last_winner := -1
var tricks := [0, 0]               # this hand, per team
var trick_seq: Array = []          # winning team of each trick this hand
var score := [0, 0]                # hand points
var hand_n := 0
var kots := 0
var wait := 0.0
var idle := 0.0
var events: Array = []             # new since the last read: [kind, ...]
var rng := RandomNumberGenerator.new()
var rev := 0
var deck: Array = []
var played: Array = []             # every card played this hand (CPU memory)
var voids: Array = []              # [seat][suit] -> shown void this hand
var illegal := 0                   # rejected plays (tests)
var think := 0.6                   # CPU thinking time (tests set it to 0)


static func suit_of(c: int) -> int: return c / 13
static func rank_of(c: int) -> int: return c % 13
static func team_of(seat: int) -> int: return seat % 2
static func is_red(c: int) -> bool: return suit_of(c) in [1, 2]
static func label(c: int) -> String: return RANKS[rank_of(c)] + SUITS[suit_of(c)]


## people: [{C, human, slot}] in seat order (always 4).
func setup(people: Array, seed := 1) -> void:
	rng.seed = seed
	for k in 4:
		var p := Player.new()
		var src: Dictionary = people[k % people.size()]
		p.seat = k; p.C = src.C; p.human = bool(src.get("human", false)); p.slot = int(src.get("slot", -1))
		players.append(p)
	dealer = rng.randi() % 4
	_new_hand()


func _new_hand() -> void:
	hand_n += 1
	dealer = (dealer + 1) % 4
	chooser = (dealer + 1) % 4
	trump = -1
	tricks = [0, 0]; trick_seq = []; trick = []; last_trick = []; last_winner = -1
	played = []
	voids = []
	for s in 4: voids.append([false, false, false, false])
	deck = []
	for c in 52: deck.append(c)
	# Fisher-Yates with our own rng, so a seed always deals the same cards
	for i in range(51, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = deck[i]; deck[i] = deck[j]; deck[j] = t
	for p in players: p.hand = []
	for k in 5: (players[chooser] as Player).hand.append(deck.pop_back())
	_sort(players[chooser])
	phase = "deal5"; wait = 0.9; turn = chooser; idle = 0.0
	events.append(["deal", dealer, chooser, hand_n])
	rev += 1


func _sort(p: Player) -> void:
	# by suit (trump first once known), then rank high to low
	var t := trump
	p.hand.sort_custom(func(a, b):
		var sa: int = suit_of(a); var sb: int = suit_of(b)
		var ka: int = -1 if sa == t else sa
		var kb: int = -1 if sb == t else sb
		if ka != kb: return ka < kb
		return rank_of(a) > rank_of(b))


func _deal_rest() -> void:
	for k in 4:
		var s := (chooser + k) % 4
		var p: Player = players[s]
		while p.hand.size() < 13: p.hand.append(deck.pop_back())
		_sort(p)
	phase = "play"; turn = chooser; lead = chooser; idle = 0.0
	events.append(["turn", turn])
	rev += 1


func cur() -> Player:
	return players[turn]


## The trump suit, named by the chooser (from their first 5 cards).
func choose_trump(seat: int, suit: int) -> bool:
	if phase != "trump" or seat != chooser or suit < 0 or suit > 3:
		illegal += 1; return false
	trump = suit
	events.append(["trump", seat, suit])
	phase = "deal"; wait = 0.9; idle = 0.0
	rev += 1
	return true


func led_suit() -> int:
	return -1 if trick.is_empty() else suit_of(int(trick[0][1]))


func legal(seat: int) -> Array:
	var p: Player = players[seat]
	if phase != "play" or seat != turn: return []
	var ls := led_suit()
	if ls < 0: return p.hand.duplicate()
	var follow := p.hand.filter(func(c): return suit_of(c) == ls)
	return follow if not follow.is_empty() else p.hand.duplicate()


func play(seat: int, card: int) -> bool:
	if not (card in legal(seat)):
		illegal += 1; return false
	var p: Player = players[seat]
	var ls := led_suit()
	if ls >= 0 and suit_of(card) != ls: voids[seat][ls] = true
	p.hand.erase(card)
	if trick.is_empty(): lead = seat
	trick.append([seat, card])
	played.append(card)
	events.append(["play", seat, card])
	idle = 0.0
	if trick.size() == 4:
		var w := winner_of(trick, trump)
		last_trick = trick.duplicate(true); last_winner = w
		var tm := team_of(w)
		tricks[tm] += 1
		trick_seq.append(tm)
		events.append(["trick", w, tricks[0], tricks[1]])
		phase = "trick_end"; wait = 1.1; turn = w
	else:
		turn = (seat + 1) % 4
		events.append(["turn", turn])
	rev += 1
	return true


## Who takes a trick: the highest trump played, else the highest card of the suit that was led.
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


func _after_trick() -> void:
	trick = []
	var a: int = tricks[0]; var b: int = tricks[1]
	var win := -1
	var pts := 1
	var kot := false
	if a >= 7 or b >= 7:
		var t := 0 if a >= 7 else 1
		var o := 1 - t
		if tricks[o] > 0: win = t                                   # ordinary hand
		elif tricks[t] == 13: win = t; pts = 2; kot = true          # all thirteen: kot
		# else: one team took every trick so far, play on for the kot
	elif a + b == 13:
		win = 0 if a > b else 1
	if win >= 0:
		score[win] += pts
		if kot: kots += 1
		events.append(["hand", win, pts, kot, score[0], score[1]])
		phase = "hand_end"; wait = 2.6
	else:
		phase = "play"; turn = last_winner; lead = turn
		events.append(["turn", turn])
	rev += 1


## Time passes: deals, trick pauses, CPU players think, idle online players get played for.
func update(dt: float) -> void:
	if phase == "done": return
	match phase:
		"deal5":
			wait -= dt
			if wait <= 0.0:
				phase = "trump"; idle = 0.0; wait = think
				events.append(["choose", chooser]); rev += 1
			return
		"deal":
			wait -= dt
			if wait <= 0.0: _deal_rest()
			return
		"trick_end":
			wait -= dt
			if wait <= 0.0: _after_trick()
			return
		"hand_end":
			wait -= dt
			if wait <= 0.0:
				if score[0] >= TARGET or score[1] >= TARGET:
					phase = "done"
					events.append(["done", 0 if score[0] >= TARGET else 1]); rev += 1
				else:
					_new_hand()
			return
	var p := cur() if phase == "play" else (players[chooser] as Player)
	if not p.human:
		wait -= dt
		if wait > 0.0: return
		wait = think
		if phase == "trump": choose_trump(chooser, best_trump(chooser))
		elif phase == "play": play(turn, best_card(turn))
		return
	idle += dt
	if idle > TURN_TIME and p.slot >= 0:
		if phase == "trump": choose_trump(chooser, best_trump(chooser))
		elif phase == "play": play(turn, best_card(turn))


# ---------------------------------------------------------------- CPU
## Trump from the first five: the suit with the most cards, strength breaking ties.
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


## Is this card the highest of its suit still out (not played, not in our hand)?
func _master(seat: int, card: int) -> bool:
	var s := suit_of(card)
	var mine: Array = (players[seat] as Player).hand
	for r in range(rank_of(card) + 1, 13):
		var c := s * 13 + r
		if not (c in played) and not (c in mine): return false
	return true


func _out_of(suit: int, seat: int) -> int:
	# how many cards of a suit are still out with the other players
	var n := 0
	var mine: Array = (players[seat] as Player).hand
	for r in 13:
		var c := suit * 13 + r
		if not (c in played) and not (c in mine): n += 1
	return n


func best_card(seat: int) -> int:
	var opts := legal(seat)
	if opts.is_empty(): return -1
	if opts.size() == 1: return opts[0]
	var p: Player = players[seat]
	var low := func(cards: Array) -> int:
		var b: int = cards[0]
		for c in cards:
			# lowest rank; a trump only if there's nothing else
			var bt: bool = suit_of(b) == trump; var ct: bool = suit_of(c) == trump
			if (bt and not ct) or (bt == ct and rank_of(c) < rank_of(b)): b = c
		return b
	var high := func(cards: Array) -> int:
		var b: int = cards[0]
		for c in cards:
			if rank_of(c) > rank_of(b): b = c
		return b
	if trick.is_empty():
		# leading: draw trumps when strong, cash masters in side suits, else lead low from the longest side suit
		var trumps := p.hand.filter(func(c): return suit_of(c) == trump)
		if trumps.size() >= 4 and _out_of(trump, seat) > 0 and _master(seat, high.call(trumps)): return high.call(trumps)
		var masters := p.hand.filter(func(c): return suit_of(c) != trump and _master(seat, c) and not _partner_or_me_only(seat, suit_of(c)))
		if not masters.is_empty(): return high.call(masters)
		var side := p.hand.filter(func(c): return suit_of(c) != trump)
		if side.is_empty(): return low.call(p.hand)
		var count := [0, 0, 0, 0]
		for c in side: count[suit_of(c)] += 1
		var longest := 0
		for s in 4: if count[s] > count[longest]: longest = s
		return low.call(side.filter(func(c): return suit_of(c) == longest))
	var ls := led_suit()
	var w := winner_of(trick, trump)
	var wc := -1
	for e in trick: if int(e[0]) == w: wc = int(e[1])
	var partner_winning := team_of(w) == team_of(seat)
	var last := trick.size() == 3
	var winners := opts.filter(func(c): return beats(c, wc, ls, trump))
	if partner_winning and (last or _master(seat, wc) or suit_of(wc) == trump and suit_of(wc) != ls):
		return low.call(opts)
	if winners.is_empty(): return low.call(opts)
	# win as cheaply as we can; when not last, a master of the led suit is safe to cash
	if not last:
		var safe := winners.filter(func(c): return suit_of(c) == ls and _master(seat, c))
		if not safe.is_empty(): return high.call(safe)
	var cheapest: int = winners[0]
	for c in winners:
		var ct: bool = suit_of(c) == trump; var bt: bool = suit_of(cheapest) == trump
		if (bt and not ct) or (bt == ct and rank_of(c) < rank_of(cheapest)): cheapest = c
	return cheapest


func _partner_or_me_only(seat: int, suit: int) -> bool:
	# an opponent is known to be void here and still holds trumps: leading the suit just gets it ruffed
	if trump < 0: return false
	for o in [(seat + 1) % 4, (seat + 3) % 4]:
		if voids[o][suit] and not voids[o][trump]: return true
	return false


# ---------------------------------------------------------------- multiplayer
## What one seat may see: their own hand, everyone's card counts, the table. seat -1 = spectator (no hands).
func snapshot_for(seat: int) -> Dictionary:
	var hands := []
	for p in players:
		hands.append(p.hand.duplicate() if p.seat == seat else p.hand.size())
	var tr := []
	for e in trick: tr.append([int(e[0]), int(e[1])])
	var lt := []
	for e in last_trick: lt.append([int(e[0]), int(e[1])])
	return {h = hands, d = dealer, ch = chooser, tp = trump, ph = phase, tu = turn, ld = lead, tr = tr, lt = lt, lw = last_winner,
		tk = tricks.duplicate(), sc = score.duplicate(), hn = hand_n, rev = rev, idle = snappedf(idle, 0.1), w = snappedf(wait, 0.05)}


func apply(s: Dictionary) -> void:
	var hs: Array = s.h
	for k in 4:
		var p: Player = players[k]
		var h = hs[k]
		if h is Array:
			p.hand = []
			for c in h: p.hand.append(int(c))
		else:
			p.hand = []
			for i in int(h): p.hand.append(-1)
	dealer = int(s.d); chooser = int(s.ch); trump = int(s.tp); phase = String(s.ph); turn = int(s.tu); lead = int(s.ld)
	trick = []
	for e in s.tr: trick.append([int(e[0]), int(e[1])])
	last_trick = []
	for e in s.lt: last_trick.append([int(e[0]), int(e[1])])
	last_winner = int(s.lw)
	tricks = [int(s.tk[0]), int(s.tk[1])]; score = [int(s.sc[0]), int(s.sc[1])]
	hand_n = int(s.hn); rev = int(s.rev); idle = float(s.get("idle", 0.0)); wait = float(s.get("w", 0.0))
