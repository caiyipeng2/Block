extends SceneTree

const L10n := preload("res://scripts/localization/game_locale.gd")
const PANEL_PATH := "res://scripts/ui/leaderboard_panel.gd"
var checks := 0
var failures := 0
var events: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(ResourceLoader.exists(PANEL_PATH), "leaderboard panel script must exist before loading")
	if failures > 0:
		_finish()
		return
	var script = load(PANEL_PATH)
	_check(script != null and script.can_instantiate(), "panel script loads")
	if failures > 0:
		_finish()
		return
	L10n.set_language("zh_CN")
	root.size = Vector2i(360, 640)
	var panel = script.new()
	panel.apply_view({"status": "unconfigured"})
	root.add_child(panel)
	panel.size = Vector2(360, 640)
	await _settle()
	_check(panel is Control, "panel is a native Control")
	for action in ["BackButton", "RetryButton", "MoreButton", "PlayButton", "ProfileButton", "NeighborsButton", "InfoButton", "AdventureTab", "ClassicTab", "FreeTab"]:
		_check(panel.get_action_button(action) is Button, "action API: " + action)
	_check(_text(panel).contains("排行榜服务尚未开放"), "unconfigured has explicit service message")
	_check(not panel.get_action_button("PlayButton").disabled, "unconfigured keeps local gameplay available")
	_check(panel.find_child("Podium", true, false).get_child_count() == 0, "unconfigured never invents players")
	panel.apply_view({"status": "empty", "mode": "classic"})
	_check(_text(panel).contains("还没有玩家上榜"), "empty is a genuine empty state")
	_check(panel.get_action_button("NeighborsButton").text == L10n.t("尚未上榜"), "unranked is not rank zero")
	_check(_text(panel).contains("取得正分后可上榜"), "touch users see eligibility without hovering")
	panel.apply_view({"status": "offline", "has_cache": false})
	_check(_text(panel).contains("暂时无法连接排行榜"), "offline without cache is connection failure")
	_check(not _text(panel).contains("还没有玩家上榜"), "connection failure is not empty")
	var entries: Array = []
	for i in range(100):
		entries.append({"rank": 2 if i == 2 else i + 1, "account_id": "test-%d" % i, "nickname": "Test very long nickname éàç %d" % i, "avatar": i % 6, "score": 268540 - i, "completed": 96 - i / 2})
	var data := {"status": "offline", "has_cache": true, "mode": "adventure", "entries": entries, "me": {"rank": 127, "nickname": "Device", "avatar": 3, "score": 83640, "completed": 42}, "updated_at": 1793000000, "pending": {"score": 999999, "completed": 43, "eligible": true}, "profile": {"nickname": "My profile", "avatar": 5}, "next_cursor": "cursor"}
	panel.apply_view(data)
	await _settle()
	_check(_text(panel).contains("离线 · 显示上次排名"), "cached offline message")
	_check(_text(panel).contains("2026-10-26"), "cache includes full update date")
	_check(panel.get_action_button("NeighborsButton").text == "127", "pending preserves accepted rank")
	_check(panel.find_child("PersonalScore", true, false).text.contains("83,640"), "pending preserves accepted score")
	_check(panel.find_child("Pending", true, false).text.contains("999,999"), "pending shows separate score")
	_check(panel.find_child("Pending", true, false).text.contains("待同步"), "eligible pending is marked")
	var podium = panel.find_child("Podium", true, false)
	_check(podium.get_child_count() == 3, "only first three entries on podium")
	_check(podium.get_child(0).get_meta("account_id") == "test-1" and podium.get_child(1).get_meta("account_id") == "test-0", "podium uses stable second first third ordering")
	_check(podium.get_child(2).find_child("Rank", true, false).text == "2", "tied rank is not replaced by podium slot")
	var rows = panel.find_child("Rows", true, false)
	_check(rows.get_child_count() == 97, "all supplied top100 entries rendered without duplicated podium")
	_check(rows.get_child(0).find_child("Rank", true, false).text == "4", "rows use actual rank")
	for row in rows.get_children():
		_check(row.size.y >= 56, "row has minimum touch height")
		_check(row.find_child("Nickname", true, false).text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "long names ellipsize")
	_check(rows.get_child(0).find_child("Score", true, false).text.contains("\n"), "adventure metrics use two lines")
	var scroll: ScrollContainer = panel.find_child("Scroll", true, false)
	_check(scroll.follow_focus and scroll.is_ancestor_of(podium), "podium scrolls and focus follows")
	_check(not scroll.is_ancestor_of(panel.get_action_button("PlayButton")), "CTA stays outside scrolling content")
	_check(not scroll.is_ancestor_of(panel.get_action_button("ProfileButton")), "personal row stays fixed")
	_check(not panel.get_action_button("MoreButton").visible, "top100 hides more even with cursor")
	_check(scroll.size.y >= 150, "small screen preserves usable scroll area")
	var fixed_y: float = panel.get_action_button("PlayButton").global_position.y
	scroll.scroll_vertical = 300
	await _settle()
	_check(scroll.scroll_vertical > 0 and panel.get_action_button("PlayButton").global_position.y == fixed_y, "scrolling never moves CTA")
	data.entries = entries.slice(0, 20)
	data.status = "ready"
	data.neighbors = [entries[3], data.me, entries[4]]
	panel.apply_view(data)
	_check(panel.get_action_button("MoreButton").visible, "cursor offers load more below cap")
	_check(panel.find_child("Neighbors", true, false).get_child_count() == 4, "optional neighbors rendered with heading")
	panel.back_requested.connect(func(): events.append("back"))
	panel.refresh_requested.connect(func(): events.append("refresh"))
	panel.more_requested.connect(func(): events.append("more"))
	panel.profile_requested.connect(func(): events.append("profile"))
	panel.neighbors_requested.connect(func(): events.append("neighbors"))
	panel.play_requested.connect(func(mode): events.append("play:" + mode))
	panel.mode_selected.connect(func(mode): events.append("mode:" + mode))
	for action in ["BackButton", "RetryButton", "MoreButton", "ProfileButton", "NeighborsButton", "PlayButton", "ClassicTab", "FreeTab", "AdventureTab"]:
		panel.get_action_button(action).pressed.emit()
	_check(events == ["back", "refresh", "more", "profile", "neighbors", "play:adventure", "mode:classic", "mode:free", "mode:adventure"], "actions emit only their distinct signals")
	panel.get_action_button("InfoButton").pressed.emit()
	_check(panel.find_child("Rules", true, false).visible, "info toggles in-content rules")
	panel.get_action_button("InfoButton").pressed.emit()
	_check(not panel.find_child("Rules", true, false).visible, "info toggles closed")
	panel.focus_primary()
	_check(root.gui_get_focus_owner() == panel.get_action_button("PlayButton"), "primary is keyboard focusable")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	panel._unhandled_key_input(escape)
	_check(events[-1] == "back", "Escape requests back")
	var french := Translation.new()
	french.locale = "fr"
	french.add_message("排行榜", "Classement mondial")
	french.add_message("先比通关数，再比总积分", "Niveaux terminés, puis total des meilleurs scores")
	french.add_message("待同步：%s", "En attente de synchronisation : %s")
	french.add_message("通关 / 总积分", "Niveaux / Total des points")
	TranslationServer.add_translation(french)
	root.size = Vector2i(360, 480)
	panel.size = Vector2(360, 480)
	for language in ["en", "fr", "zh_CN"]:
		L10n.set_language(language)
		await _settle()
		var separator := "\u202f" if language == "fr" else ","
		_check(panel.find_child("PersonalScore", true, false).text.contains("83" + separator + "640"), "locale-specific grouping: " + language)
		_check(panel.get_action_button("ProfileButton").text == "My profile", "locale never translates nickname")
		for action in ["BackButton", "InfoButton", "AdventureTab", "ClassicTab", "FreeTab", "PlayButton", "ProfileButton", "NeighborsButton"]:
			var button: Button = panel.get_action_button(action)
			_check(button.size.x >= 48 and button.size.y >= 48, "48dp action " + action)
			_check(button.get_global_rect().end.x <= 360.1, "small-screen width " + action)
		_check(panel.get_action_button("PlayButton").get_global_rect().end.y <= 480, "short screen keeps play within safe bounds")
		_check(scroll.size.y >= 100, "short screen retains scrolling space")
		for card_node in podium.get_children():
			_check(card_node.get_global_rect().end.x <= 360, "podium never widens viewport")
		for row in panel.find_child("Rows", true, false).get_children():
			_check(row.size.x <= scroll.size.x, "rows stay within scroll viewport")
	TranslationServer.remove_translation(french)
	data.pending.eligible = false
	panel.apply_view(data)
	_check(panel.find_child("Pending", true, false).text.contains("仅本机"), "ineligible pending never claims global synchronization")
	for status in ["loading", "error", "maintenance", "unconfigured"]:
		panel.apply_view({"status": status, "entries": entries, "me": data.me})
		_check(panel.find_child("Rows", true, false).get_child_count() == 0, "uncached state discards stale entries: " + status)
		_check(not panel.get_action_button("PlayButton").disabled, "local play remains available: " + status)
	panel.apply_view({"mode": "adventure", "status": "ready", "highest_completed": 96})
	_check(panel.get_action_button("PlayButton").text == L10n.t("重玩关卡"), "completed adventure offers replay")
	panel.apply_view({"mode": "free", "status": "ready"})
	_check(panel.get_action_button("PlayButton").text == L10n.t("再来一局"), "free CTA")
	root.size = Vector2i(1280, 720)
	panel.size = Vector2(1280, 720)
	await _settle()
	var card: Control = panel.find_child("OuterCard", true, false)
	_check(card.size.x <= 480 and is_equal_approx(card.get_global_rect().get_center().x, 640), "Windows panel centered at max480dp")
	await _test_player_names(panel)
	await _test_notices(panel)
	panel.free()
	_finish()

func _test_notices(panel: Control) -> void:
	var messages := ["成绩暂时无法保存到同步队列", "这次成绩未计入排行榜"]
	for message in messages:
		panel.apply_view({"status": "ready", "notice": message})
		_check(_text(panel).contains(message), "ready view displays client notice: " + message)
	var notice := panel.find_child("Notice", true, false) as Label
	_check(notice != null, "client notice has an independent label")
	if notice == null:
		return
	var scroll := panel.find_child("Scroll", true, false) as ScrollContainer
	_check(scroll.is_ancestor_of(notice), "notice lives inside scrolling content")
	_check(notice.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "long notices wrap")
	_check(notice.get_theme_color("font_color") == Color("#ffe4a0"), "notice uses existing golden warning color")
	panel.apply_view({"status": "offline", "mode": "classic", "notice": messages[0], "pending": {"score": 100, "eligible": true}})
	_check(notice.visible and notice.text == messages[0], "notice remains visible alongside connection failure")
	_check(_text(panel).contains("暂时无法连接排行榜"), "notice does not replace status")
	_check(_text(panel).contains("待同步：100"), "notice does not replace pending score")
	L10n.set_language("fr")
	await _settle()
	_check(notice.visible and notice.text == "Impossible d'enregistrer ce résultat dans la file de synchronisation pour le moment", "existing notice refreshes when locale changes")
	panel.apply_view({"status": "ready", "notice": messages[1]})
	_check(notice.visible and notice.text == "Ce résultat n'a pas été pris en compte dans le classement", "new validation notice is localized")
	L10n.set_language("zh_CN")
	await _settle()
	panel.apply_view({"status": "ready", "notice": ""})
	_check(not notice.visible and notice.text.is_empty(), "empty notice hides and clears previous message")
	panel.apply_view({"status": "ready", "notice": messages[1]})
	_check(notice.visible and notice.text == messages[1], "new notice becomes visible after clearing")
	panel.apply_view({"status": "ready"})
	_check(not notice.visible and notice.text.is_empty(), "missing notice hides and clears previous message")

func _test_player_names(panel: Control) -> void:
	var entry := {"rank": 1, "nickname": "设置", "avatar": 3, "score": 100}
	panel.apply_view({"status": "ready", "profile": {"nickname": "设置", "avatar": 0}, "entries": [entry, entry, entry, entry], "neighbors": [entry]})
	for language in ["en", "fr"]:
		L10n.set_language(language)
		await _settle()
		_check(L10n.t("设置") != "设置", "nickname fixture is a real translation key: " + language)
		var personal: Button = panel.get_action_button("ProfileButton")
		_check(personal.text == "设置" and personal.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED, "personal nickname disables automatic translation: " + language)
		for section in ["Podium", "Rows", "Neighbors"]:
			var names := panel.find_child(section, true, false).find_children("Nickname", "Label", true, false)
			_check(not names.is_empty(), "nickname coverage exists: " + section)
			for nickname: Label in names:
				_check(nickname.text == "设置" and nickname.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED, section + " preserves literal player name: " + language)
		_check(panel.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED, "translation remains enabled on panel")
		_check(panel.find_child("Title", true, false).text == L10n.t("排行榜"), "UI labels still localize: " + language)
	L10n.set_language("zh_CN")

func _settle() -> void:
	for i in range(5):
		await process_frame

func _text(node: Node) -> String:
	var result := ""
	if node is Control and not node.visible:
		return result
	if node is Label or node is Button:
		result += node.text + "\n"
	for child in node.get_children():
		result += _text(child)
	return result

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _finish() -> void:
	print("Leaderboard panel: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
