extends RefCounted

## Authored occupancy masks. Dots are playable negative space, not cells to be
## filled automatically; the masks never contain an initially full line.
const TEMPLATES := [
	{"id": "wings", "name": "双翼", "rows": ["........", ".#....#.", "##.##.##", "##.##.##", ".######.", "..####..", "........", "........"]},
	{"id": "heart", "name": "心形", "rows": ["........", ".##..##.", "###..###", ".######.", "..####..", "...##...", "........", "........"]},
	{"id": "ring", "name": "星环", "rows": ["........", "..####..", ".##..##.", ".#....#.", ".#....#.", ".##..##.", "..####..", "........"]},
	{"id": "steps", "name": "阶梯", "rows": ["........", ".....##.", "....###.", "...####.", "..#####.", ".######.", "........", "........"]},
	{"id": "butterfly", "name": "斜蝶", "rows": ["........", ".##.....", ".###..#.", "..#####.", ".#####..", ".#..###.", ".....##.", "........"]},
]

static func create(level_id: int, board_size: int, palette_count: int, template_id: String = "wings", mirror: bool = false) -> Dictionary:
	var template: Dictionary = {}
	for candidate: Dictionary in TEMPLATES:
		if str(candidate["id"]) == template_id:
			template = candidate
			break
	if template.is_empty():
		return {"error": "unknown_collection_template", "initial_cells": []}
	var rows: Array = template["rows"]
	var cells: Array[Dictionary] = []
	var seen: Dictionary = {}
	for y in range(rows.size()):
		var row := str(rows[y])
		for x in range(row.length()):
			if row.substr(x, 1) != "#":
				continue
			var mapped_x := clampi(floori(float(x) * float(board_size) / 8.0), 0, board_size - 1)
			var mapped_y := clampi(floori(float(y) * float(board_size) / 8.0), 0, board_size - 1)
			if mirror:
				mapped_x = board_size - 1 - mapped_x
			var position := Vector2i(mapped_x, mapped_y)
			if seen.has(position):
				continue
			seen[position] = true
			var color := posmod(floori(float(x) / 2.0) + floori(float(y) / 2.0) + level_id, maxi(1, palette_count))
			cells.append({"x": mapped_x, "y": mapped_y, "color": color})
	return {"template_id": template["id"], "template_name": template["name"], "initial_cells": cells}
