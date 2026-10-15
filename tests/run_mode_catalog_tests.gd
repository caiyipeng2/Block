extends SceneTree

const ModeCatalog = preload("res://scripts/modes/mode_catalog.gd")
var _failures := 0

func _initialize() -> void:
	_run_tests()
	if _failures == 0:
		print("MODE CATALOG TESTS PASSED")
	quit(0 if _failures == 0 else 1)

func _run_tests() -> void:
	var base := GameRulesConfig.new()
	var ordinary_pool_size := base.shape_pool.size()
	var expanded: GameRulesConfig = ModeCatalog.collection_rules(base)
	_assert_true(base.min_piece_cells == 3 and base.max_piece_cells == 5 and base.shape_pool.size() == ordinary_pool_size and base.combo_miss_tolerance == 0, "收集规则复制不污染普通模式配置")
	_assert_true(expanded.min_piece_cells == 2 and expanded.max_piece_cells == 9 and expanded.combo_miss_tolerance == 2, "收集模式使用独立扩池与两次铺垫容错")
	_assert_true(ModeCatalog.collection_rules(expanded).shape_pool.size() == expanded.shape_pool.size(), "重复取得收集配置不重复扩池")
	var ids: Dictionary = {}
	for piece: PieceData in expanded.shape_pool:
		ids[piece.shape_id] = true
		_assert_true(piece.is_valid_for_config(expanded), "扩展形状保持配置允许的2至9格")
	for id in ["horizontal2", "horizontal4", "horizontal5", "vertical5", "diagonal3", "rectangle2x3", "rectangle3x3"]:
		_assert_true(ids.has(id), "参考形状进入收集专用池：" + id)
	var template_ids: Dictionary = {}
	var kind_sets: Dictionary = {}
	var previous_total := 0
	for level_id in [1, 2, 3, 4, 5, 6, 9, 12, 18, 24, 36, 48, 72, 96]:
		var level: Dictionary = ModeCatalog.level_setup(level_id, 96, base)
		var repeated: Dictionary = ModeCatalog.level_setup(level_id, 96, base)
		_assert_true(level["initial_cells"] == repeated["initial_cells"] and level["target_cells"] == repeated["target_cells"], "同关图案与初始标记可复现")
		var objective: Dictionary = ModeCatalog.objective_config(level_id)
		_assert_true(level["target_counts"] == objective["target_counts"] and level["description"] == objective["description"], "页面描述与实际配额同源")
		if level_id <= 2:
			_assert_true(level["target_score"] == 368 + 24 * (level_id - 1) and level["objective_type"] == "score", "前两关保持368与392分教学目标")
			_validate_setup(level, base)
		else:
			_assert_true(level["target_total"] >= previous_total and level["target_counts"].size() == 3, "每关包含三类且配额随阶段增加")
			_assert_true(is_equal_approx(float(level["difficulty_ratio"]), ModeCatalog.collection_difficulty(level_id)) and is_equal_approx(float(level["initial_diagnostics"]["difficulty_ratio"]), float(level["difficulty_ratio"])), "关卡难度传入首托盘供块诊断")
			previous_total = level["target_total"]
			template_ids[level["template_id"]] = true
			kind_sets[str(level["target_kinds"])] = true
			_assert_true(level["initial_diagnostics"]["certification_scope"] == "current_tray" and not level["initial_diagnostics"]["whole_level_certified"], "只声明真实首托盘证书，不宣称整关必过")
			_validate_setup(level, expanded)
	for level_id in range(3, 8):
		var level: Dictionary = ModeCatalog.level_setup(level_id, 96, base)
		template_ids[level["template_id"]] = true
		_validate_setup(level, expanded)
	_assert_true(template_ids.size() >= 5, "至少五种负空间图案")
	_assert_true(kind_sets.size() > 1, "不同阶段可以替换目标类别")
	_assert_true(ModeCatalog.objective_config(3)["target_total"] == 24 and ModeCatalog.objective_config(96)["target_total"] == 120, "需求配额从24提升至120")
	_assert_true(ModeCatalog.collection_difficulty(3) == 0.0 and ModeCatalog.collection_difficulty(96) == 1.0, "第三关至第九十六关供块难度映射零至一")
	var final: Dictionary = ModeCatalog.level_setup(96, 96, base)
	_assert_true(final["target_cells"].size() < final["target_total"], "后期目标配额允许超过初始盘实际标记数")
	var classic: Dictionary = ModeCatalog.classic_setup(17, base)
	_validate_setup(classic, base)
	_assert_true(classic["initial_cells"].size() >= 16 and classic["initial_cells"].size() <= 24, "经典模式原始开局范围保持")
	var invalid_config := GameRulesConfig.new()
	invalid_config.shape_pool = []
	_assert_true(not ModeCatalog.classic_setup(17, invalid_config)["initial_diagnostics"]["solution_certified"], "经典模式无形状配置不能伪造认证")

func _validate_setup(setup: Dictionary, rules: GameRulesConfig) -> void:
	var board := BoardRules.new(rules.board_size)
	var occupied_count: int = setup["initial_cells"].size()
	_assert_true(occupied_count > 0 and occupied_count < board.size * board.size, "初始图案保留占用和负空间")
	_assert_true(occupied_count == int(setup["initial_diagnostics"]["initial_occupied"]), "实际占用数与诊断一致")
	for entry: Dictionary in setup["initial_cells"]:
		_assert_true(board.get_cell(entry["x"], entry["y"]) == -1, "初始格互异")
		board.set_cell(entry["x"], entry["y"], entry["color"])
	_assert_true(board.duplicate_board().clear_full_lines()["cells"].is_empty(), "初始盘无满行列")
	var physical = setup.get("target_cells", {})
	for cell: Vector2i in physical:
		_assert_true(board.get_cell(cell.x, cell.y) >= 0, "初始标记都附着真实方格")
		if physical is Dictionary:
			_assert_true(setup["target_counts"].has(str(physical[cell])), "初始标记种类来自关卡目标")
	var pieces: Array = setup["initial_pieces"]
	var solution: Array = setup["initial_solution"]
	_assert_true(pieces.size() == rules.tray_count and solution.size() == pieces.size(), "每组返回完整可放方案")
	var used: Dictionary = {}
	for piece: PieceData in pieces:
		_assert_true(piece.is_valid_for_config(rules), "托盘形状遵循所属模式配置")
		for cell: Vector2i in piece.targets:
			_assert_true(piece.cells.has(cell), "托盘目标附着实际局部格")
	for step: Dictionary in solution:
		var index := int(step["piece_index"])
		var origin: Vector2i = step["origin"]
		if index < 0 or index >= pieces.size() or used.has(index) or not board.can_place(pieces[index], origin):
			_assert_true(false, "托盘证书每步真实合法且每块只用一次")
			return
		used[index] = true
		board.place(pieces[index], origin, 0)
		board.clear_full_lines()

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("FAIL: " + message)
