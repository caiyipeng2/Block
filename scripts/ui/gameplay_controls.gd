class_name GameplayControls
extends Control

## Presentation only: state and scoring remain owned by GameState.
signal pause_requested
signal restart_requested
signal menu_requested
signal resume_requested
signal settings_requested
signal next_level_requested
signal levels_requested
signal objective_intro_dismissed

const BlockArt := preload("res://scripts/ui/block_art.gd")
const ArtIconButton := preload("res://scripts/ui/art_icon_button.gd")
const MODE_HIDDEN := "hidden"
const MODE_PLAYING := "playing"
const MODE_PAUSED := "paused"
const MODE_GAME_OVER := "game_over"
const MODE_LEVEL_COMPLETE := "level_complete"
const MIN_BUTTON_HEIGHT := 52.0
const GOLD := Color("#ffd05a")
const AQUA := Color("#73f8e4")
const MUTED := Color("#aec3eb")
const TARGET_KINDS := ["red_star", "gold_gem"]

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
var _mode_label: Label
var _goal_label: Label
var _goal_score_label: Label
var _playing_buttons: HBoxContainer
var _settings_button: Button
var _pause_button: Button
var _playing_restart_button: Button
var _playing_menu_button: Button
var _crown_rect := Rect2()
var _progress_track := Rect2()
var _current_badge := Rect2()
var _goal_badge := Rect2()
var _overlay_root: Control
var _scrim: ColorRect
var _card: PanelContainer
var _overlay_box: VBoxContainer
var _overlay_objective_badge: Control
var _overlay_title: Label
var _overlay_score: Label
var _overlay_best: Label
var _overlay_stats: Label
var _new_record_label: Label
var _overlay_buttons: HBoxContainer
var _resume_button: Button
var _overlay_restart_button: Button
var _overlay_menu_button: Button
var _next_level_button: Button
var _score_tween: Tween
var _display_score := 0.0
var _target_score := -1
var _notice: PanelContainer
var _notice_label: Label
var _notice_tween: Tween
var _overlay_tween: Tween
var _objective_rects: Dictionary = {}
var _intro_root: Control
var _intro_scrim: ColorRect
var _intro_scroll: ScrollContainer
var _intro_card: Control
var _intro_title: Label
var _intro_subtitle: Label
var _intro_description: Label
var _intro_targets: Control
var _intro_start_button: Button
var _intro_stats: Dictionary = {}
var _intro_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_controls()
	_configured = true
	_apply_theme()
	_apply_state(false)

func _exit_tree() -> void:
	hide_objective_intro()
	_stop_score_animation()
	_stop_overlay_animation()
	clear_notice()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _configured:
		_layout_controls()

func _draw() -> void:
	if _configured and _mode == MODE_PLAYING:
		if _is_adventure():
			if _is_collect_objective():
				_draw_collect_targets()
			else:
				_draw_level_progress()
		else:
			BlockArt.draw_icon(self, "crown", _crown_rect, GOLD)

func _is_adventure() -> bool:
	return str(_stats.get("mode", "free")) == "adventure"

func _is_collect_objective() -> bool:
	return _is_adventure() and str(_stats.get("objective_type", "score")) == "collect"

func _objective_total() -> int:
	return maxi(1, int(_stats.get("target_total", 1))) if _is_collect_objective() else maxi(1, int(_stats.get("target_score", 1)))

func _objective_current() -> int:
	return maxi(0, int(_stats.get("target_collected", 0))) if _is_collect_objective() else maxi(0, int(roundf(_display_score)))

func _target_count(source: Dictionary, field: String, kind: String) -> int:
	var counts: Variant = source.get(field, {})
	if counts is Dictionary and counts.has(kind):
		return maxi(0, int(counts[kind]))
	if field == "remaining_counts":
		if kind == "red_star" and not source.has("target_counts") and source.has("target_remaining"):
			return maxi(0, int(source["target_remaining"]))
		return maxi(0, _target_count(source, "target_counts", kind) - _target_count(source, "collected_counts", kind))
	if kind != "red_star":
		return 0
	match field:
		"target_counts":
			return maxi(0, int(source.get("target_total", 0)))
		"collected_counts":
			return maxi(0, int(source.get("target_collected", 0)))
	return 0

func _active_target_kinds(source: Dictionary) -> Array[String]:
	var kinds: Array[String] = []
	for kind: String in TARGET_KINDS:
		if _target_count(source, "target_counts", kind) > 0:
			kinds.append(kind)
	if kinds.is_empty():
		kinds.append("red_star")
	return kinds

func _remaining_count(kind: String) -> int:
	var counts: Variant = _stats.get("remaining_counts", {})
	if counts is Dictionary and counts.has(kind):
		return maxi(0, int(counts[kind]))
	return maxi(0, _target_count(_stats, "target_counts", kind) - _target_count(_stats, "collected_counts", kind))

func _target_summary(source: Dictionary, remaining: bool = false) -> String:
	var parts := PackedStringArray()
	for kind: String in _active_target_kinds(source):
		if remaining:
			var left := _target_count(source, "remaining_counts", kind)
			parts.append("%s %d" % [BlockArt.target_name(kind), left])
		else:
			parts.append("%s %d/%d" % [BlockArt.target_name(kind), _target_count(source, "collected_counts", kind), _target_count(source, "target_counts", kind)])
	return "  ·  ".join(parts)

func _draw_collect_targets() -> void:
	for kind: String in _active_target_kinds(_stats):
		var rect: Rect2 = _objective_rects.get(kind, Rect2())
		if rect.size.x <= 0.0:
			continue
		BlockArt.draw_target_marker(self, rect, 1.0, 1.0, kind)
		var count_rect := Rect2(rect.get_center().x - 35.0, rect.end.y + 1.0, 70.0, 24.0)
		_draw_centered_text(self, str(_remaining_count(kind)), count_rect, 22, Color.WHITE)

func _draw_centered_text(canvas: CanvasItem, value: String, rect: Rect2, max_font_size: int, color: Color) -> void:
	var font := _stats_label.get_theme_font("font")
	var font_size := max_font_size
	while font_size > 10 and (font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > rect.size.x or font.get_height(font_size) > rect.size.y):
		font_size -= 1
	var text_width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var baseline := rect.get_center() + Vector2(-text_width * 0.5, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	canvas.draw_string(font, baseline, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _draw_level_progress() -> void:
	if _current_badge.size.x <= 0.0:
		return
	var current_center := _current_badge.get_center()
	var goal_center := _goal_badge.get_center()
	var radius := _current_badge.size.x * 0.5
	# A continuous rail runs underneath both end caps, making one gauge.
	var rail_shadow := BlockArt.panel_style(Color("#233b6b"), int(_progress_track.size.y * 0.5), Color.TRANSPARENT)
	rail_shadow.set_content_margin_all(0.0)
	draw_style_box(rail_shadow, Rect2(_progress_track.position + Vector2(0.0, 3.0), _progress_track.size))
	var track_style := BlockArt.panel_style(Color("#182b4f"), int(_progress_track.size.y * 0.5), Color("#526fa4"))
	track_style.set_content_margin_all(0.0)
	draw_style_box(track_style, _progress_track)
	var progress := clampf(float(_objective_current()) / float(_objective_total()), 0.0, 1.0)
	var inner := _progress_track.grow(-4.0)
	var fill_width := inner.size.x * progress
	if fill_width > 0.0:
		var fill := Rect2(inner.position, Vector2(fill_width, inner.size.y))
		var fill_style := BlockArt.panel_style(AQUA if progress >= 1.0 else Color("#2eb9df"), int(inner.size.y * 0.5), Color.TRANSPARENT)
		fill_style.set_content_margin_all(0.0)
		draw_style_box(fill_style, fill)
	for center: Vector2 in [current_center, goal_center]:
		draw_circle(center + Vector2(0.0, 3.0), radius + 2.0, Color("#1b3159"))
	draw_circle(current_center, radius, Color("#169fd0"))
	draw_arc(current_center, radius - 1.0, 0.0, TAU, 64, Color("#6ae2f4"), 2.0, true)
	draw_arc(current_center + Vector2(0.0, 1.0), radius - 4.0, PI * 1.12, PI * 1.86, 24, Color(0.75, 0.97, 1.0, 0.24), 2.0, true)
	draw_circle(goal_center, radius + 1.0, Color("#243d6a"))
	draw_circle(goal_center, radius - 4.0, Color("#192a4d"))
	draw_arc(goal_center, radius - 1.0, 0.0, TAU, 64, Color("#5d7aac"), 2.0, true)
	_draw_badge_number(str(_objective_current()), _current_badge, Color("#f3ffff"))
	_draw_badge_number(str(_objective_total()), _goal_badge, GOLD)

func _draw_badge_number(value: String, rect: Rect2, color: Color) -> void:
	var font := _stats_label.get_theme_font("font")
	var font_size := _badge_font(int(value), rect.size.x)
	var text_width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	# Draw a baseline from ascent/descent instead of Label's minimum line height.
	var baseline := rect.get_center() + Vector2(-text_width * 0.5, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	draw_string(font, baseline + Vector2(0.0, 1.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.0, 0.06, 0.16, 0.25))
	draw_string(font, baseline, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _draw_overlay_objective_badge() -> void:
	var center := _overlay_objective_badge.size * 0.5
	if _is_collect_objective():
		var kinds := _active_target_kinds(_stats)
		var spacing := 58.0
		for index in range(kinds.size()):
			var marker_center := center + Vector2((float(index) - float(kinds.size() - 1) * 0.5) * spacing, 0.0)
			BlockArt.draw_target_marker(_overlay_objective_badge, Rect2(marker_center - Vector2.ONE * 24.0, Vector2.ONE * 48.0), 1.0, 1.0, kinds[index])
	else:
		_overlay_objective_badge.draw_circle(center, 25.0, Color("#293660"))
		BlockArt.draw_icon(_overlay_objective_badge, "crown", Rect2(center - Vector2.ONE * 20.0, Vector2.ONE * 40.0), GOLD)

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
	if _is_collect_objective():
		var center := Vector2.ZERO
		var kinds := _active_target_kinds(_stats)
		for kind: String in kinds:
			center += objective_target(kind)
		return center / float(kinds.size())
	if _is_adventure():
		return _current_badge.get_center()
	if is_instance_valid(_stats_label):
		return _stats_label.position + _stats_label.size * 0.5
	return Vector2(size.x * 0.5, header_height() * 0.65)

func objective_target(kind: String = "red_star") -> Vector2:
	var rect: Rect2 = _objective_rects.get(kind, Rect2())
	if _is_collect_objective() and rect.size.x > 0.0:
		return rect.get_center()
	return _current_badge.get_center() if _is_adventure() else score_target()

## The owner locks gameplay input while this independent introduction is visible.
func show_objective_intro(stats: Dictionary, reduced_motion: bool = false) -> void:
	if not _configured or _mode != MODE_PLAYING:
		return
	hide_objective_intro()
	clear_notice()
	_intro_stats = stats.duplicate(true)
	_intro_title.text = "收集目标"
	var level_id := maxi(1, int(_intro_stats.get("level_id", 1)))
	var difficulty := str(_intro_stats.get("difficulty_label", _intro_stats.get("stage_name", "")))
	_intro_subtitle.text = "第 %d 关" % level_id
	if not difficulty.is_empty():
		_intro_subtitle.text += "  ·  " + difficulty
	var description := str(_intro_stats.get("difficulty_description", ""))
	_intro_description.text = description if not description.is_empty() else "清除带标记的方块，收集全部目标"
	_intro_root.visible = true
	_set_intro_action_lock(true)
	_intro_scroll.scroll_vertical = 0
	_layout_objective_intro()
	_intro_targets.queue_redraw()
	_intro_card.queue_redraw()
	_intro_start_button.grab_focus()
	_ensure_intro_start_visible.call_deferred()
	if reduced_motion:
		return
	_intro_card.pivot_offset = _intro_card.size * 0.5
	_intro_card.scale = Vector2.ONE * 0.94
	_intro_card.modulate.a = 0.0
	_intro_scrim.modulate.a = 0.0
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_intro_tween.tween_property(_intro_card, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(_intro_card, "modulate:a", 1.0, 0.20)
	_intro_tween.tween_property(_intro_scrim, "modulate:a", 1.0, 0.20)
	_intro_tween.chain().tween_callback(func() -> void: _intro_tween = null)

func hide_objective_intro() -> void:
	_stop_intro_animation()
	if is_instance_valid(_intro_root):
		_intro_root.visible = false
	if is_instance_valid(_intro_start_button):
		_intro_start_button.release_focus()
	_intro_stats.clear()
	_set_intro_action_lock(false)

func is_objective_intro_visible() -> bool:
	return is_instance_valid(_intro_root) and _intro_root.visible

## Both button and owner keyboard actions converge here; it can emit only once.
func accept_objective_intro() -> void:
	if not is_objective_intro_visible():
		return
	hide_objective_intro()
	_focus_mode = ""
	_focus_pending = true
	objective_intro_dismissed.emit()
	_restore_objective_focus.call_deferred()

func _restore_objective_focus() -> void:
	if not _configured or not is_inside_tree() or _mode != MODE_PLAYING or is_objective_intro_visible():
		return
	_grab_first_focus()
	_focus_pending = false

func _stop_intro_animation() -> void:
	if is_instance_valid(_intro_tween):
		_intro_tween.kill()
	_intro_tween = null
	if is_instance_valid(_intro_card):
		_intro_card.scale = Vector2.ONE
		_intro_card.modulate = Color.WHITE
	if is_instance_valid(_intro_scrim):
		_intro_scrim.modulate = Color.WHITE

func _set_intro_action_lock(locked: bool) -> void:
	if not is_instance_valid(_pause_button):
		return
	_pause_button.disabled = locked
	for button: Button in [_settings_button, _playing_restart_button, _playing_menu_button]:
		button.disabled = locked or bool(_stats.get("input_locked", false))

## Objective stats: objective_type (score/collect), target_total,
## target_collected/target_remaining, plus dictionaries target_counts,
## collected_counts/remaining_counts keyed by red_star/gold_gem.
func set_mode(mode: String, stats: Dictionary = {}) -> void:
	var next_mode := mode if mode in [MODE_HIDDEN, MODE_PLAYING, MODE_PAUSED, MODE_GAME_OVER, MODE_LEVEL_COMPLETE] else MODE_HIDDEN
	var mode_changed := next_mode != _mode
	_mode = next_mode
	_stats = stats.duplicate(true)
	if next_mode != MODE_PLAYING:
		hide_objective_intro()
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
	if _mode in [MODE_PAUSED, MODE_GAME_OVER, MODE_LEVEL_COMPLETE]:
		return _local_button_rect(_overlay_restart_button)
	return _local_button_rect(_playing_restart_button)

func get_menu_rect() -> Rect2:
	if _mode in [MODE_PAUSED, MODE_GAME_OVER, MODE_LEVEL_COMPLETE]:
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
	_mode_label = _new_label("Mode", 14)
	_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_playing_root.add_child(_mode_label)
	_goal_label = _new_label("LevelGoal", 14)
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_playing_root.add_child(_goal_label)
	_goal_score_label = _new_label("TargetScore", 36)
	_goal_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_playing_root.add_child(_goal_score_label)
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
	_overlay_objective_badge = Control.new()
	_overlay_objective_badge.name = "ObjectiveBadge"
	_overlay_objective_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_objective_badge.custom_minimum_size = Vector2(56.0, 56.0)
	_overlay_objective_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_overlay_objective_badge.draw.connect(_draw_overlay_objective_badge)
	_overlay_box.add_child(_overlay_objective_badge)
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
	_next_level_button = _new_button("NextLevelButton", "下一关")
	_next_level_button.tooltip_text = "开始下一关"
	_next_level_button.pressed.connect(_on_next_level_pressed)
	_overlay_buttons.add_child(_next_level_button)
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
	_build_objective_intro()

func _build_objective_intro() -> void:
	_intro_root = Control.new()
	_intro_root.name = "ObjectiveIntro"
	_intro_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_root.z_index = 30
	_intro_root.visible = false
	add_child(_intro_root)
	_intro_scrim = ColorRect.new()
	_intro_scrim.name = "Scrim"
	_intro_scrim.color = Color(0.025, 0.045, 0.105, 0.78)
	_intro_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro_root.add_child(_intro_scrim)
	_intro_scroll = ScrollContainer.new()
	_intro_scroll.name = "RibbonViewport"
	_intro_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_intro_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_intro_scroll.follow_focus = true
	_intro_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_intro_root.add_child(_intro_scroll)
	_intro_card = Control.new()
	_intro_card.name = "Ribbon"
	_intro_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro_card.custom_minimum_size = Vector2(0.0, 390.0)
	_intro_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intro_card.draw.connect(_draw_intro_ribbon)
	_intro_scroll.add_child(_intro_card)
	_intro_title = _new_label("Title", 32)
	_intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_card.add_child(_intro_title)
	_intro_subtitle = _new_label("Level", 18)
	_intro_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_card.add_child(_intro_subtitle)
	_intro_description = _new_label("Description", 16)
	_intro_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_description.max_lines_visible = 2
	_intro_card.add_child(_intro_description)
	_intro_targets = Control.new()
	_intro_targets.name = "Targets"
	_intro_targets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_targets.draw.connect(_draw_intro_targets)
	_intro_card.add_child(_intro_targets)
	_intro_start_button = _new_button("StartChallengeButton", "开始挑战")
	_intro_start_button.pressed.connect(accept_objective_intro)
	_intro_card.add_child(_intro_start_button)
	_intro_card.resized.connect(_layout_objective_intro_content)

func _draw_intro_ribbon() -> void:
	var width := _intro_card.size.x
	var height := _intro_card.size.y
	var panel := Rect2(14.0, 0.0, maxf(1.0, width - 28.0), height)
	_intro_card.draw_colored_polygon(PackedVector2Array([Vector2(0.0, 18.0), Vector2(32.0, 18.0), Vector2(32.0, 106.0), Vector2(0.0, 106.0), Vector2(10.0, 62.0)]), Color("#2456ac"))
	_intro_card.draw_colored_polygon(PackedVector2Array([Vector2(width, 18.0), Vector2(width - 32.0, 18.0), Vector2(width - 32.0, 106.0), Vector2(width, 106.0), Vector2(width - 10.0, 62.0)]), Color("#2456ac"))
	var shadow := BlockArt.panel_style(Color(0.025, 0.045, 0.13, 0.55), 20, Color.TRANSPARENT)
	_intro_card.draw_style_box(shadow, Rect2(panel.position + Vector2(0.0, 6.0), panel.size))
	var style := BlockArt.panel_style(Color("#2c62b4"), 20, Color("#73a9ef"))
	style.set_border_width_all(2)
	_intro_card.draw_style_box(style, panel)
	_intro_card.draw_line(Vector2(32.0, 86.0), Vector2(width - 32.0, 86.0), Color(0.6, 0.8, 1.0, 0.24), 1.0, true)

func _draw_intro_targets() -> void:
	var kinds := _active_target_kinds(_intro_stats)
	var slot_width := minf(156.0, _intro_targets.size.x / float(kinds.size()))
	var icon_side := minf(72.0, slot_width * 0.58)
	for index in range(kinds.size()):
		var kind := kinds[index]
		var center_x := _intro_targets.size.x * 0.5 + (float(index) - float(kinds.size() - 1) * 0.5) * slot_width
		var icon_rect := Rect2(center_x - icon_side * 0.5, 0.0, icon_side, icon_side)
		BlockArt.draw_target_marker(_intro_targets, icon_rect, 1.0, 1.0, kind)
		_draw_centered_text(_intro_targets, str(_target_count(_intro_stats, "target_counts", kind)), Rect2(center_x - slot_width * 0.5 + 4.0, icon_side + 2.0, slot_width - 8.0, 38.0), 34, Color.WHITE)
		_draw_centered_text(_intro_targets, BlockArt.target_name(kind), Rect2(center_x - slot_width * 0.5 + 4.0, icon_side + 42.0, slot_width - 8.0, 22.0), 16, Color("#d9ebff"))

func _layout_objective_intro() -> void:
	if not is_instance_valid(_intro_root):
		return
	_intro_root.position = Vector2.ZERO
	_intro_root.size = size
	_intro_scrim.position = Vector2.ZERO
	_intro_scrim.size = size
	var width := minf(680.0, maxf(size.x - 24.0, 1.0))
	var viewport_height := minf(390.0, maxf(size.y - 24.0, 1.0))
	_intro_scroll.size = Vector2(width, viewport_height)
	_intro_scroll.position = Vector2((size.x - width) * 0.5, maxf(12.0, (size.y - viewport_height) * 0.5))
	# ScrollContainer owns the content width; its viewport stays within the window.
	_intro_scroll.queue_sort()
	_layout_objective_intro_content()
	if is_objective_intro_visible() and viewport_height < 390.0:
		_ensure_intro_start_visible.call_deferred()

func _layout_objective_intro_content() -> void:
	if not is_instance_valid(_intro_start_button):
		return
	var width := _intro_card.size.x
	_intro_card.pivot_offset = _intro_card.size * 0.5
	var inner_width := maxf(width - 64.0, 1.0)
	_intro_title.position = Vector2(32.0, 12.0)
	_intro_title.size = Vector2(inner_width, 42.0)
	_intro_title.add_theme_font_size_override("font_size", 26 if width < 360.0 else 32)
	_intro_subtitle.position = Vector2(32.0, 54.0)
	_intro_subtitle.size = Vector2(inner_width, 28.0)
	_intro_subtitle.add_theme_font_size_override("font_size", 15 if width < 360.0 else 18)
	_intro_targets.position = Vector2(32.0, 100.0)
	_intro_targets.size = Vector2(inner_width, 140.0)
	_intro_description.position = Vector2(32.0, 254.0)
	_intro_description.size = Vector2(inner_width, 50.0)
	_intro_description.add_theme_font_size_override("font_size", 14 if width < 360.0 else 16)
	var button_width := minf(320.0, inner_width)
	_intro_start_button.position = Vector2((width - button_width) * 0.5, 320.0)
	_intro_start_button.size = Vector2(button_width, 52.0)
	_intro_card.queue_redraw()
	_intro_targets.queue_redraw()

func _ensure_intro_start_visible() -> void:
	if is_objective_intro_visible() and is_instance_valid(_intro_start_button):
		_intro_scroll.ensure_control_visible(_intro_start_button)

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
	_mode_label.add_theme_color_override("font_color", MUTED)
	_goal_label.add_theme_color_override("font_color", MUTED)
	_goal_score_label.add_theme_color_override("font_color", GOLD)
	_overlay_title.add_theme_color_override("font_color", _text)
	_overlay_score.add_theme_color_override("font_color", AQUA)
	_overlay_score.add_theme_color_override("font_shadow_color", Color("#124164"))
	_overlay_score.add_theme_constant_override("shadow_offset_y", 3)
	_overlay_best.add_theme_color_override("font_color", GOLD)
	_overlay_stats.add_theme_color_override("font_color", MUTED)
	_new_record_label.add_theme_color_override("font_color", GOLD)
	_card.add_theme_stylebox_override("panel", _card_box())
	_style_button(_resume_button, GOLD, Color("#213759"))
	_style_button(_next_level_button, GOLD, Color("#213759"))
	_style_button(_overlay_restart_button, GOLD, Color("#213759"))
	_style_button(_overlay_menu_button, Color("#2c4677"), _text)
	_style_button(_intro_start_button, GOLD, Color("#213759"))
	_intro_title.add_theme_color_override("font_color", Color.WHITE)
	_intro_subtitle.add_theme_color_override("font_color", Color("#d8e9ff"))
	_intro_description.add_theme_color_override("font_color", Color("#e2edff"))
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
		_stop_overlay_animation()
		clear_notice()
	if not _configured:
		return
	_update_texts(mode_changed)
	if bool(_stats.get("reduced_motion", false)):
		_stop_overlay_animation()
	var intro_visible := is_objective_intro_visible()
	var input_locked := bool(_stats.get("input_locked", false)) or intro_visible
	# A paused feedback animation must always be resumable.
	_pause_button.disabled = intro_visible
	_resume_button.disabled = false
	_next_level_button.disabled = input_locked or not bool(_stats.get("has_next_level", false))
	for button: Button in [_settings_button, _playing_restart_button, _playing_menu_button, _overlay_restart_button, _overlay_menu_button]:
		button.disabled = input_locked
	_playing_root.visible = _mode == MODE_PLAYING
	_overlay_root.visible = _mode in [MODE_PAUSED, MODE_GAME_OVER, MODE_LEVEL_COMPLETE]
	_scrim.visible = _overlay_root.visible
	_card.visible = _overlay_root.visible
	_resume_button.visible = _mode == MODE_PAUSED
	_next_level_button.visible = _mode == MODE_LEVEL_COMPLETE
	_overlay_restart_button.visible = _overlay_root.visible
	_overlay_menu_button.visible = _overlay_root.visible
	_new_record_label.visible = _mode in [MODE_GAME_OVER, MODE_LEVEL_COMPLETE]
	_overlay_objective_badge.visible = _mode == MODE_LEVEL_COMPLETE
	_overlay_objective_badge.queue_redraw()
	_title_label.visible = not _is_adventure()
	_goal_label.visible = _is_adventure()
	# Adventure digits are drawn on the same canvas as their circular caps.
	_stats_label.visible = not _is_adventure()
	_goal_score_label.visible = false
	_stats_label.add_theme_color_override("font_color", Color("#efffff") if _is_adventure() else AQUA)
	_layout_controls()
	if _focus_pending:
		if _mode == MODE_HIDDEN:
			for button: Button in [_settings_button, _pause_button, _playing_restart_button, _playing_menu_button, _resume_button, _overlay_restart_button, _overlay_menu_button, _next_level_button]:
				button.release_focus()
		else:
			_grab_first_focus()
		_focus_pending = false
	if mode_changed and _overlay_root.visible:
		_animate_overlay_entrance()
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
	var adventure := _is_adventure()
	var level_id := int(_stats.get("level_id", 1))
	var goal := int(_stats.get("target_score", 0))
	var collect := _is_collect_objective()
	var collected := maxi(0, int(_stats.get("target_collected", 0)))
	var target_total := maxi(1, int(_stats.get("target_total", 1)))
	var remaining := maxi(0, int(_stats.get("target_remaining", target_total - collected)))
	var gameplay_mode := str(_stats.get("mode", "free"))
	_mode_label.text = "第 %d 关" % level_id if adventure else ("经典模式" if gameplay_mode == "classic" else "自由模式")
	_goal_label.text = "收集全部目标  ·  剩余 %d" % remaining if collect else "第 %d 关 · 目标 %d 分" % [level_id, goal]
	_goal_score_label.text = str(goal)
	_title_label.text = str(high_score)
	_title_label.tooltip_text = "最高分：%d" % high_score
	_detail_label.text = "放置 +%d  ·  消除 +%d  ·  %d 线" % [placement_points, clear_points, clear_lines]
	if combo > 0:
		_detail_label.text += "  ·  连击 ×%d" % combo
	if collect:
		_detail_label.text = "总分 %d  ·  " % score + _detail_label.text
	_overlay_title.text = "目标完成" if _mode == MODE_LEVEL_COMPLETE else ("已暂停" if _mode == MODE_PAUSED else ("第 %d 关未通过" % level_id if adventure else "游戏结束"))
	_overlay_score.text = "%d / %d" % [collected, target_total] if collect and _mode == MODE_LEVEL_COMPLETE else str(score)
	if collect:
		_overlay_best.text = "第 %d 关  ·  总分 %d" % [level_id, score] if _mode == MODE_LEVEL_COMPLETE else "剩余  " + _target_summary(_stats, true)
	else:
		_overlay_best.text = "第 %d 关  ·  目标 %d 分" % [level_id, goal] if adventure else "最高分  %d" % high_score
	if _mode == MODE_PAUSED:
		_overlay_stats.text = "当前连击 ×%d   ·   已消除 %d 行/列\n最近放置 +%d   消除 +%d   ·   %d 线" % [combo, total_cleared, placement_points, clear_points, clear_lines]
	else:
		_overlay_stats.text = "消除 %d 行/列   ·   完成 %d 回合\n最近放置 +%d   消除 +%d   ·   %d 线" % [total_cleared, round_index + 1, placement_points, clear_points, clear_lines]
	if collect and _mode == MODE_LEVEL_COMPLETE:
		_overlay_stats.text = _target_summary(_stats) + "\n消除 %d 行/列  ·  完成 %d 回合" % [total_cleared, round_index + 1]
	if _mode == MODE_LEVEL_COMPLETE:
		if bool(_stats.get("save_failed", false)):
			_new_record_label.text = "进度保存失败，本次运行已解锁"
		else:
			_new_record_label.text = "下一关已解锁" if bool(_stats.get("has_next_level", false)) else "恭喜完成全部 %d 关！" % int(_stats.get("total_levels", level_id))
	elif adventure:
		_new_record_label.text = "再挑战一次"
	else:
		_new_record_label.text = "新纪录！" if bool(_stats.get("new_record", false)) else "再来一局"
	_playing_menu_button.tooltip_text = "返回选关" if adventure else "返回菜单"
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
	if not _is_adventure():
		_score_tween.parallel().tween_property(_stats_label, "scale", Vector2(1.08, 1.08), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_score_tween.tween_property(_stats_label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_score_tween.tween_callback(func() -> void: _score_tween = null)

func _set_display_score(value: float) -> void:
	_display_score = value
	if is_instance_valid(_stats_label):
		_stats_label.text = str(_objective_current()) if _is_collect_objective() else str(int(roundf(value)))
	queue_redraw()

func _stop_score_animation() -> void:
	if is_instance_valid(_score_tween):
		_score_tween.kill()
	_score_tween = null
	if is_instance_valid(_stats_label):
		_stats_label.scale = Vector2.ONE

func _animate_overlay_entrance() -> void:
	_stop_overlay_animation()
	if bool(_stats.get("reduced_motion", false)):
		return
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2.ONE * 0.96
	_card.modulate.a = 0.0
	_scrim.modulate.a = 0.0
	_overlay_tween = create_tween().set_parallel(true)
	_overlay_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_overlay_tween.tween_property(_card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_overlay_tween.tween_property(_card, "modulate:a", 1.0, 0.18)
	_overlay_tween.tween_property(_scrim, "modulate:a", 1.0, 0.18)
	_overlay_tween.chain().tween_callback(func() -> void: _overlay_tween = null)

func _stop_overlay_animation() -> void:
	if is_instance_valid(_overlay_tween):
		_overlay_tween.kill()
	_overlay_tween = null
	if is_instance_valid(_card):
		_card.scale = Vector2.ONE
		_card.modulate = Color.WHITE
	if is_instance_valid(_scrim):
		_scrim.modulate = Color.WHITE

func _layout_controls() -> void:
	if not _configured:
		return
	_objective_rects.clear()
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
	_mode_label.position = Vector2(stage_left, 58.0)
	_mode_label.size = Vector2(maxf(stage_width - icons_width - 18.0, 1.0), 22.0)
	_mode_label.add_theme_font_size_override("font_size", 14 if narrow else 16)
	if _is_adventure():
		_mode_label.position.y = 19.0
		_mode_label.size.y = 38.0
		_mode_label.add_theme_font_size_override("font_size", 21 if narrow else 24)
		var badge_side := clampf(stage_width * 0.115, 64.0, 92.0) if portrait else 58.0
		var band_y := maxf(_playing_buttons.position.y + icon_side + 12.0, header_height() - badge_side - (38.0 if portrait else 18.0))
		if stacked_actions:
			band_y = maxf(band_y, _playing_buttons.position.y + icon_side + 12.0)
		_current_badge = Rect2(Vector2(stage_left, band_y), Vector2.ONE * badge_side)
		_goal_badge = Rect2(Vector2(stage_left + stage_width - badge_side, band_y), Vector2.ONE * badge_side)
		var track_height := clampf(badge_side * 0.82, 44.0, 64.0)
		var track_left := _current_badge.get_center().x
		var track_width := maxf(1.0, _goal_badge.get_center().x - track_left)
		_progress_track = Rect2(Vector2(track_left, band_y + (badge_side - track_height) * 0.5), Vector2(track_width, track_height))
		_stats_label.position = _current_badge.position + Vector2(3.0, 0.0)
		_stats_label.size = _current_badge.size - Vector2(6.0, 0.0)
		_stats_label.pivot_offset = _stats_label.size * 0.5
		_stats_label.add_theme_font_size_override("font_size", _badge_font(int(_stats.get("score", 0)), badge_side))
		_goal_score_label.position = _goal_badge.position + Vector2(3.0, 0.0)
		_goal_score_label.size = _goal_badge.size - Vector2(6.0, 0.0)
		_goal_score_label.add_theme_font_size_override("font_size", _badge_font(int(_stats.get("target_score", 0)), badge_side))
		_goal_label.position = Vector2(stage_left, band_y + badge_side + 2.0)
		_goal_label.size = Vector2(stage_width, 20.0)
		_goal_label.add_theme_font_size_override("font_size", 14 if portrait else 12)
		if _is_collect_objective():
			var kinds := _active_target_kinds(_stats)
			var target_side := clampf(badge_side * 0.60, 32.0, 56.0)
			var spacing := minf(120.0, stage_width * 0.24)
			for index in range(kinds.size()):
				var center_x := stage_left + stage_width * 0.5 + (float(index) - float(kinds.size() - 1) * 0.5) * spacing
				_objective_rects[kinds[index]] = Rect2(center_x - target_side * 0.5, band_y, target_side, target_side)
	var detail_y := field.position.y - 52.0
	_detail_label.position = Vector2(stage_left, detail_y)
	_detail_label.size = Vector2(stage_width, 24.0)
	_detail_label.add_theme_font_size_override("font_size", 12 if narrow else (clampi(int(stage_width * 0.018), 14, 22) if portrait else 14))
	_layout_overlay()
	_layout_notice()
	_layout_objective_intro()
	queue_redraw()

func _badge_font(value: int, diameter: float) -> int:
	var digit_count := maxi(1, str(maxi(0, value)).length())
	var font_size := clampi(int(minf(diameter * 0.58, (diameter - 12.0) / (float(digit_count) * 0.60))), 10, 50)
	if not is_instance_valid(_stats_label):
		return font_size
	var font := _stats_label.get_theme_font("font")
	var number := str(maxi(0, value))
	while font_size > 10 and (font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > diameter - 14.0 or font.get_height(font_size) > diameter - 12.0):
		font_size -= 1
	return font_size

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
	_overlay_objective_badge.custom_minimum_size = Vector2(132.0 if _is_collect_objective() else 56.0, 56.0)
	_overlay_title.custom_minimum_size = Vector2(0.0, 32.0)
	_overlay_score.custom_minimum_size = Vector2(0.0, 78.0)
	_overlay_best.custom_minimum_size = Vector2(0.0, 28.0)
	_overlay_stats.custom_minimum_size = Vector2(0.0, 66.0)
	_new_record_label.custom_minimum_size = Vector2(0.0, 24.0)
	_overlay_buttons.custom_minimum_size = Vector2(0.0, MIN_BUTTON_HEIGHT)
	var card_width := minf(540.0 if _mode == MODE_LEVEL_COMPLETE else 480.0, maxf(size.x - 32.0, 240.0))
	var card_height := 376.0 if _mode == MODE_PAUSED else (492.0 if _mode == MODE_LEVEL_COMPLETE else 428.0)
	var short_labels := card_width < 420.0
	_resume_button.text = "继续" if short_labels else "继续游戏"
	_next_level_button.text = "下一关" if bool(_stats.get("has_next_level", false)) else "全部通关"
	_next_level_button.tooltip_text = "开始下一关" if bool(_stats.get("has_next_level", false)) else "已通过所有关卡"
	_overlay_restart_button.text = ("重玩" if short_labels else "重玩本关") if _is_adventure() else ("重开" if short_labels else "重新开始")
	_overlay_menu_button.text = ("选关" if short_labels else "返回选关") if _is_adventure() else ("菜单" if short_labels else "返回菜单")
	_overlay_restart_button.tooltip_text = "重玩本关" if _is_adventure() else "重新开始"
	_overlay_menu_button.tooltip_text = "返回选关" if _is_adventure() else "返回菜单"
	_card.size = Vector2(card_width, card_height)
	_card.position = Vector2((size.x - card_width) * 0.5, maxf((size.y - card_height) * 0.5, 12.0))
	_card.pivot_offset = _card.size * 0.5
	# PanelContainer owns Content and its margins; do not preset child anchors.

func _grab_first_focus() -> void:
	if not _configured or _mode == MODE_HIDDEN or _focus_mode == _mode:
		return
	var first: Button
	if _mode == MODE_PLAYING:
		first = _pause_button
	elif _mode == MODE_PAUSED:
		first = _resume_button
	elif _mode == MODE_LEVEL_COMPLETE:
		first = _overlay_menu_button if _next_level_button.disabled else _next_level_button
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
	if _mode in [MODE_PAUSED, MODE_GAME_OVER, MODE_LEVEL_COMPLETE]:
		if not _overlay_restart_button.disabled:
			restart_requested.emit()
	elif not _playing_restart_button.disabled:
		restart_requested.emit()

func _on_menu_pressed() -> void:
	if _mode in [MODE_PAUSED, MODE_GAME_OVER, MODE_LEVEL_COMPLETE]:
		if not _overlay_menu_button.disabled:
			if _mode == MODE_LEVEL_COMPLETE:
				levels_requested.emit()
			else:
				menu_requested.emit()
	elif not _playing_menu_button.disabled:
		menu_requested.emit()

func _on_resume_pressed() -> void:
	if not _resume_button.disabled:
		resume_requested.emit()

func _on_settings_pressed() -> void:
	if not _settings_button.disabled:
		settings_requested.emit()

func _on_next_level_pressed() -> void:
	if _mode == MODE_LEVEL_COMPLETE and not _next_level_button.disabled:
		next_level_requested.emit()
