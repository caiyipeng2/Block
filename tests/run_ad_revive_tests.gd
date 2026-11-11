extends SceneTree

const SAVE := "user://ad-revive-test.json"

class FakeAds extends Node:
	var attempts := 0
	var result := true

	func can_attempt_revive() -> bool:
		return true

	func request_revive_interstitial(callback: Callable) -> void:
		attempts += 1
		callback.call_deferred(result)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE + ".leaderboard"))
	var data := SaveRepository.defaults()
	data["reduced_motion"] = true
	data["sound_enabled"] = false
	data["music_enabled"] = false
	SaveRepository.save_data(data, SAVE)
	root.size = Vector2i(1280, 720)
	var main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await _settle()
	var fake := FakeAds.new()
	main.ad_service = fake
	main._start_game("free")
	await _settle()
	_fill_some_cells(main.game)
	main.game.status = GameState.Status.GAME_OVER
	main.screen = "game"
	main.paused = false
	main.input_locked = false
	main._try_show_game_over()
	await _settle()
	_check(fake.attempts == 1, "first failure requests one automatic ad")
	_check(main.screen == "game" and main.game.status == GameState.Status.PLAYING and main.game.revive_used, "successful ad resumes the revived run")

	main.game.status = GameState.Status.GAME_OVER
	main.screen = "game"
	main._try_show_game_over()
	await _settle()
	_check(fake.attempts == 1 and main.screen == "game_over", "the same run never requests a second revive ad")

	main._start_game("free")
	await _settle()
	fake.result = false
	_fill_some_cells(main.game)
	main.game.status = GameState.Status.GAME_OVER
	main.screen = "game"
	main._try_show_game_over()
	await _settle()
	_check(fake.attempts == 2 and main.screen == "game_over" and main.game.status == GameState.Status.GAME_OVER, "failed or unavailable ad keeps the normal failure page")

	main.free()
	fake.free()
	await _settle()
	for path in [SAVE, SAVE + ".leaderboard"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures == 0:
		print("AD REVIVE TESTS PASSED")
	quit(0 if _failures == 0 else 1)

func _fill_some_cells(game: GameState) -> void:
	for y in range(2):
		for x in range(5):
			game.board.set_cell(x, y, 1)

func _settle() -> void:
	for _i in range(5):
		await process_frame

var _failures := 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("AD REVIVE: " + message)
