extends Control

signal back_requested
signal mode_selected(mode: String)
signal refresh_requested
signal more_requested
signal play_requested(mode: String)
signal profile_requested
signal neighbors_requested

const BlockArt := preload("res://scripts/ui/block_art.gd")
const Art := preload("res://scripts/ui/casual_panel_art.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const L10n := preload("res://scripts/localization/game_locale.gd")
const Avatar := preload("res://scripts/ui/leaderboard_avatar.gd")
const MODES := ["adventure", "classic", "free"]
const TAB_NAMES := ["AdventureTab", "ClassicTab", "FreeTab"]
const TAB_KEYS := ["闯关模式", "经典模式", "自由模式"]
const TAB_COLORS := [Color("#ffc62b"), Color("#16c855"), Color("#ba41ed")]
const RULES := "闯关先比通关数，再比总积分；经典和自由比较单局最高分。相同成绩并列，只有已确认的成绩计入排名。"

var _data: Dictionary = {}
var _mode := "adventure"
var _unit := 1.0
var _buttons: Dictionary = {}
var _outer: Panel
var _stack: VBoxContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _podium: HBoxContainer
var _rows: VBoxContainer
var _neighbors: VBoxContainer
var _title: Label
var _metric: Label
var _status: Label
var _notice: Label
var _updated: Label
var _eligibility: Label
var _rules: Label
var _rules_dialog: Control
var _rules_dialog_card: Panel
var _rules_dialog_title: Label
var _rules_dialog_body: Label
var _rules_dialog_close: Button
var _rules_dialog_ok: Button
var _pending: Label
var _personal_score: Label
var _personal_avatar: Control
var _header: HBoxContainer

func _ready() -> void:
	L10n.initialize()
	_unit = MobileLayout.dp(self, 1.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.font_weight = 600
	add_theme_font_override("font", font)
	_build()
	resized.connect(_layout)
	apply_view(_data)
	_layout()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		apply_view(_data)

func apply_view(data: Dictionary) -> void:
	var previous_mode := _mode
	_data = data.duplicate(true)
	_mode = str(_data.get("mode", "adventure"))
	if not MODES.has(_mode):
		_mode = "adventure"
	if not is_instance_valid(_outer):
		return
	if previous_mode != _mode:
		_scroll.scroll_vertical = 0
	_title.text = L10n.t("排行榜")
	_buttons.BackButton.tooltip_text = L10n.t("返回")
	_buttons.InfoButton.tooltip_text = L10n.t("排行榜规则")
	_metric.text = L10n.t("先比通关数，再比总积分" if _mode == "adventure" else "单局最高分")
	_rules.text = L10n.t(RULES)
	_rules.visible = false
	_refresh_rules_dialog()
	for i in range(MODES.size()):
		var tab: Button = _buttons[TAB_NAMES[i]]
		tab.text = L10n.t(TAB_KEYS[i])
		tab.set_pressed_no_signal(MODES[i] == _mode)
		_style_button(tab, TAB_COLORS[i] if MODES[i] == _mode else Color("#194bae"))
		if i == 0 and MODES[i] == _mode:
			for role in ["font_color", "font_hover_color", "font_pressed_color"]:
				tab.add_theme_color_override(role, Color("#56340d"))
	var status := str(_data.get("status", "unconfigured"))
	var cached := bool(_data.get("has_cache", false))
	var show_records := status == "ready" or (cached and status in ["unconfigured", "offline", "error", "maintenance", "loading"])
	_status.text = _status_text(status, cached)
	_status.visible = not _status.text.is_empty()
	_status.add_theme_color_override("font_color", Color("#ffe4a0") if status in ["offline", "error", "maintenance"] else Color("#e1eeff"))
	var notice := str(_data.get("notice", ""))
	_notice.text = L10n.t(notice) if not notice.is_empty() else ""
	_notice.visible = not notice.is_empty()
	var timestamp := int(_data.get("updated_at", 0))
	_updated.visible = show_records and timestamp > 0
	_updated.text = L10n.t("上次更新：%s（UTC）") % Time.get_datetime_string_from_unix_time(timestamp).replace("T", " ") if _updated.visible else ""
	_buttons.RetryButton.text = L10n.t("刷新" if status in ["ready", "empty"] else "重试")
	_buttons.RetryButton.visible = status != "unconfigured"
	_buttons.RetryButton.disabled = status == "loading"
	_clear(_podium)
	_clear(_rows)
	_clear(_neighbors)
	var entries: Array = _data.get("entries", []) if show_records else []
	entries = entries.slice(0, 100)
	for index in [1, 0, 2]:
		if index < mini(entries.size(), 3):
			_add_podium(entries[index], index)
	_podium.visible = not entries.is_empty()
	_header.get_child(0).text = L10n.t("名次")
	_header.get_child(1).text = L10n.t("玩家")
	_header.get_child(2).text = L10n.t("通关 / 总积分" if _mode == "adventure" else "单局最高分")
	_header.visible = not entries.is_empty()
	for index in range(3, entries.size()):
		_add_row(_rows, entries[index])
	_buttons.MoreButton.text = L10n.t("加载更多")
	_buttons.MoreButton.visible = show_records and not str(_data.get("next_cursor", "")).is_empty() and entries.size() < 100
	_buttons.MoreButton.disabled = status != "ready"
	var neighbors: Array = _data.get("neighbors", []) if show_records else []
	_neighbors.visible = not neighbors.is_empty()
	if not neighbors.is_empty():
		_label(_neighbors, "NeighborsTitle", L10n.t("我的附近排名"), 15)
		for entry: Dictionary in neighbors:
			_add_row(_neighbors, entry)
	var me: Dictionary = _data.get("me", {}) if show_records else {}
	var ranked := int(me.get("rank", 0)) > 0
	_buttons.NeighborsButton.text = _integer(int(me.rank)) if ranked else L10n.t("尚未上榜")
	_buttons.NeighborsButton.tooltip_text = L10n.t("我的附近排名") if ranked else L10n.t("通关后可上榜" if _mode == "adventure" else "取得正分后可上榜")
	_buttons.NeighborsButton.disabled = not ranked
	_eligibility.visible = not ranked
	_eligibility.text = L10n.t("通关后可上榜" if _mode == "adventure" else "取得正分后可上榜")
	_personal_score.text = _score(me) if ranked else ""
	var profile: Dictionary = _data.get("profile", {})
	_buttons.ProfileButton.text = str(profile.get("nickname", me.get("nickname", L10n.t("我"))))
	_buttons.ProfileButton.tooltip_text = L10n.t("编辑资料")
	_personal_avatar.avatar = int(profile.get("avatar", me.get("avatar", 0)))
	var pending: Dictionary = _data.get("pending", {})
	_pending.visible = not pending.is_empty()
	_pending.text = L10n.t("待同步：%s") % _score(pending).replace("\n", " / ") if bool(pending.get("eligible", false)) else L10n.t("仅本机：%s") % _score(pending).replace("\n", " / ")
	var play_key := "再来一局"
	if _mode == "adventure":
		play_key = "重玩关卡" if int(_data.get("highest_completed", 0)) >= 96 else "继续闯关"
	_buttons.PlayButton.text = L10n.t(play_key)
	_layout()
	call_deferred("_fit_buttons")

func get_action_button(action_name: String) -> Button:
	return _buttons.get(action_name)

func focus_primary() -> void:
	if rules_popup_open():
		_rules_dialog_ok.grab_focus()
		return
	if is_visible_in_tree() and is_instance_valid(_outer):
		_buttons.PlayButton.grab_focus()

func rules_popup_open() -> bool:
	return is_instance_valid(_rules_dialog) and _rules_dialog.visible

func close_rules_popup() -> void:
	if not rules_popup_open():
		return
	_rules_dialog.hide()
	if is_visible_in_tree():
		_buttons.InfoButton.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if rules_popup_open():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			close_rules_popup()
			get_viewport().set_input_as_handled()
		return
	if is_visible_in_tree() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		back_requested.emit()
		get_viewport().set_input_as_handled()

func _build() -> void:
	_outer = Panel.new()
	_outer.name = "OuterCard"
	var surface := Art.panel_style(_unit)
	surface.bg_color = Color("#1e60d5")
	surface.border_color = Color("#71b0ff")
	_outer.add_theme_stylebox_override("panel", surface)
	add_child(_outer)
	_build_rules_dialog()
	_stack = _vbox(_outer, "Layout", 8)
	var title_row := HBoxContainer.new()
	_stack.add_child(title_row)
	var back := _button(title_row, "BackButton", "", func(): back_requested.emit())
	back.custom_minimum_size.x = 48 * _unit
	back.draw.connect(func(): BlockArt.draw_icon(back, "back", Rect2(back.size * 0.25, back.size * 0.5), Color.WHITE))
	_title = _label(title_row, "Title", "", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var info := _button(title_row, "InfoButton", "", _toggle_rules)
	info.custom_minimum_size.x = 48 * _unit
	info.draw.connect(func():
		var center := info.size * 0.5
		info.draw_circle(center - Vector2(0, 9 * _unit), 2.2 * _unit, Color.WHITE, true, -1, true)
		info.draw_line(center - Vector2(0, 2 * _unit), center + Vector2(0, 10 * _unit), Color.WHITE, 3 * _unit, true)
	)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", roundi(3 * _unit))
	_stack.add_child(tabs)
	for i in range(MODES.size()):
		var mode: String = MODES[i]
		var tab := _button(tabs, TAB_NAMES[i], "", func(): mode_selected.emit(mode))
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_metric = _label(_stack, "Metric", "", 14)
	_metric.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_metric.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(_scroll)
	_content = _vbox(_scroll, "Content", 7)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules = _label(_content, "Rules", "", 14)
	_rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules.visible = false
	_status = _label(_content, "Status", "", 16)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice = _label(_content, "Notice", "", 14)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_color_override("font_color", Color("#ffe4a0"))
	_eligibility = _label(_content, "Eligibility", "", 13)
	_eligibility.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_eligibility.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_updated = _label(_content, "UpdatedAt", "", 12)
	_updated.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_updated.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(_content, "RetryButton", "", func(): refresh_requested.emit())
	_podium = HBoxContainer.new()
	_podium.name = "Podium"
	_podium.alignment = BoxContainer.ALIGNMENT_CENTER
	_podium.add_theme_constant_override("separation", roundi(3 * _unit))
	_content.add_child(_podium)
	var list_panel := PanelContainer.new()
	var inner := Art.inner_style(_unit)
	inner.bg_color = Color("#243780")
	inner.set_content_margin_all(4 * _unit)
	list_panel.add_theme_stylebox_override("panel", inner)
	_content.add_child(list_panel)
	var list_stack := _vbox(list_panel, "List", 0)
	_header = HBoxContainer.new()
	list_stack.add_child(_header)
	_label(_header, "RankHeader", "", 12).custom_minimum_size.x = 38 * _unit
	_label(_header, "PlayerHeader", "", 12).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var metric_header := _label(_header, "ScoreHeader", "", 12)
	metric_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rows = _vbox(list_stack, "Rows", 1)
	_button(_content, "MoreButton", "", func(): more_requested.emit())
	_neighbors = _vbox(_content, "Neighbors", 1)
	var personal := PanelContainer.new()
	personal.name = "PersonalRow"
	var cyan := Art.inner_style(_unit)
	cyan.bg_color = Color("#174daf")
	cyan.border_color = Color("#5af2ff")
	cyan.set_border_width_all(maxi(2, roundi(2 * _unit)))
	cyan.set_content_margin_all(3 * _unit)
	personal.add_theme_stylebox_override("panel", cyan)
	personal.custom_minimum_size.y = 56 * _unit
	_stack.add_child(personal)
	var personal_stack := _vbox(personal, "PersonalContent", 0)
	var personal_row := HBoxContainer.new()
	personal_row.add_theme_constant_override("separation", roundi(2 * _unit))
	personal_stack.add_child(personal_row)
	var rank := _button(personal_row, "NeighborsButton", "", func(): neighbors_requested.emit())
	rank.custom_minimum_size.x = 66 * _unit
	var profile := _button(personal_row, "ProfileButton", "", func(): profile_requested.emit())
	profile.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for role in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBoxFlat = profile.get_theme_stylebox(role).duplicate()
		style.content_margin_left = 38 * _unit
		profile.add_theme_stylebox_override(role, style)
	_personal_avatar = Avatar.new()
	_personal_avatar.name = "PersonalAvatar"
	_personal_avatar.position = Vector2(2, 7) * _unit
	_personal_avatar.size = Vector2.ONE * 32 * _unit
	profile.add_child(_personal_avatar)
	_personal_score = _label(personal_row, "PersonalScore", "", 13)
	_personal_score.custom_minimum_size.x = 81 * _unit
	_personal_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pending = _label(personal_stack, "Pending", "", 12)
	_pending.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending.add_theme_color_override("font_color", Color("#ffe4a0"))
	var play := _button(_stack, "PlayButton", "", func(): play_requested.emit(_mode))
	Art.style_action(play, _unit)
	play.custom_minimum_size.y = 56 * _unit
	_apply_focus_style(play)

func _layout() -> void:
	if not is_instance_valid(_outer):
		return
	var safe := MobileLayout.safe_content_rect(self)
	var width := minf(480 * _unit, safe.size.x - 16 * _unit)
	_outer.position = safe.position + Vector2((safe.size.x - width) * 0.5, 8 * _unit)
	_outer.size = Vector2(width, maxf(0, safe.size.y - 16 * _unit))
	_stack.position = Vector2.ONE * 10 * _unit
	_stack.size = _outer.size - Vector2.ONE * 20 * _unit
	_layout_rules_dialog()
	call_deferred("_fit_buttons")

func _fit_buttons() -> void:
	var candidates: Array[Button] = []
	for key in ["BackButton", "InfoButton", "AdventureTab", "ClassicTab", "FreeTab", "RetryButton", "MoreButton", "NeighborsButton", "ProfileButton", "PlayButton"]:
		var button: Button = _buttons[key]
		L10n.fit_button(button, roundi((21 if key == "PlayButton" else 16) * _unit), roundi(11 * _unit))
		if button.is_visible_in_tree() and not button.disabled:
			candidates.append(button)
	for i in range(candidates.size()):
		candidates[i].focus_previous = candidates[i].get_path_to(candidates[posmod(i - 1, candidates.size())])
		candidates[i].focus_next = candidates[i].get_path_to(candidates[(i + 1) % candidates.size()])

func _status_text(status: String, cached: bool) -> String:
	match status:
		"unconfigured": return L10n.t("排行榜服务尚未开放")
		"loading": return L10n.t("加载中…")
		"empty": return L10n.t("还没有玩家上榜，来创造第一条纪录吧")
		"offline", "error": return L10n.t("离线 · 显示上次排名" if cached else "暂时无法连接排行榜")
		"maintenance": return L10n.t("排行榜维护中，请稍后重试")
	return ""

func _score(entry: Dictionary) -> String:
	var value := _integer(int(entry.get("score", 0)))
	if _mode == "adventure":
		return L10n.t("%s关") % _integer(int(entry.get("completed", 0))) + "\n" + value
	return value

func _integer(value: int) -> String:
	var digits := str(value)
	var separator := "\u202f" if L10n.language() == "fr" else ","
	var index := digits.length() - 3
	while index > 0 and digits[index - 1] != "-":
		digits = digits.insert(index, separator)
		index -= 3
	return digits

func _add_podium(entry: Dictionary, slot: int) -> void:
	var column := VBoxContainer.new()
	column.name = "Podium%d" % slot
	column.set_meta("account_id", str(entry.get("account_id", "")))
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_END
	column.add_theme_constant_override("separation", 0)
	_podium.add_child(column)
	var center := CenterContainer.new()
	column.add_child(center)
	var avatar := Avatar.new()
	avatar.avatar = int(entry.get("avatar", 0))
	avatar.crowned = int(entry.get("rank", 0)) == 1
	avatar.custom_minimum_size = Vector2.ONE * (54 if slot == 0 else 44) * _unit
	center.add_child(avatar)
	var base := PanelContainer.new()
	var colors := [Color("#d69c26"), Color("#5f91e1"), Color("#c7744a")]
	var style := BlockArt.button_style(colors[slot])
	style.set_content_margin_all(4 * _unit)
	base.add_theme_stylebox_override("panel", style)
	base.custom_minimum_size.y = (112 if slot == 0 else 98 if slot == 1 else 90) * _unit
	column.add_child(base)
	var stack := _vbox(base, "PodiumContent", 0)
	var rank := _label(stack, "Rank", _integer(int(entry.get("rank", 0))), 26)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nickname := _label(stack, "Nickname", str(entry.get("nickname", "")), 13)
	nickname.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nickname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nickname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var score := _label(stack, "Score", _score(entry), 12)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _add_row(parent: VBoxContainer, entry: Dictionary) -> void:
	var row := PanelContainer.new()
	row.name = "Entry%d" % parent.get_child_count()
	row.custom_minimum_size.y = 56 * _unit
	var style := BlockArt.panel_style(Color("#273d89"), 4, Color("#435bb0"))
	style.set_content_margin_all(3 * _unit)
	row.add_theme_stylebox_override("panel", style)
	parent.add_child(row)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", roundi(3 * _unit))
	row.add_child(line)
	var rank := _label(line, "Rank", _integer(int(entry.get("rank", 0))), 16)
	rank.custom_minimum_size.x = 32 * _unit
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var avatar := Avatar.new()
	avatar.avatar = int(entry.get("avatar", 0))
	avatar.custom_minimum_size = Vector2.ONE * 32 * _unit
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(avatar)
	var nickname := _label(line, "Nickname", str(entry.get("nickname", "")), 14)
	nickname.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nickname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nickname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var score := _label(line, "Score", _score(entry), 13)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _label(parent: Node, node_name: String, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", roundi(font_size * _unit))
	label.add_theme_color_override("font_color", Color.WHITE)
	parent.add_child(label)
	return label

func _vbox(parent: Node, node_name: String, gap: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.add_theme_constant_override("separation", roundi(gap * _unit))
	parent.add_child(box)
	return box

func _button(parent: Node, node_name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size.y = 48 * _unit
	button.pressed.connect(action)
	_style_button(button, Color("#2056bb"))
	parent.add_child(button)
	_buttons[node_name] = button
	return button

func _style_button(button: Button, color: Color) -> void:
	Art.style_action(button, _unit, "secondary")
	for role in ["normal", "hover", "pressed"]:
		var style := BlockArt.button_style(color.lightened(0.06) if role == "hover" else color, role == "pressed")
		style.content_margin_left = 5 * _unit
		style.content_margin_right = 5 * _unit
		style.content_margin_top = 4 * _unit
		style.content_margin_bottom = 4 * _unit
		button.add_theme_stylebox_override(role, style)
	_apply_focus_style(button)

func _apply_focus_style(button: Button) -> void:
	var focus := BlockArt.panel_style(Color.TRANSPARENT, 9, Color("#b7faff"))
	focus.set_border_width_all(maxi(2, roundi(2 * _unit)))
	button.add_theme_stylebox_override("focus", focus)

func _toggle_rules() -> void:
	if rules_popup_open():
		close_rules_popup()
		return
	_refresh_rules_dialog()
	_rules_dialog.show()
	_layout_rules_dialog()
	_rules_dialog_ok.grab_focus.call_deferred()

func _refresh_rules_dialog() -> void:
	if not is_instance_valid(_rules_dialog):
		return
	_rules_dialog_title.text = L10n.t("排行榜规则")
	_rules_dialog_body.text = L10n.t(RULES)
	_rules_dialog_ok.text = L10n.t("知道了")
	_rules_dialog_close.tooltip_text = L10n.t("返回")
	_rules_dialog_close.accessibility_name = L10n.t("返回")

func _build_rules_dialog() -> void:
	_rules_dialog = Control.new()
	_rules_dialog.name = "RulesDialog"
	_rules_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_rules_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_rules_dialog.z_index = 100
	_rules_dialog.hide()
	add_child(_rules_dialog)
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.025, 0.045, 0.11, 0.76)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_rules_popup())
	_rules_dialog.add_child(backdrop)
	_rules_dialog_card = Panel.new()
	_rules_dialog_card.name = "RulesCard"
	_rules_dialog.add_child(_rules_dialog_card)
	_rules_dialog_title = _label(_rules_dialog_card, "RulesTitle", "", 22)
	_rules_dialog_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rules_dialog_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rules_dialog_body = _label(_rules_dialog_card, "RulesBody", "", 16)
	_rules_dialog_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_dialog_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_rules_dialog_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules_dialog_close = Button.new()
	_rules_dialog_close.name = "CloseButton"
	_rules_dialog_close.text = "×"
	_rules_dialog_close.pressed.connect(close_rules_popup)
	_rules_dialog_close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_button(_rules_dialog_close, Color("#2056bb"))
	_rules_dialog_card.add_child(_rules_dialog_close)
	_rules_dialog_ok = Button.new()
	_rules_dialog_ok.name = "OKButton"
	_rules_dialog_ok.pressed.connect(close_rules_popup)
	_rules_dialog_ok.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_button(_rules_dialog_ok, Color("#19b83d"))
	_rules_dialog_card.add_child(_rules_dialog_ok)
	_refresh_rules_dialog()

func _layout_rules_dialog() -> void:
	if not is_instance_valid(_rules_dialog) or not is_instance_valid(_rules_dialog_card):
		return
	_rules_dialog.position = Vector2.ZERO
	_rules_dialog.size = size
	var safe := MobileLayout.safe_content_rect(self)
	var width := minf(420.0 * _unit, maxf(1.0, safe.size.x - 32.0 * _unit))
	var height := minf(286.0 * _unit, maxf(1.0, safe.size.y - 32.0 * _unit))
	_rules_dialog_card.position = safe.get_center() - Vector2(width, height) * 0.5
	_rules_dialog_card.size = Vector2(width, height)
	_rules_dialog_card.add_theme_stylebox_override("panel", Art.panel_style(_unit))
	_rules_dialog_title.position = Vector2(18, 10) * _unit
	_rules_dialog_title.size = Vector2(width / _unit - 72, 40) * _unit
	_rules_dialog_close.position = Vector2(width - 54.0 * _unit, 8.0 * _unit)
	_rules_dialog_close.size = Vector2.ONE * 44.0 * _unit
	_rules_dialog_body.position = Vector2(20, 62) * _unit
	_rules_dialog_body.size = Vector2(width / _unit - 40, height / _unit - 132) * _unit
	_rules_dialog_ok.position = Vector2(20, height / _unit - 60) * _unit
	_rules_dialog_ok.size = Vector2(width / _unit - 40, 48) * _unit
	for label: Label in [_rules_dialog_title, _rules_dialog_body]:
		label.add_theme_font_size_override("font_size", roundi((22 if label == _rules_dialog_title else 16) * _unit))
	L10n.fit_button(_rules_dialog_close, roundi(22 * _unit), roundi(8 * _unit))
	L10n.fit_button(_rules_dialog_ok, roundi(17 * _unit), roundi(10 * _unit))

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
