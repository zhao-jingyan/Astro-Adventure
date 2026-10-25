class_name Interactable
extends Node2D

## 世界可交互物的通用基类。
##
## 节点进入场景树后会自动加入 "interactable" 组，退出时自动移除。
## 具体交互行为由交互系统监听 interaction_requested 后处理。

const GROUP_NAME := &"interactable"

signal interaction_requested(target_id: StringName, payload: Dictionary)

@export var interaction_id: StringName = &""
@export_range(0.0, 10000.0, 1.0, "or_greater") var interaction_radius := 96.0
@export var prompt_key: StringName = &""
@export var priority := 0
@export var enabled := true


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(GROUP_NAME)
	elif what == NOTIFICATION_EXIT_TREE:
		if is_in_group(GROUP_NAME):
			remove_from_group(GROUP_NAME)


## 允许游戏逻辑在运行时临时关闭或恢复交互。
func set_enabled(value: bool) -> void:
	enabled = value


## 检查目标是否启用、位于场景树中，并且玩家处于交互半径内。
func is_available(actor: Node2D) -> bool:
	if not enabled or not is_inside_tree():
		return false
	if not is_instance_valid(actor) or actor == self:
		return false

	var radius := maxf(0.0, interaction_radius)
	return (
		global_position.distance_squared_to(actor.global_position)
		<= radius * radius
	)


## can_interact 是 is_available 的语义化别名，方便调用方读取。
func can_interact(actor: Node2D) -> bool:
	return is_available(actor)


## 未单独配置提示文本时，以 interaction_id 作为回退值。
func get_prompt_key() -> StringName:
	return prompt_key if prompt_key != &"" else interaction_id


## 发起交互请求；不可交互时返回 false，也不会发出信号。
func request_interaction(actor: Node2D, payload: Dictionary = {}) -> bool:
	if not can_interact(actor):
		return false

	interaction_requested.emit(interaction_id, payload)
	return true
