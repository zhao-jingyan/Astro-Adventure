extends Node

## 数据目录：统一加载 Resource，玩法层只按稳定 id 查询内容。

const DEFAULT_DIRECTORIES := {
	"levels": "res://data/levels",
	"planets": "res://data/planets",
	"enemies": "res://data/enemies",
	"relics": "res://data/relics",
	"achievements": "res://data/achievements",
}

var _content: Dictionary = {}
var _directories: Dictionary = DEFAULT_DIRECTORIES.duplicate(true)
var _loaded := false


func _ready() -> void:
	load_all()


## 可覆盖目录进行隔离测试；正常游戏启动使用默认 res://data 布局。
func configure_directories(directories: Dictionary) -> void:
	_directories = DEFAULT_DIRECTORIES.duplicate(true)
	for content_type: Variant in directories:
		_directories[content_type] = str(directories[content_type])
	_loaded = false


func load_all() -> void:
	_content.clear()
	for content_type: String in _directories:
		var directory_path := str(_directories[content_type])
		var entries := _load_resource_directory(directory_path)
		_content[content_type] = entries
	_loaded = true


func reload() -> void:
	load_all()


func is_loaded() -> bool:
	return _loaded


func has(content_type: StringName, content_id: StringName) -> bool:
	return _entries(content_type).has(content_id)


func get_definition(content_type: StringName, content_id: StringName) -> Resource:
	return _entries(content_type).get(content_id)


func get_level(level_id: StringName) -> Resource:
	return get_definition(&"levels", level_id)


func get_planet(planet_id: StringName) -> Resource:
	return get_definition(&"planets", planet_id)


func get_enemy_species(species_id: StringName) -> Resource:
	return get_definition(&"enemies", species_id)


func get_relic(relic_id: StringName) -> Resource:
	return get_definition(&"relics", relic_id)


func get_achievement(achievement_id: StringName) -> Resource:
	return get_definition(&"achievements", achievement_id)


func get_levels() -> Array[Resource]:
	return _sorted_resources(&"levels")


func get_planets() -> Array[Resource]:
	return _sorted_resources(&"planets")


func get_enemy_species_all() -> Array[Resource]:
	return _sorted_resources(&"enemies")


func get_relics() -> Array[Resource]:
	return _sorted_resources(&"relics")


func get_achievements() -> Array[Resource]:
	return _sorted_resources(&"achievements")


func get_level_ids() -> Array[StringName]:
	return _sorted_ids(&"levels")


func get_manifest() -> Dictionary:
	var manifest := {}
	for content_type: String in _content:
		manifest[content_type] = _entries(content_type).size()
	return manifest


## 校验内容字段与跨资源引用；返回空数组表示内容目录完整。
func validate_all() -> PackedStringArray:
	var errors := PackedStringArray()
	for content_type: StringName in _directories:
		for content_id: StringName in _entries(content_type):
			var definition := get_definition(content_type, content_id)
			if definition.has_method("validate"):
				for error: Variant in definition.call("validate"):
					errors.append("[%s/%s] %s" % [content_type, content_id, str(error)])

	for level: Resource in get_levels():
		var planet_id := StringName(str(level.get("planet_id")).strip_edges())
		if planet_id.is_empty():
			errors.append("[level/%s] planet_id 为空" % level.get("id"))
		elif not has(&"planets", planet_id):
			errors.append("[level/%s] 星球不存在：%s" % [level.get("id"), planet_id])

		var spawn_table: Variant = level.get("enemy_spawn_table")
		if spawn_table is Array:
			for entry: Variant in spawn_table:
				if not (entry is Dictionary):
					continue
				var species_id := StringName(str(
					entry.get("enemy_id", entry.get("species_id", ""))
				).strip_edges())
				if not species_id.is_empty() and not has(&"enemies", species_id):
					errors.append("[level/%s] 敌人物种不存在：%s" % [level.get("id"), species_id])

	return errors


func _entries(content_type: StringName) -> Dictionary:
	return _content.get(content_type, {})


func _sorted_resources(content_type: StringName) -> Array[Resource]:
	var result: Array[Resource] = []
	for content_id: StringName in _sorted_ids(content_type):
		result.append(get_definition(content_type, content_id))
	return result


func _sorted_ids(content_type: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for content_id: StringName in _entries(content_type):
		ids.append(content_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
	return ids


func _load_resource_directory(directory_path: String) -> Dictionary:
	var resources: Dictionary = {}
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return resources

	var filenames := directory.get_files()
	filenames.sort()
	for filename: String in filenames:
		if not filename.ends_with(".tres") and not filename.ends_with(".res"):
			continue
		var resource_path := directory_path.path_join(filename)
		var definition := load(resource_path) as Resource
		if definition == null:
			push_warning("内容资源加载失败：%s" % resource_path)
			continue
		if not ("id" in definition):
			push_warning("内容资源缺少 id：%s" % resource_path)
			continue
		var content_id := StringName(str(definition.get("id")).strip_edges())
		if content_id.is_empty():
			push_warning("内容资源 id 为空：%s" % resource_path)
			continue
		if resources.has(content_id):
			push_warning("内容 id 重复：%s (%s)" % [content_id, resource_path])
			continue
		resources[content_id] = definition
	return resources
