extends SceneTree

## 基建与玩法组合根集成测试：数据目录、服务、事件、地形与交互。

var _failures: Array[String] = []
var _fuel_events := 0
var _interaction_events := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var event_bus := root.get_node("GameEvents")
	var content_registry := root.get_node("ContentRegistry")
	var achievements := root.get_node("Achievements")
	var relics := root.get_node("Relics")
	event_bus.fuel_collected.connect(_on_fuel_collected)
	event_bus.interaction_performed.connect(_on_interaction_performed)

	var packed_scene: PackedScene = load("res://scenes/main.tscn")
	var game := packed_scene.instantiate()
	root.add_child(game)
	await process_frame

	_expect(game.LEVELS.size() == 4, "主循环应从内容目录加载四个关卡")
	_expect(game.enemy_species_by_id.size() == 3, "主循环应加载三个敌人物种定义")
	_expect(game.current_planet_name == "Khepri-9", "当前星球名应来自 PlanetDefinition")
	_expect(game.terrain_query != null, "主循环应配置通用地形规则")
	_expect(game.interaction_resolver != null, "主循环应使用统一交互解析器")
	_expect(achievements.snapshot().size() == 3, "成就系统应装配内容目录中的成就")
	_expect(content_registry.validate_all().is_empty(), "内容目录跨资源校验应通过")

	var scout_definition: Resource = content_registry.get_enemy_species(&"scout")
	game.call("_begin_combat")
	game.call("_spawn_wave_enemy")
	var spawned_enemy := _first_wave_enemy(game.enemies)
	_expect(spawned_enemy != null, "主循环应能生成数据驱动的波次敌人")
	if spawned_enemy != null and scout_definition != null:
		_expect(
			spawned_enemy.get_species_id() == &"scout",
			"第一波敌人 species id 应来自关卡刷新表"
		)
		_expect(
			is_equal_approx(spawned_enemy.get_max_health(), scout_definition.max_health),
			"敌人数值应来自 EnemySpeciesDefinition"
		)

	var planet: Resource = content_registry.get_planet(&"khepri_9")
	_expect(planet != null, "应能读取 Khepri-9 视觉定义")
	if planet != null:
		var profile_colors: Dictionary = planet.get("surface_colors")
		_expect(
			game.planet_surface.COLOR_SURFACE_BASE == Color(profile_colors["base"]),
			"PlanetSurface 应应用数据中的星球调色板"
		)

	game.player_position = game.fuel_cells[0]["position"]
	game.player_marker.position = game.player_position
	game.call("_update_fuel_cells")
	_expect(_fuel_events == 1, "采集燃油应通过 EventBus 发布事件")

	game.player_position = game.SHIP_POSITION
	game.player_marker.position = game.player_position
	game.call("_try_interact")
	_expect(_interaction_events == 1, "统一交互解析应发布 interaction_performed")

	_expect(game.call("set_locale", "en"), "主循环应能切换到英文")
	_expect(game.LEVELS[0]["name"] == "Red Basin", "关卡显示名应随 locale 切换")
	game.call("set_locale", "zh_CN")
	_expect(game.LEVELS[0]["name"] == "赤砂盆地", "切回中文后关卡名应恢复")

	_expect(relics.add_relic("phase_boots"), "遗物系统应能应用数据中的遗物")
	_expect(
		is_equal_approx(relics.get_modifier("move_speed_multiplier", 1.0), 1.08),
		"遗物修正应可被玩法层查询"
	)
	relics.remove_relic("phase_boots")

	game.audio.stop_all()
	game.queue_free()
	for frame in range(3):
		await process_frame

	if _failures.is_empty():
		print("基建集成测试通过：内容、事件、服务、地形和交互均已接入玩法。")
		quit(0)
		return

	for failure: String in _failures:
		push_error("基建集成测试失败：" + failure)
	quit(1)


func _on_fuel_collected(_amount: int, _total: int) -> void:
	_fuel_events += 1


func _on_interaction_performed(_target_id: String, _payload: Dictionary) -> void:
	_interaction_events += 1


func _first_wave_enemy(enemies: Array[Enemy]) -> Enemy:
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy) and enemy.get_meta(&"wave_enemy", false):
			return enemy
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
