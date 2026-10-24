class_name GameHUD
extends Control

## 轻量 HUD：仅保留区域、燃料、驾驶员状态、键位提示与必要通知。
## 所有元素均由原生绘制 API 生成，不依赖外部字体或图片。

const DESIGN_SIZE := Vector2(1280.0, 720.0)
const INPUT_HINTS := [
	"WASD   移动",
	"Shift   冲刺",
	"E   交互 / 建造",
	"Space   应急脉冲",
]
const TRACKED_STATE_KEYS := [
	"location_name",
	"fuel",
	"fuel_max",
	"player_health",
	"player_health_max",
	"stamina",
	"stamina_max",
	"nearby_action",
	"network_status",
	"network_peers",
	"phase",
	"ship_hull",
	"ship_hull_max",
	"defense_timer",
	"siege_enemies",
]

const COLOR_BAR_BACKGROUND := Color(0.018, 0.038, 0.066, 0.86)
const COLOR_BAR_BACKGROUND_SOFT := Color(0.018, 0.038, 0.066, 0.70)
const COLOR_TRACK := Color(0.015, 0.025, 0.044, 0.88)
const COLOR_BORDER := Color(0.25, 0.55, 0.62, 0.46)
const COLOR_TEXT := Color("#edfaff")
const COLOR_MUTED := Color("#9bb5c3")
const COLOR_CYAN := Color("#68e6d0")
const COLOR_CYAN_DIM := Color("#4ca6af")
const COLOR_AMBER := Color("#f2b85f")
const COLOR_DANGER := Color("#ff7869")

var _state: Dictionary = {
	"location_name": "未知区域",
	"fuel": 0.0,
	"fuel_max": 100.0,
	"player_health": 100.0,
	"player_health_max": 100.0,
	"stamina": 100.0,
	"stamina_max": 100.0,
	"nearby_action": "",
	"network_status": "offline",
	"network_peers": 0,
	"phase": "",
}

var _notice_text := ""
var _notice_color := Color.WHITE
var _notice_duration := 0.0
var _notice_remaining := 0.0
var _notice_alpha := 0.0
var _last_state_notice: Variant = null

var _ui_scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 100

	get_viewport().size_changed.connect(_sync_to_viewport)
	resized.connect(_on_hud_resized)
	_sync_to_viewport()
	set_process(false)


func _process(delta: float) -> void:
	if _notice_remaining <= 0.0:
		return

	_notice_remaining = maxf(0.0, _notice_remaining - delta)
	var fade_duration := minf(0.24, maxf(0.06, _notice_duration * 0.2))
	_notice_alpha = clampf(_notice_remaining / fade_duration, 0.0, 1.0)

	if _notice_remaining <= 0.0:
		_notice_alpha = 0.0
		_notice_text = ""
		set_process(false)

	queue_redraw()


## 增量更新 HUD 状态；仅保存本 HUD 实际使用的字段。
func update_state(state: Dictionary) -> void:
	var needs_redraw := false
	for key: Variant in state:
		if key == &"notice" or not key in TRACKED_STATE_KEYS:
			continue
		if _state.get(key) != state[key]:
			_state[key] = state[key]
			needs_redraw = true

	_sync_state_notice(state)
	if needs_redraw:
		queue_redraw()


## 在顶部信息条下方显示短通知，并在末尾自动淡出。
func show_notice(
	text: String,
	color: Color = Color.WHITE,
	duration: float = 1.8
) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty() or duration <= 0.0:
		return

	_notice_text = clean_text
	_notice_color = color
	_notice_duration = duration
	_notice_remaining = duration
	_notice_alpha = 1.0
	set_process(true)
	queue_redraw()


func clear_notice() -> void:
	_notice_text = ""
	_notice_duration = 0.0
	_notice_remaining = 0.0
	_notice_alpha = 0.0
	set_process(false)
	queue_redraw()


func _sync_state_notice(state: Dictionary) -> void:
	if not state.has("notice"):
		return

	var notice_value: Variant = state["notice"]
	if notice_value == _last_state_notice:
		return

	if notice_value is Dictionary:
		_last_state_notice = notice_value.duplicate(true)
		var text := str(notice_value.get("text", "")).strip_edges()
		if text.is_empty():
			clear_notice()
			return
		var color := _as_color(notice_value.get("color", COLOR_TEXT), COLOR_TEXT)
		var duration := float(notice_value.get("duration", 1.8))
		show_notice(text, color, duration)
		return

	_last_state_notice = notice_value
	var text := str(notice_value).strip_edges()
	if text.is_empty():
		clear_notice()
	else:
		show_notice(text, COLOR_TEXT, 1.8)


func _sync_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.is_zero_approx():
		return

	position = Vector2.ZERO
	if not size.is_equal_approx(viewport_size):
		size = viewport_size
	_update_ui_scale()
	queue_redraw()


func _on_hud_resized() -> void:
	_update_ui_scale()
	queue_redraw()


func _update_ui_scale() -> void:
	var usable_size := size
	if usable_size.is_zero_approx():
		usable_size = get_viewport_rect().size

	_ui_scale = clampf(
		minf(usable_size.x / DESIGN_SIZE.x, usable_size.y / DESIGN_SIZE.y),
		0.75,
		1.6
	)


func _draw() -> void:
	if size.is_zero_approx():
		return

	_update_ui_scale()
	var font := ThemeDB.fallback_font
	_draw_top_status(font)
	_draw_defense_strip(font)
	_draw_input_hints(font)
	_draw_nearby_action(font)
	_draw_notice(font)
	_draw_phase_card(font)


func _draw_top_status(font: Font) -> void:
	var s := _ui_scale
	var bar := _top_bar_rect()
	draw_rect(bar, COLOR_BAR_BACKGROUND)
	draw_rect(bar, COLOR_BORDER, false, maxf(1.0, s))
	draw_rect(
		Rect2(bar.position, Vector2(maxf(2.0, 2.0 * s), bar.size.y)),
		_with_alpha(COLOR_CYAN, 0.78)
	)

	var side_padding := roundf(14.0 * s)
	var inner_left := bar.position.x + side_padding
	var inner_right := bar.end.x - side_padding
	var usable_width := inner_right - inner_left
	var region_width := usable_width * 0.30
	var fuel_width := usable_width * 0.19
	var network_width := minf(usable_width * 0.19, 148.0 * s)
	var region_right := inner_left + region_width
	var fuel_right := region_right + fuel_width
	var network_left := inner_right - network_width

	draw_line(
		Vector2(region_right, bar.position.y + 10.0 * s),
		Vector2(region_right, bar.end.y - 10.0 * s),
		_with_alpha(COLOR_BORDER, 0.65),
		maxf(1.0, s)
	)
	draw_line(
		Vector2(fuel_right, bar.position.y + 10.0 * s),
		Vector2(fuel_right, bar.end.y - 10.0 * s),
		_with_alpha(COLOR_BORDER, 0.65),
		maxf(1.0, s)
	)

	var label_size := maxi(10, roundi(10.0 * s))
	var area_size := maxi(14, roundi(16.0 * s))
	var value_size := maxi(12, roundi(14.0 * s))
	var label_y := bar.position.y + roundf(17.0 * s)
	var value_y := bar.position.y + roundf(39.0 * s)

	_draw_text(
		font,
		Vector2(inner_left, label_y),
		"当前区域",
		label_size,
		COLOR_MUTED,
		region_width - 8.0 * s
	)
	var location_name := _state_text("location_name", "未知区域").strip_edges()
	if location_name.is_empty():
		location_name = "未知区域"
	_draw_text(
		font,
		Vector2(inner_left, value_y),
		_truncate_text(font, location_name, region_width - 8.0 * s, area_size),
		area_size,
		COLOR_TEXT,
		region_width - 8.0 * s
	)

	var fuel_x := region_right + roundf(12.0 * s)
	var fuel_max := maxf(1.0, _state_number("fuel_max", 100.0))
	var fuel := clampf(_state_number("fuel", 0.0), 0.0, fuel_max)
	_draw_text(
		font,
		Vector2(fuel_x, label_y),
		"燃油",
		label_size,
		COLOR_MUTED,
		fuel_width - 20.0 * s
	)
	_draw_text(
		font,
		Vector2(fuel_x, value_y),
		"%d / %d" % [ceili(fuel), ceili(fuel_max)],
		value_size,
		COLOR_AMBER,
		fuel_width - 20.0 * s
	)

	var driver_x := fuel_right + roundf(12.0 * s)
	var driver_width := network_left - roundf(12.0 * s) - driver_x
	_draw_driver_bars(font, driver_x, driver_width, bar)
	_draw_network_tag(font, network_left, network_width, bar)


func _draw_defense_strip(font: Font) -> void:
	if _state_text("phase", "") != "defense":
		return

	var s := _ui_scale
	var top_bar := _top_bar_rect()
	var margin := roundf(18.0 * s)
	var strip := Rect2(
		Vector2(margin, top_bar.end.y + 5.0 * s),
		Vector2(minf(size.x - margin * 2.0, 620.0 * s), 30.0 * s)
	)
	draw_rect(strip, COLOR_BAR_BACKGROUND_SOFT)
	draw_rect(strip, _with_alpha(COLOR_DANGER, 0.54), false, maxf(1.0, s))

	var hull_max := maxf(1.0, _state_number("ship_hull_max", 240.0))
	var hull := clampf(_state_number("ship_hull", hull_max), 0.0, hull_max)
	var timer := maxf(0.0, _state_number("defense_timer", 0.0))
	var enemy_count := int(_state_number("siege_enemies", 0.0))
	var font_size := maxi(10, roundi(11.0 * s))
	var left := strip.position + Vector2(10.0 * s, 8.0 * s)

	_draw_text(
		font,
		left,
		"飞船耐久",
		font_size,
		COLOR_MUTED,
		74.0 * s
	)
	var bar_rect := Rect2(
		left + Vector2(78.0 * s, 5.0 * s),
		Vector2(190.0 * s, 6.0 * s)
	)
	draw_rect(bar_rect, COLOR_TRACK)
	draw_rect(
		Rect2(bar_rect.position, Vector2(bar_rect.size.x * hull / hull_max, bar_rect.size.y)),
		COLOR_DANGER if hull / hull_max < 0.35 else COLOR_CYAN
	)
	_draw_text(
		font,
		Vector2(bar_rect.end.x + 8.0 * s, left.y),
		"%d" % ceili(hull),
		font_size,
		COLOR_TEXT,
		42.0 * s
	)
	_draw_text(
		font,
		Vector2(strip.position.x + strip.size.x - 236.0 * s, left.y),
		"起飞倒计时 %02d  ·  敌群 %d" % [ceili(timer), enemy_count],
		font_size,
		COLOR_AMBER,
		226.0 * s,
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _draw_driver_bars(
	font: Font,
	start_x: float,
	width: float,
	bar: Rect2
) -> void:
	if width <= 0.0:
		return

	var s := _ui_scale
	var font_size := maxi(11, roundi(12.0 * s))
	var label_width := maxf(32.0, roundf(32.0 * s))
	var value_width := roundf(34.0 * s)
	var gap := roundf(6.0 * s)
	var track_width := maxf(24.0, width - label_width - value_width - gap * 2.0)
	var track_height := maxf(4.0, roundf(5.0 * s))
	var first_center := bar.position.y + bar.size.y * 0.35
	var row_gap := bar.size.y * 0.32

	_draw_compact_bar(
		font,
		Vector2(start_x, first_center),
		label_width,
		track_width,
		value_width,
		track_height,
		font_size,
		"生命",
		_state_number("player_health", 100.0),
		_state_number("player_health_max", 100.0),
		COLOR_CYAN
	)
	_draw_compact_bar(
		font,
		Vector2(start_x, first_center + row_gap),
		label_width,
		track_width,
		value_width,
		track_height,
		font_size,
		"体力",
		_state_number("stamina", 100.0),
		_state_number("stamina_max", 100.0),
		COLOR_AMBER
	)


func _draw_compact_bar(
	font: Font,
	origin: Vector2,
	label_width: float,
	track_width: float,
	value_width: float,
	track_height: float,
	font_size: int,
	label: String,
	value: float,
	maximum: float,
	fill_color: Color
) -> void:
	var s := _ui_scale
	var safe_maximum := maxf(1.0, maximum)
	var safe_value := clampf(value, 0.0, safe_maximum)
	var ratio := safe_value / safe_maximum
	var baseline := origin.y + font_size * 0.35
	var track_x := origin.x + label_width
	var track_rect := Rect2(
		Vector2(track_x, origin.y - track_height * 0.5),
		Vector2(track_width, track_height)
	)

	_draw_text(
		font,
		Vector2(origin.x, baseline),
		label,
		font_size,
		COLOR_MUTED,
		label_width - 3.0 * s
	)
	draw_rect(track_rect, COLOR_TRACK)
	if ratio > 0.0:
		draw_rect(
			Rect2(track_rect.position, Vector2(track_rect.size.x * ratio, track_rect.size.y)),
			fill_color
		)
	_draw_text(
		font,
		Vector2(track_rect.end.x + 6.0 * s, baseline),
		"%d" % roundi(safe_value),
		font_size,
		COLOR_TEXT,
		value_width,
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _draw_network_tag(
	font: Font,
	start_x: float,
	width: float,
	bar: Rect2
) -> void:
	if width <= 0.0:
		return

	var s := _ui_scale
	var tag := Rect2(
		Vector2(start_x, bar.position.y + 9.0 * s),
		Vector2(width, bar.size.y - 18.0 * s)
	)
	var status := _state_text("network_status", "offline")
	var status_data := _network_status_data(status)
	var status_color: Color = status_data["color"]
	var status_label: String = status_data["label"]
	var peers := maxi(0, int(_state_number("network_peers", 0.0)))
	var text := "%s · %d 连接" % [status_label, peers]
	var font_size := maxi(11, roundi(11.0 * s))

	draw_rect(tag, COLOR_TRACK)
	draw_rect(tag, _with_alpha(status_color, 0.52), false, maxf(1.0, s))
	_draw_text(
		font,
		Vector2(tag.position.x + 7.0 * s, tag.get_center().y + font_size * 0.35),
		_truncate_text(font, text, tag.size.x - 14.0 * s, font_size),
		font_size,
		status_color,
		tag.size.x - 14.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_input_hints(font: Font) -> void:
	var visible_count := mini(INPUT_HINTS.size(), 4)
	if visible_count <= 0:
		return

	var s := _ui_scale
	var margin := roundf(18.0 * s)
	var font_size := maxi(12, roundi(13.0 * s))
	var line_height := maxf(18.0, roundf(20.0 * s))
	var panel_width := maxf(120.0, roundf(160.0 * s))
	var panel_height := line_height * visible_count + roundf(16.0 * s)
	var panel := Rect2(
		Vector2(margin, size.y - margin - panel_height),
		Vector2(panel_width, panel_height)
	)

	draw_rect(panel, COLOR_BAR_BACKGROUND_SOFT)
	draw_rect(
		Rect2(panel.position, Vector2(maxf(2.0, 2.0 * s), panel.size.y)),
		_with_alpha(COLOR_CYAN_DIM, 0.72)
	)

	var text_y := panel.position.y + roundf(8.0 * s) + font_size
	for index in range(visible_count):
		_draw_text(
			font,
			Vector2(panel.position.x + 11.0 * s, text_y),
			INPUT_HINTS[index],
			font_size,
			COLOR_TEXT if index == 0 else _with_alpha(COLOR_TEXT, 0.86),
			panel.size.x - 18.0 * s
		)
		text_y += line_height


func _draw_nearby_action(font: Font) -> void:
	var action := _state_text("nearby_action", "").strip_edges()
	if action.is_empty():
		return

	var s := _ui_scale
	var margin := roundf(18.0 * s)
	var font_size := maxi(12, roundi(13.0 * s))
	var height := maxf(28.0, roundf(32.0 * s))
	var maximum_width := minf(size.x * 0.56, 520.0 * s)
	var text_width := font.get_string_size(
		action,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	).x
	var width := clampf(
		text_width + roundf(28.0 * s),
		maxf(120.0, 180.0 * s),
		maximum_width
	)
	var strip := Rect2(
		Vector2((size.x - width) * 0.5, size.y - margin - height),
		Vector2(width, height)
	)

	draw_rect(strip, COLOR_BAR_BACKGROUND)
	draw_rect(strip, _with_alpha(COLOR_AMBER, 0.44), false, maxf(1.0, s))
	_draw_text(
		font,
		Vector2(strip.position.x + 14.0 * s, strip.get_center().y + font_size * 0.36),
		_truncate_text(font, action, strip.size.x - 28.0 * s, font_size),
		font_size,
		COLOR_TEXT,
		strip.size.x - 28.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_notice(font: Font) -> void:
	if _notice_text.is_empty() or _notice_alpha <= 0.0:
		return

	var s := _ui_scale
	var top_bar := _top_bar_rect()
	var font_size := maxi(13, roundi(14.0 * s))
	var margin := roundf(18.0 * s)
	var width := minf(size.x - margin * 2.0, 460.0 * s)
	var height := maxf(30.0, roundf(34.0 * s))
	var notice_rect := Rect2(
		Vector2((size.x - width) * 0.5, top_bar.end.y + roundf(10.0 * s)),
		Vector2(width, height)
	)
	var alpha := _notice_alpha

	draw_rect(notice_rect, _with_alpha(COLOR_BAR_BACKGROUND, 0.88 * alpha))
	draw_rect(
		notice_rect,
		_with_alpha(_notice_color, 0.62 * alpha),
		false,
		maxf(1.0, s)
	)
	_draw_text(
		font,
		Vector2(
			notice_rect.position.x + 12.0 * s,
			notice_rect.get_center().y + font_size * 0.36
		),
		_truncate_text(
			font,
			_notice_text,
			notice_rect.size.x - 24.0 * s,
			font_size
		),
		font_size,
		_with_alpha(_notice_color, alpha),
		notice_rect.size.x - 24.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_phase_card(font: Font) -> void:
	var phase := _state_text("phase", "").strip_edges().to_lower()
	if phase.is_empty():
		return

	var title := ""
	var subtitle := ""
	var accent := COLOR_CYAN
	if phase in ["victory", "success", "won", "complete", "completed", "胜利", "完成"]:
		title = "远征完成"
		subtitle = "按 R 重新启航"
		accent = COLOR_CYAN
	elif phase in ["defeat", "failed", "failure", "lost", "失守", "失败"]:
		title = "营地失守"
		subtitle = "按 R 重新启航"
		accent = COLOR_DANGER
	elif phase in [
		"takeoff",
		"launch",
		"launching",
		"departure",
		"ascending",
		"起飞",
		"升空",
		"跃迁",
	]:
		title = "正在起飞"
		subtitle = "请稍候"
		accent = COLOR_AMBER
	elif phase == "result":
		title = "远征结束"
		subtitle = "准备返航"
		accent = COLOR_CYAN
	else:
		return

	var s := _ui_scale
	var title_size := maxi(16, roundi(18.0 * s))
	var subtitle_size := maxi(11, roundi(12.0 * s))
	var card_width := minf(size.x * 0.44, 320.0 * s)
	var card_height := maxf(62.0, roundf(68.0 * s))
	var card := Rect2(
		Vector2(
			(size.x - card_width) * 0.5,
			(size.y - card_height) * 0.5
		),
		Vector2(card_width, card_height)
	)

	draw_rect(card, _with_alpha(COLOR_BAR_BACKGROUND, 0.94))
	draw_rect(card, _with_alpha(accent, 0.68), false, maxf(1.0, s))
	_draw_text(
		font,
		Vector2(card.position.x + 12.0 * s, card.position.y + roundf(31.0 * s)),
		title,
		title_size,
		accent,
		card.size.x - 24.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_draw_text(
		font,
		Vector2(card.position.x + 12.0 * s, card.position.y + roundf(51.0 * s)),
		subtitle,
		subtitle_size,
		COLOR_MUTED,
		card.size.x - 24.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _top_bar_rect() -> Rect2:
	var s := _ui_scale
	var margin := roundf(18.0 * s)
	return Rect2(
		Vector2(margin, roundf(12.0 * s)),
		Vector2(size.x - margin * 2.0, maxf(46.0, roundf(52.0 * s)))
	)


func _network_status_data(status_text: String) -> Dictionary:
	var normalized := status_text.strip_edges().to_lower()
	if normalized in ["offline", "disconnected", "solo", "single", "离线", "单机"]:
		return {"label": "离线", "color": COLOR_MUTED}
	if normalized in ["host", "server", "listen", "主机"]:
		return {"label": "主机", "color": COLOR_CYAN}
	if normalized in ["client", "connected", "客户端"]:
		return {"label": "客户端", "color": COLOR_CYAN_DIM}
	if normalized.is_empty():
		return {"label": "离线", "color": COLOR_MUTED}
	return {"label": status_text.strip_edges(), "color": COLOR_MUTED}


func _state_text(key: String, fallback: String) -> String:
	var value: Variant = _state.get(key, fallback)
	if value == null:
		return fallback
	return str(value)


func _state_number(key: String, fallback: float) -> float:
	var value: Variant = _state.get(key, fallback)
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).to_float()
		_:
			return fallback


func _as_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String and Color.html_is_valid(value):
		return Color(value)
	return fallback


func _truncate_text(
	font: Font,
	text: String,
	max_width: float,
	font_size: int
) -> String:
	if max_width <= 0.0 or text.is_empty():
		return text
	if font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	).x <= max_width:
		return text

	var ellipsis := "…"
	var low := 0
	var high := text.length()
	while low < high:
		var middle := ceili((float(low) + float(high)) * 0.5)
		var candidate := text.left(middle) + ellipsis
		var candidate_width := font.get_string_size(
			candidate,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		).x
		if candidate_width <= max_width:
			low = middle
		else:
			high = middle - 1

	if low <= 0:
		return ellipsis
	return text.left(low) + ellipsis


func _draw_text(
	font: Font,
	position: Vector2,
	text: String,
	font_size: int,
	color: Color,
	width: float = -1.0,
	alignment: int = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	draw_string(font, position, text, alignment, width, font_size, color)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(alpha, 0.0, 1.0))
