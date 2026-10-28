extends SceneTree

const Settings = preload("res://scripts/ui/settings_panel.gd")
const L10n = preload("res://scripts/localization/game_locale.gd")
const Avatar = preload("res://scripts/ui/leaderboard_avatar.gd")
const AVATAR_DESCRIPTIONS := {
	"zh_CN": ["黄色方块", "绿色方块", "紫色星星", "青色菱形", "红色方块", "橙色小熊"],
	"en": ["Yellow block", "Green block", "Purple star", "Cyan diamond", "Red block", "Orange bear"],
	"fr": ["Bloc jaune", "Bloc vert", "Étoile violette", "Losange cyan", "Bloc rouge", "Ours orange"],
}
var failures := 0
var checks := 0
var profile_requests := 0
var binding_requests := 0
var saves: Array[Dictionary] = []
var closes := 0

class GameplayProbe:
	extends Node
	var leaked := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.keycode in [KEY_ENTER, KEY_ESCAPE]:
			leaked += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	L10n.set_language("zh_CN")
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(360, 640)
	var settings = Settings.new()
	settings.size = Vector2(360, 640)
	root.add_child(settings)
	await process_frame
	await _test_settings(settings)
	settings.free()
	var path := "res://scripts/ui/player_profile_dialog.gd"
	_check(ResourceLoader.exists(path), "profile dialog implementation exists")
	if ResourceLoader.exists(path):
		await _test_dialog(load(path).new())
	print("Player profile: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_settings(panel: Control) -> void:
	var edit: Button = panel.get_action_button("ProfileButton")
	var google: Button = panel.get_action_button("GoogleBindingButton")
	_check(edit != null, "settings exposes native edit-profile action")
	_check(google != null, "settings exposes native Google-binding action")
	if edit == null or google == null:
		return
	panel.profile_requested.connect(func(): profile_requests += 1)
	panel.google_binding_requested.connect(func(): binding_requests += 1)
	panel.apply_state({"sound_enabled": false, "reduced_motion": true}, true, true)
	_check(panel.get_action_button("PreviewSoundButton").disabled, "existing sound toggle contract preserved")
	_check(panel.get_action_button("RestartButton").visible, "existing in-game actions preserved")
	panel.apply_account({"nickname": "Élodie", "avatar": 4, "bound": false, "available": false})
	_check(google.disabled, "backend unavailable disables binding")
	_check(_label(panel, "AccountServiceStatus").text == L10n.t("账号服务尚未开放，本机存档正常保存"), "unavailable explanation remains visible")
	_check(_label(panel, "AccountNickname").text == "Élodie", "nickname is not localized")
	edit.pressed.emit()
	google.pressed.emit()
	_check(profile_requests == 1 and binding_requests == 0, "profile emits request; disabled binding callback cannot fake success")
	panel.apply_account({"nickname": "玩家42", "avatar": 0, "bound": false, "available": true, "sync_status": "Synchronisation…"})
	_check(not google.disabled, "available backend enables explicit binding request")
	google.pressed.emit()
	_check(binding_requests == 1 and google.text == L10n.t("绑定 Google 账号"), "request never changes binding state")
	_check(_label(panel, "AccountSyncStatus").text == "Synchronisation…", "supplied localized sync status is preserved")
	panel.apply_account({"nickname": "玩家42", "bound": true, "available": true, "save_failed": true})
	_check(google.text == L10n.t("管理绑定"), "bound state only comes from parent")
	_check(_label(panel, "AccountSaveStatus").text == L10n.t("本机存档保存失败，请重试"), "save failure never claims local save success")
	panel.apply_account({"save_failed": true, "available": false})
	_check(not _label(panel, "AccountServiceStatus").text.contains("正常保存"), "unavailable warning does not contradict a failed save")
	panel.apply_account({"available": true})
	await process_frame
	var candidates: Array = panel._focus_candidates()
	_check(candidates.has(edit) and candidates.has(google), "both account actions join settings focus chain")
	_check(candidates.find(edit) < candidates.find(panel.get_action_button("BackButton")), "profile precedes back action")
	google.grab_focus()
	await process_frame
	await process_frame
	var scroll: ScrollContainer = panel.get_node("Scroll")
	_check(scroll.scroll_vertical > 0, "account keyboard focus follows native scroll")
	_check(scroll.size.x <= 360 and scroll.get_h_scroll_bar().max_value <= scroll.size.x + 1, "account card fits 360px without horizontal overflow")
	panel.apply_account({"available": false})
	_check(edit.get_node(edit.focus_next) != google, "disabled Google action skipped by Tab")
	for code in AVATAR_DESCRIPTIONS:
		L10n.set_language(code)
		for index in range(6):
			panel.apply_account({"nickname": "设置", "avatar": index})
			var icon: Control = panel.find_child("AccountAvatar", true, false)
			_check(icon.get_script() == Avatar and icon.avatar == index, "account card uses leaderboard renderer and ID %d" % index)
			_check(icon.accessibility_name == AVATAR_DESCRIPTIONS[code][index], "account avatar describes actual artwork: %s/%d" % [code, index])
	L10n.set_language("zh_CN")

func _test_dialog(dialog: Control) -> void:
	var probe := GameplayProbe.new()
	root.add_child(probe)
	root.add_child(dialog)
	dialog.profile_saved.connect(func(nickname: String, avatar: int): saves.append({"nickname": nickname, "avatar": avatar}))
	dialog.close_requested.connect(func(): closes += 1)
	var original := {"nickname": "Élodie", "avatar": 2}
	dialog.open_profile(original)
	await process_frame
	await process_frame
	var input: LineEdit = dialog.find_child("NicknameInput", true, false)
	var save: Button = dialog.find_child("SaveButton", true, false)
	var cancel: Button = dialog.find_child("CancelButton", true, false)
	_check(input != null and save != null and cancel != null, "modal offers native nickname/save/cancel controls")
	if input == null or save == null or cancel == null:
		dialog.free()
		probe.free()
		return
	_check(input.text == "Élodie" and input.has_focus(), "opening copies nickname and focuses editor")
	for bad in ["A", "1234567890123", "[b]x[/b]", "<xx>", "ab\u0001", "ab\u200b", "ab\u202e"]:
		input.text = bad
		save.pressed.emit()
		_check(saves.is_empty() and dialog.visible, "invalid nickname rejected: " + bad.c_escape())
	for index in range(6):
		var avatar: Button = dialog.find_child("Avatar%d" % index, true, false)
		_check(avatar != null, "builtin avatar %d exists" % index)
		if avatar != null:
			avatar.pressed.emit()
			_check(avatar.button_pressed, "avatar selection is visible")
	input.text = "François"
	save.pressed.emit()
	_check(saves.size() == 1 and saves[0] == {"nickname": "François", "avatar": 5}, "save emits accented nickname and selected avatar")
	_check(dialog.visible and original == {"nickname": "Élodie", "avatar": 2}, "save awaits parent acceptance without mutating original")
	dialog.show_error("本机存档保存失败，请重试")
	_check(_label(dialog, "ProfileError").visible, "parent rejection stays visible")
	_check(input.text == "François", "parent error preserves draft")
	dialog.close_dialog()
	_check(not dialog.visible, "parent acceptance closes dialog")
	dialog.open_profile(original)
	await process_frame
	_check(input.text == "Élodie", "reopening discards unaccepted draft")
	input.text = "玩家测试"
	_push_key(KEY_ENTER, true)
	_push_key(KEY_ENTER, false)
	_check(saves.size() == 2 and dialog.visible, "Enter saves once but waits for parent")
	_push_key(KEY_ESCAPE, true)
	_push_key(KEY_ESCAPE, false)
	_check(closes == 1, "Escape requests modal close once")
	_check(probe.leaked == 0, "Enter/Escape press and release do not reach gameplay")
	dialog.close_dialog()
	dialog.open_profile(original)
	await process_frame
	cancel.pressed.emit()
	_check(closes == 2 and saves.size() == 2, "cancel never saves")
	for code in ["zh_CN", "en", "fr"]:
		L10n.set_language(code)
		dialog.open_profile(original)
		await process_frame
		await process_frame
		_check(input.text == "Élodie", "locale change preserves player content")
		for index in range(6):
			var option: Button = dialog.find_child("Avatar%d" % index, true, false)
			var icon: Control = option.get_child(0)
			_check(icon.get_script() == Avatar and icon.avatar == index, "profile option uses leaderboard renderer and ID %d" % index)
			_check(option.accessibility_name == AVATAR_DESCRIPTIONS[code][index] and option.tooltip_text == AVATAR_DESCRIPTIONS[code][index], "profile avatar describes actual artwork: %s/%d" % [code, index])
		var scroll: ScrollContainer = dialog.find_child("ProfileScroll", true, false)
		_check(scroll.size.x <= 360 and scroll.get_h_scroll_bar().max_value <= scroll.size.x + 1, "modal fits 360px: " + code)
		cancel.grab_focus()
		_push_key(KEY_TAB, true)
		_push_key(KEY_TAB, false)
		_check(dialog.is_ancestor_of(root.gui_get_focus_owner()), "Tab stays in modal")
	# Native mouse hit testing, Unicode boundaries, and synchronous parent close.
	L10n.set_language("zh_CN")
	for example in [["Éa", "Éa"], ["123456789012", "123456789012"], ["E\u0301lodie", "Élodie"], ["e\u0301".repeat(7), "é".repeat(7)], ["  Élodie  ", "Élodie"]]:
		dialog.open_profile(original)
		input.text = example[0]
		var before := saves.size()
		save.pressed.emit()
		_check(saves.size() == before + 1 and saves[-1].nickname == example[1], "client normalizes French accents and edges before length validation: " + str(example[0]))
		save.pressed.emit()
		_check(saves.size() == before + 1, "pending submission cannot save twice")
		dialog.show_error("本机存档保存失败，请重试")
	for nickname in ["é".repeat(13), "ab!", "_abc"]:
		dialog.open_profile(original)
		input.text = nickname
		var before := saves.size()
		save.pressed.emit()
		_check(saves.size() == before and _label(dialog, "ProfileError").visible and not save.disabled, "shared nickname validation rejects invalid draft: " + nickname)
	var accept := func(_nickname: String, _avatar: int): dialog.close_dialog()
	dialog.profile_saved.connect(accept)
	dialog.open_profile(original)
	await process_frame
	input.grab_focus()
	_push_key(KEY_ENTER, true)
	_push_key(KEY_ENTER, false)
	_check(not dialog.visible and probe.leaked == 0, "synchronous acceptance still swallows Enter release")
	dialog.profile_saved.disconnect(accept)
	var close := func(): dialog.close_dialog()
	dialog.close_requested.connect(close)
	dialog.open_profile(original)
	await process_frame
	_push_key(KEY_ESCAPE, true)
	_push_key(KEY_ESCAPE, false)
	_check(not dialog.visible and probe.leaked == 0, "synchronous cancellation still swallows Escape release")
	dialog.close_requested.disconnect(close)
	root.size = Vector2i(360, 320)
	dialog.open_profile(original)
	await process_frame
	await process_frame
	var profile_scroll: ScrollContainer = dialog.find_child("ProfileScroll", true, false)
	cancel.grab_focus()
	await process_frame
	await process_frame
	_check(profile_scroll.scroll_vertical > 0, "short-screen cancel is reachable by focus scrolling")
	_check(profile_scroll.get_global_rect().end.y <= 320, "short-screen scroll remains in viewport")
	var before_close := closes
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = cancel.get_global_rect().get_center()
	click.pressed = true
	root.push_input(click)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click)
	_check(closes == before_close + 1, "native mouse click activates Cancel on short screen")
	dialog.free()
	probe.free()

func _push_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	root.push_input(event)

func _label(node: Node, name_value: String) -> Label:
	return node.find_child(name_value, true, false) as Label

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
