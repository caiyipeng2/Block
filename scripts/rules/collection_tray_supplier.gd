extends RefCounted

## Geometry is certified independently of target decoration. Marker quotas
## constrain progress, never whether a legal shape may be placed.
const MAX_ATTEMPTS := 5
const TARGET_ROUNDS := 10
const MIN_MARKERS_PER_TRAY := 2
const ASSIST_MARKER_BOOST := 0.25
var _config: GameRulesConfig
var _pool: Array[PieceData] = []
var _rng := RandomNumberGenerator.new()
var _round := 0
var _difficulty := 0.0
var _assist_strength := 0.0
var _profile := "mixed"
var _configured_profile := "mixed"
var _randomness := 50.0
var _configured_randomness := 50.0
var _rounds := TARGET_ROUNDS

func _init(config: GameRulesConfig, seed: int = 0, difficulty: float = 0.0, assist_strength: float = 0.0, profile: String = "mixed", randomness: float = 50.0, rounds: int = TARGET_ROUNDS) -> void:
	_config = config
	_rng.seed = seed
	_difficulty = clampf(difficulty, 0.0, 1.0)
	_assist_strength = clampf(assist_strength, 0.0, 1.0)
	_configured_profile = profile if profile in ["friendly", "mixed", "pressure"] else "mixed"
	_configured_randomness = clampf(randomness, 0.0, 100.0)
	_profile = _configured_profile
	_randomness = _configured_randomness
	_rounds = clampi(rounds, 1, 40)
	# Retry assistance keeps the same shapes legal but steers supply toward
	# friendlier geometry and slightly wider variety instead of changing goals.
	if _assist_strength >= 0.6:
		_profile = "friendly"
	elif _assist_strength > 0.0 and _profile == "pressure":
		_profile = "mixed"
	_randomness = clampf(_randomness + 15.0 * _assist_strength, 0.0, 100.0)
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
			var top_window := 1
			if attempt == 0:
				top_window = 1 + floori(maxf(0.0, _randomness - 50.0) / 50.0 * 3.0)
			else:
				top_window = clampi(roundi(6.0 * _randomness / 50.0), 1, 8)
			var selected: Dictionary = candidates[_rng.randi_range(0, mini(top_window, candidates.size()) - 1)]
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
	var decoration := decorate(chosen, remaining_counts)
	_round += 1
	return {
		"pieces": chosen, "solution": solution,
		"diagnostics": {
			"reason": "collection_solver_fallback" if fallback else "collection_clear_friendly",
			"solution_certified": chosen.size() == _config.tray_count,
			"certification_scope": "current_tray", "whole_level_certified": false,
			"difficulty_ratio": _difficulty, "clear_friendly": not fallback,
			"effective_difficulty": _difficulty, "retry_assist_strength": _assist_strength,
			"shape_profile_configured": _configured_profile, "shape_profile": _profile,
			"randomness_configured": _configured_randomness, "randomness": _randomness,
			"target_progress_preferred": _assist_strength > 0.0,
			"marker_budget": int(decoration["marker_budget"]),
			"marker_rounds_left": int(decoration["marker_rounds_left"]),
			"attempts": attempts, "evaluated_origins": evaluated, "fallback_used": fallback,
		},
	}

func decorate(pieces: Array[PieceData], remaining_counts: Dictionary) -> Dictionary:
	# Markers follow a budget derived from the remaining quota and the level's own
	# supply horizon, not a fixed density. A high-quota level therefore shows a
	# visibly denser target load, while the horizon decides how many trays the
	# level actually spans — that is where its real difficulty lives.
	var active: Array[String] = []
	var remaining_total := 0
	for kind in remaining_counts:
		var amount := int(remaining_counts[kind])
		remaining_total += amount
		if amount > 0:
			active.append(str(kind))
	active.sort()
	for piece in pieces:
		piece.targets.clear()
	if active.is_empty() or pieces.is_empty():
		return {"marker_budget": 0, "marker_rounds_left": 0}
	var capacity := 0
	for piece in pieces:
		capacity += piece.cells.size()
	var rounds_left := maxi(1, _rounds - _round)
	var budget := ceili(float(remaining_total) / float(rounds_left))
	if _assist_strength > 0.0:
		budget = ceili(float(budget) * (1.0 + ASSIST_MARKER_BOOST * _assist_strength))
	budget = clampi(budget, MIN_MARKERS_PER_TRAY, capacity)
	var slots: Array[Dictionary] = []
	for piece in pieces:
		for cell: Vector2i in piece.cells:
			slots.append({"piece": piece, "cell": cell})
	for index in range(slots.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var temporary: Dictionary = slots[index]
		slots[index] = slots[other]
		slots[other] = temporary
	# The first markers rotate through every unfinished kind so none is starved;
	# the rest follow remaining quotas so an uneven split still finishes together.
	var weights := remaining_counts.duplicate()
	var offset := _round % active.size()
	var placed := mini(budget, slots.size())
	for index in range(placed):
		var kind := active[(offset + index) % active.size()] if index < active.size() else _weighted_kind(active, weights)
		var slot: Dictionary = slots[index]
		var piece: PieceData = slot["piece"]
		piece.targets[slot["cell"]] = kind
		weights[kind] = maxi(1, int(weights.get(kind, 1)) - 1)
	return {"marker_budget": placed, "marker_rounds_left": rounds_left}

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
	var board_size := board.size
	var base_rows: Array[int] = []
	var base_columns: Array[int] = []
	base_rows.resize(board_size)
	base_columns.resize(board_size)
	base_rows.fill(0)
	base_columns.fill(0)
	for y in range(board_size):
		for x in range(board_size):
			if board.get_cell(x, y) >= 0:
				base_rows[y] += 1
				base_columns[x] += 1
	for piece in _pool:
		var legal_origins := board.get_legal_origins(piece)
		var freedom_weight := lerpf(2.0, -4.0, _difficulty)
		var cell_weight := lerpf(12.0, 65.0, _difficulty)
		var pressure_weight := lerpf(0.25, 2.0, _difficulty)
		var occupied_weight := lerpf(12.0, 3.0, _difficulty)
		var profile_bonus := _profile_bonus(piece)
		var jitter := 90.0 * _randomness / 50.0
		for origin in legal_origins:
			var outcome := _evaluate_placement(base_rows, base_columns, piece, origin, _assist_strength > 0.0)
			var occupied: int = int(outcome["occupied"])
			var pressure: int = int(outcome["pressure"])
			# Broad shape variety matters: a pure "most empty cells" score would
			# continually choose dominoes and never expose the expanded puzzle set.
			var rank := float(outcome["cleared_count"]) * 100000.0 - float(occupied) * occupied_weight + float(pressure) * pressure_weight + float(piece.cell_count()) * cell_weight + float(legal_origins.size()) * freedom_weight + (0.0 if used.has(piece.shape_id) else 180.0) + profile_bonus + _rng.randf() * jitter
			if _assist_strength > 0.0:
				var target_progress := _needed_target_count(outcome["cleared_cells"], board_targets, remaining_counts)
				# This objective-aware bonus remains useful even when the configured
				# geometric difficulty is already zero. All origins remain legal.
				rank += _assist_strength * (float(target_progress) * 2000000.0 + float(5 - piece.cell_count()) * 520.0 + float(legal_origins.size()) * 14.0 - float(occupied) * 28.0 - float(pressure) * 0.6)
			result.append({"piece": piece, "origin": origin, "rank": rank})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["rank"] > b["rank"])
	return result

## Evaluate a hypothetical placement from row/column occupancy counts. This
## keeps the collection supplier's per-origin ranking out of full board copies.
func _evaluate_placement(base_rows: Array[int], base_columns: Array[int], piece: PieceData, origin: Vector2i, include_cleared_cells: bool) -> Dictionary:
	var board_size := base_rows.size()
	var rows := base_rows.duplicate()
	var columns := base_columns.duplicate()
	for local_cell in piece.cells:
		var cell := origin + local_cell
		if cell.x < 0 or cell.y < 0 or cell.x >= board_size or cell.y >= board_size:
			return {"cleared_count": 0, "occupied": 0, "pressure": 0, "cleared_cells": []}
		rows[cell.y] += 1
		columns[cell.x] += 1
	var full_rows: Array[int] = []
	var full_columns: Array[int] = []
	for index in range(board_size):
		if rows[index] >= board_size:
			full_rows.append(index)
		if columns[index] >= board_size:
			full_columns.append(index)
	var cleared_cells: Array[Vector2i] = []
	if include_cleared_cells:
		var seen: Dictionary = {}
		for y in full_rows:
			for x in range(board_size):
				seen[Vector2i(x, y)] = true
		for x in full_columns:
			for y in range(board_size):
				seen[Vector2i(x, y)] = true
		cleared_cells.assign(seen.keys())
	var cleared_count := full_rows.size() * board_size + full_columns.size() * board_size - full_rows.size() * full_columns.size()
	var occupied := 0
	var pressure := 0
	for index in range(board_size):
		var row_count: int = 0 if index in full_rows else rows[index] - full_columns.size()
		var column_count: int = 0 if index in full_columns else columns[index] - full_rows.size()
		occupied += row_count
		pressure += row_count * row_count + column_count * column_count
	return {"cleared_count": cleared_count, "occupied": occupied, "pressure": pressure, "cleared_cells": cleared_cells}

func _profile_bonus(piece: PieceData) -> float:
	if _profile == "mixed" or piece.cells.is_empty():
		return 0.0
	var minimum := piece.cells[0]
	var maximum := piece.cells[0]
	for cell: Vector2i in piece.cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	var width := maximum.x - minimum.x + 1
	var height := maximum.y - minimum.y + 1
	var compactness := float(piece.cells.size()) / float(maxi(1, width * height))
	var cells := piece.cell_count()
	if _profile == "friendly":
		var bonus := float(4 - mini(cells, 4)) * 9000.0 + compactness * 7000.0
		if cells >= 5:
			bonus -= 14000.0
		return bonus
	var bonus := float(maxi(0, cells - 3)) * 9000.0 + (1.0 - compactness) * 7000.0
	if cells <= 3:
		bonus -= 5000.0
	return bonus

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
