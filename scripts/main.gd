extends Node2D

## 核心循环：采集燃油、返回着陆船、选择航程，然后进入下一张地图关卡。

enum Phase {
	EXPLORING,
	LEVEL_SELECT,
	LAUNCH_DEFENSE,
	TRAVEL,
	DEFEAT,
}

const WORLD_SIZE := Vector2(7680.0, 5120.0)
const SHIP_POSITION := WORLD_SIZE * 0.5
const PLANET_NAME := "KHEPRI-9"
const FUEL_MAX := 40
const PLAYER_SPEED := 155.0
const PLAYER_SPRINT_MULTIPLIER := 1.55
const PLAYER_INTERACT_RADIUS := 112.0
const STAMINA_MAX := 100.0
const SPRINT_DRAIN := 20.0
const STAMINA_RECOVERY := 15.0
const STAMINA_RECOVERY_DELAY := 0.7
const PULSE_RADIUS := 142.0
const PULSE_COST := 24.0
const PULSE_COOLDOWN := 4.0
const FUEL_CELL_COUNT := 15
const CREATURE_COUNT := 10
const TURRET_MOUNT_RADIUS := 92.0
const TURRET_BUILD_FUEL_COST := 3
const REPAIR_FUEL_COST := 3
const REPAIR_AMOUNT := 36.0
const SHIP_HULL_MAX := 240.0
const NETWORK_PORT := 7777
const NETWORK_SEND_INTERVAL := 0.09

const COLOR_CYAN := Color("#68e0d0")
const COLOR_ICE := Color("#d9f7f3")
const COLOR_AMBER := Color("#f0b45f")
const COLOR_RED := Color("#ff6f68")
const COLOR_VIOLET := Color("#a78bfa")
const COLOR_DARK := Color(0.025, 0.018, 0.015, 1.0)

const LEVELS := [
	{
		"id": "red_basin",
		"name": "赤砂盆地",
		"map_distance": Vector2(0.0, 0.0),
		"danger": 1,
		"description": "着陆区附近分布着低产燃油罐，适合补充基础航程。",
		"seed": 137,
	},
	{
		"id": "rust_rift",
		"name": "铁锈裂谷",
		"map_distance": Vector2(1.0, 0.15),
		"danger": 2,
		"description": "撕裂地表下埋有较高产燃油，掠食体活动频繁。",
		"seed": 271,
	},
	{
		"id": "glass_dunes",
		"name": "琉璃沙海",
		"map_distance": Vector2(0.8, -1.25),
		"danger": 2,
		"description": "强风磨出的玻璃沙丘，燃油点稀疏但单次储量更高。",
		"seed": 419,
	},
	{
		"id": "deep_highland",
		"name": "深核高原",
		"map_distance": Vector2(2.35, 0.45),
		"danger": 3,
		"description": "远航终点。高浓度燃油和高威胁怪物同时出现。",
		"seed": 733,
	},
]

const INPUT_KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"sprint": [KEY_SHIFT],
	"pulse": [KEY_SPACE],
	"interact": [KEY_E],
	"network_host": [KEY_F2],
	"network_join": [KEY_F3],
	"network_leave": [KEY_F4],
}

var phase: Phase = Phase.EXPLORING
var current_level_index := 0
var visited_levels: Dictionary = {0: true}
var fuel := 5
var pending_level_index := -1
var travel_timer := 0.0
var elapsed_time := 0.0
var ship_hull := SHIP_HULL_MAX
var siege_timer := 0.0
var siege_spawn_timer := 0.0
var siege_queue: Array[int] = []

var player_position := SHIP_POSITION + Vector2(112.0, 0.0)
var player_health := 100.0
var player_health_max := 100.0
var player_alive := true
var player_invulnerability := 0.0
var respawn_timer := 0.0
var stamina := STAMINA_MAX
var stamina_recovery_delay := 0.0
var sprinting := false
var player_moving := false
var pulse_cooldown := 0.0
var pulse_visual := 0.0
var last_move_direction := Vector2.RIGHT
var walk_phase := 0.0

var fuel_cells: Array[Dictionary] = []
var enemies: Array[Enemy] = []
var turrets: Array = [null, null, null, null]
var projectiles: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var remote_players: Dictionary = {}

var network_role := "offline"
var network_connected := false
var network_sync_timer := 0.0
var network_smoke_mode := false
var network_smoke_complete := false

var rng := RandomNumberGenerator.new()
var camera: Camera2D
var player_marker: Node2D
var planet_surface: PlanetSurface
var hud: GameHUD
var level_select: LevelSelect
var audio: GameAudio


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 60
	rng.randomize()
	_ensure_input_actions()
	_setup_audio()
	_setup_hud()
	_setup_level_select()
	_setup_world()
	_connect_multiplayer_signals()
	_load_level(0, true)
	_parse_launch_arguments()
	queue_redraw()


func _process(delta: float) -> void:
	_handle_network_shortcuts()

	if phase == Phase.DEFEAT:
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		_refresh_hud()
		return

	if phase == Phase.LEVEL_SELECT:
		_refresh_hud()
		return

	if phase == Phase.LAUNCH_DEFENSE:
		elapsed_time += delta
		_update_player(delta)
		_update_launch_defense(delta)
		_update_turrets(delta)
		_update_projectiles(delta)
		_update_particles(delta)
		_update_remote_players(delta)
		_update_network_sync(delta)
		_refresh_hud()
		queue_redraw()
		return

	if phase == Phase.TRAVEL:
		travel_timer = maxf(0.0, travel_timer - delta)
		if travel_timer <= 0.0:
			_load_level(pending_level_index, true)
			phase = Phase.EXPLORING
			if audio:
				audio.play_music(&"main")
			if hud:
				hud.show_notice("已抵达 %s" % LEVELS[current_level_index]["name"], COLOR_CYAN, 1.8)
		_refresh_hud()
		queue_redraw()
		return

	elapsed_time += delta
	_update_player(delta)
	_update_fuel_cells()
	_update_turrets(delta)
	_update_projectiles(delta)
	_update_particles(delta)
	_update_remote_players(delta)
	_update_network_sync(delta)
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


func _setup_audio() -> void:
	audio = GameAudio.new()
	audio.name = "GameAudio"
	add_child(audio)
	audio.play_music(&"main", 0.0)


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


func _setup_level_select() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "LevelSelectLayer"
	canvas.layer = 30
	add_child(canvas)

	level_select = LevelSelect.new()
	level_select.name = "LevelSelect"
	level_select.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(level_select)
	level_select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_select.destination_selected.connect(_on_destination_selected)
	level_select.closed.connect(_on_level_select_closed)


func _setup_world() -> void:
	player_marker = Node2D.new()
	player_marker.name = "PlayerTarget"
	player_marker.z_index = -1
	add_child(player_marker)

	camera = Camera2D.new()
	camera.name = "FollowCamera"
	camera.enabled = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 4.5
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(WORLD_SIZE.x)
	camera.limit_bottom = int(WORLD_SIZE.y)
	add_child(camera)
	camera.make_current()


func _load_level(level_index: int, reset_player: bool) -> void:
	current_level_index = clampi(level_index, 0, LEVELS.size() - 1)
	visited_levels[LEVELS[current_level_index]["id"]] = true
	var level: Dictionary = LEVELS[current_level_index]
	rng.seed = int(level["seed"])

	if is_instance_valid(planet_surface):
		planet_surface.queue_free()
	planet_surface = PlanetSurface.new()
	planet_surface.name = "Khepri9Surface"
	planet_surface.z_index = -20
	planet_surface.configure(WORLD_SIZE, SHIP_POSITION, int(level["seed"]))
	add_child(planet_surface)

	for enemy: Enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	for turret in turrets:
		if turret is Turret and is_instance_valid(turret):
			turret.queue_free()
	turrets = [null, null, null, null]
	projectiles.clear()
	particles.clear()
	siege_queue.clear()
	siege_timer = 0.0
	siege_spawn_timer = 0.0
	ship_hull = SHIP_HULL_MAX

	if reset_player:
		player_position = SHIP_POSITION + Vector2(112.0, 0.0)
		player_alive = true
		player_health = player_health_max
		stamina = STAMINA_MAX
		respawn_timer = 0.0
		player_invulnerability = 1.0
		last_move_direction = Vector2.RIGHT
		camera.position = player_position
		camera.reset_smoothing()

	player_marker.position = player_position
	player_marker.set_meta(&"alive", player_alive)
	_spawn_fuel_cells()
	_spawn_creatures()
	queue_redraw()


func _spawn_fuel_cells() -> void:
	fuel_cells.clear()
	for index in range(FUEL_CELL_COUNT):
		var min_distance := 360.0
		var max_distance := 1050.0
		var amount := 1
		if index >= 7:
			min_distance = 1250.0
			max_distance = 2350.0
			amount = 2
		if index >= 12:
			min_distance = 2350.0
			max_distance = 3350.0
			amount = 3
		fuel_cells.append(_create_fuel_cell(min_distance, max_distance, amount))


func _create_fuel_cell(min_distance: float, max_distance: float, amount: int) -> Dictionary:
	var cell_position := SHIP_POSITION
	for attempt in range(30):
		cell_position = SHIP_POSITION + Vector2.from_angle(
			rng.randf_range(0.0, TAU)
		) * rng.randf_range(min_distance, max_distance)
		cell_position.x = clampf(cell_position.x, 80.0, WORLD_SIZE.x - 80.0)
		cell_position.y = clampf(cell_position.y, 80.0, WORLD_SIZE.y - 80.0)
		if planet_surface.get_spawn_clearance(cell_position, 22.0):
			break

	return {
		"position": cell_position,
		"amount": amount,
		"phase": rng.randf_range(0.0, TAU),
	}


func _spawn_creatures() -> void:
	var anchors: Array[Dictionary] = []
	for cell: Dictionary in fuel_cells:
		if Vector2(cell["position"]).distance_to(SHIP_POSITION) > 1200.0:
			anchors.append(cell)

	for index in range(CREATURE_COUNT):
		var kind: int = Enemy.EnemyKind.SCOUT
		if index % 5 == 4:
			kind = Enemy.EnemyKind.BRUISER
		elif index % 4 == 3:
			kind = Enemy.EnemyKind.SPITTER

		var spawn_position := SHIP_POSITION + Vector2(1900.0, 0.0)
		if not anchors.is_empty():
			var anchor: Dictionary = anchors[index % anchors.size()]
			spawn_position = Vector2(anchor["position"]) + Vector2.from_angle(
				rng.randf_range(0.0, TAU)
			) * rng.randf_range(120.0, 280.0)
		spawn_position.x = clampf(spawn_position.x, 80.0, WORLD_SIZE.x - 80.0)
		spawn_position.y = clampf(spawn_position.y, 80.0, WORLD_SIZE.y - 80.0)

		var enemy := Enemy.new()
		enemy.position = spawn_position
		enemy.z_index = 4
		enemy.configure(kind, spawn_position, spawn_position, 1.0)
		add_child(enemy)
		enemies.append(enemy)
		enemy.attack_player.connect(_on_enemy_attack_player)
		enemy.projectile_requested.connect(_on_enemy_projectile_requested.bind(enemy))
		enemy.set_player_target(player_marker, 410.0, 940.0)


func _update_player(delta: float) -> void:
	player_invulnerability = maxf(0.0, player_invulnerability - delta)
	pulse_cooldown = maxf(0.0, pulse_cooldown - delta)
	pulse_visual = maxf(0.0, pulse_visual - delta * 2.2)

	if not player_alive:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			player_alive = true
			player_health = player_health_max
			player_position = SHIP_POSITION + Vector2(96.0, 0.0)
			player_marker.position = player_position
			player_marker.set_meta(&"alive", true)
			for enemy: Enemy in enemies:
				if is_instance_valid(enemy):
					enemy.set_hunting_enabled(true)
			camera.position = player_position
			camera.reset_smoothing()
			player_invulnerability = 2.0
			if hud:
				hud.show_notice("返回着陆船 · 燃油损失 1", COLOR_CYAN, 1.6)
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player_moving = not direction.is_zero_approx()
	sprinting = player_moving and Input.is_action_pressed("sprint") and stamina > 0.0

	if sprinting:
		stamina = maxf(0.0, stamina - SPRINT_DRAIN * delta)
		stamina_recovery_delay = STAMINA_RECOVERY_DELAY
	else:
		stamina_recovery_delay = maxf(0.0, stamina_recovery_delay - delta)
		if stamina_recovery_delay <= 0.0:
			stamina = minf(STAMINA_MAX, stamina + STAMINA_RECOVERY * delta)

	if player_moving:
		last_move_direction = direction.normalized()
		var speed_multiplier := PLAYER_SPRINT_MULTIPLIER if sprinting else 1.0
		player_position += direction.normalized() * PLAYER_SPEED * speed_multiplier * delta
		walk_phase += delta * 7.0
		player_position = player_position.clamp(
			Vector2(48.0, 48.0),
			WORLD_SIZE - Vector2(48.0, 48.0)
		)

	player_marker.position = player_position
	camera.position = player_position

	if Input.is_action_just_pressed("interact"):
		_try_interact()
	if Input.is_action_just_pressed("pulse"):
		_perform_emergency_pulse()


func _try_interact() -> void:
	var slot_index := _nearest_turret_slot()
	if slot_index >= 0:
		_try_turret_interaction(slot_index)
		return

	if player_position.distance_to(SHIP_POSITION) > PLAYER_INTERACT_RADIUS:
		return

	if phase == Phase.LAUNCH_DEFENSE:
		if ship_hull >= SHIP_HULL_MAX:
			if hud:
				hud.show_notice("船体完好", COLOR_CYAN, 1.0)
		elif fuel < REPAIR_FUEL_COST:
			if hud:
				hud.show_notice("修复需要 %d 燃油" % REPAIR_FUEL_COST, COLOR_RED, 1.4)
		else:
			fuel -= REPAIR_FUEL_COST
			ship_hull = minf(SHIP_HULL_MAX, ship_hull + REPAIR_AMOUNT)
			if hud:
				hud.show_notice("船体 +%d" % int(REPAIR_AMOUNT), COLOR_CYAN, 1.2)
		return

	if network_role != "offline":
		if hud:
			hud.show_notice("联机测试暂只验证同场移动", COLOR_AMBER, 1.8)
		return
	_open_level_select()


func _try_turret_interaction(slot_index: int) -> void:
	var turret: Turret = turrets[slot_index]
	if turret == null:
		if fuel < TURRET_BUILD_FUEL_COST:
			if hud:
				hud.show_notice("建造炮台需要 %d 燃油" % TURRET_BUILD_FUEL_COST, COLOR_RED, 1.4)
			return
		fuel -= TURRET_BUILD_FUEL_COST
		_build_turret(slot_index)
		if hud:
			hud.show_notice("炮台 #%d 已上线" % (slot_index + 1), COLOR_AMBER, 1.2)
		return

	var upgrade_cost: int = turret.get_upgrade_cost()
	if turret.get_level() >= 3:
		if hud:
			hud.show_notice("炮台已达到三级", COLOR_CYAN, 1.0)
	elif fuel < upgrade_cost:
		if hud:
			hud.show_notice("升级需要 %d 燃油" % upgrade_cost, COLOR_RED, 1.4)
	elif turret.upgrade():
		fuel -= upgrade_cost
		if hud:
			hud.show_notice("炮台升级至 %d 级" % turret.get_level(), COLOR_AMBER, 1.2)
		if audio:
			audio.play_upgrade()


func _nearest_turret_slot() -> int:
	var nearest_index := -1
	var nearest_distance := 70.0
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
	_add_explosion(turret.global_position, COLOR_AMBER, 10, 65.0)
	if audio:
		audio.play_build()


func _get_mount_position(slot_index: int) -> Vector2:
	var angle := -PI * 0.25 + float(slot_index) * PI * 0.5
	return SHIP_POSITION + Vector2.from_angle(angle) * TURRET_MOUNT_RADIUS


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
		var repel := offset.normalized()
		if repel.is_zero_approx():
			repel = Vector2.from_angle(rng.randf_range(0.0, TAU))
		enemy.receive_damage(0.0, repel * 360.0)
		_add_explosion(enemy.global_position, COLOR_CYAN, 3, 40.0)

	_add_explosion(player_position, COLOR_CYAN, 14, 105.0)
	if audio:
		audio.play_shoot()


func _update_fuel_cells() -> void:
	for index in range(fuel_cells.size()):
		var cell: Dictionary = fuel_cells[index]
		if player_position.distance_to(cell["position"]) > 34.0:
			continue
		var gained := mini(int(cell["amount"]), FUEL_MAX - fuel)
		fuel = mini(FUEL_MAX, fuel + int(cell["amount"]))
		_add_explosion(cell["position"], COLOR_AMBER, 9, 70.0)
		if gained > 0:
			if hud:
				hud.show_notice("燃油 +%d" % gained, COLOR_AMBER, 1.2)
		else:
			if hud:
				hud.show_notice("燃油已满", COLOR_AMBER, 1.0)
		var distance := Vector2(cell["position"]).distance_to(SHIP_POSITION)
		fuel_cells[index] = _create_fuel_cell(
			1250.0 if distance > 1200.0 else 360.0,
			2500.0 if distance > 1200.0 else 1050.0,
			2 if distance > 1200.0 else 1
		)


func _update_turrets(delta: float) -> void:
	if phase != Phase.LAUNCH_DEFENSE:
		return
	for turret in turrets:
		if turret is Turret and is_instance_valid(turret):
			turret.update_combat(delta, enemies)


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
	projectiles.append({
		"position": origin,
		"velocity": direction * speed,
		"speed": speed,
		"target": target,
		"damage": damage,
		"color": color,
		"hostile": false,
		"life": 2.4,
	})
	if audio:
		audio.play_turret_shot()


func _on_enemy_attack_ship(damage: float) -> void:
	_damage_ship(damage)


func _on_enemy_defeated(enemy: Node, _reward: int) -> void:
	if enemy in enemies:
		enemies.erase(enemy)
	_add_explosion(enemy.global_position, COLOR_AMBER, 9, 75.0)
	if audio:
		audio.play_explosion()


func _on_enemy_attack_player(damage: float) -> void:
	_damage_player(damage)


func _on_enemy_projectile_requested(
	origin: Vector2,
	direction: Vector2,
	damage: float,
	speed: float,
	color: Color,
	enemy: Enemy
) -> void:
	if (
		not is_instance_valid(enemy)
		or (phase != Phase.LAUNCH_DEFENSE and not enemy.is_hunting_player())
	):
		return
	projectiles.append({
		"position": origin,
		"velocity": direction.normalized() * speed,
		"speed": speed,
		"target": null,
		"damage": damage,
		"color": color,
		"hostile": true,
		"life": 3.2,
	})
	if audio:
		audio.play_enemy_shot()


func _damage_ship(damage: float) -> void:
	if phase != Phase.LAUNCH_DEFENSE:
		return
	ship_hull = maxf(0.0, ship_hull - damage)
	_add_explosion(
		SHIP_POSITION + Vector2.from_angle(rng.randf_range(0.0, TAU)) * 46.0,
		COLOR_RED,
		7,
		72.0
	)
	if audio:
		audio.play_hit()
	if ship_hull <= 0.0:
		_finish_defeat()


func _damage_player(damage: float) -> void:
	if not player_alive or player_invulnerability > 0.0:
		return
	player_health = maxf(0.0, player_health - damage)
	player_invulnerability = 0.8
	_add_explosion(player_position, COLOR_RED, 8, 85.0)
	if audio:
		audio.play_hit()
	if player_health > 0.0:
		return

	player_alive = false
	respawn_timer = 2.2
	fuel = maxi(0, fuel - 1)
	player_marker.position = SHIP_POSITION
	player_marker.set_meta(&"alive", false)
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy):
			enemy.set_hunting_enabled(false)
	camera.position = SHIP_POSITION
	if hud:
		hud.show_notice("驾驶员失联 · 正在回收信标", COLOR_RED, 2.0)


func _update_projectiles(delta: float) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile: Dictionary = projectiles[index]
		projectile["life"] -= delta
		var target = projectile.get("target")
		if (
			not projectile["hostile"]
			and target != null
			and is_instance_valid(target)
		):
			var desired: Vector2 = (
				Vector2(target.global_position) - Vector2(projectile["position"])
			).normalized() * float(projectile["speed"])
			projectile["velocity"] = Vector2(projectile["velocity"]).lerp(
				desired,
				minf(1.0, delta * 9.0)
			)
		projectile["position"] += Vector2(projectile["velocity"]) * delta
		var projectile_position: Vector2 = projectile["position"]

		if projectile["life"] <= 0.0:
			projectiles.remove_at(index)
			continue

		if not projectile["hostile"]:
			var hit_enemy: Enemy = null
			for enemy: Enemy in enemies:
				if not is_instance_valid(enemy) or not enemy.is_alive():
					continue
				if projectile_position.distance_to(enemy.global_position) <= enemy.get_radius() + 4.0:
					hit_enemy = enemy
					break
			if hit_enemy:
				hit_enemy.receive_damage(
					projectile["damage"],
					Vector2(projectile["velocity"]).normalized() * 24.0
				)
				_add_explosion(projectile_position, projectile["color"], 4, 55.0)
				projectiles.remove_at(index)
			continue

		if projectile_position.distance_to(player_position) <= 15.0 and player_alive:
			_damage_player(projectile["damage"])
			_add_explosion(projectile_position, COLOR_RED, 5, 60.0)
			projectiles.remove_at(index)
			continue
		if projectile_position.distance_to(SHIP_POSITION) <= 66.0:
			_damage_ship(projectile["damage"])
			_add_explosion(projectile_position, Color(COLOR_AMBER, 0.65), 4, 45.0)
			projectiles.remove_at(index)


func _update_particles(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle["life"] -= delta
		if particle["life"] <= 0.0:
			particles.remove_at(index)
			continue
		particle["position"] += Vector2(particle["velocity"]) * delta
		particle["velocity"] = Vector2(particle["velocity"]) * pow(0.16, delta)


func _add_explosion(origin: Vector2, color: Color, count: int, force: float) -> void:
	for index in range(count):
		var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
		var life := rng.randf_range(0.3, 0.75)
		particles.append({
			"position": origin,
			"velocity": direction * rng.randf_range(force * 0.3, force),
			"life": life,
			"max_life": life,
			"color": color,
			"size": rng.randf_range(1.3, 3.3),
		})


func _open_level_select() -> void:
	phase = Phase.LEVEL_SELECT
	get_tree().paused = true
	if audio:
		audio.play_music(&"discovery")
	level_select.open(_build_level_options(), current_level_index, fuel)


func _build_level_options() -> Array:
	var current_distance: Vector2 = LEVELS[current_level_index]["map_distance"]
	var options: Array = []
	for index in range(LEVELS.size()):
		var level: Dictionary = LEVELS[index].duplicate(true)
		var distance := current_distance.distance_to(Vector2(level["map_distance"]))
		level["fuel_cost"] = 0 if index == current_level_index else maxi(1, ceili(distance * 3.4))
		level["visited"] = visited_levels.has(level["id"])
		options.append(level)
	return options


func _on_destination_selected(level_index: int) -> void:
	if level_index < 0 or level_index >= LEVELS.size():
		return
	var options := _build_level_options()
	var cost := int(options[level_index]["fuel_cost"])
	if level_index == current_level_index:
		level_select.close()
		return
	if fuel < cost:
		return

	fuel -= cost
	pending_level_index = level_index
	_begin_launch_defense(level_index, cost)
	get_tree().paused = false
	level_select.close()


func _begin_launch_defense(level_index: int, travel_cost: int) -> void:
	phase = Phase.LAUNCH_DEFENSE
	if audio:
		audio.play_music(&"anomaly")
	ship_hull = SHIP_HULL_MAX
	siege_timer = 22.0 + float(LEVELS[level_index]["danger"]) * 3.0
	siege_spawn_timer = 0.35
	siege_queue.clear()

	var danger := int(LEVELS[level_index]["danger"])
	var enemy_count := 5 + danger * 2 + int(ceil(float(travel_cost) * 0.4))
	for index in range(enemy_count):
		var kind: int = Enemy.EnemyKind.SCOUT
		if index % 6 == 5:
			kind = Enemy.EnemyKind.SPITTER
		elif index % 7 == 6:
			kind = Enemy.EnemyKind.BRUISER
		siege_queue.append(kind)

	if hud:
		hud.show_notice(
			"发射准备开始 · 守住飞船 %.0f 秒" % siege_timer,
			COLOR_AMBER,
			2.2
		)
	if audio:
		audio.play_wave()


func _update_launch_defense(delta: float) -> void:
	siege_timer = maxf(0.0, siege_timer - delta)
	if not siege_queue.is_empty():
		siege_spawn_timer -= delta
		if siege_spawn_timer <= 0.0:
			_spawn_siege_enemy()
			siege_spawn_timer = 1.05

	if siege_timer <= 0.0:
		siege_queue.clear()
		phase = Phase.TRAVEL
		travel_timer = 1.1
		if hud:
			hud.show_notice("引擎稳定 · 正在起飞", COLOR_CYAN, 1.4)


func _spawn_siege_enemy() -> void:
	if siege_queue.is_empty():
		return
	var kind: int = siege_queue.pop_front()
	var spawn_position := SHIP_POSITION + Vector2.from_angle(
		rng.randf_range(0.0, TAU)
	) * rng.randf_range(460.0, 650.0)
	var destination_danger := int(LEVELS[pending_level_index]["danger"])
	var enemy := Enemy.new()
	enemy.position = spawn_position
	enemy.z_index = 4
	enemy.configure(kind, spawn_position, SHIP_POSITION, 1.0 + destination_danger * 0.08)
	add_child(enemy)
	enemies.append(enemy)
	enemy.set_meta(&"siege_enemy", true)
	enemy.attack_ship.connect(_on_enemy_attack_ship)
	enemy.projectile_requested.connect(_on_enemy_projectile_requested.bind(enemy))
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.set_hunting_enabled(false)


func _finish_defeat() -> void:
	if phase == Phase.DEFEAT:
		return
	phase = Phase.DEFEAT
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)
	for turret in turrets:
		if turret is Turret and is_instance_valid(turret):
			turret.set_active(false)
	if audio:
		audio.play_defeat()
		audio.stop_music()
	if hud:
		hud.show_notice("飞船失守 · 按 R 重新开始", COLOR_RED, 3.0)


func _on_level_select_closed() -> void:
	if phase != Phase.LEVEL_SELECT:
		return
	get_tree().paused = false
	phase = Phase.EXPLORING
	if audio:
		audio.play_music(&"main")


func _refresh_hud() -> void:
	if not hud:
		return
	hud.update_state({
		"location_name": "%s / %s" % [PLANET_NAME, LEVELS[current_level_index]["name"]],
		"fuel": fuel,
		"fuel_max": FUEL_MAX,
		"player_health": player_health,
		"player_health_max": player_health_max,
		"stamina": stamina,
		"stamina_max": STAMINA_MAX,
		"nearby_action": _get_nearby_action(),
		"network_status": network_role,
		"network_peers": remote_players.size(),
		"phase": _get_phase_name(),
		"ship_hull": ship_hull,
		"ship_hull_max": SHIP_HULL_MAX,
		"defense_timer": siege_timer,
		"siege_enemies": _siege_enemy_count(),
	})


func _get_nearby_action() -> String:
	if not player_alive:
		return "等待返回着陆船"
	if phase == Phase.TRAVEL:
		return "航程进行中"
	var slot_index := _nearest_turret_slot()
	if slot_index >= 0:
		var turret: Turret = turrets[slot_index]
		if turret == null:
			return "E  建造炮台 #%d · %d 燃油" % [slot_index + 1, TURRET_BUILD_FUEL_COST]
		if turret.get_level() >= 3:
			return "炮台 #%d 已达到三级" % (slot_index + 1)
		return "E  升级炮台 #%d · %d 燃油" % [slot_index + 1, turret.get_upgrade_cost()]
	if player_position.distance_to(SHIP_POSITION) <= PLAYER_INTERACT_RADIUS:
		if phase == Phase.LAUNCH_DEFENSE:
			return "起飞防守中 · E 修复船体"
		return "E  登船并选择航线"
	return "寻找橙色燃油罐"


func _get_phase_name() -> String:
	if phase == Phase.TRAVEL:
		return "travel"
	if phase == Phase.LEVEL_SELECT:
		return "level_select"
	if phase == Phase.LAUNCH_DEFENSE:
		return "defense"
	if phase == Phase.DEFEAT:
		return "defeat"
	if not player_alive:
		return "down"
	return "exploring"


func _siege_enemy_count() -> int:
	var count := 0
	for enemy: Enemy in enemies:
		if (
			is_instance_valid(enemy)
			and enemy.has_meta(&"siege_enemy")
			and enemy.get_meta(&"siege_enemy", false)
		):
			count += 1
	return count


func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _parse_launch_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	network_smoke_mode = "--network-smoke" in args
	if "--host" in args:
		call_deferred("_start_host")
	elif "--join" in args:
		call_deferred("_join_localhost")


func _handle_network_shortcuts() -> void:
	if Input.is_action_just_pressed("network_host"):
		_start_host()
	elif Input.is_action_just_pressed("network_join"):
		_join_localhost()
	elif Input.is_action_just_pressed("network_leave"):
		_disconnect_network()


func _start_host() -> void:
	if network_role != "offline":
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(NETWORK_PORT, 4)
	if error != OK:
		if hud:
			hud.show_notice("创建房间失败：%s" % error_string(error), COLOR_RED, 2.0)
		return
	multiplayer.multiplayer_peer = peer
	network_role = "host"
	network_connected = true
	remote_players.clear()
	if hud:
		hud.show_notice("联机测试：主机已就绪", COLOR_CYAN, 1.8)
	print("NETWORK_HOST_READY port=%d" % NETWORK_PORT)


func _join_localhost() -> void:
	if network_role != "offline":
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client("127.0.0.1", NETWORK_PORT)
	if error != OK:
		if hud:
			hud.show_notice("加入房间失败：%s" % error_string(error), COLOR_RED, 2.0)
		return
	multiplayer.multiplayer_peer = peer
	network_role = "client"
	network_connected = false
	remote_players.clear()
	if hud:
		hud.show_notice("联机测试：正在连接本机主机", COLOR_AMBER, 1.8)


func _disconnect_network() -> void:
	if network_role == "offline":
		return
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	network_role = "offline"
	network_connected = false
	remote_players.clear()
	if hud:
		hud.show_notice("已结束联机测试", COLOR_CYAN, 1.4)


func _on_peer_connected(peer_id: int) -> void:
	if hud:
		hud.show_notice("联机测试：对端已连接 #%d" % peer_id, COLOR_CYAN, 1.6)


func _on_peer_disconnected(peer_id: int) -> void:
	remote_players.erase(peer_id)
	if hud:
		hud.show_notice("联机测试：对端已断开", COLOR_AMBER, 1.4)


func _on_connected_to_server() -> void:
	network_role = "client"
	network_connected = true
	if hud:
		hud.show_notice("联机测试：连接成功", COLOR_CYAN, 1.5)
	_request_session_sync.rpc_id(1)


func _on_connection_failed() -> void:
	network_role = "offline"
	network_connected = false
	remote_players.clear()
	if hud:
		hud.show_notice("联机测试：连接失败", COLOR_RED, 2.0)


func _on_server_disconnected() -> void:
	network_role = "offline"
	network_connected = false
	remote_players.clear()
	if hud:
		hud.show_notice("联机测试：主机已断开", COLOR_AMBER, 1.8)


@rpc("any_peer", "call_remote", "reliable")
func _request_session_sync() -> void:
	if multiplayer.get_unique_id() != 1:
		return
	var requester := multiplayer.get_remote_sender_id()
	_apply_session_state.rpc_id(requester, current_level_index, fuel)


@rpc("authority", "call_remote", "reliable")
func _apply_session_state(level_index: int, host_fuel: int) -> void:
	fuel = clampi(host_fuel, 0, FUEL_MAX)
	if level_index != current_level_index:
		_load_level(level_index, true)
	if hud:
		hud.show_notice("已同步主机关卡", COLOR_CYAN, 1.4)


func _update_network_sync(delta: float) -> void:
	if network_role == "offline" or not network_connected:
		return
	network_sync_timer -= delta
	if network_sync_timer > 0.0:
		return
	network_sync_timer = NETWORK_SEND_INTERVAL
	_receive_network_position.rpc(
		multiplayer.get_unique_id(),
		player_position,
		last_move_direction,
		player_moving
	)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_network_position(
	peer_id: int,
	remote_position: Vector2,
	facing: Vector2,
	moving: bool
) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender != peer_id:
		return
	remote_players[sender] = {
		"position": remote_position,
		"facing": facing,
		"moving": moving,
		"age": 0.0,
	}
	if network_smoke_mode:
		_finish_network_smoke(sender)


func _update_remote_players(delta: float) -> void:
	var stale_ids: Array[int] = []
	for peer_id: int in remote_players:
		var remote: Dictionary = remote_players[peer_id]
		remote["age"] = float(remote["age"]) + delta
		if remote["age"] > 2.5:
			stale_ids.append(peer_id)
	for peer_id: int in stale_ids:
		remote_players.erase(peer_id)


func _finish_network_smoke(peer_id: int) -> void:
	if network_smoke_complete:
		return
	network_smoke_complete = true
	print("NETWORK_SMOKE_OK role=%s peer=%d" % [network_role, peer_id])
	get_tree().create_timer(0.3).timeout.connect(get_tree().quit)


func _draw() -> void:
	_draw_fuel_cells()
	_draw_ship()
	_draw_player()
	_draw_remote_players()
	_draw_projectiles()
	_draw_particles()
	if phase == Phase.TRAVEL:
		_draw_travel_overlay()


func _draw_fuel_cells() -> void:
	for cell: Dictionary in fuel_cells:
		var position: Vector2 = cell["position"]
		var bob := Vector2(0.0, sin(elapsed_time * 1.8 + cell["phase"]) * 3.0)
		var center := position + bob
		var pulse := 19.0 + sin(elapsed_time * 2.0 + cell["phase"]) * 3.0
		draw_circle(center, pulse, Color(COLOR_AMBER, 0.1))
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-7.0, -11.0),
			center + Vector2(7.0, -11.0),
			center + Vector2(9.0, 9.0),
			center + Vector2(0.0, 14.0),
			center + Vector2(-9.0, 9.0),
		]), COLOR_AMBER)
		draw_rect(Rect2(center + Vector2(-3.0, -7.0), Vector2(6.0, 11.0)), COLOR_ICE)
		if int(cell["amount"]) > 1:
			draw_arc(center, 25.0, 0.0, TAU, 24, Color(COLOR_AMBER, 0.55), 2.0)


func _draw_ship() -> void:
	draw_circle(SHIP_POSITION, 118.0, Color(0.30, 0.65, 0.52, 0.08))
	draw_arc(SHIP_POSITION, 118.0, 0.0, TAU, 64, Color(COLOR_CYAN, 0.32), 2.0)
	var interactive_slot := _nearest_turret_slot()
	for index in range(turrets.size()):
		var mount := _get_mount_position(index)
		draw_line(SHIP_POSITION, mount, Color(COLOR_CYAN, 0.24), 5.0)
		draw_circle(mount, 16.0, Color(0.04, 0.08, 0.08, 0.92))
		draw_arc(mount, 16.0, 0.0, TAU, 24, Color(COLOR_CYAN, 0.42), 2.0)
		if index == interactive_slot:
			draw_arc(mount, 22.0, 0.0, TAU, 28, COLOR_AMBER, 2.0)
		if turrets[index] == null:
			draw_circle(mount, 5.0, Color(COLOR_AMBER, 0.55))
	draw_circle(SHIP_POSITION, 48.0, Color("#18252a"))
	draw_colored_polygon(PackedVector2Array([
		SHIP_POSITION + Vector2(0.0, -38.0),
		SHIP_POSITION + Vector2(25.0, 22.0),
		SHIP_POSITION + Vector2(0.0, 35.0),
		SHIP_POSITION + Vector2(-25.0, 22.0),
	]), Color("#dce8df"))
	draw_colored_polygon(PackedVector2Array([
		SHIP_POSITION + Vector2(0.0, -28.0),
		SHIP_POSITION + Vector2(16.0, 17.0),
		SHIP_POSITION + Vector2(0.0, 24.0),
		SHIP_POSITION + Vector2(-16.0, 17.0),
	]), Color("#3f7668"))
	draw_circle(SHIP_POSITION + Vector2(0.0, 4.0), 7.0, COLOR_CYAN)
	draw_string(
		ThemeDB.fallback_font,
		SHIP_POSITION + Vector2(-22.0, 65.0),
		"ECHO",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		Color(COLOR_ICE, 0.68)
	)


func _draw_player() -> void:
	if not player_alive:
		return
	if sprinting:
		for trail_index in range(3):
			var trail_position := player_position - last_move_direction * (18.0 + trail_index * 12.0)
			draw_line(
				trail_position - last_move_direction * 6.0,
				trail_position,
				Color(0.68, 0.86, 0.69, 0.2 - trail_index * 0.045),
				2.0
			)
	draw_circle(player_position, 12.0, COLOR_CYAN)
	draw_circle(player_position, 7.0, COLOR_ICE)
	draw_line(
		player_position,
		player_position + last_move_direction * 15.0,
		Color(COLOR_ICE, 0.8),
		3.0
	)

	if player_health < player_health_max:
		var ratio := player_health / player_health_max
		draw_arc(
			player_position,
			18.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * ratio,
			28,
			COLOR_CYAN if ratio > 0.35 else COLOR_RED,
			2.0
		)
	if pulse_visual > 0.0:
		var progress := 1.0 - pulse_visual
		draw_arc(
			player_position,
			22.0 + (PULSE_RADIUS - 22.0) * progress,
			0.0,
			TAU,
			48,
			Color(COLOR_CYAN, pulse_visual * 0.7),
			3.0
		)


func _draw_remote_players() -> void:
	for peer_id: int in remote_players:
		var remote: Dictionary = remote_players[peer_id]
		var remote_position: Vector2 = remote["position"]
		draw_circle(remote_position, 12.0, COLOR_VIOLET)
		draw_circle(remote_position, 6.0, COLOR_ICE)
		draw_string(
			ThemeDB.fallback_font,
			remote_position + Vector2(-18.0, -20.0),
			"P%d" % peer_id,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			11,
			COLOR_VIOLET
		)


func _draw_projectiles() -> void:
	for projectile: Dictionary in projectiles:
		var position: Vector2 = projectile["position"]
		var velocity: Vector2 = projectile["velocity"]
		var color: Color = projectile["color"]
		draw_line(position - velocity.normalized() * 11.0, position, Color(color, 0.48), 2.0)
		draw_circle(position, 3.0, color)


func _draw_particles() -> void:
	for particle: Dictionary in particles:
		var ratio: float = maxf(0.0, particle["life"] / particle["max_life"])
		var color: Color = particle["color"]
		color.a *= ratio
		draw_circle(particle["position"], particle["size"] * ratio, color)


func _draw_travel_overlay() -> void:
	var view_size := get_viewport_rect().size
	var top_left := camera.position - view_size * 0.5
	var alpha := 0.22 + sin((1.1 - travel_timer) * PI) * 0.45
	draw_rect(Rect2(top_left, view_size), Color(COLOR_DARK, clampf(alpha, 0.0, 0.72)))
