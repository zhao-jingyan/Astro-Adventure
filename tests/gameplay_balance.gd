extends SceneTree

## 数值回归：模拟玩家建满三级炮台但不参与射击时的五波防守。

const SIMULATION_STEP := 1.0 / 60.0
const MAX_SIMULATION_SECONDS := 360.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load("res://scenes/main.tscn")
	var game := packed_scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)

	game.resources = 999
	for slot_index in range(4):
		game.call("_build_turret", slot_index)
		var turret: Turret = game.turrets[slot_index]
		turret.set_base_position(game.SHIP_POSITION)
		turret.upgrade()
		turret.upgrade()

	game.call("_begin_combat")
	var simulated_seconds := 0.0
	while (
		game.phase not in [game.GamePhase.VICTORY, game.GamePhase.DEFEAT]
		and simulated_seconds < MAX_SIMULATION_SECONDS
	):
		game.call("_update_wave_logic", SIMULATION_STEP)
		for enemy: Enemy in game.enemies.duplicate():
			if is_instance_valid(enemy):
				enemy.call("_physics_process", SIMULATION_STEP)
		game.call("_update_turrets", SIMULATION_STEP)
		game.call("_update_projectiles", SIMULATION_STEP)
		game.call("_update_particles", SIMULATION_STEP)
		simulated_seconds += SIMULATION_STEP

	var final_phase = game.phase
	var final_wave: int = game.wave
	var final_hull: float = game.ship_hull
	var final_score: int = game.score
	var victory_phase = game.GamePhase.VICTORY
	game.audio.stop_all()
	game.queue_free()
	for frame in range(3):
		await process_frame

	if final_phase != victory_phase:
		push_error(
			"数值模拟失败：四级三级炮台未能守住，结果=%s，波次=%d，船体=%.1f，模拟时长=%.1f 秒"
			% [final_phase, final_wave, final_hull, simulated_seconds]
		)
		quit(1)
		return

	print(
		"数值模拟通过：五波防守完成，用时 %.1f 秒，剩余船体 %.1f，得分 %d。"
		% [simulated_seconds, final_hull, final_score]
	)
	quit(0)
