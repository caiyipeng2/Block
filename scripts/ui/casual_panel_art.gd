extends RefCounted

## Shared native materials for settings and confirmation cards.
## A broad face and a solid lower rim provide depth without glossy highlights.

static func panel_style(unit: float = 1.0) -> StyleBoxFlat:
	var style := _rounded(Color("#557ee4"), 20.0 * unit)
	style.border_color = Color("#79a0f5")
	style.set_border_width_all(maxi(roundi(unit * 1.5), 1))
	style.border_width_bottom = maxi(roundi(unit * 5.0), 2)
	style.shadow_color = Color(0.025, 0.045, 0.12, 0.38)
	style.shadow_size = roundi(8.0 * unit)
	style.shadow_offset = Vector2(0.0, 6.0 * unit)
	style.set_content_margin_all(16.0 * unit)
	return style


static func inner_style(unit: float = 1.0) -> StyleBoxFlat:
	var style := _rounded(Color("#35449b"), 13.0 * unit)
	style.border_color = Color("#4559b4")
	style.set_border_width_all(maxi(roundi(unit), 1))
	style.set_content_margin_all(14.0 * unit)
	return style


static func style_action(button: Button, unit: float = 1.0, tone: String = "green") -> void:
	var face := Color("#2aa924")
	var edge := Color("#208c1d")
	if tone == "secondary":
		face = Color("#657ac2")
		edge = Color("#405695")
	elif tone == "danger":
		face = Color("#e16659")
		edge = Color("#a74342")
	button.add_theme_stylebox_override("normal", _action_style(face, edge, unit))
	button.add_theme_stylebox_override("hover", _action_style(face, edge.lightened(0.10), unit))
	button.add_theme_stylebox_override("pressed", _action_style(face.darkened(0.06), edge, unit, true))
	button.add_theme_stylebox_override("disabled", _action_style(Color("#7883a9"), Color("#59678e"), unit, true))
	var focus := _rounded(Color.TRANSPARENT, 12.0 * unit)
	focus.border_color = Color("#c9fff4")
	focus.set_border_width_all(maxi(roundi(2.0 * unit), 2))
	focus.expand_margin_left = 2.0 * unit
	focus.expand_margin_top = 2.0 * unit
	focus.expand_margin_right = 2.0 * unit
	focus.expand_margin_bottom = 2.0 * unit
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_font_size_override("font_size", maxi(roundi(21.0 * unit), 16))
	for role in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(role, Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("#e4e9f8"))
	button.add_theme_color_override("font_shadow_color", Color(0.06, 0.14, 0.12, 0.26))
	button.add_theme_constant_override("shadow_offset_y", maxi(roundi(unit), 1))
	button.add_theme_constant_override("outline_size", 0)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func _action_style(face: Color, edge: Color, unit: float, pressed: bool = false) -> StyleBoxFlat:
	var style := _rounded(face, 11.0 * unit)
	style.border_color = edge
	style.border_width_left = maxi(roundi(unit), 1)
	style.border_width_right = maxi(roundi(unit), 1)
	style.border_width_bottom = maxi(roundi((2.0 if pressed else 5.0) * unit), 1)
	style.shadow_color = Color(0.035, 0.07, 0.14, 0.22)
	style.shadow_size = maxi(roundi(2.0 * unit), 1)
	style.shadow_offset = Vector2(0.0, (1.0 if pressed else 3.0) * unit)
	style.content_margin_left = 16.0 * unit
	style.content_margin_right = 16.0 * unit
	style.content_margin_top = 7.0 * unit
	style.content_margin_bottom = 9.0 * unit
	return style


static func _rounded(fill: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(maxi(roundi(radius), 1))
	style.corner_detail = 12
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.0
	return style


static func draw_icon(canvas: CanvasItem, kind: String, rect: Rect2, color: Color = Color.WHITE) -> void:
	var side := minf(rect.size.x, rect.size.y)
	if side <= 2.0 or color.a <= 0.0:
		return
	var origin := rect.get_center() - Vector2.ONE * side * 0.5
	var weight := maxf(side * 0.085, 1.4)
	var center := origin + Vector2.ONE * side * 0.5
	match kind:
		"sound", "preview":
			_fill(canvas, origin, side, [Vector2(0.10, 0.34), Vector2(0.29, 0.34), Vector2(0.55, 0.14), Vector2(0.55, 0.86), Vector2(0.29, 0.66), Vector2(0.10, 0.66)], color)
			canvas.draw_arc(origin + Vector2(0.50, 0.50) * side, side * 0.25, -0.95, 0.95, 24, color, weight, true)
			canvas.draw_arc(origin + Vector2(0.50, 0.50) * side, side * 0.39, -0.89, 0.89, 28, color, weight * 0.72, true)
		"music":
			canvas.draw_line(origin + Vector2(0.36, 0.73) * side, origin + Vector2(0.36, 0.25) * side, color, weight, true)
			canvas.draw_line(origin + Vector2(0.77, 0.62) * side, origin + Vector2(0.77, 0.14) * side, color, weight, true)
			_fill(canvas, origin, side, [Vector2(0.32, 0.24), Vector2(0.81, 0.11), Vector2(0.81, 0.31), Vector2(0.32, 0.44)], color)
			canvas.draw_circle(origin + Vector2(0.25, 0.75) * side, side * 0.13, color, true, -1.0, true)
			canvas.draw_circle(origin + Vector2(0.66, 0.64) * side, side * 0.13, color, true, -1.0, true)
		"shake":
			var monitor := _rounded(Color.TRANSPARENT, side * 0.065)
			monitor.border_color = color
			monitor.set_border_width_all(maxi(roundi(weight), 1))
			canvas.draw_style_box(monitor, Rect2(origin + Vector2(0.28, 0.18) * side, Vector2(0.44, 0.64) * side))
			canvas.draw_line(origin + Vector2(0.43, 0.74) * side, origin + Vector2(0.57, 0.74) * side, color, weight * 0.55, true)
			for start in [0.0, 0.79]:
				canvas.draw_polyline(PackedVector2Array([origin + Vector2(start + 0.10, 0.26) * side, origin + Vector2(start + 0.02, 0.40) * side, origin + Vector2(start + 0.12, 0.54) * side, origin + Vector2(start + 0.04, 0.69) * side]), color, weight * 0.72, true)
		"motion":
			canvas.draw_arc(center, side * 0.34, -1.1, 4.1, 40, color, weight, true)
			_fill(canvas, origin, side, [Vector2(0.43, 0.31), Vector2(0.70, 0.50), Vector2(0.43, 0.69)], color)
			canvas.draw_line(origin + Vector2(0.08, 0.30) * side, origin + Vector2(0.25, 0.30) * side, color, weight * 0.70, true)
			canvas.draw_line(origin + Vector2(0.04, 0.48) * side, origin + Vector2(0.22, 0.48) * side, color, weight * 0.70, true)
		"play":
			_fill(canvas, origin, side, [Vector2(0.29, 0.14), Vector2(0.85, 0.50), Vector2(0.29, 0.86)], color)
		"restart":
			canvas.draw_arc(center, side * 0.32, -PI * 0.28, PI * 1.34, 42, color, weight, true)
			_fill(canvas, origin, side, [Vector2(0.53, 0.08), Vector2(0.88, 0.08), Vector2(0.88, 0.43)], color)
		"home":
			_fill(canvas, origin, side, [Vector2(0.07, 0.44), Vector2(0.50, 0.10), Vector2(0.93, 0.44), Vector2(0.81, 0.57), Vector2(0.50, 0.33), Vector2(0.19, 0.57)], color)
			_fill(canvas, origin, side, [Vector2(0.24, 0.48), Vector2(0.50, 0.30), Vector2(0.76, 0.48), Vector2(0.76, 0.89), Vector2(0.57, 0.89), Vector2(0.57, 0.65), Vector2(0.43, 0.65), Vector2(0.43, 0.89), Vector2(0.24, 0.89)], color)
		"exit":
			canvas.draw_polyline(PackedVector2Array([origin + Vector2(0.53, 0.16) * side, origin + Vector2(0.20, 0.16) * side, origin + Vector2(0.20, 0.84) * side, origin + Vector2(0.53, 0.84) * side]), color, weight, true)
			canvas.draw_line(origin + Vector2(0.44, 0.50) * side, origin + Vector2(0.86, 0.50) * side, color, weight, true)
			_fill(canvas, origin, side, [Vector2(0.66, 0.27), Vector2(0.93, 0.50), Vector2(0.66, 0.73)], color)
		"close":
			canvas.draw_line(origin + Vector2(0.24, 0.24) * side, origin + Vector2(0.76, 0.76) * side, color, weight, true)
			canvas.draw_line(origin + Vector2(0.76, 0.24) * side, origin + Vector2(0.24, 0.76) * side, color, weight, true)


static func _fill(canvas: CanvasItem, origin: Vector2, side: float, points: Array, color: Color) -> void:
	var vertices := PackedVector2Array()
	for point: Vector2 in points:
		vertices.append(origin + point * side)
	canvas.draw_colored_polygon(vertices, color)
	vertices.append(vertices[0])
	canvas.draw_polyline(vertices, color, maxf(side * 0.012, 0.65), true)
