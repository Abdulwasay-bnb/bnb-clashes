class_name MafiaGame
extends Node
## BNB Mafia: the office after hours. A top-down 3D view of the floor, your character, limited vision,
## office tasks, and — if you're Mafia — a knife. Bodies get reported, the ALERT button calls a meeting,
## everyone sits at the boardroom table to chat and vote.
## Solo with bots, or online / Wi-Fi: the host runs MafiaSim and tells each player only their own role and tasks.

signal finished

const FLOOR := {"cafe": Color(0.5, 0.36, 0.25), "dev": Color(0.18, 0.22, 0.34), "hr": Color(0.42, 0.3, 0.4), "server": Color(0.14, 0.2, 0.24),
	"storage": Color(0.32, 0.3, 0.26), "print": Color(0.3, 0.32, 0.36), "board": Color(0.26, 0.16, 0.36), "reception": Color(0.36, 0.34, 0.42)}
const RED := Color(0.95, 0.28, 0.32)
const GOLD := Color(1.0, 0.82, 0.4)

var G
var sim: MafiaSim
var me := 0
var world: Node3D
var cam: Camera3D
var layer: CanvasLayer
var hud: Control
var dark: ColorRect
var font: Font
var small: Font
var rigs: Array = []           # per agent: {rig, tag, body, pool}
var lights: Array = []
var env: Environment
var task_ui: MafiaTask = null
var task_st := ""
var meeting_ui: Control = null
var meeting_phase := ""
var chat_log: RichTextLabel
var chat_in: LineEdit
var cards: Array = []
var timer_lbl: Label
var shown_chat := 0
var toast := ""
var toast_t := 0.0
var show_map := false
var results_shown := false
var paused := false
var touch_move := Vector2.ZERO
var move_id := -1
var move_origin := Vector2.ZERO
var btns := {}                 # name -> {c, r, label, on}
var roles_final: Array = []
var autoplay := false
var stats := {}
var eject_mafia := false
var _snap_t := 0.0
var _priv_t := 0.0
# online
var net: Party = null
var guest := false
var pid_agent := {}            # host: pid -> agent id
var inputs := {}
var outbox: Array = []
var inbox: Array = []


func start(g, people: Array, cfg: Dictionary, seed: int, my_id := 0) -> void:
	G = g
	me = my_id
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	small = load("res://assets/fonts/Rajdhani-Bold.ttf")
	sim = MafiaSim.new()
	sim.setup(people, cfg, seed)
	if guest:
		for a in sim.agents: a.mafia = false; a.tasks = []   # we only learn our own role from the host
	world = Node3D.new()
	G.add_child(world)
	_build_world()
	layer = CanvasLayer.new(); layer.layer = 5
	G.add_child(layer)
	dark = ColorRect.new()
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec2 c = vec2(0.5);
uniform vec2 sz = vec2(1280.0, 720.0);
uniform float r = 300.0;
uniform float dark = 0.92;
void fragment() {
	float d = distance(UV * sz, c);
	COLOR = vec4(0.0, 0.0, 0.03, smoothstep(r * 0.75, r * 1.1, d) * dark);
}"""
	var sm := ShaderMaterial.new(); sm.shader = sh
	dark.material = sm
	layer.add_child(dark)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	_layout_buttons()
	if not guest: _intro()


## The role reveal: who you are and (for the Mafia) who your partners are.
var intro_ui: Control = null
var _intro_done := false


func _intro() -> void:
	if _intro_done or layer == null: return
	_intro_done = true
	var ui = G.ui
	var m := _me()
	var root := ColorRect.new()
	root.color = Color(0.02, 0.01, 0.04, 0.96)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	intro_ui = root
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	root.add_child(v)
	var n_mafia := sim.agents.filter(func(a): return a.mafia).size() if not guest else int(sim.cfg.get("mafia", 1))
	var t: Label = ui.lbl("YOU ARE MAFIA" if m.mafia else "YOU ARE STAFF", 72, font, RED if m.mafia else Color(0.4, 0.85, 1.0), 12)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub: Label = ui.lbl("Take out the staff without getting caught." if m.mafia else "There %s %d Mafia among us. Do your tasks, stay alive, vote them out." % ["is" if n_mafia == 1 else "are", n_mafia], 24, small, Color(0.85, 0.87, 0.95))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	v.add_child(row)
	var show := sim.agents.filter(func(a): return a.mafia) if m.mafia else [m]
	for a in show:
		var col := VBoxContainer.new()
		var img := TextureRect.new(); img.texture = G.portraits.get(a.C.id); img.custom_minimum_size = Vector2(170, 170)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(img)
		var nl: Label = ui.lbl(_nm(a) + ("  (YOU)" if a == m else ""), 24, font, RED if m.mafia else Color.WHITE, 6)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(nl)
		row.add_child(col)
	if m.mafia and show.size() > 1:
		var p: Label = ui.lbl("YOUR PARTNERS ARE MARKED IN RED — ON THE FLOOR, THE MAP AND AT MEETINGS", 18, small, RED)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(p)
	G.sfx("vs")
	get_tree().create_timer(4.0 if not autoplay else 0.8).timeout.connect(func():
		if intro_ui != null and is_instance_valid(intro_ui):
			var tw := intro_ui.create_tween()
			tw.tween_property(intro_ui, "modulate:a", 0.0, 0.5)
			tw.tween_callback(intro_ui.queue_free)
		intro_ui = null)


func start_net(g, people: Array, cfg: Dictionary, seed: int, my_id: int, party: Party, is_guest: bool, pids: Dictionary) -> void:
	net = party; guest = is_guest; pid_agent = pids
	net.message.connect(_net_message)
	if not guest: net.left.connect(_net_left)
	start(g, people, cfg, seed, my_id)


func stop() -> void:
	if net != null:
		if net.message.is_connected(_net_message): net.message.disconnect(_net_message)
		if net.left.is_connected(_net_left): net.left.disconnect(_net_left)
	if world != null: world.queue_free()
	if layer != null: layer.queue_free()
	world = null; layer = null


func _me() -> MafiaSim.Agent:
	return sim.agents[me]


# ---------------------------------------------------------------- world
func _mat(c: Color, rough := 0.8, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough
	if emit > 0.0: m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	return m


func _box(size: Vector3, m: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b; mi.material_override = m; mi.position = pos
	(parent if parent != null else world).add_child(mi)
	return mi


const ROOM_TEX := {"cafe": "floor_tiles_06", "print": "floor_tiles_06", "reception": "floor_tiles_06", "server": "concrete_tiles_02",
	"storage": "concrete_tiles_02", "dev": "laminate_floor_02", "board": "laminate_floor_02", "hr": "dirty_carpet"}
const FLOOR_TINT := {"cafe": Color(1.0, 0.93, 0.85), "print": Color(0.85, 0.88, 0.95), "reception": Color(0.95, 0.92, 1.0), "server": Color(0.55, 0.62, 0.7),
	"storage": Color(0.85, 0.8, 0.7), "dev": Color(0.95, 0.9, 0.85), "board": Color(0.8, 0.65, 0.6), "hr": Color(0.75, 0.6, 0.85)}
const ROOM_SCALE := {"cafe": 0.35, "print": 0.35, "reception": 0.3, "server": 0.3, "storage": 0.3, "dev": 0.25, "board": 0.25, "hr": 0.4}
var _tex_cache := {}
var _model_cache := {}


## Photo-textured material, laid in world space so big floors tile without stretching.
func _tex_mat(name: String, tint: Color, scale: float) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [name, tint, scale]
	if _tex_cache.has(key): return _tex_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s_diff_1k.jpg" % name)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/%s_nor_gl_1k.jpg" % name)
	m.albedo_color = tint; m.roughness = 0.85
	m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_tex_cache[key] = m
	return m


## A piece of furniture, scaled to fit its footprint [w, d, h], turned, standing on the floor (or on top of something).
func _decor(d: Dictionary) -> void:
	var sz: Array = d.s
	var pos := Vector2(float(d.p[0]), float(d.p[1]))
	var holder := Node3D.new()
	holder.position = V(pos, float(d.get("y", 0.0)))
	holder.rotation.y = deg_to_rad(float(d.get("r", 0.0)))
	world.add_child(holder)
	if d.m == "rack":
		_box(Vector3(sz[0], sz[2], sz[1]), _mat(Color(0.08, 0.08, 0.1), 0.4), Vector3(0, sz[2] / 2.0, 0), holder)
		for k in 6:
			_box(Vector3(sz[0] + 0.03, 0.05, sz[1] * 0.8), _mat([Color(0.2, 1, 0.4), Color(0.2, 0.7, 1)][k % 2], 0.3, 3.0), Vector3(0, 0.3 + k * 0.32, 0), holder)
		return
	var ps: PackedScene = _model_cache.get(d.m, null)
	if ps == null:
		ps = load("res://assets/kenney/furniture/%s.glb" % d.m)
		if ps == null: return
		_model_cache[d.m] = ps
	var model: Node3D = ps.instantiate()
	holder.add_child(model)
	_tone(model)
	# measure the model, then stretch it to the footprint and sit it on the floor, centred
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var t: Transform3D = model.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform if model.is_inside_tree() else (mi as MeshInstance3D).transform
		var bb: AABB = t * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first or box.size.x <= 0.0: return
	var k := Vector3(float(sz[0]) / box.size.x, float(sz[2]) / maxf(box.size.y, 0.01), float(sz[1]) / maxf(box.size.z, 0.01))
	model.scale = k
	model.position = -Vector3(box.get_center().x * k.x, box.position.y * k.y, box.get_center().z * k.z)


## Kenney's colours are pale pastels: darken and saturate them a touch so they read under office lights.
var _tone_cache := {}
func _tone(model: Node) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null: continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			if not (src is BaseMaterial3D): continue
			if not _tone_cache.has(src):
				var m: BaseMaterial3D = src.duplicate()
				var c: Color = m.albedo_color
				c = Color.from_hsv(c.h, minf(1.0, c.s * 1.25), c.v * 0.62, c.a)
				m.albedo_color = c; m.roughness = 0.7; m.metallic = minf(m.metallic, 0.2)
				_tone_cache[src] = m
			(mi as MeshInstance3D).set_surface_override_material(i, _tone_cache[src])


static func V(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.02, 0.02, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.73, 0.85); env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true; env.glow_intensity = 0.35
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-65), deg_to_rad(20), 0); sun.light_energy = 0.55; sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40
	world.add_child(sun)
	lights.append(sun)
	# floors: photo textures (Poly Haven, CC0) laid in world space, tinted per room
	_box(Vector3(62, 0.1, 42), _tex_mat("concrete_tiles_02", Color(0.62, 0.6, 0.68), 0.35), Vector3(0, -0.05, 0))   # hallways
	for rm in MafiaSim.ROOMS:
		var r: Array = rm.r
		var c := Vector2((r[0] + r[2]) / 2.0, (r[1] + r[3]) / 2.0)
		_box(Vector3(r[2] - r[0], 0.02, r[3] - r[1]), _tex_mat(ROOM_TEX.get(rm.id, "laminate_floor_02"), FLOOR_TINT.get(rm.id, Color.WHITE), ROOM_SCALE.get(rm.id, 0.3)), V(c, 0.01))
		var l := Label3D.new()
		l.text = rm.name; l.font = font; l.font_size = 160; l.outline_size = 0
		l.modulate = Color(1, 1, 1, 0.13); l.rotation.x = -PI / 2; l.pixel_size = 0.01
		l.position = V(c, 0.03)
		world.add_child(l)
		var om := OmniLight3D.new(); om.position = V(c, 3.2); om.omni_range = 13.0; om.light_energy = 0.9
		om.light_color = Color(1.0, 0.95, 0.88)
		world.add_child(om)
		lights.append(om)
	var wall_m := _tex_mat("grey_plaster", Color(0.92, 0.9, 0.96), 0.5)
	var top_m := _mat(Color(0.55, 0.32, 0.9), 0.5, 0.6)
	for w in sim.walls:
		if not (w.size.x < 0.5 or w.size.y < 0.5): continue   # furniture: drawn from the decor list
		var c: Vector2 = w.get_center()
		_box(Vector3(w.size.x, 1.35, w.size.y), wall_m, V(c, 0.675))   # low walls: the camera looks over them
		_box(Vector3(w.size.x + 0.02, 0.06, w.size.y + 0.02), top_m, V(c, 1.35))
	# furniture (Kenney Furniture Kit, CC0)
	for d in MafiaSim.DECOR: _decor(d)
	# task stations: a glowing ring on the floor and a sign
	for s in MafiaSim.STATIONS:
		var p := MafiaSim.st_pos(s)
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new(); tor.inner_radius = 0.75; tor.outer_radius = 0.9; tor.rings = 32
		ring.mesh = tor; ring.material_override = _mat(Color(0.3, 0.8, 1.0), 0.4, 2.0); ring.position = V(p, 0.04)
		world.add_child(ring)
		var sign := Label3D.new()
		sign.text = String(s.title).to_upper(); sign.font = small; sign.font_size = 56; sign.outline_size = 8
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sign.position = V(p, 2.0); sign.modulate = Color(0.75, 0.9, 1.0)
		world.add_child(sign)
	# the ALERT button on the boardroom table, office chairs round it
	var btn := MeshInstance3D.new()
	var cy := CylinderMesh.new(); cy.top_radius = 0.45; cy.bottom_radius = 0.55; cy.height = 0.3
	btn.mesh = cy; btn.material_override = _mat(RED, 0.3, 1.4); btn.position = V(MafiaSim.ALERT_POS, 0.95)
	world.add_child(btn)
	var al := Label3D.new(); al.text = "ALERT"; al.font = font; al.font_size = 70; al.outline_size = 10
	al.billboard = BaseMaterial3D.BILLBOARD_ENABLED; al.position = V(MafiaSim.ALERT_POS, 1.8); al.modulate = RED
	world.add_child(al)
	for k in MafiaSim.SEATS:
		var a := TAU * k / MafiaSim.SEATS
		var cp := Vector2(cos(a) * 5.6, sin(a) * 3.0)
		_decor({m = "chairDesk", p = [cp.x, cp.y], r = rad_to_deg(atan2(-cp.x, -cp.y)), s = [0.8, 0.8, 1.0]})
	# fuse box in storage
	_box(Vector3(0.8, 1.2, 0.3), _mat(Color(0.75, 0.6, 0.15), 0.4), V(MafiaSim.FUSE_POS, 1.2))
	var fl := Label3D.new(); fl.text = "FUSE BOX"; fl.font = small; fl.font_size = 56; fl.outline_size = 8
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; fl.position = V(MafiaSim.FUSE_POS, 2.2); fl.modulate = GOLD
	world.add_child(fl)
	# hallway plants
	for p in [[-13, -19], [13, -19], [-13, 19], [13, 19], [-13, -6.5], [13, 8.5]]:
		_decor({m = "pottedPlant", p = p, s = [0.7, 0.7, 1.6]})
	for a in sim.agents: rigs.append(_agent_visual(a))
	cam = Camera3D.new(); cam.fov = 50; cam.far = 200
	world.add_child(cam); cam.current = true


func _agent_visual(a: MafiaSim.Agent) -> Dictionary:
	var rig := Main.make_rig(a.C, 0)
	world.add_child(rig)
	rig.position = V(a.pos)
	var tag := Label3D.new()
	tag.text = _nm(a); tag.font = font; tag.font_size = 44; tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tag.no_depth_test = true
	world.add_child(tag)
	return {rig = rig, tag = tag, body = null, pool = null, t = 0.0}


func _nm(a: MafiaSim.Agent) -> String:
	return (String(a.C.person.get("short", a.C.name)) if a.C.has("person") else String(a.C.name)).to_upper()


# ---------------------------------------------------------------- loop
func _physics_process(_dt: float) -> void:
	if sim == null or (paused and net == null): return
	var mine := _controls()
	if guest:
		net.send({t = "fi", mx = snappedf(mine.mx, 0.01), mz = snappedf(mine.mz, 0.01)})
		var got := false
		for m in inbox:
			if m.t == "fs":
				sim.apply(m.s); got = true
				for e in m.e: _event(Party.unpack_event(e))
			elif m.t == "fp":
				sim.apply_private(m.p, me)
				_intro()
		inbox.clear()
		if not got: sim.coast()
	else:
		inputs[me] = mine
		if autoplay: inputs.erase(me)
		_me().human = not autoplay
		sim.tick(inputs)
		for e in sim.events: _event(e)
		if net != null:
			outbox.append_array(sim.events)
			_snap_t -= MafiaSim.DT
			if _snap_t <= 0.0 or sim.phase != "play":
				_snap_t = 0.05
				var ev := []
				for e in outbox: ev.append(Party.pack(e))
				outbox.clear()
				net.broadcast({t = "fs", s = sim.snapshot(), e = ev})
			_priv_t -= MafiaSim.DT
			if _priv_t <= 0.0:
				_priv_t = 0.25
				for pid in pid_agent: net.send_to(pid, {t = "fp", p = sim.private_for(int(pid_agent[pid]))})
	if sim.finished() and not results_shown:
		results_shown = true
		if not guest:
			roles_final = sim.roles()
			if net != null: net.broadcast({t = "fend", roles = roles_final})
		get_tree().create_timer(1.5).timeout.connect(_show_results)


func _process(dt: float) -> void:
	if sim == null or world == null: return
	var a := Engine.get_physics_interpolation_fraction()
	var mine := _me()
	var vis := sim.vision(mine)
	for i in sim.agents.size():
		var ag: MafiaSim.Agent = sim.agents[i]
		var v: Dictionary = rigs[i]
		var rig = v.rig
		var p := ag.prev_pos.lerp(ag.pos, a)
		var meeting := sim.phase in ["meeting", "vote", "result"]
		if meeting:
			var ang := TAU * i / MafiaSim.SEATS
			p = Vector2(cos(ang) * 5.6, sin(ang) * 3.0)
		rig.position = V(p)
		var face: Vector2 = (-p).normalized() if meeting else ag.dir
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(face.x, face.y), clampf(dt * 12.0, 0.0, 1.0))
		# who you can see: the living see the living (in range, not behind walls); ghosts see everyone
		# the living see the living (in range, not behind walls); ghosts see everyone; the dead skip meetings
		var seen := false
		if meeting: seen = ag.alive
		elif i == me: seen = true
		elif not mine.alive: seen = true
		else: seen = ag.alive and mine.pos.distance_to(ag.pos) < vis and sim.sees(mine.pos, ag.pos)
		rig.visible = seen
		var tag: Label3D = v.tag
		tag.visible = seen
		tag.position = V(p, 2.3 * float(ag.C.get("scale", 1.0)))
		var partner: bool = mine.mafia and ag.mafia and i != me
		tag.modulate = RED if partner else (Color(0.7, 0.8, 1.0, 0.6) if not ag.alive else Color.WHITE)
		tag.text = _nm(ag) + ("  ☠" if not ag.alive else "")
		v.t += dt
		var clip := "idle_relaxed"
		if meeting: clip = "m_sit_talk" if sim.phase == "meeting" and fmod(v.t + i, 6.0) < 2.5 else "m_sit"
		elif ag.act == "stab": clip = "m_stab"
		elif ag.act == "task": clip = "in_tablet"
		elif ag.moving: clip = "m_run"
		if not ClipLib.has(clip): clip = "idle_fight"
		rig.set_clip(clip, fmod(v.t, Fighter._len(clip)), true, false)
		rig.apply_pose(ag.C.pose.guard, not meeting)
		if meeting: rig.position.y = 0.05
		# body where they fell
		var body_at := Vector2.INF
		for b in sim.bodies:
			if int(b.id) == i: body_at = b.pos
		if body_at != Vector2.INF and v.body == null:
			var br := Main.make_rig(ag.C, 0)
			world.add_child(br)
			br.position = V(body_at); br.rotation.y = randf() * TAU
			var dc := "gun_death" if ClipLib.has("gun_death") else "ko"
			br.set_clip(dc, Fighter._len(dc) - 0.05, true, false); br.apply_pose(ag.C.pose.guard, true)
			var pool := MeshInstance3D.new(); var pc := CylinderMesh.new(); pc.top_radius = 0.9; pc.bottom_radius = 0.9; pc.height = 0.02
			pool.mesh = pc; pool.material_override = _mat(Color(0.5, 0.03, 0.05), 0.2); pool.position = V(body_at, 0.03)
			world.add_child(pool)
			v.body = br; v.pool = pool
		elif body_at == Vector2.INF and v.body != null:
			(v.body as Node).queue_free(); (v.pool as Node).queue_free(); v.body = null; v.pool = null
		if v.body != null:
			var bv: bool = not mine.alive or (mine.pos.distance_to(body_at) < vis + 1.0 and sim.sees(mine.pos, body_at))
			(v.body as Node3D).visible = bv and not meeting; (v.pool as Node3D).visible = bv and not meeting
	# camera: above and behind you; the meeting table during meetings
	var meeting2 := sim.phase in ["meeting", "vote", "result"]
	var focus := V(mine.prev_pos.lerp(mine.pos, a)) if not meeting2 else Vector3.ZERO
	var want := focus + (Vector3(0, 11.5, 7.0) if not meeting2 else Vector3(0, 11.0, 9.0))
	cam.position = cam.position.lerp(want, clampf(dt * 6.0, 0.0, 1.0)) if cam.position != Vector3.ZERO else want
	cam.look_at(cam.position - (want - focus), Vector3.UP)
	# darkness outside your vision (less during power cuts)
	var sm: ShaderMaterial = dark.material
	var sc := cam.unproject_position(focus)
	var edge := cam.unproject_position(focus + Vector3(vis, 0, 0))
	sm.set_shader_parameter("c", sc)
	sm.set_shader_parameter("sz", hud.size)
	sm.set_shader_parameter("r", maxf(60.0, sc.distance_to(edge)))
	sm.set_shader_parameter("dark", 0.0 if (meeting2 or not mine.alive) else (0.96 if sim.power_cut else 0.88))
	env.ambient_light_energy = lerpf(env.ambient_light_energy, 0.25 if sim.power_cut else 0.7, dt * 3.0)
	toast_t = maxf(0.0, toast_t - dt)
	_meeting_sync()
	hud.queue_redraw()


# ---------------------------------------------------------------- controls
func _controls() -> Dictionary:
	if paused or task_ui != null or meeting_ui != null or not (sim.phase == "play"): return {mx = 0.0, mz = 0.0}
	var k := func(keys: Array) -> bool:
		for key in keys:
			if Input.is_physical_key_pressed(key): return true
		return false
	var mv := Vector2((1.0 if k.call([KEY_D, KEY_RIGHT]) else 0.0) - (1.0 if k.call([KEY_A, KEY_LEFT]) else 0.0),
		(1.0 if k.call([KEY_S, KEY_DOWN]) else 0.0) - (1.0 if k.call([KEY_W, KEY_UP]) else 0.0))
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var ax := Vector2(Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_X), Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_Y))
		if ax.length() > 0.2: mv = ax
	if touch_move.length() > 0.1: mv = touch_move
	return {mx = mv.x, mz = mv.y}


## What the USE button would do right now.
func _use_kind() -> String:
	var m := _me()
	if sim.phase != "play": return ""
	if sim.power_cut and m.alive and m.pos.distance_to(MafiaSim.FUSE_POS) < MafiaSim.USE_RANGE + 0.6: return "fix"
	if m.alive and m.alerts > 0 and m.pos.distance_to(MafiaSim.ALERT_POS) < MafiaSim.USE_RANGE + 2.5: return "alert"
	if not sim.task_here(m).is_empty(): return "task"
	return ""


func _do(a: String, arg = null) -> void:
	if a == "task":
		var s := sim.task_here(_me())
		if s.is_empty(): return
		_open_task(s)
		return
	if a == "use":
		var u := _use_kind()
		if u == "": return
		_do(u); return
	if guest: net.send({t = "fa", a = a, arg = arg})
	else: sim.act(me, a, arg)


func _open_task(s: Dictionary) -> void:
	if task_ui != null: return
	task_ui = MafiaTask.new()
	task_ui.setup(String(s.kind), String(s.title))
	task_st = String(s.id)
	layer.add_child(task_ui)
	task_ui.done.connect(func():
		_do("task_done", task_st)
		G.sfx("ok")
		_close_task())
	task_ui.closed.connect(_close_task)
	if autoplay: task_ui.solve()


func _close_task() -> void:
	if task_ui != null: task_ui.queue_free()
	task_ui = null


func _unhandled_input(e: InputEvent) -> void:
	if sim == null: return
	if e is InputEventKey and e.pressed and not e.echo:
		if chat_in != null and chat_in.has_focus(): return
		match e.physical_keycode:
			KEY_P, KEY_ESCAPE:
				if task_ui != null: _close_task()
				else: toggle_pause()
			KEY_E, KEY_SPACE: _do("use")
			KEY_R: _do("report")
			KEY_Q: _do("kill")
			KEY_F: _do("sabotage")
			KEY_M, KEY_TAB: show_map = not show_map


func _layout_buttons() -> void:
	var s: Vector2 = G.get_viewport().get_visible_rect().size
	var r := clampf(s.y * 0.075, 36.0, 60.0)
	btns = {
		use = {c = Vector2(s.x - r * 1.5, s.y - r * 1.6), r = r * 1.2, label = "USE"},
		report = {c = Vector2(s.x - r * 4.0, s.y - r * 1.4), r = r, label = "REPORT"},
		kill = {c = Vector2(s.x - r * 1.5, s.y - r * 4.2), r = r, label = "KILL"},
		sabotage = {c = Vector2(s.x - r * 4.0, s.y - r * 3.8), r = r * 0.85, label = "CUT POWER"},
		pause = {c = Vector2(s.x - _mm_rect(s).size.x - 70, 46), r = r * 0.6, label = "II"},
	}


func _btn_on(n: String) -> bool:
	var m := _me()
	if sim.phase != "play" and n != "pause": return false
	match n:
		"use": return _use_kind() != ""
		"report": return m.alive and not sim.body_near(m).is_empty()
		"kill": return m.alive and m.mafia and m.cool <= 0.0 and sim.kill_target(m) != null
		"sabotage": return m.alive and m.mafia and not sim.power_cut and sim.sab_cool <= 0.0
	return true


func _btn_shown(n: String) -> bool:
	if n in ["kill", "sabotage"]: return _me().mafia and _me().alive
	if n == "report": return _me().alive
	return true


func _input(e: InputEvent) -> void:
	if sim == null or task_ui != null or meeting_ui != null or results_shown: return
	var press: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not G.ui.touch_enabled)
	if press and (show_map or _mm_rect(hud.size).has_point(e.position)):
		show_map = not show_map
		get_viewport().set_input_as_handled()
		return
	if press:
		for n in btns:
			if _btn_shown(n) and e.position.distance_to(btns[n].c) <= btns[n].r * 1.1:
				if n == "pause": toggle_pause()
				elif n == "map": show_map = not show_map
				elif not paused: _do(n)
				get_viewport().set_input_as_handled()
				return
	if not G.ui.touch_enabled: return
	var vs: Vector2 = G.get_viewport().get_visible_rect().size
	if e is InputEventScreenTouch:
		if e.pressed and e.position.x < vs.x * 0.45 and move_id < 0: move_id = e.index; move_origin = e.position
		elif not e.pressed and e.index == move_id: move_id = -1; touch_move = Vector2.ZERO
	elif e is InputEventScreenDrag and e.index == move_id:
		touch_move = ((e.position - move_origin) / 70.0).limit_length(1.0)


# ---------------------------------------------------------------- events
func _event(e: Array) -> void:
	var kind: String = e[0]
	stats[kind] = stats.get(kind, 0) + 1
	match kind:
		"kill":
			if int(e[2]) == me: G.sfx("heavy"); _toast("YOU WERE TAKEN OUT")
			elif int(e[1]) == me: G.sfx("hit")
			if int(e[2]) == me or int(e[1]) == me: pass
			elif _me().pos.distance_to((sim.agents[int(e[2])] as MafiaSim.Agent).pos) < sim.vision(_me()): G.sfx("thud")
		"meeting":
			_close_task()
			if guest: sim.chat.clear()
			eject_mafia = false
			G.sfx("vs")
			_voice(int(e[1]), "power")
		"vote": G.sfx("ui")
		"voted": G.sfx("block")
		"result":
			var who := int(e[1])
			if e.size() > 2: eject_mafia = bool(e[2])
			G.sfx("ko" if who >= 0 else "ui")
			if who >= 0: _voice(who, "hurt")
		"task": if int(e[1]) == me: _toast("TASK DONE")
		"power_cut": G.sfx("thud"); _toast("POWER CUT!")
		"power_on": G.sfx("ok"); _toast("POWER RESTORED")
		"chat":
			if guest: sim.chat.append({from = int(e[1]), text = String(e[2]), ghost = bool(e[3])})
		"resume": shown_chat = 0
		"win": G.sfx("ko")


func _voice(i: int, kind: String) -> void:
	if i < 0 or i >= sim.agents.size(): return
	var s := Voices.get_sound((sim.agents[i] as MafiaSim.Agent).C, kind)
	if s == null: return
	var p := AudioStreamPlayer.new(); p.stream = s; p.volume_db = -7.0
	add_child(p); p.play(); p.finished.connect(p.queue_free)


func _toast(t: String) -> void:
	toast = t; toast_t = 2.2


func _net_message(pid: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"fs", "fp":
			if guest: inbox.append(d)
		"fend":
			if guest: roles_final = d.roles
		"fi":
			if not guest and pid_agent.has(pid): inputs[int(pid_agent[pid])] = {mx = float(d.mx), mz = float(d.mz)}
		"fa":
			if not guest and pid_agent.has(pid): sim.act(int(pid_agent[pid]), String(d.a), d.get("arg"))


func _net_left(pid: int) -> void:
	if not pid_agent.has(pid): return
	var a: MafiaSim.Agent = sim.agents[int(pid_agent[pid])]
	a.human = false
	inputs.erase(a.id)
	_toast("%s LEFT · A BOT TAKES OVER" % _nm(a))


# ---------------------------------------------------------------- meeting screen
func _meeting_sync() -> void:
	var ph := sim.phase
	var in_meeting := ph in ["meeting", "vote", "result"]
	if not in_meeting:
		if meeting_ui != null: meeting_ui.queue_free(); meeting_ui = null; meeting_phase = ""; chat_in = null
		return
	if meeting_ui == null:
		_build_meeting()
		shown_chat = 0
	if ph != meeting_phase:
		meeting_phase = ph
		_refresh_cards()
	var ui = G.ui
	var head := "BODY REPORTED" if sim.meeting_body >= 0 else "EMERGENCY MEETING"
	var left := maxi(0, ceili(sim.phase_t))
	timer_lbl.text = {"meeting": "TALK  %d" % left, "vote": "VOTE NOW  %d" % left, "result": ""}.get(ph, "")
	(meeting_ui.get_meta("head") as Label).text = head
	(meeting_ui.get_meta("sub") as Label).text = _meeting_sub()
	# chat (ghost lines only for ghosts)
	while shown_chat < sim.chat.size():
		var c: Dictionary = sim.chat[shown_chat]
		shown_chat += 1
		if c.ghost and _me().alive: continue
		var who: MafiaSim.Agent = sim.agents[int(c.from)]
		chat_log.append_text("[color=#%s]%s%s:[/color] %s\n" % [(who.C.accent as Color).lightened(0.3).to_html(false), "☠ " if c.ghost else "", _nm(who), String(c.text).replace("[", "(")])
	for k in cards.size(): _card_state(k)
	if ph == "result" and not meeting_ui.has_meta("res_shown"):
		meeting_ui.set_meta("res_shown", true)
		var r: Label = meeting_ui.get_meta("res")
		r.visible = true
		(meeting_ui.get_meta("rbg") as Control).visible = true
		r.move_to_front()
		r.text = _result_text()


func _meeting_sub() -> String:
	var by: MafiaSim.Agent = sim.agents[sim.meeting_by] if sim.meeting_by >= 0 else null
	if sim.meeting_body >= 0:
		return "%s found %s in %s" % [_nm(by) if by else "?", _nm(sim.agents[sim.meeting_body]), sim.meeting_room]
	return "%s pressed the ALERT button" % (_nm(by) if by else "?")


func _result_text() -> String:
	if sim.ejected < 0: return "NOBODY WAS FIRED" + ("  (TIE)" if sim.tie else "  (SKIPPED)")
	var e: MafiaSim.Agent = sim.agents[sim.ejected]
	var reveal: bool = bool(sim.cfg.get("reveal", true))
	if not reveal: return "%s WAS FIRED" % _nm(e)
	var was_mafia := e.mafia if not guest else eject_mafia
	return "%s WAS FIRED.  %s" % [_nm(e), "THEY WERE MAFIA!" if was_mafia else "THEY WERE NOT MAFIA."]


func _build_meeting() -> void:
	var ui = G.ui
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	meeting_ui = root
	var bg := ColorRect.new(); bg.color = Color(0.03, 0.02, 0.06, 0.82); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var vs: Vector2 = G.get_viewport().get_visible_rect().size
	var head: Label = ui.lbl("", 40, font, RED, 8)
	head.position = Vector2(30, 14); root.add_child(head)
	var sub: Label = ui.lbl("", 20, small, Color(0.85, 0.87, 0.95))
	sub.position = Vector2(32, 64); root.add_child(sub)
	timer_lbl = ui.lbl("", 30, font, GOLD, 6)
	timer_lbl.position = Vector2(vs.x - 300, 18); root.add_child(timer_lbl)
	root.set_meta("head", head); root.set_meta("sub", sub)
	# player cards: two columns
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 8)
	grid.position = Vector2(30, 104)
	root.add_child(grid)
	cards = []
	var cw := clampf(vs.x * 0.24, 220.0, 320.0)
	for i in sim.agents.size():
		var ag: MafiaSim.Agent = sim.agents[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(cw, clampf((vs.y - 220.0) / 5.0, 46.0, 72.0))
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", ui.sbox(Color(0.1, 0.08, 0.16, 0.95), ag.C.accent, 2, 0.0))
		b.add_theme_stylebox_override("hover", ui.sbox(Color(0.16, 0.12, 0.26, 0.95), GOLD, 2, 0.0))
		b.add_theme_stylebox_override("pressed", ui.sbox(Color(0.2, 0.15, 0.3, 0.95), GOLD, 3, 0.0))
		b.add_theme_stylebox_override("disabled", ui.sbox(Color(0.06, 0.05, 0.08, 0.9), Color(0.3, 0.3, 0.35), 1, 0.0))
		var h := HBoxContainer.new(); h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_preset(Control.PRESET_FULL_RECT); h.add_theme_constant_override("separation", 8)
		var img := TextureRect.new(); img.texture = G.portraits.get(ag.C.id); img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; img.custom_minimum_size = Vector2(b.custom_minimum_size.y - 6, 0)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(img)
		var nl: Label = ui.lbl(_nm(ag), 20, font, Color.WHITE)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE; nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(nl)
		var st: Label = ui.lbl("", 16, small, GOLD)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE; st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(st)
		b.add_child(h)
		var idx := i
		b.pressed.connect(func(): _vote(idx))
		grid.add_child(b)
		cards.append({btn = b, name = nl, st = st})
	var skip: Button = ui.big_btn("SKIP VOTE", Color(0.55, 0.62, 0.75), func(): _vote(-1))
	skip.position = Vector2(30, vs.y - 90); root.add_child(skip)
	root.set_meta("skip", skip)
	# chat
	var cx := 30.0 + cw * 2.0 + 30.0
	var cwid := vs.x - cx - 30.0
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ui.sbox(Color(0.05, 0.04, 0.09, 0.95), Color(0.58, 0.3, 0.85), 2, 0.0))
	panel.position = Vector2(cx, 104); panel.size = Vector2(cwid, vs.y - 260)
	root.add_child(panel)
	chat_log = RichTextLabel.new(); chat_log.bbcode_enabled = true; chat_log.scroll_following = true
	chat_log.add_theme_font_override("normal_font", small); chat_log.add_theme_font_size_override("normal_font_size", 20)
	panel.add_child(chat_log)
	chat_in = LineEdit.new()
	chat_in.placeholder_text = "Type to chat…" if _me().alive else "Ghost chat (only the dead can see this)"
	chat_in.max_length = 120
	chat_in.position = Vector2(cx, vs.y - 146); chat_in.size = Vector2(cwid - 120, 52)
	chat_in.add_theme_font_override("font", small); chat_in.add_theme_font_size_override("font_size", 22)
	chat_in.text_submitted.connect(func(t): _send_chat(t))
	root.add_child(chat_in)
	var send: Button = ui.big_btn("SEND", P2(), func(): _send_chat(chat_in.text))
	send.position = Vector2(vs.x - 140, vs.y - 150); send.custom_minimum_size = Vector2(110, 52)
	root.add_child(send)
	var quick := HBoxContainer.new(); quick.add_theme_constant_override("separation", 8)
	quick.position = Vector2(cx, vs.y - 84)
	for q in ["WHERE?", "I SAW IT", "SKIP", "NOT ME!", "SUS"]:
		var qb: Button = ui.big_btn(q, Color(0.35, 0.3, 0.5), func(): _send_chat(q.to_lower() if q != "SUS" else "sus..."))
		qb.custom_minimum_size = Vector2(0, 44); qb.add_theme_font_size_override("font_size", 16)
		quick.add_child(qb)
	root.add_child(quick)
	var res: Label = ui.lbl("", 40, font, GOLD, 10)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.autowrap_mode = TextServer.AUTOWRAP_WORD
	res.position = Vector2(20, vs.y * 0.4); res.size = Vector2(vs.x - 40, 120)
	var rbg := ColorRect.new(); rbg.color = Color(0, 0, 0, 0.75); rbg.position = Vector2(0, vs.y * 0.4 - 20); rbg.size = Vector2(vs.x, 150)
	rbg.mouse_filter = Control.MOUSE_FILTER_IGNORE; rbg.visible = false
	root.add_child(rbg); root.set_meta("rbg", rbg)
	res.visible = false
	root.add_child(res)
	root.set_meta("res", res)


static func P2() -> Color:
	return Color(0.13, 0.78, 0.92)


func _card_state(k: int) -> void:
	var ag: MafiaSim.Agent = sim.agents[k]
	var c: Dictionary = cards[k]
	var b: Button = c.btn
	var can_vote := sim.phase == "vote" and _me().alive and _me().voted == -2 and ag.alive
	b.disabled = not can_vote
	var tag := ""
	if not ag.alive: tag = "FIRED" if ag.ejected else "DEAD"
	elif sim.phase == "result" and not guest: tag = "%d votes" % sim.agents.filter(func(o): return o.voted == k).size()
	elif ag.voted != -2: tag = "VOTED ✔"
	if k == me: tag += "  (YOU)"
	if _me().mafia and ag.mafia and k != me:
		(c.name as Label).modulate = RED
		tag = "MAFIA  " + tag
	(c.st as Label).text = tag
	b.modulate = Color(1, 1, 1, 1.0 if ag.alive else 0.45)
	var skip: Button = meeting_ui.get_meta("skip")
	skip.disabled = not (sim.phase == "vote" and _me().alive and _me().voted == -2)


func _refresh_cards() -> void:
	for k in cards.size(): _card_state(k)


func _vote(target: int) -> void:
	if sim.phase != "vote" or not _me().alive or _me().voted != -2: return
	if not guest: sim.act(me, "vote", target)
	else:
		net.send({t = "fa", a = "vote", arg = target})
		_me().voted = target
	G.sfx("ok")


func _send_chat(t: String) -> void:
	t = t.strip_edges()
	if t == "": return
	if chat_in != null: chat_in.text = ""
	if guest: net.send({t = "fa", a = "chat", arg = t})
	else: sim.act(me, "chat", t)


# ---------------------------------------------------------------- HUD
func _draw_hud() -> void:
	var s := hud.size
	var m := _me()
	var ink := Color(0.95, 0.96, 1.0)
	if meeting_ui != null: return
	# role + tasks
	var role := "MAFIA" if m.mafia else "STAFF"
	hud.draw_string(font, Vector2(24, 44), role + ("  ·  GHOST" if not m.alive else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, RED if m.mafia else Color(0.4, 0.85, 1.0))
	var sub := "Take them out. Don't get caught." if m.mafia else "Finish your tasks. Find the Mafia."
	if m.mafia:
		var team := sim.agents.filter(func(o): return o.mafia and o != m).map(func(o): return _nm(o))
		if not team.is_empty(): sub = "Partner: " + ", ".join(team)
	hud.draw_string(small, Vector2(26, 70), sub, HORIZONTAL_ALIGNMENT_LEFT, 420, 18, Color(0.8, 0.82, 0.9))
	var y := 102.0
	hud.draw_string(small, Vector2(26, y), "FAKE TASKS (blend in)" if m.mafia else "YOUR TASKS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)
	for t in m.tasks:
		y += 22.0
		var stn := sim.station(t.st)
		var room := ""
		for rm in MafiaSim.ROOMS: if rm.id == stn.get("room", ""): room = rm.name
		hud.draw_string(small, Vector2(26, y), "%s %s · %s" % ["✔" if t.done else "•", stn.get("title", t.st), room.capitalize()], HORIZONTAL_ALIGNMENT_LEFT, 420, 18,
			Color(0.5, 0.9, 0.55) if t.done else ink)
	# team task bar
	var bw := minf(420.0, s.x * 0.36)
	var bar := Rect2(Vector2((s.x - bw) / 2.0, 18), Vector2(bw, 18))
	hud.draw_rect(bar, Color(0, 0, 0, 0.55))
	if sim.tasks_total > 0: hud.draw_rect(Rect2(bar.position, Vector2(bw * sim.tasks_done / float(sim.tasks_total), 18)), Color(0.35, 0.9, 0.45))
	hud.draw_rect(bar, Color(1, 1, 1, 0.4), false, 2.0)
	hud.draw_string(small, bar.position + Vector2(0, 38), "OFFICE TASKS", HORIZONTAL_ALIGNMENT_CENTER, bw, 16, Color(0.8, 0.82, 0.9))
	hud.draw_string(small, bar.position + Vector2(0, 58), sim.room_at(m.pos), HORIZONTAL_ALIGNMENT_CENTER, bw, 18, GOLD)
	if sim.power_cut:
		hud.draw_string(font, Vector2(0, 120), "POWER CUT — FIX THE FUSE BOX IN STORAGE", HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, Color(1.0, 0.6, 0.3))
	if m.mafia and m.alive and m.cool > 0.0:
		hud.draw_string(small, Vector2(0, s.y - 40), "knife ready in %d" % ceili(m.cool), HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, RED)
	# buttons
	for n in btns:
		if not _btn_shown(n): continue
		var b: Dictionary = btns[n]
		var on := _btn_on(n)
		var col := RED if n in ["kill", "sabotage", "report"] else (GOLD if n == "use" else Color(0.58, 0.3, 0.85))
		hud.draw_circle(b.c, b.r, Color(col, 0.55 if on else 0.12))
		hud.draw_arc(b.c, b.r, 0, TAU, 40, Color(col, 0.95 if on else 0.35), 3.0)
		var label: String = b.label
		if n == "use":
			label = {"fix": "FIX", "alert": "ALERT", "task": "TASK"}.get(_use_kind(), "USE")
		if n == "kill" and m.cool > 0.0: label = str(ceili(m.cool))
		var fs := int(b.r * (0.5 if label.length() <= 3 else 0.3))
		hud.draw_string(font, b.c + Vector2(-b.r, fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, Color(1, 1, 1, 1.0 if on else 0.5))
	if G.ui.touch_enabled and move_id >= 0:
		hud.draw_arc(move_origin, 70.0, 0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
		hud.draw_circle(move_origin + touch_move * 70.0, 28.0, Color(0.62, 0.38, 1.0, 0.5))
	if not G.ui.touch_enabled:
		hud.draw_string(small, Vector2(0, s.y - 12), "WASD move · E use / task · R report · Q kill · F cut power · M / tap minimap  map · P pause", HORIZONTAL_ALIGNMENT_CENTER, s.x, 17, Color(0.8, 0.82, 0.9, 0.7))
	if toast_t > 0.0:
		hud.draw_string(font, Vector2(0, s.y * 0.3), toast, HORIZONTAL_ALIGNMENT_CENTER, s.x, 46, Color(1, 1, 1, clampf(toast_t / 0.4, 0.0, 1.0)))
	if show_map: _draw_map(s)
	else: _draw_minimap(s)


## Top-right corner: the floor plan, you, your tasks, (Mafia) your partners.
func _mm_rect(s: Vector2) -> Rect2:
	var w := clampf(s.x * 0.2, 170.0, 260.0)
	return Rect2(Vector2(s.x - w - 16, 16), Vector2(w, w * 42.0 / 62.0))


func _draw_minimap(s: Vector2) -> void:
	_plan(_mm_rect(s), false)


func _plan(r: Rect2, big: bool) -> void:
	var sc := r.size.x / 62.0
	var P := func(p: Vector2) -> Vector2: return r.position + (p + Vector2(31, 21)) * sc
	hud.draw_rect(r, Color(0.03, 0.03, 0.06, 0.82))
	for rm in MafiaSim.ROOMS:
		var q: Array = rm.r
		var rr := Rect2(P.call(Vector2(q[0], q[1])), Vector2(q[2] - q[0], q[3] - q[1]) * sc)
		var here: bool = sim.room_at(_me().pos) == rm.name
		hud.draw_rect(rr, Color(0.42, 0.32, 0.62, 0.75) if here else Color(0.25, 0.2, 0.38, 0.6))
		hud.draw_rect(rr, Color(0.6, 0.5, 0.9), false, 1.5 if not big else 2.0)
		if big or here:
			hud.draw_string(small, rr.position + Vector2(0, rr.size.y / 2.0 + 6), rm.name if big else rm.name.left(9), HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 16 if big else 11, Color.WHITE)
	for t in _me().tasks:
		if not t.done: hud.draw_circle(P.call(MafiaSim.st_pos(sim.station(t.st))), 6.0 if big else 3.5, GOLD)
	if sim.power_cut: hud.draw_circle(P.call(MafiaSim.FUSE_POS), 8.0 if big else 4.5, Color(1.0, 0.6, 0.3))
	hud.draw_circle(P.call(MafiaSim.ALERT_POS), 6.0 if big else 3.0, RED)
	if _me().mafia:
		for o in sim.agents:
			if o.mafia and o.id != me and o.alive: hud.draw_circle(P.call(o.pos), 7.0 if big else 4.0, RED)
	var mp: Vector2 = P.call(_me().pos)
	hud.draw_circle(mp, 8.0 if big else 4.5, Color(0.4, 0.85, 1.0))
	hud.draw_arc(mp, (8.0 if big else 4.5) + 2.0, 0, TAU, 16, Color.WHITE, 1.5)
	hud.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.5)


func _draw_map(s: Vector2) -> void:
	var w := minf(s.x * 0.72, s.y * 0.72 * 62.0 / 42.0)
	var r := Rect2((s - Vector2(w, w * 42.0 / 62.0)) / 2.0, Vector2(w, w * 42.0 / 62.0))
	hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.5))
	_plan(r, true)
	hud.draw_string(small, Vector2(0, r.end.y + 26), "yellow: your tasks  ·  red: ALERT button" + ("  ·  red dots: your partners" if _me().mafia else "") + "   —   tap / M to close", HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(0.85, 0.87, 0.95))


func _draw_map_old(s: Vector2) -> void:
	var sc := minf(s.x * 0.7 / 62.0, s.y * 0.7 / 42.0)
	var o := s / 2.0
	var P := func(p: Vector2) -> Vector2: return o + p * sc
	hud.draw_rect(Rect2(o - Vector2(31, 21) * sc, Vector2(62, 42) * sc), Color(0.03, 0.03, 0.06, 0.9))
	for rm in MafiaSim.ROOMS:
		var r: Array = rm.r
		var rr := Rect2(P.call(Vector2(r[0], r[1])), Vector2(r[2] - r[0], r[3] - r[1]) * sc)
		hud.draw_rect(rr, Color(0.3, 0.25, 0.45, 0.6)); hud.draw_rect(rr, Color(0.6, 0.5, 0.9), false, 2.0)
		hud.draw_string(small, rr.position + Vector2(0, rr.size.y / 2.0), rm.name, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 16, Color.WHITE)
	for t in _me().tasks:
		if t.done: continue
		hud.draw_circle(P.call(MafiaSim.st_pos(sim.station(t.st))), 7.0, GOLD)
	if sim.power_cut: hud.draw_circle(P.call(MafiaSim.FUSE_POS), 9.0, Color(1.0, 0.6, 0.3))
	hud.draw_circle(P.call(_me().pos), 8.0, Color(0.4, 0.85, 1.0))
	hud.draw_string(small, Vector2(0, o.y + 21 * sc + 26), "M / MAP to close", HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(0.8, 0.82, 0.9))


# ---------------------------------------------------------------- pause + results
var pause_panel: Control = null


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.03, 0.1, 0.94); sb.border_color = Color(0.58, 0.3, 0.85); sb.set_border_width_all(2)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	return panel


func _center(p: Control) -> void:
	p.reset_size()
	p.position = (G.get_viewport().get_visible_rect().size - p.size) / 2.0


func toggle_pause() -> void:
	if results_shown or layer == null: return
	paused = not paused
	if pause_panel != null: pause_panel.queue_free(); pause_panel = null
	if not paused: return
	var ui = G.ui
	var panel := _panel()
	var v: VBoxContainer = panel.get_child(0)
	v.add_child(ui.lbl("PAUSED" if net == null else "MENU", 44, font, GOLD, 8))
	if net != null: v.add_child(ui.lbl("The game keeps going for everyone else.", 18, small, Color(0.8, 0.82, 0.9)))
	var resume: Button = ui.big_btn("RESUME", P2(), toggle_pause)
	v.add_child(resume)
	v.add_child(ui.big_btn("QUIT TO MENU", Color(0.55, 0.62, 0.75), func(): paused = false; _quit()))
	_center(panel)
	pause_panel = panel


func _quit() -> void:
	finished.emit()
	if net != null: G.lobby.leave()
	else: G.ui.show_title()


func _show_results() -> void:
	var ui = G.ui
	_close_task()
	var panel := _panel()
	var v: VBoxContainer = panel.get_child(0)
	var staff_won := sim.winner == "staff"
	var mine_won := (staff_won and not _me().mafia) or (not staff_won and _me().mafia)
	v.add_child(ui.lbl("VICTORY" if mine_won else "DEFEAT", 52, font, GOLD if mine_won else Color(0.8, 0.8, 0.9), 10))
	v.add_child(ui.lbl(("STAFF WIN — " if staff_won else "MAFIA WIN — ") + sim.win_why, 24, font, Color(0.4, 0.85, 1.0) if staff_won else RED))
	var roles: Array = roles_final if not roles_final.is_empty() else sim.roles()
	for i in sim.agents.size():
		var ag: MafiaSim.Agent = sim.agents[i]
		var maf: bool = roles[i] if i < roles.size() else false
		v.add_child(ui.lbl("%s%s   %s%s" % [_nm(ag), "  (YOU)" if i == me else "", "MAFIA" if maf else "staff", "" if ag.alive else ("  · fired" if ag.ejected else "  · dead")], 20, small, RED if maf else Color(0.85, 0.88, 0.95)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	if net != null:
		row.add_child(ui.big_btn("BACK TO LOBBY", P2(), func(): finished.emit(); G.lobby.back_to_lobby()))
		row.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), func(): finished.emit(); G.lobby.leave()))
	else:
		var C: Dictionary = _me().C
		row.add_child(ui.big_btn("PLAY AGAIN", P2(), func(): finished.emit(); G.lobby.show_menu("mafia", C)))
		row.add_child(ui.big_btn("MAIN MENU", Color(0.55, 0.62, 0.75), func(): finished.emit(); ui.show_title()))
	v.add_child(row)
	_center(panel)
