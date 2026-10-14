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
	var result := _initial_setup(level_seed, rules, requested, ratio)
	result["mode"] = ADVENTURE
	result["level_id"] = current
	result["level_seed"] = level_seed
	result["difficulty_ratio"] = ratio
	result["target_lines"] = 2 + floori(ratio * 8.0)
	result["target_score"] = target_score_for_level(current, count)
	result["candidate_samples"] = 1 + roundi(ratio * 11.0)
	result["solution_count_cap"] = 8 - roundi(ratio * 6.0)
	return result

static func target_score_for_level(level_id: int, total_levels: int = MAX_LEVELS) -> int:
	var count := maxi(1, total_levels)
	var current := clampi(level_id, 1, count)
	var ratio := float(current - 1) / float(maxi(1, count - 1))
	return 368 + 24 * (current - 1) + roundi(ratio * ratio * 800.0)

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
