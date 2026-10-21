extends Control

## Presentation only: the owner supplies map geometry and updates real tiles.
signal frame_changed(elapsed: float)
signal finished

const BlockArt = preload("res://scripts/ui/block_art.gd")
const L10n := preload("res://scripts/localization/game_locale.gd")
const LAND_TIME := 1.55
const UNLOCK_TIME := 1.67
const DURATION := 2.20
const FLIGHT_TIME := 1.00

var _completed_level := 0
var _next_level := 0
var _completed_rect := Rect2()
var _next_rect := Rect2()
var _map_viewport := Rect2()
var _elapsed := 0.0
var _playing := false
var _epoch := 0
var _tween: Tween
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	visible = false
	var display_font := SystemFont.new()
	display_font.font_names = PackedStringArray(["Microsoft YaHei", "Arial", "sans-serif"])
	display_font.font_weight = 700
	_font = display_font

func _exit_tree() -> void:
	cancel()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		queue_redraw()

func play(completed_level: int, next_level: int, completed_rect: Rect2, next_rect: Rect2, map_viewport: Rect2) -> void:
	cancel()
	if not is_inside_tree() or completed_rect.size.x <= 0.0 or map_viewport.size.y <= 0.0:
		return
	_completed_level = completed_level
	_next_level = next_level
	_completed_rect = completed_rect
	_next_rect = next_rect
	_map_viewport = map_viewport
	_playing = true
	visible = true
	var current_epoch := _epoch
	# Listeners can safely cancel even the first frame, before a Tween exists.
	_advance(0.0, current_epoch)
	if not _playing or current_epoch != _epoch:
		return
	_tween = create_tween()
	_tween.tween_method(_advance.bind(current_epoch), 0.0, DURATION, DURATION)
	_tween.tween_callback(_finish.bind(current_epoch))

func cancel() -> void:
	_epoch += 1
	if is_instance_valid(_tween):
		_tween.kill()
	_tween = null
	_playing = false
	_elapsed = 0.0
	visible = false
	queue_redraw()

func is_playing() -> bool:
	return _playing

func _advance(elapsed: float, epoch: int) -> void:
	if not _playing or epoch != _epoch:
		return
	_elapsed = elapsed
	frame_changed.emit(_elapsed)
	queue_redraw()

func _finish(epoch: int) -> void:
	if not _playing or epoch != _epoch:
		return
	_tween = null
	_playing = false
	visible = false
	queue_redraw()
	finished.emit()

func _draw() -> void:
	if not _playing:
		return
	var band_alpha := smoothstep(0.0, 0.16, _elapsed) * (1.0 - smoothstep(0.90, 1.10, _elapsed))
	if band_alpha > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.045, 0.12, band_alpha * 0.52))
		_draw_banner(band_alpha)
	_draw_flying_block()
	if _elapsed >= LAND_TIME:
		_draw_landing()
	if _next_level > _completed_level and _next_rect.size.x > 0.0 and _elapsed >= UNLOCK_TIME:
		_draw_unlock()

func _band_rect() -> Rect2:
	var width_scale := minf(size.x / 480.0, 1.0)
	var height := minf(clampf(_map_viewport.size.y * 0.31, 112.0, 132.0) * width_scale, _map_viewport.size.y * 0.68)
	return Rect2(Vector2(0.0, _map_viewport.get_center().y - height * 0.5), Vector2(size.x, height))

func _block_start() -> Vector2:
	var band := _band_rect()
	return band.get_center() + Vector2(0.0, band.size.y * 0.075)

func _block_side() -> float:
	return minf(clampf(size.x * 0.075, 44.0, 54.0), _band_rect().size.y * 0.40)

func _draw_banner(alpha: float) -> void:
	var band := _band_rect()
	var top_left := band.position
	var top_right := Vector2(band.end.x, band.position.y)
	var bottom_left := Vector2(band.position.x, band.end.y)
	draw_rect(Rect2(band.position + Vector2(0.0, 5.0), band.size), Color(0.02, 0.04, 0.12, alpha * 0.36))
	draw_polygon(PackedVector2Array([top_left, top_right, band.end, bottom_left]), PackedColorArray([
		Color(0.34, 0.49, 0.84, alpha), Color(0.32, 0.47, 0.81, alpha),
		Color(0.20, 0.34, 0.66, alpha), Color(0.22, 0.37, 0.71, alpha)
	]))
	draw_line(top_left, top_right, Color(0.66, 0.84, 1.0, alpha * 0.84), 1.4, true)
	draw_line(bottom_left, band.end, Color(0.12, 0.24, 0.52, alpha), 2.0, true)
	var title_size := int(clampf(band.size.y * 0.215, 12.0, 29.0))
	var subtitle_size := int(clampf(band.size.y * 0.118, 9.0, 16.0))
	_draw_centered(L10n.t("第 %d 关完成") % _completed_level, band.get_center() + Vector2(0.0, -band.size.y * 0.31), title_size, Color(0.97, 0.99, 1.0, alpha))
	var subtitle := L10n.t("解锁第 %d 关") % _next_level if _next_level > _completed_level else L10n.t("全部关卡已完成")
	_draw_centered(subtitle, band.get_center() + Vector2(0.0, band.size.y * 0.39), subtitle_size, Color(0.80, 0.93, 1.0, alpha))

func _draw_centered(message: String, center: Vector2, font_size: int, color: Color) -> void:
	if _font == null:
		return
	while font_size > 8 and _font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > size.x - 24.0:
		font_size -= 1
	var text_size := _font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var baseline := center + Vector2(-text_size.x * 0.5, (_font.get_ascent(font_size) - _font.get_descent(font_size)) * 0.5)
	draw_string_outline(_font, baseline + Vector2(0.0, 1.0), message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 3, Color(0.10, 0.20, 0.43, color.a * 0.70))
	draw_string(_font, baseline, message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _flight_position(progress: float) -> Vector2:
	var start := _block_start()
	var end := _completed_rect.get_center()
	var curve_height := minf(100.0, _map_viewport.size.y * 0.20)
	var side := -1.0 if end.x < start.x else 1.0
	var control_a := start + Vector2(side * curve_height * 0.55, -curve_height)
	var control_b := end + Vector2(-side * curve_height * 0.18, -curve_height * 0.70)
	var inverse := 1.0 - progress
	return inverse * inverse * inverse * start + 3.0 * inverse * inverse * progress * control_a + 3.0 * inverse * progress * progress * control_b + progress * progress * progress * end

func _draw_flying_block() -> void:
	if _elapsed >= LAND_TIME:
		return
	var start_side := _block_side()
	if _elapsed < FLIGHT_TIME:
		var entrance := clampf((_elapsed - 0.11) / 0.24, 0.0, 1.0)
		var overshoot := 1.0 + 2.70158 * pow(entrance - 1.0, 3.0) + 1.70158 * pow(entrance - 1.0, 2.0)
		var side := start_side * maxf(overshoot, 0.0)
		var center := _block_start()
		_draw_glow(center, start_side * 0.83, entrance * 0.18)
		BlockArt.draw_block(self, Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side), Color("#30cde4"), entrance)
		return
	var progress := clampf((_elapsed - FLIGHT_TIME) / (LAND_TIME - FLIGHT_TIME), 0.0, 1.0)
	var motion := smoothstep(0.0, 1.0, progress)
	var end_side := minf(_completed_rect.size.x, _completed_rect.size.y)
	for index in range(4, 0, -1):
		var trail_progress := maxf(motion - float(index) * 0.045, 0.0)
		var trail_center := _flight_position(trail_progress)
		var trail_side := lerpf(start_side, end_side, trail_progress)
		BlockArt.draw_block(self, Rect2(trail_center - Vector2.ONE * trail_side * 0.5, Vector2.ONE * trail_side), Color("#67eeef"), (1.0 - float(index) / 5.0) * 0.16 * sin(progress * PI))
	var center := _flight_position(motion)
	var side := lerpf(start_side, end_side, motion)
	_draw_glow(center, side * 0.83, 0.14)
	BlockArt.draw_block(self, Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side), Color("#30cde4"))

func _draw_glow(center: Vector2, radius: float, alpha: float) -> void:
	for ring in range(4, 0, -1):
		draw_circle(center, radius * float(ring) / 4.0, Color(0.38, 0.95, 1.0, alpha * 0.35))

func _draw_landing() -> void:
	var progress := clampf((_elapsed - LAND_TIME) / 0.44, 0.0, 1.0)
	var alpha := sin(progress * PI) * (1.0 - progress)
	var side := minf(_completed_rect.size.x, _completed_rect.size.y)
	var center := _completed_rect.get_center()
	draw_arc(center, side * lerpf(0.45, 1.12, progress), 0.0, TAU, 48, Color(0.55, 1.0, 1.0, alpha * 0.9), 2.0, true)
	_draw_glow(center, side * 1.1, alpha * 0.24)
	_draw_star_ring(center, side, progress, alpha, Color("#bdffff"), 7)

func _draw_unlock() -> void:
	var progress := clampf((_elapsed - UNLOCK_TIME) / (DURATION - UNLOCK_TIME), 0.0, 1.0)
	var alpha := smoothstep(0.0, 0.16, progress) * (1.0 - smoothstep(0.55, 1.0, progress))
	var side := minf(_next_rect.size.x, _next_rect.size.y)
	var center := _next_rect.get_center()
	for index in range(10):
		var angle := float(index) * TAU / 10.0 + progress * 0.20
		var direction := Vector2.from_angle(angle)
		draw_line(center + direction * side * (0.58 + progress * 0.25), center + direction * side * (0.84 + progress * 0.65), Color(1.0, 0.86, 0.35, alpha * 0.72), 1.5, true)
	draw_arc(center, side * (0.57 + progress * 0.62), 0.0, TAU, 48, Color(1.0, 0.91, 0.48, alpha * 0.8), 1.5, true)
	_draw_star_ring(center, side, progress, alpha, Color("#ffeb8a"), 8)

func _draw_star_ring(center: Vector2, side: float, progress: float, alpha: float, color: Color, count: int) -> void:
	for index in range(count):
		var angle := float(index) * TAU / float(count) - PI * 0.5
		var point := center + Vector2.from_angle(angle) * side * lerpf(0.55, 1.26, progress)
		var star_side := side * (0.11 if index % 2 == 0 else 0.07)
		BlockArt.draw_icon(self, "spark", Rect2(point - Vector2.ONE * star_side * 0.5, Vector2.ONE * star_side), Color(color, alpha))
