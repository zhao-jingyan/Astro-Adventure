extends SceneTree

## 内容目录集成测试：资源发现、稳定 id 查询与跨资源校验。

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry_script: Script = load("res://scripts/core/content_registry.gd")
	var registry: Node = registry_script.new()
	root.add_child(registry)
	await process_frame

	_expect(registry.is_loaded(), "ContentRegistry 应自动加载内容目录")
	_expect(registry.get_levels().size() == 4, "应发现四个关卡")
	_expect(registry.get_planets().size() == 1, "应发现 Khepri-9 星球定义")
	_expect(registry.get_enemy_species_all().size() == 3, "应发现三个敌人物种")
	_expect(registry.get_relics().size() == 3, "应发现三个遗物")
	_expect(registry.get_achievements().size() == 3, "应发现三个成就")

	var red_basin: Resource = registry.get_level(&"red_basin")
	_expect(red_basin != null, "应能按稳定 id 查询关卡")
	if red_basin != null:
		_expect(red_basin.get("planet_id") == &"khepri_9", "关卡应引用正确星球")
		_expect(not (red_basin.get("enemy_spawn_table") as Array).is_empty(), "关卡应包含刷新表")

	_expect(registry.get_enemy_species(&"scout") != null, "应能按 id 查询敌人物种")
	_expect(registry.get_relic(&"phase_boots") != null, "应能按 id 查询遗物")
	_expect(registry.get_achievement(&"first_wave_clear") != null, "应能按 id 查询成就")

	var validation_errors: PackedStringArray = registry.validate_all()
	_expect(validation_errors.is_empty(), "内容目录不应存在字段或引用错误")
	if not validation_errors.is_empty():
		for error: String in validation_errors:
			push_error(error)

	registry.queue_free()
	await process_frame

	if _failures.is_empty():
		print("内容目录测试通过：资源发现、id 查询和跨资源校验均正常。")
		quit(0)
		return

	for failure: String in _failures:
		push_error("内容目录测试失败：" + failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
