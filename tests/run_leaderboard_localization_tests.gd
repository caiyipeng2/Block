extends SceneTree

## Focused headless localization coverage: no Main, network, audio or save writes.
const L10n := preload("res://scripts/localization/game_locale.gd")
const Leaderboard := preload("res://scripts/ui/leaderboard_panel.gd")
const Profile := preload("res://scripts/ui/player_profile_dialog.gd")
const Settings := preload("res://scripts/ui/settings_panel.gd")
const Avatar := preload("res://scripts/ui/leaderboard_avatar.gd")
const RESULT_KEYS := ["查看排行榜", "上次全球排名：%d", "仅保存于本机", "成绩待同步", "尚未上榜",
	"成绩暂时无法保存到同步队列", "这次成绩未计入排行榜", "昵称为2–12个字符，不含控制字符或标记"]
const STATUS_KEYS := {
	"unconfigured": "排行榜服务尚未开放", "loading": "加载中…",
	"empty": "还没有玩家上榜，来创造第一条纪录吧", "offline": "暂时无法连接排行榜",
	"error": "暂时无法连接排行榜", "maintenance": "排行榜维护中，请稍后重试"
}

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(L10n.CATALOG_PATH))
	L10n.initialize()
	L10n.clear_missing_keys()
	root.size = Vector2i(390, 844)
	var board := Leaderboard.new()
	var profile := Profile.new()
	var settings := Settings.new()
	var surfaces: Array[SubViewport] = []
	# Independent focus scopes keep this suite about localization, not modal routing.
	for control: Control in [board, profile, settings]:
		var surface := SubViewport.new()
		surface.size = Vector2i(390, 844)
		root.add_child(surface)
		surface.add_child(control)
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		surfaces.append(surface)
	# Deliberate catalog-key collisions catch accidental translation of player names.
	var entry := {"account_id": "fixture", "nickname": "设置", "rank": 1234, "completed": 12, "score": 12345}
	board.apply_view({"mode": "adventure", "status": "ready", "entries": [entry],
		"me": entry, "profile": {"nickname": "设置", "avatar": 2}, "neighbors": [entry],
		"pending": {"eligible": true, "completed": 13, "score": 23456}, "updated_at": 1700000000})
	profile.open_profile({"nickname": "排行榜", "avatar": 2})
	profile.show_error(RESULT_KEYS[7])
	settings.apply_account({"nickname": "玩家", "avatar": 2})
	for code: String in ["en", "fr", "zh_CN", "fr", "en"]:
		L10n.set_language(code)
		await process_frame
		await process_frame
		for source: String in catalog:
			_equal(L10n.t(source), catalog[source].get(code, source), "%s runtime catalog: %s" % [code, source])
		for source: String in RESULT_KEYS:
			_check(catalog.has(source), "required result/notice key: " + source)
		_equal(L10n.t("上次全球排名：%d") % 1234,
			{"en": "Last global rank: 1234", "fr": "Dernier rang mondial : 1234", "zh_CN": "上次全球排名：1234"}[code], "formatted global rank")
		_equal(board.get("_title").text, L10n.t("排行榜"), "live leaderboard title")
		_equal(board.get("_rules").text, L10n.t(Leaderboard.RULES), "live leaderboard rules")
		_equal(board.get_action_button("AdventureTab").text, L10n.t("闯关模式"), "live Adventure tab")
		_equal(board.get_action_button("ClassicTab").text, L10n.t("经典模式"), "live Classic tab")
		_equal(board.get_action_button("FreeTab").text, L10n.t("自由模式"), "live Free Play tab")
		var number := "12\u202f345" if code == "fr" else "12,345"
		_equal(board.get("_personal_score").text, L10n.t("%s关") % "12" + "\n" + number, "localized level count and grouped score")
		_equal(board.get("_updated").text, L10n.t("上次更新：%s（UTC）") % "2023-11-14 22:13:20", "localized UTC timestamp")
		_equal(board.get_action_button("ProfileButton").text, "设置", "personal nickname unchanged")
		_equal(board.get_action_button("ProfileButton").auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED, "personal nickname bypasses automatic translation")
		_check_names(board, "Nickname", "设置")
		_equal(profile.get("_title").text, L10n.t("编辑资料"), "open profile title refreshes")
		_equal(profile.get("_error").text, L10n.t(RESULT_KEYS[7]), "open invalid nickname error refreshes")
		_equal(profile.get("_input_field").text, "排行榜", "draft nickname unchanged")
		_equal(profile.get("_input_field").auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED, "draft bypasses automatic translation")
		_equal(profile.get("_save").text, L10n.t("保存"), "profile Save refreshes")
		_equal(profile.get("_cancel").text, L10n.t("取消"), "profile Cancel refreshes")
		for index in range(6):
			var source: String = Avatar.NAMES.zh_CN[index]
			_equal(Avatar.display_name(index), L10n.t(source), "avatar description matches catalog")
			_equal(profile.get("_avatars")[index].tooltip_text, L10n.t(source), "avatar tooltip refreshes")
			_equal(profile.get("_avatars")[index].accessibility_name, L10n.t(source), "avatar accessibility name refreshes")
		_equal(settings.get("_account_labels")["AccountNickname"].text, "玩家", "account nickname unchanged")
		_equal(settings.get("_account_labels")["AccountNickname"].auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED, "account nickname bypasses automatic translation")
		_equal(settings.get("_account_labels")["AccountServiceStatus"].text, L10n.t("账号服务尚未开放，本机存档正常保存"), "account service status refreshes")
		_equal(settings.get_action_button("ProfileButton").text, L10n.t("编辑资料"), "settings profile action refreshes")
		for status: String in STATUS_KEYS:
			_equal(board.call("_status_text", status, false), L10n.t(STATUS_KEYS[status]), "localized status: " + status)
		for status: String in ["offline", "error"]:
			_equal(board.call("_status_text", status, true), L10n.t("离线 · 显示上次排名"), "localized cached status")
	for code: String in L10n.SUPPORTED_CODES:
		L10n.set_language(code)
		for mode: String in ["adventure", "classic", "free"]:
			board.apply_view({"mode": mode, "status": "empty", "pending": {"eligible": false, "score": 0}})
			_equal(board.get_action_button("NeighborsButton").text, L10n.t("尚未上榜"), "unranked label")
			_equal(board.get("_eligibility").text, L10n.t("通关后可上榜" if mode == "adventure" else "取得正分后可上榜"), "mode eligibility")
			_check(board.get("_pending").text.begins_with(L10n.t("仅本机：%s") % ""), "local-only pending label")
		settings.apply_account({"save_failed": true, "bound": true})
		_equal(settings.get("_account_labels")["AccountSaveStatus"].text, L10n.t("本机存档保存失败，请重试"), "account save failure")
		_equal(settings.get_action_button("GoogleBindingButton").text, L10n.t("管理绑定"), "linked account action")
	_equal(Array(L10n.missing_keys()), [], "no runtime missing keys")
	await process_frame
	for surface: SubViewport in surfaces:
		surface.free()
	print("LEADERBOARD LOCALIZATION TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check_names(board: Node, node_name: String, expected: String) -> void:
	var names := board.find_children(node_name, "Label", true, false)
	_equal(names.size(), 2, "podium and neighbor nickname fixtures")
	for label: Label in names:
		_equal(label.text, expected, "public nickname unchanged")
		_equal(label.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED, "public nickname bypasses automatic translation")

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s: expected %s, got %s" % [message, str(expected), str(actual)])
