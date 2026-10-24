extends SceneTree

## 运行时冒烟测试：资源分离、炮台、第一波游荡、怪物追击和波次推进。

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := await _create_game()
	_expect(game.phase == game.Phase.PREPARATION, "关卡应从准备倒计时阶段启动")
	_expect(game.wave == 1 and game.prep_timer > 0.0, "第一波应具有准备倒计时")
	_expect(game.planet_surface != null, "应加载当前关卡星球地图")
	_expect(game.crystals.size() > 0, "应生成炮台建设资源")
	_expect(game.fuel_cells.size() == game.FUEL_CELL_COUNT, "应生成独立燃油资源")
	_expect(game.enemies.size() >= game.CREATURE_COUNT, "应生成环境怪物")

	var resources_before: int = game.resources
	var fuel_before_crystal: int = game.fuel
	game.player_position = game.crystals[0]["position"]
	game.call("_update_collectibles")
	_expect(game.resources > resources_before, "靠近晶尘应增加建设资源")
	_expect(game.fuel == fuel_before_crystal, "采集晶尘不应消耗或增加燃油")

	var fuel_before_cell: int = game.fuel
	var resources_before_cell: int = game.resources
	game.player_position = game.fuel_cells[0]["position"]
	game.call("_update_fuel_cells")
	_expect(game.fuel > fuel_before_cell, "靠近燃油罐应增加独立燃油")
	_expect(game.resources == resources_before_cell, "采集燃油不应增加建设资源")

	game.resources = 100
	game.deep_cores = 1
	var fuel_before_build: int = game.fuel
	game.player_position = game.call("_get_mount_position", 0)
	game.call("_try_interact")
	game.call("_try_interact")
	game.call("_try_interact")
	var turret: Turret = game.turrets[0]
	_expect(turret != null and turret.get_level() == 3, "晶尘和深核应可建造并升级炮台")
	_expect(game.fuel == fuel_before_build, "炮台建设不应消耗航程燃油")

	game.call("_begin_combat")
	_expect(game.phase == game.Phase.COMBAT, "准备阶段结束应进入战斗")
	_expect(game.wave_spawn_queue.size() == 3, "第一波应只有三个敌人")
	game.call("_spawn_wave_enemy")
	var wave_enemy := _first_wave_enemy(game.enemies)
	_expect(wave_enemy != null, "战斗阶段应生成波次敌人")
	if wave_enemy:
		_expect(wave_enemy.is_wandering(), "第一波敌人应先在基地周围游荡")
		game.player_invulnerability = 0.0
		game.player_marker.position = game.player_position
		wave_enemy.global_position = game.player_position + Vector2(24.0, 0.0)
		var health_before: float = game.player_health
		wave_enemy.call("_physics_process", 0.2)
		_expect(game.player_health < health_before, "近身怪物应能主动攻击玩家")

	var stamina_before: float = game.stamina
	game.call("_perform_emergency_pulse")
	_expect(game.stamina < stamina_before, "应急脉冲应消耗体力")

	game.wave_spawn_queue.clear()
	for enemy: Enemy in game.enemies.duplicate():
		if enemy.get_meta(&"wave_enemy", false):
			enemy.receive_damage(9999.0)
	game.call("_update_wave_logic", 0.1)
	_expect(game.phase == game.Phase.PREPARATION, "清空当前波后应进入下一波准备阶段")
	_expect(game.wave == 2, "第一波结束后应推进到第二波")

	game.audio.stop_all()
	game.queue_free()
	for frame in range(3):
		await process_frame

	if _failures.is_empty():
		print("运行时冒烟测试通过：资源分离、炮台、第一波游荡与波次生命周期均正常。")
		quit(0)
		return

	for failure: String in _failures:
		push_error("运行时冒烟测试失败：" + failure)
	quit(1)


func _first_wave_enemy(enemies: Array[Enemy]) -> Enemy:
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy) and enemy.get_meta(&"wave_enemy", false):
			return enemy
	return null


func _create_game() -> Node:
	var packed_scene: PackedScene = load("res://scenes/main.tscn")
	var game := packed_scene.instantiate()
	root.add_child(game)
	await process_frame
	return game


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
