class_name PlanetSurface
extends Node2D

## Khepri-9 / 烬砂荒原的地表背景。
##
## 所有地形数据在 configure() 中一次性生成，_draw() 只遍历缓存数据。
## 坐标统一使用世界坐标，节点自身应位于世界原点。

const SURFACE_NAME := "Khepri-9 / 烬砂荒原"
const MIN_WORLD_SIZE := Vector2(7680.0, 5120.0)

const COLOR_SURFACE_BASE := Color("#5b3026")
const COLOR_SAFE_SAND := Color("#a06f46")
const COLOR_SAFE_LIGHT := Color("#c39761")
const COLOR_RUST := Color("#a94f35")
const COLOR_RUST_LIGHT := Color("#c66d47")
const COLOR_OCHRE := Color("#a87743")
const COLOR_OCHRE_LIGHT := Color("#cc9b5f")
const COLOR_BROWN := Color("#5a3027")
const COLOR_DEEP := Color("#3b2323")
const COLOR_DEEP_DUST := Color("#59302a")
const COLOR_SHADOW := Color("#211417")
const COLOR_CRACK := Color("#2a1819")
const COLOR_CRYSTAL := Color("#61d8c7")
const COLOR_CRYSTAL_DARK := Color("#244c5a")
const COLOR_MOSS := Color("#76d4a4")

const BACKGROUND_Z_INDEX := -20
const PATCH_COUNT_MIN := 120
const PATCH_COUNT_MAX := 220
const CRATER_COUNT_MIN := 70
const CRATER_COUNT_MAX := 120
const ROCK_COUNT_MIN := 250
const ROCK_COUNT_MAX := 450
const DUST_COUNT_MIN := 80
const DUST_COUNT_MAX := 140

var world_size := Vector2.ZERO
var base_position := Vector2.ZERO
var terrain_seed := 137
var world_rect := Rect2()
var safe_radius := 760.0
var rust_radius := 2860.0

var _configured := false
var _rng := RandomNumberGenerator.new()

var _terrain_washes: Array[Dictionary] = []
var _surface_patches: Array[Dictionary] = []
var _craters: Array[Dictionary] = []
var _cracks: Array[Dictionary] = []
var _rocks: Array[Dictionary] = []
var _dust_motes: Array[Dictionary] = []
var _moss_clusters: Array[Dictionary] = []
var _crystal_veins: Array[Dictionary] = []

var _safe_basin: PackedVector2Array = PackedVector2Array()
var _safe_basin_inner: PackedVector2Array = PackedVector2Array()
var _safe_basin_shadow: PackedVector2Array = PackedVector2Array()
var _safe_basin_rim: PackedVector2Array = PackedVector2Array()
var _safe_sediment_lines: Array[PackedVector2Array] = []


func _ready() -> void:
	z_as_relative = false
	z_index = BACKGROUND_Z_INDEX
	process_mode = Node.PROCESS_MODE_DISABLED
	if not _configured:
		configure(MIN_WORLD_SIZE, MIN_WORLD_SIZE * 0.5, 137)


## 以固定种子重建一颗星球的完整地表。
## world_size 小于最低尺寸时会自动扩展，避免 1280x720 摄像机移动时露出空白。
func configure(world_size: Vector2, base_position: Vector2, terrain_seed: int = 137) -> void:
	self.world_size = Vector2(
		maxf(MIN_WORLD_SIZE.x, ceilf(maxf(0.0, world_size.x))),
		maxf(MIN_WORLD_SIZE.y, ceilf(maxf(0.0, world_size.y)))
	)
	terrain_seed = terrain_seed

	var edge_margin := minf(220.0, minf(self.world_size.x, self.world_size.y) * 0.08)
	self.base_position = Vector2(
		clampf(base_position.x, edge_margin, self.world_size.x - edge_margin),
		clampf(base_position.y, edge_margin, self.world_size.y - edge_margin)
	)
	world_rect = Rect2(Vector2.ZERO, self.world_size)

	var short_side := minf(self.world_size.x, self.world_size.y)
	safe_radius = clampf(short_side * 0.145, 720.0, 920.0)
	rust_radius = clampf(short_side * 0.56, 2580.0, 3400.0)

	position = Vector2.ZERO
	z_as_relative = false
	z_index = BACKGROUND_Z_INDEX
	_configured = true
	_generate_all()
	queue_redraw()


## 返回世界坐标所属生态带："safe"、"rust" 或 "deep"。
func get_biome_at(world_position: Vector2) -> String:
	var distance := world_position.distance_to(base_position)
	if distance <= maxf(1.0, safe_radius):
		return "safe"
	if distance <= maxf(safe_radius + 1.0, rust_radius):
		return "rust"
	return "deep"


## 检查圆形瞬生物范围是否避开所有岩块和岩脊。
## 返回 true 表示该位置可安全生成；坐标为世界坐标。
func get_spawn_clearance(position: Vector2, radius: float) -> bool:
	if not _configured or radius < 0.0:
		return false

	var inset := world_rect.grow(-radius)
	if not inset.has_point(position):
		return false

	for rock: Dictionary in _rocks:
		var obstacle_radius := float(rock["collision_radius"])
		if rock["kind"] == "ridge":
			var segment_start: Vector2 = rock["segment_start"]
			var segment_end: Vector2 = rock["segment_end"]
			var clearance := radius + obstacle_radius
			if (
				_distance_squared_to_segment(position, segment_start, segment_end)
				<= clearance * clearance
			):
				return false
		else:
			var clearance := radius + obstacle_radius
			if position.distance_squared_to(rock["position"]) <= clearance * clearance:
				return false

	return true


## 暴露生成统计，便于主场景调试或批量生成资源前检查。
func get_generation_summary() -> Dictionary:
	return {
		"surface_name": SURFACE_NAME,
		"terrain_seed": terrain_seed,
		"world_size": world_size,
		"base_position": base_position,
		"safe_radius": safe_radius,
		"rust_radius": rust_radius,
		"surface_patches": _surface_patches.size(),
		"craters": _craters.size(),
		"rocks_and_ridges": _rocks.size(),
		"dust_motes": _dust_motes.size(),
		"cracks": _cracks.size(),
		"moss_clusters": _moss_clusters.size(),
		"crystal_veins": _crystal_veins.size(),
	}


func _generate_all() -> void:
	_terrain_washes.clear()
	_surface_patches.clear()
	_craters.clear()
	_cracks.clear()
	_rocks.clear()
	_dust_motes.clear()
	_moss_clusters.clear()
	_crystal_veins.clear()
	_safe_sediment_lines.clear()

	_rng.seed = terrain_seed
	_generate_safe_basin()
	_generate_terrain_washes(18)
	_generate_surface_patches(_rng.randi_range(PATCH_COUNT_MIN, PATCH_COUNT_MAX))
	_generate_cracks(_rng.randi_range(72, 104))
	_generate_crystal_veins(12)
	_generate_craters(_rng.randi_range(CRATER_COUNT_MIN, CRATER_COUNT_MAX))
	_generate_rocks(_rng.randi_range(ROCK_COUNT_MIN, ROCK_COUNT_MAX))
	_generate_moss_clusters(42)
	_generate_dust_motes(_rng.randi_range(DUST_COUNT_MIN, DUST_COUNT_MAX))


func _generate_safe_basin() -> void:
	var outer_radii := Vector2(safe_radius * 1.13, safe_radius * 0.94)
	_safe_basin = _make_organic_ellipse(
		base_position,
		outer_radii,
		-0.08,
		56,
		0.035,
		1.7
	)
	_safe_basin_inner = _make_organic_ellipse(
		base_position + Vector2(4.0, 2.0),
		outer_radii * 0.82,
		-0.08,
		48,
		0.025,
		1.7
	)
	_safe_basin_shadow = _translated_points(_safe_basin, Vector2(18.0, 22.0))
	_safe_basin_rim = _closed_path(_safe_basin)

	var line_count := 15
	for index in range(line_count):
		var normalized := (float(index) + 0.5) / float(line_count) * 2.0 - 1.0
		var y_offset := normalized * safe_radius * 0.72
		var half_width := sqrt(maxf(0.0, 1.0 - normalized * normalized)) * safe_radius * 0.92
		var points := PackedVector2Array()
		var point_count := 7
		for point_index in range(point_count):
			var ratio := float(point_index) / float(point_count - 1)
			var x_offset := lerpf(-half_width, half_width, ratio)
			var ripple := sin(ratio * PI * 2.0 + float(index) * 0.9) * 5.0
			points.append(base_position + Vector2(x_offset, y_offset + ripple))
		_safe_sediment_lines.append(points)


func _generate_terrain_washes(count: int) -> void:
	for index in range(count):
		var center := Vector2(
			_rng.randf_range(-180.0, world_size.x + 180.0),
			_rng.randf_range(-150.0, world_size.y + 150.0)
		)
		var biome := get_biome_at(center)
		var radii := Vector2(
			_rng.randf_range(280.0, 980.0),
			_rng.randf_range(130.0, 520.0)
		)
		var color := COLOR_BROWN
		if biome == "safe":
			color = COLOR_SAFE_SAND
		elif biome == "deep":
			color = COLOR_DEEP_DUST

		color.a = _rng.randf_range(0.08, 0.18)
		var points := _make_organic_ellipse(
			center,
			radii,
			_rng.randf_range(0.0, TAU),
			26,
			0.16,
			_rng.randf_range(0.0, TAU)
		)
		_terrain_washes.append({
			"points": points,
			"color": color,
		})


func _generate_surface_patches(count: int) -> void:
	for index in range(count):
		var center := _grid_jitter_position(index, count, 90.0)
		var biome := get_biome_at(center)
		var long_radius := _rng.randf_range(90.0, 390.0)
		var short_radius := _rng.randf_range(45.0, minf(235.0, long_radius))
		var rotation := _rng.randf_range(0.0, TAU)
		var color := _pick_surface_color(biome, index)
		var rim_color := color.lightened(_rng.randf_range(0.08, 0.19))
		color.a = _rng.randf_range(0.22, 0.48)
		rim_color.a = _rng.randf_range(0.08, 0.2)

		var radii := Vector2(long_radius, short_radius)
		var points := _make_organic_ellipse(
			center,
			radii,
			rotation,
			15,
			0.22,
			float(index) * 0.73
		)
		var outline := _closed_path(points)
		var strata: Array[PackedVector2Array] = []
		var strata_count := _rng.randi_range(1, 3)
		for strata_index in range(strata_count):
			strata.append(_make_sand_stroke(center, radii, rotation, strata_index, strata_count))

		_surface_patches.append({
			"points": points,
			"outline": outline,
			"strata": strata,
			"color": color,
			"rim_color": rim_color,
			"show_rim": index % 3 != 1,
		})


func _generate_cracks(count: int) -> void:
	for index in range(count):
		var preferred_biome := "deep" if index % 4 != 0 else "rust"
		var start := _sample_position_for_biome(preferred_biome, 150.0)
		if start.distance_to(base_position) <= safe_radius * 1.16:
			start = _sample_position_outside_range(base_position, safe_radius * 1.18, 120.0)

		var direction := _rng.randf_range(0.0, TAU)
		var points := PackedVector2Array([start])
		var segment_count := _rng.randi_range(5, 11)
		var deep_multiplier := 1.35 if preferred_biome == "deep" else 1.0
		for segment_index in range(segment_count):
			direction += _rng.randf_range(-0.46, 0.46)
			var step := _rng.randf_range(24.0, 67.0) * deep_multiplier
			var next_point: Vector2 = points[points.size() - 1] + Vector2.from_angle(direction) * step
			next_point = next_point.clamp(Vector2(18.0, 18.0), world_size - Vector2(18.0, 18.0))
			points.append(next_point)

		var branches: Array[PackedVector2Array] = []
		if _rng.randf() < 0.38:
			var branch_origin_index := _rng.randi_range(1, points.size() - 2)
			var branch_points := PackedVector2Array([points[branch_origin_index]])
			var branch_direction := direction + _rng.randf_range(0.55, 1.05) * (-1.0 if _rng.randf() < 0.5 else 1.0)
			for _branch_index in range(_rng.randi_range(2, 4)):
				branch_direction += _rng.randf_range(-0.24, 0.24)
				var branch_point: Vector2 = (
					branch_points[branch_points.size() - 1]
					+ Vector2.from_angle(branch_direction) * _rng.randf_range(18.0, 43.0)
				)
				branch_point = branch_point.clamp(
					Vector2(12.0, 12.0),
					world_size - Vector2(12.0, 12.0)
				)
				branch_points.append(branch_point)
			branches.append(branch_points)

		_cracks.append({
			"points": points,
			"branches": branches,
			"width": _rng.randf_range(1.2, 3.2),
		})


func _generate_crystal_veins(count: int) -> void:
	for index in range(count):
		var start := _sample_position_for_biome("deep", 220.0)
		var points := PackedVector2Array([start])
		var direction := _rng.randf_range(0.0, TAU)
		for _point_index in range(_rng.randi_range(4, 7)):
			direction += _rng.randf_range(-0.36, 0.36)
			var next_point: Vector2 = (
				points[points.size() - 1]
				+ Vector2.from_angle(direction) * _rng.randf_range(130.0, 280.0)
			)
			next_point = next_point.clamp(Vector2(80.0, 80.0), world_size - Vector2(80.0, 80.0))
			points.append(next_point)

		var shards: Array[Dictionary] = []
		var shard_count := _rng.randi_range(4, 8)
		for _shard_index in range(shard_count):
			var anchor_index := _rng.randi_range(0, points.size() - 1)
			var shard_direction := direction + _rng.randf_range(-1.15, 1.15)
			var shard_length := _rng.randf_range(18.0, 54.0)
			var anchor: Vector2 = points[anchor_index]
			var end_point := anchor + Vector2.from_angle(shard_direction) * shard_length
			var side := Vector2.from_angle(shard_direction + PI * 0.5) * _rng.randf_range(3.0, 9.0)
			shards.append({
				"points": PackedVector2Array([
					anchor - side,
					end_point,
					anchor + side,
				]),
			})

		_crystal_veins.append({
			"points": points,
			"glow_width": _rng.randf_range(10.0, 24.0),
			"core_width": _rng.randf_range(2.0, 5.0),
			"shards": shards,
		})


func _generate_craters(count: int) -> void:
	for index in range(count):
		var deep := index % 5 != 0
		var center := _sample_position_for_biome("deep" if deep else "rust", 100.0)
		var scale := 1.22 if deep else 0.9
		var radii := Vector2(
			_rng.randf_range(20.0, 92.0) * scale,
			_rng.randf_range(14.0, 62.0) * scale
		)

		var attempt := 0
		while center.distance_to(base_position) < safe_radius * 1.22 + maxf(radii.x, radii.y):
			center = _sample_position_for_biome("deep" if deep else "rust", 130.0)
			attempt += 1
			if attempt > 40:
				break

		var rotation := _rng.randf_range(0.0, TAU)
		var outer_points := _make_organic_ellipse(
			center,
			radii,
			rotation,
			30,
			0.085,
			_rng.randf_range(0.0, TAU)
		)
		var inner_points := _make_organic_ellipse(
			center + Vector2(radii.x * 0.08, radii.y * 0.1),
			radii * _rng.randf_range(0.58, 0.78),
			rotation,
			24,
			0.07,
			_rng.randf_range(0.0, TAU)
		)
		var shadow_points := _translated_points(outer_points, Vector2(7.0, 9.0))
		var outer_outline := _closed_path(outer_points)

		var highlight := PackedVector2Array()
		var highlight_start := 17
		for highlight_index in range(highlight_start, highlight_start + 8):
			highlight.append(outer_points[highlight_index % outer_points.size()])

		var ejecta: Array[PackedVector2Array] = []
		for _ejecta_index in range(_rng.randi_range(3, 7)):
			var ejecta_angle := _rng.randf_range(0.0, TAU)
			var ejecta_direction := Vector2.from_angle(ejecta_angle)
			var start := center + Vector2(ejecta_direction.x * radii.x, ejecta_direction.y * radii.y) * 0.92
			var finish := start + ejecta_direction * _rng.randf_range(9.0, 38.0)
			ejecta.append(PackedVector2Array([start, finish]))

		_craters.append({
			"shadow": shadow_points,
			"outer": outer_points,
			"outer_outline": outer_outline,
			"inner": inner_points,
			"highlight": highlight,
			"ejecta": ejecta,
			"shadow_color": COLOR_SHADOW,
			"floor_color": COLOR_DEEP if deep else COLOR_BROWN,
		})


func _generate_rocks(count: int) -> void:
	for index in range(count):
		var deep := index % 10 < 7
		var center := _sample_position_for_biome("deep" if deep else "rust", 65.0)
		if center.distance_to(base_position) < safe_radius * 1.1:
			center = _sample_position_outside_range(base_position, safe_radius * 1.12, 55.0)

		var ridge_chance := 0.32 if deep else 0.2
		var ridge := _rng.randf() < ridge_chance
		if ridge:
			var angle := _rng.randf_range(0.0, TAU)
			var half_length := _rng.randf_range(30.0, 96.0) * (1.18 if deep else 1.0)
			var half_width := _rng.randf_range(7.0, 18.0) * (1.16 if deep else 1.0)
			var start := center - Vector2.from_angle(angle) * half_length
			var finish := center + Vector2.from_angle(angle) * half_length
			var points := _make_ridge_polygon(start, finish, half_width, angle)
			var shadow := _translated_points(points, Vector2(5.0, 7.0))
			var outline := _closed_path(points)
			_rocks.append({
				"kind": "ridge",
				"position": center,
				"segment_start": start,
				"segment_end": finish,
				"collision_radius": half_width * 0.9,
				"points": points,
				"shadow": shadow,
				"outline": outline,
				"color": (COLOR_DEEP_DUST if deep else COLOR_BROWN).lightened(
					_rng.randf_range(0.02, 0.12)
				),
				"ridge_color": COLOR_RUST if not deep else COLOR_OCHRE,
			})
		else:
			var radius := _rng.randf_range(5.5, 17.0) * (1.3 if deep else 1.0)
			var rotation := _rng.randf_range(0.0, TAU)
			var half_radii := Vector2(
				radius * _rng.randf_range(0.8, 1.75),
				radius * _rng.randf_range(0.55, 1.1)
			)
			var points := _make_organic_ellipse(
				center,
				half_radii,
				rotation,
				_rng.randi_range(5, 8),
				0.3,
				_rng.randf_range(0.0, TAU)
			)
			var shadow := _translated_points(points, Vector2(5.0, 7.0))
			var outline := _closed_path(points)
			var facet := PackedVector2Array([
				center.lerp(points[0], 0.78),
				center.lerp(points[1], 0.7),
				center + Vector2(-half_radii.x, -half_radii.y) * 0.1,
			])
			_rocks.append({
				"kind": "boulder",
				"position": center,
				"collision_radius": maxf(half_radii.x, half_radii.y),
				"points": points,
				"shadow": shadow,
				"outline": outline,
				"facet": facet,
				"color": (COLOR_DEEP_DUST if deep else COLOR_BROWN).darkened(
					_rng.randf_range(0.03, 0.18)
				),
				"facet_color": COLOR_RUST_LIGHT.darkened(_rng.randf_range(0.05, 0.25)),
			})


func _generate_moss_clusters(count: int) -> void:
	for index in range(count):
		var center := Vector2.ZERO
		var found := false
		for attempt in range(40):
			var angle := _rng.randf_range(0.0, TAU)
			var distance := safe_radius * _rng.randf_range(0.86, 1.85)
			center = base_position + Vector2.from_angle(angle) * distance
			if (
				world_rect.grow(-35.0).has_point(center)
				and get_biome_at(center) != "deep"
			):
				found = true
				break
		if not found:
			center = _sample_position_for_biome("rust", 40.0)

		var dots: Array[Dictionary] = []
		for _dot_index in range(_rng.randi_range(2, 5)):
			dots.append({
				"offset": Vector2(
					_rng.randf_range(-18.0, 18.0),
					_rng.randf_range(-11.0, 11.0)
				),
				"radius": _rng.randf_range(1.1, 3.1),
				"halo_radius": _rng.randf_range(6.0, 13.0),
			})
		_moss_clusters.append({
			"position": center,
			"dots": dots,
			"alpha": _rng.randf_range(0.34, 0.66),
		})


func _generate_dust_motes(count: int) -> void:
	for index in range(count):
		var local_position := Vector2(
			_rng.randf_range(20.0, world_size.x - 20.0),
			_rng.randf_range(20.0, world_size.y - 20.0)
		)
		var biome := get_biome_at(local_position)
		var color := COLOR_OCHRE_LIGHT
		if biome == "deep":
			color = COLOR_RUST_LIGHT
		color.a = _rng.randf_range(0.16, 0.4)

		_dust_motes.append({
			"position": local_position,
			"radius": _rng.randf_range(0.7, 1.8),
			"length": _rng.randf_range(3.0, 11.0),
			"rotation": _rng.randf_range(-0.35, 0.18),
			"color": color,
		})


func _pick_surface_color(biome: String, index: int) -> Color:
	var choose := (index * 7 + terrain_seed) % 5
	if biome == "safe":
		return COLOR_OCHRE_LIGHT if choose < 3 else COLOR_SAFE_LIGHT
	if biome == "deep":
		return [COLOR_DEEP, COLOR_DEEP_DUST, COLOR_BROWN, COLOR_RUST, COLOR_DEEP][choose]
	return [COLOR_RUST, COLOR_OCHRE, COLOR_BROWN, COLOR_RUST_LIGHT, COLOR_OCHRE_LIGHT][choose]


func _make_sand_stroke(
	center: Vector2,
	radii: Vector2,
	rotation: float,
	index: int,
	count: int
) -> PackedVector2Array:
	var normalized := (float(index) + 1.0) / (float(count) + 1.0) * 2.0 - 1.0
	var local_y := normalized * radii.y * 0.48
	var remaining := 1.0 - normalized * normalized * 0.7
	var half_width := radii.x * 0.35 * remaining
	var points := PackedVector2Array()
	for point_index in range(4):
		var ratio := float(point_index) / 3.0
		var local_x := lerpf(-half_width, half_width, ratio)
		var bend := sin(ratio * PI + float(index)) * radii.y * 0.05
		points.append(center + Vector2(local_x, local_y + bend).rotated(rotation))
	return points


func _make_organic_ellipse(
	center: Vector2,
	radii: Vector2,
	rotation: float,
	segments: int,
	jitter: float,
	phase: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_segments := maxi(3, segments)
	for index in range(safe_segments):
		var angle := TAU * float(index) / float(safe_segments)
		var wobble := (
			1.0
			+ sin(angle * 3.0 + phase) * jitter
			+ _rng.randf_range(-jitter * 0.28, jitter * 0.28)
		)
		var local_point := Vector2(
			cos(angle) * radii.x,
			sin(angle) * radii.y
		) * wobble
		points.append(center + local_point.rotated(rotation))
	return points


func _make_ridge_polygon(
	start: Vector2,
	finish: Vector2,
	half_width: float,
	angle: float
) -> PackedVector2Array:
	var direction := Vector2.from_angle(angle)
	var normal := direction.orthogonal()
	var points := PackedVector2Array()
	points.append(start + normal * half_width * 0.45)
	for index in range(1, 4):
		var ratio := float(index) / 4.0
		points.append(
			start.lerp(finish, ratio)
			+ normal * half_width * _rng.randf_range(-0.18, 0.72)
		)
	points.append(finish + normal * half_width * 0.2)
	points.append(finish - normal * half_width * _rng.randf_range(0.2, 0.6))
	for index in range(3, 0, -1):
		var ratio := float(index) / 4.0
		points.append(
			start.lerp(finish, ratio)
			- normal * half_width * _rng.randf_range(0.3, 1.0)
		)
	points.append(start - normal * half_width * 0.55)
	return points


func _grid_jitter_position(index: int, total: int, margin: float) -> Vector2:
	var aspect := world_size.x / maxf(1.0, world_size.y)
	var columns := maxi(1, ceili(sqrt(float(total) * aspect)))
	var rows := maxi(1, ceili(float(total) / float(columns)))
	var column := index % columns
	var row := floori(float(index) / float(columns))
	var usable := world_size - Vector2(margin * 2.0, margin * 2.0)
	var cell_size := Vector2(
		usable.x / float(columns),
		usable.y / float(rows)
	)
	var cell_origin := Vector2(margin, margin) + Vector2(
		float(column) * cell_size.x,
		float(row) * cell_size.y
	)
	return cell_origin + Vector2(
		_rng.randf_range(0.12, 0.88) * cell_size.x,
		_rng.randf_range(0.12, 0.88) * cell_size.y
	)


func _sample_position_for_biome(biome: String, margin: float) -> Vector2:
	var safe_margin := clampf(margin, 1.0, minf(world_size.x, world_size.y) * 0.45)
	var candidate := base_position
	for attempt in range(90):
		candidate = Vector2(
			_rng.randf_range(safe_margin, world_size.x - safe_margin),
			_rng.randf_range(safe_margin, world_size.y - safe_margin)
		)
		if get_biome_at(candidate) == biome:
			return candidate
	return candidate


func _sample_position_outside_range(center: Vector2, distance: float, margin: float) -> Vector2:
	for attempt in range(48):
		var candidate := Vector2(
			_rng.randf_range(margin, world_size.x - margin),
			_rng.randf_range(margin, world_size.y - margin)
		)
		if candidate.distance_to(center) >= distance:
			return candidate
	return Vector2(world_size.x - margin, world_size.y - margin)


func _translated_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var translated := PackedVector2Array()
	translated.resize(points.size())
	for index in range(points.size()):
		translated[index] = points[index] + offset
	return translated


func _closed_path(points: PackedVector2Array) -> PackedVector2Array:
	var path := PackedVector2Array()
	path.resize(points.size() + 1)
	for index in range(points.size()):
		path[index] = points[index]
	if points.size() > 0:
		path[points.size()] = points[0]
	return path


func _distance_squared_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_squared_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_squared_to(start + segment * ratio)


func _draw() -> void:
	if not _configured:
		return

	_update_visible_world_rect()
	draw_rect(world_rect, COLOR_SURFACE_BASE)

	for wash: Dictionary in _terrain_washes:
		if not _points_visible(wash["points"]):
			continue
		draw_colored_polygon(wash["points"], wash["color"])

	for patch: Dictionary in _surface_patches:
		if not _points_visible(patch["points"]):
			continue
		draw_colored_polygon(patch["points"], patch["color"])
		if patch["show_rim"]:
			draw_polyline(patch["outline"], patch["rim_color"], 1.4, true)
		for stroke: PackedVector2Array in patch["strata"]:
			draw_polyline(stroke, patch["rim_color"], 1.1, true)

	if _points_visible(_safe_basin):
		_draw_safe_basin()

	for crack: Dictionary in _cracks:
		if not _points_visible(crack["points"]):
			continue
		draw_polyline(crack["points"], COLOR_CRACK, float(crack["width"]) + 2.0, true)
		draw_polyline(crack["points"], COLOR_RUST_LIGHT, 0.75, true)
		for branch: PackedVector2Array in crack["branches"]:
			draw_polyline(branch, COLOR_CRACK, maxf(1.0, float(crack["width"])), true)

	for vein: Dictionary in _crystal_veins:
		if not _points_visible(vein["points"]):
			continue
		draw_polyline(
			vein["points"],
			Color(COLOR_CRYSTAL, 0.08),
			float(vein["glow_width"]),
			true
		)
		draw_polyline(
			vein["points"],
			COLOR_CRYSTAL_DARK,
			maxf(4.0, float(vein["core_width"]) + 3.0),
			true
		)
		draw_polyline(
			vein["points"],
			Color(COLOR_CRYSTAL, 0.72),
			float(vein["core_width"]),
			true
		)
		for shard: Dictionary in vein["shards"]:
			draw_colored_polygon(shard["points"], Color(COLOR_CRYSTAL, 0.62))

	for crater: Dictionary in _craters:
		if not _points_visible(crater["outer"]):
			continue
		draw_colored_polygon(crater["shadow"], crater["shadow_color"])
		for ejecta: PackedVector2Array in crater["ejecta"]:
			draw_polyline(ejecta, Color(COLOR_SHADOW, 0.34), 1.4, true)
		draw_colored_polygon(crater["outer"], crater["floor_color"].lightened(0.1))
		draw_colored_polygon(crater["inner"], crater["floor_color"].darkened(0.2))
		draw_polyline(crater["outer_outline"], Color(COLOR_RUST_LIGHT, 0.38), 1.7, true)
		draw_polyline(crater["highlight"], Color(COLOR_OCHRE_LIGHT, 0.28), 2.1, true)

	for rock: Dictionary in _rocks:
		if not _points_visible(rock["points"]):
			continue
		if rock["kind"] == "ridge":
			draw_colored_polygon(rock["shadow"], Color(COLOR_SHADOW, 0.44))
			draw_colored_polygon(rock["points"], rock["color"])
			draw_polyline(rock["outline"], Color(rock["ridge_color"], 0.33), 1.35, true)
		else:
			draw_colored_polygon(rock["shadow"], Color(COLOR_SHADOW, 0.4))
			draw_colored_polygon(rock["points"], rock["color"])
			draw_colored_polygon(rock["facet"], Color(rock["facet_color"], 0.33))
			draw_polyline(rock["outline"], Color(COLOR_RUST_LIGHT, 0.24), 1.0, true)

	for moss: Dictionary in _moss_clusters:
		if not _view_rect.intersects(
			Rect2(Vector2(moss["position"]) - Vector2(36.0, 36.0), Vector2(72.0, 72.0)),
			false
		):
			continue
		for dot: Dictionary in moss["dots"]:
			var dot_position: Vector2 = moss["position"] + dot["offset"]
			draw_circle(dot_position, float(dot["halo_radius"]), Color(COLOR_MOSS, 0.045 * moss["alpha"]))
			draw_circle(dot_position, float(dot["halo_radius"]) * 0.48, Color(COLOR_MOSS, 0.1 * moss["alpha"]))
			draw_circle(dot_position, float(dot["radius"]), Color(COLOR_MOSS, moss["alpha"]))

	for dust: Dictionary in _dust_motes:
		if not _view_rect.has_point(dust["position"]):
			continue
		var dust_position: Vector2 = dust["position"]
		var streak := Vector2.from_angle(float(dust["rotation"])) * float(dust["length"])
		draw_line(dust_position, dust_position + streak, dust["color"], 1.0, true)
		draw_circle(dust_position, float(dust["radius"]), dust["color"])


var _view_rect := Rect2()


func _update_visible_world_rect() -> void:
	var viewport_rect := get_viewport_rect()
	var inverse_canvas := get_canvas_transform().affine_inverse()
	var corner_a := inverse_canvas * viewport_rect.position
	var corner_b := inverse_canvas * (viewport_rect.position + viewport_rect.size)
	var top_left := Vector2(minf(corner_a.x, corner_b.x), minf(corner_a.y, corner_b.y))
	var bottom_right := Vector2(maxf(corner_a.x, corner_b.x), maxf(corner_a.y, corner_b.y))
	_view_rect = Rect2(top_left, bottom_right - top_left).grow(260.0)


func _points_visible(points: PackedVector2Array) -> bool:
	if points.is_empty():
		return false

	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return _view_rect.intersects(Rect2(minimum, maximum - minimum), false)


func _draw_safe_basin() -> void:
	draw_colored_polygon(_safe_basin_shadow, Color(COLOR_SHADOW, 0.2))
	draw_colored_polygon(_safe_basin, COLOR_SAFE_SAND)
	draw_colored_polygon(_safe_basin_inner, Color(COLOR_SAFE_LIGHT, 0.52))
	draw_polyline(_safe_basin_rim, Color(COLOR_OCHRE_LIGHT, 0.32), 2.0, true)
	for line: PackedVector2Array in _safe_sediment_lines:
		draw_polyline(line, Color(COLOR_BROWN, 0.16), 1.0, true)
