extends SceneTree

var _failures: int = 0
var _tests: int = 0

func _initialize() -> void:
	for test: Callable in [
		_test_empty_identity,
		_test_geometry_duplicate_shapes,
		_test_exact_count_and_cap,
		_test_node_budget_is_not_unsolvability,
		_test_arbitrary_order_and_clear,
		_test_ranked_seed_reproducibility,
		_test_default_seed_behavior,
		_test_certified_fallback,
		_test_constructive_fallback_survives_rating_budget,
	]:
		_tests += 1
		test.call()
	print("ROUND DIFFICULTY TESTS: %d cases, %d failures" % [_tests, _failures])
	quit(0 if _failures == 0 else 1)

func _test_empty_identity() -> void:
	var generator := RoundGenerator.new(1)
	var pieces: Array[PieceData] = []
	_expect_equal(generator.count_solutions(BoardRules.new(8), pieces), {
		"count": 1, "exact": true, "truncated": false, "nodes": 0,
	}, "the empty tray has exactly one empty placement sequence")

func _test_geometry_duplicate_shapes() -> void:
	var generator := RoundGenerator.new(1)
	var pieces: Array[PieceData] = [
		PieceData.new(Vector2i.ZERO, [Vector2i.ZERO], "first"),
		PieceData.new(Vector2i.ZERO, [Vector2i(3, -2)], "second"),
	]
	var result := generator.count_solutions(BoardRules.new(1), pieces)
	_expect_equal(result["count"], 1, "different ids and translated coordinates do not multiply identical-shape index exchanges")
	_expect(result["exact"], "duplicate shapes can still be certified uniquely solvable")
	_expect_equal(generator.find_solution(BoardRules.new(1), pieces).size(), 2, "each identical piece is consumed after its placement and clear")

func _test_exact_count_and_cap() -> void:
	var generator := RoundGenerator.new(1)
	var pieces: Array[PieceData] = [_single_cell()]
	var exact := generator.count_solutions(BoardRules.new(2), pieces, 8, 100)
	_expect_equal(exact["count"], 4, "a single cell has four legal placements on an empty 2x2 board")
	_expect(exact["exact"] and not exact["truncated"], "completed enumeration reports an exact count")
	var capped := generator.count_solutions(BoardRules.new(2), pieces, 2, 100)
	_expect_equal(capped["count"], 2, "the count stops at the configured cap")
	_expect(not capped["exact"] and not capped["truncated"], "a count cap is a lower bound, distinct from a node-budget truncation")
	var one := generator.count_solutions(BoardRules.new(2), pieces, 1, 100)
	_expect_equal(one["count"], 1, "cap one stops at the first witness")
	_expect(not one["exact"], "a single capped witness must never be reported as unique")

func _test_node_budget_is_not_unsolvability() -> void:
	var generator := RoundGenerator.new(1)
	var pieces: Array[PieceData] = [_single_cell()]
	var board := BoardRules.new(2)
	var unknown := generator.count_solutions(board, pieces, 8, 1)
	_expect_equal(unknown["count"], 0, "one node may expire before a complete path is visited")
	_expect(not unknown["exact"] and unknown["truncated"], "zero after budget exhaustion is explicitly unknown")
	_expect_equal(unknown["nodes"], 1, "the rating traversal respects its node budget")
	_expect(generator.has_any_solution(board, pieces), "the uncapped solver still certifies the playable tray")
	var zero_budget := generator.count_solutions(board, pieces, 8, 0)
	_expect_equal(zero_budget["nodes"], 0, "a zero rating budget does no traversal")
	_expect(zero_budget["truncated"] and not zero_budget["exact"], "a zero budget cannot establish unsolvability")

func _test_arbitrary_order_and_clear() -> void:
	var board := BoardRules.new(3)
	board.fill_all()
	for hole: Vector2i in [Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2)]:
		board.set_cell(hole.x, hole.y, -1)
	var pieces: Array[PieceData] = [_line_three(), _single_cell()]
	var generator := RoundGenerator.new(1)
	var witness := generator.find_solution(board, pieces)
	_expect_equal(witness.size(), 2, "placing the second tray piece can clear space for the first")
	if not witness.is_empty():
		_expect_equal(witness[0]["piece_index"], 1, "the solver is not constrained to tray order")
	var result := generator.count_solutions(board, pieces, 8, 100)
	_expect_equal(result["count"], 3, "each of the three single-cell placements opens a line for the remaining piece")
	_expect(result["exact"], "arbitrary-order enumeration applies row and column clears")

func _test_ranked_seed_reproducibility() -> void:
	var first := RoundGenerator.new(20261014)
	var second := RoundGenerator.new(20261014)
	for generator: RoundGenerator in [first, second]:
		generator.candidate_samples = 4
		generator.solution_count_cap = 8
		generator.solution_node_budget = 200
	var board := BoardRules.new(8)
	for round_index in range(2):
		var a := first.generate_solvable_round(board)
		var b := second.generate_solvable_round(board)
		_expect_equal(_tray_key(a), _tray_key(b), "ranked selection reproduces shapes from the same seed")
		_expect_equal(first.last_solution, second.last_solution, "ranked selection reproduces the complete witness")
		_expect_equal(first.last_diagnostics["solution_count"], second.last_diagnostics["solution_count"], "difficulty counts reproduce with the same budget")
		_expect_equal(first.last_diagnostics["round"], round_index, "one generation advances the round counter once")
		_expect_equal(first.last_diagnostics["random_sampled_candidates"], 4, "ranked generation compares the requested distinct solvable random samples")
		_expect(first.has_any_solution(board, a), "ranked output retains a complete uncapped solution")

func _test_default_seed_behavior() -> void:
	var generator := RoundGenerator.new(19)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var config := GameRulesConfig.new()
	var board := BoardRules.new(8)
	for round_index in range(2):
		var expected: Array[PieceData] = []
		for _index in range(config.tray_count):
			var definition: ShapeDefinition = config.shape_pool[rng.randi_range(0, config.shape_pool.size() - 1)]
			expected.append(definition.to_piece())
		var actual := generator.generate_solvable_round(board)
		_expect_equal(_tray_key(actual), _tray_key(expected), "default sampling keeps the original RNG sequence and first-solvable behavior")
		_expect_equal(generator.last_diagnostics["attempts"], 1, "an empty default board returns the first solvable random group")
		_expect_equal(generator.last_diagnostics["solution_count"], -1, "default endless modes do not perform difficulty enumeration")
		_expect_equal(generator.last_diagnostics["round"], round_index, "default generation advances its round counter once")

func _test_certified_fallback() -> void:
	var config := GameRulesConfig.new()
	config.tray_count = 1
	var generator := RoundGenerator.new(1, config)
	generator.max_attempts = 0
	generator.candidate_samples = 4
	var board := BoardRules.new(3)
	board.fill_all()
	for x in range(3):
		board.set_cell(x, 0, -1)
	var certified: Array[PieceData] = [_line_three()]
	var result := generator.generate_solvable_round(board, certified)
	_expect_equal(_tray_key(result), _tray_key(certified), "a supplied candidate is independently certified and kept when random attempts are disabled")
	_expect_equal(generator.last_diagnostics["reason"], "certified_fallback", "diagnostics identify the supplied certified fallback")
	_expect_equal(generator.last_diagnostics["solution_count"], 1, "the single open row gives exactly one complete path")
	_expect(generator.last_diagnostics["solution_count_exact"], "a unique claim requires exhaustive enumeration")
	_expect_equal(generator.last_diagnostics["sampled_candidates"], 1, "the fallback is included in the number of rated candidates")
	_expect_equal(generator.last_solution.size(), 1, "fallback output stores its complete witness")

func _test_constructive_fallback_survives_rating_budget() -> void:
	var generator := RoundGenerator.new(1)
	generator.max_attempts = 0
	generator.candidate_samples = 4
	generator.solution_node_budget = 0
	var board := BoardRules.new(8)
	var result := generator.generate_solvable_round(board)
	_expect_equal(result.size(), 3, "constructive generation remains available when random generation is disabled")
	_expect_equal(generator.last_diagnostics["reason"], "constructive_fallback", "diagnostics retain the constructive fallback reason")
	_expect(generator.last_diagnostics["truncated"], "the disabled difficulty budget is reported as truncated")
	_expect(not generator.last_diagnostics["solution_count_exact"], "an unknown count is never labeled unique")
	_expect_equal(generator.last_solution.size(), 3, "the uncapped witness is retained despite an unknown difficulty count")
	_expect(generator.has_any_solution(board, result), "a rating cutoff cannot make a playable group fail generation")

func _single_cell() -> PieceData:
	return PieceData.new(Vector2i.ZERO, [Vector2i.ZERO], "single")

func _line_three() -> PieceData:
	return PieceData.new(Vector2i.ZERO, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "line3")

func _tray_key(pieces: Array[PieceData]) -> Array:
	var result: Array = []
	for piece in pieces:
		result.append(piece.cells.duplicate())
	return result

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s; actual=%s expected=%s" % [message, actual, expected])
