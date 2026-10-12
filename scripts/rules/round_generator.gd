class_name RoundGenerator
extends RefCounted

var seed: int
var rules_config: GameRulesConfig
var _rng: RandomNumberGenerator
var max_attempts: int = 100
var _shape_pool: Array[PieceData] = []

var last_solution: Array[Dictionary] = []
var last_diagnostics: Dictionary = {}
var _round_counter: int = 0
var _search_nodes: int = 0
var _fallback_nodes: int = 0
var _round_nodes: int = 0
var _duplicate_candidates: int = 0
var _warning_emitted: bool = false

func _init(initial_seed: int = 0, config: GameRulesConfig = null) -> void:
	seed = initial_seed
	rules_config = config if config != null else GameRulesConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = initial_seed
	max_attempts = max(0, rules_config.generation_attempts)
	_shape_pool = _build_shape_pool(rules_config)

func generate_solvable_round(board: BoardRules) -> Array[PieceData]:
	last_solution = []
	_warning_emitted = false
	_round_nodes = 0
	_search_nodes = 0
	_fallback_nodes = 0
	_duplicate_candidates = 0
	var started_usec := Time.get_ticks_usec()
	var tray_count: int = maxi(0, rules_config.tray_count)
	if board == null or tray_count <= 0 or _shape_pool.is_empty():
		last_diagnostics = _diagnostics(0, false, "invalid_config", started_usec)
		_log_generation_issue("RoundGenerator could not generate a round: invalid board, tray count, or shape pool.")
		_round_counter += 1
		return []

	var attempts := 0
	var impossible_candidates: Dictionary = {}
	for _attempt in range(max_attempts):
		attempts += 1
		var candidate: Array[PieceData] = []
		for _i in range(tray_count):
			candidate.append(_shape_pool[_rng.randi_range(0, _shape_pool.size() - 1)].duplicate_piece())
		var candidate_key := _candidate_key(candidate)
		if impossible_candidates.has(candidate_key):
			_duplicate_candidates += 1
			continue
		var solution := find_solution(board, candidate)
		_round_nodes += _search_nodes
		if solution.size() == tray_count:
			last_solution = _copy_solution(solution)
			last_diagnostics = _diagnostics(attempts, false, "random", started_usec)
			_round_counter += 1
			return candidate
		impossible_candidates[candidate_key] = true

	# A constructive search places shapes while it searches. It avoids the old
	# exhaustive pool^tray_count tuple enumeration and still has no hard cutoff.
	var fallback := _constructive_fallback(board, tray_count)
	_round_nodes += _fallback_nodes
	if not fallback.is_empty():
		var fallback_solution := find_solution(board, fallback)
		_round_nodes += _search_nodes
		if fallback_solution.size() == tray_count:
			last_solution = _copy_solution(fallback_solution)
			last_diagnostics = _diagnostics(attempts, true, "constructive_fallback", started_usec)
			_log_generation_issue("RoundGenerator used constructive fallback after random attempts.")
			_round_counter += 1
			return fallback

	last_diagnostics = _diagnostics(attempts, true, "no_solution", started_usec)
	_log_generation_issue("RoundGenerator found no solvable round for the current board.")
	_round_counter += 1
	return []

func has_any_solution(board: BoardRules, pieces: Array[PieceData]) -> bool:
	if pieces.is_empty():
		return true
	return not find_solution(board, pieces).is_empty()

## Returns one complete placement sequence. An empty result means no solution;
## callers that need the empty-input identity should use has_any_solution().
func find_solution(board: BoardRules, pieces: Array[PieceData]) -> Array[Dictionary]:
	_search_nodes = 0
	var result: Array[Dictionary] = []
	if board == null or pieces.is_empty():
		return result
	var remaining: Array[int] = []
	for index in range(pieces.size()):
		if pieces[index] == null or pieces[index].cells.is_empty():
			return result
		remaining.append(index)
	var failed_states: Dictionary = {}
	var path: Array[Dictionary] = []
	if _search_solution(board, pieces, remaining, path, failed_states):
		result = _copy_solution(path)
	return result

func _search_solution(board: BoardRules, pieces: Array[PieceData], remaining: Array[int], path: Array[Dictionary], failed_states: Dictionary) -> bool:
	_search_nodes += 1
	if remaining.is_empty():
		return true
	var memo_key := _state_key(board, pieces, remaining)
	if failed_states.has(memo_key):
		return false
	var seen_shapes: Dictionary = {}
	for position in range(remaining.size()):
		var index: int = remaining[position]
		var piece: PieceData = pieces[index]
		if piece == null or piece.cells.is_empty():
			continue
		var identity := _piece_identity(piece)
		if seen_shapes.has(identity):
			continue
		seen_shapes[identity] = true
		for origin in board.get_legal_origins(piece):
			var next := board.duplicate_board()
			next.place(piece, origin, 1)
			next.clear_full_lines()
			path.append({"piece_index": index, "origin": origin})
			var next_remaining: Array[int] = remaining.duplicate()
			next_remaining.remove_at(position)
			if _search_solution(next, pieces, next_remaining, path, failed_states):
				return true
			path.pop_back()
	failed_states[memo_key] = true
	return false

func _constructive_fallback(board: BoardRules, tray_count: int) -> Array[PieceData]:
	_fallback_nodes = 0
	var failed_states: Dictionary = {}
	var chosen: Array[PieceData] = []
	return _constructive_search(board, tray_count, 0, chosen, failed_states)

func _constructive_search(board: BoardRules, tray_count: int, depth: int, chosen: Array[PieceData], failed_states: Dictionary) -> Array[PieceData]:
	_fallback_nodes += 1
	if depth == tray_count:
		var completed: Array[PieceData] = []
		for piece in chosen:
			completed.append(piece.duplicate_piece())
		return completed
	var memo_key := _occupancy_key(board) + "|depth=" + str(depth)
	if failed_states.has(memo_key):
		return []
	for piece in _shape_pool:
		for origin in board.get_legal_origins(piece):
			var next := board.duplicate_board()
			next.place(piece, origin, 1)
			next.clear_full_lines()
			chosen.append(piece.duplicate_piece())
			var result := _constructive_search(next, tray_count, depth + 1, chosen, failed_states)
			chosen.pop_back()
			if result.size() == tray_count:
				return result
	failed_states[memo_key] = true
	return []

func _build_shape_pool(config: GameRulesConfig) -> Array[PieceData]:
	var pool: Array[PieceData] = []
	var seen: Dictionary = {}
	for definition in config.shape_pool:
		var piece: PieceData = null
		if definition is ShapeDefinition:
			piece = definition.to_piece()
		elif definition is PieceData:
			piece = definition.duplicate_piece()
		elif definition is Dictionary:
			piece = PieceData.new(Vector2i.ZERO, definition.get("cells", []), str(definition.get("shape_id", "")))
		if piece == null or not piece.is_valid_for_config(config) or piece.cells.is_empty():
			continue
		var identity := _piece_identity(piece)
		if seen.has(identity):
			continue
		seen[identity] = true
		pool.append(piece)
	return pool

func _piece_identity(piece: PieceData) -> String:
	var coords := PackedStringArray()
	for cell in piece.cells:
		coords.append("%d:%d" % [cell.x, cell.y])
	coords.sort()
	return "cells:" + ",".join(coords)

func _candidate_key(pieces: Array[PieceData]) -> String:
	var identities := PackedStringArray()
	for piece in pieces:
		identities.append(_piece_identity(piece))
	identities.sort()
	return "|".join(identities)

func _state_key(board: BoardRules, pieces: Array[PieceData], remaining: Array[int]) -> String:
	var identities := PackedStringArray()
	for index in remaining:
		identities.append(_piece_identity(pieces[index]))
	identities.sort()
	return _occupancy_key(board) + "|pieces=" + "|".join(identities)

func _occupancy_key(board: BoardRules) -> String:
	var key := ""
	for y in range(board.size):
		for x in range(board.size):
			key += "1" if board.get_cell(x, y) != -1 else "0"
	return key

func _copy_solution(solution: Array[Dictionary]) -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for step in solution:
		copy.append(step.duplicate(true))
	return copy

func _diagnostics(attempts: int, fallback_used: bool, reason: String, started_usec: int) -> Dictionary:
	return {
		"seed": seed,
		"round": _round_counter,
		"attempts": attempts,
		"fallback_used": fallback_used,
		"reason": reason,
		"nodes_elapsed": _round_nodes,
		"duplicate_candidates": _duplicate_candidates,
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0
	}

func _log_generation_issue(message: String) -> void:
	if _warning_emitted:
		return
	_warning_emitted = true
	push_warning(message)

