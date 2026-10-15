extends SceneTree

const ModeCatalog = preload("res://scripts/modes/mode_catalog.gd")

## Maintained coverage; normal delivery compiles this script without running it.
var failures := 0

func _initialize() -> void:
	_test_score_modes()
	_test_tutorial_adaptation()
	_test_collection_progress()
	_test_crossing_collection()
	_test_streamed_collection()
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
