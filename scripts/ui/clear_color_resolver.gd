extends RefCounted

## Resolves presentation colors from the board before its full lines are removed.
## Placement orders describe surviving cells, not the first appearance of a palette color.
## The board and placement_orders are read-only throughout this calculation.
static func resolve(board: BoardRules, placement_orders: Dictionary) -> Dictionary:
	var rows: Array[int] = []
	var columns: Array[int] = []
	var cell_colors: Dictionary = {}
	var row_colors: Dictionary = {}
	var column_colors: Dictionary = {}
	var result := {
		"cell_colors": cell_colors,
		"row_colors": row_colors,
		"column_colors": column_colors,
		"rows": rows,
		"columns": columns,
	}
	if board == null or board.size <= 0:
		return result
	for y in range(board.size):
		var full := true
		for x in range(board.size):
			if board.get_cell(x, y) < 0:
				full = false
				break
		if full:
			rows.append(y)
	for x in range(board.size):
		var full := true
		for y in range(board.size):
			if board.get_cell(x, y) < 0:
				full = false
				break
		if full:
			columns.append(x)

	# Every full row intersects every full column, so simultaneous rows/columns
	# form one connected group. Count each intersection only once in its vote.
	if not rows.is_empty() and not columns.is_empty():
		var union_cells: Array[Vector2i] = []
		var seen: Dictionary = {}
		for y in rows:
			for x in range(board.size):
				var cell := Vector2i(x, y)
				seen[cell] = true
				union_cells.append(cell)
		for x in columns:
			for y in range(board.size):
				var cell := Vector2i(x, y)
				if not seen.has(cell):
					seen[cell] = true
					union_cells.append(cell)
		var group_color := _dominant_color(board, placement_orders, union_cells)
		for cell in union_cells:
			cell_colors[cell] = group_color
		for y in rows:
			row_colors[y] = group_color
		for x in columns:
			column_colors[x] = group_color
		return result

	for y in rows:
		var line: Array[Vector2i] = []
		for x in range(board.size):
			line.append(Vector2i(x, y))
		var color_id := _dominant_color(board, placement_orders, line)
		row_colors[y] = color_id
		for cell in line:
			cell_colors[cell] = color_id
	for x in columns:
		var line: Array[Vector2i] = []
		for y in range(board.size):
			line.append(Vector2i(x, y))
		var color_id := _dominant_color(board, placement_orders, line)
		column_colors[x] = color_id
		for cell in line:
			cell_colors[cell] = color_id
	return result

static func _dominant_color(board: BoardRules, placement_orders: Dictionary, cells: Array[Vector2i]) -> int:
	var counts: Dictionary = {}
	var earliest_orders: Dictionary = {}
	for cell in cells:
		var color_id := board.get_cell(cell.x, cell.y)
		if color_id < 0:
			continue
		var order := int(placement_orders.get(cell, 0))
		counts[color_id] = int(counts.get(color_id, 0)) + 1
		if not earliest_orders.has(color_id) or order < int(earliest_orders[color_id]):
			earliest_orders[color_id] = order
	var winner := -1
	var winner_count := -1
	var winner_order := 0
	for raw_color_id in counts:
		var color_id := int(raw_color_id)
		var count := int(counts[color_id])
		var order := int(earliest_orders[color_id])
		if count > winner_count or (count == winner_count and (order < winner_order or (order == winner_order and color_id < winner))):
			winner = color_id
			winner_count = count
			winner_order = order
	return winner
