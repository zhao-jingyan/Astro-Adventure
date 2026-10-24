extends SceneTree

## 关卡间航程测试：燃油独立支付、切图后恢复第一波准备工作，并允许返航。

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := await _create_game()
	var far_index: int = game.LEVELS.size() - 1

	game.phase = game.Phase.VICTORY
	game.fuel = 0
	game.call("_open_level_select")
	game.call("_on_destination_selected", far_index)
	_expect(
		game.phase == game.Phase.LEVEL_SELECT,
		"燃油不足时不得离开关卡选择"
	)
	game.level_select.close()

	game.fuel = game.FUEL_MAX
	game.phase = game.Phase.VICTORY
	game.call("_open_level_select")
	var options: Array = game.call("_build_level_options")
	var far_cost := int(options[far_index]["fuel_cost"])
	game.call("_on_destination_selected", far_index)
	_expect(game.phase == game.Phase.TRAVEL, "燃油充足时应在关卡间起飞")
	_expect(game.fuel == game.FUEL_MAX - far_cost, "航程应扣除独立燃油")
	game.call("_process", 2.0)
	_expect(game.current_level_index == far_index, "航程结束后应加载目标地图")
	_expect(
		game.phase == game.Phase.PREPARATION and game.wave == 1,
		"新关卡应从第一波准备倒计时重新开始"
	)

	game.fuel = game.FUEL_MAX
	game.phase = game.Phase.VICTORY
	game.call("_open_level_select")
	game.call("_on_destination_selected", 0)
	game.call("_process", 2.0)
	_expect(game.current_level_index == 0, "已访问关卡应允许返航")
	_expect(game.phase == game.Phase.PREPARATION, "返航后应恢复新关卡准备工作")

	game.audio.stop_all()
	game.queue_free()
	for frame in range(3):
		await process_frame

	if _failures.is_empty():
		print("航程闭环测试通过：关卡生命周期、独立燃油和返航均正常。")
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
