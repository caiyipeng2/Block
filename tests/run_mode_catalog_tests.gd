extends SceneTree

const ModeCatalog = preload("res://scripts/modes/mode_catalog.gd")

var _failures := 0

func _initialize() -> void:
	_run_tests()
	if _failures == 0:
		print("MODE CATALOG TESTS PASSED")
	quit(0 if _failures == 0 else 1)

func _run_tests() -> void:
	var rules := GameRulesConfig.new()
	_assert_true(ModeCatalog.display_name(ModeCatalog.FREE) == "自由模式", "现有玩法命名自由模式")
	_assert_true(ModeCatalog.display_name(ModeCatalog.CLASSIC) == "经典模式", "经典模式显示名称")
	_assert_true(ModeCatalog.display_name(ModeCatalog.ADVENTURE) == "闯关模式", "闯关模式显示名称")
	for seed in [1, 1234, 90001]:
		var classic: Dictionary = ModeCatalog.classic_setup(seed, rules)
		var repeated: Dictionary = ModeCatalog.classic_setup(seed, rules)
		_assert_true(classic["initial_cells"] == repeated["initial_cells"], "经典模式同种子棋盘可复现")
		_assert_true(classic["initial_solution"] == repeated["initial_solution"], "经典模式同种子方案可复现")
		_assert_true(classic["initial_cells"].size() >= 16 and classic["initial_cells"].size() <= 24, "经典模式保留初始方块与空格")
		_validate_setup(classic, rules)
	var previous_requested := 0
	var previous_total := 0
	var collection_trays: Dictionary = {}
	for level_id in range(1, ModeCatalog.MAX_LEVELS + 1):
		var level: Dictionary = ModeCatalog.level_setup(level_id, ModeCatalog.MAX_LEVELS, rules)
		var repeated: Dictionary = ModeCatalog.level_setup(level_id, ModeCatalog.MAX_LEVELS, rules)
		_assert_true(level["initial_cells"] == repeated["initial_cells"] and level["target_cells"] == repeated["target_cells"], "同关棋盘和目标位置种类可复现")
		var requested := int(level["initial_diagnostics"]["requested_occupied"])
		_assert_true(requested >= previous_requested, "请求占用数随关卡进度不减少")
		previous_requested = requested
		var objective: Dictionary = ModeCatalog.objective_config(level_id)
		for field in ["objective_type", "target_total", "target_counts", "target_rows", "required_rounds", "difficulty_label", "description"]:
			_assert_true(level[field] == objective[field], "轻量目标信息与实际关卡一致：" + field)
		if level_id <= 2:
			_assert_true(level["objective_type"] == "score" and level["target_score"] == 368 + 24 * (level_id - 1), "仅前两关保留368/392分目标")
		else:
			_assert_true(level["target_total"] >= previous_total and level["target_score"] == 0, "第三关起使用非递减收集目标")
			previous_total = level["target_total"]
			_assert_true(level["target_counts"]["red_star"] > 0 and level["target_counts"]["gold_gem"] > 0, "收集关同时包含两类目标")
			_assert_true(level["certified_rounds"].size() == objective["required_rounds"], "认证路线轮数来自统一关卡阶段")
			var rows: Dictionary = {}
			for cell: Vector2i in level["target_cells"]:
				rows[cell.y] = true
			_assert_true(rows.size() >= int(objective["target_rows"]), "目标分布覆盖阶段要求的行数")
			var tray_key := ""
			for piece: PieceData in level["initial_pieces"]:
				tray_key += piece.shape_id + ";"
			collection_trays[tray_key] = true
		_validate_setup(level, rules)
	_assert_true(collection_trays.size() > 1, "收集关具有多种初始形状组合")
	for anchor in [[3, 8], [4, 10], [5, 12], [6, 14], [9, 16], [12, 18], [18, 22], [24, 24], [36, 28], [48, 32], [72, 36], [96, 40]]:
		_assert_true(ModeCatalog.objective_config(anchor[0])["target_total"] == anchor[1], "非线性目标表锚点：" + str(anchor[0]))
	var first: Dictionary = ModeCatalog.level_setup(1, ModeCatalog.MAX_LEVELS, rules)
	var final: Dictionary = ModeCatalog.level_setup(ModeCatalog.MAX_LEVELS, ModeCatalog.MAX_LEVELS, rules)
	_assert_true(first["initial_diagnostics"]["requested_occupied"] == 16 and final["initial_diagnostics"]["requested_occupied"] == 43, "请求初始密度从16增加至43")
	_assert_true(final["target_total"] == 40 and final["required_rounds"] == 3, "最终关覆盖40个目标及三轮认证")
	_assert_true(ModeCatalog.objective_description(1) == "目标 368 分", "教学关目标描述")
	_assert_true(ModeCatalog.objective_description(3) == "红星 6 个 · 金色宝石 2 个", "收集关描述展示两类目标")
	var one_level: Dictionary = ModeCatalog.level_setup(1, 1, rules)
	_assert_true(one_level["difficulty_ratio"] == 0.0, "单关配置不除零")
	var line_only := GameRulesConfig.new()
	line_only.shape_pool = [line_only.shape_pool[0]]
	var guaranteed: Dictionary = ModeCatalog.level_setup(96, 96, line_only)
	_validate_setup(guaranteed, line_only)
	_assert_true(guaranteed["target_total"] == 40, "仅横三配置仍能认证八行四十个初始目标")
	var empty_palette := GameRulesConfig.new()
	empty_palette.palette = PackedColorArray()
	var fallback_colors: Dictionary = ModeCatalog.classic_setup(55, empty_palette)
	for entry in fallback_colors["initial_cells"]:
		_assert_true(entry["color"] == 0, "空调色板安全使用零号颜色")
	var invalid_config := GameRulesConfig.new()
	invalid_config.shape_pool = []
	var invalid: Dictionary = ModeCatalog.classic_setup(55, invalid_config)
	_assert_true(not invalid["initial_diagnostics"]["solution_certified"], "无合法形状时不可伪造认证")

func _validate_setup(setup: Dictionary, rules: GameRulesConfig) -> void:
	var board := BoardRules.new(rules.board_size)
	var occupied_count: int = setup["initial_cells"].size()
	_assert_true(occupied_count > 0 and occupied_count < rules.board_size * rules.board_size, "初始占用保留方块与可用空格")
	_assert_true(occupied_count == int(setup["initial_diagnostics"]["initial_occupied"]), "诊断中的实际占用数与棋盘一致")
	for entry in setup["initial_cells"]:
		_assert_true(board.get_cell(entry["x"], entry["y"]) == -1, "初始坐标不重复")
		_assert_true(entry["x"] >= 0 and entry["x"] < board.size and entry["y"] >= 0 and entry["y"] < board.size, "初始坐标不越界")
		_assert_true(entry["color"] >= 0 and entry["color"] < maxi(1, rules.palette.size()), "预置颜色来自配置")
		board.set_cell(entry["x"], entry["y"], entry["color"])
	_assert_true(board.duplicate_board().clear_full_lines()["cells"].is_empty(), "初始棋盘没有满行或满列")
	var supplied = setup.get("target_cells", {})
	var targets: Dictionary = {}
	if supplied is Dictionary:
		targets = supplied.duplicate()
	else:
		for cell: Vector2i in supplied:
			targets[cell] = "red_star"
	var counts := {"red_star": 0, "gold_gem": 0}
	for cell: Vector2i in targets:
		var kind := str(targets[cell])
		_assert_true(board.get_cell(cell.x, cell.y) >= 0 and counts.has(kind), "特殊目标来自初始占用且种类合法")
		if counts.has(kind):
			counts[kind] += 1
	_assert_true(targets.size() == int(setup.get("target_total", 0)), "目标总数与互异坐标数一致")
	if setup.has("target_counts"):
		_assert_true(counts == setup["target_counts"], "两类目标数与实际位置一致")
	if setup.has("certified_rounds"):
		for round_entry: Dictionary in setup["certified_rounds"]:
			_assert_true(round_entry["occupancy_key"] == ModeCatalog.occupancy_key(board), "每轮占用签名匹配真实回放")
			_assert_true(round_entry["target_key"] == ModeCatalog.target_key(targets), "每轮剩余目标签名匹配真实回放")
			_replay_tray(board, round_entry["pieces"], round_entry["solution"], targets, rules)
	else:
		_replay_tray(board, setup["initial_pieces"], setup["initial_solution"], targets, rules)
	_assert_true(targets.is_empty(), "完整认证路线消除所有初始特殊目标")

func _replay_tray(board: BoardRules, pieces: Array, solution: Array, targets: Dictionary, rules: GameRulesConfig) -> void:
	_assert_true(pieces.size() == rules.tray_count and solution.size() == pieces.size(), "每个认证托盘有完整三块路径")
	var seen: Dictionary = {}
	for piece: PieceData in pieces:
		_assert_true(piece.is_valid_for_config(rules), "收集计划只使用普通配置尺寸方块")
	for step: Dictionary in solution:
		var index := int(step["piece_index"])
		var origin: Vector2i = step["origin"]
		if index < 0 or index >= pieces.size() or seen.has(index) or not board.can_place(pieces[index], origin):
			_assert_true(false, "认证路径每步真实合法且不重复用块")
			return
		seen[index] = true
		board.place(pieces[index], origin, index)
		var cleared := board.clear_full_lines()
		for cell in cleared["cells"]:
			targets.erase(cell)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("FAIL: " + message)
