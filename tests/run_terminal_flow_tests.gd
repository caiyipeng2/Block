extends SceneTree

var checks := 0
var failures := 0
var save_path := ProjectSettings.globalize_path("res://work/verification/terminal-save.json")

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var data := SaveRepository.defaults()
	data["sound_enabled"] = false
	data["music_enabled"] = false
	data["adventure_highest_completed"] = 2
	_check(SaveRepository.save_data(data, save_path), "create isolated save")
	root.size = Vector2i(1280, 720)
	var main = load("res://scenes/main.tscn").instantiate()
	main.save_path = save_path
	root.add_child(main)
	await process_frame
	_check(not auto_accept_quit, "system close must wait for confirmation")
	# Keep the regression process alive even before the close-policy fix exists.
	auto_accept_quit = false
	root.close_requested.emit()
	_check(main.confirmation_action == "quit" and not main.exiting, "system close opens quit confirmation")
	main._cancel_confirmation()
	_check(main.screen == "menu" and not main.exiting, "cancel system close keeps menu open")
	main._start_game("adventure", 3)
	root.close_requested.emit()
	_check(main.confirmation_action == "quit", "system close works during objective intro")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	main._input(escape)
	_check(main.confirmation_action.is_empty() and main._objective_intro_open(), "Escape cancels quit before dismissing objective intro")
	main.gameplay_ui.accept_objective_intro()
	main.game.board.set_cell(0, 0, 2)
	for originally_paused in [false, true]:
		main.paused = originally_paused
		main.move_feedback.set_paused(originally_paused)
		root.close_requested.emit()
		root.close_requested.emit()
		_check(main.confirmation_action == "quit" and not main.exiting, "repeated close keeps one confirmation")
		main._cancel_confirmation()
		_check(main.paused == originally_paused and main.game.board.get_cell(0, 0) == 2, "cancel close preserves board and pause state")
	main.paused = false
	main.move_feedback.set_paused(false)
	_test_failure_waits_for_collections(main)
	_test_collections_finish_before_board(main)
	_test_settled_while_settings_open(main)
	await process_frame
	await process_frame
	main.feedback_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	main.free()
	await create_timer(0.1).timeout
	if failures == 0:
		print("TERMINAL FLOW TESTS PASSED (%d checks)" % checks)
	else:
		push_error("TERMINAL FLOW TESTS FAILED: %d / %d" % [failures, checks])
	quit(0 if failures == 0 else 1)

func _prepare_failed_collection(main) -> Dictionary:
	main._start_game("adventure", 3)
	main.gameplay_ui.accept_objective_intro()
	main.game.board = BoardRules.new(8)
	for y in range(8):
		for x in range(8):
			if (x + y) % 2 == 1 or (y == 0 and x >= 2):
				main.game.board.set_cell(x, y, 0)
	main.game.board.set_cell(1, 0, -1)
	main.game.target_cells = {Vector2i(2, 0): "blue_diamond"}
	main.game.target_counts = {"blue_diamond": 2}
	main.game.target_remaining_counts = {"blue_diamond": 2}
	main.game.target_collected_counts = {"blue_diamond": 0}
	main.game.target_total = 2
	main.game.target_collected = 0
	main.display_remaining_counts = {"blue_diamond": 2}
	var domino := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0)], "terminal_domino")
	var square_cells: Array[Vector2i] = []
	for y in range(3):
		for x in range(3):
			square_cells.append(Vector2i(x, y))
	var square := PieceData.new(Vector2i.ZERO, square_cells, "terminal_square")
	main.game.remaining_pieces.assign([domino, square])
	var result: Dictionary = main.game.place_piece(0, Vector2i.ZERO)
	_check(bool(result["ok"]) and main.game.is_game_over() and result["collected_target_events"].size() == 1, "legal clear collects one target and leaves no legal move")
	main._record_level_failure()
	main.input_locked = true
	main.pending_move = result
	main.move_feedback.call("_ensure_collection_layer")
	var flights: Control = main.move_feedback.get("_collection_layer")
	var events: Array[Dictionary] = []
	events.assign(result["collected_target_events"])
	flights.call("enqueue", events, Rect2(0, 0, 400, 400), 50.0, {}, Vector2(200, 20), 0.0, false)
	return {"flights": flights, "failure_count": SaveRepository.level_failure_count(main.save_data, 3)}

func _test_failure_waits_for_collections(main) -> void:
	var fixture := _prepare_failed_collection(main)
	var flights: Control = fixture["flights"]
	main._on_feedback_finished()
	_check(main.screen == "game" and main.move_feedback.has_pending_collections(), "board finish must not reveal failure while targets are flying")
	main._toggle_pause()
	flights.call("_process", 2.0)
	_check(main.screen == "game" and main.display_remaining_counts["blue_diamond"] == 2, "pause freezes remaining target arrivals")
	main._toggle_pause()
	flights.call("_process", 2.0)
	_check(main.screen == "game_over" and not main.move_feedback.has_pending_collections(), "last target arrival advances to failure")
	_check(main.display_remaining_counts["blue_diamond"] == 1, "HUD reaches final remaining quota before failure")
	main._on_collections_settled()
	_check(SaveRepository.level_failure_count(SaveRepository.load_data(save_path), 3) == int(fixture["failure_count"]), "settling failure does not record another retry")

func _test_collections_finish_before_board(main) -> void:
	_prepare_failed_collection(main)
	main.move_feedback.finish_collections()
	_check(main.screen == "game" and main.input_locked, "early target completion still waits for board animation")
	main._on_feedback_finished()
	_check(main.screen == "game_over", "board completion reveals failure when targets already settled")

func _test_settled_while_settings_open(main) -> void:
	_prepare_failed_collection(main)
	main._on_feedback_finished()
	main._request_game_settings()
	main._set_setting("reduced_motion", true)
	_check(main.screen == "settings", "finishing collections cannot replace settings with failure")
	main._close_settings()
	_check(main.screen == "game_over" and not main.paused, "closing settings reveals settled failure")
	main._return_to_menu()
	main._on_collections_settled()
	_check(main.screen == "levels" and main.game == null, "late settled callback cannot reopen a departed game")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
