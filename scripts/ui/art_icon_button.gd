extends Button

## Native focus, shortcuts and tooltips are retained beneath vector icons.
const Art := preload("res://scripts/ui/block_art.gd")

@export var icon_kind: String = "pause":
	set(value):
		icon_kind = value
		queue_redraw()
@export var icon_color: Color = Color("#d8ecff"):
	set(value):
		icon_color = value
		queue_redraw()
@export var fill_color: Color = Color("#253b68"):
	set(value):
		fill_color = value
		if is_inside_tree():
			_apply_theme()
@export var frameless: bool = false:
	set(value):
		frameless = value
		if is_inside_tree():
			_apply_theme()
		else:
			queue_redraw()
@export var icon_scale: float = 0.55:
	set(value):
		icon_scale = clampf(value, 0.2, 1.0)
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = custom_minimum_size.max(Vector2(48.0, 48.0))
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = ""
	_apply_theme()
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func _draw() -> void:
	var color := icon_color
	if disabled:
		color.a *= 0.38
	elif is_hovered():
		color = color.lightened(0.12)
	var side := minf(size.x, size.y) * icon_scale
	var offset := Vector2(0.0, 1.5) if is_pressed() else Vector2.ZERO
	Art.draw_icon(self, icon_kind, Rect2((size - Vector2.ONE * side) * 0.5 + offset, Vector2.ONE * side), color)

func _apply_theme() -> void:
	if frameless:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		queue_redraw()
		return
	add_theme_stylebox_override("normal", Art.button_style(fill_color))
	add_theme_stylebox_override("hover", Art.button_style(fill_color.lightened(0.10)))
	add_theme_stylebox_override("pressed", Art.button_style(fill_color, true))
	add_theme_stylebox_override("disabled", Art.button_style(Color(fill_color.r, fill_color.g, fill_color.b, 0.55), true))
	var focus := Art.panel_style(Color.TRANSPARENT, 12, Color("#82f5e9"))
	focus.set_border_width_all(2)
	add_theme_stylebox_override("focus", focus)
	queue_redraw()
