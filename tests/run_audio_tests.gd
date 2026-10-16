extends SceneTree

const AUDIO_SCRIPT := "res://scripts/audio/feedback_audio.gd"

var _failures: int = 0
var _tests: int = 0
var _audio_script: Script

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_tests += 1
	if not FileAccess.file_exists(AUDIO_SCRIPT):
		_expect(false, "FeedbackAudio exists so sound and music settings control real audio")
		_finish()
		return
	_audio_script = load(AUDIO_SCRIPT)
	if _audio_script == null or not _audio_script.can_instantiate():
		_expect(false, "FeedbackAudio loads without script errors")
		_finish()
		return
	for test: Callable in [
		_test_initially_silent,
		_test_music_toggle,
		_test_sound_toggle,
		_test_independent_toggles,
		_test_feedback_streams,
		_test_default_and_unknown_feedback,
		_test_clear_reward_pitch,
		_test_music_stream,
		_test_master_bus_unchanged,
		_test_exit_tree_stops_players,
	]:
		_tests += 1
		await test.call()
		await process_frame
	# The audio mixer releases stopped playback references on its next update.
	await create_timer(0.5).timeout
	_finish()

func _new_audio() -> Node:
	var audio: Node = _audio_script.new()
	root.add_child(audio)
	return audio

func _dispose(audio: Node) -> void:
	audio.sound_player.stop()
	audio.music_player.stop()
	audio.free()

func _test_initially_silent() -> void:
	var audio := _new_audio()
	_expect(audio.music_player is AudioStreamPlayer, "music player is ready")
	_expect(audio.sound_player is AudioStreamPlayer, "sound player is ready")
	_expect(not audio.music_player.playing, "music waits for saved settings before playing")
	_expect(not audio.sound_player.playing, "sound starts silent")
	_dispose(audio)

func _test_music_toggle() -> void:
	var audio := _new_audio()
	audio.apply_settings({"sound_enabled": true, "music_enabled": false})
	_expect(not audio.music_player.playing, "disabled saved music never starts")
	audio.apply_settings({"sound_enabled": true, "music_enabled": true})
	_expect(audio.music_player.playing, "enabling music starts the background loop")
	var stream: AudioStream = audio.music_player.stream
	audio.apply_settings({"sound_enabled": true, "music_enabled": true})
	_expect(audio.music_player.stream == stream, "reapplying settings reuses the background stream")
	_expect(audio.music_player.playing, "reapplying enabled music keeps playback active")
	audio.apply_settings({"sound_enabled": true, "music_enabled": false})
	_expect(not audio.music_player.playing, "disabling music stops current playback")
	audio.apply_settings({"sound_enabled": true, "music_enabled": true})
	_expect(audio.music_player.playing, "music can be enabled again")
	_dispose(audio)

func _test_sound_toggle() -> void:
	var audio := _new_audio()
	audio.apply_settings({"sound_enabled": true, "music_enabled": false})
	audio.play_feedback("place")
	_expect(audio.sound_player.playing, "enabled placement feedback starts playback")
	audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	_expect(not audio.sound_player.playing, "disabling sound immediately stops current playback")
	for kind: String in ["click", "place", "clear", "invalid"]:
		audio.play_feedback(kind)
		_expect(not audio.sound_player.playing, "disabled sound blocks " + kind)
	audio.apply_settings({"sound_enabled": true, "music_enabled": false})
	audio.play_feedback("click")
	_expect(audio.sound_player.playing, "sound can be enabled again")
	_dispose(audio)

func _test_independent_toggles() -> void:
	var audio := _new_audio()
	audio.apply_settings({"sound_enabled": true, "music_enabled": true})
	audio.play_feedback("clear")
	audio.apply_settings({"sound_enabled": false, "music_enabled": true})
	_expect(audio.music_player.playing, "muting sound leaves background music active")
	_expect(not audio.sound_player.playing, "sound is muted independently")
	audio.apply_settings({"sound_enabled": true, "music_enabled": true})
	audio.play_feedback("place")
	audio.apply_settings({"sound_enabled": true, "music_enabled": false})
	_expect(audio.sound_player.playing, "muting music leaves current feedback active")
	_expect(not audio.music_player.playing, "music is muted independently")
	_dispose(audio)

func _test_feedback_streams() -> void:
	var audio := _new_audio()
	audio.apply_settings({"sound_enabled": true, "music_enabled": false})
	var unique_data: Array[PackedByteArray] = []
	for kind: String in ["click", "place", "clear", "invalid"]:
		audio.play_feedback(kind)
		var stream: AudioStreamWAV = audio.sound_player.stream
		_expect(stream != null, kind + " has a WAV stream")
		if stream == null:
			continue
		_expect_pcm(stream, kind)
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, kind + " plays once")
		_expect(stream.get_length() > 0.025 and stream.get_length() < 0.6, kind + " is short feedback")
		_expect(not unique_data.has(stream.data), kind + " has its own audible pattern")
		unique_data.append(stream.data)
		audio.play_feedback(kind)
		_expect(audio.sound_player.stream == stream, kind + " stream is cached")
		var levels := _effective_levels(stream, audio.sound_player.volume_db)
		_expect(float(levels["rms"]) >= 0.03, kind + " effective RMS is audible")
		_expect(float(levels["peak"]) < 0.5, kind + " effective peak stays below clipping")
	_dispose(audio)

func _test_default_and_unknown_feedback() -> void:
	var audio := _new_audio()
	audio.apply_settings({"sound_enabled": true, "music_enabled": false})
	audio.play_feedback("click")
	var click: AudioStream = audio.sound_player.stream
	audio.play_feedback()
	_expect(audio.sound_player.stream == click, "default feedback is click")
	audio.play_feedback("unknown")
	_expect(audio.sound_player.stream == click, "unknown feedback safely uses click")
	_dispose(audio)

func _test_clear_reward_pitch() -> void:
	var audio := _new_audio()
	audio.apply_settings({"sound_enabled": true, "music_enabled": false})
	audio.play_clear_reward(1, 1)
	var clear_stream: AudioStream = audio.sound_player.stream
	var volume: float = audio.sound_player.volume_db
	_expect(is_equal_approx(audio.sound_player.pitch_scale, 1.0), "first real single clear keeps the original pitch")
	audio.play_clear_reward(4, 2)
	_expect(audio.sound_player.stream == clear_stream and audio.sound_player.pitch_scale > 1.0, "streak and multiline use the cached clear with a rising pitch")
	audio.play_clear_reward(100, 8)
	_expect(audio.sound_player.pitch_scale < 1.27 and audio.sound_player.volume_db == volume, "reward pitch is bounded and never raises volume")
	audio.play_feedback("place")
	_expect(is_equal_approx(audio.sound_player.pitch_scale, 1.0), "ordinary sounds restore their own pitch")
	audio.apply_settings({"sound_enabled": false, "music_enabled": false})
	audio.play_clear_reward(10, 4)
	_expect(not audio.sound_player.playing, "muted reward feedback stays silent")
	_dispose(audio)

func _test_music_stream() -> void:
	var audio := _new_audio()
	audio.apply_settings({"sound_enabled": true, "music_enabled": true})
	var stream: AudioStreamWAV = audio.music_player.stream
	_expect(stream != null, "background melody has a WAV stream")
	if stream != null:
		_expect_pcm(stream, "music")
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "background melody loops forward")
		_expect(stream.loop_begin == 0, "music loop starts at the first frame")
		_expect(stream.loop_end == stream.data.size() / 2, "music loop covers all mono PCM frames")
		_expect(stream.get_length() >= 4.0 and stream.get_length() <= 16.0, "background is a short complete melody")
		var levels := _effective_levels(stream, audio.music_player.volume_db)
		_expect(float(levels["rms"]) >= 0.025, "music effective RMS is audible")
		_expect(float(levels["peak"]) < 0.5, "music effective peak stays below clipping")
	_dispose(audio)

func _test_master_bus_unchanged() -> void:
	var master := AudioServer.get_bus_index("Master")
	var volume := AudioServer.get_bus_volume_db(master)
	var muted := AudioServer.is_bus_mute(master)
	var audio := _new_audio()
	audio.apply_settings({"sound_enabled": false, "music_enabled": true})
	audio.apply_settings({"sound_enabled": true, "music_enabled": false})
	_expect(AudioServer.get_bus_volume_db(master) == volume, "settings do not alter global Master volume")
	_expect(AudioServer.is_bus_mute(master) == muted, "settings do not alter global Master mute")
	_dispose(audio)

func _test_exit_tree_stops_players() -> void:
	var audio := _new_audio()
	audio.apply_settings({"sound_enabled": true, "music_enabled": true})
	audio.play_feedback("clear")
	root.remove_child(audio)
	_expect(not audio.music_player.playing, "leaving the scene tree stops background music")
	_expect(not audio.sound_player.playing, "leaving the scene tree stops feedback")
	audio.free()

func _expect_pcm(stream: AudioStreamWAV, label: String) -> void:
	_expect(stream.mix_rate == 22050, label + " uses 22050 Hz")
	_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS, label + " uses signed 16-bit PCM")
	_expect(not stream.stereo, label + " uses mono PCM")
	var data := stream.data
	_expect(data.size() > 0 and data.size() % 2 == 0, label + " contains complete PCM frames")
	var peak := 0
	for offset: int in range(0, data.size(), 2):
		peak = maxi(peak, absi(data.decode_s16(offset)))
	_expect(peak > 0, label + " contains audible non-silent samples")
	_expect(peak <= 12000, label + " PCM amplitude stays low and does not clip")
	if data.size() >= 4:
		_expect(absi(data.decode_s16(0)) < 100 and absi(data.decode_s16(data.size() - 2)) < 100, label + " begins and ends softly")

func _effective_levels(stream: AudioStreamWAV, volume_db: float) -> Dictionary:
	var data := stream.data
	var sample_count := data.size() / 2
	var peak := 0.0
	var sum_squares := 0.0
	for offset: int in range(0, data.size(), 2):
		var sample := absf(float(data.decode_s16(offset)) / 32767.0)
		peak = maxf(peak, sample)
		sum_squares += sample * sample
	var gain := db_to_linear(volume_db)
	return {
		"peak": peak * gain,
		"rms": sqrt(sum_squares / sample_count) * gain,
	}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

func _finish() -> void:
	print("AUDIO TESTS: %d cases, %d failures" % [_tests, _failures])
	if _failures == 0:
		print("AUDIO TESTS PASSED")
	quit(0 if _failures == 0 else 1)
