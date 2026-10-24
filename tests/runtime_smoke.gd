extends SceneTree

## 无窗口运行时冒烟测试：覆盖开波、敌人、炮台、弹道、胜负和重开状态。

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := await _create_game()
	_expect(game.phase == game.GamePhase.PREPARATION, "游戏应从未开始的布防阶段启动")
	_expect(game.camera != null, "大地图应创建跟随玩家的摄像机")
	_expect(game.planet_surface != null, "主场景应使用星球地表而不是太空背景")

	var has_remote_deep_crystal := false
	for crystal: Dictionary in game.crystals:
		if (
			crystal["kind"] == "deep"
			and Vector2(crystal["position"]).distance_to(game.SHIP_POSITION) >= 2400.0
		):
			has_remote_deep_crystal = true
			break
	_expect(has_remote_deep_crystal, "深核资源必须生成在远离营地的危险区")

	game.call("_begin_combat")
	_expect(game.phase == game.GamePhase.COMBAT, "强制开波后应进入战斗阶段")
	var enemy_count_before: int = game.enemies.size()
	for index in range(4):
		game.call("_spawn_enemy")
	_expect(
		game.enemies.size() == enemy_count_before + 4,
		"应能生成波次敌人并登记至战斗列表"
	)

	var hunter: Enemy = game.enemies[enemy_count_before]
	hunter.global_position = game.player_position + Vector2(25.0, 0.0)
	var player_health_before: float = game.player_health
	hunter.call("_physics_process", 0.1)
	_expect(hunter.is_hunting_player(), "怪物进入警戒圈后应主动锁定玩家")
	_expect(game.player_health < player_health_before, "近身怪物应能主动攻击玩家")

	game.player_invulnerability = 0.0
	hunter.global_position = game.player_position + Vector2(100.0, 0.0)
	var hunter_position_before: Vector2 = hunter.global_position
	var stamina_before: float = game.stamina
	game.call("_perform_emergency_pulse")
	hunter.call("_physics_process", 0.1)
	_expect(game.stamina < stamina_before, "应急脉冲应消耗体力")
	_expect(hunter.global_position.x > hunter_position_before.x, "应急脉冲应击退近身怪物")

	var hull_before: float = game.ship_hull
	game.enemies[enemy_count_before].attack_ship.emit(10.0)
	_expect(game.ship_hull < hull_before, "敌人攻击应能对船体造成伤害")

	game.resources = 100
	game.player_position = game.call("_get_mount_position", 0)
	game.call("_try_interact")
	var first_turret: Turret = game.turrets[0]
	_expect(first_turret != null, "靠近空炮位交互应能建造炮台")
	game.call("_try_interact")
	_expect(first_turret.get_level() == 2, "再次交互应能升级炮台")
	game.resources = 100
	game.deep_cores = 0
	game.call("_try_interact")
	_expect(first_turret.get_level() == 2, "三级炮台必须要求远区深核资源")
	game.deep_cores = 1
	game.call("_try_interact")
	_expect(first_turret.get_level() == 3, "持有深核后应能升级至三级炮台")
	_expect(game.deep_cores == 0, "三级炮台升级应消耗深核资源")

	var target: Enemy = game.enemies[enemy_count_before + 1]
	target.global_position = game.SHIP_POSITION + Vector2(180.0, 0.0)
	var target_health_before: float = target.get_health()
	first_turret.update_combat(1.0, game.enemies)
	for frame in range(20):
		game.call("_update_projectiles", 0.03)
	_expect(target.get_health() < target_health_before, "炮台弹道应能命中并伤害敌人")

	var resources_before: int = game.resources
	target.receive_damage(9999.0)
	_expect(not target.is_alive(), "玩家或炮台伤害应能击毁敌人")
	_expect(game.resources > resources_before, "击毁敌人应结算资源奖励")

	game.call("_finish_game", game.GamePhase.VICTORY)
	_expect(game.phase == game.GamePhase.VICTORY, "清空最后一波后应能进入胜利结算")

	var defeated_game := await _create_game()
	defeated_game.call("_begin_combat")
	defeated_game.call("_damage_ship", 9999.0)
	_expect(defeated_game.phase == defeated_game.GamePhase.DEFEAT, "船体归零后应进入失败结算")
	game.audio.stop_all()
	defeated_game.audio.stop_all()
	game.queue_free()
	defeated_game.queue_free()
	for frame in range(3):
		await process_frame

	if _failures.is_empty():
		print("运行时冒烟测试通过：开波、敌人、炮台、弹道、结算流程均正常。")
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
