class_name InteractionResolver
extends RefCounted

## 从玩家附近的候选中解析最终交互目标。
##
## 选择顺序为先比较 priority（数值越大越优先），优先级相同时再比较距离。
## candidates 留空时会从玩家所在的场景树读取 "interactable" 组。

var actor: Node2D
var default_filter: Variant = null


func _init(p_actor: Node2D = null, p_filter: Variant = null) -> void:
	actor = p_actor
	default_filter = p_filter


func set_actor(value: Node2D) -> void:
	actor = value


func set_filter(value: Variant) -> void:
	default_filter = value


## 返回当前最优目标；没有可交互目标时返回 null。
func find_nearest(
	candidates: Array = [],
	candidate_filter: Variant = null
) -> Interactable:
	if not is_instance_valid(actor):
		return null

	var pool := candidates
	if pool.is_empty() and actor.is_inside_tree():
		pool = actor.get_tree().get_nodes_in_group(Interactable.GROUP_NAME)

	var effective_filter: Variant = (
		candidate_filter if candidate_filter != null else default_filter
	)
	var selected: Interactable = null
	var selected_distance := INF

	for entry: Variant in pool:
		if not is_instance_valid(entry) or not entry is Interactable:
			continue

		var candidate := entry as Interactable
		if not candidate.is_available(actor):
			continue
		if not _matches_filter(candidate, effective_filter):
			continue

		var distance := actor.global_position.distance_to(candidate.global_position)
		if selected == null:
			selected = candidate
			selected_distance = distance
			continue

		if candidate.priority > selected.priority:
			selected = candidate
			selected_distance = distance
		elif candidate.priority == selected.priority and distance < selected_distance:
			selected = candidate
			selected_distance = distance

	return selected


## 获取最优目标对应的提示键；无目标时返回空 StringName。
func get_prompt(candidates: Array = [], candidate_filter: Variant = null) -> StringName:
	var target := find_nearest(candidates, candidate_filter)
	return target.get_prompt_key() if target != null else &""


## 对最优目标发起交互并返回该目标；目标不存在或交互失败时返回 null。
func interact_nearest(
	candidates: Array = [],
	payload: Dictionary = {},
	candidate_filter: Variant = null
) -> Interactable:
	var target := find_nearest(candidates, candidate_filter)
	if target == null:
		return null
	if not target.request_interaction(actor, payload):
		return null
	return target


## 无需持有实例时也可完成一次目标解析。
static func select_candidate(
	target_actor: Node2D,
	candidates: Array = [],
	filter: Variant = null
) -> Interactable:
	var resolver := InteractionResolver.new(target_actor, filter)
	return resolver.find_nearest(candidates)


## 静态版本的提示键查询。
static func prompt_for(
	target_actor: Node2D,
	candidates: Array = [],
	filter: Variant = null
) -> StringName:
	var resolver := InteractionResolver.new(target_actor, filter)
	return resolver.get_prompt(candidates)


## 静态版本的最近交互入口。
static func interact_with_nearest(
	target_actor: Node2D,
	candidates: Array = [],
	filter: Variant = null,
	payload: Dictionary = {}
) -> Interactable:
	var resolver := InteractionResolver.new(target_actor, filter)
	return resolver.interact_nearest(candidates, payload)


func _matches_filter(candidate: Interactable, filter_value: Variant) -> bool:
	if filter_value == null:
		return true
	if filter_value is Callable:
		var callable: Callable = filter_value
		return callable.is_valid() and bool(callable.call(candidate))
	if filter_value is StringName or filter_value is String:
		return candidate.interaction_id == StringName(filter_value)
	return false
