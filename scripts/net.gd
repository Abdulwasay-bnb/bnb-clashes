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
## Where the online relay runs. Override in settings.cfg ([net] relay="wss://...") or with --relay=URL.
const DEFAULT_RELAY := "wss://bnb-clashes-relay.onrender.com"

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
	is_host = true; via = "relay"
	_open(relay_url(), {t = "create", v = VERSION, g = GAME})


func join_room(c: String) -> void:
	close()
	is_host = false; via = "relay"; code = c.strip_edges().to_upper()
	_open(relay_url(), {t = "join", code = code, v = VERSION, g = GAME})


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
	if ws != null:
		ws.close()
	ws = null
	if server != null: server.stop()
	server = null
	if beacon != null: beacon.close()
	beacon = null
	connected = false; _was_open = false; code = ""; _hello = {}


func send(d: Dictionary) -> void:
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
