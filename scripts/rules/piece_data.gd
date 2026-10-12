class_name PieceData
extends RefCounted

var origin: Vector2i
var cells: Array[Vector2i]
var shape_id: String

func _init(_origin: Vector2i = Vector2i.ZERO, local_cells: Array = [], _shape_id: String = "") -> void:
	origin = _origin
	shape_id = _shape_id
	cells = []
	for cell in local_cells:
		cells.append(Vector2i(cell))

func cell_count() -> int:
	return cells.size()

func duplicate_piece() -> PieceData:
	return PieceData.new(origin, cells.duplicate(), shape_id)

func is_valid_for_config(config: GameRulesConfig) -> bool:
	if config != null:
		var minimum_cells: int = maxi(3, config.min_piece_cells)
		var maximum_cells: int = mini(5, config.max_piece_cells)
		if cells.size() < minimum_cells or cells.size() > maximum_cells:
			return false
	var seen: Dictionary = {}
	for cell in cells:
		if seen.has(cell):
			return false
		seen[cell] = true
	return not cells.is_empty()
