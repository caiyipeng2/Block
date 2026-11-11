extends SceneTree

const AdService := preload("res://scripts/ads/ad_service.gd")
const TEST_ID := "ca-app-pub-3940256099942544/1033173712"
const REAL_ID := "ca-app-pub-1234567890123456/1234567890"
const STATE_PATH := "user://ad-service-test-state.json"

var _failures := 0
var _clock := 1000

class FakeBackend extends RefCounted:
	signal initialized(ok: bool)
	signal ad_ready(ready: bool)
	signal ad_load_failed
	signal ad_started
	signal ad_ended(shown: bool)
	signal privacy_requirement_changed(required: bool)
	var loaded := true
	var show_result := true
	var show_calls := 0
	var close_calls := 0
	var privacy_required := false

	func is_ad_ready() -> bool:
		return loaded

	func preload_ad() -> void:
		if loaded:
			ad_ready.emit(true)

	func show_interstitial() -> void:
		show_calls += 1
		ad_started.emit()
		ad_ended.emit(show_result)

	func show_privacy_options(callback: Callable) -> void:
		callback.call()

	func close() -> void:
		close_calls += 1

func _initialize() -> void:
	_run()
	quit(0 if _failures == 0 else 1)

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_PATH))
	_check(AdService.select_unit_id(true, TEST_ID, "") == TEST_ID, "test mode selects the Google test unit")
	_check(AdService.select_unit_id(false, TEST_ID, REAL_ID) == REAL_ID, "production mode selects the configured real unit")
	_check(AdService.select_unit_id(false, TEST_ID, "not-an-id").is_empty(), "invalid real unit disables ads")
	_check(AdService.is_valid_app_id("ca-app-pub-3940256099942544~3347511713"), "test app id is valid")
	_check(not AdService.is_valid_app_id("ca-app-pub-1/2"), "invalid app id is rejected")
	_test_desktop_noop()
	_test_cooldown_and_persistence()
	_test_unavailable_and_load_failure()
	print("AD SERVICE TESTS: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)

func _test_desktop_noop() -> void:
	var service = AdService.new()
	root.add_child(service)
	service.configure()
	_check(not service.is_available() and not service.can_attempt_revive(), "desktop never creates an ad backend")
	service.free()

func _test_cooldown_and_persistence() -> void:
	var backend := FakeBackend.new()
	var service = AdService.new()
	root.add_child(service)
	service.configure_for_test(_options(), backend, func() -> int: return _clock)
	_check(service.is_available() and service.can_attempt_revive(), "configured Android test service can attempt an ad")
	var shown: Array[bool] = []
	service.request_revive_interstitial(func(value: bool): shown.append(value))
	await process_frame
	_check(shown == [true] and backend.show_calls == 1, "a loaded ad shows and reports success")
	_check(service.cooldown_remaining() == 120, "showing starts the 120 second cooldown")
	service.request_revive_interstitial(func(value: bool): shown.append(value))
	await process_frame
	_check(shown == [true, false] and backend.show_calls == 1, "cooldown prevents a second ad")
	_clock = 1120
	_check(service.can_attempt_revive(), "cooldown ends after 120 seconds")
	service.free()

	var restored = AdService.new()
	root.add_child(restored)
	restored.configure_for_test(_options(), FakeBackend.new(), func() -> int: return 1120)
	_check(restored.cooldown_remaining() == 0, "cooldown is persisted across service instances")
	restored.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_PATH))

func _test_unavailable_and_load_failure() -> void:
	var backend := FakeBackend.new()
	var service = AdService.new()
	root.add_child(service)
	service.configure_for_test(_options(), backend, func() -> int: return _clock)
	backend.initialized.emit(false)
	_check(not service.can_attempt_revive(), "failed SDK initialization disables revive ads")
	backend.initialized.emit(true)
	backend.loaded = false
	var result: Array[bool] = []
	service.request_revive_interstitial(func(value: bool): result.append(value))
	backend.ad_load_failed.emit()
	await process_frame
	_check(result == [false], "missing fill keeps the run failed")
	service.free()

func _options() -> Dictionary:
	return {
		"use_test_ads": true,
		"test_interstitial_id": TEST_ID,
		"real_interstitial_id": REAL_ID,
		"cooldown_seconds": 120,
		"state_path": STATE_PATH,
	}

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("AD SERVICE: " + message)
