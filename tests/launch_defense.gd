extends SceneTree

## 发射防守回归：验证炮台能守住起飞窗口，而无防御会失守。

const STEP := 1.0 / 60.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var defended_game := await _create_game()
	defended_game.set_process(false)
	defended_game.fuel = defended_game.FUEL_MAX
	for slot_index in range(4):
		defended_game.call("_build_turret", slot_index)
		var turret: Turret = defended_game.turrets[slot_index]
		turret.upgrade()
	var defended_result := _simulate_launch(defended_game)
	_expect(defended_result == "travel", "四座炮台应能撑过发射防守并开始起飞")
	_expect(defended_game.ship_hull > 0.0, "有炮台防守时飞船应保持完整")

	var exposed_game := await _create_game()
	exposed_game.set_process(false)
	exposed_game.fuel = exposed_game.FUEL_MAX
	var exposed_result := _simulate_launch(exposed_game)
	_expect(exposed_result == "defeat", "没有炮台防守时发射阶段应失守")

	await _dispose_game(defended_game)
	await _dispose_game(exposed_game)

	if _failures.is_empty():
		print("发射防守测试通过：炮台防守可起飞，无防御会失守。")
		quit(0)
		return

	for failure: String in _failures:
		push_error("发射防守测试失败：" + failure)
	quit(1)


func _simulate_launch(game: Node) -> String:
	game.call("_on_destination_selected", game.LEVELS.size() - 1)
	var simulated_time := 0.0
	while (
		game.phase == game.Phase.LAUNCH_DEFENSE
		and simulated_time < 90.0
	):
		game.call("_update_launch_defense", STEP)
		for enemy: Enemy in game.enemies.duplicate():
			if is_instance_valid(enemy):
				enemy.call("_physics_process", STEP)
		game.call("_update_turrets", STEP)
		game.call("_update_projectiles", STEP)
		game.call("_update_particles", STEP)
		simulated_time += STEP

	if game.phase == game.Phase.TRAVEL:
		return "travel"
	if game.phase == game.Phase.DEFEAT:
		return "defeat"
	return "timeout"


func _create_game() -> Node:
	var packed_scene: PackedScene = load("res://scenes/main.tscn")
	var game := packed_scene.instantiate()
	root.add_child(game)
	await process_frame
	return game


func _dispose_game(game: Node) -> void:
	game.audio.stop_all()
	game.queue_free()
	for frame in range(3):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
