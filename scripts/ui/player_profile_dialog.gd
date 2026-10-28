extends Control

## Parent saves the draft, then calls close_dialog or show_error.
signal profile_saved(nickname: String, avatar: int)
signal close_requested

const Art := preload("res://scripts/ui/casual_panel_art.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const L10n := preload("res://scripts/localization/game_locale.gd")
const Avatar := preload("res://scripts/ui/leaderboard_avatar.gd")
const LeaderboardStore := preload("res://scripts/persistence/leaderboard_store.gd")

var _panel: Panel
var _scroll: ScrollContainer
var _content: VBoxContainer
var _title: Label
var _nickname_label: Label
var _help: Label
var _avatar_label: Label
var _error: Label
var _input_field: LineEdit
var _grid: GridContainer
var _avatars: Array[Button] = []
var _save: Button
var _cancel: Button
var _avatar := 0
var _error_source := ""
var _submitting := false
var _closing_requested := false
var _captured_keys: Dictionary = {}
var _forbidden := RegEx.new()
var _previous_focus: WeakRef

func _init() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 110
	_forbidden.compile("[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}\\[\\]<>]")
	_build()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_translate()
		_layout()

func _build() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	theme = Theme.new()
	theme.default_font = font
	theme.set_color("font_color", "Label", Color("#eef5ff"))
	_panel = Panel.new()
	_panel.name = "ProfileCard"
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.name = "ProfileScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_panel.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_title = _new_label("ProfileTitle")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nickname_label = _new_label("NicknameLabel")
	_input_field = LineEdit.new()
	_input_field.name = "NicknameInput"
	_input_field.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_input_field.expand_to_text_length = false
	_input_field.text_submitted.connect(func(_text: String): _submit())
	_content.add_child(_input_field)
	_help = _new_label("NicknameHelp")
	_avatar_label = _new_label("AvatarLabel")
	_grid = GridContainer.new()
	_grid.columns = 3
	_content.add_child(_grid)
	for index in range(6):
		var button := Button.new()
		button.name = "Avatar%d" % index
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_avatar.bind(index))
		_grid.add_child(button)
		var icon := Avatar.new()
		icon.avatar = index
		button.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_avatars.append(button)
	_error = _new_label("ProfileError")
	_error.add_theme_color_override("font_color", Color("#ffe2a8"))
	_save = _new_button("SaveButton", _submit)
	_cancel = _new_button("CancelButton", _request_close)
	_translate()
	_focus_chain()

func _new_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(label)
	return label

func _new_button(node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.pressed.connect(callback)
	_content.add_child(button)
	return button

func _translate() -> void:
	_title.text = L10n.t("编辑资料")
	_nickname_label.text = L10n.t("昵称")
	_help.text = L10n.t("昵称为2–12个字符，不含控制字符或标记")
	_avatar_label.text = L10n.t("选择头像")
	_save.text = L10n.t("保存")
	_cancel.text = L10n.t("取消")
	for index in range(6):
		_avatars[index].tooltip_text = Avatar.display_name(index)
		_avatars[index].accessibility_name = Avatar.display_name(index)
	_error.text = L10n.t(_error_source)
	_error.visible = not _error_source.is_empty()
	_input_field.accessibility_name = L10n.t("昵称")

func open_profile(profile: Dictionary) -> void:
	if not visible and is_inside_tree():
		var focused := get_viewport().gui_get_focus_owner()
		_previous_focus = weakref(focused) if focused != null else null
	_input_field.text = str(profile.get("nickname", ""))
	_error_source = ""
	_closing_requested = false
	_set_submitting(false)
	_select_avatar(clampi(int(profile.get("avatar", 0)), 0, 5))
	_translate()
	show()
	_layout()
	_scroll.scroll_vertical = 0
	_focus_editor.call_deferred()

func _focus_editor() -> void:
	if is_visible_in_tree():
		_input_field.grab_focus()
		_input_field.caret_column = _input_field.text.length()

func show_error(source: String) -> void:
	_error_source = source
	_set_submitting(false)
	_translate()
	_layout()

func close_dialog() -> void:
	hide()
	if _previous_focus != null:
		var previous = _previous_focus.get_ref()
		if is_instance_valid(previous) and previous.is_visible_in_tree():
			previous.grab_focus()
	_previous_focus = null

func _select_avatar(index: int) -> void:
	if _submitting:
		return
	_avatar = index
	for value in range(6):
		_avatars[value].set_pressed_no_signal(value == index)

func _submit() -> void:
	if not visible or _submitting or _closing_requested:
		return
	var nickname := LeaderboardStore.normalize_nickname(_input_field.text)
	# strip_edges also removes edge control characters; reject those in the raw draft.
	if _forbidden.search(_input_field.text) != null or not LeaderboardStore.valid_nickname(nickname):
		show_error("昵称为2–12个字符，不含控制字符或标记")
		return
	_error_source = ""
	_translate()
	_set_submitting(true)
	profile_saved.emit(nickname, _avatar)

func _set_submitting(value: bool) -> void:
	_submitting = value
	_save.disabled = value
	_input_field.editable = not value
	for button in _avatars:
		button.disabled = value
	_focus_chain()

func _request_close() -> void:
	if visible and not _closing_requested:
		_closing_requested = true
		close_requested.emit()

func _focus_chain() -> void:
	var controls: Array[Control] = [_input_field]
	if not _submitting:
		controls.append_array(_avatars)
		controls.append(_save)
	controls.append(_cancel)
	for index in range(controls.size()):
		var current := controls[index]
		var previous := current.get_path_to(controls[posmod(index - 1, controls.size())])
		var next := current.get_path_to(controls[(index + 1) % controls.size()])
		current.focus_previous = previous
		current.focus_next = next
		current.focus_neighbor_top = previous
		current.focus_neighbor_bottom = next
		current.focus_neighbor_left = previous
		current.focus_neighbor_right = next

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
	# Swallow the matching release even when a synchronous parent closed us.
	if not event.pressed and _captured_keys.has(code):
		_captured_keys.erase(code)
		get_viewport().set_input_as_handled()
		return
	if not is_visible_in_tree() or code not in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	_captured_keys[code] = true
	if code == KEY_ESCAPE:
		_request_close()
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button and is_ancestor_of(focused):
			if not focused.disabled:
				focused.pressed.emit()
		else:
			_submit()

func _unhandled_input(_event: InputEvent) -> void:
	if is_visible_in_tree():
		get_viewport().set_input_as_handled()

func _layout() -> void:
	if not is_inside_tree():
		return
	var unit := maxf(MobileLayout.dp(self, 1.0), 0.1)
	var safe := MobileLayout.safe_content_rect(self).grow(-14.0 * unit)
	var width := minf(420.0 * unit, maxf(1.0, safe.size.x))
	var height := minf(550.0 * unit, maxf(1.0, safe.size.y))
	_panel.position = safe.get_center() - Vector2(width, height) * 0.5
	_panel.size = Vector2(width, height)
	_panel.add_theme_stylebox_override("panel", Art.panel_style(unit))
	_scroll.position = Vector2.ONE * 16.0 * unit
	_scroll.size = (_panel.size - Vector2.ONE * 32.0 * unit).max(Vector2.ONE)
	_content.add_theme_constant_override("separation", roundi(10.0 * unit))
	_grid.add_theme_constant_override("h_separation", roundi(8.0 * unit))
	_grid.add_theme_constant_override("v_separation", roundi(8.0 * unit))
	for label: Label in [_title, _nickname_label, _help, _avatar_label, _error]:
		label.add_theme_font_size_override("font_size", maxi(roundi((24.0 if label == _title else 15.0) * unit), 1))
	_input_field.custom_minimum_size = Vector2(0, 48.0 * unit)
	_input_field.add_theme_font_size_override("font_size", maxi(roundi(18.0 * unit), 1))
	for button: Button in _avatars + [_save, _cancel]:
		button.custom_minimum_size = Vector2(48.0, 56.0) * unit
		Art.style_action(button, unit, "green" if button == _save else "secondary")
		L10n.fit_button(button, roundi(19.0 * unit), roundi(12.0 * unit))
		if _avatars.has(button):
			var selected: StyleBoxFlat = button.get_theme_stylebox("pressed").duplicate()
			selected.border_color = Color("#fff0a5")
			selected.set_border_width_all(maxi(roundi(3.0 * unit), 1))
			button.add_theme_stylebox_override("pressed", selected)
			button.add_theme_stylebox_override("hover_pressed", selected)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.045, 0.11, 0.76))
