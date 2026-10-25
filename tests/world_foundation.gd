extends SceneTree

## 世界交互与地形基础规则测试。

var _failures: Array[String] = []
var _signal_count := 0
var _signal_target_id: StringName = &""
var _signal_payload: Dictionary = {}
var _slide_blocked_areas: Array[Rect2] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_interaction_resolver()
	_test_terrain_query()
	await _test_interactable_group_lifecycle()

	if _failures.is_empty():
		print("世界基础测试通过：交互解析、信号、地形规则和分轴滑动均正常。")
		quit(0)
		return

	for failure: String in _failures:
		push_error("世界基础测试失败：" + failure)
	quit(1)


func _test_interaction_resolver() -> void:
	var actor := Node2D.new()
	actor.position = Vector2.ZERO
	root.add_child(actor)

	var priority_far := _make_interactable(
		&"priority_far", Vector2(70.0, 0.0), 100.0, 10, &"prompt.priority_far"
	)
	var priority_near := _make_interactable(
		&"priority_near", Vector2(50.0, 0.0), 100.0, 10, &"prompt.priority_near"
	)
	var low_near := _make_interactable(
		&"low_near", Vector2(10.0, 0.0), 100.0, 1, &"prompt.low_near"
	)
	var disabled := _make_interactable(
		&"disabled", Vector2(5.0, 0.0), 100.0, 100, &"prompt.disabled"
	)
	disabled.set_enabled(false)
	var out_of_range := _make_interactable(
		&"out_of_range", Vector2(200.0, 0.0), 20.0, 200, &"prompt.out_of_range"
	)

	for candidate in [priority_far, priority_near, low_near, disabled, out_of_range]:
		root.add_child(candidate)

	_expect(
		not disabled.can_interact(actor),
		"关闭的可交互目标不应接受交互"
	)
	_expect(
		not out_of_range.can_interact(actor),
		"交互半径之外的目标不应可交互"
	)

	var resolver := InteractionResolver.new(actor)
	_expect(
		resolver.find_nearest() == priority_near,
		"应先选择最高优先级，再在同优先级中选择最近目标"
	)
	_expect(
		resolver.get_prompt() == &"prompt.priority_near",
		"提示键应来自最终选中的目标"
	)
	_expect(
		resolver.find_nearest([], &"low_near") == low_near,
		"字符串 id 过滤器应只保留指定目标"
	)

	var low_priority_only := func(candidate: Interactable) -> bool:
		return candidate.priority == 1
	_expect(
		resolver.find_nearest([], low_priority_only) == low_near,
		"Callable 过滤器应参与候选筛选"
	)

	priority_near.interaction_requested.connect(_on_interaction_requested)
	var payload := {"source": "world_test", "amount": 3}
	var interacted := resolver.interact_nearest([], payload)
	_expect(interacted == priority_near, "交互入口应返回实际交互目标")
	_expect(_signal_count == 1, "成功交互应发出一次信号")
	_expect(_signal_target_id == &"priority_near", "信号应携带目标 id")
	_expect(
		_signal_payload == payload,
		"信号应完整保留调用方传入的 payload"
	)

	priority_near.set_enabled(false)
	priority_far.set_enabled(false)
	_expect(
		resolver.find_nearest() == low_near,
		"解析器应跳过已禁用目标并继续选择次优目标"
	)
	_expect(
		not priority_near.request_interaction(actor, {}),
		"禁用目标直接请求交互时应返回 false"
	)
	_expect(_signal_count == 1, "失败请求不应重复发出信号")

	_expect(
		InteractionResolver.select_candidate(actor) == low_near,
		"静态选择 API 应与实例解析结果一致"
	)
	_expect(
		InteractionResolver.prompt_for(actor) == &"prompt.low_near",
		"静态提示 API 应返回最终目标提示键"
	)

	root.remove_child(actor)
	for candidate in [priority_far, priority_near, low_near, disabled, out_of_range]:
		root.remove_child(candidate)
		candidate.queue_free()
	actor.queue_free()


func _test_terrain_query() -> void:
	var profile := TerrainQuery.TerrainProfile.new(
		{
			"sand": 0.75,
			"mud": 0.4,
			"boost": 1.25,
		},
		PackedStringArray(["rock", "lava"]),
		PackedStringArray(["radiation", "lava"])
	)
	var terrain := TerrainQuery.new()
	terrain.configure_from_profile(profile)

	_expect_float(
		terrain.get_speed_multiplier(PackedStringArray(["sand"])),
		0.75,
		"普通地形标签应返回对应速度倍率"
	)
	_expect_float(
		terrain.get_speed_multiplier(PackedStringArray(["sand", "mud"])),
		0.4,
		"多个速度标签同时命中时应取最慢倍率"
	)
	_expect_float(
		terrain.get_speed_multiplier(PackedStringArray(["boost"])),
		1.25,
		"地形应允许配置高于 1 的速度倍率"
	)
	_expect_float(
		terrain.get_speed_multiplier(PackedStringArray(["unknown"])),
		1.0,
		"未命中速度标签时应使用默认倍率"
	)
	_expect(terrain.is_blocked(PackedStringArray(["rock"])), "岩石标签应阻挡移动")
	_expect(
		not terrain.is_blocked(PackedStringArray(["sand"])),
		"普通可通行标签不应被误判为阻挡"
	)
	_expect(
		terrain.is_dangerous(PackedStringArray(["sand", "radiation"])),
		"危险标签应被识别"
	)
	var danger_tags := terrain.get_matching_danger_tags(
		PackedStringArray(["lava", "sand", "radiation"])
	)
	_expect(
		danger_tags == PackedStringArray(["lava", "radiation"]),
		"应返回所有实际命中的危险标签"
	)

	var sample := terrain.sample(
		Vector2(12.0, 34.0),
		PackedStringArray(["sand", "radiation"])
	)
	_expect(sample["position"] == Vector2(12.0, 34.0), "采样结果应保留世界坐标")
	_expect(sample["tags"] == PackedStringArray(["sand", "radiation"]), "采样结果应返回标签")
	_expect(not bool(sample["blocked"]), "可通行标签的 blocked 应为 false")
	_expect(bool(sample["danger"]), "危险采样应标记 danger")
	_expect_float(sample["speed_multiplier"], 0.75, "采样结果应包含速度倍率")

	var dictionary_terrain := TerrainQuery.new()
	dictionary_terrain.configure_from_dictionary({
		"speed_multipliers": {"crater": 0.5},
		"blocked_tags": ["wall"],
		"danger_tags": ["vacuum"],
	})
	_expect_float(
		dictionary_terrain.get_speed_multiplier(["crater"]),
		0.5,
		"字典配置应支持数组标签"
	)
	_expect(dictionary_terrain.is_blocked(["wall"]), "字典配置应更新阻挡标签")
	_expect(dictionary_terrain.is_dangerous(["vacuum"]), "字典配置应更新危险标签")

	_slide_blocked_areas.clear()
	_expect(
		terrain.slide_move(
			Vector2(10.0, 10.0),
			Vector2(20.0, 20.0),
			1.0,
			Callable(self, "_sample_slide_terrain")
		) == Vector2(20.0, 20.0),
		"未被阻挡时应完整移动到目标位置"
	)

	_slide_blocked_areas = [Rect2(8.0, 8.0, 4.0, 4.0)]
	_expect(
		terrain.slide_move(
			Vector2.ZERO,
			Vector2(10.0, 10.0),
			1.0,
			Callable(self, "_sample_slide_terrain")
		) == Vector2(10.0, 0.0),
		"目标被阻挡而 X 轴可通行时应沿 X 轴滑动"
	)

	_slide_blocked_areas = [
		Rect2(9.0, -1.0, 2.0, 2.0),
		Rect2(9.0, 9.0, 2.0, 2.0),
	]
	_expect(
		terrain.slide_move(
			Vector2.ZERO,
			Vector2(10.0, 10.0),
			1.0,
			Callable(self, "_sample_slide_terrain")
		) == Vector2(0.0, 10.0),
		"X 轴受阻时应尝试 Y 轴，避免岩石导致完全卡死"
	)


func _test_interactable_group_lifecycle() -> void:
	var interactable := Interactable.new()
	root.add_child(interactable)
	_expect(
		interactable.is_in_group(Interactable.GROUP_NAME),
		"可交互节点进入场景树后应自动加入 interactable 组"
	)

	root.remove_child(interactable)
	_expect(
		not interactable.is_in_group(Interactable.GROUP_NAME),
		"可交互节点退出场景树后应自动移除 interactable 组"
	)
	interactable.free()
	await process_frame


func _make_interactable(
	id: StringName,
	world_position: Vector2,
	radius: float,
	target_priority: int,
	prompt: StringName
) -> Interactable:
	var interactable := Interactable.new()
	interactable.interaction_id = id
	interactable.position = world_position
	interactable.interaction_radius = radius
	interactable.priority = target_priority
	interactable.prompt_key = prompt
	return interactable


func _on_interaction_requested(target_id: StringName, payload: Dictionary) -> void:
	_signal_count += 1
	_signal_target_id = target_id
	_signal_payload = payload.duplicate(true)


func _sample_slide_terrain(world_position: Vector2, radius: float) -> Dictionary:
	for area: Rect2 in _slide_blocked_areas:
		if area.grow(radius).has_point(world_position):
			return {
				"tags": PackedStringArray(["rock"]),
				"blocked": true,
			}
	return {
		"tags": PackedStringArray(),
		"blocked": false,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_float(actual: float, expected: float, message: String) -> void:
	_expect(is_equal_approx(actual, expected), message)
