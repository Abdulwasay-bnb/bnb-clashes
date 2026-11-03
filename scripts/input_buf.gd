class_name InputBuf
extends RefCounted
## Turns raw stick + button state into per-frame events (dash taps, sidestep taps, presses).
## Directions use numpad notation relative to the fighter: 6 = toward opponent, 4 = away, 2 = down.

class Frame:
	var dir := 5
	var pressed := 0
	var held := 0
	var ff_now := false
	var ff_recent := false
	var bb_now := false
	var up_tap := false
	var down_tap := false
	var dn := false

static var NEUTRAL := Frame.new()

var f := 0
var prev_dir := 5
var prev_held := 0
var last6 := -99
var last4 := -99
var ff_at := -99
var down_at := -99


func frame(h: int, v: int, held: int) -> Frame:
	f += 1
	var o := Frame.new()
	o.dir = 5 + h + 3 * v
	o.held = held
	o.pressed = held & ~prev_held
	o.dn = o.dir <= 3
	if o.dir == 6 and prev_dir != 6:
		if f - last6 <= 14:
			o.ff_now = true
			ff_at = f
		last6 = f
	if o.dir == 4 and prev_dir != 4:
		if f - last4 <= 14:
			o.bb_now = true
		last4 = f
	if o.dir >= 7 and prev_dir < 7:
		o.up_tap = true
	var was_dn := prev_dir <= 3
	if o.dn and not was_dn:
		down_at = f
	if not o.dn and was_dn and f - down_at <= 8:
		o.down_tap = true
	o.ff_recent = f - ff_at <= 14
	prev_dir = o.dir
	prev_held = held
	return o
