extends Node2D

## 单局主流程：驾驶、采集、建造、波次战斗与胜负结算。

enum GamePhase {
	PREPARATION,
	COMBAT,
	VICTORY,
	DEFEAT,
}

const WORLD_SIZE := Vector2(1280.0, 720.0)
const SHIP_POSITION := Vector2(640.0, 366.0)
const SAFE_RADIUS := 132.0
const SHIP_COLLISION_RADIUS := 48.0
const TURRET_MOUNT_RADIUS := 94.0
const TURRET_BUILD_COST := 14
const REPAIR_COST := 4
const REPAIR_AMOUNT := 24.0
const TOTAL_WAVES := 5
const INITIAL_PREP_TIME := 14.0
const LATER_PREP_TIME := 9.0
const CRYSTAL_COUNT := 9

const COLOR_BG := Color("#060b16")
const COLOR_PANEL := Color("#0d1a2c")
const COLOR_GRID := Color("#14263a")
const COLOR_CYAN := Color("#68e0d0")
const COLOR_ICE := Color("#d9f7f3")
const COLOR_AMBER := Color("#f2be5c")
const COLOR_RED := Color("#ff6f68")
const COLOR_VIOLET := Color("#a78bfa")

const INPUT_KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"fire": [KEY_SPACE],
	"interact": [KEY_E],
	"start_wave": [KEY_ENTER],
	"restart": [KEY_R],
	"toggle_pause": [KEY_ESCAPE],
}

@export var player_speed: float = 260.0
@export var player_fire_interval: float = 0.17

var phase: GamePhase = GamePhase.PREPARATION
var wave := 1
var prep_timer := INITIAL_PREP_TIME
var elapsed_time := 0.0
var ship_hull := 240.0
var ship_hull_max := 240.0
var resources := 8
var score := 0

var player_position := Vector2(772.0, 366.0)
var player_health := 100.0
var player_health_max := 100.0
var player_alive := true
var player_invulnerability := 0.0
var respawn_timer := 0.0
var player_fire_cooldown := 0.0
var aim_direction := Vector2.RIGHT
var last_move_direction := Vector2.RIGHT
var walk_phase := 0.0

var enemies: Array[Enemy] = []
var turrets: Array = [null, null, null, null]
var projectiles: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var crystals: Array[Dictionary] = []
var stars: Array[Dictionary] = []
var asteroids: Array[Dictionary] = []
var spawn_queue: Array[int] = []
var spawn_timer := 0.0
var is_paused := false
var rng := RandomNumberGenerator.new()
var hud: GameHUD
var audio: GameAudio


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_ensure_input_actions()
	_setup_audio()
	_setup_hud()
	_generate_environment()
	_spawn_initial_crystals()
	_start_preparation(1)
	queue_redraw()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_pause") and phase not in [GamePhase.VICTORY, GamePhase.DEFEAT]:
		_set_paused(not is_paused)

	if is_paused:
		_refresh_hud()
		return

	if phase in [GamePhase.VICTORY, GamePhase.DEFEAT]:
		if Input.is_action_just_pressed("restart"):
			get_tree().paused = false
			get_tree().reload_current_scene()
		_refresh_hud()
		return

	elapsed_time += delta
	_update_player(delta)
	_update_wave_logic(delta)
	_update_turrets(delta)
	_update_projectiles(delta)
	_update_collectibles(delta)
	_update_particles(delta)
	_refresh_hud()
	queue_redraw()


func _ensure_input_actions() -> void:
	for action_name: String in INPUT_KEYS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

		for keycode: Key in INPUT_KEYS[action_name]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keycode
			if not InputMap.action_has_event(action_name, key_event):
				InputMap.action_add_event(action_name, key_event)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUDLayer"
	canvas.layer = 20
	add_child(canvas)

	hud = GameHUD.new()
	hud.name = "GameHUD"
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _setup_audio() -> void:
	audio = GameAudio.new()
	audio.name = "GameAudio"
	add_child(audio)


func _generate_environment() -> void:
	stars.clear()
	for index in range(120):
		stars.append({
			"position": Vector2(rng.randf_range(0.0, WORLD_SIZE.x), rng.randf_range(0.0, WORLD_SIZE.y)),
			"radius": rng.randf_range(0.6, 2.1),
			"alpha": rng.randf_range(0.22, 0.9),
			"phase": rng.randf_range(0.0, TAU),
		})

	asteroids.clear()
	for index in range(16):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(210.0, 560.0)
		var asteroid_position := SHIP_POSITION + Vector2.from_angle(angle) * distance
		asteroid_position.x = clampf(asteroid_position.x, 35.0, WORLD_SIZE.x - 35.0)
		asteroid_position.y = clampf(asteroid_position.y, 35.0, WORLD_SIZE.y - 35.0)
		asteroids.append({
			"position": asteroid_position,
			"radius": rng.randf_range(5.0, 17.0),
			"rotation": rng.randf_range(0.0, TAU),
		})


func _spawn_initial_crystals() -> void:
	crystals.clear()
	for index in range(CRYSTAL_COUNT):
		crystals.append(_create_crystal())


func _create_crystal() -> Dictionary:
	var crystal_position := Vector2.ZERO
	for attempt in range(30):
		crystal_position = Vector2(
			rng.randf_range(90.0, WORLD_SIZE.x - 90.0),
			rng.randf_range(110.0, WORLD_SIZE.y - 60.0)
		)
		if crystal_position.distance_to(SHIP_POSITION) > SAFE_RADIUS + 78.0:
			break

	return {
		"position": crystal_position,
		"value": rng.randi_range(3, 5),
		"phase": rng.randf_range(0.0, TAU),
	}


func _start_preparation(next_wave: int) -> void:
	phase = GamePhase.PREPARATION
	wave = next_wave
	prep_timer = INITIAL_PREP_TIME if wave == 1 else LATER_PREP_TIME
	spawn_queue.clear()
	spawn_timer = 0.0
	if hud:
		hud.show_notice(
			"第 %d / %d 波即将抵达 · 采集资源并布防" % [wave, TOTAL_WAVES],
			COLOR_AMBER,
			2.8
		)


func _begin_combat() -> void:
	phase = GamePhase.COMBAT
	spawn_timer = 0.25
	spawn_queue.clear()

	var enemy_count := 5 + wave * 3
	for index in range(enemy_count):
		var kind: int = Enemy.EnemyKind.SCOUT
		if wave >= 3 and index % 7 == 6:
			kind = Enemy.EnemyKind.SPITTER
		elif wave >= 2 and index % 5 == 4:
			kind = Enemy.EnemyKind.BRUISER
		spawn_queue.append(kind)

	hud.show_notice("敌潮进入航道 · 守住回声号", COLOR_RED, 2.2)
	if audio:
		audio.play_wave()


func _update_wave_logic(delta: float) -> void:
	if phase == GamePhase.PREPARATION:
		prep_timer = maxf(0.0, prep_timer - delta)
		if Input.is_action_just_pressed("start_wave"):
			prep_timer = 0.0
		if prep_timer <= 0.0:
			_begin_combat()
		return

	if phase != GamePhase.COMBAT:
		return

	if not spawn_queue.is_empty():
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			_spawn_enemy()
			spawn_timer = maxf(0.25, 0.82 - wave * 0.07)
	elif enemies.is_empty():
		_complete_wave()


func _spawn_enemy() -> void:
	if spawn_queue.is_empty():
		return

	var kind: int = spawn_queue.pop_front()
	var side := rng.randi_range(0, 3)
	var spawn_position := Vector2.ZERO
	match side:
		0:
			spawn_position = Vector2(-28.0, rng.randf_range(90.0, WORLD_SIZE.y - 50.0))
		1:
			spawn_position = Vector2(WORLD_SIZE.x + 28.0, rng.randf_range(70.0, WORLD_SIZE.y - 50.0))
		2:
			spawn_position = Vector2(rng.randf_range(80.0, WORLD_SIZE.x - 80.0), -28.0)
		_:
			spawn_position = Vector2(rng.randf_range(80.0, WORLD_SIZE.x - 80.0), WORLD_SIZE.y + 28.0)

	var enemy := Enemy.new()
	enemy.position = spawn_position
	enemy.z_index = 4
	enemy.configure(kind, spawn_position, SHIP_POSITION, 1.0 + (wave - 1) * 0.14)
	add_child(enemy)
	enemies.append(enemy)
	enemy.attack_ship.connect(_on_enemy_attack_ship)
	enemy.projectile_requested.connect(_on_enemy_projectile_requested)
	enemy.defeated.connect(_on_enemy_defeated)


func _complete_wave() -> void:
	score += wave * 120
	if wave >= TOTAL_WAVES:
		_finish_game(GamePhase.VICTORY)
		return

	resources += 4
	_start_preparation(wave + 1)


func _finish_game(result: GamePhase) -> void:
	phase = result
	get_tree().paused = false
	is_paused = false

	for enemy: Enemy in enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)
	for turret in turrets:
		if turret is Turret and is_instance_valid(turret):
			turret.set_active(false)

	if result == GamePhase.VICTORY:
		_add_explosion(SHIP_POSITION, COLOR_CYAN, 28, 180.0)
		if audio:
			audio.play_victory()
	else:
		_add_explosion(SHIP_POSITION, COLOR_RED, 34, 210.0)
		if audio:
			audio.play_defeat()

	_refresh_hud()
	queue_redraw()


func _set_paused(paused_state: bool) -> void:
	is_paused = paused_state
	get_tree().paused = is_paused
	if hud:
		if is_paused:
			hud.show_notice("航行暂停 · 按 Esc 继续", COLOR_ICE, 3600.0)
		else:
			hud.clear_notice()
	_refresh_hud()


func _update_player(delta: float) -> void:
	player_invulnerability = maxf(0.0, player_invulnerability - delta)

	if not player_alive:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			player_alive = true
			player_health = player_health_max
			player_position = SHIP_POSITION + Vector2(104.0, 0.0)
			player_invulnerability = 2.0
			hud.show_notice("跃迁完成 · 驾驶员已返回航道", COLOR_CYAN, 1.6)
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if not direction.is_zero_approx():
		last_move_direction = direction.normalized()
		player_position += direction.normalized() * player_speed * delta
		walk_phase += delta * 9.0
		player_position = player_position.clamp(
			Vector2(22.0, 22.0),
			WORLD_SIZE - Vector2(22.0, 22.0)
		)

	if (
		player_position.distance_to(SHIP_POSITION) <= SAFE_RADIUS
		and player_health < player_health_max
	):
		player_health = minf(player_health_max, player_health + 10.0 * delta)

	player_fire_cooldown = maxf(0.0, player_fire_cooldown - delta)
	if Input.is_action_just_pressed("interact"):
		_try_interact()

	var firing := Input.is_action_pressed("fire") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not firing:
		return

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse_direction := get_global_mouse_position() - player_position
		if mouse_direction.length_squared() > 16.0:
			aim_direction = mouse_direction.normalized()
	else:
		var target := _nearest_enemy(player_position)
		if target:
			aim_direction = (target.global_position - player_position).normalized()
		elif not direction.is_zero_approx():
			aim_direction = direction.normalized()

	if player_fire_cooldown <= 0.0:
		_fire_player_weapon()
		player_fire_cooldown = player_fire_interval


func _fire_player_weapon() -> void:
	var origin := player_position + aim_direction * 17.0
	_add_projectile(origin, aim_direction, 18.0, 760.0, COLOR_CYAN, false, null)
	_add_particles(origin, COLOR_CYAN, 3, 55.0, aim_direction, 2.0)
	if audio:
		audio.play_shoot()


func _nearest_enemy(from_position: Vector2) -> Enemy:
	var nearest: Enemy = null
	var nearest_distance := INF
	for enemy: Enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var distance := from_position.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	return nearest


func _update_turrets(delta: float) -> void:
	if phase != GamePhase.COMBAT:
		return
	for turret in turrets:
		if turret is Turret and is_instance_valid(turret):
			turret.update_combat(delta, enemies)


func _try_interact() -> void:
	if not player_alive:
		return

	var slot_index := _nearest_turret_slot()
	if slot_index >= 0:
		var turret: Turret = turrets[slot_index]
		if turret == null:
			if resources < TURRET_BUILD_COST:
				hud.show_notice("资源不足：建造炮台需要 %d 单位" % TURRET_BUILD_COST, COLOR_RED, 1.8)
				return
			resources -= TURRET_BUILD_COST
			_build_turret(slot_index)
			hud.show_notice("炮台 #%d 已上线" % (slot_index + 1), COLOR_AMBER, 1.5)
			if audio:
				audio.play_build()
			return

		var upgrade_cost: int = turret.get_upgrade_cost()
		if turret.get_level() >= 3:
			hud.show_notice("炮台 #%d 已达到最高等级" % (slot_index + 1), COLOR_ICE, 1.5)
		elif resources < upgrade_cost:
			hud.show_notice("升级需要 %d 单位资源" % upgrade_cost, COLOR_RED, 1.8)
		elif turret.upgrade():
			resources -= upgrade_cost
			score += 25
			_add_explosion(turret.global_position, COLOR_AMBER, 8, 65.0)
			hud.show_notice("炮台 #%d 升级至 %d 级" % [slot_index + 1, turret.get_level()], COLOR_AMBER, 1.5)
			if audio:
				audio.play_upgrade()
		return

	if player_position.distance_to(SHIP_POSITION) <= SAFE_RADIUS:
		if ship_hull >= ship_hull_max:
			hud.show_notice("回声号结构完整", COLOR_CYAN, 1.3)
		elif resources < REPAIR_COST:
			hud.show_notice("资源不足：修复需要 %d 单位" % REPAIR_COST, COLOR_RED, 1.8)
		else:
			resources -= REPAIR_COST
			ship_hull = minf(ship_hull_max, ship_hull + REPAIR_AMOUNT)
			hud.show_notice("船体修复 +%d" % int(REPAIR_AMOUNT), COLOR_CYAN, 1.4)
			if audio:
				audio.play_build()


func _nearest_turret_slot() -> int:
	var nearest_index := -1
	var nearest_distance := 72.0
	for index in range(turrets.size()):
		var distance := player_position.distance_to(_get_mount_position(index))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	return nearest_index


func _build_turret(slot_index: int) -> void:
	var turret := Turret.new()
	turret.position = _get_mount_position(slot_index)
	turret.z_index = 5
	turret.configure(slot_index, turret.position)
	turret.set_base_position(SHIP_POSITION)
	add_child(turret)
	turrets[slot_index] = turret
	turret.shot_requested.connect(_on_turret_shot_requested)
	_add_explosion(turret.global_position, COLOR_AMBER, 14, 90.0)


func _get_mount_position(slot_index: int) -> Vector2:
	var angle := -PI * 0.25 + float(slot_index) * PI * 0.5
	return SHIP_POSITION + Vector2.from_angle(angle) * TURRET_MOUNT_RADIUS


func _on_turret_shot_requested(
	origin: Vector2,
	target: Node2D,
	damage: float,
	speed: float,
	color: Color
) -> void:
	var direction := Vector2.RIGHT
	if is_instance_valid(target):
		direction = (target.global_position - origin).normalized()
	_add_projectile(origin, direction, damage, speed, color, false, target)
	if audio:
		audio.play_turret_shot()


func _on_enemy_attack_ship(damage: float) -> void:
	_damage_ship(damage)


func _on_enemy_projectile_requested(
	origin: Vector2,
	direction: Vector2,
	damage: float,
	speed: float,
	color: Color
) -> void:
	_add_projectile(origin, direction, damage, speed, color, true, null)
	if audio:
		audio.play_enemy_shot()


func _on_enemy_defeated(enemy: Node, reward: int) -> void:
	if enemy in enemies:
		enemies.erase(enemy)
	resources += reward
	score += reward * 8
	_add_explosion(enemy.global_position, COLOR_AMBER, 12, 100.0)
	if audio:
		audio.play_explosion()


func _damage_ship(damage: float) -> void:
	if phase != GamePhase.COMBAT:
		return
	ship_hull = maxf(0.0, ship_hull - damage)
	if audio:
		audio.play_hit()
	_add_explosion(
		SHIP_POSITION + Vector2.from_angle(rng.randf_range(0.0, TAU)) * 42.0,
		COLOR_RED,
		7,
		85.0
	)
	if ship_hull <= 0.0:
		_finish_game(GamePhase.DEFEAT)


func _damage_player(damage: float) -> void:
	if not player_alive or player_invulnerability > 0.0:
		return
	player_health = maxf(0.0, player_health - damage)
	player_invulnerability = 0.7
	if audio:
		audio.play_hit()
	_add_explosion(player_position, COLOR_RED, 10, 110.0)
	if player_health > 0.0:
		return

	player_alive = false
	respawn_timer = 2.5
	resources = maxi(0, resources - 3)
	hud.show_notice("驾驶员失联 · 正在重构跃迁信标", COLOR_RED, 2.0)


func _add_projectile(
	origin: Vector2,
	direction: Vector2,
	damage: float,
	speed: float,
	color: Color,
	hostile: bool,
	target: Node2D
) -> void:
	projectiles.append({
		"position": origin,
		"velocity": direction.normalized() * speed,
		"speed": speed,
		"damage": damage,
		"color": color,
		"hostile": hostile,
		"target": target,
		"life": 1.6,
	})


func _update_projectiles(delta: float) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile: Dictionary = projectiles[index]
		projectile["life"] -= delta
		if projectile["life"] <= 0.0:
			projectiles.remove_at(index)
			continue

		var target = projectile["target"]
		if not projectile["hostile"] and is_instance_valid(target):
			var desired: Vector2 = (
				Vector2(target.global_position) - Vector2(projectile["position"])
			).normalized() * float(projectile["speed"])
			projectile["velocity"] = Vector2(projectile["velocity"]).lerp(desired, minf(1.0, delta * 11.0))

		projectile["position"] += Vector2(projectile["velocity"]) * delta
		var projectile_position: Vector2 = projectile["position"]

		if projectile_position.x < -80.0 or projectile_position.x > WORLD_SIZE.x + 80.0:
			projectiles.remove_at(index)
			continue
		if projectile_position.y < -80.0 or projectile_position.y > WORLD_SIZE.y + 80.0:
			projectiles.remove_at(index)
			continue

		if projectile["hostile"]:
			if player_alive and projectile_position.distance_to(player_position) <= 15.0:
				_damage_player(projectile["damage"])
				_add_explosion(projectile_position, COLOR_RED, 6, 75.0)
				projectiles.remove_at(index)
				continue
			if projectile_position.distance_to(SHIP_POSITION) <= SHIP_COLLISION_RADIUS:
				_damage_ship(projectile["damage"])
				_add_explosion(projectile_position, COLOR_RED, 8, 95.0)
				projectiles.remove_at(index)
			continue

		var hit_enemy: Enemy = null
		for enemy: Enemy in enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive():
				continue
			if projectile_position.distance_to(enemy.global_position) <= enemy.get_radius() + 4.0:
				hit_enemy = enemy
				break

		if hit_enemy:
			hit_enemy.receive_damage(projectile["damage"], Vector2(projectile["velocity"]).normalized() * 35.0)
			_add_explosion(projectile_position, projectile["color"], 6, 80.0)
			if audio:
				audio.play_hit()
			projectiles.remove_at(index)


func _add_explosion(origin: Vector2, color: Color, count: int, force: float) -> void:
	for index in range(count):
		var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
		var speed := rng.randf_range(force * 0.35, force)
		var life := rng.randf_range(0.25, 0.7)
		particles.append({
			"position": origin,
			"velocity": direction * speed,
			"life": life,
			"max_life": life,
			"color": color,
			"size": rng.randf_range(1.5, 4.2),
		})


func _add_particles(
	origin: Vector2,
	color: Color,
	count: int,
	force: float,
	direction: Vector2,
	spread: float
) -> void:
	for index in range(count):
		var velocity_direction := (direction + Vector2.from_angle(rng.randf_range(-spread, spread))).normalized()
		var life := rng.randf_range(0.12, 0.3)
		particles.append({
			"position": origin,
			"velocity": velocity_direction * rng.randf_range(force * 0.25, force),
			"life": life,
			"max_life": life,
			"color": color,
			"size": rng.randf_range(1.0, 2.6),
		})


func _update_particles(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle["life"] -= delta
		if particle["life"] <= 0.0:
			particles.remove_at(index)
			continue
		particle["position"] += Vector2(particle["velocity"]) * delta
		particle["velocity"] = Vector2(particle["velocity"]) * pow(0.08, delta)


func _update_collectibles(_delta: float) -> void:
	for index in range(crystals.size() - 1, -1, -1):
		var crystal: Dictionary = crystals[index]
		if player_position.distance_to(crystal["position"]) <= 29.0:
			resources += int(crystal["value"])
			score += 5
			_add_explosion(crystal["position"], COLOR_VIOLET, 9, 75.0)
			crystals[index] = _create_crystal()


func _refresh_hud() -> void:
	if not hud:
		return
	hud.update_state({
		"ship_hull": ship_hull,
		"ship_hull_max": ship_hull_max,
		"resources": resources,
		"wave": wave,
		"total_waves": TOTAL_WAVES,
		"wave_state": _get_wave_state_text(),
		"timer": prep_timer if phase == GamePhase.PREPARATION else -1.0,
		"player_alive": player_alive,
		"player_health": player_health,
		"player_health_max": player_health_max,
		"nearby_action": _get_context_prompt(),
		"build_prompt": "",
		"enemy_count": enemies.size(),
		"turret_count": _turret_count(),
		"score": score,
		"elapsed": elapsed_time,
		"phase": _get_phase_name(),
	})


func _get_phase_name() -> String:
	if is_paused:
		return "paused"
	match phase:
		GamePhase.PREPARATION:
			return "preparation"
		GamePhase.COMBAT:
			return "combat"
		GamePhase.VICTORY:
			return "victory"
		GamePhase.DEFEAT:
			return "defeat"
	return "preparation"


func _get_wave_state_text() -> String:
	if phase == GamePhase.PREPARATION:
		return "布防阶段"
	if phase == GamePhase.COMBAT:
		return "航道交战中"
	if phase == GamePhase.VICTORY:
		return "航道安全"
	return "回声号失联"


func _get_context_prompt() -> String:
	if not player_alive:
		return "等待驾驶员跃迁重构"
	if phase in [GamePhase.VICTORY, GamePhase.DEFEAT]:
		return "按 R 重新启航"

	var slot_index := _nearest_turret_slot()
	if slot_index >= 0:
		var turret: Turret = turrets[slot_index]
		if turret == null:
			return "E  建造炮台 #%d  ·  %d 资源" % [slot_index + 1, TURRET_BUILD_COST]
		if turret.get_level() >= 3:
			return "炮台 #%d 已达到三级" % (slot_index + 1)
		return "E  升级炮台 #%d  ·  %d 资源" % [slot_index + 1, turret.get_upgrade_cost()]

	if player_position.distance_to(SHIP_POSITION) <= SAFE_RADIUS:
		if ship_hull < ship_hull_max:
			return "E  修复船体 +%d  ·  %d 资源" % [int(REPAIR_AMOUNT), REPAIR_COST]
		return "回声号结构完整"
	return "寻找紫晶，靠近自动回收"


func _turret_count() -> int:
	var count := 0
	for turret in turrets:
		if turret is Turret:
			count += 1
	return count


func _draw() -> void:
	_draw_world_background()
	_draw_crystals()
	_draw_ship()
	_draw_player()
	_draw_projectiles()
	_draw_particles()


func _draw_world_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), COLOR_BG)
	draw_circle(Vector2(197.0, 168.0), 290.0, Color(0.10, 0.25, 0.34, 0.18))
	draw_circle(Vector2(1080.0, 620.0), 340.0, Color(0.26, 0.16, 0.37, 0.13))
	draw_circle(Vector2(900.0, 90.0), 220.0, Color(0.07, 0.29, 0.31, 0.12))

	for x in range(0, int(WORLD_SIZE.x) + 1, 64):
		draw_line(Vector2(x, 0.0), Vector2(x, WORLD_SIZE.y), COLOR_GRID, 1.0)
	for y in range(0, int(WORLD_SIZE.y) + 1, 64):
		draw_line(Vector2(0.0, y), Vector2(WORLD_SIZE.x, y), COLOR_GRID, 1.0)

	for star: Dictionary in stars:
		var alpha: float = star["alpha"] * (0.7 + sin(elapsed_time * 1.8 + star["phase"]) * 0.3)
		draw_circle(star["position"], star["radius"], Color(0.72, 0.88, 1.0, alpha))

	for asteroid: Dictionary in asteroids:
		var asteroid_position: Vector2 = asteroid["position"]
		var asteroid_radius: float = asteroid["radius"]
		draw_circle(asteroid_position, asteroid_radius + 4.0, Color(0.1, 0.18, 0.28, 0.25))
		draw_circle(asteroid_position, asteroid_radius, Color("#172438"))
		draw_arc(
			asteroid_position,
			asteroid_radius,
			asteroid["rotation"],
			asteroid["rotation"] + 2.1,
			12,
			Color("#2c4862"),
			2.0
		)

	var border_color := Color(0.36, 0.78, 0.85, 0.25)
	draw_rect(Rect2(Vector2(2.0, 2.0), WORLD_SIZE - Vector2(4.0, 4.0)), border_color, false, 2.0)


func _draw_crystals() -> void:
	for crystal: Dictionary in crystals:
		var position: Vector2 = crystal["position"]
		var bob := Vector2(0.0, sin(elapsed_time * 2.3 + crystal["phase"]) * 4.0)
		var draw_position := position + bob
		var pulse := 17.0 + sin(elapsed_time * 3.0 + crystal["phase"]) * 3.0
		draw_circle(draw_position, pulse, Color(0.56, 0.38, 0.96, 0.09))
		draw_colored_polygon(PackedVector2Array([
			draw_position + Vector2(0.0, -12.0),
			draw_position + Vector2(8.0, 0.0),
			draw_position + Vector2(0.0, 12.0),
			draw_position + Vector2(-8.0, 0.0),
		]), COLOR_VIOLET)
		draw_colored_polygon(PackedVector2Array([
			draw_position + Vector2(0.0, -9.0),
			draw_position + Vector2(3.0, 0.0),
			draw_position + Vector2(0.0, 8.0),
			draw_position + Vector2(-3.0, 0.0),
		]), COLOR_ICE)


func _draw_ship() -> void:
	var hull_ratio := clampf(ship_hull / ship_hull_max, 0.0, 1.0)
	var safe_pulse := 0.92 + sin(elapsed_time * 2.0) * 0.08
	var interactive_slot := _nearest_turret_slot()
	draw_circle(SHIP_POSITION, SAFE_RADIUS, Color(0.16, 0.52, 0.64, 0.08))
	draw_arc(
		SHIP_POSITION,
		SAFE_RADIUS * safe_pulse,
		0.0,
		TAU,
		80,
		Color(0.22, 0.64, 0.72, 0.33),
		1.5
	)

	for index in range(4):
		var mount := _get_mount_position(index)
		draw_line(SHIP_POSITION, mount, Color(0.25, 0.55, 0.68, 0.44), 7.0)
		draw_circle(mount, 17.0, COLOR_PANEL)
		draw_arc(mount, 17.0, 0.0, TAU, 24, Color(0.35, 0.65, 0.71, 0.55), 2.0)
		if index == interactive_slot:
			draw_arc(
				mount,
				23.0 + sin(elapsed_time * 5.0) * 2.0,
				0.0,
				TAU,
				28,
				COLOR_AMBER,
				2.0
			)
		if turrets[index] == null:
			draw_circle(mount, 6.0, Color(0.17, 0.32, 0.42, 0.8))
			draw_string(
				ThemeDB.fallback_font,
				mount + Vector2(-5.0, 5.0),
				str(index + 1),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				10,
				Color(0.55, 0.74, 0.76, 0.75)
			)

	var hull_color := Color("#7adce5").lerp(Color("#d65c61"), 1.0 - hull_ratio)
	draw_circle(SHIP_POSITION, 57.0, Color("#071522"))
	draw_circle(SHIP_POSITION, 52.0, Color("#203e53"))
	draw_arc(SHIP_POSITION, 52.0, -PI * 0.5, -PI * 0.5 + TAU * hull_ratio, 48, hull_color, 7.0)
	draw_colored_polygon(PackedVector2Array([
		SHIP_POSITION + Vector2(0.0, -40.0),
		SHIP_POSITION + Vector2(27.0, 22.0),
		SHIP_POSITION + Vector2(0.0, 34.0),
		SHIP_POSITION + Vector2(-27.0, 22.0),
	]), Color("#dbeaf0"))
	draw_colored_polygon(PackedVector2Array([
		SHIP_POSITION + Vector2(0.0, -29.0),
		SHIP_POSITION + Vector2(17.0, 17.0),
		SHIP_POSITION + Vector2(0.0, 24.0),
		SHIP_POSITION + Vector2(-17.0, 17.0),
	]), Color("#3b839e"))
	draw_circle(SHIP_POSITION + Vector2(0.0, 4.0), 10.0, hull_color)
	draw_circle(SHIP_POSITION + Vector2(0.0, 4.0), 4.0, COLOR_ICE)
	draw_line(SHIP_POSITION + Vector2(-48.0, 0.0), SHIP_POSITION + Vector2(-18.0, 0.0), Color("#a7c0cd"), 8.0)
	draw_line(SHIP_POSITION + Vector2(18.0, 0.0), SHIP_POSITION + Vector2(48.0, 0.0), Color("#a7c0cd"), 8.0)


func _draw_player() -> void:
	if not player_alive:
		draw_arc(
			SHIP_POSITION + Vector2(104.0, 0.0),
			18.0 + respawn_timer * 8.0,
			0.0,
			TAU,
			36,
			Color(0.4, 0.9, 0.86, 0.55),
			2.0
		)
		return

	var pulse := 0.5 + sin(walk_phase) * 0.5
	draw_circle(
		player_position - last_move_direction * 10.0,
		9.0 + pulse * 3.0,
		Color(0.34, 0.86, 0.79, 0.12)
	)
	draw_circle(player_position, 13.0, COLOR_CYAN)
	draw_circle(player_position, 8.0, COLOR_ICE)
	draw_line(player_position, player_position + aim_direction * 24.0, Color(0.68, 1.0, 0.94, 0.82), 4.0)
	draw_circle(player_position + aim_direction * 22.0, 3.0, COLOR_ICE)

	if player_health < player_health_max:
		var health_ratio := clampf(player_health / player_health_max, 0.0, 1.0)
		var health_color := COLOR_CYAN if health_ratio > 0.35 else COLOR_RED
		draw_arc(
			player_position,
			19.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * health_ratio,
			28,
			health_color,
			2.5
		)

	if player_invulnerability > 0.0:
		var flash := sin(elapsed_time * 28.0) * 0.25 + 0.55
		draw_arc(player_position, 20.0, 0.0, TAU, 24, Color(0.85, 1.0, 0.97, flash), 2.0)


func _draw_projectiles() -> void:
	for projectile: Dictionary in projectiles:
		var projectile_position: Vector2 = projectile["position"]
		var velocity: Vector2 = projectile["velocity"]
		var color: Color = projectile["color"]
		var tail_length := 15.0 if projectile["hostile"] else 20.0
		var tail := projectile_position - velocity.normalized() * tail_length
		draw_line(tail, projectile_position, Color(color, 0.5), 3.0)
		draw_circle(projectile_position, 4.0, color)
		draw_circle(projectile_position, 2.0, COLOR_ICE)


func _draw_particles() -> void:
	for particle: Dictionary in particles:
		var life_ratio: float = maxf(0.0, particle["life"] / particle["max_life"])
		var color: Color = particle["color"]
		color.a = life_ratio
		draw_circle(particle["position"], particle["size"] * life_ratio, color)
