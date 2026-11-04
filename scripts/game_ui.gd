class_name GameUI
extends CanvasLayer
## HUD, menus, character select, VS splash, pause, move list, results.

const P1C := Color(0.66, 0.4, 1.0)     # Bit & Bytes purple
const P2C := Color(0.13, 0.78, 0.92)   # Bit & Bytes cyan
const GOLD := Color(1.0, 0.81, 0.35)
const INK := Color(0.93, 0.95, 0.98)
const DIM := Color(0.56, 0.61, 0.69)
const PANEL := Color(0.06, 0.03, 0.1, 0.94)

var G   # Main
var view := "none"
var chip := [100.0, 100.0]
var F_TITLE: FontFile
var F_BODY: FontFile
var F_MED: FontFile
var root: Control
var hud: Control
var screen: Control
var plates: Array = []
var timer_lbl: Label
var round_lbl: Label
var combo: Array = []
var combo_t := [0, 0]
var pops: Array = []
var ann: Label
var flash: ColorRect
var train: RichTextLabel
var train_panel: PanelContainer
var hint: RichTextLabel
var desc_lbl: Label
var sel = null
var info: Array = []
var pad_start := false
var combo_last := [0, 0]
var touch: TouchControls
var touch_enabled := false
var nav_back: Button       # touch only: BACK (top-left) and CONFIRM (bottom-right) on menu screens
var nav_ok: Button


# ---------------------------------------------------------------- helpers
func _font(path: String) -> FontFile:
	# Load through the resource system so it works in exported builds (fonts are imported).
	return load(path) as FontFile


func lbl(text: String, size: int, font: Font = null, color := INK, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	var s := LabelSettings.new()
	s.font = font if font != null else F_BODY
	s.font_size = size
	s.font_color = color
	if outline > 0:
		s.outline_size = outline
		s.outline_color = Color(0, 0, 0, 0.85)
	s.shadow_size = 2
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_offset = Vector2(0, 3)
	l.label_settings = s
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func rich(size := 18) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_override("normal_font", F_MED)
	r.add_theme_font_override("bold_font", F_BODY)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", Color(0.79, 0.83, 0.88))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func sbox(bg: Color, border := Color(0, 0, 0, 0), bw := 0, skew := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.skew = Vector2(skew, 0)
	s.content_margin_left = 18; s.content_margin_right = 22; s.content_margin_top = 6; s.content_margin_bottom = 6
	return s


func menu_btn(text: String, cb: Callable, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	if touch_enabled:
		size = int(size * 1.3)
		b.custom_minimum_size.y = size * 1.9   # a comfortable thumb target
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", F_TITLE)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_stylebox_override("normal", sbox(Color(0, 0, 0, 0)))
	var hl := sbox(Color(P1C, 0.28), GOLD, 0, 0.3)
	hl.border_width_left = 5
	b.add_theme_stylebox_override("hover", hl)
	b.add_theme_stylebox_override("focus", hl)
	b.add_theme_stylebox_override("pressed", hl)
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func(): G.sfx("ui"))
	b.pressed.connect(func(): G.sfx("ok"); cb.call())
	return b


func full(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c


func place(c: Control, parent: Control, preset: int, pos := Vector2.ZERO) -> Control:
	parent.add_child(c)
	c.set_anchors_and_offsets_preset(preset)
	c.position += pos
	return c


func hgrad(left: Color, right: Color) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, left); g.set_color(1, right)
	var t := GradientTexture2D.new()
	t.gradient = g
	var tr := TextureRect.new()
	tr.texture = t
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func vgrad(top: Color, bottom: Color) -> TextureRect:
	var tr := hgrad(top, bottom)
	(tr.texture as GradientTexture2D).fill_to = Vector2(0, 1)
	return tr


# ---------------------------------------------------------------- custom-drawn widgets
class Bar extends Control:
	var value := 1.0
	var chip := 1.0
	var mirror := false
	var a := Color.WHITE
	var b := Color.WHITE
	var low := false
	var ticks := 10
	var t := 0.0

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _quad(x0: float, x1: float, h: float, sk: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(x0 + sk, 0), Vector2(x1 + sk, 0), Vector2(x1, h), Vector2(x0, h)])

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var sk := h * 0.4 * (-1.0 if mirror else 1.0)
		var border := Color(1, 0.4, 0.4) if low and fmod(t, 0.6) < 0.3 else Color(0.87, 0.9, 0.95)
		draw_colored_polygon(_quad(-2, w + 2, h + 2, sk), border)
		draw_colored_polygon(_quad(0, w, h, sk), Color(0.05, 0.07, 0.11))
		var seg := func(frac: float) -> Array:
			return [w * (1.0 - frac), w] if not mirror else [0.0, w * frac]
		var c: Array = seg.call(chip)
		if chip > 0: draw_colored_polygon(_quad(c[0], c[1], h, sk), Color(1, 0.23, 0.23))
		var v: Array = seg.call(value)
		if value > 0:
			var q := _quad(v[0], v[1], h, sk)
			draw_polygon(q, PackedColorArray([b, b, a, a]))
			draw_colored_polygon(_quad(v[0], v[1], h * 0.3, sk * 0.3), Color(1, 1, 1, 0.35))
		for i in range(1, ticks):
			var x := w * i / float(ticks)
			draw_line(Vector2(x + sk, 0), Vector2(x, h), Color(0, 0, 0, 0.3), 1.5)


class Diamonds extends Control:
	var n := 0
	var mirror := false
	func _draw() -> void:
		for i in 2:
			var cx := 8.0 + i * 20.0
			if mirror: cx = size.x - cx
			var pts := PackedVector2Array([Vector2(cx, 0), Vector2(cx + 7, 7), Vector2(cx, 14), Vector2(cx - 7, 7)])
			if i < n:
				draw_colored_polygon(pts, Color(1, 0.81, 0.35))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.87, 0.9, 0.95), 2.0)


class Hex extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(w * 0.14, 0), Vector2(w * 0.86, 0), Vector2(w, h / 2), Vector2(w * 0.86, h), Vector2(w * 0.14, h), Vector2(0, h / 2)])
		draw_colored_polygon(pts, Color(0.06, 0.08, 0.13, 0.95))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.15), 2.0)


class Stripes extends Control:
	## Slow-moving diagonal light bands in the two player colors.
	var a := Color(0.66, 0.4, 1.0, 0.05)
	var b := Color(0.13, 0.78, 0.92, 0.045)
	var t := 0.0
	func _process(dt: float) -> void:
		t += dt
		queue_redraw()
	func _draw() -> void:
		var h := size.y
		var step := 110.0
		var x := -h + fmod(t * 35.0, step * 2.0) - step * 2.0
		var i := 0
		while x < size.x + h:
			var c := a if i % 2 == 0 else b
			var w := step * (0.35 if i % 3 else 0.12)
			draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w - h * 0.55, h), Vector2(x - h * 0.55, h)]), c)
			x += step
			i += 1


class Radar extends Control:
	## Five-axis stat chart that animates toward its target values.
	var vals := [0.5, 0.5, 0.5, 0.5, 0.5]
	var shown := [0.0, 0.0, 0.0, 0.0, 0.0]
	var names := ["POWER", "SPEED", "HEALTH", "REACH", "TECHNIQUE"]
	var accent := Color.WHITE
	var font: Font
	func _process(_dt: float) -> void:
		for i in 5:
			shown[i] = lerpf(shown[i], vals[i], 0.15)
		queue_redraw()
	func _pt(i: int, r: float) -> Vector2:
		var ang := -PI / 2 + TAU * i / 5.0
		return size / 2 + Vector2(cos(ang), sin(ang)) * r
	func _draw() -> void:
		var R := minf(size.x, size.y) * 0.34
		for ring in [0.33, 0.66, 1.0]:
			var pts := PackedVector2Array()
			for i in 6:
				pts.append(_pt(i % 5, R * ring))
			draw_polyline(pts, Color(1, 1, 1, 0.14), 1.5)
		for i in 5:
			draw_line(size / 2, _pt(i, R), Color(1, 1, 1, 0.1), 1.0)
		var poly := PackedVector2Array()
		for i in 5:
			poly.append(_pt(i, R * clampf(shown[i], 0.08, 1.0)))
		draw_colored_polygon(poly, Color(accent, 0.32))
		poly.append(poly[0])
		draw_polyline(poly, accent, 2.5, true)
		for i in 5:
			draw_circle(poly[i], 3.5, accent)
			var s: String = names[i]
			var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, _pt(i, R + 18) - Vector2(w / 2, -5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.8, 0.88))


class SkewCard extends Control:
	## Slanted portrait card; rises and glows when a player's cursor is on it.
	var accent := Color.WHITE
	var tex: Texture2D
	var title := ""
	var font: Font
	var hl := [false, false]
	var locked := [false, false]
	var pop := 0.0
	func _process(_dt: float) -> void:
		pop = lerpf(pop, 1.0 if (hl[0] or hl[1]) else 0.0, 0.22)
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var sk := 24.0
		var up := -16.0 * pop
		var poly := PackedVector2Array([Vector2(sk, up), Vector2(w, up), Vector2(w - sk, h + up), Vector2(0, h + up)])
		if pop > 0.05:
			var glow := Color(accent, 0.25 * pop)
			draw_polyline(poly + PackedVector2Array([poly[0]]), glow, 12.0)
		draw_colored_polygon(poly, Color(0.05, 0.07, 0.12))
		if tex != null:
			var uv := PackedVector2Array()
			for p in poly:
				uv.append(Vector2(0.08 + p.x / w * 0.84, 0.02 + (p.y - up) / h * 0.9))
			var shade := 0.55 + 0.45 * pop
			draw_polygon(poly, PackedColorArray([Color(shade, shade, shade)]), uv, tex)
		else:
			var q := "?"
			var qw := font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
			draw_string(font, Vector2((w - qw) / 2, h * 0.6 + up), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(0.45, 0.5, 0.62))
		var band := PackedVector2Array([Vector2(sk * 0.17, h - 26 + up), Vector2(w - sk * 0.83, h - 26 + up), Vector2(w - sk, h + up), Vector2(0, h + up)])
		draw_colored_polygon(band, Color(0.02, 0.03, 0.06, 0.9))
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2((w - sk - tw) / 2, h - 8 + up), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 0.95, 1.0))
		draw_line(poly[0], poly[1], accent, 4.0)
		var bc := Color(0.16, 0.2, 0.3)
		if hl[0] and hl[1]: bc = Color(0.65, 0.6, 1.0)
		elif hl[0]: bc = Color(0.18, 0.9, 1.0)
		elif hl[1]: bc = Color(1.0, 0.3, 0.42)
		draw_polyline(poly + PackedVector2Array([poly[0]]), bc, 3.0 if (hl[0] or hl[1]) else 1.5)
		for s in 2:
			if not hl[s]: continue
			var tc := Color(0.18, 0.9, 1.0) if s == 0 else Color(1.0, 0.3, 0.42)
			var tag := ("1P" if s == 0 else "2P") + (" ✔" if locked[s] else "")
			var x := sk + 4.0 if s == 0 else w - 46.0
			draw_rect(Rect2(Vector2(x, up - 20), Vector2(42, 17)), tc)
			draw_string(font, Vector2(x + 5, up - 7), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.02, 0.03, 0.05))


# ---------------------------------------------------------------- build
func build() -> void:
	F_TITLE = _font("res://assets/fonts/RussoOne-Regular.ttf")
	F_BODY = _font("res://assets/fonts/Rajdhani-Bold.ttf")
	F_MED = _font("res://assets/fonts/Rajdhani-Medium.ttf")
	# Symbols (arrows, check marks, diamonds) come from DejaVu: web builds have no system font fallback.
	var sym := _font("res://assets/fonts/DejaVuSans-Bold.ttf")
	for f in [F_TITLE, F_BODY, F_MED]:
		f.fallbacks = [sym]
	root = full(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_hud()
	flash = full(ColorRect.new())
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	ann = lbl("", 96, F_TITLE, Color.WHITE, 14)
	ann.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ann.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(ann)
	ann.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ann.modulate.a = 0
	screen = full(Control.new())
	root.add_child(screen)
	# On-screen controls on phones / tablets (or forced with --touch for testing on desktop).
	touch_enabled = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args() or "--phone" in OS.get_cmdline_user_args()
	if touch_enabled:
		# keep the left thumb zone clear: training info goes under the health bars instead
		train_panel.anchor_top = 0; train_panel.anchor_bottom = 0
		train_panel.offset_top = 100; train_panel.offset_bottom = 290
	touch = TouchControls.new()
	touch.font = F_TITLE
	touch.visible = false
	touch.pause_pressed.connect(func(): if view == "game" and not G.paused: show_pause())
	root.add_child(touch)
	if touch_enabled:
		nav_back = big_btn("◀  BACK", Color(0.55, 0.62, 0.75), _nav_back)
		root.add_child(nav_back)
		nav_back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		nav_back.position = Vector2(18, 16)
		nav_ok = big_btn("CONFIRM  ✔", GOLD, _nav_ok)
		root.add_child(nav_ok)
		nav_ok.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		nav_ok.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		nav_ok.grow_vertical = Control.GROW_DIRECTION_BEGIN
		nav_ok.offset_right = -18; nav_ok.offset_bottom = -16
		nav_back.visible = false; nav_ok.visible = false


## A large, skewed touch button.
func big_btn(text: String, accent: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", F_TITLE)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.02, 0.03, 0.05))
	b.add_theme_color_override("font_pressed_color", Color(0.02, 0.03, 0.05))
	b.add_theme_color_override("font_hover_color", Color(0.02, 0.03, 0.05))
	b.custom_minimum_size = Vector2(190, 76)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := sbox(accent if st != "pressed" else accent.lightened(0.35), Color(1, 1, 1, 0.5), 2, 0.25)
		sb.content_margin_left = 26; sb.content_margin_right = 30
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func(): G.sfx("ok"); cb.call())
	return b


func _process(_dt: float) -> void:
	_process_online()
	if nav_back == null: return
	var menus := ["diff", "select", "stage", "moves", "info", "online", "ladder", "race_tracks", "ops_setup"]
	nav_back.visible = view in menus
	nav_ok.visible = view in ["select", "stage"]
	if view == "stage": nav_ok.text = "FIGHT!  ✔"
	elif view == "select" and sel != null: nav_ok.text = "CONFIRM  ✔"


func _nav_back() -> void:
	match view:
		"select": if sel != null: _select_back(_active_side())
		"stage": show_select(stage_sel.cfg)
		_: _back()


func _nav_ok() -> void:
	match view:
		"select": if sel != null: _select_confirm(_active_side())
		"stage": _stage_confirm()


func _build_hud() -> void:
	hud = full(Control.new())
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)
	for i in 2:
		var p := Control.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(p)
		if i == 0:
			p.anchor_left = 0; p.anchor_right = 0.5; p.offset_left = 16; p.offset_right = -70
		else:
			p.anchor_left = 0.5; p.anchor_right = 1; p.offset_left = 70; p.offset_right = -16
		p.offset_top = 12; p.offset_bottom = 90
		var por := Panel.new()
		por.add_theme_stylebox_override("panel", sbox(Color(0.04, 0.06, 0.12), P1C if i == 0 else P2C, 2, 0.15 if i == 0 else -0.15))
		por.clip_contents = true
		por.size = Vector2(66, 66)
		p.add_child(por)
		var img := TextureRect.new()
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.size = Vector2(76, 76); img.position = Vector2(-5, -2)
		img.flip_h = i == 1
		por.add_child(img)
		var nm := lbl("", 24, F_TITLE, INK, 6)
		var sty := lbl("", 14, F_BODY, DIM)
		var bar := Bar.new()
		bar.mirror = i == 1
		bar.a = Color(0.25, 0.85, 1.0) if i == 0 else Color(1.0, 0.36, 0.49)
		bar.b = Color(0.85, 0.97, 1.0) if i == 0 else Color(1.0, 0.88, 0.9)
		var surge := Bar.new()
		surge.mirror = i == 1
		surge.ticks = 4
		surge.a = Color(0.48, 0.36, 1.0) if i == 0 else Color(1.0, 0.6, 0.24)
		surge.b = Color(0.18, 0.9, 1.0) if i == 0 else Color(1.0, 0.3, 0.42)
		var dia := Diamonds.new()
		dia.mirror = i == 1
		for c in [nm, sty, bar, surge, dia]:
			p.add_child(c)
		plates.append({root = p, por = por, img = img, nm = nm, sty = sty, bar = bar, surge = surge, dia = dia})
		p.resized.connect(_layout_plate.bind(i))
		_layout_plate.call_deferred(i)
	var clock := Control.new()
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(clock)
	clock.anchor_left = 0.5; clock.anchor_right = 0.5; clock.offset_left = -50; clock.offset_right = 50; clock.offset_top = 10; clock.offset_bottom = 80
	var hx := Hex.new(); hx.size = Vector2(100, 56)
	clock.add_child(hx)
	timer_lbl = lbl("60", 44, F_TITLE, INK, 8)
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_lbl.size = Vector2(100, 56); timer_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clock.add_child(timer_lbl)
	round_lbl = lbl("ROUND 1", 13, F_BODY, DIM)
	round_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_lbl.size = Vector2(100, 16); round_lbl.position = Vector2(0, 58)
	clock.add_child(round_lbl)
	for i in 2:
		var c := lbl("", 64, F_TITLE, GOLD, 10)
		hud.add_child(c)
		c.anchor_top = 0.28; c.anchor_bottom = 0.28
		if i == 0:
			c.anchor_left = 0.03; c.anchor_right = 0.03
		else:
			c.anchor_left = 0.97; c.anchor_right = 0.97; c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.modulate.a = 0
		combo.append(c)
		var p := lbl("", 26, F_TITLE, GOLD, 8)
		hud.add_child(p)
		p.anchor_top = 0.2; p.anchor_bottom = 0.2
		if i == 0:
			p.anchor_left = 0.05; p.anchor_right = 0.05
		else:
			p.anchor_left = 0.95; p.anchor_right = 0.95; p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		p.modulate.a = 0
		pops.append(p)
	hint = rich(15)
	hint.add_theme_color_override("default_color", DIM)
	hud.add_child(hint)
	hint.anchor_left = 0; hint.anchor_right = 1; hint.anchor_top = 1; hint.anchor_bottom = 1
	hint.offset_top = -30; hint.offset_bottom = -6
	train_panel = PanelContainer.new()
	var tps := sbox(Color(0.03, 0.05, 0.09, 0.88), P1C, 0)
	tps.border_width_left = 3
	train_panel.add_theme_stylebox_override("panel", tps)
	hud.add_child(train_panel)
	train_panel.anchor_top = 1; train_panel.anchor_bottom = 1
	train_panel.offset_left = 16; train_panel.offset_top = -230; train_panel.offset_right = 760; train_panel.offset_bottom = -40
	train = rich(16)
	train.fit_content = true
	train_panel.add_child(train)


func _layout_plate(i: int) -> void:
	var p: Dictionary = plates[i]
	var w: float = p.root.size.x
	var r := i == 1
	var x0 := 0.0 if not r else w - 66.0
	p.por.position = Vector2(x0, 0)
	var bx := 80.0 if not r else 0.0
	var bw := w - 80.0
	p.nm.position = Vector2(bx if not r else 0, -2)
	p.nm.size = Vector2(bw, 30)
	p.nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if r else HORIZONTAL_ALIGNMENT_LEFT
	p.sty.position = Vector2(bx, 4) if not r else Vector2(0, 4)
	p.sty.size = Vector2(bw, 20)
	p.sty.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if r else HORIZONTAL_ALIGNMENT_RIGHT
	p.bar.position = Vector2(bx + 10, 30); p.bar.size = Vector2(bw - 20, 24)
	p.surge.position = Vector2(bx + (bw * 0.45 if r else 50.0), 62); p.surge.size = Vector2(bw * 0.5, 9)
	p.dia.position = Vector2(bx if not r else bw - 40, 59); p.dia.size = Vector2(40, 16)


func show_hud(g) -> void:
	for i in 2:
		var C: Dictionary = g.F[i].C
		var p: Dictionary = plates[i]
		p.nm.text = C.name
		p.sty.text = ("CPU · " + ["EASY", "NORMAL", "HARD", "BOSS"][g.cfg.lv]) if (i == 1 and g.mode == "cpu") else C.style.split("—")[0].strip_edges().to_upper()
		p.img.texture = g.portraits.get(C.id)
		(p.por.get_theme_stylebox("panel") as StyleBoxFlat).border_color = C.accent
	hint.text = "" if touch_enabled else "[center]" + ("P1 [b]WASD[/b] + [b]U I J K[/b]   ·   P2 [b]Arrows[/b] + [b]Num 4 5 1 2[/b]   ·   [b]Esc[/b] pause" if g.mode == "2p" \
		else "[b]WASD[/b] move   ·   [b]U[/b] 1   [b]I[/b] 2   [b]J[/b] 3   [b]K[/b] 4   ·   tap [b]W[/b]/[b]S[/b] sidestep   ·   [b]Esc[/b] pause & move list") + "[/center]"
	train_panel.visible = g.mode == "training"
	hud.visible = true
	view = "game"
	for i in 2: _layout_plate(i)


func hide_hud() -> void:
	hud.visible = false


func set_round_label(t: String) -> void:
	round_lbl.text = t


func update_hud(g) -> void:
	var want_touch: bool = touch_enabled and view == "game" and not g.paused
	if touch.visible != want_touch:
		touch.visible = want_touch
		touch.reset()
	for i in 2:
		var f: Fighter = g.F[i]
		var p: Dictionary = plates[i]
		var v := f.hp / f.max_hp * 100.0
		chip[i] = (maxf(v, chip[i] - 0.5) if (f.combo_hits == 0 and f.state != "air") else chip[i]) if chip[i] > v else v
		p.bar.value = v / 100.0
		p.bar.chip = chip[i] / 100.0
		p.bar.low = v < 25.0
		p.surge.value = f.meter / 100.0
		p.surge.chip = 0.0
		p.surge.low = f.meter >= 100.0
		p.dia.n = 0 if g.mode == "training" else g.wins[i]
		p.dia.queue_redraw()
		var o: Fighter = g.F[1 - i]
		if o.combo_hits >= 2:
			combo[i].text = "%d HITS\n%d DMG" % [o.combo_hits, o.combo_dmg]
			combo_t[i] = 80
			if o.combo_hits > combo_last[i]:
				# Punch the counter on every new hit.
				combo[i].pivot_offset = Vector2(0 if i == 0 else combo[i].size.x, combo[i].size.y * 0.3)
				combo[i].scale = Vector2(1.35, 1.35)
				create_tween().tween_property(combo[i], "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif combo_last[i] >= 3 and o.combo_hits == 0:
			var n: int = combo_last[i]
			var rating := "INCREDIBLE!" if n >= 9 else "AMAZING!" if n >= 7 else "GREAT!" if n >= 5 else "NICE!"
			combo[i].text += "\n" + rating
			combo_t[i] = 70
		combo_last[i] = o.combo_hits
		if combo_t[i] > 0:
			combo_t[i] -= 1
			combo[i].modulate.a = 1.0
		else:
			combo[i].modulate.a = move_toward(combo[i].modulate.a, 0.0, 0.1)
	timer_lbl.text = "∞" if g.mode == "training" else str(g.time_left)
	timer_lbl.label_settings.font_color = Color(1, 0.42, 0.42) if (g.mode != "training" and g.time_left <= 10) else INK
	if g.mode == "training":
		_update_train(g)
	var pads := Input.get_connected_joypads()
	var st := not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_START)
	if st and not pad_start and g.phase != "end":
		toggle_pause()
	pad_start = st


func _update_train(g) -> void:
	var sg := func(v) -> String:
		if typeof(v) == TYPE_STRING: return "[b]%s[/b]" % v
		var n := int(v)
		return "[b][color=%s]%s%d[/color][/b]" % ["#6bffb0" if n >= 0 else "#ff6b81", "+" if n > 0 else "", n]
	var t := "[color=#2ee6ff][b]TRAINING[/b][/color]     Dummy: [b]%s[/b] [T]     Reset [R]\n" % G.DUMMY[g.dummy]
	if g.fd != null:
		var m: Data.Move = g.fd.m
		t += "%s  [b]%s[/b]  %s\n" % [cmd_bb(m.key, g.F[0].C), m.name, lvl_bb(m.lvl)]
		var on_hit := "THROW" if m.is_throw else "LAUNCH" if m.launch else "KND" if m.kd else sg.call(m.hit if m.hit != null else 0)
		t += "Startup [b]i%d[/b]   Active [b]%d[/b]   Recovery [b]%d[/b]   Block %s   Hit %s" % [m.s, m.a, m.r, "—" if m.blk == null else sg.call(m.blk), on_hit]
		if g.fd.res != "":
			t += "\nResult: [b]%s[/b]   Measured advantage: %s" % [g.fd.res, sg.call(g.fd.adv) if g.fd.adv != null else "…"]
	else:
		t += "Do a move to see its frame data."
	if not g.trials.is_empty():
		var tr: Dictionary = g.trials[g.trial_i]
		var steps: Array = []
		for j in tr.keys.size():
			var col := "#6bffb0" if j < g.trial_step else "#ffcf5a" if j == g.trial_step else "#8e9bb0"
			steps.append("[color=%s]%s[/color]" % [col, cmd_bb(tr.keys[j], g.F[0].C) if j >= g.trial_step else "✔ " + g.F[0].C.moves[tr.keys[j]].name])
		t += "\n\n[color=#ffcf5a][b]COMBO TRIAL %d/%d — %s[/b][/color]%s   [C] next trial\n" % [g.trial_i + 1, g.trials.size(), tr.name.to_upper(), "  [color=#6bffb0]✔ CLEARED[/color]" if g.trial_done.get(g.trial_i, false) else ""]
		t += "  →  ".join(steps)
	if train.text != t:
		train.text = t


# ---------------------------------------------------------------- notation
const ARROW := {f = "→", b = "←", d = "↓", df = "↘", db = "↙", uf = "↗"}


func cmd_bb(key: String, C: Dictionary) -> String:
	var btn := func(c: String) -> String:
		return "[bgcolor=%s][color=#06101a][b] %s [/b][/color][/bgcolor]" % ["#7fe3ff" if c in ["1", "2"] else "#ffb35c", c]
	if key == "34":
		return btn.call("3") + "+" + btn.call("4") + " [color=#8e9bb0](full Surge)[/color]"
	var out := ""
	var k := key
	if ":" in k:
		var parts := k.split(":")
		out += "[bgcolor=#5b2a8a][b] %s [/b][/bgcolor] " % C.stances[parts[0]].name.to_upper()
		k = parts[1]
	var segs: Array = []
	for seg in k.split(","):
		var s := seg
		var o := ""
		if s.begins_with("ff"):
			o += "[b]→→[/b] "; s = s.substr(2)
		elif s.begins_with("ws"):
			o += "[bgcolor=#2a3550][b] WS [/b][/bgcolor] "; s = s.substr(2)
		for p in ["df", "db", "uf", "d", "b", "f"]:
			if s.begins_with(p):
				o += "[b]%s[/b] " % ARROW[p]; s = s.substr(p.length()); break
		var bs: Array = []
		for c in s:
			bs.append(btn.call(c))
		o += "+".join(bs)
		segs.append(o)
	return out + " , ".join(segs)


func lvl_bb(l: String) -> String:
	var c: String = {high = "#ffcf5a", mid = "#2ee6ff", low = "#ff6b81", throw = "#c39bff"}.get(l, "#ffffff")
	return "[color=%s][b]%s[/b][/color]" % [c, l.to_upper()]


# ---------------------------------------------------------------- effects
func announce(text: String, kind: String) -> void:
	if G.resim: return
	ann.text = text
	ann.label_settings.font_color = Color(1, 0.3, 0.42) if kind == "ko" else GOLD if kind == "fight" else Color.WHITE
	ann.reset_size()
	ann.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ann.pivot_offset = ann.size / 2
	var tw := create_tween()
	ann.modulate.a = 0
	ann.scale = Vector2(2.2, 0.4)
	tw.tween_property(ann, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(ann, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(ann, "modulate:a", 0.0, 0.3)


func pop_text(text: String, side: int) -> void:
	if G.resim: return
	var p: Label = pops[side]
	p.text = text
	var tw := create_tween()
	p.modulate.a = 1.0
	p.scale = Vector2(1.3, 1.3)
	tw.tween_property(p, "scale", Vector2.ONE, 0.15)
	tw.tween_interval(0.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)


func screen_flash(c: Color) -> void:
	if G.resim: return
	flash.color = Color(c, 0.6)
	create_tween().tween_property(flash, "color:a", 0.0, 0.6)


# ---------------------------------------------------------------- screens
func clear_screen() -> void:
	for c in screen.get_children():
		c.queue_free()
	sel = null
	info.clear()


func hide_screen() -> void:
	clear_screen()
	screen.visible = false


func _focus_first(box: Control) -> void:
	for c in box.get_children():
		if c is Button:
			c.call_deferred("grab_focus")
			return


func _menu_list(items: Array) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	for it in items:
		var b := menu_btn(it[0], it[1], it[2] if it.size() > 2 else 26)
		if it.size() > 3:
			b.focus_entered.connect(func(): if desc_lbl: desc_lbl.text = it[3])
		v.add_child(b)
	return v


const MENU_DESC := [
	"The fighting game: Arcade up to the CEO, versus, online rooms and training.",
	"BNB Rush Hour: a ten-car street race. Grab pickups, throw them at rivals, unleash your power.",
	"BNB Office Ops: team deathmatch, 1v1 up to 4v4. Pick a gun, wear a vest, hold the office.",
	"Hit levels, frame advantage, sidesteps, juggles, throws and Surge Arts, explained.",
	"Keyboard and gamepad layouts for both players.",
	"Close the game.",
]
const CLASH_DESC := [
	"Climb the office ladder: four colleagues, then HR, the PM, and the CEO himself.",
	"Fight the computer. Pick a difficulty, choose your fighter, best of three rounds.",
	"Two players on one keyboard or with two gamepads.",
	"Play a friend over the internet with a room code, or on the same Wi-Fi.",
	"Practice against a dummy. Live frame data shows startup, block and hit advantage.",
	"Back to the main menu.",
]


func show_title() -> void:
	clear_screen(); screen.visible = true; view = "title"
	G.leave_game() if not G.F.is_empty() else null
	G.set_stage("open_office")
	var a: Dictionary = Data.ROSTER.pick_random()
	var b: Dictionary = Data.ROSTER.filter(func(c): return c != a).pick_random()
	G.set_preview(0, a); G.set_preview(1, b)
	screen.add_child(full(Stripes.new()))
	var bg := full(hgrad(Color(0.02, 0.03, 0.06, 0.97), Color(0.02, 0.03, 0.06, 0.0)))
	bg.anchor_right = 0.62
	screen.add_child(bg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	screen.add_child(col)
	col.position = Vector2(110, 90) if not touch_enabled else Vector2(90, 24)
	var logo_size := 118 if not touch_enabled else 80   # phones: room for the bigger menu buttons
	# logo with a split cyan/pink "chromatic" shadow
	for word in ["BNB", "CLASHES"]:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(700, logo_size)
		for layer in [[Vector2(-5, 3), P1C], [Vector2(5, -3), P2C], [Vector2.ZERO, Color.WHITE]]:
			var l := lbl(word, logo_size, F_TITLE, layer[1], 0 if layer[1] != Color.WHITE else 14)
			l.label_settings.shadow_size = 0
			if layer[1] != Color.WHITE:
				l.modulate.a = 0.75
			l.position = layer[0]
			holder.add_child(l)
		col.add_child(holder)
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", sbox(GOLD, Color(0, 0, 0, 0), 0, 0.35))
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.add_child(lbl("FIGHT  ·  RACE  ·  SHOOT  ·  ONE OFFICE", 17, F_TITLE, Color(0.04, 0.05, 0.08)))
	col.add_child(tag)
	var wm := TextureRect.new()
	wm.texture = load("res://assets/brand/bnb_wordmark_light.png")
	wm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	wm.custom_minimum_size = Vector2(300, 46 if not touch_enabled else 34)
	wm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(wm)
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 34 if not touch_enabled else 12); col.add_child(sp)
	var labels := ["CLASH  ·  FIGHT", "RUSH HOUR  ·  RACE", "OFFICE OPS  ·  SHOOT", "HOW TO PLAY", "CONTROLS", "QUIT"]
	var cbs := [show_clash_menu, func(): show_select({mode = "race"}), func(): show_select({mode = "ops"}), show_how, show_controls, func(): G.get_tree().quit()]
	var items: Array = []
	for i in labels.size():
		items.append(["%02d   %s" % [i + 1, labels[i]], cbs[i], 28, MENU_DESC[i]])
	var m := _menu_list(items)
	col.add_child(m)
	desc_lbl = lbl(MENU_DESC[0], 20, F_MED, Color(0.79, 0.83, 0.88))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.custom_minimum_size = Vector2(460, 60)
	var sp2 := Control.new(); sp2.custom_minimum_size = Vector2(0, 18); col.add_child(sp2)
	col.add_child(desc_lbl)
	if touch_enabled:
		sp2.visible = false; desc_lbl.visible = false
		for btn in m.get_children(): btn.custom_minimum_size.y = 45
	# staggered slide-in
	var i := 0
	for btn in m.get_children():
		btn.modulate.a = 0.0
		var tw := btn.create_tween()
		tw.tween_interval(0.06 * i)
		tw.tween_property(btn, "modulate:a", 1.0, 0.25)
		i += 1
	# featured matchup card (bottom right)
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_END
	place(card, screen, Control.PRESET_BOTTOM_RIGHT, Vector2(-520, -150))
	card.custom_minimum_size = Vector2(480, 0)
	var fl := lbl("FEATURED MATCH", 14, F_BODY, DIM)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(fl)
	var mv := RichTextLabel.new()
	mv.bbcode_enabled = true; mv.fit_content = true; mv.scroll_active = false
	mv.add_theme_font_override("normal_font", F_TITLE)
	mv.add_theme_font_size_override("normal_font_size", 30)
	mv.text = "[right][color=#%s]%s[/color]  [color=#ffcf5a]VS[/color]  [color=#%s]%s[/color][/right]" % [a.accent.to_html(false), a.name, b.accent.to_html(false), b.name]
	card.add_child(mv)
	var st := lbl("%s  ·  %s" % [a.style.split("—")[0].strip_edges(), b.style.split("—")[0].strip_edges()], 16, F_BODY, DIM)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(st)
	var foot := lbl("↑↓ / W S  select    ·    Enter / U  confirm    ·    Esc / J  back", 15, F_BODY, DIM)
	place(foot, screen, Control.PRESET_BOTTOM_LEFT, Vector2(110, -34))
	foot.visible = not touch_enabled
	_focus_first(m)


func show_difficulty() -> void:
	clear_screen(); screen.visible = true; view = "diff"
	var bg := full(hgrad(Color(0.02, 0.03, 0.06, 0.95), Color(0.02, 0.03, 0.06, 0.0)))
	bg.anchor_right = 0.75
	screen.add_child(bg)
	var col := VBoxContainer.new()
	screen.add_child(col)
	col.position = Vector2(110, 160)
	col.add_child(lbl("CPU LEVEL", 72, F_TITLE, Color(0.45, 0.6, 1.0), 12))
	var m := _menu_list([
		["EASY", func(): show_select({mode = "cpu", lv = 0}), 26, "Slow reactions, rarely blocks lows. Good for exploring move lists."],
		["NORMAL", func(): show_select({mode = "cpu", lv = 1}), 26, "Blocks, punishes sometimes, uses strings and launchers."],
		["HARD", func(): show_select({mode = "cpu", lv = 2}), 26, "Reads lows, sidesteps linear moves, punishes almost everything."],
		["BACK", show_clash_menu, 20, "Back to the CLASH menu."]])
	m.set_meta("back", show_clash_menu)
	col.add_child(m)
	desc_lbl = lbl("", 20, F_MED, Color(0.79, 0.83, 0.88))
	desc_lbl.custom_minimum_size = Vector2(440, 60)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(desc_lbl)
	_focus_first(m)


# ---- character select
var card_list: Array = []   # SkewCard per roster index (0..7) + random (8)
var side_ui: Array = []


func _stats(C: Dictionary) -> Array:
	var reach := 0.0
	var n := 0
	for m in C.moves.values():
		if not m.is_throw and not m.trans:
			reach += m.range; n += 1
	return [(C.power - 0.8) / 0.45, (C.speed - 0.8) / 0.4, (C.hp - 150.0) / 50.0, (reach / maxf(1, n) - 1.0) / 0.18, C.diff / 3.0]


func _signature(C: Dictionary) -> Data.Move:
	for m in C.moves.values():
		if m.sig: return m
	return C.moves["34"]


func show_select(c: Dictionary) -> void:
	clear_screen(); screen.visible = true; view = "select"
	sel = {cfg = c, cur = [0, 1], locked = [false, false], cos = [0, 0]}
	card_list.clear(); side_ui.clear()
	screen.add_child(full(Stripes.new()))
	var top := full(vgrad(Color(0.02, 0.03, 0.06, 0.9), Color(0.02, 0.03, 0.06, 0.0)))
	top.anchor_bottom = 0.22
	screen.add_child(top)
	var bot := full(vgrad(Color(0.02, 0.03, 0.06, 0.0), Color(0.02, 0.03, 0.06, 0.97)))
	bot.anchor_top = 0.55
	screen.add_child(bot)
	for s in 2:
		var edge := full(hgrad(Color(0.02, 0.03, 0.06, 0.85), Color(0.02, 0.03, 0.06, 0.0)) if s == 0 else hgrad(Color(0.02, 0.03, 0.06, 0.0), Color(0.02, 0.03, 0.06, 0.85)))
		edge.anchor_left = 0.0 if s == 0 else 0.7; edge.anchor_right = 0.3 if s == 0 else 1.0
		screen.add_child(edge)
	# banner
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", sbox(Color(0.04, 0.06, 0.11, 0.92), Color(1, 1, 1, 0.12), 1, 0.3))
	place(banner, screen, Control.PRESET_CENTER_TOP, Vector2(-250, 16))
	banner.custom_minimum_size = Vector2(500, 0)
	var bv := VBoxContainer.new()
	banner.add_child(bv)
	var t := lbl("SELECT YOUR FIGHTER", 30, F_TITLE, INK, 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(t)
	var sub := lbl({"cpu": "VS CPU  ·  " + ["EASY", "NORMAL", "HARD", "BOSS"][c.get("lv", 1)], "2p": "VERSUS  ·  LOCAL", "training": "TRAINING", "arcade": "ARCADE  ·  CLIMB TO THE CEO", "race": "RUSH HOUR  ·  PICK YOUR DRIVER", "ops": "OFFICE OPS  ·  PICK YOUR OPERATOR", "online": "ONLINE  ·  " + ("WI-FI" if G.net.via == "lan" else "ROOM " + G.net.code)}[c.mode], 14, F_BODY, GOLD)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(sub)
	# per-side info: watermark, name plate, radar, signature
	for s in 2:
		var right := s == 1
		var al := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
		var wm := lbl("", 190, F_TITLE, Color(1, 1, 1, 0.05))
		wm.label_settings.shadow_size = 0
		screen.add_child(wm)
		wm.position = Vector2(30 if not right else 900, 250)
		wm.rotation = -0.08
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.custom_minimum_size = Vector2(380, 0)
		place(v, screen, Control.PRESET_TOP_RIGHT if right else Control.PRESET_TOP_LEFT, Vector2(-430, 120) if right else Vector2(50, 120))
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_SHRINK_END if right else Control.SIZE_SHRINK_BEGIN
		var chip_l := lbl("", 15, F_TITLE, Color(0.02, 0.03, 0.05))
		chip.add_child(chip_l)
		v.add_child(chip)
		var nm := lbl("", 44, F_TITLE, INK, 10)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD
		nm.custom_minimum_size = Vector2(380, 0)
		var ti := lbl("", 22, F_BODY, Color(0.85, 0.88, 0.93))
		var org := lbl("", 14, F_BODY, DIM)
		var sty := lbl("", 17, F_MED, Color(0.79, 0.83, 0.88))
		sty.autowrap_mode = TextServer.AUTOWRAP_WORD
		for x in [nm, ti, org, sty]:
			x.horizontal_alignment = al
			v.add_child(x)
		var radar := Radar.new()
		radar.font = F_BODY
		radar.custom_minimum_size = Vector2(300, 250)
		radar.size_flags_horizontal = Control.SIZE_SHRINK_END if right else Control.SIZE_SHRINK_BEGIN
		v.add_child(radar)
		var sig := rich(17)
		sig.custom_minimum_size = Vector2(380, 0)
		v.add_child(sig)
		var dif := lbl("", 15, F_BODY, GOLD)
		dif.horizontal_alignment = al
		v.add_child(dif)
		var cos_l := lbl("", 18, F_TITLE, INK, 6)
		cos_l.horizontal_alignment = al
		cos_l.mouse_filter = Control.MOUSE_FILTER_STOP   # tap / click to change outfit
		var side := s
		cos_l.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and sel != null:
				_select_move(side, "d"))
		v.add_child(cos_l)
		side_ui.append({wm = wm, box = v, chip = chip, chip_l = chip_l, nm = nm, ti = ti, org = org, sty = sty, radar = radar, sig = sig, dif = dif, cos = cos_l, right = right})
	# card strip
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", -10)
	screen.add_child(strip)
	strip.anchor_left = 0.5; strip.anchor_right = 0.5; strip.anchor_top = 1; strip.anchor_bottom = 1
	strip.offset_left = -560; strip.offset_right = 560; strip.offset_top = -235; strip.offset_bottom = -72
	# the whole team doesn't fit in one row: two rows of smaller cards
	var N := Data.ROSTER.size()
	var grid := GridContainer.new()
	grid.columns = ceili((N + 1) / 2.0)
	grid.add_theme_constant_override("h_separation", -6)
	grid.add_theme_constant_override("v_separation", 4)
	strip.add_child(grid)
	var cw := clampf(1200.0 / grid.columns, 70.0, 128.0)
	strip.offset_top = strip.offset_bottom - (cw * 1.12 * 2 + 30)   # room for both rows above the help line
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in N + 1:
		var card := SkewCard.new()
		card.custom_minimum_size = Vector2(cw, cw * 1.12)
		card.size_flags_vertical = Control.SIZE_SHRINK_END
		card.font = F_TITLE
		if i < N:
			var C: Dictionary = Data.ROSTER[i]
			card.accent = C.accent; card.tex = G.portraits.get(C.id); card.title = C.person.get("short", C.name)
		else:
			card.accent = Color(0.45, 0.5, 0.62); card.title = "RANDOM"
		card.mouse_entered.connect(func():
			if sel == null: return
			var sd := _active_side()
			if not sel.locked[sd] and sel.cur[sd] != i:
				sel.cur[sd] = i; G.sfx("ui"); _render_select())
		card.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and sel != null:
				var sd := _active_side()
				if sel.locked[sd]: return
				# touch: the first tap previews the fighter, tapping the same card again confirms
				if touch_enabled and sel.get("tapped", -1) != i:
					sel.tapped = i
					if sel.cur[sd] != i: sel.cos[sd] = 0
					sel.cur[sd] = i; G.sfx("ui"); _render_select()
					return
				sel.cur[sd] = i; _select_confirm(sd))
		grid.add_child(card)
		card_list.append(card)
	if touch_enabled:
		# big outfit switcher for the side that is choosing
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		place(row, screen, Control.PRESET_CENTER_BOTTOM, Vector2(0, -355))
		row.grow_horizontal = Control.GROW_DIRECTION_BOTH
		var prev := big_btn("◀", Color(0.24, 0.84, 1.0), func(): _select_move(_active_side(), "u"))
		prev.custom_minimum_size.x = 110
		row.add_child(prev)
		var cos_big := lbl("", 26, F_TITLE, INK, 6)
		cos_big.custom_minimum_size = Vector2(330, 0)
		cos_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(cos_big)
		var nxt := big_btn("▶", Color(0.24, 0.84, 1.0), func(): _select_move(_active_side(), "d"))
		nxt.custom_minimum_size.x = 110
		row.add_child(nxt)
		sel.cos_big = cos_big
		sel.cos_row = row
	var help := lbl("◀ ▶  A D / Arrows  fighter    ·    W S / ↑ ↓  costume    ·    U / Enter  confirm    ·    J / Esc  back" if c.mode != "2p" \
		else "P1   A D fighter · W S costume · U        ·        P2   ◀ ▶ fighter · ↑ ↓ costume · Num4 / O        ·        Esc  back", 15, F_BODY, DIM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place(help, screen, Control.PRESET_CENTER_BOTTOM, Vector2(0, -18))
	help.visible = not touch_enabled
	if touch_enabled:
		for u in side_ui:
			u.radar.visible = false; u.sig.visible = false; u.sty.visible = false; u.cos.visible = false
	_render_select()


func _active_side() -> int:
	if sel.cfg.mode == "online":
		return G.local_side
	if sel.cfg.mode == "2p":
		return 0 if not sel.locked[0] else 1
	return 1 if sel.locked[0] else 0


func _render_select() -> void:
	if sel == null: return
	for card in card_list:
		card.hl = [false, false]
		card.locked = [false, false]
	for s in 2:
		var u: Dictionary = side_ui[s]
		var waiting: bool = (sel.cfg.mode != "2p" and sel.cfg.mode != "online" and s == 1 and not sel.locked[0]) \
			or (sel.cfg.mode in ["race", "ops"] and s == 1) \
			or (sel.cfg.mode == "online" and s != G.local_side and not sel.get("seen", false))
		u.box.visible = not waiting
		if waiting:
			u.wm.text = "?"
			if G.preview[1] != null:
				G.preview[1].rig.queue_free(); G.preview[1] = null
			continue
		var idx: int = sel.cur[s]
		card_list[idx].hl[s] = true
		card_list[idx].locked[s] = sel.locked[s]
		if idx == Data.ROSTER.size():
			u.nm.text = "RANDOM"; u.ti.text = "Fate decides"; u.org.text = ""; u.sty.text = ""; u.wm.text = "?"
			u.sig.text = ""; u.dif.text = ""; u.cos.text = ""; u.radar.vals = [0.5, 0.5, 0.5, 0.5, 0.5]; u.radar.accent = Color(0.6, 0.65, 0.75)
			continue
		var C: Dictionary = Data.ROSTER[idx]
		var names: Array = Models.costume_names(C.id)
		sel.cos[s] = clampi(sel.cos[s], 0, names.size() - 1)
		G.set_preview(s, C, sel.cos[s])
		G.preview[s].win = sel.locked[s]
		var keys := "↑↓" if (s == 1 and sel.cfg.mode == "2p") else "W S"
		u.cos.text = ("◀  %s  ▶   %d/%d" % [names[sel.cos[s]].to_upper(), sel.cos[s] + 1, names.size()]) + ("" if sel.locked[s] else "   (" + keys + ")")
		var who := "1P" if s == 0 else ("2P" if sel.cfg.mode in ["2p", "online"] else "CPU" if sel.cfg.mode == "cpu" else "DUMMY")
		if sel.cfg.mode == "online": who = "YOU" if s == G.local_side else "RIVAL"
		u.chip_l.text = "  %s%s  " % [who, "   ·   READY" if sel.locked[s] else ""]
		u.chip.add_theme_stylebox_override("panel", sbox(C.accent, Color(0, 0, 0, 0), 0, 0.35))
		u.nm.text = C.name
		u.ti.text = C.title
		u.org.text = C.origin.to_upper()
		u.sty.text = C.style
		u.wm.text = C.name.split(" ")[0]
		u.radar.vals = _stats(C)
		u.radar.accent = C.accent
		var sm := _signature(C)
		u.sig.text = ("[right]" if u.right else "") + "[color=#8e9bb0]SIGNATURE[/color]   [b]%s[/b]   %s" % [sm.name, cmd_bb(sm.key, C)] + ("[/right]" if u.right else "")
		u.dif.text = "DIFFICULTY   " + "◆".repeat(C.diff) + "◇".repeat(3 - C.diff)
	if sel.has("cos_big"):
		var sd := _active_side()
		var idx2: int = sel.cur[sd]
		sel.cos_row.visible = idx2 < Data.ROSTER.size() and not sel.locked[sd]
		if idx2 < Data.ROSTER.size():
			var names2: Array = Models.costume_names(Data.ROSTER[idx2].id)
			sel.cos_big.text = "OUTFIT:  %s   %d/%d" % [names2[sel.cos[sd]].to_upper(), sel.cos[sd] + 1, names2.size()]


func _select_move(s: int, d: String) -> void:
	if sel.locked[s]: return
	var i: int = sel.cur[s]
	var n_cards := Data.ROSTER.size() + 1
	if d == "l": i = (i + n_cards - 1) % n_cards
	elif d == "r": i = (i + 1) % n_cards
	elif i < n_cards - 1:
		# up / down cycles the costume of the highlighted fighter
		var n: int = Models.costume_names(Data.ROSTER[i].id).size()
		sel.cos[s] = (sel.cos[s] + (n - 1 if d == "u" else 1)) % n
		G.sfx("ui")
		_render_select()
		_net_cursor()
		return
	else:
		return
	if i != sel.cur[s]: sel.cos[s] = 0
	sel.cur[s] = i
	G.sfx("ui")
	_render_select()
	_net_cursor()


## Online: show the opponent which fighter / outfit we're looking at.
func _net_cursor() -> void:
	if sel != null and sel.cfg.mode == "online":
		var s: int = G.local_side
		G.net.send({t = "cur", i = sel.cur[s], cos = sel.cos[s]})


func _select_confirm(s: int) -> void:
	if sel.locked[s]: return
	if sel.cur[s] == Data.ROSTER.size():
		sel.cur[s] = randi_range(0, Data.ROSTER.size() - 1)
		sel.cos[s] = randi_range(0, Models.costume_names(Data.ROSTER[sel.cur[s]].id).size() - 1)
	sel.locked[s] = true
	sel.tapped = -1
	G.sfx("ok")
	if sel.cfg.mode == "online":
		G.net.send({t = "pick", i = sel.cur[s], cos = sel.cos[s]})
		_render_select()
		_online_both_picked()
		return
	if sel.cfg.mode == "ops":
		var oc: Dictionary = Data.ROSTER[sel.cur[0]]
		_render_select()
		get_tree().create_timer(0.5).timeout.connect(func(): show_ops_setup(oc))
		return
	if sel.cfg.mode == "race":
		var rc: Dictionary = Data.ROSTER[sel.cur[0]]
		_render_select()
		get_tree().create_timer(0.5).timeout.connect(func(): show_race_tracks(rc))
		return
	if sel.cfg.mode == "arcade":
		var pc: Dictionary = Data.ROSTER[sel.cur[0]]
		var pcos: int = sel.cos[0]
		_render_select()
		get_tree().create_timer(0.6).timeout.connect(func(): G.start_arcade(pc, pcos))
		return
	if sel.cfg.mode != "2p" and s == 0:
		sel.cur[1] = (sel.cur[0] + randi_range(1, Data.ROSTER.size() - 1)) % Data.ROSTER.size()
	_render_select()
	if sel.locked[0] and sel.locked[1]:
		# Mirror match in the same outfit: give player 2 the next costume so both stay readable.
		if sel.cur[0] == sel.cur[1] and sel.cos[0] == sel.cos[1]:
			sel.cos[1] = (sel.cos[1] + 1) % Models.costume_names(Data.ROSTER[sel.cur[1]].id).size()
		var c: Dictionary = sel.cfg.duplicate()
		c.costumes = sel.cos.duplicate()
		var p := [Data.ROSTER[sel.cur[0]], Data.ROSTER[sel.cur[1]]]
		get_tree().create_timer(0.6).timeout.connect(func(): show_stage(c, p))


func _select_back(s: int) -> void:
	if sel.cfg.mode == "online":
		if sel.locked[s]:
			sel.locked[s] = false; G.net.send({t = "unpick"}); _render_select()
		else:
			leave_online()
		return
	if sel.locked[s]:
		sel.locked[s] = false; _render_select(); return
	if sel.cfg.mode != "2p" and sel.locked[0]:
		sel.locked[0] = false; _render_select(); return
	show_title()


# ---- stage select (the real stage loads live behind the menu)
var stage_sel := {}


func show_stage(c: Dictionary, p: Array) -> void:
	clear_screen(); screen.visible = true; view = "stage"
	stage_sel = {cfg = c, picks = p, i = 0, cards = []}
	var cos: Array = c.get("costumes", [0, 0])
	G.set_preview(0, p[0], cos[0]); G.set_preview(1, p[1], cos[1])
	G.preview[0].win = false; G.preview[1].win = false
	var bot := full(vgrad(Color(0.02, 0.03, 0.06, 0.0), Color(0.02, 0.03, 0.06, 0.95)))
	bot.anchor_top = 0.55
	screen.add_child(bot)
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", sbox(Color(0.04, 0.06, 0.11, 0.92), Color(1, 1, 1, 0.12), 1, 0.3))
	place(banner, screen, Control.PRESET_CENTER_TOP, Vector2(-220, 16))
	banner.custom_minimum_size = Vector2(440, 0)
	var t := lbl("SELECT STAGE", 30, F_TITLE, INK, 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(t)
	var name_l := lbl("", 64, F_TITLE, INK, 12)
	place(name_l, screen, Control.PRESET_BOTTOM_LEFT, Vector2(70, -330))
	var sub_l := lbl("", 20, F_BODY, GOLD)
	place(sub_l, screen, Control.PRESET_BOTTOM_LEFT, Vector2(74, -250))
	stage_sel.name_l = name_l; stage_sel.sub_l = sub_l
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", -10)
	screen.add_child(strip)
	strip.anchor_left = 0.5; strip.anchor_right = 0.5; strip.anchor_top = 1; strip.anchor_bottom = 1
	strip.offset_left = -440; strip.offset_right = 440; strip.offset_top = -205; strip.offset_bottom = -72
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	var entries: Array = Stage.LIST.duplicate()
	entries.append({id = "random", name = "Random", sub = "Let fate pick the ground", accent = Color(0.5, 0.55, 0.65)})
	for i in entries.size():
		var e: Dictionary = entries[i]
		var card := SkewCard.new()
		card.custom_minimum_size = Vector2(150, 125)
		card.size_flags_vertical = Control.SIZE_SHRINK_END
		card.font = F_TITLE
		card.accent = e.accent
		card.title = e.name.to_upper()
		if e.id != "random":
			var g := Gradient.new()
			g.set_color(0, e.accent.darkened(0.75)); g.set_color(1, e.accent.darkened(0.15))
			var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0, 1); gt.fill_to = Vector2(0, 0)
			card.tex = gt
		card.mouse_entered.connect(func(): if view == "stage" and stage_sel.i != i: stage_sel.i = i; _render_stage())
		card.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if touch_enabled and stage_sel.get("tapped", -1) != i:
					stage_sel.tapped = i; stage_sel.i = i; _render_stage()
					return
				stage_sel.i = i; _stage_confirm())
		strip.add_child(card)
		stage_sel.cards.append([card, e])
	var help := lbl("◀ ▶  A D / Arrows  choose    ·    U / Enter  fight!    ·    J / Esc  back", 15, F_BODY, DIM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place(help, screen, Control.PRESET_CENTER_BOTTOM, Vector2(0, -18))
	help.visible = not touch_enabled
	_render_stage()


func _render_stage() -> void:
	var cards: Array = stage_sel.cards
	for k in cards.size():
		cards[k][0].hl = [k == stage_sel.i, false]
	var e: Dictionary = cards[stage_sel.i][1]
	stage_sel.name_l.text = e.name.to_upper()
	stage_sel.name_l.label_settings.font_color = e.accent.lightened(0.3)
	stage_sel.sub_l.text = e.sub
	if e.id != "random":
		G.set_stage(e.id)
	G.sfx("ui")


func _stage_confirm() -> void:
	var e: Dictionary = stage_sel.cards[stage_sel.i][1]
	var c: Dictionary = stage_sel.cfg.duplicate()
	c.stage = Stage.LIST.pick_random().id if e.id == "random" else e.id
	G.sfx("ok")
	if c.mode == "online":
		c.delay = G.suggest_delay()
		G.net.send({t = "start", stage = c.stage, p = [stage_sel.picks[0].id, stage_sel.picks[1].id], cos = c.costumes, delay = c.delay})
	show_vs(c, stage_sel.picks)


func show_vs(c: Dictionary, p: Array) -> void:
	clear_screen(); screen.visible = true; view = "vs"
	G.clear_preview()
	G.sfx("vs")
	var bg := full(ColorRect.new()); bg.color = Color(0.02, 0.03, 0.05)
	screen.add_child(bg)
	for s in 2:
		var C: Dictionary = p[s]
		var side := Control.new()
		side.anchor_left = 0.0 if s == 0 else 0.5; side.anchor_right = 0.5 if s == 0 else 1.0; side.anchor_bottom = 1.0
		screen.add_child(side)
		var g := full(hgrad(C.accent.darkened(0.55), Color(0.02, 0.03, 0.05)) if s == 0 else hgrad(Color(0.02, 0.03, 0.05), C.accent.darkened(0.55)))
		side.add_child(g)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 8)
		side.add_child(full(v))
		v.offset_left = 60; v.offset_right = -60
		if C.has("boss_form"):
			var bb := lbl(C.boss_form, 40, F_TITLE, Color(1.0, 0.35, 0.45), 10)
			bb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(bb)
		var img := TextureRect.new()
		img.texture = G.portraits.get(C.id)
		img.custom_minimum_size = Vector2(300, 300)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		img.flip_h = s == 1
		img.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if s == 0 else Control.SIZE_SHRINK_END
		v.add_child(img)
		var n := lbl(C.name, 58, F_TITLE, INK, 10)
		var tt := lbl(C.title.to_upper(), 18, F_BODY, Color(0.79, 0.83, 0.88))
		for x in [n, tt]:
			x.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if s == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			v.add_child(x)
		# slide in from off-screen by animating the offsets (setting position would drop the half-screen anchors)
		var off := -800.0 if s == 0 else 800.0
		side.offset_left = off; side.offset_right = off
		var stw := side.create_tween().set_parallel()
		stw.tween_property(side, "offset_left", 0.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		stw.tween_property(side, "offset_right", 0.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	var vs := lbl("VS", 150, F_TITLE, GOLD, 18)
	place(vs, screen, Control.PRESET_CENTER)
	if c.has("stage"):
		var sl := lbl("STAGE  ·  " + Stage.info(c.stage).name.to_upper(), 18, F_TITLE, Color(0.85, 0.9, 1.0), 6)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		place(sl, screen, Control.PRESET_CENTER_BOTTOM, Vector2(-150, -60))
	vs.pivot_offset = vs.size / 2
	vs.scale = Vector2(3, 3); vs.modulate.a = 0
	var tw := vs.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(vs, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(vs, "modulate:a", 1.0, 0.2)
	get_tree().create_timer(2.1).timeout.connect(func():
		if view != "vs": return
		if c.mode == "online": G.start_online(c, p)
		else: G.start_match(c, p))


# ---- pause / moves / end / info
func toggle_pause() -> void:
	if view == "pause":
		G.paused = false; hide_screen(); view = "game"
	else:
		show_pause()


func show_pause() -> void:
	G.paused = G.mode != "online"   # an online fight can't stop for one player
	clear_screen(); screen.visible = true; view = "pause"
	var dim := full(ColorRect.new()); dim.color = Color(0.01, 0.02, 0.04, 0.72)
	screen.add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sbox(PANEL, Color(1, 1, 1, 0.12), 1))
	place(pc, screen, Control.PRESET_CENTER)
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(lbl("PAUSED", 34, F_TITLE, INK, 6))
	var items := [["RESUME", toggle_pause], ["MOVE LIST", func(): show_moves(0)], ["RESTART MATCH", func(): G.start_match(G.cfg, G.picks)],
		["CHARACTER SELECT", func(): var c: Dictionary = G.cfg; G.leave_game(); show_select(c)], ["MAIN MENU", show_title]]
	if G.mode == "online":
		items = [["RESUME", toggle_pause], ["MOVE LIST", func(): show_moves(G.local_side)], ["LEAVE MATCH", leave_online]]
	if touch_enabled:
		items.insert(2, ["TOUCH CONTROLS: " + ("D-PAD" if touch.mode == "dpad" else "STICK"), func(): touch.toggle_mode(); show_pause()])
	var m := _menu_list(items)
	m.set_meta("back", toggle_pause)
	v.add_child(m)
	pc.reset_size()
	pc.position -= pc.size / 2
	_focus_first(m)


func show_moves(i: int) -> void:
	clear_screen(); screen.visible = true; view = "moves"
	var C: Dictionary = G.F[i].C
	var dim := full(ColorRect.new()); dim.color = Color(0.01, 0.02, 0.04, 0.8)
	screen.add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sbox(PANEL, C.accent, 1))
	screen.add_child(pc)
	pc.anchor_left = 0.08; pc.anchor_right = 0.92; pc.anchor_top = 0.06; pc.anchor_bottom = 0.94
	var v := VBoxContainer.new()
	pc.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	var img := TextureRect.new()
	img.texture = G.portraits.get(C.id); img.custom_minimum_size = Vector2(72, 72)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	head.add_child(img)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(lbl(C.name + " — MOVE LIST", 30, F_TITLE, INK, 6))
	hv.add_child(lbl(C.style, 17, F_MED, DIM))
	head.add_child(hv)
	for k in 2:
		var tb := menu_btn(("P2 · " if k else "P1 · ") + G.F[k].C.name, func(): show_moves(k), 15)
		head.add_child(tb)
	var leg := rich(15)
	leg.text = "[color=#7fe3ff][b]1[/b][/color] left punch  [color=#7fe3ff][b]2[/b][/color] right punch  [color=#ffb35c][b]3[/b][/color] left kick  [color=#ffb35c][b]4[/b][/color] right kick  ·  [b]→[/b] toward opponent  ·  [b]WS[/b] while rising from crouch  ·  [b]→→[/b] dash"
	v.add_child(leg)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)
	var list: Array = C.moves.values().filter(func(m): return not m.hidden)
	var groups := [
		["SIGNATURE", list.filter(func(m): return m.sig or m.surge)],
		["STRINGS", list.filter(func(m): return "," in m.key and not ":" in m.key)],
		["STANCES", list.filter(func(m): return m.to_stance != "" or ":" in m.key)],
		["LAUNCHERS", list.filter(func(m): return m.launch and not m.sig and not ":" in m.key)],
		["LOWS", list.filter(func(m): return m.lvl == "low" and not ":" in m.key)],
		["THROWS", list.filter(func(m): return m.is_throw and not m.sig)],
		["CORE ATTACKS", list.filter(func(m): return not m.sig and not m.surge and not "," in m.key and not ":" in m.key and m.to_stance == "" and not m.launch and m.lvl != "low" and not m.is_throw)],
	]
	var sg := func(x) -> String:
		if x == null: return "—"
		var n := int(x)
		return "[color=%s]%s%d[/color]" % ["#6bffb0" if n >= 0 else "#ff6b81", "+" if n > 0 else "", n]
	for h in ["INPUT", "MOVE", "LEVEL", "STARTUP", "BLOCK", "HIT", "DMG", "PROPERTIES"]:
		grid.add_child(lbl(h, 12, F_BODY, DIM))
	for grp in groups:
		if grp[1].is_empty(): continue
		var gl := lbl(grp[0], 14, F_TITLE, C.accent)
		grid.add_child(gl)
		for x in 7: grid.add_child(Control.new())
		for m in grp[1]:
			var tags: Array = []
			for pair in [[m.launch, "Launch"], [m.kd, "KND"], [m.homing, "Homing"], [m.armor, "Armor"], [m.low, "Ducks highs"], [m.jump, "Hops lows"],
				[m.ch_launch, "CH launch"], [m.cmd_throw, "Break 1+2"], [m.trans, "Stance entry"], [m.push > 0, "Pushback"]]:
				if pair[0]: tags.append(pair[1])
			var cells_txt := [cmd_bb(m.key, C), "[b]%s[/b]" % m.name, "—" if m.trans else lvl_bb(m.lvl), "—" if m.trans else "i%d" % m.s,
				"—" if (m.is_throw or m.trans) else sg.call(m.blk), "—" if (m.is_throw or m.launch or m.kd or m.trans) else sg.call(m.hit),
				"—" if m.trans else str(int(m.dmg)), "[color=#9fd8e8]%s[/color]" % ", ".join(tags)]
			for t in cells_txt:
				var r := rich(16)
				r.text = t
				r.autowrap_mode = TextServer.AUTOWRAP_OFF
				r.custom_minimum_size = Vector2(0, 26)
				grid.add_child(r)
	var back := menu_btn("BACK", show_pause, 18)
	v.add_child(back)
	v.set_meta("back", show_pause)
	back.call_deferred("grab_focus")


func show_end_delayed() -> void:
	get_tree().create_timer(1.6).timeout.connect(show_end)


func show_end() -> void:
	if G.F.is_empty(): return
	clear_screen(); screen.visible = true; view = "end"
	var w := -1 if (G.wins[0] >= 2 and G.wins[1] >= 2) else (0 if G.wins[0] >= 2 else 1)
	var bg := full(vgrad(Color(0.02, 0.03, 0.06, 0.0), Color(0.02, 0.03, 0.06, 0.95)))
	bg.anchor_top = 0.4
	screen.add_child(bg)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	screen.add_child(h)
	h.anchor_top = 1; h.anchor_bottom = 1; h.offset_left = 70; h.offset_top = -330
	if w >= 0:
		var C: Dictionary = G.F[w].C
		var img := TextureRect.new()
		img.texture = G.portraits.get(C.id); img.custom_minimum_size = Vector2(230, 230)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		h.add_child(img)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_END
		h.add_child(v)
		var who := ("PLAYER 1" if w == 0 else "CPU" if G.mode == "cpu" else "PLAYER 2") + " WINS"
		if G.cfg.get("arcade", false): who = "YOU WIN" if w == 0 else "DEFEATED"
		v.add_child(lbl(who, 20, F_TITLE, C.accent))
		v.add_child(lbl(C.name, 76, F_TITLE, INK, 12))
		var q := lbl("“%s”" % C.quote, 22, F_MED, Color(0.87, 0.9, 0.95))
		q.autowrap_mode = TextServer.AUTOWRAP_WORD
		q.custom_minimum_size = Vector2(640, 0)
		v.add_child(q)
		var row := HBoxContainer.new()
		v.add_child(row)
		_end_buttons(row)
	else:
		var v := VBoxContainer.new()
		h.add_child(v)
		v.add_child(lbl("DRAW", 76, F_TITLE, INK, 12))
		var row := HBoxContainer.new()
		v.add_child(row)
		_end_buttons(row)


func _end_buttons(row: HBoxContainer) -> void:
	if G.cfg.get("arcade", false) and G.arcade != null:
		var won: bool = G.wins[0] >= 2 and G.wins[1] < 2
		if won:
			row.add_child(menu_btn("NEXT FIGHT", func():
				G.arcade.i += 1
				G.leave_game()
				if G.arcade.i >= G.arcade.ladder.size(): show_arcade_win()
				else: show_ladder(), 20))
		else:
			row.add_child(menu_btn("RETRY", func(): G.leave_game(); G.arcade_fight(), 20))
		row.add_child(menu_btn("QUIT ARCADE", func(): G.arcade = null; show_title(), 20))
		_focus_first(row)
		return
	if G.mode == "online":
		# (online.rematch is reset when a match starts, not here: the rival may already have asked)
		var rb: Button
		rb = menu_btn("REMATCH", func():
			online.rematch[G.local_side] = true
			rb.text = "WAITING FOR RIVAL…"
			G.net.send({t = "rematch"})
			_online_rematch(), 20)
		row.add_child(rb)
		row.add_child(menu_btn("LEAVE", leave_online, 20))
		_focus_first(row)
		return
	for it in [["REMATCH", func(): G.start_match(G.cfg, G.picks)], ["CHARACTER SELECT", func(): var c: Dictionary = G.cfg; G.leave_game(); show_select(c)], ["MAIN MENU", show_title]]:
		row.add_child(menu_btn(it[0], it[1], 20))
	_focus_first(row)


func _info_panel(title: String, body: String) -> void:
	clear_screen(); screen.visible = true; view = "info"
	var dim := full(ColorRect.new()); dim.color = Color(0.01, 0.02, 0.04, 0.8)
	screen.add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sbox(PANEL, Color(1, 1, 1, 0.12), 1))
	screen.add_child(pc)
	pc.anchor_left = 0.12; pc.anchor_right = 0.88; pc.anchor_top = 0.08; pc.anchor_bottom = 0.92
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(lbl(title, 34, F_TITLE, INK, 6))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var r := rich(19)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.text = body
	sc.add_child(r)
	var back := menu_btn("BACK", show_title, 18)
	v.add_child(back)
	v.set_meta("back", show_title)
	back.call_deferred("grab_focus")


func show_controls() -> void:
	_info_panel("CONTROLS", """[color=#2ee6ff][b]PLAYER 1 (keyboard)[/b][/color]
[b]A / D[/b] back / forward   ·   [b]S[/b] crouch   ·   tap [b]W[/b] sidestep in   ·   tap [b]S[/b] sidestep out
[b]U[/b] = 1 left punch   ·   [b]I[/b] = 2 right punch   ·   [b]J[/b] = 3 left kick   ·   [b]K[/b] = 4 right kick
In VS CPU and Training the arrow keys and P2 buttons also work for Player 1.

[color=#2ee6ff][b]PLAYER 2 (keyboard)[/b][/color]
[b]Arrow keys[/b] move   ·   [b]Num4 / O[/b] = 1   ·   [b]Num5 / P[/b] = 2   ·   [b]Num1 / L[/b] = 3   ·   [b]Num2 / ;[/b] = 4

[color=#2ee6ff][b]GAMEPADS[/b][/color]
Pad 1 → Player 1, Pad 2 → Player 2. D-pad or left stick to move. X = 1, Y = 2, A = 3, B = 4 (Xbox layout). Start = pause.

[color=#2ee6ff][b]MOVEMENT[/b][/color]
Double-tap forward to dash, double-tap back to backdash. Standing still or holding back blocks highs and mids; hold down to block lows.
Release down and press a button for [b]WS[/b] (while-standing) attacks.""")


func show_how() -> void:
	_info_panel("HOW TO PLAY", """BNB Clashes uses the core rules of 3D fighting games. Training mode shows the frame data live.

[color=#2ee6ff][b]1 · THE FRAME CLOCK[/b][/color]
The game runs 60 fixed steps per second. Every move has [b]startup[/b] (frames before it can hit), [b]active[/b] frames and [b]recovery[/b]. "i10" = hits on frame 10.

[color=#2ee6ff][b]2 · FRAME ADVANTAGE[/b][/color]
"−13 on block" means the attacker recovers 13 frames after the defender. Any move with startup ≤ 13 is a guaranteed [b]punish[/b]. Plus frames mean it is still your turn.

[color=#2ee6ff][b]3 · HIT LEVELS[/b][/color]
[color=#ffcf5a][b]HIGH[/b][/color] is blocked standing and whiffs on crouchers. [color=#2ee6ff][b]MID[/b][/color] must be blocked standing. [color=#ff6b81][b]LOW[/b][/color] must be blocked crouching.

[color=#2ee6ff][b]4 · THE THIRD DIMENSION[/b][/color]
Tap up or down to sidestep. Most attacks are [b]linear[/b] and lock their direction after 2 frames, so stepping during their startup makes them whiff. [b]Homing[/b] attacks keep tracking.

[color=#2ee6ff][b]5 · STRINGS, STANCES, WHILE-STANDING[/b][/color]
Press the next button during a move to chain a string (1,2,4). Some fighters have [b]stances[/b] (Crane, Sway, Handstand) with their own follow-ups. Rise from a crouch and press a button for a [b]WS[/b] attack.

[color=#2ee6ff][b]6 · LAUNCHERS & JUGGLES[/b][/color]
Launchers pop the opponent airborne; every attack hits them in the air. Damage scales down 10% per hit (min 30%). Juggles cap at 10 hits.

[color=#2ee6ff][b]7 · COUNTER HITS, ARMOR, THROWS[/b][/color]
Hitting during the opponent's startup is a [b]counter hit[/b] (+20% damage, more stun). Armored moves absorb one hit. Throws beat blocking but whiff on crouchers; break with 1 or 2 (command throws need 1+2).

[color=#2ee6ff][b]8 · SURGE[/b][/color]
The Surge meter fills as you deal and take damage. When full, press 3+4 for your fighter's armored Surge Art.""")


# ---------------------------------------------------------------- keyboard routing
func _back() -> void:
	for n in screen.find_children("*", "", true, false):
		if n.has_meta("back"):
			n.get_meta("back").call()
			return


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = e.physical_keycode
	if view == "game" and not G.F.is_empty():
		if k == KEY_ESCAPE and G.phase != "end":
			show_pause()
		elif G.mode == "training":
			if k == KEY_T: G.cycle_dummy()
			if k == KEY_R: G.reset_training()
			if k == KEY_C: G.cycle_trial()
		return
	if view == "ladder" and k in [KEY_U, KEY_ENTER, KEY_SPACE]:
		G.arcade_fight(); return
	if view == "stage":
		var n: int = stage_sel.cards.size()
		if k in [KEY_A, KEY_LEFT]: stage_sel.i = (stage_sel.i + n - 1) % n; _render_stage()
		elif k in [KEY_D, KEY_RIGHT]: stage_sel.i = (stage_sel.i + 1) % n; _render_stage()
		elif k in [KEY_U, KEY_ENTER, KEY_SPACE, KEY_KP_4, KEY_O]: _stage_confirm()
		elif k in [KEY_J, KEY_ESCAPE, KEY_BACKSPACE]: show_select(stage_sel.cfg)
		return
	if view == "select" and sel != null:
		var two: bool = sel.cfg.mode == "2p"
		var maps := [{KEY_A: "l", KEY_D: "r", KEY_W: "u", KEY_S: "d"}, {KEY_LEFT: "l", KEY_RIGHT: "r", KEY_UP: "u", KEY_DOWN: "d"}]
		for p in 2:
			if maps[p].has(k):
				_select_move(p if two else _active_side(), maps[p][k]); return
		if k in [KEY_U, KEY_ENTER, KEY_SPACE]: _select_confirm(0 if two else _active_side())
		elif k in [KEY_KP_4, KEY_O]: _select_confirm(1 if two else _active_side())
		elif k in [KEY_J, KEY_ESCAPE, KEY_BACKSPACE]: _select_back(0 if two else _active_side())
		elif k in [KEY_KP_1, KEY_L] and two: _select_back(1)
		return
	if k in [KEY_ESCAPE, KEY_J, KEY_BACKSPACE]:
		if view == "pause":
			toggle_pause()
		else:
			_back()


# ---------------------------------------------------------------- online lobby
var online := {status = null, rematch = [false, false], last_error = ""}


func _online_signals() -> void:
	if G.net.paired.is_connected(_on_paired): return
	G.net.paired.connect(_on_paired)
	G.net.failed.connect(func(msg):
		online.last_error = msg
		if view.begins_with("online"): show_online(msg))
	G.net.peer_left.connect(func():
		if G.mode == "online" or view.begins_with("online") or (sel != null and sel.cfg.mode == "online") or view == "stage":
			G.leave_game() if not G.F.is_empty() else null
			G.mode = ""
			G.net.close()
			show_online("Your rival left the match."))
	G.net.room_created.connect(func(code): if view == "online_wait": _render_wait())


func show_online(msg := "") -> void:
	_online_signals()
	G.net.close()
	G.mode = ""
	clear_screen(); screen.visible = true; view = "online"
	var bg := full(hgrad(Color(0.02, 0.03, 0.06, 0.95), Color(0.02, 0.03, 0.06, 0.0)))
	bg.anchor_right = 0.75
	screen.add_child(bg)
	var col := VBoxContainer.new()
	screen.add_child(col)
	col.position = Vector2(110, 130) if not touch_enabled else Vector2(90, 100)
	col.add_child(lbl("ONLINE", 72, F_TITLE, Color(0.24, 0.84, 1.0), 12))
	var items := [
		["CREATE ROOM", _online_create, 26, "Get a room code and a link to send to your friend. Works over the internet."],
		["JOIN WITH CODE", func(): show_join(""), 26, "Type the code your friend sent you."]]
	if Net.lan_supported():
		items.append(["HOST ON THIS WI-FI", _lan_host, 26, "Play someone on the same Wi-Fi network. No internet needed."])
		items.append(["FIND WI-FI GAMES", _lan_find, 26, "Look for a game hosted on this Wi-Fi network."])
	items.append(["BACK", show_title, 20, "Return to the main menu."])
	var m := _menu_list(items)
	m.set_meta("back", show_title)
	col.add_child(m)
	desc_lbl = lbl("", 20, F_MED, Color(0.79, 0.83, 0.88))
	desc_lbl.custom_minimum_size = Vector2(520, 60)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(desc_lbl)
	if msg != "":
		var e := lbl(msg, 22, F_BODY, Color(1.0, 0.45, 0.5))
		e.autowrap_mode = TextServer.AUTOWRAP_WORD
		e.custom_minimum_size = Vector2(520, 0)
		col.add_child(e)
	_focus_first(m)


## A waiting screen with a big title, a status line and a cancel button.
func _online_panel(title: String, status: String) -> VBoxContainer:
	clear_screen(); screen.visible = true
	var dim := full(ColorRect.new()); dim.color = Color(0.01, 0.02, 0.04, 0.78)
	screen.add_child(dim)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	screen.add_child(full(v))
	var t := lbl(title, 44, F_TITLE, INK, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := lbl(status, 22, F_BODY, Color(0.79, 0.83, 0.88))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(st)
	online.status = st
	v.set_meta("back", func(): show_online())
	return v


func _centered(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc


func _online_create() -> void:
	view = "online_wait"
	_online_panel("CREATE ROOM", "Connecting to the online server…")
	G.net.create_room()


func _render_wait() -> void:
	var v := _online_panel("ROOM CODE", "Send this code (or the link) to your friend. The match starts when they join.")
	view = "online_wait"
	var code: String = G.net.code
	var big := lbl(code, 110, F_TITLE, GOLD, 14)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.add_child(big_btn("COPY CODE", Color(0.24, 0.84, 1.0), func(): DisplayServer.clipboard_set(code); online.status.text = "Code copied."))
	row.add_child(big_btn("COPY LINK", GOLD, func(): DisplayServer.clipboard_set(G.room_link(code)); online.status.text = "Link copied: " + G.room_link(code)))
	row.add_child(big_btn("CANCEL", Color(0.55, 0.62, 0.75), func(): show_online()))
	v.add_child(row)


func show_join(code: String) -> void:
	_online_signals()
	var v := _online_panel("JOIN ROOM", "Enter the 5-letter code.")
	view = "online_join"
	var le := LineEdit.new()
	le.max_length = 5
	le.text = code
	le.placeholder_text = "CODE"
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.custom_minimum_size = Vector2(380, 110)
	le.add_theme_font_override("font", F_TITLE)
	le.add_theme_font_size_override("font_size", 72)
	le.add_theme_stylebox_override("normal", sbox(Color(0.04, 0.06, 0.11, 0.95), GOLD, 2, 0.0))
	le.add_theme_stylebox_override("focus", sbox(Color(0.06, 0.09, 0.16, 0.95), GOLD, 3, 0.0))
	le.text_changed.connect(func(t):
		var up: String = t.to_upper()
		if up != t:
			le.text = up; le.caret_column = up.length())
	var go := func():
		if le.text.strip_edges().length() < 4:
			online.status.text = "That code looks too short."; return
		online.status.text = "Joining " + le.text.to_upper() + "…"
		G.net.join_room(le.text)
	le.text_submitted.connect(func(_t): go.call())
	v.add_child(_centered(le))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.add_child(big_btn("JOIN", GOLD, go))
	row.add_child(big_btn("CANCEL", Color(0.55, 0.62, 0.75), func(): show_online()))
	v.add_child(row)
	le.call_deferred("grab_focus")
	if code != "": go.call()


func _lan_host() -> void:
	if not G.net.host_lan(): return
	var ips := Net.lan_addresses()
	_online_panel("HOSTING ON WI-FI", "Waiting for your rival… on their device: ONLINE → FIND WI-FI GAMES." +
		("\nOr connect to:  " + "  /  ".join(ips) if not ips.is_empty() else ""))
	view = "online_wait"
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(big_btn("CANCEL", Color(0.55, 0.62, 0.75), func(): show_online()))
	screen.get_child(1).add_child(row)


func _lan_find() -> void:
	G.net.find_lan()
	var v := _online_panel("WI-FI GAMES", "Looking for games on this network…")
	view = "online_find"
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	v.add_child(_centered(list))
	online.list = list
	online.listed = []
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	var ip_in := LineEdit.new()
	ip_in.placeholder_text = "or type an address"
	ip_in.custom_minimum_size = Vector2(360, 70)
	ip_in.add_theme_font_override("font", F_BODY)
	ip_in.add_theme_font_size_override("font_size", 30)
	ip_in.text_submitted.connect(func(t): if t.strip_edges() != "": G.net.join_lan(t.strip_edges()))
	row.add_child(ip_in)
	row.add_child(big_btn("CONNECT", GOLD, func(): if ip_in.text.strip_edges() != "": G.net.join_lan(ip_in.text.strip_edges())))
	row.add_child(big_btn("CANCEL", Color(0.55, 0.62, 0.75), func(): show_online()))
	v.add_child(row)


func _process_online() -> void:
	if view != "online_find" or not online.has("list"): return
	var ips: Array = G.net.found.keys()
	ips.sort()
	if ips == online.listed: return
	online.listed = ips
	for c in online.list.get_children(): c.queue_free()
	for ip in ips:
		online.list.add_child(big_btn("%s   (%s)" % [G.net.found[ip].name, ip], Color(0.24, 0.84, 1.0), func(): G.net.join_lan(ip)))
	online.status.text = "Tap a game to join." if not ips.is_empty() else "Looking for games on this network…"


func _on_paired() -> void:
	G.local_side = 0 if G.net.is_host else 1
	G.mode = "online"
	G.sfx("ok")
	show_select({mode = "online"})


func leave_online() -> void:
	G.net.send({t = "leave"})
	G.net.close()
	if not G.F.is_empty(): G.leave_game()
	G.mode = ""
	show_title()


func _online_both_picked() -> void:
	if sel == null or not (sel.locked[0] and sel.locked[1]): return
	if sel.cur[0] == sel.cur[1] and sel.cos[0] == sel.cos[1]:
		sel.cos[1] = (sel.cos[1] + 1) % Models.costume_names(Data.ROSTER[sel.cur[1]].id).size()
	var c: Dictionary = sel.cfg.duplicate()
	c.costumes = sel.cos.duplicate()
	var p := [Data.ROSTER[sel.cur[0]], Data.ROSTER[sel.cur[1]]]
	if G.net.is_host:
		get_tree().create_timer(0.6).timeout.connect(func(): show_stage(c, p))
	else:
		get_tree().create_timer(0.6).timeout.connect(func():
			_online_panel("STAGE SELECT", "Your rival (the host) is picking the stage…")
			view = "online_stage_wait")


func _online_rematch() -> void:
	if not (online.rematch[0] and online.rematch[1]) or not G.net.is_host: return
	var c: Dictionary = G.cfg.duplicate()
	G.net.send({t = "start", stage = c.stage, p = [G.picks[0].id, G.picks[1].id], cos = c.costumes, delay = G.suggest_delay()})
	c.delay = G.suggest_delay()
	show_vs(c, G.picks)


## Lobby messages from the rival (fight inputs are handled by Main).
func net_message(d: Dictionary) -> void:
	var r: int = 1 - G.local_side
	match d.get("t", ""):
		"cur":
			if sel != null and sel.cfg.mode == "online":
				sel.cur[r] = clampi(int(d.i), 0, Data.ROSTER.size()); sel.cos[r] = int(d.cos); sel.seen = true
				_render_select()
		"pick":
			if sel != null and sel.cfg.mode == "online":
				sel.cur[r] = clampi(int(d.i), 0, Data.ROSTER.size() - 1); sel.cos[r] = int(d.cos); sel.locked[r] = true; sel.seen = true
				G.sfx("ok")
				_render_select()
				_online_both_picked()
		"unpick":
			if sel != null and sel.cfg.mode == "online":
				sel.locked[r] = false; _render_select()
		"start":
			var c := {mode = "online", stage = String(d.stage), costumes = [int(d.cos[0]), int(d.cos[1])], delay = int(d.delay)}
			show_vs(c, [Data.by_id(String(d.p[0])), Data.by_id(String(d.p[1]))])
		"rematch":
			online.rematch[r] = true
			_online_rematch()
		"leave":
			pass   # the socket closing follows and triggers peer_left


# ---------------------------------------------------------------- arcade ladder
func show_ladder() -> void:
	clear_screen(); screen.visible = true; view = "ladder"
	var A: Dictionary = G.arcade
	G.set_stage(A.ladder[A.i].stage)
	G.set_preview(0, A.player, A.cos)
	var nxt: Dictionary = A.ladder[A.i]
	G.set_preview(1, nxt.C, 1 if nxt.C.id == A.player.id else 0)
	var dim := full(hgrad(Color(0.03, 0.01, 0.06, 0.95), Color(0.03, 0.01, 0.06, 0.2)))
	screen.add_child(dim)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	screen.add_child(col)
	col.position = Vector2(80, 60) if not touch_enabled else Vector2(70, 100)
	col.add_child(lbl("ARCADE", 56, F_TITLE, P1C, 10))
	col.add_child(lbl("%s  ·  FIGHT %d OF %d" % [A.player.name, A.i + 1, A.ladder.size()], 20, F_BODY, GOLD))
	for k in A.ladder.size():
		var e: Dictionary = A.ladder[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var mark := "✔" if k < A.i else ("▶" if k == A.i else "·")
		var c := INK if k == A.i else (DIM if k < A.i else Color(0.7, 0.72, 0.8))
		row.add_child(lbl(mark, 22, F_TITLE, P2C if k == A.i else c))
		var name_l := lbl(e.C.name, 26 if k == A.i else 20, F_TITLE, c, 6 if k == A.i else 0)
		name_l.custom_minimum_size = Vector2(360, 0)
		row.add_child(name_l)
		if e.kind != "":
			row.add_child(lbl(e.C.boss_form, 18, F_TITLE, Color(1.0, 0.35, 0.45)))
		col.add_child(row)
	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 16)
	go.add_child(big_btn("FIGHT!  ✔", GOLD, G.arcade_fight))
	go.add_child(big_btn("QUIT", Color(0.55, 0.62, 0.75), func(): G.arcade = null; show_title()))
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 14); col.add_child(sp)
	col.add_child(go)
	col.set_meta("back", func(): G.arcade = null; show_title())


func show_arcade_win() -> void:
	clear_screen(); screen.visible = true; view = "info"
	var A: Dictionary = G.arcade
	G.arcade = null
	G.set_stage("rooftop")
	G.set_preview(0, A.player, A.cos)
	if G.preview[1] != null:
		G.preview[1].rig.queue_free(); G.preview[1] = null
	G.preview[0].win = true
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	screen.add_child(full(v))
	var t := lbl("PROMOTED!", 96, F_TITLE, GOLD, 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := lbl("%s beat the whole office, HR, the PM and the CEO.\nThe corner office is yours… until Monday's stand-up." % A.player.name, 26, F_BODY, INK)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	# the (unofficial) certificate: type a name, get a PDF
	var cert_row := HBoxContainer.new()
	cert_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cert_row.add_theme_constant_override("separation", 14)
	var name_in := LineEdit.new()
	name_in.placeholder_text = "Your name for the certificate"
	name_in.max_length = 32
	name_in.custom_minimum_size = Vector2(460, 72)
	name_in.add_theme_font_override("font", F_BODY)
	name_in.add_theme_font_size_override("font_size", 30)
	cert_row.add_child(name_in)
	var status := lbl("", 20, F_MED, Color(0.79, 0.83, 0.88))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var make_cert := func():
		var who := name_in.text.strip_edges()
		if who == "":
			status.text = "Type a name first."; return
		status.text = "Printing your certificate…"
		var img: Image = await Certificate.render(self, who, A.player, G.portraits.get(A.player.id))
		status.text = Certificate.save(Certificate.to_pdf(img), who)
	name_in.text_submitted.connect(func(_t): make_cert.call())
	cert_row.add_child(big_btn("GET CERTIFICATE", GOLD, make_cert))
	v.add_child(cert_row)
	v.add_child(status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(big_btn("MAIN MENU", P2C, show_title))
	v.add_child(row)
	v.set_meta("back", show_title)


# ---------------------------------------------------------------- BNB Rush Hour
func show_race_tracks(C: Dictionary) -> void:
	clear_screen(); screen.visible = true; view = "race_tracks"
	G.set_preview(0, C)
	var dim := full(hgrad(Color(0.03, 0.01, 0.06, 0.95), Color(0.03, 0.01, 0.06, 0.2)))
	screen.add_child(dim)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	screen.add_child(col)
	col.position = Vector2(90, 90) if not touch_enabled else Vector2(70, 100)
	col.add_child(lbl("RUSH HOUR", 64, F_TITLE, P2C, 10))
	col.add_child(lbl("%s  ·  10 RACERS  ·  %d LAPS" % [C.name, RaceSim.LAPS], 20, F_BODY, GOLD))
	var items := []
	for id in RaceSim.TRACKS:
		var t: Dictionary = RaceSim.TRACKS[id]
		var tid: String = id
		items.append([String(t.name).to_upper(), func(): G.start_race(tid, C), 28, {"city": "Neon towers, night traffic, two big jumps.",
			"park": "Trees, glass offices and a hill with a jump.", "rooftop": "Thirty storeys up, over the rooftops at sunset."}.get(id, "")])
	items.append(["BACK", show_title, 20, "Back to the main menu."])
	var m := _menu_list(items)
	m.set_meta("back", show_title)
	col.add_child(m)
	desc_lbl = lbl("", 20, F_MED, Color(0.79, 0.83, 0.88))
	desc_lbl.custom_minimum_size = Vector2(480, 50)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(desc_lbl)
	_focus_first(m)


## The fighting game's own menu (CLASH on the hub).
func show_clash_menu() -> void:
	clear_screen(); screen.visible = true; view = "diff"
	var bg := full(hgrad(Color(0.02, 0.03, 0.06, 0.95), Color(0.02, 0.03, 0.06, 0.0)))
	bg.anchor_right = 0.75
	screen.add_child(bg)
	var col := VBoxContainer.new()
	screen.add_child(col)
	col.position = Vector2(110, 120) if not touch_enabled else Vector2(90, 90)
	col.add_child(lbl("CLASH", 72, F_TITLE, P1C, 12))
	var labels := ["ARCADE", "VS CPU", "VERSUS", "ONLINE", "TRAINING", "BACK"]
	var cbs := [func(): show_select({mode = "arcade", lv = 1}), show_difficulty, func(): show_select({mode = "2p"}), show_online,
		func(): show_select({mode = "training"}), show_title]
	var items := []
	for k in labels.size():
		items.append([labels[k], cbs[k], 26 if k < labels.size() - 1 else 20, CLASH_DESC[k]])
	var m := _menu_list(items)
	m.set_meta("back", show_title)
	col.add_child(m)
	desc_lbl = lbl(CLASH_DESC[0], 20, F_MED, Color(0.79, 0.83, 0.88))
	desc_lbl.custom_minimum_size = Vector2(460, 60)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(desc_lbl)
	_focus_first(m)


# ---------------------------------------------------------------- BNB Office Ops
var ops_cfg := {mine = 4, them = 4, gun = "rifle", skill = 1.0}


func show_ops_setup(C: Dictionary) -> void:
	clear_screen(); screen.visible = true; view = "ops_setup"
	G.set_preview(0, C)
	var dim := full(hgrad(Color(0.03, 0.01, 0.06, 0.95), Color(0.03, 0.01, 0.06, 0.2)))
	screen.add_child(dim)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	screen.add_child(col)
	col.position = Vector2(90, 80) if not touch_enabled else Vector2(70, 90)
	col.add_child(lbl("OFFICE OPS", 64, F_TITLE, P1C, 10))
	col.add_child(lbl("%s  ·  TEAM DEATHMATCH" % C.name, 20, F_BODY, GOLD))
	var row := func(title: String, opts: Array, key: String, names: Array) -> void:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var t := lbl(title, 22, F_TITLE, INK)
		t.custom_minimum_size = Vector2(170, 0)
		h.add_child(t)
		for k in opts.size():
			var v = opts[k]
			var b := big_btn(String(names[k]), P2C if ops_cfg[key] == v else Color(0.35, 0.38, 0.5), func(): ops_cfg[key] = v; show_ops_setup(C))
			b.custom_minimum_size = Vector2(110 if names[k].length() < 4 else 150, 58)
			b.add_theme_font_size_override("font_size", 22)
			h.add_child(b)
		col.add_child(h)
	row.call("YOUR TEAM", [1, 2, 3, 4], "mine", ["1", "2", "3", "4"])
	row.call("ENEMY TEAM", [1, 2, 3, 4], "them", ["1", "2", "3", "4"])
	row.call("GUN", ["rifle", "smg", "shotgun", "sniper"], "gun", ["RIFLE", "SMG", "SHOTGUN", "SNIPER"])
	row.call("BOTS", [0.7, 1.0, 1.4], "skill", ["EASY", "NORMAL", "HARD"])
	var g: Dictionary = OpsSim.GUNS[ops_cfg.gun]
	col.add_child(lbl("%s  ·  %d damage  ·  %d rounds  ·  %d rpm   (plus a P-9 pistol)" % [g.name, g.dmg * g.pellets, g.mag, g.rpm], 18, F_MED, Color(0.79, 0.83, 0.88)))
	col.add_child(lbl("%d v %d   ·   bots fill the empty slots   ·   first to %d kills or 5 minutes" % [ops_cfg.mine, ops_cfg.them, 10 + maxi(ops_cfg.mine, ops_cfg.them) * 5], 18, F_MED, Color(0.79, 0.83, 0.88)))
	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 16)
	go.add_child(big_btn("DEPLOY  ✔", GOLD, func(): G.start_ops(C, ops_cfg.duplicate())))
	go.add_child(big_btn("BACK", Color(0.55, 0.62, 0.75), show_title))
	col.add_child(go)
	col.set_meta("back", show_title)
