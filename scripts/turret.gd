class_name Turret
extends Node2D
## 程序化生成的能量炮台。
##
## 敌人只要求是带 global_position 的 Node2D，并实现 is_alive()。
## 可选提供 health/current_health/hp 属性或 get_health()/get_current_health()
## 方法，用于在同距离威胁之间优先攻击生命值更低的目标。

signal shot_requested(origin: Vector2, target: Node2D, damage: float, speed: float, color: Color)

const MAX_LEVEL := 3
const BASE_BUILD_COST := 14
const UPGRADE_COSTS := [16, 26]

const RANGE_BY_LEVEL := [310.0, 355.0, 405.0]
const DAMAGE_BY_LEVEL := [12.0, 20.0, 33.0]
const FIRE_RATE_BY_LEVEL := [1.6, 2.2, 3.0]
const PROJECTILE_SPEED_BY_LEVEL := [480.0, 570.0, 680.0]
const AIM_SPEED_BY_LEVEL := [8.0, 10.5, 13.0]

const DEFAULT_BASE_POSITION := Vector2(640.0, 360.0)
const FIRE_ANGLE_TOLERANCE := 0.16
const TARGET_DISTANCE_TIE := 24.0

@export var base_position := DEFAULT_BASE_POSITION:
	set(value):
		base_position = value
		_base_position_is_custom = true
		queue_redraw()

var _slot_index := -1
var _level := 1
var _active := true
var _total_investment := BASE_BUILD_COST

var _target: Node2D
var _aim_angle := 0.0
var _fire_cooldown := 0.0
var _attack_flash := 0.0
var _visual_time := 0.0
var _base_position_is_custom := false


func _ready() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	_visual_time += delta
	_attack_flash = move_toward(_attack_flash, 0.0, delta * 3.5)
	queue_redraw()


## 配置炮台槽位与局部安装坐标，并重置为 1 级初始状态。
func configure(slot_index: int, mount_position: Vector2) -> void:
	_slot_index = slot_index
	position = mount_position
	_level = 1
	_active = true
	_total_investment = BASE_BUILD_COST
	_target = null
	_fire_cooldown = 0.0
	_attack_flash = 0.0
	_aim_angle = 0.0
	queue_redraw()


## 由主场景每帧调用；enemies 保持通用 Array，以兼容尚未声明的敌人脚本。
func update_combat(delta: float, enemies: Array) -> void:
	var safe_delta := maxf(delta, 0.0)
	_fire_cooldown = maxf(_fire_cooldown - safe_delta, 0.0)

	if not _active:
		return

	_target = _select_target(enemies)
	if not _has_live_target():
		return

	var target_direction := to_local(_target.global_position)
	if target_direction.is_zero_approx():
		return

	var desired_angle := target_direction.angle()
	var aim_weight := 1.0 - exp(-float(AIM_SPEED_BY_LEVEL[_level - 1]) * safe_delta)
	_aim_angle = lerp_angle(_aim_angle, desired_angle, aim_weight)

	var angle_to_target := absf(angle_difference(_aim_angle, desired_angle))
	if _fire_cooldown <= 0.0 and angle_to_target <= FIRE_ANGLE_TOLERANCE:
		_fire_at_target()

	queue_redraw()


## 升一级；达到最高等级时返回 false。
func upgrade() -> bool:
	if _level >= MAX_LEVEL:
		return false

	_total_investment += get_upgrade_cost()
	_level += 1
	_fire_cooldown = minf(_fire_cooldown, 1.0 / get_fire_rate())
	queue_redraw()
	return true


func get_level() -> int:
	return _level


## 返回升到下一级的费用；满级时返回 0。
func get_upgrade_cost() -> int:
	if _level >= MAX_LEVEL:
		return 0
	return int(UPGRADE_COSTS[_level - 1])


func get_range() -> float:
	return float(RANGE_BY_LEVEL[_level - 1])


func get_total_investment() -> int:
	return _total_investment


## 返回当前伤害与射速，便于界面显示和外部战斗系统读取。
func get_damage() -> float:
	return float(DAMAGE_BY_LEVEL[_level - 1])


func get_fire_rate() -> float:
	return float(FIRE_RATE_BY_LEVEL[_level - 1])


func set_active(value: bool) -> void:
	_active = value
	if not _active:
		_target = null
		_fire_cooldown = 0.0
	queue_redraw()


func is_active() -> bool:
	return _active


## 供主场景把“接近基地”的判定切换为飞船或其他世界坐标。
func set_base_position(value: Vector2) -> void:
	base_position = value


func get_slot_index() -> int:
	return _slot_index


func _fire_at_target() -> void:
	_fire_cooldown = 1.0 / get_fire_rate()
	_attack_flash = 1.0

	var muzzle_local := Vector2.from_angle(_aim_angle) * _get_barrel_length()
	shot_requested.emit(
		to_global(muzzle_local),
		_target,
		get_damage(),
		float(PROJECTILE_SPEED_BY_LEVEL[_level - 1]),
		_get_level_color()
	)


func _select_target(enemies: Array) -> Node2D:
	var best_target: Node2D = null
	var best_base_distance := INF
	var best_health := INF
	var range_squared := get_range() * get_range()
	var resolved_base_position := _resolve_base_position()

	for enemy_variant: Variant in enemies:
		if not (enemy_variant is Node2D):
			continue

		var enemy := enemy_variant as Node2D
		if not is_instance_valid(enemy) or not enemy.has_method("is_alive"):
			continue

		var alive_value: Variant = enemy.call("is_alive")
		if not bool(alive_value):
			continue

		var distance_to_turret_squared := global_position.distance_squared_to(enemy.global_position)
		if distance_to_turret_squared > range_squared:
			continue

		var base_distance := resolved_base_position.distance_to(enemy.global_position)
		var enemy_health := _read_enemy_health(enemy)

		var is_closer_threat := base_distance < best_base_distance - TARGET_DISTANCE_TIE
		var is_same_threat_distance := (
			absf(base_distance - best_base_distance) <= TARGET_DISTANCE_TIE
		)
		if best_target == null or is_closer_threat or (
			is_same_threat_distance and enemy_health < best_health
		):
			best_target = enemy
			best_base_distance = base_distance
			best_health = enemy_health

	return best_target


func _has_live_target() -> bool:
	if not is_instance_valid(_target) or not _target.has_method("is_alive"):
		return false
	return bool(_target.call("is_alive"))


func _read_enemy_health(enemy: Node2D) -> float:
	for method_name: StringName in [&"get_health", &"get_current_health"]:
		if enemy.has_method(method_name):
			var method_value: Variant = enemy.call(method_name)
			if _is_number(method_value):
				return float(method_value)

	for property_name: StringName in [&"health", &"current_health", &"hp"]:
		var property_value: Variant = enemy.get(property_name)
		if _is_number(property_value):
			return float(property_value)

	return INF


func _is_number(value: Variant) -> bool:
	var value_type := typeof(value)
	return value_type == TYPE_INT or value_type == TYPE_FLOAT


func _resolve_base_position() -> Vector2:
	if _base_position_is_custom:
		return base_position
	return DEFAULT_BASE_POSITION


func _get_level_color() -> Color:
	match _level:
		2:
			return Color("#ffc857")
		3:
			return Color("#ff6b9e")
		_:
			return Color("#59e4d0")


func _get_barrel_length() -> float:
	return 27.0 + float(_level - 1) * 5.0


func _draw() -> void:
	var energy_color := _get_level_color()
	var level_growth := float(_level - 1)
	var pulse := 0.5 + sin(_visual_time * (2.4 + level_growth * 0.5)) * 0.5

	# 射程环保持较淡，避免与战场网格争夺视觉层级。
	draw_arc(
		Vector2.ZERO,
		get_range(),
		0.0,
		TAU,
		96,
		Color(energy_color, 0.12),
		1.5,
		true
	)

	if _active:
		draw_circle(Vector2.ZERO, 27.0 + level_growth * 3.0 + pulse * 2.0, Color(energy_color, 0.055))

	# 固定底座使安装方向清晰，等级灯不会随炮管旋转。
	var base_radius := 19.0 + level_growth * 1.5
	draw_circle(Vector2.ZERO, base_radius + 4.0, Color("#0a1724"))
	draw_circle(Vector2.ZERO, base_radius, Color("#1c3448"))
	draw_arc(Vector2.ZERO, base_radius, 0.0, TAU, 48, Color(energy_color, 0.7), 2.0, true)

	for index in range(3):
		draw_line(
			Vector2.from_angle(PI * 0.5 + PI * float(index) / 1.5) * (base_radius - 3.0),
			Vector2.from_angle(PI * 0.5 + PI * float(index) / 1.5) * (base_radius + 8.0),
			Color("#284c62"),
			3.0,
			true
		)

	# 炮管围绕底座中心平滑旋转，所有外观均由矢量图形绘制。
	draw_set_transform(Vector2.ZERO, _aim_angle, Vector2.ONE)
	var barrel_length := _get_barrel_length()
	_draw_barrel(barrel_length, energy_color, level_growth)
	draw_circle(Vector2.ZERO, 13.0 + level_growth, Color("#173044"))
	draw_circle(Vector2.ZERO, 9.0 + level_growth, Color(energy_color.darkened(0.22), 0.9))
	draw_circle(Vector2.ZERO, 4.5 + pulse * 1.2, Color(energy_color.lightened(0.45), 0.95))

	# 攻击闪光集中在炮口，与冷却节奏共同形成清晰的反馈。
	if _attack_flash > 0.0:
		var muzzle := Vector2(barrel_length, 0.0)
		draw_circle(muzzle, 17.0 * _attack_flash, Color(energy_color, 0.13 * _attack_flash))
		draw_circle(muzzle, 7.0 * _attack_flash, Color("#ffffff", 0.75 * _attack_flash))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 三颗等级灯位于底座下方，颜色和数量共同表达当前等级。
	var lamp_start := -14.0 + level_growth
	for index in range(MAX_LEVEL):
		var lamp_position := Vector2(lamp_start + float(index) * 14.0, base_radius + 12.0)
		var lamp_color := Color(energy_color, 0.9) if index < _level else Color("#294052")
		draw_circle(lamp_position, 3.3, lamp_color)


func _draw_barrel(barrel_length: float, energy_color: Color, level_growth: float) -> void:
	var barrel_width := 5.0 + level_growth
	var offsets: Array[float] = [0.0]
	if _level == 2:
		offsets = [-4.0, 4.0]
	elif _level == MAX_LEVEL:
		offsets = [-7.0, 0.0, 7.0]

	for barrel_y: float in offsets:
		var tip := Vector2(barrel_length, barrel_y)
		draw_line(Vector2(4.0, barrel_y), tip, Color("#0a1622"), barrel_width + 3.0, true)
		draw_line(
			Vector2(7.0, barrel_y),
			tip,
			Color(energy_color.darkened(0.3), 0.9),
			barrel_width,
			true
		)
		draw_line(
			Vector2(10.0, barrel_y),
			Vector2(barrel_length - 2.0, barrel_y),
			Color(energy_color.lightened(0.3), 0.9),
			1.5,
			true
		)

	# 高等级追加能量环，轮廓会随等级明显加宽。
	draw_arc(Vector2(7.0, 0.0), 9.0 + level_growth, -1.2, 1.2, 20, Color(energy_color, 0.75), 2.0, true)
