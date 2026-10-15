extends RefCounted

const FREE := "free"
const CLASSIC := "classic"
const ADVENTURE := "adventure"
const MAX_LEVELS := 96
const SETUP_ATTEMPTS := 8
const LEVEL_SEED_BASE := 272912

static func display_name(mode: String) -> String:
	match mode:
		CLASSIC:
			return "经典模式"
		ADVENTURE:
			return "闯关模式"
		_:
			return "自由模式"

static func classic_setup(seed: int, config: GameRulesConfig) -> Dictionary:
	var rules: GameRulesConfig = config if config != null else GameRulesConfig.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var requested := roundi(float(rng.randi_range(16, 24)) * _board_scale(rules))
	var result := _initial_setup(seed, rules, requested, 0.0)
	result["mode"] = CLASSIC
	result["level_seed"] = seed
	result["difficulty_ratio"] = 0.0
	result["candidate_samples"] = 1
	result["solution_count_cap"] = 8
	return result

static func level_setup(level_id: int, total_levels: int, config: GameRulesConfig) -> Dictionary:
	var rules: GameRulesConfig = config if config != null else GameRulesConfig.new()
	var count := maxi(1, total_levels)
	var current := clampi(level_id, 1, count)
	var ratio := float(current - 1) / float(maxi(1, count - 1))
	var level_seed := LEVEL_SEED_BASE + current * 104729
	var requested := roundi(lerpf(16.0, 43.0, ratio) * _board_scale(rules))
	var result: Dictionary
	if current <= 2:
		result = _initial_setup(level_seed, rules, requested, ratio)
		result["objective_type"] = "score"
		result["target_cells"] = []
		result["target_total"] = 0
	else:
		result = _collection_setup(level_seed, rules, requested, ratio, current, count)
		result["objective_type"] = "collect"
	result["mode"] = ADVENTURE
	result["level_id"] = current
	result["level_seed"] = level_seed
	result["difficulty_ratio"] = ratio
	result["target_lines"] = 2 + floori(ratio * 8.0)
	result["target_score"] = target_score_for_level(current, count) if current <= 2 else 0
	result["candidate_samples"] = 1 + roundi(ratio * 11.0)
	result["solution_count_cap"] = 8 - roundi(ratio * 6.0)
	return result

static func target_score_for_level(level_id: int, total_levels: int = MAX_LEVELS) -> int:
	var count := maxi(1, total_levels)
	var current := clampi(level_id, 1, count)
	if current <= 2:
		return 368 + 24 * (current - 1)
	return 0

## Read objective text without constructing or searching a level board.
static func objective_config(level_id: int, total_levels: int = MAX_LEVELS) -> Dictionary:
	var count := maxi(1, total_levels)
	var current := clampi(level_id, 1, count)
	return {
		"objective_type": "score" if current <= 2 else "collect",
		"target_score": target_score_for_level(current, count),
		"target_total": 0 if current <= 2 else _target_count_for_level(current, count),
	}

static func objective_description(level_id: int, total_levels: int = MAX_LEVELS) -> String:
	var objective := objective_config(level_id, total_levels)
	if objective["objective_type"] == "collect":
		return "消除 %d 个特殊标记" % int(objective["target_total"])
	return "目标 %d 分" % int(objective["target_score"])

static func _target_count_for_level(level_id: int, total_levels: int) -> int:
	var ratio := clampf(float(level_id - 3) / float(maxi(1, total_levels - 3)), 0.0, 1.0)
	return 2 + roundi(ratio * 10.0)

## Reserve a real clear route instead of decorating arbitrary occupied cells.
## The supplied tray is part of the level recipe and must stay paired with it.
static func _collection_setup(seed: int, config: GameRulesConfig, requested: int, difficulty: float, level_id: int, total_levels: int) -> Dictionary:
	var board_size := maxi(1, config.board_size)
	var tray_count := maxi(1, config.tray_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pieces := _collection_pieces(_shape_pool(config), tray_count, board_size, rng)
	if pieces.is_empty():
		var invalid := _invalid_setup(seed, requested, "collection_shapes_cannot_fit_reserved_bands")
		invalid["target_cells"] = []
		invalid["target_total"] = 0
		return invalid
	var protected: Dictionary = {}
	var occupied: Dictionary = {}
	var band_rows: Dictionary = {}
	var solution: Array[Dictionary] = []
	var palette_count := maxi(1, config.palette.size())
	var occupied_height := 0
	for piece in pieces:
		occupied_height += _piece_bounds(piece).size.y
	var gaps: Array[int] = []
	gaps.resize(tray_count + 1)
	gaps.fill(0)
	for _gap in range(board_size - occupied_height):
		gaps[rng.randi_range(0, tray_count)] += 1
	var y_cursor := gaps[0]
	for index in range(tray_count):
		var piece := pieces[index]
		var bounds := _piece_bounds(piece)
		var left := rng.randi_range(0, board_size - bounds.size.x)
		var origin := Vector2i(left - bounds.position.x, y_cursor - bounds.position.y)
		solution.append({"piece_index": index, "origin": origin})
		for y in range(y_cursor, y_cursor + bounds.size.y):
			band_rows[y] = true
		var row_counts: Dictionary = {}
		for local_cell in piece.cells:
			protected[origin + local_cell] = true
			row_counts[local_cell.y] = int(row_counts.get(local_cell.y, 0)) + 1
		var widest_local_y := bounds.position.y
		var widest_count := -1
		# A fixed top-to-bottom tie break keeps the seeded recipe reproducible.
		for local_y in range(bounds.position.y, bounds.end.y):
			var count_in_row := int(row_counts.get(local_y, 0))
			if count_in_row > widest_count:
				widest_local_y = local_y
				widest_count = count_in_row
		var goal_y := origin.y + widest_local_y
		for x in range(board_size):
			var position := Vector2i(x, goal_y)
			if not protected.has(position):
				occupied[position] = true
		y_cursor += bounds.size.y + gaps[index + 1]
	# Preserve a hole in every other line so none clear before the first move.
	# Prefer non-goal rows for column holes to retain the promised row route.
	_protect_collection_holes(protected, occupied, band_rows, board_size, rng)
	var cells: Array[Dictionary] = []
	var color_offset := rng.randi_range(0, palette_count - 1)
	for position: Vector2i in occupied:
		var color := (floori(float(position.x) / 2.0) + floori(float(position.y) / 2.0) + color_offset) % palette_count
		cells.append({"x": position.x, "y": position.y, "color": color})
	var fill_protected := protected.duplicate()
	for position in occupied:
		fill_protected[position] = true
	var target_occupied := maxi(requested, cells.size())
	cells.append_array(_fill_layout(fill_protected, board_size, target_occupied - cells.size(), difficulty, palette_count, rng))
	var board := BoardRules.new(board_size)
	for entry in cells:
		board.set_cell(entry["x"], entry["y"], entry["color"])
	var buckets := _cleared_initial_buckets(board, pieces, solution)
	var target_cells := _interleaved_targets(buckets, rng)
	var count := _target_count_for_level(level_id, total_levels)
	if target_cells.size() < count:
		var invalid := _invalid_setup(seed, requested, "insufficient_collectible_initial_cells")
		invalid["target_cells"] = []
		invalid["target_total"] = count
		return invalid
	target_cells.resize(count)
	var certified := count > 0 and _replay_solution(board, pieces, solution)
	return {
		"initial_cells": cells, "initial_pieces": pieces, "initial_solution": solution,
		"target_cells": target_cells, "target_total": count,
		"initial_diagnostics": {
			"seed": seed, "reason": "reserved_collection_route", "requested_occupied": requested,
			"initial_occupied": cells.size(), "solution_certified": certified,
			"target_route_certified": certified, "target_count": count,
		},
	}

static func _collection_pieces(pool: Array[PieceData], count: int, board_size: int, rng: RandomNumberGenerator) -> Array[PieceData]:
	var pieces: Array[PieceData] = []
	# Prefer different configured shapes. A repeated shortest shape remains a
	# valid fallback for custom pools that cannot fit a varied vertical recipe.
	if _pick_collection_shapes(pool, count, board_size, board_size - 1, {}, pieces, rng, false):
		return pieces
	if _pick_collection_shapes(pool, count, board_size, board_size - 1, {}, pieces, rng, true):
		return pieces
	return []

static func _pick_collection_shapes(pool: Array[PieceData], count: int, board_size: int, height_budget: int, used: Dictionary, pieces: Array[PieceData], rng: RandomNumberGenerator, allow_repeats: bool) -> bool:
	if pieces.size() == count:
		return true
	if height_budget <= 0 or (not allow_repeats and pool.size() < count):
		return false
	for index in _random_coordinates(pool.size(), rng):
		if not allow_repeats and used.has(index):
			continue
		var piece := pool[index]
		var bounds := _piece_bounds(piece)
		if bounds.size.x > board_size or bounds.size.y > height_budget:
			continue
		pieces.append(piece.duplicate_piece())
		used[index] = true
		if _pick_collection_shapes(pool, count, board_size, height_budget - bounds.size.y, used, pieces, rng, allow_repeats):
			return true
		pieces.pop_back()
		used.erase(index)
	return false

static func _piece_bounds(piece: PieceData) -> Rect2i:
	var minimum := piece.cells[0]
	var maximum := piece.cells[0]
	for cell in piece.cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

static func _random_coordinates(count: int, rng: RandomNumberGenerator) -> Array[int]:
	var coordinates: Array[int] = []
	for index in range(count):
		coordinates.append(index)
	for index in range(count - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value := coordinates[index]
		coordinates[index] = coordinates[other]
		coordinates[other] = value
	return coordinates

static func _protect_collection_holes(protected: Dictionary, occupied: Dictionary, band_rows: Dictionary, board_size: int, rng: RandomNumberGenerator) -> void:
	var untouched_rows: Array[int] = []
	for y in range(board_size):
		if not band_rows.has(y):
			untouched_rows.append(y)
	# At least one row lies outside all shape bands. A column hole there stays
	# empty throughout the certified route, even when a taller shape is placed.
	var columns := _random_coordinates(board_size, rng)
	var row_order := _random_coordinates(untouched_rows.size(), rng)
	for index in range(board_size):
		if not untouched_rows.is_empty():
			var row: int = untouched_rows[row_order[index % untouched_rows.size()]]
			protected[Vector2i(columns[index], row)] = true
	for y in range(board_size):
		var has_hole := false
		for x in range(board_size):
			has_hole = has_hole or protected.has(Vector2i(x, y))
		if not has_hole:
			var choices: Array[int] = []
			for x in range(board_size):
				if not occupied.has(Vector2i(x, y)):
					choices.append(x)
			if not choices.is_empty():
				protected[Vector2i(choices[rng.randi_range(0, choices.size() - 1)], y)] = true

static func _cleared_initial_buckets(board: BoardRules, pieces: Array[PieceData], solution: Array[Dictionary]) -> Array[Array]:
	var initial: Dictionary = {}
	for y in range(board.size):
		for x in range(board.size):
			if board.get_cell(x, y) >= 0:
				initial[Vector2i(x, y)] = true
	var replay := board.duplicate_board()
	var buckets: Array[Array] = []
	for step in solution:
		var piece: PieceData = pieces[step["piece_index"]]
		var origin: Vector2i = step["origin"]
		if not replay.can_place(piece, origin):
			return []
		replay.place(piece, origin, 0)
		var clear := replay.clear_full_lines()
		var bucket: Array[Vector2i] = []
		for cell in clear["cells"]:
			if initial.erase(cell):
				bucket.append(cell)
		buckets.append(bucket)
	return buckets

static func _interleaved_targets(buckets: Array[Array], rng: RandomNumberGenerator) -> Array[Vector2i]:
	# Alternate between distinct clear steps instead of marking only the first
	# easy row. Later levels distribute up to twelve markers across the route.
	var shuffled: Array[Array] = []
	var longest := 0
	for bucket in buckets:
		var entries: Array[Vector2i] = []
		for index in _random_coordinates(bucket.size(), rng):
			entries.append(bucket[index])
		shuffled.append(entries)
		longest = maxi(longest, entries.size())
	var result: Array[Vector2i] = []
	for index in range(longest):
		for bucket in shuffled:
			if index < bucket.size():
				result.append(bucket[index])
	return result

static func _board_scale(config: GameRulesConfig) -> float:
	return float(maxi(1, config.board_size) * maxi(1, config.board_size)) / 64.0

static func _initial_setup(seed: int, config: GameRulesConfig, requested: int, difficulty: float) -> Dictionary:
	var pool := _shape_pool(config)
	var board_size := maxi(1, config.board_size)
	var tray_count := maxi(1, config.tray_count)
	var target := clampi(requested, 1, maxi(1, board_size * board_size - 1))
	if pool.is_empty():
		return _invalid_setup(seed, target, "invalid_shape_pool")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var best: Dictionary = {}
	var attempted := 0
	for attempt in range(SETUP_ATTEMPTS):
		attempted = attempt + 1
		var pieces := _pick_pieces(pool, tray_count, board_size * board_size - target, board_size, rng)
		var candidate := _candidate(board_size, pieces, target, difficulty, config.palette.size(), rng, false)
		if candidate.is_empty():
			continue
		if best.is_empty() or candidate["initial_cells"].size() > best["initial_cells"].size():
			best = candidate
		if candidate["initial_cells"].size() == target:
			break
	if best.is_empty():
		# A row-major reservation of the smallest configured shape is the finite
		# fallback. It never invents a rotated shape or changes the play rules.
		var pieces: Array[PieceData] = []
		for _index in range(tray_count):
			pieces.append(pool[0].duplicate_piece())
		rng.seed = seed
		best = _candidate(board_size, pieces, target, difficulty, config.palette.size(), rng, true)
	if best.is_empty():
		return _invalid_setup(seed, target, "board_cannot_fit_initial_tray")
	best["initial_diagnostics"] = {
		"seed": seed,
		"reason": "reserved_route" if best["initial_cells"].size() == target else "reserved_route_reduced_density",
		"requested_occupied": target,
		"initial_occupied": best["initial_cells"].size(),
		"setup_attempts": attempted,
		"solution_certified": true
	}
	return best

static func _pick_pieces(pool: Array[PieceData], count: int, empty_budget: int, board_size: int, rng: RandomNumberGenerator) -> Array[PieceData]:
	var pieces: Array[PieceData] = []
	var minimum := pool[0].cell_count()
	# Keep room for at least one empty cell per row and column in addition to
	# the reserved route. Shared holes usually leave more spare cells than this.
	var budget := maxi(minimum * count, empty_budget - ceili(float(board_size) / 2.0))
	for index in range(count):
		var affordable: Array[PieceData] = []
		for piece in pool:
			if piece.cell_count() + minimum * (count - index - 1) <= budget:
				affordable.append(piece)
		var chosen: PieceData = affordable[rng.randi_range(0, affordable.size() - 1)]
		pieces.append(chosen.duplicate_piece())
		budget -= chosen.cell_count()
	return pieces

static func _candidate(board_size: int, pieces: Array[PieceData], target: int, difficulty: float, palette_count: int, rng: RandomNumberGenerator, deterministic: bool) -> Dictionary:
	var reserved_board := BoardRules.new(board_size)
	var reserved: Dictionary = {}
	var solution: Array[Dictionary] = []
	for index in range(pieces.size()):
		var legal := reserved_board.get_legal_origins(pieces[index])
		if legal.is_empty():
			return {}
		var origin: Vector2i = legal[0] if deterministic else legal[rng.randi_range(0, legal.size() - 1)]
		reserved_board.place(pieces[index], origin, 0)
		for local_cell in pieces[index].cells:
			reserved[origin + local_cell] = true
		solution.append({"piece_index": index, "origin": origin})
	_protect_line_holes(reserved, board_size, rng)
	var cells := _fill_layout(reserved, board_size, target, difficulty, maxi(1, palette_count), rng)
	if cells.is_empty():
		return {}
	var board := BoardRules.new(board_size)
	for cell in cells:
		board.set_cell(cell["x"], cell["y"], cell["color"])
	if not _replay_solution(board, pieces, solution):
		return {}
	return {"initial_cells": cells, "initial_pieces": pieces, "initial_solution": solution}

static func _protect_line_holes(protected: Dictionary, board_size: int, rng: RandomNumberGenerator) -> void:
	var empty_rows: Array[int] = []
	var empty_columns: Array[int] = []
	for coordinate in range(board_size):
		var row_has_hole := false
		var column_has_hole := false
		for other in range(board_size):
			row_has_hole = row_has_hole or protected.has(Vector2i(other, coordinate))
			column_has_hole = column_has_hole or protected.has(Vector2i(coordinate, other))
		if not row_has_hole:
			empty_rows.append(coordinate)
		if not column_has_hole:
			empty_columns.append(coordinate)
	while not empty_rows.is_empty() or not empty_columns.is_empty():
		var y: int = empty_rows.pop_back() if not empty_rows.is_empty() else rng.randi_range(0, board_size - 1)
		var x: int = empty_columns.pop_back() if not empty_columns.is_empty() else rng.randi_range(0, board_size - 1)
		protected[Vector2i(x, y)] = true

static func _fill_layout(protected: Dictionary, board_size: int, target: int, difficulty: float, palette_count: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var anchor := Vector2(rng.randf_range(0.0, board_size - 1), rng.randf_range(0.0, board_size - 1))
	for y in range(board_size):
		for x in range(board_size):
			var position := Vector2i(x, y)
			if protected.has(position):
				continue
			var distance := Vector2(position).distance_to(anchor) / float(board_size)
			# Earlier boards leave broad open areas; later boards distribute the
			# occupied cells more widely while preserving a certified route.
			var priority := rng.randf() + distance * (1.0 - difficulty) * 2.0
			candidates.append({"position": position, "priority": priority})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["priority"] < b["priority"])
	var cells: Array[Dictionary] = []
	var color_offset := rng.randi_range(0, palette_count - 1)
	for index in range(mini(target, candidates.size())):
		var position: Vector2i = candidates[index]["position"]
		var color := (floori(float(position.x) / 2.0) + floori(float(position.y) / 2.0) + color_offset) % palette_count
		cells.append({"x": position.x, "y": position.y, "color": color})
	return cells

static func _replay_solution(board: BoardRules, pieces: Array[PieceData], solution: Array[Dictionary]) -> bool:
	var replay := board.duplicate_board()
	if solution.size() != pieces.size():
		return false
	var used: Dictionary = {}
	for step in solution:
		var index: int = step["piece_index"]
		var origin: Vector2i = step["origin"]
		if index < 0 or index >= pieces.size() or used.has(index) or not replay.can_place(pieces[index], origin):
			return false
		replay.place(pieces[index], origin, 0)
		replay.clear_full_lines()
		used[index] = true
	return used.size() == pieces.size()

static func _shape_pool(config: GameRulesConfig) -> Array[PieceData]:
	var pool: Array[PieceData] = []
	for definition in config.shape_pool:
		var piece: PieceData = null
		if definition is ShapeDefinition:
			piece = definition.to_piece()
		elif definition is PieceData:
			piece = definition.duplicate_piece()
		elif definition is Dictionary:
			piece = PieceData.new(Vector2i.ZERO, definition.get("cells", []), str(definition.get("shape_id", "")))
		if piece != null and piece.is_valid_for_config(config):
			pool.append(piece)
	pool.sort_custom(func(a: PieceData, b: PieceData) -> bool: return a.cell_count() < b.cell_count())
	return pool

static func _invalid_setup(seed: int, target: int, reason: String) -> Dictionary:
	return {
		"initial_cells": [], "initial_pieces": [], "initial_solution": [],
		"initial_diagnostics": {
			"seed": seed, "reason": reason, "requested_occupied": target,
			"initial_occupied": 0, "solution_certified": false
		}
	}
