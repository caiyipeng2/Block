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
	var previous_count := 0
	var previous_target := 0
	for level_id in range(1, ModeCatalog.MAX_LEVELS + 1):
		var level: Dictionary = ModeCatalog.level_setup(level_id, ModeCatalog.MAX_LEVELS, rules)
		var repeated: Dictionary = ModeCatalog.level_setup(level_id, ModeCatalog.MAX_LEVELS, rules)
		_assert_true(level["level_seed"] == repeated["level_seed"], "关卡种子固定")
		_assert_true(level["initial_cells"] == repeated["initial_cells"], "同关初始布局固定")
		_assert_true(level["initial_cells"].size() >= previous_count, "关卡占用密度不随进度降低")
		previous_count = level["initial_cells"].size()
		_assert_true(level["target_score"] > previous_target, "关卡目标分随进度递增")
		previous_target = level["target_score"]
		_validate_setup(level, rules)
	var first: Dictionary = ModeCatalog.level_setup(1, ModeCatalog.MAX_LEVELS, rules)
	var final: Dictionary = ModeCatalog.level_setup(ModeCatalog.MAX_LEVELS, ModeCatalog.MAX_LEVELS, rules)
	_assert_true(first["target_score"] == 368, "首关目标为玩家确认的368分")
	_assert_true(first["initial_cells"].size() == 16, "首关初始十六格")
	_assert_true(final["initial_cells"].size() == 43, "末关初始四十三格")
	_assert_true(first["candidate_samples"] < final["candidate_samples"], "后期更积极筛选候选托盘")
	_assert_true(first["solution_count_cap"] > final["solution_count_cap"], "后期减少允许的替代路径")
	_assert_true(first["initial_cells"] != final["initial_cells"], "不同关卡有不同开局")
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
		board.clear_full_lines()

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("FAIL: " + message)
