extends RefCounted

const CollectionTemplates = preload("res://scripts/modes/collection_templates.gd")
const CollectionTraySupplier = preload("res://scripts/rules/collection_tray_supplier.gd")
const FREE := "free"
const CLASSIC := "classic"
const ADVENTURE := "adventure"
const MAX_LEVELS := 96
const SETUP_ATTEMPTS := 8
const LEVEL_SEED_BASE := 272912
const TARGET_KINDS := ["blue_diamond", "gold_gem", "yellow_star", "red_star"]
const TARGET_NAMES := {"blue_diamond": "蓝色宝石", "gold_gem": "金色宝石", "yellow_star": "黄星", "red_star": "红星"}

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
	var base: GameRulesConfig = config if config != null else GameRulesConfig.new()
	var count := maxi(1, total_levels)
	var current := clampi(level_id, 1, count)
	var ratio := float(current - 1) / float(maxi(1, count - 1))
	var level_seed := LEVEL_SEED_BASE + current * 104729
	var requested := roundi(lerpf(16.0, 43.0, ratio) * _board_scale(base))
	var objective := objective_config(current, count)
	var result: Dictionary
	if current <= 2:
		result = _initial_setup(level_seed, base, requested, ratio)
		result["target_cells"] = []
	else:
		result = _collection_setup(level_seed, collection_rules(base), current, objective, requested, collection_difficulty(current, count))
	for field in objective:
		result[field] = objective[field]
	result["mode"] = ADVENTURE
	result["level_id"] = current
	result["level_seed"] = level_seed
	result["difficulty_ratio"] = collection_difficulty(current, count) if current >= 3 else ratio
	result["candidate_samples"] = 1
	result["solution_count_cap"] = 8
	return result

## This private copy keeps all other modes' 3–5 cell pool and strict combo
## untouched. Geometry in collect rounds is ordinary configured 2–9 cell play.
static func collection_rules(base: GameRulesConfig) -> GameRulesConfig:
	var source: GameRulesConfig = base if base != null else GameRulesConfig.new()
	var rules: GameRulesConfig = source.duplicate(true)
	rules.min_piece_cells = 2
	rules.max_piece_cells = 9
	rules.combo_miss_tolerance = 2
	var pool: Array = []
	for count in range(2, 6):
		var horizontal: Array[Vector2i] = []
		var vertical: Array[Vector2i] = []
		for coordinate in range(count):
			horizontal.append(Vector2i(coordinate, 0))
			vertical.append(Vector2i(0, coordinate))
		pool.append(PieceData.new(Vector2i.ZERO, horizontal, "horizontal%d" % count))
		pool.append(PieceData.new(Vector2i.ZERO, vertical, "vertical%d" % count))
	for definition in source.shape_pool:
		var piece: PieceData = null
		if definition is ShapeDefinition:
			piece = definition.to_piece()
		elif definition is PieceData:
			piece = definition.duplicate_piece()
		elif definition is Dictionary:
			piece = PieceData.new(Vector2i.ZERO, definition.get("cells", []), str(definition.get("shape_id", "")))
		if piece != null and piece.is_valid_for_config(rules):
			pool.append(piece)
	pool.append(PieceData.new(Vector2i.ZERO, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)], "zigzag4"))
	pool.append(PieceData.new(Vector2i.ZERO, [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2)], "diagonal3"))
	for dimensions in [Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3)]:
		var cells: Array[Vector2i] = []
		for y in range(dimensions.y):
			for x in range(dimensions.x):
				cells.append(Vector2i(x, y))
		pool.append(PieceData.new(Vector2i.ZERO, cells, "rectangle%dx%d" % [dimensions.x, dimensions.y]))
	var unique_pool: Array = []
	var seen: Dictionary = {}
	for piece: PieceData in pool:
		var minimum := piece.cells[0]
		for cell in piece.cells:
			minimum.x = mini(minimum.x, cell.x)
			minimum.y = mini(minimum.y, cell.y)
		var coordinates := PackedStringArray()
		for cell in piece.cells:
			coordinates.append("%d:%d" % [cell.x - minimum.x, cell.y - minimum.y])
		coordinates.sort()
		var key := ";".join(coordinates)
		if not seen.has(key):
			seen[key] = true
			unique_pool.append(piece)
	rules.shape_pool = unique_pool
	return rules

static func target_score_for_level(level_id: int, total_levels: int = MAX_LEVELS) -> int:
	var current := clampi(level_id, 1, maxi(1, total_levels))
	return 368 + 24 * (current - 1) if current <= 2 else 0

## Quotas are finite per-kind requirements. They are not a promise that all
## markers fit on the initial board; later trays keep bringing marked cells.
static func objective_config(level_id: int, total_levels: int = MAX_LEVELS) -> Dictionary:
	var current := clampi(level_id, 1, maxi(1, total_levels))
	var counts: Dictionary = {}
	var total := _target_count_for_level(current)
	var descriptions := PackedStringArray()
	var kinds := _level_kinds(current)
	if current >= 3:
		var share := floori(float(total) / 3.0)
		for index in range(kinds.size()):
			counts[kinds[index]] = share + (1 if index < total % 3 else 0)
			descriptions.append("%s %d 个" % [TARGET_NAMES[kinds[index]], counts[kinds[index]]])
	return {
		"objective_type": "score" if current <= 2 else "collect",
		"target_score": target_score_for_level(current, total_levels),
		"target_total": total, "target_counts": counts,
		"target_kinds": kinds if current >= 3 else [],
		"difficulty_label": _difficulty_label(current),
		"description": "目标 %d 分" % target_score_for_level(current, total_levels) if current <= 2 else " · ".join(descriptions),
	}

static func objective_description(level_id: int, total_levels: int = MAX_LEVELS) -> String:
	return str(objective_config(level_id, total_levels)["description"])

static func collection_difficulty(level_id: int, total_levels: int = MAX_LEVELS) -> float:
	return clampf(float(level_id - 3) / float(maxi(1, total_levels - 3)), 0.0, 1.0)

static func _level_kinds(level_id: int) -> Array[String]:
	var omitted := posmod(3 + floori(float(maxi(0, level_id - 3)) / 5.0), TARGET_KINDS.size())
	var kinds: Array[String] = []
	for index in range(TARGET_KINDS.size()):
		if index != omitted:
			kinds.append(TARGET_KINDS[index])
	return kinds

static func _target_count_for_level(level_id: int) -> int:
	for entry in [[96, 120], [72, 108], [48, 96], [36, 84], [24, 72], [18, 66], [12, 60], [9, 48], [6, 42], [5, 36], [4, 30], [3, 24]]:
		if level_id >= int(entry[0]):
			return int(entry[1])
	return 0

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

static func _collection_setup(seed: int, rules: GameRulesConfig, level_id: int, objective: Dictionary, requested: int, difficulty: float) -> Dictionary:
	var template := CollectionTemplates.create(level_id, rules.board_size, rules.palette.size())
	var board := BoardRules.new(rules.board_size)
	for entry: Dictionary in template["initial_cells"]:
		board.set_cell(entry["x"], entry["y"], entry["color"])
	# Never start on a full line, including when a custom board size maps two
	# authored mask coordinates together.
	if not board.duplicate_board().clear_full_lines()["cells"].is_empty():
		return _invalid_setup(seed, requested, "template_contains_full_line")
	var targets: Dictionary = {}
	var kinds: Array = objective["target_kinds"]
	var marker_index := 0
	for entry: Dictionary in template["initial_cells"]:
		if posmod(int(entry["x"]) + int(entry["y"]) + level_id, 3) == 0:
			targets[Vector2i(entry["x"], entry["y"])] = kinds[marker_index % kinds.size()]
			marker_index += 1
	var generator := RoundGenerator.new(seed, rules)
	var supplier := CollectionTraySupplier.new(rules, seed, difficulty)
	var supplied := supplier.build(board, objective["target_counts"], generator)
	var diagnostics: Dictionary = supplied["diagnostics"]
	diagnostics["seed"] = seed
	diagnostics["requested_occupied"] = requested
	diagnostics["initial_occupied"] = template["initial_cells"].size()
	diagnostics["template_id"] = template["template_id"]
	diagnostics["template_name"] = template["template_name"]
	return {
		"initial_cells": template["initial_cells"], "initial_pieces": supplied["pieces"],
		"initial_solution": supplied["solution"], "target_cells": targets,
		"initial_diagnostics": diagnostics, "template_id": template["template_id"],
		"template_name": template["template_name"],
	}

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
		"initial_setup_invalid": true,
		"initial_cells": [], "initial_pieces": [], "initial_solution": [],
		"initial_diagnostics": {
			"seed": seed, "reason": reason, "requested_occupied": target,
			"initial_occupied": 0, "solution_certified": false
		}
	}
