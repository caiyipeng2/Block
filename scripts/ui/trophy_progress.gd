extends Control
## A trophy filled from the bottom using the player's completed-level ratio.


class Silhouette extends Control:

	var illuminated: bool = false


	func _draw() -> void:
		var side := minf(size.x, size.y)
		var origin := (size - Vector2.ONE * side) * 0.5
		var color := Color("#ffd154") if illuminated else Color("#1a2c52")
		var points := PackedVector2Array([
			origin + Vector2(0.20, 0.12) * side,
			origin + Vector2(0.80, 0.12) * side,
			origin + Vector2(0.73, 0.51) * side,
			origin + Vector2(0.61, 0.65) * side,
			origin + Vector2(0.39, 0.65) * side,
			origin + Vector2(0.27, 0.51) * side
		])
		var handle_color := color.darkened(0.14) if illuminated else color
		draw_arc(origin + Vector2(0.27, 0.32) * side, side * 0.19, PI * 0.5, PI * 1.5, 24, handle_color, side * 0.055, true)
		draw_arc(origin + Vector2(0.73, 0.32) * side, side * 0.19, -PI * 0.5, PI * 0.5, 24, handle_color, side * 0.055, true)
		draw_colored_polygon(points, color)
		draw_rect(Rect2(origin + Vector2(0.44, 0.62) * side, Vector2(0.12, 0.17) * side), color.darkened(0.08) if illuminated else color)
		draw_rect(Rect2(origin + Vector2(0.30, 0.79) * side, Vector2(0.40, 0.08) * side), color)
		if not illuminated:
			return
		draw_line(origin + Vector2(0.24, 0.15) * side, origin + Vector2(0.76, 0.15) * side, color.lightened(0.40), side * 0.035, true)
		var star := PackedVector2Array()
		for point in range(10):
			var radius := side * (0.16 if point % 2 == 0 else 0.075)
			star.append(origin + Vector2(0.50, 0.36) * side + Vector2.from_angle(-PI * 0.5 + float(point) * PI / 5.0) * radius)
		draw_colored_polygon(star, Color("#ac7728"))


var _progress: float = 0.0
var _dark_silhouette: Silhouette
var _fill_clip: Control
var _gold_silhouette: Silhouette


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_dark_silhouette = Silhouette.new()
	_dark_silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dark_silhouette)
	_fill_clip = Control.new()
	_fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_clip.clip_contents = true
	add_child(_fill_clip)
	_gold_silhouette = Silhouette.new()
	_gold_silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_silhouette.illuminated = true
	_fill_clip.add_child(_gold_silhouette)
	resized.connect(_layout_visuals)
	_layout_visuals()


func set_progress(completed_count: int, total_count: int) -> void:
	_progress = clampf(float(completed_count) / float(total_count), 0.0, 1.0) if total_count > 0 else 0.0
	if is_node_ready():
		_layout_visuals()


func _layout_visuals() -> void:
	_dark_silhouette.position = Vector2.ZERO
	_dark_silhouette.size = size
	_dark_silhouette.queue_redraw()
	_fill_clip.visible = _progress > 0.0
	var side := minf(size.x, size.y)
	var origin := (size - Vector2.ONE * side) * 0.5
	# Use the trophy's height, so surrounding layout space cannot delay the fill.
	var fill_top := origin.y + side * lerpf(0.87, 0.10, _progress)
	if _progress >= 1.0:
		fill_top = 0.0
	_fill_clip.position = Vector2(0.0, fill_top)
	_fill_clip.size = Vector2(size.x, maxf(0.0, size.y - fill_top))
	_gold_silhouette.position = -_fill_clip.position
	_gold_silhouette.size = size
	_gold_silhouette.queue_redraw()
