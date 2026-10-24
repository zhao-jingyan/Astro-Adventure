extends SceneTree

## 关卡生命周期：准备倒计时、战斗、清波、下一波准备和最终胜利。

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := await _create_game()
	_expect(
		game.phase == game.Phase.PREPARATION and game.wave == 1,
		"关卡应从第一波准备阶段启动"
	)
	_expect(game.prep_timer > 0.0, "准备阶段应存在倒计时")
	game.call("_update_wave_logic", game.INITIAL_PREP_TIME + 0.1)
	_expect(game.phase == game.Phase.COMBAT, "准备倒计时结束后应进入战斗")
	_expect(game.wave_spawn_queue.size() == 3, "第一波应只有三个侦察体")

	for index in range(3):
		game.call("_spawn_wave_enemy")
	var wave_enemies := _wave_enemies(game.enemies)
	var all_wandering := wave_enemies.size() == 3
	for enemy: Enemy in wave_enemies:
		all_wandering = all_wandering and enemy.is_wandering()
	_expect(all_wandering, "第一波侦察体应先在基地周围游荡")

	game.call("_update_wave_logic", 7.1)
	for enemy: Enemy in wave_enemies:
		var was_wandering := enemy.is_wandering()
		_expect(not was_wandering, "第一波游荡结束后敌人应开始进攻")

	game.wave_spawn_queue.clear()
	for enemy: Enemy in wave_enemies:
		enemy.receive_damage(9999.0)
	game.call("_update_wave_logic", 0.1)
	_expect(
		game.phase == game.Phase.PREPARATION and game.wave == 2,
		"清空第一波后应进入第二波准备倒计时"
	)

	game.wave = 5
	game.call("_begin_combat")
	game.wave_spawn_queue.clear()
	game.call("_update_wave_logic", 0.1)
	_expect(game.phase == game.Phase.VICTORY, "第五波清空后应完成关卡")
	await process_frame
	_expect(game.level_select.is_open(), "关卡完成后应打开关卡间航程图")

	game.audio.stop_all()
	game.queue_free()
	for frame in range(3):
		await process_frame

	if _failures.is_empty():
		print("关卡生命周期测试通过：倒计时、波次、清波、胜利和航线选择均正常。")
		quit(0)
		return

	for failure: String in _failures:
		push_error("关卡生命周期测试失败：" + failure)
	quit(1)


func _wave_enemies(enemies: Array[Enemy]) -> Array[Enemy]:
	var result: Array[Enemy] = []
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy) and enemy.get_meta(&"wave_enemy", false):
			result.append(enemy)
	return result


func _create_game() -> Node:
	var packed_scene: PackedScene = load("res://scenes/main.tscn")
	var game := packed_scene.instantiate()
	root.add_child(game)
	await process_frame
	return game


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
