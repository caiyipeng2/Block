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
	if _supports_isolated_paths():
		for test: Callable in [
			_test_missing_file,
			_test_corrupt_json,
			_test_non_dictionary_json,
			_test_unknown_version,
			_test_invalid_version_types,
			_test_missing_fields,
			_test_invalid_score_types,
			_test_invalid_boolean_types,
			_test_negative_score,
			_test_round_trip_changed_settings,
			_test_round_trip_default_settings,
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
		"sound_enabled": true,
		"music_enabled": true,
		"reduced_motion": false,
	}, "defaults contain the score and all three settings")

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

func _test_invalid_score_types() -> void:
	for value: Variant in ["900", true, null, [], {}, 12.5]:
		var payload := _changed_settings()
		payload["high_score"] = value
		var expected := _changed_settings()
		expected["high_score"] = 0
		_expect_equal(_load(_json_fixture("invalid-score.json", payload)), expected, "invalid score type %s uses zero without losing valid settings" % [value])

func _test_invalid_boolean_types() -> void:
	for field: String in ["sound_enabled", "music_enabled", "reduced_motion"]:
		for value: Variant in ["false", 0, 1, null, [], {}]:
			var payload := _changed_settings()
			payload[field] = value
			var expected := _changed_settings()
			expected[field] = Repository.defaults()[field]
			_expect_equal(_load(_json_fixture("invalid-boolean.json", payload)), expected, "invalid %s type %s uses its default" % [field, value])

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
	_expect_equal(_load(path), _changed_settings(), "score and three changed boolean settings round trip")

func _test_round_trip_default_settings() -> void:
	var path := _path("round-trip-default.json")
	_expect(_save(Repository.defaults(), path), "write default settings")
	_expect_equal(_load(path), Repository.defaults(), "zero score and three default boolean settings round trip")

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
	return {"version": 1, "high_score": 2468, "sound_enabled": false, "music_enabled": false, "reduced_motion": true}

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
