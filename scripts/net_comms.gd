extends Node
## Text chat and push-to-talk voice for online / Wi-Fi matches (Ludo, Office Ops, Mafia, party games).
## Rides on the match's Party link: guests send to the host, the host shows / plays it and relays to the others.
##   chat  {t = "cm", f = from pid, n = name, c = colour, x = text}
##   voice {t = "vc", f = from pid, n = name, p = base64 μ-law 8 kHz mono}
## Keys: ENTER or T to type (ENTER sends, ESC cancels), hold V to talk. Phones: the CHAT and MIC buttons.

const RATE := 8000              # voice sample rate on the wire
const CHUNK := 480              # 60 ms of voice per packet
const KEEP := 8.0               # seconds a chat line stays on screen

var G
var party: Party
var my_name := ""
var my_col := Color.WHITE
var text_on := true
var voice_ok: Callable          # () -> bool: voice allowed right now (Mafia: only in meetings)
var layer: CanvasLayer
var log_box: VBoxContainer
var input: LineEdit
var talk_lbl: Label
var lines: Array = []           # [Label, time left]
var typing := false
var talking := false
var mic_toggle := false         # phones: tap MIC to start / stop
var mic_player: AudioStreamPlayer
var capture: AudioEffectCapture
var mic_bus := -1
var pending := PackedFloat32Array()
var players := {}               # speaker key -> {player, playback, last}
var speaking := {}              # name -> seconds left on the "talking" badge
var btn_chat: Button
var btn_mic: Button


func setup(g, p: Party, name: String, col: Color, chat := true, can_talk := Callable()) -> void:
	G = g; party = p; my_name = name; my_col = col; text_on = chat
	voice_ok = can_talk if can_talk.is_valid() else func() -> bool: return true
	party.message.connect(_on_message)
	layer = CanvasLayer.new(); layer.layer = 18
	add_child(layer)
	var font: Font = load("res://assets/fonts/Rajdhani-Bold.ttf")
	log_box = VBoxContainer.new()
	log_box.position = Vector2(24, 150)
	log_box.custom_minimum_size = Vector2(520, 0)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_theme_constant_override("separation", 2)
	layer.add_child(log_box)
	input = LineEdit.new()
	input.placeholder_text = "Say something…  (ENTER send · ESC cancel)"
	input.max_length = 120
	input.position = Vector2(24, 360); input.custom_minimum_size = Vector2(520, 44)
	input.add_theme_font_override("font", font); input.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.03, 0.1, 0.9); sb.border_color = Color(0.62, 0.38, 1.0); sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	input.add_theme_stylebox_override("normal", sb); input.add_theme_stylebox_override("focus", sb)
	input.visible = false
	input.text_submitted.connect(_submit)
	layer.add_child(input)
	talk_lbl = Label.new()
	talk_lbl.position = Vector2(24, 110)
	talk_lbl.add_theme_font_override("font", font); talk_lbl.add_theme_font_size_override("font_size", 22)
	talk_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	talk_lbl.add_theme_constant_override("outline_size", 6); talk_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	layer.add_child(talk_lbl)
	if G.ui.touch_enabled:
		var vs: Vector2 = G.get_viewport().get_visible_rect().size
		btn_chat = _touch_btn("CHAT", Vector2(vs.x / 2.0 + 150, 18), func(): open_chat())
		btn_chat.visible = text_on
		btn_mic = _touch_btn("MIC", Vector2(vs.x / 2.0 + 250, 18), func(): mic_toggle = not mic_toggle)


func _touch_btn(text: String, at: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text; b.position = at; b.custom_minimum_size = Vector2(86, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	layer.add_child(b)
	return b


func _exit_tree() -> void:
	if party != null and party.message.is_connected(_on_message): party.message.disconnect(_on_message)
	_stop_mic()
	if G != null: G.set("comms_typing", false)


# ---------------------------------------------------------------- text chat
func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo: return
	if not typing and text_on and e.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_T]:
		open_chat(); get_viewport().set_input_as_handled()


func _input(e: InputEvent) -> void:
	if typing and e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
		close_chat(); get_viewport().set_input_as_handled()


func open_chat() -> void:
	if not text_on: return
	typing = true
	G.set("comms_typing", true)
	input.visible = true; input.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	input.grab_focus()


func close_chat() -> void:
	typing = false
	input.release_focus(); input.visible = false
	G.set("comms_typing", false)
	if G.get("ops") != null and not G.ui.touch_enabled: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # back to aiming


func _submit(t: String) -> void:
	var msg := t.strip_edges()
	close_chat()
	if msg == "": return
	var d := {t = "cm", n = my_name, c = my_col.to_html(false), x = msg}
	if party.is_host:
		d.f = 0
		party.broadcast(d)
	else:
		party.send(d)
	_show(my_name, my_col, msg)


func _show(name: String, col: Color, text: String) -> void:
	var l := Label.new()
	l.text = "%s:  %s" % [name, text]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(520, 0)
	l.add_theme_font_override("font", load("res://assets/fonts/Rajdhani-Bold.ttf"))
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", col.lightened(0.35))
	l.add_theme_constant_override("outline_size", 6); l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	log_box.add_child(l)
	lines.append([l, KEEP])
	while lines.size() > 6:
		(lines[0][0] as Node).queue_free(); lines.pop_front()
	G.sfx("ui")


# ---------------------------------------------------------------- messages
func _on_message(pid: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"cm":
			_show(String(d.get("n", "?")), Color.html(String(d.get("c", "ffffff"))), String(d.get("x", "")))
			if party.is_host:   # relay to everyone else
				d.f = pid
				for p in party.peers():
					if p != pid: party.send_to(p, d)
		"vc":
			var from := int(d.get("f", pid)) if not party.is_host else pid
			_play(str(from) + String(d.get("n", "")), String(d.get("n", "?")), String(d.get("p", "")))
			if party.is_host:
				d.f = pid
				for p in party.peers():
					if p != pid: party.send_to(p, d)


# ---------------------------------------------------------------- voice
func _process(dt: float) -> void:
	for l in lines.duplicate():
		l[1] -= dt
		(l[0] as Label).modulate.a = clampf(l[1], 0.0, 1.0)
		if l[1] <= 0.0: (l[0] as Node).queue_free(); lines.erase(l)
	var want: bool = (mic_toggle or (Input.is_physical_key_pressed(KEY_V) and not typing)) and voice_ok.call()
	if want and not talking: _start_mic()
	elif not want and talking: _stop_mic()
	if talking: _pump_mic()
	for k in speaking.keys():
		speaking[k] -= dt
		if speaking[k] <= 0.0: speaking.erase(k)
	var parts: Array = []
	if talking: parts.append("● YOU")
	for k in speaking: parts.append("● " + String(k))
	talk_lbl.text = ("🎙  " + "   ".join(parts)) if not parts.is_empty() else ("hold V to talk" if not G.ui.touch_enabled and voice_ok.call() else "")
	talk_lbl.modulate.a = 1.0 if not parts.is_empty() else 0.45
	if btn_mic != null: btn_mic.modulate = Color(0.4, 1.0, 0.5) if talking else Color.WHITE


func _start_mic() -> void:
	talking = true
	if mic_bus < 0:
		mic_bus = AudioServer.bus_count
		AudioServer.add_bus(mic_bus)
		AudioServer.set_bus_name(mic_bus, "NetMic")
		AudioServer.set_bus_mute(mic_bus, true)   # never hear yourself
		capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(mic_bus, capture)
	if mic_player == null:
		mic_player = AudioStreamPlayer.new()
		mic_player.stream = AudioStreamMicrophone.new()
		mic_player.bus = "NetMic"
		add_child(mic_player)
	capture.clear_buffer()
	mic_player.play()


func _stop_mic() -> void:
	talking = false
	if mic_player != null: mic_player.stop()
	pending.clear()


## Take what the mic recorded, mix to mono, downsample to 8 kHz, μ-law encode, send in 60 ms packets.
func _pump_mic() -> void:
	if capture == null: return
	var n := capture.get_frames_available()
	if n <= 0: return
	var frames := capture.get_buffer(n)
	var step := AudioServer.get_mix_rate() / RATE
	var acc := 0.0
	for f in frames:
		acc += 1.0
		if acc >= step:
			acc -= step
			pending.append((f.x + f.y) * 0.5)
	while pending.size() >= CHUNK:
		var pkt := PackedByteArray(); pkt.resize(CHUNK)
		for i in CHUNK: pkt[i] = _ulaw_enc(pending[i])
		pending = pending.slice(CHUNK)
		var d := {t = "vc", n = my_name, p = Marshalls.raw_to_base64(pkt)}
		if party.is_host:
			d.f = 0
			party.broadcast(d)
		else:
			party.send(d)


func _play(key: String, name: String, b64: String) -> void:
	if b64 == "": return
	var pkt := Marshalls.base64_to_raw(b64)
	if not players.has(key):
		var p := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new(); gen.mix_rate = RATE; gen.buffer_length = 0.5
		p.stream = gen
		add_child(p)
		p.play()
		players[key] = {player = p, playback = p.get_stream_playback()}
	var pb: AudioStreamGeneratorPlayback = players[key].playback
	var room := pb.get_frames_available()
	for i in mini(pkt.size(), room):
		var v := _ulaw_dec(pkt[i])
		pb.push_frame(Vector2(v, v))
	speaking[name] = 0.4


static func _ulaw_enc(x: float) -> int:
	var s := clampi(int(x * 32635.0), -32635, 32635)
	var sign := 0x80 if s < 0 else 0
	if s < 0: s = -s
	s += 0x84
	var exp := 7
	var mask := 0x4000
	while exp > 0 and (s & mask) == 0:
		exp -= 1; mask >>= 1
	var mant := (s >> (exp + 3)) & 0x0F
	return (~(sign | (exp << 4) | mant)) & 0xFF


static func _ulaw_dec(u: int) -> float:
	u = (~u) & 0xFF
	var sign := u & 0x80
	var exp := (u >> 4) & 0x07
	var mant := u & 0x0F
	var s := (((mant << 3) + 0x84) << exp) - 0x84
	return float(-s if sign != 0 else s) / 32768.0
