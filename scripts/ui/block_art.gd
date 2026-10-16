extends RefCounted

## Shared vector art for the board, tray, drag layer and feedback layer.
## The helpers draw only presentation and never modify the game state.

const NAVY := Color("#192441")
const GOLD := Color("#ffd154")
const AQUA := Color("#73f5e7")

## One cell rectangle is shared by the resting board and its move snapshot.
## Changing layers must never resize unrelated, stationary blocks.
static func grid_cell_rect(origin: Vector2, unit: float, inset: float = 1.0, scale_factor: float = 1.0) -> Rect2:
	var side := maxf(unit, 0.0)
	var padding := clampf(inset, 0.0, side * 0.5)
	var drawn_side := maxf(side - padding * 2.0, 0.0) * maxf(scale_factor, 0.0)
	var drawn_size := Vector2.ONE * drawn_side
	return Rect2(origin + Vector2.ONE * side * 0.5 - drawn_size * 0.5, drawn_size)

static func draw_block(canvas: CanvasItem, rect: Rect2, color: Color, opacity: float = 1.0, highlight: float = 0.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or opacity <= 0.0:
		return
	var alpha := clampf(opacity, 0.0, 1.0) * color.a
	var side := minf(rect.size.x, rect.size.y)
	if side <= 4.0:
		# Shrinking fragments cannot retain a rim and four distinct bevel faces.
		canvas.draw_rect(rect, _alpha(color, alpha))
		return
	var rim := clampf(side * 0.018, 0.55, 1.5)
	var base := color.lerp(Color.WHITE, clampf(highlight, 0.0, 1.0) * 0.28)
	var face := rect.grow(-rim)
	# Constrain the bevel to the space left after the rim, so the center
	# stays positive even when a particle crosses the small-size boundary.
	var bevel := minf(maxf(side * 0.145, 1.0), minf(face.size.x, face.size.y) * 0.25)
	var center := face.grow(-bevel)
	var tl := face.position
	var tr := Vector2(face.end.x, face.position.y)
	var br := face.end
	var bl := Vector2(face.position.x, face.end.y)
	var ctl := center.position
	var ctr := Vector2(center.end.x, center.position.y)
	var cbr := center.end
	var cbl := Vector2(center.position.x, center.end.y)
	canvas.draw_rect(Rect2(rect.position + Vector2(side * 0.025, side * 0.065), rect.size), Color(0.025, 0.035, 0.07, alpha * 0.34))
	canvas.draw_rect(rect, _alpha(base.darkened(0.52), alpha))
	canvas.draw_colored_polygon(PackedVector2Array([tl, tr, ctr, ctl]), _alpha(base.lightened(0.46), alpha))
	canvas.draw_colored_polygon(PackedVector2Array([tl, ctl, cbl, bl]), _alpha(base.lightened(0.12), alpha))
	canvas.draw_colored_polygon(PackedVector2Array([tr, br, cbr, ctr]), _alpha(base.darkened(0.25), alpha))
	canvas.draw_colored_polygon(PackedVector2Array([bl, cbl, cbr, br]), _alpha(base.darkened(0.43), alpha))
	canvas.draw_polygon(PackedVector2Array([ctl, ctr, cbr, cbl]), PackedColorArray([
		_alpha(base.lightened(0.08), alpha), _alpha(base.lightened(0.04), alpha),
		_alpha(base.darkened(0.05), alpha), _alpha(base.darkened(0.015), alpha)
	]))
	canvas.draw_line(tl + Vector2(rim, rim), tr + Vector2(-rim, rim), Color(1.0, 1.0, 1.0, alpha * 0.30), rim, true)
	canvas.draw_line(ctl, ctr, Color(1.0, 1.0, 1.0, alpha * 0.15), rim, true)

static func draw_empty_cell(canvas: CanvasItem, rect: Rect2, color: Color, subtle: bool = false) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	canvas.draw_rect(rect, color)
	var edge := clampf(minf(rect.size.x, rect.size.y) * 0.025, 0.6, 1.4)
	canvas.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), color.darkened(0.05 if subtle else 0.18), edge)
	canvas.draw_line(rect.position, Vector2(rect.position.x, rect.end.y), color.darkened(0.04 if subtle else 0.14), edge)
	canvas.draw_line(Vector2(rect.position.x, rect.end.y), rect.end, color.lightened(0.025 if subtle else 0.05), edge)
	canvas.draw_line(Vector2(rect.end.x, rect.position.y), rect.end, color.lightened(0.02 if subtle else 0.035), edge)

static func draw_board_frame(canvas: CanvasItem, rect: Rect2, compact: bool = false) -> void:
	if compact:
		var rim := clampf(rect.size.x * 0.015, 4.0, 8.0)
		canvas.draw_style_box(panel_style(Color(0.04, 0.08, 0.17, 0.28), 9, Color.TRANSPARENT), Rect2(rect.position + Vector2(0.0, 3.0), rect.size).grow(rim + 2.0))
		canvas.draw_style_box(panel_style(Color("#263b65"), 7, Color("#3c5686")), rect.grow(rim))
		canvas.draw_rect(rect.grow(1.0), Color("#111d36"))
		return
	var shadow_rect := Rect2(rect.position + Vector2(0.0, 7.0), rect.size).grow(12.0)
	canvas.draw_style_box(panel_style(Color(0.06, 0.10, 0.20, 0.28), 15, Color.TRANSPARENT), shadow_rect)
	canvas.draw_style_box(panel_style(Color("#273e6b"), 13, Color("#3e5b92")), rect.grow(11.0))
	canvas.draw_style_box(panel_style(Color("#152544"), 9, Color("#1a2d52")), rect.grow(6.0))
	canvas.draw_rect(rect.grow(1.0), Color("#111c35"))
	canvas.draw_line(rect.position + Vector2(-4.0, -5.0), Vector2(rect.end.x + 4.0, rect.position.y - 5.0), Color(0.02, 0.05, 0.11, 0.48), 2.0, true)
	canvas.draw_line(Vector2(rect.position.x - 5.0, rect.end.y + 7.0), rect.end + Vector2(5.0, 7.0), Color(0.37, 0.49, 0.74, 0.38), 2.0, true)

static func draw_background(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_polygon(PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)
	]), PackedColorArray([Color("#374f89"), Color("#354b82"), Color("#304b83"), Color("#395892")]))
	# Low contrast bands keep a quiet blue field behind bright square pieces.
	var band_count := 28
	for i in range(band_count):
		var y := rect.position.y + rect.size.y * float(i) / float(band_count)
		canvas.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.57, 0.68, 0.92, 0.012), 1.0)
	var glow_center := rect.position + rect.size * Vector2(0.5, 0.42)
	var glow_radius := minf(rect.size.x, rect.size.y) * 0.63
	for ring in range(5, 0, -1):
		canvas.draw_circle(glow_center, glow_radius * float(ring) / 5.0, Color(0.30, 0.45, 0.80, 0.012))

static func draw_icon(canvas: CanvasItem, kind: String, rect: Rect2, color: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var side := minf(rect.size.x, rect.size.y)
	var origin := rect.get_center() - Vector2.ONE * side * 0.5
	var weight := maxf(1.4, side * 0.08)
	match kind:
		"back":
			canvas.draw_polyline(PackedVector2Array([origin + Vector2(0.65, 0.15) * side, origin + Vector2(0.28, 0.50) * side, origin + Vector2(0.65, 0.85) * side]), color, weight, true)
		"crown":
			_polygon(canvas, origin, side, [Vector2(0.10, 0.32), Vector2(0.30, 0.51), Vector2(0.50, 0.12), Vector2(0.70, 0.51), Vector2(0.90, 0.32), Vector2(0.80, 0.81), Vector2(0.20, 0.81)], color)
			canvas.draw_rect(Rect2(origin + Vector2(0.20, 0.84) * side, Vector2(0.60, 0.07) * side), color.darkened(0.08))
			for point in [Vector2(0.10, 0.28), Vector2(0.50, 0.10), Vector2(0.90, 0.28)]:
				canvas.draw_circle(origin + point * side, side * 0.065, color.lightened(0.12))
			canvas.draw_line(origin + Vector2(0.23, 0.79) * side, origin + Vector2(0.77, 0.79) * side, color.lightened(0.40), maxf(1.0, side * 0.04), true)
		"gear", "settings":
			var center := origin + Vector2.ONE * side * 0.5
			var segments := 32
			for i in range(segments):
				var angle_a := TAU * float(i) / float(segments)
				var angle_b := TAU * float(i + 1) / float(segments)
				var radius_a := 0.46 if i % 4 in [1, 2] else 0.36
				var radius_b := 0.46 if (i + 1) % 4 in [1, 2] else 0.36
				canvas.draw_colored_polygon(PackedVector2Array([
					center + Vector2.from_angle(angle_a) * side * 0.19,
					center + Vector2.from_angle(angle_a) * side * radius_a,
					center + Vector2.from_angle(angle_b) * side * radius_b,
					center + Vector2.from_angle(angle_b) * side * 0.19
				]), color)
		"pause":
			canvas.draw_rect(Rect2(origin + Vector2(0.22, 0.18) * side, Vector2(0.20, 0.64) * side), color)
			canvas.draw_rect(Rect2(origin + Vector2(0.58, 0.18) * side, Vector2(0.20, 0.64) * side), color)
		"restart":
			canvas.draw_arc(origin + Vector2.ONE * side * 0.5, side * 0.30, -PI * 0.45, PI * 1.23, 28, color, weight, true)
			_polygon(canvas, origin, side, [Vector2(0.06, 0.20), Vector2(0.38, 0.20), Vector2(0.24, 0.48)], color)
		"home", "menu":
			_polygon(canvas, origin, side, [Vector2(0.08, 0.46), Vector2(0.50, 0.10), Vector2(0.92, 0.46), Vector2(0.81, 0.56), Vector2(0.50, 0.29), Vector2(0.19, 0.56)], color)
			_polygon(canvas, origin, side, [Vector2(0.23, 0.48), Vector2(0.23, 0.88), Vector2(0.43, 0.88), Vector2(0.43, 0.65), Vector2(0.57, 0.65), Vector2(0.57, 0.88), Vector2(0.77, 0.88), Vector2(0.77, 0.48), Vector2(0.50, 0.30)], color)
		"play":
			_polygon(canvas, origin, side, [Vector2(0.29, 0.15), Vector2(0.85, 0.50), Vector2(0.29, 0.85)], color)
		"close":
			canvas.draw_line(origin + Vector2(0.23, 0.23) * side, origin + Vector2(0.77, 0.77) * side, color, weight, true)
			canvas.draw_line(origin + Vector2(0.77, 0.23) * side, origin + Vector2(0.23, 0.77) * side, color, weight, true)
		"spark":
			_polygon(canvas, origin, side, [Vector2(0.50, 0.05), Vector2(0.62, 0.37), Vector2(0.94, 0.50), Vector2(0.62, 0.63), Vector2(0.50, 0.95), Vector2(0.38, 0.63), Vector2(0.06, 0.50), Vector2(0.38, 0.37)], color)
		"lock":
			canvas.draw_arc(origin + Vector2(0.50, 0.40) * side, side * 0.23, PI, TAU, 16, color, weight, true)
			canvas.draw_rect(Rect2(origin + Vector2(0.23, 0.39) * side, Vector2(0.54, 0.47) * side), color)

static func panel_style(fill: Color, radius: int = 18, border: Color = Color("#5474ac")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.corner_detail = 6
	style.set_content_margin_all(16.0)
	return style

static func button_style(fill: Color, pressed: bool = false) -> StyleBoxFlat:
	var style := panel_style(fill.darkened(0.10) if pressed else fill, 12, fill.lightened(0.20))
	style.border_width_bottom = 1 if pressed else 3
	style.border_color = fill.darkened(0.34)
	style.shadow_color = Color(0.04, 0.07, 0.15, 0.22)
	style.shadow_size = 2 if pressed else 4
	style.shadow_offset = Vector2(0.0, 1.0 if pressed else 3.0)
	style.set_content_margin_all(10.0)
	return style

static func target_tile_color(_kind: String = "red_star") -> Color:
	# Both gem kinds sit in the same warm sand-gold tile.
	return Color("#e3c38a")

static func target_name(kind: String = "red_star") -> String:
	match kind:
		"blue_diamond": return "蓝色钻石"
		"gold_gem": return "金色宝石"
		"yellow_star": return "黄色星星"
	return "红星宝石"

static func draw_target_tile(canvas: CanvasItem, rect: Rect2, opacity: float = 1.0, highlight: float = 0.0, kind: String = "red_star") -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or opacity <= 0.0:
		return
	var alpha := clampf(opacity, 0.0, 1.0)
	var side := minf(rect.size.x, rect.size.y)
	if side <= 2.0:
		canvas.draw_rect(rect, _alpha(target_tile_color(kind), alpha))
		return
	var rim := clampf(side * 0.012, 0.35, 0.8)
	var bevel := side * 0.18
	var face := rect.grow(-rim)
	var center := face.grow(-bevel)
	var tl := face.position
	var tr := Vector2(face.end.x, face.position.y)
	var br := face.end
	var bl := Vector2(face.position.x, face.end.y)
	var ctl := center.position
	var ctr := Vector2(center.end.x, center.position.y)
	var cbr := center.end
	var cbl := Vector2(center.position.x, center.end.y)
	var light := clampf(highlight, 0.0, 1.0) * 0.18
	var cream := Color("#ffe4aa")
	canvas.draw_rect(Rect2(rect.position + Vector2(0.0, clampf(side * 0.025, 0.4, 1.2)), rect.size), Color(0.42, 0.29, 0.12, alpha * 0.17))
	canvas.draw_rect(rect, _alpha(Color("#b58b4d").lerp(cream, light), alpha))
	canvas.draw_colored_polygon(PackedVector2Array([tl, tr, ctr, ctl]), _alpha(Color("#f6dba0").lerp(cream, light), alpha))
	canvas.draw_colored_polygon(PackedVector2Array([tl, ctl, cbl, bl]), _alpha(Color("#eaca8b").lerp(cream, light), alpha))
	canvas.draw_colored_polygon(PackedVector2Array([tr, br, cbr, ctr]), _alpha(Color("#c29b5c").lerp(cream, light), alpha))
	canvas.draw_colored_polygon(PackedVector2Array([bl, cbl, cbr, br]), _alpha(Color("#b88d4d").lerp(cream, light), alpha))
	canvas.draw_polygon(PackedVector2Array([ctl, ctr, cbr, cbl]), PackedColorArray([
		_alpha(Color("#ebcf97").lerp(cream, light), alpha),
		_alpha(Color("#e7c68b").lerp(cream, light), alpha),
		_alpha(Color("#ddba7c").lerp(cream, light), alpha),
		_alpha(Color("#e2c187").lerp(cream, light), alpha)
	]))
	canvas.draw_line(tl, tr, Color(1.0, 0.89, 0.67, alpha * 0.45), rim, true)

static func draw_target_marker(canvas: CanvasItem, rect: Rect2, opacity: float = 1.0, glow: float = 1.0, kind: String = "red_star") -> void:
	if rect.size.x <= 2.0 or rect.size.y <= 2.0 or opacity <= 0.0:
		return
	var side := minf(rect.size.x, rect.size.y)
	var center := rect.get_center() - Vector2(0.0, side * 0.018)
	var alpha := clampf(opacity, 0.0, 1.0)
	var is_gold := kind == "gold_gem"
	var shape := _target_outline(kind)
	var points := _target_points(shape, center, side)
	var inset := _target_points(shape, center - Vector2(side * 0.010, side * 0.014), side * (0.70 if is_gold else 0.82))
	var dark := Color("#9c6821") if is_gold else Color("#a9222e")
	var bright := Color("#ffe59a") if is_gold else Color("#fb7c80")
	var base := Color("#ffc23f") if is_gold else Color("#ee3d48")
	var shade := Color("#e58b1d") if is_gold else Color("#c92639")
	if kind == "blue_diamond":
		dark = Color("#1489ad")
		bright = Color("#a9fff2")
		base = Color("#30d4df")
		shade = Color("#16a6c9")
	elif kind == "yellow_star":
		dark = Color("#c58b25")
		bright = Color("#fff5b8")
		base = Color("#ffd34c")
		shade = Color("#e8a42f")
	var edge := clampf(side * 0.014, 0.28, 0.80)
	var rim_scale := 1.0 + edge / (side * 0.30)
	# Short colored extrusion and a narrow rim give volume without a sticker halo.
	canvas.draw_colored_polygon(_target_points(shape, center + Vector2(0.0, side * 0.037), side * 1.025), Color(0.40, 0.24, 0.11, alpha * 0.22))
	canvas.draw_colored_polygon(_target_points(shape, center + Vector2(0.0, side * 0.025), side * rim_scale), _alpha(dark, alpha))
	canvas.draw_colored_polygon(_target_points(shape, center, side * rim_scale), _alpha(dark, alpha))
	canvas.draw_colored_polygon(points, _alpha(base, alpha))
	for i in range(points.size()):
		var next := (i + 1) % points.size()
		var normal := ((shape[i] + shape[next]) * 0.5).normalized()
		var light := clampf(0.5 + normal.dot(Vector2(-0.52, -0.86)) * 0.5, 0.0, 1.0)
		var facet := shade.lerp(bright, light)
		canvas.draw_colored_polygon(PackedVector2Array([points[i], points[next], inset[next], inset[i]]), _alpha(facet, alpha))
	var table_colors := PackedColorArray()
	for point in shape:
		var top_light := clampf(0.10 - point.y * 0.22, 0.03, 0.17)
		table_colors.append(_alpha(base.lerp(bright, top_light + clampf(glow, 0.0, 2.0) * 0.012), alpha))
	canvas.draw_polygon(inset, table_colors)

static func _target_outline(kind: String) -> PackedVector2Array:
	if kind == "blue_diamond":
		return PackedVector2Array([Vector2(0.0, -0.34), Vector2(0.30, 0.0), Vector2(0.0, 0.34), Vector2(-0.30, 0.0)])
	if kind == "yellow_star":
		var star := PackedVector2Array()
		for index in range(10):
			star.append(Vector2.from_angle(-PI * 0.5 + float(index) * PI / 5.0) * (0.33 if index % 2 == 0 else 0.22))
		return star
	if kind == "gold_gem":
		return PackedVector2Array([
			Vector2(0.0, -0.315), Vector2(0.30, -0.09), Vector2(0.19, 0.28),
			Vector2(-0.19, 0.28), Vector2(-0.30, -0.09)
		])
	# Inner corners sit at roughly three quarters of the outer radius:
	# six broad points remain readable when the board cell is only 30px wide.
	return PackedVector2Array([
		Vector2(0.0, -0.30), Vector2(0.115, -0.20), Vector2(0.28, -0.15),
		Vector2(0.23, 0.0), Vector2(0.28, 0.15), Vector2(0.115, 0.20),
		Vector2(0.0, 0.30), Vector2(-0.115, 0.20), Vector2(-0.28, 0.15),
		Vector2(-0.23, 0.0), Vector2(-0.28, -0.15), Vector2(-0.115, -0.20)
	])

static func _target_points(shape: PackedVector2Array, center: Vector2, side: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in shape:
		points.append(center + point * side)
	return points

static func _alpha(color: Color, opacity: float) -> Color:
	return Color(color.r, color.g, color.b, opacity)

static func _polygon(canvas: CanvasItem, origin: Vector2, side: float, points: Array, color: Color) -> void:
	var vertices := PackedVector2Array()
	for point in points:
		vertices.append(origin + Vector2(point) * side)
	canvas.draw_colored_polygon(vertices, color)
