class_name BoardView
extends Control

var game_state: GameState
var preview_piece: PieceData
var preview_origin := Vector2i(-99, -99)
var preview_color := 0
var board_rect := Rect2()
var cell_size := 40.0
var palette := [Color("#39c979"), Color("#f4b942"), Color("#ec6a5b"), Color("#55a7e8"), Color("#b07cf2")]

func setup(state: GameState) -> void:
	game_state = state
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()

func _draw() -> void:
	var side := min(size.x, size.y)
	cell_size = floor((side - 24.0) / 8.0)
	var total := cell_size * 8.0
	board_rect = Rect2((size - Vector2(total, total)) * 0.5, Vector2(total, total))
	for y in range(8):
		for x in range(8):
			var rect := Rect2(board_rect.position + Vector2(x, y) * cell_size + Vector2(2, 2), Vector2(cell_size - 4, cell_size - 4))
			var occupied := game_state != null and game_state.board.get_cell(x, y) >= 0
			var color := palette[game_state.board.get_cell(x, y) % palette.size()] if occupied else (Color("#1d3c3b") if (x + y) % 2 == 0 else Color("#193534"))
			draw_style_box(_box(color, Color("#2a5550"), 7, 1), rect)
	if preview_piece != null and preview_origin.x >= 0:
		var legal := game_state.board.can_place(preview_piece, preview_origin)
		var color := palette[preview_color % palette.size()] if legal else Color("#db5d5d")
		for local_cell in preview_piece.cells:
			var target := preview_origin + local_cell
			if target.x < 0 or target.y < 0 or target.x >= 8 or target.y >= 8: continue
			var rect := Rect2(board_rect.position + Vector2(target.x, target.y) * cell_size + Vector2(3, 3), Vector2(cell_size - 6, cell_size - 6))
			draw_style_box(_box(Color(color, 0.72), Color("#ffffff", 0.45), 7, 2), rect)

func screen_to_origin(point: Vector2, piece: PieceData) -> Vector2i:
	var local := (point - board_rect.position) / cell_size
	var anchor := piece.cells[0] if not piece.cells.is_empty() else Vector2i.ZERO
	return Vector2i(round(local.x), round(local.y)) - anchor

func set_preview(piece: PieceData, origin: Vector2i, color_id: int) -> void:
	preview_piece = piece; preview_origin = origin; preview_color = color_id; queue_redraw()

func clear_preview() -> void:
	preview_piece = null; preview_origin = Vector2i(-99, -99); queue_redraw()

func _box(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color = fill; box.border_color = border; box.set_border_width_all(width); box.set_corner_radius_all(radius); return box
