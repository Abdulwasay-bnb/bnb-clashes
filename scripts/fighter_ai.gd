class_name FighterAI
extends RefCounted
## CPU opponent. Produces the same input a player would (relative stick + button presses).

var G
var lv := 1
var q: Array = []
var wait := 20
var seen := 0
var drift := 0
var block_p: float; var low_p: float; var punish_p: float; var ss_p: float; var break_p: float; var aggr: float


func _init(game, level: int) -> void:
	G = game
	lv = level
	# levels: 0 easy, 1 normal, 2 hard, 3 boss
	block_p = [0.3, 0.6, 0.85, 0.93][lv]; low_p = [0.15, 0.45, 0.8, 0.9][lv]; punish_p = [0.15, 0.55, 0.9, 0.97][lv]
	ss_p = [0.04, 0.12, 0.25, 0.3][lv]; break_p = [0.1, 0.4, 0.75, 0.88][lv]; aggr = [0.5, 0.62, 0.72, 0.8][lv]


static func item(h := 0, v := 0, b := 0, n := 1) -> Dictionary:
	return {h = h, v = v, b = b, n = n, go = false}


func push(s: Array) -> void:
	q = s


func emit() -> Array:
	var c: Dictionary = q[0]
	var press: int = 0 if c.go else c.b
	c.go = true
	c.n -= 1
	if c.n <= 0:
		q.pop_front()
	return [c.h, c.v, press]


## Turn a move key into a timed input sequence.
static func key_seq(key: String, C: Dictionary) -> Array:
	var k := key
	var out: Array = []
	if ":" in k:
		var parts := k.split(":")
		for m in C.moves.values():
			if m.to_stance == parts[0]:
				out.append_array(key_seq(m.key, C))
				out.append(item(0, 0, 0, m.end - 2))
				break
		k = parts[1]
	var h := 0
	var v := 0
	if k.begins_with("ff"):
		out.append_array([item(1, 0, 0, 2), item(0, 0, 0, 2), item(1, 0, 0, 2)])
		h = 1
		k = k.substr(2)
	elif k.begins_with("ws"):
		out.append_array([item(0, -1, 0, 12), item(0, 0, 0, 1)])
		k = k.substr(2)
	var dm := {df = [1, -1], db = [-1, -1], uf = [1, 1], d = [0, -1], b = [-1, 0], f = [1, 0]}
	for p in ["df", "db", "uf", "d", "b", "f"]:
		if k.begins_with(p):
			h = dm[p][0]; v = dm[p][1]
			k = k.substr(p.length())
			break
	var bits := 0
	for c in k:
		if c.is_valid_int():
			bits |= 1 << (int(c) - 1)
	out.append(item(h, v, bits, 3))
	return out


## Follow a string chain randomly (1 -> 1,2 -> 1,2,4).
static func chain_seq(m: Data.Move, C: Dictionary, prob: float) -> Array:
	var out := key_seq(m.key, C)
	var cur := m
	while not cur.next.is_empty() and randf() < prob:
		var btn: String = cur.next.keys().pick_random()
		cur = C.moves[cur.next[btn]]
		var bits := 0
		for c in btn:
			bits |= 1 << (int(c) - 1)
		out.append(item(0, 0, 0, 5))
		out.append(item(0, 0, bits, 1))
	return out


func think(me: Fighter, op: Fighter) -> Array:
	if G.phase != "fight":
		q.clear()
		return [0, 0, 0]
	if me.state == "thrown":
		if me.sf == 3 and randf() < break_p:
			push([item(0, 0, 3, 1)])
		return emit() if not q.is_empty() else [0, 0, 0]
	# React to a newly started opponent move (a "read" with a difficulty-based success rate).
	if op.state == "attack" and op.move_id != seen:
		seen = op.move_id
		var m := op.move
		var busy := me.state == "attack" or q.any(func(c): return c.b != 0 and not c.go)
		if not m.trans and not busy and (me.can_act() or me.state == "block") and me.dist_to(op) < 2.4:
			if m.is_throw:
				if randf() < block_p * 0.6:
					push([item(0, -1, 0, m.s + 6)])
			elif randf() < (low_p if m.lvl == "low" else block_p):
				if not m.homing and me.can_act() and randf() < ss_p:
					push([item(0, 1, 0, 2), item(0, 0, 0, 12)])
				elif m.lvl == "low":
					push([item(-1, -1, 0, m.s + m.a + 4)])
				else:
					push([item(0, 0, 0, m.s + m.a + 4)])
			elif me.can_act():
				var pk: Array = me.C.ai.pokes
				push(key_seq((pk.pick_random() if not pk.is_empty() else me.C.moves["1"]).key, me.C) if randf() < 0.6 else [item(1, 0, 0, m.s)])
			wait = 0
	if not q.is_empty():
		return emit()
	if wait > 0:
		wait -= 1
		return [drift, 0, 0]
	decide(me, op)
	return emit() if not q.is_empty() else [0, 0, 0]


func decide(me: Fighter, op: Fighter) -> void:
	var d := me.dist_to(op)
	var sc: float = me.C.scale
	var r := randf()
	var A: Dictionary = me.C.ai
	drift = 0
	# Punish: opponent stuck in recovery.
	if op.state == "attack" and not op.move.trans and op.sf >= op.move.s + op.move.a and (me.can_act() or (me.state == "block" and me.stun - me.sf <= 6)):
		var rem: int = op.move.end - op.sf
		if d < 1.3 * sc and rem >= 11 and randf() < punish_p:
			var opts: Array = me.C.moves.values().filter(func(m): return not m.hidden and not m.trans and not m.is_throw \
				and not ("," in m.key) and not (":" in m.key) and not m.key.begins_with("ff") and not m.key.begins_with("ws") \
				and m.key != "34" and m.s <= rem and m.lvl != "low")
			if not opts.is_empty():
				opts.sort_custom(func(a, b): return a.dmg + (25 if a.launch else 0) > b.dmg + (25 if b.launch else 0))
				push(chain_seq(opts[0], me.C, 0.8))
				return
	if not me.can_act():
		return
	if op.state == "air":
		if op.juggle >= 8: return
		if d > 1.15 * sc:
			push([item(1, 0, 0, 3)]); return
		push(chain_seq(A.juggle.pick_random(), me.C, 0.8)); return
	if op.state in ["down", "getup"]:
		push([item(-1 if d < 1.8 else 0, 0, 0, randi_range(6, 14))]); return
	# from far away: dash into a run and finish with a running attack
	if d > 3.0 and r < 0.12 + lv * 0.05:
		var frames := clampi(int((d - 1.7) / (0.088 * me.C.speed)), 4, 70)
		push([item(1, 0, 0, 2), item(0, 0, 0, 2), item(1, 0, 0, 10 + frames), item(1, 0, [1, 2, 4, 8].pick_random(), 2)])
		return
	# from mid range: jump in with a kick
	if d > 1.6 and d < 2.8 and r > 0.93 - lv * 0.02:
		push([item(1, 1, 0, 14), item(1, 1, [4, 8].pick_random(), 2), item(0, 0, 0, 20)])
		return
	if d > 2.1:
		push([item(1, 0, 0, 2), item(0, 0, 0, 2), item(1, 0, 0, 10)] if r < 0.3 else [item(1, 0, 0, randi_range(8, 18))])
		wait = randi_range(0, 8 - lv * 2)
		return
	if d > 1.25 * sc:
		if r < 0.45: push([item(1, 0, 0, randi_range(4, 10))])
		elif r < 0.62 and not A.sig.is_empty(): push(key_seq(A.sig.pick_random().key, me.C))
		elif r < 0.72: push([item(0, 1, 0, 2), item(0, 0, 0, 12)])
		elif r < 0.8:
			var lng: Array = A.heavy.filter(func(m): return m.range >= 1.2)
			if not lng.is_empty(): push(key_seq(lng.pick_random().key, me.C))
		else: wait = randi_range(6, 20)
		return
	# powers: FINAL when it's unlocked and they're close, BLUE now and then
	if me.final_ready() and d < 1.3 * sc and r < 0.35 + lv * 0.1:
		push(key_seq("24", me.C)); return
	if me.blue_ready() and d < 1.5 * sc and r < 0.06 + lv * 0.03:
		push(key_seq("13", me.C)); return
	if r < aggr:
		var cats := [[A.pokes, 4.0], [A.mids, 2.0], [A.lows, 2.0 if lv else 1.0], [A.launch, 1.0], [A.heavy, 1.2],
			[A.throws, 1.0 if lv else 0.3], [A.stance, 0.6], [A.sig, 0.6]].filter(func(c): return not c[0].is_empty())
		var tot := 0.0
		for c in cats: tot += c[1]
		var x := randf() * tot
		var pool: Array = cats[0][0]
		for c in cats:
			x -= c[1]
			if x <= 0:
				pool = c[0]; break
		var m: Data.Move = pool.pick_random()
		if m.to_stance != "":
			var fol: Array = me.C.moves.values().filter(func(s): return s.key.begins_with(m.to_stance + ":"))
			push(key_seq(fol.pick_random().key if not fol.is_empty() else m.key, me.C))
		else:
			push(chain_seq(m, me.C, [0.35, 0.55, 0.7, 0.8][lv]))
		wait = randi_range(4, maxi(5, 18 - lv * 5))
		return
	if r < aggr + 0.12:
		push([item(-1, 0, 0, 2), item(0, 0, 0, 2), item(-1, 0, 0, 14)] if randf() < 0.5 else [item(0, 1, 0, 2), item(0, 0, 0, 12)])
		return
	drift = -1 if randf() < 0.5 else (1 if lv == 0 else 0)
	wait = randi_range(8, maxi(9, 24 - lv * 6))
