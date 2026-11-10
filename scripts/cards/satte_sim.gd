extends "res://scripts/cards/room_sim.gd"
## SATTE PE SATTA (Seven on Seven), 3–8 players. All 52 cards dealt round the table (some hold one more).
## The 7♥ starts. On your turn: play any 7 to open its suit's row, or the next card up (8, 9 … K, A) or
## down (6, 5 … 2) on a row that's open. If you can't, you pass. First to empty their hand wins; play goes on
## to rank everyone else (the last one holding cards finishes last).
## Simplification: aces only go on top of the king (A high), as with the rest of the room's games.

var rows: Array = [[-1, -1], [-1, -1], [-1, -1], [-1, -1]]   # per suit: [low rank, high rank] or -1 when not open
var opened := false               # the 7♥ is down
var passes := 0


func _begin() -> void:
	variant = "satte"
	var d := shuffled(full_deck())
	var k := (dealer + 1) % n
	for c in d:
		(players[k] as Player).hand.append(c)
		k = (k + 1) % n
	for p in players: sort_hand(p.hand)
	for p in players:
		if 18 in p.hand: turn = p.seat      # 7♥ = 1 * 13 + 5
	phase = "deal"; wait = 1.0
	emit(["deal", turn])


func actor() -> int:
	return turn if phase == "play" else -1


func playable(c: int) -> bool:
	if not opened: return c == 18
	var s := suit_of(c); var r := rank_of(c)
	var row: Array = rows[s]
	if int(row[0]) < 0: return r == 5
	return r == int(row[1]) + 1 or r == int(row[0]) - 1


func legal(seat: int) -> Array:
	if phase != "play" or seat != turn: return []
	return (players[seat] as Player).hand.filter(func(c): return playable(c))


func act(seat: int, a: Dictionary) -> bool:
	if phase != "play" or seat != turn: return false
	var kind := String(a.get("a", ""))
	if kind == "pass":
		if not legal(seat).is_empty(): return false    # you must play if you can
		passes += 1
		emit(["pass", seat])
		_next()
		return true
	if kind != "play": return false
	var c := int(a.get("c", -1))
	if not (c in legal(seat)): return false
	var p: Player = players[seat]
	p.hand.erase(c)
	var s := suit_of(c); var r := rank_of(c)
	var row: Array = rows[s]
	if int(row[0]) < 0: rows[s] = [r, r]
	elif r > int(row[1]): row[1] = r
	else: row[0] = r
	opened = true
	passes = 0; idle = 0.0; steps += 1
	emit(["play", seat, c])
	if p.hand.is_empty():
		var placed := players.filter(func(q): return q.out).size()
		p.out = true; p.place = placed + 1
		emit(["escape", seat, p.place])
		var left := players.filter(func(q): return not q.out)
		if left.size() <= 1:
			for q in left: q.out = true; q.place = n
			phase = "done"
			emit(["done", players.filter(func(q): return q.place == 1)[0].seat])
			return true
	_next()
	return true


func _next() -> void:
	turn = next_seat(turn)
	wait = think; idle = 0.0
	emit(["turn", turn])


func _timed(dt: float) -> bool:
	if phase == "deal":
		wait -= dt
		if wait <= 0.0: phase = "play"; wait = think; emit(["turn", turn])
		return true
	return false


# ---------------------------------------------------------------- CPU
## Prefer cards that lead toward more of our own cards in that suit (and hold back 7s that only help others).
func cpu(seat: int) -> Dictionary:
	var opts := legal(seat)
	if opts.is_empty(): return {a = "pass"}
	var p: Player = players[seat]
	var best: int = opts[0]
	var bs := -INF
	for c in opts:
		var s := suit_of(c); var r := rank_of(c)
		var beyond := 0
		for h in p.hand:
			if suit_of(h) == s and h != c and ((r >= 5 and rank_of(h) > r) or (r <= 5 and rank_of(h) < r)): beyond += 1
		var v := beyond * 2.0 + rng.randf() * 0.5
		if r == 5 and beyond == 0: v -= 3.0     # opening a row only to help the others
		if v > bs: bs = v; best = c
	return {a = "play", c = best}


func _snap(_seat: int) -> Dictionary:
	return {rw = rows.duplicate(true), op = opened}


func _unsnap(s: Dictionary) -> void:
	rows = []
	for r in s.rw: rows.append([int(r[0]), int(r[1])])
	opened = bool(s.op)


func result_lines() -> Array:
	var order := players.duplicate()
	order.sort_custom(func(a, b): return a.place < b.place)
	return order.map(func(p): return ["%d." % p.place + (" WINNER!" if p.place == 1 else ""), p.seat])


func winner_seats() -> Array:
	return players.filter(func(p): return p.place == 1).map(func(p): return p.seat)
