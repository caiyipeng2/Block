extends RefCounted

const L10n := preload("res://scripts/localization/game_locale.gd")

## All adventure difficulty and quota values come from this table. A malformed
## table is rejected as a whole; callers must surface errors instead of silently
## substituting a level-number formula.
const PATH := "res://config/adventure_levels.csv"
const LEVEL_COUNT := 96
const COLUMNS := [
	"level_id", "objective_type", "target_score", "blue_diamond", "gold_gem",
	"yellow_star", "red_star", "difficulty", "template_id", "mirror",
	"initial_fill", "initial_markers", "seed", "difficulty_label", "note",
	"retry_assist_step", "retry_assist_max",
	"shape_profile", "extra_blocks", "near_win_lines", "randomness",
]
const SHAPE_PROFILES := ["friendly", "mixed", "pressure"]
const OPTIONAL_DEFAULTS := {
	"retry_assist_step": "20", "retry_assist_max": "60",
	"shape_profile": "mixed", "extra_blocks": "0", "near_win_lines": "0", "randomness": "50",
}
const OPTIONAL_NUMBER_COLUMNS := ["retry_assist_step", "retry_assist_max", "randomness"]
const TARGET_COLUMNS := ["blue_diamond", "gold_gem", "yellow_star", "red_star"]
const TEMPLATE_CAPACITIES := {"wings": 24, "heart": 22, "ring": 20, "steps": 20, "butterfly": 22}
const MAX_VISIBLE_ERRORS := 12

static var _loaded := false
static var _levels: Dictionary = {}
static var _errors := PackedStringArray()

## Avoid Script.reload(): the preloaded class is itself a Script resource.
static func reload_table() -> PackedStringArray:
	_loaded = true
	_levels = {}
	_errors = PackedStringArray()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		_errors.append(L10n.t("%s：无法读取关卡配置（文件错误码 %d）") % [PATH, FileAccess.get_open_error()])
		return _errors.duplicate()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if not _is_utf8(bytes):
		_errors.append(L10n.t("%s：文件不是 UTF-8 编码。请在 Excel/WPS 中另存为 CSV UTF-8（逗号分隔），不要选择普通 CSV/ANSI。") % PATH)
		return _errors.duplicate()
	var parsed := parse_text(bytes.get_string_from_utf8(), PATH)
	_levels = parsed["levels"]
	_errors = parsed["errors"]
	return _errors.duplicate()

static func errors() -> PackedStringArray:
	if not _loaded:
		reload_table()
	return _errors.duplicate()

static func level(level_id: int) -> Dictionary:
	if not _loaded:
		reload_table()
	var row: Dictionary = _levels.get(level_id, {})
	return row.duplicate(true)

## Check bytes before decoding so legacy ANSI/GBK edits produce one useful
## configuration error instead of Unicode decode errors and garbled labels.
static func _is_utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	while index < bytes.size():
		var lead := int(bytes[index])
		if lead <= 0x7f:
			index += 1
			continue
		var width := 0
		var second_min := 0x80
		var second_max := 0xbf
		if lead >= 0xc2 and lead <= 0xdf:
			width = 2
		elif lead >= 0xe0 and lead <= 0xef:
			width = 3
			if lead == 0xe0:
				second_min = 0xa0
			elif lead == 0xed:
				second_max = 0x9f
		elif lead >= 0xf0 and lead <= 0xf4:
			width = 4
			if lead == 0xf0:
				second_min = 0x90
			elif lead == 0xf4:
				second_max = 0x8f
		else:
			return false
		if index + width > bytes.size() or bytes[index + 1] < second_min or bytes[index + 1] > second_max:
			return false
		for offset in range(2, width):
			if bytes[index + offset] < 0x80 or bytes[index + offset] > 0xbf:
				return false
		index += width
	return true

## Parse supplied CSV without opening the level file, mutating the cache, or
## modifying game rules. UTF-8 BOM, CRLF, quoted commas, and escaped quotes work.
## Embedded newlines in a quoted field are intentionally not supported.
static func parse_text(text: String, source_label: String = "内存配置") -> Dictionary:
	var issues := PackedStringArray()
	var levels: Dictionary = {}
	var seen_ids: Dictionary = {}
	var headers := PackedStringArray()
	var header_line := 0
	var data_rows := 0
	var content := text.trim_prefix("\ufeff")
	var lines := content.split("\n", true)
	for index in range(lines.size()):
		var line_number := index + 1
		var raw_line := lines[index].trim_suffix("\r")
		if raw_line.strip_edges().is_empty():
			continue
		var parsed_line := _parse_csv_record(raw_line)
		if not str(parsed_line["error"]).is_empty():
			_issue(issues, source_label, line_number, "CSV", str(parsed_line["error"]))
			if header_line == 0:
				return {"levels": {}, "errors": _bounded_errors(issues, source_label)}
			data_rows += 1
			continue
		var fields: PackedStringArray = parsed_line["fields"]
		if header_line == 0:
			header_line = line_number
			headers = fields
			_validate_headers(headers, issues, source_label, line_number)
			if not issues.is_empty():
				return {"levels": {}, "errors": _bounded_errors(issues, source_label)}
			continue
		data_rows += 1
		if fields.size() != headers.size():
			_issue(issues, source_label, line_number, "CSV", "字段数为 %d，应为 %d；请检查逗号和双引号", [fields.size(), headers.size()])
			continue
		var values: Dictionary = {}
		for column_index in range(headers.size()):
			values[headers[column_index]] = fields[column_index]
		var issue_count := issues.size()
		var row := _validate_row(values, issues, source_label, line_number)
		var level_id: Variant = row.get("level_id")
		if level_id != null:
			if seen_ids.has(level_id):
				_issue(issues, source_label, line_number, "level_id", "关卡 %d 重复，首次出现于 CSV 行 %d", [level_id, seen_ids[level_id]])
			else:
				seen_ids[level_id] = line_number
		if issues.size() == issue_count and level_id != null:
			levels[level_id] = row
	if header_line == 0:
		_issue(issues, source_label, 1, "表头", "配置文件为空，需要表头和 96 个关卡")
	else:
		if data_rows != LEVEL_COUNT:
			_issue(issues, source_label, header_line, "level_id", "需要 %d 行关卡配置，实际为 %d 行", [LEVEL_COUNT, data_rows])
		var missing := PackedStringArray()
		for level_id in range(1, LEVEL_COUNT + 1):
			if not seen_ids.has(level_id):
				missing.append(str(level_id))
		if not missing.is_empty():
			_issue(issues, source_label, header_line, "level_id", "缺少关卡：%s", [", ".join(missing)])
	return {
		"levels": levels if issues.is_empty() else {},
		"errors": _bounded_errors(issues, source_label),
	}

static func _validate_headers(headers: PackedStringArray, issues: PackedStringArray, source: String, line: int) -> void:
	var seen: Dictionary = {}
	for header in headers:
		if seen.has(header):
			_issue(issues, source, line, header, "表头重复")
		seen[header] = true
		if not COLUMNS.has(header):
			_issue(issues, source, line, header, "未知列名；列名必须与配置说明一致且不能包含额外空格")
	for column in COLUMNS:
		if not seen.has(column) and not OPTIONAL_DEFAULTS.has(column):
			_issue(issues, source, line, column, "缺少必需列")

static func _validate_row(values: Dictionary, issues: PackedStringArray, source: String, line: int) -> Dictionary:
	var row: Dictionary = {}
	row["level_id"] = _integer(values["level_id"], 1, LEVEL_COUNT, "level_id", issues, source, line)
	row["target_score"] = _integer(values["target_score"], 0, 1000000, "target_score", issues, source, line)
	for column in TARGET_COLUMNS:
		row[column] = _integer(values[column], 0, 999, column, issues, source, line)
	row["difficulty"] = _number(values["difficulty"], 0.0, 100.0, "difficulty", issues, source, line)
	for column: String in OPTIONAL_NUMBER_COLUMNS:
		row[column] = _number(str(values.get(column, OPTIONAL_DEFAULTS[column])), 0.0, 100.0, column, issues, source, line)
	row["shape_profile"] = str(values.get("shape_profile", OPTIONAL_DEFAULTS["shape_profile"])).strip_edges()
	if not SHAPE_PROFILES.has(row["shape_profile"]):
		_issue(issues, source, line, "shape_profile", "仅支持 friendly、mixed 或 pressure")
	row["extra_blocks"] = _integer(str(values.get("extra_blocks", OPTIONAL_DEFAULTS["extra_blocks"])), 0, 12, "extra_blocks", issues, source, line)
	row["near_win_lines"] = _integer(str(values.get("near_win_lines", OPTIONAL_DEFAULTS["near_win_lines"])), 0, 3, "near_win_lines", issues, source, line)
	row["mirror"] = _integer(values["mirror"], 0, 1, "mirror", issues, source, line)
	row["initial_fill"] = _integer(values["initial_fill"], 0, 63, "initial_fill", issues, source, line)
	row["initial_markers"] = _integer(values["initial_markers"], 0, 64, "initial_markers", issues, source, line)
	row["seed"] = _integer(values["seed"], 1, 2147483647, "seed", issues, source, line)
	row["objective_type"] = str(values["objective_type"]).strip_edges()
	row["template_id"] = str(values["template_id"]).strip_edges()
	row["difficulty_label"] = str(values["difficulty_label"]).strip_edges()
	row["note"] = str(values["note"])
	if str(row["difficulty_label"]).is_empty():
		_issue(issues, source, line, "difficulty_label", "难度名称不能为空，例如：入门、挑战")
	var objective: String = row["objective_type"]
	if objective != "score" and objective != "collect":
		_issue(issues, source, line, "objective_type", "仅支持 score（分数）或 collect（收集）")
	var level_id: Variant = row["level_id"]
	if level_id != null:
		var expected := "score" if int(level_id) <= 2 else "collect"
		if objective != expected:
			_issue(issues, source, line, "objective_type", "第 1–2 关必须为 score，第 3–96 关必须为 collect")
	if objective == "score":
		_validate_score_row(row, issues, source, line)
	elif objective == "collect":
		_validate_collect_row(row, issues, source, line)
	return row

static func _validate_score_row(row: Dictionary, issues: PackedStringArray, source: String, line: int) -> void:
	if row["target_score"] != null and int(row["target_score"]) < 1:
		_issue(issues, source, line, "target_score", "分数关目标须为 1–1000000")
	for column in TARGET_COLUMNS:
		_require_zero(row, column, issues, source, line, "分数关不配置收集数量")
	if row["template_id"] != "random":
		_issue(issues, source, line, "template_id", "分数关须使用 random")
	_require_zero(row, "mirror", issues, source, line, "分数关镜像须为 0")
	_require_zero(row, "initial_markers", issues, source, line, "分数关初始标记须为 0")
	_require_zero(row, "extra_blocks", issues, source, line, "分数教学关不使用额外初始方块，须为 0")
	_require_zero(row, "near_win_lines", issues, source, line, "分数教学关不使用近胜线，须为 0")
	if row["shape_profile"] != "mixed":
		_issue(issues, source, line, "shape_profile", "分数教学关使用独立教学供块，须为 mixed")
	if row["randomness"] != null and not is_equal_approx(float(row["randomness"]), 50.0):
		_issue(issues, source, line, "randomness", "分数教学关使用独立教学供块，随机度须为 50")
	if row["initial_fill"] != null and int(row["initial_fill"]) < 1:
		_issue(issues, source, line, "initial_fill", "分数关初始占格数须为 1–63")

static func _validate_collect_row(row: Dictionary, issues: PackedStringArray, source: String, line: int) -> void:
	_require_zero(row, "target_score", issues, source, line, "收集关目标分数须为 0")
	_require_zero(row, "initial_fill", issues, source, line, "收集关占格由模板决定，initial_fill 须为 0")
	var total := 0
	var counts_valid := true
	for column in TARGET_COLUMNS:
		if row[column] == null:
			counts_valid = false
		else:
			total += int(row[column])
	if counts_valid and total == 0:
		_issue(issues, source, line, "blue_diamond/gold_gem/yellow_star/red_star", "收集关至少一种目标数量须大于 0")
	var template_id: String = row["template_id"]
	if not TEMPLATE_CAPACITIES.has(template_id):
		_issue(issues, source, line, "template_id", "收集关仅支持 wings、heart、ring、steps、butterfly")
	elif row["initial_markers"] != null and int(row["initial_markers"]) > int(TEMPLATE_CAPACITIES[template_id]):
		_issue(issues, source, line, "initial_markers", "%s 模板最多有 %d 个占格，初始标记不能超过该值", [template_id, TEMPLATE_CAPACITIES[template_id]])
	if row["near_win_lines"] != null and row["extra_blocks"] != null and int(row["near_win_lines"]) > int(row["extra_blocks"]):
		_issue(issues, source, line, "near_win_lines", "近胜线需要额外初始方块支撑，不能大于 extra_blocks")

static func _require_zero(row: Dictionary, column: String, issues: PackedStringArray, source: String, line: int, reason: String) -> void:
	if row[column] != null and int(row[column]) != 0:
		_issue(issues, source, line, column, reason)

static func _integer(raw: String, minimum: int, maximum: int, column: String, issues: PackedStringArray, source: String, line: int) -> Variant:
	var text := raw.strip_edges()
	# Limit significant decimal digits before conversion, so huge CSV numbers
	# cannot overflow a 64-bit integer and wrap into an apparently valid value.
	var digits := text.trim_prefix("+").trim_prefix("-").lstrip("0")
	if text.is_empty() or not text.is_valid_int() or digits.length() > 10:
		_issue(issues, source, line, column, "须填写 %d–%d 的整数，不能留空或使用小数", [minimum, maximum])
		return null
	var value := text.to_int()
	if value < minimum or value > maximum:
		_issue(issues, source, line, column, "数值 %s 超出范围 %d–%d", [text, minimum, maximum])
		return null
	return value

static func _number(raw: String, minimum: float, maximum: float, column: String, issues: PackedStringArray, source: String, line: int) -> Variant:
	var text := raw.strip_edges()
	if text.is_empty() or not text.is_valid_float():
		_issue(issues, source, line, column, "须填写 %s–%s 的有限数字", [minimum, maximum])
		return null
	var value := text.to_float()
	if not is_finite(value) or value < minimum or value > maximum:
		_issue(issues, source, line, column, "数值 %s 超出有限范围 %s–%s", [text, minimum, maximum])
		return null
	return value

static func _parse_csv_record(record: String) -> Dictionary:
	var fields := PackedStringArray()
	var field := ""
	var quoted := false
	var after_quote := false
	var index := 0
	while index < record.length():
		var character := record.substr(index, 1)
		if character == "\r":
			return {"fields": fields, "error": "字段内不能换行；请将说明写在同一行"}
		if quoted:
			if character == "\"":
				if index + 1 < record.length() and record.substr(index + 1, 1) == "\"":
					field += "\""
					index += 2
					continue
				quoted = false
				after_quote = true
			else:
				field += character
		elif after_quote:
			if character == ",":
				fields.append(field)
				field = ""
				after_quote = false
			elif character != " " and character != "\t":
				return {"fields": fields, "error": "闭合双引号后只能出现逗号或行尾"}
		elif character == ",":
			fields.append(field)
			field = ""
		elif character == "\"":
			if not field.strip_edges().is_empty():
				return {"fields": fields, "error": "未加引号的字段中出现双引号；请用双引号包围字段并将内部双引号写成两个"}
			field = ""
			quoted = true
		else:
			field += character
		index += 1
	if quoted:
		return {"fields": fields, "error": "双引号未闭合；字段内不能换行"}
	fields.append(field)
	return {"fields": fields, "error": ""}

static func _issue(issues: PackedStringArray, source: String, line: int, column: String, reason: String, arguments: Array = []) -> void:
	var message := L10n.t(reason)
	if not arguments.is_empty():
		message = message % arguments
	var source_name := L10n.t("内存配置") if source == "内存配置" else source
	var column_name := L10n.t("表头") if column == "表头" else column
	issues.append(L10n.t("%s，CSV 行 %d，列「%s」：%s") % [source_name, line, column_name, message])

static func _bounded_errors(issues: PackedStringArray, source: String) -> PackedStringArray:
	var result := PackedStringArray()
	for index in range(mini(issues.size(), MAX_VISIBLE_ERRORS)):
		result.append(issues[index])
	if issues.size() > MAX_VISIBLE_ERRORS:
		var source_name := L10n.t("内存配置") if source == "内存配置" else source
		result.append(L10n.t("%s：另有 %d 项配置错误未列出，请修正后重新读取") % [source_name, issues.size() - MAX_VISIBLE_ERRORS])
	return result
