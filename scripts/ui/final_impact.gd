extends Control

## Short contact effect for the last committed piece. This layer owns no game
## state and does not keep input locked after the board animation completes.
const PINK := Color("#f374ff")
const GOLD := Color("#ffe66b")
const AQUA := Color("#8bfff1")
const DURATION := 0.56

var _tween: Tween
var _paused := false
var _active := false
var _progress := 0.0
var _center := Vector2.ZERO
var _board_rect := Rect2()
var _board_offset := Vector2.ZERO
var _cell_size := 1.0
var _label: Label
var _label_anchor := Vector2.ZERO
var _label_base_scale := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func play(center: Vector2, board_rect: Rect2, cell_size: float) -> void:
	reset()
	_center = center
	_board_rect = board_rect
	_cell_size = maxf(cell_size, 1.0)
	_active = true
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = "Final Block!"
	_label.add_theme_font_size_override("font_size", clampi(int(board_rect.size.x * 0.105), 24, 62))
	_label.add_theme_color_override("font_color", GOLD)
	_label.add_theme_color_override("font_outline_color", Color("#b531d5"))
	_label.add_theme_constant_override("outline_size", 7)
	_label.add_theme_color_override("font_shadow_color", Color("#5e1c91"))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 4)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Microsoft YaHei", "sans-serif"])
	font.font_weight = 800
	_label.add_theme_font_override("font", font)
	add_child(_label)
	var label_size := _label.get_minimum_size()
	_label_base_scale = minf(1.0, maxf(board_rect.size.x - 20.0, 1.0) / maxf(label_size.x, 1.0))
	var label_half := label_size * _label_base_scale * 0.5
	_label.pivot_offset = label_size * 0.5
	_label_anchor = center + Vector2(0.0, _cell_size * 0.18)
	_label_anchor.x = clampf(_label_anchor.x, board_rect.position.x + label_half.x + 6.0, maxf(board_rect.position.x + label_half.x + 6.0, board_rect.end.x - label_half.x - 6.0))
	_label_anchor.y = clampf(_label_anchor.y, board_rect.position.y + label_half.y + 12.0, maxf(board_rect.position.y + label_half.y + 12.0, board_rect.end.y - label_half.y - 6.0))
	_update_progress(0.0)
	_tween = create_tween()
	_tween.tween_method(_update_progress, 0.0, 1.0, DURATION)
	_tween.tween_callback(_end)
	_apply_pause()

func set_board_offset(offset: Vector2) -> void:
	_board_offset = offset
	_position_label()
	queue_redraw()

func set_paused(paused: bool) -> void:
	_paused = paused
	_apply_pause()

func reset() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if is_instance_valid(_label):
		_label.hide()
		_label.queue_free()
	_label = null
	_active = false
	_progress = 0.0
	_board_offset = Vector2.ZERO
	queue_redraw()

func _end() -> void:
	_tween = null
	reset()

func _apply_pause() -> void:
	if _tween != null:
		if _paused:
			_tween.pause()
		else:
			_tween.play()

func _update_progress(value: float) -> void:
	_progress = value
	if is_instance_valid(_label):
		var pop := clampf(value / 0.18, 0.0, 1.0)
		_label.scale = Vector2.ONE * _label_base_scale * (0.60 + 0.40 * sin(pop * PI * 0.5) + 0.08 * sin(pop * PI))
		_label.modulate.a = 1.0 - clampf((value - 0.68) / 0.32, 0.0, 1.0)
	_position_label()
	queue_redraw()

func _position_label() -> void:
	if is_instance_valid(_label):
		_label.position = _label_anchor + _board_offset - _label.get_minimum_size() * 0.5

func _draw() -> void:
	if not _active:
		return
	var center := _center + _board_offset
	var fade := pow(1.0 - _progress, 1.35)
	var flash := 1.0 - clampf(_progress / 0.20, 0.0, 1.0)
	# Contact light is local to the piece, with a brief white core.
	draw_circle(center, _cell_size * (0.75 + _progress * 1.2), Color(PINK.r, PINK.g, PINK.b, flash * 0.20))
	draw_circle(center, _cell_size * 0.58, Color(1.0, 0.91, 1.0, flash * 0.40))
	for beam in range(8):
		var angle := float(beam) * TAU / 8.0 + 0.12
		var length := _cell_size * (1.35 + float(beam % 3) * 0.48 + _progress * 1.0)
		var tip := center + Vector2(cos(angle), sin(angle) * 0.65) * length
		var wing := Vector2(-sin(angle), cos(angle)) * _cell_size * 0.16
		draw_polygon(PackedVector2Array([center, tip + wing, tip - wing]), PackedColorArray([
			Color(1.0, 0.88, 1.0, fade * 0.30), Color(PINK.r, PINK.g, PINK.b, 0.0), Color(PINK.r, PINK.g, PINK.b, 0.0)
		]))
	_draw_ring(center, _progress, PINK)
	if _progress >= 0.12:
		_draw_ring(center, clampf((_progress - 0.12) / 0.88, 0.0, 1.0), GOLD)
	# Pink rays and gold stars spread from contact; deterministic positions avoid
	# allocating a new particle system for a single short final placement.
	for index in range(18):
		var angle := float(index) * 2.399963
		var direction := Vector2(cos(angle), sin(angle) * 0.64)
		var reach := _cell_size * (0.40 + float(index % 4) * 0.40 + _progress * 2.4)
		var point := center + direction * reach
		var radius := _cell_size * (0.055 + float(index % 3) * 0.018) * (1.0 - _progress * 0.65)
		var tint := GOLD if index % 3 == 0 else PINK
		if index % 3 == 0:
			var star := PackedVector2Array()
			for corner in range(8):
				var star_radius := radius if corner % 2 == 0 else radius * 0.30
				star.append(point + Vector2.from_angle(float(corner) * PI * 0.25 + angle + _progress) * star_radius)
			draw_colored_polygon(star, Color(tint.r, tint.g, tint.b, fade))
		else:
			var tail := point - direction * _cell_size * (0.25 + _progress * 0.20)
			draw_line(tail, point, Color(tint.r, tint.g, tint.b, fade * 0.72), maxf(1.0, _cell_size * 0.025), true)
	_draw_frame_sweep(fade)

func _draw_ring(center: Vector2, progress: float, color: Color) -> void:
	var radius := _cell_size * (0.62 + progress * 2.8)
	var alpha := pow(1.0 - progress, 1.6) * 0.70
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(center + Vector2(cos(angle), sin(angle) * 0.57) * radius)
	draw_polyline(points, Color(color.r, color.g, color.b, alpha * 0.22), maxf(3.0, _cell_size * 0.11), true)
	draw_polyline(points, Color(color.r, color.g, color.b, alpha), maxf(1.0, _cell_size * 0.035), true)

func _draw_frame_sweep(fade: float) -> void:
	var rect := Rect2(_board_rect.position + _board_offset, _board_rect.size).grow(3.0)
	draw_rect(rect, Color(AQUA.r, AQUA.g, AQUA.b, fade * 0.28), false, 2.0)
	var perimeter := (rect.size.x + rect.size.y) * 2.0
	for pulse in range(2):
		var head := fposmod(_progress * 1.35 + float(pulse) * 0.5, 1.0)
		for segment in range(12):
			var from := head - float(segment) * 0.012
			var to := from - 0.012
			var tint := GOLD if pulse == 0 else AQUA
			var alpha := fade * (1.0 - float(segment) / 12.0) * 0.90
			draw_line(_frame_point(rect, fposmod(from, 1.0) * perimeter), _frame_point(rect, fposmod(to, 1.0) * perimeter), Color(tint.r, tint.g, tint.b, alpha), 3.0, true)

func _frame_point(rect: Rect2, distance: float) -> Vector2:
	if distance <= rect.size.x:
		return rect.position + Vector2(distance, 0.0)
	distance -= rect.size.x
	if distance <= rect.size.y:
		return Vector2(rect.end.x, rect.position.y + distance)
	distance -= rect.size.y
	if distance <= rect.size.x:
		return rect.end - Vector2(distance, 0.0)
	distance -= rect.size.x
	return Vector2(rect.position.x, rect.end.y - distance)
