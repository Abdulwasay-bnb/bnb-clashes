extends Node
## Step-by-step tutorials. The first time you open a game (while tutorials are ON) its tutorial runs:
## a card per step with what to do and the controls for your device. SKIP closes it; HOW TO PLAY on any
## pause screen shows it again; the TUTORIALS ON / OFF switch there turns the first-time tutorials on or off.
## A game can supply its own steps with `static func tutorial_steps(variant) -> Array` ({title, text, keys, touch}).

signal closed

const SAVE := "user://settings.cfg"

const STEPS := {
	"clash": [
		{title = "WELCOME TO CLASH", text = "A 3D fighting game. Knock your colleague's health bar to zero to win a round; best of three rounds wins the fight.", keys = "", touch = ""},
		{title = "MOVE", text = "Walk back and forward. Double-tap forward and keep holding to RUN. Hold up to jump.", keys = "A / D move  ·  double-tap D to run  ·  hold W to jump  ·  S crouch", touch = "Left stick to move  ·  push it twice forward to run  ·  push up to jump"},
		{title = "ATTACK", text = "Four buttons: two punches and two kicks. Press them in a rhythm to chain strings.", keys = "U = punch 1  ·  I = punch 2  ·  J = kick 3  ·  K = kick 4", touch = "The four round buttons on the right"},
		{title = "DEFEND", text = "Stand still or hold back to block highs and mids. Crouch to block lows. Tap up or down to sidestep straight attacks.", keys = "hold A to block  ·  S to crouch-block  ·  tap W / S to sidestep", touch = "Pull the stick back to block, down to crouch"},
		{title = "POWERS", text = "BLUE power once a round any time. When your health drops to 30% or less, your FINAL power unlocks: a cinematic finisher. It can be blocked!", keys = "U+J = BLUE  ·  I+K = FINAL  ·  U+I = grapple", touch = "BLUE and FINAL buttons appear above the attack buttons"},
	],
	"race": [
		{title = "RUSH HOUR", text = "A ten-car street race, three laps. Finish first!", keys = "", touch = ""},
		{title = "DRIVE", text = "Gas, brake and steer. Drift through corners to keep your speed.", keys = "W gas  ·  S brake  ·  A / D steer  ·  SPACE drift", touch = "Steer with the left buttons, GAS and BRAKE on the right"},
		{title = "ITEMS", text = "Drive through the glowing ? boxes to pick up an item, then throw it at the car ahead or drop it behind you.", keys = "J use your item", touch = "ITEM button"},
		{title = "BOOST", text = "Your nitro refills over time; your personal POWER charges as you drive and race.", keys = "SHIFT nitro  ·  K your power", touch = "NITRO and POWER buttons"},
		{title = "GRAND PRIX", text = "Win all six tracks in a row from 1st place to earn the Grand Prix champion certificate.", keys = "", touch = ""},
	],
	"ops": [
		{title = "OFFICE OPS", text = "Team deathmatch. Your team glows blue, the enemy glows RED. First team to the kill target (or most kills in 5 minutes) wins.", keys = "", touch = ""},
		{title = "MOVE AND AIM", text = "Move with WASD and aim with the mouse. Sprint to get around, crouch for accuracy.", keys = "WASD move  ·  mouse aim  ·  SHIFT sprint  ·  C crouch  ·  SPACE jump", touch = "Left stick to move, drag the right side to aim"},
		{title = "SHOOT", text = "Fire with the left mouse button, aim down sights (or scope) with the right. Headshots hit hardest.", keys = "LMB fire  ·  RMB aim  ·  R reload", touch = "FIRE (drag it to aim while shooting)  ·  AIM  ·  R"},
		{title = "LOADOUT TABLE", text = "Your spawn has a table with every gun and grenade. Walk up to it, look at what you want and take it.", keys = "E take  ·  1 2 3 / Q / wheel switch  ·  G next throwable", touch = "USE appears at the table  ·  SWAP  ·  NADE"},
		{title = "SPAWN PROTECTION", text = "For 2.5 seconds after you spawn nobody can hurt you, and you can't shoot yet. Look around and plan.", keys = "", touch = ""},
	],
	"ludo": [
		{title = "LUDO", text = "Race your four pawns round the board and into your home triangle before everyone else.", keys = "", touch = ""},
		{title = "ROLL", text = "Roll the die on your turn. You need a 6 to bring a pawn out of your yard — and a 6 rolls again.", keys = "SPACE or click to roll", touch = "Tap ROLL"},
		{title = "MOVE", text = "Pawns that can move glow. Pick one. Land on a rival to send them back home; the star squares are safe.", keys = "click a glowing pawn or press 1–4", touch = "Tap a glowing pawn"},
		{title = "WIN", text = "Get all four pawns home first.", keys = "", touch = ""},
	],
	"mafia": [
		{title = "MAFIA", text = "Someone in the office is the Mafia. Staff win by finishing tasks or voting the Mafia out; the Mafia wins by picking everyone off.", keys = "", touch = ""},
		{title = "MOVE AND WORK", text = "Walk the office and do the tasks on your list (yellow markers on the map).", keys = "WASD move  ·  E / SPACE use  ·  M map", touch = "Stick to move  ·  USE button"},
		{title = "BODIES AND MEETINGS", text = "Found someone? Report it. Everyone meets at the boardroom table to chat and vote.", keys = "R report  ·  type in the chat, click a face to vote", touch = "REPORT  ·  tap a face to vote"},
		{title = "IF YOU ARE MAFIA", text = "Get close and strike when nobody's watching. Sabotage the power to cause chaos. Act innocent in meetings!", keys = "Q kill  ·  F sabotage", touch = "KILL  ·  SABOTAGE"},
	],
	"cricket": [
		{title = "OFFICE CRICKET", text = "A Super Over: each side bats six balls (or until two wickets fall), then you swap. Most runs wins.", keys = "", touch = ""},
		{title = "BOWLING", text = "Pick a delivery, aim your line, then stop the sliding meter in the green for an accurate ball.", keys = "1–4 pace / spin / yorker / bouncer  ·  A / D aim  ·  SPACE bowl", touch = "Delivery buttons  ·  drag to aim  ·  BOWL"},
		{title = "BATTING", text = "Choose leg, straight or off side. Swing when the ring closes on you: early or late and you'll miss or edge it.", keys = "A / D direction  ·  SPACE ground shot  ·  SHIFT lofted shot", touch = "LEG / STRAIGHT / OFF  ·  GROUND or LOFT"},
		{title = "SIXES AND WICKETS", text = "A perfect loft goes for SIX; a mistimed one gets caught. Ground shots are safer singles and fours.", keys = "", touch = ""},
	],
	"dash": [
		{title = "DEADLINE DASH", text = "Ten levels to the CEO's penthouse. Reach the lift at the end of each level before the timer runs out. You have 3 lives.", keys = "", touch = ""},
		{title = "RUN AND JUMP", text = "Hold run for speed. Hold jump longer to jump higher.", keys = "A / D move  ·  SHIFT run  ·  SPACE jump", touch = "◀ ▶ buttons  ·  JUMP"},
		{title = "ENEMIES AND BLOCKS", text = "Stomp bots by landing on them. Hit sticky notes from below for coins and power-ups.", keys = "", touch = ""},
		{title = "POWER-UPS", text = "Coffee: survive one extra hit. Energy drink: throw paper planes. Headphones: 10 seconds invincible. 100 coins = 1 life.", keys = "J throw paper planes", touch = "THROW (with the energy drink)"},
		{title = "LIVES", text = "Lose all 3 lives and the run starts over from level 1. Beat all ten for your Deadline Beaten certificate.", keys = "", touch = ""},
	],
	"carrom": [
		{title = "CARROM", text = "Flick the striker to pocket all nine of your coins before the other side. The red queen is a bonus — but you must cover her.", keys = "", touch = ""},
		{title = "PLACE AND AIM", text = "Slide the striker along your base line, then aim. The dotted line shows where it goes.", keys = "A / D slide  ·  mouse or ← → aim", touch = "Drag the striker along your line"},
		{title = "SHOOT", text = "Charge the power, then release.", keys = "hold SPACE or left click, release to shoot", touch = "Pull back anywhere like a slingshot and let go"},
		{title = "RULES", text = "Pocket your own coin to shoot again. Pocket the striker and it's a foul: one of your coins comes back. Cover the queen by pocketing your coin right after her.", keys = "", touch = ""},
	],
	"blast": [
		{title = "OFFICE BLAST", text = "Drop bombs, break the boxes, trap your rivals. The last one standing wins the round; first to 3 rounds wins.", keys = "", touch = ""},
		{title = "MOVE AND BOMB", text = "Bombs explode in a cross after 2.5 seconds. Get out of the line of fire!", keys = "WASD / arrows move  ·  SPACE drop a bomb", touch = "Stick to move  ·  BOMB"},
		{title = "POWER-UPS", text = "Broken boxes drop power-ups: more bombs, bigger blasts, speed, and kick (walk into a bomb to slide it).", keys = "", touch = ""},
		{title = "SUDDEN DEATH", text = "When the clock runs out the walls close in. Don't get squashed!", keys = "", touch = ""},
	],
}

var G
var kind := ""
var steps: Array = []
var i := 0
var layer: CanvasLayer
var panel: Control
var paused_tree := false


## Should a game's tutorial run automatically now? (tutorials ON and not seen yet)
static func should_show(kind: String) -> bool:
	var cf := ConfigFile.new()
	cf.load(SAVE)
	return bool(cf.get_value("tutorial", "enabled", true)) and not bool(cf.get_value("tutorial", "seen_" + kind, false))


static func enabled() -> bool:
	var cf := ConfigFile.new()
	cf.load(SAVE)
	return bool(cf.get_value("tutorial", "enabled", true))


## Turning tutorials ON again forgets which ones you've seen, so every game shows its tutorial once more.
static func set_enabled(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE)
	cf.set_value("tutorial", "enabled", on)
	if on and cf.has_section("tutorial"):
		for k in cf.get_section_keys("tutorial"):
			if String(k).begins_with("seen_"): cf.set_value("tutorial", k, false)
	cf.save(SAVE)


static func mark_seen(kind: String) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE)
	cf.set_value("tutorial", "seen_" + kind, true)
	cf.save(SAVE)


static func steps_for(kind: String, game: Object, variant: String) -> Array:
	if game != null and game.has_method("tutorial_steps"):
		var s: Array = game.tutorial_steps(variant)
		if not s.is_empty(): return s
	return STEPS.get(kind, [])


## Show the tutorial. pause: freeze the game behind it (not in online matches).
func open(g, k: String, s: Array, pause := true) -> void:
	G = g; kind = k; steps = s; i = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = CanvasLayer.new(); layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	if pause and not G.get_tree().paused:
		G.get_tree().paused = true; paused_tree = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_draw_step()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo: return
	match e.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_RIGHT: _next()
		KEY_LEFT: _back()
		KEY_ESCAPE: _close()
	get_viewport().set_input_as_handled()


func _next() -> void:
	if i >= steps.size() - 1: _close(); return
	i += 1; _draw_step()


func _back() -> void:
	if i > 0: i -= 1; _draw_step()


func _close() -> void:
	mark_seen(kind)
	if paused_tree: G.get_tree().paused = false
	paused_tree = false
	# shooters want the mouse back for aiming
	if G.get("ops") != null and not G.ui.touch_enabled: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	queue_free()


func _draw_step() -> void:
	if panel != null: panel.queue_free()
	var ui = G.ui
	var touch: bool = ui.touch_enabled
	var st: Dictionary = steps[i]
	var accent := Color(1.0, 0.81, 0.35)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.45); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	layer.add_child(root)
	panel = root
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.09, 0.96); sb.border_color = accent; sb.set_border_width_all(2); sb.border_width_left = 8
	sb.set_corner_radius_all(14); sb.set_content_margin_all(26); sb.shadow_color = Color(accent, 0.3); sb.shadow_size = 20
	p.add_theme_stylebox_override("panel", sb)
	var w := 720.0 if not touch else 640.0
	p.custom_minimum_size = Vector2(w, 0)
	root.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 12)
	top.add_child(ui.lbl("TUTORIAL", 18, ui.F_TITLE, accent))
	var dots: Label = ui.lbl("  ".join(range(steps.size()).map(func(k): return "●" if k == i else "○")), 18, ui.F_BODY, Color(1, 1, 1, 0.7))
	top.add_child(dots)
	top.add_child(ui.lbl("%d / %d" % [i + 1, steps.size()], 16, ui.F_BODY, Color(1, 1, 1, 0.5)))
	v.add_child(top)
	v.add_child(ui.lbl(String(st.title), 42 if not touch else 34, ui.F_TITLE, Color.WHITE, 8))
	var t: Label = ui.lbl(String(st.text), 22 if not touch else 20, ui.F_MED, Color(0.88, 0.9, 0.96))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD; t.custom_minimum_size = Vector2(w - 60, 0)
	v.add_child(t)
	var ctl := String(st.get("touch" if touch else "keys", ""))
	if ctl != "":
		var chip := PanelContainer.new()
		var cs := StyleBoxFlat.new(); cs.bg_color = Color(accent, 0.14); cs.border_color = Color(accent, 0.7); cs.set_border_width_all(1)
		cs.set_corner_radius_all(10); cs.set_content_margin_all(12)
		chip.add_theme_stylebox_override("panel", cs)
		var cl: Label = ui.lbl(("🎮  " if not OS.has_feature("web") else "") + ctl, 20 if not touch else 18, ui.F_BODY, accent)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD; cl.custom_minimum_size = Vector2(w - 90, 0)
		chip.add_child(cl)
		v.add_child(chip)
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_END; row.add_theme_constant_override("separation", 12)
	var skip: Button = ui.big_btn("SKIP TUTORIAL", Color(0.45, 0.48, 0.58), _close)
	row.add_child(skip)
	if i > 0: row.add_child(ui.big_btn("‹ BACK", Color(0.35, 0.38, 0.5), _back))
	var nxt: Button = ui.big_btn("LET'S PLAY ✔" if i == steps.size() - 1 else "NEXT ›", accent, _next)
	row.add_child(nxt)
	for b in [skip, nxt]: (b as Button).process_mode = Node.PROCESS_MODE_ALWAYS
	v.add_child(row)
	if not touch: v.add_child(ui.lbl("ENTER / → next  ·  ← back  ·  ESC skip", 15, ui.F_BODY, Color(1, 1, 1, 0.45)))
	p.reset_size()
	var vs: Vector2 = G.get_viewport().get_visible_rect().size
	p.position = Vector2((vs.x - p.size.x) / 2.0, vs.y - p.size.y - (60 if not touch else 30))
	nxt.call_deferred("grab_focus")
