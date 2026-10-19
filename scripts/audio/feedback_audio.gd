class_name FeedbackAudio
extends Node

const SAMPLE_RATE := 22050
# PCM envelopes are already soft; avoid attenuating their output twice.
const SOUND_VOLUME_DB := -4.0
const MUSIC_VOLUME_DB := -6.0

static var _sound_streams: Dictionary = {}
static var _music_stream: AudioStreamWAV

var sound_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var sound_enabled := true
var music_enabled := false
var _settings_applied := false

func _ready() -> void:
	if _sound_streams.is_empty():
		for kind: String in ["click", "place", "clear", "invalid"]:
			_sound_streams[kind] = _make_feedback(kind)
	if _music_stream == null:
		_music_stream = _make_music()

	sound_player = AudioStreamPlayer.new()
	sound_player.name = "SoundPlayer"
	sound_player.volume_db = SOUND_VOLUME_DB
	add_child(sound_player)
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.volume_db = MUSIC_VOLUME_DB
	music_player.stream = _music_stream
	add_child(music_player)
	# Loading saved settings decides whether the first background note should play.
	if _settings_applied:
		_apply_playback_settings()

func apply_settings(data: Dictionary) -> void:
	sound_enabled = bool(data.get("sound_enabled", true))
	music_enabled = bool(data.get("music_enabled", true))
	_settings_applied = true
	if sound_player != null and music_player != null:
		_apply_playback_settings()

func play_feedback(kind: String = "click") -> void:
	_play_sound(kind, 1.0)

func play_clear_reward(combo: int, line_count: int) -> void:
	# A small rising interval rewards actual streaks without changing points
	# or carrying the raised pitch into clicks, placement, or adventure audio.
	var semitones := minf(float(maxi(combo - 1, 0)) * 0.45 + float(maxi(line_count - 1, 0)) * 0.70, 4.0)
	_play_sound("clear", pow(2.0, semitones / 12.0))

func _play_sound(kind: String, pitch: float) -> void:
	if not sound_enabled or sound_player == null:
		return
	sound_player.pitch_scale = pitch
	sound_player.stream = _sound_streams.get(kind, _sound_streams["click"])
	sound_player.play()

func _apply_playback_settings() -> void:
	if not sound_enabled:
		sound_player.stop()
	if music_enabled:
		if not music_player.playing:
			music_player.play()
	else:
		music_player.stop()

func _make_feedback(kind: String) -> AudioStreamWAV:
	var duration := 0.065
	var start_frequency := 880.0
	var end_frequency := 660.0
	match kind:
		"place":
			duration = 0.14
			start_frequency = 392.0
			end_frequency = 523.25
		"clear":
			duration = 0.33
		"invalid":
			duration = 0.13
			start_frequency = 185.0
			end_frequency = 115.0
	var frame_count := int(duration * SAMPLE_RATE)
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	var phase := 0.0
	for frame: int in frame_count:
		var time := float(frame) / SAMPLE_RATE
		var progress := float(frame) / (frame_count - 1)
		var frequency := lerpf(start_frequency, end_frequency, progress)
		var envelope := minf(1.0, time / 0.004) * pow(1.0 - progress, 2.0)
		if kind == "clear":
			var note_index := mini(int(time / 0.11), 2)
			frequency = [523.25, 659.25, 783.99][note_index]
			var note_time := fmod(time, 0.11)
			envelope = minf(1.0, note_time / 0.006) * maxf(0.0, 1.0 - note_time / 0.11)
		phase += TAU * frequency / SAMPLE_RATE
		var sample := sin(phase) * envelope * 0.24
		pcm.encode_s16(frame * 2, int(sample * 32767.0))
	return _pcm_stream(pcm)

func _make_music() -> AudioStreamWAV:
	# An original eight-note phrase, with a gentle low sine harmony beneath it.
	var notes := PackedFloat32Array([261.63, 329.63, 392.0, 329.63, 293.66, 349.23, 440.0, 392.0])
	const NOTE_SECONDS := 1.5
	var frame_count := int(notes.size() * NOTE_SECONDS * SAMPLE_RATE)
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	for frame: int in frame_count:
		var time := float(frame) / SAMPLE_RATE
		var note_index := mini(int(time / NOTE_SECONDS), notes.size() - 1)
		var note_time := fmod(time, NOTE_SECONDS)
		var attack := minf(1.0, note_time / 0.08)
		var release := minf(1.0, (NOTE_SECONDS - note_time) / 0.22)
		var envelope := attack * release * exp(-note_time * 0.8)
		var frequency := float(notes[note_index])
		var melody := sin(TAU * frequency * note_time) + 0.15 * sin(TAU * frequency * 2.0 * note_time)
		var harmony_frequency := 130.815 if note_index < 4 else 174.615
		var harmony := sin(TAU * harmony_frequency * note_time) * 0.25
		var sample := (melody + harmony) * envelope * 0.16
		pcm.encode_s16(frame * 2, int(sample * 32767.0))
	var stream := _pcm_stream(pcm)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	# Godot 4.7's WAV mixer reads loop_end as an inclusive frame index.
	# Using the sample count reads one PCM16 frame past the buffer on Android.
	stream.loop_end = frame_count - 1
	return stream

func _pcm_stream(pcm: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	return stream
