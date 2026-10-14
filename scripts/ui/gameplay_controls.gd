class_name GameplayControls
extends Control

## Presentation only: state and scoring remain owned by GameState.
signal pause_requested
signal restart_requested
signal menu_requested
signal resume_requested
signal settings_requested

const BlockArt := preload("res://scripts/ui/block_art.gd")
const ArtIconButton := preload("res://scripts/ui/art_icon_button.gd")
const MODE_HIDDEN := "hidden"
const MODE_PLAYING := "playing"
const MODE_PAUSED := "paused"
const MODE_GAME_OVER := "game_over"
const MIN_BUTTON_HEIGHT := 52.0
const GOLD := Color("#ffd05a")
const AQUA := Color("#73f8e4")
const MUTED := Color("#aec3eb")

var _mode := MODE_HIDDEN
var _stats: Dictionary = {}
var _configured := false
var _focus_mode := ""
var _focus_pending := false
var _playfield := Rect2()
var _primary := GOLD
var _secondary := Color("#3975d8")
var _text := Color("#eef6ff")
var _surface := Color("#17284b")
var _playing_root: Control
var _title_label: Label
var _stats_label: Label
var _detail_label: Label
var _playing_buttons: HBoxContainer
var _settings_button: Button
var _pause_button: Button
var _playing_restart_button: Button
var _playing_menu_button: Button
var _crown_rect := Rect2()
var _overlay_root: Control
var _scrim: ColorRect
var _card: PanelContainer
var _overlay_box: VBoxContainer
var _overlay_title: Label
var _overlay_score: Label
var _overlay_best: Label
var _overlay_stats: Label
var _new_record_label: Label
var _overlay_buttons: HBoxContainer
var _resume_button: Button
var _overlay_restart_button: Button
var _overlay_menu_button: Button
var _score_tween: Tween
var _display_score := 0.0
var _target_score := -1
var _notice: PanelContainer
var _notice_label: Label
var _notice_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_controls()
	_configured = true
	_apply_theme()
	_apply_state(false)

func _exit_tree() -> void:
	_stop_score_animation()
	clear_notice()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _configured:
		_layout_controls()

func _draw() -> void:
	if _configured and _mode == MODE_PLAYING:
		BlockArt.draw_icon(self, "crown", _crown_rect, GOLD)

func configure(primary: Color, secondary: Color, text: Color, surface: Color) -> void:
	_primary = primary
	_secondary = secondary
	_text = text
	_surface = surface
	_apply_theme()
	if _configured:
		_layout_controls()

## Geometry is supplied by the board owner; it never affects the game rules.
func set_playfield(rect: Rect2) -> void:
	_playfield = rect
	if _configured:
		_layout_controls()

func score_target() -> Vector2:
	if is_instance_valid(_stats_label):
		return _stats_label.position + _stats_label.size * 0.5
	return Vector2(size.x * 0.5, header_height() * 0.65)

## Accepted stats include the existing score breakdown and reduced_motion.
func set_mode(mode: String, stats: Dictionary = {}) -> void:
	var next_mode := mode if mode in [MODE_HIDDEN, MODE_PLAYING, MODE_PAUSED, MODE_GAME_OVER] else MODE_HIDDEN
	var mode_changed := next_mode != _mode
	_mode = next_mode
	_stats = stats.duplicate(true)
	_apply_state(mode_changed)

func header_height() -> float:
	var height := clampf(size.y * 0.18, 148.0, 210.0)
	if size.y > size.x:
		height = clampf(size.y * 0.20, 210.0, 560.0)
	if size.x < 350.0:
		return maxf(height, 210.0)
	if size.x < 440.0:
		return maxf(height, 176.0)
	return height

func get_restart_rect() -> Rect2:
	if _mode == MODE_PAUSED or _mode == MODE_GAME_OVER:
		return _local_button_rect(_overlay_restart_button)
	return _local_button_rect(_playing_restart_button)

func get_menu_rect() -> Rect2:
	if _mode == MODE_PAUSED or _mode == MODE_GAME_OVER:
		return _local_button_rect(_overlay_menu_button)
	return _local_button_rect(_playing_menu_button)

## A single short, non-blocking notice; later notices replace earlier ones.
func show_notice(message: String, kind: String = "info", reduced_motion: bool = false) -> void:
	if not _configured or _mode != MODE_PLAYING or message.is_empty():
		return
	clear_notice()
	_notice_label.text = message
	var accent := GOLD if kind in ["success", "record"] else AQUA
	if kind in ["error", "invalid"]:
		accent = Color("#ffb677")
	var box := _button_box(Color("#193861"))
	box.border_color = Color(accent, 0.65)
	box.content_margin_top = 5.0
	box.content_margin_bottom = 5.0
	_notice.add_theme_stylebox_override("panel", box)
	_notice_label.add_theme_color_override("font_color", accent)
	_notice.modulate = Color.WHITE
	_notice.visible = true
	_layout_notice()
	_notice_tween = create_tween()
	if reduced_motion:
		_notice_tween.tween_interval(2.0)
	else:
		_notice.modulate.a = 0.0
		_notice_tween.tween_property(_notice, "modulate:a", 1.0, 0.12)
		_notice_tween.tween_interval(1.55)
		_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.24)
	_notice_tween.tween_callback(clear_notice)

func clear_notice() -> void:
	if is_instance_valid(_notice_tween):
		_notice_tween.kill()
	_notice_tween = null
	if is_instance_valid(_notice):
		_notice.visible = false
		_notice.modulate = Color.WHITE

func _build_controls() -> void:
	_playing_root = Control.new()
	_playing_root.name = "PlayingHUD"
	_playing_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_playing_root)
	_title_label = _new_label("Title", 26)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_playing_root.add_child(_title_label)
	_stats_label = _new_label("Stats", 64)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_playing_root.add_child(_stats_label)
	_detail_label = _new_label("MoveDetail", 14)
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_playing_root.add_child(_detail_label)
	_playing_buttons = HBoxContainer.new()
	_playing_buttons.name = "Actions"
	_playing_buttons.add_theme_constant_override("separation", 6)
	_playing_root.add_child(_playing_buttons)
	_settings_button = _new_icon_button("SettingsButton", "gear", "设置")
	_settings_button.pressed.connect(_on_settings_pressed)
	_playing_buttons.add_child(_settings_button)
	_pause_button = _new_icon_button("PauseButton", "pause", "暂停（Esc）")
	_pause_button.pressed.connect(_on_pause_pressed)
	_playing_buttons.add_child(_pause_button)
	_playing_restart_button = _new_icon_button("RestartButton", "restart", "重新开始（R）")
	_playing_restart_button.pressed.connect(_on_restart_pressed)
	_playing_buttons.add_child(_playing_restart_button)
	_playing_menu_button = _new_icon_button("MenuButton", "home", "返回菜单")
	_playing_menu_button.pressed.connect(_on_menu_pressed)
	_playing_buttons.add_child(_playing_menu_button)

	_overlay_root = Control.new()
	_overlay_root.name = "StateOverlay"
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay_root)
	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = Color(0.025, 0.045, 0.105, 0.76)
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
	_overlay_box.add_theme_constant_override("separation", 10)
	_card.add_child(_overlay_box)
	_overlay_title = _new_label("Title", 24)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(_overlay_title)
	_overlay_score = _new_label("Score", 68)
	_overlay_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_box.add_child(_overlay_score)
	_overlay_best = _new_label("BestScore", 18)
	_overlay_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(_overlay_best)
	_overlay_stats = _new_label("Stats", 16)
	_overlay_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Clipping keeps initial zero-width wrapping from inflating the whole card.
	_overlay_stats.max_lines_visible = 3
	_overlay_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_overlay_box.add_child(_overlay_stats)
	_new_record_label = _new_label("NewRecord", 18)
	_new_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(_new_record_label)
	_overlay_buttons = HBoxContainer.new()
	_overlay_buttons.name = "Actions"
	_overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_buttons.add_theme_constant_override("separation", 10)
	_overlay_box.add_child(_overlay_buttons)
	_resume_button = _new_button("ResumeButton", "继续游戏")
	_resume_button.tooltip_text = "继续游戏"
	_resume_button.pressed.connect(_on_resume_pressed)
	_overlay_buttons.add_child(_resume_button)
	_overlay_restart_button = _new_button("OverlayRestartButton", "重新开始")
	_overlay_restart_button.tooltip_text = "重新开始"
	_overlay_restart_button.pressed.connect(_on_restart_pressed)
	_overlay_buttons.add_child(_overlay_restart_button)
	_overlay_menu_button = _new_button("OverlayMenuButton", "返回菜单")
	_overlay_menu_button.tooltip_text = "返回菜单"
	_overlay_menu_button.pressed.connect(_on_menu_pressed)
	_overlay_buttons.add_child(_overlay_menu_button)
	_notice = PanelContainer.new()
	_notice.name = "Notice"
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.visible = false
	add_child(_notice)
	_notice_label = _new_label("Text", 15)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice_label.custom_minimum_size = Vector2(0.0, 24.0)
	_notice.add_child(_notice_label)

func _new_label(node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _new_icon_button(node_name: String, kind: String, hint: String) -> Button:
	var button := ArtIconButton.new()
	button.name = node_name
	button.icon_kind = kind
	button.icon_color = _text
	button.fill_color = Color("#264576")
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(48.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button

func _new_button(node_name: String, label: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = Vector2(44.0, MIN_BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	return button

func _apply_theme() -> void:
	if not is_instance_valid(_title_label):
		return
	_title_label.add_theme_color_override("font_color", GOLD)
	_stats_label.add_theme_color_override("font_color", AQUA)
	_stats_label.add_theme_color_override("font_shadow_color", Color("#246e94"))
	_stats_label.add_theme_constant_override("shadow_offset_y", 3)
	_detail_label.add_theme_color_override("font_color", MUTED)
	_overlay_title.add_theme_color_override("font_color", _text)
	_overlay_score.add_theme_color_override("font_color", AQUA)
	_overlay_score.add_theme_color_override("font_shadow_color", Color("#124164"))
	_overlay_score.add_theme_constant_override("shadow_offset_y", 3)
	_overlay_best.add_theme_color_override("font_color", GOLD)
	_overlay_stats.add_theme_color_override("font_color", MUTED)
	_new_record_label.add_theme_color_override("font_color", GOLD)
	_card.add_theme_stylebox_override("panel", _card_box())
	_style_button(_resume_button, GOLD, Color("#213759"))
	_style_button(_overlay_restart_button, GOLD, Color("#213759"))
	_style_button(_overlay_menu_button, Color("#2c4677"), _text)
	for button: Button in [_settings_button, _pause_button, _playing_restart_button, _playing_menu_button]:
		button.set("icon_color", _text)
		button.queue_redraw()

func _style_button(button: Button, accent: Color, foreground: Color) -> void:
	for role: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(role, foreground)
	button.add_theme_color_override("font_disabled_color", Color(foreground, 0.45))
	button.add_theme_stylebox_override("normal", _button_box(accent))
	button.add_theme_stylebox_override("hover", _button_box(accent.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _button_box(accent.darkened(0.10)))
	# Focus overlays the normal/hover style; it must not add a tinted shadow.
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.draw_center = false
	focus.border_color = AQUA
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(16)
	focus.set_expand_margin_all(3.0)
	focus.shadow_color = Color.TRANSPARENT
	focus.shadow_size = 0
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", _button_box(Color(accent, 0.35)))

func _button_box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = fill.lightened(0.25)
	box.set_border_width_all(1)
	box.set_corner_radius_all(14)
	box.shadow_color = Color(0.0, 0.02, 0.09, 0.28)
	box.shadow_size = 3
	box.shadow_offset = Vector2(0.0, 3.0)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box

func _card_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = _surface
	box.border_color = Color("#5779b6")
	box.set_border_width_all(2)
	box.set_corner_radius_all(24)
	box.shadow_color = Color(0.0, 0.01, 0.05, 0.45)
	box.shadow_size = 18
	box.shadow_offset = Vector2(0.0, 8.0)
	box.content_margin_left = 28.0
	box.content_margin_right = 28.0
	box.content_margin_top = 24.0
	box.content_margin_bottom = 24.0
	return box

func _apply_state(mode_changed: bool) -> void:
	if mode_changed:
		_focus_mode = ""
		_focus_pending = true
		_stop_score_animation()
		clear_notice()
	if not _configured:
		return
	_update_texts(mode_changed)
	var input_locked := bool(_stats.get("input_locked", false))
	# A paused feedback animation must always be resumable.
	_pause_button.disabled = false
	_resume_button.disabled = false
	for button: Button in [_settings_button, _playing_restart_button, _playing_menu_button, _overlay_restart_button, _overlay_menu_button]:
		button.disabled = input_locked
	_playing_root.visible = _mode == MODE_PLAYING
	_overlay_root.visible = _mode == MODE_PAUSED or _mode == MODE_GAME_OVER
	_scrim.visible = _overlay_root.visible
	_card.visible = _overlay_root.visible
	_resume_button.visible = _mode == MODE_PAUSED
	_overlay_restart_button.visible = _overlay_root.visible
	_overlay_menu_button.visible = _overlay_root.visible
	_new_record_label.visible = _mode == MODE_GAME_OVER
	_layout_controls()
	if _focus_pending:
		if _mode == MODE_HIDDEN:
			for button: Button in [_settings_button, _pause_button, _playing_restart_button, _playing_menu_button, _resume_button, _overlay_restart_button, _overlay_menu_button]:
				button.release_focus()
		else:
			_grab_first_focus()
		_focus_pending = false
	queue_redraw()

func _update_texts(mode_changed: bool) -> void:
	var score := int(_stats.get("score", 0))
	var high_score := int(_stats.get("high_score", 0))
	var combo := int(_stats.get("combo", 0))
	var total_cleared := int(_stats.get("total_cleared_lines", 0))
	var round_index := int(_stats.get("round_index", 0))
	var placement_points := int(_stats.get("placement_points", 0))
	var clear_points := int(_stats.get("clear_points", 0))
	var clear_lines := int(_stats.get("clear_lines", 0))
	_title_label.text = str(high_score)
	_title_label.tooltip_text = "最高分：%d" % high_score
	_detail_label.text = "放置 +%d  ·  消除 +%d  ·  %d 线" % [placement_points, clear_points, clear_lines]
	if combo > 0:
		_detail_label.text += "  ·  连击 ×%d" % combo
	_overlay_title.text = "已暂停" if _mode == MODE_PAUSED else "游戏结束"
	_overlay_score.text = str(score)
	_overlay_best.text = "最高分  %d" % high_score
	if _mode == MODE_PAUSED:
		_overlay_stats.text = "当前连击 ×%d   ·   已消除 %d 行/列\n最近放置 +%d   消除 +%d   ·   %d 线" % [combo, total_cleared, placement_points, clear_points, clear_lines]
	else:
		_overlay_stats.text = "消除 %d 行/列   ·   完成 %d 回合\n最近放置 +%d   消除 +%d   ·   %d 线" % [total_cleared, round_index + 1, placement_points, clear_points, clear_lines]
	_new_record_label.text = "新纪录！" if bool(_stats.get("new_record", false)) else "再来一局"
	_refresh_score(score, mode_changed)

func _refresh_score(score: int, mode_changed: bool) -> void:
	var reduced_motion := bool(_stats.get("reduced_motion", false))
	if mode_changed or _mode != MODE_PLAYING or reduced_motion or _target_score < 0:
		_stop_score_animation()
		_target_score = score
		_set_display_score(float(score))
		return
	if score == _target_score:
		return
	_stop_score_animation()
	_target_score = score
	_score_tween = create_tween()
	_score_tween.tween_method(_set_display_score, _display_score, float(score), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_score_tween.parallel().tween_property(_stats_label, "scale", Vector2(1.08, 1.08), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_score_tween.tween_property(_stats_label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_score_tween.tween_callback(func() -> void: _score_tween = null)

func _set_display_score(value: float) -> void:
	_display_score = value
	if is_instance_valid(_stats_label):
		_stats_label.text = str(int(roundf(value)))

func _stop_score_animation() -> void:
	if is_instance_valid(_score_tween):
		_score_tween.kill()
	_score_tween = null
	if is_instance_valid(_stats_label):
		_stats_label.scale = Vector2.ONE

func _layout_controls() -> void:
	if not _configured:
		return
	_playing_root.position = Vector2.ZERO
	_playing_root.size = Vector2(size.x, header_height())
	_overlay_root.position = Vector2.ZERO
	_overlay_root.size = size
	var field := _effective_playfield()
	var stage_width := minf(maxf(field.size.x, 520.0), maxf(size.x - 32.0, 1.0))
	var stage_left := field.get_center().x - stage_width * 0.5
	var portrait := size.y > size.x
	var icon_side := clampf(stage_width * 0.06, 48.0, 72.0) if portrait else 48.0
	for button: Button in [_settings_button, _pause_button, _playing_restart_button, _playing_menu_button]:
		button.custom_minimum_size = Vector2.ONE * icon_side
	var icons_width := icon_side * 4.0 + 6.0 * 3.0
	var narrow := stage_width < 440.0
	var stacked_actions := stage_width < 318.0
	var crown_side := clampf(stage_width * 0.06, 34.0, 58.0) if portrait else 34.0
	_crown_rect = Rect2(stage_left, 19.0, crown_side, crown_side)
	_title_label.position = Vector2(stage_left + crown_side + 8.0, 14.0)
	_title_label.size = Vector2(maxf(stage_width - icons_width - crown_side - 22.0, 1.0), maxf(44.0, crown_side + 10.0))
	var best_font := clampi(int(stage_width * 0.045), 26, 50) if portrait else 26
	_title_label.add_theme_font_size_override("font_size", 21 if narrow else best_font)
	_playing_buttons.position = Vector2(stage_left + stage_width - icons_width, 12.0)
	_playing_buttons.size = Vector2(icons_width, icon_side)
	var short_header := header_height() < 160.0
	var score_font := clampi(int(field.size.x * 0.14), 80, 144) if portrait and header_height() >= 190.0 else 64
	var score_height := float(score_font) * 1.25
	var score_y := maxf(64.0, header_height() - score_height - 25.0)
	if short_header:
		score_font = 54
		score_height = 64.0
		score_y = 64.0
	if stacked_actions:
		_title_label.size.x = maxf(stage_width - 42.0, 1.0)
		_playing_buttons.position.y = 62.0
		score_font = 54
		score_height = 64.0
		score_y = 114.0
	_stats_label.add_theme_font_size_override("font_size", score_font)
	_stats_label.position = Vector2(stage_left, score_y)
	_stats_label.size = Vector2(stage_width, score_height)
	_stats_label.pivot_offset = _stats_label.size * 0.5
	var detail_y := field.position.y - 52.0
	_detail_label.position = Vector2(stage_left, detail_y)
	_detail_label.size = Vector2(stage_width, 24.0)
	_detail_label.add_theme_font_size_override("font_size", 12 if narrow else (clampi(int(stage_width * 0.018), 14, 22) if portrait else 14))
	_layout_overlay()
	_layout_notice()
	queue_redraw()

func _effective_playfield() -> Rect2:
	if _playfield.size.x > 0.0:
		return _playfield
	var side := minf(maxf(size.x - 48.0, 1.0), 520.0)
	return Rect2(Vector2((size.x - side) * 0.5, header_height() + 48.0), Vector2(side, side))

func _layout_notice() -> void:
	if not is_instance_valid(_notice):
		return
	var field := _effective_playfield()
	var width := minf(field.size.x, 460.0)
	_notice.size = Vector2(maxf(width, 1.0), 40.0)
	_notice.position = Vector2(field.get_center().x - width * 0.5, field.end.y + 28.0)

func _layout_overlay() -> void:
	_overlay_title.custom_minimum_size = Vector2(0.0, 32.0)
	_overlay_score.custom_minimum_size = Vector2(0.0, 78.0)
	_overlay_best.custom_minimum_size = Vector2(0.0, 28.0)
	_overlay_stats.custom_minimum_size = Vector2(0.0, 66.0)
	_new_record_label.custom_minimum_size = Vector2(0.0, 24.0)
	_overlay_buttons.custom_minimum_size = Vector2(0.0, MIN_BUTTON_HEIGHT)
	var card_width := minf(480.0, maxf(size.x - 32.0, 240.0))
	var card_height := 376.0 if _mode == MODE_PAUSED else 428.0
	var short_labels := card_width < 420.0
	_resume_button.text = "继续" if short_labels else "继续游戏"
	_overlay_restart_button.text = "重开" if short_labels else "重新开始"
	_overlay_menu_button.text = "菜单" if short_labels else "返回菜单"
	_card.size = Vector2(card_width, card_height)
	_card.position = Vector2((size.x - card_width) * 0.5, maxf((size.y - card_height) * 0.5, 12.0))
	# PanelContainer owns Content and its margins; do not preset child anchors.

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

func _on_settings_pressed() -> void:
	if not _settings_button.disabled:
		settings_requested.emit()
