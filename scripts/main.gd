extends Control

const BOARD_MARGIN := 28.0
const TRAY_HEIGHT := 160.0
const FeedbackAudioScript := preload("res://scripts/audio/feedback_audio.gd")
const MoveFeedbackScript := preload("res://scripts/ui/move_feedback.gd")
const GameplayControlsScript := preload("res://scripts/ui/gameplay_controls.gd")

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
var confirmation_dialog: ConfirmationDialog
var confirmation_action := ""
var confirmation_was_paused := false
var gameplay_ui: Control
var move_feedback: Control
var input_locked := false
var drag_grab_offset := Vector2.ZERO
var piece_colors: Dictionary = {}
var pending_move: Dictionary = {}
var pending_tray: Array[PieceData] = []
var rebound_piece_id := -1
var new_record := false

func _ready() -> void:
	set_process_input(true)
	save_data = SaveRepository.load_data(save_path)
	feedback_audio = FeedbackAudioScript.new()
	feedback_audio.name = "FeedbackAudio"
	add_child(feedback_audio)
	feedback_audio.apply_settings(save_data)
	move_feedback = MoveFeedbackScript.new()
	move_feedback.name = "MoveFeedback"
	move_feedback.z_index = 5
	add_child(move_feedback)
	move_feedback.finished.connect(_on_feedback_finished)
	gameplay_ui = GameplayControlsScript.new()
	gameplay_ui.name = "GameplayControls"
	gameplay_ui.z_index = 10
	add_child(gameplay_ui)
	gameplay_ui.configure(rules_config.primary_color, rules_config.secondary_color, rules_config.text_color, rules_config.board_color)
	gameplay_ui.pause_requested.connect(_toggle_pause)
	gameplay_ui.resume_requested.connect(_toggle_pause)
	gameplay_ui.restart_requested.connect(_request_restart)
	gameplay_ui.menu_requested.connect(_request_menu)
	_create_menu_controls()
	_create_confirmation_dialog()
	resized.connect(_layout_controls)
	get_window().focus_exited.connect(_on_window_focus_lost)
	_layout_controls()
	_refresh_controls()
	menu_controls.get_node("StartButton").grab_focus()
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _input(event: InputEvent) -> void:
	if exiting:
		return
	if not confirmation_action.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_confirmation()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if screen == "game":
				_toggle_pause()
			elif screen == "game_over":
				_return_to_menu()
			elif screen == "settings":
				_show_menu()
			elif screen == "menu":
				_request_quit()
		if event.keycode == KEY_R and (screen == "game" or screen == "game_over"):
			_request_restart()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and dragging_index >= 0:
			_handle_release(event.position)
			get_viewport().set_input_as_handled()
			return
		# Native controls consume their own clicks; gameplay only handles tray drags.
		if screen != "game" or paused or input_locked or event.position.y < _header_height():
			return
		if event.pressed:
			_handle_press(event.position)
		else:
			_handle_release(event.position)
	if event is InputEventMouseMotion and dragging_index >= 0 and screen == "game" and not paused and not input_locked:
		drag_mouse = event.position
		_update_drag_preview()

func _handle_press(position: Vector2) -> void:
	if exiting or input_locked or not confirmation_action.is_empty():
		return
	if screen == "menu":
		if _menu_start_button_rect().has_point(position):
			_start_game()
		elif _menu_settings_button_rect().has_point(position):
			_show_settings()
		elif _menu_exit_button_rect().has_point(position):
			_request_quit()
		return
	if screen == "settings":
		if _settings_sound_rect().has_point(position):
			_toggle_setting("sound_enabled")
		elif _settings_music_rect().has_point(position):
			_toggle_setting("music_enabled")
		elif _settings_motion_rect().has_point(position):
			_toggle_setting("reduced_motion")
		elif _settings_back_button_rect().has_point(position):
			_show_menu()
		return
	if screen == "game_over":
		return
	if screen == "game":
		if paused:
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
			drag_grab_offset = (position - _tray_piece_origin(index, piece)) / _tray_unit(index, piece)
			_update_drag_preview()

func _handle_release(position: Vector2) -> void:
	if dragging_index < 0:
		return
	if exiting or input_locked or game == null or screen != "game" or paused or not confirmation_action.is_empty():
		_cancel_drag()
		return
	# The release may arrive without a final motion event; validate its own position.
	drag_mouse = position
	_update_drag_preview()
	var index := dragging_index
	var origin := drag_origin
	var valid := drag_valid and _board_rect().has_point(position)
	var piece: PieceData = game.remaining_pieces[index] if index >= 0 else null
	var from_origin := _floating_origin(position)
	_cancel_drag()
	if not valid:
		status_text = "放置位置无效"
		_play_feedback("invalid")
		if piece != null:
			input_locked = true
			rebound_piece_id = piece.get_instance_id()
			_refresh_controls()
			move_feedback.play_rebound(piece, from_origin, _tray_piece_origin(index, piece), _cell_size(), _tray_unit(index, piece), _piece_color(piece), rules_config.rebound_duration, _reduced_motion())
		queue_redraw()
		return
	var before_board := game.board.duplicate_board()
	pending_tray = game.remaining_pieces.duplicate()
	pending_tray.remove_at(index)
	input_locked = true
	var result: Dictionary = game.place_piece(index, origin, _piece_color_id(piece))
	if bool(result.get("ok", false)):
		pending_move = result
		last_gain = int(result.get("gained", 0))
		var cleared_lines := int(result["clear"]["rows"]) + int(result["clear"]["columns"])
		_play_feedback("clear" if cleared_lines > 0 else "place")
		status_text = "放置 +%d   清除 +%d   合计 +%d   清除 %d 行/列   连击 x%d" % [
			int(result.get("placement_points", 0)),
			int(result.get("clear_points", 0)),
			last_gain,
			cleared_lines,
			int(result.get("combo", 0)),
		]
		if game.scoring.score > int(save_data.get("high_score", 0)):
			new_record = true
			_save_high_score()
		_sync_piece_colors()
		_refresh_controls()
		move_feedback.set_paused(false)
		move_feedback.play_move(before_board, result["placed_cells"], result["clear"]["cells"], int(result["placed_color"]), _board_rect(), rules_config.palette, Vector2(rules_config.placement_duration, rules_config.clear_duration), last_gain, _reduced_motion())
	else:
		_reset_visual_feedback()
		status_text = "放置位置无效"
		_play_feedback("invalid")
	queue_redraw()

func _start_game() -> void:
	_clear_confirmation()
	_reset_visual_feedback()
	_save_high_score()
	game = GameState.new(Time.get_ticks_msec(), rules_config.board_size, rules_config)
	piece_colors.clear()
	_sync_piece_colors()
	new_record = false
	screen = "game_over" if game.is_game_over() else "game"
	paused = false
	_cancel_drag()
	status_text = "拖动方块到棋盘"
	last_gain = 0
	_play_feedback("click")
	_refresh_controls()
	queue_redraw()

func _create_confirmation_dialog() -> void:
	confirmation_dialog = ConfirmationDialog.new()
	confirmation_dialog.name = "ConfirmActionDialog"
	confirmation_dialog.dialog_autowrap = true
	confirmation_dialog.min_size = Vector2i(400, 170)
	confirmation_dialog.cancel_button_text = "取消，继续游戏"
	confirmation_dialog.get_label().add_theme_font_size_override("font_size", 18)
	for button: Button in [confirmation_dialog.get_ok_button(), confirmation_dialog.get_cancel_button()]:
		button.custom_minimum_size = Vector2(150, 44)
		button.add_theme_font_size_override("font_size", 18)
	confirmation_dialog.confirmed.connect(_confirm_action)
	confirmation_dialog.canceled.connect(_cancel_confirmation)
	add_child(confirmation_dialog)

func _request_restart() -> void:
	if exiting or input_locked or not confirmation_action.is_empty():
		return
	if screen == "game_over":
		_start_game()
	elif screen == "game":
		_show_confirmation("restart")

func _request_menu() -> void:
	if exiting or input_locked or not confirmation_action.is_empty():
		return
	if screen == "game_over":
		_return_to_menu()
	elif screen == "game":
		_show_confirmation("menu")

func _show_confirmation(action: String) -> void:
	if exiting or not confirmation_action.is_empty():
		return
	confirmation_action = action
	confirmation_was_paused = paused
	_cancel_drag()
	paused = true
	_refresh_controls()
	if action == "restart":
		confirmation_dialog.title = "确认重新开始"
		confirmation_dialog.dialog_text = "重新开始会清空当前棋盘和本局分数。\n最高分和设置会保留。"
		confirmation_dialog.ok_button_text = "确定重新开始"
	else:
		confirmation_dialog.title = "确认返回菜单"
		confirmation_dialog.dialog_text = "返回菜单后，本局棋盘不会保存。\n最高分和设置会保留。"
		confirmation_dialog.ok_button_text = "确定返回菜单"
	confirmation_dialog.popup_centered(Vector2i(440, 190))
	# Default keyboard focus stays on the non-destructive choice.
	confirmation_dialog.get_cancel_button().grab_focus()
	queue_redraw()

func _confirm_action() -> void:
	var action := confirmation_action
	_clear_confirmation()
	if action == "restart":
		_start_game()
	elif action == "menu":
		_return_to_menu()

func _cancel_confirmation() -> void:
	if confirmation_action.is_empty():
		return
	var restore_paused := confirmation_was_paused
	_clear_confirmation()
	paused = restore_paused
	_refresh_controls()
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
	queue_redraw()

func _toggle_pause() -> void:
	if screen != "game" or not confirmation_action.is_empty():
		return
	paused = not paused
	_cancel_drag()
	move_feedback.set_paused(paused)
	_refresh_controls()

func _on_window_focus_lost() -> void:
	_cancel_drag()
	if screen == "game" and confirmation_action.is_empty():
		paused = true
		move_feedback.set_paused(true)
		_refresh_controls()
	queue_redraw()

func _toggle_setting(key: String) -> void:
	_set_setting(key, not bool(save_data.get(key, false)))

func _set_setting(key: String, value: bool) -> void:
	if key not in ["sound_enabled", "music_enabled", "reduced_motion"]:
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
	if key == "reduced_motion" and value and input_locked:
		move_feedback.reset()
		_on_feedback_finished()
	_refresh_controls()
	queue_redraw()

func _persist_data() -> void:
	var saved := SaveRepository.save_data(save_data, save_path)
	save_status_text = "" if saved else "保存失败，当前设置仅在本次运行生效。"

func _show_settings() -> void:
	screen = "settings"
	_play_feedback("click")
	_refresh_controls()
	setting_controls["sound_enabled"].grab_focus()
	_fade_controls(settings_controls)
	queue_redraw()

func _show_menu() -> void:
	screen = "menu"
	_play_feedback("click")
	_refresh_controls()
	menu_controls.get_node("StartButton").grab_focus()
	_fade_controls(menu_controls)
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
	_clear_confirmation()
	_reset_visual_feedback()
	_save_high_score()
	game = null
	screen = "menu"
	paused = false
	_cancel_drag()
	status_text = ""
	last_gain = 0
	piece_colors.clear()
	_show_menu()

func _reduced_motion() -> bool:
	return bool(save_data.get("reduced_motion", false))

func _reset_visual_feedback() -> void:
	if move_feedback != null:
		move_feedback.reset()
		move_feedback.set_paused(false)
	input_locked = false
	pending_move = {}
	pending_tray = []
	rebound_piece_id = -1

func _on_feedback_finished() -> void:
	input_locked = false
	pending_move = {}
	pending_tray = []
	rebound_piece_id = -1
	if game != null and screen == "game" and game.is_game_over():
		screen = "game_over"
		paused = false
	_refresh_controls()
	queue_redraw()

func _sync_piece_colors() -> void:
	var active: Dictionary = {}
	if game != null:
		for index in range(game.remaining_pieces.size()):
			var identifier := game.remaining_pieces[index].get_instance_id()
			active[identifier] = piece_colors.get(identifier, index % maxi(1, rules_config.palette.size()))
	piece_colors = active

func _piece_color_id(piece: PieceData) -> int:
	return int(piece_colors.get(piece.get_instance_id(), 0))

func _piece_color(piece: PieceData) -> Color:
	if rules_config.palette.is_empty():
		return rules_config.primary_color
	return rules_config.palette[posmod(_piece_color_id(piece), rules_config.palette.size())]

func _save_high_score() -> void:
	if game == null:
		return
	save_data["high_score"] = max(int(save_data.get("high_score", 0)), game.scoring.score)
	_persist_data()

func _create_menu_controls() -> void:
	menu_controls = Control.new()
	menu_controls.name = "MenuControls"
	menu_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_controls)
	_add_button(menu_controls, "StartButton", "开始游戏", rules_config.primary_color, _start_game)
	_add_button(menu_controls, "SettingsButton", "设置", rules_config.secondary_color, _show_settings)
	_add_button(menu_controls, "ExitButton", "退出", rules_config.text_color.lightened(0.35), _request_quit)
	settings_controls = Control.new()
	settings_controls.name = "SettingsControls"
	settings_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(settings_controls)
	var labels := {"sound_enabled": "音效", "music_enabled": "音乐", "reduced_motion": "减少动画"}
	for key: String in labels:
		var toggle := CheckButton.new()
		toggle.name = key
		toggle.focus_mode = Control.FOCUS_ALL
		toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		toggle.add_theme_font_size_override("font_size", 19)
		toggle.add_theme_color_override("font_color", rules_config.text_color)
		toggle.add_theme_color_override("font_pressed_color", rules_config.text_color)
		toggle.add_theme_color_override("font_hover_color", rules_config.text_color)
		toggle.add_theme_color_override("font_hover_pressed_color", rules_config.text_color)
		toggle.add_theme_color_override("font_focus_color", rules_config.text_color)
		toggle.add_theme_stylebox_override("normal", _box(rules_config.background_color, 12))
		toggle.add_theme_stylebox_override("pressed", _box(rules_config.secondary_color.lightened(0.85), 12))
		toggle.add_theme_stylebox_override("hover", _box(rules_config.empty_cell_color, 12))
		toggle.add_theme_stylebox_override("hover_pressed", _box(rules_config.secondary_color.lightened(0.78), 12))
		toggle.add_theme_stylebox_override("focus", _focus_box())
		for style_name: String in ["normal", "pressed", "hover", "hover_pressed"]:
			var style: StyleBoxFlat = toggle.get_theme_stylebox(style_name)
			style.content_margin_left = 16.0
			style.content_margin_right = 16.0
		toggle.toggled.connect(_on_setting_toggled.bind(key))
		settings_controls.add_child(toggle)
		setting_controls[key] = toggle
	_add_button(settings_controls, "PreviewSoundButton", "试听音效", rules_config.primary_color, _preview_sound)
	_add_button(settings_controls, "BackButton", "返回菜单", rules_config.secondary_color, _show_menu)

func _on_setting_toggled(enabled: bool, key: String) -> void:
	_set_setting(key, enabled)

func _add_button(parent: Control, node_name: String, text: String, color: Color, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _box(color, 16))
	button.add_theme_stylebox_override("hover", _box(color.lightened(0.12), 16))
	button.add_theme_stylebox_override("pressed", _box(color.darkened(0.12), 16))
	button.add_theme_stylebox_override("focus", _focus_box())
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = rules_config.secondary_color.darkened(0.25)
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	return box

func _layout_controls() -> void:
	if menu_controls == null:
		return
	_cancel_drag()
	if move_feedback != null:
		move_feedback.reset()
	if input_locked:
		_on_feedback_finished()
	gameplay_ui.position = Vector2.ZERO
	gameplay_ui.size = size
	move_feedback.position = Vector2.ZERO
	move_feedback.size = size
	_set_control_rect(menu_controls.get_node("StartButton"), _menu_start_button_rect())
	_set_control_rect(menu_controls.get_node("SettingsButton"), _menu_settings_button_rect())
	_set_control_rect(menu_controls.get_node("ExitButton"), _menu_exit_button_rect())
	_set_control_rect(setting_controls["sound_enabled"], _settings_sound_rect())
	_set_control_rect(setting_controls["music_enabled"], _settings_music_rect())
	_set_control_rect(setting_controls["reduced_motion"], _settings_motion_rect())
	_set_control_rect(settings_controls.get_node("BackButton"), _settings_back_button_rect())
	_set_control_rect(settings_controls.get_node("PreviewSoundButton"), _settings_preview_button_rect())

func _set_control_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size

func _refresh_controls() -> void:
	if menu_controls == null:
		return
	menu_controls.visible = screen == "menu"
	settings_controls.visible = screen == "settings"
	if gameplay_ui != null:
		var mode := "hidden"
		if game != null and confirmation_action.is_empty() and not exiting:
			if screen == "game_over":
				mode = "game_over"
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
				"input_locked": input_locked,
			}
		gameplay_ui.set_mode(mode, stats)
	var preview_button: Button = settings_controls.get_node("PreviewSoundButton")
	preview_button.disabled = not bool(save_data.get("sound_enabled", false))
	preview_button.tooltip_text = "播放清除音效" if not preview_button.disabled else "请先开启音效"
	var labels := {"sound_enabled": "音效", "music_enabled": "音乐", "reduced_motion": "减少动画"}
	for key: String in setting_controls:
		var toggle: CheckButton = setting_controls[key]
		var enabled: bool = bool(save_data.get(key, false))
		toggle.set_pressed_no_signal(enabled)
		toggle.text = "%s：%s" % [labels[key], "开启" if enabled else "关闭"]

func _tray_hit(position: Vector2) -> int:
	if game == null or input_locked:
		return -1
	for index in range(game.remaining_pieces.size()):
		var piece: PieceData = game.remaining_pieces[index]
		var unit := _tray_unit(index, piece)
		var origin := _tray_piece_origin(index, piece)
		for cell in piece.cells:
			if Rect2(origin + Vector2(cell) * unit, Vector2.ONE * unit).has_point(position):
				return index
	return -1

func _display_high_score() -> int:
	return maxi(int(save_data.get("high_score", 0)), game.scoring.score if game != null else 0)

func _board_size() -> int:
	return game.board.size if game != null else rules_config.board_size

func _header_height() -> float:
	return gameplay_ui.header_height() if gameplay_ui != null else 116.0

func _visible_tray() -> Array[PieceData]:
	if input_locked and not pending_move.is_empty():
		return pending_tray
	return game.remaining_pieces if game != null else []

func _tray_slot_rect(index: int) -> Rect2:
	var count := maxi(1, rules_config.tray_count)
	var tray_width := minf(size.x - BOARD_MARGIN * 2.0, maxf(_board_rect().size.x, 480.0))
	var slot_width := (tray_width - float(count - 1) * 16.0) / float(count)
	return Rect2(Vector2((size.x - tray_width) * 0.5 + float(index) * (slot_width + 16.0), size.y - TRAY_HEIGHT + 42.0), Vector2(slot_width, TRAY_HEIGHT - 54.0))

func _piece_bounds(piece: PieceData) -> Rect2i:
	if piece.cells.is_empty():
		return Rect2i(Vector2i.ZERO, Vector2i.ONE)
	var minimum := piece.cells[0]
	var maximum := piece.cells[0]
	for cell in piece.cells:
		minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
		maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

func _tray_unit(index: int, piece: PieceData) -> float:
	var bounds := _piece_bounds(piece)
	var slot := _tray_slot_rect(index)
	return maxf(6.0, minf(30.0, minf((slot.size.x - 28.0) / float(bounds.size.x), (slot.size.y - 20.0) / float(bounds.size.y))))

func _tray_piece_origin(index: int, piece: PieceData) -> Vector2:
	var slot := _tray_slot_rect(index)
	var bounds := _piece_bounds(piece)
	var unit := _tray_unit(index, piece)
	return slot.position + (slot.size - Vector2(bounds.size) * unit) * 0.5 - Vector2(bounds.position) * unit

func _floating_origin(position: Vector2) -> Vector2:
	return position - drag_grab_offset * _cell_size()

func _menu_start_button_rect() -> Rect2:
	return Rect2(size * 0.5 - Vector2(120, 30), Vector2(240, 60))

func _menu_settings_button_rect() -> Rect2:
	return Rect2(size * 0.5 + Vector2(-120, 50), Vector2(240, 60))

func _menu_exit_button_rect() -> Rect2:
	return Rect2(size * 0.5 + Vector2(-120, 130), Vector2(240, 60))

func _settings_panel_rect() -> Rect2:
	var panel_size := Vector2(minf(440.0, size.x - 40.0), 470.0)
	return Rect2((size - panel_size) * 0.5, panel_size)

func _settings_sound_rect() -> Rect2:
	return Rect2(_settings_panel_rect().position + Vector2(30, 90), Vector2(_settings_panel_rect().size.x - 60, 54))

func _settings_music_rect() -> Rect2:
	return Rect2(_settings_panel_rect().position + Vector2(30, 160), Vector2(_settings_panel_rect().size.x - 60, 54))

func _settings_motion_rect() -> Rect2:
	return Rect2(_settings_panel_rect().position + Vector2(30, 230), Vector2(_settings_panel_rect().size.x - 60, 54))

func _settings_back_button_rect() -> Rect2:
	return Rect2(_settings_panel_rect().position + Vector2(30, 350), Vector2(_settings_panel_rect().size.x - 60, 56))

func _settings_preview_button_rect() -> Rect2:
	return Rect2(_settings_panel_rect().position + Vector2(30, 300), Vector2(_settings_panel_rect().size.x - 60, 44))

func _restart_button_rect() -> Rect2:
	return gameplay_ui.get_restart_rect() if gameplay_ui != null else Rect2()

func _menu_button_rect() -> Rect2:
	return gameplay_ui.get_menu_rect() if gameplay_ui != null else Rect2()

func _board_rect() -> Rect2:
	var top := _header_height() + 10.0
	var available_height := size.y - TRAY_HEIGHT - top - 12.0
	var board_side := maxf(48.0, minf(size.x - BOARD_MARGIN * 2.0, available_height))
	return Rect2(Vector2((size.x - board_side) * 0.5, top), Vector2(board_side, board_side))

func _cell_size() -> float:
	return _board_rect().size.x / float(maxi(1, _board_size()))

func _board_origin_from_mouse(position: Vector2, _piece: PieceData) -> Vector2i:
	var rect := _board_rect()
	var cell := _cell_size()
	var raw := (_floating_origin(position) - rect.position) / cell
	return Vector2i(roundi(raw.x), roundi(raw.y))

func _update_drag_preview() -> void:
	if dragging_index < 0 or game == null or paused or not confirmation_action.is_empty():
		return
	if dragging_index >= game.remaining_pieces.size():
		_cancel_drag()
		return
	var piece: PieceData = game.remaining_pieces[dragging_index]
	drag_origin = _board_origin_from_mouse(drag_mouse, piece)
	drag_valid = _board_rect().has_point(drag_mouse) and game.board.can_place(piece, drag_origin)
	queue_redraw()

func _draw() -> void:
	_draw_background()
	if screen == "menu":
		_draw_menu()
		return
	if screen == "settings":
		_draw_settings()
		return
	_draw_game()
	if dragging_index >= 0:
		_draw_drag_layer()

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), rules_config.background_color)

func _draw_menu() -> void:
	var center := size * 0.5
	_draw_centered_text("BLOCK BLAST", center.y - 140, 42, rules_config.text_color)
	_draw_centered_text("方块消除", center.y - 104, 24, rules_config.secondary_color)
	_draw_centered_text("最高分：%d" % int(save_data.get("high_score", 0)), center.y - 65, 20, rules_config.text_color.lightened(0.15))
	if not save_status_text.is_empty():
		_draw_centered_text(save_status_text, center.y + 225, 16, Color("#b91c1c"))

func _draw_settings() -> void:
	var panel := _settings_panel_rect()
	draw_style_box(_box(rules_config.board_color, 24), panel)
	_draw_centered_text("设置", panel.position.y + 55, 30, rules_config.text_color)
	var notice := "切换立即生效并自动保存" if save_status_text.is_empty() else save_status_text
	_draw_centered_text(notice, panel.position.y + 441, 16, rules_config.text_color.lightened(0.35) if save_status_text.is_empty() else Color("#b91c1c"))

func _draw_centered_text(text: String, baseline: float, font_size: int, color: Color) -> void:
	var width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(ThemeDB.fallback_font, Vector2((size.x - width) * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_game() -> void:
	if game == null:
		return
	draw_string(ThemeDB.fallback_font, Vector2(BOARD_MARGIN, size.y - TRAY_HEIGHT + 26), "选择方块并拖到棋盘", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, rules_config.text_color.lightened(0.3))
	_draw_board()
	_draw_tray()
	if status_text != "":
		var status_pos := Vector2(BOARD_MARGIN, size.y - 5)
		draw_string(ThemeDB.fallback_font, status_pos, status_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 2.0 * BOARD_MARGIN, 13, rules_config.text_color.lightened(0.3))

func _draw_board() -> void:
	var rect := _board_rect()
	draw_style_box(_box(rules_config.board_color, 20), rect.grow(8))
	var cell := _cell_size()
	var hide_final_board := input_locked and not pending_move.is_empty()
	for y in range(_board_size()):
		for x in range(_board_size()):
			var value := -1 if hide_final_board else game.board.get_cell(x, y)
			var color := rules_config.empty_cell_color
			if value >= 0:
				color = rules_config.primary_color if rules_config.palette.is_empty() else rules_config.palette[posmod(value, rules_config.palette.size())]
			var cell_rect := Rect2(rect.position + Vector2(x, y) * cell + Vector2(2, 2), Vector2(cell - 4, cell - 4))
			draw_style_box(_box(color, 7), cell_rect)
	if dragging_index >= 0 and game != null:
		var piece: PieceData = game.remaining_pieces[dragging_index]
		var preview_color := Color("#22c55e", 0.72) if drag_valid else Color("#ef4444", 0.58)
		for local_cell in piece.cells:
			var target := drag_origin + local_cell
			if target.x >= 0 and target.x < _board_size() and target.y >= 0 and target.y < _board_size():
				var preview_rect := Rect2(rect.position + Vector2(target.x, target.y) * cell + Vector2(2, 2), Vector2(cell - 4, cell - 4))
				draw_style_box(_box(preview_color, 7), preview_rect)

func _draw_tray() -> void:
	var pieces := _visible_tray()
	for index in range(maxi(1, rules_config.tray_count)):
		draw_style_box(_box(rules_config.board_color, 12), _tray_slot_rect(index))
		if index >= pieces.size():
			continue
		var piece: PieceData = pieces[index]
		if index == dragging_index or piece.get_instance_id() == rebound_piece_id:
			continue
		var origin := _tray_piece_origin(index, piece)
		var cell := _tray_unit(index, piece)
		for local_cell in piece.cells:
			var p := origin + Vector2(local_cell.x, local_cell.y) * cell
			var r := Rect2(p + Vector2(2, 2), Vector2(cell - 4, cell - 4))
			draw_style_box(_box(_piece_color(piece), 5), r)

func _draw_drag_layer() -> void:
	if game == null or dragging_index >= game.remaining_pieces.size():
		return
	var piece: PieceData = game.remaining_pieces[dragging_index]
	var origin := _floating_origin(drag_mouse)
	var unit := _cell_size()
	for cell in piece.cells:
		var rect := Rect2(origin + Vector2(cell) * unit + Vector2(2, 2), Vector2.ONE * (unit - 4))
		var style := _box(_piece_color(piece), 7)
		style.border_color = Color.WHITE
		style.set_border_width_all(2)
		draw_style_box(style, rect)

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
