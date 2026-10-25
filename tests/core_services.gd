extends SceneTree

## 运行时基础服务测试：事件声明、存档原子写入与损坏回退、
## 本地化回退、遗物修正，以及成就持久化和解锁幂等。

const EventBusScript = preload("res://scripts/core/event_bus.gd")
const LocalizationServiceScript = preload("res://scripts/core/localization_service.gd")
const RelicSystemScript = preload("res://scripts/systems/relic_system.gd")
const AchievementSystemScript = preload("res://scripts/systems/achievement_system.gd")

var _failures: Array[String] = []
var _temp_base := ""
var _locale_events: Array[String] = []
var _relic_events: Array[Dictionary] = []
var _achievement_events: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_temp_base = "user://core_services_test_%d_%d" % [
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]
	DirAccess.make_dir_recursive_absolute(_temp_base)

	var bus := EventBusScript.new()
	_test_event_bus(bus)
	_test_save_store()
	_test_localization(bus)
	_test_relic_system(bus)
	_test_achievement_system(bus)

	bus.free()
	_cleanup()

	if _failures.is_empty():
		print("核心服务测试通过：事件、存档、本地化、遗物与成就均正常。")
		quit(0)
		return

	for failure: String in _failures:
		push_error("核心服务测试失败：" + failure)
	quit(1)


func _test_event_bus(bus: EventBusScript) -> void:
	var expected_argument_counts := {
		"level_started": 1,
		"preparation_started": 2,
		"wave_started": 2,
		"wave_completed": 2,
		"level_completed": 1,
		"level_failed": 2,
		"travel_started": 3,
		"travel_completed": 1,
		"resource_collected": 3,
		"fuel_collected": 2,
		"player_damaged": 2,
		"enemy_defeated": 1,
		"relic_acquired": 2,
		"achievement_unlocked": 1,
		"locale_changed": 1,
		"interaction_performed": 2,
	}
	for signal_name: String in expected_argument_counts:
		_expect(bus.has_signal(signal_name), "EventBus 缺少信号：" + signal_name)
		if bus.has_signal(signal_name):
			_expect(
				_signal_argument_count(bus, signal_name) == int(expected_argument_counts[signal_name]),
				"EventBus 信号参数数量不符：" + signal_name
			)


func _test_save_store() -> void:
	var store := SaveStore.new(_temp_base, "core")
	_expect(store.set_value("profile.name", "开拓者"), "SaveStore 应支持点路径写入")
	_expect(store.set_value("profile.visits", 0), "SaveStore 应支持嵌套字段")
	_expect(store.add("profile.visits", 2) == 2, "SaveStore.add 应累加数值")
	_expect(store.get_or("profile.name") == "开拓者", "SaveStore.get 应读取写入值")
	store.set(&"compat_key", "ok")
	_expect(store.get(&"compat_key") == "ok", "SaveStore 的 Object 兼容 set/get 应可调用")
	_expect(store.flush(), "SaveStore.flush 应成功写入正式文件")
	_expect(not FileAccess.file_exists(store.get_save_path() + ".tmp"), "原子写入后不应残留临时文件")

	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(store.get_save_path()))
	_expect(raw is Dictionary, "存档根节点应为 JSON 对象")
	if raw is Dictionary:
		_expect(int(raw.get("schema_version", -1)) == SaveStore.SCHEMA_VERSION, "存档应包含 schema_version")
		_expect(str(raw.get("namespace", "")) == "core", "存档应记录 namespace")

	var reloaded := SaveStore.new(_temp_base, "core")
	_expect(reloaded.load(), "SaveStore.load 应读取有效存档")
	_expect(reloaded.get_or("profile.visits") == 2, "重新加载后数值应保持")
	_expect(reloaded.remove("profile.name"), "SaveStore.remove 应删除字段")
	_expect(not reloaded.has("profile.name"), "删除后的字段不应存在")
	_expect(reloaded.flush(), "删除后应可再次原子写入")

	var corrupt_file := FileAccess.open(reloaded.get_save_path(), FileAccess.WRITE)
	_expect(corrupt_file != null, "测试应能写入损坏存档")
	if corrupt_file != null:
		corrupt_file.store_string("{ 这不是合法 JSON")
		corrupt_file.close()
	_expect(not reloaded.load(), "损坏存档应返回加载失败")
	_expect(reloaded.snapshot().is_empty(), "损坏存档应回退为空档")

	var namespaced := SaveStore.new(_temp_base, "settings")
	namespaced.set_value("language", "zh_CN")
	_expect(namespaced.flush(), "不同 namespace 应能独立写入")
	_expect(FileAccess.file_exists(_temp_base.path_join("settings.json")), "namespace 应映射到独立文件")


func _test_localization(bus: EventBusScript) -> void:
	bus.locale_changed.connect(_record_locale)
	var localization := LocalizationServiceScript.new(bus)
	_expect(localization.get_locale() == "zh_CN", "本地化默认语言应为 zh_CN")
	_expect(
		localization.translate("notification.fuel_collected", {"amount": 12, "total": 40})
		== "燃油 +12（总燃料 40）",
		"translate 应替换命名参数"
	)
	_expect(localization.set_locale("en"), "已加载语言应可切换")
	_expect(localization.translate("hud.fuel") == "Fuel", "切换后应使用英文文本")
	_expect(
		localization.translate("localization.fallback_only") == "仅中文可用",
		"英文缺失 key 应回退 zh_CN"
	)
	_expect(
		localization.translate("missing.translation.key") == "missing.translation.key",
		"所有语言缺失时应回退 key"
	)
	_expect(not localization.set_locale("xx"), "未加载语言不应被接受")
	_expect(_locale_events == ["en"], "切换语言应只发出一次 locale_changed")
	localization.free()


func _test_relic_system(bus: EventBusScript) -> void:
	bus.relic_acquired.connect(_record_relic)
	var phase_boots := RelicDefinition.create(
		&"phase_boots",
		"relic.phase_boots.name",
		"relic.phase_boots.description",
		&"uncommon",
		{"move_speed_multiplier": 1.08}
	)
	var fuel_seed := RelicDefinition.create(
		&"fuel_seed",
		"relic.fuel_seed.name",
		"relic.fuel_seed.description",
		&"rare",
		{"max_health_add": 10}
	)
	var relics := RelicSystemScript.new(bus, [phase_boots, fuel_seed])
	_expect(relics.add_relic("phase_boots"), "应能按 id 添加已配置遗物")
	_expect(is_equal_approx(relics.get_modifier("move_speed_multiplier", 100.0), 108.0), "乘数遗物应修正基础值")
	_expect(not relics.add_relic("phase_boots"), "默认重复策略应禁止同名遗物")

	relics.duplicate_policy = RelicSystemScript.DuplicatePolicy.STACK
	_expect(relics.add_relic("phase_boots"), "切换 STACK 后应允许重复遗物")
	_expect(relics.get_relic_stacks("phase_boots") == 2, "active_relics 应记录遗物层数")
	_expect(
		is_equal_approx(relics.get_modifier("move_speed_multiplier", 100.0), 116.64),
		"叠层乘数遗物应按层数相乘"
	)
	_expect(relics.add_relic(fuel_seed), "应支持直接传入 RelicDefinition")
	_expect(is_equal_approx(relics.get_modifier("max_health_add", 100.0), 110.0), "平直加值应修正基础值")
	_expect(is_equal_approx(relics.get_modifier("max_health_add", 100.0, true), 110.0), "additive 模式应累加修正")
	_expect(relics.remove_relic("phase_boots"), "应能移除叠层遗物")
	_expect(relics.get_relic_stacks("phase_boots") == 1, "移除叠层遗物应只减少一层")
	_expect(_relic_events.size() == 3, "每次成功获得遗物都应发出 relic_acquired")
	_expect(relics.snapshot().size() == 2, "遗物快照应包含当前所有遗物")

	var by_id := RelicSystemScript.new(bus, {"fuel_seed": fuel_seed})
	_expect(by_id.add_relic("fuel_seed"), "遗物定义也应支持 id → 定义字典")
	by_id.free()
	relics.free()


func _test_achievement_system(bus: EventBusScript) -> void:
	bus.achievement_unlocked.connect(_record_achievement)
	var wave_achievement := AchievementDefinition.create(
		&"wave_two",
		"achievement.wave_two.name",
		"achievement.wave_two.description",
		&"wave_completed",
		2,
		false,
		"守住两波",
		"完成两次波次防守。"
	)
	var fuel_achievement := AchievementDefinition.create(
		&"fuel_ten",
		"achievement.fuel_ten.name",
		"achievement.fuel_ten.description",
		&"fuel_collected",
		10,
		false,
		"累计十单位燃油",
		"累计采集十单位燃油。",
		0
	)
	var initial_store := SaveStore.new(_temp_base, "not_achievements")
	var achievements := AchievementSystemScript.new(
		bus,
		initial_store,
		[wave_achievement, fuel_achievement]
	)
	_expect(initial_store.save_namespace == "achievements", "成就系统应强制使用 achievements namespace")

	bus.wave_completed.emit("red_basin", 1)
	_expect(achievements.progress_for("wave_two") == 1, "成就应按 event_name 累计进度")
	_expect(not achievements.is_unlocked("wave_two"), "未达到目标前不应解锁")
	bus.wave_completed.emit("red_basin", 2)
	bus.wave_completed.emit("red_basin", 3)
	_expect(achievements.progress_for("wave_two") == 2, "成就进度应封顶到 target_count")
	_expect(achievements.is_unlocked("wave_two"), "达到目标后应解锁")
	_expect(_achievement_events == ["wave_two"], "同一成就只能发出一次 achievement_unlocked")
	bus.fuel_collected.emit(4, 4)
	_expect(achievements.progress_for("fuel_ten") == 4, "成就应按数值事件参数累计")
	bus.fuel_collected.emit(7, 11)
	_expect(achievements.progress_for("fuel_ten") == 10, "数值进度应封顶")
	_expect(
		_achievement_events == ["wave_two", "fuel_ten"],
		"数值型成就达到目标后应解锁"
	)

	var snapshot: Dictionary = achievements.snapshot()
	_expect(snapshot.has("wave_two"), "成就 snapshot 应包含已配置成就")
	if snapshot.has("wave_two"):
		_expect(bool(snapshot["wave_two"]["unlocked"]), "成就 snapshot 应报告解锁状态")
	_expect(
		FileAccess.file_exists(_temp_base.path_join("achievements.json")),
		"成就进度应持久化到 achievements 命名空间"
	)

	achievements.free()
	var persisted_store := SaveStore.new(_temp_base, "achievements")
	var restored := AchievementSystemScript.new(
		bus,
		persisted_store,
		[wave_achievement, fuel_achievement]
	)
	_expect(restored.progress_for("wave_two") == 2, "重启后应恢复成就进度")
	_expect(restored.is_unlocked("wave_two"), "重启后应恢复解锁状态")
	_expect(
		_achievement_events == ["wave_two", "fuel_ten"],
		"加载已解锁成就时不得重复发信号"
	)
	restored.free()


func _record_locale(locale: String) -> void:
	_locale_events.append(locale)


func _record_relic(relic_id: String, stack_count: int) -> void:
	_relic_events.append({"id": relic_id, "stacks": stack_count})


func _record_achievement(achievement_id: String) -> void:
	_achievement_events.append(achievement_id)


func _signal_argument_count(object: Object, signal_name: String) -> int:
	for signal_info: Dictionary in object.get_signal_list():
		if str(signal_info.get("name", "")) == signal_name:
			return (signal_info.get("args", []) as Array).size()
	return -1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _cleanup() -> void:
	var directory := DirAccess.open(_temp_base)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(_temp_base.path_join(filename))
	DirAccess.remove_absolute(_temp_base)
