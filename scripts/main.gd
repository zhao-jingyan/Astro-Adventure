extends Node2D

## 单局主流程：异星地表探索、风险采集、基地布防与撤退求生。

enum GamePhase {
	PREPARATION,
	COMBAT,
	VICTORY,
	DEFEAT,
}

const WORLD_SIZE := Vector2(7680.0, 5120.0)
const SHIP_POSITION := WORLD_SIZE * 0.5
const PLANET_NAME := "KHEPRI-9 · 烬砂荒原"
const SAFE_RADIUS := 156.0
const SHIP_COLLISION_RADIUS := 48.0
const TURRET_MOUNT_RADIUS := 94.0
const TURRET_BUILD_COST := 14
const REPAIR_COST := 4
const REPAIR_AMOUNT := 24.0
const TOTAL_WAVES := 5
const INITIAL_PREP_TIME := 24.0
const LATER_PREP_TIME := 38.0
const LOCAL_CRYSTAL_COUNT := 18
const REMOTE_CRYSTAL_COUNT := 18
const DEEP_CRYSTAL_COUNT := 10
const AMBIENT_CREATURE_COUNT := 16
const PLAYER_BASE_SPEED := 330.0
const PLAYER_SPRINT_MULTIPLIER := 1.58
const STAMINA_MAX := 100.0
const SPRINT_STAMINA_DRAIN := 30.0
const STAMINA_RECOVERY := 19.0
const STAMINA_RECOVERY_DELAY := 0.55
const PULSE_RADIUS := 172.0
const PULSE_COST := 26.0
const PULSE_COOLDOWN := 3.4

const COLOR_PANEL := Color("#0d1a2c")
const COLOR_CYAN := Color("#68e0d0")
const COLOR_ICE := Color("#d9f7f3")
const COLOR_AMBER := Color("#f0b45f")
const COLOR_RED := Color("#ff6f68")
const COLOR_VIOLET := Color("#a78bfa")

const INPUT_KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"sprint": [KEY_SHIFT],
	"pulse": [KEY_SPACE],
	"interact": [KEY_E],
	"start_wave": [KEY_ENTER],
	"restart": [KEY_R],
	"toggle_pause": [KEY_ESCAPE],
}

@export var player_speed: float = PLAYER_BASE_SPEED

var phase: GamePhase = GamePhase.PREPARATION
var wave := 1
var prep_timer := INITIAL_PREP_TIME
var elapsed_time := 0.0
var ship_hull := 240.0
var ship_hull_max := 240.0
var resources := 8
var deep_cores := 0
var score := 0

var player_position := SHIP_POSITION + Vector2(128.0, 0.0)
var player_health := 100.0
var player_health_max := 100.0
var player_alive := true
var player_invulnerability := 0.0
var respawn_timer := 0.0
var last_move_direction := Vector2.RIGHT
var walk_phase := 0.0
var stamina := STAMINA_MAX
var stamina_recovery_delay := 0.0
var sprinting := false
var pulse_cooldown := 0.0
var pulse_visual := 0.0

var enemies: Array[Enemy] = []
var turrets: Array = [null, null, null, null]
var projectiles: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var crystals: Array[Dictionary] = []
var spawn_queue: Array[int] = []
var spawn_timer := 0.0
var ambient_respawn_timer := 62.0
var is_paused := false
var rng := RandomNumberGenerator.new()
var hud: GameHUD
var audio: GameAudio
var camera: Camera2D
var player_marker: Node2D
var planet_surface: PlanetSurface


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_ensure_input_actions()
	_setup_audio()
	_setup_hud()
	_setup_world()
	_spawn_initial_crystals()
	_spawn_ambient_creatures()
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
	_update_ambient_life(delta)
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


func _setup_world() -> void:
	planet_surface = PlanetSurface.new()
	planet_surface.name = "Khepri9Surface"
	planet_surface.z_index = -20
	planet_surface.configure(WORLD_SIZE, SHIP_POSITION, rng.randi_range(1, 999999))
	add_child(planet_surface)

	player_marker = Node2D.new()
	player_marker.name = "PlayerTarget"
	player_marker.position = player_position
	player_marker.z_index = -1
	add_child(player_marker)

	camera = Camera2D.new()
	camera.name = "FollowCamera"
	camera.position = player_position
	camera.enabled = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(WORLD_SIZE.x)
	camera.limit_bottom = int(WORLD_SIZE.y)
	add_child(camera)
	camera.make_current()


func _spawn_initial_crystals() -> void:
	crystals.clear()
	for index in range(LOCAL_CRYSTAL_COUNT):
		crystals.append(_create_crystal("common", 360.0, 1180.0))
	for index in range(REMOTE_CRYSTAL_COUNT):
		crystals.append(_create_crystal("common", 1450.0, 3150.0))
	for index in range(DEEP_CRYSTAL_COUNT):
		crystals.append(_create_crystal("deep", 2450.0, 3420.0))


func _create_crystal(kind: String, min_distance: float, max_distance: float) -> Dictionary:
	var crystal_position := Vector2.ZERO
	var clearance := 30.0 if kind == "deep" else 20.0
	for attempt in range(30):
		crystal_position = SHIP_POSITION + Vector2.from_angle(
			rng.randf_range(0.0, TAU)
		) * rng.randf_range(min_distance, max_distance)
		crystal_position.x = clampf(crystal_position.x, 80.0, WORLD_SIZE.x - 80.0)
		crystal_position.y = clampf(crystal_position.y, 80.0, WORLD_SIZE.y - 80.0)
		if (
			crystal_position.distance_to(SHIP_POSITION) >= min_distance
			and planet_surface.get_spawn_clearance(crystal_position, clearance)
		):
			break

	var crystal := {
		"position": crystal_position,
		"kind": kind,
		"value": rng.randi_range(4, 7),
		"core_amount": 0,
		"phase": rng.randf_range(0.0, TAU),
	}
	if kind == "deep":
		crystal["value"] = rng.randi_range(12, 18)
		crystal["core_amount"] = 1
	elif min_distance >= 1400.0:
		crystal["value"] = rng.randi_range(7, 11)
	return crystal


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

	hud.show_notice("地鸣逼近营地 · 回声号进入警戒", COLOR_RED, 2.2)
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
	elif _wave_enemy_count() == 0:
		_complete_wave()


func _spawn_enemy() -> void:
	if spawn_queue.is_empty():
		return

	var kind: int = spawn_queue.pop_front()
	var spawn_position := SHIP_POSITION + Vector2.from_angle(
		rng.randf_range(0.0, TAU)
	) * rng.randf_range(760.0, 980.0)

	var enemy := Enemy.new()
	enemy.position = spawn_position
	enemy.z_index = 4
	enemy.configure(kind, spawn_position, SHIP_POSITION, 1.0 + (wave - 1) * 0.14)
	add_child(enemy)
	enemies.append(enemy)
	enemy.set_meta(&"wave_enemy", true)
	enemy.set_meta(&"home_position", spawn_position)
	enemy.attack_ship.connect(_on_enemy_attack_ship)
	enemy.attack_player.connect(_on_enemy_attack_player)
	enemy.projectile_requested.connect(_on_enemy_projectile_requested)
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.set_player_target(player_marker, 440.0, 1040.0)


func _spawn_ambient_creatures() -> void:
	for index in range(AMBIENT_CREATURE_COUNT):
		_spawn_ambient_creature(index)


func _spawn_ambient_creature(index: int) -> void:
	var kind: int = Enemy.EnemyKind.SCOUT
	if index % 5 == 4:
		kind = Enemy.EnemyKind.BRUISER
	elif index % 4 == 3:
		kind = Enemy.EnemyKind.SPITTER

	var spawn_position := _get_danger_spawn_position()

	var enemy := Enemy.new()
	enemy.position = spawn_position
	enemy.z_index = 4
	enemy.configure(kind, spawn_position, spawn_position, 1.0 + rng.randf_range(0.0, 0.22))
	add_child(enemy)
	enemies.append(enemy)
	enemy.set_meta(&"wave_enemy", false)
	enemy.set_meta(&"home_position", spawn_position)
	enemy.attack_player.connect(_on_enemy_attack_player)
	enemy.projectile_requested.connect(_on_ambient_projectile_requested.bind(enemy))
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.set_player_target(player_marker, 520.0, 1180.0)


func _get_danger_spawn_position() -> Vector2:
	var anchors: Array[Dictionary] = []
	for crystal: Dictionary in crystals:
		if Vector2(crystal["position"]).distance_to(SHIP_POSITION) >= 1400.0:
			anchors.append(crystal)

	if anchors.is_empty():
		return SHIP_POSITION + Vector2.from_angle(rng.randf_range(0.0, TAU)) * 2200.0

	var anchor: Dictionary = anchors[rng.randi_range(0, anchors.size() - 1)]
	var anchor_position: Vector2 = anchor["position"]
	for attempt in range(20):
		var candidate := anchor_position + Vector2.from_angle(
			rng.randf_range(0.0, TAU)
		) * rng.randf_range(120.0, 290.0)
		candidate.x = clampf(candidate.x, 90.0, WORLD_SIZE.x - 90.0)
		candidate.y = clampf(candidate.y, 90.0, WORLD_SIZE.y - 90.0)
		if (
			candidate.distance_to(SHIP_POSITION) >= 1280.0
			and planet_surface.get_spawn_clearance(candidate, 24.0)
		):
			return candidate
	var fallback := anchor_position + Vector2(80.0, 80.0)
	fallback.x = clampf(fallback.x, 90.0, WORLD_SIZE.x - 90.0)
	fallback.y = clampf(fallback.y, 90.0, WORLD_SIZE.y - 90.0)
	return fallback


func _wave_enemy_count() -> int:
	var count := 0
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy) and enemy.get_meta(&"wave_enemy", false):
			count += 1
	return count


func _ambient_enemy_count() -> int:
	var count := 0
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy) and not enemy.get_meta(&"wave_enemy", false):
			count += 1
	return count


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
	pulse_cooldown = maxf(0.0, pulse_cooldown - delta)
	pulse_visual = maxf(0.0, pulse_visual - delta * 2.5)

	if not player_alive:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			player_alive = true
			player_health = player_health_max
			player_position = SHIP_POSITION + Vector2(104.0, 0.0)
			player_marker.position = player_position
			player_marker.set_meta(&"alive", true)
			for enemy: Enemy in enemies:
				if is_instance_valid(enemy):
					enemy.set_hunting_enabled(true)
			camera.position = player_position
			camera.reset_smoothing()
			player_invulnerability = 2.0
			hud.show_notice("信标重构完成 · 驾驶员已返回营地", COLOR_CYAN, 1.6)
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moving := not direction.is_zero_approx()
	sprinting = moving and Input.is_action_pressed("sprint") and stamina > 0.0

	if sprinting:
		stamina = maxf(0.0, stamina - SPRINT_STAMINA_DRAIN * delta)
		stamina_recovery_delay = STAMINA_RECOVERY_DELAY
	else:
		stamina_recovery_delay = maxf(0.0, stamina_recovery_delay - delta)
		if stamina_recovery_delay <= 0.0:
			stamina = minf(STAMINA_MAX, stamina + STAMINA_RECOVERY * delta)

	if not direction.is_zero_approx():
		last_move_direction = direction.normalized()
		var speed_multiplier := PLAYER_SPRINT_MULTIPLIER if sprinting else 1.0
		player_position += direction.normalized() * player_speed * speed_multiplier * delta
		walk_phase += delta * 9.0
		player_position = player_position.clamp(
			Vector2(48.0, 48.0),
			WORLD_SIZE - Vector2(48.0, 48.0)
		)

	player_marker.position = player_position
	camera.position = player_position

	if (
		player_position.distance_to(SHIP_POSITION) <= SAFE_RADIUS
		and player_health < player_health_max
	):
		player_health = minf(player_health_max, player_health + 10.0 * delta)

	if Input.is_action_just_pressed("interact"):
		_try_interact()
	if Input.is_action_just_pressed("pulse"):
		_perform_emergency_pulse()


func _perform_emergency_pulse() -> void:
	if pulse_cooldown > 0.0 or stamina < PULSE_COST:
		return

	stamina -= PULSE_COST
	stamina_recovery_delay = STAMINA_RECOVERY_DELAY
	pulse_cooldown = PULSE_COOLDOWN
	pulse_visual = 1.0
	for enemy: Enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var offset := enemy.global_position - player_position
		if offset.length() > PULSE_RADIUS:
			continue
		var repel_direction := offset.normalized()
		if repel_direction.is_zero_approx():
			repel_direction = Vector2.from_angle(rng.randf_range(0.0, TAU))
		enemy.receive_damage(0.0, repel_direction * 470.0)
		_add_explosion(enemy.global_position, COLOR_CYAN, 4, 55.0)

	_add_explosion(player_position, COLOR_CYAN, 18, 145.0)
	if audio:
		audio.play_shoot()


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
		var core_cost := 1 if turret.get_level() == 2 else 0
		if turret.get_level() >= 3:
			hud.show_notice("炮台 #%d 已达到最高等级" % (slot_index + 1), COLOR_ICE, 1.5)
		elif resources < upgrade_cost:
			hud.show_notice("升级需要 %d 单位资源" % upgrade_cost, COLOR_RED, 1.8)
		elif deep_cores < core_cost:
			hud.show_notice("三级炮台需要 1 枚深核晶体，前往荒原远端搜寻", COLOR_RED, 2.2)
		elif turret.upgrade():
			resources -= upgrade_cost
			deep_cores -= core_cost
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


func _on_enemy_attack_player(damage: float) -> void:
	_damage_player(damage)


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


func _on_ambient_projectile_requested(
	origin: Vector2,
	direction: Vector2,
	damage: float,
	speed: float,
	color: Color,
	enemy: Enemy
) -> void:
	if not is_instance_valid(enemy) or not enemy.is_hunting_player():
		return
	_on_enemy_projectile_requested(origin, direction, damage, speed, color)


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
	player_marker.position = SHIP_POSITION
	player_marker.set_meta(&"alive", false)
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy):
			enemy.set_hunting_enabled(false)
	camera.position = SHIP_POSITION
	hud.show_notice("驾驶员失联 · 营地在回收跃迁信标", COLOR_RED, 2.0)


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
		if player_position.distance_to(crystal["position"]) <= 34.0:
			resources += int(crystal["value"])
			var core_amount := int(crystal["core_amount"])
			deep_cores += core_amount
			score += 5 if core_amount == 0 else 55
			var crystal_color := COLOR_VIOLET if core_amount > 0 else COLOR_CYAN
			_add_explosion(crystal["position"], crystal_color, 12 if core_amount > 0 else 8, 90.0)
			if core_amount > 0:
				hud.show_notice("获得深核晶体 · 可升级三级炮台", COLOR_VIOLET, 2.2)
				if audio:
					audio.play_upgrade()
			crystals[index] = _respawn_crystal(str(crystal["kind"]))


func _respawn_crystal(kind: String) -> Dictionary:
	if kind == "deep":
		return _create_crystal("deep", 2450.0, 3420.0)
	var current_distance := player_position.distance_to(SHIP_POSITION)
	if current_distance > 1300.0:
		return _create_crystal("common", 1450.0, 3150.0)
	return _create_crystal("common", 360.0, 1180.0)


func _update_ambient_life(delta: float) -> void:
	ambient_respawn_timer -= delta
	if ambient_respawn_timer > 0.0:
		return
	ambient_respawn_timer = 58.0
	if _ambient_enemy_count() < AMBIENT_CREATURE_COUNT + 6:
		_spawn_ambient_creature(rng.randi_range(0, 999))


func _refresh_hud() -> void:
	if not hud:
		return
	hud.update_state({
		"ship_hull": ship_hull,
		"ship_hull_max": ship_hull_max,
		"resources": {"晶尘": resources, "深核": deep_cores},
		"planet_name": PLANET_NAME,
		"wave": wave,
		"total_waves": TOTAL_WAVES,
		"wave_state": _get_wave_state_text(),
		"timer": prep_timer if phase == GamePhase.PREPARATION else -1.0,
		"player_alive": player_alive,
		"player_health": player_health,
		"player_health_max": player_health_max,
		"stamina": stamina,
		"stamina_max": STAMINA_MAX,
		"pulse_cooldown": pulse_cooldown,
		"nearby_action": _get_context_prompt(),
		"build_prompt": "",
		"enemy_count": enemies.size(),
		"turret_count": _turret_count(),
		"score": score,
		"elapsed": elapsed_time,
		"phase": _get_phase_name(),
		"world_size": WORLD_SIZE,
		"base_position": SHIP_POSITION,
		"player_position": player_position,
		"camera_position": camera.get_screen_center_position() if camera else player_position,
		"resource_marks": _resource_marks(),
		"enemy_marks": _enemy_marks(),
	})


func _resource_marks() -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	for crystal: Dictionary in crystals:
		marks.append({
			"position": crystal["position"],
			"kind": crystal["kind"],
		})
	return marks


func _enemy_marks() -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			marks.append({"position": enemy.global_position})
	return marks


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
		return "远征窗口"
	if phase == GamePhase.COMBAT:
		return "营地遭袭"
	if phase == GamePhase.VICTORY:
		return "荒原肃清"
	return "营地失守"


func _get_context_prompt() -> String:
	if not player_alive:
		return "等待驾驶员跃迁重构"
	if phase in [GamePhase.VICTORY, GamePhase.DEFEAT]:
		return "按 R 重新启航"

	var slot_index := _nearest_turret_slot()
	if slot_index >= 0:
		var turret: Turret = turrets[slot_index]
		if turret == null:
			return "E  建造炮台 #%d  ·  %d 晶尘" % [slot_index + 1, TURRET_BUILD_COST]
		if turret.get_level() >= 3:
			return "炮台 #%d 已达到三级" % (slot_index + 1)
		var core_suffix := " + 1 深核" if turret.get_level() == 2 else ""
		return "E  升级炮台 #%d  ·  %d 晶尘%s" % [
			slot_index + 1,
			turret.get_upgrade_cost(),
			core_suffix,
		]

	if player_position.distance_to(SHIP_POSITION) <= SAFE_RADIUS:
		if ship_hull < ship_hull_max:
			return "E  修复船体 +%d  ·  %d 晶尘" % [int(REPAIR_AMOUNT), REPAIR_COST]
		return "回声号结构完整"
	if player_position.distance_to(SHIP_POSITION) > 2200.0:
		return "深核矿区 · 怪物会主动追击，保持移动"
	return "青色晶尘供基地使用，紫色深核位于荒原远端"


func _turret_count() -> int:
	var count := 0
	for turret in turrets:
		if turret is Turret:
			count += 1
	return count


func _draw() -> void:
	_draw_crystals()
	_draw_ship()
	_draw_player()
	_draw_projectiles()
	_draw_particles()


func _draw_crystals() -> void:
	for crystal: Dictionary in crystals:
		var position: Vector2 = crystal["position"]
		var bob := Vector2(0.0, sin(elapsed_time * 2.3 + crystal["phase"]) * 4.0)
		var draw_position := position + bob
		var is_deep: bool = crystal["kind"] == "deep"
		var crystal_color := COLOR_VIOLET if is_deep else COLOR_CYAN
		var crystal_size := 17.0 if is_deep else 10.0
		var pulse := (1.0 if is_deep else 0.65) * (
			17.0 + sin(elapsed_time * 3.0 + crystal["phase"]) * 4.0
		)
		draw_circle(draw_position, pulse, Color(crystal_color, 0.11))
		if is_deep:
			draw_arc(
				draw_position,
				31.0 + sin(elapsed_time * 1.8 + crystal["phase"]) * 4.0,
				crystal["phase"],
				crystal["phase"] + PI * 1.35,
				24,
				Color(crystal_color, 0.32),
				2.0
			)
		draw_colored_polygon(PackedVector2Array([
			draw_position + Vector2(0.0, -crystal_size),
			draw_position + Vector2(crystal_size * 0.66, 0.0),
			draw_position + Vector2(0.0, crystal_size),
			draw_position + Vector2(-crystal_size * 0.66, 0.0),
		]), crystal_color)
		draw_colored_polygon(PackedVector2Array([
			draw_position + Vector2(0.0, -crystal_size * 0.72),
			draw_position + Vector2(crystal_size * 0.25, 0.0),
			draw_position + Vector2(0.0, crystal_size * 0.68),
			draw_position + Vector2(-crystal_size * 0.25, 0.0),
		]), Color("#f4ffff"))
		if is_deep:
			for shard_index in range(5):
				var shard_angle: float = float(crystal["phase"]) + TAU * float(shard_index) / 5.0
				var shard_position := draw_position + Vector2.from_angle(shard_angle) * 22.0
				draw_circle(shard_position, 3.0, Color(crystal_color, 0.82))


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
	if sprinting:
		for trail_index in range(3):
			var trail_position := player_position - last_move_direction * (20.0 + trail_index * 14.0)
			draw_line(
				trail_position - last_move_direction * 8.0,
				trail_position,
				Color(0.70, 0.88, 0.72, 0.22 - trail_index * 0.05),
				2.0
			)
	draw_circle(player_position, 13.0, COLOR_CYAN)
	draw_circle(player_position, 8.0, COLOR_ICE)
	draw_line(
		player_position,
		player_position + last_move_direction * 17.0,
		Color(0.68, 1.0, 0.94, 0.82),
		3.0
	)

	if pulse_visual > 0.0:
		var pulse_progress := 1.0 - pulse_visual
		draw_arc(
			player_position,
			24.0 + (PULSE_RADIUS - 24.0) * pulse_progress,
			0.0,
			TAU,
			64,
			Color(0.52, 1.0, 0.88, pulse_visual * 0.7),
			4.0 * pulse_visual + 1.0
		)

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
