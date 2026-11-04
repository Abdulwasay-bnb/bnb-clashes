class_name Net
extends Node
## Two-player connection over one WebSocket, either through the online room relay (server/relay.mjs)
## or directly on the same Wi-Fi (the host's game is the server; it announces itself with a UDP beacon).
## Messages are small JSON dictionaries; see Main._net_message for the game protocol.

signal paired               # an opponent is connected
signal room_created(code: String)
signal failed(msg: String)
signal message(d: Dictionary)
signal peer_left

const VERSION := 1
const GAME := "bnb"         # rooms are per game on a shared relay
const LAN_PORT := 47787
const BEACON_PORT := 47788
const SETTINGS := "user://settings.cfg"
## Online rooms: the Vercel server only hands out room codes and passes the WebRTC handshake;
## the match itself then runs directly between the two players (peer-to-peer).
## A ws:// or wss:// URL instead uses the WebSocket relay in server/ (every message goes through it).
## Override in settings.cfg ([net] relay="...") or with --relay=URL.
const DEFAULT_RELAY := "https://bnb-clashes-relay.vercel.app"
const ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:stun.cloudflare.com:3478"]}]}

var ws: WebSocketPeer
var server: TCPServer          # LAN host only
var beacon: PacketPeerUDP      # LAN host broadcasts, LAN finder listens
var is_host := false
var via := ""                  # "relay" or "lan"
var code := ""
var connected := false         # paired with an opponent
var found := {}                # LAN games: ip -> {name, t}
var _hello := {}               # first message to send once the socket opens
var _was_open := false
var _beacon_t := 0.0
# peer-to-peer (WebRTC) rooms
var pc: WebRTCPeerConnection
var dc: WebRTCDataChannel
var _sig_from := 0
var _sig_t := 0.0
var _sig_busy := false
var _p2p_deadline := 0
var _epoch := 0          # which join attempt the handshake belongs to (a retry starts a new one)
var _blip_since := 0


static func relay_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--relay="): return a.substr(8)
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		return cf.get_value("net", "relay", DEFAULT_RELAY)
	return DEFAULT_RELAY


static func lan_supported() -> bool:
	return not OS.has_feature("web")   # browsers can't open server sockets


# ---------------------------------------------------------------- start / stop
func create_room() -> void:
	close()
	is_host = true
	if relay_url().begins_with("http"):
		via = "p2p"
		if not p2p_supported():
			failed.emit("Online rooms aren't available on this device. Use Wi-Fi play instead."); return
		var r := await _http(HTTPClient.METHOD_POST, "/api/room", {g = GAME})
		if not r.has("code"):
			failed.emit(r.get("error", "Can't reach the online server")); return
		code = r.code
		_start_peer()
		room_created.emit(code)
		return
	via = "relay"
	_open(relay_url(), {t = "create", v = VERSION, g = GAME})


func join_room(c: String) -> void:
	close()
	is_host = false; code = c.strip_edges().to_upper()
	if relay_url().begins_with("http"):
		via = "p2p"
		if not p2p_supported():
			failed.emit("Online rooms aren't available on this device. Use Wi-Fi play instead."); return
		var r := await _http(HTTPClient.METHOD_POST, "/api/join", {g = GAME, code = code})
		if not r.get("ok", false):
			failed.emit(r.get("error", "Can't reach the online server")); return
		_epoch = int(r.get("epoch", 0))
		_start_peer()
		_signal({t = "hello"})   # tells the host to send its offer
		return
	via = "relay"
	_open(relay_url(), {t = "join", code = code, v = VERSION, g = GAME})


# ---------------------------------------------------------------- peer-to-peer rooms (WebRTC)
static func p2p_supported() -> bool:
	if not ClassDB.class_exists("WebRTCPeerConnection"): return false
	var t := WebRTCPeerConnection.new()
	var ok := t.initialize({}) == OK
	t.close()
	return ok


func _start_peer() -> void:
	pc = WebRTCPeerConnection.new()
	pc.initialize(ICE)
	pc.session_description_created.connect(func(type: String, sdp: String):
		pc.set_local_description(type, sdp)
		_signal({t = type, sdp = sdp}))
	pc.ice_candidate_created.connect(func(media: String, index: int, cname: String):
		_signal({t = "ice", media = media, index = index, name = cname}))
	# both sides create the same pre-agreed channel, so no extra negotiation is needed
	dc = pc.create_data_channel("game", {"negotiated": true, "id": 1})
	_sig_from = 0
	_p2p_deadline = Time.get_ticks_msec() + 45000


func _restart_peer() -> void:
	if dc != null: dc.close()
	if pc != null: pc.close()
	_start_peer()


func _signal(msg: Dictionary) -> void:
	_http(HTTPClient.METHOD_POST, "/api/signal", {g = GAME, code = code, to = "guest" if is_host else "host", epoch = _epoch, msg = msg})


func _poll_signals() -> void:
	if _sig_busy: return
	_sig_busy = true
	var r := await _http(HTTPClient.METHOD_GET, "/api/signal?g=%s&code=%s&for=%s&from=%d" % [GAME, code, "host" if is_host else "guest", _sig_from], {})
	_sig_busy = false
	if pc == null or not r.has("msgs"): return
	var e := int(r.get("epoch", _epoch))
	if is_host and e != _epoch and not connected:
		# a (new) guest is trying to join: start a fresh handshake for this attempt
		_epoch = e
		_sig_from = 0
		_restart_peer()
		return
	_sig_from = int(r.get("next", _sig_from))
	for m in r.msgs:
		match String(m.get("t", "")):
			"hello":
				if is_host: pc.create_offer()
			"offer", "answer":
				pc.set_remote_description(m.t, m.sdp)
			"ice":
				pc.add_ice_candidate(m.media, int(m.index), m.name)


## Small JSON request to the room server. Returns the parsed reply ({} or {error} on failure).
func _http(method: int, path: String, body: Dictionary) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 12.0
	add_child(req)
	var headers := PackedStringArray(["content-type: application/json"])
	var err := req.request(relay_url().trim_suffix("/") + path, headers, method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if err != OK:
		req.queue_free(); return {error = "Can't reach the online server"}
	var res: Array = await req.request_completed
	req.queue_free()
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if res[0] != HTTPRequest.RESULT_SUCCESS or not (parsed is Dictionary):
		return {error = "Can't reach the online server"}
	return parsed


func _poll_p2p(dt: float) -> void:
	pc.poll()
	if dc.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		if not connected:
			_set_paired()
			if is_host: _http(HTTPClient.METHOD_POST, "/api/live", {g = GAME, code = code})   # now it's full
		while dc != null and dc.get_available_packet_count() > 0:
			var d = JSON.parse_string(dc.get_packet().get_string_from_utf8())
			if d is Dictionary: _on_message(d)
		return
	if connected:
		# a brief "disconnected" blip can recover by itself; only a closed channel, a failed connection
		# or a blip that lasts several seconds means the rival is really gone
		var st := pc.get_connection_state()
		if st == WebRTCPeerConnection.STATE_DISCONNECTED:
			if _blip_since == 0: _blip_since = Time.get_ticks_msec()
		else:
			_blip_since = 0
		var gone := dc.get_ready_state() == WebRTCDataChannel.STATE_CLOSED or st >= WebRTCPeerConnection.STATE_FAILED \
			or (_blip_since > 0 and Time.get_ticks_msec() - _blip_since > 6000)
		if gone:
			print("NET p2p lost: dc=%d pc=%d" % [dc.get_ready_state(), st])
			connected = false
			peer_left.emit()
		return
	if not connected:
		_sig_t -= dt
		if _sig_t <= 0.0:
			_sig_t = 0.4
			_poll_signals()
		if not is_host and Time.get_ticks_msec() > _p2p_deadline:
			failed.emit("Couldn't connect to your rival directly (some networks block it). Try Wi-Fi play, or another network.")
			close()


func host_lan() -> bool:
	close()
	is_host = true; via = "lan"
	server = TCPServer.new()
	if server.listen(LAN_PORT) != OK:
		server = null
		failed.emit("Can't open port %d on this device" % LAN_PORT)
		return false
	beacon = PacketPeerUDP.new()
	beacon.set_broadcast_enabled(true)
	beacon.set_dest_address("255.255.255.255", BEACON_PORT)
	return true


func find_lan() -> void:
	close()
	found.clear()
	beacon = PacketPeerUDP.new()
	if beacon.bind(BEACON_PORT) != OK:
		failed.emit("Can't listen for games on this network")
		beacon = null


func join_lan(ip: String) -> void:
	close()
	is_host = false; via = "lan"
	_open("ws://%s:%d" % [ip, LAN_PORT], {})


func close() -> void:
	if connected: print("NET close() while connected (via %s)" % via)
	if ws != null:
		ws.close()
	ws = null
	if dc != null: dc.close()
	if pc != null: pc.close()
	dc = null; pc = null
	if server != null: server.stop()
	server = null
	if beacon != null: beacon.close()
	beacon = null
	connected = false; _was_open = false; code = ""; _hello = {}


func send(d: Dictionary) -> void:
	if dc != null and dc.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		dc.put_packet(JSON.stringify(d).to_utf8_buffer())
		return
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))


## This device's addresses on the local network, to show on the host screen.
static func lan_addresses() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and int(a.split(".")[1]) in range(16, 32)):
			out.append(a)
	return out


# ---------------------------------------------------------------- polling
func _open(url: String, hello: Dictionary) -> void:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	_hello = hello
	if ws.connect_to_url(url) != OK:
		ws = null
		failed.emit("Can't reach " + url)


func _process(dt: float) -> void:
	poll(dt)


## Called every render frame and again right before each fight tick, so inputs arrive as early as possible.
func poll(dt := 0.0) -> void:
	if pc != null:
		_poll_p2p(dt)
		return
	if server != null and ws == null and server.is_connection_available():
		ws = WebSocketPeer.new()
		ws.accept_stream(server.take_connection())
	if beacon != null:
		_beacon(dt)
	if ws == null: return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			if not _hello.is_empty(): send(_hello)
			if via == "lan":
				_set_paired()
		while ws != null and ws.get_available_packet_count() > 0:
			var txt := ws.get_packet().get_string_from_utf8()
			var d = JSON.parse_string(txt)
			if d is Dictionary: _on_message(d)
	elif st == WebSocketPeer.STATE_CLOSED:
		var was := connected
		var why := ws.get_close_reason()
		ws = null
		connected = false
		if was: peer_left.emit()
		elif via == "relay": failed.emit("Can't reach the online server" + (": " + why if why != "" else ""))
		elif not is_host: failed.emit("Can't connect to that game")


func _on_message(d: Dictionary) -> void:
	match d.get("t", ""):
		"room":
			code = d.code
			room_created.emit(code)
		"paired":
			_set_paired()
		"error":
			failed.emit(d.get("msg", "Error"))
			close()
		"peer_left":
			connected = false
			peer_left.emit()
		_:
			message.emit(d)


func _set_paired() -> void:
	if connected: return
	connected = true
	if server != null:
		server.stop(); server = null   # one opponent per game
	if beacon != null:
		beacon.close(); beacon = null
	paired.emit()


func _beacon(dt: float) -> void:
	if server != null:
		_beacon_t -= dt
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			beacon.put_packet(("BNBCLASHES|%d|%s" % [VERSION, OS.get_model_name()]).to_utf8_buffer())
		return
	while beacon.get_available_packet_count() > 0:
		var pkt := beacon.get_packet().get_string_from_utf8()
		var ip := beacon.get_packet_ip()
		var parts := pkt.split("|")
		if parts.size() >= 3 and parts[0] == "BNBCLASHES" and int(parts[1]) == VERSION:
			found[ip] = {name = parts[2], t = Time.get_ticks_msec()}
	for ip in found.keys():
		if Time.get_ticks_msec() - found[ip].t > 4000: found.erase(ip)
