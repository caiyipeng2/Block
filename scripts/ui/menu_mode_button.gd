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
	var radius := 12.0 * scale_factor
	var edge := 2.0
	var depth := clampf(size.y * 0.085, 4.0, 7.0)
	var pressed_now := is_pressed() and not disabled
	var hovered_now := is_hovered() and not disabled
	var face_offset := depth * 0.63 if pressed_now else (-1.0 if hovered_now else 0.0)
	var face := Rect2(Vector2(edge, edge + face_offset), Vector2(size.x - edge * 2.0, size.y - depth - edge * 2.0))
	var base := face_color
	var opacity := 0.61 if disabled and not entrance_preview else 1.0
	if hovered_now and not pressed_now:
		base = base.lightened(0.07)
	if pressed_now:
		base = base.darkened(0.035)
	base.a *= opacity

	# Soft contact shadow and a separate dark slab give the face real depth.
	var shadow := Rect2(Vector2(edge + 1.0, depth + edge + 3.0), face.size)
	_draw_box(shadow.grow(2.0), Color(0.02, 0.07, 0.18, 0.10 * opacity), radius + 2.0)
	_draw_box(shadow, Color(0.02, 0.07, 0.18, 0.25 * opacity), radius)
	var lower_face := Rect2(Vector2(edge, edge + depth), face.size)
	_draw_box(lower_face, _alpha(face_color.darkened(0.42), opacity), radius, _alpha(face_color.darkened(0.54), opacity), 1)
	_draw_box(face, base, radius, _alpha(base.lightened(0.39), opacity * 0.84), 1)

	# Broad top sheen is kept away from the edges and text for a clean bevel.
	var sheen := Rect2(face.position + Vector2(2.0, 2.0), Vector2(face.size.x - 4.0, face.size.y * 0.34))
	_draw_box(sheen, Color(1.0, 1.0, 1.0, 0.12 * opacity), maxf(radius - 2.0, 1.0))
	var rim := face.grow(-3.0)
	_draw_box(rim, Color.TRANSPARENT, maxf(radius - 3.0, 1.0), Color(1.0, 1.0, 1.0, 0.11 * opacity), 1)
	draw_line(face.position + Vector2(radius, 2.5), Vector2(face.end.x - radius, face.position.y + 2.5), Color(1.0, 1.0, 1.0, 0.36 * opacity), 1.2, true)

	var badge_side := minf(face.size.y - 12.0 * scale_factor, 48.0 * scale_factor)
	var badge := Rect2(Vector2(face.position.x + 13.0 * scale_factor, face.get_center().y - badge_side * 0.5), Vector2.ONE * badge_side)
	var badge_color := base.darkened(0.12)
	_draw_box(badge, badge_color, 11.0 * scale_factor, Color(1.0, 1.0, 1.0, 0.23 * opacity), 1)
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
			var pin_center := center + Vector2(0.0, -side * 0.13)
			var radius := side * 0.255
			draw_colored_polygon(PackedVector2Array([pin_center + Vector2(-radius * 0.86, radius * 0.43), pin_center + Vector2(radius * 0.86, radius * 0.43), center + Vector2(0.0, side * 0.37)]), white)
			draw_circle(pin_center, radius, white)
			draw_circle(pin_center, side * 0.095, badge_color)
			draw_arc(center + Vector2(0.0, side * 0.39), side * 0.32, PI * 0.10, PI * 0.90, 18, Color(1.0, 1.0, 1.0, 0.75 * opacity), maxf(side * 0.045, 1.3), true)


func _apply_native_theme() -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color", "font_outline_color", "font_shadow_color"]:
		add_theme_color_override(color_name, Color.TRANSPARENT)
	add_theme_font_override("font", _title_font)
	add_theme_font_size_override("font_size", 18)
	add_theme_constant_override("outline_size", 0)


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
