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
	# Every inset uses the same matte, warm tan support.
	return Color("#dfbb7b")

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
	if side <= 4.0:
		canvas.draw_rect(rect, _alpha(target_tile_color(kind), alpha))
		return
	var rim := minf(clampf(side * 0.012, 0.25, 0.8), side * 0.04)
	var face := rect.grow(-rim)
	var bevel := minf(side * 0.135, minf(face.size.x, face.size.y) * 0.24)
	var center := face.grow(-bevel)
	var tl := face.position
	var tr := Vector2(face.end.x, face.position.y)
	var br := face.end
	var bl := Vector2(face.position.x, face.end.y)
	var ctl := center.position
	var ctr := Vector2(center.end.x, center.position.y)
	var cbr := center.end
	var cbl := Vector2(center.position.x, center.end.y)
	var light := clampf(highlight, 0.0, 1.0) * 0.10
	var cream := Color("#ffe7b5")
	canvas.draw_rect(Rect2(rect.position + Vector2(0.0, side * 0.025), rect.size), Color(0.36, 0.23, 0.10, alpha * 0.12))
	canvas.draw_rect(rect, _alpha(Color("#a77b46").lerp(cream, light), alpha))
	canvas.draw_polygon(PackedVector2Array([tl, tr, ctr, ctl]), PackedColorArray([
		_alpha(Color("#ffe7b5").lerp(cream, light), alpha), _alpha(Color("#f5dba6").lerp(cream, light), alpha),
		_alpha(Color("#efd09a").lerp(cream, light), alpha), _alpha(Color("#f5d9a2").lerp(cream, light), alpha)
	]))
	canvas.draw_polygon(PackedVector2Array([tl, ctl, cbl, bl]), PackedColorArray([
		_alpha(Color("#f1cd88").lerp(cream, light), alpha), _alpha(Color("#e9c17c").lerp(cream, light), alpha),
		_alpha(Color("#e9c17b").lerp(cream, light), alpha), _alpha(Color("#edca86").lerp(cream, light), alpha)
	]))
	canvas.draw_colored_polygon(PackedVector2Array([tr, br, cbr, ctr]), _alpha(Color("#b68a51").lerp(cream, light), alpha))
	canvas.draw_polygon(PackedVector2Array([bl, cbl, cbr, br]), PackedColorArray([
		_alpha(Color("#ae834c").lerp(cream, light), alpha), _alpha(Color("#bc9259").lerp(cream, light), alpha),
		_alpha(Color("#ac804a").lerp(cream, light), alpha), _alpha(Color("#a77a47").lerp(cream, light), alpha)
	]))
	canvas.draw_polygon(PackedVector2Array([ctl, ctr, cbr, cbl]), PackedColorArray([
		_alpha(Color("#eac585").lerp(cream, light), alpha),
		_alpha(Color("#dfb775").lerp(cream, light), alpha),
		_alpha(Color("#d2a768").lerp(cream, light), alpha),
		_alpha(Color("#dfb97b").lerp(cream, light), alpha)
	]))

static func draw_target_marker(canvas: CanvasItem, rect: Rect2, opacity: float = 1.0, glow: float = 1.0, kind: String = "red_star", embedded: bool = false) -> void:
	if rect.size.x <= 4.0 or rect.size.y <= 4.0 or opacity <= 0.0:
		return
	var side := minf(rect.size.x, rect.size.y)
	var center := rect.get_center() - Vector2(0.0, side * 0.012)
	var alpha := clampf(opacity, 0.0, 1.0)
	var shape := _target_outline(kind)
	var palette := _target_palette(kind)
	var body := _target_points(shape, center, side)
	if side <= 10.0:
		canvas.draw_colored_polygon(body, _target_color(palette[2], alpha, glow))
		return
	if embedded:
		_draw_target_slot(canvas, shape, center, side, alpha)
	var cap_center := center - Vector2(0.006, 0.009) * side
	var cap := _target_points(shape, cap_center, side * 0.90)
	# A proportional side wall keeps the cap inside even the concave stars.
	_draw_target_ring(canvas, body, cap, palette[0], palette[1], alpha, glow)
	if kind == "red_star" or kind == "yellow_star":
		_draw_target_star_face(canvas, shape, cap, cap_center, side * 0.90, palette, alpha, glow)
	elif kind == "gold_gem":
		_draw_target_gem_face(canvas, shape, cap, cap_center, side * 0.90, palette, alpha, glow)
	else:
		_draw_target_face_fan(canvas, cap, cap_center, palette, alpha, glow)

static func _target_palette(kind: String) -> PackedColorArray:
	# Side shadow, side light, face, front highlight, front shadow.
	match kind:
		"yellow_star": return PackedColorArray([Color("#bb6309"), Color("#fff4a5"), Color("#ffd035"), Color("#fffbb2"), Color("#eb8a0a")])
		"gold_gem": return PackedColorArray([Color("#a74402"), Color("#ffe6a3"), Color("#ffa426"), Color("#fff0b4"), Color("#d76005")])
		"blue_diamond": return PackedColorArray([Color("#087fa4"), Color("#b8fff3"), Color("#40d6e4"), Color("#b0fff2"), Color("#0b9ec4")])
	return PackedColorArray([Color("#9f071d"), Color("#ff8593"), Color("#fb3441"), Color("#ffa6b1"), Color("#c50720")])

static func _target_color(color: Color, opacity: float, glow: float = 0.0) -> Color:
	# Collection pulses change the existing faces slightly, without a halo.
	return _alpha(color.lerp(Color.WHITE, clampf(glow, 0.0, 2.0) * 0.008), opacity)

static func _draw_target_slot(canvas: CanvasItem, shape: PackedVector2Array, center: Vector2, side: float, alpha: float) -> void:
	var outer := _target_points(shape, center + Vector2(0.0, 0.003) * side, side * 1.10)
	var inner := _target_points(shape, center, side * 1.022)
	# Reversed lighting makes a shallow recess: dark upper wall, lower lip.
	_draw_target_ring(canvas, outer, inner, Color("#ffe6aa"), Color("#85532e"), alpha)
	canvas.draw_colored_polygon(inner, _alpha(Color("#754321"), alpha))

static func _draw_target_ring(canvas: CanvasItem, outer: PackedVector2Array, inner: PackedVector2Array, dark: Color, bright: Color, alpha: float, glow: float = 0.0) -> void:
	for index in range(outer.size()):
		var next := (index + 1) % outer.size()
		var edge := outer[next] - outer[index]
		var normal := Vector2(edge.y, -edge.x).normalized()
		var light := clampf(0.5 + normal.dot(Vector2(-0.55, -0.835)) * 0.5, 0.0, 1.0)
		var color := _target_color(dark.lerp(bright, light), alpha, glow)
		# Each strip is two triangles; no concave ring polygon is triangulated.
		canvas.draw_colored_polygon(PackedVector2Array([outer[index], outer[next], inner[next]]), color)
		canvas.draw_colored_polygon(PackedVector2Array([outer[index], inner[next], inner[index]]), color)

static func _draw_target_star_face(canvas: CanvasItem, shape: PackedVector2Array, cap: PackedVector2Array, center: Vector2, side: float, palette: PackedColorArray, alpha: float, glow: float) -> void:
	var tip_count := shape.size() / 2
	var crown := PackedVector2Array()
	for index in range(tip_count):
		crown.append(center + shape[index * 2] * side * (0.42 if tip_count == 6 else 0.30))
	for index in range(tip_count):
		var next := (index + 1) % tip_count
		var tip := cap[index * 2]
		var valley := cap[index * 2 + 1]
		var next_tip := cap[next * 2]
		var direction := shape[index * 2].normalized()
		var light := clampf(0.5 + direction.dot(Vector2(-0.62, -0.785)) * 0.5, 0.0, 1.0)
		var front := palette[4].lerp(palette[2], light)
		var ridge := palette[2].lerp(palette[3], light * light)
		canvas.draw_colored_polygon(PackedVector2Array([tip, valley, crown[index]]), _target_color(front, alpha, glow))
		canvas.draw_colored_polygon(PackedVector2Array([valley, crown[next], crown[index]]), _target_color(palette[2].lerp(front, 0.42), alpha, glow))
		canvas.draw_colored_polygon(PackedVector2Array([valley, next_tip, crown[next]]), _target_color(ridge, alpha, glow))
	# The small convex crown preserves a raised, bright center at board size.
	_draw_target_face_fan(canvas, crown, center, palette, alpha, glow)

static func _draw_target_gem_face(canvas: CanvasItem, shape: PackedVector2Array, cap: PackedVector2Array, center: Vector2, side: float, palette: PackedColorArray, alpha: float, glow: float) -> void:
	var table := _target_points(shape, center + Vector2(-0.015, 0.005) * side, side * 0.60)
	_draw_target_ring(canvas, cap, table, palette[4], palette[3], alpha, glow)
	canvas.draw_polygon(table, PackedColorArray([
		_target_color(Color("#ffb333"), alpha, glow), _target_color(Color("#ffa122"), alpha, glow),
		_target_color(Color("#f5931a"), alpha, glow), _target_color(Color("#ff9c24"), alpha, glow),
		_target_color(Color("#ffb33d"), alpha, glow)
	]))

static func _draw_target_face_fan(canvas: CanvasItem, outline: PackedVector2Array, center: Vector2, palette: PackedColorArray, alpha: float, glow: float) -> void:
	for index in range(outline.size()):
		var next := (index + 1) % outline.size()
		var direction := ((outline[index] + outline[next]) * 0.5 - center).normalized()
		var light := clampf(0.5 + direction.dot(Vector2(-0.62, -0.785)) * 0.5, 0.0, 1.0)
		var color := palette[4].lerp(palette[2], clampf(light * 1.35, 0.0, 1.0))
		color = color.lerp(palette[3], light * light * 0.32)
		canvas.draw_colored_polygon(PackedVector2Array([center, outline[index], outline[next]]), _target_color(color, alpha, glow))

static func _target_outline(kind: String) -> PackedVector2Array:
	if kind == "blue_diamond":
		return PackedVector2Array([Vector2(0.0, -0.34), Vector2(0.30, 0.0), Vector2(0.0, 0.34), Vector2(-0.30, 0.0)])
	if kind == "yellow_star":
		var star := PackedVector2Array()
		for index in range(10):
			var angle := -PI * 0.5 + float(index) * PI / 5.0
			var radius := 0.34 if index % 2 == 0 else 0.185
			star.append(Vector2(cos(angle) * 0.97, sin(angle) * 1.05) * radius)
		return star
	if kind == "gold_gem":
		return PackedVector2Array([
			Vector2(0.0, -0.30), Vector2(0.30, -0.075), Vector2(0.185, 0.30),
			Vector2(-0.185, 0.30), Vector2(-0.30, -0.075)
		])
	# Broad six-point rays match the approved inset, including its taller axis.
	return PackedVector2Array([
		Vector2(0.0, -0.35), Vector2(0.124, -0.212), Vector2(0.31, -0.175),
		Vector2(0.248, 0.0), Vector2(0.31, 0.175), Vector2(0.124, 0.212),
		Vector2(0.0, 0.35), Vector2(-0.124, 0.212), Vector2(-0.31, 0.175),
		Vector2(-0.248, 0.0), Vector2(-0.31, -0.175), Vector2(-0.124, -0.212)
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
