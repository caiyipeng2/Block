class_name GameState
extends RefCounted

const TutorialTrayBuilder = preload("res://scripts/rules/tutorial_tray_builder.gd")
const ModeCatalog = preload("res://scripts/modes/mode_catalog.gd")
const TARGET_KINDS := ["red_star", "gold_gem"]

enum Status { PLAYING, GAME_OVER, LEVEL_COMPLETE }

var rules_config: GameRulesConfig
var board: BoardRules
var remaining_pieces: Array[PieceData] = []
var scoring: Scoring
var generator: RoundGenerator
var status: Status = Status.PLAYING
var round_index: int = 0
var total_cleared_lines: int = 0
var total_placed_cells: int = 0
var total_cleared_cells: int = 0
var total_moves: int = 0
var generation_diagnostics: Dictionary = {}
## Breakdown of the most recent legal placement. Invalid moves do not overwrite it.
var last_placement_points: int = 0
var last_clear_points: int = 0
var last_clear_lines: int = 0
var mode := "free"
var level_id := 0
var target_score := 0
## Markers are presentation-independent coordinates on the initial occupied board.
var objective_type := "score"
var target_cells: Dictionary = {}
var target_total := 0
var target_collected := 0
var target_counts: Dictionary = {"red_star": 0, "gold_gem": 0}
var target_collected_counts: Dictionary = {"red_star": 0, "gold_gem": 0}
var target_remaining_counts: Dictionary = {"red_star": 0, "gold_gem": 0}
var difficulty_label := ""
var _tutorial_builder: TutorialTrayBuilder
var _collection_targets_valid := true
var _certified_rounds: Array[Dictionary] = []
var _next_certified_round := 0
var _plan_deviated := false

func _init(initial_seed: int = 0, board_size: int = 8, config: GameRulesConfig = null, setup: Dictionary = {}) -> void:
	rules_config = config if config != null else GameRulesConfig.new()
	var effective_size := board_size
	if config != null:
		effective_size = config.board_size
	else:
		rules_config.board_size = effective_size
	board = BoardRules.new(effective_size)
	scoring = Scoring.new(rules_config)
	generator = RoundGenerator.new(initial_seed, rules_config)
	mode = str(setup.get("mode", "free"))
	level_id = maxi(0, int(setup.get("level_id", 0)))
	target_score = maxi(0, int(setup.get("target_score", 0))) if mode == "adventure" else 0
	objective_type = "collect" if mode == "adventure" and str(setup.get("objective_type", "score")) == "collect" else "score"
	difficulty_label = str(setup.get("difficulty_label", ""))
	if objective_type == "collect":
		target_score = 0
	generator.candidate_samples = clampi(int(setup.get("candidate_samples", 1)), 1, 12) if mode == "adventure" else 1
	generator.solution_count_cap = clampi(int(setup.get("solution_count_cap", 8)), 2, 32)
	for entry: Dictionary in setup.get("initial_cells", []):
		board.set_cell(int(entry["x"]), int(entry["y"]), int(entry["color"]))
	if objective_type == "collect":
		_read_collection_targets(setup)
	if _uses_tutorial_supplier():
		_tutorial_builder = TutorialTrayBuilder.new(rules_config)
		_fill_tutorial_tray(rules_config.tray_count)
	elif objective_type == "collect" and setup.has("certified_rounds"):
		if _accept_collection_plan(setup):
			generation_diagnostics = setup.get("initial_diagnostics", {}).duplicate(true)
			generation_diagnostics["planned_route_active"] = true
			generation_diagnostics["certified_round"] = 0
		else:
			generation_diagnostics = {"reason": "invalid_collection_route", "solution_certified": false}
	elif _accept_initial_tray(setup):
		generation_diagnostics = setup.get("initial_diagnostics", {}).duplicate(true)
		if mode == "adventure" and objective_type != "collect" and generator.candidate_samples > 1:
			remaining_pieces = generator.generate_solvable_round(board, remaining_pieces)
			generation_diagnostics["difficulty_selection"] = generator.last_diagnostics.duplicate(true)
	elif objective_type == "collect":
		# A generic solvable tray does not prove these particular markers can be
		# collected. Reject a broken recipe rather than silently losing its proof.
		generation_diagnostics = {"reason": "invalid_collection_route", "solution_certified": false}
	else:
		remaining_pieces = generator.generate_solvable_round(board)
		generation_diagnostics = generator.last_diagnostics.duplicate(true)
	if remaining_pieces.is_empty():
		status = Status.GAME_OVER

func _accept_initial_tray(setup: Dictionary) -> bool:
	if objective_type == "collect" and not _collection_targets_valid:
		return false
	var pieces: Array[PieceData] = []
	for piece in setup.get("initial_pieces", []):
		if not piece is PieceData or not piece.is_valid_for_config(rules_config):
			return false
		pieces.append(piece.duplicate_piece())
	if pieces.size() != rules_config.tray_count:
		return false
	var path: Array = setup.get("initial_solution", [])
	if path.size() != pieces.size():
		return false
	var check := board.duplicate_board()
	var seen := {}
	var uncleared_targets := target_cells.duplicate()
	for step: Dictionary in path:
		var index := int(step.get("piece_index", -1))
		var origin: Vector2i = step.get("origin", Vector2i(-99, -99))
		if index < 0 or index >= pieces.size() or seen.has(index) or not check.can_place(pieces[index], origin):
			return false
		seen[index] = true
		check.place(pieces[index], origin, 0)
		var cleared := check.clear_full_lines()
		for cell in cleared["cells"]:
			uncleared_targets.erase(cell)
	if objective_type == "collect" and (target_total == 0 or not uncleared_targets.is_empty()):
		return false
	remaining_pieces = pieces
	generator.last_solution.assign(path)
	return true

func has_legal_move_for_any_remaining_piece() -> bool:
	for piece in remaining_pieces:
		if not board.get_legal_origins(piece).is_empty():
			return true
	return false

func place_piece(piece_index: int, origin: Vector2i, color_id: int = 0) -> Dictionary:
	if status != Status.PLAYING or piece_index < 0 or piece_index >= remaining_pieces.size():
		return _invalid_move_result("unavailable")
	var piece := remaining_pieces[piece_index]
	if not board.can_place(piece, origin):
		return _invalid_move_result("illegal")
	var placed_cells: Array[Vector2i] = []
	for local_cell in piece.cells:
		placed_cells.append(origin + local_cell)
	board.place(piece, origin, color_id)
	var clear_result := board.clear_full_lines()
	var collected_targets: Array[Vector2i] = []
	var collected_target_events: Array[Dictionary] = []
	for cell in clear_result["cells"]:
		if target_cells.has(cell):
			var kind := str(target_cells[cell])
			target_cells.erase(cell)
			collected_targets.append(cell)
			collected_target_events.append({"cell": cell, "kind": kind})
			target_collected_counts[kind] = int(target_collected_counts[kind]) + 1
			target_remaining_counts[kind] = int(target_remaining_counts[kind]) - 1
	target_collected += collected_targets.size()
	var cleared_lines: int = clear_result["rows"] + clear_result["columns"]
	var scoring_result := scoring.apply_move(placed_cells.size(), clear_result["cells"].size(), cleared_lines)
	var placement_points: int = scoring_result["placement_points"]
	var clear_points: int = scoring_result["clear_points"]
	var gained: int = scoring_result["gained"]
	last_placement_points = placement_points
	last_clear_points = clear_points
	last_clear_lines = cleared_lines
	total_cleared_lines += cleared_lines
	total_placed_cells += placed_cells.size()
	total_cleared_cells += clear_result["cells"].size()
	total_moves += 1
	remaining_pieces.remove_at(piece_index)
	var round_refilled := false
	var tray_adapted := false
	var certified_round_supplied := false
	if _objective_complete():
		status = Status.LEVEL_COMPLETE
	elif remaining_pieces.is_empty():
		round_index += 1
		if _uses_tutorial_supplier():
			_fill_tutorial_tray(rules_config.tray_count)
		elif objective_type == "collect" and _supply_certified_round():
			certified_round_supplied = true
		else:
			remaining_pieces = generator.generate_solvable_round(board)
			generation_diagnostics = generator.last_diagnostics.duplicate(true)
			if _plan_deviated:
				generation_diagnostics["certified_plan_deviated"] = true
				generation_diagnostics["planned_route_active"] = false
		round_refilled = not remaining_pieces.is_empty()
		if remaining_pieces.is_empty():
			status = Status.GAME_OVER
	elif _uses_tutorial_supplier():
		# After a player's different choice, certify the whole remaining tray,
		# not just one currently legal move. Only replace it when that path died.
		var remaining_solution := generator.find_solution(board, remaining_pieces)
		if remaining_solution.size() != remaining_pieces.size():
			_fill_tutorial_tray(remaining_pieces.size(), remaining_pieces)
			tray_adapted = true
			if remaining_pieces.is_empty():
				status = Status.GAME_OVER
		else:
			generator.last_solution.assign(remaining_solution)
	elif not has_legal_move_for_any_remaining_piece():
		status = Status.GAME_OVER
	return {
		"ok": true,
		"clear": clear_result,
		"placement_points": placement_points,
		"clear_points": clear_points,
		"last_placement_points": last_placement_points,
		"last_clear_points": last_clear_points,
		"last_clear_lines": last_clear_lines,
		"gained": gained,
		"score": scoring_result["score"],
		"combo": scoring_result["combo"],
		"round_index": round_index,
		"total_cleared_lines": total_cleared_lines,
		"total_placed_cells": total_placed_cells,
		"total_cleared_cells": total_cleared_cells,
		"total_moves": total_moves,
		"placed_cells": placed_cells,
		"placed_color": color_id,
		"round_refilled": round_refilled,
		"tray_adapted": tray_adapted,
		"certified_round_supplied": certified_round_supplied,
		"tutorial": _uses_tutorial_supplier(),
		"generation_diagnostics": generation_diagnostics.duplicate(true),
		"level_complete": status == Status.LEVEL_COMPLETE,
		"collected_targets": collected_targets,
		"collected_target_events": collected_target_events,
		"objective_type": objective_type,
		"target_total": target_total,
		"target_collected": target_collected,
		"target_remaining": target_cells.size(),
		"target_counts": target_counts.duplicate(),
		"target_collected_counts": target_collected_counts.duplicate(),
		"target_remaining_counts": target_remaining_counts.duplicate(),
		"difficulty_label": difficulty_label,
		"status": status
	}

func _invalid_move_result(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"placement_points": 0,
		"clear_points": 0,
		"last_placement_points": last_placement_points,
		"last_clear_points": last_clear_points,
		"last_clear_lines": last_clear_lines,
		"gained": 0,
		"tray_adapted": false,
		"certified_round_supplied": false,
		"tutorial": _uses_tutorial_supplier(),
		"score": scoring.score if scoring != null else 0,
		"combo": scoring.combo if scoring != null else 0,
		"collected_targets": [],
		"collected_target_events": [],
		"objective_type": objective_type,
		"target_total": target_total,
		"target_collected": target_collected,
		"target_remaining": target_cells.size(),
		"target_counts": target_counts.duplicate(),
		"target_collected_counts": target_collected_counts.duplicate(),
		"target_remaining_counts": target_remaining_counts.duplicate(),
		"difficulty_label": difficulty_label,
	}

func _read_collection_targets(setup: Dictionary) -> void:
	var supplied = setup.get("target_cells", [])
	if not supplied is Array and not supplied is Dictionary:
		_collection_targets_valid = false
		return
	var typed_targets := supplied is Dictionary
	for entry in supplied:
		if typeof(entry) != TYPE_VECTOR2I:
			_collection_targets_valid = false
			continue
		var cell: Vector2i = entry
		var kind := str(supplied[entry]) if typed_targets else "red_star"
		if not TARGET_KINDS.has(kind) or board.get_cell(cell.x, cell.y) < 0:
			_collection_targets_valid = false
			continue
		if target_cells.has(cell):
			continue
		target_cells[cell] = kind
		target_counts[kind] = int(target_counts[kind]) + 1
	target_total = target_cells.size()
	target_remaining_counts = target_counts.duplicate()
	if typed_targets and setup.has("target_total") and int(setup["target_total"]) != target_total:
		_collection_targets_valid = false
	if setup.has("target_counts"):
		var declared = setup["target_counts"]
		if not declared is Dictionary:
			_collection_targets_valid = false
		else:
			for key in declared:
				if not TARGET_KINDS.has(str(key)):
					_collection_targets_valid = false
			for kind in TARGET_KINDS:
				if int(declared.get(kind, 0)) != int(target_counts[kind]):
					_collection_targets_valid = false

## Validate every supplied round against the initial board, including the
## ordinary padding pieces after the final target. Never trust a diagnostic
## flag in lieu of this complete replay.
func _accept_collection_plan(setup: Dictionary) -> bool:
	if not _collection_targets_valid or target_total <= 0:
		return false
	var plan = setup.get("certified_rounds", [])
	if not plan is Array or plan.is_empty() or plan.size() > 8:
		return false
	var check := board.duplicate_board()
	var uncleared := target_cells.duplicate()
	var configured := _configured_shape_keys()
	var verified: Array[Dictionary] = []
	for entry in plan:
		if not entry is Dictionary:
			return false
		if str(entry.get("occupancy_key", "")) != ModeCatalog.occupancy_key(check) or str(entry.get("target_key", "")) != ModeCatalog.target_key(uncleared):
			return false
		var pieces: Array[PieceData] = []
		for piece in entry.get("pieces", []):
			if not piece is PieceData or not piece.is_valid_for_config(rules_config) or not configured.has(_normal_piece_key(piece)):
				return false
			pieces.append(piece.duplicate_piece())
		if pieces.size() != rules_config.tray_count:
			return false
		var path: Array = entry.get("solution", [])
		if path.size() != pieces.size():
			return false
		var seen: Dictionary = {}
		for step: Dictionary in path:
			var index := int(step.get("piece_index", -1))
			var origin: Vector2i = step.get("origin", Vector2i(-99, -99))
			if index < 0 or index >= pieces.size() or seen.has(index) or not check.can_place(pieces[index], origin):
				return false
			seen[index] = true
			check.place(pieces[index], origin, 0)
			var cleared := check.clear_full_lines()
			for cell in cleared["cells"]:
				uncleared.erase(cell)
		verified.append({"occupancy_key": entry["occupancy_key"], "target_key": entry["target_key"], "pieces": pieces, "solution": path.duplicate(true)})
	if not uncleared.is_empty():
		return false
	_certified_rounds = verified
	_next_certified_round = 1
	_assign_certified_tray(_certified_rounds[0])
	return true

func _supply_certified_round() -> bool:
	if _certified_rounds.is_empty() or _next_certified_round >= _certified_rounds.size():
		return false
	var next := _certified_rounds[_next_certified_round]
	if str(next["occupancy_key"]) != ModeCatalog.occupancy_key(board) or str(next["target_key"]) != ModeCatalog.target_key(target_cells):
		# Alternative play is permitted, but its new board no longer carries the
		# recorded proof. Fall back to normal solvable generation from here on.
		_certified_rounds.clear()
		_next_certified_round = 0
		_plan_deviated = true
		return false
	_assign_certified_tray(next)
	generation_diagnostics = {
		"reason": "certified_collection_round", "seed": generator.seed,
		"round": round_index, "certified_round": _next_certified_round,
		"certified_round_count": _certified_rounds.size(),
		"solution_certified": true, "target_route_certified": true,
		"planned_route_active": true,
	}
	generator.last_diagnostics = generation_diagnostics.duplicate(true)
	_next_certified_round += 1
	return true

func _assign_certified_tray(entry: Dictionary) -> void:
	remaining_pieces.clear()
	for piece: PieceData in entry["pieces"]:
		remaining_pieces.append(piece.duplicate_piece())
	generator.last_solution.assign(entry["solution"])

func _configured_shape_keys() -> Dictionary:
	var keys: Dictionary = {}
	for definition in rules_config.shape_pool:
		var piece: PieceData = null
		if definition is ShapeDefinition:
			piece = definition.to_piece()
		elif definition is PieceData:
			piece = definition
		elif definition is Dictionary:
			piece = PieceData.new(Vector2i.ZERO, definition.get("cells", []))
		if piece != null and piece.is_valid_for_config(rules_config):
			keys[_normal_piece_key(piece)] = true
	return keys

func _normal_piece_key(piece: PieceData) -> String:
	var minimum := piece.cells[0]
	for cell in piece.cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
	var coordinates := PackedStringArray()
	for cell in piece.cells:
		coordinates.append("%d:%d" % [cell.x - minimum.x, cell.y - minimum.y])
	coordinates.sort()
	return ";".join(coordinates)

func _uses_tutorial_supplier() -> bool:
	return mode == "adventure" and objective_type == "score" and (level_id == 1 or level_id == 2)

func _fill_tutorial_tray(count: int, preferred_pieces: Array[PieceData] = []) -> void:
	var supplied := _tutorial_builder.build(board, count, preferred_pieces)
	remaining_pieces.assign(supplied["pieces"])
	generator.last_solution.assign(supplied["solution"])
	generation_diagnostics = supplied["diagnostics"].duplicate(true)
	generation_diagnostics["seed"] = generator.seed
	generation_diagnostics["round"] = round_index
	generator.last_diagnostics = generation_diagnostics.duplicate(true)

func _objective_complete() -> bool:
	if mode != "adventure":
		return false
	if objective_type == "collect":
		return target_total > 0 and target_cells.is_empty()
	return target_score > 0 and scoring.score >= target_score

func is_game_over() -> bool:
	return status == Status.GAME_OVER

func is_level_complete() -> bool:
	return status == Status.LEVEL_COMPLETE

