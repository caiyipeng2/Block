class_name GameState
extends RefCounted

enum Status { PLAYING, GAME_OVER }

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

func _init(initial_seed: int = 0, board_size: int = 8, config: GameRulesConfig = null) -> void:
	rules_config = config if config != null else GameRulesConfig.new()
	var effective_size := board_size
	if config != null:
		effective_size = config.board_size
	else:
		rules_config.board_size = effective_size
	board = BoardRules.new(effective_size)
	scoring = Scoring.new(rules_config)
	generator = RoundGenerator.new(initial_seed, rules_config)
	remaining_pieces = generator.generate_solvable_round(board)
	generation_diagnostics = generator.last_diagnostics.duplicate(true)
	if remaining_pieces.is_empty():
		status = Status.GAME_OVER

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
	if remaining_pieces.is_empty():
		round_index += 1
		remaining_pieces = generator.generate_solvable_round(board)
		generation_diagnostics = generator.last_diagnostics.duplicate(true)
		round_refilled = not remaining_pieces.is_empty()
		if remaining_pieces.is_empty():
			status = Status.GAME_OVER
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
		"generation_diagnostics": generation_diagnostics.duplicate(true),
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
		"score": scoring.score if scoring != null else 0,
		"combo": scoring.combo if scoring != null else 0,
	}

func is_game_over() -> bool:
	return status == Status.GAME_OVER

