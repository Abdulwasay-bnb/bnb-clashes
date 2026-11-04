class_name Party
extends Node
## Many-player connection for Rush Hour and Office Ops: one host, up to 9 guests, star-shaped.
## Wi-Fi: the host's game is a WebSocket server (several guests) and announces itself with a UDP beacon.
## Online: the Vercel room server only passes WebRTC handshakes; every guest gets its own direct link to the host
## (one handshake mailbox per join attempt, the "epoch"). Messages are small JSON dictionaries.
## The fighting game keeps using Net (1 v 1); rooms for each mode are separate on the server.

signal joined(pid: int)              # host: a guest connected
signal left(pid: int)                # host: a guest dropped
signal connected_to_host             # guest: link to the host is up
signal host_left                     # guest: the host is gone
signal failed(msg: String)
signal room_created(code: String)
signal message(pid: int, d: Dictionary)   # pid 0 = the host (on guests)

const VERSION := 1
const LAN_PORT := 47789
const BEACON_PORT := 47790

var mode := ""                 # "race" / "ops"
var is_host := false
var via := ""                  # "lan" / "p2p"
var code := ""
var active := false
var ok := false                # guest: linked to the host
var found := {}                # LAN finder: ip -> {name, n, t}
var max_guests := 9
var host_name := ""

# LAN
var server: TCPServer
var beacon: PacketPeerUDP
var _beacon_t := 0.0
var socks := {}                # host: pid -> WebSocketPeer;  guest: 0 -> WebSocketPeer
var _sock_open := {}
# online (WebRTC)
var links := {}                # host: epoch -> {pc, dc, from, deadline, pid, up, blip}; guest: 0 -> same
var _sig_t := 0.0
var _sig_busy := false
var _known_epoch := 0
var _epoch := 0                # guest: our join attempt
var _next_pid := 1
var locked := false
var _keep_t := 240.0


func game_key() -> String:
	return "bnb-" + mode     # "bnb-race" / "bnb-ops"


func peers() -> Array:
	var out := []
	if via == "lan":
		for pid in socks: if _sock_open.get(pid, false): out.append(pid)
	else:
		for e in links: if links[e].up and int(links[e].pid) > 0: out.append(int(links[e].pid))
	return out


# ---------------------------------------------------------------- start / stop
func host_lan(m: String) -> bool:
	close()
	mode = m; is_host = true; via = "lan"; active = true
	server = TCPServer.new()
	if server.listen(LAN_PORT) != OK:
		server = null; active = false
		failed.emit("Can't open port %d on this device" % LAN_PORT)
		return false
	beacon = PacketPeerUDP.new()
	beacon.set_broadcast_enabled(true)
	beacon.set_dest_address("255.255.255.255", BEACON_PORT)
	return true


func find_lan(m: String) -> void:
	close()
	mode = m
	found.clear()
	beacon = PacketPeerUDP.new()
	if beacon.bind(BEACON_PORT) != OK:
		failed.emit("Can't listen for games on this network")
		beacon = null


func join_lan(m: String, ip: String) -> void:
	close()
	mode = m; is_host = false; via = "lan"; active = true
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20; ws.outbound_buffer_size = 1 << 20
	if ws.connect_to_url("ws://%s:%d" % [ip, LAN_PORT]) != OK:
		failed.emit("Can't connect to that game"); active = false; return
	socks[0] = ws


func create_room(m: String) -> void:
	close()
	mode = m; is_host = true; via = "p2p"; active = true
	if not Net.p2p_supported():
		failed.emit("Online rooms aren't available on this device. Use Wi-Fi play instead."); return
	var r := await _http(HTTPClient.METHOD_POST, "/api/room", {g = game_key()})
	if not r.has("code"):
		failed.emit(r.get("error", "Can't reach the online server")); active = false; return
	code = r.code
	_known_epoch = 0
	room_created.emit(code)


func join_room(m: String, c: String) -> void:
	close()
	mode = m; is_host = false; via = "p2p"; active = true
	code = c.strip_edges().to_upper()
	if not Net.p2p_supported():
		failed.emit("Online rooms aren't available on this device. Use Wi-Fi play instead."); return
	var r := await _http(HTTPClient.METHOD_POST, "/api/join", {g = game_key(), code = code})
	if not r.get("ok", false):
		failed.emit(r.get("error", "Can't reach the online server")); active = false; return
	_epoch = int(r.get("epoch", 0))
	links[0] = _new_link(_epoch, 0)
	_signal(_epoch, {t = "hello"})


## The host locks the room once the match starts (no joining mid-race).
func lock_room(on: bool) -> void:
	locked = on
	if via == "p2p" and is_host and code != "":
		_http(HTTPClient.METHOD_POST, "/api/live", {g = game_key(), code = code, on = on})
	if via == "lan" and is_host:
		if locked and beacon != null: beacon.close(); beacon = null
		elif not on and beacon == null and server != null:
			beacon = PacketPeerUDP.new(); beacon.set_broadcast_enabled(true); beacon.set_dest_address("255.255.255.255", BEACON_PORT)


func close() -> void:
	for pid in socks: (socks[pid] as WebSocketPeer).close()
	socks.clear(); _sock_open.clear()
	for e in links:
		var l: Dictionary = links[e]
		if l.dc != null: (l.dc as WebRTCDataChannel).close()
		if l.pc != null: (l.pc as WebRTCPeerConnection).close()
	links.clear()
	if server != null: server.stop()
	server = null
	if beacon != null: beacon.close()
	beacon = null
	active = false; ok = false; code = ""; _next_pid = 1; _known_epoch = 0; _epoch = 0; locked = false; _keep_t = 240.0


func kick(pid: int) -> void:
	if via == "lan" and socks.has(pid):
		(socks[pid] as WebSocketPeer).close(); socks.erase(pid); _sock_open.erase(pid)
	for e in links.keys():
		if int(links[e].pid) == pid:
			var l: Dictionary = links[e]
			(l.dc as WebRTCDataChannel).close(); (l.pc as WebRTCPeerConnection).close()
			links.erase(e)


# ---------------------------------------------------------------- sending
func _put(pid: int, txt: String) -> void:
	if via == "lan":
		if socks.has(pid) and (socks[pid] as WebSocketPeer).get_ready_state() == WebSocketPeer.STATE_OPEN:
			(socks[pid] as WebSocketPeer).send_text(txt)
		return
	for e in links:
		var l: Dictionary = links[e]
		if int(l.pid) == pid and l.up and (l.dc as WebRTCDataChannel).get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			(l.dc as WebRTCDataChannel).put_packet(txt.to_utf8_buffer())


## Guest -> host.
func send(d: Dictionary) -> void:
	_put(0, JSON.stringify(d))


func send_to(pid: int, d: Dictionary) -> void:
	_put(pid, JSON.stringify(d))


## Host -> every guest.
func broadcast(d: Dictionary) -> void:
	var txt := JSON.stringify(d)
	for pid in peers(): _put(pid, txt)


# ---------------------------------------------------------------- polling
func _process(dt: float) -> void:
	poll(dt)


func poll(dt := 0.0) -> void:
	if beacon != null: _beacon(dt)
	if via == "lan": _poll_lan()
	elif via == "p2p" and active: _poll_p2p(dt)


func _poll_lan() -> void:
	if server != null:
		while server.is_connection_available():
			var ws := WebSocketPeer.new()
			ws.inbound_buffer_size = 1 << 20; ws.outbound_buffer_size = 1 << 20
			ws.accept_stream(server.take_connection())
			socks[_next_pid] = ws; _next_pid += 1
	for pid in socks.keys():
		var ws: WebSocketPeer = socks[pid]
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			if not _sock_open.get(pid, false):
				_sock_open[pid] = true
				if is_host:
					if peers().size() > max_guests:
						ws.send_text(JSON.stringify({t = "full"})); ws.close(); socks.erase(pid); _sock_open.erase(pid); continue
					joined.emit(pid)
				else:
					ok = true; connected_to_host.emit()
			while ws.get_available_packet_count() > 0:
				var d = JSON.parse_string(ws.get_packet().get_string_from_utf8())
				if d is Dictionary: _got(pid, d)
		elif st == WebSocketPeer.STATE_CLOSED:
			var was: bool = _sock_open.get(pid, false)
			socks.erase(pid); _sock_open.erase(pid)
			if is_host:
				if was: left.emit(pid)
			else:
				ok = false; active = false
				if was: host_left.emit()
				else: failed.emit("Can't connect to that game")


func _got(pid: int, d: Dictionary) -> void:
	if not is_host and d.get("t", "") == "full":
		failed.emit("That game is full."); close(); return
	message.emit(pid, d)


# ---------------------------------------------------------------- online (WebRTC, one link per guest)
func _new_link(epoch: int, pid: int) -> Dictionary:
	var pc := WebRTCPeerConnection.new()
	pc.initialize(Net.ICE)
	var l := {pc = pc, dc = null, from = 0, deadline = Time.get_ticks_msec() + 45000, pid = pid, up = false, blip = 0, epoch = epoch, offered = false, has_remote = false, ice = []}
	pc.session_description_created.connect(func(type: String, sdp: String):
		pc.set_local_description(type, sdp)
		_signal(epoch, {t = type, sdp = sdp}))
	pc.ice_candidate_created.connect(func(media: String, index: int, cname: String):
		_signal(epoch, {t = "ice", media = media, index = index, name = cname}))
	l.dc = pc.create_data_channel("game", {"negotiated": true, "id": 1})
	return l


func _signal(epoch: int, msg: Dictionary) -> void:
	_http(HTTPClient.METHOD_POST, "/api/signal", {g = game_key(), code = code, to = "guest" if is_host else "host", epoch = epoch, msg = msg})


func _poll_p2p(dt: float) -> void:
	var now := Time.get_ticks_msec()
	for e in links.keys():
		var l: Dictionary = links[e]
		var pc: WebRTCPeerConnection = l.pc
		var dc: WebRTCDataChannel = l.dc
		pc.poll()
		if dc.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			if not l.up:
				l.up = true
				if is_host:
					if peers().size() > max_guests:
						dc.put_packet(JSON.stringify({t = "full"}).to_utf8_buffer())
						l.up = false; dc.close(); pc.close(); links.erase(e); continue
					l.pid = _next_pid; _next_pid += 1
					joined.emit(int(l.pid))
				else:
					ok = true; connected_to_host.emit()
			while dc.get_available_packet_count() > 0:
				var d = JSON.parse_string(dc.get_packet().get_string_from_utf8())
				if d is Dictionary: _got(int(l.pid), d)
			var st := pc.get_connection_state()
			if st == WebRTCPeerConnection.STATE_DISCONNECTED:
				if l.blip == 0: l.blip = now
			else:
				l.blip = 0
			if st >= WebRTCPeerConnection.STATE_FAILED or (l.blip > 0 and now - int(l.blip) > 6000):
				_drop(e)
			continue
		if l.up:
			_drop(e); continue
		if now > int(l.deadline):
			links.erase(e); pc.close()
			if not is_host:
				active = false
				failed.emit("Couldn't connect to the host directly (some networks block it). Try Wi-Fi play, or another network.")
	if is_host:
		_keep_t -= dt
		if _keep_t <= 0.0:   # rooms expire after 15 idle minutes: keep ours alive
			_keep_t = 240.0; lock_room(locked)
	_sig_t -= dt
	if _sig_t <= 0.0:
		_sig_t = 0.5
		_poll_signals()


func _drop(e: int) -> void:
	var l: Dictionary = links[e]
	links.erase(e)
	(l.dc as WebRTCDataChannel).close(); (l.pc as WebRTCPeerConnection).close()
	if is_host: left.emit(int(l.pid))
	else:
		ok = false; active = false; host_left.emit()


func _poll_signals() -> void:
	if _sig_busy or code == "": return
	_sig_busy = true
	if is_host:
		# the newest join attempt (this reply also says which epoch is newest)
		var r := await _http(HTTPClient.METHOD_GET, "/api/signal?g=%s&code=%s&for=host&epoch=%d&from=%d" % [game_key(), code, _known_epoch,
			int(links[_known_epoch].from) if links.has(_known_epoch) else 0], {})
		if r.has("msgs") and active:
			var latest := int(r.get("epoch", 0))
			if links.has(_known_epoch): _handle(_known_epoch, r)
			if latest > _known_epoch:
				for e in range(maxi(_known_epoch + 1, latest - 3), latest + 1):
					if not links.has(e): links[e] = _new_link(e, 0)
				_known_epoch = latest
		# older attempts still shaking hands
		for e in links.keys():
			if e == _known_epoch or not links.has(e) or links[e].up: continue
			var q := await _http(HTTPClient.METHOD_GET, "/api/signal?g=%s&code=%s&for=host&epoch=%d&from=%d" % [game_key(), code, e, int(links[e].from)], {})
			if q.has("msgs") and links.has(e): _handle(e, q)
	elif links.has(0) and not links[0].up:
		var r := await _http(HTTPClient.METHOD_GET, "/api/signal?g=%s&code=%s&for=guest&epoch=%d&from=%d" % [game_key(), code, _epoch, int(links[0].from)], {})
		if r.has("msgs") and links.has(0): _handle(0, r)
	_sig_busy = false


func _handle(e: int, r: Dictionary) -> void:
	var l: Dictionary = links[e]
	var pc: WebRTCPeerConnection = l.pc
	l.from = int(r.get("next", l.from))
	for m in r.msgs:
		match String(m.get("t", "")):
			"hello":
				if is_host and not l.offered: l.offered = true; pc.create_offer()
			"offer", "answer":
				pc.set_remote_description(m.t, m.sdp)
				l.has_remote = true
				for c in l.ice: pc.add_ice_candidate(c.media, int(c.index), c.name)
				l.ice.clear()
			"ice":
				# the handshake messages travel as separate requests and can arrive out of order
				if l.has_remote: pc.add_ice_candidate(m.media, int(m.index), m.name)
				else: l.ice.append(m)


func _http(method: int, path: String, body: Dictionary) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 12.0
	add_child(req)
	var err := req.request(Net.relay_url().trim_suffix("/") + path, PackedStringArray(["content-type: application/json"]), method,
		"" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if err != OK:
		req.queue_free(); return {error = "Can't reach the online server"}
	var res: Array = await req.request_completed
	req.queue_free()
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if res[0] != HTTPRequest.RESULT_SUCCESS or not (parsed is Dictionary):
		return {error = "Can't reach the online server"}
	return parsed


# ---------------------------------------------------------------- Wi-Fi beacon
func _beacon(dt: float) -> void:
	if server != null:
		_beacon_t -= dt
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			beacon.put_packet(("BNBPARTY|%d|%s|%s|%d" % [VERSION, mode, host_name if host_name != "" else OS.get_model_name(), peers().size() + 1]).to_utf8_buffer())
		return
	while beacon.get_available_packet_count() > 0:
		var pkt := beacon.get_packet().get_string_from_utf8()
		var ip := beacon.get_packet_ip()
		var parts := pkt.split("|")
		if parts.size() >= 5 and parts[0] == "BNBPARTY" and int(parts[1]) == VERSION and parts[2] == mode:
			found[ip] = {name = parts[3], n = int(parts[4]), t = Time.get_ticks_msec()}
	for ip in found.keys():
		if Time.get_ticks_msec() - found[ip].t > 4000: found.erase(ip)


## Rounds floats so snapshots stay small on the wire.
static func pack(v):
	if v is float: return snappedf(v, 0.001)
	if v is Vector3: return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
	if v is Array:
		var out := []
		for x in v: out.append(pack(x))
		return out
	return v


## Events back from the wire: [x, y, z] -> Vector3, whole numbers -> int (JSON turns every number into a float).
static func unpack_event(e: Array) -> Array:
	var out := []
	for x in e:
		if x is Array and x.size() == 3 and (x[0] is float or x[0] is int):
			out.append(Vector3(x[0], x[1], x[2]))
		elif x is float and x == floorf(x) and absf(x) < 1e9:
			out.append(int(x))
		else:
			out.append(x)
	return out
