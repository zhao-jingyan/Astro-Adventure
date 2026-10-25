@tool
class_name AchievementDefinition
extends Resource

## 成就定义。
## 事件名由统计系统发布，成就层只记录监听目标与解锁条件。

@export var id: StringName = &""
@export var display_name_key: String = ""
@export var description_key: String = ""
@export var display_name_fallback: String = ""
@export var description_fallback: String = ""
@export var event_name: StringName = &""
@export var target_count: int = 1
## 大于等于 0 时，使用信号对应位置的数值作为本次进度；-1 表示每次事件计 1。
@export var amount_argument_index: int = -1
@export var hidden: bool = false


## 创建成就定义。
static func create(
	definition_id: StringName = &"",
	display_name_key_value: String = "",
	description_key_value: String = "",
	event: StringName = &"",
	target: int = 1,
	is_hidden: bool = false,
	name_fallback: String = "",
	description_fallback_value: String = "",
	progress_argument_index: int = -1
) -> AchievementDefinition:
	var definition := AchievementDefinition.new()
	definition.id = definition_id
	definition.display_name_key = display_name_key_value
	definition.description_key = description_key_value
	definition.display_name_fallback = name_fallback
	definition.description_fallback = description_fallback_value
	definition.event_name = event
	definition.target_count = target
	definition.amount_argument_index = progress_argument_index
	definition.hidden = is_hidden
	return definition


## 返回成就定义的完整快照。
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name_key": display_name_key,
		"description_key": description_key,
		"display_name_fallback": display_name_fallback,
		"description_fallback": description_fallback,
		"event_name": event_name,
		"target_count": target_count,
		"amount_argument_index": amount_argument_index,
		"hidden": hidden,
	}


## 校验成就展示键、事件名和累计目标。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).strip_edges().is_empty():
		errors.append("achievement.id 不能为空")
	if display_name_key.strip_edges().is_empty():
		errors.append("achievement.display_name_key 不能为空")
	if description_key.strip_edges().is_empty():
		errors.append("achievement.description_key 不能为空")
	if String(event_name).strip_edges().is_empty():
		errors.append("achievement.event_name 不能为空")
	if target_count < 1:
		errors.append("achievement.target_count 必须大于等于 1")
	if amount_argument_index < -1:
		errors.append("achievement.amount_argument_index 必须大于等于 -1")
	return errors
