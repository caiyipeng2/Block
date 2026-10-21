extends Button

## The approved artwork owns the face; Button owns focus and activation.
## Keep the original image intact and clip its blue surroundings at draw time.
const BUTTON_ART: Texture2D = preload("res://assets/ui/menu/approved_mode_buttons.png")
const L10n := preload("res://scripts/localization/game_locale.gd")
const LOCALIZED_FACE := preload("res://scripts/ui/menu_mode_button.gdshader")
const FACE_REGIONS := {
	"adventure": Rect2(210.0, 246.0, 877.0, 213.0),
	"classic": Rect2(210.0, 532.0, 877.0, 213.0),
	"free": Rect2(210.0, 813.0, 877.0, 209.0),
}
const CORNER_RATIO := 30.0 / 213.0
const CORNER_STEPS := 12

@export var mode_kind: String = "adventure":
	set(value):
		mode_kind = value
		queue_redraw()
@export var title_text: String = "闯关模式":
	set(value):
		title_text = value
		if is_node_ready():
			_refresh_localized_title()
# Retained for the menu's presentation API; the selected artwork has one line.
@export var subtitle_text: String = ""
@export var face_color: Color = Color("#ffb525")
var _localized_title: Label

var entrance_preview := false:
	set(value):
		entrance_preview = value
		if is_node_ready():
			_refresh_localized_title()


func _ready() -> void:
	custom_minimum_size = custom_minimum_size.max(Vector2(176.0, 44.0))
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# The semantic text remains available to the native Button even though its
	# visible lettering, icon and material are baked together in the approved art.
	_apply_native_theme()
	_localized_title = Label.new()
	_localized_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_localized_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_localized_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_localized_title.clip_text = true
	_localized_title.use_parent_material = false
	var latin_font := SystemFont.new()
	latin_font.font_names = PackedStringArray(["Arial", "Segoe UI", "sans-serif"])
	latin_font.font_weight = 900
	latin_font.font_italic = true
	_localized_title.add_theme_font_override("font", latin_font)
	_localized_title.add_theme_color_override("font_color", Color.WHITE)
	_localized_title.add_theme_color_override("font_shadow_color", Color(0.18, 0.08, 0.10, 0.35))
	_localized_title.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_localized_title)
	for redraw_signal in [mouse_entered, mouse_exited, focus_entered, focus_exited, button_down, button_up, resized]:
		redraw_signal.connect(_refresh_localized_title)
	_refresh_localized_title()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_localized_title()


func _refresh_localized_title() -> void:
	text = L10n.t(title_text)
	if not is_instance_valid(_localized_title):
		return
	var translated := L10n.language() != "zh_CN"
	_localized_title.visible = translated
	if translated:
		if material == null:
			var face_material := ShaderMaterial.new()
			face_material.shader = LOCALIZED_FACE
			material = face_material
		_localized_title.text = text
		_localized_title.position = Vector2(size.x * 0.355, size.y * 0.04)
		_localized_title.size = Vector2(size.x * 0.535, size.y * 0.90)
		var font := _localized_title.get_theme_font("font")
		_localized_title.add_theme_font_size_override("font_size", L10n.fitted_size(font, text, _localized_title.size.x - 6.0, maxi(12, roundi(size.y * 0.49)), 10))
	else:
		material = null
	queue_redraw()


func set_reduced_motion(_enabled: bool) -> void:
	# Feedback is immediate and has no looping or interpolated motion.
	queue_redraw()


func get_face_source_region() -> Rect2:
	return FACE_REGIONS.get(mode_kind, FACE_REGIONS["adventure"])


func _draw() -> void:
	if size.x <= 4.0 or size.y <= 4.0:
		return
	var face := Rect2(Vector2.ZERO, size)
	var radius := face.size.y * CORNER_RATIO
	var scale_factor := clampf(face.size.y / 84.0, 0.50, 1.50)
	var pressed_now := is_pressed() and not disabled
	var hovered_now := is_hovered() and not disabled
	var opacity := 0.61 if disabled and not entrance_preview else 1.0
	if is_instance_valid(_localized_title) and _localized_title.visible:
		_localized_title.position.y = size.y * 0.04 + (2.0 * scale_factor if pressed_now else 0.0)
		_localized_title.modulate.a = opacity
	_draw_shadow(face, radius, scale_factor, opacity, pressed_now)
	if pressed_now:
		# Translate the whole artwork without squeezing its icons or lettering.
		face.position.y += 2.0 * scale_factor
	var brightness := 1.035 if hovered_now and not pressed_now else 1.0
	_draw_art_face(face, radius, Color(brightness, brightness, brightness, opacity))

	# Native focus and activation remain available without a visible focus outline.


func _draw_art_face(rect: Rect2, radius: float, tint: Color) -> void:
	var vertices := _rounded_outline(rect, radius)
	var uvs := PackedVector2Array()
	var region := get_face_source_region()
	var texture_size := BUTTON_ART.get_size()
	# Half a texel avoids sampling the adjacent blue background along straight
	# edges. The convex outline clips that background away at the round corners.
	var sample_region := region.grow(-0.5)
	for vertex in vertices:
		var relative := (vertex - rect.position) / rect.size
		uvs.append((sample_region.position + relative * sample_region.size) / texture_size)
	draw_polygon(vertices, PackedColorArray([tint]), uvs, BUTTON_ART)


func _rounded_outline(rect: Rect2, radius: float) -> PackedVector2Array:
	var corner := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var centers := PackedVector2Array([
		rect.position + Vector2.ONE * corner,
		Vector2(rect.end.x - corner, rect.position.y + corner),
		rect.end - Vector2.ONE * corner,
		Vector2(rect.position.x + corner, rect.end.y - corner),
	])
	var points := PackedVector2Array()
	for index in range(4):
		var start_angle := PI + float(index) * PI * 0.5
		for step in range(CORNER_STEPS + 1):
			var angle := start_angle + PI * 0.5 * float(step) / float(CORNER_STEPS)
			points.append(centers[index] + Vector2.from_angle(angle) * corner)
	return points


func _draw_shadow(face: Rect2, radius: float, scale_factor: float, opacity: float, pressed_now: bool) -> void:
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0.02, 0.05, 0.14, 0.13 * opacity)
	shadow.set_corner_radius_all(roundi(radius))
	shadow.shadow_color = Color(0.01, 0.04, 0.12, 0.12 * opacity)
	shadow.shadow_size = maxi(roundi(4.0 * scale_factor), 1)
	shadow.shadow_offset = Vector2(0.0, 2.0 * scale_factor)
	shadow.anti_aliasing = true
	var offset := 2.0 if pressed_now else 4.0
	draw_style_box(shadow, Rect2(face.position + Vector2(0.0, offset * scale_factor), face.size))


func _apply_native_theme() -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color", "font_outline_color", "font_shadow_color"]:
		add_theme_color_override(color_name, Color.TRANSPARENT)
	add_theme_font_size_override("font_size", 18)
	add_theme_constant_override("outline_size", 0)
