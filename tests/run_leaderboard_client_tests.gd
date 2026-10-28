extends SceneTree

var failures := 0
const STORE_PATH := "user://leaderboard-test.json"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not ResourceLoader.exists("res://scripts/persistence/leaderboard_store.gd"):
		_check(false, "leaderboard store is implemented")
		quit(1)
		return
	var store_script = load("res://scripts/persistence/leaderboard_store.gd")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE_PATH))
	var source := SaveRepository.defaults()
	source.merge({"high_score": 120, "classic_high_score": 90, "adventure_highest_completed": 2, "adventure_best_scores": {"1": 30, "2": 50, "3": 999}}, true)
	var store = store_script.new()
	store.initialize(STORE_PATH, source, "test-device")
	_check(store.data["local_records"]["adventure"] == {"completed": 2, "score": 80}, "only completed level best scores enter adventure record")
	_check(store.data["local_records"]["classic"]["score"] == 90, "classic stays separate")
	var uid: String = store.data["device_uid"]
	_check(not uid.contains("test-device") and uid.begins_with("v1_"), "device identifier is not exposed")
	source["high_score"] = 800
	store.update_records(source)
	_check(store.data["legacy_snapshot"]["high_score"] == 120, "migration freezes first snapshot")
	var restored = store_script.new()
	restored.initialize(STORE_PATH, source, "test-device")
	_check(restored.data["device_uid"] == uid, "identity survives reload")
	_check(restored.data["legacy_snapshot"]["high_score"] == 120, "reload cannot expand legacy import")
	_check(restored.data["local_records"]["free"]["score"] == 800, "local best survives reload")
	_check(store.update_profile("Étoile", 3), "French nickname accepted")
	_check(not store.update_profile("x", 0), "short nickname rejected")
	_check(not store.update_profile("Valid", 6), "unknown avatar rejected")
	_check(not store.update_profile("a\nb", 0), "control characters rejected")
	store.enqueue({"id": "run-a", "sequence": 1, "mode": "free", "score": 150})
	store.enqueue({"id": "run-a", "sequence": 2, "mode": "free", "score": 180})
	store.enqueue({"id": "run-a", "sequence": 1, "mode": "free", "score": 150})
	_check(store.data["queue"].size() == 1 and store.data["queue"][0]["score"] == 180, "queue retains latest checkpoint without duplicates")
	store.acknowledge("run-a", 1)
	_check(store.data["queue"].size() == 1, "late acknowledgement cannot erase newer checkpoint")
	store.acknowledge("run-a", 2)
	_check(store.data["queue"].is_empty(), "acknowledged checkpoint removed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE_PATH))
	await _test_client()
	_test_tickets_and_checkpoints()
	_test_retry_and_malformed_responses()
	_test_profile_and_cache_acknowledgements()
	_test_stale_acknowledgements()
	_test_result_modes()
	_test_corrupt_persistence()
	_test_open_board_migration_race()
	_test_profile_write_failure()
	_test_refresh_encoding()
	_test_pagination_consistency()
	_test_persistence_network_gate()
	_test_session_renewal()
	_test_stale_failures()
	_test_adventure_pending()
	await _test_transport()
	if failures == 0:
		print("LEADERBOARD CLIENT TESTS PASSED")
	quit(0 if failures == 0 else 1)

class TestTransport extends Node:
	signal completed(id: int, status: int, body: Dictionary, error: String)
	var requests: Array = []
	func send(url: String, method: int, headers: PackedStringArray, body: String) -> int:
		requests.append({"url": url, "method": method, "headers": headers, "body": body})
		return requests.size()

func _test_client() -> void:
	if not ResourceLoader.exists("res://scripts/persistence/leaderboard_client.gd"):
		_check(false, "leaderboard client is implemented")
		return
	var script = load("res://scripts/persistence/leaderboard_client.gd")
	var client = script.new()
	root.add_child(client)
	var wire := TestTransport.new()
	client.configure(STORE_PATH, SaveRepository.defaults(), wire)
	client.open_board("classic")
	_check(wire.requests.is_empty(), "unconfigured client never sends network requests")
	_check(client.view()["status"] == "unconfigured" and client.view()["me"].is_empty(), "unconfigured service does not fabricate rank")
	client.begin_run("classic", 0, 42, 0)
	client.record_move(0, Vector2i(1, 2), 3, 20, false)
	client.finish_run(20, false)
	_check(client.store.data["queue"].is_empty(), "offline-started score never enters verified submission queue")
	client.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE_PATH))
	client = script.new()
	root.add_child(client)
	wire = TestTransport.new()
	client.configure(STORE_PATH, SaveRepository.defaults(), wire, "https://leaderboard.invalid", "test-public-key")
	client.open_board("classic")
	_check(wire.requests.size() == 1 and wire.requests[0]["url"].contains("accounts:signUp"), "anonymous session precedes leaderboard access")
	wire.completed.emit(1, 200, {"idToken": "test-token", "refreshToken": "test-refresh", "localId": "account-a", "expiresIn": "3600"}, "")
	var board_id := wire.requests.size()
	_check(wire.requests[-1]["url"].contains("/leaderboards/classic"), "authorized session reads selected mode")
	var entry := {"account_id": "account-a", "rank": 127, "nickname": "Étoile", "avatar": 2, "score": 90, "completed": 0}
	wire.completed.emit(board_id, 200, {"entries": [], "me": entry, "next_cursor": "", "updated_at": 1700000000}, "")
	_check(client.view()["me"].get("rank") == 127, "personal rank may be outside top100")
	client.open_board("free", true)
	var free_id := wire.requests.size()
	client.open_board("adventure", true)
	wire.completed.emit(free_id, 200, {"entries": [], "me": {}, "next_cursor": "", "updated_at": 1700000000}, "")
	_check(client.view()["mode"] == "adventure", "late response cannot change selected tab")
	client.open_board("classic", true)
	wire.completed.emit(wire.requests.size(), 503, {}, "")
	_check(client.view()["status"] == "maintenance" and client.view()["me"].get("score") == 90, "maintenance preserves acknowledged cache")
	client.open_board("classic", true)
	wire.completed.emit(wire.requests.size(), 200, {"entries": [{"rank": -2}], "me": {}, "updated_at": 0}, "")
	_check(client.view()["me"].get("rank") == 127, "malformed payload cannot erase cache")
	client.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE_PATH))

func _test_open_board_migration_race() -> void:
	var client := _new_client(false)
	var wire: TestTransport = client._transport
	client.open_board("classic")
	wire.completed.emit(1, 200, {"idToken": "token", "refreshToken": "refresh", "localId": "account-a", "expiresIn": "3600"}, "")
	var old_board := wire.requests.size()
	wire.completed.emit(2, 200, {"migration_id": client.store.data["legacy_id"], "accepted": true}, "")
	_check(wire.requests.size() > old_board, "migration ACK refreshes already-open board rather than leaving loading")
	wire.completed.emit(old_board, 200, _empty_board(), "")
	if wire.requests.size() > old_board:
		wire.completed.emit(wire.requests.size(), 200, _empty_board(), "")
	_check(client.view()["status"] == "empty", "first-open migration race settles to real empty board")
	_dispose(client)

func _test_profile_write_failure() -> void:
	var client := _new_client()
	var profile: Dictionary = client.store.data["profile"].duplicate()
	client.store.read_failed = true
	client.store.save_failed = true
	_check(not client.update_profile("ValidName", 2), "failed profile persistence cannot report save success")
	_check(client.store.data["profile"] == profile, "failed profile save retains accepted profile")
	_dispose(client)

func _test_refresh_encoding() -> void:
	var client := _new_client()
	client.store.data["session"]["expires_at"] = 0
	client.store.data["session"]["refresh_token"] = "refresh+token&=value"
	client.connect_service()
	var request: Dictionary = client._transport.requests[0]
	_check(request["headers"].has("Content-Type: application/x-www-form-urlencoded"), "refresh token uses form content type")
	_check(request["body"] == "grant_type=refresh_token&refresh_token=refresh%2Btoken%26%3Dvalue", "refresh token is safely form encoded")
	_dispose(client)

func _test_pagination_consistency() -> void:
	var client := _new_client()
	var wire: TestTransport = client._transport
	client.open_board("classic")
	var first := _empty_board()
	first["entries"] = [{"account_id": "a", "rank": 1, "nickname": "Alpha", "avatar": 0, "score": 100, "completed": 0}, {"account_id": "b", "rank": 2, "nickname": "Beta", "avatar": 0, "score": 90, "completed": 0}]
	first["next_cursor"] = "page2"
	wire.completed.emit(1, 200, first, "")
	client.load_more()
	var second := _empty_board()
	second["entries"] = [{"account_id": "c", "rank": 1, "nickname": "Gamma", "avatar": 0, "score": 110, "completed": 0}]
	wire.completed.emit(2, 200, second, "")
	_check(client.view()["entries"] == first["entries"], "rank inversion across pages retains acknowledged cache")
	_check(wire.requests.size() == 3 and not wire.requests[-1]["url"].contains("cursor="), "contradictory pagination restarts at first page")
	var restored = load("res://scripts/persistence/leaderboard_store.gd").new()
	restored.initialize(STORE_PATH, SaveRepository.defaults(), "test-device")
	_check(not restored.read_failed, "pagination cannot persist cache rejected on next launch")
	_dispose(client)

func _test_persistence_network_gate() -> void:
	var client := _new_client(false)
	var wire: TestTransport = client._transport
	var identity: String = client.store.data["legacy_id"]
	client.store.path = "user://leaderboard-missing-parent/test.json"
	client.store.persist()
	client.connect_service()
	_check(wire.requests.is_empty(), "undurable initial identity cannot create remote account")
	_check(client._retry_at > 0, "initial persistence failure schedules retry")
	client.store.path = STORE_PATH
	_expire_retry(client)
	_check(wire.requests.size() == 1 and client.store.data["legacy_id"] == identity, "storage recovery retries same migration identity")
	client.store.path = "user://leaderboard-missing-parent/test.json"
	wire.completed.emit(1, 200, {"idToken": "token", "refreshToken": "refresh", "localId": "account-a", "expiresIn": "3600"}, "")
	_check(wire.requests.size() == 1 and client._retry_at > 0, "undurable authenticated session cannot import records")
	client.begin_run("classic", 0, 42, 0)
	_check(client._run["local_only"] and wire.requests.size() == 1, "undurable session cannot issue verified run ticket")
	client.store.path = STORE_PATH
	_expire_retry(client)
	_check(wire.requests.size() == 2 and wire.requests[-1]["url"].ends_with("/v1/legacy-import"), "storage recovery preserves authenticated account without signup")
	_dispose(client)

func _test_session_renewal() -> void:
	var client := _new_client()
	var wire: TestTransport = client._transport
	client.store.data["session"]["expires_at"] = Time.get_unix_time_from_system() + 30
	client._process(0.0)
	_check(wire.requests.size() == 1 and wire.requests[-1]["url"].contains("securetoken"), "idle session refreshes before expiry with board closed")
	client._process(0.0)
	_check(wire.requests.size() == 1, "session renewal has one inflight auth request")
	wire.completed.emit(1, 503, {}, "")
	client._process(0.0)
	_check(wire.requests.size() == 1 and client._retry_at > 0, "automatic renewal honors backoff")
	_dispose(client)

func _test_stale_failures() -> void:
	for kind in ["board", "neighbors"]:
		var client := _new_client()
		var wire: TestTransport = client._transport
		client.open_board("classic")
		var stale := wire.requests.size()
		if kind == "neighbors":
			wire.completed.emit(stale, 200, _empty_board(), "")
			client.load_neighbors()
			stale = wire.requests.size()
		client._invalidate_cache("classic")
		client.open_board("classic", true)
		wire.completed.emit(wire.requests.size(), 200, _empty_board(), "")
		wire.completed.emit(stale, 503, {}, "")
		_check(client.view()["status"] == "empty" and client._retry_at == 0, "obsolete %s failure cannot replace fresh status or schedule retry" % kind)
		_dispose(client)

func _test_adventure_pending() -> void:
	var client := _new_client()
	var wire: TestTransport = client._transport
	var source := SaveRepository.defaults()
	client.begin_run("adventure", 1, 42, 0)
	_ticket(client)
	client.record_move(0, Vector2i.ZERO, 0, 30, true)
	wire.completed.emit(wire.requests.size(), 200, {"accepted": true, "run_id": client._run["id"], "sequence": 1}, "")
	source["adventure_highest_completed"] = 1
	source["adventure_best_scores"] = {"1": 30}
	client.update_records(source)
	client.begin_run("adventure", 2, 42, 0)
	_ticket(client)
	client.record_move(0, Vector2i.ZERO, 0, 50, true)
	source["adventure_highest_completed"] = 2
	source["adventure_best_scores"]["2"] = 50
	client.update_records(source)
	_check(not client.result_view("adventure")["local_only"] and client._local_pending("adventure").get("eligible", false), "single-level checkpoint contributes to cumulative pending adventure record")
	wire.completed.emit(wire.requests.size(), 200, {"accepted": true, "run_id": client._run["id"], "sequence": 1}, "")
	client.begin_run("adventure", 1, 99, 0)
	_ticket(client)
	client.record_move(0, Vector2i.ZERO, 0, 40, true)
	source["adventure_best_scores"]["1"] = 40
	client.update_records(source)
	_check(client._local_pending("adventure").get("eligible", false), "earlier-level replay improvement remains eligible with higher levels completed")
	var restored = load("res://scripts/persistence/leaderboard_client.gd").new()
	root.add_child(restored)
	restored.configure(STORE_PATH, source, TestTransport.new(), "https://leaderboard.invalid", "test-public-key")
	restored.set_process(false)
	_check(not restored.store.read_failed and restored._local_pending("adventure").get("eligible", false), "acknowledged per-level baseline and pending improvement survive restart")
	restored.free()
	source["adventure_best_scores"]["2"] = 100
	client.update_records(source)
	_check(client.result_view("adventure")["local_only"], "queued earlier-level improvement cannot make an offline higher total eligible")
	_dispose(client)

func _new_client(authenticated: bool = true) -> Node:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE_PATH))
	var client: Node = load("res://scripts/persistence/leaderboard_client.gd").new()
	root.add_child(client)
	client.configure(STORE_PATH, SaveRepository.defaults(), TestTransport.new(), "https://leaderboard.invalid", "test-public-key")
	client.set_process(false)
	if authenticated:
		client.store.data["session"] = {"id_token": "token", "refresh_token": "refresh", "account_id": "account-a", "expires_at": Time.get_unix_time_from_system() + 3600}
		client.store.data["legacy_done"] = true
	return client

func _dispose(client: Node) -> void:
	client.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE_PATH))

func _empty_board() -> Dictionary:
	return {"entries": [], "me": {}, "next_cursor": "", "updated_at": 1700000000}

func _ticket(client: Node) -> void:
	client._transport.completed.emit(client._transport.requests.size(), 200, {"run_id": client._run["id"], "ticket": "signed-ticket", "ruleset_id": client._ruleset}, "")

func _expire_retry(client: Node) -> void:
	# Advance only the retry deadline: no wall-clock waits or real network.
	client._retry_at = Time.get_ticks_msec()
	if client._retry_at == 0:
		client._retry_at = 1
	client._process(0.0)

func _test_tickets_and_checkpoints() -> void:
	var client := _new_client()
	var wire: TestTransport = client._transport
	client.begin_run("classic", 0, 42, 0)
	_ticket(client)
	for index in range(10):
		client.record_move(0, Vector2i(1, 2), 3, 100, false)
	var old_ack := wire.requests.size()
	_check(client.store.data["queue"].size() == 1 and client.store.data["queue"][0]["sequence"] == 10, "timely ticket allows ten-move checkpoint")
	var checkpoint: Dictionary = JSON.parse_string(wire.requests[-1]["body"])
	_check(checkpoint["moves"].size() == 10 and checkpoint["ticket"] == "signed-ticket" and wire.requests[-1]["headers"].has("Authorization: Bearer token"), "checkpoint carries replay, ticket and authorization")
	client.record_move(1, Vector2i(2, 3), 4, 110, false)
	client.finish_run(110, false)
	wire.completed.emit(old_ack, 200, {"accepted": true, "run_id": checkpoint["id"], "sequence": 10}, "")
	_check(client.store.data["queue"].size() == 1 and client.store.data["queue"][0]["sequence"] == 11, "old ACK preserves and sends newer checkpoint")
	_check(JSON.parse_string(wire.requests[-1]["body"])["sequence"] == 11, "newest checkpoint follows stale sequence ACK")
	var newest := wire.requests.size()
	wire.completed.emit(newest, 503, {}, "")
	_check(client.store.data["queue"].size() == 1 and client._retry_at > 0, "checkpoint failure retains replay for retry")
	_expire_retry(client)
	_check(wire.requests.size() == newest + 1 and JSON.parse_string(wire.requests[-1]["body"])["sequence"] == 11, "closed-board retry resubmits checkpoint")
	wire.completed.emit(wire.requests.size(), 422, {}, "")
	_check(client.store.data["queue"].is_empty() and not client.view()["notice"].is_empty(), "rejected checkpoint is removed with notice")
	_dispose(client)

	client = _new_client()
	wire = client._transport
	client.begin_run("free", 0, 42, 0)
	client.record_move(0, Vector2i.ZERO, 0, 10, false)
	_ticket(client)
	client.record_move(0, Vector2i.ZERO, 0, 20, false)
	client.finish_run(20, false)
	_check(client._run["local_only"] and client.store.data["queue"].is_empty(), "ticket after first move cannot rehabilitate local-only run")
	client.begin_run("classic", 0, 1, 0)
	var old_ticket := wire.requests.size()
	var old_run: String = client._run["id"]
	client.begin_run("classic", 0, 2, 0)
	wire.completed.emit(old_ticket, 200, {"run_id": old_run, "ticket": "old", "ruleset_id": client._ruleset}, "")
	_check(client._run["ticket"].is_empty(), "old-run ticket cannot authorize current run")
	_ticket(client)
	_check(client._run["ticket"] == "signed-ticket", "current-run ticket still accepted after stale response")
	_dispose(client)

	client = _new_client(false)
	client.begin_run("free", 0, 42, 0)
	client.connect_service()
	client._transport.completed.emit(1, 200, {"idToken": "token", "refreshToken": "refresh", "localId": "a", "expiresIn": "3600"}, "")
	client.record_move(0, Vector2i.ZERO, 0, 10, true)
	client.finish_run(10, true)
	_check(client._run["local_only"] and client.store.data["queue"].is_empty(), "reconnecting cannot submit offline-started run")
	_dispose(client)

	client = _new_client()
	client.begin_run("adventure", 3, 42, 0)
	_ticket(client)
	for index in range(10):
		client.record_move(0, Vector2i.ZERO, 0, 100, false)
	_check(client.store.data["queue"].is_empty(), "unfinished adventure level never checkpoints")
	client.record_move(0, Vector2i.ZERO, 0, 120, true)
	_check(client.store.data["queue"].size() == 1, "completed adventure level checkpoints")
	_dispose(client)

func _test_retry_and_malformed_responses() -> void:
	var client := _new_client()
	var wire: TestTransport = client._transport
	client.update_profile("First", 1)
	wire.completed.emit(1, 503, {}, "")
	var deadline: int = client._retry_at
	client.open_board("classic", true)
	wire.completed.emit(2, 200, _empty_board(), "")
	_check(client._retry_at == deadline, "unrelated board success cannot cancel profile retry")
	var before := wire.requests.size()
	_expire_retry(client)
	var profile_sent := false
	for request: Dictionary in wire.requests.slice(before):
		profile_sent = profile_sent or request["url"].ends_with("/v1/profile")
	_check(profile_sent, "retry with board open still resumes synchronization")
	_dispose(client)

	for kind in ["auth", "auth_refresh", "legacy", "checkpoint", "profile"]:
		client = _new_client(kind not in ["auth", "auth_refresh"])
		wire = client._transport
		match kind:
			"auth", "auth_refresh":
				if kind == "auth_refresh":
					client.store.data["session"] = {"refresh_token": "refresh"}
				client.connect_service()
			"legacy":
				client.store.data["legacy_done"] = false
				client.connect_service()
			"profile":
				client.update_profile("First", 1)
			"checkpoint":
				client.begin_run("free", 0, 42, 0)
				_ticket(client)
				client.record_move(0, Vector2i.ZERO, 0, 10, true)
		var request_id := wire.requests.size()
		wire.completed.emit(request_id, 200, {}, "")
		_check(client._retry_at > 0 and client._states["free" if kind == "checkpoint" else client.selected_mode] == "error", "malformed 200 " + kind + " schedules visible retry")
		_check(not client._sync_busy and not client._auth_busy, "malformed " + kind + " releases busy flags")
		if kind == "checkpoint":
			_check(client.store.data["queue"].size() == 1, "malformed checkpoint ACK retains queue")
		_expire_retry(client)
		_check(wire.requests.size() == request_id + 1 and wire.requests[-1]["url"] == wire.requests[request_id - 1]["url"], "malformed " + kind + " retries same operation")
		_dispose(client)

	client = _new_client(false)
	client.connect_service()
	client._transport.completed.emit(1, 200, {"idToken": "token", "refreshToken": "refresh", "localId": "a", "expiresIn": "not-a-duration"}, "")
	_check(client.store.data["session"].is_empty() and client._retry_at > 0, "invalid auth expiry cannot install unusable session")
	_dispose(client)

func _test_profile_and_cache_acknowledgements() -> void:
	var client := _new_client()
	var wire: TestTransport = client._transport
	client.update_profile("First", 1)
	client.update_profile("Newest", 2)
	wire.completed.emit(1, 200, {"accepted": true}, "")
	_check(client.store.data["profile_dirty"] and wire.requests.size() == 2, "profile changed inflight immediately syncs newest after old ACK")
	if wire.requests.size() == 2:
		_check(JSON.parse_string(wire.requests[1]["body"])["nickname"] == "Newest", "follow-up profile request uses newest profile")
		wire.completed.emit(2, 200, {"accepted": true}, "")
		_check(not client.store.data["profile_dirty"], "matching profile ACK clears dirty flag")
	_dispose(client)

	for kind in ["legacy", "checkpoint"]:
		client = _new_client()
		wire = client._transport
		for mode in ["free", "classic", "adventure"]:
			client.open_board(mode)
			wire.completed.emit(wire.requests.size(), 200, _empty_board(), "")
		client.close_board()
		if kind == "legacy":
			client.store.data["legacy_done"] = false
			client.connect_service()
			wire.completed.emit(wire.requests.size(), 200, {"accepted": true, "migration_id": client.store.data["legacy_id"]}, "")
		else:
			client.begin_run("classic", 0, 42, 0)
			_ticket(client)
			client.record_move(0, Vector2i.ZERO, 0, 10, true)
			wire.completed.emit(wire.requests.size(), 200, {"accepted": true, "run_id": client._run["id"], "sequence": 1}, "")
		var before := wire.requests.size()
		client.open_board("classic")
		_check(wire.requests.size() == before + 1, "accepted " + kind + " invalidates affected cache before next open")
		if kind == "legacy":
			before = wire.requests.size()
			client.open_board("free")
			_check(wire.requests.size() == before + 1, "migration invalidates all mode caches")
		_dispose(client)

func _test_stale_acknowledgements() -> void:
	var client := _new_client()
	var wire: TestTransport = client._transport
	client.begin_run("classic", 0, 42, 0)
	_ticket(client)
	client.record_move(0, Vector2i.ZERO, 0, 10, true)
	var first_ack := wire.requests.size()
	var first_run: String = client._run["id"]
	client.record_move(0, Vector2i.ZERO, 0, 20, true)
	wire.completed.emit(first_ack, 422, {}, "")
	_check(client.store.data["queue"].size() == 1 and client.store.data["queue"][0]["sequence"] == 2, "stale rejection cannot remove newer checkpoint")
	_check(wire.requests.size() == first_ack + 1 and JSON.parse_string(wire.requests[-1]["body"])["sequence"] == 2, "rejection continues syncing newer eligible checkpoint")
	var second_ack := wire.requests.size()
	client.begin_run("free", 0, 99, 0)
	_ticket(client)
	client.record_move(0, Vector2i.ZERO, 0, 30, true)
	wire.completed.emit(second_ack, 200, {"accepted": true, "run_id": first_run, "sequence": 2}, "")
	_check(client.store.data["queue"].size() == 1 and client.store.data["queue"][0]["id"] == client._run["id"], "old-run ACK cannot erase new-run checkpoint")
	var current_ack := wire.requests.size()
	wire.completed.emit(current_ack, 200, {"accepted": true, "run_id": first_run, "sequence": 1}, "")
	_check(client.store.data["queue"].size() == 1 and client._retry_at > 0, "mismatched checkpoint ACK preserves current run and schedules retry")
	_expire_retry(client)
	wire.completed.emit(wire.requests.size(), 200, {"accepted": true, "run_id": client._run["id"], "sequence": 1}, "")
	_check(client.store.data["queue"].is_empty(), "matching retried ACK drains queue")
	_dispose(client)

	client = _new_client()
	wire = client._transport
	client.store.data["legacy_done"] = false
	client.connect_service()
	wire.completed.emit(1, 200, {"accepted": true, "migration_id": "other-migration"}, "")
	_check(not client.store.data["legacy_done"] and client._retry_at > 0, "mismatched migration ACK cannot mark import done")
	_dispose(client)

	client = _new_client()
	wire = client._transport
	client.open_board("classic")
	wire.completed.emit(1, 200, _empty_board(), "")
	client.open_board("classic", true)
	var stale_board := wire.requests.size()
	client.begin_run("classic", 0, 42, 0)
	_ticket(client)
	client.record_move(0, Vector2i.ZERO, 0, 10, true)
	var before := wire.requests.size()
	wire.completed.emit(before, 200, {"accepted": true, "run_id": client._run["id"], "sequence": 1}, "")
	_check(wire.requests.size() == before + 1, "ACK immediately refreshes despite pre-ACK inflight board")
	client.open_board("classic")
	_check(wire.requests.size() == before + 1, "opening board reuses post-ACK refresh")
	var fresh_board := wire.requests.size()
	var fresh := _empty_board()
	fresh["me"] = {"account_id": "account-a", "rank": 1, "nickname": "Player", "avatar": 0, "completed": 0, "score": 10}
	wire.completed.emit(fresh_board, 200, fresh, "")
	wire.completed.emit(stale_board, 200, _empty_board(), "")
	_check(client.view()["me"].get("score") == 10 and client.result_view("classic")["rank"] == 1, "late pre-ACK board cannot replace refreshed acknowledged rank")
	_dispose(client)

func _test_result_modes() -> void:
	var client := _new_client()
	client.begin_run("classic", 0, 42, 0)
	_ticket(client)
	client.record_move(0, Vector2i.ZERO, 0, 100, true)
	var source := SaveRepository.defaults()
	source["high_score"] = 200
	source["classic_high_score"] = 100
	client.update_records(source)
	var free: Dictionary = client.result_view("free")
	var classic: Dictionary = client.result_view("classic")
	_check(not free["pending"] and free.get("local_only", false), "other-mode queue cannot mark local-only free score pending")
	_check(classic["pending"] and not classic.get("local_only", true), "current-mode eligible checkpoint is pending, not local-only")
	_check(classic.has("rank") and classic.has("available"), "result view retains existing rank and availability keys")
	source["classic_high_score"] = 200
	client.update_records(source)
	_check(client.result_view("classic").get("local_only", false), "higher offline best remains local-only even with lower eligible checkpoint")
	_dispose(client)

	client = _new_client()
	client.store.data["legacy_done"] = false
	client.store.data["legacy_snapshot"]["classic_high_score"] = 90
	_check(not client.result_view("free")["pending"] and client.result_view("classic")["pending"], "migration pending only applies to modes with importable records")
	_dispose(client)

func _test_corrupt_persistence() -> void:
	var client := _new_client()
	client.begin_run("classic", 0, 42, 0)
	_ticket(client)
	client.record_move(0, Vector2i.ZERO, 0, 10, true)
	client.open_board("classic")
	client._transport.completed.emit(client._transport.requests.size(), 200, _empty_board(), "")
	var valid: Dictionary = client.store.data.duplicate(true)
	var key: String = client._cache_key("classic")
	_dispose(client)
	var variants: Array[Dictionary] = []
	for field in ["entries", "me", "fetched_at", "next_cursor"]:
		var broken := valid.duplicate(true)
		broken["cache"][key][field] = ["corrupt"] if field != "entries" else [7]
		variants.append(broken)
	var broken := valid.duplicate(true)
	broken["cache"][key] = "corrupt"
	variants.append(broken)
	for field in ["id_token", "refresh_token", "expires_at"]:
		broken = valid.duplicate(true)
		broken["session"][field] = {"corrupt": true}
		variants.append(broken)
	for field in ["mode", "score", "sequence", "moves", "ticket"]:
		broken = valid.duplicate(true)
		broken["queue"][0][field] = ["corrupt"]
		variants.append(broken)
	broken = valid.duplicate(true)
	broken["queue"][0]["moves"][0]["x"] = {}
	variants.append(broken)
	broken = valid.duplicate(true)
	broken["queue"][0].erase("mode")
	variants.append(broken)
	broken = valid.duplicate(true)
	broken["local_records"]["free"] = "corrupt"
	variants.append(broken)
	broken = valid.duplicate(true)
	broken["legacy_snapshot"]["adventure_best_scores"] = []
	variants.append(broken)
	for scores in [[], {"0": 10}, {"97": 10}, {"01": 10}, {"1": -1}, {"1": []}]:
		broken = valid.duplicate(true)
		broken["adventure_acknowledged"] = {"ruleset": scores}
		variants.append(broken)
	for field in ["nickname", "avatar"]:
		broken = valid.duplicate(true)
		broken["profile"][field] = {}
		variants.append(broken)
	for field in ["rank", "nickname", "score", "completed", "account_id"]:
		broken = valid.duplicate(true)
		var entry := {"account_id": "a", "nickname": "Player", "rank": 1, "avatar": 0, "score": 10, "completed": 0}
		entry[field] = {}
		broken["cache"][key]["me"] = entry
		variants.append(broken)
	for sequence in [-1, 0, 1.5, 20001]:
		broken = valid.duplicate(true)
		broken["queue"][0]["sequence"] = sequence
		variants.append(broken)
	for field in ["level", "seed", "failures", "completed", "closed", "local_only", "ruleset_id"]:
		broken = valid.duplicate(true)
		broken["queue"][0][field] = {}
		variants.append(broken)
	broken = valid.duplicate(true)
	broken["queue"][0]["moves"] = []
	variants.append(broken)
	broken = valid.duplicate(true)
	broken["queue"].append(broken["queue"][0].duplicate(true))
	variants.append(broken)
	for index in range(variants.size()):
		var serialized := JSON.stringify(variants[index])
		var file := FileAccess.open(STORE_PATH, FileAccess.WRITE)
		file.store_string(serialized)
		file.close()
		client = load("res://scripts/persistence/leaderboard_client.gd").new()
		root.add_child(client)
		client.configure(STORE_PATH, SaveRepository.defaults(), TestTransport.new(), "https://leaderboard.invalid", "key")
		_check(client.store.read_failed, "nested corruption rejected, case %d" % index)
		# Only exercise consumers once validation rejected unsafe data; avoids masking assertions with engine errors on the red run.
		if client.store.read_failed:
			client.open_board("classic")
			client.view()
			client.result_view("classic")
			client.update_profile("SafeName", 1)
			client.update_records(SaveRepository.defaults())
			_check(not client.available() and client._transport.requests.is_empty(), "corrupt persistence disables network safely")
		_check(FileAccess.get_file_as_string(STORE_PATH) == serialized, "corrupt file preserved byte-for-byte, case %d" % index)
		_dispose(client)
	var file := FileAccess.open(STORE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(valid))
	file.close()
	var store: RefCounted = load("res://scripts/persistence/leaderboard_store.gd").new()
	store.initialize(STORE_PATH, SaveRepository.defaults())
	_check(not store.read_failed and store.data["queue"].size() == 1 and store.data["cache"].has(key), "valid nested replay, session and cache survive JSON reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE_PATH))

func _test_transport() -> void:
	var transport: Node = load("res://scripts/persistence/leaderboard_transport.gd").new()
	root.add_child(transport)
	var received: Array = []
	transport.completed.connect(func(id: int, status: int, body: Dictionary, error: String): received.append([id, status, body, error]))
	var id: int = transport.send("http://leaderboard.invalid", HTTPClient.METHOD_GET, PackedStringArray(), "")
	_check(received.is_empty(), "transport errors are deferred until client can register request")
	await process_frame
	_check(received == [[id, 0, {}, "invalid_endpoint"]], "transport rejects non-HTTPS without network")
	transport.free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
