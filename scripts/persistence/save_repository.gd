class_name SaveRepository
extends RefCounted

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

static func defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"high_score": 0,
		"sound_enabled": true,
		"music_enabled": true,
		"reduced_motion": false,
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

static func _normalized_data(data: Dictionary) -> Dictionary:
	var payload := defaults()
	var score: Variant = data.get("high_score")
	if score is int:
		payload["high_score"] = maxi(0, score)
	elif score is float and is_finite(score) and score == floor(score):
		# JSON decodes whole numbers as floats; reject values outside int64.
		if score >= 0.0 and score < 9223372036854775808.0:
			payload["high_score"] = int(score)
	for key: String in ["sound_enabled", "music_enabled", "reduced_motion"]:
		var value: Variant = data.get(key)
		if value is bool:
			payload[key] = value
	return payload
