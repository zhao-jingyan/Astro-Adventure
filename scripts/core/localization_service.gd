extends Node

## 从 res://data/localization/*.json 加载 key → text 文本表。
##
## 当指定语言缺少 key 时回退到 zh_CN，再找不到时返回 key 本身。

const EventBusScript = preload("res://scripts/core/event_bus.gd")
const DEFAULT_DIRECTORY := "res://data/localization"
const FALLBACK_LOCALE := "zh_CN"

var event_bus: EventBusScript

var _directory := DEFAULT_DIRECTORY
var _translations: Dictionary = {}
var _locale := FALLBACK_LOCALE


func _init(start_event_bus: EventBusScript = null, start_directory: String = DEFAULT_DIRECTORY) -> void:
	event_bus = start_event_bus
	_directory = start_directory
	reload()


func _ready() -> void:
	if event_bus == null:
		call_deferred("_resolve_default_event_bus")


## 显式注入事件总线，便于无 autoload 测试。
func setup(start_event_bus: EventBusScript) -> void:
	event_bus = start_event_bus


func reload() -> bool:
	_translations.clear()
	var directory := DirAccess.open(_directory)
	if directory == null:
		push_error("无法打开本地化目录：%s" % _directory)
		return false

	var filenames := directory.get_files()
	filenames.sort()
	for filename: String in filenames:
		if not filename.ends_with(".json"):
			continue
		var locale := filename.get_basename()
		var path := _directory.path_join(filename)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			push_error("本地化文件不是 JSON 对象：%s" % path)
			continue

		var entries: Dictionary = {}
		for key: Variant in parsed:
			entries[str(key)] = str((parsed as Dictionary)[key])
		_translations[locale] = entries

	if _translations.is_empty():
		push_error("本地化目录中没有可用文本：%s" % _directory)
	return not _translations.is_empty()


func set_locale(next_locale: String) -> bool:
	var normalized := next_locale.strip_edges()
	if not _translations.has(normalized):
		return false
	if normalized == _locale:
		return true

	_locale = normalized
	if event_bus != null:
		event_bus.locale_changed.emit(_locale)
	return true


func get_locale() -> String:
	return _locale


func get_available_locales() -> PackedStringArray:
	var locales := PackedStringArray(_translations.keys())
	locales.sort()
	return locales


## 翻译并替换 {name} 形式的参数。
func translate(key: String, params: Dictionary = {}, locale: String = "") -> String:
	var requested_locale := locale.strip_edges()
	if requested_locale.is_empty():
		requested_locale = _locale

	var translated := _lookup(requested_locale, key)
	if translated.is_empty():
		translated = _lookup(FALLBACK_LOCALE, key)
	if translated.is_empty():
		return key

	for parameter_name: Variant in params:
		translated = translated.replace(
			"{%s}" % str(parameter_name),
			str(params[parameter_name])
		)
	return translated


func has_key(key: String, locale: String = "") -> bool:
	var requested_locale := locale.strip_edges()
	if requested_locale.is_empty():
		requested_locale = _locale
	return not _lookup(requested_locale, key).is_empty()


func _lookup(locale: String, key: String) -> String:
	var entries: Variant = _translations.get(locale, {})
	if not (entries is Dictionary):
		return ""
	var translated: Variant = (entries as Dictionary).get(key)
	return "" if translated == null else str(translated)


func _find_or_create_event_bus() -> EventBusScript:
	var existing := get_node_or_null("/root/GameEvents")
	if existing is EventBusScript:
		return existing
	if not is_inside_tree():
		return null
	var fallback := EventBusScript.new()
	fallback.name = "GameEvents"
	get_tree().root.add_child(fallback)
	return fallback


func _resolve_default_event_bus() -> void:
	if event_bus == null:
		event_bus = _find_or_create_event_bus()
