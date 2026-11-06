class_name Certificate
## The (completely unofficial) Bit & Bytes certificates: Clash Arcade (beat the CEO), the Rush Hour Grand Prix
## (win all six tracks) and Deadline Dash (clear all ten levels).
## Drawn with Controls in an offscreen viewport, then wrapped into a one-page PDF (JPEG image page).
## It's a joke: the disclaimer in the bottom-right corner says so.

const W := 1754   # A4 landscape at 150 dpi
const H := 1240
const PURPLE := Color(0.42, 0.21, 0.59)
const CYAN := Color(0.13, 0.7, 0.85)
const INK := Color(0.12, 0.1, 0.16)


## The three certificates (only the competitive arcade runs give one).
const KINDS := {
	"clash": {title = "CERTIFICATE OF ACHIEVEMENT", a = Color(0.42, 0.21, 0.59), b = Color(0.13, 0.7, 0.85), paper = Color(0.99, 0.97, 0.93),
		lead = "Bit & Bytes proudly (and slightly nervously) certifies that",
		body = "has fulfilled the lifelong dream of every employee: beating the CEO in BNB Clashes, fighting as %s, and surviving HR and the Project Manager along the way.",
		perks = "Perks:  bragging rights (non-transferable)   ·   promotion pending HR approval   ·   tea still only at 3 PM and 5 PM (Ali has spoken)",
		sigs = [["Hamza Khan", "CEO  (defeated, fair and square)"], ["Kashaf ud Duja", "HR  (mildly impressed)"]], seal = "ARCADE\nCHAMPION", emblem = "fist"},
	"rush": {title = "GRAND PRIX CHAMPION", a = Color(0.78, 0.1, 0.12), b = Color(0.08, 0.08, 0.1), paper = Color(0.98, 0.97, 0.95),
		lead = "By order of the BNB Rush Hour race stewards, it is hereby declared that",
		body = "won all six races of the Rush Hour Grand Prix from first place, every single time, driving as %s: Downtown Loop, Office Park, Rooftop Circuit, Seaside Boulevard, Canyon Run and Snowy Pass. Nine colleagues saw nothing but tail lights.",
		perks = "Perks:  the parking spot next to the CEO (Fridays only)   ·   a lifetime pass on 9 AM traffic   ·   all speeding tickets forwarded to HR",
		sigs = [["Sabir ud Din", "Race Director  (waved the flag)"], ["Ali", "Pit Crew Chief  (chai served at the pit stop)"]], seal = "6 / 6\nWINS", emblem = "flag"},
	"dash": {title = "DEADLINE BEATEN", a = Color(0.95, 0.45, 0.1), b = Color(0.1, 0.55, 0.6), paper = Color(0.99, 0.98, 0.94),
		lead = "The Project Management Office confirms, with visible relief, that",
		body = "dashed through all ten levels of Deadline Dash as %s, outran HR, the Sysadmin and the Legacy Wizard, and beat the CEO to the deadline in the penthouse.",
		perks = "Perks:  one (1) deadline extension   ·   unlimited coffee refills   ·   out-of-office auto-reply privileges for a whole afternoon",
		sigs = [["Amina Mughal", "Project Manager  (deadline met, finally)"], ["Hamza Khan", "CEO  (outrun on his own floor)"]], seal = "10 / 10\nLEVELS", emblem = "clock"},
}


## Render the certificate to an Image (needs two drawn frames, so it's a coroutine).
## kind: clash / rush / dash; stats: one line of the run's numbers printed under the citation.
static func render(host: Node, player: String, C: Dictionary, portrait: Texture2D, kind := "clash", stats := "") -> Image:
	var K: Dictionary = KINDS.get(kind, KINDS.clash)
	var A: Color = K.a
	var B: Color = K.b
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var root := Control.new()
	root.size = Vector2(W, H)
	vp.add_child(root)
	var title_font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var body_font: Font = load("res://assets/fonts/Rajdhani-Bold.ttf")
	var med_font: Font = load("res://assets/fonts/Rajdhani-Medium.ttf")

	var bg := ColorRect.new(); bg.color = K.paper; bg.size = Vector2(W, H)
	root.add_child(bg)
	# a faint guilloche of rings behind everything
	var deco := Control.new(); deco.size = Vector2(W, H)
	deco.draw.connect(func():
		for k in 28:
			deco.draw_arc(Vector2(W / 2.0, H / 2.0 + 40), 140.0 + k * 22.0, 0, TAU, 128, Color(A, 0.035), 2.0)
		if kind == "rush":   # chequered bands top and bottom
			for x in range(0, W, 40):
				for row in 2:
					var on := (x / 40 + row) % 2 == 0
					deco.draw_rect(Rect2(x, 72 + row * 20, 40, 20), Color(0.08, 0.08, 0.1) if on else Color(1, 1, 1))
					deco.draw_rect(Rect2(x, H - 106 + row * 20, 40, 20), Color(0.08, 0.08, 0.1) if on else Color(1, 1, 1))
		elif kind == "dash":   # deadline hazard stripes in the corners
			for k in 9:
				deco.draw_colored_polygon(PackedVector2Array([Vector2(70 + k * 30, 70), Vector2(85 + k * 30, 70), Vector2(70, 85 + k * 30), Vector2(70, 70 + k * 30)]), Color(A, 0.5) if k % 2 == 0 else Color(0, 0, 0, 0))
				deco.draw_colored_polygon(PackedVector2Array([Vector2(W - 70 - k * 30, H - 70), Vector2(W - 85 - k * 30, H - 70), Vector2(W - 70, H - 85 - k * 30), Vector2(W - 70, H - 70 - k * 30)]), Color(A, 0.5) if k % 2 == 0 else Color(0, 0, 0, 0))
	)
	root.add_child(deco)
	# double frame
	for inset in [[34, 10, A], [62, 3, B]]:
		var fr := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0); sb.border_color = inset[2]
		sb.set_border_width_all(inset[1])
		fr.add_theme_stylebox_override("panel", sb)
		fr.position = Vector2(inset[0], inset[0]); fr.size = Vector2(W - inset[0] * 2, H - inset[0] * 2)
		root.add_child(fr)

	var text := func(t: String, font: Font, sz: int, col: Color, y: float, w := W - 300.0) -> Label:
		var l := Label.new()
		l.text = t
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", sz)
		l.add_theme_color_override("font_color", col)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.size = Vector2(w, 0)
		l.position = Vector2((W - w) / 2.0, y)
		root.add_child(l)
		return l

	# company logo
	var mark := TextureRect.new()
	mark.texture = load("res://assets/brand/bnb_mark_trim.png")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size = Vector2(150, 130); mark.position = Vector2(W / 2.0 - 230, 110)
	root.add_child(mark)
	var word := TextureRect.new()
	word.texture = load("res://assets/brand/bnb_wordmark.png")
	word.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	word.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	word.size = Vector2(300, 80); word.position = Vector2(W / 2.0 - 70, 135)
	root.add_child(word)

	text.call(String(K.title), title_font, 76 if String(K.title).length() < 22 else 62, A, 255 if String(K.title).length() < 22 else 262)
	text.call(String(K.lead), med_font, 36, INK, 360)
	text.call(player.strip_edges().to_upper(), title_font, 96, INK, 410)
	var line := ColorRect.new(); line.color = B; line.size = Vector2(900, 4); line.position = Vector2(W / 2.0 - 450, 535)
	root.add_child(line)
	text.call(String(K.body) % String(C.name), body_font, 34, INK, 560, W - 440.0)
	if stats != "": text.call(stats, title_font, 28, B if kind != "rush" else A, 700, W - 360.0)
	text.call(String(K.perks), med_font, 25, A, 750, W - 360.0)

	# hero portrait in a ring
	if portrait != null:
		var pr := TextureRect.new()
		pr.texture = portrait
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pr.size = Vector2(190, 190); pr.position = Vector2(W / 2.0 - 95, 815)
		root.add_child(pr)

	# the emblem (left) and the gold seal (right)
	var art := Control.new(); art.size = Vector2(W, H)
	var gold := Color(0.85, 0.65, 0.15)
	art.draw.connect(func():
		var e := Vector2(250, 430)
		match String(K.emblem):
			"flag":   # chequered flag on a pole
				art.draw_line(e + Vector2(-60, -70), e + Vector2(-60, 110), INK, 8.0)
				for r in 4:
					for c2 in 5:
						var p := e + Vector2(-56 + c2 * 26, -70 + r * 24 + sin(c2 * 0.9) * 8)
						art.draw_rect(Rect2(p, Vector2(26, 24)), INK if (r + c2) % 2 == 0 else Color.WHITE)
				art.draw_rect(Rect2(e + Vector2(-56, -70), Vector2(130, 96)), INK, false, 3.0)
			"clock":  # a stopwatch stopped just before the deadline
				art.draw_circle(e, 86, Color(A, 0.15))
				art.draw_arc(e, 86, 0, TAU, 64, A, 8.0)
				art.draw_rect(Rect2(e + Vector2(-14, -116), Vector2(28, 26)), A)
				for k in 12:
					var an := TAU * k / 12.0
					art.draw_line(e + Vector2(sin(an), -cos(an)) * 70, e + Vector2(sin(an), -cos(an)) * 80, INK, 4.0)
				art.draw_line(e, e + Vector2(sin(-0.2), -cos(-0.2)) * 64, INK, 6.0)
				art.draw_line(e, e + Vector2(sin(1.9), -cos(1.9)) * 44, B, 6.0)
				art.draw_circle(e, 8, INK)
			_:        # crossed fists / lightning bolt
				art.draw_colored_polygon(PackedVector2Array([e + Vector2(-20, -100), e + Vector2(40, -100), e + Vector2(5, -10), e + Vector2(45, -10),
					e + Vector2(-35, 110), e + Vector2(-5, 15), e + Vector2(-45, 15)]), A)
		# gold seal with a rosette edge and ribbons
		var s := Vector2(W - 250, 420)
		art.draw_colored_polygon(PackedVector2Array([s + Vector2(-50, 60), s + Vector2(-20, 60), s + Vector2(-35, 125), s + Vector2(-60, 112)]), A)
		art.draw_colored_polygon(PackedVector2Array([s + Vector2(20, 60), s + Vector2(50, 60), s + Vector2(60, 112), s + Vector2(35, 125)]), B)
		var pts := PackedVector2Array()
		for k in 48:
			var an := TAU * k / 48.0
			pts.append(s + Vector2(cos(an), sin(an)) * (100.0 if k % 2 == 0 else 90.0))
		art.draw_colored_polygon(pts, gold)
		art.draw_circle(s, 78, gold.lightened(0.25))
		art.draw_arc(s, 70, 0, TAU, 64, gold.darkened(0.25), 3.0)
	)
	root.add_child(art)
	var seal := Label.new()
	seal.text = String(K.seal)
	seal.add_theme_font_override("font", title_font); seal.add_theme_font_size_override("font_size", 30)
	seal.add_theme_color_override("font_color", Color(0.45, 0.3, 0.05))
	seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.size = Vector2(160, 120); seal.position = Vector2(W - 330, 360); seal.rotation = -0.12
	root.add_child(seal)
	# "OFFICIAL-ISH" rubber stamp
	var stampx := Label.new()
	stampx.text = "OFFICIAL-ISH"
	stampx.add_theme_font_override("font", title_font); stampx.add_theme_font_size_override("font_size", 40)
	stampx.add_theme_color_override("font_color", Color(A, 0.55))
	stampx.rotation = -0.3; stampx.position = Vector2(W - 520, 860)
	root.add_child(stampx)

	# "signatures"
	var sigs: Array = K.sigs
	for k in 2:
		var x: float = 260.0 if k == 0 else W - 760.0
		var sig := Label.new()
		sig.text = String(sigs[k][0])
		sig.add_theme_font_override("font", title_font)
		sig.add_theme_font_size_override("font_size", 40)
		sig.add_theme_color_override("font_color", Color(0.2, 0.25, 0.55))
		sig.rotation = -0.05
		sig.position = Vector2(x + 40, 930)
		root.add_child(sig)
		var sl := ColorRect.new(); sl.color = INK; sl.size = Vector2(500, 3); sl.position = Vector2(x, 990)
		root.add_child(sl)
		var role := Label.new()
		role.text = String(sigs[k][1])
		role.add_theme_font_override("font", med_font)
		role.add_theme_font_size_override("font_size", 26)
		role.add_theme_color_override("font_color", INK)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role.size = Vector2(500, 0); role.position = Vector2(x, 1000)
		root.add_child(role)

	var d := Time.get_date_dict_from_system()
	var stamp := Label.new()
	stamp.text = "Issued %04d-%02d-%02d   ·   No. BNB-%s-%06d" % [d.year, d.month, d.day, kind.to_upper(), randi() % 1000000]
	stamp.add_theme_font_override("font", med_font)
	stamp.add_theme_font_size_override("font_size", 24)
	stamp.add_theme_color_override("font_color", Color(0.4, 0.38, 0.45))
	stamp.position = Vector2(100, H - 168)
	root.add_child(stamp)
	# the important part
	var fun := Label.new()
	fun.text = "Just for fun. Not a real certificate, award, promotion or HR document.\nNo bosses were harmed. Fun intended."
	fun.add_theme_font_override("font", med_font)
	fun.add_theme_font_size_override("font_size", 22)
	fun.add_theme_color_override("font_color", Color(0.45, 0.42, 0.5))
	fun.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fun.size = Vector2(760, 0)
	fun.position = Vector2(W - 860, H - 186)
	root.add_child(fun)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


## One-page PDF (A4 landscape) showing the image. JPEG data goes straight in as a DCTDecode stream.
static func to_pdf(img: Image) -> PackedByteArray:
	var jpg := img.save_jpg_to_buffer(0.92)
	var pw := 842
	var ph := 595
	var out := PackedByteArray()
	var offs: Array = []
	var add := func(s: String): out.append_array(s.to_ascii_buffer())
	add.call("%PDF-1.4\n")
	offs.append(out.size()); add.call("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
	offs.append(out.size()); add.call("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")
	offs.append(out.size()); add.call("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>\nendobj\n" % [pw, ph])
	offs.append(out.size())
	add.call("4 0 obj\n<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length %d >>\nstream\n" % [img.get_width(), img.get_height(), jpg.size()])
	out.append_array(jpg)
	add.call("\nendstream\nendobj\n")
	var content := "q %d 0 0 %d 0 0 cm /Im0 Do Q" % [pw, ph]
	offs.append(out.size()); add.call("5 0 obj\n<< /Length %d >>\nstream\n%s\nendstream\nendobj\n" % [content.length(), content])
	var xref := out.size()
	add.call("xref\n0 6\n0000000000 65535 f \n")
	for o in offs: add.call("%010d 00000 n \n" % o)
	add.call("trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % xref)
	return out


## Save the PDF where the player can find it. Returns a message for the screen.
static func save(pdf: PackedByteArray, player: String, kind := "clash") -> String:
	var fname := "BNB_Certificate_%s.pdf" % player.strip_edges().replace(" ", "_").validate_filename()
	if kind != "clash": fname = "BNB_%s_Certificate_%s.pdf" % [kind.capitalize(), player.strip_edges().replace(" ", "_").validate_filename()]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(pdf, fname, "application/pdf")
		return "Downloaded " + fname
	var dirs := [OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), OS.get_user_data_dir()]
	for d in dirs:
		if d == "": continue
		var path: String = d.path_join(fname)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null: continue
		f.store_buffer(pdf)
		f.close()
		if not OS.has_feature("mobile"): OS.shell_open(path)
		return "Saved to " + path
	return "Couldn't save the certificate on this device."
