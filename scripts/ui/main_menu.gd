extends Control

## A native menu owns its layout and finite introduction, leaving Main to route
## actions. Nothing in the opening represents resource-loading progress.
signal free_requested
signal classic_requested
signal adventure_requested
signal settings_requested
signal quit_requested

const Art := preload("res://scripts/ui/block_art.gd")
const ModeButton := preload("res://scripts/ui/menu_mode_button.gd")
const MenuLogo := preload("res://scripts/ui/menu_logo.gd")
const IconButton := preload("res://scripts/ui/art_icon_button.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const OPENING_DURATION := 3.60
const OPENING_PHASE_DURATION := 2.20
const RETURN_DURATION := 0.30
const MODE_FACE_ASPECT := 877.0 / 213.0
const MODE_GAP_RATIO := 0.34
const MODE_SIZE_SCALE := 0.60
const MODE_FOOTER_CLEARANCE := 18.0
const MOBILE_MODE_WIDTH_RATIO := 0.66
const MOBILE_MODE_GAP_RATIO := 0.24
const SPINNER_SIZE_SCALE := 1.30

var _logo: Control
var _best: Label
var _warning: Label
var _skip: Label
var _buttons: Array[Button] = []
var _destinations: Dictionary = {}
var _logo_destination := Vector2.ZERO
var _tween: Tween
var _opening := false
var _has_opened := false
var _returning := false
var _reduced_motion := false
var _elapsed := 0.0
var _font: Font
var _best_rect := Rect2()
var _content_rect := Rect2()
var _epoch := 0
var _skip_key_release := 0
var _skip_mouse_release := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Microsoft YaHei", "sans-serif"])
	font.font_weight = 800
	_font = font
	_build_controls()
	resized.connect(_on_resized)
	visibility_changed.connect(_on_visibility_changed)
	_layout_controls()

func _exit_tree() -> void:
	_stop_animation()

func set_profile(high_score: int, save_warning: String, reduced_motion: bool) -> void:
	if not is_instance_valid(_best):
		return
	_best.text = "最高分  %d" % maxi(high_score, 0)
	_warning.text = save_warning
	_warning.tooltip_text = save_warning
	set_reduced_motion(reduced_motion)

func set_reduced_motion(enabled: bool) -> void:
	var changed := enabled != _reduced_motion
	_reduced_motion = enabled
	for button: Button in _buttons:
		button.set_reduced_motion(enabled)
	if changed and enabled:
		finish_opening()

func present(first_launch: bool = false, reduced_motion: bool = false) -> void:
	_stop_animation()
	_reduced_motion = reduced_motion
	_layout_controls()
	if first_launch and not _has_opened and not reduced_motion:
		_has_opened = true
		_opening = true
		_elapsed = 0.0
		for button: Button in _buttons:
			button.disabled = true
			button.entrance_preview = true
		get_node("SettingsButton").disabled = true
		get_node("ExitButton").disabled = true
		_apply_opening(0.0)
		var epoch := _epoch
		_tween = create_tween()
		_tween.tween_method(_advance_opening.bind(epoch), 0.0, OPENING_DURATION, OPENING_DURATION)
		_tween.tween_callback(_finish_epoch.bind(epoch))
	else:
		_has_opened = true
		_settle_controls()
		get_node("AdventureButton").grab_focus()
		if not reduced_motion:
			_returning = true
			var epoch := _epoch
			_advance_return(0.0, epoch)
			_tween = create_tween()
			_tween.tween_method(_advance_return.bind(epoch), 0.0, 1.0, RETURN_DURATION)
			_tween.tween_callback(_finish_epoch.bind(epoch))
		else:
			get_node("AdventureButton").grab_focus()

func is_opening() -> bool:
	return _opening

func consume_opening_input(event: InputEvent) -> bool:
	if not is_visible_in_tree():
		return false
	if _skip_key_release != 0 and event is InputEventKey and event.keycode == _skip_key_release:
		if not event.pressed:
			_skip_key_release = 0
		return true
	if _skip_mouse_release and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_skip_mouse_release = false
		return true
	if not _opening:
		return false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		finish_opening()
		_skip_mouse_release = true
		return true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
		finish_opening()
		_skip_key_release = event.keycode
		return true
	# Tab and other gameplay shortcuts do not reach disabled background modes.
	return event is InputEventKey

func finish_opening(focus_default: bool = true) -> void:
	var needs_focus := _opening or get_viewport().gui_get_focus_owner() == null
	_stop_animation()
	if is_node_ready():
		_settle_controls()
		if focus_default and needs_focus and is_visible_in_tree():
			get_node("AdventureButton").grab_focus()

func _stop_animation() -> void:
	_epoch += 1
	if is_instance_valid(_tween):
		_tween.kill()
	_tween = null
	_opening = false
	_returning = false
	_skip_key_release = 0
	_skip_mouse_release = false

func _finish_epoch(epoch: int) -> void:
	if epoch == _epoch:
		finish_opening(not _returning)

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_stop_animation()
		if is_node_ready():
			_settle_controls()

func _on_resized() -> void:
	var was_entering := _opening or _returning
	_stop_animation()
	_layout_controls()
	_settle_controls()
	if was_entering and is_visible_in_tree() and get_viewport().gui_get_focus_owner() == null:
		get_node("AdventureButton").grab_focus()

func _build_controls() -> void:
	_logo = MenuLogo.new()
	_logo.name = "MenuLogo"
	add_child(_logo)
	_best = _label(17, Color("#ffe590"))
	_best.name = "BestScore"
	add_child(_best)
	var definitions := [
		["AdventureButton", "adventure", "闯关模式", "", Color("#f3a509")],
		["ClassicButton", "classic", "经典模式", "", Color("#0bc5a4")],
		["StartButton", "free", "自由模式", "", Color("#d92eea")],
	]
	for definition: Array in definitions:
		var button := ModeButton.new()
		button.name = definition[0]
		button.mode_kind = definition[1]
		button.title_text = definition[2]
		button.subtitle_text = definition[3]
		button.face_color = definition[4]
		add_child(button)
		_buttons.append(button)
	_buttons[0].pressed.connect(func() -> void: adventure_requested.emit())
	_buttons[1].pressed.connect(func() -> void: classic_requested.emit())
	_buttons[2].pressed.connect(func() -> void: free_requested.emit())
	var settings := Button.new()
	settings.set_script(IconButton)
	settings.name = "SettingsButton"
	settings.set("icon_kind", "gear")
	settings.set("fill_color", Color("#21599f"))
	settings.tooltip_text = "游戏设置"
	settings.pressed.connect(func() -> void: settings_requested.emit())
	add_child(settings)
	var focus := Art.panel_style(Color.TRANSPARENT, 12, Color("#b8ffff"))
	focus.set_border_width_all(2)
	focus.shadow_size = 0
	settings.add_theme_stylebox_override("focus", focus)
	var exit_button := Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "退出游戏"
	exit_button.focus_mode = Control.FOCUS_ALL
	exit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	exit_button.add_theme_font_size_override("font_size", 16)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		exit_button.add_theme_color_override(state, Color("#dbf3ff"))
	exit_button.add_theme_stylebox_override("normal", Art.button_style(Color("#2263a6")))
	exit_button.add_theme_stylebox_override("hover", Art.button_style(Color("#2e77ba")))
	exit_button.add_theme_stylebox_override("pressed", Art.button_style(Color("#2263a6"), true))
	exit_button.add_theme_stylebox_override("focus", focus)
	exit_button.pressed.connect(func() -> void: quit_requested.emit())
	add_child(exit_button)
	_warning = _label(12, Color("#ffe0b3"))
	_warning.name = "SaveWarning"
	add_child(_warning)
	_skip = _label(13, Color("#d3e6ff"))
	_skip.text = "点击或按 Enter 跳过"
	_skip.name = "OpeningSkip"
	add_child(_skip)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _layout_controls() -> void:
	if not is_instance_valid(_logo):
		return
	_content_rect = MobileLayout.safe_content_rect(self)
	if MobileLayout.is_mobile():
		_layout_mobile_controls()
		return
	var scale_factor := clampf(size.y / 720.0, 0.62, 1.0)
	var logo_width := minf(minf(400.0, maxf(size.x - 56.0, 120.0)), size.y * 0.55)
	_logo.size = Vector2(logo_width, minf(logo_width * 0.47, size.y * (0.18 if size.y < 420.0 else 0.24)))
	_logo.pivot_offset = _logo.size * 0.5
	_logo_destination = Vector2((size.x - _logo.size.x) * 0.5, 12.0 if size.y < 420.0 else maxf(34.0, size.y * 0.105))
	var exit_height := maxf(34.0, 40.0 * scale_factor)
	var exit_top := minf(size.y - 70.0 * scale_factor, size.y - 25.0 - exit_height - 6.0)
	var minimum_top := _logo_destination.y + _logo.size.y + (60.0 if size.y >= 560.0 else 22.0) * scale_factor
	# Fit the approved artwork as one proportional face; compact windows shrink
	# the whole stack instead of squeezing the icons or italic lettering.
	var stack_space := maxf(exit_top - MODE_FOOTER_CLEARANCE - minimum_top, 0.0)
	var width := minf(380.0, maxf(200.0, size.x - 56.0))
	var fitted_height := minf(width / MODE_FACE_ASPECT, stack_space / (3.0 + 2.0 * MODE_GAP_RATIO))
	var button_height := maxf(44.0, fitted_height * MODE_SIZE_SCALE)
	width = button_height * MODE_FACE_ASPECT
	var gap := button_height * MODE_GAP_RATIO
	var stack_height := button_height * 3.0 + gap * 2.0
	var future_row := button_height + gap if stack_space >= button_height * 4.0 + gap * 3.0 else 0.0
	var lowest_top := exit_top - MODE_FOOTER_CLEARANCE - stack_height - future_row
	var top := clampf(size.y * 0.49, minf(minimum_top, lowest_top), lowest_top)
	_destinations.clear()
	for index in range(_buttons.size()):
		var button: Button = _buttons[index]
		button.size = Vector2(width, button_height)
		button.pivot_offset = button.size * 0.5
		_destinations[button.name] = Vector2((size.x - width) * 0.5, top + float(index) * (button_height + gap))
	var settings: Control = get_node("SettingsButton")
	settings.position = Vector2(maxf(12.0, size.x - 72.0), 20.0)
	settings.size = Vector2(48.0, 48.0)
	var exit_button: Control = get_node("ExitButton")
	exit_button.size = Vector2(128.0, exit_height)
	exit_button.position = Vector2((size.x - exit_button.size.x) * 0.5, exit_top)
	_best_rect = Rect2(Vector2((size.x - 220.0) * 0.5, _logo_destination.y + _logo.size.y + 8.0), Vector2(220.0, 32.0))
	_best.position = _best_rect.position + Vector2(22.0, 0.0)
	_best.size = _best_rect.size - Vector2(30.0, 0.0)
	_warning.position = Vector2(12.0, size.y - 25.0)
	_warning.size = Vector2(maxf(size.x - 24.0, 0.0), 20.0)
	_skip.position = Vector2(16.0, size.y - 47.0)
	_skip.size = Vector2(maxf(size.x - 32.0, 0.0), 24.0)

func _layout_mobile_controls() -> void:
	var area := _content_rect
	var unit := MobileLayout.dp(self, 1.0)
	var padding := 20.0 * unit
	var target := MobileLayout.touch_target(self)
	var logo_width := minf(area.size.x * 0.72, 286.0 * unit)
	_logo.size = Vector2(logo_width, logo_width * 0.47)
	_logo.pivot_offset = _logo.size * 0.5
	_logo_destination = area.position + Vector2((area.size.x - logo_width) * 0.5, area.size.y * 0.105)
	var settings: Control = get_node("SettingsButton")
	settings.size = Vector2.ONE * target
	settings.tooltip_text = ""
	settings.position = Vector2(area.end.x - padding - target, area.position.y + 12.0 * unit)
	var exit_button: Button = get_node("ExitButton")
	exit_button.size = Vector2(150.0 * unit, target)
	exit_button.position = Vector2(area.get_center().x - exit_button.size.x * 0.5, area.end.y - 40.0 * unit - target)
	exit_button.add_theme_font_size_override("font_size", roundi(18.0 * unit))
	_best_rect = Rect2(Vector2(area.get_center().x - 120.0 * unit, _logo_destination.y + _logo.size.y + 12.0 * unit), Vector2(240.0, 32.0) * unit)
	_best.position = _best_rect.position + Vector2(28.0 * unit, 0.0)
	_best.size = _best_rect.size - Vector2(34.0 * unit, 0.0)
	_best.add_theme_font_size_override("font_size", roundi(17.0 * unit))
	var minimum_top := _best_rect.end.y + 28.0 * unit
	var stack_end := exit_button.position.y - 24.0 * unit
	var stack_space := maxf(stack_end - minimum_top, 0.0)
	# Reserve a fourth row for the future More entry when space permits. Fit the
	# three real modes first on short screens, keeping the approved face intact.
	var available_width := maxf(area.size.x - padding * 2.0, 0.0)
	var minimum_height := minf(target, available_width / MODE_FACE_ASPECT)
	var preferred_width := minf(area.size.x * MOBILE_MODE_WIDTH_RATIO, 280.0 * unit)
	var preferred_height := clampf(preferred_width / MODE_FACE_ASPECT, minimum_height, available_width / MODE_FACE_ASPECT)
	var rows := 4.0 if stack_space >= minimum_height * (4.0 + 3.0 * MOBILE_MODE_GAP_RATIO) else 3.0
	var button_height := minf(preferred_height, stack_space / (rows + (rows - 1.0) * MOBILE_MODE_GAP_RATIO))
	var width := button_height * MODE_FACE_ASPECT
	var gap := button_height * MOBILE_MODE_GAP_RATIO
	var lowest_top := stack_end - button_height * rows - gap * (rows - 1.0)
	var top := clampf(area.position.y + area.size.y * 0.49, minf(minimum_top, lowest_top), lowest_top)
	_destinations.clear()
	for index in range(_buttons.size()):
		var button: Button = _buttons[index]
		button.size = Vector2(width, button_height)
		button.pivot_offset = button.size * 0.5
		_destinations[button.name] = Vector2(area.get_center().x - width * 0.5, top + float(index) * (button_height + gap))
	_warning.position = Vector2(area.position.x + padding, area.end.y - 22.0 * unit)
	_warning.size = Vector2(maxf(area.size.x - padding * 2.0, 0.0), 20.0 * unit)
	_warning.add_theme_font_size_override("font_size", roundi(12.0 * unit))
	_skip.position = Vector2(area.position.x + padding, area.end.y - 28.0 * unit)
	_skip.size = Vector2(maxf(area.size.x - padding * 2.0, 0.0), 24.0 * unit)
	_skip.add_theme_font_size_override("font_size", roundi(13.0 * unit))
	_skip.text = "轻触屏幕跳过"

func _settle_controls() -> void:
	_logo.position = _logo_destination
	_logo.scale = Vector2.ONE
	_logo.modulate = Color.WHITE
	_logo.visible = true
	_logo.set_glint(0.0)
	for button: Button in _buttons:
		button.position = _destinations.get(button.name, Vector2.ZERO)
		button.scale = Vector2.ONE
		button.modulate = Color.WHITE
		button.disabled = false
		button.entrance_preview = false
	for name in ["SettingsButton", "ExitButton"]:
		var button: Button = get_node(name)
		button.modulate = Color.WHITE
		button.disabled = false
	_best.modulate = Color.WHITE
	_best.visible = size.y >= 560.0
	_warning.visible = true
	_skip.visible = false
	queue_redraw()

func _advance_opening(elapsed: float, epoch: int) -> void:
	if epoch == _epoch and _opening:
		_apply_opening(elapsed)

func _apply_opening(elapsed: float) -> void:
	# Keep all existing phase transitions synchronized while slowing the whole
	# introduction. Spinner rotation uses this same clock, so it slows too.
	elapsed = elapsed * OPENING_PHASE_DURATION / OPENING_DURATION
	_elapsed = elapsed
	var title_in := smoothstep(0.52, 0.92, elapsed)
	var move_up := smoothstep(1.10, 1.68, elapsed)
	var centered := _content_rect.position + Vector2((_content_rect.size.x - _logo.size.x) * 0.5, _content_rect.size.y * 0.34 - _logo.size.y * 0.5)
	_logo.visible = title_in > 0.0
	_logo.position = centered.lerp(_logo_destination, move_up)
	_logo.scale = Vector2.ONE * (0.70 + title_in * 0.30 + sin(title_in * PI) * 0.10)
	_logo.modulate.a = title_in
	_logo.set_glint(clampf((elapsed - 0.80) / 0.60, 0.0, 1.0))
	for index in range(_buttons.size()):
		var button: Button = _buttons[index]
		var entering := smoothstep(1.52 + float(index) * 0.11, 1.94 + float(index) * 0.11, elapsed)
		button.position = _destinations[button.name] + Vector2(0.0, (1.0 - entering) * _entry_distance(button, 35.0))
		button.modulate.a = entering
		button.scale = Vector2.ONE * (0.94 + entering * 0.06)
	_best.visible = size.y >= 560.0
	_best.modulate.a = smoothstep(1.58, 1.96, elapsed)
	get_node("SettingsButton").modulate.a = smoothstep(1.64, 2.02, elapsed)
	get_node("ExitButton").modulate.a = smoothstep(1.80, 2.16, elapsed)
	_warning.visible = false
	_skip.visible = elapsed < 1.80
	queue_redraw()

func _advance_return(progress: float, epoch: int) -> void:
	if epoch != _epoch or not _returning:
		return
	var blend := 1.0 - pow(1.0 - progress, 3.0)
	for button: Button in _buttons:
		button.position = _destinations[button.name] + Vector2(0.0, (1.0 - blend) * _entry_distance(button, 14.0))
		button.modulate.a = 0.45 + blend * 0.55

func _entry_distance(button: Button, preferred: float) -> float:
	if button != _buttons.back():
		return preferred
	# Keep the last card's animated bounds above the footer, including its
	# contact shadow, in compact windows as well as at the final position.
	var destination: Vector2 = _destinations[button.name]
	var available: float = get_node("ExitButton").position.y - destination.y - button.size.y - MODE_FOOTER_CLEARANCE
	return clampf(available, 0.0, preferred)

func _draw() -> void:
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]), PackedColorArray([Color("#173da8"), Color("#204ab4"), Color("#188cd1"), Color("#197dcc")]))
	var center := Vector2(size.x * 0.5, size.y * 0.40)
	for ring in range(6, 0, -1):
		draw_circle(center, minf(size.x * 0.48, size.y * 0.52) * float(ring) / 6.0, Color(0.18, 0.67, 0.98, 0.015))
	if _opening:
		_draw_studio()
		_draw_spinner()
	if not _opening and size.y >= 560.0:
		draw_style_box(Art.panel_style(Color(0.06, 0.23, 0.50, 0.34), 16, Color(0.63, 0.87, 1.0, 0.20)), _best_rect)
		var icon_scale := MobileLayout.dp(self, 1.0)
		Art.draw_icon(self, "crown", Rect2(_best_rect.position + Vector2(14.0, 5.0) * icon_scale, Vector2(22.0, 22.0) * icon_scale), Color("#ffda64"))

func _draw_studio() -> void:
	var alpha := smoothstep(0.0, 0.14, _elapsed) * (1.0 - smoothstep(0.44, 0.66, _elapsed))
	if alpha <= 0.0 or _font == null:
		return
	var center := _content_rect.position + _content_rect.size * Vector2(0.5, 0.42)
	var unit := clampf(minf(size.x, size.y) * 0.039, 13.0, 25.0)
	var cells := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	for index in range(cells.size()):
		var color := Color("#ffce45") if index % 2 == 0 else Color("#76edff")
		var settle := smoothstep(float(index) * 0.025, 0.22 + float(index) * 0.025, _elapsed)
		var origin: Vector2 = center + Vector2(-unit, -unit * 2.8) + cells[index] * unit + Vector2(0.0, (1.0 - settle) * -18.0)
		Art.draw_block(self, Rect2(origin, Vector2.ONE * (unit - 1.0)), color, alpha)
	_draw_centered("FUNBLOCK", center + Vector2(0.0, unit * 0.75), clampi(roundi(unit * 1.24), 18, 32), Color(0.96, 0.99, 1.0, alpha))
	_draw_centered("S T U D I O", center + Vector2(0.0, unit * 1.75), clampi(roundi(unit * 0.54), 10, 15), Color(0.72, 0.88, 1.0, alpha))

func _draw_spinner() -> void:
	var alpha := smoothstep(0.76, 0.90, _elapsed) * (1.0 - smoothstep(1.30, 1.53, _elapsed))
	if alpha <= 0.0:
		return
	var unit := clampf(minf(size.x, size.y) * 0.025, 10.0, 17.0) * SPINNER_SIZE_SCALE
	var center := _content_rect.position + _content_rect.size * Vector2(0.5, 0.55)
	draw_set_transform(center, (_elapsed - 0.8) * 4.0)
	for cell: Vector2 in [Vector2(-1.5, -0.5), Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-1.5, 0.5)]:
		# Rotate the larger piece around its bounding-box center, without orbiting.
		var origin := (cell - Vector2(0.0, 0.5)) * unit + Vector2.ONE * 0.5
		Art.draw_block(self, Rect2(origin, Vector2.ONE * (unit - 1.0)), Color("#ffd149"), alpha)
	draw_set_transform(Vector2.ZERO)

func _draw_centered(message: String, center: Vector2, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(_font, center - Vector2(width * 0.5, 0.0), message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
