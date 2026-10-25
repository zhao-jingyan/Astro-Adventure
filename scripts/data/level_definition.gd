@tool
class_name LevelDefinition
extends Resource

## 星球区域关卡定义。
## 敌人生成表使用可扩展的 Dictionary 条目，权重和波次范围都可由数据调整。

@export var id: StringName = &""
@export var display_name_key: String = ""
@export var description_key: String = ""
@export var display_name_fallback: String = ""
@export var description_fallback: String = ""
@export var planet_id: StringName = &""
@export var map_position: Vector2 = Vector2.ZERO
@export var danger: int = 1
@export var initial_prep_seconds: float = 24.0
@export var later_prep_seconds: float = 38.0
@export var total_waves: int = 5
@export var terrain_seed: int = 0
@export var enemy_spawn_table: Array[Dictionary] = []
## 每波生成的敌人数量；索引 0 对应第一波。
@export var wave_enemy_counts: Array[int] = []


## 创建区域关卡定义；生成表会被深复制后保存。
static func create(
	definition_id: StringName = &"",
	display_name_key_value: String = "",
	description_key_value: String = "",
	planet: StringName = &"",
	position: Vector2 = Vector2.ZERO,
	danger_level: int = 1,
	initial_prep: float = 24.0,
	later_prep: float = 38.0,
	wave_count: int = 5,
	seed_value: int = 0,
	spawn_table: Array[Dictionary] = [],
	name_fallback: String = "",
	description_fallback_value: String = "",
	wave_counts: Array[int] = []
) -> LevelDefinition:
	var definition := LevelDefinition.new()
	definition.id = definition_id
	definition.display_name_key = display_name_key_value
	definition.description_key = description_key_value
	definition.display_name_fallback = name_fallback
	definition.description_fallback = description_fallback_value
	definition.planet_id = planet
	definition.map_position = position
	definition.danger = danger_level
	definition.initial_prep_seconds = initial_prep
	definition.later_prep_seconds = later_prep
	definition.total_waves = wave_count
	definition.terrain_seed = seed_value
	definition.enemy_spawn_table = spawn_table.duplicate(true)
	if definition.enemy_spawn_table.is_empty():
		definition.enemy_spawn_table.append({
			"enemy_id": &"scout",
			"weight": 1.0,
			"min_wave": 1,
			"max_wave": wave_count,
		})
	if wave_counts.is_empty():
		for index in range(wave_count):
			definition.wave_enemy_counts.append(3 + index * 3)
	else:
		definition.wave_enemy_counts = wave_counts.duplicate()
	return definition


## 返回可直接用于选关、地图和波次系统的完整关卡数据。
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name_key": display_name_key,
		"description_key": description_key,
		"display_name_fallback": display_name_fallback,
		"description_fallback": description_fallback,
		"planet_id": planet_id,
		"map_position": map_position,
		"danger": danger,
		"initial_prep_seconds": initial_prep_seconds,
		"later_prep_seconds": later_prep_seconds,
		"total_waves": total_waves,
		"terrain_seed": terrain_seed,
		"enemy_spawn_table": enemy_spawn_table.duplicate(true),
		"wave_enemy_counts": wave_enemy_counts.duplicate(),
	}


## 校验关卡字段和每一条敌人生成配置。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).strip_edges().is_empty():
		errors.append("level.id 不能为空")
	if display_name_key.strip_edges().is_empty():
		errors.append("level.display_name_key 不能为空")
	if description_key.strip_edges().is_empty():
		errors.append("level.description_key 不能为空")
	if String(planet_id).strip_edges().is_empty():
		errors.append("level.planet_id 不能为空")
	if danger < 1:
		errors.append("level.danger 必须大于等于 1")
	if initial_prep_seconds <= 0.0:
		errors.append("level.initial_prep_seconds 必须大于 0")
	if later_prep_seconds <= 0.0:
		errors.append("level.later_prep_seconds 必须大于 0")
	if total_waves < 1:
		errors.append("level.total_waves 必须大于等于 1")
	if enemy_spawn_table.is_empty():
		errors.append("level.enemy_spawn_table 不能为空")
	if wave_enemy_counts.size() != total_waves:
		errors.append("level.wave_enemy_counts 长度必须等于 total_waves")
	else:
		for index in range(wave_enemy_counts.size()):
			if wave_enemy_counts[index] <= 0:
				errors.append(
					"level.wave_enemy_counts[%d] 必须大于 0" % index
				)

	for index in range(enemy_spawn_table.size()):
		var entry: Dictionary = enemy_spawn_table[index]
		var enemy_value: Variant = entry.get("enemy_id", "")
		if not (enemy_value is String or enemy_value is StringName):
			errors.append("level.enemy_spawn_table[%d].enemy_id 必须是字符串" % index)
		elif String(enemy_value).strip_edges().is_empty():
			errors.append("level.enemy_spawn_table[%d].enemy_id 不能为空" % index)

		var weight_value: Variant = entry.get("weight", 0.0)
		if not (weight_value is int or weight_value is float):
			errors.append("level.enemy_spawn_table[%d].weight 必须是数值" % index)
		elif float(weight_value) <= 0.0:
			errors.append("level.enemy_spawn_table[%d].weight 必须大于 0" % index)

		var min_wave := int(entry.get("min_wave", 1))
		var max_wave := int(entry.get("max_wave", total_waves))
		if min_wave < 1 or max_wave < min_wave or max_wave > total_waves:
			errors.append(
				"level.enemy_spawn_table[%d] 的波次范围 [%d, %d] 无效"
				% [index, min_wave, max_wave]
			)

	return errors
