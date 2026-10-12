extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	_run_tests()
	if _failures == 0:
		print("RULE TESTS PASSED")
		quit(0)
	else:
		quit(1)

func _run_tests() -> void:
	var board := BoardRules.new(8)
	_assert_equal(board.size, 8, "棋盘为 8x8")
	var line_piece := PieceData.new(Vector2i.ZERO, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	_assert_true(board.can_place(line_piece, Vector2i.ZERO), "空棋盘可放置")
	_assert_true(not board.can_place(line_piece, Vector2i(7, 0)), "越界形状不可放置")
	board.place(line_piece, Vector2i.ZERO, 2)
	_assert_true(not board.can_place(line_piece, Vector2i.ZERO), "重叠形状不可放置")

	var full_row := BoardRules.new(8)
	full_row.fill_cell_row(0, 1)
	var clear_result := full_row.clear_full_lines()
	_assert_equal(clear_result["rows"], 1, "完整行数量")
	_assert_equal(clear_result["columns"], 0, "完整列数量")
	_assert_equal(clear_result["cells"].size(), 8, "完整行清除格数")
	_assert_equal(full_row.get_cell(0, 0), -1, "清除后不下落且格子为空")

	var cross := BoardRules.new(8)
	cross.fill_cell_row(0, 1)
	cross.fill_cell_column(0, 1)
	var cross_result := cross.clear_full_lines()
	_assert_equal(cross_result["rows"], 1, "交叉局面行数")
	_assert_equal(cross_result["columns"], 1, "交叉局面列数")
	_assert_equal(cross_result["cells"].size(), 15, "行列交叉格只清一次")

	var scoring := Scoring.new()
	_assert_equal(scoring.score_placement(3), 30, "三格落子计分")
	_assert_equal(scoring.score_clear(8, 1), 80, "单线计分")
	_assert_equal(scoring.score_clear(15, 2), 225, "双线倍率计分")
	scoring.register_move(true)
	scoring.register_move(true)
	_assert_equal(scoring.combo, 2, "连续清除连击递增")
	scoring.register_move(false)
	_assert_equal(scoring.combo, 0, "未清线有效落子重置连击")

	var clearing_state := GameState.new(7)
	clearing_state.board.fill_cell_row(0, 1)
	for x in range(5, 8):
		clearing_state.board.set_cell(x, 0, -1)
	var clear_piece := PieceData.new(Vector2i.ZERO, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	clearing_state.remaining_pieces = [clear_piece, clear_piece.duplicate_piece(), clear_piece.duplicate_piece()]
	var clear_move := clearing_state.place_piece(0, Vector2i(5, 0), 2)
	_assert_true(bool(clear_move["ok"]), "可完成一整行的落子有效")
	_assert_equal(clear_move["clear"]["rows"], 1, "GameState 结算整行")
	_assert_equal(clear_move.get("placement_points", -1), 30, "GameState 返回落子分")
	_assert_equal(clear_move.get("clear_points", -1), 80, "GameState 返回清除分")
	_assert_equal(clear_move.get("last_placement_points", -1), 30, "GameState 保存最近落子分")
	_assert_equal(clear_move.get("last_clear_points", -1), 80, "GameState 保存最近清除分")
	_assert_equal(clear_move.get("last_clear_lines", -1), 1, "GameState 保存最近清除行数")
	_assert_equal(clear_move.get("gained", -1), 110, "GameState 返回本次总得分")
	_assert_equal(clear_move["score"], 110, "GameState 更新总分")
	_assert_equal(clear_move["combo"], 1, "GameState 更新连击")
	_assert_equal(clear_move.get("total_cleared_lines", -1), 1, "GameState 累计清除行数")
	_assert_equal(clearing_state.total_cleared_lines, 1, "GameState 保存累计清除行数")

	var placement_state := GameState.new(8)
	placement_state.board.set_cell(7, 7, 1)
	var placement_piece := PieceData.new(Vector2i.ZERO, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	placement_state.remaining_pieces = [placement_piece]
	var placement_move := placement_state.place_piece(0, Vector2i(0, 0), 1)
	_assert_true(bool(placement_move["ok"]), "无消除的合法落子有效")
	_assert_equal(placement_move.get("placement_points", -1), 30, "无消除落子仍获得放置分")
	_assert_equal(placement_move.get("clear_points", -1), 0, "无消除落子清除分为零")
	_assert_equal(placement_move.get("last_placement_points", -1), 30, "无消除保存最近落子分")
	_assert_equal(placement_move.get("last_clear_points", -1), 0, "无消除保存最近清除分")
	_assert_equal(placement_move.get("last_clear_lines", -1), 0, "无消除保存最近清除行数")
	_assert_equal(placement_move.get("gained", -1), 30, "无消除落子总分")
	_assert_equal(placement_move.get("combo", -1), 0, "无清线有效落子连击归零")

	var invalid_state := GameState.new(9)
	invalid_state.remaining_pieces = [placement_piece]
	var invalid_move := invalid_state.place_piece(0, Vector2i(7, 7), 1)
	_assert_true(not bool(invalid_move["ok"]), "越界落子无效")
	_assert_equal(invalid_move.get("placement_points", -1), 0, "无效落子不获得放置分")
	_assert_equal(invalid_move.get("clear_points", -1), 0, "无效落子不获得清除分")
	_assert_equal(invalid_move.get("last_placement_points", -1), 0, "初始最近落子分为零")
	_assert_equal(invalid_move.get("last_clear_points", -1), 0, "初始最近清除分为零")
	_assert_equal(invalid_move.get("last_clear_lines", -1), 0, "初始最近清除行数为零")
	_assert_equal(invalid_move.get("gained", -1), 0, "无效落子不增加总分")
	_assert_equal(invalid_move.get("score", -1), 0, "无效落子不改变总分")

	var invalid_after_valid := placement_state.place_piece(999, Vector2i.ZERO, 1)
	_assert_true(not bool(invalid_after_valid["ok"]), "合法落子后的越界索引无效")
	_assert_equal(invalid_after_valid.get("last_placement_points", -1), 30, "无效落子保持最近落子分")
	_assert_equal(invalid_after_valid.get("last_clear_points", -1), 0, "无效落子保持最近清除分")
	_assert_equal(invalid_after_valid.get("last_clear_lines", -1), 0, "无效落子保持最近清除行数")

	var generator := RoundGenerator.new(1234)
	var round := generator.generate_solvable_round(BoardRules.new(8))
	_assert_equal(round.size(), 3, "每轮恰好三块")
	_assert_true(generator.has_any_solution(BoardRules.new(8), round), "新一轮至少存在一种可解排列")

	var state := GameState.new(1234)
	_assert_true(state.has_legal_move_for_any_remaining_piece(), "只要任意剩余方块可放就不能结束")
	var blocked := GameState.new(99)
	blocked.board.fill_all(1)
	blocked.remaining_pieces = [PieceData.new(Vector2i.ZERO, [Vector2i.ZERO])]
	_assert_true(not blocked.has_legal_move_for_any_remaining_piece(), "所有剩余方块无落点时结束")

	# Keep interface coverage available for later explicit test runs. This task
	# only maintains these cases; automated gameplay execution is not authorized.
	var configured_rules := GameRulesConfig.new()
	configured_rules.base_points_per_cell = 7
	configured_rules.multiline_bonus_step = 1.0
	var configured_score := Scoring.new(configured_rules)
	_assert_equal(configured_score.score_clear(15, 2), 210, "配置控制清格分数与多线倍率")
	var shipped_rules := load("res://config/default_rules.tres") as GameRulesConfig
	_assert_true(shipped_rules != null, "默认规则资源可加载")
	if shipped_rules != null:
		_assert_equal(shipped_rules.board_size, 8, "资源棋盘保持 8x8")
		_assert_equal(shipped_rules.tray_count, 3, "资源每轮三块")
		_assert_equal(shipped_rules.shape_pool.size(), 5, "资源保持五种固定方向形状")
	_assert_true(generator.has_any_solution(BoardRules.new(8), []), "空方块组保持可解恒等语义")

	var order_board := BoardRules.new(3)
	for y in range(2):
		order_board.set_cell(0, y, 1)
		order_board.set_cell(2, y, 9)
	var square := PieceData.new(Vector2i.ZERO, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], "same_id")
	var row_line := line_piece.duplicate_piece()
	row_line.shape_id = "same_id"
	var ordered_pieces: Array[PieceData] = [square, row_line]
	var order_before := order_board.duplicate_board()
	var order_solution := generator.find_solution(order_board, ordered_pieces)
	_assert_equal(order_solution.size(), 2, "先清线再落方块的任意顺序方案可求得")
	if not order_solution.is_empty():
		_assert_equal(order_solution[0]["piece_index"], 1, "同 ID 不同形状仍分别求解")
	for y in range(3):
		for x in range(3):
			_assert_equal(order_board.get_cell(x, y), order_before.get_cell(x, y), "求解不修改活动棋盘")
	var recolored := order_board.duplicate_board()
	for y in range(3):
		for x in range(3):
			if recolored.get_cell(x, y) != -1:
				recolored.set_cell(x, y, 4)
	_assert_equal(generator.find_solution(recolored, ordered_pieces), order_solution, "颜色不影响求解序列")

	var fallback_rules := GameRulesConfig.new()
	fallback_rules.generation_attempts = 0
	var fallback_generator := RoundGenerator.new(333, fallback_rules)
	var fallback_round := fallback_generator.generate_solvable_round(BoardRules.new(8))
	_assert_equal(fallback_round.size(), 3, "零随机尝试时构造式保底得到整组三块")
	_assert_equal(fallback_generator.last_solution.size(), 3, "保底返回完整可复现方案")
	_assert_true(bool(fallback_generator.last_diagnostics.get("fallback_used", false)), "保底诊断标记")
	_assert_equal(fallback_generator.last_diagnostics.get("attempts", -1), 0, "保底诊断记录零随机尝试")
	var dead_board := BoardRules.new(8)
	dead_board.fill_all(0)
	_assert_true(fallback_generator.generate_solvable_round(dead_board).is_empty(), "无首步合法落点时返回真实无方案")
	_assert_equal(fallback_generator.last_diagnostics.get("reason", ""), "no_solution", "无方案诊断原因")
	var first_seeded := RoundGenerator.new(987)
	var second_seeded := RoundGenerator.new(987)
	var first_round := first_seeded.generate_solvable_round(BoardRules.new(8))
	var second_round := second_seeded.generate_solvable_round(BoardRules.new(8))
	for index in range(first_round.size()):
		_assert_equal(first_round[index].cells, second_round[index].cells, "相同种子生成相同方块组")
	_assert_equal(first_seeded.last_solution, second_seeded.last_solution, "相同种子返回相同求解序列")

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("FAIL: " + message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		push_error("FAIL: %s; actual=%s expected=%s" % [message, actual, expected])
