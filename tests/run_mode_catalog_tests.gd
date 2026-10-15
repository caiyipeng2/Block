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
	var previous_target_total := 0
	var collection_trays: Dictionary = {}
	for level_id in range(1, ModeCatalog.MAX_LEVELS + 1):
		var level: Dictionary = ModeCatalog.level_setup(level_id, ModeCatalog.MAX_LEVELS, rules)
		var repeated: Dictionary = ModeCatalog.level_setup(level_id, ModeCatalog.MAX_LEVELS, rules)
		_assert_true(level["level_seed"] == repeated["level_seed"], "关卡种子固定")
		_assert_true(level["initial_cells"] == repeated["initial_cells"], "同关初始布局固定")
		_assert_true(level["target_cells"] == repeated["target_cells"], "同关特殊标记固定")
		var requested := int(level["initial_diagnostics"]["requested_occupied"])
		_assert_true(requested >= previous_requested, "请求的关卡占用数随进度不减少")
		previous_requested = requested
		var objective: Dictionary = ModeCatalog.objective_config(level_id)
		_assert_true(level["objective_type"] == objective["objective_type"] and level["target_total"] == objective["target_total"], "轻量目标信息与实际关卡一致")
		if level_id <= 2:
			_assert_true(level["objective_type"] == "score" and level["target_score"] == 368 + 24 * (level_id - 1), "仅前两关以368和392分为目标")
		else:
			_assert_true(level["objective_type"] == "collect" and level["target_score"] == 0, "第三关起以清除标记通关")
			_assert_true(level["target_total"] >= previous_target_total, "特殊目标数量不随进度减少")
			previous_target_total = level["target_total"]
			var shape_ids: Dictionary = {}
			var total_height := 0
			var tray_key := ""
			for piece: PieceData in level["initial_pieces"]:
				shape_ids[piece.shape_id] = true
				tray_key += piece.shape_id + ";"
				var min_y := piece.cells[0].y
				var max_y := piece.cells[0].y
				for cell in piece.cells:
					min_y = mini(min_y, cell.y)
					max_y = maxi(max_y, cell.y)
				total_height += max_y - min_y + 1
			collection_trays[tray_key] = true
			_assert_true(shape_ids.size() == rules.tray_count, "默认特殊关优先使用不同形状")
			_assert_true(total_height <= rules.board_size - 1, "认证形状带保留至少一行永久列孔")
		_validate_setup(level, rules)
	_assert_true(collection_trays.size() > 1, "不同关卡使用不同的形状组合与顺序")
	var first: Dictionary = ModeCatalog.level_setup(1, ModeCatalog.MAX_LEVELS, rules)
	var final: Dictionary = ModeCatalog.level_setup(ModeCatalog.MAX_LEVELS, ModeCatalog.MAX_LEVELS, rules)
	_assert_true(first["target_score"] == 368, "首关目标为玩家确认的368分")
	_assert_true(first["initial_diagnostics"]["requested_occupied"] == 16, "首关请求十六个初始占用格")
	_assert_true(final["initial_diagnostics"]["requested_occupied"] == 43, "末关请求四十三个初始占用格，实际数量服从认证路线")
	_assert_true(final["target_total"] == 12, "末关含十二个特殊标记")
	_assert_true(first["candidate_samples"] < final["candidate_samples"], "后期更积极筛选候选托盘")
	_assert_true(first["solution_count_cap"] > final["solution_count_cap"], "后期减少允许的替代路径")
	_assert_true(first["initial_cells"] != final["initial_cells"], "不同关卡有不同开局")
	var third: Dictionary = ModeCatalog.level_setup(3, ModeCatalog.MAX_LEVELS, rules)
	_assert_true(third["target_total"] == 2, "第三关从两个特殊标记开始")
	_assert_true(third["target_cells"][0].y != third["target_cells"][1].y, "起始特殊目标分散在不同清除行")
	_assert_true(ModeCatalog.objective_description(1) == "目标 368 分", "分数关目标描述")
	_assert_true(ModeCatalog.objective_description(3) == "消除 2 个特殊标记", "消除关目标描述")
	var one_level: Dictionary = ModeCatalog.level_setup(1, 1, rules)
	_assert_true(one_level["difficulty_ratio"] == 0.0, "单关配置不除零")
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
	_assert_true(occupied_count > 0 and occupied_count < rules.board_size * rules.board_size, "实际初始占用保留方块与可用空格")
	_assert_true(occupied_count == int(setup["initial_diagnostics"]["initial_occupied"]), "诊断中的实际占用数与生成棋盘一致")
	_assert_true(occupied_count >= int(setup.get("target_total", 0)), "初始占用格数足以容纳所有特殊目标")
	for entry in setup["initial_cells"]:
		_assert_true(board.get_cell(entry["x"], entry["y"]) == -1, "初始坐标不重复")
		_assert_true(entry["x"] >= 0 and entry["x"] < board.size and entry["y"] >= 0 and entry["y"] < board.size, "初始坐标不越界")
		_assert_true(entry["color"] >= 0 and entry["color"] < maxi(1, rules.palette.size()), "预置颜色来自配置")
		board.set_cell(entry["x"], entry["y"], entry["color"])
	var cleared := board.duplicate_board().clear_full_lines()
	_assert_true(cleared["cells"].is_empty(), "预置棋盘不包含需要开场自动清除的满线")
	var pieces: Array[PieceData] = []
	pieces.assign(setup["initial_pieces"])
	_assert_true(pieces.size() == rules.tray_count, "开局托盘数量符合规则")
	_assert_true(setup["initial_solution"].size() == rules.tray_count, "开局返回完整放置方案")
	_assert_true(setup["initial_diagnostics"]["solution_certified"], "开局已完成可解认证")
	var targets: Dictionary = {}
	for cell: Vector2i in setup.get("target_cells", []):
		_assert_true(board.get_cell(cell.x, cell.y) >= 0 and not targets.has(cell), "特殊标记必须是互异的初始占用格")
		targets[cell] = true
	var used: Dictionary = {}
	for step in setup["initial_solution"]:
		var index: int = step["piece_index"]
		var origin: Vector2i = step["origin"]
		_assert_true(not used.has(index), "解路径每块仅使用一次")
		used[index] = true
		if not board.can_place(pieces[index], origin):
			_assert_true(false, "开局方案每步均为真实合法落点")
			return
		board.place(pieces[index], origin, index)
		var clear_result := board.clear_full_lines()
		for cell in clear_result["cells"]:
			targets.erase(cell)
	_assert_true(targets.is_empty(), "认证路线会真实清除全部特殊标记")

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("FAIL: " + message)
