extends Node

## 事件驱动成就系统。
##
## 每条 AchievementDefinition 监听一个 EventBus 信号，事件发生一次计一次。
## 进度和“已解锁”标记都写入 SaveStore 的 achievements 命名空间。

const EventBusScript = preload("res://scripts/core/event_bus.gd")
const SAVE_NAMESPACE := "achievements"

var event_bus: EventBusScript
var save_store: SaveStore
var definitions: Array[AchievementDefinition] = []

var _definitions_by_id: Dictionary = {}
var _definitions_by_event: Dictionary = {}
var _connections: Dictionary = {}
var _progress: Dictionary = {}
var _unlocked: Dictionary = {}
var _setup_complete := false


func _init(
	start_event_bus: EventBusScript = null,
	start_save_store: SaveStore = null,
	start_definitions: Array[AchievementDefinition] = []
) -> void:
	if start_event_bus != null and start_save_store != null:
		setup(start_event_bus, start_save_store, start_definitions)
	elif not start_definitions.is_empty():
		definitions = start_definitions.duplicate()


func _ready() -> void:
	if _setup_complete:
		return
	if event_bus == null:
		call_deferred("_setup_default_dependencies")
		return
	if save_store == null:
		save_store = SaveStore.new("user://saves", SAVE_NAMESPACE)
	setup(event_bus, save_store, definitions)


func _exit_tree() -> void:
	_disconnect_events()


## 显式装配依赖；测试可传入临时目录创建的 SaveStore。
func setup(
	start_event_bus: EventBusScript,
	start_save_store: SaveStore,
	start_definitions: Array[AchievementDefinition] = []
) -> void:
	_disconnect_events()
	event_bus = start_event_bus
	save_store = start_save_store
	definitions = start_definitions.duplicate()

	if save_store.save_namespace != SAVE_NAMESPACE:
		save_store.save_namespace = SAVE_NAMESPACE
	save_store.load()
	_index_definitions()
	_load_progress()
	_connect_events()
	_setup_complete = true


func set_definitions(next_definitions: Array[AchievementDefinition]) -> void:
	definitions = next_definitions.duplicate()
	_disconnect_events()
	_index_definitions()
	_load_progress()
	_connect_events()


func progress_for(achievement_id: Variant) -> int:
	return int(_progress.get(str(achievement_id), 0))


func is_unlocked(achievement_id: Variant) -> bool:
	return bool(_unlocked.get(str(achievement_id), false))


## 返回所有已配置成就的当前状态，供 HUD 或调试面板只读消费。
func snapshot() -> Dictionary:
	var result: Dictionary = {}
	for definition: AchievementDefinition in definitions:
		var definition_id := str(definition.id)
		result[definition_id] = {
			"event_name": str(definition.event_name),
			"current": progress_for(definition_id),
			"progress": progress_for(definition_id),
			"target_count": definition.target_count,
			"target": definition.target_count,
			"unlocked": is_unlocked(definition_id),
		}
	return result


## 也可由不依赖 EventBus 的测试或离线迁移逻辑直接累计。
func count_event(event_name: String, amount: int = 1) -> void:
	if amount <= 0:
		return

	var changed := false
	for definition: AchievementDefinition in _definitions_by_event.get(event_name, []):
		changed = _advance_definition(definition, amount) or changed

	if changed:
		_persist()


func _advance_definition(
	definition: AchievementDefinition,
	requested_amount: int
) -> bool:
	var definition_id := str(definition.id)
	var previous := progress_for(definition_id)
	var next_value := mini(
		previous + requested_amount,
		maxi(definition.target_count, 1)
	)
	var changed := false
	if next_value != previous:
		_progress[definition_id] = next_value
		changed = true

	if next_value >= definition.target_count and not is_unlocked(definition_id):
		_unlocked[definition_id] = true
		changed = true
		if event_bus != null:
			event_bus.achievement_unlocked.emit(definition_id)
	return changed


func _dispatch_event(event_name: String, event_arguments: Array) -> void:
	for definition: AchievementDefinition in _definitions_by_event.get(event_name, []):
		var amount := 1
		var amount_index := definition.amount_argument_index
		if amount_index >= 0 and amount_index < event_arguments.size():
			var raw_amount: Variant = event_arguments[amount_index]
			if raw_amount is int or raw_amount is float:
				amount = maxi(0, roundi(float(raw_amount)))
		if amount <= 0:
			continue
		if _advance_definition(definition, amount):
			_persist()


func _index_definitions() -> void:
	_definitions_by_id.clear()
	_definitions_by_event.clear()
	for definition: AchievementDefinition in definitions:
		var definition_id := str(definition.id).strip_edges()
		var event_name := str(definition.event_name).strip_edges()
		if definition_id.is_empty() or event_name.is_empty() or _definitions_by_id.has(definition_id):
			continue
		_definitions_by_id[definition_id] = definition
		if not _definitions_by_event.has(event_name):
			_definitions_by_event[event_name] = []
		(_definitions_by_event[event_name] as Array).append(definition)


func _load_progress() -> void:
	_progress.clear()
	_unlocked.clear()
	if save_store == null:
		return

	var stored_progress: Variant = save_store.get_or("progress", {})
	if stored_progress is Dictionary:
		for achievement_id: Variant in stored_progress:
			_progress[str(achievement_id)] = maxi(int(stored_progress[achievement_id]), 0)

	var stored_unlocked: Variant = save_store.get_or("unlocked", {})
	if stored_unlocked is Dictionary:
		for achievement_id: Variant in stored_unlocked:
			_unlocked[str(achievement_id)] = bool(stored_unlocked[achievement_id])

	# 旧档若有达标进度但缺少解锁标记，以进度为准静默修复，启动时不重复播放解锁。
	for definition: AchievementDefinition in definitions:
		var definition_id := str(definition.id)
		if progress_for(definition_id) >= definition.target_count:
			_unlocked[definition_id] = true


func _connect_events() -> void:
	if event_bus == null:
		return
	for event_name: Variant in _definitions_by_event:
		var event_text := str(event_name)
		if not event_bus.has_signal(event_text):
			push_warning("成就事件不存在：%s" % event_text)
			continue

		var argument_count := _signal_argument_count(event_text)
		var callback: Callable
		match argument_count:
			0:
				callback = Callable(self, "_on_event_0").bind(event_text)
			1:
				callback = Callable(self, "_on_event_1").bind(event_text)
			2:
				callback = Callable(self, "_on_event_2").bind(event_text)
			3:
				callback = Callable(self, "_on_event_3").bind(event_text)
			_:
				push_warning("成就暂不支持超过三个参数的信号：%s" % event_text)
				continue
		event_bus.connect(event_text, callback)
		_connections[event_text] = callback


func _disconnect_events() -> void:
	if event_bus != null:
		for event_name: Variant in _connections:
			var callback: Callable = _connections[event_name]
			if event_bus.is_connected(event_name, callback):
				event_bus.disconnect(event_name, callback)
	_connections.clear()


func _on_event_0(event_name: String) -> void:
	_dispatch_event(event_name, [])


func _on_event_1(argument_1: Variant, event_name: String) -> void:
	_dispatch_event(event_name, [argument_1])


func _on_event_2(argument_1: Variant, argument_2: Variant, event_name: String) -> void:
	_dispatch_event(event_name, [argument_1, argument_2])


func _on_event_3(
	argument_1: Variant,
	argument_2: Variant,
	argument_3: Variant,
	event_name: String
) -> void:
	_dispatch_event(event_name, [argument_1, argument_2, argument_3])


func _signal_argument_count(event_name: String) -> int:
	for signal_info: Dictionary in event_bus.get_signal_list():
		if str(signal_info.get("name", "")) == event_name:
			return (signal_info.get("args", []) as Array).size()
	return -1


func _persist() -> void:
	if save_store == null:
		return
	save_store.set_value("progress", _progress)
	save_store.set_value("unlocked", _unlocked)
	save_store.flush()


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


func _setup_default_dependencies() -> void:
	if _setup_complete:
		return
	if event_bus == null:
		event_bus = _find_or_create_event_bus()
	if event_bus == null:
		push_error("成就系统无法解析 EventBus")
		return
	if save_store == null:
		save_store = SaveStore.new("user://saves", SAVE_NAMESPACE)
	setup(event_bus, save_store, definitions)
