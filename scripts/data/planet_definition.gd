@tool
class_name PlanetDefinition
extends Resource

## 星球级内容定义。
## 地表生成器只依赖这里的种子、配色和音乐轨道，不在运行时硬编码设定。

const REQUIRED_SURFACE_COLOR_KEYS := [
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

@export var id: StringName = &""
@export var display_name_key: String = ""
@export var description_key: String = ""
@export var display_name_fallback: String = ""
@export var description_fallback: String = ""
@export var terrain_seed: int = 0
@export var surface_colors: Dictionary = {}
@export var music_track_id: StringName = &"main"


## 创建星球定义；传入的配色字典会被复制，避免共享可变数据。
static func create(
	definition_id: StringName = &"",
	name_key: String = "",
	description_key_value: String = "",
	seed_value: int = 0,
	colors: Dictionary = {},
	track_id: StringName = &"main",
	name_fallback: String = "",
	description_fallback_value: String = ""
) -> PlanetDefinition:
	var definition := PlanetDefinition.new()
	definition.id = definition_id
	definition.display_name_key = name_key
	definition.description_key = description_key_value
	definition.display_name_fallback = name_fallback
	definition.description_fallback = description_fallback_value
	definition.terrain_seed = seed_value
	definition.surface_colors = colors.duplicate(true)
	definition.music_track_id = track_id
	return definition


## 返回内容定义层的完整快照，便于调试、存档或交给纯数据消费方。
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name_key": display_name_key,
		"description_key": description_key,
		"display_name_fallback": display_name_fallback,
		"description_fallback": description_fallback,
		"terrain_seed": terrain_seed,
		"surface_colors": surface_colors.duplicate(true),
		"music_track_id": music_track_id,
	}


## 返回全部结构问题；空数组表示该定义可用于加载。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).strip_edges().is_empty():
		errors.append("planet.id 不能为空")
	if display_name_key.strip_edges().is_empty():
		errors.append("planet.display_name_key 不能为空")
	if description_key.strip_edges().is_empty():
		errors.append("planet.description_key 不能为空")
	if String(music_track_id).strip_edges().is_empty():
		errors.append("planet.music_track_id 不能为空")

	for color_key: String in REQUIRED_SURFACE_COLOR_KEYS:
		if not surface_colors.has(color_key):
			errors.append("planet.surface_colors 缺少 %s" % color_key)
		elif typeof(surface_colors[color_key]) != TYPE_COLOR:
			errors.append("planet.surface_colors.%s 必须是 Color" % color_key)

	return errors
