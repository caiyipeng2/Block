extends RefCounted

const FREE := "free"
const CLASSIC := "classic"
const ADVENTURE := "adventure"
const MAX_LEVELS := 96
const SETUP_ATTEMPTS := 8
const LEVEL_SEED_BASE := 272912
const COLLECTION_RECIPE_ATTEMPTS := 12
const TARGET_KINDS := ["red_star", "gold_gem"]

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
	var objective := objective_config(current, count)
	for field in ["target_counts", "difficulty_label", "description", "target_rows", "required_rounds"]:
		result[field] = objective[field]
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
	var target_rows := _target_rows_for_level(current) if current >= 3 else 0
	var target_total := _target_count_for_level(current, count) if current >= 3 else 0
	var gold := roundi(float(target_total) * (0.25 + 0.05 * float(maxi(0, target_rows - 3))))
	var target_counts := {"red_star": target_total - gold, "gold_gem": gold}
	var result := {
		"objective_type": "score" if current <= 2 else "collect",
		"target_score": target_score_for_level(current, count),
		"target_total": target_total, "target_counts": target_counts,
		"target_rows": target_rows, "required_rounds": ceili(float(target_rows) / 3.0),
		"difficulty_label": _difficulty_label(current),
	}
	result["description"] = "目标 %d 分" % int(result["target_score"]) if current <= 2 else "红星 %d 个 · 金色宝石 %d 个" % [target_counts["red_star"], target_counts["gold_gem"]]
	return result

static func objective_description(level_id: int, total_levels: int = MAX_LEVELS) -> String:
	var objective := objective_config(level_id, total_levels)
	return str(objective["description"])

static func _target_count_for_level(level_id: int, total_levels: int) -> int:
	var current := clampi(level_id, 1, maxi(1, total_levels))
	for entry in [[96, 40], [72, 36], [48, 32], [36, 28], [24, 24], [18, 22], [12, 18], [9, 16], [6, 14], [5, 12], [4, 10], [3, 8]]:
		if current >= int(entry[0]):
			return int(entry[1])
	return 0

static func _target_rows_for_level(level_id: int) -> int:
	if level_id <= 5:
		return 3
	if level_id <= 11:
		return 4
	if level_id <= 17:
		return 5
	if level_id <= 35:
		return 6
	if level_id <= 71:
		return 7
	return 8

static func _difficulty_label(level_id: int) -> String:
	if level_id <= 2:
		return "教学"
	if level_id <= 5:
		return "入门"
	if level_id <= 11:
		return "进阶"
	if level_id <= 23:
		return "挑战"
	if level_id <= 47:
		return "困难"
	if level_id <= 71:
		return "专家"
	return "大师"

## Build a bounded, bottom-to-top route. A shape's top occupied row is the
## current goal row; its other cells use work space opened by preceding rows.
## The full route is replayed on the final initial board before accepting it.
static func _collection_setup(seed: int, config: GameRulesConfig, requested: int, _difficulty: float, level_id: int, total_levels: int) -> Dictionary:
	var objective := objective_config(level_id, total_levels)
	var row_count: int = objective["target_rows"]
	var pool := _shape_pool(config)
	var line: PieceData = null
	for piece in pool:
		var bounds := _piece_bounds(piece)
		if piece.cell_count() == 3 and bounds.size == Vector2i(3, 1):
			line = piece
			break
	if config.tray_count != 3 or config.board_size < row_count or line == null:
		return _invalid_collection(seed, requested, objective, "collection_route_incompatible_config")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for _attempt in range(COLLECTION_RECIPE_ATTEMPTS):
		var recipe := _collection_recipe(config.board_size, row_count, pool, line, rng, false)
		var certified := _certify_collection_recipe(recipe, pool, config, objective, requested, seed)
		if not certified.is_empty():
			certified["initial_diagnostics"]["recipe_attempts"] = _attempt + 1
			return certified
	# Horizontal triples are an ordinary configured shape. This finite fallback
	# guarantees a route without altering the board, shape rules, or goal count.
	var fallback := _collection_recipe(config.board_size, row_count, pool, line, rng, true)
	var certified := _certify_collection_recipe(fallback, pool, config, objective, requested, seed)
	if certified.is_empty():
		return _invalid_collection(seed, requested, objective, "collection_route_cannot_certify_targets")
	certified["initial_diagnostics"]["recipe_attempts"] = COLLECTION_RECIPE_ATTEMPTS
	certified["initial_diagnostics"]["fallback_used"] = true
	return certified

static func _collection_recipe(board_size: int, row_count: int, pool: Array[PieceData], line: PieceData, rng: RandomNumberGenerator, fallback: bool) -> Dictionary:
	var board := BoardRules.new(board_size)
	var initial: Array[Dictionary] = []
	var pieces: Array[PieceData] = []
	var solution: Array[Dictionary] = []
	var used_shapes: Dictionary = {}
	for index in range(row_count):
		var y := board_size - 1 - index
		var candidates: Array[Dictionary] = []
		for pool_index in range(pool.size()):
			var piece := pool[pool_index]
			var bounds := _piece_bounds(piece)
			if bounds.size.x > board_size or bounds.size.y > index + 1:
				continue
			if (fallback or index == 0) and piece != line:
				continue
			candidates.append({"piece": piece, "priority": float(used_shapes.get(piece.shape_id, 0)) * 10.0 + rng.randf()})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["priority"] < b["priority"])
		var chosen: Dictionary = {}
		for candidate in candidates:
			var piece: PieceData = candidate["piece"]
			var bounds := _piece_bounds(piece)
			var horizontal_order := _random_coordinates(board_size - bounds.size.x + 1, rng)
			if fallback and row_count == board_size:
				# The first two equal holes protect the first clear; subsequent
				# holes cover every column, preventing an initially full column.
				var left := 0 if index <= 1 else mini((index - 1) * 3, board_size - 3)
				horizontal_order = [left]
			for left in horizontal_order:
				var origin := Vector2i(left - bounds.position.x, y - bounds.position.y)
				var holes: Dictionary = {}
				for cell in piece.cells:
					if cell.y == bounds.position.y:
						holes[origin.x + cell.x] = true
				var next := board.duplicate_board()
				var row_cells: Array[Dictionary] = []
				for x in range(board_size):
					if not holes.has(x):
						next.set_cell(x, y, 0)
						row_cells.append({"x": x, "y": y, "color": 0})
				if not next.can_place(piece, origin):
					continue
				next.place(piece, origin, 0)
				next.clear_full_lines()
				chosen = {"piece": piece, "origin": origin, "board": next, "initial": row_cells}
				break
			if not chosen.is_empty():
				break
		if chosen.is_empty():
			return {}
		var piece: PieceData = chosen["piece"]
		pieces.append(piece.duplicate_piece())
		solution.append({"piece_index": index, "origin": chosen["origin"]})
		initial.append_array(chosen["initial"])
		board = chosen["board"]
		used_shapes[piece.shape_id] = int(used_shapes.get(piece.shape_id, 0)) + 1
	return {"initial_cells": initial, "pieces": pieces, "solution": solution, "goal_rows": row_count}

static func _certify_collection_recipe(recipe: Dictionary, pool: Array[PieceData], config: GameRulesConfig, objective: Dictionary, requested: int, seed: int) -> Dictionary:
	if recipe.is_empty():
		return {}
	var board := BoardRules.new(config.board_size)
	var initial_remaining: Dictionary = {}
	var initial_cells: Array[Dictionary] = []
	var color_offset := posmod(seed, maxi(1, config.palette.size()))
	for entry: Dictionary in recipe["initial_cells"]:
		var color := (floori(float(entry["x"]) / 2.0) + floori(float(entry["y"]) / 2.0) + color_offset) % maxi(1, config.palette.size())
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		board.set_cell(cell.x, cell.y, color)
		initial_remaining[cell] = true
		initial_cells.append({"x": cell.x, "y": cell.y, "color": color})
	if not board.duplicate_board().clear_full_lines()["cells"].is_empty():
		return {}
	var initial_board := board.duplicate_board()
	var pieces: Array[PieceData] = []
	pieces.assign(recipe["pieces"])
	var solution: Array[Dictionary] = []
	solution.assign(recipe["solution"])
	var buckets: Array[Array] = []
	for index in range(solution.size()):
		var step: Dictionary = solution[index]
		var piece := pieces[index]
		var origin: Vector2i = step["origin"]
		if not board.can_place(piece, origin):
			return {}
		board.place(piece, origin, 0)
		var cleared := board.clear_full_lines()
		var bucket: Array[Vector2i] = []
		var expected_y := board.size - 1 - index
		for cell in cleared["cells"]:
			if initial_remaining.erase(cell):
				# Reject premature crossing clears that steal future goal rows.
				if cell.y != expected_y:
					return {}
				bucket.append(cell)
		if bucket.is_empty():
			return {}
		buckets.append(bucket)
	if not initial_remaining.is_empty():
		return {}
	var ordered_targets := _interleaved_targets(buckets, seed)
	var target_total: int = objective["target_total"]
	if ordered_targets.size() < target_total:
		return {}
	ordered_targets.resize(target_total)
	var targets: Dictionary = {}
	var gold: int = objective["target_counts"]["gold_gem"]
	for index in range(target_total):
		var is_gold := floori(float((index + 1) * gold) / float(target_total)) > floori(float(index * gold) / float(target_total))
		var kind := "gold_gem" if is_gold else "red_star"
		targets[ordered_targets[index]] = kind
	# Pad the last round with legal ordinary pieces in the opened work area.
	# Completion still happens immediately when the last marker is collected.
	while pieces.size() % config.tray_count != 0:
		var padded := false
		for piece in pool:
			var legal := board.get_legal_origins(piece)
			if legal.is_empty():
				continue
			var origin: Vector2i = legal[0]
			solution.append({"piece_index": pieces.size(), "origin": origin})
			pieces.append(piece.duplicate_piece())
			board.place(piece, origin, 0)
			board.clear_full_lines()
			padded = true
			break
		if not padded:
			return {}
	var rounds := _make_certified_rounds(initial_board, targets, pieces, solution, config.tray_count)
	if rounds.is_empty():
		return {}
	return {
		"initial_cells": initial_cells, "initial_pieces": rounds[0]["pieces"],
		"initial_solution": rounds[0]["solution"], "certified_rounds": rounds,
		"target_cells": targets, "target_counts": objective["target_counts"].duplicate(),
		"target_total": target_total,
		"initial_diagnostics": {
			"seed": seed, "reason": "certified_collection_route", "requested_occupied": requested,
			"initial_occupied": initial_cells.size(), "solution_certified": true,
			"target_route_certified": true, "target_count": target_total,
			"certified_round_count": rounds.size(), "certified_move_count": pieces.size(),
			"goal_rows": recipe["goal_rows"], "fallback_used": false,
		},
	}

static func _make_certified_rounds(board: BoardRules, targets: Dictionary, pieces: Array[PieceData], solution: Array[Dictionary], tray_count: int) -> Array[Dictionary]:
	var rounds: Array[Dictionary] = []
	var replay := board.duplicate_board()
	var remaining := targets.duplicate()
	for offset in range(0, pieces.size(), tray_count):
		var round_pieces: Array[PieceData] = []
		var round_solution: Array[Dictionary] = []
		var board_key := occupancy_key(replay)
		var targets_key := target_key(remaining)
		for index in range(tray_count):
			var piece := pieces[offset + index].duplicate_piece()
			var origin: Vector2i = solution[offset + index]["origin"]
			if not replay.can_place(piece, origin):
				return []
			round_pieces.append(piece)
			round_solution.append({"piece_index": index, "origin": origin})
			replay.place(piece, origin, 0)
			var cleared := replay.clear_full_lines()
			for cell in cleared["cells"]:
				remaining.erase(cell)
		rounds.append({"occupancy_key": board_key, "target_key": targets_key, "pieces": round_pieces, "solution": round_solution})
	if not remaining.is_empty():
		return []
	return rounds

static func _interleaved_targets(buckets: Array[Array], seed: int) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 3989
	var shuffled: Array[Array] = []
	var longest := 0
	for bucket in buckets:
		var entries: Array[Vector2i] = []
		for index in _random_coordinates(bucket.size(), rng):
			entries.append(bucket[index])
		shuffled.append(entries)
		longest = maxi(longest, entries.size())
	var targets: Array[Vector2i] = []
	for index in range(longest):
		for bucket in shuffled:
			if index < bucket.size():
				targets.append(bucket[index])
	return targets

static func occupancy_key(board: BoardRules) -> String:
	var key := ""
	for y in range(board.size):
		for x in range(board.size):
			key += "1" if board.get_cell(x, y) >= 0 else "0"
	return key

static func target_key(targets: Dictionary) -> String:
	var entries := PackedStringArray()
	for cell: Vector2i in targets:
		entries.append("%d,%d:%s" % [cell.x, cell.y, str(targets[cell])])
	entries.sort()
	return ";".join(entries)

static func _invalid_collection(seed: int, requested: int, objective: Dictionary, reason: String) -> Dictionary:
	var invalid := _invalid_setup(seed, requested, reason)
	invalid["target_cells"] = {}
	invalid["target_counts"] = objective["target_counts"].duplicate()
	invalid["target_total"] = objective["target_total"]
	invalid["certified_rounds"] = []
	return invalid

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
