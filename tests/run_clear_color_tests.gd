extends SceneTree

const Resolver = preload("res://scripts/ui/clear_color_resolver.gd")
const Preview = preload("res://scripts/ui/clear_preview.gd")

var _failures: int = 0

# Maintained as regression coverage only. Run only after explicit authorization;
# normal delivery uses lightweight script parsing and user runtime acceptance.
func _initialize() -> void:
	_test_majority()
	_test_tie_uses_placement_order()
	_test_oldest_surviving_cell_of_color()
	_test_parallel_lines_stay_independent()
	_test_crossing_group_deduplicates_cells()
	_test_multiple_crossings_form_one_group()
	_test_fallbacks_and_empty_board()
	_test_spectrum_band_strength_tiers()
	if _failures == 0:
		print("CLEAR COLOR TESTS PASSED")
	quit(0 if _failures == 0 else 1)

func _test_majority() -> void:
	var board := BoardRules.new(4)
	_set_row(board, 0, [8, 2, 2, 2])
	var orders := {Vector2i(0, 0): 1, Vector2i(1, 0): 4, Vector2i(2, 0): 5, Vector2i(3, 0): 6}
	var result: Dictionary = Resolver.resolve(board, orders)
	_assert_equal(result["row_colors"].get(0, -1), 2, "数量优先于先放置")
	_assert_equal(result["cell_colors"].size(), 4, "整行统一颜色")
	for x in range(4):
		_assert_equal(result["cell_colors"].get(Vector2i(x, 0), -1), 2, "多数颜色覆盖同行每格")

func _test_tie_uses_placement_order() -> void:
	var board := BoardRules.new(4)
	_set_row(board, 1, [1, 1, 9, 9])
	var orders := {Vector2i(0, 1): 5, Vector2i(1, 1): 4, Vector2i(2, 1): 1, Vector2i(3, 1): 3}
	var result: Dictionary = Resolver.resolve(board, orders)
	_assert_equal(result["row_colors"].get(1, -1), 9, "平票按落子序号而非坐标或颜色编号")

func _test_oldest_surviving_cell_of_color() -> void:
	var board := BoardRules.new(4)
	_set_row(board, 2, [7, 7, 1, 1])
	var orders := {Vector2i(0, 2): 1, Vector2i(1, 2): 9, Vector2i(2, 2): 3, Vector2i(3, 2): 4}
	var result: Dictionary = Resolver.resolve(board, orders)
	_assert_equal(result["row_colors"].get(2, -1), 7, "后放同色不能覆盖仍在行内的早期序号")

func _test_parallel_lines_stay_independent() -> void:
	var board := BoardRules.new(4)
	_set_row(board, 0, [4, 4, 4, 1])
	_set_row(board, 2, [2, 2, 3, 2])
	var result: Dictionary = Resolver.resolve(board, {})
	_assert_equal(result["rows"], [0, 2], "平行满行列表")
	_assert_equal(result["columns"], [], "平行满行不生成满列")
	_assert_equal(result["row_colors"].get(0, -1), 4, "第一满行保留自己的多数颜色")
	_assert_equal(result["row_colors"].get(2, -1), 2, "第二满行独立选色")
	var columns_board := BoardRules.new(4)
	for y in range(4):
		columns_board.set_cell(1, y, 5 if y < 3 else 0)
		columns_board.set_cell(3, y, 6 if y > 0 else 0)
	var columns_result: Dictionary = Resolver.resolve(columns_board, {})
	_assert_equal(columns_result["column_colors"].get(1, -1), 5, "第一满列独立选色")
	_assert_equal(columns_result["column_colors"].get(3, -1), 6, "第二满列独立选色")

func _test_crossing_group_deduplicates_cells() -> void:
	var board := BoardRules.new(4)
	_set_row(board, 0, [2, 2, 1, 1])
	board.set_cell(0, 1, 2)
	board.set_cell(0, 2, 1)
	board.set_cell(0, 3, 1)
	var orders := {Vector2i(0, 0): 1, Vector2i(1, 0): 2, Vector2i(0, 1): 3}
	for cell in [Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 2), Vector2i(0, 3)]:
		orders[cell] = 5
	var before_board := board.duplicate_board()
	var before_orders := orders.duplicate(true)
	var result: Dictionary = Resolver.resolve(board, orders)
	# Color 1 has four unique cells; color 2 has three. Double-counting the
	# intersection would incorrectly tie and select the earlier color 2.
	_assert_equal(result["cell_colors"].size(), 7, "交叉组去重共有七格")
	_assert_equal(result["row_colors"].get(0, -1), 1, "交叉组按去重后的多数颜色")
	_assert_equal(result["column_colors"].get(0, -1), 1, "交叉行列使用同一主色")
	for cell in result["cell_colors"]:
		_assert_equal(result["cell_colors"][cell], 1, "交叉组内每格统一颜色")
	_assert_equal(orders, before_orders, "解析不会改写落子序号")
	for y in range(board.size):
		for x in range(board.size):
			_assert_equal(board.get_cell(x, y), before_board.get_cell(x, y), "解析不会改写棋盘")

func _test_multiple_crossings_form_one_group() -> void:
	var board := BoardRules.new(4)
	_set_row(board, 0, [2, 2, 2, 2])
	_set_row(board, 1, [3, 3, 3, 3])
	for y in range(2, 4):
		board.set_cell(0, y, 3)
		board.set_cell(1, y, 3)
	var result: Dictionary = Resolver.resolve(board, {})
	_assert_equal(result["rows"], [0, 1], "交叉组包含多条完整行")
	_assert_equal(result["columns"], [0, 1], "交叉组包含多条完整列")
	_assert_equal(result["cell_colors"].size(), 12, "四个交点在多线组中只统计一次")
	for key in result["row_colors"]:
		_assert_equal(result["row_colors"][key], 3, "连通组所有行使用组多数色")
	for key in result["column_colors"]:
		_assert_equal(result["column_colors"][key], 3, "连通组所有列使用组多数色")

func _test_fallbacks_and_empty_board() -> void:
	var board := BoardRules.new(4)
	_set_row(board, 0, [9, 9, 2, 2])
	var unknown_result: Dictionary = Resolver.resolve(board, {Vector2i(2, 0): 1, Vector2i(3, 0): 1})
	_assert_equal(unknown_result["row_colors"].get(0, -1), 9, "未知序号按零处理")
	var equal_result: Dictionary = Resolver.resolve(board, {})
	_assert_equal(equal_result["row_colors"].get(0, -1), 2, "数量和序号均相同时按颜色编号稳定回退")
	var empty_result: Dictionary = Resolver.resolve(BoardRules.new(4), {})
	for key in ["cell_colors", "row_colors", "column_colors", "rows", "columns"]:
		_assert_equal(empty_result[key].size(), 0, "空棋盘无消除颜色: " + key)

func _test_spectrum_band_strength_tiers() -> void:
	_assert_close(Preview.spectrum_band_strength(0), 0.0, "没有消除线时不启用彩虹带")
	_assert_close(Preview.spectrum_band_strength(1), 0.0, "单行保持轻量，不出现彩虹带")
	_assert_close(Preview.spectrum_band_strength(2), 0.5, "两线彩虹带半档")
	_assert_close(Preview.spectrum_band_strength(3), 0.75, "三线彩虹带三档")
	_assert_close(Preview.spectrum_band_strength(4), 1.0, "四线彩虹带满档")
	_assert_close(Preview.spectrum_band_strength(6), 1.0, "彩虹带档位封顶为 1")

func _set_row(board: BoardRules, y: int, colors: Array) -> void:
	for x in range(colors.size()):
		board.set_cell(x, y, int(colors[x]))

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(message + ": expected=" + str(expected) + ", actual=" + str(actual))

func _assert_close(actual: float, expected: float, message: String) -> void:
	if absf(actual - expected) > 0.0001:
		_failures += 1
		push_error(message + ": expected=" + str(expected) + ", actual=" + str(actual))
