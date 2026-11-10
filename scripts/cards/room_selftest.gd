extends RefCounted
## --autotest=cardssim, the card room part: each game's key rules, many CPU games per player count,
## determinism by seed, and hidden-information snapshots.

const SIMS := {
	"thulla": preload("res://scripts/cards/thulla_sim.gd"), "satte": preload("res://scripts/cards/satte_sim.gd"),
	"dehla": preload("res://scripts/cards/trick_sim.gd"), "kadi": preload("res://scripts/cards/trick_sim.gd"),
	"teenpatti": preload("res://scripts/cards/teenpatti_sim.gd"), "seep": preload("res://scripts/cards/seep_sim.gd"),
}
const COUNTS := {"thulla": [3, 4, 6], "satte": [3, 5, 8], "dehla": [4], "kadi": [4, 6], "teenpatti": [3, 4, 6], "seep": [2, 4]}


static func make(v: String, np: int, seed: int):
	var s = SIMS[v].new()
	if v in ["dehla", "kadi"]: s.mode = v
	s.think = 0.0
	var people := []
	for k in np: people.append({C = Data.ROSTER[k % Data.ROSTER.size()], human = false, slot = -1})
	s.setup(people, seed)
	return s


static func play_out(s, cap := 300000) -> Array:
	var log := []
	var it := 0
	while s.phase != "done" and it < cap:
		s.update(3.0)
		for e in s.events:
			if e[0] in ["play", "bet", "bid", "capture", "build", "cement", "throw", "pass"]: log.append(str(e))
		s.events.clear(); it += 1
	return log


static func C(suit: int, rank: int) -> int: return suit * 13 + rank


static func run() -> Array:
	var fails := []
	_rules(fails)
	for v in COUNTS:
		for np in COUNTS[v]:
			var games := 40 if v != "teenpatti" else 60
			var ill := 0; var stuck := 0; var steps := 0
			for g in games:
				var s = make(v, np, 7000 + g)
				play_out(s)
				if s.phase != "done": stuck += 1
				ill += s.illegal; steps += s.steps
			# determinism
			var a := play_out(make(v, np, 99)); var b := play_out(make(v, np, 99))
			var det := a == b
			# hidden info: a guest only gets its own cards; they survive the wire
			var h = make(v, np, 5)
			var guard := 0
			while h.actor() < 0 and h.phase != "done" and guard < 100: h.update(3.0); guard += 1
			if v == "teenpatti": h.players[1].seen = true
			var sn: Dictionary = h.snapshot_for(1)
			var leak := false
			for k in np:
				var hv = sn.p[k][0]
				if k != 1 and hv is Array and not (hv as Array).is_empty(): leak = true
			var wire: Dictionary = JSON.parse_string(JSON.stringify(sn))
			var gst = make(v, np, 1)
			gst.apply(wire)
			var own_ok: bool = gst.players[1].hand == h.players[1].hand
			var others_hidden: bool = gst.players[0].hand.all(func(c): return c < 0)
			if v == "teenpatti" and not (0 in h.reveal): others_hidden = others_hidden
			if ill > 0: fails.append("%s %dp: %d illegal CPU moves" % [v, np, ill])
			if stuck > 0: fails.append("%s %dp: %d games stuck" % [v, np, stuck])
			if not det: fails.append("%s %dp not deterministic" % [v, np])
			if leak or not others_hidden: fails.append("%s %dp snapshot leaks another hand" % [v, np])
			if not own_ok: fails.append("%s %dp own hand lost on the wire" % [v, np])
			print("AUTOTEST cardssim %s %dp games=%d illegal=%d stuck=%d avg_moves=%d deterministic=%s hidden_ok=%s" % [v, np, games, ill, stuck, steps / games, det, not leak and others_hidden and own_ok])
	return fails


static func _rules(fails: Array) -> void:
	# ---- Thulla: follow suit; a thulla makes the highest card of the led suit pick the trick up
	var t = make("thulla", 4, 3)
	t.phase = "play"; t.first = false
	t.players[0].hand = [C(0, 3), C(1, 4)]
	t.players[1].hand = [C(0, 11), C(2, 2)]
	t.players[2].hand = [C(1, 0), C(3, 5)]
	t.players[3].hand = [C(0, 1), C(3, 3)]
	t._start_trick(0)
	t.act(0, {a = "play", c = C(0, 3)})
	if t.act(1, {a = "play", c = C(2, 2)}): fails.append("thulla: revoke accepted")
	t.act(1, {a = "play", c = C(0, 11)})
	if not t.act(2, {a = "play", c = C(1, 0)}): fails.append("thulla: a thulla when void rejected")
	if t.phase != "trick_end" or t.turn != 1 or t.players[1].hand.size() != 4: fails.append("thulla: wrong pickup (turn %d, hand %d)" % [t.turn, t.players[1].hand.size()])
	# ---- Satte: only 7♥ opens; then up / down by one; you may only pass when stuck
	var st = make("satte", 4, 3)
	st.phase = "play"; st.opened = false; st.turn = 0
	st.players[0].hand = [C(1, 5), C(1, 6), C(0, 5)]
	if st.playable(C(0, 5)) or not st.playable(C(1, 5)): fails.append("satte: only the 7♥ may start")
	if st.act(0, {a = "pass"}): fails.append("satte: pass allowed with a legal card")
	st.act(0, {a = "play", c = C(1, 5)})
	if not (st.playable(C(1, 6)) and st.playable(C(1, 4)) and st.playable(C(0, 5))) or st.playable(C(1, 7)): fails.append("satte: row building wrong")
	# ---- Dehla / Kadi: the 10s decide; 2–2 goes to tricks; the hidden kadi is set by the first void
	var TS = SIMS.dehla
	if TS.hand_winner([3, 1], [5, 8]) != 0 or TS.hand_winner([2, 2], [8, 5]) != 0 or TS.hand_winner([2, 2], [5, 8]) != 1 or TS.hand_winner([0, 4], [9, 4]) != 1:
		fails.append("dehla: hand winner by 10s wrong")
	var k = make("kadi", 4, 3)
	k.phase = "play"; k.trump = -1; k.turn = 1; k.trick = [[0, C(0, 5)]]
	k.players[1].hand = [C(1, 2), C(3, 9)]
	k.act(1, {a = "play", c = C(1, 2)})
	if k.trump != 1: fails.append("kadi: hidden trump not set by the first void")
	if TS.winner_of([[0, C(0, 12)], [1, C(1, 0)]], 1) != 1: fails.append("kadi: trump should beat the led ace")
	# ---- Teen Patti ranking
	var TP = SIMS.teenpatti
	var v := func(cards: Array) -> Array: return TP.hand_value(cards)
	var trail: Array = v.call([C(0, 0), C(1, 0), C(2, 0)])
	var pure: Array = v.call([C(1, 12), C(1, 11), C(1, 10)])
	var seq_akq: Array = v.call([C(0, 12), C(1, 11), C(2, 10)])
	var seq_a23: Array = v.call([C(0, 12), C(1, 0), C(2, 1)])
	var seq_kqj: Array = v.call([C(0, 11), C(1, 10), C(2, 9)])
	var colour: Array = v.call([C(3, 12), C(3, 7), C(3, 2)])
	var pair: Array = v.call([C(0, 12), C(1, 12), C(2, 3)])
	var high: Array = v.call([C(0, 12), C(1, 10), C(2, 3)])
	var order := [trail, pure, seq_akq, seq_a23, seq_kqj, colour, pair, high]
	for i in order.size() - 1:
		if TP.compare(order[i], order[i + 1]) <= 0: fails.append("teen patti: ranking %d should beat %d" % [i, i + 1])
	if TP.compare(v.call([C(0, 5), C(1, 5), C(2, 12)]), v.call([C(0, 5), C(3, 5), C(2, 11)])) <= 0: fails.append("teen patti: pair kicker")
	# ---- Seep: values, points, capture by sums, the seep bonus
	var SP = SIMS.seep
	var total := 0
	for c in 52: total += SP.points(c)
	if total != 100: fails.append("seep: deck points %d, not 100" % total)
	var got: Array = SP.capture_set([C(3, 1), C(1, 3), C(2, 6)], 8)   # 3 + 5, and the 8
	if got.size() != 3: fails.append("seep: capture by sums took %d cards" % got.size())
	var sp = make("seep", 2, 3)
	sp.phase = "play"; sp.turn = 0; sp.bid_pending = false
	sp.table = [C(1, 3)]; sp.houses = []
	sp.players[0].hand = [C(0, 3), C(3, 11)]; sp.players[1].hand = [C(1, 9)]
	sp.deck = [C(2, 2)]
	var mv: Array = sp.moves(0).filter(func(m): return String(m.k) == "capture" and int(m.c) == C(0, 3))
	if mv.is_empty() or not sp.act(0, {a = "move", m = mv[0]}) or sp.seeps[0] != 1 or sp.deal_pts[0] != 50: fails.append("seep: seep bonus missing")
	sp.table = [C(2, 7)]; sp.turn = 0; sp.players[0].hand = [C(3, 2), C(0, 11)]   # 4 + 9 = 13 with a K in hand
	var bld: Array = sp.moves(0).filter(func(m): return String(m.k) == "build" and int(m.h) == 13)
	if bld.is_empty(): fails.append("seep: house of 13 not offered")
