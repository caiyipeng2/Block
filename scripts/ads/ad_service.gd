extends Node

signal ad_started
signal ad_ended(shown: bool)
signal state_changed

const AD_BACKEND_PATH := "res://scripts/ads/admob_backend.gd"
const DEFAULT_COOLDOWN_SECONDS := 120
const TEST_APP_ID := "ca-app-pub-3940256099942544~3347511713"

var _enabled := false
var _platform_ok := false
var _backend = null
var _backend_ready := false
var _use_test_ads := true
var _unit_id := ""
var _cooldown_seconds := DEFAULT_COOLDOWN_SECONDS
var _last_shown_unix := 0
var _state_path := "user://ads_state.json"
var _now_override: Callable = Callable()
var _waiting_callback: Callable = Callable()
var _wait_timer: SceneTreeTimer
var _showing := false
var _privacy_required := false

static func is_valid_app_id(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^ca-app-pub-[0-9]{16}~[0-9]{10}$")
	return pattern.search(value) != null

static func is_valid_interstitial_id(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^ca-app-pub-[0-9]{16}/[0-9]{10}$")
	return pattern.search(value) != null

static func select_unit_id(use_test_ads: bool, test_id: String, real_id: String) -> String:
	var selected := test_id.strip_edges() if use_test_ads else real_id.strip_edges()
	if not is_valid_interstitial_id(selected):
		return ""
	return selected

func configure() -> void:
	_platform_ok = OS.has_feature("android")
	_enabled = bool(ProjectSettings.get_setting("ads/enabled", false))
	_use_test_ads = bool(ProjectSettings.get_setting("ads/use_test_ads", true))
	_cooldown_seconds = maxi(0, int(ProjectSettings.get_setting("ads/cooldown_seconds", DEFAULT_COOLDOWN_SECONDS)))
	_unit_id = select_unit_id(
		_use_test_ads,
		str(ProjectSettings.get_setting("ads/test_interstitial_id", "")),
		str(ProjectSettings.get_setting("ads/real_interstitial_id", ""))
	)
	var app_id := str(ProjectSettings.get_setting("admob/general/android/app_id", "")).strip_edges()
	if _use_test_ads and app_id.is_empty():
		app_id = TEST_APP_ID
	if not _enabled or not _platform_ok or _unit_id.is_empty() or not is_valid_app_id(app_id):
		return
	_load_state()
	var backend_script: Script = load(AD_BACKEND_PATH)
	if backend_script == null:
		return
	_backend = backend_script.new()
	_connect_backend()
	_backend.configure(self, _unit_id, _use_test_ads, str(ProjectSettings.get_setting("ads/debug_consent_geography", "")))
	state_changed.emit()

func configure_for_test(options: Dictionary, backend: Object, clock: Callable = Callable()) -> void:
	_enabled = true
	_platform_ok = true
	_use_test_ads = bool(options.get("use_test_ads", true))
	_unit_id = select_unit_id(
		_use_test_ads,
		str(options.get("test_interstitial_id", "")),
		str(options.get("real_interstitial_id", ""))
	)
	_cooldown_seconds = maxi(0, int(options.get("cooldown_seconds", DEFAULT_COOLDOWN_SECONDS)))
	_state_path = str(options.get("state_path", "user://ads-test-state.json"))
	_now_override = clock
	_load_state()
	_backend = backend
	_backend_ready = true
	_connect_backend()
	state_changed.emit()

func is_enabled() -> bool:
	return _enabled

func is_available() -> bool:
	return _enabled and _platform_ok and _backend != null and not _unit_id.is_empty()

func is_ready() -> bool:
	return is_available() and _backend_ready

func cooldown_remaining() -> int:
	if _cooldown_seconds <= 0:
		return 0
	return maxi(0, _cooldown_seconds - (_now_unix() - _last_shown_unix))

func can_attempt_revive() -> bool:
	return is_ready() and not _showing and not _waiting_callback.is_valid() and cooldown_remaining() == 0

func request_revive_interstitial(callback: Callable) -> void:
	if not can_attempt_revive():
		callback.call_deferred(false)
		return
	_waiting_callback = callback
	if _backend.is_ad_ready():
		_show_interstitial()
		return
	_wait_timer = get_tree().create_timer(4.0)
	_wait_timer.timeout.connect(_on_wait_timeout)
	_backend.preload_ad()
	if _waiting_callback.is_valid() and _backend.is_ad_ready() and not _showing:
		_show_interstitial()

func privacy_options_required() -> bool:
	return is_ready() and _privacy_required

func show_privacy_options(callback: Callable = Callable()) -> void:
	if not is_ready() or not _backend.has_method("show_privacy_options"):
		if callback.is_valid():
			callback.call_deferred()
		return
	_backend.show_privacy_options(callback)

func _show_interstitial() -> void:
	_cancel_wait_timer()
	_showing = true
	_backend.show_interstitial()

func _on_wait_timeout() -> void:
	_wait_timer = null
	_fail_waiting()

func _fail_waiting() -> void:
	_cancel_wait_timer()
	var callback := _waiting_callback
	_waiting_callback = Callable()
	if callback.is_valid():
		callback.call_deferred(false)

func _cancel_wait_timer() -> void:
	if _wait_timer != null and _wait_timer.timeout.is_connected(_on_wait_timeout):
		_wait_timer.timeout.disconnect(_on_wait_timeout)
	_wait_timer = null

func _connect_backend() -> void:
	if _backend == null:
		return
	if _backend.has_signal("initialized"):
		_backend.connect("initialized", _on_backend_initialized)
	if _backend.has_signal("ad_ready"):
		_backend.connect("ad_ready", _on_backend_ad_ready)
	if _backend.has_signal("ad_load_failed"):
		_backend.connect("ad_load_failed", _on_backend_ad_load_failed)
	if _backend.has_signal("ad_started"):
		_backend.connect("ad_started", _on_backend_ad_started)
	if _backend.has_signal("ad_ended"):
		_backend.connect("ad_ended", _on_backend_ad_ended)
	if _backend.has_signal("privacy_requirement_changed"):
		_backend.connect("privacy_requirement_changed", _on_privacy_requirement_changed)

func _on_backend_initialized(ok: bool) -> void:
	_backend_ready = ok
	state_changed.emit()

func _on_backend_ad_ready(ready: bool) -> void:
	if ready and _waiting_callback.is_valid() and not _showing:
		_show_interstitial()
	state_changed.emit()

func _on_backend_ad_load_failed() -> void:
	if _waiting_callback.is_valid():
		_fail_waiting()
	state_changed.emit()

func _on_backend_ad_started() -> void:
	_cancel_wait_timer()
	_showing = true
	_last_shown_unix = _now_unix()
	_save_state()
	ad_started.emit()

func _on_backend_ad_ended(shown: bool) -> void:
	_showing = false
	var callback := _waiting_callback
	_waiting_callback = Callable()
	if callback.is_valid():
		callback.call_deferred(shown)
	ad_ended.emit(shown)
	state_changed.emit()

func _on_privacy_requirement_changed(required: bool) -> void:
	_privacy_required = required
	state_changed.emit()

func _exit_tree() -> void:
	_cancel_wait_timer()
	if _backend != null and _backend.has_method("close"):
		_backend.close()

func _now_unix() -> int:
	if _now_override.is_valid():
		return int(_now_override.call())
	return int(Time.get_unix_time_from_system())

func _load_state() -> void:
	_last_shown_unix = 0
	if not FileAccess.file_exists(_state_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_state_path))
	if parsed is Dictionary:
		_last_shown_unix = maxi(0, int(parsed.get("last_interstitial_unix", 0)))

func _save_state() -> void:
	var file := FileAccess.open(_state_path, FileAccess.WRITE)
	if file == null:
		push_warning("AdService could not persist interstitial cooldown.")
		return
	file.store_string(JSON.stringify({"last_interstitial_unix": _last_shown_unix}))
	file.close()
