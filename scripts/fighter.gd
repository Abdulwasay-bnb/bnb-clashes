class_name Fighter
extends RefCounted
## Frame-driven fighter state machine. One step() per 60 Hz physics tick.

const FREE_FACE := ["idle", "walkf", "walkb", "crouch", "side", "dash", "bdash", "block", "hit", "getup", "stance", "run", "skid", "jump"]
const INVULN := ["down", "getup", "ko", "thrown", "throwing", "win", "final", "finaled"]
const FINAL_HP := 0.3    # the FINAL POWER unlocks at or below 30% health
static var move_seq := 0

var G   # main game node
var C: Dictionary
var side := 0
var rig: Node3D
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var air_v := Vector3.ZERO
var vy := 0.0
var face := 0.0
var meter := 0.0
var hp := 0.0
var max_hp := 0.0
var state := "idle"
var sf := 0
var move: Data.Move
var queued := ""
var buffer = null
var pend := 0
var pend_age := 0
var pend_dir := 5
var pend_ff := false
var ws_t := 0
var stance := ""
var stun := 0
var juggle := 0
var combo_hits := 0
var combo_dmg := 0
var flash := 0.0
var walk_ph := 0.0
var crouch_held := false
var crouch_block := false
var hit_crouch := false
var hit_lvl := "high"
var has_hit := false
var break_throw := false
var cmd_thrown := false
var thrown_by := ""
var victim: Fighter
var thrower: Fighter
var tm: Data.Move
var throw_dir := Vector3.FORWARD
var down_len := 38
var throw_t := 0.0
var armor_used := false
var move_id := 0
var no_guard := false
var refill := 0
var side_dir := 1
var disp: PackedFloat32Array
var from: PackedFloat32Array
var pose_vel := Pose.zero()           # spring velocity per joint
var prev_disp := Pose.zero()          # last tick's pose / position for render interpolation
var prev_pos := Vector3.ZERO
var prev_face := 0.0
var bounced := false
var anim_t := 0.0        # running time for looping clips
var voice_at := 0        # last voice line (ms), so grunts don't stack
# visual wear for the whole match (not part of the fight state)
var bruise := 0.0        # bruising + one eye swelling shut
var dirt := 0.0          # dust on the clothes from knockdowns
var blood_on := 0.0      # blood stains on the clothes
var last_rt := -1.0
var blue_used := false   # BLUE POWER: once per round, any time
var final_used := false  # FINAL POWER: once per round, low health only
var final_hit := 0       # cinematic: which beat landed last (victim's reaction clip)
var final_t := 0         # cinematic: attacker frame of that beat
var slammed := 0         # frames left showing the end of a throw (the landing)
var fall_kind := "back"  # how a knockdown looks: fly (launched / power), back, sweep (low), forward (KO variety)
var air_est := 40        # frames this flight is expected to last (to time the fall clip to the landing)
var last_dir := 5        # stick direction this frame (numpad, relative to the opponent)
var up_hold := 0         # frames up has been held: tap = sidestep, hold = jump


func _init(game, ch: Dictionary, s: int, costume := 0) -> void:
	G = game
	C = ch
	side = s
	max_hp = C.hp
	rig = Main.make_rig(C, costume)
	G.add_child(rig)


func reset(x: float) -> void:
	pos = Vector3(x, 0, 0); vel = Vector3.ZERO; air_v = Vector3.ZERO; vy = 0.0
	face = PI / 2 if x < 0 else -PI / 2
	hp = max_hp; state = "idle"; sf = 0; move = null; queued = ""; buffer = null
	pend = 0; pend_age = 0; pend_dir = 5; pend_ff = false; ws_t = 0; stance = ""
	stun = 0; juggle = 0; combo_hits = 0; combo_dmg = 0; flash = 0.0; walk_ph = 0.0
	crouch_held = false; crouch_block = false; hit_crouch = false; has_hit = false
	break_throw = false; cmd_thrown = false; victim = null; tm = null; down_len = 38; throw_t = 0.0
	blue_used = false; final_used = false; final_hit = 0
	armor_used = false; no_guard = false; refill = 0
	disp = C.pose.guard.duplicate(); from = disp
	pose_vel = Pose.zero(); prev_disp = disp.duplicate(); prev_pos = pos; prev_face = face; bounced = false


func fwd() -> Vector3: return Vector3(sin(face), 0, cos(face))
# Sidestep axis: +1 = into the background (away from camera) for either player.
func lat() -> Vector3:
	var s := 1.0 if side == 0 else -1.0
	return Vector3(cos(face) * s, 0, -sin(face) * s)
func dist_to(o: Fighter) -> float: return Vector2(o.pos.x - pos.x, o.pos.z - pos.z).length()
func face_to(o: Fighter, k: float) -> void: face = lerp_angle(face, atan2(o.pos.x - pos.x, o.pos.z - pos.z), k)
func set_state(s: String) -> void:
	state = s
	sf = 0


func to_neutral() -> void:
	move = null; queued = ""; stance = ""
	disp[Pose.YAW] = wrapf(disp[Pose.YAW], -PI, PI)
	set_state("crouch" if crouch_held else "idle")
	combo_hits = 0; combo_dmg = 0; juggle = 0; bounced = false


func can_act() -> bool:
	return state in ["idle", "walkf", "walkb", "crouch", "stance", "skid"] or (state == "side" and sf > 5) \
		or (state == "dash" and sf > 3) or (state == "bdash" and sf > 10) or (state == "run" and sf > 2) or (state == "jump" and sf > 3)


## In the air on their own (a jump or a jump attack) rather than launched.
func airborne() -> bool:
	return state == "jump" or (state == "attack" and move != null and move.key.begins_with("j"))


func is_low() -> bool:
	return state == "crouch" or (state == "block" and crouch_block) or (state == "hit" and hit_crouch) \
		or (state == "attack" and move.low and sf >= 3) or (state == "stance" and C.stances[stance].low)


func is_jumping() -> bool:
	return (state == "attack" and move.jump and sf >= 4 and sf < move.s + move.a) or (airborne() and pos.y > 0.15)


# Neutral or holding back = standing guard (highs & mids). Holding down = crouch guard (lows).
func is_blocking(lvl: String) -> bool:
	if no_guard:
		return false
	if lvl == "low":
		return state == "crouch" or (state == "block" and crouch_block)
	return state in ["idle", "walkb"] or (state == "block" and not crouch_block) or (state == "bdash" and sf > 8)


func collect(inp: InputBuf.Frame) -> void:
	crouch_held = inp.dn
	if inp.pressed:
		if pend == 0:
			pend_dir = inp.dir; pend_ff = inp.ff_recent; pend_age = 0
		pend |= inp.pressed
		if inp.ff_recent:
			pend_ff = true


func control(inp: InputBuf.Frame) -> void:
	collect(inp)
	last_dir = inp.dir
	up_hold = up_hold + 1 if inp.dir >= 7 else 0
	if state == "block":
		crouch_block = inp.dn
	# Buttons wait 2 frames so simultaneous presses (1+2, 3+4) register together.
	if pend != 0:
		pend_age += 1
		if pend_age >= 2:
			handle_buttons(pend, inp.dir if pend_dir == 5 else pend_dir, pend_ff)
			pend = 0
	if can_act():
		if buffer != null:
			var b = buffer
			# A second press buffered behind the first becomes its string follow-up.
			buffer = {bits = b.chain, dir = 5, ff = false, ttl = 14} if b.has("chain") else null
			try_start(b.bits, b.dir, b.ff)
			return
		if pend == 0:
			movement(inp)
	elif buffer != null:
		buffer.ttl -= 1
		if buffer.ttl <= 0:
			buffer = null


static func btn_str(bits: int) -> String:
	var s := ""
	for i in 4:
		if bits & (1 << i):
			s += str(i + 1)
	return s


static func first_btn(bits: int) -> String:
	return "1" if bits & 1 else "2" if bits & 2 else "3" if bits & 4 else "4"


static func dir_prefixes(d: int) -> Array:
	match d:
		3: return ["df", "d"]
		1: return ["db", "d"]
		2: return ["d"]
		9: return ["uf", "f"]
		6: return ["f"]
		4, 7: return ["b"]
	return [""]


func handle_buttons(bits: int, d: int, ff: bool) -> void:
	if state == "thrown":
		if sf <= 16 and ((bits & 3) == 3 if cmd_thrown else (bits & 3) != 0):
			break_throw = true
		return
	if state == "attack" and not move.next.is_empty() and queued == "" and sf <= move.s + move.a + 12:
		var nk = move.next.get(btn_str(bits), move.next.get(first_btn(bits), ""))
		if nk != "":
			queued = nk
			return
	if state == "attack" and queued != "":
		# A string press arrived early (e.g. during hit-freeze): keep it for the next hit.
		buffer = {bits = bits, dir = d, ff = ff, ttl = 20}
		return
	if can_act():
		try_start(bits, d, ff)
	elif buffer != null and buffer.ttl > 0 and not buffer.has("chain"):
		buffer.chain = bits
		buffer.ttl = 14
	else:
		buffer = {bits = bits, dir = d, ff = ff, ttl = 14}


# Pick a move from button(s) + direction + context (stance, dash, while-standing).
func try_start(bits: int, d: int, ff: bool) -> void:
	var M: Dictionary = C.moves
	var b := btn_str(bits)
	var b1 := first_btn(bits)
	var pre := dir_prefixes(d)
	var cands: Array = []
	# running and jumping have their own attacks
	if state == "run" or (state == "skid" and sf < 9):
		cands.append("run" + b); cands.append("run" + b1)
	if state == "jump":
		cands.append("j" + b); cands.append("j" + b1)
		for k in cands:
			if M.has(k): start_move(k); return
		return
	if state == "stance":
		for p in pre + [""]:
			cands.append(stance + ":" + p + b)
			cands.append(stance + ":" + b1)
	if ff:
		cands.append("ff" + b); cands.append("ff" + b1)
	if ws_t > 0:
		cands.append("ws" + b); cands.append("ws" + b1)
	for p in pre:
		cands.append(p + b)
	cands.append(b)
	for p in pre:
		cands.append(p + b1)
	cands.append(b1)
	for k in cands:
		if M.has(k) and power_ok(k):
			start_move(k)
			return


func blue_ready() -> bool: return not blue_used
func final_ready() -> bool: return not final_used and hp <= max_hp * FINAL_HP and hp > 0


func power_ok(k: String) -> bool:
	if k == "34" or k == "13": return blue_ready()
	if k == "24":
		if not final_ready() and not G.resim: G.ui.pop_text("FINAL USED" if final_used else "FINAL: HEALTH ≤ 30%", side)
		return final_ready()
	return true


func start_move(key: String) -> void:
	var m: Data.Move = C.moves[key]
	disp[Pose.YAW] = wrapf(disp[Pose.YAW], -PI, PI)
	move = m
	from = disp.duplicate()
	set_state("attack")
	has_hit = false; queued = ""; armor_used = false; ws_t = 0
	if m.surge: G.voice(self, "power")
	elif m.launch or m.kd or m.dmg >= 18 or m.is_throw: G.voice(self, "heavy")
	elif randf() < 0.45: G.voice(self, "attack")
	move_seq += 1
	move_id = move_seq
	if buffer != null and not m.next.is_empty():
		var nk = m.next.get(btn_str(buffer.bits), m.next.get(first_btn(buffer.bits), ""))
		if nk != "":
			queued = nk
			buffer = null
	if m.final:
		final_used = true
		G.ui.pop_text("FINAL POWER", side); G.ui.screen_flash(Color(1.0, 0.3, 0.2)); G.sfx("surge"); G.voice(self, "power")
	if m.surge:
		blue_used = true
		meter = 0.0
		G.surge_cam = {f = self, t = m.s + 8}
		G.sfx("surge")
		G.ui.pop_text(C.surge_name, side)
		G.ui.screen_flash(C.accent)
		# the fighter's power props fly in and land on the first active frame
		if C.has("person") and G.F.size() == 2:
			var fx: Array = C.person.get("fx", [])
			if fx.is_empty(): PowerProps.launch(G, self, G.F[1 - side], String(C.person.get("prop", "")), m.s / 60.0)
			else: PowerProps.play(G, self, G.F[1 - side], fx, m.s / 60.0)
	if side == 0 and G.mode == "training" and not m.trans:
		G.fd = {m = m, res = "", adv = null, tr = null}


func movement(inp: InputBuf.Frame) -> void:
	if state == "jump": return
	if state == "run":
		if inp.dir >= 7 and up_hold >= 3: jump(1.6); return       # running jump: long and fast
		if inp.dir != 6 and inp.dir != 9: set_state("skid")
		return
	if state == "side" and sf >= 5 and up_hold >= 7:
		# held up: the sidestep becomes a jump (up-back / up / up-forward)
		jump(-1.0 if last_dir == 7 else (1.0 if last_dir == 9 else 0.0)); return
	if inp.ff_now and state != "crouch":
		set_state("dash"); return
	if inp.bb_now:
		set_state("bdash"); return
	if inp.up_tap:
		set_state("side"); side_dir = 1; return
	if inp.down_tap and state == "crouch":
		set_state("side"); side_dir = -1; return
	if state in ["side", "dash", "bdash"]:
		return
	var d := inp.dir
	if state == "stance":
		if d == 4 or d == 7:
			stance = ""
			set_state("walkb")
		return
	var ns := "crouch" if d <= 3 else "walkf" if (d == 6 or d == 9) else "walkb" if (d == 4 or d == 7) else "idle"
	if state == "crouch" and ns != "crouch":
		ws_t = 10   # "while standing" window
	if ns != state:
		set_state(ns)


## Leave the ground: dirx = -1 back, 0 straight up, 1 forward (1.6 from a run).
func jump(dirx: float) -> void:
	set_state("jump")
	vy = 0.118 if absf(dirx) < 1.5 else 0.105
	air_v = fwd() * 0.045 * dirx * C.speed
	pos.y = 0.01
	squash(0.5)
	G.sfx("whoosh")


func step(opp: Fighter) -> void:
	sf += 1
	if slammed > 0: slammed -= 1
	if ws_t > 0:
		ws_t -= 1
	var f := fwd()
	var sp: float = C.speed
	match state:
		"walkf":
			pos += f * 0.03 * sp; walk_ph += 0.25 * sp
		"walkb":
			pos -= f * 0.024 * sp; walk_ph -= 0.22 * sp
		"dash":
			pos += f * 0.11 * sp * maxf(0.0, 1.0 - sf / 14.0); walk_ph += 0.4
			if sf >= 10 and (last_dir == 6 or last_dir == 9) and dist_to(opp) > 1.4:
				set_state("run")   # still holding forward: break into a run
			elif sf >= 14:
				to_neutral()
				squash(0.4)   # plant the feet at the end of the dash
		"run":
			pos += f * 0.088 * sp; walk_ph += 0.45 * sp
			face_to(opp, 0.08)
			if dist_to(opp) < 0.95 or sf > 150: set_state("skid")
		"skid":
			pos += f * 0.06 * sp * maxf(0.0, 1.0 - sf / 10.0)
			if sf >= 10:
				to_neutral(); squash(0.5)
		"bdash":
			pos -= f * 0.1 * sp * maxf(0.0, 1.0 - sf / 18.0)
			if sf >= 18: to_neutral()
		"side":
			pos += lat() * side_dir * 0.09 * C.side_bonus * maxf(0.0, 1.0 - sf / 16.0)
			if sf >= 16: to_neutral()
		"stance":
			if sf >= C.stances[stance].dur: to_neutral()
		"attack":
			var m := move
			if airborne():
				# jump attacks: keep flying; touching down ends them
				if sf <= 2: face_to(opp, 0.35)
				if pos.y <= 0.0 and sf > 3:
					pos.y = 0.0; to_neutral(); squash(0.7); G.sfx("thud"); return
				if sf >= m.end:
					move = null; state = "jump"   # finished the strike, still falling
				return
			if m.jump and sf == m.s + m.a + 2:
				squash(0.8)
			# Linear moves only track for 2 frames; homing moves track through startup.
			if sf <= 2 or (m.homing and sf < m.s):
				face_to(opp, 0.5 if m.homing else 0.35)
			if m.move > 0.0 and sf <= m.s + m.a:
				pos += f * m.move * C.scale
			if m.back > 0.0 and sf <= m.s:
				pos -= f * m.back
			if not m.trans and sf == maxi(1, m.s - 4):
				G.sfx("whoosh")
			if queued != "" and sf > m.s + m.a:
				start_move(queued); return
			if m.auto != "" and sf > m.s + m.a:
				start_move(m.auto); return
			if sf >= m.end:
				if m.to_stance != "":
					stance = m.to_stance
					disp[Pose.YAW] = wrapf(disp[Pose.YAW], -PI, PI)
					move = null
					set_state("stance")
				else:
					to_neutral()
		"hit", "block":
			if sf >= stun: to_neutral()
		"down":
			if sf >= down_len: set_state("getup")
		"getup":
			if sf >= 22:
				to_neutral()
				squash(0.6)
		"throwing":
			throw_step()
		"final":
			final_step()
		"finaled":
			if sf > 3 and (thrower == null or thrower.state != "final"):
				pos.y = 0.0; down_len = 40; set_state("down")
		"thrown":
			# Safety net: never stay grabbed by someone who is no longer throwing.
			if sf > 3 and (thrower == null or thrower.state != "throwing" or thrower.victim != self):
				pos.y = 0.0; down_len = 30
				dirt = minf(1.0, dirt + 0.3)   # landed on the floor: clothes get dusty
				set_state("down")
		"air":
			if pos.y <= 0.0 and sf > 2 and vy <= 0.0:
				pos.y = 0.0
				land()


## Grapples: both fighters play a slice of a Mixamo throw / thrown pair at real speed; the victim hits the
## floor (damage, shake) on the frame the thrown clip lands. Positions are ours (the clips aren't co-located).
const THROW_SETS := {
	"over": {a = "throw", b = "thrown", a0 = 0.6, a1 = 4.0, b0 = 1.2, b1 = 4.0, hit = 0.79, dur = 110, gap = 0.75, travel = 0.0},
	"slam": {a = "throw_hell_a", b = "thrown_hell_b", a0 = 3.6, a1 = 6.8, b0 = 3.8, b1 = 7.0, hit = 0.69, dur = 120, gap = 0.7, travel = 0.0},
	"takedown": {a = "throw_takedown_a", b = "thrown_takedown_b", a0 = 0.3, a1 = 2.6, b0 = 0.8, b1 = 2.6, hit = 0.5, dur = 92, gap = 0.7, travel = 1.3},
	# a real Mixamo pair: judo shoulder throw (the victim lands at 3.4 s)
	"shoulder": {a = "g_shoulder_a", b = "g_shoulder_b", a0 = 1.0, a1 = 4.3, b0 = 1.0, b1 = 4.3, hit = 0.72, dur = 150, gap = 0.75, travel = 0.0},
	# a leaping shoulder throw: thrower flies through, victim cartwheels away
	"flying": {a = "g_flying_shoulder", b = "g_thrown", a0 = 0.0, a1 = 2.9, b0 = 0.6, b1 = 3.1, hit = 0.76, dur = 128, gap = 0.7, travel = 0.9},
	# picked up overhead and slammed down
	"grabslam": {a = "g_grab_slam", b = "fall_fly", a0 = 1.4, a1 = 4.2, b0 = 0.3, b1 = 0.36, hit = 0.75, dur = 125, gap = 0.6, travel = 0.0, lift = 1.3},
	# lifted by the throat, held up... and slammed
	"choke": {a = "g_choke_lift", b = "fall_fly", a0 = 0.8, a1 = 4.6, b0 = 0.3, b1 = 0.36, hit = 0.86, dur = 168, gap = 0.55, travel = 0.0, lift = 1.45},
}
## Everyone's own grapple (by person), falling back to their fighting style's.
const PERSON_THROW := {"hamza_khan": "choke", "tuaha_aamir": "choke", "muhammad_sufyan": "grabslam", "nabeel_ahmad": "grabslam",
	"muhammad_nauman_nawaz": "slam", "usman_najeeb": "grabslam", "kashaf_ud_duja": "slam", "abdul_wasay": "shoulder", "faisal_ahmed": "shoulder",
	"zia_khan": "shoulder", "muhammad_mubarak": "shoulder", "amina_mughal": "flying", "muzdalfa_naeem": "flying", "umar_farooq": "over",
	"aqsa_altaf": "flying", "mahveen_khan": "flying", "muhammad_saad": "over", "samreen_fatima": "flying", "syeda_ghazia": "over",
	"daniyal_zubair": "takedown", "faizan_ali": "takedown", "sarfraz_yousaf": "takedown", "kiran_fazal": "knees", "sabir_ud_din": "knees",
	"ali": "knees", "abdul_wasay_waqas": "over"}


static func throw_set(m: Data.Move) -> Dictionary:
	if m == null: return THROW_SETS.over
	var ts: Dictionary = THROW_SETS.get(m.throw_type, THROW_SETS.over)
	if not (ClipLib.has(ts.a) and ClipLib.has(ts.b)): return {}
	return ts


func throw_dur() -> int:
	var ts := throw_set(tm)
	return int(ts.dur) if not ts.is_empty() and tm.throw_type != "knees" else 60


func throw_step() -> void:
	var d := victim
	var f := throw_dir
	var m := tm
	if d.state == "thrown" and d.break_throw:
		set_state("block"); stun = 20; crouch_block = false
		d.set_state("block"); d.stun = 20; d.crouch_block = false; d.pos.y = 0
		d.vel = f * 0.12; vel = -f * 0.08
		G.ui.pop_text("THROW BREAK", d.side); G.sfx("block"); G.announce_voice("combo_breaker")
		return
	var dur := throw_dur()
	if d.state == "thrown":
		d.face = face + PI
		var dmg := roundi(m.dmg * C.power)
		var grab_k := clampf(sf / 8.0, 0.2, 1.0)   # ease the victim into the hold
		if m.throw_type == "knees":
			d.pos = d.pos.lerp(Vector3(pos.x + f.x * 0.62, 0, pos.z + f.z * 0.62), grab_k)
			if sf in [18, 28, 38]:
				var part := roundi(dmg / 3.0)
				G.hurt(d, part, self); d.combo_dmg += part; d.flash = 1.0; G.hitstop = 5; G.shake = 0.1
				G.sfx("hit"); G.burst(Vector3(d.pos.x, 1.0, d.pos.z), Color.WHITE, 10, 3.0)
			if sf == 44:
				d.set_state("air"); d.vy = 0.06; d.air_v = f * 0.04; d.juggle = 8; d.pos.y = 0.01
				G.fd_log(self, "THROW")
				if d.hp <= 0: G.ko_start(self)
		else:
			var ts := throw_set(m)
			var hit_f := int(float(ts.get("hit", 0.6)) * dur)
			d.throw_t = clampf(float(sf) / dur, 0.0, 1.0)
			# a tackle carries both fighters forward until the slam
			if float(ts.get("travel", 0.0)) > 0.0 and sf < hit_f:
				pos += f * (float(ts.travel) / hit_f)
			var lift_y := 0.0
			if ts.has("lift") and sf < hit_f:
				lift_y = float(ts.lift) * smoothstep(float(hit_f) * 0.25, float(hit_f) * 0.6, float(sf))
			d.pos = d.pos.lerp(Vector3(pos.x + f.x * float(ts.get("gap", 0.75)), lift_y, pos.z + f.z * float(ts.get("gap", 0.75))), grab_k if lift_y == 0.0 else 0.5)
			if sf == hit_f:
				# their own flourish: the person's signature prop bursts out on the landing
				if C.has("person") and String(C.person.get("prop", "")) != "":
					PowerProps.play(G, self, d, [["burst", String(C.person.prop), 0.0, 6]], 0.3)
				G.hurt(d, dmg, self); d.combo_dmg = dmg; d.pos.y = 0; d.down_len = 46
				d.set_state("ko" if d.hp <= 0 else "down")
				d.slammed = 30   # keep the thrown clip's landing pose for a moment
				G.hitstop = 8; G.shake = 0.3; G.sfx("heavy")
				G.burst(Vector3(d.pos.x, 0.3, d.pos.z), C.accent, 20, 3.5); G.ring(Vector3(d.pos.x, 0.3, d.pos.z), Color.WHITE, 1.0)
				G.fd_log(self, "THROW")
				if d.hp <= 0: G.ko_start(self)
	if sf >= dur:
		to_neutral()


## FINAL POWER (red, low health): a cinematic built per person —
##   1) SUMMON: their own power move, their signature props fly in with their catchphrase
##   2) BEAT-DOWN: a combo in their fighting style; damage lands on the clip's real strike frames
##   3) FINISHER: style-specific (launching uppercut / flip kick / fireball blast / choke lift / grab-and-slam)
##   4) TAUNT over the fallen opponent
## The plan comes from clip data only, so both online players build the same one.
const FINAL_STYLES := {
	"vex": {segs = [["f_quad_punch", 0.3, 1.35], ["f_body_blow", 0.1, 1.1]], fin = ["f_knee_jabs_upper", 3.5, 4.75, 4.2, "launch"], taunt = ["f_chest_thump", 0.2, 2.2]},
	"bastion": {segs = [["f_body_blow", 0.1, 1.2], ["fin_combo_punch", 0.4, 1.5]], fin = ["g_choke_lift", 0.8, 4.45, 4.3, "lift"], taunt = ["f_flex", 1.8, 3.4]},
	"sora": {segs = [["fin_mma_kick", 0.2, 1.1], ["atk_hurricane", 0.2, 1.6]], fin = ["f_spin_flip_kick", 0.9, 2.45, 1.93, "launch"], taunt = ["f_battlecry", 0.0, 2.0]},
	"lio": {segs = [["f_flyknee_punch", 0.1, 2.15]], fin = ["f_flip_kick", 0.1, 1.55, 1.0, "launch"], taunt = ["f_battlecry", 0.0, 2.0]},
	"tao": {segs = [["atk_palm_combo", 0.6, 2.7], ["fin_combo_elbow", 0.45, 1.2]], fin = ["f_fireball", 1.3, 3.0, 2.3, "blast"], taunt = ["intro_bow", 0.2, 2.0]},
	"kael": {segs = [["f_knee_jabs_upper", 1.0, 2.9], ["fin_combo_elbow", 0.45, 1.2]], fin = ["fin_fly_kick", 0.05, 1.3, 0.43, "launch"], taunt = ["f_chest_thump", 0.2, 2.2]},
	"ember": {segs = [["f_punch_elbow", 1.7, 3.2]], fin = ["g_grab_slam", 1.4, 4.0, 3.5, "lift"], taunt = ["f_flex", 1.8, 3.4]},
	"mara": {segs = [["fin_combo_punch", 0.4, 1.5], ["fin_mma_kick", 0.2, 1.1]], fin = ["f_backflip_upper", 1.1, 2.45, 2.17, "launch"], taunt = ["f_battlecry", 0.0, 2.0]},
}
const FINAL_SPEED := 1.15
const FINAL_SUMMON := 70
static var _final_plans := {}


static func final_plan(C: Dictionary) -> Dictionary:
	var key := String(C.id)
	if _final_plans.has(key): return _final_plans[key]
	var style: Dictionary = FINAL_STYLES.get(C.arch, FINAL_STYLES.mara)
	var segs := []
	var f := FINAL_SUMMON
	var pa := own_clip(C, "power_anim", "pw_twohand")
	segs.append({clip = pa, t0 = 0.0, t1 = minf(_len(pa), FINAL_SUMMON / 60.0 * FINAL_SPEED), f0 = 0, f1 = FINAL_SUMMON, beats = [int(FINAL_SUMMON * 0.62)], kind = "summon"})
	for sg in style.segs:
		if not ClipLib.has(sg[0]): continue
		var n := int((float(sg[2]) - float(sg[1])) * 60.0 / FINAL_SPEED)
		var beats := []
		var c: ClipLib.Clip = ClipLib.get_clip(sg[0])
		for h in c.hits:
			if h.reach > 0.4 and h.t >= float(sg[1]) and h.t <= float(sg[2]):
				var bf := f + int((h.t - float(sg[1])) * 60.0 / FINAL_SPEED)
				if beats.is_empty() or bf - int(beats[-1]) >= 8: beats.append(bf)
		segs.append({clip = sg[0], t0 = float(sg[1]), t1 = float(sg[2]), f0 = f, f1 = f + n, beats = beats, kind = "combo"})
		f += n
	var fin: Array = style.fin
	var fn := int((float(fin[2]) - float(fin[1])) * 60.0 / FINAL_SPEED)
	var hit_f := f + int((float(fin[3]) - float(fin[1])) * 60.0 / FINAL_SPEED)
	segs.append({clip = fin[0], t0 = float(fin[1]), t1 = float(fin[2]), f0 = f, f1 = f + fn, beats = [hit_f], kind = fin[4]})
	var fin_f0 := f
	f += fn
	var tt: Array = style.taunt
	var tn := int((float(tt[2]) - float(tt[1])) * 60.0)
	segs.append({clip = tt[0], t0 = float(tt[1]), t1 = float(tt[2]), f0 = f, f1 = f + tn, beats = [], kind = "taunt"})
	var plan := {segs = segs, hit_f = hit_f, fin_kind = fin[4], fin_f0 = fin_f0, total = f + tn}
	_final_plans[key] = plan
	return plan


func _final_seg(at: int) -> Dictionary:
	var plan := final_plan(C)
	for sg in plan.segs:
		if at < int(sg.f1): return sg
	return plan.segs[-1]


func final_step() -> void:
	var d := victim
	var f := throw_dir
	var plan := final_plan(C)
	if sf >= int(plan.total):
		to_neutral(); return
	if d == null or d.state != "finaled" or d.thrower != self:
		return   # the victim has been launched / slammed: finish the taunt
	d.face = face + PI
	var lift := 0.0
	if plan.fin_kind == "lift" and sf >= int(plan.fin_f0):
		var span := float(int(plan.hit_f) - int(plan.fin_f0))
		lift = 1.4 * smoothstep(float(plan.fin_f0) + span * 0.2, float(plan.fin_f0) + span * 0.55, float(sf))
	d.pos = d.pos.lerp(Vector3(pos.x + f.x * (0.85 if lift == 0.0 else 0.5), lift, pos.z + f.z * (0.85 if lift == 0.0 else 0.5)), 0.35)
	# the summon: their props fly in with their catchphrase
	if sf == int(FINAL_SUMMON * 0.35) and C.has("person"):
		var fx: Array = C.person.get("fx", [])
		if fx.is_empty(): PowerProps.launch(G, self, d, String(C.person.get("prop", "")), 0.5)
		else: PowerProps.play(G, self, d, fx, 0.5)
		G.sfx("surge")
	var is_beat := false
	for sgm in plan.segs:
		if sf in sgm.beats: is_beat = true
	if not is_beat: return
	var finisher: bool = sf == int(plan.hit_f)
	var dmg := maxi(1, roundi(d.max_hp * (0.11 if finisher else 0.022) * C.power))
	G.hurt(d, dmg, self); d.combo_hits += 1; d.combo_dmg += dmg; d.flash = 1.0
	d.final_hit += 1; d.final_t = sf
	var at := Vector3(d.pos.x, 1.1 + d.pos.y * 0.5, d.pos.z)
	if not finisher:
		G.hitstop = 5; G.shake = 0.1
		G.sfx("hit" if d.final_hit % 3 else "heavy"); G.burst(at, Color.WHITE if d.final_hit % 2 else Color(1, 0.82, 0.4), 14, 3.0)
		d.kick("high" if d.final_hit % 2 else "mid", 1.0)
		if d.final_hit % 2 == 0: G.voice(d, "hurt")
		return
	# FINISHER
	G.hitstop = 14; G.shake = 0.6; G.slow = 45
	G.sfx("heavy"); G.sfx("ko")
	G.burst(at, C.accent, 44, 6.5); G.ring(Vector3(d.pos.x, 0.25, d.pos.z), Color.WHITE, 2.2); G.ring(Vector3(d.pos.x, 0.3, d.pos.z), C.accent, 3.4)
	if C.has("person"):
		PowerProps.play(G, self, d, [["burst", String(C.person.get("prop", "")), 0.0, 10]], 0.3)
	G.ui.pop_text(String(C.surge_name).to_upper() + "!", side)
	G.voice(d, "ko" if d.hp <= 0 else "hurt")
	d.thrower = null
	if plan.fin_kind == "lift":   # ...and SLAM
		d.pos.y = 0.0; d.fall_kind = "fly"; d.down_len = 70
		d.set_state("ko" if d.hp <= 0 else "down")
	else:                          # launched / blasted across the room
		var blast: bool = plan.fin_kind == "blast"
		d.fall_kind = "fly"; d.juggle = 9
		d.vy = 0.1 if blast else 0.15; d.air_v = f * (0.11 if blast else 0.05); d.pos.y = 0.05
		d.air_est = int(2.0 * d.vy / Main.GRAV) + 4
		d.set_state("air")
	if d.hp <= 0: G.ko_start(self)


func physics() -> void:
	if airborne():
		pos.y += vy
		vy -= Main.GRAV
		pos += air_v
		if pos.y <= 0.0 and vy < 0.0:
			pos.y = 0.0
			if state == "jump":
				set_state("idle"); squash(0.8); G.sfx("thud")
		var ra := Vector2(pos.x, pos.z).length()
		if ra > Main.ARENA_R:
			pos.x *= Main.ARENA_R / ra; pos.z *= Main.ARENA_R / ra
		return
	if pos.y > 0.0 and state in ["hit", "block"]:
		# knocked out of a jump: fall the rest of the way as a juggle
		set_state("air"); air_v = -fwd() * 0.02
	if state == "air":
		pos.y += vy
		vy -= Main.GRAV * (1.0 + juggle * 0.04)
		pos += air_v
		if pos.y <= 0 and vy < 0:
			pos.y = 0
			land()
	elif state != "thrown":
		pos += vel
		vel *= 0.8
	var r := Vector2(pos.x, pos.z).length()
	if r > Main.ARENA_R:
		pos.x *= Main.ARENA_R / r
		pos.z *= Main.ARENA_R / r


func land() -> void:
	if not bounced and hp > 0 and combo_hits > 0:
		# Ground bounce: a short hop that combos can pick up.
		bounced = true
		vy = 0.05; pos.y = 0.01; air_v *= 0.3; juggle += 2
		pose_vel[Pose.ROOT_RX] += 0.25; pose_vel[Pose.TORSO_X] -= 0.2   # body slaps the floor and rebounds
		G.shake = maxf(G.shake, 0.08); G.sfx("thud")
		G.burst(Vector3(pos.x, 0.05, pos.z), Color(0.72, 0.77, 0.84), 8, 1.2)
		return
	juggle = 0; air_v = Vector3.ZERO; down_len = 38; bounced = false
	set_state("ko" if hp <= 0 else "down")
	pose_vel[Pose.TORSO_X] += 0.18; pose_vel[Pose.HEAD_X] += 0.25   # head and chest settle after the fall
	G.shake = maxf(G.shake, 0.1); G.sfx("thud")
	G.burst(Vector3(pos.x, 0.05, pos.z), Color(0.72, 0.77, 0.84), 10, 1.5)


# Keyframed move playback: from-pose -> keys -> back to guard / stance.
func sample_move() -> PackedFloat32Array:
	var m := move
	var pf := 0
	var pp := from
	for k in m.track:
		if sf < k[0]:
			var u := clampf(float(sf - pf) / float(k[0] - pf), 0.0, 1.0)
			var c: int = k[2] if k.size() > 2 else 0
			var e := Pose.ease_io(u) if c == 0 else (1.0 - pow(1.0 - u, 3.0)) if c == 1 else u * u * u
			return Pose.lerp_p(pp, k[1], e)
		pf = k[0]
		pp = k[1]
	var e: PackedFloat32Array = (C.stances[m.to_stance].pose if m.to_stance != "" else C.pose.crouch if crouch_held else C.pose.guard).duplicate()
	e[Pose.YAW] += roundf((pp[Pose.YAW] - e[Pose.YAW]) / TAU) * TAU   # finish spins forward instead of unwinding
	return Pose.lerp_p(pp, e, Pose.ease_io(clampf(float(sf - pf) / maxf(1.0, m.end - pf) * 1.2, 0.0, 1.0)))


func target_pose() -> PackedFloat32Array:
	var P: Dictionary = C.pose
	match state:
		"attack": return sample_move()
		"stance": return C.stances[stance].pose
		"crouch": return P.crouch
		"block":
			var bt := (1.0 - pow(1.0 - clampf(sf / 3.0, 0.0, 1.0), 2.0)) * (1.0 - smoothstep(stun * 0.7, float(stun), float(sf)))
			return Pose.lerp_p(P.crouch if crouch_block else P.guard, P.cblock if crouch_block else P.block, maxf(bt, 0.35))
		"hit":
			# Snap into the recoil, hold, then ease back to guard before the stun ends.
			var into := 1.0 - pow(1.0 - clampf(sf / 3.0, 0.0, 1.0), 3.0)
			var out := 1.0 - smoothstep(stun * 0.5, float(stun), float(sf))
			var hp: PackedFloat32Array = P.hitC if hit_crouch else P.hitM if hit_lvl == "mid" else P.hitH
			return Pose.lerp_p(P.crouch if hit_crouch else P.guard, hp, into * out)
		"air":
			var a: PackedFloat32Array = P.air.duplicate()
			a[Pose.ROOT_RX] = -0.5 - clampf(0.3 - vy * 6.0, 0.0, 1.1)
			return a
		"thrown":
			if thrown_by == "knees":
				return P.hitM
			var t: PackedFloat32Array = P.air.duplicate()
			t[Pose.ROOT_RX] = -0.5 - throw_t * 2.6
			return t
		"down", "ko": return P.down
		"getup": return Pose.lerp_p(P.down, P.guard, Pose.ease_io(clampf(sf / 20.0, 0.0, 1.0)))
		"side": return P.side
		"jump":
			# knees tucked on the way up, legs reaching for the floor on the way down
			var j: PackedFloat32Array = P.guard.duplicate()
			var tuck := clampf(vy * 9.0, 0.0, 1.0)
			j[Pose.LHX] -= 0.9 * tuck + 0.2; j[Pose.RHX] -= 0.6 * tuck + 0.1
			j[Pose.LK] += 1.3 * tuck + 0.3; j[Pose.RK] += 1.0 * tuck + 0.3
			return j
		"skid": return P.dash
		"dash": return P.dash
		"bdash": return P.bdash
		"throwing":
			if tm.throw_type == "knees":
				return P.knee if (sf > 12 and sf % 10 < 6) else P.grab
			return P.grab if sf < 12 else P.lift
		"win": return P.win
	return P.guard


## Physical reaction: push joint velocities so the spring pose system recoils naturally.
## lvl = where it landed, power ~ damage / 10, blocked = guard absorbed it.
func kick(lvl: String, power: float, blocked := false) -> void:
	var p := clampf(power, 0.4, 2.2) * (0.45 if blocked else 1.0)
	var twist := randf_range(-0.1, 0.1) * p
	match lvl:
		"high":
			pose_vel[Pose.HEAD_X] -= 0.32 * p; pose_vel[Pose.TORSO_X] -= 0.14 * p
			pose_vel[Pose.HEAD_Y] += twist * 1.5
		"low":
			pose_vel[Pose.LK] += 0.25 * p; pose_vel[Pose.RK] += 0.18 * p; pose_vel[Pose.HIP_Y] -= 0.035 * p
			pose_vel[Pose.TORSO_X] += 0.08 * p
		_:
			pose_vel[Pose.TORSO_X] += 0.2 * p; pose_vel[Pose.HEAD_X] += 0.12 * p; pose_vel[Pose.HIP_Y] -= 0.025 * p
	pose_vel[Pose.TORSO_Y] += twist
	pose_vel[Pose.TORSO_Z] += randf_range(-0.06, 0.06) * p
	if blocked:
		pose_vel[Pose.LSX] += 0.15 * p; pose_vel[Pose.RSX] += 0.15 * p


## Impact recoil for the attacker (a connecting hit stops the limb and jolts the body back a little).
func recoil(power: float) -> void:
	pose_vel[Pose.TORSO_X] -= 0.05 * clampf(power, 0.4, 2.0)
	pose_vel[Pose.HIP_Y] -= 0.01


## Landing squash: knees absorb the fall.
func squash(power: float) -> void:
	pose_vel[Pose.HIP_Y] -= 0.06 * power
	pose_vel[Pose.LK] += 0.35 * power; pose_vel[Pose.RK] += 0.35 * power
	pose_vel[Pose.TORSO_X] += 0.08 * power


func save_prev() -> void:
	prev_disp = disp.duplicate()
	prev_pos = pos
	prev_face = face


func tick_pose() -> void:
	# Damped spring per joint: smooth, slightly organic motion without the lag of a plain lerp.
	var w := 0.8 if state in ["attack", "throwing"] else 0.6 if state in ["hit", "block", "thrown"] else 0.36
	var damp := 2.0 * 0.82 * w
	var t := target_pose()
	for i in Pose.N:
		pose_vel[i] += w * w * (t[i] - disp[i]) - damp * pose_vel[i]
		disp[i] += pose_vel[i]
	flash *= 0.82


static func idle_clip(id: String) -> String:
	if id == "lio": return ""    # capoeira ginga stays procedural
	return {"mara": "idle_bounce", "kael": "idle_bounce", "sora": "idle_bounce", "bastion": "idle_fight_b", "tao": "idle_fight_b"}.get(id, "idle_fight")


## Match-start and victory animations, per fighter (fall back to the keyframed poses when missing).
const INTRO := {"vex": "intro_salute", "bastion": "intro_flex", "sora": "intro_bow", "ember": "intro_neck",
	"mara": "intro_warmup", "lio": "intro_warmup", "tao": "intro_bow", "kael": "intro_bow"}
const WIN := {"vex": "win_boxing", "bastion": "win_cheer", "sora": "win_celebrate", "ember": "win_cheer",
	"mara": "win_boxing", "lio": "win_celebrate", "tao": "win_fistpump", "kael": "win_fistpump"}
## Paired throw clips [attacker, victim] for grapplers; everyone else uses the shared pair.
const THROWS := {"ember": ["throw_hell_a", "thrown_hell_b"], "bastion": ["throw_takedown_a", "thrown_takedown_b"]}


## When each fall clip's body reaches the floor (seconds).
const FALL_LAND := {"fall_fly": 0.95, "fall_back": 1.0, "fall_sweep": 1.5, "fall_forward": 1.0, "knockdown": 1.2}


func _fall_clip() -> String:
	var n: String = {"fly": "fall_fly", "back": "fall_back", "sweep": "fall_sweep", "forward": "fall_forward"}.get(fall_kind, "fall_back")
	return n if ClipLib.has(n) else ""


static func throw_pair(f: Fighter) -> Array:
	var p: Array = THROWS.get(f.C.arch, []) if f != null else []
	if p.size() == 2 and ClipLib.has(p[0]) and ClipLib.has(p[1]): return p
	return ["throw", "thrown"]


## A fighter's own clips from their design (fight idle / select-screen pose / match intro), when present.
static func own_clip(C: Dictionary, key: String, fallback: String) -> String:
	var n: String = (C.get("person", {}) as Dictionary).get(key, "")
	return n if n != "" and ClipLib.has(n) else fallback


static func _len(n: String) -> float:
	var c: ClipLib.Clip = ClipLib.get_clip(n)
	return c.length if c != null else 1.0


## Which Mixamo clip (and time) fits the current state; "" keeps the keyframed poses.
func clip_request() -> Array:
	match state:
		"attack":
			if move != null and move.surge:
				var pa := own_clip(C, "power_anim", "")
				if pa != "":
					var c: ClipLib.Clip = ClipLib.get_clip(pa)
					var rel: float = c.hits[0].t if not c.hits.is_empty() else c.length * 0.45
					var tt := lerpf(maxf(0.0, rel - 0.6), rel, float(sf) / maxf(1.0, move.s)) if sf < move.s \
						else lerpf(rel, minf(c.length, rel + 0.8), clampf(float(sf - move.s) / maxf(1.0, move.end - move.s), 0.0, 1.0))
					return [pa, tt]
			var d = MoveClips.info(move)
			if d == null: return ["", 0.0]
			return [d.clip, MoveClips.time_at(d, move, sf), d.mirror]
		"crouch":
			return ["crouch_idle", fmod(anim_t, _len("crouch_idle"))]
		"idle":
			var ic: String = own_clip(C, "intro", INTRO.get(C.arch, ""))
			if G.phase == "intro" and ClipLib.has(ic):
				# fit the clip into the intro, never slower than real time
				var el := float(G.INTRO_FRAMES - G.phase_t) / 60.0
				return [ic, minf(el * maxf(1.0, _len(ic) / 2.4), _len(ic))]
			var n := own_clip(C, "idle", idle_clip(C.arch))
			return [n, fmod(anim_t, _len(n))]
		# walking clips follow the distance actually covered (walk_ph grows with it), so feet don't slide:
		# one loop of step_forward ~ 0.55 m of travel, step_back ~ 0.45 m
		"walkf":
			return ["step_forward", fposmod(absf(walk_ph) / (0.55 * 8.33) * _len("step_forward"), _len("step_forward"))]
		"walkb":
			return ["step_back", fposmod(absf(walk_ph) / (0.45 * 9.17) * _len("step_back"), _len("step_back"))]
		"dash":
			return ["step_long", minf(sf / 14.0, 1.0) * _len("step_long")]
		"run":
			# the run clip follows the distance covered: one loop ~ 2.2 m
			return ["m_run", fposmod(absf(walk_ph) / 11.0 * _len("m_run"), _len("m_run"))] if ClipLib.has("m_run") else ["", 0.0]
		"bdash":
			return ["step_back_b", minf(sf / 18.0, 1.0) * _len("step_back_b")]
		"side":
			var n := "strafe_left" if side_dir * (1 if side == 0 else -1) > 0 else "strafe_right"
			return [n, minf(sf / 16.0, 1.0) * _len(n)]
		"block":
			if crouch_block: return ["", 0.0]
			return ["block", minf(sf / 20.0, 1.0) * _len("block") * 0.45]
		"hit":
			if hit_crouch: return ["", 0.0]
			var n := "hit_heavy" if stun > 26 else ("hit_body" if hit_lvl != "high" else ("hit_head" if combo_hits % 2 == 1 else "hit_head_side"))
			return [n, minf(float(sf) / maxf(1.0, stun), 1.0) * _len(n) * 0.65]
		"air":
			var fc := _fall_clip()
			if fc == "": return ["", 0.0]
			var land: float = FALL_LAND.get(fc, 1.0)
			return [fc, minf(float(sf) / maxf(8.0, air_est), 0.92) * land]
		"down", "ko":
			if slammed > 0 and thrower != null and thrower.tm != null and not throw_set(thrower.tm).is_empty():
				var ts := throw_set(thrower.tm)
				if ts.has("lift"): return ["fall_fly", FALL_LAND.fall_fly + minf(sf / 30.0, 1.0) * 0.5]
				return [ts.b, lerpf(ts.b0, ts.b1, clampf(float(thrower.sf) / thrower.throw_dur(), 0.0, 1.0))]
			var fd := _fall_clip()
			if fd != "": return [fd, lerpf(float(FALL_LAND.get(fd, 1.0)) * 0.92, minf(_len(fd), float(FALL_LAND.get(fd, 1.0)) + 0.8), minf(sf / 14.0, 1.0))]
			if state == "ko": return ["ko", lerpf(0.78, 1.0, minf(sf / 20.0, 1.0)) * _len("ko")]
			return ["knockdown", lerpf(0.72, 1.0, minf(sf / 12.0, 1.0)) * _len("knockdown")]
		"getup":
			# the agile styles kip up now and then
			if C.arch in ["sora", "lio", "mara", "tao"] and ClipLib.has("getup_kip") and (int(max_hp) + side + combo_dmg) % 2 == 0:
				return ["getup_kip", lerpf(0.3, 1.9, minf(sf / 22.0, 1.0))]
			return ["getup_quick", minf(sf / 22.0, 1.0) * _len("getup_quick")]
		"throwing":
			var ts := throw_set(tm)
			if ts.is_empty() or tm.throw_type == "knees": return ["", 0.0]
			return [ts.a, lerpf(ts.a0, ts.a1, clampf(float(sf) / throw_dur(), 0.0, 1.0))]
		"thrown":
			if thrower == null or thrower.tm == null: return ["", 0.0]
			var ts := throw_set(thrower.tm)
			if ts.is_empty() or thrower.tm.throw_type == "knees": return ["", 0.0]
			return [ts.b, lerpf(ts.b0, ts.b1, clampf(float(thrower.sf) / thrower.throw_dur(), 0.0, 1.0))]
		"final":
			var sg := _final_seg(sf)
			var u := clampf(float(sf - int(sg.f0)) / maxf(1.0, float(int(sg.f1) - int(sg.f0))), 0.0, 1.0)
			return [sg.clip, lerpf(float(sg.t0), float(sg.t1), u)]
		"finaled":
			if thrower == null: return ["", 0.0]
			var plan := final_plan(thrower.C)
			if plan.fin_kind == "lift" and thrower.sf >= int(plan.fin_f0) + 20: return ["fall_fly", 0.35]   # held overhead
			if thrower.sf < FINAL_SUMMON and final_hit == 0: return ["v_big_stomach" if ClipLib.has("v_big_stomach") else "hit_heavy", minf(thrower.sf / 60.0, 1.2)]
			var rc: String = ["hit_head", "v_big_stomach", "hit_kidney", "v_stomach_upper"][final_hit % 4]
			if not ClipLib.has(rc): rc = "hit_heavy"
			return [rc, minf(float(thrower.sf - final_t) / 60.0 + 0.2, _len(rc) * 0.8)]
		"win":
			var n: String = WIN.get(C.arch, "")
			return [n, minf(sf / 60.0, _len(n))]
	return ["", 0.0]


var held_prop: Node3D


## Their intro prop (chai cup, phone, tablet...) sits in the right hand while the intro plays.
func _update_held_prop() -> void:
	var want: String = (C.get("person", {}) as Dictionary).get("intro_prop", "")
	var show: bool = want != "" and G.phase == "intro" and state == "idle"
	if show and held_prop == null:
		held_prop = PowerProps.build(want, C.accent)
		held_prop.scale = Vector3.ONE * 1.0
		G.add_child(held_prop)
	if held_prop != null:
		if not show:
			held_prop.queue_free(); held_prop = null
		else:
			held_prop.global_transform = rig.hand_xform(true).translated_local(Vector3(0, 0.07, 0))


func render(t: float) -> void:
	_update_held_prop()
	if rig.has_method("set_wear"): rig.set_wear(bruise, dirt, blood_on)
	if last_rt < 0.0: last_rt = t
	anim_t += clampf(t - last_rt, 0.0, 0.1)
	last_rt = t
	var cr := clip_request()
	# paired throws (e.g. a takedown) were authored with both fighters in one space: keep the hip motion,
	# and draw the victim at the thrower's spot and facing so the two halves line up
	var pair := false
	rig.set_clip(cr[0], cr[1], state != "air", cr[2] if cr.size() > 2 else false, pair)
	var a := Engine.get_physics_interpolation_fraction()
	var p := Pose.lerp_p(prev_disp, disp, a)
	rig.position = prev_pos.lerp(pos, a)
	rig.rotation.y = lerp_angle(prev_face, face, a)
	if pair and state == "thrown" and thrower != null:
		rig.position = thrower.prev_pos.lerp(thrower.pos, a)
		rig.rotation.y = lerp_angle(thrower.prev_face, thrower.face, a)
	if state in ["walkf", "walkb", "dash"]:
		# Step cycle: legs swing, knees lift on the passing leg, hips sway, torso counter-rotates, arms pump.
		var s := sin(walk_ph)
		var c := cos(walk_ph)
		var amp := 1.3 if state == "dash" else 1.0
		p[Pose.LHX] += s * 0.34 * amp; p[Pose.RHX] -= s * 0.34 * amp
		p[Pose.LK] += maxf(0.0, -c) * 0.45 * amp; p[Pose.RK] += maxf(0.0, c) * 0.45 * amp
		p[Pose.HIP_Y] += absf(c) * 0.022 - 0.012
		p[Pose.HIP_YAW] += s * 0.1
		p[Pose.TORSO_Y] -= s * 0.12
		p[Pose.TORSO_Z] += c * 0.03
		p[Pose.LSX] -= s * 0.12; p[Pose.RSX] += s * 0.12
	elif state == "idle":
		Idle.apply(C.arch, p, t + side * 0.9)
	rig.apply_pose(p, not (state in ["air", "thrown", "down", "ko", "getup", "jump"]) and not airborne())
	rig.set_flash(flash * 0.8)
	rig.set_face("angry" if state in ["attack", "throwing", "dash", "run"] else "sad" if state in ["hit", "air", "down", "ko", "thrown"] \
		else "happy" if state == "win" else "surprised" if state == "block" else "neutral")
	if C.has("boss_form"):
		rig.set_glow(1.6 + sin(t * 5.0) * 0.6)   # boss aura
	else:
		rig.set_glow(1.3 + sin(t * 12.0) * 0.8 if meter >= 100.0 else 0.9)
