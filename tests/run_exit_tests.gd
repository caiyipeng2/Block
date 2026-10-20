extends SceneTree

var save_path := ProjectSettings.globalize_path("res://work/verification/exit-save.json")

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var initial := SaveRepository.defaults()
	initial["high_score"] = 80
	if not SaveRepository.save_data(initial, save_path):
		push_error("FAIL: exit fixture could not be saved")
		quit(1)
		return
	var main = load("res://scenes/main.tscn").instantiate()
	main.save_path = save_path
	root.add_child(main)
	await process_frame
	main._start_game()
	main.game.scoring.score = 120
	main._return_to_menu()
	main.quit_requested.connect(_verify_saved_exit.bind(main))
	var button: Button = main.get_node("MenuControls/ExitButton")
	button.pressed.emit()
	if main.confirmation_action != "quit" or main.exiting:
		push_error("FAIL: exit must ask before stopping the game")
		quit(1)
		return
	main.confirmation_dialog.get_ok_button().pressed.emit()

func _verify_saved_exit(main: Control) -> void:
	var loaded := SaveRepository.load_data(save_path)
	if int(loaded["high_score"]) != 120 or main.screen != "menu":
		push_error("FAIL: exit discarded high score or routed incorrectly")
		return
	if main.feedback_audio.music_player.playing or main.feedback_audio.sound_player.playing:
		push_error("FAIL: exit must stop audio before shutting down")
		return
	print("EXIT TEST PASSED")
