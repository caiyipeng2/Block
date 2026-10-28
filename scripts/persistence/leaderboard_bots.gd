extends RefCounted

## Local presentation filler for a configured board response. Bots never enter
## the verified submission queue and are marked internally so real players can
## replace them as the server's real-player count grows.
const TARGET_COUNT := 100
const REFRESH_SECONDS := 1800
const NAME_LEFT := [
	"晨星", "青柠", "星光", "夜航", "小满", "长风", "蓝莓", "橙子", "木槿", "流云",
	"微光", "云朵", "拾光", "南风", "白露", "晴空", "月桂", "松果", "星河", "海盐",
	"纸飞机", "小岛", "远山", "薄荷", "初雪", "橘子", "柚子", "栗子", "风铃", "朝露",
	"落日", "闪电", "秋水", "山茶", "雨声", "蒲公英", "蓝鲸", "松鼠", "月面", "风筝",
]
const NAME_RIGHT := [
	"方块", "星尘", "积木", "拼图", "小队", "旅人", "小熊", "小鹿", "小龙", "小鱼",
	"队长", "高手", "达人", "棋手", "探险家", "收藏家", "清线手", "落点师", "连消王", "小方格",
]

static func current_epoch(now: int = -1) -> int:
	var timestamp := now if now >= 0 else int(Time.get_unix_time_from_system())
	return floori(float(timestamp) / float(refresh_seconds()))

static func target_count() -> int:
	return clampi(int(ProjectSettings.get_setting("leaderboard/bot_target_count", TARGET_COUNT)), 1, TARGET_COUNT)

static func refresh_seconds() -> int:
	return maxi(60, int(ProjectSettings.get_setting("leaderboard/bot_refresh_seconds", REFRESH_SECONDS)))

static func fill(mode: String, entries: Array, real_player_count: int, target_count: int = TARGET_COUNT, epoch: int = -1, me: Dictionary = {}) -> Dictionary:
	var target := clampi(target_count, 1, TARGET_COUNT)
	var refresh_epoch := current_epoch() if epoch < 0 else epoch
	var real: Array[Dictionary] = []
	var seen := {}
	for raw: Variant in entries:
		if not raw is Dictionary or bool(raw.get("is_bot", false)):
			continue
		var account_id := str(raw.get("account_id", ""))
		if account_id.is_empty() or seen.has(account_id):
			continue
		var copy: Dictionary = raw.duplicate(true)
		seen[account_id] = true
		real.append(copy)
	if not me.is_empty() and int(me.get("rank", 0)) > 0 and int(me.get("rank", 0)) <= target:
		var me_id := str(me.get("account_id", ""))
		if not me_id.is_empty() and not seen.has(me_id):
			var me_copy: Dictionary = me.duplicate(true)
			real.append(me_copy)
			seen[me_id] = true
	var known_real_count := maxi(real_player_count, real.size())
	var bot_count := maxi(0, target - real.size()) if known_real_count < target else 0
	for slot in range(bot_count):
		real.append(_make_bot(mode, slot, refresh_epoch, real))
	_sort_entries(real, mode)
	_assign_ranks(real, mode)
	return {"entries": real.slice(0, target), "real_player_count": known_real_count, "bot_count": bot_count, "bot_epoch": refresh_epoch}

static func _make_bot(mode: String, slot: int, epoch: int, real: Array[Dictionary]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(mode, slot, epoch)
	var name_index := posmod(_mode_offset(mode) + epoch * 13 + slot * 7, NAME_LEFT.size())
	var suffix_index := posmod(_mode_offset(mode) * 3 + epoch * 17 + slot * 11, NAME_RIGHT.size())
	var nickname: String = str(NAME_LEFT[name_index]) + str(NAME_RIGHT[suffix_index])
	if slot >= NAME_LEFT.size():
		nickname += str((slot % 9) + 1)
	var score_floor := _minimum_score(real)
	var completed_floor := _minimum_completed(real)
	var score := 0
	var completed := 0
	if real.is_empty():
		if mode == "adventure":
			completed = clampi(96 - int(float(slot) * 0.88) + rng.randi_range(-2, 2), 0, 96)
			score = maxi(0, completed * 2600 + rng.randi_range(0, 2600) - slot * 37)
		else:
			var base := 72000 if mode == "free" else 54000
			score = maxi(0, base - slot * 520 + rng.randi_range(-220, 220))
	else:
		if mode == "adventure":
			completed = completed_floor
			var step := maxi(1, int(score_floor / maxi(2, real.size() + 1)))
			score = maxi(0, score_floor - (slot + 1) * step + rng.randi_range(-step / 3, step / 3))
		else:
			var step := maxi(1, int(score_floor / maxi(2, real.size() + 1)))
			score = maxi(0, score_floor - (slot + 1) * step + rng.randi_range(-step / 3, step / 3))
	return {
		"account_id": "bot:%s:%03d" % [mode, slot],
		"nickname": nickname,
		"avatar": posmod(slot + epoch + _mode_offset(mode), 6),
		"score": score,
		"completed": completed,
		"is_bot": true,
		"bot_epoch": epoch,
	}

static func _sort_entries(entries: Array[Dictionary], mode: String) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var compared := _compare(a, b, mode)
		if compared != 0:
			return compared > 0
		return str(a.get("account_id", "")) < str(b.get("account_id", ""))
	)

static func _assign_ranks(entries: Array[Dictionary], mode: String) -> void:
	var previous: Dictionary = {}
	var rank := 0
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		if index == 0 or _compare(entry, previous, mode) != 0:
			rank = index + 1
		entry["rank"] = rank
		previous = entry

static func _compare(a: Dictionary, b: Dictionary, mode: String) -> int:
	if mode == "adventure":
		var completed_delta := int(a.get("completed", 0)) - int(b.get("completed", 0))
		if completed_delta != 0:
			return completed_delta
	return int(a.get("score", 0)) - int(b.get("score", 0))

static func _minimum_score(entries: Array[Dictionary]) -> int:
	if entries.is_empty():
		return 0
	var result := int(entries[0].get("score", 0))
	for entry: Dictionary in entries:
		result = mini(result, int(entry.get("score", 0)))
	return result

static func _minimum_completed(entries: Array[Dictionary]) -> int:
	if entries.is_empty():
		return 0
	var result := int(entries[0].get("completed", 0))
	for entry: Dictionary in entries:
		result = mini(result, int(entry.get("completed", 0)))
	return result

static func _mode_offset(mode: String) -> int:
	match mode:
		"adventure": return 11
		"classic": return 23
		_: return 37

static func _seed(mode: String, slot: int, epoch: int) -> int:
	var value := 17 + _mode_offset(mode)
	for character in mode:
		value = value * 31 + character.unicode_at(0)
	return absi(value + slot * 7919 + epoch * 104729)
