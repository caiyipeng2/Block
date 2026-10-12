class_name GameRulesConfig
extends Resource

@export_range(1, 32, 1) var board_size: int = 8
@export_range(1, 8, 1) var tray_count: int = 3
@export_range(3, 5, 1) var min_piece_cells: int = 3
@export_range(3, 5, 1) var max_piece_cells: int = 5
@export_range(0, 1000, 1) var base_points_per_cell: int = 10
@export_range(0.0, 5.0, 0.1) var multiline_bonus_step: float = 0.5
@export_range(0, 1000, 1) var generation_attempts: int = 100
@export var shape_pool: Array = []

@export var palette: PackedColorArray = PackedColorArray([
	Color("#ef476f"),
	Color("#06d6a0"),
	Color("#118ab2"),
	Color("#ffd166"),
	Color("#8338ec")
])
@export var background_color: Color = Color("#fdf2f8")
@export var board_color: Color = Color("#ffffff")
@export var empty_cell_color: Color = Color("#fce7f3")
@export var primary_color: Color = Color("#ec4899")
@export var secondary_color: Color = Color("#8b5cf6")
@export var text_color: Color = Color("#0f172a")

@export var placement_duration: float = 0.12
@export var clear_duration: float = 0.22
@export var rebound_duration: float = 0.20

func _init() -> void:
	# Keep directly instantiated configs equivalent to the shipped resource.
	if shape_pool.is_empty():
		shape_pool = _default_shape_definitions()

func _default_shape_definitions() -> Array:
	return [
		_shape("line3", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]),
		_shape("step3", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]),
		_shape("square4", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]),
		_shape("tee4", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)]),
		_shape("corner5", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)])
	]

func _shape(identifier: String, local_cells: Array) -> ShapeDefinition:
	var definition := ShapeDefinition.new()
	definition.shape_id = identifier
	definition.cells.assign(local_cells)
	return definition

