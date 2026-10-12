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
		return {"ok": false, "reason": "unavailable"}
	var piece := remaining_pieces[piece_index]
	if not board.can_place(piece, origin):
		return {"ok": false, "reason": "illegal"}
	var placed_cells: Array[Vector2i] = []
	for local_cell in piece.cells:
		placed_cells.append(origin + local_cell)
	board.place(piece, origin, color_id)
	var clear_result := board.clear_full_lines()
	var cleared_lines: int = clear_result["rows"] + clear_result["columns"]
	var gained: int = scoring.apply_clear(clear_result["cells"].size(), cleared_lines)
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
		"gained": gained,
		"score": scoring.score,
		"combo": scoring.combo,
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

func is_game_over() -> bool:
	return status == Status.GAME_OVER

