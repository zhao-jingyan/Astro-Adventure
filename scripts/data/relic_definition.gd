@tool
class_name RelicDefinition
extends Resource

## 遗物定义。
## modifiers 的键由消费系统约定，新增效果只需增加数据项。

@export var id: StringName = &""
@export var display_name_key: String = ""
@export var description_key: String = ""
@export var display_name_fallback: String = ""
@export var description_fallback: String = ""
@export var rarity: StringName = &"common"
@export var modifiers: Dictionary = {}


## 创建遗物定义；效果字典会被深复制。
static func create(
	definition_id: StringName = &"",
	display_name_key_value: String = "",
	description_key_value: String = "",
	rarity_value: StringName = &"common",
	modifier_values: Dictionary = {},
	name_fallback: String = "",
	description_fallback_value: String = ""
) -> RelicDefinition:
	var definition := RelicDefinition.new()
	definition.id = definition_id
	definition.display_name_key = display_name_key_value
	definition.description_key = description_key_value
	definition.display_name_fallback = name_fallback
	definition.description_fallback = description_fallback_value
	definition.rarity = rarity_value
	definition.modifiers = modifier_values.duplicate(true)
	return definition


## 返回遗物定义的完整快照。
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name_key": display_name_key,
		"description_key": description_key,
		"display_name_fallback": display_name_fallback,
		"description_fallback": description_fallback,
		"rarity": rarity,
		"modifiers": modifiers.duplicate(true),
	}


## 校验遗物标识及所有数值修正项。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).strip_edges().is_empty():
		errors.append("relic.id 不能为空")
	if display_name_key.strip_edges().is_empty():
		errors.append("relic.display_name_key 不能为空")
	if description_key.strip_edges().is_empty():
		errors.append("relic.description_key 不能为空")
	if String(rarity).strip_edges().is_empty():
		errors.append("relic.rarity 不能为空")
	if modifiers.is_empty():
		errors.append("relic.modifiers 不能为空")

	for modifier_key: Variant in modifiers:
		var modifier_name := String(modifier_key).strip_edges()
		if modifier_name.is_empty():
			errors.append("relic.modifiers 不能包含空键")
			continue
		var modifier_value: Variant = modifiers[modifier_key]
		if not (modifier_value is int or modifier_value is float):
			errors.append("relic.modifiers.%s 必须是数值" % modifier_name)

	return errors
