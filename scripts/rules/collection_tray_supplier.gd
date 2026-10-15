extends RefCounted

## Geometry is certified independently of target decoration. Marker quotas
## constrain progress, never whether a legal shape may be placed.
const MAX_ATTEMPTS := 5
var _config: GameRulesConfig
var _pool: Array[PieceData] = []
var _rng := RandomNumberGenerator.new()
var _round := 0
var _difficulty := 0.0
var _assist_strength := 0.0

func _init(config: GameRulesConfig, seed: int = 0, difficulty: float = 0.0, assist_strength: float = 0.0) -> void:
	_config = config
	_rng.seed = seed
	_difficulty = clampf(difficulty, 0.0, 1.0)
	_assist_strength = clampf(assist_strength, 0.0, 1.0)
	for definition in config.shape_pool:
		var piece: PieceData = null
		if definition is ShapeDefinition:
			piece = definition.to_piece()
		elif definition is PieceData:
			piece = definition.duplicate_piece()
		elif definition is Dictionary:
			piece = PieceData.new(Vector2i.ZERO, definition.get("cells", []), str(definition.get("shape_id", "")))
		if piece != null and piece.is_valid_for_config(config):
			_pool.append(piece)

func build(board: BoardRules, remaining_counts: Dictionary, generator: RoundGenerator, board_targets: Dictionary = {}) -> Dictionary:
	var chosen: Array[PieceData] = []
	var solution: Array[Dictionary] = []
	var evaluated := 0
	var attempts := 0
	for attempt in range(MAX_ATTEMPTS):
		attempts = attempt + 1
		chosen.clear()
		solution.clear()
		var replay := board.duplicate_board()
		var simulated_targets := board_targets.duplicate()
		var simulated_remaining := remaining_counts.duplicate()
		var used: Dictionary = {}
		for index in range(_config.tray_count):
			var candidates := _ranked_placements(replay, used, simulated_targets, simulated_remaining)
			evaluated += candidates.size()
			if candidates.is_empty():
				break
			# The first pass takes the best clear. Subsequent finite passes try
			# nearby alternatives if a greedy first move trapped a later piece.
			var selected: Dictionary = candidates[0 if attempt == 0 else _rng.randi_range(0, mini(5, candidates.size() - 1))]
			var piece: PieceData = selected["piece"]
			var origin: Vector2i = selected["origin"]
			chosen.append(piece.duplicate_piece())
			solution.append({"piece_index": index, "origin": origin})
			used[piece.shape_id] = true
			replay.place(piece, origin, 0)
			var cleared := replay.clear_full_lines()
			if _assist_strength > 0.0:
				_consume_simulated_targets(cleared["cells"], simulated_targets, simulated_remaining)
		if chosen.size() == _config.tray_count:
			break
	var fallback := chosen.size() != _config.tray_count
	if fallback:
		# Reuse the existing complete solver rather than declaring a fair board
		# dead solely because the limited clear-friendly search ran out of tries.
		chosen = generator.generate_solvable_round(board)
		solution = generator.last_solution.duplicate(true)
	decorate(chosen, remaining_counts)
	_round += 1
	return {
		"pieces": chosen, "solution": solution,
		"diagnostics": {
			"reason": "collection_solver_fallback" if fallback else "collection_clear_friendly",
			"solution_certified": chosen.size() == _config.tray_count,
			"certification_scope": "current_tray", "whole_level_certified": false,
			"difficulty_ratio": _difficulty, "clear_friendly": not fallback,
			"effective_difficulty": _difficulty, "retry_assist_strength": _assist_strength,
			"target_progress_preferred": _assist_strength > 0.0,
			"attempts": attempts, "evaluated_origins": evaluated, "fallback_used": fallback,
		},
	}

func decorate(pieces: Array[PieceData], remaining_counts: Dictionary) -> void:
	var active: Array[String] = []
	for kind in remaining_counts:
		if int(remaining_counts[kind]) > 0:
			active.append(str(kind))
	active.sort()
	if active.is_empty():
		return
	if _assist_strength > 0.0:
		_decorate_assisted(pieces, remaining_counts, active)
		return
	var offset := _round % active.size()
	for piece in pieces:
		piece.targets.clear()
		var order := _shuffled_indices(piece.cells.size())
		# At least one marker per piece. A whole marked long piece is allowed
		# when only one target remains; excess does not reduce counters below 0.
		var marker_count := maxi(1, ceili(float(piece.cells.size()) * _rng.randf_range(0.45, 0.85)))
		for index in range(marker_count):
			piece.targets[piece.cells[order[index]]] = active[(offset + index) % active.size()]
		offset = (offset + marker_count) % active.size()

func _decorate_assisted(pieces: Array[PieceData], remaining_counts: Dictionary, active: Array[String]) -> void:
	# Rotate a guaranteed marker through every unfinished kind; additional
	# markers favor the larger remaining quotas without expanding a quota list.
	var offset := _round % active.size()
	var weights := remaining_counts.duplicate()
	var density_min := clampf(0.45 + 0.5 * _assist_strength, 0.45, 0.95)
	var density_max := clampf(0.85 + 0.25 * _assist_strength, density_min, 1.0)
	for piece in pieces:
		piece.targets.clear()
		var order := _shuffled_indices(piece.cells.size())
		var marker_count := mini(piece.cells.size(), maxi(1, ceili(float(piece.cells.size()) * _rng.randf_range(density_min, density_max))))
		for index in range(marker_count):
			var kind := active[offset] if index == 0 else _weighted_kind(active, weights)
			piece.targets[piece.cells[order[index]]] = kind
			weights[kind] = maxi(1, int(weights.get(kind, 1)) - 1)
		offset = (offset + 1) % active.size()

func _weighted_kind(active: Array[String], weights: Dictionary) -> String:
	var total := 0
	for kind in active:
		total += maxi(1, int(weights.get(kind, 1)))
	var ticket := _rng.randf() * float(total)
	for kind in active:
		ticket -= float(maxi(1, int(weights.get(kind, 1))))
		if ticket < 0.0:
			return kind
	return active.back()

func _ranked_placements(board: BoardRules, used: Dictionary, board_targets: Dictionary = {}, remaining_counts: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for piece in _pool:
		var legal_origins := board.get_legal_origins(piece)
		var freedom_weight := lerpf(2.0, -4.0, _difficulty)
		var cell_weight := lerpf(12.0, 65.0, _difficulty)
		var pressure_weight := lerpf(0.25, 2.0, _difficulty)
		var occupied_weight := lerpf(12.0, 3.0, _difficulty)
		for origin in legal_origins:
			var next := board.duplicate_board()
			next.place(piece, origin, 0)
			var cleared := next.clear_full_lines()
			var occupied := 0
			var pressure := 0
			for coordinate in range(next.size):
				var row := 0
				var column := 0
				for other in range(next.size):
					row += int(next.get_cell(other, coordinate) >= 0)
					column += int(next.get_cell(coordinate, other) >= 0)
				occupied += row
				pressure += row * row + column * column
			# Broad shape variety matters: a pure "most empty cells" score would
			# continually choose dominoes and never expose the expanded puzzle set.
			var rank := float(cleared["cells"].size()) * 100000.0 - float(occupied) * occupied_weight + float(pressure) * pressure_weight + float(piece.cell_count()) * cell_weight + float(legal_origins.size()) * freedom_weight + (0.0 if used.has(piece.shape_id) else 180.0) + _rng.randf() * 90.0
			if _assist_strength > 0.0:
				var target_progress := _needed_target_count(cleared["cells"], board_targets, remaining_counts)
				# This objective-aware bonus remains useful even when the configured
				# geometric difficulty is already zero. All origins remain legal.
				rank += _assist_strength * (float(target_progress) * 2000000.0 + float(5 - piece.cell_count()) * 520.0 + float(legal_origins.size()) * 14.0 - float(occupied) * 28.0 - float(pressure) * 0.6)
			result.append({"piece": piece, "origin": origin, "rank": rank})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["rank"] > b["rank"])
	return result

func _needed_target_count(cleared_cells: Array, board_targets: Dictionary, remaining_counts: Dictionary) -> int:
	var matched: Dictionary = {}
	var seen: Dictionary = {}
	var progress := 0
	for cell in cleared_cells:
		if seen.has(cell) or not board_targets.has(cell):
			continue
		seen[cell] = true
		var kind := str(board_targets[cell])
		var counted := int(matched.get(kind, 0))
		if counted < maxi(0, int(remaining_counts.get(kind, 0))):
			matched[kind] = counted + 1
			progress += 1
	return progress

func _consume_simulated_targets(cleared_cells: Array, board_targets: Dictionary, remaining_counts: Dictionary) -> void:
	for cell in cleared_cells:
		if not board_targets.has(cell):
			continue
		var kind := str(board_targets[cell])
		board_targets.erase(cell)
		if remaining_counts.has(kind):
			remaining_counts[kind] = maxi(0, int(remaining_counts[kind]) - 1)

func _shuffled_indices(count: int) -> Array[int]:
	var result: Array[int] = []
	for index in range(count):
		result.append(index)
	for index in range(count - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var temporary := result[index]
		result[index] = result[other]
		result[other] = temporary
	return result
