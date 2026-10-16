extends RefCounted

## Presentation only: the caller supplies the resolver's deduplicated clear mask.
## Cached geometry stays in cell coordinates so resizing never leaves a stale halo.

var _cell_colors: Dictionary = {}
var _row_colors: Dictionary = {}
var _column_colors: Dictionary = {}
var _palette := PackedColorArray()
var _board_size: int = 0
var _phase: float = 0.0
var _edges: Array[Dictionary] = []
var _joints: Dictionary = {}
var _spark_points: Array[Dictionary] = []

func configure(cell_colors: Dictionary, row_colors: Dictionary, column_colors: Dictionary, board_size: int, palette: PackedColorArray) -> void:
	if board_size <= 0 or cell_colors.is_empty():
		reset()
		return
	if board_size == _board_size and cell_colors == _cell_colors and row_colors == _row_colors and column_colors == _column_colors and palette == _palette:
		return
	_cell_colors = cell_colors.duplicate()
	_row_colors = row_colors.duplicate()
	_column_colors = column_colors.duplicate()
	_palette = palette.duplicate()
	_board_size = board_size
	_phase = 0.0
	_rebuild_geometry()

func reset() -> void:
	_cell_colors.clear()
	_row_colors.clear()
	_column_colors.clear()
	_palette.clear()
	_edges.clear()
	_joints.clear()
	_spark_points.clear()
	_board_size = 0
	_phase = 0.0

func advance(delta: float) -> void:
	if is_active() and is_finite(delta) and delta > 0.0:
		_phase = fposmod(_phase + delta, TAU * 20.0)

func is_active() -> bool:
	return _board_size > 0 and not _edges.is_empty()

func highlight(reduced_motion: bool) -> float:
	if not is_active():
		return 0.0
	return 0.29 if reduced_motion else 0.29 + sin(_phase * 0.85) * 0.018

func draw(canvas: CanvasItem, board_rect: Rect2, reduced_motion: bool, intensity: float = 1.0, show_sparks: bool = true) -> void:
	if not is_active() or board_rect.size.x <= 0.0 or board_rect.size.y <= 0.0:
		return
	var cell_size := board_rect.size / float(_board_size)
	var unit := minf(cell_size.x, cell_size.y)
	var breath := (1.0 if reduced_motion else 0.98 + sin(_phase * 0.85) * 0.02) * clampf(intensity, 0.0, 1.0)
	# Small opacity steps feather the bloom; the narrow rim carries the color.
	var halo_extent := minf(unit * 0.19, 11.5)
	_draw_layer(canvas, board_rect, cell_size, halo_extent, 0.008 * breath, 0.20, false, reduced_motion)
	_draw_layer(canvas, board_rect, cell_size, halo_extent * 0.83, 0.014 * breath, 0.20, false, reduced_motion)
	_draw_layer(canvas, board_rect, cell_size, halo_extent * 0.67, 0.022 * breath, 0.20, false, reduced_motion)
	_draw_layer(canvas, board_rect, cell_size, halo_extent * 0.52, 0.034 * breath, 0.20, false, reduced_motion)
	_draw_layer(canvas, board_rect, cell_size, halo_extent * 0.39, 0.047 * breath, 0.20, false, reduced_motion)
	_draw_layer(canvas, board_rect, cell_size, halo_extent * 0.28, 0.065 * breath, 0.20, false, reduced_motion)
	_draw_layer(canvas, board_rect, cell_size, halo_extent * 0.19, 0.090 * breath, 0.20, false, reduced_motion)
	_draw_layer(canvas, board_rect, cell_size, minf(unit * 0.020, 1.25), 0.48 * breath, 0.52, false, reduced_motion)
	var core_half_width := minf(unit * 0.025, clampf(unit * 0.007, 0.35, 0.50))
	_draw_layer(canvas, board_rect, cell_size, core_half_width, 0.78 * breath, 0.62, true, reduced_motion)
	if not reduced_motion and show_sparks and intensity > 0.0:
		_draw_sparks(canvas, board_rect, cell_size, unit, breath)

func _rebuild_geometry() -> void:
	_edges.clear()
	_joints.clear()
	_spark_points.clear()
	var edge_map: Dictionary = {}
	# Unit edges make the exact union outline, including a crossing's concave corners.
	for y in range(_board_size):
		for x in range(_board_size):
			var cell := Vector2i(x, y)
			if not _cell_colors.has(cell):
				continue
			var color_index: int = int(_cell_colors[cell])
			if not _cell_colors.has(cell + Vector2i.UP):
				_add_edge(edge_map, Vector3i(x, y, 0), color_index, true, Vector2.UP)
			if not _cell_colors.has(cell + Vector2i.DOWN):
				_add_edge(edge_map, Vector3i(x, y + 1, 0), color_index, true, Vector2.DOWN)
			if not _cell_colors.has(cell + Vector2i.LEFT):
				_add_edge(edge_map, Vector3i(x, y, 1), color_index, true, Vector2.LEFT)
			if not _cell_colors.has(cell + Vector2i.RIGHT):
				_add_edge(edge_map, Vector3i(x + 1, y, 1), color_index, true, Vector2.RIGHT)
	# Keep each line's outline visible inside the union. Shared edges are stored once.
	for y in range(_board_size):
		if not _row_colors.has(y):
			continue
		for x in range(_board_size):
			if _cell_colors.has(Vector2i(x, y)):
				_add_edge(edge_map, Vector3i(x, y, 0), int(_row_colors[y]), false)
				_add_edge(edge_map, Vector3i(x, y + 1, 0), int(_row_colors[y]), false)
	for x in range(_board_size):
		if not _column_colors.has(x):
			continue
		for y in range(_board_size):
			if _cell_colors.has(Vector2i(x, y)):
				_add_edge(edge_map, Vector3i(x, y, 1), int(_column_colors[x]), false)
				_add_edge(edge_map, Vector3i(x + 1, y, 1), int(_column_colors[x]), false)
	var outer_edges: Array[Dictionary] = []
	for key in edge_map:
		var edge: Dictionary = edge_map[key]
		_edges.append(edge)
		_add_joint(Vector2i(edge["a"]), edge)
		_add_joint(Vector2i(edge["b"]), edge)
		if bool(edge["outer"]):
			outer_edges.append(edge)
	for point in _joints:
		var joint: Dictionary = _joints[point]
		var directions: int = int(joint["directions"])
		joint["straight"] = directions == 3 or directions == 12
		joint["outline"] = _joint_outline(directions)
	if outer_edges.is_empty():
		return
	var spark_count := mini(4, maxi(2, floori(float(outer_edges.size()) * 0.13)))
	for index in range(spark_count):
		var edge_index := mini(int((float(index) + 0.35) * float(outer_edges.size()) / float(spark_count)), outer_edges.size() - 1)
		var edge: Dictionary = outer_edges[edge_index]
		var along := fposmod(float(index) * 0.61803398875 + 0.31, 1.0)
		var point: Vector2 = Vector2(edge["a"]).lerp(Vector2(edge["b"]), along)
		point += Vector2(edge["normal"]) * 0.12
		_spark_points.append({"point": point, "offset": float(index) * 2.39996323})

func _add_edge(edge_map: Dictionary, key: Vector3i, color_index: int, outer: bool, normal: Vector2 = Vector2.ZERO) -> void:
	if edge_map.has(key):
		return
	var start := Vector2(key.x, key.y)
	var end := start + (Vector2.RIGHT if key.z == 0 else Vector2.DOWN)
	edge_map[key] = {"a": start, "b": end, "color": color_index, "outer": outer, "normal": normal}

func _add_joint(point: Vector2i, edge: Dictionary) -> void:
	var joint: Dictionary = _joints.get(point, {"color": int(edge["color"]), "outer": false, "directions": 0})
	if bool(edge["outer"]):
		joint["color"] = int(edge["color"])
		joint["outer"] = true
	var direction: Vector2 = Vector2(edge["b"]) - Vector2(edge["a"])
	if Vector2(point) == Vector2(edge["b"]):
		direction = -direction
	var direction_bit := (1 if direction.x < 0.0 else 2) if direction.x != 0.0 else (4 if direction.y < 0.0 else 8)
	joint["directions"] = int(joint["directions"]) | direction_bit
	_joints[point] = joint

func _joint_outline(directions: int) -> PackedVector2Array:
	var corners := [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]
	var corner_masks := [5, 6, 10, 9]
	var arc_starts := [PI, PI * 1.5, 0.0, PI * 0.5]
	var points := PackedVector2Array()
	for index in range(4):
		if (directions & int(corner_masks[index])) != 0:
			points.append(corners[index])
			continue
		# Round only the quadrant without an outgoing edge, preserving exact joins.
		for step in range(4):
			var angle := float(arc_starts[index]) + float(step) * PI / 6.0
			points.append(Vector2(cos(angle), sin(angle)))
	return points

func _draw_layer(canvas: CanvasItem, board_rect: Rect2, cell_size: Vector2, half_width: float, opacity: float, inner_strength: float, white_core: bool, reduced_motion: bool) -> void:
	if half_width <= 0.0:
		return
	# Straight segments meet directly; corners share one patch without stacked glow.
	for edge in _edges:
		var start: Vector2 = board_rect.position + Vector2(edge["a"]) * cell_size
		var end: Vector2 = board_rect.position + Vector2(edge["b"]) * cell_size
		var direction := (end - start).normalized()
		var across := Vector2(-direction.y, direction.x) * half_width
		if not bool(_joints[Vector2i(edge["a"])]["straight"]):
			start += direction * half_width
		if not bool(_joints[Vector2i(edge["b"])]["straight"]):
			end -= direction * half_width
		var alpha := opacity * (1.0 if bool(edge["outer"]) else inner_strength)
		_paint_polygon(canvas, PackedVector2Array([start - across, end - across, end + across, start + across]), board_rect, cell_size, int(edge["color"]), alpha, white_core, reduced_motion)
	for point in _joints:
		var joint: Dictionary = _joints[point]
		if bool(joint["straight"]):
			continue
		var center: Vector2 = board_rect.position + Vector2(point) * cell_size
		var alpha := opacity * (1.0 if bool(joint["outer"]) else inner_strength)
		var points := PackedVector2Array()
		for offset in joint["outline"]:
			points.append(center + Vector2(offset) * half_width)
		_paint_polygon(canvas, points, board_rect, cell_size, int(joint["color"]), alpha, white_core, reduced_motion)

func _paint_polygon(canvas: CanvasItem, points: PackedVector2Array, board_rect: Rect2, cell_size: Vector2, color_index: int, opacity: float, white_core: bool, reduced_motion: bool) -> void:
	# Subpixel board rectangles may collapse after Vector2 rounding; skip empty strips.
	if (points[1] - points[0]).cross(points[2] - points[0]) == 0.0:
		return
	var colors := PackedColorArray()
	for point in points:
		var color := _edge_color((point - board_rect.position) / cell_size, color_index, reduced_motion)
		if white_core:
			color = color.lerp(Color(1.0, 0.97, 0.88), 0.56)
		colors.append(Color(color.r, color.g, color.b, opacity * color.a))
	canvas.draw_polygon(points, colors)

func _edge_color(point: Vector2, _color_index: int, reduced_motion: bool) -> Color:
	return spectrum_color(point, _board_size, not _row_colors.is_empty(), not _column_colors.is_empty(), 0.0 if reduced_motion else _phase)

## Use each line's long axis. Sampling only x turns a vertical clear into a
## nearly solid hue; a crossing uses one continuous field to avoid color seams.
static func spectrum_color(point: Vector2, board_size: int, has_rows: bool, has_columns: bool, phase: float = 0.0) -> Color:
	var normalized := point / float(maxi(board_size, 1))
	var along := normalized.y if has_columns and not has_rows else normalized.x
	if has_rows and has_columns:
		along = normalized.x + normalized.y
	var hue := fposmod(0.84 - along * 0.80 + sin(phase * 0.15) * 0.008, 1.0)
	return Color.from_hsv(hue, 0.62, 1.0)

func _draw_sparks(canvas: CanvasItem, board_rect: Rect2, cell_size: Vector2, unit: float, strength: float) -> void:
	var radius := minf(unit * 0.009, 0.60)
	if radius <= 0.0:
		return
	for spark in _spark_points:
		var wave := 0.5 + sin(_phase * 0.85 + float(spark["offset"])) * 0.5
		var alpha := pow(wave, 3.0) * 0.30 * strength
		if alpha < 0.02:
			continue
		var center: Vector2 = board_rect.position + Vector2(spark["point"]) * cell_size
		canvas.draw_circle(center, radius * 2.5, Color(1.0, 0.97, 0.88, alpha * 0.08))
		canvas.draw_circle(center, radius, Color(1.0, 0.97, 0.88, alpha))
