extends SceneTree

const Repository := preload("res://scripts/persistence/save_repository.gd")

var _failures: int = 0
var _tests: int = 0
var _directory: String
var _repository := Repository.new()

func _initialize() -> void:
	_directory = ProjectSettings.globalize_path("res://work/verification/save-tests")
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		push_error("Cannot create isolated save-test directory")
		quit(1)
		return

	_run(_test_defaults)
	_run(_test_path_contract)
	_run(_test_sequential_level_unlock)
	_run(_test_replayed_level_best_score)
	_run(_test_level_record_rejects_invalid_input)
	_run(_test_level_failure_count)
	_run(_test_level_failure_record)
	_run(_test_level_failure_record_rejects_invalid_input)
	_run(_test_level_failure_normalization)
	_run(_test_level_completion_clears_only_its_failure_count)
	if _supports_isolated_paths():
		for test: Callable in [
			_test_missing_file,
			_test_corrupt_json,
			_test_non_dictionary_json,
			_test_unknown_version,
			_test_invalid_version_types,
			_test_missing_fields,
			_test_old_save_mode_migration,
			_test_invalid_score_types,
			_test_invalid_adventure_progress,
			_test_invalid_adventure_best_scores,
			_test_invalid_adventure_retry_failures,
			_test_invalid_boolean_types,
			_test_language_settings,
			_test_invalid_language_preserves_records,
			_test_negative_score,
			_test_round_trip_changed_settings,
			_test_round_trip_default_settings,
			_test_round_trip_mode_progress,
			_test_round_trip_retry_failures,
			_test_save_normalizes_invalid_fields,
			_test_save_uses_current_version,
			_test_overwrites_existing_save,
			_test_missing_parent_write_failure,
			_test_temp_write_failure_preserves_save,
			_test_replace_failure,
			_test_success_removes_temp,
		]:
			_run(test)

	print("SAVE TESTS: %d cases, %d failures" % [_tests, _failures])
	if _failures == 0:
		print("SAVE TESTS PASSED")
	quit(0 if _failures == 0 else 1)

func _run(test: Callable) -> void:
	_tests += 1
	test.call()

func _test_defaults() -> void:
	_expect_equal(Repository.defaults(), {
		"version": 1,
		"high_score": 0,
		"classic_high_score": 0,
		"adventure_highest_completed": 0,
		"adventure_best_scores": {},
		"adventure_retry_failures": {},
		"sound_enabled": true,
		"music_enabled": true,
		"reduced_motion": false,
		"screen_shake": true,
		"language": "zh_CN",
	}, "defaults contain independent mode records, four boolean settings and Chinese language")

func _test_path_contract() -> void:
	_expect(_supports_isolated_paths(), "load_data and save_data accept an optional isolated path")

func _supports_isolated_paths() -> bool:
	var load_supported := false
	var save_supported := false
	for method: Dictionary in _repository.get_script().get_script_method_list():
		if method["name"] == "load_data":
			load_supported = method["args"].size() == 1 and method["default_args"].size() == 1
		elif method["name"] == "save_data":
			save_supported = method["args"].size() == 2 and method["default_args"].size() == 1
	return load_supported and save_supported

func _test_missing_file() -> void:
	var path := _path("missing.json")
	_remove_file(path)
	_expect_equal(_load(path), Repository.defaults(), "missing file uses safe defaults")

func _test_corrupt_json() -> void:
	var path := _fixture("corrupt.json", "{not valid JSON")
	_expect_equal(_load(path), Repository.defaults(), "corrupt JSON uses safe defaults")

func _test_non_dictionary_json() -> void:
	var path := _fixture("array.json", "[1, 2, 3]")
	_expect_equal(_load(path), Repository.defaults(), "non-dictionary JSON uses safe defaults")

func _test_unknown_version() -> void:
	var payload := _changed_settings()
	payload["version"] = 999
	_expect_equal(_load(_json_fixture("unknown-version.json", payload)), Repository.defaults(), "unknown version uses safe defaults")

func _test_invalid_version_types() -> void:
	for value: Variant in ["1", true, null, 1.5, [], {}]:
		var payload := _changed_settings()
		payload["version"] = value
		_expect_equal(_load(_json_fixture("invalid-version.json", payload)), Repository.defaults(), "invalid version type %s uses defaults" % [value])
	_expect_equal(_load(_json_fixture("missing-version.json", {"high_score": 500})), Repository.defaults(), "missing version uses defaults")

func _test_missing_fields() -> void:
	_expect_equal(_load(_json_fixture("missing-fields.json", {"version": 1})), Repository.defaults(), "missing fields use defaults")

func _test_old_save_mode_migration() -> void:
	var legacy := {"version": 1, "high_score": 2468, "sound_enabled": false, "music_enabled": false, "reduced_motion": true, "screen_shake": false}
	var path := _json_fixture("legacy-mode-migration.json", legacy)
	_expect_equal(_load(path), _changed_settings(), "version-1 score remains the free-mode record and valid settings survive")
	_expect_equal(FileAccess.get_file_as_string(path), JSON.stringify(legacy), "loading an old save does not rewrite it")
	_expect_equal(_load(path)["adventure_retry_failures"], {}, "legacy saves start without per-level retry assistance")
	_expect_equal(_load(path)["language"], "zh_CN", "legacy saves without language keep Chinese as the default")

func _test_invalid_score_types() -> void:
	for field: String in ["high_score", "classic_high_score"]:
		for value: Variant in ["900", true, null, [], {}, 12.5, 9223372036854775808.0]:
			var payload := _changed_settings()
			payload[field] = value
			var expected := _changed_settings()
			expected[field] = 0
			_expect_equal(_load(_json_fixture("invalid-score.json", payload)), expected, "invalid %s value %s uses zero without losing valid settings" % [field, value])

func _test_invalid_adventure_progress() -> void:
	for value: Variant in [true, false, "2", null, [], {}, -1, 1.5, 10001, 9223372036854775808.0]:
		var payload := _changed_settings()
		payload["adventure_highest_completed"] = value
		_expect_equal(_load(_json_fixture("invalid-adventure-progress.json", payload)), _changed_settings(), "invalid highest-completed value %s uses zero" % [value])
	var payload := _changed_settings()
	payload["adventure_highest_completed"] = 10000
	_expect_equal(_load(_json_fixture("max-adventure-progress.json", payload))["adventure_highest_completed"], 10000, "bounded progress supports future level packs")

func _test_invalid_adventure_best_scores() -> void:
	for value: Variant in [true, "scores", 5, [], null]:
		var payload := _changed_settings()
		payload["adventure_best_scores"] = value
		_expect_equal(_load(_json_fixture("invalid-adventure-scores.json", payload)), _changed_settings(), "invalid best-score container %s uses an empty dictionary" % [value])
	var payload := _changed_settings()
	payload["adventure_best_scores"] = {
		"1": 350, "2": 0, "3": true, "4": 1.5, "5": -1,
		"6": 9223372036854775808.0, "7": "300", "8": null,
		"0": 100, "-1": 100, "01": 100, "+1": 100,
		"1.0": 100, "10001": 100, "99999999999999999999": 100,
		"10000": 800,
	}
	var expected := _changed_settings()
	expected["adventure_best_scores"] = {"1": 350, "2": 0, "10000": 800}
	_expect_equal(_load(_json_fixture("filtered-adventure-scores.json", payload)), expected, "only canonical positive level keys and finite nonnegative integer scores survive")
	var with_numeric_key := _changed_settings()
	with_numeric_key["adventure_best_scores"] = {1: 100, "2": 200}
	var normalized := Repository.record_level_completed(with_numeric_key, 0, 0)
	_expect_equal(normalized["adventure_best_scores"], {"2": 200}, "in-memory numeric keys are not silently accepted as canonical string keys")

func _test_sequential_level_unlock() -> void:
	var data := _changed_settings()
	var first := Repository.record_level_completed(data, 1, 350)
	_expect_equal(first["adventure_highest_completed"], 1, "first completed level unlocks only level 2")
	_expect_equal(first["adventure_best_scores"], {"1": 350}, "first completion stores its best score")
	_expect_equal(data, _changed_settings(), "recording returns a new record without mutating the input")
	var skipped := Repository.record_level_completed(first, 3, 900)
	_expect_equal(skipped, first, "skipping level 2 neither unlocks nor records level 3")
	var second := Repository.record_level_completed(first, 2, 450)
	_expect_equal(second["adventure_highest_completed"], 2, "completing the next level advances sequential progress")
	_expect_equal(second["adventure_best_scores"], {"1": 350, "2": 450}, "sequential completion preserves previous scores")
	_expect_equal(first["adventure_best_scores"], {"1": 350}, "new completion does not mutate the previous nested score dictionary")
	_expect_equal(second["high_score"], 2468, "adventure completion preserves the free-mode high score")
	_expect_equal(second["sound_enabled"], false, "adventure completion preserves settings")

func _test_replayed_level_best_score() -> void:
	var data := Repository.record_level_completed(Repository.defaults(), 1, 350)
	data = Repository.record_level_completed(data, 2, 450)
	var improved := Repository.record_level_completed(data, 1, 600)
	_expect_equal(improved["adventure_highest_completed"], 2, "replaying an earlier level never rolls progress back")
	_expect_equal(improved["adventure_best_scores"], {"1": 600, "2": 450}, "replay updates only an improved level best score")
	_expect_equal(Repository.record_level_completed(improved, 1, 0), improved, "lower replay scores do not replace a best score")

func _test_level_record_rejects_invalid_input() -> void:
	var data := Repository.defaults()
	for level_id: Variant in [0, -1, 10001, true, false, 1.0, 1.5, "1", null]:
		_expect_equal(Repository.record_level_completed(data, level_id, 350), data, "invalid level id %s cannot unlock progress" % [level_id])
	for score: Variant in [-1, true, false, 350.0, 350.5, "350", null, [], {}, INF, NAN]:
		_expect_equal(Repository.record_level_completed(data, 1, score), data, "invalid completion score %s cannot unlock progress" % [score])
	var at_limit := Repository.defaults()
	at_limit["adventure_highest_completed"] = 10000
	_expect_equal(Repository.record_level_completed(at_limit, 10001, 100), at_limit, "completion cannot exceed the bounded supported level range")

func _test_level_failure_count() -> void:
	var data := Repository.defaults()
	_expect_equal(Repository.level_failure_count(data, 1), 0, "new levels have no failures")
	data["adventure_retry_failures"] = {"1": 3.0, "2": 99, "3": 0, "4": true}
	_expect_equal(Repository.level_failure_count(data, 1), 3, "whole JSON numbers are accepted as failure counts")
	_expect_equal(Repository.level_failure_count(data, 2), 0, "stored retry count on a locked level is ignored")
	data["adventure_highest_completed"] = 1
	_expect_equal(Repository.level_failure_count(data, 2), 99, "maximum retry count is readable once the level is unlocked")
	_expect_equal(Repository.level_failure_count(data, 3), 0, "zero failure count is safely readable")
	_expect_equal(Repository.level_failure_count(data, 4), 0, "boolean failure count is rejected")
	for level_id: int in [0, -1, 10001]:
		_expect_equal(Repository.level_failure_count(data, level_id), 0, "out-of-range level has no failure count")

func _test_level_failure_record() -> void:
	var data := _changed_settings()
	data["classic_high_score"] = 4321
	var first := Repository.record_level_failed(data, 1)
	var expected := data.duplicate(true)
	expected["adventure_retry_failures"] = {"1": 1}
	_expect_equal(first, expected, "recording a failure increments only that level without scores or unlocks")
	_expect_equal(data["adventure_retry_failures"], {}, "failure recording does not mutate its input")
	var second := Repository.record_level_failed(first, 1)
	_expect_equal(second["adventure_retry_failures"], {"1": 2}, "a second recorded failure increments once")
	_expect_equal(first["adventure_retry_failures"], {"1": 1}, "failure recording does not mutate nested previous counters")
	second["adventure_retry_failures"] = {"1": 98}
	var capped := Repository.record_level_failed(Repository.record_level_failed(second, 1), 1)
	_expect_equal(capped["adventure_retry_failures"], {"1": 99}, "repeated failures saturate at 99")
	var unlocked := Repository.record_level_completed(data, 1, 350)
	_expect_equal(Repository.record_level_failed(unlocked, 2)["adventure_retry_failures"], {"2": 1}, "next unlocked level can record a failure")

func _test_level_failure_record_rejects_invalid_input() -> void:
	var data := Repository.defaults()
	for level_id: Variant in [0, -1, 10001, true, false, 1.0, 1.5, "1", null, [], {}, INF, NAN]:
		_expect_equal(Repository.record_level_failed(data, level_id), data, "invalid failure level id %s is ignored" % [level_id])
	_expect_equal(Repository.record_level_failed(data, 2), data, "a locked level cannot record a failure")
	var unlocked := Repository.record_level_completed(data, 1, 350)
	_expect_equal(Repository.record_level_failed(unlocked, 3), unlocked, "failure recording cannot skip the next unlocked level")

func _test_level_failure_normalization() -> void:
	var data := _changed_settings()
	data["adventure_retry_failures"] = {
		"1": 3.0, "2": 0, "3": true, "4": 1.5, "5": -1,
		"6": INF, "7": NAN, "8": "3", "9": 100,
		"10": null, "11": [], "12": {}, "10000": 99,
		"0": 1, "-1": 1, "01": 1, "+1": 1, "1.0": 1,
		"10001": 1, "99999999999999999999": 1, 13: 2,
	}
	var normalized := Repository.record_level_failed(data, 0)
	_expect_equal(normalized["adventure_retry_failures"], {"1": 3}, "only canonical unlocked level keys and integer counts 1 to 99 survive")
	_expect_equal(Repository.level_failure_count(data, 10000), 0, "locked-level counters cannot activate assistance")
	_expect_equal(normalized["high_score"], data["high_score"], "failure normalization preserves valid score fields")
	_expect_equal(normalized["sound_enabled"], data["sound_enabled"], "failure normalization preserves valid settings")
	for value: Variant in [true, false, "counts", 3, [], null]:
		data["adventure_retry_failures"] = value
		_expect_equal(Repository.record_level_failed(data, 0)["adventure_retry_failures"], {}, "invalid failure-count containers use an empty dictionary")

func _test_level_completion_clears_only_its_failure_count() -> void:
	var data := Repository.record_level_completed(_changed_settings(), 1, 350)
	data["adventure_retry_failures"] = {"1": 2, "2": 5}
	var invalid := Repository.record_level_completed(data, 2, true)
	_expect_equal(invalid["adventure_retry_failures"], {"1": 2, "2": 5}, "invalid completion does not clear retry assistance")
	var completed := Repository.record_level_completed(data, 2, 450)
	_expect_equal(completed["adventure_retry_failures"], {"1": 2}, "passing a level clears only that level's failure count")
	_expect_equal(data["adventure_retry_failures"], {"1": 2, "2": 5}, "completion does not mutate the input retry dictionary")
	_expect_equal(completed["adventure_highest_completed"], 2, "retry cleanup preserves normal sequential unlocking")
	_expect_equal(completed["adventure_best_scores"], {"1": 350, "2": 450}, "retry cleanup preserves level best-score recording")
	var replayed := Repository.record_level_completed(completed, 1, 100)
	_expect_equal(replayed["adventure_retry_failures"], {}, "passing a replayed level also clears its retry assistance")

func _test_invalid_adventure_retry_failures() -> void:
	var payload := _changed_settings()
	payload["adventure_retry_failures"] = {"1": 2, "2": 99, "3": 0, "4": true, "5": 2.5, "6": -1, "7": 100, "01": 3, "10001": 2}
	var expected := _changed_settings()
	expected["adventure_retry_failures"] = {"1": 2}
	_expect_equal(_load(_json_fixture("filtered-adventure-retry-failures.json", payload)), expected, "loaded retry counts are strictly normalized without losing settings")

func _test_invalid_boolean_types() -> void:
	for field: String in ["sound_enabled", "music_enabled", "reduced_motion", "screen_shake"]:
		for value: Variant in ["false", 0, 1, null, [], {}]:
			var payload := _changed_settings()
			payload[field] = value
			var expected := _changed_settings()
			expected[field] = Repository.defaults()[field]
			_expect_equal(_load(_json_fixture("invalid-boolean.json", payload)), expected, "invalid %s type %s uses its default" % [field, value])

func _test_language_settings() -> void:
	for language: String in ["zh_CN", "en", "fr"]:
		var payload := _changed_settings()
		payload["language"] = language
		payload["classic_high_score"] = 4321
		payload = Repository.record_level_completed(payload, 1, 350)
		payload = Repository.record_level_failed(payload, 2)
		var path := _json_fixture("language-settings.json", payload)
		_expect_equal(_load(path), payload, "supported language %s loads with scores, progress and retry counts intact" % language)
		_expect(_save(payload, path), "supported language %s saves" % language)
		_expect_equal(_load(path), payload, "supported language %s round trips without changing other settings or records" % language)

func _test_invalid_language_preserves_records() -> void:
	var expected := _changed_settings()
	expected["classic_high_score"] = 4321
	expected = Repository.record_level_completed(expected, 1, 350)
	expected = Repository.record_level_failed(expected, 2)
	for value: Variant in ["de", "en_US", "fr-FR", "", true, false, 1, null, [], {}]:
		var payload := expected.duplicate(true)
		payload["language"] = value
		var path := _json_fixture("invalid-language.json", payload)
		_expect_equal(_load(path), expected, "unsupported language %s falls back to Chinese without losing scores or progress" % [value])
		_expect(_save(payload, path), "invalid language %s can be safely normalized when saving" % [value])
		_expect_equal(_load(path), expected, "saving an invalid language preserves mode records, retry counts and boolean settings")

func _test_negative_score() -> void:
	var payload := _changed_settings()
	payload["high_score"] = -80
	var path := _json_fixture("negative-score.json", payload)
	_expect_equal(_load(path)["high_score"], 0, "loaded negative score is zero")
	_expect(_save(payload, path), "negative-score write succeeds")
	_expect_equal(_load(path)["high_score"], 0, "saved negative score is zero")

func _test_round_trip_changed_settings() -> void:
	var path := _path("round-trip-changed.json")
	_expect(_save(_changed_settings(), path), "write changed settings")
	_expect_equal(_load(path), _changed_settings(), "score, four changed boolean settings and default language round trip")

func _test_round_trip_default_settings() -> void:
	var path := _path("round-trip-default.json")
	_expect(_save(Repository.defaults(), path), "write default settings")
	_expect_equal(_load(path), Repository.defaults(), "zero score, four default boolean settings and default language round trip")

func _test_round_trip_mode_progress() -> void:
	var payload := _changed_settings()
	payload["classic_high_score"] = 4321
	payload = Repository.record_level_completed(payload, 1, 350)
	payload = Repository.record_level_completed(payload, 2, 450)
	var path := _path("round-trip-modes.json")
	_expect(_save(payload, path), "write independent scores and adventure progress")
	_expect_equal(_load(path), payload, "all mode records and settings survive a save/load round trip")

func _test_round_trip_retry_failures() -> void:
	var payload := Repository.record_level_completed(_changed_settings(), 1, 350)
	payload = Repository.record_level_failed(payload, 2)
	payload = Repository.record_level_failed(payload, 2)
	var path := _path("round-trip-retry-failures.json")
	_expect(_save(payload, path), "write per-level retry counts")
	_expect_equal(_load(path), payload, "retry counts round trip through JSON with progress, best scores and settings")
	_expect_equal(_load(path)["version"], 1, "retry counts do not change the compatible version-1 save format")

func _test_save_normalizes_invalid_fields() -> void:
	var path := _path("invalid-save.json")
	_expect(_save({"high_score": "500", "sound_enabled": 0, "music_enabled": null, "reduced_motion": "true"}, path), "write safely normalized invalid fields")
	_expect_equal(_load(path), Repository.defaults(), "invalid fields are safely normalized before saving")

func _test_save_uses_current_version() -> void:
	var payload := _changed_settings()
	payload["version"] = 999
	payload["unknown"] = "discarded"
	var path := _path("current-version.json")
	_expect(_save(payload, path), "write ignores caller's unsupported version")
	_expect_equal(_load(path), _changed_settings(), "writer always uses current version")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect_equal(raw.size(), Repository.defaults().size(), "writer persists only supported fields")

func _test_overwrites_existing_save() -> void:
	var path := _json_fixture("overwrite.json", Repository.defaults())
	_expect(_save(_changed_settings(), path), "replace existing save")
	_expect_equal(_load(path), _changed_settings(), "replaced save contains the complete new record")

func _test_missing_parent_write_failure() -> void:
	var path := _directory.path_join("parent-does-not-exist/save.json")
	_expect(not _save(_changed_settings(), path), "missing parent returns false")
	_expect(not FileAccess.file_exists(path), "failed write does not create final save")

func _test_temp_write_failure_preserves_save() -> void:
	var path := _json_fixture("temp-blocked.json", Repository.defaults())
	var temp_path := path + ".tmp"
	_remove_file(temp_path)
	_expect_equal(DirAccess.make_dir_absolute(temp_path), OK, "create unavailable temp-file fixture")
	var before := FileAccess.get_file_as_string(path)
	_expect(not _save(_changed_settings(), path), "unavailable temp file returns false")
	_expect_equal(FileAccess.get_file_as_string(path), before, "failed temporary write preserves previous save bytes")
	_expect_equal(DirAccess.remove_absolute(temp_path), OK, "remove unavailable temp-file fixture")

func _test_replace_failure() -> void:
	var path := _path("directory-destination.json")
	_expect_equal(DirAccess.make_dir_absolute(path), OK, "create directory destination fixture")
	var sentinel := path.path_join("keep.txt")
	_fixture_absolute(sentinel, "keep this existing content")
	_expect(not _save(_changed_settings(), path), "failed replacement returns false")
	_expect_equal(FileAccess.get_file_as_string(sentinel), "keep this existing content", "failed replacement preserves destination content")
	_expect(not FileAccess.file_exists(path + ".tmp"), "failed replacement cleans temporary file")
	_remove_file(sentinel)
	_expect_equal(DirAccess.remove_absolute(path), OK, "remove directory destination fixture")

func _test_success_removes_temp() -> void:
	var path := _path("no-temp-after-save.json")
	_expect(_save(_changed_settings(), path), "save for temporary-file cleanup")
	_expect(not FileAccess.file_exists(path + ".tmp"), "successful replacement leaves no temporary file")

func _changed_settings() -> Dictionary:
	var data := Repository.defaults()
	data["high_score"] = 2468
	data["sound_enabled"] = false
	data["music_enabled"] = false
	data["reduced_motion"] = true
	data["screen_shake"] = false
	return data

func _path(name: String) -> String:
	return _directory.path_join(name)

func _json_fixture(name: String, data: Dictionary) -> String:
	return _fixture(name, JSON.stringify(data))

func _fixture(name: String, text: String) -> String:
	var path := _path(name)
	_fixture_absolute(path, text)
	return path

func _fixture_absolute(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures += 1
		push_error("FAIL: cannot create isolated fixture " + path)
		return
	file.store_string(text)
	file.close()

func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		_expect_equal(DirAccess.remove_absolute(path), OK, "remove isolated fixture " + path)

func _load(path: String) -> Dictionary:
	return _repository.callv("load_data", [path])

func _save(data: Dictionary, path: String) -> bool:
	return _repository.callv("save_data", [data, path])

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s; actual=%s expected=%s" % [message, actual, expected])
