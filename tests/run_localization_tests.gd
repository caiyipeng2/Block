extends SceneTree

## Headless integration coverage; every write is confined to this test folder.
const L10n := preload("res://scripts/localization/game_locale.gd")
const Repository := preload("res://scripts/persistence/save_repository.gd")
const TEST_DIRECTORY := "res://work/localization-20261020"
const MAIN_SCENE := "res://scenes/main.tscn"

var _failures := 0
var _checks := 0
var _snapshots: Array[Dictionary] = []
var _failure_details: Array[String] = []
var _player_save_existed := false
var _player_save_hash := ""
var _save_path := ""

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_save_path = ProjectSettings.globalize_path(TEST_DIRECTORY.path_join("test-save.json"))
	if DirAccess.make_dir_recursive_absolute(_save_path.get_base_dir()) != OK:
		_check(false, "create isolated localization test directory")
		_finish()
		return
	_player_save_existed = FileAccess.file_exists(Repository.SAVE_PATH)
	if _player_save_existed:
		_player_save_hash = FileAccess.get_sha256(Repository.SAVE_PATH)
	_check(_contains_chinese("设置 · Français") and not _contains_chinese("Level 1 · Complete ×2"), "Chinese detector ignores shared punctuation and Latin accents")
	_test_repository_languages()
	var seed := Repository.defaults()
	seed.merge({"sound_enabled": false, "music_enabled": false, "reduced_motion": true,
		"screen_shake": false, "high_score": 7777, "classic_high_score": 8888,
		"adventure_highest_completed": 5, "adventure_best_scores": {"1": 321, "3": 987}}, true)
	_check(Repository.save_data(seed, _save_path), "seed isolated save before Main.ready")
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	var scene: PackedScene = load(MAIN_SCENE)
	if scene == null:
		_check(false, "load real Main scene")
		_finish()
		return
	var main = scene.instantiate()
	main.save_path = _save_path
	root.add_child(main)
	await _settle()
	_check(main.is_node_ready(), "run after Main.ready")
	_equal(main.save_path, _save_path, "Main uses isolated save")
	_check(not main.feedback_audio.sound_player.playing and not main.feedback_audio.music_player.playing, "test audio remains disabled")
	L10n.clear_missing_keys()
	await _test_error_localization(main)
	await _test_menu_opening_roundtrip(scene)
	for code: String in L10n.SUPPORTED_CODES:
		await _test_language_surfaces(main, code)
	await _test_live_language_roundtrips(main)
	await _test_compact_layouts(main)
	_choose_language(main, "fr")
	await _settle()
	var expected_profile: Dictionary = main.save_data.duplicate(true)
	main.feedback_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	main.free()
	await _settle()
	var reloaded = scene.instantiate()
	reloaded.save_path = _save_path
	root.add_child(reloaded)
	await _settle()
	_equal(L10n.language(), "fr", "fresh Main restores saved French language")
	_equal(reloaded.save_data, expected_profile, "fresh Main restores profile and mode records")
	_snapshot(reloaded, "fr", "reloaded-menu")
	_equal(Array(L10n.missing_keys()), [], "all exercised source keys exist in translation catalog")
	reloaded.feedback_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	reloaded.free()
	await _settle()
	_finish()

func _test_menu_opening_roundtrip(scene: PackedScene) -> void:
	var path := ProjectSettings.globalize_path(TEST_DIRECTORY.path_join("opening-save.json"))
	var profile := Repository.defaults()
	profile.merge({"sound_enabled": false, "music_enabled": false, "reduced_motion": false, "screen_shake": false}, true)
	_check(Repository.save_data(profile, path), "prepare isolated menu opening save")
	var opening_main = scene.instantiate()
	opening_main.save_path = path
	root.add_child(opening_main)
	await _settle()
	var menu: Control = opening_main.menu_controls
	_check(menu.is_opening(), "fresh ordinary menu starts actual opening sequence")
	var epoch: int = menu.get("_epoch")
	var tween: Tween = menu.get("_tween")
	for code: String in ["en", "fr", "zh_CN"]:
		_choose_language(opening_main, code)
		await _settle()
		_check(menu.is_opening(), "language preserves opening visibility")
		_equal(menu.get("_epoch"), epoch, "language does not restart menu opening")
		_equal(menu.get("_tween"), tween, "language preserves menu opening tween")
		_equal(opening_main.game, null, "language cannot activate a menu mode")
		_snapshot(opening_main, code, "live-menu-opening")
	opening_main.feedback_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	opening_main.free()
	await _settle()

func _test_repository_languages() -> void:
	var path := ProjectSettings.globalize_path(TEST_DIRECTORY.path_join("repository-language.json"))
	var legacy := {"version": 1, "high_score": 2468, "classic_high_score": 4567,
		"adventure_highest_completed": 3, "adventure_best_scores": {"2": 765},
		"adventure_retry_failures": {"4": 2}, "sound_enabled": false,
		"music_enabled": false, "reduced_motion": true, "screen_shake": false}
	_write_json(path, legacy)
	var original := FileAccess.get_file_as_string(path)
	var migrated := Repository.load_data(path)
	_equal(migrated["language"], "zh_CN", "old save without language defaults to Chinese")
	for key: String in legacy:
		_equal(migrated[key], legacy[key], "old save preserves %s" % key)
	_equal(FileAccess.get_file_as_string(path), original, "old save is not rewritten on load")
	for code: String in L10n.SUPPORTED_CODES:
		var profile := migrated.duplicate(true)
		profile["language"] = code
		_check(Repository.save_data(profile, path), "persist %s language" % code)
		_equal(Repository.load_data(path), profile, "roundtrip %s preserves progress and settings" % code)
	for invalid: Variant in ["de", "", "EN", null, 3, true, [], {}]:
		var profile := legacy.duplicate(true)
		profile["language"] = invalid
		_write_json(path, profile)
		_equal(Repository.load_data(path)["language"], "zh_CN", "invalid language safely defaults: %s" % str(invalid))

func _test_error_localization(main) -> void:
	var config_error_sources: Array[String] = [
		"仅支持 friendly、mixed 或 pressure",
		"分数教学关不使用额外初始方块，须为 0",
		"分数教学关不使用近胜线，须为 0",
		"分数教学关使用独立教学供块，随机度须为 50",
		"分数教学关使用独立教学供块，须为 mixed",
		"近胜线需要额外初始方块支撑，不能大于 extra_blocks",
	]
	var setup_reasons := [
		"invalid_level_configuration",
		"unknown_collection_template",
		"initial_markers_exceed_actual_template_cells",
		"template_contains_full_line",
		"invalid_shape_pool",
		"board_cannot_fit_initial_tray",
	]
	for code: String in ["en", "fr"]:
		_choose_language(main, code)
		await _settle()
		for source: String in config_error_sources:
			_assert_translated(L10n.t(source), code, "%s translates configuration validation source" % code)
		_check(main.has_method("_localized_setup_reason"), "%s exposes a localized setup reason mapper" % code)
		if main.has_method("_localized_setup_reason"):
			for reason: String in setup_reasons:
				var translated := str(main.call("_localized_setup_reason", reason))
				_check(translated != reason, "%s maps setup reason %s to player text" % [code, reason])
				_assert_translated(translated, code, "%s setup reason %s" % [code, reason])
	var screen_before: String = main.screen
	var game_before = main.game
	_choose_language(main, "zh_CN")
	main._show_level_config_error("fixture error")
	await _settle()
	var body_source := "闯关配置未生效：\n\n%s\n\n请修正 config/adventure_levels.csv 后重新进入选关页。"
	for code: String in ["zh_CN", "en", "fr", "en", "zh_CN"]:
		_choose_language(main, code)
		await _settle()
		_check(main.level_config_dialog.visible, "configuration error dialog stays open after %s switch" % code)
		_equal(main.level_config_dialog.title, L10n.t("关卡配置错误"), "configuration error title refreshes %s" % code)
		_equal(main.level_config_dialog.dialog_text, L10n.t(body_source) % "fixture error", "configuration error body refreshes %s" % code)
		_equal(main.level_config_dialog.get_ok_button().text, L10n.t("知道了"), "configuration error OK refreshes %s" % code)
		_equal(main.screen, screen_before, "configuration error language switch keeps screen")
		_equal(main.game, game_before, "configuration error language switch keeps game")
	_check(main.has_method("_show_initial_setup_error"), "configuration error dialog has a refreshable setup-error entry point")
	if main.has_method("_show_initial_setup_error"):
		_choose_language(main, "zh_CN")
		main.call("_show_initial_setup_error", 3, "unknown_collection_template")
		await _settle()
		_choose_language(main, "en")
		await _settle()
		_assert_translated(main.level_config_dialog.dialog_text, "en", "English setup error dialog refresh")
		_check(not main.level_config_dialog.dialog_text.contains("unknown_collection_template"), "English setup error hides machine reason")
		_choose_language(main, "fr")
		await _settle()
		_assert_translated(main.level_config_dialog.dialog_text, "fr", "French setup error dialog refresh")
		_check(not main.level_config_dialog.dialog_text.contains("unknown_collection_template"), "French setup error hides machine reason")
	main.level_config_dialog.hide()
	var original_rules: GameRulesConfig = main.rules_config
	var broken_rules: GameRulesConfig = original_rules.duplicate(true)
	broken_rules.shape_pool.clear()
	main.rules_config = broken_rules
	for code: String in ["en", "fr"]:
		_choose_language(main, code)
		main._start_game("adventure", 1)
		await _settle()
		_check(main.level_config_dialog.visible, "%s invalid setup opens configuration dialog" % code)
		_assert_translated(main.level_config_dialog.dialog_text, code, "%s invalid setup dialog" % code)
		_check(not main.level_config_dialog.dialog_text.contains("invalid_shape_pool"), "%s invalid setup hides machine reason" % code)
	main.level_config_dialog.hide()
	main.rules_config = original_rules
	_choose_language(main, "zh_CN")
	await _settle()

func _test_language_surfaces(main, code: String) -> void:
	main._show_menu()
	main.menu_controls.finish_opening()
	_choose_language(main, code)
	await _settle()
	_equal(L10n.language(), code, "settings selector activates %s" % code)
	_equal(Repository.load_data(_save_path)["language"], code, "selector persists %s immediately" % code)
	_snapshot(main, code, "menu")
	for definition: Array in [["AdventureButton", "闯关模式"], ["ClassicButton", "经典模式"], ["StartButton", "自由模式"]]:
		var button: Button = main.menu_controls.get_node(NodePath(definition[0]))
		_equal(button.text, L10n.t(definition[1]), "%s menu semantic label %s" % [code, definition[0]])
		if code != "zh_CN":
			_check(button.material is ShaderMaterial, "%s menu replaces baked Chinese face" % code)
			_check(button.get("_localized_title").visible, "%s menu shows translated face title" % code)
	main.save_status_text = "保存失败，进度、最高分和设置仅本次生效。"
	main._refresh_controls()
	_snapshot(main, code, "menu-save-warning")
	main._show_settings()
	await _settle()
	_snapshot(main, code, "menu-settings")
	_equal(main.settings_controls.language_select.selected, L10n.SUPPORTED_CODES.find(code), "language selector matches active locale")
	for index in range(L10n.LANGUAGE_NAMES.size()):
		_equal(main.settings_controls.language_select.get_item_text(index), L10n.LANGUAGE_NAMES[index], "language names keep their native spelling")
	for key: String in ["sound_enabled", "music_enabled", "reduced_motion", "screen_shake"]:
		_equal(main.setting_controls[key].button_pressed, main.save_data[key], "language preserves setting %s" % key)
	_snapshot(main, code, "settings-save-warning")
	main.save_status_text = ""
	main._close_settings()
	main._open_levels()
	main.level_select.call("_select_level", 2)
	await _settle()
	_snapshot(main, code, "level-select")
	main.level_select.set_save_status("进度保存失败，仅本次运行有效")
	_snapshot(main, code, "map-save-warning")
	main.level_select.set_save_status("")
	var selected_before: int = main.level_select.selected_level
	var unlock_epoch_before: int = main.level_select.get("_unlock_epoch")
	for alternate: String in L10n.SUPPORTED_CODES:
		_choose_language(main, alternate)
		await _settle()
		_equal(main.level_select.selected_level, selected_before, "map selection survives %s switch" % alternate)
		_equal(main.level_select.get("_unlock_epoch"), unlock_epoch_before, "language does not reset unlock presentation")
		_snapshot(main, alternate, "selected-map-roundtrip")
	_choose_language(main, code)
	for mode: String in ["free", "classic", "adventure"]:
		main._start_game(mode, 1 if mode == "adventure" else 0)
		_set_sample_score(main)
		await _settle()
		_snapshot(main, code, "%s-hud" % mode)
		_equal(main.gameplay_ui.get("_display_score"), 4321.0, "HUD displays actual %s score" % mode)
		var impact: Control = main.move_feedback.get("_final_impact")
		if not is_instance_valid(impact):
			main.move_feedback.call("_ensure_final_impact")
			impact = main.move_feedback.get("_final_impact")
		impact.play(Vector2(640.0, 300.0), Rect2(380.0, 140.0, 520.0, 520.0), 65.0)
		await _settle()
		_snapshot(main, code, "%s-final-block" % mode)
		var impact_label: Label = impact.get("_label")
		_equal(impact_label.text, L10n.t("Final Block!"), "final block headline translates")
		if code == "fr":
			_check(impact_label.text != "Final Block!", "final block headline is localized in French")
		impact.reset()
		if mode == "adventure":
			_equal(main.gameplay_ui.get("_goal_label").text, L10n.t("第 %d 关 · 目标 %d 分") % [1, main.game.target_score], "score-level objective uses translated numeric template")
		for notice: String in ["这里放不下，再试一个位置", "新纪录！继续挑战", "新的三块，继续！"]:
			main.gameplay_ui.show_notice(notice, "info", true)
			_snapshot(main, code, "%s-notice" % mode)
			_equal(main.gameplay_ui.get("_notice_label").text, L10n.t(notice), "action notice translates immediately")
		main._request_game_settings()
		await _settle()
		_snapshot(main, code, "%s-game-settings" % mode)
		main._close_settings()
		main.paused = true
		main._refresh_controls()
		await _settle()
		_snapshot(main, code, "%s-paused" % mode)
		_equal(main.gameplay_ui.get("_overlay_title").text, L10n.t("已暂停"), "pause heading translates")
		main.paused = false
		main._refresh_controls()
		for action: String in ["restart", "menu", "quit"]:
			main._show_confirmation(action)
			await _settle()
			_snapshot(main, code, "%s-confirm-%s" % [mode, action])
			_check(main.confirmation_dialog.visible and not main.confirmation_dialog.dialog_text.is_empty(), "confirmation displays real action text")
			main._cancel_confirmation()
		main.game.status = GameState.Status.GAME_OVER
		main.screen = "game_over"
		main._refresh_controls()
		await _settle()
		_snapshot(main, code, "%s-game-over" % mode)
		if mode == "adventure":
			main.game.status = GameState.Status.LEVEL_COMPLETE
			main.screen = "level_complete"
			main._refresh_controls()
			await _settle()
			_snapshot(main, code, "score-level-complete")
	main._start_game("adventure", 3)
	main.gameplay_ui.show_objective_intro(main._collection_intro_stats(), false)
	await _settle()
	_snapshot(main, code, "collect-intro")
	_check(main.gameplay_ui.is_objective_intro_visible(), "collection intro is visible")
	var intro_description: String = main.gameplay_ui.get("_intro_description").text
	for kind: String in main.game.target_counts:
		_check(intro_description.contains(str(main.game.target_counts[kind])), "intro contains actual %s quota" % kind)
	main.gameplay_ui.accept_objective_intro()
	_set_sample_score(main)
	await _settle()
	_snapshot(main, code, "collect-hud")
	main.paused = true
	main._refresh_controls()
	await _settle()
	_snapshot(main, code, "collect-paused")
	main.paused = false
	main.game.status = GameState.Status.GAME_OVER
	main.screen = "game_over"
	main._refresh_controls()
	await _settle()
	_snapshot(main, code, "collect-game-over")
	_show_collection_victory(main)
	await _settle()
	_snapshot(main, code, "collect-level-complete")
	_equal(main.gameplay_ui.get("_overlay_title").text, L10n.t("Well Done!"), "collect victory heading translates")
	var final_stats: Dictionary = main.gameplay_ui.get("_stats").duplicate(true)
	final_stats["level_id"] = 96
	final_stats["has_next_level"] = false
	main.gameplay_ui.set_mode("level_complete", final_stats)
	await _settle()
	_snapshot(main, code, "final-level-complete")
	_equal(main.gameplay_ui.get("_next_level_button").text, L10n.t("全部通关"), "last level uses all-levels-complete label")
	_check(main.gameplay_ui.get("_next_level_button").disabled, "last level does not activate a nonexistent next level")
	main.save_status_text = "保存失败，进度、最高分和设置仅本次生效。"
	main._refresh_controls()
	await _settle()
	_snapshot(main, code, "collect-victory-save-warning")
	main.save_status_text = ""
	_equal(Array(L10n.missing_keys()), [], "%s interfaces have no missing source keys" % code)

func _test_live_language_roundtrips(main) -> void:
	main.save_data["reduced_motion"] = false
	main._start_game("adventure", 3)
	_set_sample_score(main)
	var state_before := _game_snapshot(main)
	var intro_epoch: int = main.gameplay_ui.get("_intro_epoch")
	var intro_tween: Tween = main.gameplay_ui.get("_intro_tween")
	_check(is_instance_valid(intro_tween), "intro has a live presentation tween")
	for code: String in ["en", "fr", "zh_CN"]:
		_choose_language(main, code)
		await _settle()
		_equal(_game_snapshot(main), state_before, "switch during intro preserves board/score/tray/counts/level")
		_equal(main.gameplay_ui.get("_intro_epoch"), intro_epoch, "language does not restart collection intro")
		_equal(main.gameplay_ui.get("_intro_tween"), intro_tween, "language preserves live intro tween identity")
		_check(main.gameplay_ui.is_objective_intro_visible(), "intro remains open across language switch")
		_snapshot(main, code, "live-intro-roundtrip")
	main.gameplay_ui.accept_objective_intro()
	main.gameplay_ui.show_notice("新纪录！继续挑战", "record", false)
	var notice_tween: Tween = main.gameplay_ui.get("_notice_tween")
	main.gameplay_ui.show_progress_milestone(50, false)
	var banner: Control = main.gameplay_ui.get("_progress_banner")
	var banner_tween: Tween = banner.get("_tween")
	for code: String in ["en", "fr", "zh_CN"]:
		_choose_language(main, code)
		await _settle()
		_equal(_game_snapshot(main), state_before, "live HUD switch preserves real game state")
		_equal(main.gameplay_ui.get("_notice_tween"), notice_tween, "language preserves current notice lifetime")
		_equal(main.gameplay_ui.get("_notice_label").text, L10n.t("新纪录！继续挑战"), "existing notice relabels in place")
		_equal(banner.get("_percent"), 50, "language preserves milestone percent")
		_equal(banner.get("_tween"), banner_tween, "language does not restart milestone")
		_assert_translated(L10n.t("%d%% Done") % 50, code, "canvas milestone template")
	var praise: Control = main.move_feedback.get("_praise_layer")
	var surviving: Array[Vector2] = []
	praise.play(3, 2, Vector2(640.0, 300.0), Rect2(380.0, 140.0, 520.0, 520.0), 65.0, surviving, 0.0, false, true)
	await _settle()
	var praise_tween: Tween = praise.get("_tween")
	for code: String in ["en", "fr", "zh_CN"]:
		_choose_language(main, code)
		await _settle()
		_equal(praise.get("_tween"), praise_tween, "language preserves active clear praise tween")
		_equal(praise.get("_display_combo"), 3, "language preserves real combo count")
		_equal(praise.get("_detail").text, L10n.t("%d Lines") % 2, "clear praise uses translated actual line count")
		_snapshot(main, code, "live-clear-praise")
	praise.reset()
	_show_collection_victory(main)
	var victory_tween: Tween = main.gameplay_ui.get("_victory_tween")
	_check(is_instance_valid(victory_tween), "victory has a live presentation tween")
	var victory_before := _game_snapshot(main)
	for code: String in ["en", "fr", "zh_CN"]:
		_choose_language(main, code)
		await _settle()
		_equal(_game_snapshot(main), victory_before, "victory relabel preserves completed game snapshot")
		_equal(main.gameplay_ui.get("_victory_tween"), victory_tween, "language does not replay victory tween")
		_snapshot(main, code, "live-victory-roundtrip")
	main.save_data["reduced_motion"] = true
	main._start_game("free")
	_set_sample_score(main)
	main._show_confirmation("restart")
	var modal_before := _game_snapshot(main)
	var dialog_sequence: int = main.confirmation_dialog.get("_open_sequence")
	for code: String in ["en", "fr", "zh_CN"]:
		_choose_language(main, code)
		await _settle()
		_equal(_game_snapshot(main), modal_before, "open modal language switch preserves game state")
		_equal(main.confirmation_dialog.get("_open_sequence"), dialog_sequence, "language does not reopen confirmation")
		_equal(main.confirmation_action, "restart", "language preserves pending confirmation action")
		_snapshot(main, code, "live-confirm-roundtrip")
	main._cancel_confirmation()

func _test_compact_layouts(main) -> void:
	for dimensions: Vector2i in [Vector2i(360, 640), Vector2i(450, 975), Vector2i(720, 1280)]:
		root.size = dimensions
		await _settle()
		for code: String in ["en", "fr"]:
			_choose_language(main, code)
			main._show_settings()
			await _settle()
			_snapshot(main, code, "compact-%s-settings" % str(dimensions))
			main._close_settings()
			main._start_game("adventure", 3)
			main.gameplay_ui.show_objective_intro(main._collection_intro_stats(), false)
			await _settle()
			_check_multiline_visibility(main.gameplay_ui.get("_intro_description"), "%s %s collection description" % [code, dimensions])
			_snapshot(main, code, "compact-%s-collection-intro" % str(dimensions))
			var real_counts: Dictionary = main.game.target_counts.duplicate(true)
			var stress_intro: Dictionary = main._collection_intro_stats().duplicate(true)
			stress_intro["target_counts"] = {"blue_diamond": 999, "gold_gem": 999, "yellow_star": 999, "red_star": 999}
			stress_intro["target_total"] = 3996
			main.gameplay_ui.show_objective_intro(stress_intro, false)
			await _settle()
			_check_multiline_visibility(main.gameplay_ui.get("_intro_description"), "%s %s four-quota description" % [code, dimensions])
			_snapshot(main, code, "compact-%s-max-quota-intro" % str(dimensions))
			_equal(main.game.target_counts, real_counts, "extreme UI fixture cannot alter real target counts")
			main.gameplay_ui.accept_objective_intro()
			main.paused = true
			main._refresh_controls()
			await _settle()
			_check_multiline_visibility(main.gameplay_ui.get("_overlay_best"), "%s %s paused quota summary" % [code, dimensions])
			_snapshot(main, code, "compact-%s-collect-paused" % str(dimensions))
			main.paused = false
			main.game.status = GameState.Status.GAME_OVER
			main.screen = "game_over"
			main._refresh_controls()
			await _settle()
			_check_multiline_visibility(main.gameplay_ui.get("_overlay_best"), "%s %s failed quota summary" % [code, dimensions])
			_snapshot(main, code, "compact-%s-collect-failed" % str(dimensions))
			_show_collection_victory(main)
			await _settle()
			_snapshot(main, code, "compact-%s-victory" % str(dimensions))
			for name: String in ["_next_level_button", "_overlay_restart_button", "_overlay_menu_button"]:
				var button: Button = main.gameplay_ui.get(name)
				_check(button.visible and button.size.x > 0.0, "compact result action remains visible: %s" % name)
				var style := button.get_theme_stylebox("normal")
				var available := button.size.x - style.get_content_margin(SIDE_LEFT) - style.get_content_margin(SIDE_RIGHT)
				var measured := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, button.get_theme_font_size("font_size")).x
				_check(measured <= available + 1.0, "%s compact action fits text width: %s" % [code, button.text])
	root.size = Vector2i(1280, 720)
	await _settle()

func _check_multiline_visibility(label: Label, context: String) -> void:
	var line_count := label.get_line_count()
	var visible_count := label.get_visible_line_count()
	_check(visible_count >= line_count, "%s shows every shaped line (%d/%d), label height=%s" % [context, visible_count, line_count, label.size.y])
	var shaped_height := float(line_count * label.get_line_height()) + float(maxi(line_count - 1, 0) * label.get_theme_constant("line_spacing"))
	_check(label.size.y + 1.0 >= shaped_height, "%s actual label height %s fits shaped multiline height %s" % [context, label.size.y, shaped_height])

func _set_sample_score(main) -> void:
	main.game.scoring.score = 4321
	main.game.scoring.combo = 3
	main.game.total_cleared_lines = 12
	main.game.round_index = 7
	main.game.last_placement_points = 6
	main.game.last_clear_points = 48
	main.game.last_clear_lines = 2
	main.game.board.set_cell(0, 0, 2)
	main._refresh_controls()

func _show_collection_victory(main) -> void:
	main.gameplay_ui.accept_objective_intro()
	main.paused = false
	main.game.status = GameState.Status.LEVEL_COMPLETE
	main.game.target_collected = main.game.target_total
	for kind: String in main.game.target_counts:
		main.game.target_collected_counts[kind] = main.game.target_counts[kind]
		main.game.target_remaining_counts[kind] = 0
		main.display_remaining_counts[kind] = 0
	main.screen = "level_complete"
	main._refresh_controls()

func _choose_language(main, code: String) -> void:
	var picker: OptionButton = main.settings_controls.language_select
	var index := L10n.SUPPORTED_CODES.find(code)
	picker.select(index)
	picker.item_selected.emit(index)

func _game_snapshot(main) -> Dictionary:
	var cells: Array[int] = []
	for y in range(main.game.board.size):
		for x in range(main.game.board.size):
			cells.append(main.game.board.get_cell(x, y))
	var tray: Array = []
	for piece: PieceData in main.game.remaining_pieces:
		tray.append([piece.get_instance_id(), piece.cells.duplicate()])
	return {"game": main.game.get_instance_id(), "board": cells, "tray": tray,
		"score": main.game.scoring.score, "combo": main.game.scoring.combo,
		"level": main.current_level, "selected_level": main.level_select.selected_level,
		"status": main.game.status, "screen": main.screen, "paused": main.paused,
		"target_counts": main.game.target_counts.duplicate(true),
		"collected": main.game.target_collected_counts.duplicate(true),
		"remaining": main.game.target_remaining_counts.duplicate(true),
		"display_remaining": main.display_remaining_counts.duplicate(true)}

func _snapshot(main, code: String, surface: String) -> void:
	var items: Array[Dictionary] = []
	_collect_visible_text(main, code, surface, items)
	_check(not items.is_empty(), "%s %s exposes visible UI text" % [code, surface])
	_snapshots.append({"language": code, "surface": surface, "text": items})

func _collect_visible_text(node: Node, code: String, surface: String, items: Array[Dictionary]) -> void:
	if node is CanvasItem and not node.is_visible_in_tree():
		return
	if node is Window and not node.visible:
		return
	if node is Control:
		var value := ""
		if node is Label or node is Button:
			value = node.text
		var tooltip: String = node.tooltip_text
		if not value.is_empty() or not tooltip.is_empty():
			var item := {"path": str(node.get_path()), "text": value, "tooltip": tooltip}
			if node is Label:
				item["lines"] = node.get_line_count()
				item["visible_lines"] = node.get_visible_line_count()
				item["height"] = node.size.y
				item["font_size"] = node.get_theme_font_size("font_size")
			items.append(item)
			_assert_translated(value, code, "%s %s text" % [surface, node.get_path()])
			_assert_translated(tooltip, code, "%s %s tooltip" % [surface, node.get_path()])
	for child: Node in node.get_children():
		_collect_visible_text(child, code, surface, items)

func _assert_translated(value: String, code: String, label: String) -> void:
	if code != "zh_CN" and not value.is_empty():
		_check(not _contains_chinese(value), "%s has no Chinese residue: %s" % [label, value])

func _contains_chinese(value: String) -> bool:
	for index in range(value.length()):
		var codepoint := value.unicode_at(index)
		if (codepoint >= 0x3400 and codepoint <= 0x4dbf) or (codepoint >= 0x4e00 and codepoint <= 0x9fff) or (codepoint >= 0x20000 and codepoint <= 0x2fa1f):
			return true
	return false

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "open isolated JSON fixture")
	if file != null:
		file.store_string(JSON.stringify(payload))
		file.close()

func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (actual=%s expected=%s)" % [label, str(actual), str(expected)])

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		_failure_details.append(label)
		if _failures <= 40:
			push_error("LOCALIZATION: " + label)

func _finish() -> void:
	_equal(FileAccess.file_exists(Repository.SAVE_PATH), _player_save_existed, "real player save existence remains unchanged")
	if _player_save_existed:
		_equal(FileAccess.get_sha256(Repository.SAVE_PATH), _player_save_hash, "real player save bytes remain unchanged")
	var report := {"checks": _checks, "failures": _failures, "failure_details": _failure_details, "surfaces": _snapshots,
		"player_save_unchanged": FileAccess.file_exists(Repository.SAVE_PATH) == _player_save_existed and (not _player_save_existed or FileAccess.get_sha256(Repository.SAVE_PATH) == _player_save_hash)}
	if not _save_path.is_empty():
		var report_file := FileAccess.open(_save_path.get_base_dir().path_join("localization-report.json"), FileAccess.WRITE)
		if report_file != null:
			report_file.store_string(JSON.stringify(report, "\t"))
			report_file.close()
	print("LOCALIZATION TESTS: %d checks, %d failures, %d UI snapshots" % [_checks, _failures, _snapshots.size()])
	quit(0 if _failures == 0 else 1)
