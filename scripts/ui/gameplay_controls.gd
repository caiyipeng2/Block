class_name GameplayControls
extends Control

## Native HUD and state overlays for the gameplay screen.
##
## The owner supplies the state through `set_mode`; this control only emits
## intent signals and never mutates GameState itself.

signal pause_requested
signal restart_requested
signal menu_requested
signal resume_requested

const MODE_HIDDEN := "hidden"
const MODE_PLAYING := "playing"
const MODE_PAUSED := "paused"
const MODE_GAME_OVER := "game_over"
const WIDE_BREAKPOINT := 700.0
const MIN_BUTTON_HEIGHT := 48.0

var _mode := MODE_HIDDEN
var _stats: Dictionary = {}
var _configured := false
var _focus_mode := ""
var _focus_pending := false

var _primary := Color("#ec4899")
var _secondary := Color("#8b5cf6")
var _text := Color("#0f172a")
var _surface := Color("#ffffff")

var _playing_root: Control
var _title_label: Label
var _stats_label: Label
var _detail_label: Label
var _playing_buttons: HBoxContainer
var _pause_button: Button
var _playing_restart_button: Button
var _playing_menu_button: Button

var _overlay_root: Control
var _scrim: ColorRect
var _card: PanelContainer
var _overlay_box: VBoxContainer
var _overlay_title: Label
var _overlay_stats: Label
var _new_record_label: Label
var _overlay_buttons: HBoxContainer
var _resume_button: Button
var _overlay_restart_button: Button
var _overlay_menu_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_controls()
	_configured = true
	_apply_theme()
	_apply_state(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _configured:
		_layout_controls()

## Apply the palette used by every native control in this layer.
func configure(primary: Color, secondary: Color, text: Color, surface: Color) -> void:
	_primary = primary
	_secondary = secondary
	_text = text
	_surface = surface
	_apply_theme()
	if _configured:
		_layout_controls()

## Switch the presentation state and refresh all statistic labels.
## `stats` accepts score, high_score, combo, total_cleared_lines,
## round_index, placement_points, clear_points, clear_lines, new_record,
## and input_locked.
func set_mode(mode: String, stats: Dictionary = {}) -> void:
	var next_mode := mode if mode in [MODE_HIDDEN, MODE_PLAYING, MODE_PAUSED, MODE_GAME_OVER] else MODE_HIDDEN
	var mode_changed := next_mode != _mode
	_mode = next_mode
	_stats = stats.duplicate(true)
	_apply_state(mode_changed)

func header_height() -> float:
	return 116.0 if size.x >= WIDE_BREAKPOINT else 164.0

## Return the currently relevant restart button in this control's local space.
func get_restart_rect() -> Rect2:
	if _mode == MODE_PAUSED or _mode == MODE_GAME_OVER:
		return _local_button_rect(_overlay_restart_button)
	return _local_button_rect(_playing_restart_button)

## Return the currently relevant menu button in this control's local space.
func get_menu_rect() -> Rect2:
	if _mode == MODE_PAUSED or _mode == MODE_GAME_OVER:
		return _local_button_rect(_overlay_menu_button)
	return _local_button_rect(_playing_menu_button)

func _build_controls() -> void:
	_playing_root = Control.new()
	_playing_root.name = "PlayingHUD"
	_playing_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_playing_root)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "BLOCK BLAST"
	_title_label.clip_text = true
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_playing_root.add_child(_title_label)

	_stats_label = Label.new()
	_stats_label.name = "Stats"
	_stats_label.clip_text = true
	_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 18)
	_playing_root.add_child(_stats_label)

	_detail_label = Label.new()
	_detail_label.name = "MoveDetail"
	_detail_label.clip_text = true
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_label.add_theme_font_size_override("font_size", 15)
	_playing_root.add_child(_detail_label)

	_playing_buttons = HBoxContainer.new()
	_playing_buttons.name = "Actions"
	_playing_buttons.add_theme_constant_override("separation", 8)
	_playing_root.add_child(_playing_buttons)
	_pause_button = _new_button("PauseButton", "暂停", _primary)
	_pause_button.pressed.connect(_on_pause_pressed)
	_playing_buttons.add_child(_pause_button)
	_playing_restart_button = _new_button("RestartButton", "重新开始", _primary)
	_playing_restart_button.pressed.connect(_on_restart_pressed)
	_playing_buttons.add_child(_playing_restart_button)
	_playing_menu_button = _new_button("MenuButton", "返回菜单", _secondary)
	_playing_menu_button.pressed.connect(_on_menu_pressed)
	_playing_buttons.add_child(_playing_menu_button)

	_overlay_root = Control.new()
	_overlay_root.name = "StateOverlay"
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay_root)

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = Color(0.03, 0.06, 0.12, 0.68)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.add_child(_scrim)

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.add_child(_card)
	_overlay_box = VBoxContainer.new()
	_overlay_box.name = "Content"
	_overlay_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_box.add_theme_constant_override("separation", 12)
	_card.add_child(_overlay_box)

	_overlay_title = Label.new()
	_overlay_title.name = "Title"
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 30)
	_overlay_box.add_child(_overlay_title)

	_overlay_stats = Label.new()
	_overlay_stats.name = "Stats"
	_overlay_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_stats.add_theme_font_size_override("font_size", 18)
	_overlay_box.add_child(_overlay_stats)

	_new_record_label = Label.new()
	_new_record_label.name = "NewRecord"
	_new_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_new_record_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_new_record_label.add_theme_font_size_override("font_size", 19)
	_overlay_box.add_child(_new_record_label)

	_overlay_buttons = HBoxContainer.new()
	_overlay_buttons.name = "Actions"
	_overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_buttons.add_theme_constant_override("separation", 10)
	_overlay_box.add_child(_overlay_buttons)

	_resume_button = _new_button("ResumeButton", "继续", _primary)
	_resume_button.pressed.connect(_on_resume_pressed)
	_overlay_buttons.add_child(_resume_button)
	_overlay_restart_button = _new_button("OverlayRestartButton", "重新开始", _primary)
	_overlay_restart_button.pressed.connect(_on_restart_pressed)
	_overlay_buttons.add_child(_overlay_restart_button)
	_overlay_menu_button = _new_button("OverlayMenuButton", "返回菜单", _secondary)
	_overlay_menu_button.pressed.connect(_on_menu_pressed)
	_overlay_buttons.add_child(_overlay_menu_button)

func _new_button(node_name: String, label: String, color: Color) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = Vector2(44.0, MIN_BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	button.set_meta("accent_color", color)
	return button

func _apply_theme() -> void:
	if not is_instance_valid(_title_label):
		return
	_title_label.add_theme_color_override("font_color", _text)
	_stats_label.add_theme_color_override("font_color", _text.lightened(0.12))
	_detail_label.add_theme_color_override("font_color", _text.lightened(0.28))
	_overlay_title.add_theme_color_override("font_color", _text)
	_overlay_stats.add_theme_color_override("font_color", _text.lightened(0.12))
	_new_record_label.add_theme_color_override("font_color", _primary.darkened(0.08))
	_card.add_theme_stylebox_override("panel", _card_box())
	for button: Button in [_pause_button, _playing_restart_button, _playing_menu_button, _resume_button, _overlay_restart_button, _overlay_menu_button]:
		var accent := _secondary if button == _playing_menu_button or button == _overlay_menu_button else _primary
		button.set_meta("accent_color", accent)
		_style_button(button, accent)

func _style_button(button: Button, accent: Color) -> void:
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.58))
	button.add_theme_stylebox_override("normal", _button_box(accent))
	button.add_theme_stylebox_override("hover", _button_box(accent.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _button_box(accent.darkened(0.12)))
	button.add_theme_stylebox_override("focus", _focus_box(accent))
	button.add_theme_stylebox_override("disabled", _button_box(Color(accent, 0.42)))

func _button_box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color(1.0, 1.0, 1.0, 0.2)
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box

func _focus_box(accent: Color) -> StyleBoxFlat:
	var box := _button_box(accent)
	box.border_color = Color.WHITE
	box.set_border_width_all(3)
	return box

func _card_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = _surface
	box.border_color = Color(_primary, 0.22)
	box.set_border_width_all(1)
	box.set_corner_radius_all(22)
	box.shadow_color = Color(0.02, 0.04, 0.1, 0.25)
	box.shadow_size = 10
	box.content_margin_left = 28.0
	box.content_margin_right = 28.0
	box.content_margin_top = 24.0
	box.content_margin_bottom = 24.0
	return box

func _apply_state(mode_changed: bool) -> void:
	if mode_changed:
		_focus_mode = ""
		_focus_pending = true
	if not _configured:
		return
	_update_texts()
	var input_locked := bool(_stats.get("input_locked", false))
	# Feedback can pause and resume while its state-changing actions stay locked.
	_pause_button.disabled = false
	_resume_button.disabled = false
	for button: Button in [_playing_restart_button, _playing_menu_button, _overlay_restart_button, _overlay_menu_button]:
		button.disabled = input_locked

	_playing_root.visible = _mode == MODE_PLAYING
	_overlay_root.visible = _mode == MODE_PAUSED or _mode == MODE_GAME_OVER
	_scrim.visible = _overlay_root.visible
	_card.visible = _overlay_root.visible
	_resume_button.visible = _mode == MODE_PAUSED
	_overlay_restart_button.visible = _mode == MODE_PAUSED or _mode == MODE_GAME_OVER
	_overlay_menu_button.visible = _mode == MODE_PAUSED or _mode == MODE_GAME_OVER
	_new_record_label.visible = _mode == MODE_GAME_OVER
	_layout_controls()

	if _focus_pending:
		if _mode == MODE_HIDDEN:
			for button: Button in [_pause_button, _playing_restart_button, _playing_menu_button, _resume_button, _overlay_restart_button, _overlay_menu_button]:
				button.release_focus()
		else:
			_grab_first_focus()
		_focus_pending = false

func _update_texts() -> void:
	var score := int(_stats.get("score", 0))
	var high_score := int(_stats.get("high_score", 0))
	var combo := int(_stats.get("combo", 0))
	var total_cleared := int(_stats.get("total_cleared_lines", 0))
	var round_index := int(_stats.get("round_index", 0))
	var placement_points := int(_stats.get("placement_points", 0))
	var clear_points := int(_stats.get("clear_points", 0))
	var clear_lines := int(_stats.get("clear_lines", 0))
	_stats_label.text = "分数 %d   最高 %d   连击 x%d" % [score, high_score, combo]
	_detail_label.text = "本次放置 +%d   清除 +%d   清除线 %d" % [placement_points, clear_points, clear_lines]
	_overlay_title.text = "已暂停" if _mode == MODE_PAUSED else "游戏结束"
	if _mode == MODE_PAUSED:
		_overlay_stats.text = "当前分数：%d\n最高分：%d\n连击：x%d\n最近：放置 +%d · 清除 +%d · 线 %d" % [score, high_score, combo, placement_points, clear_points, clear_lines]
		_new_record_label.text = ""
	else:
		_overlay_stats.text = "本局得分：%d\n最高分：%d\n总消线：%d\n回合：%d\n最近：放置 +%d · 清除 +%d · 线 %d" % [score, high_score, total_cleared, round_index + 1, placement_points, clear_points, clear_lines]
		_new_record_label.text = "新纪录！" if bool(_stats.get("new_record", false)) else "继续挑战更高分"

func _layout_controls() -> void:
	if not _configured:
		return
	_playing_root.position = Vector2.ZERO
	_playing_root.size = Vector2(size.x, header_height())
	_overlay_root.position = Vector2.ZERO
	_overlay_root.size = size
	if size.x < WIDE_BREAKPOINT:
		_layout_narrow_playing()
	else:
		_layout_wide_playing()
	_layout_overlay()

func _layout_wide_playing() -> void:
	_title_label.position = Vector2(24.0, 12.0)
	_title_label.size = Vector2(minf(360.0, maxf(size.x - 420.0, 220.0)), 44.0)
	_playing_buttons.position = Vector2(maxf(24.0, size.x - 360.0), 10.0)
	_playing_buttons.size = Vector2(minf(336.0, maxf(size.x - 48.0, 240.0)), MIN_BUTTON_HEIGHT)
	_stats_label.position = Vector2(24.0, 68.0)
	_stats_label.size = Vector2(maxf(size.x - 48.0, 1.0), 25.0)
	_detail_label.position = Vector2(24.0, 91.0)
	_detail_label.size = Vector2(maxf(size.x - 48.0, 1.0), 22.0)

func _layout_narrow_playing() -> void:
	_title_label.position = Vector2(20.0, 8.0)
	_title_label.size = Vector2(maxf(size.x - 40.0, 1.0), 34.0)
	_stats_label.position = Vector2(20.0, 45.0)
	_stats_label.size = Vector2(maxf(size.x - 40.0, 1.0), 28.0)
	_detail_label.position = Vector2(20.0, 73.0)
	_detail_label.size = Vector2(maxf(size.x - 40.0, 1.0), 28.0)
	_playing_buttons.position = Vector2(20.0, 112.0)
	_playing_buttons.size = Vector2(maxf(size.x - 40.0, 1.0), MIN_BUTTON_HEIGHT)

func _layout_overlay() -> void:
	var card_width := minf(560.0, maxf(size.x - 24.0, 280.0))
	var card_height := 302.0 if _mode == MODE_PAUSED else 410.0
	_card.size = Vector2(card_width, card_height)
	_card.position = Vector2((size.x - card_width) * 0.5, maxf((size.y - card_height) * 0.5, 12.0))
	# PanelContainer lays out its child inside the panel content area. Do not
	# assign the child the panel's own size: that feeds the size back into the
	# panel minimum-size calculation and can push the overlay content offscreen.
	_overlay_title.custom_minimum_size = Vector2(0.0, 42.0)
	_overlay_stats.custom_minimum_size = Vector2(0.0, 86.0 if _mode == MODE_GAME_OVER else 74.0)
	_new_record_label.custom_minimum_size = Vector2(0.0, 30.0)
	_overlay_buttons.custom_minimum_size = Vector2(0.0, MIN_BUTTON_HEIGHT)

func _grab_first_focus() -> void:
	if not _configured or _mode == MODE_HIDDEN or _focus_mode == _mode:
		return
	var first: Button
	if _mode == MODE_PLAYING:
		first = _pause_button
	elif _mode == MODE_PAUSED:
		first = _resume_button
	else:
		first = _overlay_restart_button
	if is_instance_valid(first) and not first.disabled and first.visible:
		_focus_mode = _mode
		first.grab_focus()

func _local_button_rect(button: Button) -> Rect2:
	if not is_instance_valid(button):
		return Rect2()
	var global_rect := button.get_global_rect()
	return Rect2(global_rect.position - global_position, global_rect.size)

func _on_pause_pressed() -> void:
	if not _pause_button.disabled:
		pause_requested.emit()

func _on_restart_pressed() -> void:
	if _mode == MODE_PAUSED or _mode == MODE_GAME_OVER:
		if not _overlay_restart_button.disabled:
			restart_requested.emit()
	elif not _playing_restart_button.disabled:
		restart_requested.emit()

func _on_menu_pressed() -> void:
	if _mode == MODE_PAUSED or _mode == MODE_GAME_OVER:
		if not _overlay_menu_button.disabled:
			menu_requested.emit()
	elif not _playing_menu_button.disabled:
		menu_requested.emit()

func _on_resume_pressed() -> void:
	if not _resume_button.disabled:
		resume_requested.emit()
