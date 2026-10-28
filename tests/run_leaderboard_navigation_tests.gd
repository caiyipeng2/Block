extends SceneTree

const SAVE := "user://leaderboard-navigation-test.json"
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := SaveRepository.defaults()
	data["reduced_motion"] = true
	data["sound_enabled"] = false
	data["music_enabled"] = false
	data["adventure_highest_completed"] = 3
	SaveRepository.save_data(data, SAVE)
	root.size = Vector2i(1280, 720)
	var main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await process_frame
	_check(main.has_method("_open_leaderboard"), "main routes leaderboard entry")
	if main.has_method("_open_leaderboard"):
		main.menu_controls.get_node("LeaderboardButton").pressed.emit()
		_check(main.screen == "leaderboard", "menu trophy opens leaderboard")
		_check(main.leaderboard_client.selected_mode == "adventure", "first menu entry defaults to adventure")
		main.leaderboard_panel.get_action_button("ProfileButton").pressed.emit()
		_check(main.player_profile_dialog.visible, "profile editor opens from personal row")
		main.player_profile_dialog.get("_cancel").pressed.emit()
		_check(not main.player_profile_dialog.visible and main.screen == "leaderboard", "cancel closes profile without leaving board")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		main._open_player_profile()
		main._input(escape)
		_check(not main.player_profile_dialog.visible and main.screen == "leaderboard", "system-back routing closes top profile only")
		main._show_confirmation("quit")
		main._input(escape)
		_check(main.confirmation_action.is_empty() and main.screen == "leaderboard", "Escape dismisses quit before underlying leaderboard")
		main._cancel_confirmation()
		for profile_open in [false, true]:
			if profile_open:
				main._open_player_profile()
			main._show_confirmation("quit")
			await process_frame
			await process_frame
			var cancel: Button = main.confirmation_dialog.get("_cancel_button")
			var point := cancel.get_global_rect().get_center()
			for pressed in [true, false]:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.position = point
				click.global_position = point
				click.pressed = pressed
				root.push_input(click, true)
			_check(main.confirmation_action.is_empty(), "pointer reaches top quit confirmation with profile=%s" % profile_open)
			main._cancel_confirmation()
			main.player_profile_dialog.close_dialog()
		main._close_leaderboard()
		_check(main.screen == "menu", "back returns to menu")
		main._show_settings()
		main.settings_controls.get_action_button("ProfileButton").pressed.emit()
		await process_frame
		main.player_profile_dialog.get("_input_field").text = "Étoile"
		main.player_profile_dialog.get("_save").pressed.emit()
		_check(not main.player_profile_dialog.visible and main.leaderboard_client.store.data["profile"]["nickname"] == "Étoile", "save profile from settings while editor owns focus")
		main._open_player_profile()
		main.player_profile_dialog.get("_input_field").text = "NewName"
		main.leaderboard_client.store.path = "user://leaderboard-missing-parent/test.json"
		main.player_profile_dialog.get("_save").pressed.emit()
		_check(main.player_profile_dialog.visible and main.player_profile_dialog.get("_error").text == "本机存档保存失败，请重试", "failed profile save keeps dialog open with storage error")
		_check(main.leaderboard_client.store.data["profile"]["nickname"] == "Étoile" and not main.player_profile_dialog.get("_save").disabled, "failed profile save retains accepted name and permits retry")
		main.leaderboard_client.store.path = SAVE + ".leaderboard"
		main.player_profile_dialog.get("_save").pressed.emit()
		_check(not main.player_profile_dialog.visible and main.leaderboard_client.store.data["profile"]["nickname"] == "NewName", "profile retry closes only after durable save")
		main._close_settings()
		main._open_levels()
		main.level_select.selected_level = 2
		main._open_leaderboard("adventure")
		main._close_leaderboard()
		_check(main.screen == "levels" and main.level_select.selected_level == 2, "back preserves selected level")
		main._start_game("classic")
		var original = main.game
		main.screen = "game_over"
		main._refresh_controls()
		var result_button: Button = main.gameplay_ui.get("_leaderboard_button")
		_check(result_button.is_visible_in_tree(), "terminal leaderboard action is visible")
		var status_label: Label = main.gameplay_ui.get("_leaderboard_status")
		var actions: HBoxContainer = main.gameplay_ui.get("_overlay_buttons")
		for refresh in range(3):
			main._refresh_controls()
			_check(status_label.get_index() < result_button.get_index() and result_button.get_index() < actions.get_index(), "result action ordering remains stable on refresh %d" % refresh)
		_check(main.gameplay_ui.get("_leaderboard_status").text == "仅保存于本机", "unconfigured result reports local save only")
		result_button.pressed.emit()
		_check(main.screen == "leaderboard" and main.game == original, "result entry does not replace game")
		main._close_leaderboard()
		_check(main.screen == "game_over" and main.game == original, "back restores same result")
		main._open_leaderboard("classic")
		main._play_from_leaderboard("free")
		_check(main.screen == "game" and main.game_mode == "free" and main.game != original, "play action starts selected mode only when clicked")
		_check(not result_button.is_visible_in_tree(), "gameplay hides result leaderboard action")
		main._toggle_pause()
		_check(not result_button.is_visible_in_tree(), "pause hides result leaderboard action")
		main._toggle_pause()
		main._return_to_menu()
		main._open_leaderboard("adventure")
		main._play_from_leaderboard("adventure")
		_check(main.screen == "levels" and main.level_select.selected_level == 4, "continue adventure selects latest unlocked without starting")
	await process_frame
	await process_frame
	main.free()
	await create_timer(0.1).timeout
	for path in [SAVE, SAVE + ".leaderboard"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures == 0:
		print("LEADERBOARD NAVIGATION TESTS PASSED")
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
