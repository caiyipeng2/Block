class_name PieceTray
extends Control

signal piece_pressed(index: int, position: Vector2)
var pieces: Array[PieceData] = []
var hit_rects: Array[Rect2] = []
var palette := [Color("#39c979"), Color("#f4b942"), Color("#ec6a5b")]

func set_pieces(value: Array[PieceData]) -> void: pieces = value; queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for i in range(hit_rects.size()):
			if hit_rects[i].has_point(event.position) and i < pieces.size(): piece_pressed.emit(i, event.position); accept_event()

func _draw() -> void:
	hit_rects.clear(); var gap := 18.0; var slot_w := maxf(120.0, (size.x - gap * 2.0) / 3.0)
	for i in range(3):
		var slot := Rect2(i * (slot_w + gap), 8, slot_w, max(90.0, size.y - 16)); hit_rects.append(slot)
		draw_style_box(_box(Color("#132b2b"), Color("#315351"), 16, 2), slot)
		if i >= pieces.size(): continue
		var piece := pieces[i]; var max_cell := Vector2i.ZERO
		for cell in piece.cells: max_cell.x = max(max_cell.x, cell.x); max_cell.y = max(max_cell.y, cell.y)
		var unit: float = min(24.0, (slot.size.x - 24.0) / max(1, max_cell.x + 1), (slot.size.y - 24.0) / max(1, max_cell.y + 1))
		var offset := slot.position + (slot.size - Vector2(max_cell.x + 1, max_cell.y + 1) * unit) * 0.5
		for cell in piece.cells:
			var rect := Rect2(offset + Vector2(cell.x, cell.y) * unit + Vector2(2, 2), Vector2(unit - 4, unit - 4)); draw_style_box(_box(palette[i], Color("#ffffff", 0.16), 6, 1), rect)

func _box(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color = fill; box.border_color = border; box.set_border_width_all(width); box.set_corner_radius_all(radius); return box
