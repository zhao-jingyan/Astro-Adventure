@tool
class_name EnemySpeciesDefinition
extends Resource

## 敌人物种的基础属性。
## visual_kind 只描述当前三种外观，behavior_id 和 traits 负责驱动可扩展行为。

const MIN_VISUAL_KIND := 0
const MAX_VISUAL_KIND := 2

@export var id: StringName = &""
@export var display_name_key: String = ""
@export var display_name_fallback: String = ""
@export_range(0, 2, 1) var visual_kind: int = 0
@export var behavior_id: StringName = &"aggressive"
@export var traits: PackedStringArray = PackedStringArray()
@export var max_health: float = 1.0
@export var move_speed: float = 1.0
@export var radius: float = 1.0
@export var reward: int = 0
@export var attack_damage: float = 0.0
@export var attack_interval: float = 1.0
@export var attack_range: float = 0.0
@export var projectile_speed: float = 0.0
@export var projectile_color: Color = Color.WHITE
@export var body_color: Color = Color.WHITE
@export var aggro_radius: float = 430.0
@export var leash_radius: float = 1050.0


## 创建敌人物种；所有运行参数都由数据传入。
static func create(
	definition_id: StringName = &"",
	display_name_key_value: String = "",
	kind: int = 0,
	behavior: StringName = &"aggressive",
	trait_values: PackedStringArray = PackedStringArray(),
	health: float = 1.0,
	speed: float = 1.0,
	body_radius: float = 1.0,
	reward_value: int = 0,
	damage: float = 0.0,
	interval: float = 1.0,
	range_value: float = 0.0,
	projectile_speed_value: float = 0.0,
	projectile_tint: Color = Color.WHITE,
	body_tint: Color = Color.WHITE,
	aggro: float = 430.0,
	leash: float = 1050.0,
	name_fallback: String = ""
) -> EnemySpeciesDefinition:
	var definition := EnemySpeciesDefinition.new()
	definition.id = definition_id
	definition.display_name_key = display_name_key_value
	definition.display_name_fallback = name_fallback
	definition.visual_kind = kind
	definition.behavior_id = behavior
	definition.traits = trait_values.duplicate()
	definition.max_health = health
	definition.move_speed = speed
	definition.radius = body_radius
	definition.reward = reward_value
	definition.attack_damage = damage
	definition.attack_interval = interval
	definition.attack_range = range_value
	definition.projectile_speed = projectile_speed_value
	definition.projectile_color = projectile_tint
	definition.body_color = body_tint
	definition.aggro_radius = aggro
	definition.leash_radius = leash
	return definition


## 返回敌人物种的完整快照。
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name_key": display_name_key,
		"display_name_fallback": display_name_fallback,
		"visual_kind": visual_kind,
		"behavior_id": behavior_id,
		"traits": traits.duplicate(),
		"max_health": max_health,
		"move_speed": move_speed,
		"radius": radius,
		"reward": reward,
		"attack_damage": attack_damage,
		"attack_interval": attack_interval,
		"attack_range": attack_range,
		"projectile_speed": projectile_speed,
		"projectile_color": projectile_color,
		"body_color": body_color,
		"aggro_radius": aggro_radius,
		"leash_radius": leash_radius,
	}


## 校验外观索引、行为标识和战斗数值。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).strip_edges().is_empty():
		errors.append("enemy.id 不能为空")
	if display_name_key.strip_edges().is_empty():
		errors.append("enemy.display_name_key 不能为空")
	if visual_kind < MIN_VISUAL_KIND or visual_kind > MAX_VISUAL_KIND:
		errors.append("enemy.visual_kind 必须在 0 到 2 之间")
	if String(behavior_id).strip_edges().is_empty():
		errors.append("enemy.behavior_id 不能为空")
	if traits.is_empty():
		errors.append("enemy.traits 不能为空")
	if max_health <= 0.0:
		errors.append("enemy.max_health 必须大于 0")
	if move_speed < 0.0:
		errors.append("enemy.move_speed 不能小于 0")
	if radius <= 0.0:
		errors.append("enemy.radius 必须大于 0")
	if reward < 0:
		errors.append("enemy.reward 不能小于 0")
	if attack_damage < 0.0:
		errors.append("enemy.attack_damage 不能小于 0")
	if attack_interval <= 0.0:
		errors.append("enemy.attack_interval 必须大于 0")
	if attack_range < 0.0:
		errors.append("enemy.attack_range 不能小于 0")
	if projectile_speed < 0.0:
		errors.append("enemy.projectile_speed 不能小于 0")
	if aggro_radius < 0.0:
		errors.append("enemy.aggro_radius 不能小于 0")
	if leash_radius < aggro_radius:
		errors.append("enemy.leash_radius 不能小于 aggro_radius")
	return errors
