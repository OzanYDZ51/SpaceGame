class_name LocaleSystem
extends Node

# =============================================================================
# Locale — i18n autoload singleton
# Loads flat JSON dictionaries, provides t(key) lookup with French fallback.
# Persists language choice in user://settings.cfg [general] language.
# =============================================================================

signal language_changed(lang_code: String)

const LOCALE_DIR: String = "res://data/locale/"
const SETTINGS_PATH: String = "user://settings.cfg"

const SUPPORTED_LANGUAGES: Array[Dictionary] = [
	{"code": "fr", "label": "Français"},
	{"code": "en", "label": "English"},
	{"code": "tr", "label": "Türkçe"},
]

var _current_lang: String = "fr"
var _strings: Dictionary = {}
var _fallback: Dictionary = {}


func _ready() -> void:
	_fallback = _load_json("fr")
	var saved_lang: String = _load_saved_language()
	if saved_lang != "" and saved_lang != "fr":
		_strings = _load_json(saved_lang)
		_current_lang = saved_lang
	else:
		_strings = _fallback
		_current_lang = "fr"


func t(key: String) -> String:
	var val = _strings.get(key)
	if val is String:
		return val
	val = _fallback.get(key)
	if val is String:
		return val
	push_warning("Locale: missing key '%s'" % key)
	return key


func set_language(code: String) -> void:
	if code == _current_lang:
		return
	if code == "fr":
		_strings = _fallback
	else:
		_strings = _load_json(code)
	_current_lang = code
	_save_language(code)
	language_changed.emit(code)


func get_language() -> String:
	return _current_lang


func get_language_labels() -> PackedStringArray:
	var labels: PackedStringArray = []
	for entry in SUPPORTED_LANGUAGES:
		labels.append(entry["label"])
	return labels


func get_language_index() -> int:
	for i in SUPPORTED_LANGUAGES.size():
		if SUPPORTED_LANGUAGES[i]["code"] == _current_lang:
			return i
	return 0


func _load_json(lang_code: String) -> Dictionary:
	var path: String = LOCALE_DIR + lang_code + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Locale: cannot open %s" % path)
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("Locale: invalid JSON in %s" % path)
	return {}


func _load_saved_language() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ""
	return cfg.get_value("general", "language", "")


func _save_language(code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # Load existing to preserve other settings
	cfg.set_value("general", "language", code)
	cfg.save(SETTINGS_PATH)
