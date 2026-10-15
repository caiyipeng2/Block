class_name GameplayControls
extends Control

## Presentation only: state and scoring remain owned by GameState.
signal pause_requested
signal restart_requested
signal menu_requested
signal resume_requested
signal settings_requested
signal open_settings_requested
signal next_level_requested
signal levels_requested
signal objective_intro_dismissed

const BlockArt := preload("res://scripts/ui/block_art.gd")
const ArtIconButton := preload("res://scripts/ui/art_icon_button.gd")
const ProgressBanner := preload("res://scripts/ui/progress_banner.gd")
const MODE_HIDDEN := "hidden"
const MODE_PLAYING := "playing"
const MODE_PAUSED := "paused"
const MODE_GAME_OVER := "game_over"
const MODE_LEVEL_COMPLETE := "level_complete"
const MIN_BUTTON_HEIGHT := 52.0
const GOLD := Color("#ffd05a")
const AQUA := Color("#73f8e4")
const MUTED := Color("#aec3eb")
const TARGET_KINDS := ["blue_diamond", "gold_gem", "yellow_star", "red_star"]
## Victory timing and strength are presentation-only tuning values, in seconds.
const VICTORY_SEQUENCE_DURATION := 2.80
const VICTORY_GEM_START := 0.10
const VICTORY_TITLE_START := 0.44
const VICTORY_ACTION_START := 0.84
const VICTORY_SHEEN_START := 1.12
const VICTORY_GEM_OVERSHOOT := 1.25
const VICTORY_GLOW_STRENGTH := 1.0
const VICTORY_CONFETTI_COUNT := 104
const VICTORY_HERO_SIZE := Vector2(440.0, 280.0)
const VICTORY_CARD_WIDTH := 640.0
const VICTORY_CARD_HEIGHT := 630.0

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
var _collect_navigation: Control
var _collect_back_button: Button
var _collect_settings_button: Button
var _crown_rect := Rect2()
var _progress_track := Rect2()
var _current_badge := Rect2()
var _goal_badge := Rect2()
var _overlay_root: Control
var _card_viewport: ScrollContainer
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
var _overlay_secondary_buttons: HBoxContainer
var _overlay_settings_button: Button
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
var _intro_effects: Control
var _intro_skip_hint: Label
var _intro_flight_progress := -1.0
var _entry_progress := -1.0
var _intro_epoch := 0
var _target_pulses: Dictionary = {}
var _victory_progress := 1.0
var _victory_tween: Tween
var _victory_confetti: Control
var _victory_particles: Array[Dictionary] = []
var _victory_ambient_running := false
var _victory_ambient_time := 0.0
var _victory_button_ready := true
var _progress_banner: ProgressBanner
var _progress_banner_paused := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_controls()
	_configured = true
	_apply_theme()
	_apply_state(false)

func _exit_tree() -> void:
	clear_progress_milestones()
	hide_objective_intro()
	_stop_score_animation()
	_stop_overlay_animation()
	_stop_victory_animation()
	clear_notice()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _configured:
		_target_pulses.clear()
		_stop_victory_animation()
		_layout_controls()

func _process(delta: float) -> void:
	if _victory_ambient_running:
		_victory_ambient_time += delta
		_overlay_objective_badge.queue_redraw()
	if _target_pulses.is_empty():
		return
	for kind: String in _target_pulses.keys():
		var next := maxf(float(_target_pulses[kind]) - delta / 0.32, 0.0)
		if next <= 0.0:
			_target_pulses.erase(kind)
		else:
			_target_pulses[kind] = next
	queue_redraw()

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
	if counts is Dictionary and source.has(field):
		return maxi(0, int(counts.get(kind, 0)))
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
	# The owner advances this presentation dictionary only when flights arrive.
	var counts: Variant = _stats.get("display_remaining_counts", _stats.get("remaining_counts", {}))
	if counts is Dictionary and counts.has(kind):
		return maxi(0, int(counts[kind]))
	return maxi(0, _target_count(_stats, "target_counts", kind) - _target_count(_stats, "collected_counts", kind))

## Counts stay owned by the caller; this API provides arrival feedback only.
func notify_target_arrival(kind: String, counted: bool = true) -> void:
	if not counted or not _is_collect_objective() or bool(_stats.get("reduced_motion", false)):
		return
	_target_pulses[kind] = 1.0
	queue_redraw()

func apply_target_arrival(kind: String, counted: bool = true) -> void:
	notify_target_arrival(kind, counted)

func sync_target_display() -> void:
	# The latest set_mode stats already carry the owner's synchronized counts.
	_target_pulses.clear()
	queue_redraw()

func reset_target_display() -> void:
	sync_target_display()

## Presentation only: milestones are detected from arrival counts by the owner.
func show_progress_milestone(percent: int, reduced_motion: bool = false) -> void:
	if not _configured or not _is_collect_objective() or _mode not in [MODE_PLAYING, MODE_PAUSED] or is_objective_intro_visible():
		return
	_progress_banner.set_playfield(_effective_playfield(), size)
	_progress_banner.set_paused(_progress_banner_paused or _mode == MODE_PAUSED)
	_progress_banner.show_milestone(percent, reduced_motion)

func clear_progress_milestones() -> void:
	_progress_banner_paused = false
	if is_instance_valid(_progress_banner):
		_progress_banner.clear()

func set_progress_banner_paused(paused: bool) -> void:
	_progress_banner_paused = paused
	if is_instance_valid(_progress_banner):
		_progress_banner.set_paused(paused or _mode != MODE_PLAYING or is_objective_intro_visible())

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
		var pulse := float(_target_pulses.get(kind, 0.0))
		var scale_factor := 1.0 + sin(pulse * PI) * 0.16
		var marker_rect := Rect2(rect.get_center() - rect.size * scale_factor * 0.5, rect.size * scale_factor)
		if pulse > 0.0:
			draw_circle(rect.get_center(), rect.size.x * (0.55 + (1.0 - pulse) * 0.3), Color(0.65, 0.95, 1.0, pulse * 0.16))
		BlockArt.draw_target_marker(self, marker_rect, 1.0, 1.0 + pulse * 0.5, kind)
		var count_rect := Rect2(rect.get_center().x - 35.0, rect.end.y + 1.0, 70.0, 24.0)
		if _remaining_count(kind) <= 0:
			_draw_check(self, count_rect.get_center(), 9.0, 1.0)
		else:
			_draw_centered_text(self, str(_remaining_count(kind)), count_rect, 22, Color.WHITE)

func _draw_check(canvas: CanvasItem, center: Vector2, side: float, opacity: float) -> void:
	var points := PackedVector2Array([center + Vector2(-side * 0.70, 0.0), center + Vector2(-side * 0.12, side * 0.48), center + Vector2(side * 0.78, -side * 0.60)])
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(0.0, 1.5))
	var weight := maxf(3.5, side * 0.25)
	canvas.draw_polyline(shadow, Color(0.0, 0.20, 0.08, opacity), weight + 2.0, true)
	canvas.draw_polyline(points, Color(0.35, 1.0, 0.18, opacity), weight, true)

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
		var victory := _mode == MODE_LEVEL_COMPLETE
		if victory:
			_draw_victory_targets(kinds)
			return
		var spacing := minf(64.0, _overlay_objective_badge.size.x / float(maxi(kinds.size(), 1)))
		var marker_side := minf(48.0, spacing * 0.80)
		for index in range(kinds.size()):
			var marker_center := center + Vector2((float(index) - float(kinds.size() - 1) * 0.5) * spacing, 0.0)
			BlockArt.draw_target_marker(_overlay_objective_badge, Rect2(marker_center - Vector2.ONE * marker_side * 0.5, Vector2.ONE * marker_side), 1.0, 1.0, kinds[index])
	else:
		_overlay_objective_badge.draw_circle(center, 25.0, Color("#293660"))
		BlockArt.draw_icon(_overlay_objective_badge, "crown", Rect2(center - Vector2.ONE * 20.0, Vector2.ONE * 40.0), GOLD)

func _victory_time() -> float:
	return _victory_progress * VICTORY_SEQUENCE_DURATION

func _victory_marker_center(index: int, count: int) -> Vector2:
	var bounds := _overlay_objective_badge.size
	if count == 3:
		# The middle category crowns the group, with the other two below it.
		var horizontal := 0.265 if index == 0 else (0.735 if index == 2 else 0.5)
		return Vector2(bounds.x * horizontal, bounds.y * (0.265 if index == 1 else 0.64))
	if count == 1:
		return bounds * Vector2(0.5, 0.47)
	if count == 2:
		return bounds * Vector2(0.30 if index == 0 else 0.70, 0.48)
	var angle := -PI * 0.5 + TAU * float(index) / float(maxi(count, 1))
	return bounds * 0.5 + Vector2(cos(angle) * bounds.x * 0.29, sin(angle) * bounds.y * 0.28)

func _victory_pop(progress: float, overshoot: float) -> float:
	if progress <= 0.0:
		return 0.0
	if progress < 0.46:
		return lerpf(0.20, overshoot, sin(progress / 0.46 * PI * 0.5))
	var settling := (progress - 0.46) / 0.54
	return lerpf(overshoot, 1.0, 1.0 - pow(1.0 - settling, 3.0))

func _victory_presentation_kinds(kinds: Array[String]) -> Array[String]:
	if kinds.size() != 3:
		return kinds
	var upper := "gold_gem" if kinds.has("gold_gem") else kinds[0]
	var lower: Array[String] = []
	for kind: String in kinds:
		if kind != upper:
			lower.append(kind)
	var ordered: Array[String] = [lower[0], upper, lower[1]]
	return ordered

func _draw_victory_targets(kinds: Array[String]) -> void:
	var presentation_kinds := _victory_presentation_kinds(kinds)
	var reduced := bool(_stats.get("reduced_motion", false))
	var elapsed := _victory_time()
	var bounds := _overlay_objective_badge.size
	var marker_side := minf(bounds.x * 0.30, bounds.y * 0.42)
	_draw_victory_glow(reduced)
	for index in range(presentation_kinds.size()):
		var reveal := 1.0 if reduced else clampf((elapsed - VICTORY_GEM_START - float(index) * 0.065) / 0.34, 0.0, 1.0)
		if reveal <= 0.0:
			continue
		var marker_center := _victory_marker_center(index, presentation_kinds.size())
		if _victory_ambient_running:
			marker_center.y += sin(_victory_ambient_time * 1.8 + float(index) * 1.9) * 2.5
		var scale_factor := 1.0 if reduced else _victory_pop(reveal, VICTORY_GEM_OVERSHOOT)
		var side := marker_side * scale_factor
		var flash := 0.0 if reduced else sin(reveal * PI) * 0.65
		for ring in range(4, 0, -1):
			_overlay_objective_badge.draw_circle(marker_center, marker_side * (0.48 + float(ring) * 0.10), Color(1.0, 0.78, 0.23, 0.022 * reveal * VICTORY_GLOW_STRENGTH))
		BlockArt.draw_target_marker(_overlay_objective_badge, Rect2(marker_center - Vector2.ONE * side * 0.5, Vector2.ONE * side), minf(reveal * 4.0, 1.0), 1.15 + flash, presentation_kinds[index])
		var check_reveal := 1.0 if reduced else clampf((elapsed - 0.30 - float(index) * 0.085) / 0.20, 0.0, 1.0)
		if check_reveal > 0.0:
			var check_scale := 1.0 if reduced else _victory_pop(check_reveal, 1.30)
			_draw_check(_overlay_objective_badge, marker_center + Vector2(marker_side * 0.10, marker_side * 0.43), marker_side * 0.24 * check_scale, minf(check_reveal * 3.0, 1.0))

func _draw_victory_glow(reduced: bool) -> void:
	var canvas := _overlay_objective_badge
	var bounds := canvas.size
	var center := bounds * Vector2(0.5, 0.49)
	var radius := minf(bounds.x * 0.48, bounds.y * 0.61)
	var reveal := 1.0 if reduced else clampf((_victory_time() - 0.08) / 0.40, 0.0, 1.0)
	var strength := (0.48 if reduced else 1.0) * reveal * VICTORY_GLOW_STRENGTH
	for ring in range(10, 0, -1):
		var fraction := float(ring) / 10.0
		canvas.draw_circle(center, radius * fraction, Color(1.0, 0.70 + 0.14 * (1.0 - fraction), 0.20, (0.012 + (1.0 - fraction) * 0.022) * strength))
	if reduced:
		return
	var angle_offset := _victory_ambient_time * 0.12
	for ray in range(10):
		var angle := angle_offset + TAU * float(ray) / 10.0
		var ray_length := radius * (0.96 if ray % 2 == 0 else 1.08)
		canvas.draw_colored_polygon(PackedVector2Array([center, center + Vector2.from_angle(angle - 0.10) * ray_length, center + Vector2.from_angle(angle + 0.10) * ray_length]), Color(1.0, 0.85, 0.42, 0.030 * strength))
	for index in range(9):
		var phase := angle_offset * 1.6 + TAU * float(index) / 9.0
		var orbit := Vector2(cos(phase), sin(phase)) * radius * (0.65 + float(index % 3) * 0.10)
		var twinkle := 0.35 + 0.65 * pow(maxf(0.0, sin(_victory_ambient_time * 2.6 + float(index) * 2.0)), 3.0)
		var point := center + orbit
		var length := 2.0 + twinkle * 2.5
		var color := Color(1.0, 0.95, 0.62, twinkle * strength)
		canvas.draw_line(point - Vector2(length, 0.0), point + Vector2(length, 0.0), color, 1.3, true)
		canvas.draw_line(point - Vector2(0.0, length), point + Vector2(0.0, length), color, 1.3, true)

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
	clear_progress_milestones()
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
	_intro_root.grab_focus()
	var epoch := _intro_epoch
	if reduced_motion:
		_accept_intro_if_epoch.call_deferred(epoch)
		return
	_intro_card.pivot_offset = _intro_card.size * 0.5
	_intro_card.scale = Vector2.ONE * 0.94
	_intro_card.modulate.a = 0.0
	_intro_scrim.modulate.a = 0.0
	_intro_tween = create_tween()
	_intro_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_intro_tween.tween_property(_intro_card, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_intro_tween.parallel().tween_property(_intro_card, "modulate:a", 1.0, 0.20)
	_intro_tween.parallel().tween_property(_intro_scrim, "modulate:a", 1.0, 0.20)
	_intro_tween.tween_interval(0.80)
	_intro_tween.tween_callback(_begin_intro_flight)
	_intro_tween.tween_method(_set_intro_flight_progress, 0.0, 1.0, 0.48)
	_intro_tween.parallel().tween_property(_intro_card, "modulate:a", 0.0, 0.30)
	_intro_tween.parallel().tween_property(_intro_scrim, "modulate:a", 0.0, 0.34)
	_intro_tween.tween_callback(_begin_board_entry)
	_intro_tween.tween_method(_set_entry_progress, 0.0, 1.0, 0.70).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_intro_tween.tween_callback(_complete_intro_sequence)

func hide_objective_intro() -> void:
	_intro_epoch += 1
	_stop_intro_animation()
	if is_instance_valid(_intro_root):
		_intro_root.visible = false
	if is_instance_valid(_intro_start_button):
		_intro_start_button.release_focus()
	_intro_stats.clear()
	_set_intro_action_lock(false)
	if is_instance_valid(_intro_root):
		_intro_root.release_focus()

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

func _accept_intro_if_epoch(epoch: int) -> void:
	if epoch == _intro_epoch:
		accept_objective_intro()

func _complete_intro_sequence() -> void:
	_intro_tween = null
	accept_objective_intro()

func _begin_intro_flight() -> void:
	_intro_targets.visible = false
	_intro_flight_progress = 0.0
	_intro_effects.queue_redraw()

func _set_intro_flight_progress(progress: float) -> void:
	_intro_flight_progress = progress
	_intro_effects.queue_redraw()

func _begin_board_entry() -> void:
	_intro_flight_progress = -1.0
	_entry_progress = 0.0
	_intro_scroll.visible = false
	_intro_effects.queue_redraw()

func _set_entry_progress(progress: float) -> void:
	_entry_progress = progress
	_intro_effects.queue_redraw()

func _stop_intro_animation() -> void:
	if is_instance_valid(_intro_tween):
		_intro_tween.kill()
	_intro_tween = null
	_intro_flight_progress = -1.0
	_entry_progress = -1.0
	if is_instance_valid(_intro_targets):
		_intro_targets.visible = true
	if is_instance_valid(_intro_scroll):
		_intro_scroll.visible = true
	if is_instance_valid(_intro_effects):
		_intro_effects.queue_redraw()
	if is_instance_valid(_intro_card):
		_intro_card.scale = Vector2.ONE
		_intro_card.modulate = Color.WHITE
	if is_instance_valid(_intro_scrim):
		_intro_scrim.modulate = Color.WHITE

func _set_intro_action_lock(locked: bool) -> void:
	if not is_instance_valid(_pause_button):
		return
	_pause_button.disabled = locked
	for button: Button in [_settings_button, _playing_restart_button, _playing_menu_button, _collect_back_button, _collect_settings_button]:
		button.disabled = locked or bool(_stats.get("input_locked", false))

## Objective stats: objective_type (score/collect), target_total,
## target_collected/target_remaining, plus dictionaries target_counts,
## collected_counts/remaining_counts and display_remaining_counts keyed by kind.
func set_mode(mode: String, stats: Dictionary = {}) -> void:
	var next_mode := mode if mode in [MODE_HIDDEN, MODE_PLAYING, MODE_PAUSED, MODE_GAME_OVER, MODE_LEVEL_COMPLETE] else MODE_HIDDEN
	var mode_changed := next_mode != _mode
	_mode = next_mode
	_stats = stats.duplicate(true)
	if next_mode != MODE_PLAYING:
		hide_objective_intro()
	_apply_state(mode_changed)

func header_height() -> float:
	if _is_collect_objective():
		return clampf(size.y * 0.15, 132.0 if size.y > size.x else 116.0, 180.0)
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
	if _is_collect_objective():
		return _local_button_rect(_collect_back_button)
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
	_collect_navigation = Control.new()
	_collect_navigation.name = "CollectionNavigation"
	_collect_navigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playing_root.add_child(_collect_navigation)
	_collect_back_button = _new_icon_button("BackButton", "back", "返回选关")
	_collect_back_button.pressed.connect(func() -> void:
		if not _collect_back_button.disabled:
			menu_requested.emit())
	_collect_navigation.add_child(_collect_back_button)
	_collect_settings_button = _new_icon_button("SettingsButton", "gear", "暂停与设置")
	_collect_settings_button.pressed.connect(func() -> void:
		if not _collect_settings_button.disabled:
			settings_requested.emit())
	_collect_navigation.add_child(_collect_settings_button)

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
	_card_viewport = ScrollContainer.new()
	_card_viewport.name = "CardViewport"
	_card_viewport.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_viewport.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_card_viewport.follow_focus = true
	_card_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_viewport.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_overlay_root.add_child(_card_viewport)
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.resized.connect(_on_card_resized)
	_card_viewport.add_child(_card)
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
	_overlay_secondary_buttons = HBoxContainer.new()
	_overlay_secondary_buttons.name = "SecondaryActions"
	_overlay_secondary_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_secondary_buttons.add_theme_constant_override("separation", 10)
	_overlay_box.add_child(_overlay_secondary_buttons)
	_overlay_settings_button = _new_button("SettingsButton", "设置")
	_overlay_settings_button.pressed.connect(func() -> void:
		if not _overlay_settings_button.disabled:
			open_settings_requested.emit())
	_overlay_secondary_buttons.add_child(_overlay_settings_button)
	_victory_confetti = Control.new()
	_victory_confetti.name = "VictoryConfetti"
	_victory_confetti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_victory_confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_victory_confetti.draw.connect(_draw_victory_confetti)
	_overlay_root.add_child(_victory_confetti)
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
	_progress_banner = ProgressBanner.new()
	_progress_banner.name = "ProgressMilestones"
	_progress_banner.z_index = 4
	add_child(_progress_banner)

func _build_objective_intro() -> void:
	_intro_root = Control.new()
	_intro_root.name = "ObjectiveIntro"
	_intro_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_root.focus_mode = Control.FOCUS_ALL
	_intro_root.z_index = 30
	_intro_root.visible = false
	add_child(_intro_root)
	_intro_scrim = ColorRect.new()
	_intro_scrim.name = "Scrim"
	_intro_scrim.color = Color(0.025, 0.045, 0.105, 0.78)
	_intro_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro_scrim.gui_input.connect(_on_intro_gui_input)
	_intro_root.add_child(_intro_scrim)
	_intro_scroll = ScrollContainer.new()
	_intro_scroll.name = "RibbonViewport"
	_intro_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro_scroll.gui_input.connect(_on_intro_gui_input)
	_intro_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_intro_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_intro_scroll.follow_focus = true
	_intro_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_intro_root.add_child(_intro_scroll)
	_intro_card = Control.new()
	_intro_card.name = "Ribbon"
	_intro_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro_card.custom_minimum_size = Vector2(0.0, 260.0)
	_intro_card.gui_input.connect(_on_intro_gui_input)
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
	_intro_start_button.visible = false
	_intro_start_button.pressed.connect(accept_objective_intro)
	_intro_card.add_child(_intro_start_button)
	_intro_skip_hint = _new_label("SkipHint", 12)
	_intro_skip_hint.text = "点击或按任意确认键跳过"
	_intro_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_skip_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_card.add_child(_intro_skip_hint)
	_intro_card.resized.connect(_layout_objective_intro_content)
	_intro_effects = Control.new()
	_intro_effects.name = "IntroductionEffects"
	_intro_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_effects.draw.connect(_draw_intro_effects)
	_intro_root.add_child(_intro_effects)

func _on_intro_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_intro_root.accept_event()
		accept_objective_intro()

func _on_card_resized() -> void:
	_card.pivot_offset = _card.size * 0.5

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
	var icon_side := minf(60.0, slot_width * 0.58)
	for index in range(kinds.size()):
		var kind := kinds[index]
		var center_x := _intro_targets.size.x * 0.5 + (float(index) - float(kinds.size() - 1) * 0.5) * slot_width
		var icon_rect := Rect2(center_x - icon_side * 0.5, 0.0, icon_side, icon_side)
		BlockArt.draw_target_marker(_intro_targets, icon_rect, 1.0, 1.0, kind)
		_draw_centered_text(_intro_targets, str(_target_count(_intro_stats, "target_counts", kind)), Rect2(center_x - slot_width * 0.5 + 4.0, icon_side + 2.0, slot_width - 8.0, 30.0), 28, Color.WHITE)
		_draw_centered_text(_intro_targets, BlockArt.target_name(kind), Rect2(center_x - slot_width * 0.5 + 4.0, icon_side + 34.0, slot_width - 8.0, 18.0), 13, Color("#d9ebff"))

func _draw_intro_effects() -> void:
	if not is_objective_intro_visible():
		return
	if _intro_flight_progress >= 0.0:
		var kinds := _active_target_kinds(_intro_stats)
		var slot_width := minf(156.0, _intro_targets.size.x / float(kinds.size()))
		var icon_side := minf(60.0, slot_width * 0.58)
		var target_origin := _intro_targets.global_position - _intro_effects.global_position
		for index in range(kinds.size()):
			var progress := clampf((_intro_flight_progress - float(index) * 0.08) / 0.84, 0.0, 1.0)
			var start := target_origin + Vector2(_intro_targets.size.x * 0.5 + (float(index) - float(kinds.size() - 1) * 0.5) * slot_width, icon_side * 0.5)
			var destination := objective_target(kinds[index])
			var eased := progress * progress * (3.0 - 2.0 * progress)
			var point := start.lerp(destination, eased) - Vector2(0.0, sin(progress * PI) * 34.0)
			var side := lerpf(icon_side, 34.0, eased)
			BlockArt.draw_target_marker(_intro_effects, Rect2(point - Vector2.ONE * side * 0.5, Vector2.ONE * side), 1.0 - clampf((progress - 0.94) / 0.06, 0.0, 1.0), 1.4, kinds[index])
	if _entry_progress >= 0.0:
		var field := _effective_playfield()
		var side := field.size.x / 8.0
		var filling := clampf(_entry_progress / 0.40, 0.0, 1.0)
		var wiping := clampf((_entry_progress - 0.40) / 0.60, 0.0, 1.0)
		for row in range(8):
			for column in range(8):
				var delay := float(column + row) / 14.0
				var reveal := clampf(wiping * 2.0 - delay, 0.0, 1.0)
				if reveal >= 1.0:
					continue
				var rect := Rect2(field.position + Vector2(column, row) * side + Vector2.ONE, Vector2.ONE * maxf(side - 2.0, 1.0))
				_intro_effects.draw_rect(rect, Color(0.07, 0.11, 0.22, 1.0 - reveal))
				if filling >= delay:
					var color := Color("#5bd33d") if column < 4 else Color("#4979e8")
					BlockArt.draw_block(_intro_effects, rect, color, 1.0 - reveal, 0.1)

func _layout_objective_intro() -> void:
	if not is_instance_valid(_intro_root):
		return
	_intro_root.position = Vector2.ZERO
	_intro_root.size = size
	_intro_scrim.position = Vector2.ZERO
	_intro_scrim.size = size
	var width := minf(680.0, maxf(size.x - 24.0, 1.0))
	var viewport_height := minf(260.0, maxf(size.y - 24.0, 1.0))
	_intro_scroll.size = Vector2(width, viewport_height)
	_intro_scroll.position = Vector2((size.x - width) * 0.5, maxf(12.0, (size.y - viewport_height) * 0.5))
	# ScrollContainer owns the content width; its viewport stays within the window.
	_intro_scroll.queue_sort()
	_layout_objective_intro_content()
	_intro_effects.position = Vector2.ZERO
	_intro_effects.size = size
	_intro_effects.queue_redraw()

func _layout_objective_intro_content() -> void:
	if not is_instance_valid(_intro_start_button):
		return
	var width := _intro_card.size.x
	_intro_card.pivot_offset = _intro_card.size * 0.5
	var inner_width := maxf(width - 64.0, 1.0)
	_intro_title.position = Vector2(32.0, 6.0)
	_intro_title.size = Vector2(inner_width, 36.0)
	_intro_title.add_theme_font_size_override("font_size", 24 if width < 360.0 else 28)
	_intro_subtitle.position = Vector2(32.0, 42.0)
	_intro_subtitle.size = Vector2(inner_width, 28.0)
	_intro_subtitle.add_theme_font_size_override("font_size", 14 if width < 360.0 else 16)
	_intro_targets.position = Vector2(32.0, 86.0)
	_intro_targets.size = Vector2(inner_width, 112.0)
	_intro_description.position = Vector2(32.0, 204.0)
	_intro_description.size = Vector2(inner_width, 32.0)
	_intro_description.add_theme_font_size_override("font_size", 12 if width < 360.0 else 14)
	var button_width := minf(320.0, inner_width)
	_intro_start_button.position = Vector2((width - button_width) * 0.5, 320.0)
	_intro_start_button.size = Vector2(button_width, 52.0)
	_intro_skip_hint.position = Vector2(32.0, 238.0)
	_intro_skip_hint.size = Vector2(inner_width, 18.0)
	_intro_card.queue_redraw()
	_intro_targets.queue_redraw()

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
	_style_button(_overlay_settings_button, Color("#2c4677"), _text)
	_style_button(_intro_start_button, GOLD, Color("#213759"))
	_intro_title.add_theme_color_override("font_color", Color.WHITE)
	_intro_subtitle.add_theme_color_override("font_color", Color("#d8e9ff"))
	_intro_description.add_theme_color_override("font_color", Color("#e2edff"))
	_intro_skip_hint.add_theme_color_override("font_color", Color("#b7d4fa"))
	for button: Button in [_settings_button, _pause_button, _playing_restart_button, _playing_menu_button, _collect_back_button, _collect_settings_button]:
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
		_stop_victory_animation()
		clear_notice()
	if not _configured:
		return
	if _mode in [MODE_PLAYING, MODE_PAUSED] and _is_collect_objective():
		_progress_banner.set_paused(_progress_banner_paused or _mode == MODE_PAUSED or is_objective_intro_visible())
	else:
		clear_progress_milestones()
	_update_texts(mode_changed)
	if bool(_stats.get("reduced_motion", false)):
		_stop_overlay_animation()
		_stop_victory_animation()
		_target_pulses.clear()
		if is_objective_intro_visible():
			_accept_intro_if_epoch.call_deferred(_intro_epoch)
	var intro_visible := is_objective_intro_visible()
	var input_locked := bool(_stats.get("input_locked", false)) or intro_visible
	# A paused feedback animation must always be resumable.
	_pause_button.disabled = intro_visible
	_resume_button.disabled = false
	_next_level_button.disabled = input_locked or not bool(_stats.get("has_next_level", false))
	for button: Button in [_settings_button, _playing_restart_button, _playing_menu_button, _overlay_restart_button, _overlay_menu_button, _overlay_settings_button, _collect_back_button, _collect_settings_button]:
		button.disabled = input_locked
	_playing_root.visible = _mode == MODE_PLAYING
	_overlay_root.visible = _mode in [MODE_PAUSED, MODE_GAME_OVER, MODE_LEVEL_COMPLETE]
	_scrim.visible = _overlay_root.visible
	_card.visible = _overlay_root.visible
	_card_viewport.visible = _overlay_root.visible
	_resume_button.visible = _mode == MODE_PAUSED
	_next_level_button.visible = _mode == MODE_LEVEL_COMPLETE
	_overlay_restart_button.visible = _overlay_root.visible
	_overlay_menu_button.visible = _overlay_root.visible
	_configure_overlay_actions()
	_new_record_label.visible = _mode in [MODE_GAME_OVER, MODE_LEVEL_COMPLETE]
	_overlay_objective_badge.visible = _mode == MODE_LEVEL_COMPLETE
	_overlay_objective_badge.queue_redraw()
	_title_label.visible = not _is_adventure()
	_goal_label.visible = _is_adventure() and not _is_collect_objective()
	_mode_label.visible = not _is_collect_objective()
	_detail_label.visible = not _is_collect_objective()
	_playing_buttons.visible = not _is_collect_objective()
	_collect_navigation.visible = _is_collect_objective()
	# Adventure digits are drawn on the same canvas as their circular caps.
	_stats_label.visible = not _is_adventure()
	_goal_score_label.visible = false
	_stats_label.add_theme_color_override("font_color", Color("#efffff") if _is_adventure() else AQUA)
	_layout_controls()
	if _focus_pending:
		if _mode == MODE_HIDDEN:
			for button: Button in [_settings_button, _pause_button, _playing_restart_button, _playing_menu_button, _resume_button, _overlay_restart_button, _overlay_menu_button, _next_level_button, _overlay_settings_button, _collect_back_button, _collect_settings_button]:
				button.release_focus()
		else:
			_grab_first_focus()
		_focus_pending = false
	if mode_changed and _overlay_root.visible:
		_animate_overlay_entrance()
		if _mode == MODE_LEVEL_COMPLETE and _is_collect_objective():
			_start_victory_animation()
	queue_redraw()

func _configure_overlay_actions() -> void:
	var collect_victory := _is_collect_objective() and _mode == MODE_LEVEL_COMPLETE
	var target_parent: Node = _overlay_secondary_buttons if collect_victory else _overlay_buttons
	for button: Button in [_overlay_restart_button, _overlay_menu_button]:
		if button.get_parent() != target_parent:
			button.reparent(target_parent)
	_overlay_settings_button.visible = _is_collect_objective() and _mode == MODE_PAUSED
	_overlay_secondary_buttons.visible = collect_victory or _overlay_settings_button.visible
	_overlay_score.visible = not collect_victory
	_style_button(_next_level_button, Color("#36cf23"), Color.WHITE)
	_style_button(_overlay_restart_button, Color("#294775") if collect_victory else GOLD, _text if collect_victory else Color("#213759"))
	for button: Button in [_overlay_restart_button, _overlay_menu_button]:
		button.custom_minimum_size.y = 40.0 if collect_victory else MIN_BUTTON_HEIGHT
		button.add_theme_font_size_override("font_size", 15 if collect_victory else 17)
	if collect_victory:
		var clear_panel := StyleBoxEmpty.new()
		clear_panel.set_content_margin_all(20.0)
		_card.add_theme_stylebox_override("panel", clear_panel)
		_overlay_title.add_theme_font_size_override("font_size", 46)
		_overlay_title.add_theme_color_override("font_color", Color("#ddffff"))
		_overlay_title.add_theme_color_override("font_outline_color", Color("#154577"))
		_overlay_title.add_theme_constant_override("outline_size", 5)
		_overlay_title.add_theme_color_override("font_shadow_color", Color(0.01, 0.08, 0.23, 0.72))
		_overlay_title.add_theme_constant_override("shadow_offset_y", 4)
		_overlay_box.move_child(_overlay_title, 0)
		_overlay_box.move_child(_overlay_objective_badge, 1)
	else:
		_card.add_theme_stylebox_override("panel", _card_box())
		_overlay_title.add_theme_font_size_override("font_size", 24)
		_overlay_title.add_theme_color_override("font_color", _text)
		_overlay_title.add_theme_constant_override("outline_size", 0)
		_overlay_title.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		_overlay_title.add_theme_constant_override("shadow_offset_y", 0)
		_overlay_box.move_child(_overlay_objective_badge, 0)
		_overlay_box.move_child(_overlay_title, 1)

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
	_overlay_title.text = ("Well Done!" if collect else "目标完成") if _mode == MODE_LEVEL_COMPLETE else ("已暂停" if _mode == MODE_PAUSED else ("第 %d 关未通过" % level_id if adventure else "游戏结束"))
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
		_overlay_stats.text = "全部目标已完成\n消除 %d 行/列  ·  完成 %d 回合" % [total_cleared, round_index + 1]
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

func _start_victory_animation() -> void:
	_stop_victory_animation()
	if bool(_stats.get("reduced_motion", false)):
		return
	_victory_progress = 0.0
	_victory_ambient_time = 0.0
	_victory_ambient_running = true
	_victory_button_ready = false
	_set_victory_action_visible(false)
	_overlay_title.modulate.a = 0.0
	_overlay_title.scale = Vector2.ONE * 0.55
	_overlay_title.rotation = deg_to_rad(-4.0)
	var random := RandomNumberGenerator.new()
	random.seed = Time.get_ticks_usec()
	var colors := [GOLD, AQUA, Color("#fb5f7a"), Color("#a67cf1"), Color("#8fed4d")]
	for index in range(VICTORY_CONFETTI_COUNT):
		var direction := -1.0 if index % 2 == 0 else 1.0
		_victory_particles.append({
			# Relative to the live hero group, so scroll/resize cannot detach it.
			"origin": Vector2(direction * random.randf_range(0.34, 0.44), random.randf_range(-0.08, 0.10)),
			"velocity": Vector2(direction * random.randf_range(75.0, 195.0), random.randf_range(-230.0, -115.0)),
			"color": colors[index % colors.size()],
			"side": random.randf_range(4.0, 8.5),
			"angle": random.randf_range(-PI, PI),
			"delay": random.randf_range(0.0, 0.12),
		})
	_victory_tween = create_tween()
	_victory_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_victory_tween.tween_method(_set_victory_progress, 0.0, 1.0, VICTORY_SEQUENCE_DURATION)
	_victory_tween.tween_callback(func() -> void:
		_victory_tween = null
		_victory_particles.clear()
		_set_victory_action_visible(true)
		_victory_confetti.queue_redraw())
	# The hidden primary action must never retain invisible keyboard focus.
	if not _overlay_restart_button.has_focus() and not _overlay_menu_button.has_focus():
		_overlay_restart_button.grab_focus()
		_ensure_overlay_focus_visible.call_deferred(_overlay_restart_button)
	_set_victory_progress(0.0)

func _set_victory_progress(progress: float) -> void:
	_victory_progress = progress
	var elapsed := _victory_time()
	var title_reveal := clampf((elapsed - VICTORY_TITLE_START) / 0.30, 0.0, 1.0)
	_overlay_title.pivot_offset = _overlay_title.size * 0.5
	_overlay_title.scale = Vector2.ONE * _victory_pop(title_reveal, 1.10)
	_overlay_title.modulate.a = minf(title_reveal * 3.0, 1.0)
	_overlay_title.rotation = deg_to_rad(-4.0) * (1.0 - title_reveal)
	var action_reveal := clampf((elapsed - VICTORY_ACTION_START) / 0.28, 0.0, 1.0)
	if action_reveal > 0.0:
		_set_victory_action_visible(action_reveal >= 0.15)
		_next_level_button.pivot_offset = _next_level_button.size * 0.5
		_next_level_button.scale = Vector2.ONE * _victory_pop(action_reveal, 1.08)
		_next_level_button.modulate.a = minf(action_reveal * 3.0, 1.0)
	_overlay_objective_badge.queue_redraw()
	_victory_confetti.queue_redraw()

func _set_victory_action_visible(ready: bool) -> void:
	_victory_button_ready = ready
	if not is_instance_valid(_next_level_button):
		return
	_next_level_button.modulate = Color.WHITE if ready else Color(1.0, 1.0, 1.0, 0.0)
	_next_level_button.scale = Vector2.ONE
	_next_level_button.mouse_filter = Control.MOUSE_FILTER_STOP if ready else Control.MOUSE_FILTER_IGNORE
	_next_level_button.focus_mode = Control.FOCUS_ALL if ready else Control.FOCUS_NONE
	if not ready:
		_next_level_button.release_focus()
	elif _mode == MODE_LEVEL_COMPLETE and _is_collect_objective() and _next_level_button.is_visible_in_tree() and not _next_level_button.disabled and is_inside_tree() and get_viewport() != null and not is_instance_valid(get_viewport().gui_get_focus_owner()):
		# Do not steal a secondary action the player has already selected.
		_next_level_button.grab_focus()

func _stop_victory_animation() -> void:
	if is_instance_valid(_victory_tween):
		_victory_tween.kill()
	_victory_tween = null
	_victory_progress = 1.0
	_victory_ambient_running = false
	_victory_ambient_time = 0.0
	_victory_particles.clear()
	_set_victory_action_visible(true)
	if is_instance_valid(_overlay_title):
		_overlay_title.scale = Vector2.ONE
		_overlay_title.modulate = Color.WHITE
		_overlay_title.rotation = 0.0
	if is_instance_valid(_overlay_objective_badge):
		_overlay_objective_badge.queue_redraw()
	if is_instance_valid(_victory_confetti):
		_victory_confetti.queue_redraw()

func _draw_victory_confetti() -> void:
	if _mode != MODE_LEVEL_COMPLETE or not _is_collect_objective():
		return
	var elapsed := _victory_time()
	var anchor := _overlay_objective_badge.global_position - _victory_confetti.global_position + _overlay_objective_badge.size * Vector2(0.5, 0.49)
	var viewport_rect := Rect2(_card_viewport.global_position - _victory_confetti.global_position, _card_viewport.size)
	var group_size := _overlay_objective_badge.size
	var intensity_scale := clampf(group_size.x / 330.0, 0.55, 1.30)
	for particle: Dictionary in _victory_particles:
		var lifetime := elapsed - 0.42 - float(particle["delay"])
		if lifetime < 0.0:
			continue
		var relative_origin: Vector2 = particle["origin"]
		var origin := anchor + relative_origin * group_size
		var velocity: Vector2 = particle["velocity"]
		var point := origin + (velocity * lifetime + Vector2(0.0, lifetime * lifetime * 120.0)) * intensity_scale
		if not viewport_rect.grow(-8.0).has_point(point):
			continue
		var color: Color = particle["color"]
		color.a = 1.0 - clampf((lifetime - 1.60) / 0.70, 0.0, 1.0)
		var angle := float(particle["angle"]) + lifetime * 5.0
		var side := float(particle["side"]) * intensity_scale
		var vertices := PackedVector2Array()
		for corner in [Vector2(-0.5, -1.0), Vector2(0.5, -1.0), Vector2(0.5, 1.0), Vector2(-0.5, 1.0)]:
			vertices.append(point + corner.rotated(angle) * side)
		_victory_confetti.draw_colored_polygon(vertices, color)
	_draw_victory_action_sheen(viewport_rect)

func _draw_victory_action_sheen(viewport_rect: Rect2) -> void:
	if bool(_stats.get("reduced_motion", false)) or not _victory_button_ready:
		return
	var progress := (_victory_time() - VICTORY_SHEEN_START) / 0.64
	if progress < 0.0 or progress > 1.0:
		return
	var global_rect := _next_level_button.get_global_rect()
	var rect := Rect2(global_rect.position - _victory_confetti.global_position, global_rect.size).grow(-4.0)
	var clipped := rect.intersection(viewport_rect)
	if not clipped.has_area():
		return
	var middle := lerpf(rect.position.x - rect.size.x * 0.30, rect.end.x + rect.size.x * 0.30, progress)
	var half_width := rect.size.x * 0.12
	for row in range(0, int(rect.size.y), 2):
		var y := rect.position.y + float(row)
		if y < clipped.position.y or y > clipped.end.y:
			continue
		var skew := (float(row) / maxf(rect.size.y, 1.0) - 0.5) * rect.size.y * 0.65
		for layer in range(3, 0, -1):
			var width := half_width * float(layer) / 3.0
			var left := maxf(clipped.position.x, middle + skew - width)
			var right := minf(clipped.end.x, middle + skew + width)
			if right > left:
				_victory_confetti.draw_line(Vector2(left, y), Vector2(right, y), Color(1.0, 1.0, 0.85, 0.065), 2.0)

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
	if _is_collect_objective():
		_layout_collect_hud(stage_left, stage_width)
	_layout_overlay()
	_layout_notice()
	_layout_objective_intro()
	_progress_banner.set_playfield(field, size)
	queue_redraw()

func _layout_collect_hud(stage_left: float, stage_width: float) -> void:
	_collect_navigation.position = Vector2.ZERO
	_collect_navigation.size = Vector2(size.x, header_height())
	var navigation_side := 48.0
	_collect_back_button.position = Vector2(stage_left, 12.0)
	_collect_back_button.size = Vector2.ONE * navigation_side
	_collect_settings_button.position = Vector2(stage_left + stage_width - navigation_side, 12.0)
	_collect_settings_button.size = Vector2.ONE * navigation_side
	var kinds := _active_target_kinds(_stats)
	var target_side := clampf(stage_width * 0.075, 32.0, 52.0)
	var spacing := minf(92.0, stage_width * 0.22)
	var target_y := header_height() - target_side - 28.0
	_objective_rects.clear()
	for index in range(kinds.size()):
		var center_x := stage_left + stage_width * 0.5 + (float(index) - float(kinds.size() - 1) * 0.5) * spacing
		_objective_rects[kinds[index]] = Rect2(center_x - target_side * 0.5, target_y, target_side, target_side)

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
	var collect_victory := _is_collect_objective() and _mode == MODE_LEVEL_COMPLETE
	_overlay_objective_badge.custom_minimum_size = Vector2(minf(VICTORY_HERO_SIZE.x, maxf(size.x - 80.0, 96.0)) if collect_victory else (192.0 if _is_collect_objective() else 56.0), VICTORY_HERO_SIZE.y if collect_victory else 56.0)
	_overlay_title.custom_minimum_size = Vector2(0.0, 64.0 if collect_victory else 32.0)
	if collect_victory:
		_overlay_title.add_theme_font_size_override("font_size", 32 if size.x < 420.0 else 46)
	_overlay_title.pivot_offset = _overlay_title.size * 0.5
	_overlay_score.custom_minimum_size = Vector2(0.0, 78.0)
	_overlay_best.custom_minimum_size = Vector2(0.0, 20.0 if collect_victory else 28.0)
	_overlay_best.add_theme_font_size_override("font_size", 14 if collect_victory else 18)
	_overlay_best.add_theme_color_override("font_color", MUTED if collect_victory else GOLD)
	_overlay_stats.custom_minimum_size = Vector2(0.0, 32.0 if collect_victory else 66.0)
	_overlay_stats.add_theme_font_size_override("font_size", 12 if collect_victory else 16)
	var save_warning := collect_victory and bool(_stats.get("save_failed", false))
	_new_record_label.custom_minimum_size = Vector2(0.0, (48.0 if size.x < 420.0 else 26.0) if save_warning else (22.0 if collect_victory else 24.0))
	_new_record_label.add_theme_font_size_override("font_size", 16 if save_warning else (14 if collect_victory else 18))
	_new_record_label.add_theme_color_override("font_color", Color("#ffc586") if save_warning else (MUTED if collect_victory else GOLD))
	_new_record_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if save_warning else TextServer.AUTOWRAP_OFF
	_new_record_label.max_lines_visible = 2 if save_warning else 1
	_overlay_buttons.custom_minimum_size = Vector2(0.0, MIN_BUTTON_HEIGHT)
	_overlay_secondary_buttons.custom_minimum_size = Vector2(0.0, 40.0 if collect_victory else MIN_BUTTON_HEIGHT)
	var card_width := minf(VICTORY_CARD_WIDTH if collect_victory else (540.0 if _mode == MODE_LEVEL_COMPLETE else 480.0), maxf(size.x - 32.0, 240.0))
	var card_height := (438.0 if _is_collect_objective() else 376.0) if _mode == MODE_PAUSED else (VICTORY_CARD_HEIGHT if collect_victory else (492.0 if _mode == MODE_LEVEL_COMPLETE else 428.0))
	var short_labels := card_width < 420.0
	_resume_button.text = "继续" if short_labels else "继续游戏"
	_next_level_button.text = "下一关" if bool(_stats.get("has_next_level", false)) else "全部通关"
	_next_level_button.tooltip_text = "开始下一关" if bool(_stats.get("has_next_level", false)) else "已通过所有关卡"
	_overlay_restart_button.text = ("重玩" if short_labels else "重玩本关") if _is_adventure() else ("重开" if short_labels else "重新开始")
	_overlay_menu_button.text = ("选关" if short_labels else "返回选关") if _is_adventure() else ("菜单" if short_labels else "返回菜单")
	_overlay_restart_button.tooltip_text = "重玩本关" if _is_adventure() else "重新开始"
	_overlay_menu_button.tooltip_text = "返回选关" if _is_adventure() else "返回菜单"
	var viewport_height := minf(card_height, maxf(size.y - 24.0, 1.0))
	_card_viewport.size = Vector2(card_width, viewport_height)
	_card_viewport.position = Vector2((size.x - card_width) * 0.5, maxf((size.y - viewport_height) * 0.5, 12.0))
	_card.custom_minimum_size = Vector2(0.0, card_height)
	_card_viewport.queue_sort()
	_card.pivot_offset = _card.size * 0.5
	# PanelContainer owns Content and its margins; do not preset child anchors.

func _grab_first_focus() -> void:
	if not _configured or _mode == MODE_HIDDEN or _focus_mode == _mode:
		return
	var first: Button
	if _mode == MODE_PLAYING:
		first = _collect_settings_button if _is_collect_objective() else _pause_button
	elif _mode == MODE_PAUSED:
		first = _resume_button
	elif _mode == MODE_LEVEL_COMPLETE:
		first = _overlay_restart_button if _is_collect_objective() and not _victory_button_ready else (_overlay_menu_button if _next_level_button.disabled else _next_level_button)
	else:
		first = _overlay_restart_button
	if is_instance_valid(first) and not first.disabled and first.visible:
		_focus_mode = _mode
		first.grab_focus()
		_ensure_overlay_focus_visible.call_deferred(first)

func _ensure_overlay_focus_visible(button: Button) -> void:
	if is_instance_valid(button) and button.has_focus() and is_instance_valid(_card_viewport) and _overlay_root.visible and button.is_inside_tree() and _card.is_ancestor_of(button):
		_card_viewport.ensure_control_visible(button)

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
	if _mode == MODE_LEVEL_COMPLETE and not _next_level_button.disabled and (not _is_collect_objective() or _victory_button_ready):
		next_level_requested.emit()
