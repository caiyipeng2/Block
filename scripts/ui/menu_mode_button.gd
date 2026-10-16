extends Button

## Sculpted menu face; the native Button owns focus, shortcuts and activation.
const Art := preload("res://scripts/ui/block_art.gd")

@export var mode_kind: String = "adventure":
	set(value):
		mode_kind = value
		queue_redraw()
@export var title_text: String = "闯关模式":
	set(value):
		title_text = value
		text = value
		queue_redraw()
@export var subtitle_text: String = "逐关点亮方块地图":
	set(value):
		subtitle_text = value
		queue_redraw()
@export var face_color: Color = Color("#ffb525"):
	set(value):
		face_color = value
		queue_redraw()

var _title_font := SystemFont.new()
var _subtitle_font := SystemFont.new()
var entrance_preview := false:
	set(value):
		entrance_preview = value
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = custom_minimum_size.max(Vector2(200.0, 60.0))
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = title_text
	_title_font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI", "Noto Sans CJK SC"])
	_title_font.font_weight = 750
	_subtitle_font.font_names = _title_font.font_names
	_subtitle_font.font_weight = 500
	_apply_native_theme()
	for redraw_signal in [mouse_entered, mouse_exited, focus_entered, focus_exited, button_down, button_up, resized]:
		redraw_signal.connect(queue_redraw)
	queue_redraw()


func set_reduced_motion(_enabled: bool) -> void:
	# Hover and press use their native immediate state, with no looping motion.
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var scale_factor := clampf(size.y / 72.0, 0.72, 1.35)
	var radius := clampf(12.0 * scale_factor, 10.0, 14.0)
	var edge := 2.0
	var pressed_now := is_pressed() and not disabled
	var hovered_now := is_hovered() and not disabled
	var face_offset := clampf(1.5 * scale_factor, 1.0, 2.0) if pressed_now else 0.0
	var face := Rect2(Vector2(edge, edge + face_offset), Vector2(size.x - edge * 2.0, size.y - edge * 2.0 - face_offset))
	var base := face_color
	var opacity := 0.61 if disabled and not entrance_preview else 1.0
	if hovered_now and not pressed_now:
		base = base.lightened(0.07)
	if pressed_now:
		base = base.darkened(0.035)
	base.a *= opacity

	# The curved rim belongs to the face itself; there is no extruded base.
	# Closely spaced, same-hue layers soften every edge, including the corners.
	_draw_rounded_gradient(face, base, radius, opacity, 1.0)
	_draw_rounded_gradient(face.grow(-0.8 * scale_factor), base, radius - 0.8 * scale_factor, opacity, 0.52)
	_draw_rounded_gradient(face.grow(-1.8 * scale_factor), base, radius - 1.8 * scale_factor, opacity, 0.0)
	_draw_box(face, Color.TRANSPARENT, radius, _alpha(base.lightened(0.15), 0.44), 1)
	_draw_top_rim(face.grow(-1.3 * scale_factor), radius - 1.3 * scale_factor, opacity)

	var badge_side := minf(face.size.y - 12.0 * scale_factor, 48.0 * scale_factor)
	var badge := Rect2(Vector2(face.position.x + 13.0 * scale_factor, face.get_center().y - badge_side * 0.5), Vector2.ONE * badge_side)
	var badge_color := base.lightened(0.065)
	_draw_box(badge, badge_color, 11.0 * scale_factor, Color(1.0, 1.0, 1.0, 0.20 * opacity), 1)
	_draw_mode_icon(badge.grow(-5.5 * scale_factor), opacity, badge_color)
	_draw_copy(face, badge, scale_factor, opacity)

	var arrow_center := Vector2(face.end.x - 19.0 * scale_factor, face.get_center().y)
	var arrow_size := 4.2 * scale_factor
	draw_polyline(PackedVector2Array([arrow_center + Vector2(-arrow_size * 0.5, -arrow_size), arrow_center + Vector2(arrow_size * 0.5, 0.0), arrow_center + Vector2(-arrow_size * 0.5, arrow_size)]), Color(1.0, 1.0, 1.0, 0.85 * opacity), 2.4 * scale_factor, true)

	# Keyboard focus never changes the face tint or simulates being pressed.
	if has_focus() and not disabled:
		_draw_box(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), Color.TRANSPARENT, radius + 1.0, Color("#b9fff6"), 2)


func _draw_copy(face: Rect2, badge: Rect2, scale_factor: float, opacity: float) -> void:
	var left := badge.end.x + 14.0 * scale_factor
	var available := maxf(face.end.x - 40.0 * scale_factor - left, 1.0)
	var title_size := clampi(roundi(24.0 * scale_factor), 18, 30)
	while title_size > 12 and _title_font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size).x > available:
		title_size -= 1
	var subtitle_size := clampi(roundi(13.0 * scale_factor), 11, 16)
	var subtitle_width := _subtitle_font.get_string_size(subtitle_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, subtitle_size).x
	var with_subtitle := not subtitle_text.is_empty() and subtitle_width <= available and face.size.y >= 46.0
	var title_height := _title_font.get_height(title_size)
	var subtitle_height := _subtitle_font.get_height(subtitle_size) if with_subtitle else 0.0
	var line_gap := 1.5 * scale_factor if with_subtitle else 0.0
	var top := face.get_center().y - (title_height + subtitle_height + line_gap) * 0.5
	var title_position := Vector2(left, top + _title_font.get_ascent(title_size))
	draw_string_outline(_title_font, title_position + Vector2(0.0, 1.3 * scale_factor), title_text, HORIZONTAL_ALIGNMENT_LEFT, available, title_size, 2, Color(0.10, 0.12, 0.27, 0.19 * opacity))
	draw_string(_title_font, title_position, title_text, HORIZONTAL_ALIGNMENT_LEFT, available, title_size, Color(1.0, 1.0, 1.0, opacity))
	if with_subtitle:
		var subtitle_position := Vector2(left, top + title_height + line_gap + _subtitle_font.get_ascent(subtitle_size))
		draw_string(_subtitle_font, subtitle_position, subtitle_text, HORIZONTAL_ALIGNMENT_LEFT, available, subtitle_size, Color(1.0, 1.0, 1.0, 0.91 * opacity))


func _draw_mode_icon(rect: Rect2, opacity: float, badge_color: Color) -> void:
	var white := Color(1.0, 1.0, 1.0, opacity)
	var side := minf(rect.size.x, rect.size.y)
	var center := rect.get_center()
	match mode_kind:
		"classic":
			var points := PackedVector2Array()
			for step in range(65):
				var angle := TAU * float(step) / 64.0
				points.append(center + Vector2(sin(angle) * 0.43, sin(angle * 2.0) * 0.23) * side)
			draw_polyline(points, white, maxf(side * 0.105, 2.5), true)
		"free":
			var unit := side * 0.43
			var origin := center - Vector2.ONE * unit
			Art.draw_block(self, Rect2(origin + Vector2(unit * 0.52, 0.0), Vector2.ONE * unit), Color("#d9ffff"), opacity)
			Art.draw_block(self, Rect2(origin + Vector2(0.0, unit * 1.02), Vector2.ONE * unit), Color("#59e6ec"), opacity)
			Art.draw_block(self, Rect2(origin + Vector2(unit * 1.04, unit * 1.02), Vector2.ONE * unit), Color("#ffffff"), opacity)
		_:
			# Keep the pin and its ground arc inside the same padded icon bounds,
			# including the stroke width at the smallest menu button size.
			var pin_center := center + Vector2(0.0, -side * 0.16)
			var radius := side * 0.235
			draw_colored_polygon(PackedVector2Array([pin_center + Vector2(-radius * 0.86, radius * 0.43), pin_center + Vector2(radius * 0.86, radius * 0.43), center + Vector2(0.0, side * 0.24)]), white)
			draw_circle(pin_center, radius, white)
			draw_circle(pin_center, side * 0.085, badge_color)
			draw_arc(center + Vector2(0.0, side * 0.25), side * 0.19, PI * 0.10, PI * 0.90, 18, Color(1.0, 1.0, 1.0, 0.75 * opacity), maxf(side * 0.042, 1.2), true)


func _apply_native_theme() -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color", "font_outline_color", "font_shadow_color"]:
		add_theme_color_override(color_name, Color.TRANSPARENT)
	add_theme_font_override("font", _title_font)
	add_theme_font_size_override("font_size", 18)
	add_theme_constant_override("outline_size", 0)


func _draw_rounded_gradient(rect: Rect2, base: Color, radius: float, opacity: float, rim_weight: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var corner := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var strips := maxi(ceili(rect.size.y / 1.4), 1)
	for strip in range(strips):
		var top := rect.size.y * float(strip) / float(strips)
		var bottom := rect.size.y * float(strip + 1) / float(strips)
		var top_inset := _round_edge_inset(top, rect.size.y, corner)
		var bottom_inset := _round_edge_inset(bottom, rect.size.y, corner)
		var top_color := _face_gradient_color(base, top / rect.size.y, rim_weight, opacity)
		var bottom_color := _face_gradient_color(base, bottom / rect.size.y, rim_weight, opacity)
		draw_polygon(PackedVector2Array([
			rect.position + Vector2(top_inset, top),
			rect.position + Vector2(rect.size.x - top_inset, top),
			rect.position + Vector2(rect.size.x - bottom_inset, bottom),
			rect.position + Vector2(bottom_inset, bottom),
		]), PackedColorArray([top_color, top_color, bottom_color, bottom_color]))


func _round_edge_inset(y: float, height: float, radius: float) -> float:
	var corner_y := maxf(radius - minf(y, height - y), 0.0)
	return radius - sqrt(maxf(radius * radius - corner_y * corner_y, 0.0))


func _face_gradient_color(base: Color, progress: float, rim_weight: float, opacity: float) -> Color:
	# A continuous sheen fades through the face rather than ending in a band.
	var color: Color
	if progress < 0.09:
		color = base.lightened(lerpf(0.30 + rim_weight * 0.24, 0.18 + rim_weight * 0.06, progress / 0.09))
	elif progress < 0.40:
		color = base.lightened(lerpf(0.18 + rim_weight * 0.06, 0.035, (progress - 0.09) / 0.31))
	elif progress < 0.70:
		color = base.lightened(lerpf(0.035, 0.0, (progress - 0.40) / 0.30))
	elif progress < 0.91:
		color = base.darkened(lerpf(0.0, 0.025, (progress - 0.70) / 0.21))
	else:
		color = base.darkened(lerpf(0.025, 0.07 + rim_weight * 0.16, (progress - 0.91) / 0.09))
	color.a = opacity
	return color


func _draw_top_rim(rect: Rect2, radius: float, opacity: float) -> void:
	var points := PackedVector2Array()
	var left_center := rect.position + Vector2.ONE * radius
	var right_center := Vector2(rect.end.x - radius, rect.position.y + radius)
	for step in range(13):
		var angle := lerpf(PI, PI * 1.5, float(step) / 12.0)
		points.append(left_center + Vector2.from_angle(angle) * radius)
	for step in range(13):
		var angle := lerpf(PI * 1.5, TAU, float(step) / 12.0)
		points.append(right_center + Vector2.from_angle(angle) * radius)
	draw_polyline(points, Color(1.0, 1.0, 1.0, 0.22 * opacity), 1.1, true)
	# A small corner glint makes the glossy surface readable at menu scale.
	draw_arc(left_center, radius - 0.8, PI * 1.12, PI * 1.37, 12, Color(1.0, 1.0, 1.0, 0.47 * opacity), 1.5, true)


func _draw_box(rect: Rect2, fill: Color, radius: float, border: Color = Color.TRANSPARENT, border_width: int = 0) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(roundi(radius))
	box.anti_aliasing = true
	draw_style_box(box, rect)


func _alpha(color: Color, opacity: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * opacity)
