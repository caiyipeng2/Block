extends RefCounted

## A bounded preview of ordinary pieces. This never moves the live board or
## awards predicted clears; the returned path only certifies the current tray.
const BEAM_WIDTH := 8
const DEFAULT_EVALUATION_BUDGET := 6500

var evaluation_budget := DEFAULT_EVALUATION_BUDGET
var _config: GameRulesConfig
var _pool: Array[PieceData] = []
var _rng := RandomNumberGenerator.new()
var _evaluated := 0
var _budget_exhausted := false

func _init(config: GameRulesConfig, initial_seed: int = 0) -> void:
	_config = config
	_rng.seed = initial_seed
	for definition in config.shape_pool:
		var piece: PieceData = null
		if definition is ShapeDefinition:
			piece = definition.to_piece()
		elif definition is PieceData:
			piece = definition.duplicate_piece()
		elif definition is Dictionary:
			piece = PieceData.new(Vector2i.ZERO, definition.get("cells", []), str(definition.get("shape_id", "")))
		if piece != null and piece.is_valid_for_config(config):
			_pool.append(piece.duplicate_piece())

func build(board: BoardRules, generator: RoundGenerator, score_limit: int = 1500) -> Dictionary:
	_evaluated = 0
	_budget_exhausted = false
	var started_usec := Time.get_ticks_usec()
	var beam: Array[Dictionary] = []
	var complete: Array[Dictionary] = []
	if board != null and _config.tray_count > 0 and not _pool.is_empty():
		beam.append({
			"board": board.duplicate_board(), "pieces": [], "solution": [],
			"clear_steps": [], "first_lines": 0, "lines": 0,
			"single_moves": 0, "multiline_moves": 0, "clear_moves": 0,
			"consecutive": 0, "last_clear": false, "first_clear_step": 0,
			"root_shape": -1, "setup": 0, "tie": 0.0,
		})
		for depth in range(_config.tray_count):
			var candidates: Array[Dictionary] = []
			for state in beam:
				_expand(state, depth, candidates)
				if _budget_exhausted:
					break
			if _budget_exhausted or candidates.is_empty():
				break
			if depth == _config.tray_count - 1:
				complete = candidates
				break
			beam = _select_beam(candidates)
	if not _budget_exhausted and not complete.is_empty():
		complete.sort_custom(_better)
		var best: Dictionary = complete[0]
		var pieces := _copy_pieces(best["pieces"])
		var solution: Array[Dictionary] = []
		solution.assign(best["solution"].duplicate(true))
		if _certify(board, pieces, solution):
			return {
				"pieces": pieces, "solution": solution,
				"diagnostics": {
					"seed": generator.seed, "opening_assist": true, "threshold": score_limit,
					"reason": "opening_clear_friendly", "solution_certified": true,
					"certification_scope": "current_tray", "fallback_used": false,
					"predicted_clear_lines": best["lines"],
					"predicted_single_line_moves": best["single_moves"],
					"predicted_multiline_moves": best["multiline_moves"],
					"predicted_clear_moves": best["clear_moves"],
					"predicted_consecutive_clear_pairs": best["consecutive"],
					"predicted_first_clear_step": best["first_clear_step"],
					"predicted_clear_steps": best["clear_steps"].duplicate(),
					"beam_width": BEAM_WIDTH, "evaluation_budget": maxi(0, evaluation_budget),
					"evaluated_origins": _evaluated, "budget_exhausted": false,
					"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
				},
			}
	# A limited preview is never proof that the board is dead. Preserve the
	# existing complete generator, including its genuine no-solution outcome.
	var fallback := generator.generate_solvable_round(board)
	var fallback_path: Array[Dictionary] = []
	fallback_path.assign(generator.last_solution.duplicate(true))
	var diagnostics := generator.last_diagnostics.duplicate(true)
	diagnostics["opening_assist"] = false
	diagnostics["opening_assist_requested"] = true
	diagnostics["opening_assist_fallback_reason"] = "budget_exhausted" if _budget_exhausted else "no_certified_complete_path"
	diagnostics["threshold"] = score_limit
	diagnostics["evaluation_budget"] = maxi(0, evaluation_budget)
	diagnostics["evaluated_origins"] = _evaluated
	diagnostics["budget_exhausted"] = _budget_exhausted
	diagnostics["solution_certified"] = _certify(board, fallback, fallback_path)
	return {"pieces": _copy_pieces(fallback), "solution": fallback_path, "diagnostics": diagnostics}

func _expand(state: Dictionary, depth: int, candidates: Array[Dictionary]) -> void:
	var previous: BoardRules = state["board"]
	for shape_index in range(_pool.size()):
		var piece := _pool[shape_index]
		for origin in previous.get_legal_origins(piece):
			if _evaluated >= maxi(0, evaluation_budget):
				_budget_exhausted = true
				return
			_evaluated += 1
			var next := previous.duplicate_board()
			next.place(piece, origin, 0)
			var cleared := next.clear_full_lines()
			var lines: int = cleared["rows"] + cleared["columns"]
			var pieces: Array = state["pieces"].duplicate()
			pieces.append(piece)
			var path: Array = state["solution"].duplicate(true)
			path.append({"piece_index": depth, "origin": origin})
			var clear_steps: Array = state["clear_steps"].duplicate()
			clear_steps.append(lines)
			var total_lines := int(state["lines"]) + lines
			candidates.append({
				"board": next, "pieces": pieces, "solution": path, "clear_steps": clear_steps,
				"first_lines": lines if depth == 0 else state["first_lines"],
				"lines": total_lines,
				"single_moves": int(state["single_moves"]) + int(lines == 1),
				"multiline_moves": int(state["multiline_moves"]) + int(lines > 1),
				"clear_moves": int(state["clear_moves"]) + int(lines > 0),
				"consecutive": int(state["consecutive"]) + int(lines > 0 and bool(state["last_clear"])),
				"last_clear": lines > 0,
				"first_clear_step": depth + 1 if lines > 0 and int(state["first_clear_step"]) == 0 else state["first_clear_step"],
				"root_shape": shape_index if depth == 0 else state["root_shape"],
				"setup": _setup_value(next) if total_lines == 0 else 0, "tie": _rng.randf(),
			})

func _select_beam(candidates: Array[Dictionary]) -> Array[Dictionary]:
	candidates.sort_custom(_better)
	var selected: Array[Dictionary] = []
	var per_shape: Dictionary = {}
	# Keep different first shapes in play so an equally good opening is not
	# always the same template. Seeded ties also explore different locations.
	for state in candidates:
		var root_shape := int(state["root_shape"])
		if int(per_shape.get(root_shape, 0)) >= 2:
			continue
		selected.append(state)
		per_shape[root_shape] = int(per_shape.get(root_shape, 0)) + 1
		if selected.size() == BEAM_WIDTH:
			return selected
	for state in candidates:
		if not selected.has(state):
			selected.append(state)
			if selected.size() == BEAM_WIDTH:
				break
	return selected

func _better(a: Dictionary, b: Dictionary) -> bool:
	for key in ["first_lines", "lines", "multiline_moves", "consecutive", "clear_moves"]:
		if int(a[key]) != int(b[key]):
			return int(a[key]) > int(b[key])
	if int(a["first_clear_step"]) != int(b["first_clear_step"]):
		return int(a["first_clear_step"]) < int(b["first_clear_step"])
	# Once equally good clear paths exist, seeded ties vary the supplied shapes.
	# Before that point, build near-full lines without sealing isolated holes.
	if int(a["lines"]) == 0 and int(a["setup"]) != int(b["setup"]):
		return int(a["setup"]) > int(b["setup"])
	return float(a["tie"]) > float(b["tie"])

func _setup_value(board: BoardRules) -> int:
	var occupied: Array[Array] = []
	for y in range(board.size):
		var occupied_row: Array[bool] = []
		for x in range(board.size):
			occupied_row.append(board.get_cell(x, y) >= 0)
		occupied.append(occupied_row)
	var pressure := 0
	var adjacency := 0
	var edge_contacts := 0
	var holes := 0
	var narrow := 0
	var minimum := Vector2i(board.size, board.size)
	var maximum := Vector2i(-1, -1)
	for y in range(board.size):
		var row := 0
		var column := 0
		for x in range(board.size):
			column += int(occupied[x][y])
			if occupied[y][x]:
				row += 1
				edge_contacts += int(x == 0 or x == board.size - 1) + int(y == 0 or y == board.size - 1)
				minimum = Vector2i(mini(minimum.x, x), mini(minimum.y, y))
				maximum = Vector2i(maxi(maximum.x, x), maxi(maximum.y, y))
				adjacency += int(x + 1 < board.size and occupied[y][x + 1])
				adjacency += int(y + 1 < board.size and occupied[y + 1][x])
			else:
				var exits := int(x > 0 and not occupied[y][x - 1]) + int(x + 1 < board.size and not occupied[y][x + 1])
				exits += int(y > 0 and not occupied[y - 1][x]) + int(y + 1 < board.size and not occupied[y + 1][x])
				holes += int(exits == 0)
				narrow += int(exits == 1)
		pressure += row * row * row + column * column * column
	var area := 0 if maximum.x < 0 else (maximum.x - minimum.x + 1) * (maximum.y - minimum.y + 1)
	return pressure * 4 + adjacency * 2 + edge_contacts * 6 - area * 3 - holes * 350 - narrow * 20

func _certify(board: BoardRules, pieces: Array[PieceData], solution: Array[Dictionary]) -> bool:
	if board == null or pieces.size() != _config.tray_count or solution.size() != pieces.size() or pieces.is_empty():
		return false
	var replay := board.duplicate_board()
	var used: Dictionary = {}
	for step in solution:
		var index := int(step.get("piece_index", -1))
		var origin: Vector2i = step.get("origin", Vector2i(-99, -99))
		if index < 0 or index >= pieces.size() or used.has(index) or not pieces[index].is_valid_for_config(_config) or not replay.can_place(pieces[index], origin):
			return false
		used[index] = true
		replay.place(pieces[index], origin, 0)
		replay.clear_full_lines()
	return true

func _copy_pieces(pieces: Array) -> Array[PieceData]:
	var copied: Array[PieceData] = []
	for piece: PieceData in pieces:
		copied.append(piece.duplicate_piece())
	return copied
