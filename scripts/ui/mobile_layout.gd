extends RefCounted

## Convert physical Android insets once, before laying out native Controls.
## The caller keeps its own size and coordinate system; no parent UI is scaled.
static var _metrics_frame: int = -1
static var _safe_rects: Dictionary = {}
static var _density_frame: int = -1
static var _density: float = 1.0
static func is_mobile() -> bool:
	return OS.has_feature("android")


static func safe_content_rect(canvas: Control) -> Rect2:
	var bounds := Rect2(Vector2.ZERO, canvas.size)
	if not is_mobile() or not bounds.has_area():
		return bounds
	var viewport := canvas.get_viewport()
	if viewport == null:
		return bounds
	var local_to_screen := viewport.get_screen_transform() * canvas.get_global_transform_with_canvas()
	if is_zero_approx(local_to_screen.determinant()):
		return bounds
	var frame := Engine.get_process_frames()
	if frame != _metrics_frame:
		_metrics_frame = frame
		_safe_rects.clear()
	var canvas_id := canvas.get_instance_id()
	var cached: Dictionary = _safe_rects.get(canvas_id, {})
	if cached.get("size") == canvas.size and cached.get("transform") == local_to_screen:
		return cached["rect"]
	var screen := Rect2(Vector2(DisplayServer.screen_get_position()), Vector2(DisplayServer.screen_get_size()))
	var window := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if not safe.has_area():
		safe = screen
	# Some Android versions omit transient system-bar insets in immersive mode.
	# Reserve only the physical display edges, so an already inset app window or
	# letterbox does not have its top/bottom padding subtracted a second time.
	if screen.has_area():
		var edge_padding := 24.0 * _pixel_density()
		var edge_safe := Rect2(screen.position + Vector2(0.0, edge_padding), screen.size - Vector2(0.0, edge_padding * 2.0))
		if edge_safe.has_area():
			safe = safe.intersection(edge_safe)
	if window.has_area():
		safe = safe.intersection(window)
	if not safe.has_area():
		return bounds
	var local_safe := (local_to_screen.affine_inverse() * safe).intersection(bounds)
	var result := local_safe if local_safe.has_area() else bounds
	_safe_rects[canvas_id] = {"size": canvas.size, "transform": local_to_screen, "rect": result}
	return result


static func dp(canvas: Control, value: float) -> float:
	if not is_mobile() or canvas.get_viewport() == null:
		return value
	var local_to_screen := canvas.get_viewport().get_screen_transform() * canvas.get_global_transform_with_canvas()
	var pixels_per_unit := minf(local_to_screen.x.length(), local_to_screen.y.length())
	return value * _pixel_density() / maxf(pixels_per_unit, 0.001)


static func touch_target(canvas: Control, minimum_dp: float = 48.0) -> float:
	return dp(canvas, minimum_dp)


static func _pixel_density() -> float:
	var frame := Engine.get_process_frames()
	if frame != _density_frame:
		_density_frame = frame
		_density = float(maxi(DisplayServer.screen_get_dpi(), 120)) / 160.0
	return _density
