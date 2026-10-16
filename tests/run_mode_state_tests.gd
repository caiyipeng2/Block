extends SceneTree

const ModeCatalog = preload("res://scripts/modes/mode_catalog.gd")
const OpeningTraySupplier = preload("res://scripts/rules/opening_tray_supplier.gd")

## Maintained coverage; normal delivery compiles this script without running it.
var failures := 0

func _initialize() -> void:
	_test_score_modes()
	_test_rejected_configuration()
	_test_tutorial_adaptation()
	_test_collection_progress()
	_test_crossing_collection()
	_test_streamed_collection()
	_test_retry_supply()
	_test_opening_scope_and_threshold()
	_test_opening_clear_paths()
	_test_opening_reproducibility_and_fallback()
	if failures == 0:
		print("MODE STATE TESTS PASSED")
	quit(0 if failures == 0 else 1)

func _test_score_modes() -> void:
	var config := GameRulesConfig.new()
	var line := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	var setup := {
		"mode": "adventure", "level_id": 1, "target_score": 100,
		"initial_cells": [],
		"initial_pieces": [line, line.duplicate_piece(), line.duplicate_piece()],
		"initial_solution": [
			{"piece_index": 0, "origin": Vector2i.ZERO},
			{"piece_index": 1, "origin": Vector2i(3, 0)},
			{"piece_index": 2, "origin": Vector2i(0, 1)},
		],
	}
	var adventure := GameState.new(17, 8, config, setup)
	_check(adventure.scoring.score == 0, "预置与初始托盘不计分")
	for x in range(5):
		adventure.board.set_cell(x, 0, 1)
	# Reaching the goal with the last tray piece must not trigger a fresh round.
	adventure.remaining_pieces = [line]
	var result := adventure.place_piece(0, Vector2i(5, 0), 2)
	_check(bool(result["ok"]) and int(result["gained"]) == 110, "模式复用既有放置加清除计分")
	_check(adventure.is_level_complete() and not adventure.is_game_over(), "达标优先通关")
	_check(not bool(result["round_refilled"]) and adventure.round_index == 0, "通关不补新组三块")
	_check(adventure.remaining_pieces.is_empty(), "最后一块通关后无额外托盘")
	var denied := adventure.place_piece(0, Vector2i.ZERO, 0)
	_check(not bool(denied["ok"]) and adventure.scoring.score == 110, "通关后拒绝继续落子")
	var free_setup := setup.duplicate(true)
	free_setup["mode"] = "free"
	free_setup["target_score"] = 1
	var free := GameState.new(18, 8, config, free_setup)
	var free_move := free.place_piece(0, Vector2i.ZERO, 0)
	_check(bool(free_move["ok"]) and not free.is_level_complete() and free.target_score == 0, "自由模式不受目标限制")
	free_setup["mode"] = "classic"
	var classic := GameState.new(19, 8, config, free_setup)
	classic.place_piece(0, Vector2i.ZERO, 0)
	_check(not classic.is_level_complete() and classic.target_score == 0, "经典模式不受目标限制")

func _test_rejected_configuration() -> void:
	var config := GameRulesConfig.new()
	for invalid_flag in ["config_valid", "initial_setup_invalid"]:
		var setup := {"mode": "adventure", "level_id": 1, "objective_type": "score", "target_score": 368}
		setup[invalid_flag] = invalid_flag != "config_valid"
		var rejected := GameState.new(17, 8, config, setup)
		_check(rejected.is_game_over() and not rejected.is_level_complete() and rejected.remaining_pieces.is_empty(), "分数关显式配置失败不能静默生成普通游戏：" + invalid_flag)
		_check(rejected.scoring.score == 0, "配置拒绝不赠分：" + invalid_flag)

func _isolated_holes_setup(mode: String = "adventure", level_id: int = 1) -> Dictionary:
	var initial: Array[Dictionary] = []
	for y in range(8):
		for x in range(8):
			if (x + y) % 2 == 1:
				initial.append({"x": x, "y": y, "color": 0})
	return {"mode": mode, "level_id": level_id, "objective_type": "score", "target_score": 10000, "initial_cells": initial}

func _test_tutorial_adaptation() -> void:
	var config := GameRulesConfig.new()
	var first := GameState.new(31, 8, config, _isolated_holes_setup())
	_check(not first.is_game_over() and first.remaining_pieces.size() == 3, "第一关孤立空洞残局仍可供应完整托盘")
	_check(bool(first.generation_diagnostics.get("tutorial", false)), "前两关供应诊断标记为教学保底")
	_check(first.scoring.score == 0 and first.board.get_cell(0, 0) == -1, "供块不改棋盘也不赠送分数")
	for piece in first.remaining_pieces:
		_check(piece.cell_count() == 1 and not piece.is_valid_for_config(config), "孤立孔使用内部单格救援且不放宽全局形状规则")
	var retained := first.remaining_pieces.duplicate()
	var ordinary_move := first.place_piece(0, Vector2i.ZERO, 1)
	_check(int(ordinary_move["placement_points"]) == 10 and int(ordinary_move["clear_points"]) == 0, "单格救援按实际一格计10分")
	_check(not bool(ordinary_move["tray_adapted"]) and first.remaining_pieces[0] == retained[1] and first.remaining_pieces[1] == retained[2], "剩余托盘仍有完整路径时不换块")
	var second := GameState.new(32, 8, config, _isolated_holes_setup("adventure", 2))
	var rescue := second.remaining_pieces[0]
	var line := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	var square := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)])
	second.remaining_pieces = [rescue, line, square]
	var adapted := second.place_piece(0, Vector2i.ZERO, 2)
	_check(bool(adapted["tray_adapted"]) and second.remaining_pieces.size() == 2 and not second.is_game_over(), "第二关落子后堵死的剩余两块自动适配且不提前结束")
	_check(second.generator.find_solution(second.board, second.remaining_pieces).size() == 2, "适配后的剩余组具有真实完整放置路径")
	_check(second.scoring.score == 10 and second.round_index == 0, "剩余组适配不送分也不推进回合号")
	_check(second.board.get_cell(0, 0) == 2 and second.board.get_cell(2, 0) == -1, "适配保留玩家落子且不填未操作的空格")
	var pair_setup := _isolated_holes_setup()
	var pair_initial: Array[Dictionary] = []
	for entry: Dictionary in pair_setup["initial_cells"]:
		if int(entry["x"]) != 1 or int(entry["y"]) != 0:
			pair_initial.append(entry)
	pair_initial.append({"x": 2, "y": 0, "color": 0})
	pair_setup["initial_cells"] = pair_initial
	var paired := GameState.new(34, 8, config, pair_setup)
	_check(paired.remaining_pieces[0].cell_count() == 2, "只有二格可用时先使用二格救援")
	var pair_move := paired.place_piece(0, Vector2i.ZERO, 1)
	_check(int(pair_move["placement_points"]) == 20 and int(pair_move["clear_points"]) == 0, "二格救援按实际两格计20分")
	for mode in ["free", "classic", "adventure"]:
		var level_id := 3 if mode == "adventure" else 1
		var ordinary := GameState.new(33, 8, config, _isolated_holes_setup(mode, level_id))
		_check(not bool(ordinary.generation_diagnostics.get("tutorial", false)) and ordinary.is_game_over(), "自由经典和第三关不引入教学救援：" + mode)

func _collection_setup() -> Dictionary:
	var line := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	var initial: Array[Dictionary] = []
	for y in [0, 2, 4]:
		for x in range(5):
			initial.append({"x": x, "y": y, "color": y % 6})
	return {
		"mode": "adventure", "level_id": 3, "objective_type": "collect",
		"target_score": 1, "candidate_samples": 12,
		"target_cells": [Vector2i(0, 2), Vector2i(0, 4), Vector2i(0, 4)],
		"initial_cells": initial,
		"initial_pieces": [line, line.duplicate_piece(), line.duplicate_piece()],
		"initial_solution": [
			{"piece_index": 0, "origin": Vector2i(5, 0)},
			{"piece_index": 1, "origin": Vector2i(5, 2)},
			{"piece_index": 2, "origin": Vector2i(5, 4)},
		],
	}

func _test_collection_progress() -> void:
	var config := GameRulesConfig.new()
	var setup := _collection_setup()
	var adventure := GameState.new(22, 8, config, setup)
	_check(adventure.objective_type == "collect" and adventure.target_score == 0, "特殊目标关不使用分数作为通关条件")
	_check(adventure.target_total == 2 and adventure.target_collected == 0, "重复目标坐标去重且开局尚未收集")
	_check(adventure.remaining_pieces[0].cells == setup["initial_pieces"][0].cells, "特殊关保留带目标认证的初始托盘")
	var ordinary := adventure.place_piece(0, Vector2i(5, 0), 1)
	_check(bool(ordinary["ok"]) and ordinary["collected_targets"].is_empty(), "普通消除不增加特殊目标收集")
	_check(adventure.scoring.score > 1 and not adventure.is_level_complete(), "分数超过旧目标但标记尚在时不通关")
	var first_target := adventure.place_piece(0, Vector2i(5, 2), 2)
	_check(first_target["target_collected"] == 1 and first_target["target_remaining"] == 1, "清除一枚特殊标记更新剩余数")
	_check(first_target["collected_targets"] == [Vector2i(0, 2)], "结果返回真实清除的特殊格坐标")
	var previous_score := adventure.scoring.score
	var invalid := adventure.place_piece(0, Vector2i(-1, -1), 2)
	_check(not bool(invalid["ok"]) and invalid["target_collected"] == 1 and invalid["target_remaining"] == 1, "非法落子保持收集状态不变")
	_check(invalid["collected_targets"].is_empty() and adventure.scoring.score == previous_score, "非法落子无收集或分数增量")
	var final_target := adventure.place_piece(0, Vector2i(5, 4), 3)
	_check(adventure.is_level_complete() and final_target["target_remaining"] == 0, "特殊目标清完即通关")
	_check(not bool(final_target["round_refilled"]) and adventure.round_index == 0, "清完目标优先胜利且不补盘")
	var restarted := GameState.new(22, 8, config, setup)
	_check(restarted.target_total == 2 and restarted.target_collected == 0 and restarted.target_cells.size() == 2 and restarted.scoring.score == 0, "重开恢复原始特殊标记和零进度")
	var invalid_setup := setup.duplicate(true)
	invalid_setup["target_cells"] = [Vector2i(7, 7)]
	var broken := GameState.new(22, 8, config, invalid_setup)
	_check(broken.is_game_over() and not broken.is_level_complete(), "空白格不能伪造特殊目标并自动过关")
	invalid_setup["target_cells"] = [Vector2i(0, 2)]
	invalid_setup["initial_solution"] = [
		{"piece_index": 0, "origin": Vector2i(5, 0)},
		{"piece_index": 1, "origin": Vector2i(0, 6)},
		{"piece_index": 2, "origin": Vector2i(3, 6)},
	]
	var uncertified := GameState.new(22, 8, config, invalid_setup)
	_check(not uncertified.is_game_over(), "持续补给模式只要求首组完整可放，不要求三步清完全部目标")

func _test_crossing_collection() -> void:
	var config := GameRulesConfig.new()
	var step := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(0, 1), Vector2i(1, 1)])
	var line := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	var occupied: Dictionary = {}
	for coordinate in range(8):
		if coordinate != 5:
			occupied[Vector2i(coordinate, 0)] = true
		if coordinate != 1:
			occupied[Vector2i(6, coordinate)] = true
	var initial: Array[Dictionary] = []
	for cell: Vector2i in occupied:
		initial.append({"x": cell.x, "y": cell.y, "color": 1})
	var setup := {
		"mode": "adventure", "level_id": 3, "objective_type": "collect",
		"target_cells": {Vector2i(6, 0): "red_star", Vector2i(0, 0): "gold_gem"},
		"target_counts": {"red_star": 1, "gold_gem": 1}, "target_total": 2, "initial_cells": initial,
		"initial_pieces": [step, line, line.duplicate_piece()],
		"initial_solution": [
			{"piece_index": 0, "origin": Vector2i(5, 0)},
			{"piece_index": 1, "origin": Vector2i(0, 3)},
			{"piece_index": 2, "origin": Vector2i(0, 4)},
		],
	}
	var adventure := GameState.new(23, 8, config, setup)
	var result := adventure.place_piece(0, Vector2i(5, 0), 2)
	_check(result["clear"]["rows"] == 1 and result["clear"]["columns"] == 1, "交叉消除场景真实包含行列")
	_check(result["target_collected"] == 2 and result["collected_targets"].size() == 2, "行列交叉特殊格去重，两类目标各收集一次")
	_check(result["target_collected_counts"] == {"red_star": 1, "gold_gem": 1} and result["collected_target_events"].size() == 2, "分类进度和动画事件与真实目标一致")
	_check(adventure.is_level_complete() and adventure.remaining_pieces.size() == 2, "目标清完后即便仍有托盘方块也立即胜利")
	_check_collection_sums(adventure, "交叉消除")
	var restarted := GameState.new(23, 8, config, setup)
	_check(restarted.target_counts == {"red_star": 1, "gold_gem": 1} and restarted.target_collected_counts == {"red_star": 0, "gold_gem": 0}, "重开恢复两类目标总数和零进度")
	_check_collection_sums(restarted, "重开")
	var malformed := setup.duplicate(true)
	malformed["target_total"] = 3
	_check(GameState.new(23, 8, config, malformed).is_game_over(), "声明分类配额与总量不符时拒绝开局")
	malformed = setup.duplicate(true)
	malformed["target_cells"][Vector2i(7, 7)] = "red_star"
	_check(GameState.new(23, 8, config, malformed).is_game_over(), "包含空白格的目标集不能静默缩减后开局")

func _test_streamed_collection() -> void:
	var base := GameRulesConfig.new()
	var line := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)], "line3")
	var initial: Array[Dictionary] = []
	for y in [0, 2, 4]:
		for x in range(5):
			initial.append({"x": x, "y": y, "color": 1})
	initial.append({"x": 0, "y": 6, "color": 1})
	var first := line.duplicate_piece()
	first.targets = {Vector2i(0, 0): "blue_diamond", Vector2i(1, 0): "blue_diamond"}
	var second := line.duplicate_piece()
	second.targets = {Vector2i(0, 0): "gold_gem"}
	var setup := {
		"mode": "adventure", "level_id": 3, "objective_type": "collect",
		"initial_cells": initial,
		"target_cells": {Vector2i(0, 0): "blue_diamond", Vector2i(0, 2): "blue_diamond", Vector2i(0, 4): "yellow_star", Vector2i(0, 6): "blue_diamond"},
		"target_counts": {"blue_diamond": 1, "gold_gem": 1, "yellow_star": 1}, "target_total": 3,
		"initial_pieces": [first, second, line.duplicate_piece()],
		"initial_solution": [
			{"piece_index": 0, "origin": Vector2i(5, 0)},
			{"piece_index": 1, "origin": Vector2i(5, 2)},
			{"piece_index": 2, "origin": Vector2i(5, 4)},
		],
	}
	var adventure := GameState.new(40, 8, base, setup)
	_check(not adventure.is_game_over() and base.max_piece_cells == 5 and adventure.rules_config.max_piece_cells == 9, "收集专用扩池不污染传入配置")
	var result := adventure.place_piece(0, Vector2i(5, 0), 2)
	_check(result["placed_targets"].size() == 2 and result["collected_target_events"].size() == 3, "托盘局部标记落地转世界坐标后参与同次消除")
	var counted := 0
	for event: Dictionary in result["collected_target_events"]:
		counted += int(event["counted"])
	_check(counted == 1 and adventure.target_collected == 1 and adventure.target_remaining_counts["blue_diamond"] == 0, "富余标记保留事件但需求归零截断")
	_check(adventure.target_cells.has(Vector2i(0, 2)) and adventure.target_cells.has(Vector2i(0, 6)), "某类已完成后原有同类标记继续留盘")
	_check_collection_sums(adventure, "蓝色配额完成")
	result = adventure.place_piece(0, Vector2i(5, 2), 3)
	_check(result["collected_target_events"].size() == 2 and adventure.target_collected == 2, "已完成类与未完成类同时清除只给后者计需求")
	_check_collection_sums(adventure, "分类混合清除")
	result = adventure.place_piece(0, Vector2i(5, 4), 4)
	_check(adventure.is_level_complete() and adventure.target_cells.has(Vector2i(0, 6)), "所有类别配额达标即可胜利，盘上允许保留旧富余标记")
	_check(result["target_remaining"] == 0 and result["marked_cells_remaining"] == 1, "需求剩余数与盘上标记数独立暴露")
	_check_collection_sums(adventure, "需求完成")
	var restarted := GameState.new(40, 8, base, setup)
	_check(restarted.target_collected == 0 and restarted.target_cells.size() == 4 and restarted.target_remaining_counts == setup["target_counts"], "重开恢复需求和初始物理标记")
	var supplier_rules: GameRulesConfig = ModeCatalog.collection_rules(base)
	var supplier = preload("res://scripts/rules/collection_tray_supplier.gd").new(supplier_rules, 50)
	var generator := RoundGenerator.new(50, supplier_rules)
	var supplied: Dictionary = supplier.build(BoardRules.new(8), {"blue_diamond": 1, "gold_gem": 0}, generator)
	var supplied_pieces: Array[PieceData] = []
	supplied_pieces.assign(supplied["pieces"])
	var marker_count := 0
	for piece in supplied_pieces:
		for cell: Vector2i in piece.targets:
			marker_count += 1
			_check(piece.targets[cell] == "blue_diamond", "新供给只分配尚未完成类型")
	_check(marker_count > 1 and supplied_pieces.size() == 3, "只差一个目标仍允许明显富余，不将供块硬限为一枚")
	_check(generator.find_solution(BoardRules.new(8), supplied_pieces).size() == 3, "持续补给托盘仍有完整真实几何路径")
	_check(supplied["diagnostics"]["certification_scope"] == "current_tray", "供块诊断仅承诺当前三块可放")
	var hard_supplier = preload("res://scripts/rules/collection_tray_supplier.gd").new(supplier_rules, 50, 1.0)
	var hard_supplied: Dictionary = hard_supplier.build(BoardRules.new(8), {"blue_diamond": 1}, generator)
	_check(float(hard_supplied["diagnostics"]["difficulty_ratio"]) == 1.0 and not bool(hard_supplied["diagnostics"]["whole_level_certified"]), "后期供块记录难度且不宣称整关唯一解")
	for piece: PieceData in hard_supplied["pieces"]:
		_check(piece.is_valid_for_config(supplier_rules), "后期难度权重不改变合法形状约束")

func _test_retry_supply() -> void:
	var setup := _collection_setup()
	setup["target_counts"] = {"blue_diamond": 50, "gold_gem": 1}
	setup["target_total"] = 51
	setup["target_cells"] = {Vector2i(0, 2): "blue_diamond", Vector2i(0, 4): "gold_gem"}
	setup["difficulty_ratio"] = 0.36
	setup["retry_assist_strength"] = 0.4
	setup.erase("initial_pieces")
	setup.erase("initial_solution")
	var state := GameState.new(64, 8, GameRulesConfig.new(), setup)
	_check(not state.is_game_over() and is_equal_approx(state.retry_assist_strength, 0.4), "收集开局保存本次重试辅助强度")
	_check(is_equal_approx(float(state.generation_diagnostics["retry_assist_strength"]), 0.4) and is_equal_approx(float(state.generation_diagnostics["difficulty_ratio"]), 0.36), "首组供应使用本次有效难度和辅助强度")
	var before_board := state.board.duplicate_board()
	var before_targets := state.target_cells.duplicate(true)
	var before_remaining := state.target_remaining_counts.duplicate(true)
	state._fill_collection_tray()
	_check(is_equal_approx(float(state.generation_diagnostics["retry_assist_strength"]), 0.4) and is_equal_approx(float(state.generation_diagnostics["difficulty_ratio"]), 0.36), "后续供应继续使用同一开局辅助参数")
	_check(state.target_cells == before_targets and state.target_remaining_counts == before_remaining, "候选供块模拟不修改真实盘上标记或剩余配额")
	var board_unchanged := true
	for y in range(state.board.size):
		for x in range(state.board.size):
			board_unchanged = board_unchanged and state.board.get_cell(x, y) == before_board.get_cell(x, y)
	_check(board_unchanged and state.scoring.score == 0 and state.total_moves == 0, "重试供块不移动现有方格、不送分也不制造玩家落子")
	_check(state.generator.find_solution(state.board, state.remaining_pieces).size() == state.rules_config.tray_count, "辅助后的供应仍保留完整三块几何解")
	var supplier = state.get("_collection_supplier")
	var markers := {Vector2i(0, 0): "blue_diamond", Vector2i(1, 0): "blue_diamond", Vector2i(2, 0): "gold_gem", Vector2i(3, 0): "red_star"}
	var cleared: Array = [Vector2i(0, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(7, 7)]
	_check(supplier._needed_target_count(cleared, markers, {"blue_diamond": 1, "gold_gem": 0}) == 1, "辅助评价去重交叉坐标、按需求封顶并忽略已满或不需要种类")
	_check(supplier._needed_target_count(cleared, markers, {"blue_diamond": 2, "gold_gem": 1}) == 3, "辅助评价按每类真实剩余量计算有效收集进度")

func _opening_fixture(mode: String) -> Dictionary:
	var line := PieceData.new(Vector2i.ZERO, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)], "line3")
	return {
		"mode": mode, "target_score": 1,
		"initial_pieces": [line, line.duplicate_piece(), line.duplicate_piece()],
		"initial_solution": [
			{"piece_index": 0, "origin": Vector2i.ZERO},
			{"piece_index": 1, "origin": Vector2i(3, 0)},
			{"piece_index": 2, "origin": Vector2i(0, 1)},
		],
		"initial_diagnostics": {"fixture": true},
	}

func _test_opening_scope_and_threshold() -> void:
	var classic_config := GameRulesConfig.new()
	var generated_classic := GameState.new(80, 8, classic_config, ModeCatalog.classic_setup(80, classic_config))
	_check(bool(generated_classic.generation_diagnostics.get("opening_assist", false)), "真实经典入口生成的认证初盘也启用普通开局辅助")
	for mode in ["free", "classic"]:
		var state := GameState.new(81, 8, GameRulesConfig.new(), {"mode": mode})
		_check(bool(state.generation_diagnostics.get("opening_assist", false)) and state.remaining_pieces.size() == 3, "普通初盘在1500分前使用完整消除友好供应：" + mode)
		_check(state.scoring.score == 0 and state.total_moves == 0 and state.target_score == 0, "预测路径不赠分、不制造落子且不设通关目标：" + mode)
		state.scoring.score = 1499
		_check(state._uses_opening_supplier(), "1499分仍在辅助范围：" + mode)
		state.scoring.score = 1500
		_check(not state._uses_opening_supplier(), "1500分立即离开辅助范围：" + mode)
		for refill_score in [1499, 1500]:
			var boundary := GameState.new(82, 8, GameRulesConfig.new(), _opening_fixture(mode))
			boundary.remaining_pieces = [boundary.remaining_pieces[0]]
			boundary.scoring.score = refill_score - 30
			var refill := boundary.place_piece(0, Vector2i.ZERO)
			_check(bool(refill["round_refilled"]) and boundary.scoring.score == refill_score and boundary.round_index == 1, "补盘按真实落子后分数判断边界：%s/%d" % [mode, refill_score])
			_check(bool(boundary.generation_diagnostics.get("opening_assist", false)) == (refill_score < 1500), "1499/1500补盘选择正确且不残留辅助诊断：%s/%d" % [mode, refill_score])
			_check(not bool(refill["tray_adapted"]) and not boundary.is_level_complete(), "普通补盘不使用动态适配也不设无限分终点：" + mode)
		var fixture := _opening_fixture(mode)
		var crossing := GameState.new(83, 8, GameRulesConfig.new(), fixture)
		_check(bool(crossing.generation_diagnostics.get("fixture", false)) and crossing.remaining_pieces[0] != fixture["initial_pieces"][0], "显式合法认证初盘保留且复制：" + mode)
		var retained := crossing.remaining_pieces.duplicate()
		crossing.scoring.score = 1499
		var crossed := crossing.place_piece(0, Vector2i.ZERO)
		_check(crossing.scoring.score == 1529 and crossing.remaining_pieces[0] == retained[1] and crossing.remaining_pieces[1] == retained[2], "跨过阈值不更换已经发出的两块：" + mode)
		_check(not bool(crossed["round_refilled"]) and not bool(crossed["tray_adapted"]) and bool(crossing.generation_diagnostics.get("fixture", false)), "跨阈值仅在耗尽托盘后切换：" + mode)
		crossing.place_piece(0, Vector2i(3, 0))
		var next_round := crossing.place_piece(0, Vector2i(0, 1))
		_check(bool(next_round["round_refilled"]) and not crossing.generation_diagnostics.has("opening_assist") and not crossing.generation_diagnostics.has("fixture"), "跨阈值后下一组三块恢复原始生成与诊断：" + mode)
	for level in [1, 2, 3]:
		var adventure := GameState.new(84, 8, GameRulesConfig.new(), {"mode": "adventure", "level_id": level, "target_score": 10000})
		_check(not adventure._uses_opening_supplier() and not adventure.generation_diagnostics.has("opening_assist"), "闯关分数/教学供应不进入普通开局辅助：%d" % level)
	var collection := GameState.new(85, 8, GameRulesConfig.new(), _collection_setup())
	_check(not collection._uses_opening_supplier() and not collection.generation_diagnostics.has("opening_assist"), "冒险收集分支不进入普通开局辅助")

func _test_opening_clear_paths() -> void:
	var config := GameRulesConfig.new()
	var gap := BoardRules.new(8)
	for x in range(5):
		gap.set_cell(x, 0, 3)
	var before_gap := gap.duplicate_board()
	var supplied: Dictionary = OpeningTraySupplier.new(config, 86).build(gap, RoundGenerator.new(86, config))
	var gap_lines := _check_opening_certificate(gap, supplied, "单行缺口")
	_check(not gap_lines.is_empty() and gap_lines[0] == 1, "可立即补齐的普通三格缺口优先单线消除")
	_check(_same_board(gap, before_gap), "供应模拟不修改真实棋盘、格色或空格")
	var crossing := BoardRules.new(8)
	for coordinate in range(8):
		if coordinate != 5:
			crossing.set_cell(coordinate, 0, 1)
		if coordinate != 1:
			crossing.set_cell(6, coordinate, 1)
	var multiple: Dictionary = OpeningTraySupplier.new(config, 87).build(crossing, RoundGenerator.new(87, config))
	var multiple_lines := _check_opening_certificate(crossing, multiple, "交叉多线")
	_check(not multiple_lines.is_empty() and multiple_lines[0] >= 2 and int(multiple["diagnostics"].get("predicted_multiline_moves", 0)) >= 1, "能一手交叉清线时优先多线并提供完整后三块证书")
	var consecutive := BoardRules.new(8)
	for y in [0, 2, 4]:
		for x in range(5):
			consecutive.set_cell(x, y, 2)
	var chained: Dictionary = OpeningTraySupplier.new(config, 88).build(consecutive, RoundGenerator.new(88, config))
	var chained_lines := _check_opening_certificate(consecutive, chained, "连续清线")
	_check(chained_lines == [1, 1, 1] and int(chained["diagnostics"].get("predicted_consecutive_clear_pairs", 0)) == 2, "三条现成缺口优先真实三手连续清线路径")
	for initial_seed in [17, 49, 72]:
		var empty := BoardRules.new(8)
		var opening: Dictionary = OpeningTraySupplier.new(config, initial_seed).build(empty, RoundGenerator.new(initial_seed, config))
		var opening_lines := _check_opening_certificate(empty, opening, "空盘铺垫/%d" % initial_seed)
		var total := 0
		for count in opening_lines:
			total += count
		_check(total >= 1 and int(opening["diagnostics"].get("predicted_first_clear_step", 0)) in [2, 3], "默认自由空盘能以普通块在两至三手补线：%d" % initial_seed)
		_check(int(opening["diagnostics"]["evaluated_origins"]) <= int(opening["diagnostics"]["evaluation_budget"]), "开局搜索不超出声明预算：%d" % initial_seed)
		for piece: PieceData in opening["pieces"]:
			var in_pool := false
			for definition: ShapeDefinition in config.shape_pool:
				in_pool = in_pool or (piece.shape_id == definition.shape_id and piece.cells == definition.cells)
			_check(in_pool and piece.is_valid_for_config(config) and piece.cell_count() >= 3 and piece.targets.is_empty(), "普通开局只用原形状、原方向，不加入教学救援或收集标记")

func _test_opening_reproducibility_and_fallback() -> void:
	var config := GameRulesConfig.new()
	var original_cells: Array[Vector2i] = config.shape_pool[0].cells.duplicate()
	var empty := BoardRules.new(8)
	var first: Dictionary = OpeningTraySupplier.new(config, 89).build(empty, RoundGenerator.new(89, config))
	var second: Dictionary = OpeningTraySupplier.new(config, 89).build(empty, RoundGenerator.new(89, config))
	_check(first["solution"] == second["solution"] and first["diagnostics"]["predicted_clear_steps"] == second["diagnostics"]["predicted_clear_steps"], "相同种子重现相同完整证书与清线预测")
	for index in range(config.tray_count):
		_check(first["pieces"][index].shape_id == second["pieces"][index].shape_id and first["pieces"][index].cells == second["pieces"][index].cells, "相同种子重现相同托盘形状")
	var other_cells: Array[Vector2i] = first["pieces"][1].cells.duplicate()
	var independent_cells: Array[Vector2i] = second["pieces"][0].cells.duplicate()
	first["pieces"][0].cells.append(Vector2i(99, 99))
	first["solution"][0]["origin"] = Vector2i(-99, -99)
	_check(first["pieces"][1].cells == other_cells and second["pieces"][0].cells == independent_cells and second["solution"][0]["origin"] != Vector2i(-99, -99), "返回方块与证书各自深复制，不相互串改")
	_check(config.shape_pool[0].cells == original_cells and config.min_piece_cells == 3 and config.max_piece_cells == 5 and config.combo_miss_tolerance == 0, "供块与返回值修改不污染共享普通配置、池或断连规则")
	var limited = OpeningTraySupplier.new(config, 90)
	limited.evaluation_budget = 0
	var fallback: Dictionary = limited.build(empty, RoundGenerator.new(90, config))
	_check_opening_certificate(empty, fallback, "预算回退")
	_check(fallback["pieces"].size() == config.tray_count and bool(fallback["diagnostics"].get("budget_exhausted", false)) and not bool(fallback["diagnostics"].get("opening_assist", true)), "预算耗尽调用原生成器，不把搜索截断误判为无解")
	var restricted := GameRulesConfig.new()
	restricted.shape_pool = [config.shape_pool[0]]
	var restricted_result: Dictionary = OpeningTraySupplier.new(restricted, 91).build(empty, RoundGenerator.new(91, restricted))
	_check_opening_certificate(empty, restricted_result, "受限普通池")
	for piece: PieceData in restricted_result["pieces"]:
		_check(piece.shape_id == "line3" and piece.cells == original_cells, "自定义普通池保持原配置，不为消除擅自扩池或旋转")

func _check_opening_certificate(board: BoardRules, supplied: Dictionary, label: String) -> Array[int]:
	var pieces: Array[PieceData] = []
	pieces.assign(supplied["pieces"])
	var path: Array = supplied["solution"]
	var lines: Array[int] = []
	_check(pieces.size() == 3 and path.size() == pieces.size() and bool(supplied["diagnostics"].get("solution_certified", false)), label + "：整组三块带已认证路径")
	var replay := board.duplicate_board()
	var used: Dictionary = {}
	for step: Dictionary in path:
		var index := int(step.get("piece_index", -1))
		var valid_index := index >= 0 and index < pieces.size() and not used.has(index)
		_check(valid_index, label + "：证书每块恰好使用一次")
		if not valid_index:
			return lines
		var origin: Vector2i = step["origin"]
		var legal := replay.can_place(pieces[index], origin)
		_check(legal, label + "：证书每步真实合法")
		if not legal:
			return lines
		used[index] = true
		replay.place(pieces[index], origin)
		var clear := replay.clear_full_lines()
		lines.append(int(clear["rows"]) + int(clear["columns"]))
	if bool(supplied["diagnostics"].get("opening_assist", false)):
		_check(lines == supplied["diagnostics"]["predicted_clear_steps"], label + "：诊断预测与证书真实消除一致")
	return lines

func _same_board(first: BoardRules, second: BoardRules) -> bool:
	if first.size != second.size:
		return false
	for y in range(first.size):
		for x in range(first.size):
			if first.get_cell(x, y) != second.get_cell(x, y):
				return false
	return true

func _check_collection_sums(state: GameState, label: String) -> void:
	var total := 0
	var collected := 0
	var remaining := 0
	for kind in state.target_counts:
		total += int(state.target_counts[kind])
		collected += int(state.target_collected_counts[kind])
		remaining += int(state.target_remaining_counts[kind])
		_check(int(state.target_remaining_counts[kind]) >= 0 and int(state.target_collected_counts[kind]) <= int(state.target_counts[kind]), label + "：分类进度不越界")
	_check(total == state.target_total and collected == state.target_collected, label + "：分类总数与汇总守恒")
	_check(collected + remaining == total, label + "：剩余需求与已完成数守恒，不依赖物理标记数量")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + message)
