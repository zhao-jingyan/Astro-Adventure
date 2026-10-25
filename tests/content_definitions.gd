extends SceneTree

## 内容定义层测试：全量加载 .tres，并检查结构、唯一性和基础语义。

const CATEGORIES := {
	"planets": {
		"directory": "res://data/planets",
		"script_path": "res://scripts/data/planet_definition.gd",
		"minimum_count": 1,
		"required_fields": [
			"id",
			"display_name_key",
			"description_key",
			"terrain_seed",
			"surface_colors",
			"music_track_id",
		],
	},
	"levels": {
		"directory": "res://data/levels",
		"script_path": "res://scripts/data/level_definition.gd",
		"minimum_count": 4,
		"required_fields": [
			"id",
			"display_name_key",
			"description_key",
			"planet_id",
			"map_position",
			"danger",
			"initial_prep_seconds",
			"later_prep_seconds",
			"total_waves",
			"terrain_seed",
			"enemy_spawn_table",
		],
	},
	"enemies": {
		"directory": "res://data/enemies",
		"script_path": "res://scripts/data/enemy_species_definition.gd",
		"minimum_count": 3,
		"required_fields": [
			"id",
			"display_name_key",
			"visual_kind",
			"behavior_id",
			"traits",
			"max_health",
			"move_speed",
			"radius",
			"reward",
			"attack_damage",
			"attack_interval",
			"attack_range",
			"projectile_speed",
			"projectile_color",
			"body_color",
			"aggro_radius",
			"leash_radius",
		],
	},
	"relics": {
		"directory": "res://data/relics",
		"script_path": "res://scripts/data/relic_definition.gd",
		"minimum_count": 3,
		"required_fields": [
			"id",
			"display_name_key",
			"description_key",
			"rarity",
			"modifiers",
		],
	},
	"achievements": {
		"directory": "res://data/achievements",
		"script_path": "res://scripts/data/achievement_definition.gd",
		"minimum_count": 3,
		"required_fields": [
			"id",
			"display_name_key",
			"description_key",
			"event_name",
			"target_count",
			"hidden",
		],
	},
}

const SURFACE_COLOR_KEYS := [
	"base",
	"safe_sand",
	"safe_light",
	"rust",
	"ochre",
	"deep",
	"shadow",
	"crystal",
	"moss",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definitions_by_category: Dictionary = {}

	for category_name: String in CATEGORIES:
		var category: Dictionary = CATEGORIES[category_name]
		var definitions := _load_category(category_name, category)
		definitions_by_category[category_name] = definitions

	_validate_global_ids(definitions_by_category)
	_validate_khepri(definitions_by_category.get("planets", []))
	_validate_levels(definitions_by_category.get("levels", []))
	_validate_enemy_species(definitions_by_category.get("enemies", []))
	_validate_sample_ids(definitions_by_category.get("relics", []), [
		&"phase_boots",
		&"stamina_condenser",
		&"fuel_seed",
	])
	_validate_sample_ids(definitions_by_category.get("achievements", []), [
		&"first_wave_clear",
		&"first_cross_map",
		&"fuel_collector",
	])

	if _failures.is_empty():
		print("内容定义测试通过：全部资源可加载，ID 唯一，字段与校验结果正常。")
		quit(0)
		return

	for failure: String in _failures:
		push_error("内容定义测试失败：" + failure)
	quit(1)


func _load_category(category_name: String, category: Dictionary) -> Array:
	var directory: String = category["directory"]
	var expected_script: Resource = load(category["script_path"])
	var files := DirAccess.get_files_at(directory)
	files.sort()
	var definitions: Array = []
	var seen_ids: Dictionary = {}
	var tres_count := 0

	for file_name: String in files:
		if file_name.get_extension() != "tres":
			continue
		tres_count += 1
		var path := directory.path_join(file_name)
		var resource := ResourceLoader.load(path)
		_expect(resource != null, "%s 无法加载" % path)
		if resource == null:
			continue

		_expect(
			resource.get_script() == expected_script,
			"%s 未使用预期的 Resource 脚本" % path
		)
		_expect(resource.has_method("to_dict"), "%s 缺少 to_dict()" % path)
		_expect(resource.has_method("validate"), "%s 缺少 validate()" % path)
		if not resource.has_method("to_dict") or not resource.has_method("validate"):
			continue

		var definition_id := String(resource.get("id"))
		_expect(not definition_id.is_empty(), "%s 的 id 不能为空" % path)
		_expect(
			not seen_ids.has(definition_id),
			"%s 的 id %s 与 %s 重复" % [path, definition_id, seen_ids.get(definition_id, "")]
		)
		seen_ids[definition_id] = path

		var validation_errors: PackedStringArray = resource.call("validate")
		_expect(
			validation_errors.is_empty(),
			"%s 校验失败：%s" % [path, ", ".join(validation_errors)]
		)

		var data_value: Variant = resource.call("to_dict")
		_expect(data_value is Dictionary, "%s 的 to_dict() 必须返回 Dictionary" % path)
		if data_value is Dictionary:
			var data := data_value as Dictionary
			for field_name: String in category["required_fields"]:
				_expect(data.has(field_name), "%s 的 to_dict() 缺少字段 %s" % [path, field_name])

		definitions.append(resource)

	_expect(
		tres_count >= int(category["minimum_count"]),
		"%s 至少需要 %d 个 .tres，当前为 %d 个"
		% [category_name, int(category["minimum_count"]), tres_count]
	)
	return definitions


func _validate_khepri(planets: Array) -> void:
	var khepri := _find_by_id(planets, &"khepri_9")
	_expect(khepri != null, "缺少 Khepri-9 星球定义")
	if khepri == null:
		return

	_expect(
		String(khepri.get("display_name_key")) == "planet.khepri_9.name",
		"Khepri-9 必须使用 i18n 名称键"
	)
	var colors: Dictionary = khepri.get("surface_colors")
	for color_key: String in SURFACE_COLOR_KEYS:
		_expect(colors.has(color_key), "Khepri-9 缺少地表颜色 %s" % color_key)


func _validate_levels(levels: Array) -> void:
	var expected_ids: Array[StringName] = [
		&"red_basin",
		&"rust_rift",
		&"glass_dunes",
		&"deep_highland",
	]
	for expected_id: StringName in expected_ids:
		var level := _find_by_id(levels, expected_id)
		_expect(level != null, "缺少区域关卡 %s" % expected_id)
		if level == null:
			continue
		_expect(String(level.get("planet_id")) == "khepri_9", "%s 的 planet_id 不正确" % expected_id)
		var spawn_table: Array = level.get("enemy_spawn_table")
		_expect(not spawn_table.is_empty(), "%s 的 enemy_spawn_table 不能为空" % expected_id)


func _validate_enemy_species(enemies: Array) -> void:
	var expected_ids: Array[StringName] = [&"scout", &"bruiser", &"spitter"]
	var visual_kinds: Dictionary = {}
	for expected_id: StringName in expected_ids:
		var enemy := _find_by_id(enemies, expected_id)
		_expect(enemy != null, "缺少敌人物种 %s" % expected_id)
		if enemy == null:
			continue
		visual_kinds[int(enemy.get("visual_kind"))] = true

	for visual_kind in range(3):
		_expect(visual_kinds.has(visual_kind), "缺少 visual_kind=%d 的敌人外观" % visual_kind)


func _validate_sample_ids(definitions: Array, expected_ids: Array[StringName]) -> void:
	for expected_id: StringName in expected_ids:
		_expect(_find_by_id(definitions, expected_id) != null, "缺少示例定义 %s" % expected_id)


func _validate_global_ids(definitions_by_category: Dictionary) -> void:
	var seen_ids: Dictionary = {}
	for category_name: String in definitions_by_category:
		var definitions: Array = definitions_by_category[category_name]
		for resource: Resource in definitions:
			var definition_id := String(resource.get("id"))
			_expect(
				not seen_ids.has(definition_id),
				"id %s 在 %s 与 %s 之间重复"
				% [definition_id, seen_ids.get(definition_id, ""), category_name]
			)
			seen_ids[definition_id] = category_name


func _find_by_id(definitions: Array, definition_id: StringName) -> Resource:
	for resource: Variant in definitions:
		if resource is Resource and String(resource.get("id")) == String(definition_id):
			return resource
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
