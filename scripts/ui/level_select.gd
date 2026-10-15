extends Control

## Native, scrollable adventure map. The owner supplies progress and level goals.
const Art := preload("res://scripts/ui/block_art.gd")
const IconButton := preload("res://scripts/ui/art_icon_button.gd")

signal back_requested
signal level_started(level_id: int)
signal level_selected(level_id: int)

var total_levels: int = 96
var selected_level: int = 1
var highest_completed: int = 0

var _unlocked_level: int = 1
var _header: Panel
var _footer: Panel
var _back: Button
var _title: Label
var _progress: Label
var _scroll: ScrollContainer
var _map: Control
var _route: AdventureRoute
var _marker: GoldDiamond
var _trophy: Control
var _map_caption: Label
var _description: Label
var _start: Button
var _save_warning: Label
var _save_status := ""
var _tiles: Dictionary = {}
var _description_text: String = ""
var _reveal_queued: bool = false
var _focus_on_reveal: bool = false
var _center_on_reveal: bool = false
var _animate_on_reveal: bool = false
var _reduced_motion: bool = false
var _last_activated_level: int = 0
var _scroll_tween: Tween
var _manual_scroll_epoch: int = 0
var _programmatic_focus: bool = false
var _reveal_level: int = 0


class AdventureRoute extends Control:

	const RouteArt := preload("res://scripts/ui/block_art.gd")

	var points := PackedVector2Array()
	var completed_count: int = 0
	var tile_side: float = 56.0

	func _draw() -> void:
		for index in range(maxi(0, points.size() - 1)):
			var start := points[index]
			var finish := points[index + 1]
			var active := index < completed_count
			var curve := PackedVector2Array()
			for step in range(17):
				var t := float(step) / 16.0
				var blend := t * t * (3.0 - 2.0 * t)
				curve.append(Vector2(lerpf(start.x, finish.x, blend), lerpf(start.y, finish.y, t)))
			draw_polyline(curve, Color(0.07, 0.15, 0.30, 0.45), 12.0, true)
			draw_polyline(curve, Color("#4caeb4") if active else Color("#456a90"), 6.0, true)
			draw_polyline(curve, Color(0.58, 0.98, 0.84, 0.44) if active else Color(0.57, 0.76, 0.87, 0.20), 1.5, true)
			var center := (start + finish) * 0.5
			if index % 2 == 0:
				_draw_leaf(center, -1.0 if index % 4 == 0 else 1.0, active)
			else:
				draw_circle(center, 4.0, Color("#d6bc68") if active else Color("#597c9e"))
				draw_circle(center + Vector2(-0.7, -1.0), 1.4, Color(1.0, 0.94, 0.63, 0.7) if active else Color(0.69, 0.81, 0.94, 0.3))
		var font := get_theme_default_font()
		for index in range(0, points.size(), 12):
			var center := points[index]
			var completed := index < completed_count
			var platform := Rect2(center + Vector2(-74.0, tile_side * 0.39), Vector2(148.0, 18.0))
			draw_style_box(RouteArt.panel_style(Color("#346d7d") if completed else Color("#2c4772"), 9, Color("#5a879f")), platform)
			var caption := "第 %d 段旅程" % (floori(float(index) / 12.0) + 1)
			var text_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
			draw_string(font, Vector2(center.x - text_width * 0.5, center.y + tile_side * 0.5 + 36.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color("#b8d9e8"))

	func _draw_leaf(center: Vector2, direction: float, active: bool) -> void:
		var root := center + Vector2(direction * 3.0, 2.0)
		var tip := center + Vector2(direction * 37.0, -17.0)
		var leaf := PackedVector2Array([
			root, center + Vector2(direction * 9.0, -19.0),
			center + Vector2(direction * 26.0, -26.0), tip,
			center + Vector2(direction * 28.0, 0.0), center + Vector2(direction * 14.0, 7.0)
		])
		draw_colored_polygon(leaf, Color(0.25, 0.67, 0.57, 0.7) if active else Color(0.35, 0.55, 0.67, 0.35))
		draw_line(root, tip, Color(0.62, 0.91, 0.76, 0.55) if active else Color(0.67, 0.81, 0.88, 0.24), 1.4, true)


class GoldDiamond extends Control:

	var reduced_motion: bool = false
	var _phase: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_update_processing()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
			_update_processing()

	func set_reduced_motion(enabled: bool) -> void:
		reduced_motion = enabled
		if enabled:
			_phase = 0.0
		_update_processing()
		queue_redraw()

	func _update_processing() -> void:
		set_process(is_visible_in_tree() and not reduced_motion)

	func _process(delta: float) -> void:
		_phase = fmod(_phase + delta * 3.2, TAU)
		queue_redraw()

	func _draw() -> void:
		var bob := 0.0 if reduced_motion else sin(_phase) * 5.0
		var center := Vector2(size.x * 0.5, 19.0 + bob)
		for radius in [22.0, 17.0, 13.0]:
			draw_circle(center, radius, Color(1.0, 0.82, 0.23, 0.035))
		draw_set_transform(Vector2(size.x * 0.5, size.y - 3.0), 0.0, Vector2(1.0, 0.22))
		draw_circle(Vector2.ZERO, 10.5 - bob * 0.16, Color(0.03, 0.08, 0.17, 0.27))
		draw_set_transform(center, 0.0 if reduced_motion else sin(_phase * 0.5) * 0.055)
		var top := Vector2(0.0, -13.5)
		var right := Vector2(15.5, -3.0)
		var bottom := Vector2(0.0, 16.0)
		var left := Vector2(-15.5, -3.0)
		draw_colored_polygon(PackedVector2Array([top, right, Vector2(0.0, 4.0), left]), Color("#ffe986"))
		draw_colored_polygon(PackedVector2Array([left, Vector2(0.0, 4.0), bottom]), Color("#f4ba37"))
		draw_colored_polygon(PackedVector2Array([Vector2(0.0, 4.0), right, bottom]), Color("#cc8b24"))
		draw_polyline(PackedVector2Array([left, top, right]), Color("#fff6c2"), 1.5, true)
		draw_set_transform(Vector2.ZERO)


class LevelTile extends Button:

	const TileArt := preload("res://scripts/ui/block_art.gd")

	var level_id: int = 1
	var completed: bool = false
	var selected: bool = false
	var _number: Label

	func _ready() -> void:
		custom_minimum_size = Vector2(48.0, 48.0)
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		text = str(level_id)
		# The bevel is drawn below a child label; keep native Button text for
		# keyboard/accessibility semantics without drawing it twice.
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
			add_theme_color_override(state, Color.TRANSPARENT)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		_number = Label.new()
		_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_number)
		for event in [mouse_entered, mouse_exited, focus_entered, focus_exited, button_down, button_up]:
			event.connect(queue_redraw)
		refresh()

	func refresh() -> void:
		if is_instance_valid(_number):
			_number.text = str(level_id)
			_number.add_theme_font_size_override("font_size", clampi(int(size.x * 0.40), 18, 26))
			_number.add_theme_color_override("font_color", Color("#273451") if selected else (Color("#efffff") if completed else Color("#91a6ce")))
		queue_redraw()

	func _draw() -> void:
		var color := Color("#263c68")
		if selected:
			color = Color("#ffd154")
		elif completed:
			color = Color("#31bddc")
		elif not disabled:
			color = Color("#4f83ce")
		if is_pressed() and not disabled:
			color = color.darkened(0.08)
		var inset := 3.0
		var rect := Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0)
		TileArt.draw_block(self, rect, color, 0.76 if disabled else 1.0, 0.12 if is_hovered() and not disabled else 0.0)
		if selected:
			draw_rect(rect.grow(1.0), Color("#fff2ac"), false, 2.0)
		if has_focus():
			# An outline cannot tint the fill, unlike a translucent focus panel.
			draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), Color("#82f5e9"), false, 2.0)


class TrophyArt extends Control:

	func _draw() -> void:
		var side := minf(size.x, size.y)
		var origin := (size - Vector2.ONE * side) * 0.5
		var gold := Color("#ffd154")
		var points := PackedVector2Array([
			origin + Vector2(0.20, 0.12) * side,
			origin + Vector2(0.80, 0.12) * side,
			origin + Vector2(0.73, 0.51) * side,
			origin + Vector2(0.61, 0.65) * side,
			origin + Vector2(0.39, 0.65) * side,
			origin + Vector2(0.27, 0.51) * side
		])
		draw_arc(origin + Vector2(0.27, 0.32) * side, side * 0.19, PI * 0.5, PI * 1.5, 24, gold.darkened(0.14), side * 0.055, true)
		draw_arc(origin + Vector2(0.73, 0.32) * side, side * 0.19, -PI * 0.5, PI * 0.5, 24, gold.darkened(0.14), side * 0.055, true)
		draw_colored_polygon(points, gold)
		draw_rect(Rect2(origin + Vector2(0.44, 0.62) * side, Vector2(0.12, 0.17) * side), gold.darkened(0.08))
		draw_rect(Rect2(origin + Vector2(0.30, 0.79) * side, Vector2(0.40, 0.08) * side), gold)
		draw_line(origin + Vector2(0.24, 0.15) * side, origin + Vector2(0.76, 0.15) * side, gold.lightened(0.40), side * 0.035, true)
		var star := PackedVector2Array()
		for point in range(10):
			var radius := side * (0.16 if point % 2 == 0 else 0.075)
			star.append(origin + Vector2(0.50, 0.36) * side + Vector2.from_angle(-PI * 0.5 + float(point) * PI / 5.0) * radius)
		draw_colored_polygon(star, Color("#ac7728"))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_controls()
	resized.connect(_layout_controls)
	visibility_changed.connect(_on_visibility_changed)
	_layout_controls()
	_rebuild_tiles()
	_refresh_selection()


func configure(level_count: int, completed_count: int, initial_selection: int = 0) -> void:
	_cancel_scroll_animation()
	total_levels = maxi(1, level_count)
	highest_completed = clampi(completed_count, 0, total_levels)
	_unlocked_level = mini(total_levels, highest_completed + 1)
	selected_level = _unlocked_level if initial_selection <= 0 else clampi(initial_selection, 1, _unlocked_level)
	_description_text = ""
	if is_node_ready():
		_rebuild_tiles()
		_refresh_selection()


func select_latest() -> void:
	_select_level(_unlocked_level)

func set_save_status(message: String) -> void:
	_save_status = message
	if is_instance_valid(_save_warning):
		_save_warning.text = message
		_save_warning.tooltip_text = message
		_save_warning.visible = not message.is_empty()


func activate() -> void:
	var animate_upward := _last_activated_level > 0 and _unlocked_level > _last_activated_level
	select_latest()
	_schedule_reveal(true, true, animate_upward)
	_last_activated_level = selected_level


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if is_instance_valid(_marker):
		_marker.set_reduced_motion(enabled)
	if enabled:
		_cancel_scroll_animation()


func _exit_tree() -> void:
	_cancel_scroll_animation()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_cancel_scroll_animation()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not is_instance_valid(_scroll):
		return
	var pointer_in_map := _scroll.get_global_rect().has_point(get_global_mouse_position())
	var user_scroll := false
	if event is InputEventMouseButton and event.pressed and pointer_in_map:
		user_scroll = event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
	elif event is InputEventMouseMotion and pointer_in_map:
		user_scroll = (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE)) != 0
	elif event is InputEventKey and event.pressed:
		user_scroll = event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END, KEY_UP, KEY_DOWN]
	if user_scroll:
		_manual_scroll_epoch += 1
		_cancel_scroll_animation()


func _cancel_scroll_animation() -> void:
	if is_instance_valid(_scroll_tween):
		_scroll_tween.kill()
	_scroll_tween = null
	_animate_on_reveal = false


func set_level_description(value: String) -> void:
	_description_text = value
	_refresh_description()


func _build_controls() -> void:
	_header = Panel.new()
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.add_theme_stylebox_override("panel", Art.panel_style(Color("#3f5fac"), 0, Color("#597ec5")))
	add_child(_header)
	_back = Button.new()
	_back.set_script(IconButton)
	_back.set("icon_kind", "back")
	_back.tooltip_text = "返回主菜单"
	_back.pressed.connect(func() -> void: back_requested.emit())
	_header.add_child(_back)
	_title = _label(32, Color("#efffff"))
	_title.text = "闯关模式"
	_header.add_child(_title)
	_progress = _label(17, Color("#c8dafa"))
	_header.add_child(_progress)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# Reveal the marker with its tile, rather than letting native focus clip it.
	_scroll.follow_focus = false
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scroll)
	_map = Control.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_map)
	_route = AdventureRoute.new()
	_route.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(_route)
	_trophy = TrophyArt.new()
	_trophy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(_trophy)
	_map_caption = _label(18, Color("#c8e9ff"))
	_map_caption.text = "沿着藤蔓向上，点亮下一段旅程"
	_map.add_child(_map_caption)
	_marker = GoldDiamond.new()
	_marker.name = "SelectedLevelMarker"
	_marker.z_index = 2
	_marker.set_reduced_motion(_reduced_motion)
	_map.add_child(_marker)
	_footer = Panel.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_STOP
	_footer.add_theme_stylebox_override("panel", Art.panel_style(Color("#304b87"), 0, Color("#597ec5")))
	add_child(_footer)
	_description = _label(18, Color("#d7ebff"))
	_description.clip_text = true
	_footer.add_child(_description)
	_start = Button.new()
	_start.custom_minimum_size = Vector2(48.0, 56.0)
	_start.focus_mode = Control.FOCUS_ALL
	_start.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_start.add_theme_font_size_override("font_size", 24)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_start.add_theme_color_override(state, Color("#efffff"))
	_start.add_theme_stylebox_override("normal", Art.button_style(Color("#36af38")))
	_start.add_theme_stylebox_override("hover", Art.button_style(Color("#4abd43")))
	_start.add_theme_stylebox_override("pressed", Art.button_style(Color("#36af38"), true))
	var focus := Art.panel_style(Color.TRANSPARENT, 12, Color("#82f5e9"))
	focus.set_border_width_all(2)
	focus.shadow_size = 0
	_start.add_theme_stylebox_override("focus", focus)
	_start.pressed.connect(_start_selected_level)
	_footer.add_child(_start)
	_save_warning = _label(12, Color("#ffbb8e"))
	_footer.add_child(_save_warning)
	set_save_status(_save_status)


func _label(font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.autowrap_mode = TextServer.AUTOWRAP_OFF
	result.clip_text = true
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


func _rebuild_tiles() -> void:
	for tile in _tiles.values():
		_map.remove_child(tile)
		tile.queue_free()
	_tiles.clear()
	for level_id in range(1, total_levels + 1):
		var tile := LevelTile.new()
		tile.name = "Level%d" % level_id
		tile.level_id = level_id
		tile.disabled = level_id > _unlocked_level
		tile.completed = level_id <= highest_completed
		tile.tooltip_text = "第 %d 关%s" % [level_id, " · 尚未解锁" if tile.disabled else (" · 已通关" if tile.completed else "")]
		tile.pressed.connect(_select_level.bind(level_id))
		tile.focus_entered.connect(_on_tile_focused.bind(level_id))
		_map.add_child(tile)
		_tiles[level_id] = tile
	for level_id in _tiles:
		var tile: LevelTile = _tiles[level_id]
		if int(level_id) < _unlocked_level:
			tile.focus_neighbor_top = tile.get_path_to(_tiles[int(level_id) + 1])
		if int(level_id) > 1:
			tile.focus_neighbor_bottom = tile.get_path_to(_tiles[int(level_id) - 1])
	_layout_map()


func _layout_controls() -> void:
	if not is_instance_valid(_header):
		return
	var header_height := 104.0
	var footer_height := 132.0
	_header.position = Vector2.ZERO
	_header.size = Vector2(size.x, header_height)
	_back.position = Vector2(24.0, 20.0)
	_back.size = Vector2(52.0, 52.0)
	var heading_right_margin := 86.0 if size.x >= 480.0 else 20.0
	_title.position = Vector2(86.0, 16.0)
	_title.size = Vector2(maxf(0.0, size.x - 86.0 - heading_right_margin), 42.0)
	_title.add_theme_font_size_override("font_size", 32 if size.x >= 480.0 else 26)
	_progress.position = Vector2(86.0, 61.0)
	_progress.size = Vector2(maxf(0.0, size.x - 86.0 - heading_right_margin), 28.0)
	_progress.add_theme_font_size_override("font_size", 17 if size.x >= 480.0 else 14)
	_scroll.position = Vector2(16.0, header_height + 12.0)
	_scroll.size = Vector2(maxf(0.0, size.x - 32.0), maxf(0.0, size.y - header_height - footer_height - 24.0))
	_footer.position = Vector2(0.0, maxf(header_height, size.y - footer_height))
	_footer.size = Vector2(size.x, footer_height)
	_description.position = Vector2(24.0, 10.0)
	_description.size = Vector2(maxf(0.0, size.x - 48.0), 32.0)
	var button_width := minf(600.0, maxf(48.0, size.x - 64.0))
	_start.position = Vector2((size.x - button_width) * 0.5, 51.0)
	_start.size = Vector2(button_width, 58.0)
	_save_warning.position = Vector2(24.0, 112.0)
	_save_warning.size = Vector2(maxf(0.0, size.x - 48.0), 18.0)
	_layout_map()


func _layout_map() -> void:
	if not is_instance_valid(_map):
		return
	# One climbing route keeps the next challenge above the current one. A
	# chapter adds a breathing space, without packing future levels into a grid.
	var content_width := maxf(160.0, _scroll.size.x - 24.0)
	var available_width := minf(760.0, content_width - 24.0)
	var tile_side := clampf(floorf(content_width * 0.095), 48.0, 64.0)
	var amplitude := maxf(18.0, (available_width - tile_side - 64.0) * 0.34)
	var step_height := 104.0
	var chapter_gap := 68.0
	var chapter_count := floori(float(total_levels - 1) / 12.0)
	var top_space := 222.0
	var map_height := top_space + float(total_levels - 1) * step_height + float(chapter_count) * chapter_gap + tile_side + 108.0
	_map.custom_minimum_size = Vector2(0.0, map_height)
	_route.position = Vector2.ZERO
	_route.size = Vector2(content_width, map_height)
	_route.tile_side = tile_side
	_route.completed_count = highest_completed
	_route.points.clear()
	_trophy.position = Vector2((content_width - 124.0) * 0.5, 14.0)
	_trophy.size = Vector2(124.0, 124.0)
	_map_caption.position = Vector2(8.0, 152.0)
	_map_caption.size = Vector2(maxf(0.0, content_width - 16.0), 32.0)
	_map_caption.add_theme_font_size_override("font_size", 18 if content_width >= 440.0 else 15)
	for level_id in range(1, total_levels + 1):
		var tile: LevelTile = _tiles.get(level_id)
		if not is_instance_valid(tile):
			continue
		var chapter := floori(float(level_id - 1) / 12.0)
		var phase := -PI * 0.5 + float(level_id - 1) * PI / 4.4
		var center := Vector2(content_width * 0.5 + sin(phase) * amplitude,
			top_space + float(total_levels - level_id) * step_height + float(chapter_count - chapter) * chapter_gap + tile_side * 0.5)
		tile.position = center - Vector2.ONE * tile_side * 0.5
		tile.size = Vector2.ONE * tile_side
		tile.refresh()
		_route.points.append(center)
	_route.queue_redraw()
	_position_marker()


func _position_marker() -> void:
	var tile: LevelTile = _tiles.get(selected_level)
	if not is_instance_valid(tile) or not is_instance_valid(_marker):
		return
	_marker.size = Vector2(48.0, 48.0)
	_marker.position = Vector2(tile.position.x + tile.size.x * 0.5 - 24.0, tile.position.y - 48.0)


func _select_level(level_id: int) -> void:
	if level_id < 1 or level_id > _unlocked_level:
		return
	selected_level = level_id
	_description_text = ""
	_refresh_selection()
	level_selected.emit(selected_level)
	_schedule_reveal()


func _refresh_selection() -> void:
	if not is_instance_valid(_start):
		return
	for level_id in _tiles:
		var tile: LevelTile = _tiles[level_id]
		tile.selected = int(level_id) == selected_level
		tile.refresh()
	_progress.text = "已通关 %d / %d" % [highest_completed, total_levels]
	_start.text = "开始第 %d 关" % selected_level
	_position_marker()
	_refresh_description()


func _refresh_description() -> void:
	if not is_instance_valid(_description):
		return
	if not _description_text.is_empty():
		_description.text = _description_text
	elif selected_level <= highest_completed:
		_description.text = "第 %d 关 · 已通关，可以再次挑战" % selected_level
	elif selected_level == total_levels:
		_description.text = "第 %d 关 · 挑战最后一关，点亮整张地图" % selected_level
	else:
		_description.text = "第 %d 关 · 通过后解锁下一关" % selected_level
	_description.tooltip_text = _description.text


func _start_selected_level() -> void:
	if selected_level >= 1 and selected_level <= _unlocked_level:
		level_started.emit(selected_level)


func _on_tile_focused(level_id: int) -> void:
	if not _programmatic_focus:
		_reveal_level = level_id
		_schedule_reveal()


func _schedule_reveal(focus_selected: bool = false, center_selected: bool = false, animate_upward: bool = false) -> void:
	_focus_on_reveal = _focus_on_reveal or focus_selected
	_center_on_reveal = _center_on_reveal or center_selected
	_animate_on_reveal = _animate_on_reveal or animate_upward
	if _reveal_queued or not is_inside_tree():
		return
	_reveal_queued = true
	_reveal_selection.call_deferred()


func _reveal_selection() -> void:
	# A frame lets ScrollContainer apply its child's new minimum height first.
	var manual_epoch := _manual_scroll_epoch
	if not is_inside_tree():
		_reveal_queued = false
		_focus_on_reveal = false
		return
	await get_tree().process_frame
	_reveal_queued = false
	if not is_visible_in_tree() or manual_epoch != _manual_scroll_epoch:
		_focus_on_reveal = false
		_center_on_reveal = false
		_animate_on_reveal = false
		_reveal_level = 0
		return
	var level_id := _reveal_level if _reveal_level > 0 and not _center_on_reveal else selected_level
	_reveal_level = 0
	var tile: LevelTile = _tiles.get(level_id)
	if not is_instance_valid(tile):
		_focus_on_reveal = false
		_center_on_reveal = false
		_animate_on_reveal = false
		return
	var viewport_height := _scroll.size.y
	var visible_top := float(_scroll.scroll_vertical)
	var target := visible_top
	if _center_on_reveal:
		target = tile.position.y + tile.size.y * 0.5 - viewport_height * 0.66
	elif tile.position.y - 56.0 < visible_top + 12.0:
		target = tile.position.y - 68.0
	elif tile.position.y + tile.size.y + 16.0 > visible_top + viewport_height:
		target = tile.position.y + tile.size.y + 24.0 - viewport_height
	var scroll_bar := _scroll.get_v_scroll_bar()
	var maximum := maxf(0.0, scroll_bar.max_value - scroll_bar.page)
	target = clampf(target, 0.0, maximum)
	var animate := _animate_on_reveal and not _reduced_motion and target < visible_top - 2.0
	_cancel_scroll_animation()
	if animate:
		# Returning from a completed level shows a short climb. An old manual
		# scroll position must never cause a tour through thousands of pixels.
		if visible_top - target > viewport_height * 0.85:
			_scroll.scroll_vertical = int(minf(maximum, target + viewport_height * 0.45))
		_scroll_tween = create_tween()
		_scroll_tween.tween_property(_scroll, "scroll_vertical", int(target), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_scroll.scroll_vertical = int(target)
	if _focus_on_reveal:
		_programmatic_focus = true
		tile.grab_focus()
		_programmatic_focus = false
	_focus_on_reveal = false
	_center_on_reveal = false
