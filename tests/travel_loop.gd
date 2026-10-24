extends SceneTree

## 航程闭环测试：燃油不足、远航、切换地图和返回已访问关卡。

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := await _create_game()
	var far_index: int = game.LEVELS.size() - 1

	game.fuel = 0
	game.call("_on_destination_selected", far_index)
	_expect(
		game.phase == game.Phase.EXPLORING and game.current_level_index == 0,
		"燃油不足时不得切换关卡"
	)

	game.fuel = game.FUEL_MAX
	game.call("_open_level_select")
	var options: Array = game.call("_build_level_options")
	var far_cost := int(options[far_index]["fuel_cost"])
	_expect(far_cost > 0, "远距离关卡应存在燃油成本")
	game.call("_on_destination_selected", far_index)
	_expect(game.phase == game.Phase.LAUNCH_DEFENSE, "选定目的地后应进入发射防守")
	_expect(game.fuel == game.FUEL_MAX - far_cost, "远航应扣除对应燃油")
	game.call("_update_launch_defense", 100.0)
	_expect(game.phase == game.Phase.TRAVEL, "发射防守结束后应进入起飞")
	game.call("_process", 2.0)
	_expect(game.current_level_index == far_index, "航程结束后应加载目标地图")

	game.fuel = game.FUEL_MAX
	game.call("_open_level_select")
	game.call("_on_destination_selected", 0)
	game.call("_update_launch_defense", 100.0)
	game.call("_process", 2.0)
	_expect(game.current_level_index == 0, "已访问关卡应允许再次进入以补充燃油")
	_expect(game.phase == game.Phase.EXPLORING, "返航后应恢复探索阶段")

	game.audio.stop_all()
	game.queue_free()
	for frame in range(3):
		await process_frame

	if _failures.is_empty():
		print("航程闭环测试通过：燃油限制、发射防守、远航和返回关卡均正常。")
		quit(0)
		return

	for failure: String in _failures:
		push_error("航程闭环测试失败：" + failure)
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
