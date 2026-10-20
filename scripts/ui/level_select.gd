extends Control

## Native, scrollable adventure map. Concrete objectives are shown in-game.
const Art := preload("res://scripts/ui/block_art.gd")
const IconButton := preload("res://scripts/ui/art_icon_button.gd")
const UnlockEffect := preload("res://scripts/ui/level_unlock_effect.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

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
var _marker: GoldDiamond
var _trophy: Control
var _map_caption: Label
var _start: Button
var _save_warning: Label
var _save_status := ""
var _tiles: Dictionary = {}
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
var _unlock_effect: Control
var _unlock_source: int = 0
var _unlock_destination: int = 0
var _unlock_running := false
var _unlock_waiting := false
var _unlock_epoch := 0


class GoldDiamond extends Control:

	var reduced_motion: bool = false
	var bob_amplitude: float = 3.0
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
		var bob := 0.0 if reduced_motion else sin(_phase) * bob_amplitude
		var center := Vector2(size.x * 0.5, 13.0 + bob)
		for radius in [15.0, 12.0, 9.0]:
			draw_circle(center, radius, Color(1.0, 0.82, 0.23, 0.035))
		draw_set_transform(Vector2(size.x * 0.5, size.y - 3.0), 0.0, Vector2(1.0, 0.22))
		draw_circle(Vector2.ZERO, 7.0 - bob * 0.16, Color(0.03, 0.08, 0.17, 0.27))
		draw_set_transform(center, 0.0 if reduced_motion else sin(_phase * 0.5) * 0.055)
		var top := Vector2(0.0, -9.5)
		var right := Vector2(11.0, -2.0)
		var bottom := Vector2(0.0, 11.2)
		var left := Vector2(-11.0, -2.0)
		draw_colored_polygon(PackedVector2Array([top, right, Vector2(0.0, 2.8), left]), Color("#ffe986"))
		draw_colored_polygon(PackedVector2Array([left, Vector2(0.0, 2.8), bottom]), Color("#f4ba37"))
		draw_colored_polygon(PackedVector2Array([Vector2(0.0, 2.8), right, bottom]), Color("#cc8b24"))
		draw_polyline(PackedVector2Array([left, top, right]), Color("#fff6c2"), 1.5, true)
		draw_set_transform(Vector2.ZERO)


class LevelTile extends Button:

	const TileArt := preload("res://scripts/ui/block_art.gd")

	var level_id: int = 1
	var completed: bool = false
	var selected: bool = false
	var visual_side: float = 32.0
	var _number: Label
	var _presentation_color := Color.TRANSPARENT
	var _presentation_number_color := Color.TRANSPARENT
	var _presentation_scale := 1.0
	var _presentation_flash := 0.0
	var _presentation_active := false

	func _ready() -> void:
		custom_minimum_size = Vector2(32.0, 32.0)
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
			_number.add_theme_font_size_override("font_size", clampi(roundi(visual_side * 0.45), 13, 36 if OS.has_feature("android") else 16))
			_number.add_theme_color_override("font_color", Color("#273451") if selected else (Color("#efffff") if completed else Color("#91a6ce")))
			if _presentation_active:
				_number.add_theme_color_override("font_color", _presentation_number_color)
			_number.pivot_offset = size * 0.5
			_number.scale = Vector2.ONE * _presentation_scale
		queue_redraw()

	func set_presentation(color: Color, number_color: Color, scale_factor: float = 1.0, flash: float = 0.0) -> void:
		_presentation_active = true
		_presentation_color = color
		_presentation_number_color = number_color
		_presentation_scale = scale_factor
		_presentation_flash = flash
		refresh()

	func reset_presentation() -> void:
		_presentation_active = false
		_presentation_scale = 1.0
		_presentation_flash = 0.0
		refresh()

	func _draw() -> void:
		var color := Color("#263c68")
		if selected:
			color = Color("#ffd154")
		elif completed:
			color = Color("#31bddc")
		elif not disabled:
			color = Color("#4f83ce")
		if _presentation_active:
			color = _presentation_color.lerp(Color.WHITE, _presentation_flash * 0.55)
		if is_pressed() and not disabled:
			color = color.darkened(0.08)
		# A compact drawing retains a comfortable native hit target around it.
		var side := minf(visual_side, minf(size.x, size.y)) * _presentation_scale
		var rect := Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)
		TileArt.draw_block(self, rect, color, 0.76 if disabled else 1.0, 0.12 if is_hovered() and not disabled else 0.0)
		if selected and not _presentation_active:
			draw_rect(rect.grow(1.0), Color("#fff2ac"), false, 2.0)
		if has_focus() and not _presentation_active:
			# An outline cannot tint the fill, unlike a translucent focus panel.
			draw_rect(rect.grow(2.5), Color("#82f5e9"), false, 1.6)


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
	_cancel_unlock_animation()
	_cancel_scroll_animation()
	total_levels = maxi(1, level_count)
	highest_completed = clampi(completed_count, 0, total_levels)
	_unlocked_level = mini(total_levels, highest_completed + 1)
	selected_level = _unlocked_level if initial_selection <= 0 else clampi(initial_selection, 1, _unlocked_level)
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


func activate(completed_level: int = 0, newly_unlocked_level: int = 0) -> void:
	_cancel_unlock_animation()
	var animate_upward := _last_activated_level > 0 and _unlocked_level > _last_activated_level
	select_latest()
	if not _reduced_motion and completed_level >= 1 and completed_level <= highest_completed and newly_unlocked_level == _unlocked_level and newly_unlocked_level == completed_level + 1:
		_unlock_source = completed_level
		_unlock_destination = newly_unlocked_level
		_prepare_unlock_visuals()
	_schedule_reveal(true, true, animate_upward)
	_last_activated_level = selected_level


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if is_instance_valid(_marker):
		_marker.set_reduced_motion(enabled)
	if enabled:
		_cancel_unlock_animation()
		_cancel_scroll_animation()


func _exit_tree() -> void:
	_cancel_unlock_animation()
	_cancel_scroll_animation()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_cancel_unlock_animation()
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
		_cancel_unlock_animation()
		_cancel_scroll_animation()


func _cancel_scroll_animation() -> void:
	if is_instance_valid(_scroll_tween):
		_scroll_tween.kill()
	_scroll_tween = null
	_animate_on_reveal = false


func _build_controls() -> void:
	_header = Panel.new()
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.add_theme_stylebox_override("panel", Art.panel_style(Color("#4e66c1"), 0, Color("#6c88d6")))
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
	_trophy = TrophyArt.new()
	_trophy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(_trophy)
	_map_caption = _label(18, Color("#c8e9ff"))
	_map_caption.text = "逐关挑战，点亮你的方块地图"
	_map.add_child(_map_caption)
	_marker = GoldDiamond.new()
	_marker.name = "SelectedLevelMarker"
	_marker.z_index = 2
	_marker.set_reduced_motion(_reduced_motion)
	_map.add_child(_marker)
	_footer = Panel.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_STOP
	_footer.add_theme_stylebox_override("panel", Art.panel_style(Color("#4e66c1"), 0, Color("#6c88d6")))
	add_child(_footer)
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
	_unlock_effect = UnlockEffect.new()
	_unlock_effect.name = "LevelUnlockEffect"
	_unlock_effect.z_index = 8
	_unlock_effect.frame_changed.connect(_on_unlock_frame)
	_unlock_effect.finished.connect(_cancel_unlock_animation)
	add_child(_unlock_effect)


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
	_layout_map()


func _layout_controls() -> void:
	if not is_instance_valid(_header):
		return
	_cancel_unlock_animation()
	_unlock_effect.position = Vector2.ZERO
	_unlock_effect.size = size
	if MobileLayout.is_mobile():
		_layout_mobile_controls()
		_layout_map()
		return
	var header_height := 104.0
	var footer_height := 104.0
	_header.position = Vector2.ZERO
	_header.size = Vector2(size.x, header_height)
	_back.position = Vector2(24.0, 20.0)
	_back.size = Vector2(52.0, 52.0)
	_back.set("frameless", false)
	_back.set("icon_scale", 0.55)
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
	var button_width := minf(600.0, maxf(48.0, size.x - 64.0))
	_start.position = Vector2((size.x - button_width) * 0.5, 18.0)
	_start.size = Vector2(button_width, 58.0)
	_save_warning.position = Vector2(24.0, 82.0)
	_save_warning.size = Vector2(maxf(0.0, size.x - 48.0), 18.0)
	_layout_map()

func _layout_mobile_controls() -> void:
	var area := MobileLayout.safe_content_rect(self)
	var unit := MobileLayout.dp(self, 1.0)
	var target := MobileLayout.touch_target(self)
	var header_height := 84.0 * unit
	var footer_height := 96.0 * unit
	_header.position = area.position
	_header.size = Vector2(area.size.x, header_height)
	_back.position = Vector2(8.0, 8.0) * unit
	_back.size = Vector2.ONE * target
	_back.set("frameless", true)
	_back.set("icon_scale", 0.48)
	_title.position = Vector2(64.0, 12.0) * unit
	_title.size = Vector2(maxf(1.0, area.size.x - 128.0 * unit), 40.0 * unit)
	_title.add_theme_font_size_override("font_size", roundi(26.0 * unit))
	_progress.position = Vector2(64.0, 56.0) * unit
	_progress.size = Vector2(maxf(1.0, area.size.x - 128.0 * unit), 20.0 * unit)
	_progress.add_theme_font_size_override("font_size", roundi(13.0 * unit))
	_scroll.position = area.position + Vector2(8.0 * unit, header_height + 8.0 * unit)
	_scroll.size = Vector2(maxf(1.0, area.size.x - 16.0 * unit), maxf(1.0, area.size.y - header_height - footer_height - 16.0 * unit))
	_footer.position = Vector2(area.position.x, area.end.y - footer_height)
	_footer.size = Vector2(area.size.x, footer_height)
	var button_width := minf(280.0 * unit, maxf(1.0, area.size.x * 0.66))
	_start.position = Vector2((area.size.x - button_width) * 0.5, 16.0 * unit)
	_start.size = Vector2(button_width, maxf(target, 56.0 * unit))
	_start.add_theme_font_size_override("font_size", roundi(23.0 * unit))
	_save_warning.position = Vector2(12.0, 76.0) * unit
	_save_warning.size = Vector2(area.size.x - 24.0 * unit, 18.0 * unit)
	_save_warning.add_theme_font_size_override("font_size", roundi(11.0 * unit))


func _layout_map() -> void:
	if not is_instance_valid(_map):
		return
	# Restore the original ascending block tower, with compact square cells.
	# Reserve scrollbar space so its appearance cannot clip the last column.
	var content_width := maxf(56.0, _scroll.size.x - 24.0)
	var available_width := minf(440.0, maxf(32.0, content_width - 24.0))
	var gap := 4.0
	var minimum_side := 32.0
	var maximum_side := 36.0
	if MobileLayout.is_mobile():
		available_width = maxf(1.0, content_width - MobileLayout.dp(self, 16.0))
		gap = MobileLayout.dp(self, 1.5)
		minimum_side = MobileLayout.dp(self, 28.0)
		maximum_side = MobileLayout.dp(self, 32.0)
	var columns := clampi(int((available_width + gap) / (minimum_side + gap * 2.0)), 1, 11)
	if MobileLayout.is_mobile():
		columns = clampi(int((available_width + gap) / (minimum_side + gap)), 1, 11)
	var tile_side := clampf(floorf((available_width - float(columns - 1) * gap) / float(columns)), minimum_side, maximum_side)
	var pitch := tile_side + gap
	var map_width := float(columns) * pitch - gap
	var proportions := [1.0, 0.82, 0.73, 0.55, 0.55, 0.64, 0.73, 0.82, 0.73, 0.64, 0.55, 0.73, 0.64, 0.55, 0.36]
	var rows: Array[Dictionary] = []
	var first_level := 1
	while first_level <= total_levels:
		var row_index := rows.size()
		var row_capacity := clampi(roundi(float(columns) * float(proportions[row_index % proportions.size()])), mini(3, columns), columns)
		var count := mini(row_capacity, total_levels - first_level + 1)
		rows.append({"first": first_level, "count": count})
		first_level += count
	_trophy.position = Vector2((content_width - 124.0) * 0.5, 14.0)
	_trophy.size = Vector2(124.0, 124.0)
	_map_caption.position = Vector2(8.0, 142.0)
	_map_caption.size = Vector2(maxf(0.0, content_width - 16.0), 32.0)
	_map_caption.add_theme_font_size_override("font_size", 18 if content_width >= 440.0 else 15)
	if MobileLayout.is_mobile():
		_map_caption.add_theme_font_size_override("font_size", roundi(MobileLayout.dp(self, 14.0)))
	var top_space := 190.0
	if MobileLayout.is_mobile():
		# The larger floating badge needs its own space below the map caption.
		top_space = maxf(top_space, _map_caption.position.y + _map_caption.size.y + MobileLayout.dp(self, 24.0))
	var map_height := top_space + float(rows.size()) * pitch + 28.0
	_map.custom_minimum_size = Vector2(0.0, map_height)
	var left := (content_width - map_width) * 0.5
	for row_index in range(rows.size()):
		var row: Dictionary = rows[row_index]
		var count := int(row["count"])
		var free_columns := columns - count
		var stagger := 1 if row_index % 4 == 2 else 0
		var offset_columns := clampi(floori(float(free_columns) * 0.5) + stagger, 0, free_columns)
		var y := top_space + float(rows.size() - row_index - 1) * pitch
		for index in range(count):
			var tile: LevelTile = _tiles.get(int(row["first"]) + index)
			if not is_instance_valid(tile):
				continue
			tile.position = Vector2(left + float(offset_columns + index) * pitch, y)
			tile.size = Vector2.ONE * tile_side
			tile.visual_side = tile_side - 4.0
			tile.refresh()
	_position_marker()
	_schedule_reveal()


func _position_marker() -> void:
	var tile: LevelTile = _tiles.get(_unlock_source if _unlock_destination > 0 else selected_level)
	if not is_instance_valid(tile) or not is_instance_valid(_marker):
		return
	_marker.size = Vector2(34.0, 34.0)
	_marker.scale = _marker_layout_scale()
	_marker.bob_amplitude = 2.0 if MobileLayout.is_mobile() else 3.0
	_marker.position = _marker_position_for_tile(tile)
	_marker.queue_redraw()


func _marker_layout_scale() -> Vector2:
	if not MobileLayout.is_mobile():
		return Vector2.ONE * 0.65
	var horizontal := MobileLayout.dp(self, 28.0) / 22.0
	# A broad, low pyramid fits the band between adjacent level numbers.
	return Vector2(horizontal, horizontal * 0.53)


func _marker_position_for_tile(tile: LevelTile) -> Vector2:
	var marker_scale := _marker_layout_scale()
	var x := tile.position.x + tile.size.x * 0.5 - 17.0 * marker_scale.x
	if not MobileLayout.is_mobile():
		return Vector2(x, tile.position.y - 12.0)
	var face_top := tile.position.y + (tile.size.y - tile.visual_side) * 0.5
	# The diamond's neutral tip is local y=24.2. Keep it at the upper edge,
	# above the selected number, even as density changes its visible size.
	return Vector2(x, face_top + MobileLayout.dp(self, 5.0) - 24.2 * marker_scale.y)


func _prepare_unlock_visuals() -> void:
	var source: LevelTile = _tiles.get(_unlock_source)
	var destination: LevelTile = _tiles.get(_unlock_destination)
	if not is_instance_valid(source) or not is_instance_valid(destination):
		_cancel_unlock_animation()
		return
	source.set_presentation(Color("#ffd154"), Color("#273451"))
	destination.set_presentation(Color("#263c68"), Color("#91a6ce"))
	_position_marker()


func _begin_unlock_animation() -> void:
	if _unlock_destination <= 0 or _unlock_running or _unlock_waiting:
		return
	# ScrollContainer applies its last scroll value during the next sort.
	# Read the tile's screen position only after that, and never revive a
	# sequence cancelled while this frame was pending.
	_unlock_waiting = true
	var epoch := _unlock_epoch
	await get_tree().process_frame
	if epoch != _unlock_epoch or not is_inside_tree():
		return
	_unlock_waiting = false
	if _reduced_motion or not is_visible_in_tree() or _scroll.size.y < 96.0:
		_cancel_unlock_animation()
		return
	var source: LevelTile = _tiles.get(_unlock_source)
	var destination: LevelTile = _tiles.get(_unlock_destination)
	if not is_instance_valid(source) or not is_instance_valid(destination):
		_cancel_unlock_animation()
		return
	var source_rect := _tile_view_rect(source)
	var destination_rect := _tile_view_rect(destination)
	if not _scroll.get_rect().encloses(source_rect) or not _scroll.get_rect().encloses(destination_rect):
		_cancel_unlock_animation()
		return
	_unlock_running = true
	_unlock_effect.play(_unlock_source, _unlock_destination, source_rect, destination_rect, _scroll.get_rect())


func _tile_view_rect(tile: LevelTile) -> Rect2:
	var origin := tile.get_global_rect().position - global_position
	return Rect2(origin + (tile.size - Vector2.ONE * tile.visual_side) * 0.5, Vector2.ONE * tile.visual_side)


func _on_unlock_frame(elapsed: float) -> void:
	if not _unlock_running:
		return
	var source: LevelTile = _tiles.get(_unlock_source)
	var destination: LevelTile = _tiles.get(_unlock_destination)
	if not is_instance_valid(source) or not is_instance_valid(destination):
		_cancel_unlock_animation()
		return
	var landing := clampf((elapsed - UnlockEffect.LAND_TIME) / 0.22, 0.0, 1.0)
	var unlocking := clampf((elapsed - UnlockEffect.UNLOCK_TIME) / 0.34, 0.0, 1.0)
	var source_color := Color("#ffd154").lerp(Color("#31bddc"), clampf(landing * 2.5, 0.0, 1.0))
	var source_text := Color("#273451").lerp(Color("#efffff"), landing)
	source.set_presentation(source_color, source_text, 1.0 + sin(landing * PI) * 0.14, sin(landing * PI) * 0.65)
	var destination_color := Color("#263c68").lerp(Color("#ffd154"), smoothstep(0.0, 1.0, unlocking))
	var destination_text := Color("#91a6ce").lerp(Color("#273451"), unlocking)
	destination.set_presentation(destination_color, destination_text, 1.0 + sin(unlocking * PI) * 0.20, sin(unlocking * PI) * 0.42)
	var start := _marker_position_for_tile(source)
	var finish := _marker_position_for_tile(destination)
	var hop := MobileLayout.dp(self, 12.0) if MobileLayout.is_mobile() else 20.0
	_marker.position = start.lerp(finish, smoothstep(0.0, 1.0, unlocking)) + Vector2(0.0, -sin(unlocking * PI) * hop)


func _cancel_unlock_animation() -> void:
	if _unlock_destination <= 0 and not _unlock_running and not _unlock_waiting:
		return
	_unlock_epoch += 1
	_unlock_waiting = false
	_unlock_running = false
	if is_instance_valid(_unlock_effect):
		_unlock_effect.cancel()
	for level_id in [_unlock_source, _unlock_destination]:
		var tile: LevelTile = _tiles.get(level_id)
		if is_instance_valid(tile):
			tile.reset_presentation()
	_unlock_source = 0
	_unlock_destination = 0
	_position_marker()


func _select_level(level_id: int) -> void:
	if level_id < 1 or level_id > _unlocked_level:
		return
	_cancel_unlock_animation()
	selected_level = level_id
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


func _start_selected_level() -> void:
	if selected_level >= 1 and selected_level <= _unlocked_level:
		_cancel_unlock_animation()
		level_started.emit(selected_level)


func _on_tile_focused(level_id: int) -> void:
	if not _programmatic_focus:
		_cancel_unlock_animation()
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
		_cancel_unlock_animation()
		_focus_on_reveal = false
		_center_on_reveal = false
		_animate_on_reveal = false
		_reveal_level = 0
		return
	var level_id := _reveal_level if _reveal_level > 0 and not _center_on_reveal else selected_level
	_reveal_level = 0
	var tile: LevelTile = _tiles.get(level_id)
	if not is_instance_valid(tile):
		_cancel_unlock_animation()
		_focus_on_reveal = false
		_center_on_reveal = false
		_animate_on_reveal = false
		return
	var viewport_height := _scroll.size.y
	var visible_top := float(_scroll.scroll_vertical)
	var target := visible_top
	var marker_top := _marker_position_for_tile(tile).y - 5.0 * _marker_layout_scale().y
	var padding := MobileLayout.dp(self, 8.0) if MobileLayout.is_mobile() else 12.0
	if _center_on_reveal:
		target = tile.position.y + tile.size.y * 0.5 - viewport_height * 0.66
	elif marker_top < visible_top + padding:
		target = marker_top - padding
	elif tile.position.y + tile.size.y + padding > visible_top + viewport_height:
		target = tile.position.y + tile.size.y + padding * 2.0 - viewport_height
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
		if _unlock_destination > 0:
			_scroll_tween.tween_callback(_begin_unlock_animation)
	else:
		_scroll.scroll_vertical = int(target)
		_begin_unlock_animation()
	if _focus_on_reveal:
		_programmatic_focus = true
		tile.grab_focus()
		_programmatic_focus = false
	_focus_on_reveal = false
	_center_on_reveal = false
