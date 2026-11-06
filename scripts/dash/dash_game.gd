extends Node
## Placeholder: being built. Contract: start(g, C) / stop(), signal finished, var autoplay, var stats.

signal finished

var G
var autoplay := false
var stats := {}
var layer: CanvasLayer


func start(g, C: Dictionary) -> void:
	G = g
	layer = CanvasLayer.new()
	G.add_child(layer)
	var l := Label.new()
	l.text = "DEADLINE DASH  ·  COMING SOON"
	l.add_theme_font_size_override("font_size", 48)
	l.position = Vector2(200, 300)
	layer.add_child(l)
	G.get_tree().create_timer(2.0).timeout.connect(func(): finished.emit())


func stop() -> void:
	if layer != null: layer.queue_free()
	layer = null
