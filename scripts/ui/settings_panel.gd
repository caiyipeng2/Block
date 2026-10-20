extends Control

## Presentation only: Main owns persistence, pausing and destructive actions.
signal setting_changed(key: String, value: bool)
signal close_requested
signal preview_requested
signal restart_requested
signal menu_requested
signal quit_requested

const Art := preload("res://scripts/ui/casual_panel_art.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const TOP_SETTINGS := ["sound_enabled", "music_enabled", "screen_shake"]
const SETTING_NAMES := {"sound_enabled": "音效", "music_enabled": "背景音乐", "screen_shake": "画面震动", "reduced_motion": "减少动画"}
const SETTING_ICONS := {"sound_enabled": "sound", "music_enabled": "music", "screen_shake": "shake", "reduced_motion": "motion"}
const CHECKBUTTON_THEME_ICONS := ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "checked_mirrored", "unchecked_mirrored", "checked_disabled_mirrored", "unchecked_disabled_mirrored"]

var toggles: Dictionary = {}
var _buttons: Dictionary = {}
var _settings: Dictionary = {}
var _in_game := false
var _return_to_levels := false
var _save_warning := ""
var _panel_rect := Rect2()
var _unit := 1.0
var _outer: Panel
var _inner: Panel
var _title: Label
var _close: Button
var _scroll: ScrollContainer
var _content: VBoxContainer
var _top: HBoxContainer
var _separator: HSeparator
var _hint: Label
var _font: SystemFont
var _empty_icon: ImageTexture
var _focus_signature := -1
var _show_focus_outline := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	_font.font_weight = 600
	var empty := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	empty.fill(Color.TRANSPARENT)
	_empty_icon = ImageTexture.create_from_image(empty)
	_show_focus_outline = not MobileLayout.is_mobile()
	_build_controls()
	resized.connect(_layout_controls)
	visibility_changed.connect(_on_visibility_changed)
	_layout_controls()
	set_process(is_visible_in_tree())
	_refresh_focus_chain(true)


func _process(_delta: float) -> void:
	# BaseButton has no disabled_changed signal. A tiny visible-only state mask
	# also covers callers changing a returned button's disabled/visible property.
	_refresh_focus_chain()


func _input(event: InputEvent) -> void:
	if not MobileLayout.is_mobile():
		return
	# Record input modality while hidden too, so opening Settings with a physical
	# keyboard still shows focus. Never consume these events or change focus.
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_focus_outline_visible(false)
	elif event is InputEventKey and event.pressed:
		_set_focus_outline_visible(true)
	elif event is InputEventJoypadButton and event.pressed:
		_set_focus_outline_visible(true)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.35:
		_set_focus_outline_visible(true)


func _set_focus_outline_visible(show_outline: bool) -> void:
	if _show_focus_outline == show_outline:
		return
	_show_focus_outline = show_outline
	for button: Button in _focus_candidates():
		var focus: StyleBox = button.get_meta("keyboard_focus_style", null)
		if focus != null:
			_apply_focus_style(button, focus)


func _apply_focus_style(button: Button, keyboard_style: StyleBox) -> void:
	button.set_meta("keyboard_focus_style", keyboard_style)
	button.add_theme_stylebox_override("focus", keyboard_style if _show_focus_outline else StyleBoxEmpty.new())
	button.queue_redraw()


func apply_state(settings: Dictionary, in_game: bool, return_to_levels: bool, save_warning: String = "") -> void:
	_settings = settings.duplicate()
	_in_game = in_game
	_return_to_levels = return_to_levels
	_save_warning = save_warning
	if not is_instance_valid(_hint):
		return
	for key: String in toggles:
		var toggle: CheckButton = toggles[key]
		toggle.set_pressed_no_signal(bool(settings.get(key, key != "reduced_motion")))
		toggle.queue_redraw()
	_buttons["BackButton"].text = "返回游戏" if in_game else "返回菜单"
	_buttons["RestartButton"].visible = in_game
	_buttons["MenuButton"].visible = in_game
	_buttons["MenuButton"].text = "返回关卡" if return_to_levels else "返回菜单"
	_buttons["PreviewSoundButton"].disabled = not bool(settings.get("sound_enabled", true))
	_buttons["PreviewSoundButton"].tooltip_text = "试听一次消除音效" if bool(settings.get("sound_enabled", true)) else "开启音效后可以试听"
	_hint.text = "设置自动保存" if save_warning.is_empty() else save_warning
	_hint.add_theme_color_override("font_color", Color("#d4e2ff") if save_warning.is_empty() else Color("#ffe2a8"))
	_layout_controls()
	_refresh_focus_chain(true)


func get_action_button(action_name: String) -> Button:
	return _buttons.get(action_name)


func get_panel_rect() -> Rect2:
	return _panel_rect


func focus_primary() -> void:
	if not is_visible_in_tree():
		return
	_refresh_focus_chain(true)
	_scroll.scroll_vertical = 0
	for button: Button in _focus_candidates():
		if button.visible and not button.disabled:
			button.grab_focus()
			return


func _focus_candidates() -> Array[Button]:
	var candidates: Array[Button] = []
	for key: String in ["sound_enabled", "music_enabled", "screen_shake", "reduced_motion"]:
		var toggle: Button = toggles.get(key)
		if is_instance_valid(toggle):
			candidates.append(toggle)
	for action_name: String in ["BackButton", "RestartButton", "MenuButton", "PreviewSoundButton", "QuitButton", "CloseButton"]:
		var button: Button = _buttons.get(action_name)
		if is_instance_valid(button):
			candidates.append(button)
	return candidates


func _refresh_focus_chain(force: bool = false) -> void:
	var candidates := _focus_candidates()
	var eligible: Array[Button] = []
	var signature := 0
	for index in range(candidates.size()):
		var button: Button = candidates[index]
		if button.visible and not button.disabled:
			signature |= 1 << index
			eligible.append(button)
	if not force and signature == _focus_signature:
		return
	_focus_signature = signature
	if eligible.is_empty():
		return
	# Explicit relative paths keep Tab, Shift+Tab and all arrow searches inside
	# this modal instead of falling back to the still-visible game/menu below it.
	for index in range(eligible.size()):
		var button: Button = eligible[index]
		var previous: Button = eligible[posmod(index - 1, eligible.size())]
		var next: Button = eligible[(index + 1) % eligible.size()]
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(next)
		_set_directional_focus(button, previous, next, previous, next)
	var top_row: Array[Button] = []
	for key: String in TOP_SETTINGS:
		var button: Button = toggles.get(key)
		if eligible.has(button):
			top_row.append(button)
	var rows: Array[Button] = []
	for button: Button in eligible:
		if not top_row.has(button) and button != _close:
			rows.append(button)
	var first: Button = eligible[0]
	var last: Button = eligible[-1]
	var close: Button = _close if eligible.has(_close) else last
	var down_from_top: Button = rows[0] if not rows.is_empty() else close
	for index in range(top_row.size()):
		var button: Button = top_row[index]
		_set_directional_focus(button, close, down_from_top, top_row[posmod(index - 1, top_row.size())], top_row[(index + 1) % top_row.size()])
	for index in range(rows.size()):
		var button: Button = rows[index]
		var above: Button = rows[index - 1] if index > 0 else first
		var below: Button = rows[index + 1] if index + 1 < rows.size() else close
		_set_directional_focus(button, above, below, button, button)
	if eligible.has(_close):
		_set_directional_focus(_close, rows[-1] if not rows.is_empty() else first, first, first, first)
	var focused := get_viewport().gui_get_focus_owner()
	if is_visible_in_tree() and candidates.has(focused) and not eligible.has(focused):
		first.grab_focus()


func _set_directional_focus(button: Button, above: Button, below: Button, left: Button, right: Button) -> void:
	button.focus_neighbor_top = button.get_path_to(above)
	button.focus_neighbor_bottom = button.get_path_to(below)
	button.focus_neighbor_left = button.get_path_to(left)
	button.focus_neighbor_right = button.get_path_to(right)


func _build_controls() -> void:
	_outer = Panel.new()
	_outer.name = "OuterCard"
	_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_outer)
	_inner = Panel.new()
	_inner.name = "InnerCard"
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inner)
	_title = Label.new()
	_title.name = "Title"
	_title.text = "设置"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_override("font", _font)
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.add_theme_color_override("font_shadow_color", Color(0.08, 0.17, 0.40, 0.30))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_title)
	_close = Button.new()
	_close.name = "CloseButton"
	_close.tooltip_text = "关闭设置"
	_close.focus_mode = Control.FOCUS_ALL
	_close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close.pressed.connect(func(): close_requested.emit())
	_close.draw.connect(_draw_close)
	_connect_redraw(_close)
	add_child(_close)
	_buttons["CloseButton"] = _close
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_content)
	_top = HBoxContainer.new()
	_top.name = "QuickToggles"
	_content.add_child(_top)
	for key: String in TOP_SETTINGS:
		var toggle := _new_toggle(key)
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_top.add_child(toggle)
	_separator = HSeparator.new()
	_separator.name = "Separator"
	var separator_style := StyleBoxFlat.new()
	separator_style.bg_color = Color("#293a86")
	separator_style.content_margin_top = 1.0
	separator_style.content_margin_bottom = 1.0
	_separator.add_theme_stylebox_override("separator", separator_style)
	_content.add_child(_separator)
	_content.add_child(_new_toggle("reduced_motion"))
	_add_action("BackButton", "返回菜单", "play", func(): close_requested.emit())
	_add_action("RestartButton", "重新开始", "restart", func(): restart_requested.emit())
	_add_action("MenuButton", "返回菜单", "home", func(): menu_requested.emit())
	_add_action("PreviewSoundButton", "试听音效", "preview", func(): preview_requested.emit())
	_add_action("QuitButton", "退出游戏", "exit", func(): quit_requested.emit(), "secondary")
	_hint = Label.new()
	_hint.name = "SaveStatus"
	_hint.text = "设置自动保存"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_override("font", _font)
	_content.add_child(_hint)
	apply_state(_settings, _in_game, _return_to_levels, _save_warning)


func _new_toggle(key: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.name = key
	# Retain native CheckButton text and checked state for keyboard/accessibility;
	# its visible icon and lettering are drawn together with consistent spacing.
	toggle.text = SETTING_NAMES[key]
	toggle.tooltip_text = {
		"sound_enabled": "开启或关闭游戏音效",
		"music_enabled": "开启或关闭背景音乐",
		"screen_shake": "消除时棋盘轻震；减少动画开启后不会震动",
		"reduced_motion": "减少粒子、飞行和画面震动，保留清晰的结果提示",
	}[key]
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# CheckButton's theme uses checked/unchecked (not on/off). Override all LTR,
	# RTL and disabled states with a transparent 1px texture, retaining semantics.
	for icon_name: String in CHECKBUTTON_THEME_ICONS:
		toggle.add_theme_icon_override(icon_name, _empty_icon)
	for role in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		toggle.add_theme_color_override(role, Color.TRANSPARENT)
	toggle.draw.connect(_draw_toggle.bind(toggle, key))
	toggle.toggled.connect(_on_toggle.bind(key))
	_connect_redraw(toggle)
	toggles[key] = toggle
	return toggle


func _add_action(node_name: String, label: String, icon_kind: String, action: Callable, tone: String = "green") -> void:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.add_theme_font_override("font", _font)
	button.pressed.connect(action)
	button.draw.connect(_draw_action_icon.bind(button, icon_kind))
	button.set_meta("tone", tone)
	_connect_redraw(button)
	_content.add_child(button)
	_buttons[node_name] = button


func _connect_redraw(button: BaseButton) -> void:
	for redraw_signal in [button.mouse_entered, button.mouse_exited, button.focus_entered, button.focus_exited, button.button_down, button.button_up, button.resized]:
		redraw_signal.connect(button.queue_redraw)


func _on_toggle(value: bool, key: String) -> void:
	_settings[key] = value
	setting_changed.emit(key, value)
	for toggle: CheckButton in toggles.values():
		toggle.queue_redraw()


func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())
	if visible and is_node_ready():
		_scroll.scroll_vertical = 0
		_layout_controls()
		_refresh_focus_chain(true)


func _layout_controls() -> void:
	if not is_instance_valid(_outer):
		return
	var safe := MobileLayout.safe_content_rect(self)
	_unit = maxf(MobileLayout.dp(self, 1.0), 0.1)
	var margin := 14.0 * _unit
	var width := minf(480.0 * _unit, maxf(safe.size.x - margin * 2.0, 0.0))
	var header := 66.0 * _unit
	var action_height := maxf(54.0 * _unit, MobileLayout.touch_target(self))
	var top_height := 104.0 * _unit
	var gap := 10.0 * _unit
	var motion_height := maxf(62.0 * _unit, MobileLayout.touch_target(self))
	var hint_height := (42.0 if not _save_warning.is_empty() else 26.0) * _unit
	# Set children first, then ask the native containers for their real minimum.
	# Rounding dp, fonts, separators and invisible rows makes a hand-counted sum
	# slightly too short on high-density Android, causing a full-length scrollbar.
	_content.add_theme_constant_override("separation", maxi(roundi(gap), 1))
	_top.add_theme_constant_override("separation", maxi(roundi(5.0 * _unit), 1))
	_top.custom_minimum_size.y = top_height
	for key: String in TOP_SETTINGS:
		var toggle: CheckButton = toggles[key]
		toggle.custom_minimum_size = Vector2(MobileLayout.touch_target(self), top_height)
		_style_toggle(toggle)
	var motion: CheckButton = toggles["reduced_motion"]
	motion.custom_minimum_size.y = motion_height
	_style_toggle(motion)
	for action_name: String in _buttons:
		if action_name == "CloseButton":
			continue
		var button: Button = _buttons[action_name]
		button.custom_minimum_size = Vector2(0.0, action_height)
		Art.style_action(button, _unit, str(button.get_meta("tone", "green")))
		_apply_focus_style(button, button.get_theme_stylebox("focus"))
		button.queue_redraw()
	_hint.custom_minimum_size.y = hint_height
	_hint.add_theme_font_size_override("font_size", roundi(12.0 * _unit))
	_hint.add_theme_color_override("font_color", Color("#d4e2ff") if _save_warning.is_empty() else Color("#ffe2a8"))
	var content_minimum := ceilf(_content.get_combined_minimum_size().y)
	# 16dp outer bottom + 12dp inner top/bottom + 8dp rounding/visual clearance.
	var desired_height := header + 48.0 * _unit + content_minimum
	var height := minf(desired_height, maxf(safe.size.y - margin * 2.0, 0.0))
	_panel_rect = Rect2(safe.get_center() - Vector2(width, height) * 0.5, Vector2(width, height))
	_set_rect(_outer, _panel_rect)
	_outer.add_theme_stylebox_override("panel", Art.panel_style(_unit))
	var inner := Rect2(_panel_rect.position + Vector2(14.0 * _unit, header), Vector2(maxf(width - 28.0 * _unit, 0.0), maxf(height - header - 16.0 * _unit, 0.0)))
	_set_rect(_inner, inner)
	_inner.add_theme_stylebox_override("panel", Art.inner_style(_unit))
	var close_side := maxf(44.0 * _unit, MobileLayout.touch_target(self))
	_set_rect(_close, Rect2(_panel_rect.end.x - close_side - 9.0 * _unit, _panel_rect.position.y + 7.0 * _unit, close_side, close_side))
	_set_rect(_title, Rect2(_panel_rect.position.x + close_side + 8.0 * _unit, _panel_rect.position.y + 6.0 * _unit, maxf(width - close_side * 2.0 - 16.0 * _unit, 0.0), close_side + 4.0 * _unit))
	_title.add_theme_font_size_override("font_size", roundi(27.0 * _unit))
	_style_toggle(_close)
	_set_rect(_scroll, inner.grow(-12.0 * _unit))
	queue_redraw()


func _style_toggle(button: Button) -> void:
	var normal := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_stylebox_override("disabled", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.75, 0.85, 1.0, 0.07)
	hover.set_corner_radius_all(maxi(roundi(9.0 * _unit), 1))
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("hover_pressed", hover)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("#c9fff4")
	focus.set_corner_radius_all(maxi(roundi(9.0 * _unit), 1))
	focus.set_border_width_all(maxi(roundi(2.0 * _unit), 1))
	_apply_focus_style(button, focus)
	button.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.045, 0.11, 0.76))


func _draw_close() -> void:
	var side := minf(_close.size.x, _close.size.y) * 0.58
	Art.draw_icon(_close, "close", Rect2((_close.size - Vector2.ONE * side) * 0.5, Vector2.ONE * side), Color("#ecf5ff"))


func _draw_toggle(toggle: CheckButton, key: String) -> void:
	var on := toggle.button_pressed
	if key == "reduced_motion":
		_draw_motion_toggle(toggle, on)
		return
	var icon_side := 39.0 * _unit
	var icon_rect := Rect2((toggle.size.x - icon_side) * 0.5, 8.0 * _unit, icon_side, icon_side)
	var paused_shake := key == "screen_shake" and bool(_settings.get("reduced_motion", false)) and on
	Art.draw_icon(toggle, SETTING_ICONS[key], icon_rect, Color("#c6d3ec") if paused_shake else Color.WHITE)
	if not on:
		var from := icon_rect.position + Vector2(0.05, 0.95) * icon_side
		var to := icon_rect.position + Vector2(0.95, 0.05) * icon_side
		toggle.draw_line(from + Vector2(1.0, 1.0) * _unit, to + Vector2(1.0, 1.0) * _unit, Color(0.25, 0.04, 0.10, 0.45), 5.0 * _unit, true)
		toggle.draw_line(from, to, Color("#ff625d"), 3.5 * _unit, true)
	var title_rect := Rect2(0.0, 54.0 * _unit, toggle.size.x, 24.0 * _unit)
	_draw_text(toggle, SETTING_NAMES[key], title_rect, 15.0 * _unit, Color.WHITE)
	var status := "精简时暂停" if paused_shake else ("已开启" if on else "已关闭")
	_draw_text(toggle, status, Rect2(0.0, 79.0 * _unit, toggle.size.x, 19.0 * _unit), 11.0 * _unit, Color("#c4e9ff") if on else Color("#e6c7d1"))


func _draw_motion_toggle(toggle: CheckButton, on: bool) -> void:
	var icon_side := 29.0 * _unit
	Art.draw_icon(toggle, "motion", Rect2(7.0 * _unit, (toggle.size.y - icon_side) * 0.5, icon_side, icon_side), Color("#dceaff"))
	var switch_size := Vector2(44.0, 25.0) * _unit
	var switch_rect := Rect2(toggle.size.x - switch_size.x - 6.0 * _unit, (toggle.size.y - switch_size.y) * 0.5, switch_size.x, switch_size.y)
	var switch_style := StyleBoxFlat.new()
	switch_style.bg_color = Color("#35c83e") if on else Color("#7081bb")
	switch_style.set_corner_radius_all(maxi(roundi(switch_size.y * 0.5), 1))
	switch_style.anti_aliasing = true
	toggle.draw_style_box(switch_style, switch_rect)
	var handle_radius := switch_size.y * 0.36
	var handle_center := switch_rect.position + Vector2(switch_size.x - switch_size.y * 0.5 if on else switch_size.y * 0.5, switch_size.y * 0.5)
	toggle.draw_circle(handle_center, handle_radius, Color.WHITE, true, -1.0, true)
	var text_left := 47.0 * _unit
	var text_width := maxf(switch_rect.position.x - text_left - 7.0 * _unit, 0.0)
	_draw_text(toggle, "减少动画", Rect2(text_left, 7.0 * _unit, text_width, 25.0 * _unit), 16.0 * _unit, Color.WHITE, false)
	_draw_text(toggle, "减少粒子、飞行和震动", Rect2(text_left, 32.0 * _unit, text_width, 22.0 * _unit), 11.0 * _unit, Color("#c4d4f6"), false)


func _draw_action_icon(button: Button, icon_kind: String) -> void:
	var side := minf(29.0 * _unit, button.size.y * 0.54)
	var rect := Rect2(18.0 * _unit, (button.size.y - side) * 0.5 - 1.0 * _unit, side, side)
	var color := Color("#e1e7f4") if button.disabled else Color.WHITE
	Art.draw_icon(button, icon_kind, rect, color)


func _draw_text(canvas: CanvasItem, text: String, rect: Rect2, requested_size: float, color: Color, centered: bool = true) -> void:
	if not rect.has_area():
		return
	var font_size := maxi(roundi(requested_size), 1)
	while font_size > maxi(roundi(9.0 * _unit), 1) and _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > rect.size.x:
		font_size -= 1
	var text_width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var baseline := Vector2(rect.position.x + (rect.size.x - text_width) * 0.5 if centered else rect.position.x, rect.get_center().y + (_font.get_ascent(font_size) - _font.get_descent(font_size)) * 0.5)
	canvas.draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, font_size, color)


func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size.max(Vector2.ZERO)
