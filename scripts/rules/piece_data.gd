class_name PieceData
extends RefCounted

var origin: Vector2i
var cells: Array[Vector2i]
var shape_id: String
## Local marked cells travel with the piece until a legal placement commits.
var targets: Dictionary = {}

func _init(_origin: Vector2i = Vector2i.ZERO, local_cells: Array = [], _shape_id: String = "", local_targets: Dictionary = {}) -> void:
	origin = _origin
	shape_id = _shape_id
	cells = []
	for cell in local_cells:
		cells.append(Vector2i(cell))
	targets = local_targets.duplicate(true)

func cell_count() -> int:
	return cells.size()

func duplicate_piece() -> PieceData:
	return PieceData.new(origin, cells.duplicate(), shape_id, targets)

func is_valid_for_config(config: GameRulesConfig) -> bool:
	if config != null:
		var minimum_cells: int = maxi(1, config.min_piece_cells)
		var maximum_cells: int = maxi(minimum_cells, config.max_piece_cells)
		if cells.size() < minimum_cells or cells.size() > maximum_cells:
			return false
	var seen: Dictionary = {}
	for cell in cells:
		if seen.has(cell):
			return false
		seen[cell] = true
	for cell in targets:
		if not cell is Vector2i or not seen.has(cell) or not targets[cell] is String or not ["blue_diamond", "gold_gem", "yellow_star", "red_star"].has(targets[cell]):
			return false
	return not cells.is_empty()
