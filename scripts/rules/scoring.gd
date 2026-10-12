class_name Scoring
extends RefCounted

var score: int = 0
var combo: int = 0
var base_points_per_cell: int = 10
var multiline_bonus_step: float = 0.5

func _init(config: GameRulesConfig = null) -> void:
	if config != null:
		base_points_per_cell = config.base_points_per_cell
		multiline_bonus_step = config.multiline_bonus_step

func score_clear(cleared_cell_count: int, line_count: int) -> int:
	if cleared_cell_count <= 0 or line_count <= 0:
		return 0
	var multiplier := 1.0 + multiline_bonus_step * float(line_count - 1)
	return int(round(float(cleared_cell_count * base_points_per_cell) * multiplier))

func score_placement(placed_cell_count: int) -> int:
	## Points awarded for placing cells, before line clearing.
	if placed_cell_count <= 0:
		return 0
	return placed_cell_count * base_points_per_cell

func register_move(cleared_line: bool) -> void:
	if cleared_line:
		combo += 1
	else:
		combo = 0

func apply_move(placed_cell_count: int, cleared_cell_count: int, line_count: int) -> Dictionary:
	## Apply one legal move and expose placement/clear points separately.
	## Every legal placement earns points for its cells. Clearing earns an
	## additional amount, with the multiline multiplier applied only to that
	## clear portion. A legal move without a clear resets combo to zero.
	register_move(line_count > 0)
	var placement_points := score_placement(placed_cell_count)
	var clear_points := score_clear(cleared_cell_count, line_count)
	var gained := placement_points + clear_points
	score += gained
	return {
		"placement_points": placement_points,
		"clear_points": clear_points,
		"gained": gained,
		"score": score,
		"combo": combo,
	}

func apply_clear(cleared_cell_count: int, line_count: int, placed_cell_count: int = 0) -> int:
	## Legacy wrapper retained for callers using the old clear-only API.
	return int(apply_move(placed_cell_count, cleared_cell_count, line_count)["gained"])
