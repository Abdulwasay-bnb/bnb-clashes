class_name PartyLobby
extends Node
## Online / Wi-Fi lobby for Rush Hour (up to 10 racers) and Office Ops (up to 4 v 4).
## The host sees who joined, picks the track (or team sizes and bot skill) and starts; CPU players fill the empty seats.
## Protocol (JSON): guest "hi" {c, gun} -> host "lobby" {players, cfg} -> host "start" {...} -> in-game messages
## (RaceGame / OpsGame) -> results -> everyone back in the lobby.

var G
var party: Party
var mode := ""                 # race / ops
var C: Dictionary              # this player's character
var gun := "rifle"
var players: Array = []        # [{pid, c, gun}] — pid 0 is the host
var cfg := {track = "city", mine = 4, them = 4, skill = 1.0, fill = true, total = 8, mafia = 2, cool = 30.0, reveal = true}
var status: Label
var list_box: VBoxContainer
var found_box: VBoxContainer
var found_shown: Array = []
var in_game := false
var view := ""                 # menu / join / find / lobby


func _init(g) -> void:
	G = g


func _ready() -> void:
	party = Party.new()
	add_child(party)
	party.joined.connect(func(_pid): G.sfx("ok"))
	party.left.connect(_on_left)
	party.connected_to_host.connect(func(): party.send({t = "hi", c = C.id, gun = gun}))
	party.host_left.connect(func(): _gone("The host left the game."))
	party.failed.connect(func(msg): if not in_game: show_menu(mode, C, msg))
	party.room_created.connect(func(_code): _render_lobby())
	party.message.connect(_on_message)


func max_players() -> int:
	return {"race": 10, "ops": 8, "ludo": 4, "mafia": 10}.get(mode, 8)


func title() -> String:
	return {"race": "RUSH HOUR", "ops": "OFFICE OPS", "ludo": "LUDO", "mafia": "MAFIA"}.get(mode, "")


# ---------------------------------------------------------------- menu
func show_menu(m: String, who: Dictionary, msg := "") -> void:
	var ui = G.ui
	party.close()
	in_game = false
	mode = m; C = who; view = "menu"
	gun = String(ui.ops_cfg.gun)
	ui.clear_screen(); ui.screen.visible = true; ui.view = "party"
	G.set_preview(0, C)
	ui.screen.add_child(ui.full(ui.hgrad(Color(0.03, 0.01, 0.06, 0.95), Color(0.03, 0.01, 0.06, 0.2))))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	ui.screen.add_child(col)
	col.position = Vector2(90, 90) if not ui.touch_enabled else Vector2(70, 100)
	col.add_child(ui.lbl(title(), 64, ui.F_TITLE, {"race": Color(0.13, 0.78, 0.92), "ludo": Color(1.0, 0.81, 0.35), "mafia": Color(0.95, 0.3, 0.35)}.get(mode, Color(0.66, 0.4, 1.0)), 10))
	col.add_child(ui.lbl("%s  ·  PLAY WITH FRIENDS  ·  UP TO %d PLAYERS" % [C.name, max_players()], 20, ui.F_BODY, Color(1.0, 0.81, 0.35)))
	var back := _back_cb()
	var items := []
	if mode == "mafia":
		items.append(["PLAY WITH BOTS", _mafia_solo_setup, 26, "You and office bots. Find the Mafia — or be them."])
	items.append_array([
		["CREATE ROOM", _create, 26, "Get a room code to send to your friends. Works over the internet."],
		["JOIN WITH CODE", _show_join, 26, "Type the code a friend sent you."]])
	if Net.lan_supported():
		items.append(["HOST ON THIS WI-FI", _host_lan, 26, "Friends on the same Wi-Fi join you. No internet needed."])
		items.append(["FIND WI-FI GAMES", _find_lan, 26, "Look for a game hosted on this Wi-Fi network."])
	items.append(["BACK", back, 20, "Back."])
	var mlist: VBoxContainer = ui._menu_list(items)
	mlist.set_meta("back", back)
	col.add_child(mlist)
	ui.desc_lbl = ui.lbl("Empty seats are filled by CPU players.", 20, ui.F_MED, Color(0.79, 0.83, 0.88))
	ui.desc_lbl.custom_minimum_size = Vector2(520, 50)
	ui.desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(ui.desc_lbl)
	if msg != "":
		var e: Label = ui.lbl(msg, 22, ui.F_BODY, Color(1.0, 0.45, 0.5))
		e.autowrap_mode = TextServer.AUTOWRAP_WORD
		e.custom_minimum_size = Vector2(520, 0)
		col.add_child(e)
	ui._focus_first(mlist)


func _back_cb() -> Callable:
	var who := C
	if mode == "race": return func(): party.close(); G.ui.show_race_tracks(who)
	if mode == "ludo": return func(): party.close(); G.ui.show_ludo_menu(who)
	if mode == "mafia": return func(): party.close(); G.ui.show_title()
	return func(): party.close(); G.ui.show_ops_setup(who)


## A centred panel: title, status line; returns the column to add to.
func _panel(title: String, msg: String) -> VBoxContainer:
	var ui = G.ui
	ui.clear_screen(); ui.screen.visible = true; ui.view = "party"
	var dim: ColorRect = ui.full(ColorRect.new()); dim.color = Color(0.01, 0.02, 0.04, 0.8)
	ui.screen.add_child(dim)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	ui.screen.add_child(ui.full(v))
	var t: Label = ui.lbl(title, 44, ui.F_TITLE, Color(0.93, 0.95, 0.98), 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	status = ui.lbl(msg, 22, ui.F_BODY, Color(0.79, 0.83, 0.88))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(status)
	v.set_meta("back", func(): show_menu(mode, C))
	return v


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 14)
	return r


# ---------------------------------------------------------------- host / join
func _create() -> void:
	players = [{pid = 0, c = C.id, gun = gun}]
	view = "lobby"
	_panel("CREATE ROOM", "Connecting to the online server…")
	party.max_guests = max_players() - 1
	party.create_room(mode)


func _host_lan() -> void:
	players = [{pid = 0, c = C.id, gun = gun}]
	party.max_guests = max_players() - 1
	party.host_name = String(C.person.get("short", C.name)) if C.has("person") else String(C.name)
	if not party.host_lan(mode): return
	view = "lobby"
	_render_lobby()


func _show_join() -> void:
	var ui = G.ui
	view = "join"
	var v := _panel("JOIN ROOM", "Enter the 5-letter code.")
	var le := LineEdit.new()
	le.max_length = 5
	le.placeholder_text = "CODE"
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.custom_minimum_size = Vector2(380, 110)
	le.add_theme_font_override("font", ui.F_TITLE)
	le.add_theme_font_size_override("font_size", 72)
	le.add_theme_stylebox_override("normal", ui.sbox(Color(0.04, 0.06, 0.11, 0.95), Color(1.0, 0.81, 0.35), 2, 0.0))
	le.add_theme_stylebox_override("focus", ui.sbox(Color(0.06, 0.09, 0.16, 0.95), Color(1.0, 0.81, 0.35), 3, 0.0))
	le.text_changed.connect(func(t):
		var up: String = t.to_upper()
		if up != t: le.text = up; le.caret_column = up.length())
	var go := func():
		if le.text.strip_edges().length() < 4:
			status.text = "That code looks too short."; return
		join_code(le.text)
	le.text_submitted.connect(func(_t): go.call())
	v.add_child(ui._centered(le))
	var r := _row()
	r.add_child(ui.big_btn("JOIN", Color(1.0, 0.81, 0.35), go))
	r.add_child(ui.big_btn("CANCEL", Color(0.55, 0.62, 0.75), func(): show_menu(mode, C)))
	v.add_child(r)
	le.call_deferred("grab_focus")


func join_code(code: String) -> void:
	view = "lobby"
	players = []
	_panel("JOINING " + code.strip_edges().to_upper(), "Connecting to the host…")
	party.join_room(mode, code)


func join_ip(ip: String) -> void:
	view = "lobby"
	players = []
	_panel("JOINING", "Connecting to %s…" % ip)
	party.join_lan(mode, ip)


func _find_lan() -> void:
	var ui = G.ui
	party.find_lan(mode)
	view = "find"
	var v := _panel("WI-FI GAMES", "Looking for %s games on this network…" % title().capitalize())
	found_box = VBoxContainer.new()
	found_box.add_theme_constant_override("separation", 10)
	v.add_child(ui._centered(found_box))
	found_shown = []
	var r := _row()
	var ip_in := LineEdit.new()
	ip_in.placeholder_text = "or type an address"
	ip_in.custom_minimum_size = Vector2(360, 70)
	ip_in.add_theme_font_override("font", ui.F_BODY)
	ip_in.add_theme_font_size_override("font_size", 30)
	ip_in.text_submitted.connect(func(t): if t.strip_edges() != "": join_ip(t.strip_edges()))
	r.add_child(ip_in)
	r.add_child(ui.big_btn("CONNECT", Color(1.0, 0.81, 0.35), func(): if ip_in.text.strip_edges() != "": join_ip(ip_in.text.strip_edges())))
	r.add_child(ui.big_btn("CANCEL", Color(0.55, 0.62, 0.75), func(): show_menu(mode, C)))
	v.add_child(r)


func _process(_dt: float) -> void:
	if view != "find" or found_box == null or not is_instance_valid(found_box): return
	var ips: Array = party.found.keys()
	ips.sort()
	var sig := []
	for ip in ips: sig.append("%s:%d" % [ip, party.found[ip].n])
	if sig == found_shown: return
	found_shown = sig
	for c in found_box.get_children(): c.queue_free()
	for ip in ips:
		var f: Dictionary = party.found[ip]
		var addr: String = ip
		found_box.add_child(G.ui.big_btn("%s'S GAME   ·   %d / %d   (%s)" % [String(f.name).to_upper(), f.n, max_players(), ip], Color(0.24, 0.84, 1.0), func(): join_ip(addr)))
	status.text = "Tap a game to join." if not ips.is_empty() else "Looking for games on this network…"


# ---------------------------------------------------------------- lobby
func _render_lobby() -> void:
	if in_game: return
	var ui = G.ui
	view = "lobby"
	var host := party.is_host
	var title := "LOBBY"
	var how := ""
	if host and party.via == "p2p": title = "ROOM  " + party.code; how = "Friends: %s → PLAY WITH FRIENDS → JOIN WITH CODE" % title()
	elif host:
		# home / office Wi-Fi addresses first; 172.x are usually virtual (Docker, VMs) and only shown if nothing else
		var ips := Net.lan_addresses().filter(func(a): return not String(a).begins_with("172."))
		if ips.is_empty(): ips = Net.lan_addresses().slice(0, 2)
		title = "HOSTING ON WI-FI"
		how = "Friends on this Wi-Fi: FIND WI-FI GAMES" + ("   ·   or connect to " + "  /  ".join(ips) if not ips.is_empty() else "")
	else:
		how = "Waiting for the host to start…" if party.ok else "Connecting…"
	var v := _panel(title, how)
	v.set_meta("back", leave)
	# players
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 4)
	var n := players.size()
	list_box.add_child(ui.lbl("PLAYERS  %d / %d   ·   %d CPU" % [n, max_players(), maxi(0, _seats() - n)], 22, ui.F_TITLE, Color(1.0, 0.81, 0.35)))
	for k in players.size():
		var p: Dictionary = players[k]
		var pc: Dictionary = Data.by_id(String(p.c))
		var tag := "  (HOST)" if int(p.pid) == 0 else ""
		var team := ""
		if mode == "ops": team = "   ·   " + OpsGame.TEAM_NAME[k % 2] + "   ·   " + String(OpsSim.GUNS[String(p.gun)].name)
		list_box.add_child(ui.lbl("%s%s%s" % [pc.name, tag, team], 22, ui.F_BODY, (pc.accent as Color).lightened(0.35)))
	v.add_child(ui._centered(list_box))
	# settings
	if mode == "race":
		if host:
			var r := _row()
			for id in RaceSim.TRACKS:
				var tid: String = id
				var b: Button = ui.big_btn(String(RaceSim.TRACKS[id].name).to_upper(), Color(0.13, 0.78, 0.92) if cfg.track == tid else Color(0.35, 0.38, 0.5), func(): cfg.track = tid; _changed())
				b.add_theme_font_size_override("font_size", 20)
				r.add_child(b)
			v.add_child(r)
		else:
			v.add_child(_centered_lbl("TRACK:  " + String(RaceSim.TRACKS.get(cfg.track, RaceSim.TRACKS.city).name).to_upper()))
	elif mode == "mafia":
		if host:
			v.add_child(_opt_row("PLAYERS", [5, 6, 8, 10], "total", ["5", "6", "8", "10"]))
			v.add_child(_opt_row("MAFIA", [1, 2, 3], "mafia", ["1", "2", "3"]))
			v.add_child(_opt_row("KNIFE COOLDOWN", [20.0, 30.0, 45.0], "cool", ["20s", "30s", "45s"]))
			v.add_child(_opt_row("REVEAL FIRED", [true, false], "reveal", ["YES", "NO"]))
		else:
			v.add_child(_centered_lbl("%d PLAYERS  ·  %d MAFIA  ·  KNIFE %ds" % [maxi(int(cfg.total), players.size()), int(cfg.mafia), int(cfg.cool)]))
	elif mode == "ludo":
		if host: v.add_child(_opt_row("EMPTY SEATS", [true, false], "fill", ["CPU PLAYERS", "LEAVE EMPTY"]))
		else: v.add_child(_centered_lbl("EMPTY SEATS:  " + ("CPU PLAYERS" if cfg.fill else "LEFT EMPTY")))
	elif mode == "ops":
		if host:
			v.add_child(_opt_row("TEAM SIZE", [1, 2, 3, 4], "mine", ["1", "2", "3", "4"]))
			v.add_child(_opt_row("ENEMY SIZE", [1, 2, 3, 4], "them", ["1", "2", "3", "4"]))
			v.add_child(_opt_row("BOTS", [0.7, 1.0, 1.4], "skill", ["EASY", "NORMAL", "HARD"]))
		else:
			var a_b := _team_sizes()
			v.add_child(_centered_lbl("%d v %d   ·   BOTS %s" % [a_b[0], a_b[1], {0.7: "EASY", 1.0: "NORMAL", 1.4: "HARD"}.get(float(cfg.skill), "NORMAL")]))
	var r2 := _row()
	if host:
		var start: Button = ui.big_btn("START  ✔", Color(1.0, 0.81, 0.35), start_match)
		r2.add_child(start)
		if party.via == "p2p":
			var code := party.code
			r2.add_child(ui.big_btn("COPY CODE", Color(0.24, 0.84, 1.0), func(): DisplayServer.clipboard_set(code); status.text = "Code copied."))
		start.call_deferred("grab_focus")
	r2.add_child(ui.big_btn("LEAVE", Color(0.55, 0.62, 0.75), leave))
	v.add_child(r2)


func _centered_lbl(t: String) -> Control:
	var l: Label = G.ui.lbl(t, 22, G.ui.F_TITLE, Color(0.93, 0.95, 0.98))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _opt_row(title: String, opts: Array, key: String, names: Array) -> HBoxContainer:
	var ui = G.ui
	var h := _row()
	var t: Label = ui.lbl(title, 20, ui.F_TITLE, Color(0.93, 0.95, 0.98))
	t.custom_minimum_size = Vector2(160, 0)
	h.add_child(t)
	for k in opts.size():
		var val = opts[k]
		var b: Button = ui.big_btn(String(names[k]), Color(0.13, 0.78, 0.92) if cfg[key] == val else Color(0.35, 0.38, 0.5), func(): cfg[key] = val; _changed())
		b.custom_minimum_size = Vector2(96 if String(names[k]).length() < 4 else 140, 52)
		b.add_theme_font_size_override("font_size", 20)
		h.add_child(b)
	return h


func _seats() -> int:
	if mode == "race": return 10
	if mode == "mafia": return maxi(int(cfg.total), players.size())
	if mode == "ludo": return 4 if cfg.fill else maxi(2, players.size())
	var ab := _team_sizes()
	return ab[0] + ab[1]


## Office Ops teams: humans alternate between the two teams; bots fill up to the chosen sizes.
func _team_sizes() -> Array:
	var n := players.size()
	return [maxi(int(cfg.mine), (n + 1) / 2), maxi(int(cfg.them), n / 2)]


func _changed() -> void:
	if view == "solo":
		_mafia_solo_setup(); return
	_broadcast_lobby()
	_render_lobby()


func _broadcast_lobby() -> void:
	if party.is_host: party.broadcast({t = "lobby", players = players, cfg = cfg, mode = mode})


func _on_left(pid: int) -> void:
	players = players.filter(func(p): return int(p.pid) != pid)
	if not in_game:
		_broadcast_lobby(); _render_lobby()


func _gone(msg: String) -> void:
	if in_game:
		in_game = false
		G.end_race(); G.end_ops(); G.end_ludo(); G.end_mafia()
	show_menu(mode, C, msg)


func leave() -> void:
	in_game = false
	party.close()
	G.ui.show_title()


## After the results: back to the room (the host opens it for joins again).
func back_to_lobby() -> void:
	in_game = false
	if not party.active:
		show_menu(mode, C, "The connection was lost."); return
	if party.is_host:
		party.lock_room(false)
		_broadcast_lobby()
	_render_lobby()


# ---------------------------------------------------------------- messages
func _on_message(pid: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"hi":
			if not party.is_host: return
			var c := String(d.get("c", "abdul_wasay"))
			if Data.by_id(c).is_empty(): c = "abdul_wasay"
			var g := String(d.get("gun", "rifle"))
			if not OpsSim.GUNS.has(g) or g == "pistol": g = "rifle"
			players = players.filter(func(p): return int(p.pid) != pid)
			players.append({pid = pid, c = c, gun = g})
			if in_game:
				party.send_to(pid, {t = "busy"})   # they wait in the lobby until this match ends
			_broadcast_lobby()
			if not in_game: _render_lobby()
		"busy":
			if status != null and is_instance_valid(status): status.text = "A match is on. You'll join the next one."
		"lobby":
			if party.is_host: return
			players = d.players
			cfg = d.cfg
			if not in_game: _render_lobby()
		"start":
			if not party.is_host: _start_guest(d)


# ---------------------------------------------------------------- starting a match
func start_match() -> void:
	if not party.is_host: return
	var seed := randi()
	var chosen := {}
	for p in players: chosen[String(p.c)] = true
	var pool := Data.ROSTER.filter(func(c): return not chosen.has(String(c.id)))
	pool.shuffle()
	party.lock_room(true)
	in_game = true
	if mode == "mafia":
		var ids := []
		for p in players: ids.append(String(p.c))
		for c in pool:
			if ids.size() >= _seats(): break
			ids.append(String(c.id))
		var mc := _mafia_cfg()
		var pids := {}
		for k in players.size():
			var pid := int(players[k].pid)
			if pid != 0:
				pids[pid] = k
				party.send_to(pid, {t = "start", mode = "mafia", people = ids, humans = players.size(), cfg = mc, seed = seed, me = k})
		G.start_mafia(_ludo_people(ids, players.size()), mc, seed, 0, party, false, pids)
		return
	if mode == "ludo":
		var ids := []
		for p in players: ids.append(String(p.c))
		var n := 4 if cfg.fill else maxi(2, players.size())
		for c in pool:
			if ids.size() >= n: break
			ids.append(String(c.id))
		var pids := {}
		for k in players.size():
			var pid := int(players[k].pid)
			if pid != 0:
				pids[pid] = k
				party.send_to(pid, {t = "start", mode = "ludo", people = ids, humans = players.size(), seed = seed, me = k})
		G.start_ludo_net(_ludo_people(ids, players.size()), seed, 0, party, false, pids)
		return
	if mode == "race":
		var ids := []
		for p in players: ids.append(String(p.c))
		for c in pool:
			if ids.size() >= 10: break
			ids.append(String(c.id))
		var pids := {}
		for k in players.size():
			var pid := int(players[k].pid)
			if pid != 0:
				pids[pid] = k
				party.send_to(pid, {t = "start", mode = "race", track = cfg.track, people = ids, humans = players.size(), seed = seed, me = k})
		G.start_race_net(String(cfg.track), _people(ids), players.size(), seed, 0, party, false, pids)
	else:
		var ab := _team_sizes()
		var a := []
		var b := []
		var hum_a := []
		var hum_b := []
		for k in players.size(): (hum_a if k % 2 == 0 else hum_b).append(k)
		for k in hum_a: a.append(String(players[k].c))
		for k in hum_b: b.append(String(players[k].c))
		var pi := 0
		while a.size() < ab[0] and pi < pool.size(): a.append(String(pool[pi].id)); pi += 1
		while b.size() < ab[1] and pi < pool.size(): b.append(String(pool[pi].id)); pi += 1
		# soldier ids: team A first, then team B
		var humans := {}
		var guns := {}
		var slot_of := {}   # player index -> soldier id
		for j in hum_a.size(): slot_of[hum_a[j]] = j
		for j in hum_b.size(): slot_of[hum_b[j]] = a.size() + j
		for k in players.size():
			humans[str(slot_of[k])] = k; guns[str(slot_of[k])] = String(players[k].gun)
		var pids := {}
		for k in players.size():
			var pid := int(players[k].pid)
			if pid != 0:
				pids[pid] = int(slot_of[k])
				party.send_to(pid, {t = "start", mode = "ops", a = a, b = b, humans = humans, guns = guns, skill = cfg.skill, seed = seed, me = slot_of[k]})
		G.start_ops_net(_people(a), _people(b), _int_keys(humans), _int_keys(guns), float(cfg.skill), seed, int(slot_of[0]), party, false, pids)


func _start_guest(d: Dictionary) -> void:
	if in_game:
		G.end_race(); G.end_ops(); G.end_ludo(); G.end_mafia()
	in_game = true
	if String(d.mode) == "mafia":
		G.start_mafia(_ludo_people(d.people, int(d.humans)), d.cfg, int(d.seed), int(d.me), party, true, {})
	elif String(d.mode) == "ludo":
		G.start_ludo_net(_ludo_people(d.people, int(d.humans)), int(d.seed), int(d.me), party, true, {})
	elif String(d.mode) == "race":
		G.start_race_net(String(d.track), _people(d.people), int(d.humans), int(d.seed), int(d.me), party, true, {})
	else:
		G.start_ops_net(_people(d.a), _people(d.b), _int_keys(d.humans), _int_keys(d.guns), float(d.skill), int(d.seed), int(d.me), party, true, {})


func _mafia_cfg() -> Dictionary:
	return {mafia = int(cfg.mafia), cool = float(cfg.cool), reveal = bool(cfg.reveal), talk = 20.0, vote = 40.0, tasks = 5}


## Solo: you plus office bots.
func _mafia_solo_setup() -> void:
	var ui = G.ui
	var v := _panel("MAFIA  ·  WITH BOTS", "You and office bots. Roles are dealt at random.")
	view = "solo"
	v.set_meta("back", func(): show_menu(mode, C))
	v.add_child(_opt_row("PLAYERS", [5, 6, 8, 10], "total", ["5", "6", "8", "10"]))
	v.add_child(_opt_row("MAFIA", [1, 2, 3], "mafia", ["1", "2", "3"]))
	v.add_child(_opt_row("KNIFE COOLDOWN", [20.0, 30.0, 45.0], "cool", ["20s", "30s", "45s"]))
	var r := _row()
	r.add_child(ui.big_btn("START  ✔", Color(1.0, 0.81, 0.35), func(): start_mafia_solo()))
	r.add_child(ui.big_btn("BACK", Color(0.55, 0.62, 0.75), func(): show_menu(mode, C)))
	v.add_child(r)


func start_mafia_solo(force_mafia := -1) -> void:
	var pool := Data.ROSTER.filter(func(c): return c.id != C.id)
	pool.shuffle()
	var ids := [String(C.id)]
	for c in pool:
		if ids.size() >= int(cfg.total): break
		ids.append(String(c.id))
	var mc := _mafia_cfg()
	if force_mafia >= 0: mc.force = force_mafia
	G.start_mafia(_ludo_people(ids, 1), mc, randi(), 0)


func _ludo_people(ids: Array, humans: int) -> Array:
	var out := []
	var cs := _people(ids)
	for k in cs.size(): out.append({C = cs[k], human = k < humans, slot = k if k < humans else -1})
	return out


func _people(ids: Array) -> Array:
	var out := []
	for id in ids:
		var c: Dictionary = Data.by_id(String(id))
		out.append(c if not c.is_empty() else Data.ROSTER[0])
	return out


static func _int_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d: out[int(k)] = int(d[k]) if (d[k] is float or d[k] is int) else d[k]
	return out
