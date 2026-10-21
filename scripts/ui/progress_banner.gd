extends Control

## A nonblocking, presentation-only queue. The owner decides milestone progress.
const DISPLAY_DURATION := 1.30
const REDUCED_DURATION := 1.05
const TRAVEL_MARGIN := 24.0
const L10n := preload("res://scripts/localization/game_locale.gd")

var _playfield := Rect2()
var _viewport_size := Vector2.ZERO
var _base_position := Vector2.ZERO
var _pending: Array[Dictionary] = []
var _percent := 0
var _progress := 0.0
var _reduced := false
var _paused := false
var _tween: Tween
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	visible = false
	var display_font := SystemFont.new()
	display_font.font_names = PackedStringArray(["Arial", "Microsoft YaHei", "sans-serif"])
	display_font.font_weight = 800
	_font = display_font

func _exit_tree() -> void:
	clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		queue_redraw()

func set_playfield(rect: Rect2, viewport_size: Vector2) -> void:
	_playfield = rect
	_viewport_size = viewport_size
	_layout_banner()

func show_milestone(percent: int, reduced_motion: bool = false) -> void:
	if percent not in [50, 90] or percent == _percent:
		return
	for item: Dictionary in _pending:
		if int(item["percent"]) == percent:
			return
	_pending.append({"percent": percent, "reduced": reduced_motion})
	if _percent == 0:
		_start_next()

func clear() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	_tween = null
	_pending.clear()
	_percent = 0
	_progress = 0.0
	visible = false
	modulate = Color.WHITE
	scale = Vector2.ONE
	rotation = 0.0
	queue_redraw()

func set_paused(paused: bool) -> void:
	if _paused == paused:
		return
	_paused = paused
	visible = _percent > 0 and not paused
	if is_instance_valid(_tween):
		if paused:
			_tween.pause()
		else:
			_tween.play()
	elif not paused and _percent == 0:
		_start_next()

func _start_next() -> void:
	if _paused or _pending.is_empty() or not is_inside_tree():
		return
	var item: Dictionary = _pending.pop_front()
	_percent = int(item["percent"])
	_reduced = bool(item["reduced"])
	_progress = 0.0
	visible = true
	_layout_banner()
	_tween = create_tween()
	if _reduced:
		_tween.tween_interval(REDUCED_DURATION)
	else:
		_tween.tween_method(_set_progress, 0.0, 1.0, DISPLAY_DURATION)
	_tween.tween_callback(_finish_current)

func _finish_current() -> void:
	_tween = null
	_percent = 0
	visible = false
	_start_next()

func _layout_banner() -> void:
	if _playfield.size.x <= 0.0 or _viewport_size.x <= 0.0:
		return
	var maximum_width := minf(500.0, minf(_playfield.size.x * 0.94, maxf(_viewport_size.x - 24.0, 1.0)))
	var width := clampf(_playfield.size.x * 0.76, minf(240.0, maximum_width), maximum_width)
	var height := minf(clampf(_playfield.size.x * 0.15, 42.0, 70.0), maxf(_playfield.size.x * 0.24, 28.0))
	size = Vector2(maxf(width, 1.0), height)
	_base_position = Vector2(_playfield.get_center().x - width * 0.5, _playfield.position.y + maxf(6.0, height * 0.10))
	pivot_offset = size * 0.5
	_apply_visuals()

func _set_progress(progress: float) -> void:
	_progress = progress
	_apply_visuals()

func _apply_visuals() -> void:
	if _reduced:
		position = _base_position
		rotation = 0.0
		modulate = Color.WHITE
		scale = Vector2.ONE
	else:
		# 50% drifts left-to-right, 90% sweeps back right-to-left, both fully
		# crossing the playfield like the reference banner instead of popping
		# in place. The offscreen endpoints keep entry and exit seamless.
		var t := clampf(_progress, 0.0, 1.0)
		var left := _playfield.position.x - size.x - TRAVEL_MARGIN
		var right := _playfield.end.x + TRAVEL_MARGIN
		var from_x := left if _percent == 50 else right
		var to_x := right if _percent == 50 else left
		position = Vector2(lerpf(from_x, to_x, t), _base_position.y - sin(t * PI) * minf(8.0, size.y * 0.12))
		rotation = sin(t * PI * 2.0) * 0.022 * (1.0 if _percent == 50 else -1.0)
		modulate = Color.WHITE
		scale = Vector2.ONE
	queue_redraw()

func _draw() -> void:
	if _percent == 0 or size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_ribbon()
	_draw_smiling_block()
	_draw_message()
	_draw_stars()

func _draw_ribbon() -> void:
	var width := size.x
	var height := size.y
	var tail := height * 0.32
	var top := height * 0.12
	var bottom := height * 0.88
	# Two folded tails and the warm gradient front are original vector shapes.
	draw_colored_polygon(PackedVector2Array([Vector2(0.0, top + 5.0), Vector2(tail * 1.5, top + 5.0), Vector2(tail * 1.5, bottom + 3.0), Vector2(0.0, bottom + 3.0), Vector2(tail * 0.28, height * 0.52)]), Color("#b83235"))
	draw_colored_polygon(PackedVector2Array([Vector2(width, top + 5.0), Vector2(width - tail * 1.5, top + 5.0), Vector2(width - tail * 1.5, bottom + 3.0), Vector2(width, bottom + 3.0), Vector2(width - tail * 0.28, height * 0.52)]), Color("#c6422a"))
	var left := tail * 0.65
	var right := width - left
	var corners := PackedVector2Array([Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)])
	var shadow := PackedVector2Array()
	for point in corners:
		shadow.append(point + Vector2(0.0, 3.0))
	draw_colored_polygon(shadow, Color(0.12, 0.04, 0.12, 0.32))
	draw_polygon(corners, PackedColorArray([Color("#ff8040"), Color("#ff9c3f"), Color("#e24b32"), Color("#e43b3d")]))
	draw_line(Vector2(left, top + 1.0), Vector2(right, top + 1.0), Color("#ffcb7d"), 1.4, true)
	draw_line(Vector2(left, bottom), Vector2(right, bottom), Color("#a82f2e"), 2.0, true)

func _draw_smiling_block() -> void:
	var side := size.y * 0.77
	var center := Vector2(size.y * 0.62, size.y * 0.47)
	var angle := 0.0 if _reduced else sin(_progress * PI * 2.0) * 0.045
	draw_set_transform(center, angle)
	var rect := Rect2(Vector2.ONE * -side * 0.5, Vector2.ONE * side)
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0.13, 0.05, 0.25, 0.30)
	shadow.set_corner_radius_all(int(side * 0.18))
	draw_style_box(shadow, Rect2(rect.position + Vector2(1.0, 3.0), rect.size))
	var block := StyleBoxFlat.new()
	block.bg_color = Color("#ad7df2")
	block.border_color = Color("#7546bb")
	block.set_border_width_all(2)
	block.set_corner_radius_all(int(side * 0.18))
	draw_style_box(block, rect)
	draw_line(rect.position + Vector2(side * 0.18, side * 0.13), rect.position + Vector2(side * 0.78, side * 0.13), Color("#dcc2ff"), maxf(1.5, side * 0.06), true)
	var eye_radius := maxf(1.6, side * 0.045)
	for direction in [-1.0, 1.0]:
		var eye := Vector2(direction * side * 0.16, -side * 0.055)
		draw_circle(eye, eye_radius, Color("#33204d"))
		draw_circle(eye + Vector2(-eye_radius * 0.25, -eye_radius * 0.35), eye_radius * 0.27, Color.WHITE)
		draw_circle(Vector2(direction * side * 0.31, side * 0.13), side * 0.065, Color(1.0, 0.60, 0.78, 0.55))
	draw_arc(Vector2(0.0, side * 0.06), side * 0.17, PI * 0.12, PI * 0.88, 16, Color("#523066"), maxf(1.4, side * 0.035), true)
	draw_set_transform(Vector2.ZERO)

func _draw_message() -> void:
	if _font == null:
		return
	var message := L10n.t("%d%% Done") % _percent
	var left := size.y * 1.10
	var right := size.x - size.y * 0.42
	var available := maxf(right - left, 1.0)
	var font_size := int(clampf(size.y * 0.53, 15.0, 39.0))
	while font_size > 10 and _font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > available:
		font_size -= 1
	var text_width := _font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var baseline := Vector2(left + (available - text_width) * 0.5, size.y * 0.50 + (_font.get_ascent(font_size) - _font.get_descent(font_size)) * 0.5)
	draw_string_outline(_font, baseline + Vector2(0.0, 1.0), message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, Color("#a63b2a"))
	draw_string(_font, baseline, message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color("#fff3a6"))

func _draw_stars() -> void:
	var strength := 1.0 if _reduced else minf(_progress * 8.0, 1.0) * (1.0 - clampf((_progress - 0.70) / 0.30, 0.0, 1.0))
	for index in range(7):
		var ratio := float(index) / 6.0
		var point := Vector2(lerpf(size.y * 0.26, size.x - size.y * 0.23, ratio), size.y * (0.08 if index % 2 == 0 else 0.91))
		if not _reduced:
			point += Vector2(sin(float(index) * 2.0) * 6.0, -_progress * 12.0)
		var radius := size.y * (0.048 if index % 3 == 0 else 0.032)
		var star := PackedVector2Array()
		for corner in range(8):
			var angle := -PI * 0.5 + float(corner) * PI * 0.25
			star.append(point + Vector2.from_angle(angle) * radius * (1.0 if corner % 2 == 0 else 0.30))
		draw_colored_polygon(star, Color(1.0, 0.91, 0.40, strength * 0.90))
