extends RefCounted

## Presentation-only players used to keep sparse leaderboards populated.
## Bots are deliberately low/mid progression: a real player must beat a bot's
## actual ranking metric before that bot leaves the visible top 100.
const TARGET_COUNT := 100
const MODEL_VERSION := 2
const DAILY_REFRESH_SECONDS := 86400
const WEEKLY_REFRESH_SECONDS := 604800
const DAILY_REFRESH_HOUR_UTC := 4
const CLASSIC_DEFAULT_CAP := 12000
const FREE_DEFAULT_CAP := 18000

const NAME_LEFT := [
	"小满", "南风", "栗子", "晴空", "月桂", "松果", "海盐", "薄荷", "初雪", "橘子",
	"柚子", "风铃", "朝露", "秋水", "山茶", "雨声", "蓝鲸", "松鼠", "月面", "风筝",
	"晨星", "青柠", "夜航", "长风", "蓝莓", "木槿", "流云", "微光", "云朵", "拾光",
	"星河", "纸飞机", "小岛", "远山", "落日", "闪电", "蒲公英", "晚霞", "橙光", "白露",
]
const NAME_RIGHT := [
	"方块", "星尘", "积木", "拼图", "小队", "旅人", "小熊", "小鹿", "小龙", "小鱼",
	"棋手", "探险家", "收藏家", "清线手", "落点师", "小方格", "蓝调", "慢慢来", "七号", "十三",
]
const LATIN_NAMES := [
	"Luna", "Momo", "Kai", "Rin", "Nova", "Mika", "Taro", "Nori", "Aki", "Kiko",
	"Milo", "Coco", "Yuki", "Zoe", "Nana", "Echo", "Iris", "Aria", "Noah", "Leo",
	"Sora", "Mina", "Lynn", "Aster", "Pico", "Nico", "Riku", "Kuma", "Mori", "Niko",
]

static func current_epoch(now: int = -1) -> int:
	var timestamp := now if now >= 0 else int(Time.get_unix_time_from_system())
	return floori(float(timestamp - DAILY_REFRESH_HOUR_UTC * 3600) / float(refresh_seconds()))

static func current_week_epoch(now: int = -1) -> int:
	return week_epoch(now)

static func week_epoch(now: int = -1) -> int:
	var timestamp := now if now >= 0 else int(Time.get_unix_time_from_system())
	# Unix epoch started on Thursday. Adding three days makes bucket 0 begin
	# on Monday 00:00 UTC.
	return floori(float(timestamp + 3 * 86400) / float(week_refresh_seconds()))

static func target_count() -> int:
	return clampi(int(ProjectSettings.get_setting("leaderboard/bot_target_count", TARGET_COUNT)), 1, TARGET_COUNT)

static func refresh_seconds() -> int:
	return maxi(DAILY_REFRESH_SECONDS, int(ProjectSettings.get_setting("leaderboard/bot_daily_refresh_seconds", DAILY_REFRESH_SECONDS)))

static func week_refresh_seconds() -> int:
	return maxi(WEEKLY_REFRESH_SECONDS, int(ProjectSettings.get_setting("leaderboard/bot_weekly_refresh_seconds", WEEKLY_REFRESH_SECONDS)))

static func fill(mode: String, entries: Array, real_player_count: int, target_count: int = TARGET_COUNT, epoch: int = -1, me: Dictionary = {}, weekly_epoch: int = -1, previous_bots: Array = []) -> Dictionary:
	var target := clampi(target_count, 1, TARGET_COUNT)
	var day := current_epoch() if epoch < 0 else epoch
	var week := current_week_epoch() if weekly_epoch < 0 else weekly_epoch
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
			real.append(me.duplicate(true))
			seen[me_id] = true
	var known_real_count := maxi(real_player_count, real.size())
	# Generate a full synthetic population. Real entries only displace bots when
	# their actual ranking metric is high enough to survive the top-100 cut.
	var bot_seed_count := target if known_real_count < target else 0
	var previous_by_id := _previous_bot_map(previous_bots)
	var used_names := {}
	for entry: Dictionary in real:
		used_names[str(entry.get("nickname", ""))] = true
	var merged: Array[Dictionary] = real.duplicate(true)
	for slot in range(bot_seed_count):
		var bot := _make_bot(mode, slot, day, week, known_real_count, previous_by_id, used_names)
		merged.append(bot)
		used_names[str(bot["nickname"])] = true
	_sort_entries(merged, mode)
	_assign_ranks(merged, mode)
	var visible: Array = merged.slice(0, target)
	return {
		"entries": visible,
		"real_player_count": known_real_count,
		"bot_count": _count_bots(visible),
		"bot_epoch": day,
		"bot_week_epoch": week,
		"bot_model_version": MODEL_VERSION,
	}

static func _make_bot(mode: String, slot: int, day: int, week: int, real_player_count: int, previous_by_id: Dictionary, used_names: Dictionary) -> Dictionary:
	var account_id := _account_id(slot, week)
	var profile_rng := RandomNumberGenerator.new()
	profile_rng.seed = _seed("profile", slot, week)
	var bot := {
		"account_id": account_id,
		"nickname": _nickname(slot, week, account_id, used_names),
		"avatar": _avatar(slot, week, account_id),
		"score": 0,
		"completed": 0,
		"is_bot": true,
		"bot_epoch": day,
		"bot_week_epoch": week,
		"bot_model_version": MODEL_VERSION,
	}
	if mode == "adventure":
		bot["completed"] = _adventure_completed(slot, week, real_player_count, profile_rng)
		bot["score"] = _adventure_score(slot, int(bot["completed"]), day, week, profile_rng)
	else:
		bot["score"] = _score_for_mode(mode, slot, day, week, profile_rng)
	var previous: Dictionary = previous_by_id.get(account_id, {})
	if not previous.is_empty() and int(previous.get("bot_model_version", 0)) == MODEL_VERSION:
		bot["score"] = maxi(int(bot["score"]), int(previous.get("score", 0)))
		bot["completed"] = maxi(int(bot["completed"]), int(previous.get("completed", 0)))
		bot["nickname"] = str(previous.get("nickname", bot["nickname"]))
		bot["avatar"] = int(previous.get("avatar", bot["avatar"]))
	return bot

static func _adventure_completed(slot: int, week: int, real_player_count: int, rng: RandomNumberGenerator) -> int:
	var cap := _adventure_cap(real_player_count)
	var percentile := posmod(slot * 37 + week * 11 + 17, 100)
	if percentile < 10:
		return rng.randi_range(0, mini(3, cap))
	if percentile < 45:
		return rng.randi_range(mini(4, cap), mini(12, cap))
	if percentile < 80:
		return rng.randi_range(mini(13, cap), mini(24, cap))
	if percentile < 95:
		return rng.randi_range(mini(25, cap), mini(40, cap))
	return rng.randi_range(mini(41, cap), cap)

static func _adventure_score(slot: int, completed: int, day: int, week: int, rng: RandomNumberGenerator) -> int:
	if completed <= 0:
		return 0
	var total := 0
	for level in range(1, completed + 1):
		var level_rng := RandomNumberGenerator.new()
		level_rng.seed = _seed("level:%d" % level, slot, week)
		var base := 850 + level * 8 + level_rng.randi_range(-90, 90)
		var spread := 240 + level_rng.randi_range(0, 160)
		total += maxi(120, base + rng.randi_range(-spread, spread))
	# A small deterministic daily improvement; previous cache values clamp it
	# upward, so a bot's best score never falls on a later refresh.
	var daily_gain := posmod(_seed("daily", slot, day), 5) * maxi(1, completed)
	return total + daily_gain

static func _score_for_mode(mode: String, slot: int, day: int, week: int, rng: RandomNumberGenerator) -> int:
	var cap := _mode_cap(mode)
	var percentile := posmod(slot * 43 + week * 7 + 29, 100)
	var low := 0.05
	var high := 0.20
	if percentile >= 45 and percentile < 85:
		low = 0.20
		high = 0.55
	elif percentile >= 85:
		low = 0.55
		high = 1.0
	var score := int(float(cap) * rng.randf_range(low, high))
	var active := posmod(_seed("activity:%s" % mode, slot, week), 100) < 25
	if active:
		score += posmod(_seed("daily:%s" % mode, slot, day), maxi(2, int(float(cap) * 0.05)))
	return clampi(score, 0, cap)

static func _adventure_cap(real_player_count: int) -> int:
	if real_player_count < 10:
		return 40
	if real_player_count < 50:
		return 50
	return 60

static func _mode_cap(mode: String) -> int:
	var setting := "leaderboard/bot_%s_score_cap" % mode
	var fallback := FREE_DEFAULT_CAP if mode == "free" else CLASSIC_DEFAULT_CAP
	return maxi(100, int(ProjectSettings.get_setting(setting, fallback)))

static func _previous_bot_map(previous_bots: Array) -> Dictionary:
	var result := {}
	for raw: Variant in previous_bots:
		if raw is Dictionary and bool(raw.get("is_bot", false)):
			var account_id := str(raw.get("account_id", ""))
			if not account_id.is_empty():
				result[account_id] = raw
	return result

static func _account_id(slot: int, week: int) -> String:
	# Keep most identities stable between weeks, while replacing a deterministic
	# 20% so the board gets new people without looking freshly randomized.
	if posmod(slot * 37 + week, 100) < 20:
		return "bot:new:%04d:%03d" % [week, slot]
	return "bot:slot:%03d" % slot

static func _nickname(slot: int, week: int, account_id: String, used_names: Dictionary) -> String:
	var seed := _seed("name:%s" % account_id, slot, week)
	var style := posmod(seed, 4)
	var name := ""
	if style == 0:
		name = str(NAME_LEFT[posmod(seed, NAME_LEFT.size())]) + str(NAME_RIGHT[posmod(seed / 7, NAME_RIGHT.size())])
	elif style == 1:
		name = str(LATIN_NAMES[posmod(seed, LATIN_NAMES.size())]) + str(posmod(seed / 11, 90) + 1)
	elif style == 2:
		name = str(NAME_LEFT[posmod(seed / 5, NAME_LEFT.size())]) + str(posmod(seed / 13, 99) + 1)
	else:
		name = str(LATIN_NAMES[posmod(seed / 3, LATIN_NAMES.size())]) + "_" + str(posmod(seed / 17, 90) + 1)
	var suffix := 1
	var unique := name
	while used_names.has(unique):
		unique = name + str(suffix)
		suffix += 1
	return unique

static func _avatar(slot: int, week: int, account_id: String) -> int:
	return posmod(_seed("avatar:%s" % account_id, slot, week), 6)

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

static func _count_bots(entries: Array) -> int:
	var count := 0
	for entry: Variant in entries:
		if entry is Dictionary and bool(entry.get("is_bot", false)):
			count += 1
	return count

static func _seed(kind: String, slot: int, epoch: int) -> int:
	var value := 17 + slot * 7919 + epoch * 104729
	for character in kind:
		value = value * 31 + character.unicode_at(0)
	return absi(value)
