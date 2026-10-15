extends RefCounted

## Only GameState's first two score levels use this supplier. It never writes
## to the live board or changes scoring, goals, or the global configured pool.
var _ordinary_pool: Array[PieceData] = []
var _ordinary_keys: Dictionary = {}

func _init(config: GameRulesConfig) -> void:
	for definition in config.shape_pool:
		var piece: PieceData = null
		if definition is ShapeDefinition:
			piece = definition.to_piece()
		elif definition is PieceData:
			piece = definition.duplicate_piece()
		elif definition is Dictionary:
			piece = PieceData.new(Vector2i.ZERO, definition.get("cells", []), str(definition.get("shape_id", "")))
		if piece == null or not piece.is_valid_for_config(config):
			continue
		var key := _piece_key(piece)
		if not _ordinary_keys.has(key):
			_ordinary_keys[key] = true
			_ordinary_pool.append(piece)

## Greedy construction visits at most count * (pool size + 3) * board area
## candidate origins. Each chosen placement is replayed before the next one,
## so the returned route certifies the entire tray without tuple enumeration.
func build(board: BoardRules, count: int, preferred_pieces: Array[PieceData] = []) -> Dictionary:
	var pieces: Array[PieceData] = []
	var solution: Array[Dictionary] = []
	var rescue_shapes: Array[String] = []
	var used_preferred: Dictionary = {}
	var used_shapes: Dictionary = {}
	var evaluated := 0
	var replay := board.duplicate_board()
	for index in range(maxi(0, count)):
		var candidates := _candidates(preferred_pieces, used_preferred, false)
		var selected := _best_placement(replay, candidates, used_shapes)
		evaluated += int(selected.get("evaluated", 0))
		if not bool(selected.get("found", false)):
			# A single cell is the final safety net, used only when neither
			# ordinary pieces nor either orientation of a two-cell piece fits.
			for rescue_cells in [2, 1]:
				candidates = _candidates(preferred_pieces, used_preferred, true, rescue_cells)
				selected = _best_placement(replay, candidates, used_shapes)
				evaluated += int(selected.get("evaluated", 0))
				if bool(selected.get("found", false)):
					break
		if not bool(selected.get("found", false)):
			return _result([], [], rescue_shapes, evaluated, count, false)
		var piece: PieceData = selected["piece"]
		var preferred_index: int = selected["preferred_index"]
		# Keep an existing tray instance when possible, preserving its visual
		# identity; newly supplied shapes receive their own PieceData instance.
		pieces.append(piece if preferred_index >= 0 else piece.duplicate_piece())
		if preferred_index >= 0:
			used_preferred[preferred_index] = true
		var key := _piece_key(piece)
		used_shapes[key] = int(used_shapes.get(key, 0)) + 1
		var origin: Vector2i = selected["origin"]
		solution.append({"piece_index": index, "origin": origin})
		replay.place(piece, origin, 0)
		replay.clear_full_lines()
		if piece.cell_count() < 3:
			rescue_shapes.append(piece.shape_id)
	return _result(pieces, solution, rescue_shapes, evaluated, count, true)

func _candidates(preferred: Array[PieceData], used: Dictionary, rescue: bool, rescue_cells: int = 0) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index in range(preferred.size()):
		var piece := preferred[index]
		if piece == null or piece.cells.is_empty() or used.has(index):
			continue
		var key := _piece_key(piece)
		if seen.has(key) or (not rescue and not _ordinary_keys.has(key)) or (rescue and piece.cell_count() != rescue_cells):
			continue
		seen[key] = true
		candidates.append({"piece": piece, "preferred_index": index})
	var pool := _rescue_pool() if rescue else _ordinary_pool
	for piece in pool:
		if rescue and piece.cell_count() != rescue_cells:
			continue
		var key := _piece_key(piece)
		if not seen.has(key):
			seen[key] = true
			candidates.append({"piece": piece, "preferred_index": -1})
	return candidates

func _best_placement(board: BoardRules, candidates: Array[Dictionary], used_shapes: Dictionary) -> Dictionary:
	var best: Dictionary = {"found": false}
	var evaluated := 0
	for candidate in candidates:
		var piece: PieceData = candidate["piece"]
		var key := _piece_key(piece)
		for origin in board.get_legal_origins(piece):
			evaluated += 1
			var next := board.duplicate_board()
			next.place(piece, origin, 0)
			var cleared := next.clear_full_lines()
			var profile := _board_profile(next)
			var ranked := {
				"found": true, "piece": piece, "origin": origin,
				"preferred_index": int(candidate["preferred_index"]),
				"cleared": cleared["cells"].size(),
				"used": int(used_shapes.get(key, 0)),
				"empty": profile["empty"], "closest": profile["closest"],
				"pressure": profile["pressure"],
			}
			if not bool(best["found"]) or _is_better(ranked, best):
				best = ranked
	best["evaluated"] = evaluated
	return best

func _is_better(candidate: Dictionary, current: Dictionary) -> bool:
	if candidate["cleared"] != current["cleared"]:
		return candidate["cleared"] > current["cleared"]
	var candidate_kept := int(candidate["preferred_index"]) >= 0
	var current_kept := int(current["preferred_index"]) >= 0
	if candidate_kept != current_kept:
		return candidate_kept
	if candidate["used"] != current["used"]:
		return candidate["used"] < current["used"]
	if candidate["closest"] != current["closest"]:
		return candidate["closest"] > current["closest"]
	if candidate["pressure"] != current["pressure"]:
		return candidate["pressure"] > current["pressure"]
	return candidate["empty"] > current["empty"]

func _board_profile(board: BoardRules) -> Dictionary:
	var empty := 0
	var closest := 0
	var pressure := 0
	for coordinate in range(board.size):
		var row_count := 0
		var column_count := 0
		for other in range(board.size):
			if board.get_cell(other, coordinate) >= 0:
				row_count += 1
			else:
				empty += 1
			if board.get_cell(coordinate, other) >= 0:
				column_count += 1
		closest = maxi(closest, maxi(row_count, column_count))
		pressure += row_count * row_count + column_count * column_count
	return {"empty": empty, "closest": closest, "pressure": pressure}

func _rescue_pool() -> Array[PieceData]:
	return [
		PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0)], "tutorial_rescue_horizontal2"),
		PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(0, 1)], "tutorial_rescue_vertical2"),
		PieceData.new(Vector2i.ZERO, [Vector2i.ZERO], "tutorial_rescue_single1"),
	]

func _piece_key(piece: PieceData) -> String:
	var minimum := piece.cells[0]
	for cell in piece.cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
	var coordinates := PackedStringArray()
	for cell in piece.cells:
		coordinates.append("%d:%d" % [cell.x - minimum.x, cell.y - minimum.y])
	coordinates.sort()
	return ";".join(coordinates)

func _result(pieces: Array[PieceData], solution: Array[Dictionary], rescue_shapes: Array[String], evaluated: int, requested: int, certified: bool) -> Dictionary:
	return {
		"pieces": pieces, "solution": solution,
		"diagnostics": {
			"tutorial": true,
			"reason": ("tutorial_clear_friendly" if rescue_shapes.is_empty() else "tutorial_rescue") if certified else "tutorial_no_empty_cell",
			"requested_count": requested, "piece_count": pieces.size(),
			"solution_certified": certified, "rescue_count": rescue_shapes.size(),
			"rescue_shapes": rescue_shapes, "evaluated_origins": evaluated,
		},
	}
