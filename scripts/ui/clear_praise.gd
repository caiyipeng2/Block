extends Control

## Clear praise is independent of board busy/collection completion. Tier rules
## and timings live here so tuning presentation cannot alter scoring or combo.
const LINE_THRESHOLDS := [2, 3, 4]
const COMBO_THRESHOLDS := [4, 7, 10]
const TITLES := ["Combo", "Perfect!", "Excellent!", "Unbelievable!"]
const DURATION := 0.96
const ENDLESS_DURATION := 1.14
const GOLD := Color("#ffe56d")
const AQUA := Color("#b2ffff")
const PURPLE := Color("#cc8fff")
const OUTLINE := Color("#172b75")
const L10n := preload("res://scripts/localization/game_locale.gd")

var _tween: Tween
var _paused := false
var _active := false
var _tier := 0
var _progress := 0.0
var _cell_size := 1.0
var _content: Control
var _content_size := Vector2.ZERO
var _anchor := Vector2.ZERO
var _board_offset := Vector2.ZERO
var _base_scale := 1.0
var _pop_scale := 1.0
var _alpha := 1.0
var _endless_feedback := false
var _single_clear := false
var _display_combo := 0
var _display_lines := 0
var _display_board := Rect2()
var _word: Label
var _number: Label
var _caption: Label
var _detail: Label

static func tier_for(line_count: int, combo: int) -> int:
	var tier := 0
	for index in range(LINE_THRESHOLDS.size()):
		if line_count >= int(LINE_THRESHOLDS[index]) or combo >= int(COMBO_THRESHOLDS[index]):
			tier = index + 1
	return tier

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		# Preserve the current animation time and real clear/combo snapshot.
		_refresh_content_text()

func play(combo: int, line_count: int, clear_anchor: Vector2, board_rect: Rect2,
		cell_size: float, surviving_targets: Array[Vector2], delay: float = 0.0, force_combo: bool = false,
		endless_feedback: bool = false) -> void:
	var next_tier := tier_for(line_count, combo)
	var light_single := line_count == 1 and combo < 2
	if line_count < 1 or (next_tier == 0 and combo < 2 and not force_combo and not light_single):
		return
	reset()
	_tier = next_tier
	_endless_feedback = endless_feedback
	_single_clear = light_single and not force_combo
	_display_combo = combo
	_display_lines = line_count
	_display_board = board_rect
	_cell_size = maxf(cell_size, 1.0)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	var font_size := clampi(int(board_rect.size.x * (0.118 if _tier > 0 else 0.105)), 26, 76 if _tier > 0 else 58)
	if _single_clear:
		font_size = clampi(int(board_rect.size.x * 0.086), 24, 48)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Microsoft YaHei", "sans-serif"])
	font.font_weight = 900
	font.font_italic = true
	var word_color := AQUA if _tier in [0, 2] else (GOLD if _tier == 1 else Color("#f1d5ff"))
	_word = _new_label("", font_size, word_color, 9 if _tier > 0 else 7, font)
	if combo >= 2:
		# This is the real consecutive-clear count, never the number of lines.
		_number = _new_label(str(combo), int(font_size * (1.44 if endless_feedback else 1.32)), GOLD, 10, font)
		if _tier > 0:
			_caption = _new_label("", clampi(int(font_size * 0.25), 12, 17), AQUA, 3, font)
	if line_count >= 2 or endless_feedback or _single_clear:
		_detail = _new_label("", clampi(int(font_size * 0.34), 14, 23), Color("#d6f8ff"), 3, font)
	_refresh_content_text()
	_anchor = _choose_anchor(clear_anchor, board_rect, surviving_targets)
	_content.hide()
	_tween = create_tween()
	if delay > 0.0:
		_tween.tween_interval(delay)
	_tween.tween_callback(_show)
	var duration := (1.04 if _single_clear else ENDLESS_DURATION + float(_tier) * 0.02) if endless_feedback else DURATION
	_tween.tween_method(_update_progress, 0.0, 1.0, duration)
	_tween.tween_callback(_end)
	_apply_pause()

func _refresh_content_text() -> void:
	if not is_instance_valid(_content) or not is_instance_valid(_word):
		return
	_word.text = L10n.t("Nice!" if _single_clear else str(TITLES[_tier]))
	_word.position = Vector2.ZERO
	var word_size := _word.get_minimum_size()
	_content_size = word_size
	var caption_y := word_size.y
	if is_instance_valid(_number):
		_number.text = str(_display_combo)
		var number_size := _number.get_minimum_size()
		var gap := maxf(4.0, float(_word.get_theme_font_size("font_size")) * 0.06)
		_number.position = Vector2(word_size.x + gap, 0.0)
		_word.position.y = maxf(0.0, number_size.y - word_size.y) * 0.68
		_content_size = Vector2(word_size.x + gap + number_size.x, maxf(word_size.y, number_size.y))
		caption_y = _content_size.y - 3.0
		if is_instance_valid(_caption):
			_caption.text = L10n.t("COMBO")
			var caption_size := _caption.get_minimum_size()
			_caption.position = Vector2(_number.position.x + (number_size.x - caption_size.x) * 0.5, caption_y)
	if is_instance_valid(_detail):
		_detail.text = L10n.t("%d Line" if _display_lines == 1 else "%d Lines") % _display_lines
		var detail_size := _detail.get_minimum_size()
		_detail.position = Vector2((word_size.x - detail_size.x) * 0.5, caption_y)
	var left := 0.0
	for child: Label in _content.get_children():
		child.size = child.get_minimum_size()
		left = minf(left, child.position.x)
		_content_size = _content_size.max(child.position + child.size)
	_content_size.x -= left
	for child: Label in _content.get_children():
		child.position.x -= left
	_content.size = _content_size
	_content.pivot_offset = _content_size * 0.5
	_base_scale = minf(1.0, maxf(_display_board.size.x - 34.0, 1.0) / maxf(_content_size.x * 1.28, 1.0))
	_position_content()
	queue_redraw()

func get_reserved_rect() -> Rect2:
	if not is_instance_valid(_content):
		return Rect2()
	# Include the largest pop, slight tilt, outline and shadow so score text
	# can start above the words while the praise itself remains independent.
	var half := _content_size * _base_scale * 0.64
	if _endless_feedback:
		# Reserve the visible early star burst too, including the 1.27 peak.
		# Late distant stars are nearly transparent by the time scores fly.
		var star_extent := Vector2(_content_size.x * 0.28 + _cell_size * (1.5 if _single_clear else 2.1), _cell_size * (0.9 if _single_clear else 1.3)) * _base_scale * 1.27
		half.x = maxf(half.x, star_extent.x)
		half.y = maxf(half.y, star_extent.y)
	var tilt := deg_to_rad(3.0)
	var extent := Vector2(half.x * cos(tilt) + half.y * sin(tilt), half.x * sin(tilt) + half.y * cos(tilt)) + Vector2(14.0, 18.0)
	return Rect2(_anchor + _board_offset - extent, extent * 2.0)

func _new_label(text: String, font_size: int, color: Color, outline_size: int, font: Font) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_shadow_color", Color("#102049"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 5)
	_content.add_child(label)
	return label

func _choose_anchor(clear_anchor: Vector2, board_rect: Rect2, targets: Array[Vector2]) -> Vector2:
	var half := _content_size * _base_scale * 0.5 + Vector2(10.0, 12.0)
	var desired := clear_anchor + Vector2(0.0, _cell_size * 0.88)
	var candidates: Array[Vector2] = [
		desired,
		Vector2(desired.x, board_rect.end.y - half.y - 5.0),
		desired + Vector2(-_cell_size * 1.3, _cell_size * 0.65),
		desired + Vector2(_cell_size * 1.3, _cell_size * 0.65),
		clear_anchor - Vector2(0.0, _cell_size * 1.2),
	]
	var best := board_rect.get_center()
	var best_cost := INF
	for candidate in candidates:
		candidate.x = clampf(candidate.x, board_rect.position.x + half.x, maxf(board_rect.position.x + half.x, board_rect.end.x - half.x))
		candidate.y = clampf(candidate.y, board_rect.position.y + half.y + 8.0, maxf(board_rect.position.y + half.y + 8.0, board_rect.end.y - half.y))
		var rect := Rect2(candidate - half, half * 2.0).grow(_cell_size * 0.15)
		var cost := candidate.distance_squared_to(desired)
		for target in targets:
			if rect.has_point(target):
				cost += 1000000.0
		if cost < best_cost:
			best_cost = cost
			best = candidate
	return best

func set_paused(paused: bool) -> void:
	_paused = paused
	_apply_pause()

func set_board_offset(offset: Vector2) -> void:
	_board_offset = offset
	_position_content()
	queue_redraw()

func reset() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if is_instance_valid(_content):
		_content.hide()
		_content.queue_free()
	_content = null
	_word = null
	_number = null
	_caption = null
	_detail = null
	_active = false
	_progress = 0.0
	_endless_feedback = false
	_single_clear = false
	_board_offset = Vector2.ZERO
	queue_redraw()

func _show() -> void:
	_active = true
	if is_instance_valid(_content):
		_content.show()
	_update_progress(0.0)

func _end() -> void:
	_tween = null
	reset()

func _apply_pause() -> void:
	if _tween != null:
		if _paused:
			_tween.pause()
		else:
			_tween.play()

func _update_progress(value: float) -> void:
	_progress = value
	var entrance := clampf(value / 0.19, 0.0, 1.0)
	_pop_scale = 0.46 + 0.54 * sin(entrance * PI * 0.5) + (0.28 if _tier > 0 else 0.08) * sin(entrance * PI)
	_alpha = 1.0 - clampf((value - 0.73) / 0.27, 0.0, 1.0)
	if _endless_feedback:
		var peak := 1.10 if _single_clear else minf(1.18 + float(_tier) * 0.03, 1.27)
		if entrance < 0.62:
			_pop_scale = lerpf(0.56, peak, sin(entrance / 0.62 * PI * 0.5))
		else:
			var settle := (entrance - 0.62) / 0.38
			_pop_scale = lerpf(peak, 1.0, 1.0 - pow(1.0 - settle, 2.0))
		_alpha = 1.0 - clampf((value - 0.78) / 0.22, 0.0, 1.0)
	_position_content()
	queue_redraw()

func _position_content() -> void:
	if is_instance_valid(_content):
		_content.position = _anchor + _board_offset - _content_size * 0.5
		_content.scale = Vector2.ONE * _base_scale * _pop_scale
		_content.rotation = deg_to_rad(-3.0) * (1.0 - _progress * 0.45)
		_content.modulate.a = _alpha

func _draw() -> void:
	if not _active:
		return
	if _endless_feedback:
		_draw_endless_praise()
		return
	if _tier == 0 and not _single_clear:
		return
	var angle := deg_to_rad(-3.0) * (1.0 - _progress * 0.45)
	draw_set_transform(_anchor + _board_offset, angle, Vector2.ONE * _base_scale * _pop_scale)
	var half := _content_size * Vector2(0.56, 0.39)
	var left := -half.x - _cell_size * 0.30
	var right := half.x + _cell_size * 0.30
	var band_alpha := _alpha * 0.42
	# A translucent color ribbon supports the type without hiding the board.
	draw_polygon(PackedVector2Array([
		Vector2(left, -half.y), Vector2(0.0, -half.y - 5.0), Vector2(right, -half.y),
		Vector2(right - 8.0, half.y), Vector2(0.0, half.y + 5.0), Vector2(left + 8.0, half.y)
	]), PackedColorArray([
		Color(GOLD.r, GOLD.g, GOLD.b, 0.0), Color(AQUA.r, AQUA.g, AQUA.b, band_alpha * 0.64), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.0),
		Color(PURPLE.r, PURPLE.g, PURPLE.b, band_alpha * 0.28), Color(PURPLE.r, PURPLE.g, PURPLE.b, band_alpha), Color(GOLD.r, GOLD.g, GOLD.b, band_alpha * 0.28)
	]))
	var burst := 1.0 - clampf(_progress / 0.48, 0.0, 1.0)
	for ray in range(6 + _tier * 2):
		var ray_angle := float(ray) * 2.399963
		var direction := Vector2(cos(ray_angle), sin(ray_angle) * 0.55)
		var tip := direction * _cell_size * (1.2 + _progress * 2.0 + float(_tier) * 0.18)
		var wing := Vector2(-direction.y, direction.x) * _cell_size * 0.10
		draw_polygon(PackedVector2Array([Vector2.ZERO, tip + wing, tip - wing]), PackedColorArray([
			Color(1.0, 0.95, 0.77, burst * 0.28), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.0), Color(AQUA.r, AQUA.g, AQUA.b, 0.0)
		]))
	var star_fade := pow(1.0 - _progress, 1.3)
	for index in range(8 + _tier * 5):
		var star_angle := float(index) * 2.399963 + 0.35
		var spread := Vector2(cos(star_angle), sin(star_angle) * 0.60)
		var point := spread * _cell_size * (0.75 + _progress * 2.2 + float(index % 3) * 0.25)
		var radius := _cell_size * (0.045 + float(index % 3) * 0.015) * (1.0 - _progress * 0.55)
		var tint := GOLD if index % 3 == 0 else (AQUA if index % 3 == 1 else PURPLE)
		var points := PackedVector2Array()
		for corner in range(8):
			var r := radius if corner % 2 == 0 else radius * 0.28
			points.append(point + Vector2.from_angle(float(corner) * PI * 0.25 + star_angle + _progress) * r)
		draw_colored_polygon(points, Color(tint.r, tint.g, tint.b, star_fade * 0.90))
	draw_set_transform(Vector2.ZERO)

func _draw_endless_praise() -> void:
	var angle := deg_to_rad(-3.0) * (1.0 - _progress * 0.45)
	draw_set_transform(_anchor + _board_offset, angle, Vector2.ONE * _base_scale * _pop_scale)
	# Keep the words open over the board: a soft halo and sparse gold/aqua
	# stars give feedback without an opaque ribbon or another tile material.
	var strength := 0.58 if _single_clear else 1.0 + float(_tier) * 0.18
	var halo_radius := minf(_content_size.x * 0.46, _cell_size * 2.0)
	for layer in range(3):
		var halo := Color(AQUA.r, AQUA.g, AQUA.b, _alpha * strength * 0.025 / float(layer + 1))
		draw_circle(Vector2.ZERO, halo_radius + float(layer) * _cell_size * 0.15, halo)
	var star_fade := pow(1.0 - _progress, 1.35)
	var count := 4 if _single_clear else 8 + _tier * 3
	for index in range(count):
		var star_angle := float(index) * 2.399963 + 0.35
		var direction := Vector2(cos(star_angle), sin(star_angle) * 0.58)
		var distance := _cell_size * (0.9 + _progress * (1.2 if _single_clear else 1.9))
		var point := direction * distance + Vector2(signf(direction.x) * _content_size.x * 0.28, 0.0)
		var radius := _cell_size * (0.040 + float(index % 3) * 0.012) * (1.0 - _progress * 0.55)
		var tint := GOLD if index % 2 == 0 else AQUA
		var points := PackedVector2Array()
		for corner in range(8):
			var r := radius if corner % 2 == 0 else radius * 0.26
			points.append(point + Vector2.from_angle(float(corner) * PI * 0.25 + star_angle) * r)
		draw_colored_polygon(points, Color(tint.r, tint.g, tint.b, star_fade * 0.82))
	draw_set_transform(Vector2.ZERO)
