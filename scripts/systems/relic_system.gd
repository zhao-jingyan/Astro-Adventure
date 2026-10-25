extends Node

## 遗物持有与数值修正。
##
## active_relics 保存 id → 层数。默认禁止重复遗物；切换为 STACK 后允许叠层。
## 修正键以 _multiplier 结尾时按乘数生效，其余按键提供平直加值。

const EventBusScript = preload("res://scripts/core/event_bus.gd")

enum DuplicatePolicy {
	FORBID,
	STACK,
}

var event_bus: EventBusScript
var duplicate_policy: DuplicatePolicy = DuplicatePolicy.FORBID
var max_stacks := 0
var active_relics: Dictionary = {}

var _definitions: Dictionary = {}


## 布尔式重复策略入口；与 duplicate_policy 同步。
var allow_duplicate_relics: bool:
	get:
		return duplicate_policy == DuplicatePolicy.STACK
	set(value):
		duplicate_policy = DuplicatePolicy.STACK if value else DuplicatePolicy.FORBID


func _init(start_event_bus: EventBusScript = null, definitions: Variant = []) -> void:
	if start_event_bus != null:
		setup(start_event_bus, definitions)
	elif definitions is Array and not (definitions as Array).is_empty():
		_install_definitions(definitions)
	elif definitions is Dictionary and not (definitions as Dictionary).is_empty():
		_install_definitions(definitions)


func _ready() -> void:
	if event_bus == null:
		call_deferred("_resolve_default_event_bus")


## 显式注入 EventBus 与遗物定义。
## definitions 可以是 RelicDefinition 数组，也可以是 id → RelicDefinition 的字典。
func setup(start_event_bus: EventBusScript, definitions: Variant = []) -> void:
	event_bus = start_event_bus
	active_relics.clear()
	_install_definitions(definitions)


func set_definitions(definitions: Variant) -> void:
	_install_definitions(definitions)


func set_duplicate_policy(policy: DuplicatePolicy) -> void:
	duplicate_policy = policy


## 按 id 添加遗物，也可以直接传入尚未登记的 RelicDefinition。
func add_relic(relic: Variant) -> bool:
	var definition := _resolve_definition(relic)
	if definition == null or definition.id.is_empty():
		return false

	var relic_id := String(definition.id)
	_definitions[relic_id] = definition
	var current_stacks := int(active_relics.get(relic_id, 0))
	if current_stacks > 0 and duplicate_policy == DuplicatePolicy.FORBID:
		return false
	if max_stacks > 0 and current_stacks >= max_stacks:
		return false

	var next_stacks := current_stacks + 1
	active_relics[relic_id] = next_stacks
	if event_bus != null:
		event_bus.relic_acquired.emit(relic_id, next_stacks)
	return true


## 移除遗物；叠层遗物每次只减少一层。
func remove_relic(relic_id: Variant) -> bool:
	var normalized_id := str(relic_id)
	var current_stacks := int(active_relics.get(normalized_id, 0))
	if current_stacks <= 0:
		return false
	if current_stacks <= 1:
		active_relics.erase(normalized_id)
	else:
		active_relics[normalized_id] = current_stacks - 1
	return true


func get_relic_stacks(relic_id: Variant) -> int:
	return int(active_relics.get(str(relic_id), 0))


func get_definition(relic_id: Variant) -> RelicDefinition:
	return _definitions.get(str(relic_id))


## additive 为 true 时总是使用 base + 修正总和；否则按修正键后缀应用乘数或加值。
func get_modifier(key: String, base_value: float, additive: bool = false) -> float:
	if additive:
		return base_value + _sum_modifier(key)
	return _apply_aggregated_modifier(key, base_value, get_all_modifiers(false).get(key, 1.0))


## 返回所有遗物修正的聚合值。
## 非 additive 模式合并乘法键，其余键累加；additive 模式全部累加。
func get_all_modifiers(additive: bool = false) -> Dictionary:
	var result: Dictionary = {}
	for relic_id: Variant in active_relics:
		var definition: RelicDefinition = _definitions.get(str(relic_id))
		if definition == null:
			continue
		var stacks := int(active_relics[relic_id])
		for modifier_key: Variant in definition.modifiers:
			var normalized_key := str(modifier_key)
			var value: Variant = definition.modifiers[modifier_key]
			if not (value is int or value is float):
				continue
			var numeric_value := float(value)
			if additive or not normalized_key.ends_with("_multiplier"):
				result[normalized_key] = float(result.get(normalized_key, 0.0)) + numeric_value * stacks
			else:
				var current_multiplier := float(result.get(normalized_key, 1.0))
				current_multiplier *= pow(numeric_value, stacks)
				result[normalized_key] = current_multiplier
	return result


func snapshot() -> Dictionary:
	return active_relics.duplicate(true)


func _install_definitions(definitions: Variant) -> void:
	_definitions.clear()
	if definitions is Array:
		for entry: Variant in definitions:
			if entry is RelicDefinition and not (entry as RelicDefinition).id.is_empty():
				_definitions[str((entry as RelicDefinition).id)] = entry
	elif definitions is Dictionary:
		for definition_id: Variant in definitions:
			var definition: Variant = (definitions as Dictionary)[definition_id]
			if definition is RelicDefinition:
				_definitions[str(definition_id)] = definition


func _resolve_definition(relic: Variant) -> RelicDefinition:
	if relic is RelicDefinition:
		return relic
	if relic is String or relic is StringName:
		return _definitions.get(str(relic))
	return null


func _sum_modifier(key: String) -> float:
	var total := 0.0
	for relic_id: Variant in active_relics:
		var definition: RelicDefinition = _definitions.get(str(relic_id))
		if definition == null:
			continue
		var raw_value: Variant = definition.modifiers.get(key)
		if raw_value is int or raw_value is float:
			total += float(raw_value) * int(active_relics[relic_id])
	return total


func _apply_aggregated_modifier(key: String, base_value: float, value: Variant) -> float:
	var numeric_value := float(value)
	if key.ends_with("_multiplier"):
		return base_value * numeric_value
	return base_value + numeric_value


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
