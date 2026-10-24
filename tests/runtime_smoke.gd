extends SceneTree

## 运行时冒烟测试：燃油采集、怪物追击、应急脉冲与航程图入口。

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := await _create_game()
	_expect(game.phase == game.Phase.EXPLORING, "游戏应从地表探索阶段启动")
	_expect(game.planet_surface != null, "主场景应加载星球地表")
	_expect(game.fuel_cells.size() == game.FUEL_CELL_COUNT, "当前关卡应生成燃油点")
	_expect(game.enemies.size() == game.CREATURE_COUNT, "当前关卡应生成主动怪物")

	var hunter: Enemy = game.enemies[0]
	hunter.global_position = game.player_position + Vector2(24.0, 0.0)
	game.player_invulnerability = 0.0
	var health_before: float = game.player_health
	hunter.call("_physics_process", 0.2)
	_expect(hunter.is_hunting_player(), "怪物进入警戒圈后应主动锁定玩家")
	_expect(game.player_health < health_before, "近身怪物应能攻击玩家")

	game.player_invulnerability = 0.0
	hunter.global_position = game.player_position + Vector2(95.0, 0.0)
	var hunter_position: Vector2 = hunter.global_position
	var stamina_before: float = game.stamina
	game.call("_perform_emergency_pulse")
	hunter.call("_physics_process", 0.12)
	_expect(game.stamina < stamina_before, "应急脉冲应消耗体力")
	_expect(hunter.global_position.x > hunter_position.x, "应急脉冲应击退近身怪物")

	var fuel_before: int = game.fuel
	game.player_position = game.fuel_cells[0]["position"]
	game.call("_update_fuel_cells")
	_expect(game.fuel > fuel_before, "靠近燃油罐应增加燃油")

	game.fuel = 10
	game.player_position = game.call("_get_mount_position", 0)
	var turret_fuel_before: int = game.fuel
	game.call("_try_interact")
	_expect(game.turrets[0] != null, "靠近炮位应能消耗燃油建造炮台")
	_expect(game.fuel < turret_fuel_before, "建造炮台应与航程共用燃油")

	game.player_position = game.SHIP_POSITION
	game.call("_try_interact")
	_expect(game.phase == game.Phase.LEVEL_SELECT, "靠近着陆船交互应打开航程图")
	_expect(game.level_select.is_open(), "航程图应进入可见状态")

	var options: Array = game.call("_build_level_options")
	var target_index := -1
	for index in range(options.size()):
		if (
			index != game.current_level_index
			and int(options[index]["fuel_cost"]) <= game.fuel
		):
			target_index = index
			break
	_expect(target_index >= 0, "当前燃油应至少支持一个目的地")
	if target_index >= 0:
		var fuel_before_travel: int = game.fuel
		game.call("_on_destination_selected", target_index)
		_expect(game.phase == game.Phase.LAUNCH_DEFENSE, "确认目的地后应先进入发射防守")
		_expect(game.fuel < fuel_before_travel, "起飞应消耗燃油")
		var hull_before_defense: float = game.ship_hull
		game.call("_damage_ship", 10.0)
		_expect(game.ship_hull < hull_before_defense, "围攻敌人应能损伤飞船")
		game.call("_update_launch_defense", 0.5)
		_expect(game.call("_siege_enemy_count") > 0, "发射防守期间应生成围攻敌群")
		game.call("_update_launch_defense", 100.0)
		_expect(game.phase == game.Phase.TRAVEL, "发射防守结束后应开始起飞")
		game.call("_process", 2.0)
		_expect(game.phase == game.Phase.EXPLORING, "航程结束后应进入新关卡")
		_expect(game.current_level_index == target_index, "抵达后应切换至目的地关卡")

	game.audio.stop_all()
	game.queue_free()
	for frame in range(3):
		await process_frame

	if _failures.is_empty():
		print("运行时冒烟测试通过：燃油、炮台、追击、击退、发射防守和航程切换均正常。")
		quit(0)
		return

	for failure: String in _failures:
		push_error("运行时冒烟测试失败：" + failure)
	quit(1)


func _create_game() -> Node:
	var packed_scene: PackedScene = load("res://scenes/main.tscn")
	var game := packed_scene.instantiate()
	root.add_child(game)
	await process_frame
	return game


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
