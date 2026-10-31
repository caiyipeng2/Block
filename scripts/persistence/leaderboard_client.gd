extends Node

signal changed
const Store := preload("res://scripts/persistence/leaderboard_store.gd")
const Transport := preload("res://scripts/persistence/leaderboard_transport.gd")
const Bots := preload("res://scripts/persistence/leaderboard_bots.gd")
const CACHE_SECONDS := 60
const MAX_REPLAY_MOVES := 20000
const BOARD_LIMIT := 100
var store: RefCounted
var selected_mode := "adventure"
var _transport: Node
var _base_url := ""
var _api_key := ""
var _ruleset := ""
var _requests: Dictionary = {}
var _states: Dictionary = {}
var _generations: Dictionary = {}
var _run: Dictionary = {}
var _auth_busy := false
var _sync_busy := false
var _opened := false
var _retry_at := 0
var _retry_delay := 5
var _notice := ""
var _neighbors: Array = []

func configure(path: String, local_save: Dictionary, transport: Node = null, base_url: String = "", api_key: String = "") -> void:
	store = Store.new()
	store.initialize(path, local_save)
	selected_mode = store.data["last_mode"]
	_base_url = base_url.trim_suffix("/")
	_api_key = api_key
	_ruleset = str(ProjectSettings.get_setting("leaderboard/ruleset_id", "block-0.9.5-v1"))
	_transport = transport if transport != null else Transport.new()
	add_child(_transport)
	_transport.completed.connect(_on_response)
	for mode: String in Store.MODES:
		_states[mode] = "offline" if store.data["cache"].has(_cache_key(mode)) else "unconfigured"
		_generations[mode] = 0
	_seed_offline_bot_caches()

func available() -> bool:
	return _base_url.begins_with("https://") and not _api_key.is_empty() and not store.read_failed

func _process(_delta: float) -> void:
	if _refresh_bot_cache(selected_mode):
		changed.emit()
	if available() and _retry_at > 0 and Time.get_ticks_msec() >= _retry_at:
		_retry_at = 0
		# Board reads and writes are independent: opening a board must not
		# consume the only wake-up for a failed profile/import/checkpoint.
		connect_service()
		if _opened and _has_session():
			open_board(selected_mode, true)
	elif available() and _retry_at == 0 and not store.data["session"].is_empty() and not _has_session():
		connect_service()

func connect_service() -> void:
	if not available() or _auth_busy or _retry_at > 0:
		return
	if not _ensure_persisted():
		return
	if _has_session():
		_sync_next()
		return
	_auth_busy = true
	var session: Dictionary = store.data["session"]
	if not str(session.get("refresh_token", "")).is_empty():
		_send("auth_refresh", "https://securetoken.googleapis.com/v1/token?key=" + _api_key.uri_encode(), HTTPClient.METHOD_POST, {"grant_type": "refresh_token", "refresh_token": session["refresh_token"]}, {}, false)
	else:
		_send("auth", "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + _api_key.uri_encode(), HTTPClient.METHOD_POST, {"returnSecureToken": true}, {}, false)

func open_board(mode: String = "", force: bool = false) -> void:
	if mode in Store.MODES:
		selected_mode = mode
		store.data["last_mode"] = mode
		store.persist()
	_opened = true
	_neighbors.clear()
	_refresh_bot_cache(selected_mode)
	if not available():
		_states[selected_mode] = "unconfigured"
		changed.emit()
		return
	var cached: Dictionary = store.data["cache"].get(_cache_key(selected_mode), {})
	if not force and not cached.is_empty() and Time.get_unix_time_from_system() - float(cached.get("fetched_at", 0)) < CACHE_SECONDS:
		_states[selected_mode] = "empty" if cached["entries"].is_empty() else "ready"
		changed.emit()
		return
	if _has_pending("board", selected_mode):
		return
	_states[selected_mode] = "loading"
	if not _has_session():
		connect_service()
	else:
		_fetch_board(selected_mode)
	changed.emit()

func close_board() -> void:
	_opened = false

func load_more() -> void:
	var current := view()
	if not available() or not _has_session() or str(current["next_cursor"]).is_empty() or current["entries"].size() >= BOARD_LIMIT or _has_pending("board", selected_mode):
		return
	_fetch_board(selected_mode, current["next_cursor"])

func load_neighbors() -> void:
	if not available() or not _has_session() or _has_pending("neighbors", selected_mode):
		return
	_send("neighbors", _base_url + "/v1/leaderboards/" + selected_mode + "/me?ruleset_id=" + _ruleset.uri_encode(), HTTPClient.METHOD_GET, {}, {"mode": selected_mode, "generation": _generations[selected_mode]})

func view() -> Dictionary:
	_refresh_bot_cache(selected_mode)
	var cached: Dictionary = store.data["cache"].get(_cache_key(selected_mode), {})
	var mine: Dictionary = cached.get("me", {})
	var pending := _local_pending(selected_mode)
	return {"mode": selected_mode, "status": _states[selected_mode], "has_cache": not cached.is_empty(), "entries": cached.get("entries", []).duplicate(true), "me": mine.duplicate(true), "updated_at": int(cached.get("updated_at", 0)), "pending": pending, "next_cursor": cached.get("next_cursor", ""), "profile": store.data["profile"].duplicate(), "highest_completed": store.data["local_records"]["adventure"]["completed"], "neighbors": _neighbors.duplicate(true), "notice": _notice}

func _local_pending(mode: String) -> Dictionary:
	var mine: Dictionary = store.data["cache"].get(_cache_key(mode), {}).get("me", {})
	var local: Dictionary = store.data["local_records"][mode]
	var pending := {}
	if int(local["completed"]) > int(mine.get("completed", 0)) or (int(local["completed"]) == int(mine.get("completed", 0)) and int(local["score"]) > int(mine.get("score", 0))):
		pending = local.duplicate()
		pending["eligible"] = not bool(store.data["legacy_done"]) and local == Store.records(store.data["legacy_snapshot"])[mode]
		if mode == "adventure":
			pending["eligible"] = _adventure_eligible(local)
		else:
			for queued: Dictionary in store.data["queue"]:
				if queued.get("mode") == mode and queued.get("ruleset_id") == _ruleset and int(queued.get("score", 0)) >= int(local["score"]):
					pending["eligible"] = true
	return pending

func _adventure_eligible(local: Dictionary) -> bool:
	var scores: Dictionary = store.data["legacy_snapshot"]["adventure_best_scores"].duplicate()
	var acknowledged: Dictionary = store.data["adventure_acknowledged"].get(_ruleset, {})
	for level: String in acknowledged:
		scores[level] = maxi(int(scores.get(level, 0)), int(acknowledged[level]))
	for queued: Dictionary in store.data["queue"]:
		if queued.get("mode") == "adventure" and queued.get("ruleset_id") == _ruleset and queued.get("completed") == true:
			var level := str(int(queued["level"]))
			scores[level] = maxi(int(scores.get(level, 0)), int(queued["score"]))
	var total := 0
	for level in range(1, int(local["completed"]) + 1):
		if not scores.has(str(level)):
			return false
		total = mini(total + int(scores[str(level)]), Store.MAX_SCORE)
	return total >= int(local["score"])

func result_view(mode: String) -> Dictionary:
	var cache: Dictionary = store.data["cache"].get(_cache_key(mode), {})
	var legacy: Dictionary = Store.records(store.data["legacy_snapshot"])[mode]
	var pending: bool = not store.data["legacy_done"] and (int(legacy["score"]) > 0 or int(legacy["completed"]) > 0)
	for queued: Dictionary in store.data["queue"]:
		if queued["mode"] == mode:
			pending = true
	var local := _local_pending(mode)
	return {"rank": int(cache.get("me", {}).get("rank", 0)), "available": available(), "pending": pending, "local_only": not local.is_empty() and not local["eligible"]}

func account_view() -> Dictionary:
	var result: Dictionary = store.data["profile"].duplicate()
	result.merge({"bound": false, "available": false, "sync_status": "", "save_failed": store.save_failed})
	return result

func update_records(local_save: Dictionary) -> void:
	store.update_records(local_save)
	changed.emit()

func update_profile(nickname: String, avatar: int) -> bool:
	if not store.update_profile(nickname, avatar):
		return false
	_sync_next()
	changed.emit()
	return true

func begin_run(mode: String, level: int, seed: int, failures: int) -> void:
	_run = {"id": Store.random_id(), "mode": mode, "level": level, "seed": seed, "failures": failures, "ruleset_id": _ruleset, "sequence": 0, "moves": [], "ticket": "", "local_only": false, "closed": false}
	if available() and _has_session():
		_send("ticket", _base_url + "/v1/runs", HTTPClient.METHOD_POST, {"run_id": _run["id"], "mode": mode, "level": level, "seed": seed, "failures": failures, "ruleset_id": _ruleset}, {"run_id": _run["id"]})
	else:
		_run["local_only"] = true

func record_move(piece_index: int, origin: Vector2i, color: int, score: int, completed: bool) -> void:
	if _run.is_empty() or _run["closed"]:
		return
	if str(_run["ticket"]).is_empty() or _run["moves"].size() >= MAX_REPLAY_MOVES:
		_run["local_only"] = true
	if _run["local_only"]:
		return
	_run["moves"].append({"piece_index": piece_index, "x": origin.x, "y": origin.y, "color": color})
	_run["sequence"] = int(_run["sequence"]) + 1
	if completed or int(_run["sequence"]) % 10 == 0:
		_checkpoint(score, completed)

func finish_run(score: int, completed: bool) -> void:
	if _run.is_empty() or _run["closed"]:
		return
	_checkpoint(score, completed)
	_run["closed"] = true

func _checkpoint(score: int, completed: bool) -> void:
	if _run["local_only"] or str(_run["ticket"]).is_empty() or int(_run["sequence"]) == 0 or (_run["mode"] == "adventure" and not completed):
		return
	var payload := _run.duplicate(true)
	payload["score"] = score
	payload["completed"] = completed
	if not store.enqueue(payload):
		_notice = "成绩暂时无法保存到同步队列"
	_sync_next()
	changed.emit()

func _has_session() -> bool:
	var session: Dictionary = store.data["session"]
	return not store.save_failed and not str(session.get("id_token", "")).is_empty() and float(session.get("expires_at", 0)) > Time.get_unix_time_from_system() + 60.0

func _ensure_persisted() -> bool:
	if store.save_failed and not store.persist():
		_schedule_retry(0, selected_mode)
		changed.emit()
		return false
	return true

func _sync_next() -> void:
	if not available() or _sync_busy or _retry_at > 0:
		return
	if not _has_session():
		connect_service()
		return
	_sync_busy = true
	if not store.data["legacy_done"]:
		_send("legacy", _base_url + "/v1/legacy-import", HTTPClient.METHOD_POST, {"migration_id": store.data["legacy_id"], "device_uid": store.data["device_uid"], "ruleset_id": _ruleset, "snapshot": store.data["legacy_snapshot"], "profile": store.data["profile"]})
	elif store.data["profile_dirty"]:
		_send("profile", _base_url + "/v1/profile", HTTPClient.METHOD_PUT, store.data["profile"], {"profile": store.data["profile"].duplicate()})
	elif not store.data["queue"].is_empty():
		var record: Dictionary = store.data["queue"][0]
		_send("checkpoint", _base_url + "/v1/runs/" + str(record["id"]).uri_encode() + "/checkpoints", HTTPClient.METHOD_POST, record, {"run_id": record["id"], "sequence": record["sequence"], "mode": record["mode"], "level": record["level"], "score": record["score"], "ruleset_id": record["ruleset_id"]})
	else:
		_sync_busy = false

func _fetch_board(mode: String, cursor: String = "") -> void:
	_generations[mode] = int(_generations[mode]) + 1
	var url := _base_url + "/v1/leaderboards/" + mode + "?limit=" + str(BOARD_LIMIT) + "&ruleset_id=" + _ruleset.uri_encode()
	if not cursor.is_empty():
		url += "&cursor=" + cursor.uri_encode()
	_send("board", url, HTTPClient.METHOD_GET, {}, {"mode": mode, "cursor": cursor, "generation": _generations[mode]})

func _send(kind: String, url: String, method: int, payload: Dictionary, context: Dictionary = {}, authorized: bool = true) -> void:
	if not _ensure_persisted():
		if kind in ["auth", "auth_refresh"]:
			_auth_busy = false
		if kind in ["legacy", "checkpoint", "profile"]:
			_sync_busy = false
		return
	var headers := PackedStringArray(["Content-Type: application/json"])
	if authorized:
		headers.append("Authorization: Bearer " + str(store.data["session"].get("id_token", "")))
	var body := "" if method == HTTPClient.METHOD_GET else JSON.stringify(payload)
	if kind == "auth_refresh":
		headers[0] = "Content-Type: application/x-www-form-urlencoded"
		body = "grant_type=refresh_token&refresh_token=" + str(payload["refresh_token"]).uri_encode()
	var id: int = _transport.send(url, method, headers, body)
	_requests[id] = context.merged({"kind": kind})

func _has_pending(kind: String, mode: String) -> bool:
	for context: Dictionary in _requests.values():
		if context["kind"] == kind and context.get("mode") == mode and context.get("generation", _generations[mode]) == _generations[mode]:
			return true
	return false

func _schedule_retry(status: int, mode: String) -> void:
	_retry_at = maxi(_retry_at, Time.get_ticks_msec() + _retry_delay * 1000)
	_retry_delay = mini(_retry_delay * 2, 300)
	_states[mode] = "maintenance" if status == 503 else ("offline" if status == 0 else "error")

func _invalidate_cache(mode: String) -> void:
	# Retain the last acknowledged board for offline display, but do not let
	# pre-ACK reads make it fresh again. Refresh on the next board open.
	_generations[mode] = int(_generations[mode]) + 1
	var cached: Dictionary = store.data["cache"].get(_cache_key(mode), {})
	if not cached.is_empty():
		cached["fetched_at"] = 0
	if mode == selected_mode:
		_neighbors.clear()

func _on_response(id: int, status: int, body: Dictionary, error: String) -> void:
	if not _requests.has(id):
		return
	var context: Dictionary = _requests[id]
	_requests.erase(id)
	var kind: String = context["kind"]
	if kind in ["board", "neighbors"] and context["generation"] != _generations[context["mode"]]:
		return
	if kind in ["auth", "auth_refresh"]:
		_auth_busy = false
	if kind in ["legacy", "checkpoint", "profile"]:
		_sync_busy = false
	if not error.is_empty() or status < 200 or status >= 300:
		if status == 401 and kind not in ["auth", "auth_refresh"]:
			store.data["session"]["expires_at"] = 0
			store.persist()
		if kind == "checkpoint" and status == 422:
			store.acknowledge(context["run_id"], context["sequence"])
			_notice = "这次成绩未计入排行榜"
			_sync_next()
		else:
			_schedule_retry(status, context.get("mode", selected_mode))
		changed.emit()
		return
	# A successful parallel read/ticket is not acknowledgement of failed work.
	# Only the retry wake-up consumes a scheduled deadline.
	var malformed := false
	match kind:
		"auth", "auth_refresh":
			var token: Variant = body.get("idToken" if kind == "auth" else "id_token")
			var refresh: Variant = body.get("refreshToken" if kind == "auth" else "refresh_token")
			var account: Variant = body.get("localId" if kind == "auth" else "user_id")
			var expiry: Variant = body.get("expiresIn" if kind == "auth" else "expires_in", 3600)
			if expiry is String and expiry.is_valid_float():
				expiry = float(expiry)
			if not token is String or token.is_empty() or not refresh is String or refresh.is_empty() or not account is String or account.is_empty() or not _valid_integer(expiry, 61, Store.MAX_SCORE):
				malformed = true
			else:
				store.data["session"] = {"id_token": token, "refresh_token": refresh, "account_id": account, "expires_at": Time.get_unix_time_from_system() + minf(float(expiry), 3600.0)}
				if not store.persist():
					_schedule_retry(0, selected_mode)
					changed.emit()
					return
				_sync_next()
				if _opened and not _has_pending("board", selected_mode):
					_fetch_board(selected_mode)
		"board":
			_accept_board(context, body)
		"neighbors":
			if context["mode"] == selected_mode and context["generation"] == _generations[selected_mode] and _valid_entries(body.get("neighbors"), 5):
				_neighbors = body["neighbors"]
		"ticket":
			if _run.get("id") == context["run_id"] and not _run["local_only"] and not _run["closed"] and body.get("ticket") is String and body.get("run_id") == context["run_id"] and body.get("ruleset_id") == _ruleset:
				_run["ticket"] = body["ticket"]
		"legacy":
			if body.get("migration_id") == store.data["legacy_id"] and body.get("accepted") is bool and body["accepted"]:
				store.data["legacy_done"] = true
				for mode: String in Store.MODES:
					_invalidate_cache(mode)
				store.persist()
				_sync_next()
				if _opened:
					_fetch_board(selected_mode)
			else:
				malformed = true
		"checkpoint":
			if body.get("run_id") == context["run_id"] and _valid_integer(body.get("sequence"), 1, MAX_REPLAY_MOVES) and body["sequence"] == context["sequence"] and body.get("accepted") is bool and body["accepted"]:
				_invalidate_cache(context["mode"])
				if context["mode"] == "adventure":
					var scores: Dictionary = store.data["adventure_acknowledged"].get(context["ruleset_id"], {})
					var level := str(int(context["level"]))
					scores[level] = maxi(int(scores.get(level, 0)), int(context["score"]))
					store.data["adventure_acknowledged"][context["ruleset_id"]] = scores
				store.acknowledge(context["run_id"], context["sequence"])
				_sync_next()
				if _opened and context["mode"] == selected_mode:
					_fetch_board(selected_mode)
			else:
				malformed = true
		"profile":
			if body.get("accepted") is bool and body["accepted"]:
				if store.data["profile"] == context["profile"]:
					store.data["profile_dirty"] = false
					store.persist()
				_sync_next()
			else:
				malformed = true
	if malformed:
		_schedule_retry(200, context.get("mode", selected_mode))
	elif _retry_at == 0:
		_retry_delay = 5
	changed.emit()

func _accept_board(context: Dictionary, body: Dictionary) -> void:
	var mode: String = context["mode"]
	if context["generation"] != _generations[mode]:
		return
	var real_player_count: Variant = body.get("real_player_count", body.get("total_players", body.get("entries", []).size()))
	if not _valid_entries(body.get("entries"), BOARD_LIMIT) or not _valid_integer(real_player_count, 0, Store.MAX_SCORE) or not body.get("me") is Dictionary or (not body["me"].is_empty() and not _valid_entry(body["me"])) or not body.get("next_cursor", "") is String or not _valid_integer(body.get("updated_at"), 0, Store.MAX_SCORE):
		_states[mode] = "error"
		return
	var entries: Array = body["entries"].duplicate(true)
	if not context["cursor"].is_empty():
		var cache: Dictionary = store.data["cache"].get(_cache_key(mode), {})
		if cache.get("next_cursor") != context["cursor"]:
			return
		var previous: Array = []
		for entry: Dictionary in cache.get("entries", []):
			if not bool(entry.get("is_bot", false)):
				previous.append(entry.duplicate(true))
		var ids := {}
		for entry: Dictionary in previous:
			ids[entry["account_id"]] = true
		for entry: Dictionary in entries:
			if not ids.has(entry["account_id"]):
				previous.append(entry)
		entries = previous.slice(0, 100)
		if not _valid_entries(entries, BOARD_LIMIT):
			_states[mode] = "loading"
			_fetch_board(mode)
			return
	var filled: Dictionary = Bots.fill(mode, entries, int(real_player_count), Bots.target_count(), Bots.current_epoch(), body["me"])
	entries = filled["entries"]
	var next_cursor := str(body.get("next_cursor", "")) if int(filled["real_player_count"]) >= BOARD_LIMIT and entries.size() < BOARD_LIMIT else ""
	store.data["cache"][_cache_key(mode)] = {"entries": entries, "me": body["me"], "real_player_count": filled["real_player_count"], "bot_epoch": filled["bot_epoch"], "next_cursor": next_cursor, "updated_at": body["updated_at"], "fetched_at": Time.get_unix_time_from_system()}
	store.persist()
	_states[mode] = "empty" if entries.is_empty() else "ready"

func _refresh_bot_cache(mode: String) -> bool:
	var key := _cache_key(mode)
	if not store.data.get("cache", {}).has(key):
		return false
	var cache: Dictionary = store.data["cache"][key]
	var epoch := Bots.current_epoch()
	var real_entries: Array = []
	var has_bots := false
	for entry: Dictionary in cache.get("entries", []):
		if not bool(entry.get("is_bot", false)):
			real_entries.append(entry.duplicate(true))
		else:
			has_bots = true
	var real_player_count := int(cache.get("real_player_count", real_entries.size()))
	if int(cache.get("bot_epoch", -1)) == epoch and (has_bots or real_player_count >= Bots.target_count() or real_entries.size() >= Bots.target_count()):
		return false
	var filled: Dictionary = Bots.fill(mode, real_entries, int(cache.get("real_player_count", real_entries.size())), Bots.target_count(), epoch, cache.get("me", {}))
	cache["entries"] = filled["entries"]
	cache["bot_epoch"] = filled["bot_epoch"]
	cache["real_player_count"] = filled["real_player_count"]
	store.persist()
	return true

func _seed_offline_bot_caches() -> void:
	# A missing backend must still leave the board useful in a fresh install.
	# These entries are explicitly presentation-only and are replaced by the
	# first valid server response; no local score is assigned a global rank.
	if available():
		return
	var changed_local := false
	for mode: String in Store.MODES:
		var key := _cache_key(mode)
		if store.data["cache"].has(key):
			continue
		var filled: Dictionary = Bots.fill(mode, [], 0, Bots.target_count(), Bots.current_epoch(), {})
		store.data["cache"][key] = {
			"entries": filled["entries"], "me": {}, "real_player_count": 0,
			"bot_epoch": filled["bot_epoch"], "next_cursor": "", "updated_at": 0,
			"fetched_at": 0,
		}
		changed_local = true
	if changed_local:
		store.persist()

func _cache_key(mode: String) -> String:
	return _ruleset + ":" + mode

static func _valid_entries(value: Variant, limit: int) -> bool:
	return Store.valid_entries(value, limit)

static func _valid_entry(entry: Dictionary) -> bool:
	return Store.valid_entry(entry)

static func _valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return Store.valid_integer(value, minimum, maximum)
