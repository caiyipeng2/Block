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
	_check(Bots.target_count() == 100 and Bots.refresh_seconds() >= 86400 and Bots.week_refresh_seconds() >= 604800, "bot daily and weekly settings are bounded")
	_test_classic_fill()
	_test_adventure_rule_order()
	_test_sparse_adventure_distribution()
	_test_replacement_thresholds()
	_test_epoch_changes()
	_test_daily_weekly_cycles()
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

func _test_sparse_adventure_distribution() -> void:
	var result: Dictionary = Bots.fill("adventure", [], 0, 100, 20000)
	var entries: Array = result["entries"]
	var completed_values := {}
	var under_24 := 0
	var maximum := 0
	for entry: Dictionary in entries:
		var completed := int(entry.get("completed", 0))
		completed_values[completed] = true
		maximum = maxi(maximum, completed)
		if completed <= 24:
			under_24 += 1
	_check(maximum <= 60, "sparse adventure bots stay below the replacement ceiling")
	_check(under_24 >= 80, "most sparse adventure bots remain low or mid progression")
	_check(completed_values.size() >= 10, "sparse adventure bots use varied completion bands")

func _test_replacement_thresholds() -> void:
	var baseline: Dictionary = Bots.fill("classic", [], 0, 100, 20000)
	var bots: Array = baseline["entries"]
	var strongest := int(bots[0].get("score", 0))
	var weakest := int(bots[bots.size() - 1].get("score", 0))
	var low_player := [{"account_id": "real-low", "nickname": "低分玩家", "avatar": 0, "score": maxi(0, weakest - 1), "completed": 0}]
	var low_result: Dictionary = Bots.fill("classic", low_player, 1, 100, 20000)
	_check(not _contains_account(low_result["entries"], "real-low"), "a player below every bot does not displace a bot")
	_check(_count_bots(low_result["entries"]) == 100, "low player leaves all visible bot slots intact")
	var high_player := [{"account_id": "real-high", "nickname": "高分玩家", "avatar": 0, "score": strongest + 1, "completed": 0}]
	var high_result: Dictionary = Bots.fill("classic", high_player, 1, 100, 20000)
	_check(_contains_account(high_result["entries"], "real-high"), "a player above a bot enters the visible board")
	_check(_count_bots(high_result["entries"]) == 99, "a qualifying player displaces one bot")

func _test_daily_weekly_cycles() -> void:
	var day_one: Dictionary = Bots.fill("free", [], 0, 100, 20000)
	var same_day: Dictionary = Bots.fill("free", [], 0, 100, 20000)
	var next_day: Dictionary = Bots.fill("free", [], 0, 100, 20001, {}, 2857, day_one["entries"])
	_check(_snapshot(day_one["entries"]) == _snapshot(same_day["entries"]), "same day bot snapshot is deterministic")
	_check(_count_changed_scores(day_one["entries"], next_day["entries"]) > 0, "daily cycle changes some bot scores")
	_check(_no_score_decrease(day_one["entries"], next_day["entries"]), "daily bot best scores never decrease")
	var next_week: Dictionary = Bots.fill("free", [], 0, 100, 20007, {}, 2858, next_day["entries"])
	_check(_count_shared_accounts(next_day["entries"], next_week["entries"]) >= 70, "weekly cycle preserves most bot identities")
	_check(_count_shared_accounts(next_day["entries"], next_week["entries"]) < 100, "weekly cycle replaces part of the bot population")

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

func _contains_account(entries: Array, account_id: String) -> bool:
	for entry: Dictionary in entries:
		if str(entry.get("account_id", "")) == account_id:
			return true
	return false

func _snapshot(entries: Array) -> String:
	var result: Array = []
	for entry: Dictionary in entries:
		result.append([entry.get("account_id", ""), entry.get("nickname", ""), entry.get("score", 0), entry.get("completed", 0), entry.get("rank", 0)])
	return JSON.stringify(result)

func _count_changed_scores(before: Array, after: Array) -> int:
	var previous := {}
	for entry: Dictionary in before:
		previous[str(entry.get("account_id", ""))] = int(entry.get("score", 0))
	var changed := 0
	for entry: Dictionary in after:
		var account_id := str(entry.get("account_id", ""))
		if previous.has(account_id) and previous[account_id] != int(entry.get("score", 0)):
			changed += 1
	return changed

func _no_score_decrease(before: Array, after: Array) -> bool:
	var previous := {}
	for entry: Dictionary in before:
		previous[str(entry.get("account_id", ""))] = int(entry.get("score", 0))
	for entry: Dictionary in after:
		var account_id := str(entry.get("account_id", ""))
		if previous.has(account_id) and int(entry.get("score", 0)) < previous[account_id]:
			return false
	return true

func _count_shared_accounts(before: Array, after: Array) -> int:
	var previous := {}
	for entry: Dictionary in before:
		previous[str(entry.get("account_id", ""))] = true
	var shared := 0
	for entry: Dictionary in after:
		if previous.has(str(entry.get("account_id", ""))):
			shared += 1
	return shared

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
