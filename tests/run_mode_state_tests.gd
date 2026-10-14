extends SceneTree

## Maintained coverage; normal delivery compiles this script without running it.
var failures := 0

func _initialize() -> void:
	var config := GameRulesConfig.new()
	var line := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	var setup := {
		"mode": "adventure", "level_id": 1, "target_score": 100,
		"initial_cells": [],
		"initial_pieces": [line, line.duplicate_piece(), line.duplicate_piece()],
		"initial_solution": [
			{"piece_index": 0, "origin": Vector2i.ZERO},
			{"piece_index": 1, "origin": Vector2i(3, 0)},
			{"piece_index": 2, "origin": Vector2i(0, 1)},
		],
	}
	var adventure := GameState.new(17, 8, config, setup)
	_check(adventure.scoring.score == 0, "预置与初始托盘不计分")
	for x in range(5):
		adventure.board.set_cell(x, 0, 1)
	# Reaching the goal with the last tray piece must not trigger a fresh round.
	adventure.remaining_pieces = [line]
	var result := adventure.place_piece(0, Vector2i(5, 0), 2)
	_check(bool(result["ok"]) and int(result["gained"]) == 110, "模式复用既有放置加清除计分")
	_check(adventure.is_level_complete() and not adventure.is_game_over(), "达标优先通关")
	_check(not bool(result["round_refilled"]) and adventure.round_index == 0, "通关不补新组三块")
	_check(adventure.remaining_pieces.is_empty(), "最后一块通关后无额外托盘")
	var denied := adventure.place_piece(0, Vector2i.ZERO, 0)
	_check(not bool(denied["ok"]) and adventure.scoring.score == 110, "通关后拒绝继续落子")
	var free_setup := setup.duplicate(true)
	free_setup["mode"] = "free"
	free_setup["target_score"] = 1
	var free := GameState.new(18, 8, config, free_setup)
	var free_move := free.place_piece(0, Vector2i.ZERO, 0)
	_check(bool(free_move["ok"]) and not free.is_level_complete() and free.target_score == 0, "自由模式不受目标限制")
	free_setup["mode"] = "classic"
	var classic := GameState.new(19, 8, config, free_setup)
	classic.place_piece(0, Vector2i.ZERO, 0)
	_check(not classic.is_level_complete() and classic.target_score == 0, "经典模式不受目标限制")
	if failures == 0:
		print("MODE STATE TESTS PASSED")
	quit(0 if failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + message)
