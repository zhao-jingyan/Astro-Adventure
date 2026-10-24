class_name Enemy
extends Node2D

## 俯视角塔防/射击游戏中的基础敌人。
## 由主场景创建后先调用 configure，再加入场景树。

enum EnemyKind {
	SCOUT,
	BRUISER,
	SPITTER,
}

signal attack_ship(damage: float)
signal attack_player(damage: float)
signal projectile_requested(
	origin: Vector2,
	direction: Vector2,
	damage: float,
	speed: float,
	color: Color
)
signal defeated(enemy: Node, reward: int)

const FORMATION_GOLDEN_ANGLE := 2.399963229728653
const ARRIVAL_DISTANCE := 2.5
const HIT_FLASH_DURATION := 0.1
const MAX_KNOCKBACK_SPEED := 560.0
const KNOCKBACK_DECELERATION := 760.0
const PLAYER_MELEE_REACH := 24.0

var _kind: EnemyKind = EnemyKind.SCOUT
var _target_position := Vector2.ZERO
var _approach_position := Vector2.ZERO
var _formation_angle := 0.0
var _formation_radius := 0.0
var _facing := Vector2.RIGHT

var _configured := false
var _alive := false
var _health := 0.0
var _max_health := 0.0
var _move_speed := 0.0
var _radius := 0.0
var _reward := 0
var _attack_damage := 0.0
var _attack_interval := 1.0
var _attack_timer := 0.0
var _attack_range := 0.0
var _projectile_speed := 0.0
var _projectile_color := Color.WHITE
var _body_color := Color.WHITE

var _knockback_velocity := Vector2.ZERO
var _flash_time := 0.0
var _animation_time := 0.0

var _player_target: Node2D
var _aggro_radius := 430.0
var _leash_radius := 1050.0
var _hunting_player := false
var _hunting_enabled := true


func _ready() -> void:
	set_physics_process(_configured and _alive)
	queue_redraw()


func _process(delta: float) -> void:
	if not _configured or not _alive:
		return

	_animation_time += delta
	if _flash_time > 0.0:
		_flash_time = maxf(_flash_time - delta, 0.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not _configured or not _alive:
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_apply_knockback(delta)

	# 玩家追击拥有更高优先级，追击期间不会再执行基地攻击分支。
	if _update_player_hunt(delta):
		return

	_update_base_behavior(delta)


func _update_base_behavior(delta: float) -> void:
	var to_target := _target_position - global_position
	var target_distance := to_target.length()

	if _kind == EnemyKind.SPITTER:
		if target_distance > 0.001:
			_facing = to_target / target_distance

		# 进入射程即可开火，但仍继续移动到自己的环形落点。
		if target_distance <= _attack_range:
			_try_ranged_attack()
		_move_toward_approach_position(delta)
		return

	var to_approach := _approach_position - global_position
	var approach_distance := to_approach.length()
	if approach_distance > ARRIVAL_DISTANCE:
		_move_toward_approach_position(delta)
		return

	if target_distance > 0.001:
		_facing = to_target / target_distance
	_try_melee_attack()


func set_player_target(
	target: Node2D,
	aggro_radius: float = 430.0,
	leash_radius: float = 1050.0
) -> void:
	_aggro_radius = maxf(aggro_radius, 0.0)
	_leash_radius = maxf(leash_radius, _aggro_radius)
	_hunting_player = false

	if not is_instance_valid(target) or target.is_queued_for_deletion():
		_player_target = null
		return

	_player_target = target


func is_hunting_player() -> bool:
	return _hunting_player and _has_valid_player_target()


func set_hunting_enabled(enabled: bool) -> void:
	_hunting_enabled = enabled
	if not _hunting_enabled:
		_hunting_player = false


func clear_player_target() -> void:
	_player_target = null
	_hunting_player = false


## 配置敌人的类型、出生点、基地中心和波次强度。
## target_position 是基地中心，不是敌人最终站位。
func configure(
	kind: EnemyKind,
	start_position: Vector2,
	target_position: Vector2,
	wave_scale: float
) -> void:
	var safe_scale := maxf(wave_scale, 0.1)
	var base_health := 0.0
	var base_speed := 0.0
	var base_radius := 0.0
	var base_reward := 0
	var base_damage := 0.0
	var base_interval := 1.0
	var formation_gap := 0.0

	_kind = kind
	match kind:
		EnemyKind.SCOUT:
			base_health = 42.0
			base_speed = 136.0
			base_radius = 12.0
			base_reward = 6
			base_damage = 9.0
			base_interval = 1.05
			formation_gap = 54.0
			_projectile_speed = 0.0
			_attack_range = 0.0
			_projectile_color = Color("#6ff7ff")
			_body_color = Color("#35d9ff")
		EnemyKind.BRUISER:
			base_health = 180.0
			base_speed = 58.0
			base_radius = 22.0
			base_reward = 20
			base_damage = 22.0
			base_interval = 2.15
			formation_gap = 92.0
			_projectile_speed = 0.0
			_attack_range = 0.0
			_projectile_color = Color("#ffb15f")
			_body_color = Color("#ff7a45")
		EnemyKind.SPITTER:
			base_health = 74.0
			base_speed = 88.0
			base_radius = 15.0
			base_reward = 13
			base_damage = 11.0
			base_interval = 1.55
			formation_gap = 166.0
			_projectile_speed = 310.0
			_attack_range = 350.0
			_projectile_color = Color("#9dff6a")
			_body_color = Color("#b66cff")
		_:
			push_warning("未知敌人类型，按侦察兵处理。")
			configure(EnemyKind.SCOUT, start_position, target_position, wave_scale)
			return

	_max_health = base_health * safe_scale
	_health = _max_health
	_move_speed = base_speed * clampf(0.9 + safe_scale * 0.1, 0.9, 1.35)
	_radius = base_radius * clampf(sqrt(safe_scale), 0.9, 1.25)
	_reward = maxi(1, roundi(float(base_reward) * (0.85 + safe_scale * 0.15)))
	_attack_damage = base_damage * (1.0 + (safe_scale - 1.0) * 0.18)

	# 为同一波次中的敌人错开攻击节奏，避免声音和特效完全同步。
	var cadence_variation := 0.94 + fposmod(float(get_instance_id()), 13.0) * 0.01
	_attack_interval = base_interval \
		* clampf(1.06 - safe_scale * 0.06, 0.68, 1.05) \
		* cadence_variation

	_target_position = target_position
	global_position = start_position
	_configured = true
	_alive = true
	_flash_time = 0.0
	_attack_timer = 0.0
	_knockback_velocity = Vector2.ZERO
	_hunting_player = false

	# 用稳定的黄金角序列给每个实例分配环形站位。
	var kind_offset := float(kind) * 0.71
	_formation_angle = fposmod(
		float(get_instance_id()) * FORMATION_GOLDEN_ANGLE + kind_offset,
		TAU
	)
	_formation_radius = formation_gap + _radius
	_approach_position = _target_position + Vector2.from_angle(_formation_angle) * _formation_radius

	var initial_direction := _approach_position - global_position
	if not initial_direction.is_zero_approx():
		_facing = initial_direction.normalized()
	elif not (_target_position - global_position).is_zero_approx():
		_facing = (_target_position - global_position).normalized()

	set_physics_process(true)
	set_process(true)
	queue_redraw()


## 承受伤害并施加击退冲量；生命归零时只触发一次 defeated。
func receive_damage(amount: float, impulse: Vector2 = Vector2.ZERO) -> void:
	if not _configured or not _alive:
		return

	if amount > 0.0:
		_health = maxf(_health - amount, 0.0)
		_flash_time = HIT_FLASH_DURATION

	if not impulse.is_zero_approx():
		_knockback_velocity = (_knockback_velocity + impulse).limit_length(MAX_KNOCKBACK_SPEED)

	if _health <= 0.0:
		_die()
	queue_redraw()


func get_radius() -> float:
	return _radius


func get_kind() -> EnemyKind:
	return _kind


func is_alive() -> bool:
	return _alive


func get_health() -> float:
	return _health


func get_max_health() -> float:
	return _max_health


func get_reward() -> int:
	return _reward


func get_target_position() -> Vector2:
	return _target_position


func _update_player_hunt(delta: float) -> bool:
	if not _hunting_enabled or not _has_valid_player_target():
		return false

	var player_position := _player_target.global_position
	var distance_to_player := global_position.distance_to(player_position)

	if not _hunting_player:
		if distance_to_player > _aggro_radius:
			return false
		_hunting_player = true

	# 超出牵引范围后立即放弃，当前帧回到原有基地行为。
	if distance_to_player > _leash_radius:
		_hunting_player = false
		return false

	var to_player := player_position - global_position
	if not to_player.is_zero_approx():
		_facing = to_player.normalized()

	if _kind == EnemyKind.SPITTER:
		if distance_to_player <= _attack_range:
			_try_ranged_attack()
		_move_toward_position(player_position, delta)
		return true

	var melee_reach := _radius + PLAYER_MELEE_REACH
	if distance_to_player > melee_reach:
		_move_toward_position(player_position, delta)
	else:
		_try_melee_player_attack()
	return true


func _has_valid_player_target() -> bool:
	if not is_instance_valid(_player_target) or _player_target.is_queued_for_deletion():
		clear_player_target()
		return false

	# 约定玩家节点通过 is_alive() 暴露存活状态；失效或死亡时安全回退。
	if _player_target.has_method("is_alive"):
		var alive_value: Variant = _player_target.call("is_alive")
		if not bool(alive_value):
			clear_player_target()
			return false
	else:
		# 兼容直接暴露存活布尔属性的玩家节点。
		for property_name: StringName in [&"is_alive", &"player_alive", &"alive"]:
			if property_name in _player_target:
				var state_value: Variant = _player_target.get(property_name)
				if state_value is bool and not bool(state_value):
					clear_player_target()
					return false
				break

	return true


func _move_toward_approach_position(delta: float) -> void:
	var offset := _approach_position - global_position
	var distance := offset.length()
	if distance <= ARRIVAL_DISTANCE:
		return

	var direction := offset / distance
	_facing = direction
	global_position += direction * minf(_move_speed * delta, distance)
	queue_redraw()


func _move_toward_position(destination: Vector2, delta: float) -> void:
	var offset := destination - global_position
	var distance := offset.length()
	if distance <= ARRIVAL_DISTANCE:
		return

	var direction := offset / distance
	global_position += direction * minf(_move_speed * delta, distance)
	queue_redraw()


func _apply_knockback(delta: float) -> void:
	if _knockback_velocity.is_zero_approx():
		return

	global_position += _knockback_velocity * delta
	_knockback_velocity = _knockback_velocity.move_toward(
		Vector2.ZERO,
		KNOCKBACK_DECELERATION * delta
	)
	queue_redraw()


func _try_melee_attack() -> void:
	if _attack_timer > 0.0:
		return

	attack_ship.emit(_attack_damage)
	_attack_timer = _attack_interval


func _try_melee_player_attack() -> void:
	if _attack_timer > 0.0:
		return

	attack_player.emit(_attack_damage)
	_attack_timer = _attack_interval


func _try_ranged_attack() -> void:
	if _attack_timer > 0.0:
		return

	var direction := _facing
	if direction.is_zero_approx():
		direction = Vector2.RIGHT

	var origin := global_position + direction * (_radius * 1.45)
	projectile_requested.emit(
		origin,
		direction,
		_attack_damage,
		_projectile_speed,
		_projectile_color
	)
	_attack_timer = _attack_interval


func _die() -> void:
	if not _alive:
		return

	_alive = false
	clear_player_target()
	set_physics_process(false)
	set_process(false)
	defeated.emit(self, _reward)
	queue_free()


func _draw() -> void:
	if not _configured:
		return

	var flash_ratio := clampf(_flash_time / HIT_FLASH_DURATION, 0.0, 1.0)
	var body_color := _body_color.lerp(Color.WHITE, flash_ratio * 0.82)
	var pulse := 1.0 + sin(_animation_time * 4.2) * 0.035
	_draw_glow(_body_color, pulse)

	match _kind:
		EnemyKind.SCOUT:
			_draw_scout(body_color)
		EnemyKind.BRUISER:
			_draw_bruiser(body_color)
		EnemyKind.SPITTER:
			_draw_spitter(body_color)

	_draw_health_bar()
	if flash_ratio > 0.0:
		draw_arc(
			Vector2.ZERO,
			_radius * 1.42,
			0.0,
			TAU,
			32,
			Color(1.0, 1.0, 1.0, flash_ratio * 0.72),
			2.0,
			true
		)


func _draw_glow(color: Color, pulse: float) -> void:
	draw_circle(
		Vector2.ZERO,
		_radius * 1.85 * pulse,
		Color(color.r, color.g, color.b, 0.035)
	)
	draw_circle(
		Vector2.ZERO,
		_radius * 1.48 * pulse,
		Color(color.r, color.g, color.b, 0.055)
	)
	draw_circle(
		Vector2.ZERO,
		_radius * 1.16 * pulse,
		Color(color.r, color.g, color.b, 0.09)
	)


func _draw_scout(color: Color) -> void:
	var radius := _radius
	var flame := PackedVector2Array([
		_oriented(Vector2(-radius * 0.72, 0.0)),
		_oriented(Vector2(-radius * 1.55, -radius * 0.34)),
		_oriented(Vector2(-radius * 1.18, 0.0)),
		_oriented(Vector2(-radius * 1.55, radius * 0.34)),
	])
	draw_colored_polygon(flame, Color(1.0, 0.56, 0.18, 0.72))

	var hull := PackedVector2Array([
		_oriented(Vector2(radius * 1.5, 0.0)),
		_oriented(Vector2(radius * 0.18, -radius * 0.72)),
		_oriented(Vector2(-radius * 0.72, -radius * 1.05)),
		_oriented(Vector2(-radius * 0.5, -radius * 0.2)),
		_oriented(Vector2(-radius * 0.96, 0.0)),
		_oriented(Vector2(-radius * 0.5, radius * 0.2)),
		_oriented(Vector2(-radius * 0.72, radius * 1.05)),
		_oriented(Vector2(radius * 0.18, radius * 0.72)),
	])
	draw_colored_polygon(hull, color.darkened(0.18))
	draw_polyline(_closed_points(hull), color.lightened(0.35), 1.8, true)

	var left_wing := PackedVector2Array([
		_oriented(Vector2(radius * 0.1, -radius * 0.22)),
		_oriented(Vector2(-radius * 0.5, -radius * 1.0)),
		_oriented(Vector2(-radius * 0.72, -radius * 0.12)),
	])
	var right_wing := PackedVector2Array([
		_oriented(Vector2(radius * 0.1, radius * 0.22)),
		_oriented(Vector2(-radius * 0.5, radius * 1.0)),
		_oriented(Vector2(-radius * 0.72, radius * 0.12)),
	])
	var wing_color := color.lightened(0.12)
	draw_colored_polygon(left_wing, wing_color)
	draw_colored_polygon(right_wing, wing_color)

	var cockpit := _oriented(Vector2(radius * 0.36, 0.0))
	draw_circle(cockpit, radius * 0.22, Color("#e9ffff"))
	draw_circle(cockpit, radius * 0.11, Color("#20a9cb"))


func _draw_bruiser(color: Color) -> void:
	var radius := _radius
	var hull := PackedVector2Array([
		_oriented(Vector2(radius * 1.32, 0.0)),
		_oriented(Vector2(radius * 0.72, -radius * 0.78)),
		_oriented(Vector2(radius * 0.12, -radius * 1.12)),
		_oriented(Vector2(-radius * 0.72, -radius * 0.92)),
		_oriented(Vector2(-radius * 1.15, -radius * 0.36)),
		_oriented(Vector2(-radius * 1.15, radius * 0.36)),
		_oriented(Vector2(-radius * 0.72, radius * 0.92)),
		_oriented(Vector2(radius * 0.12, radius * 1.12)),
		_oriented(Vector2(radius * 0.72, radius * 0.78)),
	])
	draw_colored_polygon(hull, color.darkened(0.24))
	draw_polyline(_closed_points(hull), color.lightened(0.3), 2.4, true)

	var upper_plate := PackedVector2Array([
		_oriented(Vector2(radius * 0.95, -radius * 0.12)),
		_oriented(Vector2(radius * 0.48, -radius * 0.72)),
		_oriented(Vector2(-radius * 0.56, -radius * 0.7)),
		_oriented(Vector2(-radius * 0.6, -radius * 0.26)),
	])
	var lower_plate := PackedVector2Array([
		_oriented(Vector2(radius * 0.95, radius * 0.12)),
		_oriented(Vector2(radius * 0.48, radius * 0.72)),
		_oriented(Vector2(-radius * 0.56, radius * 0.7)),
		_oriented(Vector2(-radius * 0.6, radius * 0.26)),
	])
	var plate_color := color.lightened(0.08)
	draw_colored_polygon(upper_plate, plate_color)
	draw_colored_polygon(lower_plate, plate_color)

	var front_armor := PackedVector2Array([
		_oriented(Vector2(radius * 1.18, 0.0)),
		_oriented(Vector2(radius * 0.56, -radius * 0.42)),
		_oriented(Vector2(radius * 0.56, radius * 0.42)),
	])
	draw_colored_polygon(front_armor, Color("#ffd49b"))
	draw_circle(
		_oriented(Vector2(-radius * 0.2, 0.0)),
		radius * 0.3,
		Color("#7d291d")
	)
	draw_circle(
		_oriented(Vector2(-radius * 0.2, 0.0)),
		radius * 0.15,
		Color("#ffdb75")
	)


func _draw_spitter(color: Color) -> void:
	var radius := _radius
	var cannon_start := _oriented(Vector2(radius * 0.2, 0.0))
	var cannon_end := _oriented(Vector2(radius * 1.7, 0.0))
	draw_line(
		cannon_start,
		cannon_end,
		Color(color.r, color.g, color.b, 0.28),
		radius * 0.58,
		true
	)
	draw_line(
		cannon_start,
		cannon_end,
		color.lightened(0.25),
		radius * 0.27,
		true
	)
	draw_circle(cannon_end, radius * 0.17, Color("#d8ff9a"))

	var hull := PackedVector2Array([
		_oriented(Vector2(radius * 0.72, 0.0)),
		_oriented(Vector2(radius * 0.22, -radius * 0.62)),
		_oriented(Vector2(-radius * 0.48, -radius * 0.9)),
		_oriented(Vector2(-radius * 1.02, -radius * 0.46)),
		_oriented(Vector2(-radius * 1.02, radius * 0.46)),
		_oriented(Vector2(-radius * 0.48, radius * 0.9)),
		_oriented(Vector2(radius * 0.22, radius * 0.62)),
	])
	draw_colored_polygon(hull, color.darkened(0.22))
	draw_polyline(_closed_points(hull), color.lightened(0.3), 2.0, true)

	var upper_fin := PackedVector2Array([
		_oriented(Vector2(-radius * 0.06, -radius * 0.35)),
		_oriented(Vector2(-radius * 0.26, -radius * 1.1)),
		_oriented(Vector2(-radius * 0.72, -radius * 0.5)),
	])
	var lower_fin := PackedVector2Array([
		_oriented(Vector2(-radius * 0.06, radius * 0.35)),
		_oriented(Vector2(-radius * 0.26, radius * 1.1)),
		_oriented(Vector2(-radius * 0.72, radius * 0.5)),
	])
	draw_colored_polygon(upper_fin, color.lightened(0.09))
	draw_colored_polygon(lower_fin, color.lightened(0.09))

	var core := _oriented(Vector2(-radius * 0.16, 0.0))
	draw_circle(core, radius * 0.34, Color(0.36, 1.0, 0.38, 0.22))
	draw_circle(core, radius * 0.2, Color("#a6ff69"))
	draw_circle(core, radius * 0.08, Color("#efffdc"))


func _draw_health_bar() -> void:
	var bar_width := clampf(_radius * 2.5, 30.0, 64.0)
	var bar_position := Vector2(-bar_width * 0.5, -_radius - 13.0)
	var ratio := clampf(_health / maxf(_max_health, 1.0), 0.0, 1.0)
	var health_color := Color("#65f59a")
	if ratio <= 0.55:
		health_color = Color("#ffd15c")
	if ratio <= 0.25:
		health_color = Color("#ff5f61")

	draw_rect(
		Rect2(bar_position - Vector2.ONE, Vector2(bar_width + 2.0, 6.0)),
		Color(0.015, 0.025, 0.05, 0.9)
	)
	draw_rect(Rect2(bar_position, Vector2(bar_width, 4.0)), Color("#283344"))
	draw_rect(
		Rect2(bar_position, Vector2(bar_width * ratio, 4.0)),
		health_color
	)


func _oriented(local_point: Vector2) -> Vector2:
	return local_point.rotated(_facing.angle())


func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not closed.is_empty():
		closed.append(closed[0])
	return closed
