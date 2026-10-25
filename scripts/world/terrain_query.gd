class_name TerrainQuery
extends RefCounted

## 与绘制层解耦的地形规则查询。
##
## 地形标签由具体星球表面采样后传入，本类只负责速度、阻挡和危险规则。
## 多个速度标签同时命中时取最慢的倍率，避免重复乘算导致异常减速。

const DEFAULT_SPEED_MULTIPLIER := 1.0


## 可通过 .tres 数据文件配置的地形档案。
class TerrainProfile:
	extends Resource

	@export var speed_multipliers: Dictionary = {}
	@export var blocked_tags := PackedStringArray()
	@export var danger_tags := PackedStringArray()

	func _init(
		p_speed_multipliers: Dictionary = {},
		p_blocked_tags := PackedStringArray(),
		p_danger_tags := PackedStringArray()
	) -> void:
		speed_multipliers = p_speed_multipliers.duplicate(true)
		blocked_tags = p_blocked_tags.duplicate()
		danger_tags = p_danger_tags.duplicate()


var speed_multipliers: Dictionary = {}
var blocked_tags := PackedStringArray()
var danger_tags := PackedStringArray()
var default_speed_multiplier := DEFAULT_SPEED_MULTIPLIER


## 从资源档案复制规则，后续修改档案不会影响已配置的查询器。
func configure_from_profile(
	profile: TerrainProfile,
	p_default_speed_multiplier: float = DEFAULT_SPEED_MULTIPLIER
) -> void:
	default_speed_multiplier = maxf(0.0, p_default_speed_multiplier)
	if profile == null:
		speed_multipliers.clear()
		blocked_tags = PackedStringArray()
		danger_tags = PackedStringArray()
		return

	speed_multipliers = _normalize_speed_multipliers(profile.speed_multipliers)
	blocked_tags = _normalize_tags(profile.blocked_tags)
	danger_tags = _normalize_tags(profile.danger_tags)


## 使用字典快速配置，字段名与 TerrainProfile 的属性保持一致。
func configure_from_dictionary(
	config: Dictionary,
	p_default_speed_multiplier: float = DEFAULT_SPEED_MULTIPLIER
) -> void:
	default_speed_multiplier = maxf(0.0, p_default_speed_multiplier)
	var speed_source: Variant = config.get("speed_multipliers", {})
	speed_multipliers = (
		_normalize_speed_multipliers(speed_source)
		if speed_source is Dictionary
		else {}
	)
	blocked_tags = _normalize_tags(config.get("blocked_tags", PackedStringArray()))
	danger_tags = _normalize_tags(config.get("danger_tags", PackedStringArray()))


## 生成统一的采样结果，方便 PlanetSurface 或其他地形提供者直接适配。
func sample(position: Vector2, tags: Variant = PackedStringArray()) -> Dictionary:
	var normalized_tags := _normalize_tags(tags)
	var matching_danger_tags := get_matching_danger_tags(normalized_tags)
	return {
		"position": position,
		"tags": normalized_tags,
		"blocked": is_blocked(normalized_tags),
		"speed_multiplier": get_speed_multiplier(normalized_tags),
		"danger": not matching_danger_tags.is_empty(),
		"danger_tags": matching_danger_tags,
	}


## 返回标签组合的速度倍率；没有命中时使用配置的默认值。
func get_speed_multiplier(tags: Variant = PackedStringArray()) -> float:
	var result := INF
	for tag: String in _normalize_tags(tags):
		var key := StringName(tag)
		if speed_multipliers.has(key):
			result = minf(result, float(speed_multipliers[key]))
	return result if result != INF else default_speed_multiplier


## 任一标签命中阻挡列表时，该位置不可通行。
func is_blocked(tags: Variant = PackedStringArray()) -> bool:
	for tag: String in _normalize_tags(tags):
		if blocked_tags.has(tag):
			return true
	return false


## 返回当前标签实际命中的危险标签。
func get_matching_danger_tags(tags: Variant = PackedStringArray()) -> PackedStringArray:
	var matches := PackedStringArray()
	for tag: String in _normalize_tags(tags):
		if danger_tags.has(tag):
			matches.append(tag)
	return matches


func is_dangerous(tags: Variant = PackedStringArray()) -> bool:
	return not get_matching_danger_tags(tags).is_empty()


## 尝试完整移动，受阻时依次尝试 X、Y 分轴；返回最终可站立位置。
##
## sampler 接受 (position, radius)，返回包含 tags 和 blocked 字段的 Dictionary。
## 若没有 blocked 字段，则使用返回的 tags 按当前 TerrainQuery 规则判断。
func slide_move(
	current: Vector2,
	desired: Vector2,
	radius: float,
	sampler: Callable
) -> Vector2:
	if not sampler.is_valid() or desired.is_equal_approx(current):
		return current

	var sample_radius := maxf(0.0, radius)
	if not _sample_is_blocked(sampler, desired, sample_radius):
		return desired

	var result := current
	var x_position := Vector2(desired.x, current.y)
	if not _sample_is_blocked(sampler, x_position, sample_radius):
		result.x = desired.x

	var y_position := Vector2(result.x, desired.y)
	if not _sample_is_blocked(sampler, y_position, sample_radius):
		result.y = desired.y

	return result


func _sample_is_blocked(sampler: Callable, position: Vector2, radius: float) -> bool:
	var result: Variant = sampler.call(position, radius)
	if result is bool:
		return result

	if result is Dictionary:
		var sample_data: Dictionary = result
		if sample_data.has("blocked"):
			return bool(sample_data["blocked"])
		if sample_data.has("is_blocked"):
			return bool(sample_data["is_blocked"])
		return is_blocked(sample_data.get("tags", PackedStringArray()))

	if result is Object:
		var object_sample: Object = result
		var blocked_value: Variant = object_sample.get("blocked")
		if blocked_value != null:
			return bool(blocked_value)
		var tags_value: Variant = object_sample.get("tags")
		if tags_value != null:
			return is_blocked(tags_value)

	return false


func _normalize_speed_multipliers(source: Dictionary) -> Dictionary:
	var normalized := {}
	for key: Variant in source:
		normalized[StringName(str(key))] = maxf(0.0, float(source[key]))
	return normalized


func _normalize_tags(value: Variant) -> PackedStringArray:
	var normalized := PackedStringArray()
	if value == null:
		return normalized

	if value is PackedStringArray:
		for tag: String in value:
			if not tag.is_empty():
				normalized.append(tag)
	elif value is Array:
		for tag_value: Variant in value:
			var tag := str(tag_value)
			if not tag.is_empty():
				normalized.append(tag)
	elif value is String or value is StringName:
		var tag := str(value)
		if not tag.is_empty():
			normalized.append(tag)

	return normalized
