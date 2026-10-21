class_name GameState
extends RefCounted

const TutorialTrayBuilder = preload("res://scripts/rules/tutorial_tray_builder.gd")
const ModeCatalog = preload("res://scripts/modes/mode_catalog.gd")
const CollectionTraySupplier = preload("res://scripts/rules/collection_tray_supplier.gd")
const OpeningTraySupplier = preload("res://scripts/rules/opening_tray_supplier.gd")
const OPENING_ASSIST_SCORE_LIMIT := 1500
const TARGET_KINDS := ["blue_diamond", "gold_gem", "yellow_star", "red_star"]

enum Status { PLAYING, GAME_OVER, LEVEL_COMPLETE }

var rules_config: GameRulesConfig
var board: BoardRules
var remaining_pieces: Array[PieceData] = []
var scoring: Scoring
var generator: RoundGenerator
var status: Status = Status.PLAYING
var round_index: int = 0
var total_cleared_lines: int = 0
var total_placed_cells: int = 0
var total_cleared_cells: int = 0
var total_moves: int = 0
var generation_diagnostics: Dictionary = {}
## Breakdown of the most recent legal placement. Invalid moves do not overwrite it.
var last_placement_points: int = 0
var last_clear_points: int = 0
var last_clear_lines: int = 0
var mode := "free"
var level_id := 0
var target_score := 0
## Physical markers may outnumber the remaining collection quota.
var objective_type := "score"
var target_cells: Dictionary = {}
var target_total := 0
var target_collected := 0
var target_counts: Dictionary = {}
var target_collected_counts: Dictionary = {}
var target_remaining_counts: Dictionary = {}
var difficulty_label := ""
var retry_assist_strength := 0.0
var _tutorial_builder: TutorialTrayBuilder
var _collection_targets_valid := true
var _collection_supplier: CollectionTraySupplier
var _opening_supplier: OpeningTraySupplier

func _init(initial_seed: int = 0, board_size: int = 8, config: GameRulesConfig = null, setup: Dictionary = {}) -> void:
	mode = str(setup.get("mode", "free"))
	level_id = maxi(0, int(setup.get("level_id", 0)))
	objective_type = "collect" if mode == "adventure" and str(setup.get("objective_type", "score")) == "collect" else "score"
	rules_config = config if config != null else GameRulesConfig.new()
	if config == null:
		rules_config.board_size = board_size
	if objective_type == "collect":
		rules_config = ModeCatalog.collection_rules(rules_config)
	board = BoardRules.new(rules_config.board_size)
	scoring = Scoring.new(rules_config)
	generator = RoundGenerator.new(initial_seed, rules_config)
	target_score = maxi(0, int(setup.get("target_score", 0))) if mode == "adventure" and objective_type == "score" else 0
	difficulty_label = str(setup.get("difficulty_label", ""))
	if not bool(setup.get("config_valid", true)) or bool(setup.get("initial_setup_invalid", false)):
		generation_diagnostics = setup.get("initial_diagnostics", {"reason": "invalid_level_configuration", "solution_certified": false}).duplicate(true)
		status = Status.GAME_OVER
		return
	generator.candidate_samples = clampi(int(setup.get("candidate_samples", 1)), 1, 12) if mode == "adventure" else 1
	generator.solution_count_cap = clampi(int(setup.get("solution_count_cap", 8)), 2, 32)
	if objective_type == "collect":
		var difficulty := clampf(float(setup.get("difficulty_ratio", ModeCatalog.collection_difficulty(level_id))), 0.0, 1.0)
		retry_assist_strength = clampf(float(setup.get("retry_assist_strength", 0.0)), 0.0, 1.0)
		_collection_supplier = CollectionTraySupplier.new(
			rules_config, initial_seed, difficulty, retry_assist_strength,
			str(setup.get("shape_profile", "mixed")), float(setup.get("randomness", 50.0)),
			int(setup.get("marker_rounds", CollectionTraySupplier.TARGET_ROUNDS))
		)
	for entry: Dictionary in setup.get("initial_cells", []):
		board.set_cell(int(entry["x"]), int(entry["y"]), int(entry["color"]))
	if objective_type == "collect":
		_read_collection_targets(setup)
		if bool(setup.get("initial_setup_invalid", false)):
			_collection_targets_valid = false
	if _uses_tutorial_supplier():
		_tutorial_builder = TutorialTrayBuilder.new(rules_config)
		_fill_tutorial_tray(rules_config.tray_count)
	elif _accept_initial_tray(setup):
		generation_diagnostics = setup.get("initial_diagnostics", {}).duplicate(true)
		if _uses_opening_supplier() and bool(setup.get("opening_assist_initial", false)):
			_fill_regular_tray()
		elif mode == "adventure" and objective_type != "collect" and generator.candidate_samples > 1:
			remaining_pieces = generator.generate_solvable_round(board, remaining_pieces)
			generation_diagnostics["difficulty_selection"] = generator.last_diagnostics.duplicate(true)
	elif objective_type == "collect":
		if _collection_targets_valid and target_total > 0:
			_fill_collection_tray()
		else:
			generation_diagnostics = setup.get("initial_diagnostics", {}).duplicate(true)
			if generation_diagnostics.is_empty():
				generation_diagnostics = {"reason": "invalid_collection_objectives", "solution_certified": false}
	else:
		_fill_regular_tray()
	if remaining_pieces.is_empty():
		status = Status.GAME_OVER

func _accept_initial_tray(setup: Dictionary) -> bool:
	if objective_type == "collect" and not _collection_targets_valid:
		return false
	var pieces: Array[PieceData] = []
	for piece in setup.get("initial_pieces", []):
		if not piece is PieceData or not piece.is_valid_for_config(rules_config):
			return false
		pieces.append(piece.duplicate_piece())
	if pieces.size() != rules_config.tray_count:
		return false
	var path: Array = setup.get("initial_solution", [])
	if path.size() != pieces.size():
		return false
	var check := board.duplicate_board()
	var seen := {}
	for step: Dictionary in path:
		var index := int(step.get("piece_index", -1))
		var origin: Vector2i = step.get("origin", Vector2i(-99, -99))
		if index < 0 or index >= pieces.size() or seen.has(index) or not check.can_place(pieces[index], origin):
			return false
		seen[index] = true
		check.place(pieces[index], origin, 0)
		check.clear_full_lines()
	remaining_pieces = pieces
	generator.last_solution.assign(path)
	return true

func has_legal_move_for_any_remaining_piece() -> bool:
	for piece in remaining_pieces:
		if not board.get_legal_origins(piece).is_empty():
			return true
	return false

func place_piece(piece_index: int, origin: Vector2i, color_id: int = 0) -> Dictionary:
	if status != Status.PLAYING or piece_index < 0 or piece_index >= remaining_pieces.size():
		return _invalid_move_result("unavailable")
	var piece := remaining_pieces[piece_index]
	if not board.can_place(piece, origin):
		return _invalid_move_result("illegal")
	var placed_cells: Array[Vector2i] = []
	for local_cell in piece.cells:
		placed_cells.append(origin + local_cell)
	var placed_targets: Dictionary = {}
	if objective_type == "collect":
		for local_cell: Vector2i in piece.targets:
			var world_cell := origin + local_cell
			var kind := str(piece.targets[local_cell])
			if piece.cells.has(local_cell) and TARGET_KINDS.has(kind):
				target_cells[world_cell] = kind
				placed_targets[world_cell] = kind
	board.place(piece, origin, color_id)
	var clear_result := board.clear_full_lines()
	var collected_targets: Array[Vector2i] = []
	var collected_target_events: Array[Dictionary] = []
	for cell in clear_result["cells"]:
		if target_cells.has(cell):
			var kind := str(target_cells[cell])
			target_cells.erase(cell)
			collected_targets.append(cell)
			var counted := int(target_remaining_counts.get(kind, 0)) > 0
			collected_target_events.append({"cell": cell, "kind": kind, "counted": counted})
			if counted:
				target_collected_counts[kind] = int(target_collected_counts[kind]) + 1
				target_remaining_counts[kind] = int(target_remaining_counts[kind]) - 1
				target_collected += 1
	var cleared_lines: int = clear_result["rows"] + clear_result["columns"]
	var scoring_result := scoring.apply_move(placed_cells.size(), clear_result["cells"].size(), cleared_lines)
	var placement_points: int = scoring_result["placement_points"]
	var clear_points: int = scoring_result["clear_points"]
	var gained: int = scoring_result["gained"]
	last_placement_points = placement_points
	last_clear_points = clear_points
	last_clear_lines = cleared_lines
	total_cleared_lines += cleared_lines
	total_placed_cells += placed_cells.size()
	total_cleared_cells += clear_result["cells"].size()
	total_moves += 1
	remaining_pieces.remove_at(piece_index)
	var round_refilled := false
	var tray_adapted := false
	if _objective_complete():
		status = Status.LEVEL_COMPLETE
	elif remaining_pieces.is_empty():
		round_index += 1
		if _uses_tutorial_supplier():
			_fill_tutorial_tray(rules_config.tray_count)
		elif objective_type == "collect":
			_fill_collection_tray()
		else:
			_fill_regular_tray()
		round_refilled = not remaining_pieces.is_empty()
		if remaining_pieces.is_empty():
			status = Status.GAME_OVER
	elif _uses_tutorial_supplier():
		# After a player's different choice, certify the whole remaining tray,
		# not just one currently legal move. Only replace it when that path died.
		var remaining_solution := generator.find_solution(board, remaining_pieces)
		if remaining_solution.size() != remaining_pieces.size():
			_fill_tutorial_tray(remaining_pieces.size(), remaining_pieces)
			tray_adapted = true
			if remaining_pieces.is_empty():
				status = Status.GAME_OVER
		else:
			generator.last_solution.assign(remaining_solution)
	elif not has_legal_move_for_any_remaining_piece():
		status = Status.GAME_OVER
	return {
		"ok": true,
		"clear": clear_result,
		"placement_points": placement_points,
		"clear_points": clear_points,
		"last_placement_points": last_placement_points,
		"last_clear_points": last_clear_points,
		"last_clear_lines": last_clear_lines,
		"gained": gained,
		"score": scoring_result["score"],
		"combo": scoring_result["combo"],
		"round_index": round_index,
		"total_cleared_lines": total_cleared_lines,
		"total_placed_cells": total_placed_cells,
		"total_cleared_cells": total_cleared_cells,
		"total_moves": total_moves,
		"placed_cells": placed_cells,
		"placed_color": color_id,
		"placed_targets": placed_targets,
		"round_refilled": round_refilled,
		"tray_adapted": tray_adapted,
		"certified_round_supplied": false,
		"tutorial": _uses_tutorial_supplier(),
		"generation_diagnostics": generation_diagnostics.duplicate(true),
		"level_complete": status == Status.LEVEL_COMPLETE,
		"collected_targets": collected_targets,
		"collected_target_events": collected_target_events,
		"objective_type": objective_type,
		"target_total": target_total,
		"target_collected": target_collected,
		"target_remaining": target_total - target_collected,
		"marked_cells_remaining": target_cells.size(),
		"target_counts": target_counts.duplicate(),
		"target_collected_counts": target_collected_counts.duplicate(),
		"target_remaining_counts": target_remaining_counts.duplicate(),
		"difficulty_label": difficulty_label,
		"status": status
	}

func _invalid_move_result(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"placement_points": 0,
		"clear_points": 0,
		"last_placement_points": last_placement_points,
		"last_clear_points": last_clear_points,
		"last_clear_lines": last_clear_lines,
		"gained": 0,
		"tray_adapted": false,
		"certified_round_supplied": false,
		"tutorial": _uses_tutorial_supplier(),
		"score": scoring.score if scoring != null else 0,
		"combo": scoring.combo if scoring != null else 0,
		"collected_targets": [],
		"collected_target_events": [],
		"objective_type": objective_type,
		"target_total": target_total,
		"target_collected": target_collected,
		"target_remaining": target_total - target_collected,
		"marked_cells_remaining": target_cells.size(),
		"target_counts": target_counts.duplicate(),
		"target_collected_counts": target_collected_counts.duplicate(),
		"target_remaining_counts": target_remaining_counts.duplicate(),
		"difficulty_label": difficulty_label,
	}

func _read_collection_targets(setup: Dictionary) -> void:
	var supplied = setup.get("target_cells", [])
	if not supplied is Array and not supplied is Dictionary:
		_collection_targets_valid = false
		return
	var physical_counts: Dictionary = {}
	for entry in supplied:
		if typeof(entry) != TYPE_VECTOR2I:
			_collection_targets_valid = false
			continue
		var cell: Vector2i = entry
		var kind := str(supplied[entry]) if supplied is Dictionary else "red_star"
		if not TARGET_KINDS.has(kind) or board.get_cell(cell.x, cell.y) < 0:
			_collection_targets_valid = false
			continue
		if not target_cells.has(cell):
			target_cells[cell] = kind
			physical_counts[kind] = int(physical_counts.get(kind, 0)) + 1
	var declared = setup.get("target_counts", physical_counts)
	if not declared is Dictionary:
		_collection_targets_valid = false
		return
	for kind in declared:
		if not TARGET_KINDS.has(str(kind)) or int(declared[kind]) < 0:
			_collection_targets_valid = false
			continue
		target_counts[str(kind)] = int(declared[kind])
	for kind in physical_counts:
		if not target_counts.has(kind):
			_collection_targets_valid = false
	for kind in target_counts:
		target_total += int(target_counts[kind])
		target_collected_counts[kind] = 0
		target_remaining_counts[kind] = int(target_counts[kind])
	if setup.has("target_total") and int(setup["target_total"]) != target_total:
		_collection_targets_valid = false
	if target_total <= 0:
		_collection_targets_valid = false

func _fill_collection_tray() -> void:
	var supplied := _collection_supplier.build(board, target_remaining_counts, generator, target_cells)
	remaining_pieces.assign(supplied["pieces"])
	generator.last_solution.assign(supplied["solution"])
	generation_diagnostics = supplied["diagnostics"].duplicate(true)
	generation_diagnostics["seed"] = generator.seed
	generation_diagnostics["round"] = round_index
	generator.last_diagnostics = generation_diagnostics.duplicate(true)

func _uses_opening_supplier() -> bool:
	return mode in ["free", "classic"] and scoring.score < OPENING_ASSIST_SCORE_LIMIT

func _fill_regular_tray() -> void:
	if not _uses_opening_supplier():
		remaining_pieces = generator.generate_solvable_round(board)
		generation_diagnostics = generator.last_diagnostics.duplicate(true)
		generation_diagnostics["round"] = round_index
		generator.last_diagnostics = generation_diagnostics.duplicate(true)
		return
	if _opening_supplier == null:
		_opening_supplier = OpeningTraySupplier.new(rules_config, generator.seed)
	var supplied := _opening_supplier.build(board, generator, OPENING_ASSIST_SCORE_LIMIT)
	remaining_pieces.assign(supplied["pieces"])
	generator.last_solution.assign(supplied["solution"].duplicate(true))
	generation_diagnostics = supplied["diagnostics"].duplicate(true)
	generation_diagnostics["seed"] = generator.seed
	generation_diagnostics["round"] = round_index
	generator.last_diagnostics = generation_diagnostics.duplicate(true)

func _uses_tutorial_supplier() -> bool:
	return mode == "adventure" and objective_type == "score" and (level_id == 1 or level_id == 2)

func _fill_tutorial_tray(count: int, preferred_pieces: Array[PieceData] = []) -> void:
	var supplied := _tutorial_builder.build(board, count, preferred_pieces)
	remaining_pieces.assign(supplied["pieces"])
	generator.last_solution.assign(supplied["solution"])
	generation_diagnostics = supplied["diagnostics"].duplicate(true)
	generation_diagnostics["seed"] = generator.seed
	generation_diagnostics["round"] = round_index
	generator.last_diagnostics = generation_diagnostics.duplicate(true)

func _objective_complete() -> bool:
	if mode != "adventure":
		return false
	if objective_type == "collect":
		return target_total > 0 and target_collected >= target_total
	return target_score > 0 and scoring.score >= target_score

func is_game_over() -> bool:
	return status == Status.GAME_OVER

func is_level_complete() -> bool:
	return status == Status.LEVEL_COMPLETE

