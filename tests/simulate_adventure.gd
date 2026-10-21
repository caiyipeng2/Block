extends SceneTree

## Headless Monte Carlo harness for adventure levels. It reuses the production
## ModeCatalog/GameState path, so quota pacing, retry assistance and tray
## certification all match the game; only the player policy is simulated.
##
## Example:
##   godot --headless --path . --script res://tests/simulate_adventure.gd -- \
##     --levels=1-12 --runs=20 --agents=random,greedy --output=user://sim.json

const ModeCatalog = preload("res://scripts/modes/mode_catalog.gd")
const LevelTable = preload("res://scripts/modes/adventure_level_table.gd")
const MAX_MOVES := 600
const NEAR_WIN_REMAINING := 2
const NEAR_WIN_SCORE_RATIO := 0.9

var _levels: Array[int] = []
var _runs := 20
var _agents: Array[String] = ["random", "greedy", "casual"]
var _output_path := "user://adventure_sim_report.json"
var _seed_base := 90210
var _max_moves := MAX_MOVES
var _seed_mode := "level"
var _casual_mistake := 0.25
var _fatigue_base := 0.05
var _fatigue_slope := 3.0
var _fatigue_power := 2.0
var _verbose_runs := false

func _initialize() -> void:
	_parse_args()
	var started := Time.get_ticks_msec()
	var base := GameRulesConfig.new()
	var report := {
		"generated_at": Time.get_datetime_string_from_system(true),
		"config_path": LevelTable.PATH,
		"config_md5": FileAccess.get_md5(LevelTable.PATH),
		"runs_per_level": _runs,
		"agents": _agents,
		"seed_base": _seed_base,
		"seed_mode": _seed_mode,
		"casual_mistake": _casual_mistake,
		"fatigue_base": _fatigue_base,
		"fatigue_slope": _fatigue_slope,
		"fatigue_power": _fatigue_power,
		"near_win_rule": {
			"collect_remaining_at_most": "max(2, ceil(20% of quota))",
			"score_ratio_at_least": NEAR_WIN_SCORE_RATIO,
			"fuuu": "0 when no failures; otherwise failed_runs / failed_runs_that_reached_near_win",
		},
		"levels": [],
	}
	print("SIM config_md5=%s levels=%d runs=%d agents=%s" % [report["config_md5"], _levels.size(), _runs, ",".join(_agents)])
	for level_id in _levels:
		var level_report := _simulate_level(level_id, base)
		report["levels"].append(level_report)
		for entry: Dictionary in level_report["agents"]:
			print("LEVEL %d %s win=%.1f%% near=%.1f%% fuuu=%.2f moves=%.1f rem=%.1f ms=%.0f" % [
				level_id, entry["agent"], float(entry["pass_rate"]) * 100.0,
				float(entry["near_win_rate"]) * 100.0, float(entry["fuuu"]),
				float(entry["avg_moves"]), float(entry["avg_remaining"]), float(entry["avg_ms"]),
			])
	report["elapsed_ms"] = Time.get_ticks_msec() - started
	_write_report(report)
	print("SIM DONE elapsed_ms=%d output=%s" % [report["elapsed_ms"], _output_path])
	quit(0)

func _parse_args() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if text.begins_with("--levels="):
			_levels = _parse_levels(text.trim_prefix("--levels="))
		elif text.begins_with("--runs="):
			_runs = maxi(1, int(text.trim_prefix("--runs=")))
		elif text.begins_with("--agents="):
			_agents.clear()
			for agent in text.trim_prefix("--agents=").split(",", false):
				if agent in ["random", "greedy", "casual"]:
					_agents.append(agent)
			if _agents.is_empty():
				_agents = ["random", "greedy", "casual"]
		elif text.begins_with("--output="):
			_output_path = text.trim_prefix("--output=")
		elif text.begins_with("--seed-base="):
			_seed_base = int(text.trim_prefix("--seed-base="))
		elif text.begins_with("--seed-mode="):
			var mode := text.trim_prefix("--seed-mode=")
			if mode in ["level", "vary"]:
				_seed_mode = mode
		elif text.begins_with("--max-moves="):
			_max_moves = maxi(1, int(text.trim_prefix("--max-moves=")))
		elif text.begins_with("--mistake="):
			_casual_mistake = clampf(float(text.trim_prefix("--mistake=")), 0.0, 1.0)
		elif text.begins_with("--fatigue-base="):
			_fatigue_base = clampf(float(text.trim_prefix("--fatigue-base=")), 0.0, 1.0)
		elif text.begins_with("--fatigue-slope="):
			_fatigue_slope = maxf(0.0, float(text.trim_prefix("--fatigue-slope=")))
		elif text.begins_with("--fatigue-power="):
			_fatigue_power = maxf(1.0, float(text.trim_prefix("--fatigue-power=")))
		elif text == "--verbose-runs":
			_verbose_runs = true
	if _levels.is_empty():
		for level_id in range(1, LevelTable.LEVEL_COUNT + 1):
			_levels.append(level_id)

func _parse_levels(text: String) -> Array[int]:
	var result: Array[int] = []
	for part in text.split(",", false):
		var token := str(part).strip_edges()
		if token.contains("-"):
			var bounds := token.split("-", false)
			if bounds.size() == 2:
				var first := clampi(int(bounds[0]), 1, LevelTable.LEVEL_COUNT)
				var last := clampi(int(bounds[1]), 1, LevelTable.LEVEL_COUNT)
				for level_id in range(mini(first, last), maxi(first, last) + 1):
					if not result.has(level_id):
						result.append(level_id)
		elif int(token) > 0:
			var level_id := clampi(int(token), 1, LevelTable.LEVEL_COUNT)
			if not result.has(level_id):
				result.append(level_id)
	result.sort()
	return result

func _simulate_level(level_id: int, base: GameRulesConfig) -> Dictionary:
	var setup := ModeCatalog.level_setup(level_id, LevelTable.LEVEL_COUNT, base)
	var row := ModeCatalog.level_config(level_id)
	var agents_report: Array[Dictionary] = []
	for agent_index in range(_agents.size()):
		var agent := _agents[agent_index]
		var stats := {
			"agent": agent, "runs": 0, "wins": 0, "timeouts": 0,
			"near_win_runs": 0, "near_win_failures": 0,
			"moves_total": 0, "clears_total": 0, "placed_total": 0,
			"score_total": 0, "remaining_total": 0, "ms_total": 0,
			"final_near_lines_total": 0, "fallback_rounds_total": 0,
			"dead_refill_total": 0, "stuck_mid_tray_total": 0,
			"slips_total": 0, "plan_failures_total": 0,
		}
		for run_index in range(_runs):
			var policy_seed := _seed_base + level_id * 100003 + agent_index * 7919 + run_index
			var supply_seed := int(setup.get("level_seed", policy_seed))
			if _seed_mode == "vary":
				supply_seed = policy_seed
			var result := _simulate_run(setup, base, agent, supply_seed, policy_seed)
			stats["runs"] += 1
			if result["outcome"] == "complete":
				stats["wins"] += 1
			elif result["outcome"] == "timeout":
				stats["timeouts"] += 1
			if bool(result["near_win"]):
				stats["near_win_runs"] += 1
				if result["outcome"] != "complete":
					stats["near_win_failures"] += 1
			stats["moves_total"] += int(result["moves"])
			stats["clears_total"] += int(result["clears"])
			stats["placed_total"] += int(result["placed"])
			stats["score_total"] += int(result["score"])
			stats["remaining_total"] += int(result["remaining"])
			stats["ms_total"] += int(result["ms"])
			stats["final_near_lines_total"] += int(result["final_near_lines"])
			stats["fallback_rounds_total"] += int(result["fallback_rounds"])
			stats["dead_refill_total"] += 1 if bool(result["dead_refill"]) else 0
			stats["stuck_mid_tray_total"] += 1 if bool(result["stuck_mid_tray"]) else 0
			stats["slips_total"] += int(result["slips"])
			stats["plan_failures_total"] += int(result["plan_failures"])
			if _verbose_runs:
				print("  run %d %s outcome=%s moves=%d rem=%d near=%s slips=%d plan_failures=%d" % [
					run_index, agent, result["outcome"], int(result["moves"]), int(result["remaining"]),
					str(result["near_win"]), int(result["slips"]), int(result["plan_failures"]),
				])
		var runs := maxi(1, int(stats["runs"]))
		var failures := maxi(0, int(stats["runs"]) - int(stats["wins"]))
		var near_failures := int(stats["near_win_failures"])
		agents_report.append({
			"agent": agent,
			"runs": stats["runs"], "wins": stats["wins"], "timeouts": stats["timeouts"],
			"pass_rate": float(stats["wins"]) / float(runs),
			"near_win_rate": float(stats["near_win_runs"]) / float(runs),
			"near_win_failure_rate": float(near_failures) / float(maxi(1, failures)),
			"fuuu": 0.0 if failures == 0 else (float(failures) / float(near_failures) if near_failures > 0 else 9999.0),
			"fuuu_applicable": failures > 0,
			"avg_moves": float(stats["moves_total"]) / float(runs),
			"avg_clears": float(stats["clears_total"]) / float(runs),
			"avg_placed_cells": float(stats["placed_total"]) / float(runs),
			"avg_score": float(stats["score_total"]) / float(runs),
			"avg_remaining": float(stats["remaining_total"]) / float(runs),
			"avg_final_near_lines": float(stats["final_near_lines_total"]) / float(runs),
			"avg_fallback_rounds": float(stats["fallback_rounds_total"]) / float(runs),
			"dead_refill_rate": float(stats["dead_refill_total"]) / float(runs),
			"stuck_mid_tray_rate": float(stats["stuck_mid_tray_total"]) / float(runs),
			"avg_slips": float(stats["slips_total"]) / float(runs),
			"avg_plan_failures": float(stats["plan_failures_total"]) / float(runs),
			"avg_ms": float(stats["ms_total"]) / float(runs),
		})
	return {
		"level_id": level_id,
		"objective_type": setup.get("objective_type", "invalid"),
		"target_score": int(setup.get("target_score", 0)),
		"target_total": int(setup.get("target_total", 0)),
		"difficulty": float(row.get("difficulty", 0.0)),
		"difficulty_ratio": float(setup.get("difficulty_ratio", 0.0)),
		"template_id": str(setup.get("template_id", "random")),
		"initial_occupied": int(setup.get("initial_diagnostics", {}).get("initial_occupied", 0)),
		"initial_markers": int(setup.get("initial_diagnostics", {}).get("initial_markers", 0)),
		"initial_near_lines": int(setup.get("initial_diagnostics", {}).get("near_win_lines", 0)),
		"shape_profile": str(setup.get("shape_profile", "mixed")),
		"extra_blocks": int(setup.get("extra_blocks", 0)),
		"near_win_lines": int(setup.get("near_win_lines", 0)),
		"randomness": float(setup.get("randomness", 50.0)),
		"opening_certified": bool(setup.get("initial_diagnostics", {}).get("solution_certified", false)),
		"agents": agents_report,
	}

func _simulate_run(setup: Dictionary, base: GameRulesConfig, agent: String, supply_seed: int, policy_seed: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var state := GameState.new(supply_seed, base.board_size, base, setup)
	var rng := RandomNumberGenerator.new()
	rng.seed = policy_seed ^ 0x51A7
	var moves := 0
	var fallback_rounds := 0
	var dead_refill := false
	var stuck_mid_tray := false
	var best_remaining := int(state.target_total) if state.objective_type == "collect" else 0
	var best_score := 0
	var outcome := "running"
	var plan: Array[Dictionary] = []
	var plan_round := -1
	var plan_locked := false
	var slips := 0
	var plan_failures := 0
	var plan_failure_round := -1
	while moves < _max_moves:
		if state.status != GameState.Status.PLAYING:
			break
		var chosen := {}
		if agent == "random":
			chosen = _choose_move(state, agent, rng)
		elif plan_locked and plan_round == state.round_index:
			# A casual slip is not instantly corrected: the rest of the tray is
			# played by feel, like a player who has lost the intended order.
			chosen = _choose_move(state, agent, rng)
		else:
			plan_locked = false
			plan = _valid_plan(state, plan, plan_round)
			if plan.is_empty():
				plan_round = state.round_index
				plan = _plan_tray(state, rng, agent == "casual")
				if plan.is_empty() and plan_failure_round != state.round_index:
					plan_failures += 1
					plan_failure_round = state.round_index
				if agent == "casual" and not plan.is_empty() and rng.randf() < _casual_mistake_chance(state, slips):
					plan.clear()
					plan_locked = true
					slips += 1
					chosen = _choose_move(state, "casual", rng)
				elif not plan.is_empty():
					chosen = {"piece": plan[0]["piece"], "origin": plan[0]["origin"]}
			if chosen.is_empty():
				if not plan.is_empty():
					chosen = {"piece": plan[0]["piece"], "origin": plan[0]["origin"]}
				else:
					chosen = _choose_move(state, agent, rng)
			if not chosen.is_empty() and not plan.is_empty() and chosen.get("piece") == plan[0]["piece"]:
				plan.remove_at(0)
		if chosen.is_empty():
			stuck_mid_tray = true
			break
		var piece_index := _piece_index(state, chosen["piece"])
		if piece_index < 0:
			plan.clear()
			break
		var placed := state.place_piece(piece_index, chosen["origin"], 0)
		moves += 1
		if not bool(placed.get("ok", false)):
			break
		if state.status == GameState.Status.PLAYING and bool(placed.get("round_refilled", false)):
			if bool(state.generation_diagnostics.get("fallback_used", false)):
				fallback_rounds += 1
		if state.status == GameState.Status.GAME_OVER:
			dead_refill = state.remaining_pieces.is_empty()
			stuck_mid_tray = not dead_refill
		if state.objective_type == "collect":
			best_remaining = mini(best_remaining, state.target_total - state.target_collected)
		best_score = maxi(best_score, state.scoring.score)
	if state.status == GameState.Status.LEVEL_COMPLETE:
		outcome = "complete"
	elif state.status == GameState.Status.GAME_OVER:
		outcome = "game_over"
	else:
		outcome = "timeout"
	var remaining := maxi(0, state.target_total - state.target_collected) if state.objective_type == "collect" else maxi(0, state.target_score - state.scoring.score)
	var near_win := best_remaining <= _near_win_threshold(state.target_total) if state.objective_type == "collect" else float(best_score) >= float(maxi(1, state.target_score)) * NEAR_WIN_SCORE_RATIO
	return {
		"outcome": outcome,
		"near_win": near_win,
		"moves": moves,
		"rounds": state.round_index,
		"fallback_rounds": fallback_rounds,
		"dead_refill": dead_refill,
		"stuck_mid_tray": stuck_mid_tray,
		"clears": state.total_cleared_lines,
		"placed": state.total_placed_cells,
		"score": state.scoring.score if state.scoring != null else 0,
		"remaining": remaining,
		"slips": slips,
		"plan_failures": plan_failures,
		"final_near_lines": _count_near_lines(state.board),
		"ms": Time.get_ticks_msec() - started,
	}

func _near_win_threshold(target_total: int) -> int:
	return maxi(NEAR_WIN_REMAINING, ceili(float(target_total) * 0.2))

func _count_near_lines(board: BoardRules) -> int:
	var count := 0
	for y in range(board.size):
		var filled := 0
		for x in range(board.size):
			if board.get_cell(x, y) >= 0:
				filled += 1
		if filled == board.size - 1:
			count += 1
	for x in range(board.size):
		var filled := 0
		for y in range(board.size):
			if board.get_cell(x, y) >= 0:
				filled += 1
		if filled == board.size - 1:
			count += 1
	return count

func _casual_mistake_chance(state: GameState, slips: int) -> float:
	# Simple players drift under fatigue: slips are more likely once the quota
	# is nearly complete, and an earlier slip makes the next one likelier.
	var progress := 0.0
	if state.objective_type == "collect" and state.target_total > 0:
		progress = clampf(float(state.target_collected) / float(state.target_total), 0.0, 1.0)
	elif state.target_score > 0:
		progress = clampf(float(state.scoring.score) / float(state.target_score), 0.0, 1.0)
	return clampf(_casual_mistake * (_fatigue_base + _fatigue_slope * pow(progress, _fatigue_power)) + 0.12 * float(slips), 0.0, 1.0)

func _piece_index(state: GameState, piece: PieceData) -> int:
	for index in range(state.remaining_pieces.size()):
		if state.remaining_pieces[index] == piece:
			return index
	return -1

func _valid_plan(state: GameState, plan: Array[Dictionary], plan_round: int) -> Array[Dictionary]:
	if plan.is_empty() or plan_round != state.round_index:
		return []
	for step: Dictionary in plan:
		if _piece_index(state, step["piece"]) < 0 or not state.board.can_place(step["piece"], step["origin"]):
			return []
	return plan
func _plan_tray(state: GameState, rng: RandomNumberGenerator, randomize: bool) -> Array[Dictionary]:
	var pieces: Array[PieceData] = []
	for piece: PieceData in state.remaining_pieces:
		pieces.append(piece)
	var path: Array[Dictionary] = []
	var budget := {"left": 64}
	var solved := _search_plan(state.board.duplicate_board(), pieces, path, state.target_cells, rng, randomize, budget)
	if solved:
		return path
	return []

func _search_plan(board: BoardRules, pieces: Array[PieceData], path: Array[Dictionary], targets: Dictionary, rng: RandomNumberGenerator, randomize: bool, budget: Dictionary) -> bool:
	if pieces.is_empty():
		return true
	if int(budget["left"]) <= 0:
		return false
	budget["left"] = int(budget["left"]) - 1
	var size := board.size
	var row_counts: Array[int] = []
	var column_counts: Array[int] = []
	row_counts.resize(size)
	column_counts.resize(size)
	row_counts.fill(0)
	column_counts.fill(0)
	for y in range(size):
		for x in range(size):
			if board.get_cell(x, y) >= 0:
				row_counts[y] += 1
				column_counts[x] += 1
	var candidates: Array[Dictionary] = []
	for index in range(pieces.size()):
		var piece := pieces[index]
		for origin: Vector2i in board.get_legal_origins(piece):
			var added_rows := row_counts.duplicate()
			var added_columns := column_counts.duplicate()
			for cell: Vector2i in piece.cells:
				added_rows[origin.y + cell.y] += 1
				added_columns[origin.x + cell.x] += 1
			var clears := 0
			for coordinate in range(size):
				if added_rows[coordinate] >= size:
					clears += 1
				if added_columns[coordinate] >= size:
					clears += 1
			var hits := 0
			for local_cell: Vector2i in piece.targets:
				var cell := origin + local_cell
				if added_rows[cell.y] >= size or added_columns[cell.x] >= size:
					hits += 1
			var rank := float(clears) * 4000.0 + float(hits) * 1500.0 + float(piece.cells.size()) * 3.0
			if randomize:
				rank += rng.randf() * 900.0
			candidates.append({"index": index, "piece": piece, "origin": origin, "rank": rank})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rank"]) > float(b["rank"]))
	for candidate_index in range(mini(6, candidates.size())):
		var candidate: Dictionary = candidates[candidate_index]
		var next := board.duplicate_board()
		next.place(candidate["piece"], candidate["origin"], 0)
		next.clear_full_lines()
		var rest: Array[PieceData] = []
		for index in range(pieces.size()):
			if index != int(candidate["index"]):
				rest.append(pieces[index])
		path.append({"piece": candidate["piece"], "origin": candidate["origin"]})
		if _search_plan(next, rest, path, targets, rng, randomize, budget):
			return true
		path.pop_back()
		if int(budget["left"]) <= 0:
			return false
	return false

func _choose_move(state: GameState, agent: String, rng: RandomNumberGenerator) -> Dictionary:
	var candidates := _legal_candidates(state)
	if candidates.is_empty():
		return {}
	if agent == "random":
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var row_counts: Array[int] = []
	var column_counts: Array[int] = []
	row_counts.resize(state.board.size)
	column_counts.resize(state.board.size)
	row_counts.fill(0)
	column_counts.fill(0)
	var filled_before := 0
	for y in range(state.board.size):
		for x in range(state.board.size):
			if state.board.get_cell(x, y) >= 0:
				row_counts[y] += 1
				column_counts[x] += 1
				filled_before += 1
	var ranked: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var metric := _evaluate_move(state, candidate["piece"], candidate["origin"], row_counts, column_counts, filled_before)
		candidate["rank"] = metric["rank"]
		candidate["clears"] = metric["clears"]
		candidate["target_hits"] = metric["target_hits"]
		ranked.append(candidate)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rank"]) > float(b["rank"]))
	if agent == "greedy":
		var top := _first_safe_candidate(state, ranked, mini(12, ranked.size()))
		return top if not top.is_empty() else ranked[0]
	# Casual keeps a short list of plausible human choices and prefers the top
	# one most of the time, but avoids moves that empty the tray and also leave
	# no placeable piece at all.
	var safe_ranked: Array[Dictionary] = []
	for candidate: Dictionary in ranked:
		if _is_candidate_safe(state, candidate):
			safe_ranked.append(candidate)
		if safe_ranked.size() >= 4:
			break
	if not safe_ranked.is_empty():
		if rng.randf() < 0.35:
			return safe_ranked[rng.randi_range(0, safe_ranked.size() - 1)]
		return safe_ranked[0]
	var window := mini(4, ranked.size())
	var pick := 0
	if rng.randf() < 0.35:
		pick = rng.randi_range(0, window - 1)
	return ranked[pick]

func _first_safe_candidate(state: GameState, ranked: Array[Dictionary], limit: int) -> Dictionary:
	for index in range(mini(limit, ranked.size())):
		if _is_candidate_safe(state, ranked[index]):
			return ranked[index]
	return {}

func _is_candidate_safe(state: GameState, candidate: Dictionary) -> bool:
	# The game only ends when no remaining piece fits at all; a temporarily
	# blocked piece can be reopened by clearing with another one first.
	var board_after := state.board.duplicate_board()
	board_after.place(candidate["piece"], candidate["origin"], 0)
	board_after.clear_full_lines()
	for piece_index in range(state.remaining_pieces.size()):
		if piece_index == int(candidate["piece_index"]):
			continue
		if not board_after.get_legal_origins(state.remaining_pieces[piece_index]).is_empty():
			return true
	return false

func _legal_candidates(state: GameState) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for piece_index in range(state.remaining_pieces.size()):
		var piece: PieceData = state.remaining_pieces[piece_index]
		for origin: Vector2i in state.board.get_legal_origins(piece):
			candidates.append({"piece_index": piece_index, "piece": piece, "origin": origin})
	return candidates

func _evaluate_move(state: GameState, piece: PieceData, origin: Vector2i, row_counts: Array[int], column_counts: Array[int], filled_before: int) -> Dictionary:
	var size := state.board.size
	var next_rows := row_counts.duplicate()
	var next_columns := column_counts.duplicate()
	for local_cell: Vector2i in piece.cells:
		var cell := origin + local_cell
		next_rows[cell.y] += 1
		next_columns[cell.x] += 1
	var full_rows: Array[int] = []
	var full_columns: Array[int] = []
	for coordinate in range(size):
		if next_rows[coordinate] >= size:
			full_rows.append(coordinate)
		if next_columns[coordinate] >= size:
			full_columns.append(coordinate)
	var cleared: Dictionary = {}
	for y in full_rows:
		for x in range(size):
			cleared[Vector2i(x, y)] = true
	for x in full_columns:
		for y in range(size):
			cleared[Vector2i(x, y)] = true
	var target_hits := 0
	for cell: Vector2i in cleared:
		if state.target_cells.has(cell):
			var kind := str(state.target_cells[cell])
			if int(state.target_remaining_counts.get(kind, 0)) > 0:
				target_hits += 1
	for local_cell: Vector2i in piece.targets:
		var world := origin + local_cell
		if cleared.has(world):
			var kind := str(piece.targets[local_cell])
			if int(state.target_remaining_counts.get(kind, 0)) > 0:
				target_hits += 1
	# The post-clear counts are derivable without copying the board: full rows
	# and columns empty out, and every other line loses the crossing clears.
	var near_lines := 0
	var pressure := 0
	for y in range(size):
		var count: int = int(next_rows[y]) - full_columns.size()
		if int(next_rows[y]) >= size:
			count = 0
		pressure += count * count
		if count == size - 1:
			near_lines += 1
	for x in range(size):
		var count: int = int(next_columns[x]) - full_rows.size()
		if int(next_columns[x]) >= size:
			count = 0
		pressure += count * count
		if count == size - 1:
			near_lines += 1
	var occupied := filled_before + piece.cells.size() - cleared.size()
	var rank := float(cleared.size()) * 100000.0 + float(target_hits) * 20000.0
	rank += float(pressure) * 12.0 + float(64 - occupied) * 3.0 + float(near_lines) * 40.0
	return {"rank": rank, "clears": cleared.size(), "target_hits": target_hits}

func _write_report(report: Dictionary) -> void:
	var path := _output_path
	if path.begins_with("user://") or path.begins_with("res://"):
		pass
	elif path.contains("/") or path.contains("\\"):
		var directory := path.get_base_dir()
		if not directory.is_empty():
			DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write simulation report to " + path)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
