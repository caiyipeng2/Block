extends SceneTree

# Explicit device test: run with --display-driver headless --audio-driver WASAPI.
# The ordinary headless audio suite never starts a real output device.
const AUDIO_SCRIPT := preload("res://scripts/audio/feedback_audio.gd")
const SILENT_PEAK := 0.00001

var _checks := 0
var _failures := 0
var _audio: Node
var _capture: AudioEffectCapture
var _master := -1
var _effect_index := -1
var _initial_effect_count := 0
var _master_volume := 0.0
var _master_muted := false

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var driver := AudioServer.get_driver_name()
	print("OUTPUT_DRIVER ", driver)
	print("OUTPUT_DEVICE ", AudioServer.output_device)
	print("OUTPUT_DEVICES ", AudioServer.get_output_device_list())
	_expect(driver != "Dummy", "real output test requires a device driver, not Dummy")
	if driver == "Dummy":
		await _finish()
		return
	_master = AudioServer.get_bus_index("Master")
	_expect(_master >= 0, "Master output bus exists")
	if _master < 0:
		await _finish()
		return
	_master_volume = AudioServer.get_bus_volume_db(_master)
	_master_muted = AudioServer.is_bus_mute(_master)
	_initial_effect_count = AudioServer.get_bus_effect_count(_master)
	print("MASTER_VOLUME ", _master_volume, " MUTE ", _master_muted)
	_expect(not _master_muted, "Master is not muted during device validation")
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 2.0
	_effect_index = _initial_effect_count
	AudioServer.add_bus_effect(_master, _capture)
	_audio = AUDIO_SCRIPT.new()
	root.add_child(_audio)
	_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	await _settle_and_clear()
	await _expect_silent("INITIAL_OFF")
	await _test_music_output()
	for kind: String in ["click", "place", "clear", "invalid"]:
		await _test_sound_output(kind)
	await _finish()

func _test_music_output() -> void:
	_audio.apply_settings({"sound_enabled": false, "music_enabled": true})
	var levels: Dictionary = await _collect_levels(1.1)
	_report("MUSIC", levels)
	_expect(not _audio.sound_player.playing, "music is measured without sound feedback")
	_expect(int(levels["frames"]) > 0, "music reaches the audio mixer")
	_expect(float(levels["peak"]) > 0.02, "music has audible mixed output")
	_expect(float(levels["peak"]) < 0.5, "music mixed output does not clip")
	_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	await _settle_and_clear()
	await _expect_silent("MUSIC_OFF")

func _test_sound_output(kind: String) -> void:
	_audio.apply_settings({"sound_enabled": true, "music_enabled": false})
	_capture.clear_buffer()
	_audio.play_feedback(kind)
	var levels: Dictionary = await _collect_levels(0.45)
	_report(kind.to_upper(), levels)
	_expect(not _audio.music_player.playing, kind + " is measured without background music")
	_expect(int(levels["frames"]) > 0, kind + " reaches the audio mixer")
	_expect(float(levels["peak"]) > 0.03, kind + " has audible mixed output")
	_expect(float(levels["peak"]) < 0.5, kind + " mixed output does not clip")
	_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	await _settle_and_clear()
	_audio.play_feedback(kind)
	await _expect_silent(kind.to_upper() + "_OFF")

func _expect_silent(label: String) -> void:
	var levels: Dictionary = await _collect_levels(0.15)
	_report(label, levels)
	_expect(float(levels["peak"]) <= SILENT_PEAK, label + " produces no mixed output")

func _settle_and_clear() -> void:
	await _wait_for_mix()
	_capture.clear_buffer()

func _wait_for_mix() -> void:
	var started := Time.get_ticks_usec()
	var mix_epoch := started - int(AudioServer.get_time_since_last_mix() * 1000000.0)
	while Time.get_ticks_usec() - started < 500000:
		await process_frame
		var next_epoch := Time.get_ticks_usec() - int(AudioServer.get_time_since_last_mix() * 1000000.0)
		if next_epoch > mix_epoch + 1000:
			break
	# Playback references are released on the main thread after the completed mix.
	await process_frame
	await process_frame

func _collect_levels(seconds: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var peak := 0.0
	var sum_squares := 0.0
	var frames := 0
	var meter_peak_db := -200.0
	while true:
		var available := _capture.get_frames_available()
		if available > 0:
			var buffer := _capture.get_buffer(available)
			for sample: Vector2 in buffer:
				peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
				sum_squares += sample.x * sample.x + sample.y * sample.y
			frames += buffer.size()
		meter_peak_db = maxf(meter_peak_db, AudioServer.get_bus_peak_volume_left_db(_master, 0))
		meter_peak_db = maxf(meter_peak_db, AudioServer.get_bus_peak_volume_right_db(_master, 0))
		if Time.get_ticks_usec() - started >= int(seconds * 1000000.0):
			break
		await process_frame
	return {
		"peak": peak,
		"rms": sqrt(sum_squares / (frames * 2)) if frames > 0 else 0.0,
		"frames": frames,
		"master_peak_db": meter_peak_db,
	}

func _report(label: String, levels: Dictionary) -> void:
	print("OUTPUT_LEVEL %s peak_db=%.3f rms_db=%.3f frames=%d master_peak_db=%.3f" % [
		label,
		linear_to_db(maxf(float(levels["peak"]), 0.0000000001)),
		linear_to_db(maxf(float(levels["rms"]), 0.0000000001)),
		int(levels["frames"]),
		float(levels["master_peak_db"]),
	])

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

func _finish() -> void:
	if _audio != null:
		_audio.apply_settings({"sound_enabled": false, "music_enabled": false})
		_audio.queue_free()
		_audio = null
		await _wait_for_mix()
	if _effect_index >= 0:
		AudioServer.remove_bus_effect(_master, _effect_index)
		_capture = null
		await _wait_for_mix()
		_expect(AudioServer.get_bus_effect_count(_master) == _initial_effect_count, "capture effect is removed")
		_expect(AudioServer.get_bus_volume_db(_master) == _master_volume, "Master volume remains unchanged")
		_expect(AudioServer.is_bus_mute(_master) == _master_muted, "Master mute remains unchanged")
	print("AUDIO OUTPUT TESTS: %d checks, %d failures" % [_checks, _failures])
	if _failures == 0:
		print("AUDIO OUTPUT TESTS PASSED")
	quit(0 if _failures == 0 else 1)
