class_name SaveRepository
extends RefCounted

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const MAX_LEVEL_ID := 10000

static func defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"high_score": 0,
		"classic_high_score": 0,
		"adventure_highest_completed": 0,
		"adventure_best_scores": {},
		"sound_enabled": true,
		"music_enabled": true,
		"reduced_motion": false,
		"screen_shake": true,
	}

static func load_data(path: String = SAVE_PATH) -> Dictionary:
	var data := defaults()
	if not FileAccess.file_exists(path):
		return data

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return data
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return data
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return data
	var version: Variant = parsed.get("version")
	if not (version is int or version is float) or version != SAVE_VERSION:
		return data

	return _normalized_data(parsed)

static func save_data(data: Dictionary, path: String = SAVE_PATH) -> bool:
	var payload := _normalized_data(data)
	var target_path := ProjectSettings.globalize_path(path)
	var temporary_path := target_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return false
	# Replace only after the complete record has been flushed and closed.
	if DirAccess.rename_absolute(temporary_path, target_path) != OK:
		DirAccess.remove_absolute(temporary_path)
		return false
	return true

static func record_level_completed(data: Dictionary, level_id: Variant, score: Variant) -> Dictionary:
	var payload := _normalized_data(data)
	# Variant parameters keep bools and fractional numbers from being silently
	# converted by a typed int argument before this validation can run.
	if typeof(level_id) != TYPE_INT or typeof(score) != TYPE_INT:
		return payload
	if level_id < 1 or level_id > MAX_LEVEL_ID or score < 0:
		return payload
	var highest: int = payload["adventure_highest_completed"]
	if level_id > highest + 1:
		return payload
	var key := str(level_id)
	var best_scores: Dictionary = payload["adventure_best_scores"]
	best_scores[key] = maxi(int(best_scores.get(key, 0)), score)
	payload["adventure_highest_completed"] = maxi(highest, level_id)
	return payload

static func _normalized_data(data: Dictionary) -> Dictionary:
	var payload := defaults()
	for key: String in ["high_score", "classic_high_score"]:
		var score: Variant = _nonnegative_integer(data.get(key))
		if score != null:
			payload[key] = score
	var highest: Variant = _nonnegative_integer(data.get("adventure_highest_completed"))
	if highest != null and highest <= MAX_LEVEL_ID:
		payload["adventure_highest_completed"] = highest
	var stored_best: Variant = data.get("adventure_best_scores")
	if stored_best is Dictionary:
		var best_scores: Dictionary = payload["adventure_best_scores"]
		for key: Variant in stored_best:
			if not key is String or key.length() > 5 or not key.is_valid_int():
				continue
			var level_id := int(key)
			if level_id < 1 or level_id > MAX_LEVEL_ID or str(level_id) != key:
				continue
			var score: Variant = _nonnegative_integer(stored_best[key])
			if score != null:
				best_scores[key] = score
	for key: String in ["sound_enabled", "music_enabled", "reduced_motion", "screen_shake"]:
		var value: Variant = data.get(key)
		if value is bool:
			payload[key] = value
	return payload

static func _nonnegative_integer(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value if value >= 0 else null
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value):
		# JSON decodes whole numbers as floats; reject values outside int64.
		if value >= 0.0 and value < 9223372036854775808.0:
			return int(value)
	return null
