class_name Main
extends Node3D
## Game root: arena, camera, combat resolution, effects, audio, match flow.

const GRAV := 0.0072
const ARENA_R := 7.4
const ADDITIVE := preload("res://shaders/additive.gdshader")

const INTRO_FRAMES := 200   # match-start animation, then "FIGHT!" at 45 frames left
var loader: LoadingScreen
var ui: GameUI
var camera: Camera3D
var mode := ""
var cfg := {}
var picks: Array = []
var F: Array = []
var inputs: Array = []
var ai: Array = [null, null]
var wins := [0, 0]
var round_n := 1
var frame := 0
var hitstop := 0
var slow := 0
var shake := 0.0
var time_left := 60
var phase := "menu"
var phase_t := 0
var winner := -1
var cam_a = null
var dummy := 0
var fd = null
var surge_cam = null
var paused := false
var portraits := {}
var preview: Array = [null, null]
var cam_pos := Vector3(0, 1.6, 6)
var cam_look := Vector3(0, 1, 0)
var sparks: Array = []
var rings: Array = []
var spark_i := 0
var ring_i := 0
var sounds := {}
var players: Array = []
var player_i := 0
var t_now := 0.0
var autotest := ""
var stage: Stage
var trials: Array = []
var trial_i := 0
var trial_step := 0
var trial_done := {}

const DUMMY := ["Stand (no guard)", "Guard all", "Crouch", "CPU"]


static func make_rig(C: Dictionary, costume := 0) -> Node3D:
	var r = VrmRig.new() if VrmRig.has_model(C) else ToonRig.new()
	if r is VrmRig:
		r.costume = costume
	r.build(C)
	return r


func _ready() -> void:
	loader = LoadingScreen.new()
	add_child(loader)
	loader.open("LOADING")
	await get_tree().process_frame
	Data.load_all()
	net = Net.new()
	add_child(net)
	net.message.connect(net_message)
	await ClipLib.load_all_async(get_tree(), func(f): loader.progress("LOADING MOVES", f * 0.7))
	_setup_input_map()
	if OS.has_feature("mobile") or "--phone" in OS.get_cmdline_user_args():
		# phones: the whole 2D UI 25% larger (menus are laid out for a 900-unit-tall screen)
		get_window().content_scale_factor = 1.25
	if OS.has_feature("mobile"):
		# Phones: lighter shadows, no MSAA, slightly reduced 3D resolution (UI stays sharp).
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().scaling_3d_scale = 0.8
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
	set_stage("open_office")
	_build_fx()
	_build_audio()
	camera = Camera3D.new()
	camera.fov = 38
	camera.far = 200
	add_child(camera)
	ui = GameUI.new()
	ui.G = self
	add_child(ui)
	ui.build()
	portraits = await _make_portraits()
	loader.close()
	if OS.has_feature("web"):
		# a shared room link (…/?room=CODE) opens straight into that room
		var q = JavaScriptBridge.eval("new URLSearchParams(location.search).get('room') || ''")
		if q is String and q != "":
			ui.show_join(q)
			return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			autotest = a.substr(11)
	if autotest != "":
		_run_autotest()
	else:
		ui.show_title()


func _setup_input_map() -> void:
	var add := func(action: String, key: Key) -> void:
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(action, e)
	add.call("ui_up", KEY_W); add.call("ui_down", KEY_S); add.call("ui_left", KEY_A); add.call("ui_right", KEY_D)
	add.call("ui_accept", KEY_U); add.call("ui_cancel", KEY_J)


# ------------------------------------------------------------------ world
func _mesh(m: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m; mi.material_override = mat; mi.position = pos; mi.rotation = rot
	add_child(mi)
	return mi


func set_stage(sid: String) -> void:
	if stage != null and stage.id == sid: return
	if stage != null: stage.queue_free()
	stage = Stage.make(sid)
	add_child(stage)


func _build_fx() -> void:
	var oct := SphereMesh.new(); oct.radius = 0.035; oct.height = 0.07; oct.radial_segments = 4; oct.rings = 2
	for i in 100:
		var m := ShaderMaterial.new(); m.shader = ADDITIVE
		var mi := _mesh(oct, m)
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("v", Vector3.ZERO); mi.set_meta("life", 0.0); mi.set_meta("max", 1.0)
		sparks.append(mi)
	var tor := TorusMesh.new(); tor.inner_radius = 0.15; tor.outer_radius = 0.2; tor.ring_segments = 4
	for i in 8:
		var m := ShaderMaterial.new(); m.shader = ADDITIVE
		var mi := _mesh(tor, m)
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("life", 0.0); mi.set_meta("size", 1.0)
		rings.append(mi)


func burst(p: Vector3, color: Color, n: int, speed: float) -> void:
	if resim: return
	for i in n:
		var mi: MeshInstance3D = sparks[spark_i % sparks.size()]
		spark_i += 1
		mi.position = p; mi.visible = true
		mi.material_override.set_shader_parameter("color", color)
		var v := Vector3(randf() - 0.5, randf() * 0.8, randf() - 0.5).normalized() * speed * randf_range(0.4, 1.2)
		var life := randf_range(0.25, 0.5)
		mi.set_meta("v", v); mi.set_meta("life", life); mi.set_meta("max", life)


func ring(p: Vector3, color: Color, size: float) -> void:
	if resim: return
	var mi: MeshInstance3D = rings[ring_i % rings.size()]
	ring_i += 1
	mi.position = p; mi.visible = true
	mi.material_override.set_shader_parameter("color", color)
	mi.set_meta("life", 0.25); mi.set_meta("size", size)


func _update_fx(dt: float) -> void:
	for mi in sparks:
		if not mi.visible: continue
		var life: float = mi.get_meta("life") - dt
		if life <= 0:
			mi.visible = false; continue
		var v: Vector3 = mi.get_meta("v")
		mi.position += v * dt
		v.y -= 7.0 * dt
		mi.set_meta("v", v); mi.set_meta("life", life)
		var k: float = life / mi.get_meta("max")
		mi.material_override.set_shader_parameter("alpha", k)
		mi.scale = Vector3.ONE * (0.6 + k)
	for mi in rings:
		if not mi.visible: continue
		var life: float = mi.get_meta("life") - dt
		if life <= 0:
			mi.visible = false; continue
		mi.set_meta("life", life)
		var t := 1.0 - life / 0.25
		mi.scale = Vector3.ONE * mi.get_meta("size") * (1.0 + t * 5.0)
		mi.material_override.set_shader_parameter("alpha", 1.0 - t)
		mi.look_at(camera.global_position)
		mi.rotate_object_local(Vector3.RIGHT, PI / 2)


# ------------------------------------------------------------------ audio (synthesized)
func _build_audio() -> void:
	for k in ["hit", "heavy", "block", "whoosh", "thud", "grab", "ko", "surge", "ui", "ok", "vs"]:
		sounds[k] = _synth(k)
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6
		add_child(p)
		players.append(p)


func _synth(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var spec := {
		hit = [0.12, 1400.0, 0.7, 140.0, 55.0, 0.6], heavy = [0.28, 900.0, 0.9, 110.0, 35.0, 0.9],
		block = [0.06, 6000.0, 0.45, 1500.0, 900.0, 0.12], whoosh = [0.14, 1800.0, 0.18, 0.0, 0.0, 0.0],
		thud = [0.2, 300.0, 0.6, 70.0, 40.0, 0.5], grab = [0.08, 900.0, 0.4, 0.0, 0.0, 0.0],
		ko = [1.1, 600.0, 0.8, 200.0, 30.0, 0.35], surge = [0.5, 2500.0, 0.3, 220.0, 880.0, 0.25],
		ui = [0.05, 0.0, 0.0, 660.0, 990.0, 0.08], ok = [0.14, 0.0, 0.0, 520.0, 1560.0, 0.1], vs = [0.6, 500.0, 0.7, 90.0, 45.0, 0.3],
	}
	var s: Array = spec[kind]
	var dur: float = s[0]
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var a: float = exp(-TAU * maxf(1.0, s[1]) / rate) if s[1] > 0 else 0.0
	var phase_acc := 0.0
	for i in n:
		var t := float(i) / rate
		var env := pow(1.0 - t / dur, 2.0)
		var nz := randf() * 2.0 - 1.0
		lp = lp * a + nz * (1.0 - a)
		var v: float = lp * s[2] * (3.0 if kind == "block" else 1.6)
		if kind == "block":
			v = (nz - lp) * s[2]   # high-passed click
		if s[5] > 0:
			var f: float = s[3] * pow(s[4] / s[3], t / dur)
			phase_acc += TAU * f / rate
			var wave := sin(phase_acc) if kind != "ko" else fposmod(phase_acc / TAU, 1.0) * 2.0 - 1.0
			v += wave * s[5]
		data.encode_s16(i * 2, int(clampf(v * env, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


var voice_players: Array = []


## A fighter's voice: attack / heavy / hurt / ko / power / win. Throttled so grunts don't stack up.
func voice(f: Fighter, kind: String) -> void:
	if resim or f == null: return
	var now := Time.get_ticks_msec()
	if kind in ["attack", "hurt"] and now - f.voice_at < 260: return
	f.voice_at = now
	var s := Voices.get_sound(f.C, kind)
	if s == null: return
	if voice_players.is_empty():
		for i in 4:
			var vp := AudioStreamPlayer.new(); vp.volume_db = -3; add_child(vp); voice_players.append(vp)
	var p: AudioStreamPlayer = voice_players[f.side * 2 + (1 if kind in ["hurt", "ko"] else 0)]
	p.stream = s
	p.pitch_scale = randf_range(0.97, 1.04)
	p.play()


## Blood droplets from a hard hit (cosmetic).
func blood(at: Vector3, dir: Vector3, amount: int) -> void:
	if resim: return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.02, 0.04)
	m.roughness = 0.3
	var mesh := SphereMesh.new(); mesh.radius = 0.018; mesh.height = 0.036; mesh.radial_segments = 6; mesh.rings = 3
	for k in amount:
		var d := MeshInstance3D.new()
		d.mesh = mesh; d.material_override = m
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
		d.position = at
		var v := (dir * randf_range(0.6, 1.6) + Vector3(randf_range(-0.6, 0.6), randf_range(0.4, 1.4), randf_range(-0.6, 0.6))) * 1.6
		var land := Vector3(at.x + v.x * 0.35, 0.01, at.z + v.z * 0.35)
		var tw := d.create_tween()
		tw.tween_method(func(u: float):
			d.position = at.lerp(land, u) + Vector3(0, sin(u * PI) * 0.35 * v.y * 0.4, 0), 0.0, 1.0, randf_range(0.35, 0.55))
		tw.tween_property(d, "scale", Vector3(2.2, 0.15, 2.2), 0.06)   # splat on the floor
		tw.tween_interval(4.0)
		tw.tween_property(d, "scale", Vector3(0.01, 0.01, 0.01), 0.6)
		tw.tween_callback(d.queue_free)


func sfx(k: String) -> void:
	if resim: return
	if not sounds.has(k): return
	var p: AudioStreamPlayer = players[player_i % players.size()]
	player_i += 1
	p.stream = sounds[k]
	p.play()


# ------------------------------------------------------------------ portraits
func _make_portraits() -> Dictionary:
	var out := {}
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new(); cam.fov = 26
	vp.add_child(cam)
	var key := DirectionalLight3D.new(); key.light_energy = 1.4; key.rotation = Vector3(deg_to_rad(-30), deg_to_rad(20), 0)
	vp.add_child(key)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.75, 0.95); env.environment.ambient_light_energy = 0.7
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vp.add_child(env)
	DirAccess.make_dir_recursive_absolute("user://portraits")
	for C in Data.ROSTER:
		if loader: loader.progress("PREPARING FIGHTERS", 0.7 + 0.3 * float(Data.ROSTER.find(C)) / Data.ROSTER.size())
		# portraits are cached on disk and only re-rendered when the fighter's look changes
		var cache := "user://portraits/%s_%d.png" % [C.id, hash(str(Models.spec(C.id, 0)) + str(C.scale))]
		if FileAccess.file_exists(cache):
			var cimg := Image.load_from_file(cache)
			if cimg != null and not cimg.is_empty():
				out[C.id] = ImageTexture.create_from_image(cimg)
				continue
		var rig := make_rig(C)
		vp.add_child(rig)
		rig.apply_pose(C.pose.guard)
		rig.rotation.y = -0.45
		var hp: Vector3 = rig.head.global_position
		cam.position = hp + Vector3(0.3, 0.08, 1.55)
		cam.look_at(hp + Vector3(0, -0.02, 0))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		out[C.id] = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else PlaceholderTexture2D.new()
		if img != null and not img.is_empty(): img.save_png(cache)
		rig.queue_free()
	vp.queue_free()
	return out


# ------------------------------------------------------------------ input
const KM := [
	{l = [KEY_A], r = [KEY_D], u = [KEY_W], d = [KEY_S], b = [[KEY_U], [KEY_I], [KEY_J], [KEY_K]]},
	{l = [KEY_LEFT], r = [KEY_RIGHT], u = [KEY_UP], d = [KEY_DOWN], b = [[KEY_KP_4, KEY_O], [KEY_KP_5, KEY_P], [KEY_KP_1, KEY_L], [KEY_KP_2, KEY_SEMICOLON]]},
]
var test_keys := {}   # used by autotest to fake key presses


func _key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k) or test_keys.get(k, false)


func _raw(i: int) -> Array:
	var m: Dictionary = KM[i]
	var any := func(a: Array) -> bool:
		for k in a:
			if _key(k): return true
		return false
	var held := 0
	for j in 4:
		if any.call(m.b[j]): held |= 1 << j
	var x: int = (1 if any.call(m.r) else 0) - (1 if any.call(m.l) else 0)
	var y: int = (1 if any.call(m.u) else 0) - (1 if any.call(m.d) else 0)
	return [x, y, held]


func _pad(i: int):
	var pads := Input.get_connected_joypads()
	if i >= pads.size(): return null
	var dev: int = pads[i]
	var x := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	var y := -Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT): x = -1
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT): x = 1
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_UP): y = 1
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN): y = -1
	var held := 0
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_X): held |= 1
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_Y): held |= 2
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_A): held |= 4
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_B): held |= 8
	return [int(signf(x)) if absf(x) > 0.5 else 0, int(signf(y)) if absf(y) > 0.5 else 0, held]


func read_player(i: int) -> InputBuf.Frame:
	var inp: InputBuf = inputs[i]
	if mode == "online":
		var n: Array = net_in[i].get(nf, [0, 0, 0])
		return inp.frame(n[0] if i == 0 else -n[0], n[1], n[2])
	if ai[i] != null:
		var o: Array = ai[i].think(F[i], F[1 - i])
		return inp.frame(o[0], o[1], o[2])
	if i == 1 and mode == "training":
		var o := _dummy_think()
		return inp.frame(o[0], o[1], o[2])
	var r := _raw(i)
	if mode != "2p" and i == 0:
		var r2 := _raw(1)
		r = [clampi(r[0] + r2[0], -1, 1), clampi(r[1] + r2[1], -1, 1), r[2] | r2[2]]
	if i == 0 and ui.touch != null and ui.touch.visible:
		var t: TouchControls = ui.touch
		r = [clampi(r[0] + t.x, -1, 1), clampi(r[1] + t.y, -1, 1), r[2] | t.held]
	var p = _pad(i)
	if p != null:
		r = [clampi(r[0] + p[0], -1, 1), clampi(r[1] + p[1], -1, 1), r[2] | p[2]]
	# Camera keeps P1 on the left, so "right" means forward for P1 and back for P2.
	return inp.frame(r[0] if i == 0 else -r[0], r[1], r[2])


## This device's controls (keyboard, touch, first gamepad), screen-relative: [x, y, held buttons].
func _device_raw() -> Array:
	if test_net_input.is_valid(): return test_net_input.call(nf)
	var r := _raw(0)
	var r2 := _raw(1)
	r = [clampi(r[0] + r2[0], -1, 1), clampi(r[1] + r2[1], -1, 1), r[2] | r2[2]]
	if ui.touch != null and ui.touch.visible:
		r = [clampi(r[0] + ui.touch.x, -1, 1), clampi(r[1] + ui.touch.y, -1, 1), r[2] | ui.touch.held]
	var p = _pad(0)
	if p != null:
		r = [clampi(r[0] + p[0], -1, 1), clampi(r[1] + p[1], -1, 1), r[2] | p[2]]
	return r


var test_net_input: Callable   # autotest: scripted controls for online tests


func _dummy_think() -> Array:
	var A: Fighter = F[0]
	var B: Fighter = F[1]
	B.no_guard = dummy == 0
	if dummy == 2: return [0, -1, 0]
	if dummy == 1 and A.state == "attack" and A.move.lvl == "low": return [-1, -1, 0]
	return [0, 0, 0]


# ------------------------------------------------------------------ match flow
func start_match(c: Dictionary, p: Array) -> void:
	loader.open("LOADING FIGHT")
	await get_tree().process_frame
	await get_tree().process_frame
	clear_preview()
	for f in F:
		f.rig.queue_free()
	F = []   # nothing ticks or renders while the new fight loads
	cfg = c; picks = p; mode = c.mode
	set_stage(c.get("stage", Stage.LIST.pick_random().id))
	var cos: Array = c.get("costumes", [0, 0])
	loader.progress("LOADING " + String(p[0].name).to_upper(), 0.3)
	await get_tree().process_frame
	var f0 := Fighter.new(self, p[0], 0, cos[0])
	loader.progress("LOADING " + String(p[1].name).to_upper(), 0.65)
	await get_tree().process_frame
	F = [f0, Fighter.new(self, p[1], 1, cos[1])]
	inputs = [InputBuf.new(), InputBuf.new()]
	ai = [null, FighterAI.new(self, c.lv) if mode == "cpu" else null]
	wins = [0, 0]; round_n = 1; frame = 0; dummy = 0; fd = null; paused = false
	trials = Data.trials(p[0]) if mode == "training" else []
	trial_i = 0; trial_step = 0; trial_done = {}
	ui.hide_screen()
	ui.show_hud(self)
	start_round()
	loader.close()


func start_round() -> void:
	F[0].reset(-1.2); F[1].reset(1.2)
	ui.chip = [100.0, 100.0]
	time_left = 60; hitstop = 0; slow = 0; winner = -1; cam_a = null; surge_cam = null
	ui.set_round_label("TRAINING" if mode == "training" else "ROUND %d" % round_n)
	if mode == "training":
		phase = "fight"; F[0].meter = 100.0
		return
	phase = "intro"; phase_t = INTRO_FRAMES
	ui.announce("FINAL ROUND" if wins[0] == 1 and wins[1] == 1 else "ROUND %d" % round_n, "")


func ko_start(w: Fighter) -> void:
	if phase != "fight": return
	phase = "ko"; phase_t = 210; winner = w.side; slow = 60
	ui.announce("PERFECT K.O." if w.hp >= w.max_hp else "K.O.", "ko")
	sfx("ko")
	voice(F[1 - w.side], "ko")


func time_up() -> void:
	var a: float = F[0].hp / F[0].max_hp
	var b: float = F[1].hp / F[1].max_hp
	phase = "ko"; phase_t = 170
	winner = 0 if a > b else 1 if b > a else -1
	ui.announce("TIME", "ko")


func end_round() -> void:
	if winner == -1:
		wins[0] += 1; wins[1] += 1
	else:
		wins[winner] += 1
	if wins[0] >= 2 or wins[1] >= 2:
		phase = "end"
		ui.show_end_delayed()
	else:
		round_n += 1
		start_round()


# ------------------------------------------------------------------ arcade
## Arcade: four colleagues, then HR (mini boss), the PM (bonus boss) and the CEO (final boss).
var arcade = null   # {player, cos, ladder: [{C, kind, stage, lv}], i}


func start_arcade(C: Dictionary, cos: int) -> void:
	var pool := Data.ROSTER.filter(func(x): return x.get("boss", "") == "" and x.id != C.id)
	pool.shuffle()
	var ladder := []
	var stages := ["open_office", "server_room", "cafeteria", "boardroom"]
	stages.shuffle()
	for k in mini(4, pool.size()):
		ladder.append({C = pool[k], kind = "", stage = stages[k % stages.size()], lv = 1 if k < 2 else 2})
	for b in [["mini", "open_office"], ["bonus", "boardroom"], ["final", "rooftop"]]:
		var B := Data.boss_of(b[0])
		if B.is_empty() or (B.id == C.id and b[0] != "final"): continue
		ladder.append({C = Data.boss_form(B), kind = b[0], stage = b[1], lv = Data.BOSS_FORM[b[0]].lv})
	arcade = {player = C, cos = cos, ladder = ladder, i = 0}
	ui.show_ladder()


func arcade_fight() -> void:
	var e: Dictionary = arcade.ladder[arcade.i]
	var opp_cos := 1 if e.C.id == arcade.player.id else 0   # mirror match: different outfit
	ui.show_vs({mode = "cpu", lv = e.lv, stage = e.stage, arcade = true, costumes = [arcade.cos, opp_cos]}, [arcade.player, e.C])


# ------------------------------------------------------------------ BNB Rush Hour
var race: RaceGame


func start_race(track_id: String, C: Dictionary) -> void:
	loader.open("LOADING RACE")
	await get_tree().process_frame
	await get_tree().process_frame
	clear_preview()
	if stage != null: stage.visible = false
	ui.hide_screen()
	ui.view = "race"
	ui.hide_hud()
	race = RaceGame.new()
	add_child(race)
	race.start(self, track_id, C)
	race.finished.connect(end_race)
	loader.close()


# ------------------------------------------------------------------ BNB Office Ops
var ops: OpsGame


func start_ops(C: Dictionary, cfg: Dictionary) -> void:
	loader.open("DEPLOYING")
	await get_tree().process_frame
	await get_tree().process_frame
	clear_preview()
	if stage != null: stage.visible = false
	ui.hide_screen(); ui.view = "ops"; ui.hide_hud()
	# teams: you + colleagues vs colleagues; the CEO / bosses are fair game too
	var pool := Data.ROSTER.filter(func(c): return c.id != C.id)
	pool.shuffle()
	var a := [C] + pool.slice(0, int(cfg.mine) - 1)
	var b := pool.slice(int(cfg.mine) - 1, int(cfg.mine) - 1 + int(cfg.them))
	ops = OpsGame.new()
	add_child(ops)
	ops.start(self, a, b, String(cfg.gun), float(cfg.skill))
	ops.finished.connect(end_ops)
	loader.close()


func end_ops() -> void:
	if ops != null:
		ops.stop(); ops.queue_free(); ops = null
	if stage != null: stage.visible = true
	camera.current = true


func end_race() -> void:
	if race != null:
		race.stop(); race.queue_free(); race = null
	if stage != null: stage.visible = true
	camera.current = true


func leave_game() -> void:
	for f in F:
		f.rig.queue_free()
	F = []
	phase = "menu"; paused = false
	ui.hide_hud()


func _physics_process(_dt: float) -> void:
	if mode == "online":
		if not F.is_empty(): _net_step()
		return
	if F.is_empty() or paused or phase == "menu":
		return
	tick()


# ------------------------------------------------------------------ online (lockstep)
# Both games run exactly the same fight: each sends its own controls for a tick a few frames ahead
# (net_delay hides the network delay) and a tick only runs once both players' controls for it are here.
# Every second the guest compares a fingerprint of the fight with the host's; if they ever differ
# (e.g. float differences between a phone and a PC) the host sends its full state and the guest
# snaps to it, then re-runs the few ticks it had already played.
var net: Net
var local_side := 0
var nf := 0                       # fight ticks run so far, identical on both games
var net_delay := 3
var net_in: Array = [{}, {}]      # side -> {tick: [x, y, held]}
var local_next := 1
var net_hash: Array = [{}, {}]    # [ours, host's]: tick -> fingerprint (guest only)
var snap_pending = null
var snap_requested := false
var send_snap := false
var resim := false                # re-running ticks after a resync: no sounds or effects
var net_stall := 0
var net_ping := {sent = 0, ms = 0}
const NET_SKIP := ["G", "C", "rig", "flash", "disp", "from", "pose_vel", "prev_disp", "prev_pos", "prev_face", "anim_t", "last_rt",
	"voice_at", "bruise", "dirt", "blood_on", "held_prop"]   # cosmetic, not fight state


## Input delay for this connection: the one-way trip in ticks, plus one for jitter.
func suggest_delay() -> int:
	return clampi(int(ceil(net_ping.ms / 2.0 / 16.7)) + 1, 2, 8)


const WEB_URL := "https://abdulwasay-bnb.github.io/bnb-clashes/"


func room_link(code: String) -> String:
	return WEB_URL + "?room=" + code


var online_matches := 0   # online matches started this session (autotests use it to spot a rematch)


func start_online(c: Dictionary, p: Array) -> void:
	online_matches += 1
	local_side = 0 if net.is_host else 1
	ui.online.rematch = [false, false]
	net_delay = clampi(int(c.get("delay", 3)), 2, 10)
	nf = 0
	net_in = [{}, {}]; net_hash = [{}, {}]
	snap_pending = null; snap_requested = false; send_snap = false; net_stall = 0
	for k in range(1, net_delay + 1):
		net_in[0][k] = [0, 0, 0]; net_in[1][k] = [0, 0, 0]
	local_next = net_delay + 1
	await start_match(c, p)


func _net_step() -> void:
	net.poll()
	if not net.connected: return
	var steps := 0
	while true:
		# sample this device's controls for a tick a few frames ahead
		while local_next <= nf + net_delay:
			var r := _device_raw()
			net_in[local_side][local_next] = r
			net.send({t = "in", f = local_next, d = r})
			local_next += 1
		# catch up at most one extra tick per frame when the opponent is ahead
		if steps >= 2 or not (net_in[0].has(nf + 1) and net_in[1].has(nf + 1)): break
		nf += 1
		tick()
		_net_after_tick()
		steps += 1
	net_stall = 0 if steps > 0 else net_stall + 1


func _net_after_tick() -> void:
	net_in[0].erase(nf - 300); net_in[1].erase(nf - 300)
	if autotest.begins_with("net") or autotest.begins_with("lan"):
		if nf % 300 == 0: print("AUTOTEST net tick %d hash %d" % [nf, _state_hash()])
	if nf % 60 == 0:
		var h := _state_hash()
		if net.is_host:
			net.send({t = "h", f = nf, h = h})
		else:
			net_hash[0][nf] = h
			_check_hash(nf)
	if send_snap:
		send_snap = false
		net.send({t = "snap", f = nf, s = Marshalls.raw_to_base64(var_to_bytes(_snapshot()))})
	if snap_pending != null and nf >= snap_pending.f:
		_apply_snap()


func _check_hash(f: int) -> void:
	if not (net_hash[0].has(f) and net_hash[1].has(f)): return
	var same: bool = net_hash[0][f] == net_hash[1][f]
	net_hash[0].erase(f); net_hash[1].erase(f)
	if not same and not snap_requested:
		snap_requested = true
		print("NET desync at tick %d, resyncing from host" % f)
		net.send({t = "resync"})


func _apply_snap() -> void:
	var s: Dictionary = snap_pending
	snap_pending = null; snap_requested = false
	var target := nf
	_restore(bytes_to_var(Marshalls.base64_to_raw(s.s)))
	nf = s.f
	resim = true
	while nf < target:
		nf += 1
		tick()
	resim = false
	net_hash = [{}, {}]
	print("NET resynced from host tick %d, replayed %d ticks" % [s.f, target - s.f])


func net_message(d: Dictionary) -> void:
	match d.get("t", ""):
		"in": net_in[1 - local_side][int(d.f)] = [int(d.d[0]), int(d.d[1]), int(d.d[2])]
		"h":
			net_hash[1][int(d.f)] = int(d.h)
			_check_hash(int(d.f))
		"resync": send_snap = true
		"snap": snap_pending = {f = int(d.f), s = d.s}
		"ping": net.send({t = "pong", ms = d.ms})
		"pong": net_ping.ms = Time.get_ticks_msec() - int(d.ms)
		_: ui.net_message(d)


## Fingerprint of everything that decides the fight (rounded, so it only trips on real divergence).
func _state_hash() -> int:
	var a := [time_left, phase, phase_t, wins, round_n, hitstop]
	for f in F:
		a.append_array([f.pos.snapped(Vector3.ONE * 0.01), roundf(f.hp), f.state, f.sf, roundf(f.meter), f.move.key if f.move else ""])
	return hash(str(a))


func _snapshot() -> Dictionary:
	return {m = {frame = frame, hitstop = hitstop, slow = slow, time_left = time_left, phase = phase, phase_t = phase_t,
		winner = winner, wins = wins.duplicate(), round_n = round_n},
		f = [_obj_state(F[0]), _obj_state(F[1])], i = [_obj_state(inputs[0]), _obj_state(inputs[1])]}


func _obj_state(o: Object) -> Dictionary:
	var d := {}
	for p in o.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or p.name in NET_SKIP: continue
		d[p.name] = _enc(o.get(p.name))
	return d


func _enc(v):
	if v is Fighter: return {"#f": v.side}
	if v is Data.Move:
		for s in 2:
			if F[s].C.moves.get(v.key) == v: return {"#m": v.key, "s": s}
		return null
	if v is Object: return null
	if v is Dictionary:
		var o := {}
		for k in v: o[k] = _enc(v[k])
		return o
	if v is Array: return v.map(_enc)
	return v


func _dec(v):
	if v is Dictionary:
		if v.has("#f"): return F[int(v["#f"])]
		if v.has("#m"): return F[int(v.s)].C.moves.get(v["#m"])
		var o := {}
		for k in v: o[k] = _dec(v[k])
		return o
	if v is Array: return v.map(_dec)
	return v


func _restore(s: Dictionary) -> void:
	for k in s.m: set(k, s.m[k])
	for i in 2:
		for k in s.f[i]: F[i].set(k, _dec(s.f[i][k]))
		for k in s.i[i]: inputs[i].set(k, _dec(s.i[i][k]))


func tick() -> void:
	var ins := [read_player(0), read_player(1)]
	if hitstop > 0:
		hitstop -= 1
		F[0].collect(ins[0]); F[1].collect(ins[1])
		return
	if slow > 0:
		slow -= 1
		if slow % 3: return
	frame += 1
	F[0].save_prev(); F[1].save_prev()
	var A: Fighter = F[0]
	var B: Fighter = F[1]
	var live := phase == "fight"
	A.control(ins[0] if live else InputBuf.NEUTRAL)
	B.control(ins[1] if live else InputBuf.NEUTRAL)
	A.step(B); B.step(A)
	var r1 = check(A, B)
	var r2 = check(B, A)       # resolve simultaneously so trades are possible
	if r1 != null: r1.m = A.move; r1.rem = remaining(A)
	if r2 != null: r2.m = B.move; r2.rem = remaining(B)
	if r1 != null: apply_hit(A, B, r1)
	# A throw and a hit landing on the same frame: the grab wins, the other hit is dropped
	# (otherwise the thrower gets knocked out of the throw and the victim is left frozen).
	var grabbed := A.state in ["throwing", "thrown"] or B.state in ["throwing", "thrown"]
	if r2 != null and not (grabbed and r2.type != "throw"): apply_hit(B, A, r2)
	A.physics(); B.physics(); separate(A, B)
	if A.state in Fighter.FREE_FACE: A.face_to(B, 0.3)
	if B.state in Fighter.FREE_FACE: B.face_to(A, 0.3)
	A.tick_pose(); B.tick_pose()
	if surge_cam != null:
		surge_cam.t -= 1
		if surge_cam.t <= 0: surge_cam = null
	match phase:
		"intro":
			phase_t -= 1
			if phase_t == 45: ui.announce("FIGHT!", "fight")
			if phase_t <= 0: phase = "fight"
		"fight":
			if mode == "training": training_tick()
			elif frame % 60 == 0:
				time_left -= 1
				if time_left <= 0: time_up()
		"ko":
			var w: Fighter = F[winner] if winner >= 0 else null
			if w != null and phase_t < 110 and w.can_act():
				w.set_state("win"); voice(w, "win")
			phase_t -= 1
			if phase_t <= 0: end_round()


# ------------------------------------------------------------------ combat
func remaining(att: Fighter) -> int:
	return att.move.end - att.sf


func check(att: Fighter, def: Fighter):
	if att.state != "attack" or att.has_hit: return null
	var m := att.move
	if m.trans or att.sf < m.s or att.sf >= m.s + m.a: return null   # only active frames hit
	if def.state in Fighter.INVULN: return null
	var fx := sin(att.face)
	var fz := cos(att.face)
	var dx := def.pos.x - att.pos.x
	var dz := def.pos.z - att.pos.z
	var fwd := dx * fx + dz * fz
	var lat := absf(dx * fz - dz * fx)
	var air := def.state == "air"
	var ds: float = def.C.scale
	# Airborne bodies are bigger targets, which keeps juggles consistent.
	if fwd < -0.1 or fwd > m.range * att.C.scale + 0.22 * ds + (0.35 if air else 0.0) or lat > 0.32 * ds + (0.25 if air else 0.05):
		return null
	if m.is_throw:
		return null if (air or def.is_low() or def.state in ["hit", "block"] or def.is_jumping()) else {type = "throw", fwd = fwd}
	if air:
		return null if (def.juggle >= 10 or (m.lvl == "low" and def.pos.y > 0.45)) else {type = "hit", fwd = fwd, ch = false}
	if m.lvl == "high" and def.is_low(): return null     # highs whiff on crouchers
	if m.lvl == "low" and def.is_jumping(): return null  # lows whiff on hops
	if def.state == "attack" and def.move.armor and def.sf < def.move.s and not def.armor_used:
		return {type = "armor", fwd = fwd}
	if def.is_blocking(m.lvl): return {type = "block", fwd = fwd}
	return {type = "hit", fwd = fwd, ch = def.state == "attack" and def.sf < def.move.s}


func hurt(def: Fighter, dmg: int, att: Fighter) -> void:
	def.hp = maxf(1.0 if mode == "training" else 0.0, def.hp - dmg)
	# wear and tear: bruising and a swelling eye build up over the match
	def.bruise = minf(1.0, def.bruise + dmg / def.max_hp * 1.6)
	if dmg >= 6 and def.hp > 0.0 and randf() < 0.75: voice(def, "hurt")
	att.meter = minf(100.0, att.meter + dmg * 0.9)
	def.meter = minf(100.0, def.meter + dmg * 1.1)


func apply_hit(att: Fighter, def: Fighter, res: Dictionary) -> void:
	var m: Data.Move = res.m   # snapshot: a trade may already have cancelled att.move
	var rem: int = res.rem
	var f := att.fwd()
	att.has_hit = true
	if res.type == "throw":
		if att.state != "attack": return   # the grab was interrupted in the same frame
		start_throw(att, def, m); return
	var air := def.state == "air"
	var was_low := def.is_low()
	var hy: float = def.pos.y + 0.95 if air else (1.5 if m.lvl == "high" else 0.35 if m.lvl == "low" else 1.05) * def.C.scale
	var d := maxf(0.25, res.fwd - 0.28 * def.C.scale)
	var cp := Vector3(att.pos.x + f.x * d, hy, att.pos.z + f.z * d)
	if res.type != "block" and (m.surge or m.launch or m.kd or res.ch or m.dmg >= 16):
		blood(cp, f, 10 if m.surge else 6)
		def.blood_on = minf(1.0, def.blood_on + 0.18)
	if res.type == "armor":
		hurt(def, roundi(m.dmg * att.C.power * 0.6), att); def.armor_used = true; def.flash = 1.0
		hitstop = 8; burst(cp, Color(1, 0.82, 0.4), 14, 3.0); sfx("block"); ui.pop_text("ARMOR", def.side)
		return
	if res.type == "block":
		def.set_state("block"); def.stun = maxi(4, rem + int(m.blk if m.blk != null else 0))
		def.crouch_block = m.lvl == "low"
		def.vel = f * (m.push * 0.8 if m.push > 0 else 0.05)
		att.meter = minf(100.0, att.meter + 2); def.meter = minf(100.0, def.meter + 3)
		def.kick(m.lvl, m.dmg / 10.0, true)
		hitstop = 5; burst(cp, Color(0.5, 0.85, 1.0), 10, 2.5); sfx("block"); fd_log(att, "BLOCK")
		return
	# Damage scaling: each extra hit in a combo is worth 10% less (min 30%).
	var sc := maxf(0.3, 1.0 - 0.1 * def.combo_hits) if def.combo_hits > 0 else 1.0
	var dmg := maxi(1, roundi(m.dmg * att.C.power * sc * (1.2 if res.ch else 1.0)))
	hurt(def, dmg, att); def.combo_hits += 1; def.combo_dmg += dmg; def.flash = 1.0
	var launch: bool = m.launch or (res.ch and m.ch_launch)
	if air or launch or m.kd or def.hp <= 0:
		if air:
			def.vy = maxf(def.vy, maxf(0.028, 0.072 - 0.006 * def.juggle)); def.air_v = f * 0.008; def.juggle += 1
		elif launch:
			def.vy = 0.14; def.air_v = f * 0.003; def.juggle = 1; def.pos.y = 0.01
			if att.state == "attack" and att.move == m:
				att.sf = maxi(att.sf, m.end - 12)   # a landed launcher recovers fast enough to juggle
		else:
			def.vy = 0.12 if m.surge else 0.08; def.air_v = f * (0.075 if m.surge else 0.04); def.juggle = 7; def.pos.y = 0.01
		if def.hp <= 0:
			def.vy = maxf(def.vy, 0.1); def.air_v = f * 0.05
		if def.state != "air": def.set_state("air")
		def.move = null; def.queued = ""; def.stance = ""
	else:
		def.set_state("hit")
		def.stun = maxi(6, rem + int(m.hit if m.hit != null else 0) + (8 if res.ch else 0))
		def.hit_lvl = m.lvl; def.hit_crouch = was_low; def.move = null; def.queued = ""; def.stance = ""
		def.vel = f * (m.push if m.push > 0 else 0.045)
	def.kick("high" if air else m.lvl, m.dmg / 10.0 * (1.4 if res.ch else 1.0))
	att.recoil(m.dmg / 10.0)
	var big: bool = m.surge or launch or m.kd or res.ch
	hitstop = 40 if m.surge else 10 if big else 7
	shake = 0.35 if m.surge else 0.16 if big else 0.07
	burst(cp, att.C.accent if m.surge else Color(1, 0.82, 0.4) if res.ch else Color.WHITE, 22 if big else 12, 4.5 if big else 3.0)
	ring(cp, att.C.accent if m.surge else Color.WHITE, 1.0 if big else 0.6)
	sfx("heavy" if big else "hit")
	if res.ch: ui.pop_text("COUNTER HIT", att.side)
	elif launch and not air: ui.pop_text("LAUNCH", att.side)
	if m.surge: ui.screen_flash(att.C.accent)
	fd_log(att, "COUNTER HIT" if res.ch else "HIT")
	trial_hit(att, def, m)
	if def.hp <= 0: ko_start(att)


func start_throw(att: Fighter, def: Fighter, m: Data.Move) -> void:
	att.set_state("throwing"); att.victim = def; att.tm = m; att.throw_dir = att.fwd(); att.move = null
	def.set_state("thrown"); def.thrower = att; def.break_throw = false; def.cmd_thrown = m.cmd_throw; def.thrown_by = m.throw_type
	def.pend = 0; def.buffer = null; def.throw_t = 0.0; def.move = null; def.stance = ""
	hitstop = 4; sfx("grab")
	ui.pop_text(m.name.to_upper(), att.side)


func separate(A: Fighter, B: Fighter) -> void:
	if A.state == "thrown" or B.state == "thrown" or A.pos.y > 0.6 or B.pos.y > 0.6: return
	var dx := B.pos.x - A.pos.x
	var dz := B.pos.z - A.pos.z
	var d := maxf(0.0001, Vector2(dx, dz).length())
	var mn: float = 0.32 * (A.C.scale + B.C.scale)
	if d < mn:
		var p := (mn - d) / 2.0
		A.pos.x -= dx / d * p; A.pos.z -= dz / d * p
		B.pos.x += dx / d * p; B.pos.z += dz / d * p


# ------------------------------------------------------------------ training
func fd_log(att: Fighter, res: String) -> void:
	if mode != "training" or att.side != 0 or fd == null: return
	fd.res = res; fd.adv = null; fd.tr = {f = 0, a = -1, d = -1}


func training_tick() -> void:
	var A: Fighter = F[0]
	var B: Fighter = F[1]
	for f in F:
		if f.can_act() and f.hp < f.max_hp:
			f.refill += 1
			if f.refill > 50:
				f.hp = f.max_hp; f.refill = 0; ui.chip[f.side] = 100.0
		else:
			f.refill = 0
	if A.can_act(): A.meter = 100.0
	if trial_step > 0 and B.combo_hits == 0 and B.can_act(): trial_step = 0   # combo dropped
	if fd != null and fd.tr != null:   # measure real frame advantage: who can act first after contact
		var tr: Dictionary = fd.tr
		tr.f += 1
		if B.state in ["air", "down", "ko"]:
			fd.adv = "LAUNCH" if B.state == "air" else "KND"; fd.tr = null; return
		if tr.a < 0 and A.can_act(): tr.a = tr.f
		if tr.d < 0 and B.can_act(): tr.d = tr.f
		if tr.a >= 0 and tr.d >= 0:
			fd.adv = tr.d - tr.a; fd.tr = null
		elif tr.f > 150:
			fd.tr = null


func trial_hit(att: Fighter, def: Fighter, m: Data.Move) -> void:
	if mode != "training" or att.side != 0 or trials.is_empty(): return
	var keys: Array = trials[trial_i].keys
	if def.combo_hits == 1: trial_step = 0
	if trial_step < keys.size() and m.key == keys[trial_step]:
		trial_step += 1
	else:
		trial_step = 1 if m.key == keys[0] else 0
	if trial_step >= keys.size():
		trial_done[trial_i] = true
		trial_step = 0
		ui.announce("TRIAL CLEAR!", "fight")
		sfx("ok")


func cycle_trial() -> void:
	if trials.is_empty(): return
	trial_i = (trial_i + 1) % trials.size()
	trial_step = 0


func cycle_dummy() -> void:
	dummy = (dummy + 1) % DUMMY.size()
	ai[1] = FighterAI.new(self, 1) if dummy == 3 else null
	F[1].no_guard = false


func reset_training() -> void:
	F[0].reset(-1.2); F[1].reset(1.2); F[0].meter = 100.0; fd = null; cam_a = null; ui.chip = [100.0, 100.0]


# ------------------------------------------------------------------ per-frame visuals
func _process(dt: float) -> void:
	t_now += dt
	if ui == null: return   # still on the startup loader
	if net.connected and Time.get_ticks_msec() - net_ping.sent > 1500:
		net_ping.sent = Time.get_ticks_msec()
		net.send({t = "ping", ms = net_ping.sent})
	if not F.is_empty():
		for f in F:
			f.render(t_now)
		_update_camera()
		ui.update_hud(self)
	else:
		_menu_camera()
	_update_fx(dt)


func _update_camera() -> void:
	var A: Fighter = F[0]
	var B: Fighter = F[1]
	var dv := Vector2(B.pos.x - A.pos.x, B.pos.z - A.pos.z)
	var sep := maxf(0.001, dv.length())
	dv /= sep
	var ta := atan2(-dv.y, dv.x)   # camera sits on the side that keeps P1 screen-left
	cam_a = ta if cam_a == null else lerp_angle(cam_a, ta, 0.08)
	var cx := (A.pos.x + B.pos.x) / 2.0
	var cz := (A.pos.z + B.pos.z) / 2.0
	var air := maxf(A.pos.y, B.pos.y) * 0.35
	var dist := maxf(3.7, sep * 1.15 + 2.5)
	var h := 1.45 + air
	var ly := 1.05 + air
	var ang: float = cam_a
	if surge_cam != null:
		var S: Fighter = surge_cam.f
		cx = S.pos.x; cz = S.pos.z; dist = 2.4; h = 1.15; ly = 1.3; ang += -0.5 if S.side else 0.5
	if phase == "intro" and phase_t > 50:
		var k := minf(phase_t - 50, 60)
		dist += k * 0.03; ang += k * 0.006
	if phase == "end" or (phase == "ko" and phase_t < 100 and winner >= 0):
		var W: Fighter = F[maxi(0, winner)]
		cx = W.pos.x; cz = W.pos.z; dist = 3.0; ly = 1.2; h = 1.3
		ang = W.face + (-0.5 if W.side else 0.5)
	cam_pos = cam_pos.lerp(Vector3(cx + sin(ang) * dist, h, cz + cos(ang) * dist), 0.1)
	cam_look = cam_look.lerp(Vector3(cx, ly, cz), 0.14)
	camera.position = cam_pos
	if shake > 0.002:
		camera.position += Vector3(randf() - 0.5, randf() - 0.5, 0) * shake
		shake *= 0.86
	camera.look_at(cam_look)


func _menu_camera() -> void:
	var sel: bool = ui.view == "select"
	var a := t_now * 0.11
	if sel:
		cam_pos = cam_pos.lerp(Vector3(0, 1.25, 5.3), 0.08); cam_look = cam_look.lerp(Vector3(0, 1.08, 0), 0.08)
	else:
		cam_pos = Vector3(sin(a) * 5.6, 1.45, cos(a) * 5.6); cam_look = Vector3(0, 1.05, 0)
	camera.position = cam_pos
	camera.look_at(cam_look)
	for i in 2:
		var pv = preview[i]
		if pv == null: continue
		var r = pv.rig
		r.position = Vector3((1.3 if i else -1.3) if sel else (1.55 if i else -1.55), 0, 0)
		r.rotation.y = ((-0.45 if i else 0.45) if sel else (-PI / 2 if i else PI / 2))
		pv.disp = Pose.lerp_p(pv.disp, pv.C.pose.win if pv.win else pv.C.pose.guard, 0.12)
		var q: PackedFloat32Array = pv.disp.duplicate()
		if not pv.win:
			Idle.apply(pv.C.arch, q, t_now + i * 0.9)
		var ic := "" if pv.win else Fighter.own_clip(pv.C, "pose", Fighter.own_clip(pv.C, "idle", Fighter.idle_clip(pv.C.arch)))
		r.set_clip(ic, fmod(t_now + i * 0.7, Fighter._len(ic)) if ic != "" else 0.0)
		r.apply_pose(q)


func set_preview(side: int, C: Dictionary, costume := 0) -> void:
	if preview[side] != null and preview[side].C == C and preview[side].costume == costume: return
	if preview[side] != null: preview[side].rig.queue_free()
	var rig := make_rig(C, costume)
	add_child(rig)
	# glowing pedestal in the fighter's color
	for spec in [[0.42, 0.62, 0.9], [0.0, 0.62, 0.18]]:
		var m := ShaderMaterial.new(); m.shader = ADDITIVE
		m.set_shader_parameter("color", C.accent); m.set_shader_parameter("alpha", spec[2])
		var mesh: Mesh
		if spec[0] > 0.0:
			var tor := TorusMesh.new(); tor.inner_radius = spec[0]; tor.outer_radius = spec[1]; tor.rings = 48
			mesh = tor
		else:
			var disc := CylinderMesh.new(); disc.top_radius = spec[1]; disc.bottom_radius = spec[1]; disc.height = 0.01
			mesh = disc
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = m; mi.position.y = 0.01
		mi.scale = Vector3(1, 0.05, 1) if spec[0] > 0.0 else Vector3.ONE
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(mi)
	preview[side] = {C = C, rig = rig, disp = C.pose.guard.duplicate(), win = false, costume = costume}


func clear_preview() -> void:
	for i in 2:
		if preview[i] != null:
			preview[i].rig.queue_free()
			preview[i] = null


# ------------------------------------------------------------------ automated checks (xvfb)
func _run_autotest() -> void:
	var shot := func(name: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://shot_%s.png" % name)
	match autotest:
		"title":
			ui.show_title()
			await get_tree().create_timer(1.0).timeout
			await shot.call("title")
		"mobile":
			# run with --phone: the new modes' screens and touch controls at a phone's shape
			ui.show_title(); await get_tree().create_timer(1.0).timeout; await shot.call("p_title")
			ui.show_select({mode = "race"}); await get_tree().create_timer(1.0).timeout; await shot.call("p_select")
			ui.show_ops_setup(Data.by_id("abdul_wasay")); await get_tree().create_timer(0.6).timeout; await shot.call("p_ops_setup")
			await start_race("city", Data.by_id("hamza_khan"))
			race.autopilot = true
			await get_tree().create_timer(6.0).timeout; await shot.call("p_race")
			race.toggle_pause(); await get_tree().create_timer(0.5).timeout; await shot.call("p_pause")
			end_race()
			await start_ops(Data.by_id("abdul_wasay"), {mine = 2, them = 2, gun = "rifle", skill = 1.0})
			ops.autopilot = true
			await get_tree().create_timer(5.0).timeout; await shot.call("p_ops")
			print("AUTOTEST mobile touch=%s" % ui.touch_enabled)
			end_ops()
		"menus":
			ui.show_title(); await get_tree().create_timer(1.0).timeout; await shot.call("m_title")
			ui.show_clash_menu(); await get_tree().create_timer(0.6).timeout; await shot.call("m_clash")
			ui.show_select({mode = "race"}); await get_tree().create_timer(1.0).timeout; await shot.call("m_select_race")
			ui.show_race_tracks(Data.by_id("abdul_wasay")); await get_tree().create_timer(0.6).timeout; await shot.call("m_tracks")
			ui.show_ops_setup(Data.by_id("abdul_wasay")); await get_tree().create_timer(0.6).timeout; await shot.call("m_ops")
		"stagesel":
			ui.show_stage({mode = "cpu", lv = 1}, [Data.by_id("ember"), Data.by_id("bastion")])
			ui.stage_sel.i = 2
			ui._render_stage()
			await get_tree().create_timer(2.0).timeout
			await shot.call("stagesel")
		"select":
			ui.show_select({mode = "cpu", lv = 1})
			await get_tree().create_timer(1.0).timeout
			await shot.call("select")
		"fight":
			var ids := ["mara", "lio"]
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--pair="): ids = a.substr(7).split(",")
			var st := "open_office"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--stage="): st = a.substr(8)
			await start_match({mode = "cpu", lv = 2, stage = st}, [Data.by_id(ids[0]), Data.by_id(ids[1])])
			ai[0] = FighterAI.new(self, 2)
			await get_tree().create_timer(6.0).timeout
			await shot.call("fight")
			print("AUTOTEST hp=", F[0].hp, ",", F[1].hp, " phase=", phase)
			var t0 := Time.get_ticks_usec()
			for i in 100:
				F[0].render(t_now); F[1].render(t_now)
			print("AUTOTEST pose cost per frame (both fighters): %.2f ms" % ((Time.get_ticks_usec() - t0) / 100000.0))
		"moves":
			await start_match({mode = "training"}, [Data.by_id("kael"), Data.by_id("bastion")])
			await get_tree().create_timer(0.3).timeout
			ui.show_pause(); ui.show_moves(0)
			await get_tree().create_timer(0.5).timeout
			await shot.call("moves")
		"closeup":
			var id := "sora"
			var mv := ""
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--id="): id = a.substr(5)
				if a.begins_with("--move="): mv = a.substr(7)
			var C := Data.by_id(id)
			var cos := 0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--costume="): cos = int(a.substr(10))
			var rig := make_rig(C, cos)
			add_child(rig)
			var clip := ""
			var ct := 0.0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--clip="): clip = a.substr(7)
				if a.begins_with("--ct="): ct = float(a.substr(5))
			if clip != "":
				print("AUTOTEST clips loaded: ", ClipLib.clips.size(), " ", ", ".join(ClipLib.clips.keys().map(func(k): return "%s(%.1fs)" % [k, ClipLib.get_clip(k).length])))
				for i in 8:
					rig.set_clip(clip, ct * ClipLib.get_clip(clip).length)
					rig.apply_pose(C.pose.guard, clip != "knockdown")
			var p: PackedFloat32Array = C.pose.guard
			if mv != "":
				var m: Data.Move = C.moves[mv]
				p = m.track[m.track.size() - 1][1]
			if clip == "":
				rig.apply_pose(p)
			rig.rotation.y = 0.5
			ui.hide_screen()
			set_process(false)
			camera.position = Vector3(1.1, 1.3, 1.9)
			camera.look_at(Vector3(0, 1.05, 0))
			await get_tree().create_timer(0.5).timeout
			await shot.call("closeup")
		"trials":
			for id in ["kael", "bastion", "mara", "vex", "sora"]:
				await start_match({mode = "training"}, [Data.by_id(id), Data.by_id("bastion")])
				F[0].reset(-0.55); F[1].reset(0.55)
				for t in trials.size():
					print("AUTOTEST trials ", id, " #", t, " ", trials[t].name, " ", trials[t].keys)
				# trial index of the launcher juggle
				for t in trials.size():
					if trials[t].name == "Launcher Juggle": trial_i = t
				var keys: Array = trials[trial_i].keys
				var launcher: String = keys[0]
				var seq := []
				var dirs := {df = [KEY_D, KEY_S], d = [KEY_S], b = [KEY_A], f = [KEY_D], uf = [KEY_D, KEY_W]}
				var btn := {"1": KEY_U, "2": KEY_I, "3": KEY_J, "4": KEY_K}
				var pre := launcher.rstrip("1234")
				var dk: Array = dirs.get(pre, [])
				seq.append([dk, 2]); seq.append([dk + [btn[launcher.right(1)]], 4]); seq.append([[], 30])
				# follow-up string: keys[1] is its first button, each later key adds one button
				for j in range(1, keys.size()):
					seq.append([[btn[keys[j].right(1)]], 3]); seq.append([[], 5])
				for i in 10: await get_tree().physics_frame
				var trace := []
				for st in seq:
					test_keys.clear()
					for kk in st[0]: test_keys[kk] = true
					for i in st[1]:
						await get_tree().physics_frame
						trace.append("%s/%d|%s y%.2f h%d" % [F[0].move.key if F[0].move else F[0].state, F[0].sf, F[1].state, F[1].pos.y, F[1].combo_hits])
				test_keys.clear()
				var best := 0
				for i in 90:
					await get_tree().physics_frame
					best = maxi(best, F[1].combo_hits)
					trace.append("%s/%d|%s y%.2f h%d d%.2f" % [F[0].move.key if F[0].move else F[0].state, F[0].sf, F[1].state, F[1].pos.y, F[1].combo_hits, F[0].dist_to(F[1])])
				if id == "bastion": print("AUTOTEST TRACE ", " ; ".join(trace))
				print("AUTOTEST juggle %-8s keys=%s cleared=%s max_hits=%d" % [id, keys, trial_done.get(trial_i, false), best])
		"springs":
			await start_match({mode = "cpu", lv = 2}, [Data.by_id("vex"), Data.by_id("ember")])
			ai[0] = FighterAI.new(self, 2)
			var stats := {}
			for f in 300:
				await get_tree().physics_frame
				if f % 30 != 29: continue
				for fi in 2:
					var r = F[fi].rig
					if not (r is VrmRig): continue
					var mx := 0.0
					var tot := 0.0
					var n := 0
					var bad := false
					for chain in r.springs:
						for jn in chain:
							var q: Quaternion = r.skel.get_bone_pose_rotation(jn.b)
							var rq: Quaternion = r.rest_l[jn.b].basis.get_rotation_quaternion()
							var ang := rad_to_deg(q.angle_to(rq))
							if is_nan(ang): bad = true
							mx = maxf(mx, ang); tot += ang; n += 1
					var key: String = F[fi].C.id
					if not stats.has(key): stats[key] = []
					stats[key].append("%.0f/%.0f%s" % [tot / maxf(1, n), mx, " NaN!" if bad else ""])
			for k in stats:
				print("AUTOTEST springs %s joints=%d avg/max deg over time: %s" % [k, _count_joints(k), " ".join(stats[k])])
			var t0 := Time.get_ticks_usec()
			for i in 100:
				F[0].render(t_now); F[1].render(t_now)
			print("AUTOTEST pose+springs cost per frame (both): %.2f ms" % ((Time.get_ticks_usec() - t0) / 100000.0))
			await shot.call("fight")
		"nethost", "netjoin", "lanhost", "lanjoin":
			# Two game processes play an online match through the relay (or directly on LAN).
			# Args: --codefile=PATH (room code hand-off), --relay=ws://..., --lanip=127.0.0.1
			var host := autotest.ends_with("host")
			var lan := autotest.begins_with("lan")
			var codefile := ""
			var lanip := "127.0.0.1"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--codefile="): codefile = a.substr(11)
				if a.begins_with("--lanip="): lanip = a.substr(8)
			ui.show_online()
			if host:
				if lan:
					ui._lan_host()
				else:
					net.room_created.connect(func(code):
						var f := FileAccess.open(codefile, FileAccess.WRITE); f.store_string(code); f.close()
						print("AUTOTEST net room ", code))
					ui._online_create()
			else:
				if lan:
					await get_tree().create_timer(1.0).timeout
					net.join_lan(lanip)
				else:
					var code := ""
					for k in 100:
						if FileAccess.file_exists(codefile):
							code = FileAccess.get_file_as_string(codefile).strip_edges()
							if code != "": break
						await get_tree().create_timer(0.2).timeout
					# first a join that gets abandoned (used to leave the room "full"), then the real one
					await net.join_room(code)
					net.close()
					await get_tree().create_timer(1.0).timeout
					ui.show_join(code)
			for k in 150:
				if net.connected: break
				await get_tree().create_timer(0.1).timeout
			print("AUTOTEST net paired=%s host=%s" % [net.connected, net.is_host])
			await get_tree().create_timer(0.5).timeout
			# each side picks its fighter on its own screen
			var me := local_side
			print("AUTOTEST net select view=%s sel=%s" % [ui.view, ui.sel != null])
			ui.sel.cur[me] = 7 if host else 4
			ui._select_confirm(me)
			print("AUTOTEST net picked")
			if host:
				for k in 100:
					if ui.view == "stage": break
					await get_tree().create_timer(0.1).timeout
				print("AUTOTEST net host view=%s" % ui.view)
				ui.stage_sel.i = 0
				ui._stage_confirm()
			# scripted controls: walk in, mix up attacks, sometimes back off or crouch
			test_net_input = func(t: int) -> Array:
				var phase_k := (t / 40 + (3 if host else 0)) % 6
				var x: int = [1, 1, 0, -1, 1, 0][phase_k]
				var y := -1 if (t / 90) % 5 == 4 else 0
				var held := 0
				if t % 11 < 2: held = [1, 2, 4, 8][(t / 11 + (1 if host else 2)) % 4]
				return [x, y, held]
			var desynced := false
			for k in 6000:
				await get_tree().create_timer(0.05).timeout
				if not desynced and not host and nf >= 420:
					desynced = true
					F[0].hp -= 7.0   # corrupt the guest's copy: the next fingerprint must catch it
					print("AUTOTEST net guest corrupted state at tick %d" % nf)
				if k % 400 == 0: print("AUTOTEST net progress view=%s mode=%s nf=%d F=%d in0=%d in1=%d" % [ui.view, mode, nf, F.size(), net_in[0].size(), net_in[1].size()])
				if nf >= 960 or not net.connected: break
			print("AUTOTEST net done nf=%d connected=%s hp=%s wins=%s" % [nf, net.connected, [roundf(F[0].hp), roundf(F[1].hp)] if not F.is_empty() else [], wins])
			# rematch race: the guest asks before the host's results screen even exists
			test_net_input = Callable()
			if not host:
				ui.show_end()
				ui.online.rematch[local_side] = true; net.send({t = "rematch"}); ui._online_rematch()
				print("AUTOTEST net guest asked for rematch")
			else:
				await get_tree().create_timer(2.0).timeout
				ui.show_end()
				await get_tree().create_timer(1.0).timeout
				ui.online.rematch[local_side] = true; net.send({t = "rematch"}); ui._online_rematch()
				print("AUTOTEST net host asked for rematch")
			var before := online_matches
			var started := false
			for k in 600:
				await get_tree().create_timer(0.05).timeout
				if online_matches > before and not F.is_empty() and nf > 30:
					started = true; break
			print("AUTOTEST net rematch started=%s view=%s nf=%d connected=%s" % [started, ui.view, nf, net.connected])
			await get_tree().create_timer(3.0).timeout   # let the rival see it too before hanging up
			net.close()
		"onlinemenu":
			ui.show_online()
			await get_tree().create_timer(0.6).timeout
			await shot.call("online")
			ui.show_join("")
			await get_tree().create_timer(0.4).timeout
			await shot.call("join")
			net.code = "K7QP2"
			ui._render_wait()
			await get_tree().create_timer(0.4).timeout
			await shot.call("room")
		"arcade":
			# pick the first fighter, check the ladder, then start the final boss fight directly
			start_arcade(Data.ROSTER[0], 0)
			await get_tree().create_timer(1.0).timeout
			print("AUTOTEST arcade ladder: %s" % [arcade.ladder.map(func(e): return "%s%s(lv%d,%s)" % [e.C.id, ("[" + e.C.boss_form + "]") if e.C.has("boss_form") else "", e.lv, e.stage])])
			await shot.call("ladder")
			arcade.i = arcade.ladder.size() - 1
			arcade_fight()
			await get_tree().create_timer(1.8).timeout
			await shot.call("bossvs")
			await get_tree().create_timer(4.0).timeout
			print("AUTOTEST boss fight: %s hp=%d power=%.2f ai_lv=%d vs %s hp=%d power=%.2f" % [F[1].C.name, F[1].max_hp, F[1].C.power, ai[1].lv, F[0].C.name, F[0].max_hp, F[0].C.power])
			var H := Data.boss_of("final")
			print("AUTOTEST playable CEO hp=%d power=%.2f" % [H.hp, H.power])
			await get_tree().create_timer(2.0).timeout
			await shot.call("bossfight")
		"props":
			# every power prop, lined up in a row (visual check)
			set_stage("open_office")
			var kinds: Array = PowerProps.STYLE.keys()
			for k in kinds.size():
				var pr := PowerProps.build(kinds[k], Color(0.6, 0.4, 1.0))
				pr.scale = Vector3.ONE * 2.0
				pr.position = Vector3(-4.4 + (k % 8) * 1.25, 2.4 - (k / 8) * 0.85, 0)
				add_child(pr)
			camera.position = Vector3(0, 1.6, 6.5); camera.look_at(Vector3(0, 1.6, 0))
			set_process(false)
			await get_tree().create_timer(0.5).timeout
			await shot.call("props")
			set_process(true)
			# and a real power: the CEO's Hostile Takeover against Ali
			await start_match({mode = "training", stage = "boardroom"}, [Data.by_id("ali"), Data.by_id("hamza_khan")])
			await get_tree().create_timer(0.5).timeout
			F[0].meter = 100.0
			for pr in get_children():
				if pr is Node3D and pr.get_parent() == self and pr.scale.x == 2.0 and not (pr is Camera3D): pr.queue_free()
			PowerProps.launch(self, F[0], F[1], "goat", 0.9)
			PowerProps.launch(self, F[0], F[1], "agents", 0.9)
			await get_tree().create_timer(0.35).timeout
			await shot.call("propfly")
		"poses":
			# select-screen personality poses, two fighters at a time
			ui.show_select({mode = "cpu", lv = 1})
			var pairs := [["ali", "hamza_khan"], ["tuaha_aamir", "sabir_ud_din"]]
			for k in pairs.size():
				set_preview(0, Data.by_id(pairs[k][0])); set_preview(1, Data.by_id(pairs[k][1]))
				await get_tree().create_timer(2.5).timeout
				await shot.call("poses%d" % k)
		"grapple":
			# Hamza's takedown and Kashaf's slam, three frames each (paired throws must line up)
			for who in ["hamza_khan", "kashaf_ud_duja"]:
				await start_match({mode = "training", stage = "boardroom"}, [Data.by_id(who), Data.by_id("ali")])
				dummy = 0
				F[0].reset(-0.5); F[1].reset(0.5)
				for i in 5: await get_tree().physics_frame
				F[0].start_move("12")
				for k in 3:
					for i in 14: await get_tree().physics_frame
					await shot.call("grapple_%s_%d" % [who, k])
		"powers":
			# fire each listed fighter's power at a dummy; two shots per power (wind-up, impact)
			var ids := ["hamza_khan", "kashaf_ud_duja", "muhammad_mubarak", "zia_khan", "faisal_ahmed", "muhammad_nauman_nawaz", "sabir_ud_din", "ali"]
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--ids="): ids = a.substr(6).split(",")
			for id in ids:
				await start_match({mode = "training", stage = "open_office"}, [Data.by_id(id), Data.by_id("tuaha_aamir")])
				dummy = 0
				F[0].reset(-1.1); F[1].reset(1.1)
				for i in 10: await get_tree().physics_frame
				var key := ""
				for k in F[0].C.moves:
					if F[0].C.moves[k].surge: key = k
				F[0].meter = 100.0
				F[0].start_move(key)
				var s0: int = F[0].C.moves[key].s
				for i in maxi(1, s0 - 6): await get_tree().physics_frame
				await shot.call("pw_%s_0" % id)
				for i in 14: await get_tree().physics_frame
				await shot.call("pw_%s_1" % id)
		"skull":
			for id in ["hamza_khan", "kashaf_ud_duja", "amina_mughal"]:
				var r := make_rig(Data.by_id(id))
				add_child(r)
				if r is VrmRig: print("AUTOTEST skull %s %s" % [id, r.skull])
				r.queue_free()
		"certificate":
			var img: Image = await Certificate.render(self, "Abdul Wasay", Data.by_id("ali"), portraits.get("ali"))
			img.save_png("user://shot_certificate.png")
			var pdf := Certificate.to_pdf(img)
			var f := FileAccess.open("user://test_certificate.pdf", FileAccess.WRITE); f.store_buffer(pdf); f.close()
			print("AUTOTEST certificate %dx%d pdf=%d bytes" % [img.get_width(), img.get_height(), pdf.size()])
		"intro":
			await start_match({mode = "cpu", lv = 1, stage = "cafeteria"}, [Data.by_id("ali"), Data.by_id("hamza_khan")])
			for k in 3:
				await get_tree().create_timer(0.9).timeout
				await shot.call("intro%d" % k)
		"wear":
			# voices to listen to + a fighter after a rough match
			for id in ["hamza_khan", "ali", "kashaf_ud_duja", "sarfraz_yousaf", "tuaha_aamir"]:
				var C := Data.by_id(id)
				for kind in ["attack", "heavy", "hurt", "ko", "power", "win"]:
					var w := Voices.get_sound(C, kind)
					w.save_to_wav("user://voice_%s_%s.wav" % [id, kind])
			print("AUTOTEST voices saved")
			await start_match({mode = "training", stage = "open_office"}, [Data.by_id("hamza_khan"), Data.by_id("kashaf_ud_duja")])
			for f in F:
				f.bruise = 0.9; f.dirt = 0.8; f.blood_on = 0.6
			blood(F[0].pos + Vector3(0.4, 1.3, 0), Vector3(1, 0, 0), 12)
			await get_tree().create_timer(0.25).timeout
			camera.position = F[0].pos + Vector3(0.9, 1.5, 1.6); camera.look_at(F[0].pos + Vector3(0, 1.2, 0))
			set_process(false)
			await get_tree().create_timer(0.2).timeout
			await shot.call("wear")
			set_process(true)
		"backview":
			# women's outfits from behind, mid-stride (legs must stay covered)
			var ids := ["amina_mughal", "aqsa_altaf", "kashaf_ud_duja"]
			for k in ids.size():
				await start_match({mode = "training", stage = "open_office"}, [Data.by_id(ids[k]), Data.by_id("ali")])
				test_keys[KEY_D] = true
				await get_tree().create_timer(0.6).timeout
				test_keys[KEY_D] = false
				var f: Fighter = F[0]
				camera.position = f.pos + Vector3(-2.2, 1.0, -0.6) * Vector3(1, 1, 1)
				camera.look_at(f.pos + Vector3(0, 0.6, 0))
				set_process(false)
				await get_tree().create_timer(0.15).timeout
				await shot.call("back%d" % k)
				set_process(true)
		"race":
			# a race on each track with the CPU driving the player too: places change, items fly, laps count
			var tracks := ["city", "park", "rooftop"]
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--track="): tracks = [a.substr(8)]
			for tid in tracks:
				await start_race(tid, Data.by_id("hamza_khan"))
				race.autopilot = true
				for k in 3:
					await get_tree().create_timer(6.0 if k == 0 else 7.0).timeout
					await shot.call("race_%s_%d" % [tid, k])
				var me: RaceSim.Racer = race.sim.racers[0]
				var places := race.sim.racers.map(func(r): return "%s:%d/L%d" % [r.C.person.get("short", r.C.id), r.place, r.lap])
				print("AUTOTEST race %s t=%.1f state=%s me lap=%d place=%d speed=%.0f events=%s" % [tid, race.sim.time, race.sim.state, me.lap, me.place, me.speed, race.stats])
				print("AUTOTEST race %s places %s" % [tid, " ".join(places)])
				end_race()
		"racecar":
			# close-up of a car and its driver
			await start_race("park", Data.by_id("kashaf_ud_duja"))
			await get_tree().create_timer(1.0).timeout
			race.set_process(false)
			var c: Node3D = race.world.cars[0].root
			race.world.draw(1.0, 0.016)
			var rg: Node3D = race.world.cars[0].rig
			var vis := []
			for mi in rg.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).is_visible_in_tree(): vis.append(mi.name)
			print("AUTOTEST racecar rig=%s at %s scale %s visible_meshes=%d model=%s" % [rg.get_class(), rg.global_position, rg.scale, vis.size(), (rg.get("model") as Node3D).global_position if rg.get("model") != null else "-"])
			race.world.cam.position = c.global_position + Vector3(3.2, 2.2, 3.5)
			race.world.cam.look_at(c.global_position + Vector3(0, 1.0, 0))
			await get_tree().create_timer(0.3).timeout
			await shot.call("racecar")
			# the grid from the side and from behind
			var c3: Node3D = race.world.cars[3].root
			race.world.cam.position = c3.global_position + c3.global_transform.basis.x * 9.0 + Vector3(0, 2.5, 0)
			race.world.cam.look_at(c3.global_position + Vector3(0, 0.8, 0))
			await get_tree().create_timer(0.3).timeout
			await shot.call("racegrid")
			race.world.cam.position = c.global_position - c.global_transform.basis.z * 6.0 + Vector3(1.5, 2.0, 0)
			race.world.cam.look_at(c.global_position + Vector3(0, 0.8, 0))
			await get_tree().create_timer(0.3).timeout
			await shot.call("racerear")
			end_race()
		"racefull":
			await start_race("park", Data.by_id("ali"))
			race.autopilot = true
			for k in 400:
				await get_tree().create_timer(0.5).timeout
				if race.results_shown: break
			await get_tree().create_timer(2.0).timeout
			await shot.call("raceresults")
			var res := race.sim.racers.duplicate()
			res.sort_custom(func(a, b): return a.place < b.place)
			print("AUTOTEST racefull state=%s time=%.1f results=%s events=%s" % [race.sim.state, race.sim.time,
				" ".join(res.map(func(r): return "%d.%s(%s)" % [r.place, r.C.person.get("short", ""), "%.1f" % r.finished if r.finished >= 0 else "dnf"])), race.stats])
			end_race()
		"racesim":
			# the race rules alone, every track, all CPU, as fast as possible: everyone should finish
			var count := 10
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--cars="): count = int(a.substr(7))
			for tid in RaceSim.TRACKS:
				var people := Data.ROSTER.slice(0, count)
				var sim := RaceSim.new()
				sim.setup(tid, people, 0, 42)
				var counts := {}
				var ticks := 0
				while sim.state != "done" and ticks < 60 * 60 * 6:
					sim.tick({})
					ticks += 1
					for e in sim.events: counts[e[0]] = counts.get(e[0], 0) + 1
				var res := sim.racers.duplicate()
				res.sort_custom(func(x, y): return x.place < y.place)
				print("AUTOTEST racesim %s len=%dm done=%s time=%.1fs finishers=%d" % [tid, sim.length, sim.state == "done", sim.time, res.filter(func(r): return r.finished >= 0.0).size()])
				print("AUTOTEST racesim %s top: %s" % [tid, " ".join(res.slice(0, 5).map(func(r): return "%d.%s %.1fs hits=%d" % [r.place, r.C.person.get("short", ""), r.finished, r.hits]))])
				print("AUTOTEST racesim %s events %s" % [tid, counts])
				var walltime := 0
				var lats := []
				for r in sim.racers: lats.append("%.1f" % r.lat)
				print("AUTOTEST racesim %s final lats %s" % [tid, lats])
		"opssim":
			# whole matches with bots on both sides, as fast as possible
			for sizes in [[1, 1], [2, 1], [4, 4]]:
				var sim := OpsSim.new()
				var pool := Data.ROSTER.duplicate()
				sim.setup(pool.slice(0, sizes[0]), pool.slice(10, 10 + sizes[1]), {}, {}, 7)
				var counts := {}
				var ticks := 0
				while sim.state != "done" and ticks < 60 * 360:
					sim.tick({}); ticks += 1
					for e in sim.events: counts[e[0]] = counts.get(e[0], 0) + 1
				var heads := 0
				print("AUTOTEST opssim %dv%d done=%s time=%.0fs score=%s goal=%d shots=%d hits=%d kills=%d vest_breaks=%d" % [sizes[0], sizes[1], sim.state == "done", sim.time, sim.score, sim.goal,
					counts.get("shot", 0), counts.get("hit", 0), counts.get("kill", 0), counts.get("vest_break", 0)])
				print("AUTOTEST opssim %dv%d players %s" % [sizes[0], sizes[1], " ".join(sim.soldiers.map(func(o): return "%s(%s %dk/%dd vest%d)" % [o.C.person.get("short", ""), o.guns[0], o.kills, o.deaths, o.max_armor]))])
		"ops":
			await start_ops(Data.by_id("abdul_wasay"), {mine = 4, them = 4, gun = "rifle", skill = 1.0})
			ops.autopilot = true
			for k in 4:
				await get_tree().create_timer(5.0).timeout
				await shot.call("ops_%d" % k)
			print("AUTOTEST ops t=%.1f score=%s events=%s" % [ops.sim.time, ops.sim.score, ops.stats])
			# aim down sights with the sniper: the scope overlay
			ops.sim.soldiers[0].guns[0] = "sniper"; ops._rebuild_view_gun()
			ops.autopilot = false
			ops.hold_ads = true
			ops.sim.soldiers[0].hp = 100; ops.sim.soldiers[0].alive = true
			for k in 40: await get_tree().physics_frame
			await shot.call("ops_scope")
			# a close look at an enemy soldier (rig, rifle clip, gun in hand)
			ops.hold_ads = false
			var me0: OpsSim.Soldier = ops.sim.soldiers[0]
			for o in ops.sim.soldiers:
				if o.team != me0.team:
					o.pos = me0.pos + Vector3(sin(me0.yaw), 0, cos(me0.yaw)) * 4.0; o.prev_pos = o.pos; me0.pitch = 0.0
					break
			for k in 3: await get_tree().physics_frame
			await shot.call("ops_enemy")
			end_ops()
		"trade":
			for setup in [["throw vs jab", "12", "1", 2], ["jab vs throw", "1", "12", -2], ["throw vs throw", "12", "12", 0]]:
				await start_match({mode = "training"}, [Data.by_id("tao"), Data.by_id("lio")])
				dummy = 0
				F[0].reset(-0.5); F[1].reset(0.5)
				for i in 5: await get_tree().physics_frame
				# line the active frames up so both connect on the same tick
				var d: int = setup[3]
				if d >= 0:
					F[0].start_move(setup[1])
					for i in d: await get_tree().physics_frame
					F[1].start_move(setup[2])
				else:
					F[1].start_move(setup[2])
					for i in -d: await get_tree().physics_frame
					F[0].start_move(setup[1])
				var states := []
				for i in 150:
					await get_tree().physics_frame
					if i % 30 == 29: states.append("%s/%s" % [F[0].state, F[1].state])
				print("AUTOTEST trade %-15s -> %s  final ok=%s" % [setup[0], " ".join(states), str(not (F[0].state in ["thrown", "throwing"] or F[1].state in ["thrown", "throwing"]))])
		"touch":
			await start_match({mode = "training", stage = "open_office"}, [Data.by_id("kael"), Data.by_id("bastion")])
			for i in 30: await get_tree().physics_frame
			var t: TouchControls = ui.touch
			var vp := get_viewport()
			var ev := func(cls, idx: int, pos: Vector2, pressed := true):
				var e = cls.new()
				e.index = idx; e.position = get_viewport().get_final_transform() * pos   # injected events are in window pixels
				if cls == InputEventScreenTouch: e.pressed = pressed
				Input.parse_input_event(e)
			var x0: float = F[0].pos.x
			var base := Vector2(t.size.x * 0.2, t.size.y * 0.7)
			ev.call(InputEventScreenTouch, 0, base)
			for i in 3: await get_tree().physics_frame
			ev.call(InputEventScreenDrag, 0, base + Vector2(80, 0))
			for i in 30: await get_tree().physics_frame
			var walked: float = F[0].pos.x - x0
			print("AUTOTEST touch stick: visible=%s x=%d state=%s walked=%.2f size=%s btn1=%s" % [t.visible, t.x, F[0].state, walked, t.size, t.buttons[0].center])
			await shot.call("touch")
			ev.call(InputEventScreenTouch, 0, base + Vector2(80, 0), false)
			for i in 10: await get_tree().physics_frame
			var b1: Vector2 = t.buttons[0].center
			ev.call(InputEventScreenTouch, 1, b1)
			for i in 4: await get_tree().physics_frame
			ev.call(InputEventScreenTouch, 1, b1, false)
			var seen := ""
			for i in 20:
				await get_tree().physics_frame
				if F[0].move != null: seen = F[0].move.key
			print("AUTOTEST touch button 1 -> move %s" % seen)
		"dpad":
			await start_match({mode = "training", stage = "open_office"}, [Data.by_id("sora"), Data.by_id("bastion")])
			for i in 30: await get_tree().physics_frame
			var t: TouchControls = ui.touch
			var ev := func(cls, idx: int, pos: Vector2, pressed := true):
				var e = cls.new()
				e.index = idx; e.position = pos
				if cls == InputEventScreenTouch: e.pressed = pressed
				Input.parse_input_event(e)
			# stick mode: tap the ▲ button -> sidestep
			t.set_mode("stick")
			for i in 3: await get_tree().physics_frame
			ev.call(InputEventScreenTouch, 0, t.vbuttons[0].center)
			var seen := []
			for i in 6:
				await get_tree().physics_frame
				if not F[0].state in seen: seen.append(F[0].state)
			ev.call(InputEventScreenTouch, 0, t.vbuttons[0].center, false)
			for i in 20: await get_tree().physics_frame
			print("AUTOTEST stick-mode ▲ -> states %s" % [seen])
			# d-pad mode: hold ▶ -> walk forward
			t.set_mode("dpad")
			F[0].reset(-1.5); F[1].reset(1.5)
			for i in 5: await get_tree().physics_frame
			var x0: float = F[0].pos.x
			var right: Vector2 = t.dpad_center + Vector2(t.dpad_r * 0.7, 0)
			ev.call(InputEventScreenTouch, 0, right)
			for i in 30: await get_tree().physics_frame
			print("AUTOTEST dpad ▶ -> x=%d state=%s walked=%.2f" % [t.x, F[0].state, F[0].pos.x - x0])
			await shot.call("dpad")
			ev.call(InputEventScreenTouch, 0, right, false)
			t.set_mode("stick")
		"cliphits":
			for nm in ClipLib.clips.keys():
				if not nm.begins_with("atk_"): continue
				var c: ClipLib.Clip = ClipLib.get_clip(nm)
				var hs := []
				for h in c.hits: hs.append("%s@%.2fs(reach %.2f, h %.2f)" % [h.limb, h.t, h.reach, h.height])
				print("AUTOTEST %-20s len %.2fs  hits: %s" % [nm, c.length, ", ".join(hs)])
			for C in Data.ROSTER:
				var mapped := []
				var n_att := 0
				for m in C.moves.values():
					if m.trans or m.is_throw or m.surge: continue
					n_att += 1
					var d = MoveClips.info(m)
					if d != null: mapped.append("%s=%s%s" % [m.key, d.clip.trim_prefix("atk_"), "(M)" if d.mirror else ""])
				print("AUTOTEST map %-8s %d/%d: %s" % [C.id, mapped.size(), n_att, " ".join(mapped)])
		"combat":
			await _combat_checks()
		"string":
			await start_match({mode = "training"}, [Data.by_id("mara"), Data.by_id("bastion")])
			F[0].reset(-0.55); F[1].reset(0.55)
			for i in 10: await get_tree().physics_frame
			var plan := {0: KEY_U, 8: KEY_I, 17: KEY_U}
			var log := []
			for f in 60:
				test_keys.clear()
				for start in plan:
					if f >= start and f < start + 4: test_keys[plan[start]] = true
				await get_tree().physics_frame
				log.append("%d:%s/%s q=%s" % [f, F[0].move.key if F[0].move else F[0].state, F[0].sf, F[0].queued])
			print("AUTOTEST ", " ".join(log))
	get_tree().quit()


func _count_joints(id: String) -> int:
	for f in F:
		if f.C.id == id and f.rig is VrmRig:
			var n := 0
			for chain in f.rig.springs: n += chain.size()
			return n
	return 0


func _combat_checks() -> void:
	# Drive inputs through the real input path and report frame data.
	var cases := [
		["kael", 1, [[[KEY_U], 4]], "jab vs guard"],
		["vex", 1, [[[KEY_D, KEY_S], 2], [[KEY_D, KEY_S, KEY_I], 4]], "df+2 vs guard"],
		["sora", 0, [[[KEY_A, KEY_J], 4], [[], 12], [[KEY_K], 4]], "crane 4"],
		["ember", 1, [[[KEY_D], 3], [[], 2], [[KEY_D], 3], [[KEY_D, KEY_U], 4]], "ff+1 command throw"],
		["bastion", 0, [[[KEY_S], 14], [[], 1], [[KEY_I], 4]], "ws2"],
		["mara", 0, [[[KEY_U], 4], [[], 4], [[KEY_I], 4], [[], 5], [[KEY_U], 4]], "1,2,1 string"],
	]
	for c in cases:
		await start_match({mode = "training"}, [Data.by_id(c[0]), Data.by_id("bastion")])
		dummy = c[1]
		F[0].reset(-0.55); F[1].reset(0.55)
		for i in 10: await get_tree().physics_frame
		var hp0: float = F[1].hp
		for step in c[2]:
			test_keys.clear()
			for k in step[0]: test_keys[k] = true
			for i in step[1]: await get_tree().physics_frame
		test_keys.clear()
		var min_hp := hp0
		for i in 80:
			await get_tree().physics_frame
			min_hp = minf(min_hp, F[1].hp)
		print("AUTOTEST %-20s move=%s res=%s adv=%s dmg=%d" % [c[3], fd.m.key if fd != null else "-", fd.res if fd != null else "-", str(fd.adv) if fd != null else "-", hp0 - min_hp])
