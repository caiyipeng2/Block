extends RefCounted

## Register source-key translations once; the engine broadcasts locale changes.
const CATALOG_PATH := "res://assets/localization/messages.json"
const SUPPORTED_CODES := ["zh_CN", "en", "fr"]
const LANGUAGE_NAMES := ["中文", "English", "Français"]

static var _initialized := false
static var _messages: Dictionary = {}
static var _translations: Array[Translation] = []
static var _missing: Dictionary = {}

static func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if parsed is Dictionary:
		_messages = parsed
	else:
		push_error("Invalid localization catalog: " + CATALOG_PATH)
	for code: String in SUPPORTED_CODES:
		var translation := Translation.new()
		translation.locale = code
		for source: String in _messages:
			var values: Dictionary = _messages[source]
			translation.add_message(source, str(values.get(code, source)))
		TranslationServer.add_translation(translation)
		_translations.append(translation)
	TranslationServer.set_locale("zh_CN")

static func normalize(code: String) -> String:
	var normalized := code.replace("-", "_").to_lower()
	if normalized.begins_with("en"):
		return "en"
	if normalized.begins_with("fr"):
		return "fr"
	return "zh_CN"

static func set_language(code: String) -> void:
	initialize()
	TranslationServer.set_locale(normalize(code))

static func language() -> String:
	return normalize(TranslationServer.get_locale())

static func t(source: String) -> String:
	initialize()
	if not _messages.has(source) and not source.is_empty():
		_missing[source] = true
	return str(TranslationServer.translate(source))

static func missing_keys() -> PackedStringArray:
	return PackedStringArray(_missing.keys())

static func clear_missing_keys() -> void:
	_missing.clear()

static func fitted_size(font: Font, value: String, width: float, maximum: int, minimum: int = 10) -> int:
	var result := maxi(maximum, minimum)
	while result > minimum and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, result).x > maxf(width, 1.0):
		result -= 1
	return result

static func fit_button(button: Button, maximum: int, minimum: int = 10, reserved_width: float = 0.0) -> void:
	button.clip_text = true
	if button.size.x <= 0.0:
		return
	var style := button.get_theme_stylebox("normal")
	var width := button.size.x - style.get_content_margin(SIDE_LEFT) - style.get_content_margin(SIDE_RIGHT) - reserved_width
	button.add_theme_font_size_override("font_size", fitted_size(button.get_theme_font("font"), button.text, width, maximum, minimum))
