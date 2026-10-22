extends Control

const BOARD_MARGIN := 28.0
const Art := preload("res://scripts/ui/block_art.gd")
const ClearColorResolver := preload("res://scripts/ui/clear_color_resolver.gd")
const ClearPreviewScript := preload("res://scripts/ui/clear_preview.gd")
const FeedbackAudioScript := preload("res://scripts/audio/feedback_audio.gd")
const MoveFeedbackScript := preload("res://scripts/ui/move_feedback.gd")
const GameplayControlsScript := preload("res://scripts/ui/gameplay_controls.gd")
const ModeCatalog := preload("res://scripts/modes/mode_catalog.gd")
const LevelSelectScript := preload("res://scripts/ui/level_select.gd")
const MainMenuScript := preload("res://scripts/ui/main_menu.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const SettingsPanelScript := preload("res://scripts/ui/settings_panel.gd")
const ActionConfirmationScript := preload("res://scripts/ui/action_confirmation.gd")
const L10n := preload("res://scripts/localization/game_locale.gd")
const SETUP_REASON_SOURCES := {
	"invalid_level_configuration": "关卡配置不可用",
	"unknown_collection_template": "未知收集模板",
	"initial_markers_exceed_actual_template_cells": "初始标记超过模板占格",
	"template_contains_full_line": "模板包含完整行列",
	"invalid_shape_pool": "形状池无有效方块",
	"board_cannot_fit_initial_tray": "当前棋盘无法容纳初始托盘",
}

signal quit_requested

@export var save_path := SaveRepository.SAVE_PATH
@export var rules_config: GameRulesConfig = preload("res://config/default_rules.tres")

var game: GameState
var save_data: Dictionary
var screen := "menu"
var paused := false
var dragging_index := -1
var drag_mouse := Vector2.ZERO
var drag_origin := Vector2i.ZERO
var drag_valid := false
var status_text := ""
var last_gain := 0
var save_status_text := ""
var menu_controls: Control
var settings_controls: Control
var setting_controls: Dictionary = {}
var feedback_audio: Node
var transition: Tween
var exiting := false
var confirmation_dialog: Control
var confirmation_return_focus: Control
var settings_return_focus: Control
var confirmation_action := ""
var confirmation_was_paused := false
var gameplay_ui: Control
var move_feedback: Control
var input_locked := false
var drag_grab_offset := Vector2.ZERO
var touch_drag_active := false
var piece_colors: Dictionary = {}
var pending_move: Dictionary = {}
var pending_tray: Array[PieceData] = []
var rebound_piece_id := -1
var new_record := false
var settings_origin := "menu"
var settings_was_paused := false
var board_shake_offset := Vector2.ZERO
var shake_elapsed := 0.0
var shake_duration := 0.0
var shake_strength := 0.0
var final_impact_shake := false
var last_notice_round := -1
var preview_clear_colors: Dictionary = {}
var clear_preview := ClearPreviewScript.new()
var board_placement_orders: Dictionary = {}
var placement_sequence := 0
var game_mode := "free"
var current_level := 0
var level_select: Control
var level_completion_recorded := false
var level_failure_recorded := false
var level_objective: Dictionary = {}
var display_remaining_counts: Dictionary = {}
var progress_milestones_shown: Dictionary = {}
var pending_level_unlock: Dictionary = {}
var level_config_dialog: AcceptDialog
var _level_config_error_kind := ""
var _level_config_error_details := ""
var _level_config_error_level := 0
var _level_config_error_reason := ""

func _ready() -> void:
	set_process_input(true)
	save_data = SaveRepository.load_data(save_path)
	L10n.set_language(str(save_data.get("language", "zh_CN")))
	feedback_audio = FeedbackAudioScript.new()
	feedback_audio.name = "FeedbackAudio"
	add_child(feedback_audio)
	feedback_audio.apply_settings(save_data)
	move_feedback = MoveFeedbackScript.new()
	move_feedback.name = "MoveFeedback"
	move_feedback.z_index = 5
	add_child(move_feedback)
	move_feedback.finished.connect(_on_feedback_finished)
	move_feedback.shake_requested.connect(_request_board_shake)
	move_feedback.impact_requested.connect(_request_final_impact)
	move_feedback.target_arrived.connect(_on_target_arrived)
	move_feedback.collections_settled.connect(_on_collections_settled)
	gameplay_ui = GameplayControlsScript.new()
	gameplay_ui.name = "GameplayControls"
	gameplay_ui.z_index = 10
	add_child(gameplay_ui)
	gameplay_ui.configure(rules_config.primary_color, rules_config.secondary_color, rules_config.text_color, rules_config.board_color)
	gameplay_ui.pause_requested.connect(_toggle_pause)
	gameplay_ui.resume_requested.connect(_toggle_pause)
	gameplay_ui.restart_requested.connect(_request_restart)
	gameplay_ui.menu_requested.connect(_request_menu)
	gameplay_ui.settings_requested.connect(_on_settings_requested)
	gameplay_ui.open_settings_requested.connect(_request_game_settings)
	gameplay_ui.next_level_requested.connect(_start_next_level)
	gameplay_ui.levels_requested.connect(_return_to_menu)
	gameplay_ui.objective_intro_dismissed.connect(_on_objective_intro_dismissed)
	level_select = LevelSelectScript.new()
	level_select.name = "LevelSelect"
	level_select.z_index = 12
	add_child(level_select)
	level_select.back_requested.connect(_show_menu)
	level_select.level_started.connect(_start_adventure_level)
	_create_menu_controls()
	_create_confirmation_dialog()
	resized.connect(_layout_controls)
	get_window().focus_exited.connect(_on_window_focus_lost)
	_layout_controls()
	_refresh_controls()
	menu_controls.present(true, _reduced_motion())
	queue_redraw()

func _process(delta: float) -> void:
	if screen == "game" and not paused and not input_locked and dragging_index >= 0 and drag_valid and not _reduced_motion():
		clear_preview.advance(delta)
	if shake_duration > 0.0 and screen == "game" and not paused:
		shake_elapsed += delta
		var progress := clampf(shake_elapsed / shake_duration, 0.0, 1.0)
		var amplitude := shake_strength * (1.0 - progress)
		if final_impact_shake:
			# One downward impact and a rapidly settling rebound; ordinary drops
			# never enter this camera profile.
			var envelope := pow(1.0 - progress, 2.2)
			board_shake_offset = Vector2(sin(progress * TAU * 3.0) * 0.20, sin(progress * TAU * 2.4)) * shake_strength * envelope
		else:
			board_shake_offset = Vector2(sin(shake_elapsed * 115.0), cos(shake_elapsed * 91.0) * 0.6) * amplitude
		if progress >= 1.0:
			_stop_board_shake()
		move_feedback.set_board_offset(board_shake_offset)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and is_instance_valid(settings_controls):
		_refresh_confirmation_texts()
		_refresh_controls()
		_refresh_level_config_dialog()
		queue_redraw()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and OS.has_feature("android"):
		# Android's system back uses the same pause/menu path as desktop Esc.
		var back_event := InputEventKey.new()
		back_event.keycode = KEY_ESCAPE
		back_event.pressed = true
		_input(back_event)

func _input(event: InputEvent) -> void:
	if exiting:
		return
	if screen == "menu" and menu_controls.consume_opening_input(event):
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(level_config_dialog) and level_config_dialog.visible:
		return
	if _objective_intro_open():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			gameplay_ui.accept_objective_intro()
			get_viewport().set_input_as_handled()
		# Leave mouse/Tab events to the native modal controls. No tray or
		# gameplay shortcut can act before the player accepts the objective.
		return
	if not confirmation_action.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_confirmation()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if screen == "game":
				_toggle_pause()
			elif screen == "game_over" or screen == "level_complete":
				_return_to_menu()
			elif screen == "levels":
				_show_menu()
			elif screen == "settings":
				_close_settings()
			elif screen == "menu":
				_ask_quit()
		if event.keycode == KEY_R and screen in ["game", "game_over", "level_complete"]:
			_request_restart()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.canceled:
			_cancel_drag()
			get_viewport().set_input_as_handled()
			return
		if not event.pressed and dragging_index >= 0:
			_handle_release(event.position)
			get_viewport().set_input_as_handled()
			return
		# Native controls consume their own clicks; gameplay only handles tray drags.
		if screen != "game" or paused or input_locked or event.position.y < _header_height():
			return
		if event.pressed:
			touch_drag_active = MobileLayout.is_mobile() and event.device == InputEvent.DEVICE_ID_EMULATION
			_handle_press(event.position)
		else:
			_handle_release(event.position)
	if event is InputEventMouseMotion and dragging_index >= 0 and screen == "game" and not paused and not input_locked:
		drag_mouse = event.position
		_update_drag_preview()

func _handle_press(position: Vector2) -> void:
	if exiting or input_locked or _objective_intro_open() or not confirmation_action.is_empty():
		return
	if screen == "menu":
		# Native menu buttons own their input and animated bounds.
		return
	if screen == "settings":
		return
	if screen == "game_over":
		return
	if screen == "game":
		if paused or game == null or game.status != GameState.Status.PLAYING:
			return
		if _restart_button_rect().has_point(position):
			_request_restart()
			return
		if _menu_button_rect().has_point(position):
			_request_menu()
			return
		var index := _tray_hit(position)
		if index >= 0:
			dragging_index = index
			drag_mouse = position
			var piece: PieceData = game.remaining_pieces[index]
			if touch_drag_active:
				var bounds := _piece_bounds(piece)
				drag_grab_offset = Vector2(bounds.position) + Vector2(bounds.size) * 0.5
			else:
				drag_grab_offset = (position - _tray_piece_origin(index, piece)) / _tray_unit(index, piece)
			_update_drag_preview()

func _handle_release(position: Vector2) -> void:
	if dragging_index < 0:
		return
	if exiting or input_locked or _objective_intro_open() or game == null or screen != "game" or paused or not confirmation_action.is_empty():
		_cancel_drag()
		return
	# The release may arrive without a final motion event; validate its own position.
	drag_mouse = position
	_update_drag_preview()
	var index := dragging_index
	var origin := drag_origin
	var valid := drag_valid and _board_rect().has_point(_drag_anchor(position))
	var piece: PieceData = game.remaining_pieces[index] if index >= 0 else null
	var from_origin := _floating_origin(position)
	_cancel_drag()
	if not valid:
		status_text = "放置位置无效"
		gameplay_ui.show_notice("这里放不下，再试一个位置", "invalid", _reduced_motion())
		_play_feedback("invalid")
		if piece != null:
			input_locked = true
			rebound_piece_id = piece.get_instance_id()
			_refresh_controls()
			move_feedback.play_rebound(piece, from_origin, _tray_piece_origin(index, piece), _cell_size(), _tray_unit(index, piece), _piece_color(piece), rules_config.rebound_duration, _reduced_motion(), _board_cell_inset(), _tray_cell_inset())
		queue_redraw()
		return
	var before_board := game.board.duplicate_board()
	var before_targets := game.target_cells.duplicate()
	for local_cell: Vector2i in piece.targets:
		before_targets[origin + local_cell] = piece.targets[local_cell]
	pending_tray = game.remaining_pieces.duplicate()
	pending_tray.remove_at(index)
	input_locked = true
	var result: Dictionary = game.place_piece(index, origin, _piece_color_id(piece))
	if bool(result.get("ok", false)):
		_record_level_failure()
		if bool(result.get("tray_adapted", false)):
			# Tutorial adaptation happens after the legal move. Keep the visual
			# tray paired with the new instances before their colors are synced.
			pending_tray = game.remaining_pieces.duplicate()
		var next_order := placement_sequence + 1
		var placed_cells: Array[Vector2i] = result["placed_cells"]
		var next_orders := _orders_with_placement(placed_cells, next_order)
		var resolved_board := before_board.duplicate_board()
		resolved_board.place(piece, origin, int(result["placed_color"]))
		var clear_appearance := ClearColorResolver.resolve(resolved_board, next_orders)
		placement_sequence = next_order
		board_placement_orders = next_orders
		for coordinate in result["clear"]["cells"]:
			board_placement_orders.erase(coordinate)
		pending_move = result
		last_gain = int(result.get("gained", 0))
		var cleared_lines := int(result["clear"]["rows"]) + int(result["clear"]["columns"])
		var final_impact := _is_collect_mode() and game.is_level_complete() and not _reduced_motion()
		if not final_impact:
			if cleared_lines > 0 and game_mode in ["free", "classic"]:
				feedback_audio.play_clear_reward(int(result["combo"]), cleared_lines)
			else:
				_play_feedback("clear" if cleared_lines > 0 else "place")
		status_text = "放置 +%d   清除 +%d   合计 +%d   清除 %d 行/列   连击 x%d" % [
			int(result.get("placement_points", 0)),
			int(result.get("clear_points", 0)),
			last_gain,
			cleared_lines,
			int(result.get("combo", 0)),
		]
		if game.scoring.score > _stored_high_score():
			var first_record := not new_record
			new_record = true
			_save_high_score()
			if first_record and not _is_collect_mode():
				gameplay_ui.show_notice("新纪录！继续挑战", "record", _reduced_motion())
		if game.is_level_complete():
			gameplay_ui.clear_progress_milestones()
			_record_level_completion()
		_sync_piece_colors()
		_refresh_controls()
		move_feedback.set_paused(false)
		move_feedback.play_move(before_board, result["placed_cells"], result["clear"]["cells"], int(result["placed_color"]), _board_rect(), rules_config.palette, Vector2(rules_config.placement_duration, rules_config.clear_duration), last_gain, _reduced_motion(), _move_feedback_context(result, clear_appearance, before_targets))
	else:
		_reset_visual_feedback()
		status_text = "放置位置无效"
		_play_feedback("invalid")
	queue_redraw()

func _move_feedback_context(result: Dictionary, clear_appearance: Dictionary, target_cells: Dictionary) -> Dictionary:
	# Clear effects and praise consume the same real result in every mode.
	# Only collection levels may attach targets or the final-block sequence.
	var context := {
		"combo": int(result.get("combo", game.scoring.combo)),
		"cell_inset": _board_cell_inset(),
		"clear_lines": int(result["clear"]["rows"]) + int(result["clear"]["columns"]),
		"placement_points": int(result.get("placement_points", 0)),
		"clear_points": int(result.get("clear_points", 0)),
		"score_target": gameplay_ui.score_target(),
		"shake_enabled": bool(save_data.get("screen_shake", true)),
		"clear_colors": clear_appearance["cell_colors"],
		"clear_row_colors": clear_appearance["row_colors"],
		"clear_column_colors": clear_appearance["column_colors"],
		"objective_type": game.objective_type,
		"final_block": false,
		"score_flight_enabled": true,
		"endless_feedback": game_mode in ["free", "classic"],
	}
	if _is_collect_mode():
		context.merge({
			"target_cells": target_cells,
			"collected_targets": result.get("collected_targets", []),
			"collected_target_events": result.get("collected_target_events", []),
			"objective_target": gameplay_ui.score_target(),
			"objective_targets": {
				"blue_diamond": gameplay_ui.objective_target("blue_diamond"),
				"red_star": gameplay_ui.objective_target("red_star"),
				"gold_gem": gameplay_ui.objective_target("gold_gem"),
				"yellow_star": gameplay_ui.objective_target("yellow_star"),
			},
			"final_block": game.is_level_complete(),
			"score_flight_enabled": false,
		}, true)
	return context

func _start_game(mode: String = "", level_id: int = 0) -> void:
	var next_mode := mode if not mode.is_empty() else game_mode
	var next_level := level_id if level_id > 0 else current_level
	if next_mode == "adventure" and not _reload_adventure_config():
		return
	var seed := Time.get_ticks_msec()
	var setup: Dictionary = {}
	if next_mode == "classic":
		next_level = 0
		setup = ModeCatalog.classic_setup(seed, rules_config)
	elif next_mode == "adventure":
		next_level = clampi(next_level, 1, _unlocked_level())
		var failures := SaveRepository.level_failure_count(save_data, next_level)
		setup = ModeCatalog.level_setup(next_level, ModeCatalog.MAX_LEVELS, rules_config, failures)
		if not bool(setup.get("config_valid", false)) or bool(setup.get("initial_setup_invalid", false)):
			_show_initial_setup_error(next_level, str(setup.get("initial_diagnostics", {}).get("reason", "配置错误")))
			return
		seed = int(setup["level_seed"])
	else:
		next_mode = "free"
		next_level = 0
	# Validate the next setup before touching the current game's snapshot.
	_clear_confirmation()
	_reset_visual_feedback()
	_save_high_score()
	game_mode = next_mode
	current_level = next_level
	level_objective = ModeCatalog.objective_config(current_level) if game_mode == "adventure" else {}
	game = GameState.new(seed, rules_config.board_size, rules_config, setup)
	display_remaining_counts = game.target_remaining_counts.duplicate()
	progress_milestones_shown.clear()
	level_completion_recorded = false
	level_failure_recorded = false
	board_placement_orders.clear()
	var initial_cells: Array = setup.get("initial_cells", [])
	for index in range(initial_cells.size()):
		var entry: Dictionary = initial_cells[index]
		board_placement_orders[Vector2i(int(entry["x"]), int(entry["y"]))] = index - initial_cells.size()
	placement_sequence = 0
	piece_colors.clear()
	_sync_piece_colors()
	new_record = false
	last_notice_round = 0
	screen = "game_over" if game.is_game_over() else "game"
	paused = false
	_cancel_drag()
	status_text = "拖动方块到棋盘"
	last_gain = 0
	_play_feedback("click")
	_refresh_controls()
	if screen == "game" and game.objective_type == "collect":
		gameplay_ui.show_objective_intro(_collection_intro_stats(), _reduced_motion())
		_refresh_controls()
	else:
		var notice := str(level_objective.get("description", "")) if game_mode == "adventure" else "拖动方块，填满一行或一列"
		gameplay_ui.show_notice(notice, "info", _reduced_motion())
	queue_redraw()

func _objective_intro_open() -> bool:
	return gameplay_ui != null and gameplay_ui.is_objective_intro_visible()

func _is_collect_mode() -> bool:
	return game != null and game_mode == "adventure" and game.objective_type == "collect"

func _result_feedback_pending() -> bool:
	return input_locked or (move_feedback != null and move_feedback.has_pending_collections())

func _on_target_arrived(kind: String, counted: bool) -> void:
	if exiting or not _is_collect_mode():
		return
	if counted:
		display_remaining_counts[kind] = maxi(0, int(display_remaining_counts.get(kind, 0)) - 1)
	_refresh_controls()
	gameplay_ui.notify_target_arrival(kind, counted)
	_check_progress_milestones()
	queue_redraw()

func _check_progress_milestones() -> void:
	if not _is_collect_mode() or game.target_total <= 0 or game.status != GameState.Status.PLAYING:
		return
	if exiting or screen != "game" or paused or _objective_intro_open() or not confirmation_action.is_empty():
		return
	var remaining := 0
	for count in display_remaining_counts.values():
		remaining += maxi(0, int(count))
	var collected := clampi(game.target_total - remaining, 0, game.target_total)
	if collected >= game.target_total:
		return
	for threshold in [50, 90]:
		if not progress_milestones_shown.has(threshold) and collected * 100 >= game.target_total * threshold:
			progress_milestones_shown[threshold] = true
			gameplay_ui.show_progress_milestone(threshold, _reduced_motion())

func _on_collections_settled() -> void:
	_try_show_level_complete()

func _try_show_level_complete() -> void:
	if exiting or game == null or screen != "game" or not game.is_level_complete() or _result_feedback_pending():
		return
	# Praise can outlive the board animation, but must not linger under victory.
	move_feedback.reset_move()
	_record_level_completion()
	screen = "level_complete"
	paused = false
	_refresh_controls()
	queue_redraw()

func _collection_intro_stats() -> Dictionary:
	var stats := level_objective.duplicate(true)
	if game != null:
		stats.merge({
			"level_id": current_level,
			"objective_type": game.objective_type,
			"target_counts": game.target_counts.duplicate(),
			"collected_counts": game.target_collected_counts.duplicate(),
			"remaining_counts": game.target_remaining_counts.duplicate(),
			"display_remaining_counts": display_remaining_counts.duplicate(),
			"target_total": game.target_total,
			"difficulty_description": str(level_objective.get("description", "")),
		}, true)
	return stats

func _on_objective_intro_dismissed() -> void:
	if exiting or game == null or screen != "game":
		return
	_cancel_drag()
	_play_feedback("click")
	_refresh_controls()
	queue_redraw()

func _unlocked_level() -> int:
	return mini(ModeCatalog.MAX_LEVELS, int(save_data.get("adventure_highest_completed", 0)) + 1)

func _open_levels(reload_table: bool = true) -> void:
	if reload_table and not _reload_adventure_config():
		return
	screen = "levels"
	paused = false
	level_select.configure(ModeCatalog.MAX_LEVELS, int(save_data.get("adventure_highest_completed", 0)))
	level_select.set_reduced_motion(_reduced_motion())
	level_select.set_save_status("进度保存失败，仅本次运行有效" if not save_status_text.is_empty() else "")
	_refresh_controls()
	var unlock_event := pending_level_unlock
	pending_level_unlock = {}
	level_select.activate(int(unlock_event.get("completed", 0)), int(unlock_event.get("unlocked", 0)))
	_play_feedback("click")
	queue_redraw()

func _reload_adventure_config() -> bool:
	var errors := ModeCatalog.reload_level_config()
	if errors.is_empty():
		return true
	var visible_errors := PackedStringArray()
	for index in range(mini(3, errors.size())):
		visible_errors.append(errors[index])
	if errors.size() > 3:
		visible_errors.append(L10n.t("另有错误，请查看 Godot 输出。"))
	push_error("\n".join(errors))
	_show_level_config_error("\n".join(visible_errors), "table")
	return false

func _localized_setup_reason(reason: String) -> String:
	var source := str(SETUP_REASON_SOURCES.get(reason, "配置错误"))
	return L10n.t(source)

func _show_initial_setup_error(level_id: int, reason: String) -> void:
	_level_config_error_kind = "setup"
	_level_config_error_details = ""
	_level_config_error_level = level_id
	_level_config_error_reason = reason
	_apply_level_config_error_dialog()

func _show_level_config_error(details: String, kind: String = "details") -> void:
	_level_config_error_kind = kind
	_level_config_error_details = details
	_level_config_error_level = 0
	_level_config_error_reason = ""
	_apply_level_config_error_dialog()

func _refresh_level_config_dialog() -> void:
	if not is_instance_valid(level_config_dialog) or not level_config_dialog.visible:
		return
	if _level_config_error_kind == "table":
		var errors := ModeCatalog.reload_level_config()
		if errors.is_empty():
			return
		var visible_errors := PackedStringArray()
		for index in range(mini(3, errors.size())):
			visible_errors.append(errors[index])
		if errors.size() > 3:
			visible_errors.append(L10n.t("另有错误，请查看 Godot 输出。"))
		_level_config_error_details = "\n".join(visible_errors)
	_apply_level_config_error_dialog()

func _apply_level_config_error_dialog() -> void:
	var should_popup := not is_instance_valid(level_config_dialog) or not level_config_dialog.visible
	if not is_instance_valid(level_config_dialog):
		level_config_dialog = AcceptDialog.new()
		level_config_dialog.name = "LevelConfigError"
		level_config_dialog.dialog_autowrap = true
		level_config_dialog.theme = confirmation_dialog.theme
		add_child(level_config_dialog)
	level_config_dialog.title = L10n.t("关卡配置错误")
	level_config_dialog.ok_button_text = L10n.t("知道了")
	var details := _level_config_error_details
	if _level_config_error_kind == "setup":
		details = L10n.t("第 %d 关初始配置无法用于当前棋盘：%s") % [_level_config_error_level, _localized_setup_reason(_level_config_error_reason)]
	level_config_dialog.dialog_text = L10n.t("闯关配置未生效：\n\n%s\n\n请修正 config/adventure_levels.csv 后重新进入选关页。") % details
	_refresh_controls()
	var width := mini(720, maxi(260, int(size.x) - 48))
	level_config_dialog.min_size = Vector2i(width, 200)
	if should_popup:
		level_config_dialog.popup_centered(Vector2i(width, 0))

func _start_adventure_level(level_id: int) -> void:
	if level_id >= 1 and level_id <= _unlocked_level():
		_start_game("adventure", level_id)

func _start_next_level() -> void:
	if game != null and game.is_level_complete() and current_level < ModeCatalog.MAX_LEVELS:
		_return_to_menu()

func _record_level_completion() -> void:
	if game == null or game_mode != "adventure" or not game.is_level_complete():
		return
	if not level_completion_recorded:
		var previously_unlocked := _unlocked_level()
		save_data = SaveRepository.record_level_completed(save_data, current_level, game.scoring.score)
		var newly_unlocked := _unlocked_level()
		if newly_unlocked > previously_unlocked:
			pending_level_unlock = {"completed": current_level, "unlocked": newly_unlocked}
		level_completion_recorded = true
	_persist_data()

func _record_level_failure() -> void:
	if game == null or game_mode != "adventure" or level_failure_recorded or not game.is_game_over() or game.total_moves < 1:
		return
	# Commit once at the logical failure, before feedback or navigation can
	# invoke another save. Pauses, voluntary restarts and invalid setups do not
	# satisfy this terminal-state check.
	level_failure_recorded = true
	save_data = SaveRepository.record_level_failed(save_data, current_level)
	_persist_data()

func _create_confirmation_dialog() -> void:
	confirmation_dialog = ActionConfirmationScript.new()
	confirmation_dialog.name = "ConfirmActionDialog"
	add_child(confirmation_dialog)
	confirmation_dialog.confirmed.connect(_confirm_action)
	confirmation_dialog.canceled.connect(_cancel_confirmation)

func _request_restart() -> void:
	if exiting or input_locked or _objective_intro_open() or not confirmation_action.is_empty():
		return
	if screen == "game_over" or screen == "level_complete":
		_start_game()
	elif screen == "game":
		_show_confirmation("restart")

func _request_menu() -> void:
	if exiting or input_locked or _objective_intro_open() or not confirmation_action.is_empty():
		return
	if screen == "game_over" or screen == "level_complete":
		_return_to_menu()
	elif screen == "game":
		_show_confirmation("menu")

func _show_confirmation(action: String) -> void:
	if exiting or not confirmation_action.is_empty():
		return
	confirmation_return_focus = get_viewport().gui_get_focus_owner()
	confirmation_action = action
	confirmation_was_paused = paused
	_cancel_drag()
	paused = true
	move_feedback.set_paused(true)
	_refresh_controls()
	confirmation_dialog.show_action(action)
	_refresh_confirmation_texts()
	confirmation_dialog.popup_centered(Vector2i(448, 0))
	queue_redraw()

func _refresh_confirmation_texts() -> void:
	if confirmation_action.is_empty():
		return
	confirmation_dialog.cancel_button_text = L10n.t("继续游戏" if screen == "game" else "暂不退出")
	if confirmation_action == "quit":
		confirmation_dialog.title = L10n.t("退出游戏")
		confirmation_dialog.dialog_text = L10n.t("确定退出游戏吗？\n最高分、通关记录和设置会保留。") + (L10n.t("\n本局棋盘不会保存。") if game != null else "")
		confirmation_dialog.ok_button_text = L10n.t("确定退出")
	elif confirmation_action == "restart":
		confirmation_dialog.title = L10n.t("重新开始")
		confirmation_dialog.dialog_text = L10n.t("重新开始会清空当前棋盘和本局分数。\n最高分和设置会保留。")
		confirmation_dialog.ok_button_text = L10n.t("重新开始")
	else:
		confirmation_dialog.title = L10n.t("返回选关" if game_mode == "adventure" else "返回菜单")
		confirmation_dialog.dialog_text = L10n.t("返回选关后，本局棋盘不会保存。\n最高分、通关记录和设置会保留。" if game_mode == "adventure" else "返回菜单后，本局棋盘不会保存。\n最高分、通关记录和设置会保留。")
		confirmation_dialog.ok_button_text = L10n.t("确定返回选关" if game_mode == "adventure" else "确定返回菜单")

func _confirm_action() -> void:
	var action := confirmation_action
	_clear_confirmation()
	confirmation_return_focus = null
	if action == "restart":
		_start_game()
	elif action == "menu":
		_return_to_menu()
	elif action == "quit":
		_request_quit()

func _cancel_confirmation() -> void:
	if confirmation_action.is_empty():
		return
	var restore_paused := confirmation_was_paused
	var restore_focus := confirmation_return_focus
	confirmation_return_focus = null
	_clear_confirmation()
	paused = restore_paused
	move_feedback.set_paused(paused)
	_refresh_controls()
	_check_progress_milestones()
	if is_instance_valid(restore_focus) and restore_focus.is_visible_in_tree():
		restore_focus.grab_focus()
	queue_redraw()

func _clear_confirmation() -> void:
	confirmation_action = ""
	if confirmation_dialog != null:
		confirmation_dialog.hide()

func _cancel_drag() -> void:
	dragging_index = -1
	drag_valid = false
	drag_origin = Vector2i(-99, -99)
	drag_grab_offset = Vector2.ZERO
	touch_drag_active = false
	preview_clear_colors.clear()
	clear_preview.reset()
	queue_redraw()

func _toggle_pause() -> void:
	if screen != "game" or _objective_intro_open() or not confirmation_action.is_empty():
		return
	paused = not paused
	_cancel_drag()
	move_feedback.set_paused(paused)
	_refresh_controls()
	_check_progress_milestones()

func _on_window_focus_lost() -> void:
	_cancel_drag()
	if screen == "menu":
		menu_controls.finish_opening()
	if _objective_intro_open():
		return
	if screen == "game" and confirmation_action.is_empty():
		paused = true
		move_feedback.set_paused(true)
		_refresh_controls()
	queue_redraw()

func _toggle_setting(key: String) -> void:
	_set_setting(key, not bool(save_data.get(key, false)))

func _set_setting(key: String, value: bool) -> void:
	if key not in ["sound_enabled", "music_enabled", "reduced_motion", "screen_shake"]:
		return
	save_data[key] = value
	_persist_data()
	if feedback_audio != null:
		feedback_audio.apply_settings(save_data)
		feedback_audio.play_feedback("click")
	if key == "reduced_motion" and value and transition != null:
		transition.kill()
		settings_controls.modulate.a = 1.0
		menu_controls.modulate.a = 1.0
	if key == "reduced_motion" and value:
		move_feedback.finish_collections()
		move_feedback.reset()
		if input_locked:
			_on_feedback_finished()
	if (key == "screen_shake" and not value) or (key == "reduced_motion" and value):
		_stop_board_shake()
	_refresh_controls()
	queue_redraw()

func _persist_data() -> void:
	var saved := SaveRepository.save_data(save_data, save_path)
	save_status_text = "" if saved else "保存失败，进度、最高分和设置仅本次生效。"

func _set_language(language: String) -> void:
	if language not in L10n.SUPPORTED_CODES:
		return
	save_data["language"] = language
	L10n.set_language(language)
	_persist_data()
	_refresh_controls()
	queue_redraw()

func _show_settings() -> void:
	settings_return_focus = get_viewport().gui_get_focus_owner()
	settings_origin = "menu"
	screen = "settings"
	_play_feedback("click")
	_refresh_controls()
	settings_controls.focus_primary()
	_fade_controls(settings_controls)
	queue_redraw()

func _request_game_settings() -> void:
	if screen != "game" or _objective_intro_open() or not confirmation_action.is_empty():
		return
	settings_return_focus = get_viewport().gui_get_focus_owner()
	settings_origin = "game"
	settings_was_paused = paused
	paused = true
	_cancel_drag()
	move_feedback.set_paused(true)
	screen = "settings"
	_refresh_controls()
	settings_controls.focus_primary()
	_fade_controls(settings_controls)
	queue_redraw()

func _on_settings_requested() -> void:
	_request_game_settings()

func _close_settings() -> void:
	var restore_focus := settings_return_focus
	settings_return_focus = null
	if settings_origin == "game" and game != null:
		screen = "game"
		if not _result_feedback_pending():
			if game.is_level_complete():
				screen = "level_complete"
			elif game.is_game_over():
				screen = "game_over"
		paused = settings_was_paused if screen == "game" else false
		move_feedback.set_paused(paused)
		_refresh_controls()
		_check_progress_milestones()
		queue_redraw()
	else:
		_show_menu()
	if is_instance_valid(restore_focus) and restore_focus.is_visible_in_tree():
		if not restore_focus is BaseButton or not restore_focus.disabled:
			restore_focus.grab_focus()

func _show_menu() -> void:
	screen = "menu"
	_play_feedback("click")
	_refresh_controls()
	menu_controls.present(false, _reduced_motion())
	queue_redraw()

func _play_feedback(kind: String) -> void:
	if feedback_audio != null:
		feedback_audio.play_feedback(kind)

func _preview_sound() -> void:
	if bool(save_data.get("sound_enabled", false)):
		_play_feedback("clear")

func _request_quit() -> void:
	if exiting:
		return
	exiting = true
	menu_controls.finish_opening()
	_clear_confirmation()
	_cancel_drag()
	_reset_visual_feedback()
	set_process_input(false)
	_save_high_score()
	if feedback_audio != null:
		feedback_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	quit_requested.emit()
	if feedback_audio != null:
		feedback_audio.queue_free()
		feedback_audio = null
	# Wait for a real mixer update. A new timer can expire during a long startup frame.
	var stopped_at := Time.get_ticks_usec()
	var last_mix_usec := stopped_at - int(AudioServer.get_time_since_last_mix() * 1000000.0)
	var next_mix_usec := last_mix_usec
	while next_mix_usec <= last_mix_usec + 1000 and Time.get_ticks_usec() - stopped_at < 500000:
		await get_tree().process_frame
		next_mix_usec = Time.get_ticks_usec() - int(AudioServer.get_time_since_last_mix() * 1000000.0)
	# Main-thread cleanup releases playback references after that completed mix.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

func _fade_controls(control: Control) -> void:
	if transition != null:
		transition.kill()
	control.modulate.a = 1.0
	if not bool(save_data.get("reduced_motion", false)):
		control.modulate.a = 0.0
		transition = create_tween()
		transition.tween_property(control, "modulate:a", 1.0, 0.15)

func _return_to_menu() -> void:
	# A broken edited table must not discard the current game before we can
	# actually open its destination. Reuse this validated snapshot below.
	if game_mode == "adventure" and not _reload_adventure_config():
		return
	_clear_confirmation()
	_reset_visual_feedback()
	_save_high_score()
	game = null
	board_placement_orders.clear()
	placement_sequence = 0
	screen = "menu"
	paused = false
	_cancel_drag()
	status_text = ""
	last_gain = 0
	piece_colors.clear()
	if game_mode == "adventure":
		_open_levels(false)
	else:
		_show_menu()

func _reduced_motion() -> bool:
	return bool(save_data.get("reduced_motion", false))

func _reset_visual_feedback() -> void:
	_stop_board_shake()
	if gameplay_ui != null:
		gameplay_ui.clear_notice()
		gameplay_ui.clear_progress_milestones()
		gameplay_ui.hide_objective_intro()
	if move_feedback != null:
		move_feedback.reset()
		move_feedback.set_paused(false)
	input_locked = false
	pending_move = {}
	pending_tray = []
	rebound_piece_id = -1

func _on_feedback_finished() -> void:
	_stop_board_shake()
	var refilled := bool(pending_move.get("round_refilled", false))
	input_locked = false
	pending_move = {}
	pending_tray = []
	rebound_piece_id = -1
	if game != null and screen == "game" and game.is_game_over():
		screen = "game_over"
		paused = false
	elif game != null and screen == "game" and game.is_level_complete():
		_try_show_level_complete()
	_refresh_controls()
	if game != null and screen == "game" and refilled and game.round_index != last_notice_round and not _is_collect_mode():
		last_notice_round = game.round_index
		gameplay_ui.show_notice("新的三块，继续！", "info", _reduced_motion())
	queue_redraw()

func _request_board_shake(strength: float, duration: float) -> void:
	if _reduced_motion() or not bool(save_data.get("screen_shake", true)):
		return
	if final_impact_shake and shake_duration > 0.0:
		return
	final_impact_shake = false
	shake_elapsed = 0.0
	shake_duration = maxf(duration, 0.01)
	shake_strength = minf(strength, 5.0)

func _request_final_impact(strength: float, duration: float) -> void:
	if exiting or screen != "game" or not _is_collect_mode() or not game.is_level_complete():
		return
	_play_feedback("clear")
	if _reduced_motion() or not bool(save_data.get("screen_shake", true)):
		return
	final_impact_shake = true
	shake_elapsed = 0.0
	shake_duration = clampf(duration, 0.12, 0.40)
	shake_strength = clampf(strength * 1.25, 0.0, 12.0)

func _stop_board_shake() -> void:
	board_shake_offset = Vector2.ZERO
	shake_duration = 0.0
	final_impact_shake = false
	if move_feedback != null:
		move_feedback.set_board_offset(Vector2.ZERO)

func _sync_piece_colors() -> void:
	var active: Dictionary = {}
	if game != null:
		for index in range(game.remaining_pieces.size()):
			var identifier := game.remaining_pieces[index].get_instance_id()
			active[identifier] = piece_colors.get(identifier, (index + game.round_index * rules_config.tray_count) % maxi(1, rules_config.palette.size()))
	piece_colors = active

func _piece_color_id(piece: PieceData) -> int:
	return int(piece_colors.get(piece.get_instance_id(), 0))

func _piece_color(piece: PieceData) -> Color:
	return _block_color(_piece_color_id(piece))

func _block_color(color_id: int) -> Color:
	if rules_config.palette.is_empty():
		return rules_config.primary_color
	return rules_config.palette[posmod(color_id, rules_config.palette.size())]

func _orders_with_placement(placed_cells: Array[Vector2i], order: int) -> Dictionary:
	# Preview works on a copy; only a successful release commits these timestamps.
	var orders := board_placement_orders.duplicate()
	for coordinate in placed_cells:
		orders[coordinate] = order
	return orders

func _save_high_score() -> void:
	if game == null:
		return
	if game_mode == "adventure":
		_record_level_failure()
		_record_level_completion()
		return
	var key := "classic_high_score" if game_mode == "classic" else "high_score"
	save_data[key] = maxi(int(save_data.get(key, 0)), game.scoring.score)
	_persist_data()

func _stored_high_score() -> int:
	if game_mode == "adventure":
		var scores: Dictionary = save_data.get("adventure_best_scores", {})
		return int(scores.get(str(current_level), 0))
	return int(save_data.get("classic_high_score" if game_mode == "classic" else "high_score", 0))

func _create_menu_controls() -> void:
	menu_controls = MainMenuScript.new()
	menu_controls.name = "MenuControls"
	menu_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_controls)
	menu_controls.free_requested.connect(_start_game.bind("free"))
	menu_controls.classic_requested.connect(_start_game.bind("classic"))
	menu_controls.adventure_requested.connect(_open_levels)
	menu_controls.settings_requested.connect(_show_settings)
	menu_controls.quit_requested.connect(_ask_quit)
	settings_controls = SettingsPanelScript.new()
	settings_controls.name = "SettingsControls"
	settings_controls.z_index = 30
	add_child(settings_controls)
	setting_controls = settings_controls.toggles
	settings_controls.setting_changed.connect(_set_setting)
	settings_controls.language_changed.connect(_set_language)
	settings_controls.close_requested.connect(_close_settings)
	settings_controls.preview_requested.connect(_preview_sound)
	settings_controls.restart_requested.connect(_restart_from_settings)
	settings_controls.menu_requested.connect(_menu_from_settings)
	settings_controls.quit_requested.connect(_ask_quit)

func _restart_from_settings() -> void:
	if screen != "settings" or settings_origin != "game":
		return
	_close_settings()
	_request_restart()

func _menu_from_settings() -> void:
	if screen != "settings" or settings_origin != "game":
		return
	_close_settings()
	_request_menu()

func _ask_quit() -> void:
	if not exiting and confirmation_action.is_empty():
		menu_controls.finish_opening()
		_show_confirmation("quit")

func _on_setting_toggled(enabled: bool, key: String) -> void:
	_set_setting(key, enabled)

func _add_button(parent: Control, node_name: String, text: String, color: Color, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 22)
	var text_color := Color("#253556") if color.get_luminance() > 0.5 else rules_config.text_color
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, text_color)
	button.add_theme_stylebox_override("normal", Art.button_style(color))
	button.add_theme_stylebox_override("hover", Art.button_style(color.lightened(0.10)))
	button.add_theme_stylebox_override("pressed", Art.button_style(color, true))
	button.add_theme_stylebox_override("disabled", Art.button_style(color.darkened(0.3), true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _layout_controls() -> void:
	if menu_controls == null:
		return
	_cancel_drag()
	_stop_board_shake()
	if move_feedback != null:
		move_feedback.finish_collections()
		move_feedback.reset()
	if input_locked:
		_on_feedback_finished()
	gameplay_ui.position = Vector2.ZERO
	gameplay_ui.size = size
	gameplay_ui.set_playfield(_board_rect())
	level_select.position = Vector2.ZERO
	level_select.size = size
	move_feedback.position = Vector2.ZERO
	move_feedback.size = size
	menu_controls.position = Vector2.ZERO
	menu_controls.size = size
	settings_controls.position = Vector2.ZERO
	settings_controls.size = size
	if is_instance_valid(confirmation_dialog):
		confirmation_dialog.position = Vector2.ZERO
		confirmation_dialog.size = size
	_check_progress_milestones()

func _set_control_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size

func _refresh_controls() -> void:
	if menu_controls == null:
		return
	menu_controls.set_profile(maxi(int(save_data.get("high_score", 0)), int(save_data.get("classic_high_score", 0))), save_status_text, _reduced_motion())
	menu_controls.visible = screen == "menu" or (screen == "settings" and settings_origin == "menu")
	settings_controls.visible = screen == "settings"
	level_select.visible = screen == "levels"
	move_feedback.visible = screen in ["game", "game_over", "level_complete"] or (screen == "settings" and settings_origin == "game")
	if gameplay_ui != null:
		if screen != "game" or exiting:
			gameplay_ui.hide_objective_intro()
		var mode := "hidden"
		var modal_backdrop := game != null and ((screen == "settings" and settings_origin == "game") or (screen == "game" and not confirmation_action.is_empty()))
		if modal_backdrop and not exiting:
			# Preserve the score and target HUD behind the dimmed modal, while
			# disabling its actions and preventing it from taking keyboard focus.
			mode = "playing"
		elif game != null and confirmation_action.is_empty() and not exiting:
			if screen == "game_over":
				mode = "game_over"
			elif screen == "level_complete":
				mode = "level_complete"
			elif screen == "game":
				mode = "paused" if paused else "playing"
		var stats: Dictionary = {}
		if game != null:
			stats = {
				"score": game.scoring.score,
				"high_score": _display_high_score(),
				"combo": game.scoring.combo,
				"total_cleared_lines": game.total_cleared_lines,
				"round_index": game.round_index,
				"placement_points": game.last_placement_points,
				"clear_points": game.last_clear_points,
				"clear_lines": game.last_clear_lines,
				"new_record": new_record,
				"input_locked": modal_backdrop or input_locked or _objective_intro_open() or (screen == "game" and game.is_level_complete()),
				"modal_backdrop": modal_backdrop,
				"reduced_motion": _reduced_motion(),
				"mode": game_mode,
				"level_id": current_level,
				"target_score": game.target_score,
				"objective_type": game.objective_type,
				"target_total": game.target_total,
				"target_collected": game.target_collected,
				"target_remaining": maxi(0, game.target_total - game.target_collected),
				"target_counts": game.target_counts.duplicate(),
				"collected_counts": game.target_collected_counts.duplicate(),
				"remaining_counts": game.target_remaining_counts.duplicate(),
				"display_remaining_counts": display_remaining_counts.duplicate(),
				"difficulty_label": str(level_objective.get("difficulty_label", "")),
				"highest_completed": int(save_data.get("adventure_highest_completed", 0)),
				"has_next_level": current_level < ModeCatalog.MAX_LEVELS,
				"total_levels": ModeCatalog.MAX_LEVELS,
				"save_failed": not save_status_text.is_empty(),
			}
		gameplay_ui.set_playfield(_board_rect())
		gameplay_ui.set_mode(mode, stats)
	settings_controls.apply_state(save_data, settings_origin == "game" and game != null, game_mode == "adventure", save_status_text)

func _tray_hit(position: Vector2) -> int:
	if game == null or input_locked or _objective_intro_open() or game.status != GameState.Status.PLAYING:
		return -1
	for index in range(game.remaining_pieces.size()):
		var piece: PieceData = game.remaining_pieces[index]
		if MobileLayout.is_mobile() and _tray_slot_rect(index).has_point(position):
			return index
		var unit := _tray_unit(index, piece)
		var origin := _tray_piece_origin(index, piece)
		for cell in piece.cells:
			if Rect2(origin + Vector2(cell) * unit, Vector2.ONE * unit).has_point(position):
				return index
	return -1

func _display_high_score() -> int:
	return maxi(_stored_high_score(), game.scoring.score if game != null else 0)

func _board_size() -> int:
	return game.board.size if game != null else rules_config.board_size

func _header_height() -> float:
	if MobileLayout.is_mobile():
		var content := MobileLayout.safe_content_rect(self)
		var target := MobileLayout.touch_target(self)
		return content.position.y + (maxf(clampf(content.size.y * 0.15, 200.0, 260.0), target * 2.4) if _is_collect_mode() else maxf(clampf(content.size.y * 0.20, 240.0, 330.0), target * 2.8))
	# Resolve from the new game's state, before HUD set_mode has changed modes.
	if _is_collect_mode():
		return maxf(clampf(size.y * 0.15, 116.0, 180.0), 132.0 if size.y > size.x else 116.0)
	var height := clampf(size.y * 0.18, 148.0, 210.0)
	if size.y > size.x:
		height = clampf(size.y * 0.20, 210.0, 560.0)
	if size.x < 350.0:
		return maxf(height, 210.0)
	if size.x < 440.0:
		return maxf(height, 176.0)
	return height

func _tray_height() -> float:
	if MobileLayout.is_mobile():
		return float(_tray_max_bounds().y) * _tray_preferred_unit() + MobileLayout.dp(self, 36.0)
	var base_height := clampf(size.y * 0.21, 148.0, 230.0) if _is_collect_mode() else clampf(size.y * 0.16, 128.0, 190.0)
	var padding := 32.0 if _is_collect_mode() else 52.0
	return maxf(base_height, float(_tray_max_bounds().y) * _tray_preferred_unit() + padding)

func _tray_preferred_unit() -> float:
	# A common UI scale keeps the same cell size across game modes. Reserve
	# space for long shapes first, rather than reducing collection pieces.
	if MobileLayout.is_mobile():
		var content_width := MobileLayout.safe_content_rect(self).size.x
		var columns := float(maxi(1, rules_config.tray_count))
		var slot_width := (content_width - MobileLayout.dp(self, 24.0) - (columns - 1.0) * MobileLayout.dp(self, 10.0)) / columns
		return maxf(8.0, minf(content_width / 18.0, (slot_width - MobileLayout.dp(self, 8.0)) / 5.0))
	var ui_scale := minf(size.x / 1280.0, size.y / 720.0)
	return clampf(roundf(24.0 * ui_scale), 8.0, 48.0)

func _visible_tray() -> Array[PieceData]:
	if input_locked and not pending_move.is_empty():
		return pending_tray
	return game.remaining_pieces if game != null else []

func _tray_slot_rect(index: int) -> Rect2:
	var count := maxi(1, rules_config.tray_count)
	var inner_padding := 12.0 if _is_collect_mode() else 24.0
	if MobileLayout.is_mobile():
		var content := MobileLayout.safe_content_rect(self)
		var gap := MobileLayout.dp(self, 10.0)
		var margin := MobileLayout.dp(self, 12.0)
		var width := maxf(1.0, content.size.x - margin * 2.0)
		var slot_width := maxf(1.0, (width - float(count - 1) * gap) / float(count))
		var tray_top := _board_rect().end.y + MobileLayout.dp(self, 48.0)
		return Rect2(Vector2(content.position.x + margin + float(index) * (slot_width + gap), tray_top), Vector2(slot_width, _tray_height() - MobileLayout.dp(self, 12.0)))
	var required_slot_width := float(_tray_max_bounds().x) * _tray_preferred_unit() + inner_padding
	var required_width := float(count) * required_slot_width + float(count - 1) * 16.0
	var tray_width := minf(size.x - BOARD_MARGIN * 2.0, maxf(maxf(_board_rect().size.x, 440.0), required_width))
	var slot_width := (tray_width - float(count - 1) * 16.0) / float(count)
	var tray_top := _board_rect().end.y + (clampf(_cell_size() * 0.6, 12.0, 40.0) if _is_collect_mode() else 84.0)
	return Rect2(Vector2((size.x - tray_width) * 0.5 + float(index) * (slot_width + 16.0), tray_top), Vector2(slot_width, _tray_height() - (20.0 if _is_collect_mode() else 32.0)))

func _piece_bounds(piece: PieceData) -> Rect2i:
	if piece.cells.is_empty():
		return Rect2i(Vector2i.ZERO, Vector2i.ONE)
	var minimum := piece.cells[0]
	var maximum := piece.cells[0]
	for cell in piece.cells:
		minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
		maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

func _tray_max_bounds() -> Vector2i:
	# Reserve the whole mode's shape envelope, rather than resizing each piece
	# independently or changing the remaining pieces after one is consumed.
	var extent := Vector2i.ONE
	var mode_rules: GameRulesConfig = game.rules_config if game != null else rules_config
	var shapes: Array[PieceData] = []
	for definition in mode_rules.shape_pool:
		if definition is ShapeDefinition:
			shapes.append(definition.to_piece())
		elif definition is PieceData:
			shapes.append(definition)
		elif definition is Dictionary:
			shapes.append(PieceData.new(Vector2i.ZERO, definition.get("cells", [])))
	shapes.append_array(_visible_tray())
	if game != null:
		shapes.append_array(game.remaining_pieces)
	for shape in shapes:
		var bounds := _piece_bounds(shape).size
		extent.x = maxi(extent.x, bounds.x)
		extent.y = maxi(extent.y, bounds.y)
	return extent

func _tray_unit(_index: int, _piece: PieceData) -> float:
	var extent := _tray_max_bounds()
	var slot := _tray_slot_rect(0)
	var padding := Vector2(12.0, 12.0) if _is_collect_mode() else Vector2(24.0, 20.0)
	if MobileLayout.is_mobile():
		padding = Vector2.ONE * MobileLayout.dp(self, 8.0)
	var available := (slot.size - padding).max(Vector2.ONE)
	var fit := minf(available.x / float(extent.x), available.y / float(extent.y))
	return minf(_tray_preferred_unit(), fit)

func _tray_cell_inset() -> float:
	return 0.2

func _tray_piece_origin(index: int, piece: PieceData) -> Vector2:
	var slot := _tray_slot_rect(index)
	var bounds := _piece_bounds(piece)
	var unit := _tray_unit(index, piece)
	return slot.position + (slot.size - Vector2(bounds.size) * unit) * 0.5 - Vector2(bounds.position) * unit

func _floating_origin(position: Vector2) -> Vector2:
	return _drag_anchor(position) - drag_grab_offset * _cell_size()

func _drag_anchor(position: Vector2) -> Vector2:
	# Use the same lifted anchor for the held piece, preview and release.
	return position - Vector2(0.0, MobileLayout.dp(self, 64.0)) if touch_drag_active else position


func _restart_button_rect() -> Rect2:
	return gameplay_ui.get_restart_rect() if gameplay_ui != null else Rect2()

func _menu_button_rect() -> Rect2:
	return gameplay_ui.get_menu_rect() if gameplay_ui != null else Rect2()

func _board_rect() -> Rect2:
	if MobileLayout.is_mobile():
		var content := MobileLayout.safe_content_rect(self)
		var top := _header_height() + MobileLayout.dp(self, 16.0)
		var available := content.end.y - top - _tray_height() - MobileLayout.dp(self, 88.0)
		var board_side := maxf(48.0, minf(content.size.x - MobileLayout.dp(self, 24.0), available))
		return Rect2(Vector2(content.get_center().x - board_side * 0.5, top), Vector2.ONE * board_side)
	var top := _header_height() + (16.0 if _is_collect_mode() else (64.0 if game_mode == "adventure" else 48.0))
	# Keep distinct bands for the notice, tray and bottom instruction.
	var available_height := size.y - _tray_height() - top - (58.0 if _is_collect_mode() else 84.0)
	var width_limit := size.x * 0.90 if size.y > size.x else 660.0
	var board_side := maxf(48.0, minf(width_limit, minf(size.x - BOARD_MARGIN * 2.0, available_height)))
	return Rect2(Vector2((size.x - board_side) * 0.5, top), Vector2(board_side, board_side))

func _cell_size() -> float:
	return _board_rect().size.x / float(maxi(1, _board_size()))

func _board_cell_inset() -> float:
	return 0.4 if _is_collect_mode() else 1.0

func _board_origin_from_mouse(position: Vector2, _piece: PieceData) -> Vector2i:
	var rect := _board_rect()
	var cell := _cell_size()
	var raw := (_floating_origin(position) - rect.position) / cell
	return Vector2i(roundi(raw.x), roundi(raw.y))

func _update_drag_preview() -> void:
	if dragging_index < 0 or game == null or screen != "game" or paused or input_locked or not confirmation_action.is_empty():
		_cancel_drag()
		return
	if dragging_index >= game.remaining_pieces.size():
		_cancel_drag()
		return
	var piece: PieceData = game.remaining_pieces[dragging_index]
	drag_origin = _board_origin_from_mouse(drag_mouse, piece)
	drag_valid = _board_rect().has_point(_drag_anchor(drag_mouse)) and game.board.can_place(piece, drag_origin)
	preview_clear_colors.clear()
	if drag_valid:
		var preview_board := game.board.duplicate_board()
		preview_board.place(piece, drag_origin, _piece_color_id(piece))
		var placed_cells: Array[Vector2i] = []
		for local_cell in piece.cells:
			placed_cells.append(drag_origin + local_cell)
		var appearance := ClearColorResolver.resolve(preview_board, _orders_with_placement(placed_cells, placement_sequence + 1))
		preview_clear_colors = appearance["cell_colors"]
		var preview_palette := rules_config.palette if not rules_config.palette.is_empty() else PackedColorArray([rules_config.primary_color])
		clear_preview.configure(preview_clear_colors, appearance["row_colors"], appearance["column_colors"], _board_size(), preview_palette)
	else:
		clear_preview.reset()
	queue_redraw()

func _draw() -> void:
	_draw_background()
	if screen == "menu":
		return
	if screen == "settings":
		_draw_settings()
		return
	if screen == "levels":
		return
	_draw_game()
	if dragging_index >= 0:
		_draw_drag_layer()

func _draw_background() -> void:
	Art.draw_background(self, Rect2(Vector2.ZERO, size))

func _draw_settings() -> void:
	# SettingsPanel owns its scrim and native controls; keep the live playfield
	# behind it so the panel feels like part of the current game.
	if settings_origin == "game" and game != null:
		_draw_game()

func _draw_centered_text(text: String, baseline: float, font_size: int, color: Color) -> void:
	var width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var center_x := MobileLayout.safe_content_rect(self).get_center().x if MobileLayout.is_mobile() else size.x * 0.5
	draw_string(ThemeDB.fallback_font, Vector2(center_x - width * 0.5, baseline + 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.035, 0.06, 0.14, 0.65))
	draw_string(ThemeDB.fallback_font, Vector2(center_x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_game() -> void:
	if game == null:
		return
	_draw_board()
	_draw_tray()
	var hint_y := minf(_tray_slot_rect(0).end.y + 22.0, size.y - 8.0)
	if MobileLayout.is_mobile():
		hint_y = minf(_tray_slot_rect(0).end.y + MobileLayout.dp(self, 20.0), MobileLayout.safe_content_rect(self).end.y - MobileLayout.dp(self, 8.0))
	_draw_centered_text(L10n.t("选择一块，拖到棋盘" if dragging_index < 0 else "松开放置"), hint_y, roundi(MobileLayout.dp(self, 14.0)) if MobileLayout.is_mobile() else 14, Color("#b3cbed"))

func _draw_board() -> void:
	var rect := _board_rect()
	rect.position += board_shake_offset
	Art.draw_board_frame(self, rect, _is_collect_mode())
	var cell := _cell_size()
	var hide_final_board := input_locked and not pending_move.is_empty()
	# Paint every empty cell before any occupied cell, matching the snapshot.
	# Otherwise later empty cells clip the shadows of their left/top neighbours.
	for y in range(_board_size()):
		for x in range(_board_size()):
			var empty_rect := Art.grid_cell_rect(rect.position + Vector2(x, y) * cell, cell, _board_cell_inset())
			Art.draw_empty_cell(self, empty_rect, rules_config.empty_cell_color, _is_collect_mode())
	for y in range(_board_size()):
		for x in range(_board_size()):
			var value := -1 if hide_final_board else game.board.get_cell(x, y)
			var color := rules_config.empty_cell_color
			if value >= 0:
				color = _block_color(int(preview_clear_colors.get(Vector2i(x, y), value)))
			var cell_rect := Art.grid_cell_rect(rect.position + Vector2(x, y) * cell, cell, _board_cell_inset())
			if value < 0:
				continue
			else:
				if game.target_cells.has(Vector2i(x, y)) and not preview_clear_colors.has(Vector2i(x, y)):
					Art.draw_target_tile(self, cell_rect, 1.0, 0.0, _target_kind_at(Vector2i(x, y)))
				else:
					Art.draw_block(self, cell_rect, color, 1.0, clear_preview.highlight(_reduced_motion()) if preview_clear_colors.has(Vector2i(x, y)) else 0.0)
				if game.target_cells.has(Vector2i(x, y)):
					Art.draw_target_marker(self, cell_rect, 1.0, 1.0, _target_kind_at(Vector2i(x, y)), true)
	if dragging_index >= 0 and game != null:
		var piece: PieceData = game.remaining_pieces[dragging_index]
		for local_cell in piece.cells:
			var target := drag_origin + local_cell
			if target.x >= 0 and target.x < _board_size() and target.y >= 0 and target.y < _board_size():
				var preview_rect := Art.grid_cell_rect(rect.position + Vector2(target) * cell, cell, _board_cell_inset())
				if drag_valid:
					# The landing ghost uses the same marked tile and material as
					# the held piece; its ordinary palette color is not its backing.
					var clear_color: Variant = _block_color(int(preview_clear_colors[target])) if preview_clear_colors.has(target) else null
					_draw_piece_cell(piece, local_cell, preview_rect, 1.0 if clear_color is Color else 0.32, clear_color)
				else:
					# Keep occupied targets readable instead of stacking a second
					# insert/socket over them while the attempted placement is invalid.
					if game.board.get_cell(target.x, target.y) < 0:
						Art.draw_block(self, preview_rect, Color("#ff7575"), 0.40, 0.2)
						if piece.targets.has(local_cell):
							Art.draw_target_marker(self, preview_rect, 0.78, 1.0, str(piece.targets[local_cell]), true)
					draw_rect(preview_rect.grow(-1.0), Color("#ffb3a9"), false, 1.5)
	if dragging_index >= 0 and drag_valid and not hide_final_board:
		clear_preview.draw(self, rect, _reduced_motion())

func _target_kind_at(cell: Vector2i) -> String:
	return str(game.target_cells.get(cell, "red_star")) if game != null else "red_star"

func _draw_tray() -> void:
	var pieces := _visible_tray()
	for index in range(maxi(1, rules_config.tray_count)):
		if index >= pieces.size():
			continue
		var piece: PieceData = pieces[index]
		if index == dragging_index or piece.get_instance_id() == rebound_piece_id:
			continue
		var origin := _tray_piece_origin(index, piece)
		var cell := _tray_unit(index, piece)
		for local_cell in piece.cells:
			var p := origin + Vector2(local_cell.x, local_cell.y) * cell
			var r := Art.grid_cell_rect(p, cell, _tray_cell_inset())
			_draw_piece_cell(piece, local_cell, r)

func _draw_piece_cell(piece: PieceData, local_cell: Vector2i, rect: Rect2, opacity: float = 1.0, clear_color: Variant = null) -> void:
	var marked := piece.targets.has(local_cell)
	if clear_color is Color:
		Art.draw_block(self, rect, clear_color, opacity, clear_preview.highlight(_reduced_motion()))
	elif marked:
		Art.draw_target_tile(self, rect, opacity, 0.0, str(piece.targets[local_cell]))
	else:
		Art.draw_block(self, rect, _piece_color(piece), opacity)
	if marked:
		Art.draw_target_marker(self, rect, opacity, 1.0, str(piece.targets[local_cell]), true)

func _draw_drag_layer() -> void:
	if game == null or dragging_index >= game.remaining_pieces.size():
		return
	var piece: PieceData = game.remaining_pieces[dragging_index]
	var origin := _floating_origin(drag_mouse)
	var unit := _cell_size()
	for cell in piece.cells:
		var rect := Art.grid_cell_rect(origin + Vector2(cell) * unit, unit, _board_cell_inset())
		var target: Vector2i = drag_origin + cell
		if drag_valid and preview_clear_colors.has(target):
			_draw_piece_cell(piece, cell, rect, 1.0, _block_color(int(preview_clear_colors[target])))
		else:
			_draw_piece_cell(piece, cell, rect, 0.96)

func _box(color: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = int(radius)
	box.corner_radius_top_right = int(radius)
	box.corner_radius_bottom_left = int(radius)
	box.corner_radius_bottom_right = int(radius)
	box.shadow_color = Color(0.15, 0.1, 0.2, 0.12)
	box.shadow_size = 4
	return box
