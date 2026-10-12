class_name MoveFeedback
extends Control

## Visual-only feedback layer for a single move or a tray-piece rebound.
## The owning screen remains responsible for committing the game state and
## restoring the normal board after `finished` is emitted.

signal finished

var blocks_board: bool:
	get:
		return _board_overlay_active

var _busy := false
var _board_overlay_active := false
var _paused := false
var _tween: Tween
var _score_tween: Tween
var _overlay_visible := false

var _board_rect := Rect2()
var _board_size := 0
var _cell_size := 0.0
var _palette := PackedColorArray()
var _cell_colors: Dictionary = {}
var _placed_cells: Dictionary = {}
var _clear_cells: Dictionary = {}
var _placed_scale := 1.0
var _clear_progress := 0.0
var _clear_started := false

var _rebound_piece: PieceData
var _rebound_from_origin := Vector2.ZERO
var _rebound_to_origin := Vector2.ZERO
var _rebound_from_unit := 0.0
var _rebound_to_unit := 0.0
var _rebound_color := Color.WHITE
var _rebound_progress := 0.0

var _score_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func is_busy() -> bool:
	return _busy

func play_move(
		before_board: BoardRules,
		placed_cells: Array[Vector2i],
		clear_cells: Array[Vector2i],
		placed_color: int,
		rect: Rect2,
		palette: PackedColorArray,
		durations: Vector2,
		gained: int,
		reduced_motion: bool
	) -> void:
	reset()
	if before_board == null or before_board.size <= 0:
		_busy = true
		_finish()
		return

	_board_rect = rect
	_board_size = before_board.size
	_cell_size = _board_rect.size.x / float(_board_size)
	_palette = palette
	_cell_colors.clear()
	_placed_cells.clear()
	_clear_cells.clear()
	_overlay_visible = true
	_board_overlay_active = true
	_placed_scale = 0.82
	_clear_progress = 0.0
	_clear_started = false

	for y in range(_board_size):
		for x in range(_board_size):
			var color_id := before_board.get_cell(x, y)
			if color_id >= 0:
				_cell_colors[Vector2i(x, y)] = color_id

	for cell in placed_cells:
		var coordinate := Vector2i(cell)
		_placed_cells[coordinate] = true
		# A placed cell is one visual cell even when the source array repeats it.
		_cell_colors[coordinate] = placed_color

	for cell in clear_cells:
		_clear_cells[Vector2i(cell)] = true

	_busy = true
	queue_redraw()

	if reduced_motion:
		_placed_scale = 1.0
		_clear_progress = 1.0
		_finish()
		return
	if gained != 0:
		_start_score_float(gained, placed_cells, durations)

	var placement_duration := maxf(durations.x, 0.001)
	var clear_duration := maxf(durations.y, 0.001)
	_tween = create_tween()
	_tween.tween_method(_set_placed_scale, 0.82, 1.08, placement_duration * 0.7)
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_placed_scale, 1.08, 1.0, placement_duration * 0.3)
	if not _clear_cells.is_empty():
		_tween.tween_callback(_begin_clear)
		_tween.tween_method(_set_clear_progress, 0.0, 1.0, clear_duration)
		_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_finish)
	_apply_paused_state()

func play_rebound(
		piece: PieceData,
		from_origin: Vector2,
		to_origin: Vector2,
		from_unit: float,
		to_unit: float,
		color: Color,
		duration: float,
		reduced_motion: bool
	) -> void:
	reset()
	if piece == null or piece.cells.is_empty():
		_busy = true
		_finish()
		return

	_rebound_piece = piece
	_rebound_from_origin = from_origin
	_rebound_to_origin = to_origin
	_rebound_from_unit = maxf(from_unit, 0.0)
	_rebound_to_unit = maxf(to_unit, 0.0)
	_rebound_color = color
	_rebound_progress = 0.0
	_overlay_visible = true
	_board_overlay_active = false
	_busy = true
	queue_redraw()

	if reduced_motion:
		_rebound_progress = 1.0
		_finish()
		return

	_tween = create_tween()
	_tween.tween_method(_set_rebound_progress, 0.0, 1.0, maxf(duration, 0.001))
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_finish)
	_apply_paused_state()

func reset() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if _score_tween != null:
		_score_tween.kill()
		_score_tween = null
	if is_instance_valid(_score_label):
		_score_label.hide()
		_score_label.queue_free()
	_score_label = null
	_busy = false
	_board_overlay_active = false
	_overlay_visible = false
	_cell_colors.clear()
	_placed_cells.clear()
	_clear_cells.clear()
	_rebound_piece = null
	_clear_progress = 0.0
	_clear_started = false
	_rebound_progress = 0.0
	queue_redraw()

func set_paused(paused: bool) -> void:
	_paused = paused
	_apply_paused_state()

func _apply_paused_state() -> void:
	if _tween != null:
		if _paused:
			_tween.pause()
		else:
			_tween.play()
	if _score_tween != null:
		if _paused:
			_score_tween.pause()
		else:
			_score_tween.play()

func _set_placed_scale(value: float) -> void:
	_placed_scale = value
	queue_redraw()

func _begin_clear() -> void:
	_clear_started = true
	_clear_progress = 0.0
	queue_redraw()

func _set_clear_progress(value: float) -> void:
	_clear_progress = value
	queue_redraw()

func _set_rebound_progress(value: float) -> void:
	_rebound_progress = value
	queue_redraw()

func _finish() -> void:
	if not _busy:
		return
	if _tween != null:
		_tween = null
	_busy = false
	_board_overlay_active = false
	_overlay_visible = false
	queue_redraw()
	# The owner can safely restore its board in the finished callback.
	finished.emit()

func _start_score_float(gained: int, placed_cells: Array[Vector2i], durations: Vector2) -> void:
	_score_label = Label.new()
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_label.text = "+%d" % gained
	_score_label.add_theme_font_size_override("font_size", 24)
	_score_label.add_theme_color_override("font_color", Color("#ffe08a"))
	_score_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.1, 0.1, 0.8))
	_score_label.add_theme_constant_override("shadow_offset_x", 2)
	_score_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_score_label)
	var anchor := _board_rect.get_center()
	if not placed_cells.is_empty():
		anchor = Vector2.ZERO
		for cell in placed_cells:
			anchor += _cell_center(Vector2i(cell))
		anchor /= float(placed_cells.size())
	_score_label.position = anchor + Vector2(-_score_label.get_minimum_size().x * 0.5, -28.0)
	_score_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var float_duration := maxf(durations.x + durations.y, 0.45)
	_score_tween = create_tween()
	_score_tween.tween_property(_score_label, "position", _score_label.position + Vector2(0.0, -24.0), float_duration)
	_score_tween.parallel().tween_property(_score_label, "modulate:a", 0.0, float_duration)
	_score_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_score_tween.tween_callback(_end_score_float)
	_apply_paused_state()

func _end_score_float() -> void:
	_score_tween = null
	if is_instance_valid(_score_label):
		_score_label.hide()
		_score_label.queue_free()
	_score_label = null

func _draw() -> void:
	if not _overlay_visible:
		return
	if _rebound_piece != null:
		_draw_rebound()
		return
	if _board_size <= 0 or _cell_size <= 0.0:
		return
	for key in _cell_colors.keys():
		var coordinate: Vector2i = key
		var color_id: int = _cell_colors[key]
		var alpha := 1.0
		var block_scale := 1.0
		if _clear_started and _clear_cells.has(coordinate):
			alpha = 1.0 - _clear_progress
			block_scale = lerpf(1.0, 0.72, _clear_progress)
		elif _placed_cells.has(coordinate):
			block_scale = _placed_scale
		_draw_board_cell(coordinate, _color_for_id(color_id), block_scale, alpha)

func _draw_board_cell(coordinate: Vector2i, color: Color, block_scale: float, alpha: float) -> void:
	if coordinate.x < 0 or coordinate.y < 0 or coordinate.x >= _board_size or coordinate.y >= _board_size:
		return
	var source_rect := Rect2(_board_rect.position + Vector2(coordinate) * _cell_size, Vector2.ONE * _cell_size)
	var draw_size := Vector2(maxf(_cell_size - 4.0, 1.0), maxf(_cell_size - 4.0, 1.0)) * block_scale
	var draw_rect := Rect2(source_rect.get_center() - draw_size * 0.5, draw_size)
	var fill := Color(color.r, color.g, color.b, color.a * alpha)
	draw_style_box(_block_box(fill, 7), draw_rect)

func _draw_rebound() -> void:
	if _rebound_piece == null:
		return
	var progress := _rebound_progress
	var origin := _rebound_from_origin.lerp(_rebound_to_origin, progress)
	var unit := lerpf(_rebound_from_unit, _rebound_to_unit, progress)
	for local_cell in _rebound_piece.cells:
		var cell_rect := Rect2(origin + Vector2(local_cell) * unit + Vector2(2.0, 2.0), Vector2.ONE * maxf(unit - 4.0, 1.0))
		draw_style_box(_block_box(_rebound_color, 5), cell_rect)

func _cell_center(coordinate: Vector2i) -> Vector2:
	return _board_rect.position + (Vector2(coordinate) + Vector2.ONE * 0.5) * _cell_size

func _color_for_id(color_id: int) -> Color:
	if _palette.is_empty():
		return Color("#39c979")
	return _palette[posmod(color_id, _palette.size())]

func _block_box(fill: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.shadow_color = Color(0.15, 0.1, 0.2, 0.12 * fill.a)
	box.shadow_size = 4
	return box
