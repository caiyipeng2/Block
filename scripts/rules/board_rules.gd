class_name BoardRules
extends RefCounted

var size: int
var _cells: Array[Array]

func _init(board_size: int = 8) -> void:
	size = board_size
	_cells = []
	for y in range(size):
		var row: Array[int] = []
		row.resize(size)
		row.fill(-1)
		_cells.append(row)

func get_cell(x: int, y: int) -> int:
	if not _in_bounds(Vector2i(x, y)):
		return -1
	return _cells[y][x]

func set_cell(x: int, y: int, color_id: int) -> void:
	if _in_bounds(Vector2i(x, y)):
		_cells[y][x] = color_id

func can_place(piece: PieceData, origin: Vector2i) -> bool:
	if piece == null or piece.cells.is_empty():
		return false
	var seen := {}
	for local_cell in piece.cells:
		var target := origin + local_cell
		if not _in_bounds(target) or seen.has(target) or get_cell(target.x, target.y) != -1:
			return false
		seen[target] = true
	return true

func place(piece: PieceData, origin: Vector2i, color_id: int = 0) -> void:
	if not can_place(piece, origin):
		return
	for local_cell in piece.cells:
		var target := origin + local_cell
		_cells[target.y][target.x] = color_id

func get_legal_origins(piece: PieceData) -> Array[Vector2i]:
	var origins: Array[Vector2i] = []
	if piece == null or piece.cells.is_empty():
		return origins
	var minimum: Vector2i = piece.cells[0]
	var maximum: Vector2i = piece.cells[0]
	for cell in piece.cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	for y in range(-minimum.y, size - maximum.y):
		for x in range(-minimum.x, size - maximum.x):
			var origin := Vector2i(x, y)
			if can_place(piece, origin):
				origins.append(origin)
	return origins

func clear_full_lines() -> Dictionary:
	var full_rows: Array[int] = []
	var full_columns: Array[int] = []
	for y in range(size):
		var full := true
		for x in range(size):
			if _cells[y][x] == -1:
				full = false
				break
		if full:
			full_rows.append(y)
	for x in range(size):
		var full := true
		for y in range(size):
			if _cells[y][x] == -1:
				full = false
				break
		if full:
			full_columns.append(x)
	var cleared: Array[Vector2i] = []
	var seen := {}
	for y in full_rows:
		for x in range(size):
			var cell := Vector2i(x, y)
			seen[cell] = true
	for x in full_columns:
		for y in range(size):
			var cell := Vector2i(x, y)
			seen[cell] = true
	for cell in seen.keys():
		var coordinate: Vector2i = cell
		cleared.append(coordinate)
		_cells[coordinate.y][coordinate.x] = -1
	return {"cells": cleared, "rows": full_rows.size(), "columns": full_columns.size()}

func duplicate_board() -> BoardRules:
	var copy := BoardRules.new(size)
	for y in range(size):
		for x in range(size):
			copy._cells[y][x] = _cells[y][x]
	return copy

func fill_cell_row(y: int, color_id: int = 0) -> void:
	for x in range(size):
		set_cell(x, y, color_id)

func fill_cell_column(x: int, color_id: int = 0) -> void:
	for y in range(size):
		set_cell(x, y, color_id)

func fill_all(color_id: int = 0) -> void:
	for y in range(size):
		fill_cell_row(y, color_id)

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < size and cell.y >= 0 and cell.y < size
