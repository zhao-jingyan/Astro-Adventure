extends SceneTree

## 无窗口运行时冒烟测试：覆盖开波、敌人、炮台、弹道、胜负和重开状态。

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := await _create_game()
	_expect(game.phase == game.GamePhase.PREPARATION, "游戏应从未开始的布防阶段启动")

	game.call("_begin_combat")
	_expect(game.phase == game.GamePhase.COMBAT, "强制开波后应进入战斗阶段")
	for index in range(4):
		game.call("_spawn_enemy")
	_expect(game.enemies.size() == 4, "应能生成敌人并登记至战斗列表")

	var hull_before: float = game.ship_hull
	game.enemies[0].attack_ship.emit(10.0)
	_expect(game.ship_hull < hull_before, "敌人攻击应能对船体造成伤害")

	game.resources = 100
	game.player_position = game.call("_get_mount_position", 0)
	game.call("_try_interact")
	var first_turret: Turret = game.turrets[0]
	_expect(first_turret != null, "靠近空炮位交互应能建造炮台")
	game.call("_try_interact")
	_expect(first_turret.get_level() == 2, "再次交互应能升级炮台")

	var target: Enemy = game.enemies[1]
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
