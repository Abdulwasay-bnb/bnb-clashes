extends Node
## Placeholder: being built (Tumble Tuesday). Same contract as the party games:
## start(g, people, seed, slot, pass_play) / start_net(g, people, seed, slot, party, is_guest, pids) / stop(),
## signal finished, var autoplay, var stats; optional static tutorial_steps(variant) -> Array.

signal finished

var G
var autoplay := false
var stats := {}
var variant := ""
var layer: CanvasLayer


func start(g, people: Array, seed: int, slot := 0, pass_play := false) -> void:
	G = g
	layer = CanvasLayer.new()
	G.add_child(layer)
	var l := Label.new()
	l.text = "TUMBLE TUESDAY  ·  COMING SOON"
	l.add_theme_font_size_override("font_size", 48)
	l.position = Vector2(200, 300)
	layer.add_child(l)
	G.get_tree().create_timer(2.0).timeout.connect(func(): finished.emit())


func start_net(g, people: Array, seed: int, slot: int, party: Party, is_guest: bool, pids: Dictionary) -> void:
	start(g, people, seed, slot, false)


func stop() -> void:
	if layer != null: layer.queue_free()
	layer = null
