extends SceneTree

const ModeCatalog = preload("res://scripts/modes/mode_catalog.gd")
const LevelTable = preload("res://scripts/modes/adventure_level_table.gd")
const ClearColorResolver = preload("res://scripts/ui/clear_color_resolver.gd")

var failures := 0
var checks := 0
var save_path := ProjectSettings.globalize_path("res://work/verification/ui-save.json")

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	var main = load("res://scenes/main.tscn").instantiate()
	if main.get("save_path") == null:
		_check(false, "场景必须支持隔离存档路径，测试不得改写玩家存档")
		main.free()
		_finish()
		return
	main.save_path = save_path
	root.add_child(main)
	await process_frame
	_check(main.is_node_ready(), "测试在真实 ready 生命周期之后执行")
	_equal(main.screen, "menu", "启动显示主菜单")
	_check(main.save_data.has("sound_enabled"), "场景加载完整设置")
	await _test_menu_presentation(main)
	var settings_button: Button = main.get_node_or_null("MenuControls/SettingsButton")
	var exit_button: Button = main.get_node_or_null("MenuControls/ExitButton")
	_check(settings_button != null and settings_button.visible, "主菜单显示可聚焦的设置按钮")
	_check(exit_button != null and exit_button.visible, "主菜单显示退出按钮")
	if settings_button != null:
		_check_no_focus_outline(settings_button, "主菜单设置按钮")
	if exit_button != null:
		_check_no_focus_outline(exit_button, "主菜单退出按钮")
	if settings_button == null or exit_button == null:
		main.free()
		_finish()
		return
	settings_button.pressed.emit()
	_equal(main.screen, "settings", "点击原生设置按钮进入设置面板")
	_equal(main.game, null, "设置界面不会创建游戏局面")
	var preview_button: Button = main.settings_controls.get_action_button("PreviewSoundButton")
	_check(preview_button != null and preview_button.visible, "设置提供可见试听音效按钮")
	if preview_button != null:
		_check_no_focus_outline(preview_button, "设置操作按钮")
	if preview_button != null:
		main._set_setting("sound_enabled", true)
		preview_button.pressed.emit()
		_check(main.feedback_audio.sound_player.playing, "试听按钮触发真实音效")
		main._set_setting("sound_enabled", false)
		_check(preview_button.disabled, "音效关闭时试听按钮禁用")
		main._set_setting("sound_enabled", true)
	for key in ["sound_enabled", "music_enabled", "reduced_motion", "screen_shake"]:
		var toggle: CheckButton = main.setting_controls[key]
		_equal(toggle.focus_mode, Control.FOCUS_ALL, "图标开关支持键盘聚焦")
		_check_no_focus_outline(toggle, "设置开关 %s" % key)
		_check(not toggle.text.is_empty(), "图标开关保留中文可访问名称")
		var previous: bool = main.save_data[key]
		toggle.button_pressed = not previous
		_equal(main.save_data[key], not previous, "%s 点击切换" % key)
		if key == "music_enabled":
			_equal(main.feedback_audio.music_player.playing, not previous, "音乐开关实际控制播放器")
		elif key == "sound_enabled":
			main.feedback_audio.play_feedback("place")
			_equal(main.feedback_audio.sound_player.playing, not previous, "音效开关实际控制播放器")
		var stored: Dictionary = SaveRepository.load_data(save_path)
		_equal(stored[key], not previous, "%s 已实际保存" % key)
		toggle.button_pressed = previous
		_equal(main.save_data[key], previous, "%s 再次点击恢复" % key)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	main._input(escape)
	_equal(main.screen, "menu", "Esc 关闭设置而不退出游戏")
	main.menu_controls.finish_opening()
	main.get_node("MenuControls/StartButton").pressed.emit()
	_equal(main.screen, "game", "主菜单开始按钮进入游戏")
	var hud_settings: Button = main.get_node("GameplayControls/PlayingHUD/Actions/SettingsButton")
	var hud_pause: Button = main.get_node("GameplayControls/PlayingHUD/Actions/PauseButton")
	_check_no_focus_outline(hud_settings, "游戏设置齿轮")
	_check_no_focus_outline(hud_pause, "游戏暂停按钮")
	_check_no_focus_outline(main.gameplay_ui.get("_resume_button"), "暂停继续按钮")
	main.game.board.set_cell(0, 0, 2)
	main.get_node("GameplayControls/PlayingHUD/Actions/RestartButton").pressed.emit()
	_equal(main.confirmation_action, "restart", "重新开始先显示确认")
	_check_no_focus_outline(main.confirmation_dialog.get_ok_button(), "确认弹窗主操作")
	_check_no_focus_outline(main.confirmation_dialog.get_cancel_button(), "确认弹窗取消操作")
	_equal(main.game.board.get_cell(0, 0), 2, "确认之前保留棋盘")
	main._cancel_confirmation()
	_equal(main.game.board.get_cell(0, 0), 2, "取消重开仍保留棋盘")
	_check(not main.paused, "取消恢复原来的运行状态")
	main.get_node("GameplayControls/PlayingHUD/Actions/RestartButton").pressed.emit()
	main._confirm_action()
	_equal(main.game.board.get_cell(0, 0), -1, "重新开始会清空本局棋盘")
	_equal(main.game.scoring.score, 0, "重新开始重置本局分数")
	main.get_node("GameplayControls/PlayingHUD/Actions/MenuButton").pressed.emit()
	_equal(main.confirmation_action, "menu", "返回菜单先显示确认")
	_equal(main.screen, "game", "确认之前不会离开游戏")
	main._confirm_action()
	_equal(main.screen, "menu", "常驻返回菜单按钮可用")
	_equal(main.game, null, "返回菜单清理当前局")
	main.menu_controls.finish_opening()
	_test_shared_clear_feedback(main)
	_test_clear_drag_preview(main)
	_test_retry_failure_lifecycle(main)
	# A completed game locks the board while gems arrive, but its result
	# screen must release the primary and secondary navigation buttons.
	main.save_data["adventure_highest_completed"] = 2
	main._start_game("adventure", 3)
	var objective_stats := {"target_counts": main.game.target_counts, "target_total": main.game.target_total}
	var configured_kinds := 0
	for kind: String in LevelTable.TARGET_COLUMNS:
		if int(LevelTable.level(3).get(kind, 0)) > 0:
			configured_kinds += 1
	var visible_kinds: Array = main.gameplay_ui.call("_active_target_kinds", objective_stats)
	_equal(visible_kinds.size(), configured_kinds, "本关只显示配表里配额大于零的目标种类")
	_equal(main.gameplay_ui.call("_target_count", objective_stats, "target_counts", "red_star"), 0, "缺席的红星不按总配额虚构目标")
	main.gameplay_ui.accept_objective_intro()
	main.game.status = GameState.Status.LEVEL_COMPLETE
	main._record_level_completion()
	_equal(SaveRepository.level_failure_count(main.save_data, 3), 0, "通关记录清除本关此前失败辅助")
	main.screen = "level_complete"
	main._refresh_controls()
	var next_level: Button = main.gameplay_ui.get("_next_level_button")
	var result_menu: Button = main.gameplay_ui.get("_overlay_menu_button")
	_check(next_level != null and not next_level.disabled, "通关面板释放下一关按钮")
	_check(result_menu != null and not result_menu.disabled, "通关面板释放返回选关按钮")
	_check_no_focus_outline(next_level, "通关下一关按钮")
	_check_no_focus_outline(result_menu, "通关返回选关按钮")
	next_level.pressed.emit()
	_equal(main.screen, "levels", "下一关先进入选关页展示新关解锁")
	_equal(main.game, null, "进入选关页清理上一关游戏")
	_equal(main.level_select.selected_level, 4, "解锁后默认选择新关卡")
	_equal(main.pending_level_unlock, {}, "解锁表现事件交付选关页后消费")
	main._show_menu()
	var saved_settings: Dictionary = main.save_data.duplicate()
	main.feedback_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	main.free()
	var reloaded = load("res://scenes/main.tscn").instantiate()
	reloaded.save_path = save_path
	root.add_child(reloaded)
	await process_frame
	_equal(reloaded.save_data, saved_settings, "重新创建场景仍加载已保存设置")
	reloaded._set_setting("reduced_motion", true)
	reloaded._show_settings()
	_equal(reloaded.settings_controls.modulate.a, 1.0, "减少动画立即显示设置面板")
	reloaded._show_menu()
	reloaded._set_setting("reduced_motion", false)
	reloaded._show_settings()
	_equal(reloaded.settings_controls.modulate.a, 0.0, "普通模式启动界面淡入")
	await create_timer(0.2).timeout
	_equal(reloaded.settings_controls.modulate.a, 1.0, "界面淡入完成")
	reloaded._show_settings()
	reloaded.save_path = ProjectSettings.globalize_path("res://work/verification/no-parent/settings.json")
	reloaded._toggle_setting("sound_enabled")
	_check(not reloaded.save_status_text.is_empty(), "保存失败显示可见提示")
	reloaded.save_path = save_path
	reloaded._toggle_setting("sound_enabled")
	_check(reloaded.save_status_text.is_empty(), "保存成功清除失败提示")
	reloaded.feedback_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	reloaded.free()
	await create_timer(0.5).timeout
	_finish()

func _test_menu_presentation(main) -> void:
	var menu: Control = main.menu_controls
	_check(menu != null and menu == main.get_node_or_null("MenuControls"), "原生主菜单保留 MenuControls 入口")
	if menu == null:
		return
	var definitions := [
		["AdventureButton", "adventure", "闯关模式"],
		["ClassicButton", "classic", "经典模式"],
		["StartButton", "free", "自由模式"],
	]
	var buttons: Array[Button] = []
	for definition: Array in definitions:
		var button: Button = menu.get_node_or_null(NodePath(definition[0]))
		_check(button != null, "%s 保留原生节点路径" % definition[0])
		if button == null:
			continue
		buttons.append(button)
		_equal(button.text, definition[2], "%s 使用中文模式名称" % definition[0])
		_equal(button.get("mode_kind"), definition[1], "%s 图标由对应模式配置驱动" % definition[0])
		_check(button.has_method("get_face_source_region"), "%s 使用选定效果图的按钮美术" % definition[0])
		_check(str(button.get("subtitle_text")).is_empty(), "%s 只保留主标题" % definition[0])
		_equal(button.focus_mode, Control.FOCUS_ALL, "%s 保留键盘聚焦" % definition[0])
	# Only the first actual presentation may be an opening. Do not override its
	# private latch or wait for wall-clock animations just to exercise a skip.
	if menu.is_opening():
		var skip_press := InputEventMouseButton.new()
		skip_press.button_index = MOUSE_BUTTON_LEFT
		skip_press.pressed = true
		if not buttons.is_empty():
			skip_press.position = buttons[0].get_global_rect().get_center()
		main._input(skip_press)
		_check(not menu.is_opening(), "主入口优先消费点击并结束开屏")
		_equal(main.screen, "menu", "跳过点击不穿透到模式选择")
		_equal(main.game, null, "跳过点击不会创建游戏")
		var skip_release := InputEventMouseButton.new()
		skip_release.button_index = MOUSE_BUTTON_LEFT
		skip_release.pressed = false
		skip_release.position = skip_press.position
		_check(menu.consume_opening_input(skip_release), "跳过点击对应的释放也被消费")
		_equal(main.screen, "menu", "跳过释放后仍停留主菜单")
		_equal(main.game, null, "跳过释放不会启动关卡")
	menu.finish_opening()
	for button: Button in buttons:
		_check(not button.disabled and button.visible, "%s 演出结束后恢复可用" % button.name)
		_equal(button.modulate.a, 1.0, "%s 演出结束后完全显示" % button.name)
		_equal(button.scale, Vector2.ONE, "%s 演出结束后恢复原生尺度" % button.name)
	for button_name in ["SettingsButton", "ExitButton"]:
		var button: Button = menu.get_node_or_null(NodePath(button_name))
		_check(button != null and not button.disabled, "%s 演出结束后可用" % button_name)
	menu.present(true, false)
	_check(not menu.is_opening(), "已展示的菜单不会因再次 present 重播开屏")
	main._show_menu()
	_check(not menu.is_opening(), "返回菜单只播放短过渡，不重播开屏")
	var reduced_motion_before := bool(main.save_data.get("reduced_motion", false))
	main._set_setting("reduced_motion", true)
	_check(not menu.is_opening(), "减少动画立即结束菜单演出")
	for button: Button in buttons:
		_check(not button.disabled and is_equal_approx(button.modulate.a, 1.0), "%s 减少动画不残留禁用或透明状态" % button.name)
	# Exercise compact layout without taking screenshots or relying on font pixels.
	var menu_size_before := menu.size
	menu.size = Vector2(720.0, 560.0)
	await process_frame
	_check(not menu.is_opening(), "菜单改尺寸不会重播开屏")
	for index in range(buttons.size()):
		var button: Button = buttons[index]
		_check(not button.disabled and is_equal_approx(button.modulate.a, 1.0), "%s 改尺寸后保持完整可用" % button.name)
		var button_rect := button.get_rect()
		_check(Rect2(Vector2.ZERO, menu.size).encloses(button_rect), "%s 紧凑布局仍在菜单范围内" % button.name)
		if index > 0:
			_check(not buttons[index - 1].get_rect().intersects(button_rect), "紧凑布局相邻模式按钮不重叠")
	menu.size = menu_size_before
	await process_frame
	main._set_setting("reduced_motion", reduced_motion_before)
	menu.finish_opening()
	_equal(main.screen, "menu", "菜单表现检查结束仍停留主菜单")
	_equal(main.game, null, "菜单表现检查不创建游戏局面")

func _test_shared_clear_feedback(main) -> void:
	var reduced_motion_before := bool(main.save_data.get("reduced_motion", false))
	main._set_setting("reduced_motion", false)
	var rules_before := _feedback_rules_snapshot(main.rules_config)
	var praise: Control = main.move_feedback.get_node("ClearPraise")
	# Enter collect first so this also detects its larger pool or combo tolerance
	# leaking into the shared resource when either ordinary mode starts later.
	main.save_data["adventure_highest_completed"] = 2
	main._start_game("adventure", 3)
	_equal(_feedback_rules_snapshot(main.rules_config), rules_before, "收集模式不改写共用规则资源")
	for line_count in [1, 2, 3, 4]:
		main.game.scoring = Scoring.new(main.game.rules_config)
		main.move_feedback.reset()
		_present_feedback_fixture(main, _feedback_move_fixture(main, line_count))
		var adventure_words := _praise_words(praise)
		var adventure_titles := {1: "Nice!", 2: "Perfect!", 3: "Excellent!", 4: "Unbelievable!"}
		var line_text := "1 Line" if line_count == 1 else "%d Lines" % line_count
		_check(adventure_words.has(adventure_titles[line_count]) and adventure_words.has(line_text), "闯关真实 %d 线显示即时赞语和线数" % line_count)
	main.move_feedback.reset()
	for mode in ["free", "classic"]:
		main._start_game(mode)
		_equal(main.move_feedback.get_node("ClearPraise"), praise, "%s 复用同一个赞语层" % mode)
		_equal(_feedback_rules_snapshot(main.game.rules_config), rules_before, "%s 保留原形状池、计分与严格 Combo 规则" % mode)
		for line_count in [2, 3, 4]:
			main.game.scoring = Scoring.new(main.game.rules_config)
			var fixture := _feedback_move_fixture(main, line_count)
			var result: Dictionary = fixture["result"]
			var context: Dictionary = fixture["context"]
			_check(bool(context["endless_feedback"]), "%s 合法反馈仅按普通模式标识启用奖励表现" % mode)
			var leaked_fields: Array[String] = []
			for field: String in context:
				if field.begins_with("target_") or field.begins_with("collected_") or field.begins_with("objective_target") or field == "level_complete":
					leaked_fields.append(field)
			_equal(leaked_fields, [], "%s 普通反馈不携带收集或目标通关字段" % mode)
			_check(not bool(context["final_block"]) and bool(context["score_flight_enabled"]) and context["objective_type"] == "score", "%s 普通反馈保持计分飞行且不触发 Final Block" % mode)
			_present_feedback_fixture(main, fixture)
			var words := _praise_words(praise)
			var titles := {2: "Perfect!", 3: "Excellent!", 4: "Unbelievable!"}
			_check(words.has(titles[line_count]) and words.has("%d Lines" % line_count), "%s 真实 %d 线进入共用多线赞语" % [mode, line_count])
			_equal(result["combo"], 1, "同手多线只算一次真实 Combo")
			_check(not words.has("1") and not words.has("COMBO"), "多线赞语不伪造额外连击数字")
			_check(not main.move_feedback.has_pending_collections() and not main.move_feedback.get_node("FinalImpact").get("_active") and not main.game.is_level_complete(), "%s 清线不产生收集飞行、末次重落或目标通关" % mode)
			_check_score_above_praise(main.move_feedback, praise, "%s 多线加分" % mode)
		main.game.scoring = Scoring.new(main.game.rules_config)
		main.move_feedback.reset()
		for combo in range(1, 11):
			var fixture := _feedback_move_fixture(main, 1)
			_equal(fixture["result"]["combo"], combo, "%s 第 %d 次连续真实单线的规则 Combo" % [mode, combo])
			_present_feedback_fixture(main, fixture)
			if combo == 1:
				var single_words := _praise_words(praise)
				_check(single_words.has("Nice!") and single_words.has("1 Line") and not single_words.has("1"), "%s 首次单消有清楚反馈且不伪造连击数字" % mode)
			if combo in [2, 4, 7, 10]:
				var titles := {2: "Combo", 4: "Perfect!", 7: "Excellent!", 10: "Unbelievable!"}
				var words := _praise_words(praise)
				_check(words.has(titles[combo]) and words.has(str(combo)) and not words.has("2 Lines"), "%s 连续单线按真实 Combo %d 升阶" % [mode, combo])
		_test_praise_lifecycle(main, praise)
	_equal(_feedback_rules_snapshot(main.rules_config), rules_before, "视觉演出和模式切换后共用规则仍未污染")
	main._set_setting("reduced_motion", reduced_motion_before)
	main.menu_controls.finish_opening()

func _test_praise_lifecycle(main, praise: Control) -> void:
	var feedback: Control = main.move_feedback
	var content: Control = praise.get("_content")
	var progress := float(praise.get("_progress"))
	var ordinary := _feedback_move_fixture(main, 0)
	_equal(ordinary["result"]["combo"], 0, "下一次未清线落子仍按普通模式规则断连")
	_present_feedback_fixture(main, ordinary)
	_check(praise.get("_content") == content and bool(praise.get("_active")) and content.visible, "普通落子保留尚未结束的高阶赞语")
	_equal(praise.get("_progress"), progress, "下一落子不会重播或缩短旧赞语")
	_check_score_above_praise(feedback, praise, "保留赞语时普通落子加分")
	# An actual clear after the miss gets its own single-clear reward. Its
	# words must describe this result rather than retain a stale combo count.
	_present_feedback_fixture(main, _feedback_move_fixture(main, 1))
	_check(_praise_words(praise).has("Nice!") and not _praise_words(praise).has("COMBO"), "断连后的首个单线显示 Nice 且没有虚假连击")
	content = praise.get("_content")
	progress = float(praise.get("_progress"))
	var score_before := int(main.game.scoring.score)
	var combo_before := int(main.game.scoring.combo)
	var invalid: Dictionary = main.game.place_piece(0, Vector2i(-1, -1), 0)
	_check(not invalid["ok"], "回弹夹具先经历真实非法落子")
	feedback.play_rebound(main.game.remaining_pieces[0], Vector2(200, 200), Vector2(200, 600), 40.0, 24.0, Color.WHITE, 0.2, false)
	_check(praise.get("_content") == content and bool(praise.get("_active")) and content.visible, "非法落子回弹不截断未结束赞语")
	_equal(praise.get("_progress"), progress, "非法回弹不会重播旧赞语")
	_equal([main.game.scoring.score, main.game.scoring.combo], [score_before, combo_before], "非法回弹不改分数与 Combo")
	_finish_feedback_snapshot(feedback)
	feedback.reset_move()
	_check_feedback_cleared(feedback, praise, "显式 reset_move")
	var fixture := _feedback_move_fixture(main, 2)
	_present_feedback_fixture(main, fixture)
	_present_feedback_fixture(main, _feedback_move_fixture(main, 0), true)
	_check_feedback_cleared(feedback, praise, "减少动画落子", true)
	_present_feedback_fixture(main, _feedback_move_fixture(main, 2))
	main._set_setting("reduced_motion", true)
	_check_feedback_cleared(feedback, praise, "开启减少动画设置")
	main._set_setting("reduced_motion", false)
	_present_feedback_fixture(main, _feedback_move_fixture(main, 2))
	main.get_node("GameplayControls/PlayingHUD/Actions/RestartButton").pressed.emit()
	_equal(main.confirmation_action, "restart", "赞语存续期间仍可正常确认重开")
	main._confirm_action()
	_check_feedback_cleared(feedback, praise, "确认重开")
	_present_feedback_fixture(main, _feedback_move_fixture(main, 2))
	main.get_node("GameplayControls/PlayingHUD/Actions/MenuButton").pressed.emit()
	_equal(main.confirmation_action, "menu", "赞语存续期间仍可正常确认返回")
	main._confirm_action()
	_check_feedback_cleared(feedback, praise, "确认返回菜单")
	_equal(main.game, null, "返回时释放当前棋局")

func _feedback_move_fixture(main, line_count: int) -> Dictionary:
	# Board/tray fixtures make legal placements deterministic. Scoring and
	# combo always come from place_piece; no praise threshold is injected.
	main.game.board = BoardRules.new(main.game.rules_config.board_size)
	for y in range(line_count):
		for x in range(1, main.game.board.size):
			main.game.board.set_cell(x, y, 0)
	var cells: Array[Vector2i] = []
	for y in range(maxi(line_count, 3)):
		cells.append(Vector2i(0, y))
	var piece := PieceData.new(Vector2i.ZERO, cells, "feedback_test_vertical")
	main.game.remaining_pieces.assign([piece, piece.duplicate_piece(), piece.duplicate_piece()])
	var before: BoardRules = main.game.board.duplicate_board()
	var resolved: BoardRules = before.duplicate_board()
	resolved.place(piece, Vector2i.ZERO, 1)
	var result: Dictionary = main.game.place_piece(0, Vector2i.ZERO, 1)
	_check(bool(result["ok"]) and int(result["clear"]["rows"]) + int(result["clear"]["columns"]) == line_count, "视觉夹具完成真实合法落子与预期清线")
	var appearance: Dictionary = ClearColorResolver.resolve(resolved, {})
	# Supplying a marker here verifies ordinary contexts omit it entirely.
	var context: Dictionary = main._move_feedback_context(result, appearance, {Vector2i(7, 7): "red_star"})
	return {"before": before, "result": result, "context": context}

func _present_feedback_fixture(main, fixture: Dictionary, reduced_motion: bool = false) -> void:
	var feedback: Control = main.move_feedback
	var result: Dictionary = fixture["result"]
	var score_before := int(main.game.scoring.score)
	var combo_before := int(main.game.scoring.combo)
	feedback.set_paused(true)
	feedback.play_move(fixture["before"], result["placed_cells"], result["clear"]["cells"], result["placed_color"], main._board_rect(), main.rules_config.palette, Vector2(0.12, 0.32), result["gained"], reduced_motion, fixture["context"])
	if not reduced_motion and not result["clear"]["cells"].is_empty():
		var praise: Control = feedback.get_node("ClearPraise")
		var previous_content: Control = praise.get("_content")
		feedback._begin_clear()
		_equal(feedback.get("_score_label"), null, "清线加分等赞语定位后再生成")
		feedback._begin_sweep()
		feedback._begin_dispersion()
		if praise.get("_content") != null and praise.get("_content") != previous_content:
			praise._show()
			praise._update_progress(0.25)
	_finish_feedback_snapshot(feedback)
	_equal([main.game.scoring.score, main.game.scoring.combo], [score_before, combo_before], "视觉阶段不再次结算分数或 Combo")

func _finish_feedback_snapshot(feedback: Control) -> void:
	# Drive event boundaries without waiting for or leaving a board Tween that
	# could replay those callbacks after the fixture has been replaced.
	var tween: Tween = feedback.get("_tween")
	if tween != null:
		tween.kill()
	feedback._finish()

func _praise_words(praise: Control) -> PackedStringArray:
	var words := PackedStringArray()
	var content: Control = praise.get("_content")
	if content != null:
		for child in content.get_children():
			if child is Label:
				words.append(child.text)
	return words

func _check_score_above_praise(feedback: Control, praise: Control, message: String) -> void:
	var score: Label = feedback.get("_score_label")
	var reserved: Rect2 = praise.get_reserved_rect()
	_check(score != null and reserved.has_area(), message + "具有真实加分标签和赞语保留区")
	if score == null or not reserved.has_area():
		return
	var score_rect := Rect2(score.position, score.get_minimum_size()).grow(6.0)
	_check(score_rect.end.y <= reserved.position.y and not score_rect.intersects(reserved), message + "起点在赞语保留区上方且不重叠")

func _check_feedback_cleared(feedback: Control, praise: Control, message: String, allow_static_score: bool = false) -> void:
	_check(praise.get("_content") == null and not bool(praise.get("_active")) and not praise.get_reserved_rect().has_area(), message + "完整清理赞语与保留区")
	_check(not feedback.get("_clear_outline").is_active(), message + "清理实际消除的彩虹轮廓")
	_check(not feedback.is_busy() and not feedback.blocks_board and not feedback.has_pending_collections() and not feedback.get_node("FinalImpact").get("_active"), message + "不残留棋盘锁、收集或末次重落")
	if not allow_static_score:
		_equal(feedback.get("_score_label"), null, message + "清理旧加分标签")

func _feedback_rules_snapshot(rules: GameRulesConfig) -> Dictionary:
	var shapes: Array = []
	for shape in rules.shape_pool:
		shapes.append([shape.shape_id, shape.cells.duplicate()])
	return {"board": rules.board_size, "tray": rules.tray_count, "min": rules.min_piece_cells, "max": rules.max_piece_cells, "misses": rules.combo_miss_tolerance, "points": rules.base_points_per_cell, "multiline": rules.multiline_bonus_step, "shapes": shapes, "palette": rules.palette.duplicate()}

func _test_clear_drag_preview(main) -> void:
	var reduced_motion_before := bool(main.save_data.get("reduced_motion", false))
	var rules_before := _feedback_rules_snapshot(main.rules_config)
	main._set_setting("reduced_motion", false)
	for mode in ["free", "classic", "adventure"]:
		main._start_game(mode, 3 if mode == "adventure" else 0)
		main.gameplay_ui.accept_objective_intro()
		_check_preview_cleared(main, "%s 开局不残留上个模式预览" % mode)
		var patterns := ["row", "column"]
		if mode == "adventure":
			patterns.append("cross")
		for pattern in patterns:
			var appearance := _clear_preview_fixture(main, pattern)
			var before := _preview_game_snapshot(main)
			_drag_preview_to(main, Vector2i.ZERO)
			_check(main.drag_valid and main.clear_preview.is_active(), "%s %s 合法满线同时启用变色和光边" % [mode, pattern])
			var spectrum_start: Color = main.clear_preview._edge_color(Vector2.ZERO, 2, true)
			var spectrum_end: Color = main.clear_preview._edge_color(Vector2(0, 7) if pattern == "column" else Vector2(7, 0), 2, true)
			var spectrum_distance := Vector3(spectrum_start.r, spectrum_start.g, spectrum_start.b).distance_to(Vector3(spectrum_end.r, spectrum_end.g, spectrum_end.b))
			_check(spectrum_distance > 0.45, "%s %s 柔和光边沿行列长度仍保持可区分的彩虹" % [mode, pattern])
			_equal(main.preview_clear_colors, appearance["cell_colors"], "%s %s 使用实际消除主色解析结果" % [mode, pattern])
			_equal(main.preview_clear_colors.size(), 15 if pattern == "cross" else 8, "相交行列只预览十五个唯一格，单线为八格")
			_equal(main.preview_clear_colors.values().count(2), main.preview_clear_colors.size(), "拖动块与既有格统一为本组多数主色")
			_equal(_preview_game_snapshot(main), before, "清线预览不改变棋盘、托盘、分数、Combo 或目标")
			_drag_preview_to(main, Vector2i(3, 3))
			_check(main.drag_valid, "普通空位仍允许合法预览")
			_check_preview_cleared(main, "可放但不满线时无清线变色和光框")
			_drag_preview_to(main, Vector2i(7, 7))
			_check(not main.drag_valid, "鼠标在棋盘内但方块越界仍判非法")
			_check_preview_cleared(main, "非法落点不残留先前满线光框")
			_equal(_preview_game_snapshot(main), before, "移动到普通或非法落点也不提前提交规则状态")
		_drag_preview_to(main, Vector2i.ZERO)
		var before := _preview_game_snapshot(main)
		main._set_setting("reduced_motion", true)
		var static_highlight: float = main.clear_preview.highlight(true)
		main._process(0.5)
		_check(main.clear_preview.is_active() and static_highlight > 0.2, "减少动画仍保留可读的静态清线高亮")
		_equal(main.clear_preview.highlight(true), static_highlight, "减少动画的静态高亮不随时间变化")
		main._set_setting("reduced_motion", false)
		main._cancel_drag()
		_check_preview_cleared(main, "取消拖动清理满线预览")
		_drag_preview_to(main, Vector2i.ZERO)
		main._toggle_pause()
		_check(main.paused, "预览期间暂停仍立即生效")
		_check_preview_cleared(main, "暂停清理满线预览")
		main._toggle_pause()
		_drag_preview_to(main, Vector2i.ZERO)
		main._layout_controls()
		_check_preview_cleared(main, "界面重排清理旧拖动及光框")
		_equal(_preview_game_snapshot(main), before, "静态高亮、取消、暂停和重排不改变游戏状态")
		# Leave one real preview active to exercise the next mode/menu transition.
		_drag_preview_to(main, Vector2i.ZERO)
	main._return_to_menu()
	_check_preview_cleared(main, "返回菜单不保留最后的满线预览")
	_equal(main.game, null, "真实返回入口释放预览所属棋局")
	main._show_menu()
	_equal(_feedback_rules_snapshot(main.rules_config), rules_before, "三模式拖动预览不污染共用规则")
	main._set_setting("reduced_motion", reduced_motion_before)
	main.menu_controls.finish_opening()

func _clear_preview_fixture(main, pattern: String) -> Dictionary:
	main._cancel_drag()
	main.game.board = BoardRules.new(8)
	main.board_placement_orders.clear()
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)]
	if pattern == "column":
		cells.assign([Vector2i.ZERO, Vector2i(0, 1), Vector2i(0, 2)])
	elif pattern == "cross":
		cells.assign([Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)])
	if pattern != "column":
		main.game.board.fill_cell_row(0, 2)
	if pattern != "row":
		main.game.board.fill_cell_column(0, 2)
	for cell in cells:
		main.game.board.set_cell(cell.x, cell.y, -1)
	var piece := PieceData.new(Vector2i.ZERO, cells, "clear_preview_" + pattern)
	main.game.remaining_pieces.assign([piece, piece.duplicate_piece(), piece.duplicate_piece()])
	main._sync_piece_colors()
	var resolved: BoardRules = main.game.board.duplicate_board()
	resolved.place(piece, Vector2i.ZERO, main._piece_color_id(piece))
	return ClearColorResolver.resolve(resolved, {})

func _drag_preview_to(main, origin: Vector2i) -> void:
	# Use a real tray press with a nonzero grab offset, then Main's mouse-motion
	# entry. Neither the resulting origin nor the clear mask is injected.
	var grab := Vector2(0.25, 0.5)
	if main.dragging_index < 0:
		var piece: PieceData = main.game.remaining_pieces[0]
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = main._tray_piece_origin(0, piece) + grab * main._tray_unit(0, piece)
		main._input(press)
		_check(main.dragging_index == 0 and main.drag_grab_offset.is_equal_approx(grab), "真实托盘按下取得首块及非零抓取偏移")
	var motion := InputEventMouseMotion.new()
	motion.position = main._board_rect().position + (Vector2(origin) + grab) * main._cell_size()
	main._input(motion)
	_equal(main.drag_origin, origin, "实际鼠标移动通过抓取偏移换算为预期棋盘落点")

func _preview_game_snapshot(main) -> Dictionary:
	var pieces: Array = []
	for piece: PieceData in main.game.remaining_pieces:
		pieces.append([piece.get_instance_id(), piece.cells.duplicate(), piece.targets.duplicate(true)])
	return {
		"board": main.game.board.get("_cells").duplicate(true), "pieces": pieces,
		"scoring": [main.game.scoring.score, main.game.scoring.combo, main.game.scoring.combo_misses],
		"moves": main.game.total_moves, "status": main.game.status,
		"targets": [main.game.target_cells.duplicate(true), main.game.target_total, main.game.target_collected],
		"counts": [main.game.target_counts.duplicate(), main.game.target_remaining_counts.duplicate(), main.game.target_collected_counts.duplicate()],
	}

func _check_preview_cleared(main, message: String) -> void:
	_check(main.preview_clear_colors.is_empty() and not main.clear_preview.is_active() and main.clear_preview.highlight(true) == 0.0, message)

func _test_retry_failure_lifecycle(main) -> void:
	# This fixture only uses the test's isolated save_path. Two legal moves
	# exhaust its available lines; the final 3x3 block has no legal origin.
	main.save_data["adventure_highest_completed"] = 2
	main.save_data["adventure_retry_failures"] = {}
	main._start_game("adventure", 3)
	main.gameplay_ui.accept_objective_intro()
	main.game.board = BoardRules.new(8)
	main.game.target_cells.clear()
	for y in range(8):
		for x in range(8):
			if (x + y) % 2 == 1:
				main.game.board.set_cell(x, y, 0)
	for y in [0, 2]:
		for x in range(3):
			main.game.board.set_cell(x, y, -1)
	var line := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)], "retry_test_line")
	var square_cells: Array[Vector2i] = []
	for y in range(3):
		for x in range(3):
			square_cells.append(Vector2i(x, y))
	var square := PieceData.new(Vector2i.ZERO, square_cells, "retry_test_square")
	main.game.remaining_pieces.assign([line, line.duplicate_piece(), square])
	var first: Dictionary = main.game.place_piece(0, Vector2i.ZERO, 1)
	_check(bool(first["ok"]) and main.game.total_moves == 1 and not main.game.is_game_over(), "失败统计夹具首先完成一次真实合法落子且仍可继续")
	main._record_level_failure()
	_equal(SaveRepository.level_failure_count(main.save_data, 3), 0, "已有落子但仍在进行的棋局不记失败")
	var final_move: Dictionary = main.game.place_piece(0, Vector2i(0, 2), 1)
	_check(bool(final_move["ok"]) and main.game.total_moves == 2 and main.game.is_game_over(), "真实落子使最后方块无合法落点才进入失败")
	main._record_level_failure()
	main._record_level_failure()
	_equal(SaveRepository.level_failure_count(main.save_data, 3), 1, "同一真实失败无论记录多少次都只增加一次")
	_equal(SaveRepository.level_failure_count(SaveRepository.load_data(save_path), 3), 1, "失败次数在任何重开之前已经写入隔离存档")
	main._start_game("adventure", 3)
	main.gameplay_ui.accept_objective_intro()
	_check(not main.level_failure_recorded and is_equal_approx(main.game.retry_assist_strength, ModeCatalog.retry_assistance(3, 1)), "下一次进入读取已保存失败次数并重置本局记录标记")
	main._toggle_pause()
	main._record_level_failure()
	_equal(SaveRepository.level_failure_count(main.save_data, 3), 1, "暂停中的未失败棋局不累加失败次数")
	main._toggle_pause()
	main._show_menu()
	_equal(SaveRepository.level_failure_count(main.save_data, 3), 1, "主动离开未失败棋局不累加失败次数")

func _check_no_focus_outline(button: Button, label: String) -> void:
	_check(button != null and button.get_theme_stylebox("focus") is StyleBoxEmpty, "%s 不显示自然焦点外框" % label)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s; actual=%s expected=%s" % [message, actual, expected])

func _finish() -> void:
	if failures == 0:
		print("UI ACTION TESTS PASSED (%d checks)" % checks)
	else:
		print("UI ACTION TESTS FAILED: %d/%d" % [failures, checks])
	quit(0 if failures == 0 else 1)
