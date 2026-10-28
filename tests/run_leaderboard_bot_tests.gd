extends SceneTree

const Bots := preload("res://scripts/persistence/leaderboard_bots.gd")

var _failures := 0

func _initialize() -> void:
	_run()
	quit(0 if _failures == 0 else 1)

func _run() -> void:
	_check(ResourceLoader.exists("res://scripts/persistence/leaderboard_bots.gd"), "leaderboard bot filler exists")
	if not ResourceLoader.exists("res://scripts/persistence/leaderboard_bots.gd"):
		return
	_check(Bots.target_count() == 100 and Bots.refresh_seconds() >= 60, "bot target and refresh settings are bounded")
	_test_classic_fill()
	_test_adventure_rule_order()
	_test_epoch_changes()
	_test_real_player_cutover()
	if _failures == 0:
		print("LEADERBOARD BOT TESTS PASSED")

func _test_classic_fill() -> void:
	var real := [
		{"account_id": "real-a", "nickname": "晨星", "avatar": 0, "score": 18000, "completed": 0},
		{"account_id": "real-b", "nickname": "小满", "avatar": 1, "score": 15000, "completed": 0},
		{"account_id": "real-c", "nickname": "积木熊", "avatar": 2, "score": 12000, "completed": 0},
	]
	var result: Dictionary = Bots.fill("classic", real, 3, 100, 100)
	var entries: Array = result["entries"]
	_check(entries.size() == 100, "classic fills the visible board to 100 entries")
	_check(_count_bots(entries) == 97, "classic uses bots only for missing real-player slots")
	_check(_count_real(entries) == 3, "classic preserves every real player")
	_check(_is_sorted(entries, "classic"), "classic bot scores obey descending score order")
	_check(_valid_ranks(entries, "classic"), "classic bot ranks use competition ranking")
	_check(_unique_bot_names(entries), "classic bot names are unique within one refresh epoch")

func _test_adventure_rule_order() -> void:
	var real := [
		{"account_id": "real-a", "nickname": "方块王者", "avatar": 0, "score": 268540, "completed": 96},
		{"account_id": "real-b", "nickname": "青柠方块", "avatar": 1, "score": 251800, "completed": 96},
	]
	var result: Dictionary = Bots.fill("adventure", real, 2, 100, 101)
	var entries: Array = result["entries"]
	_check(entries.size() == 100, "adventure fills the visible board to 100 entries")
	_check(_count_bots(entries) == 98, "adventure uses bots for missing players")
	_check(_is_sorted(entries, "adventure"), "adventure bots obey completed-level then total-score order")
	_check(_valid_ranks(entries, "adventure"), "adventure bot ranks use both ranking keys")

func _test_epoch_changes() -> void:
	var first: Dictionary = Bots.fill("free", [], 0, 100, 200)
	var second: Dictionary = Bots.fill("free", [], 0, 100, 201)
	var first_entry: Dictionary = first["entries"][0]
	var second_entry: Dictionary = second["entries"][0]
	_check(first_entry["is_bot"] and second_entry["is_bot"], "bot entries carry internal bot metadata")
	_check(first_entry["nickname"] != second_entry["nickname"] or first_entry["score"] != second_entry["score"], "bot names or scores change between refresh epochs")

func _test_real_player_cutover() -> void:
	var real: Array = []
	for index in range(100):
		real.append({"account_id": "real-%03d" % index, "nickname": "玩家%03d" % index, "avatar": index % 6, "score": 200000 - index * 100, "completed": 0})
	var result: Dictionary = Bots.fill("free", real, 100, 100, 300)
	var entries: Array = result["entries"]
	_check(entries.size() == 100, "100 real players keep a full board")
	_check(_count_bots(entries) == 0, "bots disappear when real players reach 100")
	_check(_count_real(entries) == 100, "all real players remain after bot cutover")

func _count_bots(entries: Array) -> int:
	var count := 0
	for entry: Dictionary in entries:
		if bool(entry.get("is_bot", false)):
			count += 1
	return count

func _count_real(entries: Array) -> int:
	return entries.size() - _count_bots(entries)

func _unique_bot_names(entries: Array) -> bool:
	var names := {}
	for entry: Dictionary in entries:
		if not bool(entry.get("is_bot", false)):
			continue
		var nickname := str(entry.get("nickname", ""))
		if names.has(nickname):
			return false
		names[nickname] = true
	return true

func _is_sorted(entries: Array, mode: String) -> bool:
	for index in range(1, entries.size()):
		var previous: Dictionary = entries[index - 1]
		var current: Dictionary = entries[index]
		var previous_key := [int(previous.get("completed", 0)), int(previous.get("score", 0))] if mode == "adventure" else [int(previous.get("score", 0))]
		var current_key := [int(current.get("completed", 0)), int(current.get("score", 0))] if mode == "adventure" else [int(current.get("score", 0))]
		if current_key > previous_key:
			return false
	return true

func _valid_ranks(entries: Array, mode: String) -> bool:
	var previous_key := []
	var previous_rank := 0
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var key := [int(entry.get("completed", 0)), int(entry.get("score", 0))] if mode == "adventure" else [int(entry.get("score", 0))]
		var expected := previous_rank if index > 0 and key == previous_key else index + 1
		if int(entry.get("rank", 0)) != expected:
			return false
		previous_key = key
		previous_rank = expected
	return true

func _check(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("BOT TEST: " + message)
