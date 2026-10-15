extends SceneTree

const ModeCatalog = preload("res://scripts/modes/mode_catalog.gd")
const LevelTable = preload("res://scripts/modes/adventure_level_table.gd")
const CollectionTemplates = preload("res://scripts/modes/collection_templates.gd")
var _failures := 0

func _initialize() -> void:
	_run_tests()
	if _failures == 0:
		print("MODE CATALOG TESTS PASSED")
	quit(0 if _failures == 0 else 1)

func _run_tests() -> void:
	_test_table_parser()
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
	_assert_true(ModeCatalog.reload_level_config().is_empty(), "当前 CSV 完整有效")
	for level_id in range(1, LevelTable.LEVEL_COUNT + 1):
		var row: Dictionary = ModeCatalog.level_config(level_id)
		var level: Dictionary = ModeCatalog.level_setup(level_id, LevelTable.LEVEL_COUNT, base)
		var repeated: Dictionary = ModeCatalog.level_setup(level_id, LevelTable.LEVEL_COUNT, base)
		_assert_true(level["initial_cells"] == repeated["initial_cells"] and level["target_cells"] == repeated["target_cells"], "同关图案与初始标记可复现")
		var objective: Dictionary = ModeCatalog.objective_config(level_id)
		_assert_true(level["target_counts"] == objective["target_counts"] and level["description"] == objective["description"], "页面描述与实际配额同源")
		var expected_counts: Dictionary = {}
		var expected_total := 0
		for kind: String in LevelTable.TARGET_COLUMNS:
			var amount := int(row[kind])
			if amount > 0:
				expected_counts[kind] = amount
				expected_total += amount
		_assert_true(level["config_valid"] and level["target_counts"] == expected_counts and level["target_total"] == expected_total, "每类配额与总量精确读取 CSV，零配额不进入目标")
		_assert_true(level["target_score"] == int(row["target_score"]) and level["objective_type"] == row["objective_type"], "分数与目标类型精确读取 CSV")
		_assert_true(is_equal_approx(float(level["difficulty_ratio"]), float(row["difficulty"]) / 100.0) and is_equal_approx(ModeCatalog.collection_difficulty(level_id), float(row["difficulty"]) / 100.0), "供块难度仅按表值百分比换算")
		_assert_true(level["level_seed"] == int(row["seed"]) and level["initial_diagnostics"]["seed"] == int(row["seed"]), "关卡随机种子精确读取 CSV")
		if level_id <= 2:
			_assert_true(int(level["initial_diagnostics"]["requested_occupied"]) == int(row["initial_fill"]) and level["target_cells"].is_empty(), "教学初始占格请求来自表且不生成收集标记")
			_validate_setup(level, base)
		else:
			_assert_true(level["target_counts"].size() >= 1 and level["target_counts"].size() <= 4, "收集关允许一至四种正配额目标")
			_assert_true(is_equal_approx(float(level["initial_diagnostics"]["difficulty_ratio"]), float(row["difficulty"]) / 100.0), "表内难度传入首托盘供块诊断")
			_assert_true(level["target_cells"].size() == int(row["initial_markers"]) and level["initial_diagnostics"]["initial_markers"] == int(row["initial_markers"]), "初始物理标记数精确读取 CSV，不与总配额混同")
			var template: Dictionary = CollectionTemplates.create(level_id, base.board_size, base.palette.size(), str(row["template_id"]), bool(row["mirror"]))
			_assert_true(level["template_id"] == row["template_id"] and level["initial_cells"] == template["initial_cells"], "模板与镜像由表指定，不按关号自动选取")
			_assert_true(level["initial_diagnostics"]["certification_scope"] == "current_tray" and not level["initial_diagnostics"]["whole_level_certified"], "只声明真实首托盘证书，不宣称整关必过")
			_validate_setup(level, expanded)
		if level_id == 3:
			_test_retry_setup(level, row, base, expanded)
	for tutorial_level in [1, 2]:
		_assert_true(is_zero_approx(ModeCatalog.retry_assistance(tutorial_level, 99)), "前两关继续独立教学保底，不叠加重试辅助")
	var classic: Dictionary = ModeCatalog.classic_setup(17, base)
	_validate_setup(classic, base)
	_assert_true(classic["initial_cells"].size() >= 16 and classic["initial_cells"].size() <= 24, "经典模式原始开局范围保持")
	var invalid_config := GameRulesConfig.new()
	invalid_config.shape_pool = []
	_assert_true(not ModeCatalog.classic_setup(17, invalid_config)["initial_diagnostics"]["solution_certified"], "经典模式无形状配置不能伪造认证")
	_assert_true(base.min_piece_cells == 3 and base.max_piece_cells == 5 and base.shape_pool.size() == ordinary_pool_size and base.combo_miss_tolerance == 0, "遍历所有表内关卡后普通模式配置保持独立")

func _test_retry_setup(original: Dictionary, row: Dictionary, base: GameRulesConfig, expanded: GameRulesConfig) -> void:
	var previous_assistance := 0.0
	for failures in [1, 99]:
		var retry: Dictionary = ModeCatalog.level_setup(3, LevelTable.LEVEL_COUNT, base, failures)
		var expected := minf(float(failures) * float(row["retry_assist_step"]), float(row["retry_assist_max"])) / 100.0
		_assert_true(is_equal_approx(float(retry["retry_assist_strength"]), expected) and expected >= previous_assistance, "重试辅助随真实失败次数增加且按本关表值封顶")
		_assert_true(is_equal_approx(float(retry["base_difficulty_ratio"]), float(original["difficulty_ratio"])) and is_equal_approx(float(retry["difficulty_ratio"]), float(original["difficulty_ratio"]) * (1.0 - expected)), "重试保留基础难度并仅调整有效供块难度")
		_assert_true(retry["retry_failures"] == failures, "开局保存本次读取的失败次数")
		for field in ["target_counts", "target_total", "target_score", "level_seed", "initial_cells", "target_cells", "template_id"]:
			_assert_true(retry[field] == original[field], "辅助不改目标、种子或初始棋盘：" + field)
		_assert_true(is_equal_approx(float(retry["initial_diagnostics"]["retry_assist_strength"]), expected) and is_equal_approx(float(retry["initial_diagnostics"]["difficulty_ratio"]), float(retry["difficulty_ratio"])), "首组供块诊断与开局重试辅助参数一致")
		_validate_setup(retry, expanded)
		previous_assistance = expected
	_assert_true(is_zero_approx(ModeCatalog.retry_assistance(3, -1)), "负失败次数不产生辅助")

func _test_table_parser() -> void:
	var reader_script: Script = LevelTable
	_assert_true(not reader_script.has_script_method("reload") and reader_script.has_script_method("reload_table"), "读表入口避免与 Script.reload 原生方法重名")
	_assert_true(LevelTable._is_utf8("教学,关卡😀".to_utf8_buffer()), "中文与四字节字符的 UTF-8 配置编码有效")
	_assert_true(not LevelTable._is_utf8(PackedByteArray([0xbd, 0xcc, 0xd1, 0xa7])), "ANSI/GBK 配置需明确提示改存 UTF-8")
	_assert_true(not LevelTable._is_utf8(PackedByteArray([0xe0, 0x80, 0x80])) and not LevelTable._is_utf8(PackedByteArray([0xf0, 0x9f])), "拒绝过长编码与截断 UTF-8 字符")
	var source := FileAccess.get_file_as_string(LevelTable.PATH)
	var parsed: Dictionary = LevelTable.parse_text(source, "测试原表")
	_assert_true(parsed["errors"].is_empty() and parsed["levels"].size() == LevelTable.LEVEL_COUNT, "完整配置包含 1–96 关且无解析错误")
	if not parsed["errors"].is_empty():
		return
	var legacy: Dictionary = LevelTable.parse_text(_csv_with_changes(source, {}, ["retry_assist_step", "retry_assist_max"]), "旧版十五列配置")
	_assert_true(legacy["errors"].is_empty() and legacy["levels"].size() == LevelTable.LEVEL_COUNT, "旧十五列配置无需新增列也可继续读取")
	if legacy["errors"].is_empty():
		_assert_true(is_equal_approx(float(legacy["levels"][3]["retry_assist_step"]), 20.0) and is_equal_approx(float(legacy["levels"][3]["retry_assist_max"]), 60.0), "缺少重试可选列采用每次20与上限60的兼容默认值")
	var custom_assist: Dictionary = LevelTable.parse_text(_csv_with_changes(source, {3: {"retry_assist_step": 0, "retry_assist_max": 0}, 4: {"retry_assist_step": 12.5, "retry_assist_max": 100}}), "自定义重试辅助配置")
	_assert_true(custom_assist["errors"].is_empty(), "重试配置允许零值关闭、小数步长及百分百上限")
	if custom_assist["errors"].is_empty():
		_assert_true(custom_assist["levels"][3]["retry_assist_step"] == 0.0 and custom_assist["levels"][3]["retry_assist_max"] == 0.0 and custom_assist["levels"][4]["retry_assist_step"] == 12.5 and custom_assist["levels"][4]["retry_assist_max"] == 100.0, "重试配表精确保留零值和独立列值")
	for column in ["retry_assist_step", "retry_assist_max"]:
		for invalid in [-1, 100.1, "not-a-number"]:
			_assert_table_rejected(_csv_with_changes(source, {3: {column: invalid}}), column, "越界或非数值重试参数拒绝整表：" + column)
	var nonlinear := _csv_with_changes(source, {
		3: {"blue_diamond": 13, "gold_gem": 0, "yellow_star": 4, "red_star": 0, "difficulty": 85},
		4: {"blue_diamond": 2, "gold_gem": 1, "yellow_star": 0, "red_star": 0, "difficulty": 12},
		5: {"blue_diamond": 1, "gold_gem": 2, "yellow_star": 3, "red_star": 4, "difficulty": 57.5},
		6: {"blue_diamond": 0, "gold_gem": 0, "yellow_star": 0, "red_star": 6, "difficulty": 0},
	})
	var tuned: Dictionary = LevelTable.parse_text(nonlinear, "自定义非单调配置")
	_assert_true(tuned["errors"].is_empty(), "后关配额和难度可以下降，不强制线性或单调增长")
	if tuned["errors"].is_empty():
		var levels: Dictionary = tuned["levels"]
		_assert_true(levels[3]["blue_diamond"] == 13 and levels[3]["gold_gem"] == 0 and levels[3]["yellow_star"] == 4 and levels[3]["red_star"] == 0 and levels[3]["difficulty"] == 85.0, "自定义不等量及零配额原样保留，不重新均分")
		_assert_true(levels[4]["blue_diamond"] == 2 and levels[4]["gold_gem"] == 1 and levels[4]["yellow_star"] == 0 and levels[4]["red_star"] == 0 and levels[4]["difficulty"] == 12.0, "后关低配额与低难度不被关号公式覆盖")
		_assert_true(levels[5]["blue_diamond"] == 1 and levels[5]["gold_gem"] == 2 and levels[5]["yellow_star"] == 3 and levels[5]["red_star"] == 4 and levels[5]["difficulty"] == 57.5, "四种目标与小数难度均可独立配置")
		_assert_true(levels[6]["blue_diamond"] == 0 and levels[6]["gold_gem"] == 0 and levels[6]["yellow_star"] == 0 and levels[6]["red_star"] == 6, "单一种类配额配置同样有效")
	_assert_table_rejected(_csv_with_changes(source, {4: {"level_id": 3}}), "level_id", "重复关号拒绝整表")
	var missing_lines := source.replace("\r\n", "\n").strip_edges().split("\n", true)
	missing_lines.remove_at(3)
	_assert_table_rejected("\n".join(missing_lines), "level_id", "缺少关卡拒绝整表")
	for invalid in [-1, 1.5]:
		_assert_table_rejected(_csv_with_changes(source, {3: {"blue_diamond": invalid}}), "blue_diamond", "负数或小数收集配额拒绝整表")
	_assert_table_rejected(_csv_with_changes(source, {3: {"template_id": "missing_template"}}), "template_id", "未知模板拒绝整表")
	_assert_table_rejected(_csv_with_changes(source, {3: {"template_id": "wings", "initial_markers": 25}}), "initial_markers", "初始标记超过模板占格拒绝整表")
	var quoted_note := "非线性,四目标\"独立配额\""
	var encoded := "\ufeff" + _csv_with_changes(source, {3: {"note": quoted_note}}).replace("\n", "\r\n")
	var portable: Dictionary = LevelTable.parse_text(encoded, "带 BOM 的 Windows CSV")
	_assert_true(portable["errors"].is_empty(), "支持 UTF-8 BOM、CRLF、引号逗号和转义双引号")
	if portable["errors"].is_empty():
		_assert_true(portable["levels"][3]["note"] == quoted_note, "备注逗号及双引号不破坏其他配置字段")

func _csv_with_changes(source: String, changes: Dictionary, excluded_columns: Array[String] = []) -> String:
	# Serialize parsed source rows so authored notes may contain quoted commas.
	var parsed: Dictionary = LevelTable.parse_text(source, "测试配置源")
	var columns := PackedStringArray()
	for column: String in LevelTable.COLUMNS:
		if not excluded_columns.has(column):
			columns.append(column)
	var lines := PackedStringArray([",".join(columns)])
	for level_id in range(1, LevelTable.LEVEL_COUNT + 1):
		var row: Dictionary = parsed["levels"][level_id].duplicate(true)
		row.merge(changes.get(level_id, {}), true)
		var fields := PackedStringArray()
		for column: String in columns:
			var value := str(row[column])
			fields.append("\"%s\"" % value.replace("\"", "\"\"") if value.contains(",") or value.contains("\"") else value)
		lines.append(",".join(fields))
	return "\n".join(lines)

func _assert_table_rejected(source: String, column: String, message: String) -> void:
	var parsed: Dictionary = LevelTable.parse_text(source, "故意无效配置")
	_assert_true(parsed["levels"].is_empty() and not parsed["errors"].is_empty(), message)
	var details := "\n".join(parsed["errors"])
	_assert_true(details.contains("CSV 行") and details.contains(column), "解析错误附带行号与相关列：" + column)

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
