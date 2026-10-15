class_name GameState
extends RefCounted

const TutorialTrayBuilder = preload("res://scripts/rules/tutorial_tray_builder.gd")

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
var _tutorial_builder: TutorialTrayBuilder

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
	if objective_type == "collect":
		target_score = 0
	generator.candidate_samples = clampi(int(setup.get("candidate_samples", 1)), 1, 12) if mode == "adventure" else 1
	generator.solution_count_cap = clampi(int(setup.get("solution_count_cap", 8)), 2, 32)
	for entry: Dictionary in setup.get("initial_cells", []):
		board.set_cell(int(entry["x"]), int(entry["y"]), int(entry["color"]))
	if objective_type == "collect":
		for entry in setup.get("target_cells", []):
			var cell := Vector2i(entry)
			if board.get_cell(cell.x, cell.y) >= 0:
				target_cells[cell] = true
		target_total = target_cells.size()
	if _uses_tutorial_supplier():
		_tutorial_builder = TutorialTrayBuilder.new(rules_config)
		_fill_tutorial_tray(rules_config.tray_count)
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
	for cell in clear_result["cells"]:
		if target_cells.erase(cell):
			collected_targets.append(cell)
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
	if _objective_complete():
		status = Status.LEVEL_COMPLETE
	elif remaining_pieces.is_empty():
		round_index += 1
		if _uses_tutorial_supplier():
			_fill_tutorial_tray(rules_config.tray_count)
		else:
			remaining_pieces = generator.generate_solvable_round(board)
			generation_diagnostics = generator.last_diagnostics.duplicate(true)
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
		"tutorial": _uses_tutorial_supplier(),
		"generation_diagnostics": generation_diagnostics.duplicate(true),
		"level_complete": status == Status.LEVEL_COMPLETE,
		"collected_targets": collected_targets,
		"objective_type": objective_type,
		"target_total": target_total,
		"target_collected": target_collected,
		"target_remaining": target_cells.size(),
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
		"tutorial": _uses_tutorial_supplier(),
		"score": scoring.score if scoring != null else 0,
		"combo": scoring.combo if scoring != null else 0,
		"collected_targets": [],
		"objective_type": objective_type,
		"target_total": target_total,
		"target_collected": target_collected,
		"target_remaining": target_cells.size(),
	}

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

