class_name LevelSelect
extends Control

## Khepri-9 地表航程图。
##
## 覆盖层完全使用原生绘制，不依赖图片、字体文件或场景资源。
## `levels` 中的每个 Dictionary 提供节点数据，展示层只复制数据，不直接修改调用方的数组。

signal destination_selected(index: int)
signal closed()

const DESIGN_SIZE := Vector2(1280.0, 720.0)
const MAP_RECT := Rect2(36.0, 122.0, 782.0, 522.0)
const MAP_INNER_RECT := Rect2(74.0, 184.0, 706.0, 365.0)
const DETAIL_RECT := Rect2(838.0, 122.0, 406.0, 522.0)

const COLOR_BACKDROP := Color(0.035, 0.031, 0.027, 0.965)
const COLOR_BACKDROP_LIGHT := Color(0.082, 0.061, 0.045, 0.94)
const COLOR_MAP := Color(0.105, 0.075, 0.055, 0.98)
const COLOR_MAP_LIGHT := Color(0.165, 0.112, 0.071, 0.82)
const COLOR_PANEL := Color(0.067, 0.052, 0.042, 0.98)
const COLOR_PANEL_LIGHT := Color(0.125, 0.087, 0.059, 0.82)
const COLOR_BORDER := Color(0.49, 0.32, 0.18, 0.62)
const COLOR_BORDER_SOFT := Color(0.42, 0.31, 0.22, 0.32)
const COLOR_SAND := Color("#d6b17a")
const COLOR_SAND_LIGHT := Color("#f2d7a5")
const COLOR_MUTED := Color("#a88f70")
const COLOR_CYAN := Color("#71d9cb")
const COLOR_CYAN_DIM := Color("#2f776f")
const COLOR_AMBER := Color("#efb45f")
const COLOR_AMBER_DIM := Color("#9b6533")
const COLOR_RED := Color("#e77964")
const COLOR_RED_DIM := Color("#873f36")
const COLOR_GREEN := Color("#8ab28b")

var _levels: Array = []
var _current_index := -1
var _current_fuel := 0
var _selected_index := -1
var _is_open := false
var _node_positions: Array[Vector2] = []
var _ui_scale := 1.0
var _ui_offset := Vector2.ZERO


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(false)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_sync_to_viewport)
	resized.connect(_on_resized)
	_sync_to_viewport()

	if not _is_open:
		hide()
	elif is_inside_tree():
		grab_focus()


## 打开航程图。节点数据会被深复制，避免覆盖层意外改写外部状态。
func open(levels: Array, current_index: int, current_fuel: int) -> void:
	_levels = levels.duplicate(true)
	_current_fuel = maxi(0, current_fuel)
	if _levels.is_empty():
		_current_index = -1
		_selected_index = -1
	else:
		_current_index = clampi(current_index, 0, _levels.size() - 1)
		_selected_index = _current_index

	_is_open = true
	set_process_input(true)
	show()
	_sync_to_viewport()
	_rebuild_node_positions()
	if is_inside_tree():
		grab_focus()
	queue_redraw()


## 关闭航程图；仅在实际由打开状态切换为关闭状态时发出一次 closed。
func close() -> void:
	if not _is_open:
		hide()
		set_process_input(false)
		return

	_is_open = false
	hide()
	set_process_input(false)
	if has_focus():
		release_focus()
	closed.emit()


func is_open() -> bool:
	return _is_open


## 更新剩余燃油，并立即刷新节点可达状态。
func set_fuel(fuel: int) -> void:
	var normalized_fuel := maxi(0, fuel)
	if _current_fuel == normalized_fuel:
		return

	_current_fuel = normalized_fuel
	queue_redraw()


## 选中节点索引。索引超出范围时按节点数量循环。
func select_index(index: int) -> void:
	if _levels.is_empty():
		return

	var normalized_index := wrapi(index, 0, _levels.size())
	if _selected_index == normalized_index:
		return

	_selected_index = normalized_index
	queue_redraw()


## 确认当前选中的目的地。已访问关卡可以再次进入以补充燃油。
func confirm_current() -> void:
	if not _is_open or not _can_confirm(_selected_index):
		return

	var destination_index := _selected_index
	destination_selected.emit(destination_index)
	close()


func get_selected_index() -> int:
	return _selected_index


func _input(event: InputEvent) -> void:
	if not _is_open or not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var key_code: int = key_event.keycode
	if key_code == 0:
		key_code = key_event.physical_keycode

	var handled := true
	if key_code >= KEY_1 and key_code <= KEY_9:
		select_index(key_code - KEY_1)
	elif key_code == KEY_LEFT or key_code == KEY_UP:
		_cycle_selection(-1)
	elif key_code == KEY_RIGHT or key_code == KEY_DOWN:
		_cycle_selection(1)
	elif key_code == KEY_ENTER or key_code == KEY_KP_ENTER:
		confirm_current()
	elif key_code == KEY_ESCAPE:
		close()
	else:
		handled = false

	if handled:
		get_viewport().set_input_as_handled()


## 鼠标交互由覆盖层自身消费，避免普通点击穿透到地表玩法。
func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				var hit_index := _node_at(mouse_event.position)
				if hit_index >= 0:
					var clicked_selected := hit_index == _selected_index
					select_index(hit_index)
					if (mouse_event.double_click or clicked_selected) and _can_confirm(hit_index):
						confirm_current()
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_selection(-1)
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_selection(1)
			accept_event()


func _cycle_selection(direction: int) -> void:
	if _levels.is_empty():
		return

	if _selected_index < 0:
		select_index(0)
	else:
		select_index(_selected_index + direction)


func _node_at(local_position: Vector2) -> int:
	if _node_positions.is_empty() or _ui_scale <= 0.0001:
		return -1

	var design_position := (local_position - _ui_offset) / _ui_scale
	var hit_radius := 30.0
	var closest_index := -1
	var closest_distance := INF
	for index in range(_node_positions.size()):
		var distance := design_position.distance_to(_node_positions[index])
		if distance <= hit_radius and distance < closest_distance:
			closest_distance = distance
			closest_index = index
	return closest_index


func _sync_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	position = Vector2.ZERO
	if not size.is_equal_approx(viewport_size):
		size = viewport_size

	_refresh_ui_transform()
	_rebuild_node_positions()
	queue_redraw()


func _on_resized() -> void:
	_refresh_ui_transform()
	_rebuild_node_positions()
	queue_redraw()


func _refresh_ui_transform() -> void:
	var usable_size := size
	if usable_size.x <= 0.0 or usable_size.y <= 0.0:
		usable_size = get_viewport_rect().size

	_ui_scale = maxf(
		0.08,
		minf(usable_size.x / DESIGN_SIZE.x, usable_size.y / DESIGN_SIZE.y)
	)
	_ui_offset = (usable_size - DESIGN_SIZE * _ui_scale) * 0.5


func _rebuild_node_positions() -> void:
	_node_positions.clear()
	if _levels.is_empty():
		return

	var relatives: Array[Vector2] = []
	var has_complete_map := true
	for level_index in range(_levels.size()):
		var map_distance = _level_dictionary(level_index).get("map_distance", null)
		if map_distance is Vector2:
			relatives.append(map_distance as Vector2)
		elif map_distance is Vector2i:
			relatives.append(Vector2(map_distance as Vector2i))
		elif map_distance is Array and (map_distance as Array).size() >= 2:
			var raw_position := map_distance as Array
			relatives.append(Vector2(float(raw_position[0]), float(raw_position[1])))
		else:
			has_complete_map = false
			relatives.append(Vector2.ZERO)

	if not has_complete_map or not _has_usable_relative_map(relatives):
		_node_positions = _build_fallback_positions(_levels.size())
		return

	var bounds := Rect2(relatives[0], Vector2.ZERO)
	for relative_position in relatives:
		bounds = bounds.expand(relative_position)
	bounds = bounds.expand(Vector2.ZERO)

	var relative_width := maxf(bounds.size.x, 1.0)
	var relative_height := maxf(bounds.size.y, 1.0)
	var scale_x := MAP_INNER_RECT.size.x / relative_width
	var scale_y := MAP_INNER_RECT.size.y / relative_height
	var map_scale := minf(scale_x, scale_y)
	var map_center := MAP_INNER_RECT.get_center()
	var relative_center := bounds.get_center()

	for relative_position in relatives:
		_node_positions.append(
			map_center + (relative_position - relative_center) * map_scale
		)


func _has_usable_relative_map(relative_positions: Array[Vector2]) -> bool:
	if relative_positions.size() <= 1:
		return true

	var first_position := relative_positions[0]
	for index in range(1, relative_positions.size()):
		if not relative_positions[index].is_equal_approx(first_position):
			return true
	return false


func _build_fallback_positions(count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if count <= 0:
		return positions
	if count == 1:
		positions.append(MAP_INNER_RECT.get_center())
		return positions

	var columns := mini(3, count)
	var rows := ceili(float(count) / float(columns))
	for index in range(count):
		var row := index / columns
		var column := index % columns
		if row % 2 == 1:
			column = columns - 1 - column

		var x_ratio := float(column) / float(maxi(1, columns - 1))
		var y_ratio := float(row) / float(maxi(1, rows - 1))
		positions.append(
			Vector2(
				lerpf(MAP_INNER_RECT.position.x, MAP_INNER_RECT.end.x, x_ratio),
				lerpf(MAP_INNER_RECT.position.y, MAP_INNER_RECT.end.y, y_ratio)
			)
		)
	return positions


func _level_dictionary(index: int) -> Dictionary:
	if index < 0 or index >= _levels.size():
		return {}
	if _levels[index] is Dictionary:
		return _levels[index] as Dictionary
	return {}


func _level_name(index: int) -> String:
	var level := _level_dictionary(index)
	var value := str(level.get("name", "")).strip_edges()
	return value if not value.is_empty() else "未命名节点"


func _level_id(index: int) -> String:
	var level := _level_dictionary(index)
	var value := str(level.get("id", "")).strip_edges()
	return value if not value.is_empty() else "未编号"


func _level_description(index: int) -> String:
	var level := _level_dictionary(index)
	var value := str(level.get("description", "")).strip_edges()
	return value if not value.is_empty() else "尚无该区域的地形与补给记录。"


func _level_fuel_cost(index: int) -> int:
	var value = _level_dictionary(index).get("fuel_cost", 0)
	if value is int or value is float:
		return maxi(0, int(value))
	if value is String and (value as String).is_valid_int():
		return maxi(0, int(value))
	return 0


func _level_danger_value(index: int) -> int:
	var value = _level_dictionary(index).get("danger", 0)
	if value is int or value is float:
		return clampi(int(value), 0, 5)
	if value is String:
		var normalized := (value as String).strip_edges().to_lower()
		match normalized:
			"安全", "safe", "none", "0":
				return 0
			"低", "低危", "low", "1":
				return 1
			"中", "中危", "medium", "2":
				return 2
			"高", "高危", "high", "3":
				return 3
			"极高", "极高危", "extreme", "severe", "4", "5":
				return 5
	return 0


func _level_visited(index: int) -> bool:
	var value = _level_dictionary(index).get("visited", false)
	if value is bool:
		return value
	if value is int or value is float:
		return int(value) != 0
	if value is String:
		return (value as String).strip_edges().to_lower() in [
			"true", "yes", "1", "是", "已访问"
		]
	return false


func _can_confirm(index: int) -> bool:
	if index < 0 or index >= _levels.size() or index == _current_index:
		return false
	return _level_fuel_cost(index) <= _current_fuel


func _node_state(index: int) -> String:
	if index == _current_index:
		return "current"
	if _level_fuel_cost(index) > _current_fuel:
		return "insufficient"
	if _level_visited(index):
		return "visited"
	return "reachable"


func _danger_label(index: int) -> String:
	match _level_danger_value(index):
		0:
			return "安全"
		1:
			return "低危"
		2:
			return "中危"
		3:
			return "高危"
		_:
			return "极高危"


func _danger_color(index: int) -> Color:
	var danger := _level_danger_value(index)
	if danger <= 1:
		return COLOR_GREEN
	if danger <= 2:
		return COLOR_AMBER
	return COLOR_RED


func _draw() -> void:
	if not _is_open or size.x <= 0.0 or size.y <= 0.0:
		return

	_refresh_ui_transform()
	var font := ThemeDB.fallback_font

	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKDROP)
	_draw_backdrop_grain()

	draw_set_transform(_ui_offset, 0.0, Vector2(_ui_scale, _ui_scale))
	_draw_header(font)
	_draw_map(font)
	_draw_detail_panel(font)
	_draw_footer_hints(font)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_backdrop_grain() -> void:
	var band_height := maxf(8.0, size.y / 36.0)
	for index in range(18):
		var band_alpha := 0.018 * float(18 - index) / 18.0
		draw_rect(
			Rect2(0.0, band_height * index, size.x, band_height + 1.0),
			Color(0.35, 0.20, 0.10, band_alpha)
		)

	for index in range(26):
		var x := fmod(float(index * 173 + 47), maxf(1.0, size.x))
		var y := fmod(float(index * 89 + 31), maxf(1.0, size.y))
		var radius := 0.7 + float(index % 3) * 0.45
		draw_circle(Vector2(x, y), radius, Color(0.62, 0.43, 0.24, 0.13))


func _draw_header(font: Font) -> void:
	draw_rect(Rect2(36.0, 34.0, 4.0, 54.0), COLOR_AMBER)
	draw_string(
		font,
		Vector2(54.0, 65.0),
		"KHEPRI-9 地表航程图",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		28,
		COLOR_SAND_LIGHT
	)
	draw_string(
		font,
		Vector2(55.0, 87.0),
		"远征路线 / 区域测绘档案",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		COLOR_MUTED
	)

	draw_line(Vector2(36.0, 103.0), Vector2(1244.0, 103.0), COLOR_BORDER_SOFT, 1.0)

	var fuel_rect := Rect2(1044.0, 39.0, 200.0, 49.0)
	draw_rect(fuel_rect, Color(0.11, 0.079, 0.052, 0.92))
	draw_rect(fuel_rect, COLOR_BORDER, false, 1.0)
	draw_string(
		font,
		Vector2(fuel_rect.position.x + 14.0, fuel_rect.position.y + 18.0),
		"当前燃油",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		COLOR_MUTED
	)
	draw_string(
		font,
		Vector2(fuel_rect.position.x + 13.0, fuel_rect.position.y + 40.0),
		"%d 单位" % _current_fuel,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		22,
		COLOR_AMBER
	)

	draw_string(
		font,
		Vector2(868.0, 62.0),
		"%d 个记录节点" % _levels.size(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		COLOR_MUTED
	)
	draw_string(
		font,
		Vector2(868.0, 82.0),
		"燃油不足的航线无法确认",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		Color(COLOR_MUTED, 0.82)
	)


func _draw_map(font: Font) -> void:
	draw_rect(MAP_RECT, COLOR_MAP)
	draw_rect(MAP_RECT, COLOR_BORDER, false, 1.0)
	_draw_panel_corners(MAP_RECT, COLOR_SAND, 16.0)

	draw_string(
		font,
		Vector2(MAP_RECT.position.x + 20.0, MAP_RECT.position.y + 30.0),
		"区域测绘图",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		15,
		COLOR_SAND
	)
	draw_string(
		font,
		Vector2(MAP_RECT.end.x - 164.0, MAP_RECT.position.y + 29.0),
		"比例 1:24000",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		Color(COLOR_MUTED, 0.76)
	)
	draw_line(
		Vector2(MAP_RECT.position.x + 20.0, MAP_RECT.position.y + 42.0),
		Vector2(MAP_RECT.end.x - 20.0, MAP_RECT.position.y + 42.0),
		COLOR_BORDER_SOFT,
		1.0
	)

	_draw_map_terrain(font)
	_draw_route_lines()
	_draw_map_nodes(font)
	_draw_map_legend(font)


func _draw_map_terrain(font: Font) -> void:
	var region_data := [
		{
			"center": Vector2(246.0, 300.0),
			"radii": Vector2(176.0, 92.0),
			"color": Color(0.34, 0.17, 0.085, 0.38),
			"phase": 0.4,
			"label": "赤砂盆地",
			"label_position": Vector2(154.0, 231.0),
		},
		{
			"center": Vector2(565.0, 414.0),
			"radii": Vector2(220.0, 102.0),
			"color": Color(0.20, 0.12, 0.075, 0.52),
			"phase": 1.7,
			"label": "熔盐洼地",
			"label_position": Vector2(467.0, 522.0),
		},
		{
			"center": Vector2(612.0, 250.0),
			"radii": Vector2(132.0, 75.0),
			"color": Color(0.40, 0.23, 0.11, 0.24),
			"phase": 2.5,
			"label": "远岸台地",
			"label_position": Vector2(566.0, 191.0),
		},
	]

	for region: Dictionary in region_data:
		var points := _organic_ellipse(
			region["center"],
			region["radii"],
			float(region["phase"]),
			38,
			0.07
		)
		draw_colored_polygon(points, region["color"])
		draw_string(
			font,
			region["label_position"],
			region["label"],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			10,
			Color(COLOR_MUTED, 0.52)
		)

	for grid_x in range(8):
		var x := MAP_RECT.position.x + 20.0 + float(grid_x) * 102.0
		draw_line(
			Vector2(x, MAP_RECT.position.y + 43.0),
			Vector2(x, MAP_RECT.end.y - 55.0),
			Color(COLOR_BORDER_SOFT, 0.40),
			1.0
		)
	for grid_y in range(5):
		var y := MAP_RECT.position.y + 64.0 + float(grid_y) * 91.0
		draw_line(
			Vector2(MAP_RECT.position.x + 12.0, y),
			Vector2(MAP_RECT.end.x - 12.0, y),
			Color(COLOR_BORDER_SOFT, 0.34),
			1.0
		)

	var contour_specs := [
		[Vector2(385.0, 369.0), Vector2(266.0, 146.0), 0.2],
		[Vector2(385.0, 369.0), Vector2(221.0, 119.0), 0.2],
		[Vector2(385.0, 369.0), Vector2(178.0, 94.0), 0.2],
		[Vector2(385.0, 369.0), Vector2(135.0, 71.0), 0.2],
		[Vector2(603.0, 276.0), Vector2(101.0, 58.0), 1.1],
		[Vector2(603.0, 276.0), Vector2(73.0, 40.0), 1.1],
		[Vector2(603.0, 276.0), Vector2(45.0, 25.0), 1.1],
	]
	for contour: Array in contour_specs:
		var contour_points := _organic_ellipse(
			contour[0],
			contour[1],
			float(contour[2]),
			72,
			0.018
		)
		draw_polyline(contour_points, Color(0.60, 0.42, 0.24, 0.22), 1.0, true)

	var ridge_paths := [
		PackedVector2Array([
			Vector2(84.0, 467.0),
			Vector2(151.0, 451.0),
			Vector2(219.0, 456.0),
			Vector2(281.0, 441.0),
			Vector2(345.0, 447.0),
		]),
		PackedVector2Array([
			Vector2(456.0, 181.0),
			Vector2(506.0, 210.0),
			Vector2(553.0, 225.0),
			Vector2(625.0, 248.0),
			Vector2(690.0, 264.0),
		]),
		PackedVector2Array([
			Vector2(651.0, 455.0),
			Vector2(687.0, 438.0),
			Vector2(738.0, 443.0),
			Vector2(780.0, 426.0),
		]),
	]
	for ridge: PackedVector2Array in ridge_paths:
		draw_polyline(ridge, Color(0.055, 0.032, 0.025, 0.86), 5.0, true)
		draw_polyline(ridge, Color(0.46, 0.27, 0.15, 0.48), 1.2, true)
		var hatch_count := maxi(2, ridge.size() - 1)
		for index in range(hatch_count):
			var hatch_start := ridge[index]
			var hatch_end := ridge[index + 1]
			var hatch_center := hatch_start.lerp(hatch_end, 0.52)
			var normal := (hatch_end - hatch_start).normalized().orthogonal()
			draw_line(
				hatch_center - normal * 5.0,
				hatch_center + normal * 5.0,
				Color(COLOR_MUTED, 0.32),
				1.0
			)

	for dust_index in range(48):
		var dust_x := (
			MAP_RECT.position.x
			+ 22.0
			+ fmod(float(dust_index * 127 + 39), MAP_RECT.size.x - 44.0)
		)
		var dust_y := (
			MAP_RECT.position.y
			+ 55.0
			+ fmod(float(dust_index * 71 + 17), MAP_RECT.size.y - 118.0)
		)
		var dust_radius := 0.6 + float(dust_index % 3) * 0.35
		draw_circle(
			Vector2(dust_x, dust_y),
			dust_radius,
			Color(0.77, 0.59, 0.35, 0.20)
		)


func _draw_route_lines() -> void:
	if _node_positions.size() <= 1:
		return

	for index in range(_node_positions.size() - 1):
		var route := _curved_route(_node_positions[index], _node_positions[index + 1], index)
		draw_polyline(route, Color(0.03, 0.024, 0.021, 0.82), 6.0, true)
		draw_polyline(route, Color(0.58, 0.39, 0.22, 0.44), 1.7, true)

		var route_target_state := _node_state(index + 1)
		if route_target_state == "visited":
			draw_polyline(route, Color(COLOR_GREEN, 0.54), 1.2, true)
		elif route_target_state == "insufficient":
			_draw_route_ticks(route, COLOR_RED_DIM)

	if _current_index >= 0 and _selected_index >= 0 and _current_index != _selected_index:
		var first_segment := mini(_current_index, _selected_index)
		var last_segment := maxi(_current_index, _selected_index)
		for index in range(first_segment, last_segment):
			var planned_route := _curved_route(
				_node_positions[index],
				_node_positions[index + 1],
				index
			)
			_draw_dashed_polyline(planned_route, Color(COLOR_CYAN, 0.78), 2.1)


func _curved_route(from: Vector2, to: Vector2, seed: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var direction := to - from
	var bend := direction.normalized().orthogonal() * (8.0 + float(seed % 3) * 4.0)
	var control := from.lerp(to, 0.5) + bend
	var segment_count := 20
	for point_index in range(segment_count + 1):
		var ratio := float(point_index) / float(segment_count)
		var inverse := 1.0 - ratio
		points.append(
			from * inverse * inverse
			+ control * 2.0 * inverse * ratio
			+ to * ratio * ratio
		)
	return points


func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in range(0, points.size() - 1, 2):
		draw_line(points[index], points[index + 1], color, width, true)


func _draw_route_ticks(points: PackedVector2Array, color: Color) -> void:
	for index in range(3, points.size() - 2, 5):
		var direction := (points[index + 1] - points[index - 1]).normalized()
		var normal := direction.orthogonal()
		draw_line(points[index] - normal * 3.0, points[index] + normal * 3.0, color, 1.5)


func _draw_map_nodes(font: Font) -> void:
	for index in range(_node_positions.size()):
		var position := _node_positions[index]
		var state := _node_state(index)
		var node_color := COLOR_SAND
		var node_fill := Color(0.13, 0.095, 0.069, 1.0)
		var radius := 15.0

		match state:
			"current":
				node_color = COLOR_AMBER
				node_fill = Color(0.22, 0.14, 0.065, 1.0)
				radius = 19.0
			"reachable":
				node_color = COLOR_CYAN
				node_fill = Color(0.068, 0.16, 0.15, 1.0)
			"insufficient":
				node_color = COLOR_RED
				node_fill = Color(0.17, 0.073, 0.062, 1.0)
			"visited":
				node_color = COLOR_GREEN
				node_fill = Color(0.075, 0.12, 0.075, 1.0)

		draw_circle(position + Vector2(3.0, 4.0), radius + 5.0, Color(0.0, 0.0, 0.0, 0.38))
		draw_circle(position, radius + 5.0, Color(COLOR_MAP, 0.95))
		draw_arc(position, radius + 4.0, 0.0, TAU, 40, node_color, 1.6, true)
		draw_circle(position, radius, node_fill)
		draw_arc(position, radius, 0.0, TAU, 34, Color(node_color, 0.82), 1.0, true)

		match state:
			"current":
				_draw_current_beacon(position)
			"reachable":
				draw_circle(position, 4.7, node_color)
				draw_arc(position, 9.0, 0.0, TAU, 24, Color(node_color, 0.55), 1.0, true)
			"insufficient":
				draw_line(
					position + Vector2(-5.0, -5.0),
					position + Vector2(5.0, 5.0),
					node_color,
					1.8
				)
				draw_line(
					position + Vector2(5.0, -5.0),
					position + Vector2(-5.0, 5.0),
					node_color,
					1.8
				)
			"visited":
				var check_points := PackedVector2Array([
					position + Vector2(-7.0, 0.0),
					position + Vector2(-2.0, 5.0),
					position + Vector2(8.0, -6.0),
				])
				draw_polyline(check_points, node_color, 2.2, true)

		if index == _selected_index:
			_draw_selection_marks(position, radius + 9.0)

		var number_text := str(index + 1)
		var number_position := position + Vector2(-7.0, -radius - 10.0)
		draw_string(
			font,
			number_position,
			number_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			10,
			Color(node_color, 0.96)
		)

		var label := _fit_text(font, _level_name(index), 12, 144.0)
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x
		var label_y := position.y + radius + 23.0
		if label_y > MAP_RECT.end.y - 72.0:
			label_y = position.y - radius - 15.0
		draw_string(
			font,
			Vector2(position.x - label_width * 0.5, label_y),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			12,
			COLOR_SAND_LIGHT if index == _selected_index else Color(COLOR_SAND, 0.88)
		)

		if state != "current":
			_draw_danger_pips(position + Vector2(radius - 2.0, -radius - 8.0), index)


func _draw_current_beacon(position: Vector2) -> void:
	draw_arc(position, 10.0, 0.0, TAU, 30, Color(COLOR_AMBER, 0.65), 1.2, true)
	draw_line(
		position + Vector2(0.0, -5.0),
		position + Vector2(5.0, 6.0),
		COLOR_SAND_LIGHT,
		1.6
	)
	draw_line(
		position + Vector2(0.0, -5.0),
		position + Vector2(-5.0, 6.0),
		COLOR_SAND_LIGHT,
		1.6
	)
	draw_line(
		position + Vector2(-3.5, 3.0),
		position + Vector2(3.5, 3.0),
		COLOR_SAND_LIGHT,
		1.0
	)
	draw_line(
		position + Vector2(0.0, -20.0),
		position + Vector2(0.0, -27.0),
		Color(COLOR_AMBER, 0.72),
		1.0
	)


func _draw_selection_marks(position: Vector2, radius: float) -> void:
	draw_arc(position, radius, 0.0, TAU, 44, Color(COLOR_CYAN, 0.85), 1.4, true)
	var bracket_color := Color(COLOR_CYAN, 0.98)
	for corner in range(4):
		var angle := float(corner) * PI * 0.5 + PI * 0.25
		var center := position + Vector2.from_angle(angle) * (radius + 4.0)
		var tangent := Vector2.from_angle(angle + PI * 0.5)
		draw_line(center - tangent * 5.0, center + tangent * 5.0, bracket_color, 1.8)


func _draw_danger_pips(position: Vector2, index: int) -> void:
	var danger := _level_danger_value(index)
	var pip_color := _danger_color(index)
	for pip_index in range(3):
		var pip_position := position + Vector2(float(pip_index) * 4.5, 0.0)
		var pip_height := 3.0 + float(pip_index) * 1.6
		var active := danger > 0 and pip_index < ceili(float(danger) / 2.0)
		draw_rect(
			Rect2(pip_position.x, pip_position.y - pip_height, 2.4, pip_height),
			pip_color if active else Color(COLOR_MUTED, 0.25)
		)


func _draw_map_legend(font: Font) -> void:
	var legend_y := MAP_RECT.end.y - 28.0
	draw_line(
		Vector2(MAP_RECT.position.x + 18.0, legend_y - 18.0),
		Vector2(MAP_RECT.end.x - 18.0, legend_y - 18.0),
		COLOR_BORDER_SOFT,
		1.0
	)

	var entries := [
		[COLOR_AMBER, "当前"],
		[COLOR_CYAN, "可达"],
		[COLOR_RED, "燃油不足"],
		[COLOR_GREEN, "已勘探"],
	]
	var cursor_x := MAP_RECT.position.x + 20.0
	for entry: Array in entries:
		var entry_color: Color = entry[0]
		var entry_text: String = entry[1]
		draw_circle(Vector2(cursor_x, legend_y), 3.5, entry_color)
		draw_string(
			font,
			Vector2(cursor_x + 10.0, legend_y + 4.0),
			entry_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			10,
			COLOR_MUTED
		)
		cursor_x += 54.0 + float(entry_text.length()) * 10.0

	var scale_x := MAP_RECT.end.x - 116.0
	draw_line(Vector2(scale_x, legend_y), Vector2(scale_x + 42.0, legend_y), COLOR_SAND, 1.4)
	draw_line(Vector2(scale_x, legend_y - 4.0), Vector2(scale_x, legend_y + 4.0), COLOR_SAND, 1.2)
	draw_line(
		Vector2(scale_x + 42.0, legend_y - 4.0),
		Vector2(scale_x + 42.0, legend_y + 4.0),
		COLOR_SAND,
		1.2
	)
	draw_string(
		font,
		Vector2(scale_x + 49.0, legend_y + 4.0),
		"2 公里",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		COLOR_MUTED
	)


func _draw_detail_panel(font: Font) -> void:
	draw_rect(DETAIL_RECT, COLOR_PANEL)
	draw_rect(DETAIL_RECT, COLOR_BORDER, false, 1.0)
	_draw_panel_corners(DETAIL_RECT, COLOR_AMBER, 14.0)

	if _selected_index < 0 or _selected_index >= _levels.size():
		draw_string(
			font,
			Vector2(DETAIL_RECT.position.x + 24.0, DETAIL_RECT.position.y + 42.0),
			"目的地档案",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			14,
			COLOR_AMBER
		)
		draw_string(
			font,
			Vector2(DETAIL_RECT.position.x + 24.0, DETAIL_RECT.position.y + 106.0),
			"尚无可用航线记录",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			20,
			COLOR_SAND_LIGHT
		)
		draw_multiline_string(
			font,
			Vector2(DETAIL_RECT.position.x + 24.0, DETAIL_RECT.position.y + 140.0),
			"等待远征系统导入节点数据后，航程图会显示可抵达的地表区域。",
			HORIZONTAL_ALIGNMENT_LEFT,
			DETAIL_RECT.size.x - 48.0,
			13,
			3,
			COLOR_MUTED
		)
		return

	var selected_state := _node_state(_selected_index)
	var cost := _level_fuel_cost(_selected_index)
	var danger_value := _level_danger_value(_selected_index)
	var status_text := "航线可达"
	var status_color := COLOR_CYAN
	match selected_state:
		"current":
			status_text = "当前驻留节点"
			status_color = COLOR_AMBER
		"visited":
			status_text = "已勘探"
			status_color = COLOR_GREEN
		"insufficient":
			status_text = "燃油不足"
			status_color = COLOR_RED

	var content_x := DETAIL_RECT.position.x + 24.0
	var content_width := DETAIL_RECT.size.x - 48.0

	draw_string(
		font,
		Vector2(content_x, DETAIL_RECT.position.y + 37.0),
		"目的地档案",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		COLOR_AMBER
	)
	var id_text := "记录号  %s" % _level_id(_selected_index)
	var id_width := font.get_string_size(id_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x
	draw_string(
		font,
		Vector2(DETAIL_RECT.end.x - 24.0 - id_width, DETAIL_RECT.position.y + 37.0),
		id_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		COLOR_MUTED
	)
	draw_line(
		Vector2(content_x, DETAIL_RECT.position.y + 49.0),
		Vector2(content_x + content_width, DETAIL_RECT.position.y + 49.0),
		COLOR_BORDER_SOFT,
		1.0
	)

	var title := _fit_text(font, _level_name(_selected_index), 23, content_width)
	draw_string(
		font,
		Vector2(content_x, DETAIL_RECT.position.y + 87.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		23,
		COLOR_SAND_LIGHT
	)

	var status_width := (
		font.get_string_size(status_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
		+ 18.0
	)
	var status_rect := Rect2(content_x, DETAIL_RECT.position.y + 104.0, status_width, 24.0)
	draw_rect(status_rect, Color(status_color, 0.12))
	draw_rect(status_rect, Color(status_color, 0.55), false, 1.0)
	draw_string(
		font,
		Vector2(status_rect.position.x + 9.0, status_rect.position.y + 17.0),
		status_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		status_color
	)

	var danger_text := "危险等级  %s" % _danger_label(_selected_index)
	draw_string(
		font,
		Vector2(content_x + status_width + 18.0, DETAIL_RECT.position.y + 121.0),
		danger_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		_danger_color(_selected_index)
	)

	draw_string(
		font,
		Vector2(content_x, DETAIL_RECT.position.y + 165.0),
		"区域说明",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		COLOR_MUTED
	)
	draw_multiline_string(
		font,
		Vector2(content_x, DETAIL_RECT.position.y + 189.0),
		_level_description(_selected_index),
		HORIZONTAL_ALIGNMENT_LEFT,
		content_width,
		13,
		5,
		Color(COLOR_SAND, 0.90)
	)

	draw_line(
		Vector2(content_x, DETAIL_RECT.position.y + 283.0),
		Vector2(content_x + content_width, DETAIL_RECT.position.y + 283.0),
		COLOR_BORDER_SOFT,
		1.0
	)

	var fuel_card_width := (content_width - 12.0) * 0.5
	var current_fuel_rect := Rect2(
		content_x,
		DETAIL_RECT.position.y + 303.0,
		fuel_card_width,
		82.0
	)
	var cost_rect := Rect2(
		content_x + fuel_card_width + 12.0,
		DETAIL_RECT.position.y + 303.0,
		fuel_card_width,
		82.0
	)
	_draw_stat_card(
		font,
		current_fuel_rect,
		"当前燃油",
		"%d" % _current_fuel,
		"单位",
		COLOR_AMBER
	)
	_draw_stat_card(
		font,
		cost_rect,
		"所需燃油",
		"%d" % cost,
		"单位",
		COLOR_CYAN if cost <= _current_fuel else COLOR_RED
	)

	var fuel_ratio := 0.0
	if cost > 0:
		fuel_ratio = clampf(float(_current_fuel) / float(cost), 0.0, 1.0)
	elif _current_fuel > 0:
		fuel_ratio = 1.0
	var fuel_bar_rect := Rect2(
		content_x,
		DETAIL_RECT.position.y + 399.0,
		content_width,
		7.0
	)
	draw_rect(fuel_bar_rect, Color(0.025, 0.021, 0.018, 0.9))
	draw_rect(
		Rect2(fuel_bar_rect.position, Vector2(fuel_bar_rect.size.x * fuel_ratio, fuel_bar_rect.size.y)),
		COLOR_CYAN if cost <= _current_fuel else COLOR_RED
	)
	draw_rect(fuel_bar_rect, COLOR_BORDER_SOFT, false, 1.0)

	var balance_text := "抵达后预计余量  %d 单位" % (_current_fuel - cost)
	if cost > _current_fuel:
		balance_text = "仍缺少 %d 单位燃油" % (cost - _current_fuel)
	else:
		balance_text = "抵达后预计余量  %d 单位" % (_current_fuel - cost)
	draw_string(
		font,
		Vector2(content_x, DETAIL_RECT.position.y + 429.0),
		balance_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		COLOR_MUTED
	)

	var route_number := _selected_index + 1
	draw_string(
		font,
		Vector2(content_x, DETAIL_RECT.position.y + 474.0),
		"计划航线  %02d → %02d" % [maxi(1, _current_index + 1), route_number],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		COLOR_MUTED
	)

	var action_text := "Enter / 双击节点  确认出发"
	var action_color := COLOR_CYAN
	match selected_state:
		"current":
			action_text = "当前节点，请选择下一目的地"
			action_color = COLOR_MUTED
		"visited":
			action_text = "该区域已完成勘探"
			action_color = COLOR_MUTED
		"insufficient":
			action_text = "燃油不足，无法确认此航线"
			action_color = COLOR_RED

	var action_rect := Rect2(
		content_x,
		DETAIL_RECT.position.y + 488.0,
		content_width,
		22.0
	)
	draw_rect(action_rect, Color(action_color, 0.075))
	var action_width := font.get_string_size(
		action_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11
	).x
	draw_string(
		font,
		Vector2(action_rect.position.x + 8.0, action_rect.position.y + 16.0),
		action_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		action_rect.size.x - 16.0,
		11,
		action_color
	)
	if action_width > action_rect.size.x - 16.0 and selected_state == "reachable":
		draw_string(
			font,
			Vector2(content_x, DETAIL_RECT.position.y + 507.0),
			"也可再次点击已选中的可达节点",
			HORIZONTAL_ALIGNMENT_LEFT,
			content_width,
			9,
			COLOR_MUTED
		)

	# 危险等级以五格短刻度补充，避免依赖颜色单一表达风险。
	var meter_x := DETAIL_RECT.end.x - 112.0
	var meter_y := DETAIL_RECT.position.y + 113.0
	for pip_index in range(5):
		var pip_rect := Rect2(float(meter_x + pip_index * 13), float(meter_y), 8.0, 4.0)
		var active_count := 0
		if danger_value > 0:
			active_count = clampi(danger_value, 1, 5)
		draw_rect(
			pip_rect,
			_danger_color(_selected_index)
			if pip_index < active_count
			else Color(COLOR_MUTED, 0.17)
		)


func _draw_stat_card(
	font: Font,
	rect: Rect2,
	label: String,
	value: String,
	unit: String,
	accent: Color
) -> void:
	draw_rect(rect, COLOR_PANEL_LIGHT)
	draw_rect(rect, Color(accent, 0.28), false, 1.0)
	draw_string(
		font,
		Vector2(rect.position.x + 12.0, rect.position.y + 20.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		COLOR_MUTED
	)
	draw_string(
		font,
		Vector2(rect.position.x + 12.0, rect.position.y + 57.0),
		value,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		25,
		accent
	)
	var value_width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 25).x
	draw_string(
		font,
		Vector2(rect.position.x + 18.0 + value_width, rect.position.y + 57.0),
		unit,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		COLOR_MUTED
	)


func _draw_footer_hints(font: Font) -> void:
	draw_line(Vector2(36.0, 658.0), Vector2(1244.0, 658.0), COLOR_BORDER_SOFT, 1.0)
	draw_string(
		font,
		Vector2(36.0, 682.0),
		"1–9  选择节点",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		COLOR_MUTED
	)
	draw_string(
		font,
		Vector2(174.0, 682.0),
		"方向键  循环选择",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		COLOR_MUTED
	)
	draw_string(
		font,
		Vector2(342.0, 682.0),
		"Enter  确认",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		COLOR_MUTED
	)
	draw_string(
		font,
		Vector2(475.0, 682.0),
		"Esc  返回远征",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		COLOR_MUTED
	)
	draw_string(
		font,
		Vector2(933.0, 682.0),
		"单击选择 · 双击出发",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		Color(COLOR_MUTED, 0.86)
	)


func _draw_panel_corners(rect: Rect2, color: Color, length: float) -> void:
	var corner_color := Color(color, 0.74)
	draw_line(rect.position, rect.position + Vector2(length, 0.0), corner_color, 1.5)
	draw_line(rect.position, rect.position + Vector2(0.0, length), corner_color, 1.5)
	draw_line(
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x - length, rect.position.y),
		corner_color,
		1.5
	)
	draw_line(
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, rect.position.y + length),
		corner_color,
		1.5
	)
	draw_line(
		Vector2(rect.position.x, rect.end.y),
		Vector2(rect.position.x + length, rect.end.y),
		corner_color,
		1.5
	)
	draw_line(
		Vector2(rect.position.x, rect.end.y),
		Vector2(rect.position.x, rect.end.y - length),
		corner_color,
		1.5
	)
	draw_line(
		rect.end,
		rect.end - Vector2(length, 0.0),
		corner_color,
		1.5
	)
	draw_line(
		rect.end,
		rect.end - Vector2(0.0, length),
		corner_color,
		1.5
	)


func _organic_ellipse(
	center: Vector2,
	radii: Vector2,
	phase: float,
	point_count: int,
	wobble: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_count := maxi(12, point_count)
	for point_index in range(safe_count + 1):
		var ratio := float(point_index) / float(safe_count)
		var angle := ratio * TAU
		var radius_scale := 1.0 + sin(angle * 3.0 + phase) * wobble
		radius_scale += sin(angle * 5.0 - phase * 1.7) * wobble * 0.45
		points.append(
			center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * radius_scale
		)
	return points


func _fit_text(font: Font, text: String, font_size: int, max_width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= max_width:
		return text

	var ellipsis := "…"
	var fitted := text
	while not fitted.is_empty():
		fitted = fitted.left(fitted.length() - 1)
		var candidate := fitted.rstrip("，。；、,. ") + ellipsis
		if font.get_string_size(
			candidate,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		).x <= max_width:
			return candidate
	return ellipsis
