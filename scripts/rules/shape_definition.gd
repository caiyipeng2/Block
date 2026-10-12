class_name ShapeDefinition
extends Resource

## Stable identifier for editor configuration and diagnostics.
@export var shape_id: String = ""
## Local cell coordinates. Rotation is deliberately not applied by MVP rules.
@export var cells: Array[Vector2i] = []

func to_piece() -> PieceData:
	return PieceData.new(Vector2i.ZERO, cells, shape_id)

