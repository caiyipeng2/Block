class_name MoveFeedback
extends Control

## Visual-only snapshot while a move resolves. Decorative effects continue
## after finished so particle lifetime does not extend the input lock.
signal finished
signal shake_requested(strength: float, duration: float)
signal impact_requested(strength: float, duration: float)
signal target_arrived(kind: String, counted: bool)
signal collections_settled

const BlockArt = preload("res://scripts/ui/block_art.gd")
const CollectionFlights = preload("res://scripts/ui/collection_flights.gd")
const FinalImpact = preload("res://scripts/ui/final_impact.gd")
const ClearPraise = preload("res://scripts/ui/clear_praise.gd")
const GOLD := Color("#ffdc57")
const CYAN := Color("#a0f8ff")
const OUTLINE := Color("#182a71")
const FLASH_DURATION := 0.06
const SWEEP_DURATION := 0.10
const ACCENT_DURATION := 0.62
const SCORE_FLIGHT_DURATION := 0.58
const FINAL_LIFT_DURATION := 0.20
const FINAL_HOLD_DURATION := 0.07
const FINAL_SLAM_DURATION := 0.09
const FINAL_REBOUND_DURATION := 0.12
const FINAL_PEAK_SCALE := 1.95
const FINAL_PLACEMENT_DURATION := FINAL_LIFT_DURATION + FINAL_HOLD_DURATION + FINAL_SLAM_DURATION + FINAL_REBOUND_DURATION

var blocks_board: bool:
	get:
		return _board_overlay_active

var _busy := false
var _board_overlay_active := false
var _paused := false
var _tween: Tween
var _score_tween: Tween
var _accent_tween: Tween
var _overlay_visible := false

var _board_rect := Rect2()
var _board_offset := Vector2.ZERO
var _board_size := 0
var _cell_size := 0.0
var _cell_inset := 1.0
var _palette := PackedColorArray()
var _context: Dictionary = {}
var _cell_colors: Dictionary = {}
var _placed_cells: Dictionary = {}
var _clear_cells: Dictionary = {}
var _clear_colors: Dictionary = {}
var _clear_row_colors: Dictionary = {}
var _clear_column_colors: Dictionary = {}
var _target_cells: Dictionary = {}
var _collected_target_events: Array[Dictionary] = []
var _clear_rows: Array[int] = []
var _clear_columns: Array[int] = []
var _placed_scale := 1.0
var _clear_progress := 0.0
var _flash_progress := 0.0
var _sweep_progress := 0.0
var _clear_started := false
var _sweep_started := false
var _dispersing := false
var _gained := 0

var _rebound_piece: PieceData
var _rebound_from_origin := Vector2.ZERO
var _rebound_to_origin := Vector2.ZERO
var _rebound_from_unit := 0.0
var _rebound_to_unit := 0.0
var _rebound_from_inset := 1.0
var _rebound_to_inset := 1.0
var _rebound_color := Color.WHITE
var _rebound_progress := 0.0

var _score_label: Label
var _score_origin := Vector2.ZERO
var _score_target := Vector2.ZERO
var _collection_layer: Control
var _final_impact: Control
var _praise_layer: Control
var _final_move := false
var _final_piece_pivot := Vector2.ZERO
var _final_piece_scale := Vector2.ONE
var _final_piece_lift := 0.0
var _accent_progress := 0.0
var _particles: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_collection_layer()
	_ensure_final_impact()
	_ensure_praise_layer()

func is_busy() -> bool:
	return _busy

func set_board_offset(offset: Vector2) -> void:
	_board_offset = offset
	if is_instance_valid(_collection_layer):
		_collection_layer.set_board_offset(offset)
	if is_instance_valid(_final_impact):
		_final_impact.set_board_offset(offset)
	if is_instance_valid(_praise_layer):
		_praise_layer.set_board_offset(offset)
	queue_redraw()

func has_pending_collections() -> bool:
	return is_instance_valid(_collection_layer) and _collection_layer.has_pending_collections()

func finish_collections() -> void:
	if is_instance_valid(_collection_layer):
		_collection_layer.finish_collections()

func _ensure_collection_layer() -> void:
	if is_instance_valid(_collection_layer):
		return
	_collection_layer = CollectionFlights.new()
	_collection_layer.name = "CollectionFlights"
	_collection_layer.z_index = 2
	add_child(_collection_layer)
	_collection_layer.target_arrived.connect(_on_collection_target_arrived)
	_collection_layer.collections_settled.connect(_on_collections_settled)
	_collection_layer.set_paused(_paused)

func _on_collection_target_arrived(kind: String, counted: bool) -> void:
	target_arrived.emit(kind, counted)

func _on_collections_settled() -> void:
	collections_settled.emit()

func _ensure_final_impact() -> void:
	if is_instance_valid(_final_impact):
		return
	_final_impact = FinalImpact.new()
	_final_impact.name = "FinalImpact"
	_final_impact.z_index = 1
	add_child(_final_impact)
	_final_impact.set_paused(_paused)

func _ensure_praise_layer() -> void:
	if is_instance_valid(_praise_layer):
		return
	_praise_layer = ClearPraise.new()
	_praise_layer.name = "ClearPraise"
	_praise_layer.z_index = 3
	add_child(_praise_layer)
	_praise_layer.set_paused(_paused)

func play_move(
		before_board: BoardRules,
		placed_cells: Array[Vector2i],
		clear_cells: Array[Vector2i],
		placed_color: int,
		rect: Rect2,
		palette: PackedColorArray,
		durations: Vector2,
		gained: int,
		reduced_motion: bool,
		context: Dictionary = {}
	) -> void:
	reset_move()
	if before_board == null or before_board.size <= 0:
		_busy = true
		_finish()
		return
	_board_rect = rect
	_board_size = before_board.size
	_cell_size = _board_rect.size.x / float(_board_size)
	_cell_inset = float(context.get("cell_inset", 1.0))
	_palette = palette
	_context = context.duplicate()
	_final_move = bool(context.get("final_block", false)) and not reduced_motion and not placed_cells.is_empty()
	_clear_colors = context.get("clear_colors", {}).duplicate()
	_clear_row_colors = context.get("clear_row_colors", {}).duplicate()
	_clear_column_colors = context.get("clear_column_colors", {}).duplicate()
	_capture_target_context(context)
	_gained = gained
	_overlay_visible = true
	_board_overlay_active = true
	_placed_scale = 0.90
	for y in range(_board_size):
		for x in range(_board_size):
			var color_id := before_board.get_cell(x, y)
			if color_id >= 0:
				_cell_colors[Vector2i(x, y)] = color_id
	for coordinate in placed_cells:
		_placed_cells[coordinate] = true
		_cell_colors[coordinate] = placed_color
	for coordinate in clear_cells:
		_clear_cells[coordinate] = true
	_final_piece_pivot = _placed_bounds_center()
	_collect_clear_lines()
	_busy = true
	var placement_duration := FINAL_PLACEMENT_DURATION if _final_move else clampf(durations.x, 0.06, 0.14)
	_enqueue_collection_events(reduced_motion, placement_duration + FLASH_DURATION + SWEEP_DURATION)
	queue_redraw()
	if reduced_motion:
		if gained > 0 and not _is_collection_presentation():
			_start_score_float(true)
		_finish()
		return
	if _clear_cells.is_empty() and gained > 0 and not _is_collection_presentation():
		_start_score_float(false)
	# Ordinary moves block at most .50s. The last piece has a distinct .48s
	# lift-and-contact lead-in, followed by the same bounded clear phase.
	# durations.y includes the flash and sweep, not just fragment dispersion.
	var disperse_duration := clampf(durations.y - FLASH_DURATION - SWEEP_DURATION, 0.10, 0.20)
	_tween = create_tween()
	if _final_move:
		_placed_scale = 1.0
		_tween.tween_method(_set_final_lift, 0.0, 1.0, FINAL_LIFT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_interval(FINAL_HOLD_DURATION)
		_tween.tween_method(_set_final_slam, 0.0, 1.0, FINAL_SLAM_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tween.tween_callback(_begin_final_impact)
		_tween.tween_method(_set_final_squash, 0.0, 1.0, FINAL_REBOUND_DURATION * 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_final_settle, 0.0, 1.0, FINAL_REBOUND_DURATION * 0.60).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		_tween.tween_method(_set_placed_scale, 0.90, 1.06, placement_duration * 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_placed_scale, 1.06, 1.0, placement_duration * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	if not _clear_cells.is_empty():
		_tween.tween_callback(_begin_clear)
		_tween.tween_method(_set_flash_progress, 0.0, 1.0, FLASH_DURATION)
		_tween.tween_callback(_begin_sweep)
		_tween.tween_method(_set_sweep_progress, 0.0, 1.0, SWEEP_DURATION)
		_tween.tween_callback(_begin_dispersion)
		_tween.tween_method(_set_clear_progress, 0.0, 1.0, disperse_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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
		reduced_motion: bool,
		from_inset: float = 1.0,
		to_inset: float = 1.0
	) -> void:
	reset_move()
	if piece == null or piece.cells.is_empty():
		_busy = true
		_finish()
		return
	_rebound_piece = piece
	_rebound_from_origin = from_origin
	_rebound_to_origin = to_origin
	_rebound_from_unit = maxf(from_unit, 0.0)
	_rebound_to_unit = maxf(to_unit, 0.0)
	_rebound_from_inset = maxf(from_inset, 0.0)
	_rebound_to_inset = maxf(to_inset, 0.0)
	_rebound_color = color
	_overlay_visible = true
	_busy = true
	queue_redraw()
	if reduced_motion:
		_finish()
		return
	_tween = create_tween()
	_tween.tween_method(_set_rebound_progress, 0.0, 1.0, clampf(duration, 0.08, 0.30)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_finish)
	_apply_paused_state()

func reset() -> void:
	reset_move()
	if is_instance_valid(_collection_layer):
		_collection_layer.reset()

## Starting the next placement only clears its board snapshot and accents.
## Previously collected gems keep flying and retain their arrival callbacks.
func reset_move() -> void:
	if is_instance_valid(_final_impact):
		_final_impact.reset()
	if is_instance_valid(_praise_layer):
		_praise_layer.reset()
	for tween in [_tween, _score_tween, _accent_tween]:
		if tween != null:
			tween.kill()
	_tween = null
	_score_tween = null
	_accent_tween = null
	_remove_score_label()
	_busy = false
	_board_overlay_active = false
	_overlay_visible = false
	_board_offset = Vector2.ZERO
	_cell_colors.clear()
	_placed_cells.clear()
	_clear_cells.clear()
	_clear_colors.clear()
	_clear_row_colors.clear()
	_clear_column_colors.clear()
	_target_cells.clear()
	_collected_target_events.clear()
	_clear_rows.clear()
	_clear_columns.clear()
	_context.clear()
	_particles.clear()
	_rebound_piece = null
	_clear_progress = 0.0
	_flash_progress = 0.0
	_sweep_progress = 0.0
	_accent_progress = 0.0
	_clear_started = false
	_sweep_started = false
	_dispersing = false
	_rebound_progress = 0.0
	_final_move = false
	_final_piece_scale = Vector2.ONE
	_final_piece_lift = 0.0
	_final_piece_pivot = Vector2.ZERO
	queue_redraw()

func set_paused(paused: bool) -> void:
	_paused = paused
	if is_instance_valid(_collection_layer):
		_collection_layer.set_paused(paused)
	if is_instance_valid(_final_impact):
		_final_impact.set_paused(paused)
	if is_instance_valid(_praise_layer):
		_praise_layer.set_paused(paused)
	_apply_paused_state()

func _apply_paused_state() -> void:
	for tween in [_tween, _score_tween, _accent_tween]:
		if tween != null:
			if _paused:
				tween.pause()
			else:
				tween.play()

func _set_placed_scale(value: float) -> void:
	_placed_scale = value
	queue_redraw()

func _placed_bounds_center() -> Vector2:
	if _placed_cells.is_empty():
		return _board_rect.get_center()
	var first: Vector2i = _placed_cells.keys()[0]
	var minimum := first
	var maximum := first
	for key in _placed_cells:
		var coordinate: Vector2i = key
		minimum = Vector2i(mini(minimum.x, coordinate.x), mini(minimum.y, coordinate.y))
		maximum = Vector2i(maxi(maximum.x, coordinate.x), maxi(maximum.y, coordinate.y))
	return _board_rect.position + (Vector2(minimum + maximum) + Vector2.ONE) * _cell_size * 0.5

func _set_final_lift(progress: float) -> void:
	_final_piece_scale = Vector2.ONE * lerpf(1.0, FINAL_PEAK_SCALE, progress)
	_final_piece_lift = _cell_size * 0.62 * progress
	queue_redraw()

func _set_final_slam(progress: float) -> void:
	_final_piece_scale = Vector2.ONE * lerpf(FINAL_PEAK_SCALE, 1.0, progress)
	_final_piece_lift = _cell_size * 0.62 * (1.0 - progress)
	queue_redraw()

func _begin_final_impact() -> void:
	_final_piece_scale = Vector2(1.14, 0.86)
	_final_piece_lift = 0.0
	_ensure_final_impact()
	_final_impact.play(_final_piece_pivot, _board_rect, _cell_size)
	_final_impact.set_board_offset(_board_offset)
	# The owner also synchronizes the existing impact sound here. It decides
	# whether the dedicated camera impulse is enabled by the player settings.
	impact_requested.emit(8.0, 0.30)
	queue_redraw()

func _set_final_squash(progress: float) -> void:
	_final_piece_scale = Vector2(1.14, 0.86).lerp(Vector2(0.97, 1.045), progress)
	queue_redraw()

func _set_final_settle(progress: float) -> void:
	_final_piece_scale = Vector2(0.97, 1.045).lerp(Vector2.ONE, progress)
	queue_redraw()

func _set_flash_progress(value: float) -> void:
	_flash_progress = value
	queue_redraw()

func _set_sweep_progress(value: float) -> void:
	_sweep_progress = value
	queue_redraw()

func _set_clear_progress(value: float) -> void:
	_clear_progress = value
	queue_redraw()

func _set_rebound_progress(value: float) -> void:
	_rebound_progress = value
	queue_redraw()

func _begin_clear() -> void:
	_clear_started = true
	if _gained > 0 and not _is_collection_presentation():
		_start_score_float(false)
	if not _final_move and bool(_context.get("shake_enabled", true)):
		var line_count := maxi(int(_context.get("clear_lines", _clear_rows.size() + _clear_columns.size())), 1)
		shake_requested.emit(minf(1.6 + float(line_count) * 0.65, 4.8), minf(0.14 + float(line_count) * 0.025, 0.24))
	queue_redraw()

func _begin_sweep() -> void:
	_sweep_started = true
	queue_redraw()

func _begin_dispersion() -> void:
	_dispersing = true
	_spawn_particles()
	_start_combo()
	_accent_tween = create_tween()
	_accent_tween.tween_method(_set_accent_progress, 0.0, 1.0, ACCENT_DURATION)
	_accent_tween.tween_callback(_end_accents)
	_apply_paused_state()

func _finish() -> void:
	if not _busy:
		return
	_tween = null
	_busy = false
	_board_overlay_active = false
	_overlay_visible = false
	_rebound_piece = null
	queue_redraw()
	# Owner restores its board now, while nonblocking accent tweens continue.
	finished.emit()

func _collect_clear_lines() -> void:
	var row_counts: Dictionary = {}
	var column_counts: Dictionary = {}
	for key in _clear_cells:
		var cell: Vector2i = key
		row_counts[cell.y] = int(row_counts.get(cell.y, 0)) + 1
		column_counts[cell.x] = int(column_counts.get(cell.x, 0)) + 1
	for row in row_counts:
		if int(row_counts[row]) == _board_size:
			_clear_rows.append(int(row))
	for column in column_counts:
		if int(column_counts[column]) == _board_size:
			_clear_columns.append(int(column))

func _score_anchor() -> Vector2:
	var coordinates := _clear_cells if not _clear_cells.is_empty() else _placed_cells
	if coordinates.is_empty():
		return _board_rect.get_center()
	var result := Vector2.ZERO
	for key in coordinates:
		var coordinate: Vector2i = key
		result += _cell_center(coordinate)
	return result / float(coordinates.size())

func _is_collection_presentation() -> bool:
	return str(_context.get("objective_type", "")) == "collect" or not bool(_context.get("score_flight_enabled", true))

func _start_score_float(static_text: bool) -> void:
	_score_label = _make_effect_label("+%d" % _gained, clampi(int(_cell_size * 0.55), 22, 38), GOLD, 4)
	_score_origin = _score_anchor() + Vector2(0.0, -_cell_size * 0.30)
	_score_target = _context.get("score_target", Vector2(_board_rect.get_center().x, maxf(_board_rect.position.y - 54.0, 28.0)))
	if not bool(_context.get("score_flight_enabled", true)):
		_score_target = _score_origin + Vector2(0.0, -32.0)
	_score_label.position = _score_origin - _score_label.get_minimum_size() * 0.5
	_score_tween = create_tween()
	if static_text:
		_score_tween.tween_interval(0.35)
		_score_tween.tween_property(_score_label, "modulate:a", 0.0, 0.20)
	else:
		_score_tween.tween_interval(0.10)
		_score_tween.tween_method(_set_score_progress, 0.0, 1.0, SCORE_FLIGHT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_score_tween.tween_callback(_end_score_float)
	_apply_paused_state()

func _set_score_progress(progress: float) -> void:
	if not is_instance_valid(_score_label):
		return
	var center := _score_origin.lerp(_score_target, progress)
	center.y -= sin(progress * PI) * minf(_cell_size * 0.85, 48.0)
	_score_label.scale = Vector2.ONE * lerpf(1.0, 0.62, progress)
	_score_label.position = center - _score_label.get_minimum_size() * _score_label.scale * 0.5
	_score_label.modulate.a = 1.0 - clampf((progress - 0.80) / 0.20, 0.0, 1.0)

func _end_score_float() -> void:
	_score_tween = null
	_remove_score_label()

func _remove_score_label() -> void:
	if is_instance_valid(_score_label):
		_score_label.hide()
		_score_label.queue_free()
	_score_label = null

func _make_effect_label(text: String, font_size: int, color: Color, outline_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.08, 0.25, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 4)
	add_child(label)
	return label

func _start_combo() -> void:
	var combo := int(_context.get("combo", 0))
	var line_count := int(_context.get("clear_lines", _clear_rows.size() + _clear_columns.size()))
	if line_count < 1:
		return
	var targets: Array[Vector2] = []
	for key in _target_cells:
		var coordinate: Vector2i = key
		if not _clear_cells.has(coordinate):
			targets.append(_cell_center(coordinate))
	_ensure_praise_layer()
	# Final Block belongs exclusively to the contact helper. Delay follow-up
	# praise until its title has faded; board busy and collection timings stay
	# unchanged, and the displayed combo is always the real rule result.
	_praise_layer.play(combo, line_count, _score_anchor(), _board_rect, _cell_size, targets, 0.32 if _final_move else 0.0, _final_move)

func _set_accent_progress(progress: float) -> void:
	_accent_progress = progress
	queue_redraw()

func _end_accents() -> void:
	_accent_tween = null
	_particles.clear()
	queue_redraw()

func _spawn_particles() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = Time.get_ticks_usec()
	var budget := 144
	for key in _clear_cells:
		var cell: Vector2i = key
		var color := _color_for_id(_resolved_cell_color_id(cell))
		for i in range(3):
			if _particles.size() >= budget:
				return
			var velocity := Vector2(random.randf_range(-1.0, 1.0), random.randf_range(-1.5, -0.2)) * _cell_size * random.randf_range(1.4, 2.6)
			_particles.append({
				"origin": _cell_center(cell) + Vector2(random.randf_range(-0.2, 0.2), random.randf_range(-0.2, 0.2)) * _cell_size,
				"velocity": velocity,
				"size": random.randf_range(0.055, 0.12) * _cell_size,
				"color": GOLD if i == 2 else color.lightened(0.24),
				"star": i == 2,
				"rotation": random.randf_range(0.0, TAU)
			})

func _draw() -> void:
	if _overlay_visible:
		if _rebound_piece != null:
			_draw_rebound()
		elif _board_size > 0 and _cell_size > 0.0:
			var whole_piece := _final_move and not _clear_started
			# Use the resting board's row order, including newly placed cells.
			for y in range(_board_size):
				for x in range(_board_size):
					var coordinate := Vector2i(x, y)
					if not _cell_colors.has(coordinate):
						continue
					if whole_piece and _placed_cells.has(coordinate):
						continue
					var alpha := 1.0
					var block_scale := 1.0
					var highlight := 0.0
					if _clear_started and _clear_cells.has(coordinate):
						highlight = 0.70 if _sweep_started else sin(_flash_progress * PI) * 0.95
						if _dispersing:
							alpha = 1.0 - _clear_progress
							block_scale = lerpf(1.0, 0.32, _clear_progress)
					elif _placed_cells.has(coordinate):
						block_scale = _placed_scale
					_draw_board_cell(coordinate, _color_for_id(_resolved_cell_color_id(coordinate)), block_scale, alpha, highlight)
			if whole_piece:
				_draw_final_piece()
			_draw_clear_lines()
	_draw_particles()

func _draw_final_piece() -> void:
	# Transform the whole piece once: both tile sizes and their spacing follow
	# the same pivot. Other occupied cells use the untouched shared grid path.
	var pivot := _final_piece_pivot + _board_offset
	var transform_origin := pivot - pivot * _final_piece_scale - Vector2(0.0, _final_piece_lift)
	draw_set_transform(transform_origin, 0.0, _final_piece_scale)
	for y in range(_board_size):
		for x in range(_board_size):
			var coordinate := Vector2i(x, y)
			if _placed_cells.has(coordinate):
				_draw_board_cell(coordinate, _color_for_id(int(_cell_colors[coordinate])), 1.0, 1.0, 0.12)
	draw_set_transform(Vector2.ZERO)

func _draw_board_cell(coordinate: Vector2i, color: Color, block_scale: float, alpha: float, highlight: float) -> void:
	if coordinate.x < 0 or coordinate.y < 0 or coordinate.x >= _board_size or coordinate.y >= _board_size:
		return
	var cell_origin := _board_rect.position + _board_offset + Vector2(coordinate) * _cell_size
	var block_rect := BlockArt.grid_cell_rect(cell_origin, _cell_size, _cell_inset, block_scale)
	var lifted_target := _final_move and not _clear_started and _placed_cells.has(coordinate)
	if _target_cells.has(coordinate) and (not _clear_cells.has(coordinate) or lifted_target):
		BlockArt.draw_target_tile(self, block_rect, alpha, highlight, _target_kind(_target_cells[coordinate]))
	else:
		BlockArt.draw_block(self, block_rect, color, alpha, highlight)
	if _target_cells.has(coordinate):
		BlockArt.draw_target_marker(self, block_rect, alpha, 1.0, _target_kind(_target_cells[coordinate]))

func _enqueue_collection_events(reduced_motion: bool, launch_delay: float) -> void:
	if _collected_target_events.is_empty():
		return
	_ensure_collection_layer()
	var fallback_destination: Vector2 = _context.get("objective_target", Vector2(_board_rect.get_center().x, _board_rect.position.y - 50.0))
	var objective_targets: Dictionary = _context.get("objective_targets", {})
	_collection_layer.enqueue(_collected_target_events, _board_rect, _cell_size, objective_targets, fallback_destination, launch_delay, reduced_motion)

func _capture_target_context(context: Dictionary) -> void:
	var before_targets: Dictionary = context.get("target_cells", {})
	for cell in before_targets:
		if cell is Vector2i:
			_target_cells[cell] = _target_kind(before_targets[cell])
	# Typed events retain each collected kind even after the state removes it.
	# The old coordinate-only payload remains compatible through the snapshot.
	var events: Array = context.get("collected_target_events", [])
	if events.is_empty():
		events = context.get("collected_targets", [])
	var seen: Dictionary = {}
	for entry in events:
		var coordinate: Variant = entry.get("cell") if entry is Dictionary else entry
		if not coordinate is Vector2i or seen.has(coordinate):
			continue
		var kind := _target_kind(entry.get("kind", _target_cells.get(coordinate, "red_star"))) if entry is Dictionary else _target_kind(_target_cells.get(coordinate, "red_star"))
		var counted := bool(entry.get("counted", true)) if entry is Dictionary else true
		_collected_target_events.append({"cell": coordinate, "kind": kind, "counted": counted})
		seen[coordinate] = true

func _target_kind(value: Variant) -> String:
	return str(value) if value is String and value in ["red_star", "gold_gem", "blue_diamond", "yellow_star"] else "red_star"

func _draw_clear_lines() -> void:
	if not _clear_started or _dispersing:
		return
	for row in _clear_rows:
		var color := _color_for_id(int(_clear_row_colors[row])) if _clear_row_colors.has(row) else CYAN
		_draw_clear_line(Rect2(_board_rect.position + _board_offset + Vector2(0.0, row * _cell_size), Vector2(_board_rect.size.x, _cell_size)), true, color)
	for column in _clear_columns:
		var color := _color_for_id(int(_clear_column_colors[column])) if _clear_column_colors.has(column) else CYAN
		_draw_clear_line(Rect2(_board_rect.position + _board_offset + Vector2(column * _cell_size, 0.0), Vector2(_cell_size, _board_rect.size.y)), false, color)

func _draw_clear_line(line_rect: Rect2, horizontal: bool, color: Color) -> void:
	var flash_alpha := (1.0 - _flash_progress) * 0.62 if not _sweep_started else 0.18
	var flash_color := color.lightened(0.62)
	flash_color.a = flash_alpha
	draw_rect(line_rect, flash_color)
	if not _sweep_started:
		return
	var center := line_rect.position + (Vector2(line_rect.size.x * _sweep_progress, line_rect.size.y * 0.5) if horizontal else Vector2(line_rect.size.x * 0.5, line_rect.size.y * _sweep_progress))
	var beam_size := Vector2(_cell_size * 0.32, line_rect.size.y) if horizontal else Vector2(line_rect.size.x, _cell_size * 0.32)
	draw_rect(Rect2(center - beam_size * 0.5, beam_size), Color(1.0, 1.0, 1.0, 0.92))
	var start := Vector2(line_rect.position.x, line_rect.get_center().y) if horizontal else Vector2(line_rect.get_center().x, line_rect.position.y)
	var end := Vector2(line_rect.end.x, line_rect.get_center().y) if horizontal else Vector2(line_rect.get_center().x, line_rect.end.y)
	var glow_color := color.lightened(0.24)
	glow_color.a = 0.36
	draw_line(start, end, glow_color, 8.0, true)
	draw_line(start, end, Color(1.0, 1.0, 1.0, 0.88), 2.0, true)

func _draw_particles() -> void:
	var elapsed := _accent_progress * ACCENT_DURATION
	var alpha := pow(1.0 - _accent_progress, 1.3)
	for particle in _particles:
		var origin: Vector2 = particle["origin"]
		var velocity: Vector2 = particle["velocity"]
		var point := origin + _board_offset + velocity * elapsed + Vector2(0.0, _cell_size * 2.2 * elapsed * elapsed)
		var radius := float(particle["size"]) * (1.0 - _accent_progress * 0.65)
		var color: Color = particle["color"]
		color.a *= alpha
		if bool(particle["star"]):
			draw_circle(point, radius * 1.8, Color(color.r, color.g, color.b, color.a * 0.16))
			draw_line(point - Vector2(radius, 0.0), point + Vector2(radius, 0.0), color, 2.0, true)
			draw_line(point - Vector2(0.0, radius), point + Vector2(0.0, radius), color, 2.0, true)
			draw_circle(point, maxf(radius * 0.30, 0.3), Color(1.0, 1.0, 1.0, alpha))
		else:
			var angle := float(particle["rotation"]) + elapsed * 5.0
			var points := PackedVector2Array()
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				points.append(point + corner.rotated(angle) * radius)
			draw_colored_polygon(points, color)

func _draw_rebound() -> void:
	var origin := _rebound_from_origin.lerp(_rebound_to_origin, _rebound_progress)
	var unit := lerpf(_rebound_from_unit, _rebound_to_unit, _rebound_progress)
	var inset := lerpf(_rebound_from_inset, _rebound_to_inset, _rebound_progress)
	for local_cell in _rebound_piece.cells:
		var cell_rect := BlockArt.grid_cell_rect(origin + Vector2(local_cell) * unit, unit, inset)
		if _rebound_piece.targets.has(local_cell):
			var kind := _target_kind(_rebound_piece.targets[local_cell])
			BlockArt.draw_target_tile(self, cell_rect, 1.0, 0.0, kind)
			BlockArt.draw_target_marker(self, cell_rect, 1.0, 1.0, kind)
		else:
			BlockArt.draw_block(self, cell_rect, _rebound_color)

func _cell_center(coordinate: Vector2i) -> Vector2:
	return _board_rect.position + (Vector2(coordinate) + Vector2.ONE * 0.5) * _cell_size

func _resolved_cell_color_id(coordinate: Vector2i) -> int:
	var original := int(_cell_colors.get(coordinate, 0))
	if _clear_cells.has(coordinate):
		return int(_clear_colors.get(coordinate, original))
	return original

func _color_for_id(color_id: int) -> Color:
	if _palette.is_empty():
		return Color("#4e6af1")
	return _palette[posmod(color_id, _palette.size())]
