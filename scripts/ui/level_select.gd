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
	_layout_controls()
	_rebuild_tiles()
	_refresh_selection()


func configure(level_count: int, completed_count: int, initial_selection: int = 0) -> void:
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
	select_latest()
	_schedule_reveal(true)


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
	_scroll.follow_focus = true
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
		_map.add_child(tile)
		_tiles[level_id] = tile
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
	_schedule_reveal()


func _layout_map() -> void:
	if not is_instance_valid(_map):
		return
	# Rows grow upward from level 1, like a tower made of square blocks.
	# Reserve scrollbar space so a newly visible scrollbar cannot clip a tile.
	var content_width := maxf(52.0, _scroll.size.x - 24.0)
	var available_width := minf(704.0, maxf(52.0, content_width - 24.0))
	var columns := clampi(int((available_width + 4.0) / 52.0), 1, 11)
	var tile_side := clampf(floorf((available_width - float(columns - 1) * 4.0) / float(columns)), 48.0, 62.0)
	var pitch := tile_side + 4.0
	var map_width := float(columns) * pitch - 4.0
	var proportions := [1.0, 0.82, 0.73, 0.55, 0.55, 0.64, 0.73, 0.82, 0.73, 0.64, 0.55, 0.73, 0.64, 0.55, 0.36]
	var rows: Array = []
	var first_level := 1
	while first_level <= total_levels:
		var row_index := rows.size()
		var row_capacity := clampi(int(round(float(columns) * float(proportions[row_index % proportions.size()]))), mini(3, columns), columns)
		var count := mini(row_capacity, total_levels - first_level + 1)
		rows.append({"first": first_level, "count": count})
		first_level += count
	var top_space := 190.0
	var map_height := top_space + float(rows.size()) * pitch + 28.0
	_map.custom_minimum_size = Vector2(0.0, map_height)
	_trophy.position = Vector2((content_width - 124.0) * 0.5, 14.0)
	_trophy.size = Vector2(124.0, 124.0)
	_map_caption.position = Vector2(8.0, 142.0)
	_map_caption.size = Vector2(maxf(0.0, content_width - 16.0), 32.0)
	var left := (content_width - map_width) * 0.5
	for row_index in range(rows.size()):
		var row: Dictionary = rows[row_index]
		var count := int(row["count"])
		var free_columns := columns - count
		var stagger := 1 if row_index % 4 == 2 else 0
		var offset_columns := clampi(int(floor(float(free_columns) * 0.5)) + stagger, 0, free_columns)
		var y := top_space + float(rows.size() - row_index - 1) * pitch
		for index in range(count):
			var tile: LevelTile = _tiles.get(int(row["first"]) + index)
			if not is_instance_valid(tile):
				continue
			tile.position = Vector2(left + float(offset_columns + index) * pitch, y)
			tile.size = Vector2.ONE * tile_side
			tile.refresh()


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


func _schedule_reveal(focus_selected: bool = false) -> void:
	_focus_on_reveal = _focus_on_reveal or focus_selected
	if _reveal_queued or not is_inside_tree():
		return
	_reveal_queued = true
	_reveal_selection.call_deferred()


func _reveal_selection() -> void:
	# A frame lets ScrollContainer apply its child's new minimum height first.
	if not is_inside_tree():
		_reveal_queued = false
		_focus_on_reveal = false
		return
	await get_tree().process_frame
	_reveal_queued = false
	if not is_visible_in_tree():
		_focus_on_reveal = false
		return
	var tile: LevelTile = _tiles.get(selected_level)
	if not is_instance_valid(tile):
		return
	_scroll.ensure_control_visible(tile)
	if _focus_on_reveal:
		tile.grab_focus()
	_focus_on_reveal = false
