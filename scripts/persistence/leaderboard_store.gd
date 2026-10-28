extends RefCounted

const MODES := ["adventure", "classic", "free"]
const MAX_SCORE := 9007199254740991
const MAX_QUEUE := 128
var data: Dictionary = {}
var path := ""
var save_failed := false
var read_failed := false

func initialize(file_path: String, local_save: Dictionary, device_id: String = "") -> void:
	path = file_path
	var identity := device_id if not device_id.is_empty() else OS.get_unique_id()
	if identity.is_empty():
		identity = random_id()
	data = {
		"version": 1, "device_uid": "v1_" + ("Block/device/v1/" + identity).sha256_text(),
		"profile": {"nickname": "玩家%04d" % (randi() % 10000), "avatar": 0},
		"profile_dirty": false, "legacy_id": random_id(), "legacy_done": false,
		"legacy_snapshot": score_snapshot(local_save), "local_records": records(local_save),
		"queue": [], "cache": {}, "session": {}, "adventure_acknowledged": {}, "last_mode": "adventure",
	}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not _valid_saved_data(parsed):
			read_failed = true
			save_failed = true
			return
		data = parsed
	update_records(local_save)

static func random_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func score_snapshot(source: Dictionary) -> Dictionary:
	var normalized := SaveRepository._normalized_data(source)
	var best := {}
	var completed := mini(int(normalized["adventure_highest_completed"]), 96)
	for level in range(1, completed + 1):
		best[str(level)] = mini(int(normalized["adventure_best_scores"].get(str(level), 0)), MAX_SCORE)
	return {"high_score": mini(int(normalized["high_score"]), MAX_SCORE), "classic_high_score": mini(int(normalized["classic_high_score"]), MAX_SCORE), "adventure_highest_completed": completed, "adventure_best_scores": best}

static func records(source: Dictionary) -> Dictionary:
	var snapshot := score_snapshot(source)
	var total := 0
	for score: Variant in snapshot["adventure_best_scores"].values():
		total = mini(total + int(score), MAX_SCORE)
	return {
		"free": {"completed": 0, "score": snapshot["high_score"]},
		"classic": {"completed": 0, "score": snapshot["classic_high_score"]},
		"adventure": {"completed": snapshot["adventure_highest_completed"], "score": total},
	}

func update_records(source: Dictionary) -> void:
	data["local_records"] = records(source)
	persist()

func update_profile(nickname: String, avatar: int) -> bool:
	nickname = normalize_nickname(nickname)
	if not valid_nickname(nickname) or avatar < 0 or avatar > 5:
		return false
	var previous: Dictionary = data["profile"]
	var was_dirty: bool = data["profile_dirty"]
	data["profile"] = {"nickname": nickname, "avatar": avatar}
	data["profile_dirty"] = true
	if not persist():
		data["profile"] = previous
		data["profile_dirty"] = was_dirty
		return false
	return true

static func normalize_nickname(value: String) -> String:
	var accents := {"\u0300": ["AEIOUaeiou", "ÀÈÌÒÙàèìòù"], "\u0301": ["AEIOUYaeiouy", "ÁÉÍÓÚÝáéíóúý"], "\u0302": ["AEIOUaeiou", "ÂÊÎÔÛâêîôû"], "\u0308": ["AEIOUYaeiouy", "ÄËÏÖÜŸäëïöüÿ"], "\u0327": ["Cc", "Çç"]}
	for mark: String in accents:
		var pair: Array = accents[mark]
		for index in range(pair[0].length()):
			value = value.replace(pair[0][index] + mark, pair[1][index])
	return value.strip_edges()

static func valid_nickname(value: String) -> bool:
	if value.length() < 2 or value.length() > 12:
		return false
	var pattern := RegEx.new()
	pattern.compile("^[\\p{L}\\p{N}][\\p{L}\\p{M}\\p{N} _-]*$")
	return pattern.search(value) != null

func enqueue(record: Dictionary) -> bool:
	var queue: Array = data["queue"]
	for index in range(queue.size()):
		if queue[index]["id"] == record["id"]:
			if int(record["sequence"]) > int(queue[index]["sequence"]):
				queue[index] = record.duplicate(true)
			return persist()
	if queue.size() >= MAX_QUEUE:
		return false
	queue.append(record.duplicate(true))
	return persist()

func acknowledge(id: String, sequence: int) -> void:
	var queue: Array = data["queue"]
	for index in range(queue.size() - 1, -1, -1):
		if queue[index]["id"] == id and int(queue[index]["sequence"]) <= sequence:
			queue.remove_at(index)
	persist()

func persist() -> bool:
	if read_failed:
		return false
	var target := ProjectSettings.globalize_path(path)
	var temporary := target + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		save_failed = true
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, target)
	save_failed = error != OK
	if save_failed:
		DirAccess.remove_absolute(temporary)
	return not save_failed

static func _valid_saved_data(value: Variant) -> bool:
	# Validate the entire document before installing it or calling update_records(),
	# which persists. A damaged document must remain untouched on disk.
	if not value is Dictionary or not valid_integer(value.get("version"), 1, 1):
		return false
	for key in ["profile", "legacy_snapshot", "local_records", "cache", "session", "adventure_acknowledged"]:
		if not value.get(key) is Dictionary:
			return false
	if not _nonempty_string(value.get("device_uid")) or not _nonempty_string(value.get("legacy_id")) or value.get("last_mode") not in MODES or not value.get("legacy_done") is bool or not value.get("profile_dirty") is bool:
		return false
	var profile: Dictionary = value["profile"]
	if not profile.get("nickname") is String or not valid_nickname(profile["nickname"]) or not valid_integer(profile.get("avatar"), 0, 5):
		return false
	if not _valid_snapshot(value["legacy_snapshot"]):
		return false
	for ruleset: Variant in value["adventure_acknowledged"]:
		var scores: Variant = value["adventure_acknowledged"][ruleset]
		if not _nonempty_string(ruleset) or not scores is Dictionary:
			return false
		for level: Variant in scores:
			if not level is String or not level.is_valid_int() or str(int(level)) != level or not valid_integer(int(level), 1, 96) or not valid_integer(scores[level], 0, MAX_SCORE):
				return false
	for mode: String in MODES:
		var record: Variant = value["local_records"].get(mode)
		if not record is Dictionary or not valid_integer(record.get("score"), 0, MAX_SCORE) or not valid_integer(record.get("completed"), 0, 96 if mode == "adventure" else 0):
			return false
	for key: Variant in value["cache"]:
		if not _nonempty_string(key) or not valid_cache(value["cache"][key]):
			return false
	var session: Dictionary = value["session"]
	if not session.is_empty():
		for key in ["id_token", "refresh_token", "account_id"]:
			if not _nonempty_string(session.get(key)):
				return false
		if not _valid_number(session.get("expires_at"), 0, MAX_SCORE):
			return false
	if not value.get("queue") is Array or value["queue"].size() > MAX_QUEUE:
		return false
	var ids := {}
	for record: Variant in value["queue"]:
		if not _valid_checkpoint(record) or ids.has(record["id"]):
			return false
		ids[record["id"]] = true
	return true

static func _valid_snapshot(snapshot: Dictionary) -> bool:
	for key in ["high_score", "classic_high_score"]:
		if not valid_integer(snapshot.get(key), 0, MAX_SCORE):
			return false
	if not valid_integer(snapshot.get("adventure_highest_completed"), 0, 96) or not snapshot.get("adventure_best_scores") is Dictionary:
		return false
	for level: Variant in snapshot["adventure_best_scores"]:
		if not level is String or not level.is_valid_int() or str(int(level)) != level or not valid_integer(int(level), 1, int(snapshot["adventure_highest_completed"])) or not valid_integer(snapshot["adventure_best_scores"][level], 0, MAX_SCORE):
			return false
	return true

static func _valid_checkpoint(record: Variant) -> bool:
	if not record is Dictionary:
		return false
	for key in ["id", "ticket", "ruleset_id"]:
		if not _nonempty_string(record.get(key)):
			return false
	if record.get("mode") not in MODES or not valid_integer(record.get("sequence"), 1, 20000) or not valid_integer(record.get("score"), 0, MAX_SCORE) or not valid_integer(record.get("level"), 0, 96) or not valid_integer(record.get("failures"), 0, MAX_SCORE):
		return false
	var seed: Variant = record.get("seed")
	if not (seed is int or seed is float) or not is_finite(float(seed)) or float(seed) != floor(float(seed)):
		return false
	if not record.get("completed") is bool or not record.get("closed") is bool or not record.get("local_only") is bool or record["local_only"]:
		return false
	if not record.get("moves") is Array or record["moves"].size() != int(record["sequence"]):
		return false
	for move: Variant in record["moves"]:
		if not move is Dictionary:
			return false
		for key in ["piece_index", "x", "y", "color"]:
			if not valid_integer(move.get(key), -MAX_SCORE, MAX_SCORE):
				return false
	return true

static func valid_cache(cache: Variant) -> bool:
	return cache is Dictionary and valid_entries(cache.get("entries"), 100) and cache.get("me") is Dictionary and (cache["me"].is_empty() or valid_entry(cache["me"])) and cache.get("next_cursor") is String and valid_integer(cache.get("updated_at"), 0, MAX_SCORE) and _valid_number(cache.get("fetched_at"), 0, MAX_SCORE)

static func valid_entries(value: Variant, limit: int) -> bool:
	if not value is Array or value.size() > limit:
		return false
	var ids := {}
	var previous_rank := 0
	for entry: Variant in value:
		if not entry is Dictionary or not valid_entry(entry) or ids.has(entry["account_id"]) or int(entry["rank"]) < previous_rank:
			return false
		ids[entry["account_id"]] = true
		previous_rank = int(entry["rank"])
	return true

static func valid_entry(entry: Dictionary) -> bool:
	return _nonempty_string(entry.get("account_id")) and entry["account_id"].length() <= 128 and entry.get("nickname") is String and valid_nickname(entry["nickname"]) and valid_integer(entry.get("rank"), 1, MAX_SCORE) and valid_integer(entry.get("avatar"), 0, 5) and valid_integer(entry.get("score"), 0, MAX_SCORE) and valid_integer(entry.get("completed"), 0, 96)

static func valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _valid_number(value, minimum, maximum) and float(value) == floor(float(value))

static func _valid_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _nonempty_string(value: Variant) -> bool:
	return value is String and not value.is_empty()
