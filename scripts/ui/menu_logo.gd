extends Control

## Original vector title art. The menu owns entrance, position and opacity;
## this control only redraws when its bounds or the requested glint change.

const ART_SIZE := Vector2(400.0, 188.0)
const TITLE_COLORS: Array[Color] = [
	Color("#ffb632"), Color("#45c8ff"), Color("#ff6264"),
	Color("#ffdc3e"), Color("#cd66f4")
]
const TITLE_TILTS: Array[float] = [-0.075, 0.035, -0.035, 0.045, 0.075]
const TITLE_LIFTS: Array[float] = [1.0, -3.0, 0.0, -2.0, 2.0]

var _display_font: SystemFont
var _glint_progress: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_display_font = SystemFont.new()
	_display_font.font_names = PackedStringArray(["Arial Black", "Segoe UI Black", "Trebuchet MS"])
	_display_font.font_weight = 900
	resized.connect(queue_redraw)


func set_glint(progress: float) -> void:
	_glint_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var fit := minf(size.x / ART_SIZE.x, size.y / ART_SIZE.y)
	var origin := (size - ART_SIZE * fit) * 0.5
	_draw_crown(origin, fit)
	_draw_top_word(origin, fit)
	_draw_bottom_word(origin, fit)
	_draw_glint(origin, fit)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_top_word(origin: Vector2, fit: float) -> void:
	var word := "BLOCK"
	var font_size := 78
	var widths: Array[float] = []
	var total_width := 0.0
	for index in range(word.length()):
		var letter_width := _display_font.get_string_size(word.substr(index, 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		widths.append(letter_width)
		total_width += letter_width
	# Leave breathing room for tilted edges and the extrusion at either end.
	var word_fit := minf(1.0, 348.0 / maxf(total_width, 1.0))
	var cursor := (ART_SIZE.x - total_width * word_fit) * 0.5 - 3.0
	for index in range(word.length()):
		var letter_width := widths[index]
		var anchor := Vector2(cursor + letter_width * word_fit * 0.5, 106.0 + TITLE_LIFTS[index])
		_draw_letter(word.substr(index, 1), anchor, letter_width, font_size,
			TITLE_COLORS[index], TITLE_TILTS[index], origin, fit, word_fit, 6)
		cursor += letter_width * word_fit


func _draw_bottom_word(origin: Vector2, fit: float) -> void:
	var word := "BLAST"
	var font_size := 56
	var letter_spacing := 1.8
	var widths: Array[float] = []
	var total_width := letter_spacing * float(word.length() - 1)
	for index in range(word.length()):
		var letter_width := _display_font.get_string_size(word.substr(index, 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		widths.append(letter_width)
		total_width += letter_width
	var word_fit := minf(1.0, 251.0 / maxf(total_width, 1.0))
	var cursor := (ART_SIZE.x - total_width * word_fit) * 0.5 - 2.0
	for index in range(word.length()):
		var letter_width := widths[index]
		var color := Color("#30edee").lerp(Color("#36bffc"), float(index) / 6.0)
		_draw_letter(word.substr(index, 1), Vector2(cursor + letter_width * word_fit * 0.5, 164.0),
			letter_width, font_size, color, -0.025, origin, fit, word_fit, 5)
		cursor += (letter_width + letter_spacing) * word_fit


func _draw_letter(letter: String, anchor: Vector2, letter_width: float, font_size: int,
		color: Color, tilt: float, origin: Vector2, fit: float, word_fit: float, depth: int) -> void:
	draw_set_transform(origin + anchor * fit, tilt, Vector2.ONE * fit * word_fit)
	var baseline := Vector2(-letter_width * 0.5, 0.0)
	# A broad navy silhouette plus several solid side layers gives each glyph
	# depth without a texture or a blurred halo obscuring the letter edges.
	draw_string_outline(_display_font, baseline + Vector2(4.0, float(depth) + 3.0), letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, Color(0.015, 0.07, 0.22, 0.32))
	for layer in range(depth, 0, -1):
		var side_color := Color("#153e83").lerp(color.darkened(0.48), 1.0 - float(layer) / float(depth + 1))
		var shift := Vector2(float(layer) * 0.62, float(layer))
		draw_string_outline(_display_font, baseline + shift, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 2, Color("#16487f"))
		draw_string(_display_font, baseline + shift, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, side_color)
	draw_string_outline(_display_font, baseline, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 2, color.darkened(0.25))
	draw_string(_display_font, baseline + Vector2(-0.4, -1.2), letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color.lightened(0.48))
	draw_string(_display_font, baseline, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_crown(origin: Vector2, fit: float) -> void:
	draw_set_transform(origin + Vector2(203.0, 12.0) * fit, -0.10, Vector2.ONE * fit)
	var crown := PackedVector2Array([
		Vector2(-26.0, 4.0), Vector2(-13.0, 17.0), Vector2(0.0, -5.0),
		Vector2(13.0, 17.0), Vector2(26.0, 4.0), Vector2(20.0, 34.0), Vector2(-20.0, 34.0)
	])
	var shadow := PackedVector2Array()
	for vertex in crown:
		shadow.append(vertex + Vector2(1.5, 3.5))
	draw_colored_polygon(shadow, Color("#865308"))
	draw_polygon(crown, PackedColorArray([
		Color("#ffec83"), Color("#ffcb39"), Color("#fff2a4"),
		Color("#ffcb39"), Color("#ffe475"), Color("#f7a512"), Color("#ffc530")
	]))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-23.0, 8.0), Vector2(-18.0, 29.0), Vector2(-3.0, 29.0), Vector2(0.0, 0.0),
		Vector2(-13.0, 19.0)
	]), Color(1.0, 0.96, 0.65, 0.25))
	draw_line(Vector2(-19.0, 29.0), Vector2(19.0, 29.0), Color("#fff2a0"), 2.0, true)
	draw_line(Vector2(-19.0, 34.0), Vector2(19.0, 34.0), Color("#e9900c"), 3.0, true)
	for bead in [Vector2(-26.0, 3.0), Vector2(0.0, -6.0), Vector2(26.0, 3.0)]:
		draw_circle(bead + Vector2(0.7, 1.4), 4.4, Color("#b57410"))
		draw_circle(bead, 4.2, Color("#ffdc4c"))
		draw_circle(bead + Vector2(-1.0, -1.1), 1.7, Color("#fff5b0"))


func _draw_glint(origin: Vector2, fit: float) -> void:
	if _glint_progress <= 0.0 or _glint_progress >= 1.0:
		return
	draw_set_transform(origin, 0.0, Vector2.ONE * fit)
	var strength := sin(_glint_progress * PI)
	var path := Vector2(lerpf(52.0, 350.0, _glint_progress), lerpf(91.0, 44.0, _glint_progress))
	_draw_spark(path, 10.0 * strength, strength)
	_draw_spark(Vector2(226.0, 12.0), 6.0 * strength, strength * 0.82)
	_draw_spark(Vector2(310.0, 138.0), 5.5 * strength, strength * 0.64)


func _draw_spark(center: Vector2, radius: float, opacity: float) -> void:
	if radius <= 0.0:
		return
	draw_circle(center, radius * 1.45, Color(0.68, 0.98, 1.0, opacity * 0.055))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius * 0.20, -radius * 0.20),
		center + Vector2(radius, 0.0), center + Vector2(radius * 0.20, radius * 0.20),
		center + Vector2(0.0, radius), center + Vector2(-radius * 0.20, radius * 0.20),
		center + Vector2(-radius, 0.0), center + Vector2(-radius * 0.20, -radius * 0.20)
	]), Color(1.0, 1.0, 0.90, opacity))
