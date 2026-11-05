class_name Certificate
## The (completely unofficial) Bit & Bytes certificate for beating the CEO in Arcade.
## Drawn with Controls in an offscreen viewport, then wrapped into a one-page PDF (JPEG image page).
## It's a joke: the disclaimer in the bottom-right corner says so.

const W := 1754   # A4 landscape at 150 dpi
const H := 1240
const PURPLE := Color(0.42, 0.21, 0.59)
const CYAN := Color(0.13, 0.7, 0.85)
const INK := Color(0.12, 0.1, 0.16)


## Render the certificate to an Image (needs two drawn frames, so it's a coroutine).
static func render(host: Node, player: String, C: Dictionary, portrait: Texture2D) -> Image:
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

	var bg := ColorRect.new(); bg.color = Color(0.99, 0.97, 0.93); bg.size = Vector2(W, H)
	root.add_child(bg)
	# double frame
	for inset in [[34, 10, PURPLE], [62, 3, CYAN]]:
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
	mark.size = Vector2(150, 130); mark.position = Vector2(W / 2.0 - 230, 100)
	root.add_child(mark)
	var word := TextureRect.new()
	word.texture = load("res://assets/brand/bnb_wordmark.png")
	word.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	word.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	word.size = Vector2(300, 80); word.position = Vector2(W / 2.0 - 70, 125)
	root.add_child(word)

	text.call("CERTIFICATE OF ACHIEVEMENT", title_font, 76, PURPLE, 255)
	text.call("Bit & Bytes proudly (and slightly nervously) certifies that", med_font, 38, INK, 360)
	var nm: Label = text.call(player.strip_edges().to_upper(), title_font, 96, INK, 420)
	var line := ColorRect.new(); line.color = CYAN; line.size = Vector2(900, 4); line.position = Vector2(W / 2.0 - 450, 545)
	root.add_child(line)
	text.call("has fulfilled the lifelong dream of every employee: beating the CEO in BNB Clashes, fighting as %s, and surviving HR and the Project Manager along the way." % String(C.name), body_font, 36, INK, 570, W - 300.0)
	text.call("Perks:  bragging rights (non-transferable)   ·   promotion pending HR approval   ·   tea still only at 3 PM and 5 PM (Ali has spoken)", med_font, 26, PURPLE, 770, W - 360.0)

	# fighter portrait
	if portrait != null:
		var pr := TextureRect.new()
		pr.texture = portrait
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pr.size = Vector2(190, 190); pr.position = Vector2(W / 2.0 - 95, 820)
		root.add_child(pr)

	# "signatures"
	for sgn in [[260.0, "Hamza Khan", "CEO  (defeated, fair and square)"], [W - 760.0, "Kashaf ud Duja", "HR  (mildly impressed)"]]:
		var x: float = sgn[0]
		var sig := Label.new()
		sig.text = sgn[1]
		sig.add_theme_font_override("font", title_font)
		sig.add_theme_font_size_override("font_size", 40)
		sig.add_theme_color_override("font_color", Color(0.2, 0.25, 0.55))
		sig.rotation = -0.05
		sig.position = Vector2(x + 40, 900)
		root.add_child(sig)
		var sl := ColorRect.new(); sl.color = INK; sl.size = Vector2(500, 3); sl.position = Vector2(x, 960)
		root.add_child(sl)
		var role := Label.new()
		role.text = sgn[2]
		role.add_theme_font_override("font", med_font)
		role.add_theme_font_size_override("font_size", 28)
		role.add_theme_color_override("font_color", INK)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role.size = Vector2(500, 0); role.position = Vector2(x, 970)
		root.add_child(role)

	var d := Time.get_date_dict_from_system()
	var stamp := Label.new()
	stamp.text = "Issued %04d-%02d-%02d   ·   No. BNB-%06d" % [d.year, d.month, d.day, randi() % 1000000]
	stamp.add_theme_font_override("font", med_font)
	stamp.add_theme_font_size_override("font_size", 24)
	stamp.add_theme_color_override("font_color", Color(0.4, 0.38, 0.45))
	stamp.position = Vector2(100, H - 120)
	root.add_child(stamp)
	# the important part
	var fun := Label.new()
	fun.text = "Just for fun. Not a real certificate, award, promotion or HR document.\nNo bosses were harmed. Fun intended."
	fun.add_theme_font_override("font", med_font)
	fun.add_theme_font_size_override("font_size", 22)
	fun.add_theme_color_override("font_color", Color(0.45, 0.42, 0.5))
	fun.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fun.size = Vector2(760, 0)
	fun.position = Vector2(W - 860, H - 132)
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
static func save(pdf: PackedByteArray, player: String) -> String:
	var fname := "BNB_Certificate_%s.pdf" % player.strip_edges().replace(" ", "_").validate_filename()
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
