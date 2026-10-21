extends Control

## A canvas modal keeps Android dialogs inside the game's safe area. Button
## activation remains native, with the non-destructive choice focused first.
signal confirmed
signal canceled

const PanelArt := preload("res://scripts/ui/casual_panel_art.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const L10n := preload("res://scripts/localization/game_locale.gd")

class ActionIcon:
	extends Control
	var kind: String = "exit":
		set(value):
			kind = value
			queue_redraw()

	func _draw() -> void:
		var side := minf(size.x, size.y) * 0.86
		PanelArt.draw_icon(self, kind, Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side), Color.WHITE)

class CloseButton:
	extends Button

	func _draw() -> void:
		var side := minf(size.x, size.y) * 0.46
		var tint := Color("#ddebff") if not is_hovered() else Color.WHITE
		PanelArt.draw_icon(self, "close", Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side), tint)

var title: String = "确认离开":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = value
var dialog_text: String = "离开后，本局棋盘不会保存。":
	set(value):
		dialog_text = value
		if _body_label != null:
			_body_label.text = value
		_schedule_layout()
var ok_button_text: String = "确定离开":
	set(value):
		ok_button_text = value
		if _ok_button != null:
			_ok_button.text = value
var cancel_button_text: String = "继续游戏":
	set(value):
		cancel_button_text = value
		if _cancel_button != null:
			_cancel_button.text = value
var icon_kind: String = "exit":
	set(value):
		icon_kind = value
		if _action_icon != null:
			_action_icon.kind = "exit" if value == "quit" else value
# Kept for the former ConfirmationDialog call sites. The content determines
# height so a legacy 170 px minimum cannot clip the two large action buttons.
var min_size: Vector2i = Vector2i(400, 170)
var dialog_autowrap: bool = true

var _panel: Panel
var _title_label: Label
var _close_button: CloseButton
var _scroll: ScrollContainer
var _inner: PanelContainer
var _margins: MarginContainer
var _content: VBoxContainer
var _body_row: HBoxContainer
var _action_icon: ActionIcon
var _body_label: Label
var _cancel_button: Button
var _ok_button: Button
var _resolved := true
var _open_sequence := 0
var _requested_size := Vector2i.ZERO
var _layout_queued := false
var _navigation_focus := false
var _focus_styles: Array[StyleBox] = []
var _touch_focus_style := StyleBoxEmpty.new()


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_built()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_schedule_layout)
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_close_button):
		_close_button.tooltip_text = L10n.t("取消，继续游戏")
		_schedule_layout()


func _ensure_built() -> void:
	if _panel != null:
		return
	theme = Theme.new()
	theme.set_color("font_color", "Label", Color("#f8fcff"))
	theme.set_color("font_shadow_color", "Label", Color(0.06, 0.10, 0.27, 0.30))
	theme.set_constant("shadow_offset_y", "Label", 1)
	_panel = Panel.new()
	_panel.name = "ConfirmationCard"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_title_label = Label.new()
	_title_label.text = L10n.t(title)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_title_label)
	_close_button = CloseButton.new()
	_close_button.name = "Close"
	_close_button.tooltip_text = L10n.t("取消，继续游戏")
	_close_button.pressed.connect(_cancel)
	_panel.add_child(_close_button)
	_scroll = ScrollContainer.new()
	_scroll.name = "SafeContent"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	_panel.add_child(_scroll)
	_inner = PanelContainer.new()
	_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_inner)
	_margins = MarginContainer.new()
	_inner.add_child(_margins)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margins.add_child(_content)
	_body_row = HBoxContainer.new()
	_content.add_child(_body_row)
	_action_icon = ActionIcon.new()
	_action_icon.kind = icon_kind
	_action_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_row.add_child(_action_icon)
	_body_label = Label.new()
	_body_label.text = L10n.t(dialog_text)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_row.add_child(_body_label)
	_cancel_button = Button.new()
	_cancel_button.name = "Continue"
	_cancel_button.text = L10n.t(cancel_button_text)
	_cancel_button.pressed.connect(_cancel)
	_content.add_child(_cancel_button)
	_ok_button = Button.new()
	_ok_button.name = "Confirm"
	_ok_button.text = L10n.t(ok_button_text)
	_ok_button.pressed.connect(_confirm)
	_content.add_child(_ok_button)
	for button: Button in [_cancel_button, _ok_button, _close_button]:
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Both choices stay reachable when a short screen requires scrolling.
	_cancel_button.focus_neighbor_bottom = _cancel_button.get_path_to(_ok_button)
	_cancel_button.focus_neighbor_top = _cancel_button.get_path_to(_ok_button)
	_ok_button.focus_neighbor_bottom = _ok_button.get_path_to(_cancel_button)
	_ok_button.focus_neighbor_top = _ok_button.get_path_to(_cancel_button)
	_cancel_button.focus_neighbor_left = _cancel_button.get_path_to(_ok_button)
	_cancel_button.focus_neighbor_right = _cancel_button.get_path_to(_ok_button)
	_ok_button.focus_neighbor_left = _ok_button.get_path_to(_cancel_button)
	_ok_button.focus_neighbor_right = _ok_button.get_path_to(_cancel_button)
	_close_button.focus_neighbor_top = _close_button.get_path_to(_cancel_button)
	_close_button.focus_neighbor_bottom = _close_button.get_path_to(_cancel_button)
	_close_button.focus_neighbor_left = _close_button.get_path_to(_cancel_button)
	_close_button.focus_neighbor_right = _close_button.get_path_to(_cancel_button)
	_cancel_button.focus_next = _cancel_button.get_path_to(_ok_button)
	_ok_button.focus_next = _ok_button.get_path_to(_close_button)
	_close_button.focus_next = _close_button.get_path_to(_cancel_button)
	_cancel_button.focus_previous = _cancel_button.get_path_to(_close_button)
	_ok_button.focus_previous = _ok_button.get_path_to(_cancel_button)
	_close_button.focus_previous = _close_button.get_path_to(_ok_button)


func popup_centered(requested: Vector2i = Vector2i.ZERO) -> void:
	_requested_size = requested
	_resolved = false
	_open_sequence += 1
	visible = true
	_layout()
	_scroll.scroll_vertical = 0
	_focus_cancel.call_deferred(_open_sequence)
	queue_redraw()


func show_action(action: String) -> void:
	icon_kind = "exit" if action == "quit" else ("home" if action == "menu" else action)


func get_ok_button() -> Button:
	_ensure_built()
	return _ok_button


func get_cancel_button() -> Button:
	_ensure_built()
	return _cancel_button


func get_label() -> Label:
	_ensure_built()
	return _body_label


func _schedule_layout() -> void:
	if not is_inside_tree() or _layout_queued:
		return
	_layout_queued = true
	_layout.call_deferred()


func _layout() -> void:
	_layout_queued = false
	if not is_inside_tree() or _panel == null:
		return
	var unit := MobileLayout.dp(self, 1.0)
	var safe := MobileLayout.safe_content_rect(self)
	var padding := 16.0 * unit
	var available := Rect2(safe.position + Vector2.ONE * padding, (safe.size - Vector2.ONE * padding * 2.0).max(Vector2.ONE))
	var width := minf(available.size.x, 420.0 * unit if MobileLayout.is_mobile() else 448.0)
	if not MobileLayout.is_mobile() and _requested_size.x >= 400:
		width = minf(available.size.x, clampf(float(_requested_size.x), 420.0, 480.0))
	var body_width := maxf(1.0, width - 144.0 * unit)
	# Reserve enough wrapped text height without making long translations force
	# the card beyond the safe area. The ScrollContainer handles the remainder.
	var estimated_lines := 0
	for line: String in dialog_text.split("\n"):
		estimated_lines += maxi(1, ceili(float(line.length()) * 16.0 * unit / body_width))
	var body_height := maxf(76.0, float(estimated_lines) * 22.0) * unit
	# Independently rounded container margins and font minimums can exceed this
	# estimate by a few physical pixels. Leave 12 dp breathing room so a full
	# height scrollbar is not shown for an otherwise comfortably fitting card.
	var natural_height := (64.0 + 16.0 + 32.0 + 104.0 + 24.0 + 12.0) * unit + body_height
	var height := minf(available.size.y, natural_height)
	_panel.position = available.get_center() - Vector2(width, height) * 0.5
	_panel.size = Vector2(width, height)
	_panel.add_theme_stylebox_override("panel", PanelArt.panel_style(unit))
	_title_label.position = Vector2(54.0, 10.0) * unit
	_title_label.size = Vector2(maxf(1.0, width - 108.0 * unit), 44.0 * unit)
	_title_label.add_theme_font_size_override("font_size", L10n.fitted_size(_title_label.get_theme_font("font"), _title_label.text, _title_label.size.x, roundi(24.0 * unit), roundi(14.0 * unit)))
	_close_button.position = Vector2(width - 54.0 * unit, 8.0 * unit)
	_close_button.size = Vector2.ONE * 48.0 * unit
	PanelArt.style_action(_close_button, unit, "secondary")
	var clear_style := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		_close_button.add_theme_stylebox_override(state, clear_style)
	_scroll.position = Vector2(14.0, 64.0) * unit
	_scroll.size = Vector2(maxf(1.0, width - 28.0 * unit), maxf(1.0, height - 80.0 * unit))
	var inner_style := PanelArt.inner_style(unit)
	inner_style.set_content_margin_all(0.0)
	_inner.add_theme_stylebox_override("panel", inner_style)
	for edge: String in ["left", "right", "top", "bottom"]:
		_margins.add_theme_constant_override("margin_" + edge, roundi(16.0 * unit))
	_content.add_theme_constant_override("separation", roundi(12.0 * unit))
	_body_row.add_theme_constant_override("separation", roundi(14.0 * unit))
	_body_row.custom_minimum_size.y = body_height
	_action_icon.custom_minimum_size = Vector2(58.0, 64.0) * unit
	_body_label.add_theme_font_size_override("font_size", roundi(16.0 * unit))
	for button: Button in [_cancel_button, _ok_button]:
		button.custom_minimum_size = Vector2(0.0, 52.0 * unit)
		button.add_theme_font_size_override("font_size", roundi(19.0 * unit))
	PanelArt.style_action(_cancel_button, unit, "green")
	PanelArt.style_action(_ok_button, unit, "danger")
	for button: Button in [_cancel_button, _ok_button]:
		L10n.fit_button(button, roundi(19.0 * unit), roundi(12.0 * unit))
	_focus_styles.clear()
	for button: Button in [_cancel_button, _ok_button, _close_button]:
		_focus_styles.append(button.get_theme_stylebox("focus"))
	_apply_focus_visibility()
	queue_redraw()


func _focus_cancel(sequence: int) -> void:
	if visible and not _resolved and sequence == _open_sequence:
		_cancel_button.grab_focus()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.12, 0.74))


func _input(event: InputEvent) -> void:
	if not MobileLayout.is_mobile():
		return
	# Keep tracking the last input even while hidden, so opening the card with a
	# keyboard already shows its safe default. Native focus itself is retained
	# for touch users; only its painted outline changes with the input method.
	var navigation := _navigation_focus
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton:
		navigation = false
	elif event is InputEventKey and event.pressed:
		navigation = true
	elif event is InputEventJoypadButton and event.pressed:
		navigation = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		navigation = true
	if navigation != _navigation_focus:
		_navigation_focus = navigation
		_apply_focus_visibility()


func _apply_focus_visibility() -> void:
	var buttons: Array[Button] = [_cancel_button, _ok_button, _close_button]
	if _focus_styles.size() != buttons.size():
		return
	var show_focus := not MobileLayout.is_mobile() or _navigation_focus
	for index in range(buttons.size()):
		buttons[index].add_theme_stylebox_override("focus", _focus_styles[index] if show_focus else _touch_focus_style)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel()


func _confirm() -> void:
	if not visible or _resolved:
		return
	_resolved = true
	hide()
	confirmed.emit()


func _cancel() -> void:
	if not visible or _resolved:
		return
	_resolved = true
	hide()
	canceled.emit()
