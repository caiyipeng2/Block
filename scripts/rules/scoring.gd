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

func register_move(cleared_line: bool) -> void:
	if cleared_line:
		combo += 1
	else:
		combo = 0

func apply_clear(cleared_cell_count: int, line_count: int) -> int:
	register_move(line_count > 0)
	var gained := score_clear(cleared_cell_count, line_count)
	score += gained
	return gained
