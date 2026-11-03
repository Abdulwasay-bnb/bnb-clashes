class_name LoadingScreen
extends CanvasLayer
## Full-screen loader shown while the game bakes animations, renders portraits or builds a fight.
## Heavy steps call progress() and then yield a frame, so the bar and spinner keep moving.

var bg: ColorRect
var logo: TextureRect
var bar: Control
var label: Label
var frac := 0.0
var shown := 0.0
var spin := 0.0


func _init() -> void:
	layer = 100
	bg = ColorRect.new()
	bg.color = Color(0.035, 0.039, 0.086)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	logo = TextureRect.new()
	logo.texture = load("res://assets/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.anchor_bottom = 0.78
	bg.add_child(logo)
	bar = Control.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.draw.connect(_draw_bar)
	bg.add_child(bar)
	label = Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.anchor_top = 0.86
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", load("res://assets/fonts/Rajdhani-Bold.ttf"))
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.67, 0.71, 0.85))
	bg.add_child(label)
	visible = false


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


## Size the backdrop to the visible screen (anchors alone don't resolve directly under a CanvasLayer).
func _fit() -> void:
	var r := get_viewport().get_visible_rect()
	bg.position = r.position
	bg.size = r.size


func open(text: String) -> void:
	frac = 0.0; shown = 0.0
	label.text = text
	visible = true
	bg.modulate.a = 1.0
	if is_inside_tree(): _fit()


func progress(text: String, f: float) -> void:
	label.text = text
	frac = clampf(f, 0.0, 1.0)


func close() -> void:
	frac = 1.0
	var tw := create_tween()
	tw.tween_property(bg, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func(): visible = false)


func _process(dt: float) -> void:
	if not visible: return
	shown = move_toward(shown, frac, dt * 2.5)
	spin += dt * 6.0
	bar.queue_redraw()


func _draw_bar() -> void:
	var s := bar.size
	var w := minf(s.x * 0.5, 560.0)
	var r := Rect2(Vector2((s.x - w) / 2, s.y * 0.8), Vector2(w, 6))
	bar.draw_rect(r, Color(1, 1, 1, 0.1))
	bar.draw_rect(Rect2(r.position, Vector2(w * shown, 6)), Color(0.24, 0.84, 1.0))
	# spinner, so a long single step still shows the game is alive
	var c := Vector2(r.position.x - 26, r.position.y + 3)
	bar.draw_arc(c, 10, spin, spin + 4.2, 24, Color(1.0, 0.24, 0.67), 3.0)
