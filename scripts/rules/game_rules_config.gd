class_name GameRulesConfig
extends Resource

@export_range(1, 32, 1) var board_size: int = 8
@export_range(1, 8, 1) var tray_count: int = 3
@export_range(1, 9, 1) var min_piece_cells: int = 3
@export_range(1, 9, 1) var max_piece_cells: int = 5
## Default modes break on the first miss; collection rules use two setup moves.
@export_range(0, 5, 1) var combo_miss_tolerance: int = 0
@export_range(0, 1000, 1) var base_points_per_cell: int = 10
@export_range(0.0, 5.0, 0.1) var multiline_bonus_step: float = 0.5
@export_range(0, 1000, 1) var generation_attempts: int = 100
@export var shape_pool: Array = []

@export var palette: PackedColorArray = PackedColorArray([
	Color("#ff8b26"),
	Color("#a85ce8"),
	Color("#4477f3"),
	Color("#53d63d"),
	Color("#ffd14d"),
	Color("#29c4e8")
])
@export var background_color: Color = Color("#38558f")
@export var board_color: Color = Color("#182443")
@export var empty_cell_color: Color = Color("#202b49")
@export var primary_color: Color = Color("#ffc94a")
@export var secondary_color: Color = Color("#4477f3")
@export var text_color: Color = Color("#edf7ff")

@export var placement_duration: float = 0.12
@export var clear_duration: float = 0.32
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

