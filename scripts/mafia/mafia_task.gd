class_name MafiaTask
extends Control
## One office task, played on screen (mouse or touch). Emits done when solved, closed when abandoned.
##   coffee  — hold to fill the cup, let go between the lines       plant   — water every dry leaf
##   code    — tap the line with the bug                            keypad  — type the code on the sticky note
##   sign    — sign by joining the dots 1 → 6                      shred   — feed papers when the marker is in the slot
##   cables  — join each coloured cable to its port                 printer — pull out every scrap of jammed paper
##   mail    — drop each letter in its department's tray

signal done
signal closed

var kind := ""
var title := ""
var font: Font
var small: Font
var rng := RandomNumberGenerator.new()
var box := Rect2()
var st := {}                   # the task's own state
var finished_t := -1.0
var holding := false

const BUGS := [
	[["if (user.isAdmin = true) {", "  grantAccess(user);", "}", "log(\"checked\", user.id);", "return user;"], 0],
	[["total = 0", "for i in range(len(items)):", "    total += items[i + 1]", "print(total)", "save(total)"], 2],
	[["let price = 100;", "let tax = price * 0.17;", "let sum = price + tax", "if (sum > 0) pay(sum);", "receipt(sum);"], 2],
	[["def area(w, h):", "    return w * h", "box = area(3, 4)", "print(\"area\", box)", "assert box == 7"], 4],
	[["while (retries > 0) {", "  send(packet);", "  retries++;", "}", "close(socket);"], 2],
	[["SELECT name", "FROM staff", "WHERE dept = 'HR'", "ORDER BY name", "LIMIT -1;"], 4],
]
const DEPTS := [["HR", Color(0.95, 0.4, 0.5)], ["DEV", Color(0.4, 0.7, 1.0)], ["SALES", Color(1.0, 0.8, 0.3)], ["OPS", Color(0.45, 0.9, 0.55)]]
const WIRES := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.25), Color(0.4, 0.9, 0.45)]


func setup(k: String, t: String) -> void:
	kind = k; title = t
	rng.randomize()
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	match kind:
		"coffee": st = {fill = 0.0, lo = rng.randf_range(0.62, 0.72), band = 0.12}
		"plant":
			var leaves := []
			for i in 6: leaves.append({p = Vector2(rng.randf_range(0.25, 0.75), rng.randf_range(0.2, 0.62)), dry = i < 4})
			st = {leaves = leaves}
		"code":
			var b: Array = BUGS[rng.randi() % BUGS.size()]
			st = {lines = b[0], bug = b[1], wrong = -1, wrong_t = 0.0}
		"keypad": st = {code = "%04d" % rng.randi_range(0, 9999), typed = "", bad_t = 0.0}
		"sign":
			var pts := []
			for i in 6: pts.append(Vector2(0.15 + i * 0.14, 0.45 + sin(i * 1.7 + rng.randf()) * 0.18))
			st = {pts = pts, next = 0}
		"shred": st = {x = 0.0, v = 0.9, slot = rng.randf_range(0.3, 0.7), fed = 0, need = 3, miss_t = 0.0}
		"cables":
			var order := [0, 1, 2, 3]
			order.shuffle()
			st = {right = order, linked = [false, false, false, false], pick = -1}
		"printer":
			var scraps := []
			for i in 5: scraps.append({p = Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.3, 0.75)), r = rng.randf_range(-0.6, 0.6), gone = false})
			st = {scraps = scraps}
		"mail":
			var letters := []
			for i in 5: letters.append(rng.randi() % 4)
			st = {letters = letters, at = 0, bad_t = 0.0}


func _process(dt: float) -> void:
	var vs := get_viewport_rect().size
	var w := minf(vs.x * 0.86, 720.0)
	var h := minf(vs.y * 0.78, 460.0)
	box = Rect2((vs - Vector2(w, h)) / 2.0, Vector2(w, h))
	if finished_t >= 0.0:
		finished_t += dt
		if finished_t > 0.7: done.emit(); finished_t = -10.0
	match kind:
		"coffee":
			if holding and finished_t < 0.0:
				st.fill = minf(1.0, st.fill + dt * 0.42)
				if st.fill >= 1.0: st.fill = 0.0; holding = false   # overflowed: start again
		"shred":
			st.x += st.v * dt
			if st.x > 1.0 or st.x < 0.0: st.v = -st.v; st.x = clampf(st.x, 0.0, 1.0)
	for k in ["wrong_t", "bad_t", "miss_t"]:
		if st.has(k): st[k] = maxf(0.0, float(st[k]) - dt)
	queue_redraw()


func _win() -> void:
	if finished_t < 0.0 and finished_t > -5.0: finished_t = 0.0


func _L(p: Vector2) -> Vector2:     # 0..1 inside the play area -> screen
	var a := Rect2(box.position + Vector2(24, 70), box.size - Vector2(48, 100))
	return a.position + p * a.size


func _area() -> Rect2:
	return Rect2(box.position + Vector2(24, 70), box.size - Vector2(48, 100))


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_LEFT: return
	var p: Vector2 = e.position
	if e.pressed and Rect2(box.end.x - 56, box.position.y + 10, 46, 46).has_point(p):
		closed.emit(); return
	if finished_t >= 0.0: return
	var a := _area()
	match kind:
		"coffee":
			if e.pressed: holding = true
			elif holding:
				holding = false
				if st.fill >= st.lo and st.fill <= st.lo + st.band: _win()
				else: st.fill = 0.0
		"plant":
			if not e.pressed: return
			for l in st.leaves:
				if l.dry and _L(l.p).distance_to(p) < a.size.x * 0.07: l.dry = false
			if st.leaves.all(func(l): return not l.dry): _win()
		"code":
			if not e.pressed: return
			var lh := a.size.y / 6.0
			var i := int((p.y - a.position.y - lh * 0.5) / lh)
			if i >= 0 and i < st.lines.size():
				if i == st.bug: _win()
				else: st.wrong = i; st.wrong_t = 0.6
		"keypad":
			if not e.pressed: return
			var k := _key_at(p)
			if k == "": return
			if k == "C": st.typed = ""
			elif k == "OK":
				if st.typed == st.code: _win()
				else: st.typed = ""; st.bad_t = 0.6
			elif String(st.typed).length() < 4: st.typed += k
		"sign":
			if not e.pressed: return
			var n: int = st.next
			if n < st.pts.size() and _L(st.pts[n]).distance_to(p) < 34.0:
				st.next = n + 1
				if st.next >= st.pts.size(): _win()
		"shred":
			if not e.pressed: return
			if absf(st.x - st.slot) < 0.08:
				st.fed += 1; st.slot = rng.randf_range(0.2, 0.8); st.v *= 1.15
				if st.fed >= st.need: _win()
			else: st.miss_t = 0.4
		"cables":
			if not e.pressed: return
			for i in 4:
				if _cable_l(i).distance_to(p) < 30.0 and not st.linked[i]: st.pick = i; return
			if st.pick >= 0:
				for j in 4:
					if _cable_r(j).distance_to(p) < 34.0:
						if st.right[j] == st.pick: st.linked[st.pick] = true
						st.pick = -1
						if st.linked.all(func(x): return x): _win()
						return
		"printer":
			if not e.pressed: return
			for s in st.scraps:
				if not s.gone and _L(s.p).distance_to(p) < a.size.x * 0.08: s.gone = true; break
			if st.scraps.all(func(s): return s.gone): _win()
		"mail":
			if not e.pressed or st.at >= st.letters.size(): return
			for t in 4:
				if _tray(t).has_point(p):
					if t == st.letters[st.at]:
						st.at += 1
						if st.at >= st.letters.size(): _win()
					else: st.bad_t = 0.5
					return


func _key_at(p: Vector2) -> String:
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK"]
	for i in 12:
		if _key_rect(i).has_point(p): return keys[i]
	return ""


func _key_rect(i: int) -> Rect2:
	var a := _area()
	var kw := minf(a.size.x * 0.13, 78.0)
	var kh := a.size.y / 4.6
	var x0 := a.position.x + a.size.x * 0.52
	return Rect2(Vector2(x0 + (i % 3) * (kw + 8), a.position.y + (i / 3) * (kh + 6)), Vector2(kw, kh))


func _cable_l(i: int) -> Vector2: return _L(Vector2(0.08, 0.15 + i * 0.23))
func _cable_r(i: int) -> Vector2: return _L(Vector2(0.92, 0.15 + i * 0.23))


func _tray(t: int) -> Rect2:
	var a := _area()
	var w := a.size.x / 4.0 - 12.0
	return Rect2(Vector2(a.position.x + t * (w + 16), a.end.y - a.size.y * 0.36), Vector2(w, a.size.y * 0.34))


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	draw_rect(box, Color(0.07, 0.05, 0.12, 0.97))
	draw_rect(box, Color(0.58, 0.3, 0.85), false, 3.0)
	draw_string(font, box.position + Vector2(24, 46), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 100, 28, Color(1.0, 0.82, 0.4))
	var xb := Rect2(box.end.x - 56, box.position.y + 10, 46, 46)
	draw_rect(xb, Color(0.3, 0.25, 0.4)); draw_string(font, xb.position + Vector2(0, 34), "✕", HORIZONTAL_ALIGNMENT_CENTER, 46, 28, Color.WHITE)
	var a := _area()
	var ink := Color(0.94, 0.95, 1.0)
	match kind:
		"coffee":
			var cup := Rect2(a.position + Vector2(a.size.x * 0.38, a.size.y * 0.1), Vector2(a.size.x * 0.24, a.size.y * 0.8))
			draw_rect(cup, Color(0.9, 0.9, 0.92), false, 4.0)
			var fh: float = cup.size.y * st.fill
			draw_rect(Rect2(Vector2(cup.position.x + 3, cup.end.y - fh), Vector2(cup.size.x - 6, fh)), Color(0.45, 0.27, 0.13))
			for f in [st.lo, st.lo + st.band]:
				var y: float = cup.end.y - cup.size.y * f
				draw_line(Vector2(cup.position.x - 20, y), Vector2(cup.end.x + 20, y), Color(0.4, 1.0, 0.5), 3.0)
			draw_string(small, Vector2(a.position.x, a.end.y + 22), "HOLD to pour  ·  let go between the green lines", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 20, ink)
		"plant":
			draw_rect(Rect2(_L(Vector2(0.42, 0.72)), Vector2(a.size.x * 0.16, a.size.y * 0.25)), Color(0.55, 0.3, 0.2))
			draw_line(_L(Vector2(0.5, 0.72)), _L(Vector2(0.5, 0.25)), Color(0.3, 0.55, 0.25), 6.0)
			for l in st.leaves:
				draw_line(_L(Vector2(0.5, l.p.y + 0.05)), _L(l.p), Color(0.3, 0.55, 0.25), 3.0)
				draw_circle(_L(l.p), a.size.x * 0.05, Color(0.6, 0.45, 0.2) if l.dry else Color(0.35, 0.85, 0.4))
			draw_string(small, Vector2(a.position.x, a.end.y + 22), "Tap every dry (brown) leaf", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 20, ink)
		"code":
			var lh := a.size.y / 6.0
			for i in st.lines.size():
				var r := Rect2(Vector2(a.position.x, a.position.y + lh * (i + 0.5)), Vector2(a.size.x, lh - 6))
				draw_rect(r, Color(0.9, 0.25, 0.3, 0.5) if i == st.wrong and st.wrong_t > 0.0 else (Color(0.3, 0.9, 0.4, 0.4) if finished_t >= 0.0 and i == st.bug else Color(0.12, 0.1, 0.18)))
				draw_string(small, r.position + Vector2(12, lh * 0.62), "%d   %s" % [i + 1, st.lines[i]], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 24, Color(0.7, 0.9, 1.0))
			draw_string(small, Vector2(a.position.x, a.position.y + 18), "One line has a bug. Tap it.", HORIZONTAL_ALIGNMENT_LEFT, a.size.x, 20, ink)
		"keypad":
			var note := Rect2(a.position + Vector2(a.size.x * 0.04, a.size.y * 0.12), Vector2(a.size.x * 0.36, a.size.y * 0.42))
			draw_rect(note, Color(1.0, 0.92, 0.45))
			draw_string(small, note.position + Vector2(12, 30), "IT says:", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.3, 0.25, 0.1))
			draw_string(font, note.position + Vector2(12, note.size.y * 0.75), st.code, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(0.2, 0.15, 0.05))
			var scr := Rect2(a.position + Vector2(a.size.x * 0.04, a.size.y * 0.62), Vector2(a.size.x * 0.36, a.size.y * 0.22))
			draw_rect(scr, Color(0.9, 0.2, 0.25) if st.bad_t > 0.0 else Color(0.05, 0.12, 0.08))
			draw_string(font, scr.position + Vector2(12, scr.size.y * 0.75), String(st.typed).rpad(4, "_"), HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0.4, 1.0, 0.5))
			var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK"]
			for i in 12:
				var kr := _key_rect(i)
				draw_rect(kr, Color(0.22, 0.2, 0.3)); draw_rect(kr, Color(0.58, 0.3, 0.85), false, 2.0)
				draw_string(font, kr.position + Vector2(0, kr.size.y * 0.66), keys[i], HORIZONTAL_ALIGNMENT_CENTER, kr.size.x, 24, Color.WHITE)
		"sign":
			for i in st.pts.size():
				if i < st.next and i > 0: draw_line(_L(st.pts[i - 1]), _L(st.pts[i]), Color(0.3, 0.6, 1.0), 5.0)
				var c := Color(0.3, 0.6, 1.0) if i < st.next else (Color(1.0, 0.82, 0.4) if i == st.next else Color(0.6, 0.6, 0.7))
				draw_circle(_L(st.pts[i]), 18.0, c)
				draw_string(font, _L(st.pts[i]) + Vector2(-18, 8), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 36, 20, Color(0.05, 0.05, 0.1))
			draw_line(_L(Vector2(0.08, 0.8)), _L(Vector2(0.92, 0.8)), Color(0.6, 0.6, 0.7), 2.0)
			draw_string(small, Vector2(a.position.x, a.end.y + 22), "Sign: tap the dots 1 → 6", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 20, ink)
		"shred":
			var bar := Rect2(_L(Vector2(0.05, 0.45)), Vector2(a.size.x * 0.9, 40))
			draw_rect(bar, Color(0.15, 0.12, 0.2))
			draw_rect(Rect2(Vector2(bar.position.x + bar.size.x * (st.slot - 0.08), bar.position.y), Vector2(bar.size.x * 0.16, 40)), Color(0.35, 0.85, 0.45, 0.7))
			draw_rect(Rect2(Vector2(bar.position.x + bar.size.x * st.x - 4, bar.position.y - 10), Vector2(8, 60)), Color(0.9, 0.3, 0.3) if st.miss_t > 0.0 else Color.WHITE)
			draw_string(font, Vector2(a.position.x, a.position.y + 40), "%d / %d" % [st.fed, st.need], HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 32, ink)
			draw_string(small, Vector2(a.position.x, a.end.y + 22), "Tap when the marker is in the green slot", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 20, ink)
		"cables":
			for i in 4:
				draw_circle(_cable_l(i), 16.0, WIRES[i])
				draw_rect(Rect2(_cable_r(i) - Vector2(18, 18), Vector2(36, 36)), WIRES[st.right[i]].darkened(0.2))
				if st.linked[i]: draw_line(_cable_l(i), _cable_r(st.right.find(i)), WIRES[i], 8.0)
			if st.pick >= 0: draw_arc(_cable_l(st.pick), 24.0, 0, TAU, 24, Color.WHITE, 3.0)
			draw_string(small, Vector2(a.position.x, a.end.y + 22), "Tap a cable, then the port of the same colour", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 20, ink)
		"printer":
			draw_rect(Rect2(_L(Vector2(0.12, 0.2)), a.size * Vector2(0.76, 0.66)), Color(0.25, 0.25, 0.3))
			for s in st.scraps:
				if s.gone: continue
				var c := _L(s.p)
				var pts := PackedVector2Array()
				for k in 4: pts.append(c + Vector2(34, 24).rotated(s.r + k * PI / 2.0) * Vector2(1.0, 0.8 if k % 2 else 1.2))
				draw_colored_polygon(pts, Color(0.96, 0.96, 0.92))
			draw_string(small, Vector2(a.position.x, a.end.y + 22), "Pull out every scrap of jammed paper", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 20, ink)
		"mail":
			for t in 4:
				var tr := _tray(t)
				draw_rect(tr, (DEPTS[t][1] as Color).darkened(0.45)); draw_rect(tr, DEPTS[t][1], false, 3.0)
				draw_string(font, tr.position + Vector2(0, tr.size.y * 0.6), DEPTS[t][0], HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 24, Color.WHITE)
			if st.at < st.letters.size():
				var d: Array = DEPTS[st.letters[st.at]]
				var lr := Rect2(_L(Vector2(0.3, 0.05)), a.size * Vector2(0.4, 0.34))
				draw_rect(lr, Color(0.95, 0.93, 0.86) if st.bad_t <= 0.0 else Color(1.0, 0.6, 0.6))
				draw_rect(Rect2(lr.position + Vector2(10, 10), Vector2(lr.size.x * 0.3, 10)), d[1])
				draw_string(font, lr.position + Vector2(0, lr.size.y * 0.66), "TO: " + String(d[0]), HORIZONTAL_ALIGNMENT_CENTER, lr.size.x, 26, Color(0.15, 0.12, 0.2))
			draw_string(small, Vector2(a.position.x, a.position.y + 4), "Letter %d / %d — tap its tray" % [mini(st.at + 1, st.letters.size()), st.letters.size()], HORIZONTAL_ALIGNMENT_LEFT, a.size.x, 20, ink)
	if finished_t >= 0.0:
		draw_string(font, Vector2(box.position.x, box.get_center().y), "DONE ✔", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 64, Color(0.4, 1.0, 0.5))


## Tests: solve it instantly.
func solve() -> void:
	_win()
