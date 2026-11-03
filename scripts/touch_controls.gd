class_name TouchControls
extends Control
## On-screen controls for phones and tablets. Two movement layouts (switch in the pause menu):
##   STICK: floating stick on the left half + ▲ ▼ buttons beside it (sidestep in / crouch, sidestep out)
##   D-PAD: fixed controller-style cross (8 directions, slide between arrows)
## Right side: 1 2 / 3 4 attack buttons, 1+2 (throw) and 3+4 (Surge) shortcuts, pause button.
## Main reads x, y (screen-relative direction) and held (button bits) exactly like the keyboard.

signal pause_pressed

const SETTINGS := "user://settings.cfg"
const DEAD := 22.0         # pixels before the floating stick registers a direction

var mode := "stick"        # "stick" or "dpad"
var x := 0
var y := 0
var held := 0
var font: Font
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var touches := {}          # touch index -> attack button bits
var dir_touches := {}      # touch index -> Vector2i from ▲ ▼ buttons or the d-pad
var buttons: Array = []    # attack buttons: [{bits, label, center, radius, color}]
var vbuttons: Array = []   # ▲ ▼ beside the stick: [{dir, label, center, radius}]
var dpad_center := Vector2.ZERO
var dpad_r := 90.0
var pause_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		mode = cf.get_value("touch", "mode", "stick")
	# Size from the viewport directly (rotation / window resizes re-run the layout).
	get_viewport().size_changed.connect(_layout)
	_layout()


func set_mode(m: String) -> void:
	mode = m
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("touch", "mode", m)
	cf.save(SETTINGS)
	reset()


func toggle_mode() -> void:
	set_mode("dpad" if mode == "stick" else "stick")


func _layout() -> void:
	var s := get_viewport_rect().size
	position = Vector2.ZERO
	size = s
	var r := clampf(s.y * 0.085, 34.0, 70.0)          # button radius scales with the screen
	var c := Vector2(s.x - r * 3.4, s.y - r * 3.4)     # center of the 2x2 attack grid
	var g := r * 1.15
	var P := Color(0.45, 0.85, 1.0)
	var K := Color(1.0, 0.7, 0.35)
	buttons = [
		{bits = 1, label = "1", center = c + Vector2(-g, -g), radius = r, color = P},
		{bits = 2, label = "2", center = c + Vector2(g, -g), radius = r, color = P},
		{bits = 4, label = "3", center = c + Vector2(-g, g), radius = r, color = K},
		{bits = 8, label = "4", center = c + Vector2(g, g), radius = r, color = K},
		{bits = 3, label = "1+2", center = c + Vector2(-g * 2.9, -g * 0.2), radius = r * 0.62, color = Color(0.75, 0.6, 1.0)},
		{bits = 12, label = "3+4", center = c + Vector2(-g * 2.9, g * 1.35), radius = r * 0.62, color = Color(1.0, 0.5, 0.6)},
	]
	# ▲ ▼ next to the stick zone (stick mode)
	var vr := r * 0.72
	var vx := s.x * 0.36
	vbuttons = [
		{dir = Vector2i(0, 1), label = "▲", center = Vector2(vx, s.y - r * 4.3), radius = vr},
		{dir = Vector2i(0, -1), label = "▼", center = Vector2(vx, s.y - r * 2.1), radius = vr},
	]
	# fixed d-pad (d-pad mode)
	dpad_r = clampf(s.y * 0.16, 70.0, 140.0)
	dpad_center = Vector2(dpad_r * 1.45, s.y - dpad_r * 1.35)
	pause_rect = Rect2(Vector2(s.x / 2 - 48, s.y - 86), Vector2(96, 72))
	queue_redraw()


func reset() -> void:
	x = 0; y = 0; held = 0; stick_id = -1; touches.clear(); dir_touches.clear()
	_layout()


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			if pause_rect.has_point(e.position):
				pause_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			var b := _button_at(e.position)
			var d = _dir_at(e.position)
			if b >= 0:
				touches[e.index] = b
			elif d != null:
				dir_touches[e.index] = d
			elif mode == "stick" and e.position.x < size.x * 0.5 and stick_id < 0:
				stick_id = e.index
				stick_origin = e.position
				stick_pos = e.position
		else:
			touches.erase(e.index)
			dir_touches.erase(e.index)
			if e.index == stick_id:
				stick_id = -1
		_update()
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		if e.index == stick_id:
			stick_pos = e.position
		elif touches.has(e.index):
			# sliding a thumb across buttons (e.g. 1 -> 2 for a string) presses the new one
			var b := _button_at(e.position)
			if b >= 0: touches[e.index] = b
		elif dir_touches.has(e.index):
			# rolling the thumb across the d-pad / arrows changes direction
			var d = _dir_at(e.position)
			if d != null: dir_touches[e.index] = d
		_update()
		get_viewport().set_input_as_handled()


func _button_at(p: Vector2) -> int:
	for b in buttons:
		if p.distance_to(b.center) <= b.radius * 1.12:
			return b.bits
	return -1


## Direction from the ▲ ▼ buttons (stick mode) or the d-pad (d-pad mode); null when not on one.
func _dir_at(p: Vector2):
	if mode == "stick":
		for v in vbuttons:
			if p.distance_to(v.center) <= v.radius * 1.15:
				return v.dir
		return null
	var d := p - dpad_center
	if d.length() > dpad_r * 1.25:
		return null
	if d.length() < dpad_r * 0.22:
		return Vector2i.ZERO   # thumb resting in the middle
	return _octant(d)


static func _octant(d: Vector2) -> Vector2i:
	var a := fposmod(atan2(-d.y, d.x), TAU)      # 0 = right, counter-clockwise
	var oct := int(round(a / (TAU / 8.0))) % 8
	return Vector2i([1, 1, 0, -1, -1, -1, 0, 1][oct], [0, 1, 1, 1, 0, -1, -1, -1][oct])


func _update() -> void:
	held = 0
	for i in touches:
		held |= touches[i]
	var v := Vector2i.ZERO
	if stick_id >= 0:
		var d := stick_pos - stick_origin
		if d.length() > DEAD:
			v = _octant(d)
	for i in dir_touches:
		var dv: Vector2i = dir_touches[i]
		if dv.x != 0: v.x = dv.x
		if dv.y != 0: v.y = dv.y
	x = v.x
	y = v.y
	queue_redraw()


func _draw_button(center: Vector2, radius: float, label: String, c: Color, on: bool) -> void:
	draw_circle(center, radius, Color(c, 0.55 if on else 0.18))
	draw_arc(center, radius, 0, TAU, 40, Color(c, 0.95 if on else 0.6), 3.0)
	if font:
		var fs := int(radius * (0.7 if label.length() == 1 else 0.42))
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, center + Vector2(-w / 2, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))


func _draw() -> void:
	var W := Color(0.85, 0.9, 1.0)
	if mode == "stick":
		if stick_id >= 0:
			var r := clampf(size.y * 0.11, 50.0, 95.0)
			var d := (stick_pos - stick_origin).limit_length(r)
			draw_circle(stick_origin, r, Color(1, 1, 1, 0.08))
			draw_arc(stick_origin, r, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
			draw_circle(stick_origin + d, r * 0.42, Color(0.45, 0.85, 1.0, 0.55))
		else:
			var hint := Vector2(size.x * 0.16, size.y * 0.72)
			draw_arc(hint, 56, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0)
			if font: draw_string(font, hint + Vector2(-40, 6), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 80, 16, Color(1, 1, 1, 0.3))
		for v in vbuttons:
			_draw_button(v.center, v.radius, v.label, W, y == v.dir.y and dir_touches.values().has(v.dir))
	else:
		# controller-style cross
		var c := dpad_center
		var arm := dpad_r * 0.42
		var len := dpad_r
		draw_circle(c, dpad_r * 1.08, Color(0, 0, 0, 0.18))
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var dir := Vector2(dv.x, -dv.y)
			var on: bool = (dv.x != 0 and x == dv.x) or (dv.y != 0 and y == dv.y)
			var rect_center := c + dir * len * 0.55
			var ext := Vector2(len * 0.55, arm) if dv.x != 0 else Vector2(arm, len * 0.55)
			draw_rect(Rect2(rect_center - ext, ext * 2), Color(W, 0.45 if on else 0.14))
			draw_rect(Rect2(rect_center - ext, ext * 2), Color(W, 0.75 if on else 0.4), false, 2.0)
			if font:
				var lbl: String = {Vector2i(1, 0): "▶", Vector2i(-1, 0): "◀", Vector2i(0, 1): "▲", Vector2i(0, -1): "▼"}[dv]
				var fs := int(arm * 0.9)
				var p := c + dir * len * 0.72
				draw_string(font, p + Vector2(-fs * 0.35, fs * 0.35), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
		draw_rect(Rect2(c - Vector2(arm, arm), Vector2(arm, arm) * 2), Color(W, 0.14))
	for b in buttons:
		_draw_button(b.center, b.radius, b.label, b.color, (held & b.bits) == b.bits)
	draw_rect(pause_rect, Color(0, 0, 0, 0.35))
	draw_rect(pause_rect, Color(1, 1, 1, 0.4), false, 2.0)
	var pc := pause_rect.get_center()
	draw_rect(Rect2(pc + Vector2(-16, -17), Vector2(11, 34)), Color(1, 1, 1, 0.85))
	draw_rect(Rect2(pc + Vector2(5, -17), Vector2(11, 34)), Color(1, 1, 1, 0.85))
