class_name GameHUD
extends Control

## 战斗 HUD：全部内容均由原生绘制 API 生成，不依赖额外字体、图片或场景。

const DESIGN_SIZE := Vector2(1280.0, 720.0)

const COLOR_PANEL := Color(0.025, 0.055, 0.095, 0.88)
const COLOR_PANEL_DARK := Color(0.012, 0.028, 0.052, 0.94)
const COLOR_BORDER := Color(0.21, 0.43, 0.56, 0.55)
const COLOR_CYAN := Color("#68e6d0")
const COLOR_CYAN_DIM := Color("#3e9ba5")
const COLOR_AMBER := Color("#f2b85f")
const COLOR_TEXT := Color("#edfaff")
const COLOR_MUTED := Color("#92afc2")
const COLOR_DANGER := Color("#ff7869")
const COLOR_TRANSPARENT := Color.TRANSPARENT

const WAVE_STATE_LABELS := {
	"idle": "待命",
	"ready": "准备阶段",
	"prepare": "准备阶段",
	"preparing": "准备阶段",
	"countdown": "倒计时",
	"active": "交战中",
	"combat": "交战中",
	"fighting": "交战中",
	"in_progress": "交战中",
	"intermission": "波次间休整",
	"break": "波次间休整",
	"rest": "波次间休整",
	"complete": "波次完成",
	"completed": "波次完成",
	"victory": "防守成功",
	"defeat": "防线失守",
	"failed": "防线失守",
}

var _state: Dictionary = {
	"ship_hull": 100.0,
	"ship_hull_max": 100.0,
	"resources": 0,
	"wave": 0,
	"total_waves": 0,
	"wave_state": "",
	"timer": -1.0,
	"player_alive": true,
	"nearby_action": "",
	"build_prompt": "",
	"enemy_count": 0,
	"turret_count": 0,
	"score": 0,
	"elapsed": 0.0,
	"phase": "",
}

var _notice_text := ""
var _notice_color := Color.WHITE
var _notice_duration := 0.0
var _notice_remaining := 0.0
var _notice_alpha := 0.0

var _ui_scale := 1.0
var _has_wave_snapshot := false
var _last_wave := 0
var _last_wave_state := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 100

	get_viewport().size_changed.connect(_sync_to_viewport)
	resized.connect(_on_hud_resized)
	_sync_to_viewport()


func _process(delta: float) -> void:
	if _notice_remaining <= 0.0:
		return

	_notice_remaining = maxf(0.0, _notice_remaining - delta)
	var fade_duration := minf(0.42, maxf(0.08, _notice_duration * 0.3))
	_notice_alpha = clampf(_notice_remaining / fade_duration, 0.0, 1.0)

	if _notice_remaining <= 0.0:
		_notice_alpha = 0.0
		_notice_text = ""

	queue_redraw()


## 增量更新 HUD 状态；未传入的字段会保留当前值。
func update_state(state: Dictionary) -> void:
	for key: Variant in state:
		_state[key] = state[key]

	_detect_wave_transition()
	queue_redraw()


## 在画面上方显示一条会自动淡出的通知。
func show_notice(text: String, color: Color = Color.WHITE, duration: float = 2.0) -> void:
	if text.strip_edges().is_empty() or duration <= 0.0:
		return

	_notice_text = text
	_notice_color = color
	_notice_duration = duration
	_notice_remaining = duration
	_notice_alpha = 1.0
	queue_redraw()


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
		0.65,
		2.0
	)


func _detect_wave_transition() -> void:
	var current_wave := int(_state_number("wave", 0.0))
	var current_wave_state := _state_text("wave_state", "").strip_edges()

	if not _has_wave_snapshot:
		_has_wave_snapshot = true
		_last_wave = current_wave
		_last_wave_state = current_wave_state
		return

	if current_wave != _last_wave and current_wave > 0:
		var state_label := _localize_wave_state(current_wave_state)
		show_notice("第 %d 波 · %s" % [current_wave, state_label], COLOR_CYAN, 2.4)
	elif (
		not current_wave_state.is_empty()
		and current_wave_state != _last_wave_state
		and current_wave > 0
	):
		var state_label := _localize_wave_state(current_wave_state)
		show_notice("第 %d 波 · %s" % [current_wave, state_label], COLOR_AMBER, 1.8)

	_last_wave = current_wave
	_last_wave_state = current_wave_state


func _draw() -> void:
	if size.is_zero_approx():
		return

	_update_ui_scale()
	var font := ThemeDB.fallback_font
	_draw_screen_shading()
	_draw_top_panels(font)
	_draw_control_panel(font)
	_draw_status_panel(font)
	_draw_timer_banner(font)

	if not _state_bool("player_alive", true):
		_draw_destroyed_overlay(font)

	_draw_notice(font)
	_draw_result_overlay(font)


func _draw_screen_shading() -> void:
	var s := _ui_scale
	for index in range(6):
		var band_height := 22.0 * s
		var alpha := 0.055 * float(6 - index) / 6.0
		draw_rect(
			Rect2(0.0, band_height * float(index), size.x, band_height + 1.0),
			Color(0.005, 0.025, 0.055, alpha)
		)

	var bottom_band_height := 17.0 * s
	for index in range(5):
		var alpha := 0.045 * float(5 - index) / 5.0
		var band_y := size.y - bottom_band_height * float(5 - index)
		draw_rect(
			Rect2(0.0, band_y, size.x, bottom_band_height + 1.0),
			Color(0.005, 0.02, 0.045, alpha)
		)


func _draw_top_panels(font: Font) -> void:
	var s := _ui_scale
	var pad := 28.0 * s
	var panel_y := 18.0 * s
	var panel_height := 94.0 * s
	var left_width := minf(390.0 * s, size.x * 0.29)
	var center_width := minf(276.0 * s, size.x * 0.225)
	var right_width := minf(360.0 * s, size.x * 0.27)

	var hull_rect := Rect2(pad, panel_y, left_width, panel_height)
	var wave_rect := Rect2(
		(size.x - center_width) * 0.5,
		panel_y,
		center_width,
		panel_height
	)
	var resource_rect := Rect2(
		size.x - pad - right_width,
		panel_y,
		right_width,
		panel_height
	)

	_draw_panel(hull_rect, COLOR_CYAN)
	_draw_panel(wave_rect, COLOR_AMBER)
	_draw_panel(resource_rect, COLOR_CYAN)

	_draw_hull_panel(font, hull_rect)
	_draw_wave_panel(font, wave_rect)
	_draw_resource_panel(font, resource_rect)


func _draw_hull_panel(font: Font, rect: Rect2) -> void:
	var s := _ui_scale
	var inner_x := rect.position.x + 18.0 * s
	var inner_width := rect.size.x - 36.0 * s
	var hull_max := maxf(1.0, _state_number("ship_hull_max", 100.0))
	var hull := clampf(_state_number("ship_hull", hull_max), 0.0, hull_max)
	var hull_ratio := hull / hull_max
	var hull_color := COLOR_CYAN
	if hull_ratio <= 0.25:
		hull_color = COLOR_DANGER
	elif hull_ratio <= 0.5:
		hull_color = COLOR_AMBER

	draw_circle(Vector2(inner_x + 4.0 * s, rect.position.y + 19.0 * s), 3.5 * s, hull_color)
	_draw_text(
		font,
		Vector2(inner_x + 14.0 * s, rect.position.y + 10.0 * s),
		"基地耐久",
		roundi(13.0 * s),
		COLOR_MUTED,
		inner_width - 14.0 * s
	)
	_draw_text(
		font,
		Vector2(inner_x, rect.position.y + 7.0 * s),
		"%d / %d" % [int(ceil(hull)), int(ceil(hull_max))],
		roundi(19.0 * s),
		COLOR_TEXT,
		inner_width,
		HORIZONTAL_ALIGNMENT_RIGHT
	)

	var bar_rect := Rect2(
		inner_x,
		rect.position.y + 52.0 * s,
		inner_width,
		12.0 * s
	)
	draw_rect(bar_rect, COLOR_PANEL_DARK)
	draw_rect(
		Rect2(bar_rect.position, Vector2(bar_rect.size.x * hull_ratio, bar_rect.size.y)),
		hull_color
	)
	draw_rect(bar_rect, _with_alpha(COLOR_BORDER, 0.8), false, maxf(1.0, s))

	var status_text := "船体状态稳定"
	if hull_ratio <= 0.25:
		status_text = "警告：船体严重受损"
	elif hull_ratio <= 0.5:
		status_text = "注意：船体受损"
	_draw_text(
		font,
		Vector2(inner_x, rect.position.y + 71.0 * s),
		status_text,
		roundi(11.0 * s),
		hull_color if hull_ratio <= 0.5 else COLOR_MUTED,
		inner_width
	)


func _draw_wave_panel(font: Font, rect: Rect2) -> void:
	var s := _ui_scale
	var inner_width := rect.size.x - 28.0 * s
	var wave := int(_state_number("wave", 0.0))
	var total_waves := int(_state_number("total_waves", 0.0))
	var wave_text := "--"
	if _state.has("wave") and wave > 0:
		wave_text = "%02d / %02d" % [wave, total_waves] if total_waves > 0 else "%02d" % wave

	_draw_text(
		font,
		Vector2(rect.position.x + 14.0 * s, rect.position.y + 10.0 * s),
		"当前波次",
		roundi(12.0 * s),
		COLOR_MUTED,
		inner_width,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_draw_text(
		font,
		Vector2(rect.position.x + 14.0 * s, rect.position.y + 28.0 * s),
		wave_text,
		roundi(25.0 * s),
		COLOR_TEXT,
		inner_width,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_draw_text(
		font,
		Vector2(rect.position.x + 14.0 * s, rect.position.y + 66.0 * s),
		_localize_wave_state(_state_text("wave_state", "")),
		roundi(12.0 * s),
		COLOR_AMBER,
		inner_width,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_resource_panel(font: Font, rect: Rect2) -> void:
	var s := _ui_scale
	var inner_x := rect.position.x + 18.0 * s
	var inner_width := rect.size.x - 36.0 * s

	_draw_text(
		font,
		Vector2(inner_x, rect.position.y + 10.0 * s),
		"可用资源",
		roundi(12.0 * s),
		COLOR_MUTED,
		inner_width
	)
	_draw_text(
		font,
		Vector2(inner_x, rect.position.y + 28.0 * s),
		_format_resources(),
		roundi(20.0 * s),
		COLOR_AMBER,
		inner_width
	)

	var score := int(_state_number("score", 0.0))
	var elapsed := maxf(0.0, _state_number("elapsed", 0.0))
	var detail := "得分 %s   ·   用时 %s" % [_format_integer(score), _format_clock(elapsed)]
	_draw_text(
		font,
		Vector2(inner_x, rect.position.y + 66.0 * s),
		detail,
		roundi(11.0 * s),
		COLOR_MUTED,
		inner_width
	)


func _draw_control_panel(font: Font) -> void:
	var s := _ui_scale
	var pad := 28.0 * s
	var panel_width := minf(430.0 * s, size.x * 0.37)
	var nearby_action := _state_text("nearby_action", "").strip_edges()
	var build_prompt := _state_text("build_prompt", "").strip_edges()
	var has_extra_line := not nearby_action.is_empty() and not build_prompt.is_empty()
	var panel_height := (112.0 if has_extra_line else 92.0) * s
	var rect := Rect2(
		pad,
		size.y - pad - panel_height,
		panel_width,
		panel_height
	)
	_draw_panel(rect, COLOR_CYAN)

	var inner_x := rect.position.x + 15.0 * s
	var inner_width := rect.size.x - 30.0 * s
	_draw_text(
		font,
		Vector2(inner_x, rect.position.y + 9.0 * s),
		"操控",
		roundi(12.0 * s),
		COLOR_CYAN,
		inner_width
	)
	_draw_text(
		font,
		Vector2(inner_x, rect.position.y + 31.0 * s),
		"WASD / 方向键   移动",
		roundi(15.0 * s),
		COLOR_TEXT,
		inner_width
	)

	var interaction_text := nearby_action
	if interaction_text.is_empty():
		interaction_text = build_prompt
	if interaction_text.is_empty():
		interaction_text = "靠近设施可进行交互"
	_draw_text(
		font,
		Vector2(inner_x, rect.position.y + 57.0 * s),
		interaction_text,
		roundi(13.0 * s),
		COLOR_AMBER if not nearby_action.is_empty() or not build_prompt.is_empty() else COLOR_MUTED,
		inner_width
	)

	if has_extra_line:
		_draw_text(
			font,
			Vector2(inner_x, rect.position.y + 82.0 * s),
			build_prompt,
			roundi(12.0 * s),
			COLOR_AMBER,
			inner_width
		)


func _draw_status_panel(font: Font) -> void:
	var s := _ui_scale
	var pad := 28.0 * s
	var panel_width := minf(460.0 * s, size.x * 0.40)
	var panel_height := 92.0 * s
	var rect := Rect2(
		size.x - pad - panel_width,
		size.y - pad - panel_height,
		panel_width,
		panel_height
	)
	_draw_panel(rect, COLOR_AMBER)

	var column_width := rect.size.x / 3.0
	var labels := ["敌军", "炮台", "得分"]
	var values := [
		_format_integer(int(_state_number("enemy_count", 0.0))),
		_format_integer(int(_state_number("turret_count", 0.0))),
		_format_integer(int(_state_number("score", 0.0))),
	]

	for index in range(3):
		var column_x := rect.position.x + column_width * float(index)
		if index > 0:
			draw_line(
				Vector2(column_x, rect.position.y + 18.0 * s),
				Vector2(column_x, rect.end.y - 18.0 * s),
				_with_alpha(COLOR_BORDER, 0.55),
				maxf(1.0, s)
			)

		_draw_text(
			font,
			Vector2(column_x, rect.position.y + 16.0 * s),
			labels[index],
			roundi(11.0 * s),
			COLOR_MUTED,
			column_width,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_draw_text(
			font,
			Vector2(column_x, rect.position.y + 35.0 * s),
			values[index],
			roundi(21.0 * s),
			COLOR_TEXT,
			column_width,
			HORIZONTAL_ALIGNMENT_CENTER
		)

	_draw_text(
		font,
		Vector2(rect.position.x + 12.0 * s, rect.position.y + 70.0 * s),
		"战场态势",
		roundi(10.0 * s),
		COLOR_AMBER,
		rect.size.x - 24.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_timer_banner(font: Font) -> void:
	if not _state.has("timer"):
		return

	var timer := _state_number("timer", -1.0)
	if timer < 0.0 or not _state_bool("player_alive", true):
		return

	var s := _ui_scale
	var banner_width := minf(246.0 * s, size.x * 0.30)
	var banner_height := 38.0 * s
	var rect := Rect2(
		(size.x - banner_width) * 0.5,
		124.0 * s,
		banner_width,
		banner_height
	)
	draw_rect(rect, Color(0.018, 0.052, 0.085, 0.9))
	draw_rect(
		Rect2(rect.position, Vector2(3.0 * s, rect.size.y)),
		COLOR_AMBER
	)
	draw_rect(rect, _with_alpha(COLOR_BORDER, 0.7), false, maxf(1.0, s))
	_draw_text(
		font,
		Vector2(rect.position.x + 12.0 * s, rect.position.y + 10.0 * s),
		"倒计时  %s" % _format_clock(timer),
		roundi(16.0 * s),
		COLOR_TEXT,
		rect.size.x - 24.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_destroyed_overlay(font: Font) -> void:
	var s := _ui_scale
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.012, 0.02, 0.24))

	var panel_width := minf(420.0 * s, size.x - 56.0 * s)
	var panel_height := 116.0 * s
	var rect := Rect2(
		(size.x - panel_width) * 0.5,
		(size.y - panel_height) * 0.5,
		panel_width,
		panel_height
	)
	draw_rect(rect, Color(0.07, 0.018, 0.025, 0.94))
	draw_rect(rect, COLOR_DANGER, false, maxf(2.0, 2.0 * s))
	_draw_text(
		font,
		Vector2(rect.position.x + 20.0 * s, rect.position.y + 24.0 * s),
		"机体损毁",
		roundi(30.0 * s),
		COLOR_DANGER,
		rect.size.x - 40.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_draw_text(
		font,
		Vector2(rect.position.x + 20.0 * s, rect.position.y + 73.0 * s),
		"等待重新部署",
		roundi(15.0 * s),
		COLOR_TEXT,
		rect.size.x - 40.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_notice(font: Font) -> void:
	if _notice_text.is_empty() or _notice_alpha <= 0.0:
		return

	var s := _ui_scale
	var panel_width := minf(570.0 * s, size.x - 56.0 * s)
	var panel_height := 48.0 * s
	var rect := Rect2(
		(size.x - panel_width) * 0.5,
		185.0 * s,
		panel_width,
		panel_height
	)
	draw_rect(rect, _with_alpha(COLOR_PANEL_DARK, _notice_alpha))
	draw_rect(
		Rect2(rect.position, Vector2(3.0 * s, rect.size.y)),
		_with_alpha(_notice_color, _notice_alpha)
	)
	draw_rect(
		rect,
		_with_alpha(COLOR_BORDER, _notice_alpha),
		false,
		maxf(1.0, s)
	)
	draw_circle(
		Vector2(rect.position.x + 18.0 * s, rect.get_center().y),
		4.0 * s,
		_with_alpha(_notice_color, _notice_alpha)
	)
	_draw_text(
		font,
		Vector2(rect.position.x + 32.0 * s, rect.position.y + 14.0 * s),
		_notice_text,
		roundi(17.0 * s),
		_with_alpha(COLOR_TEXT, _notice_alpha),
		rect.size.x - 52.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_result_overlay(font: Font) -> void:
	var phase := _state_text("phase", "").strip_edges().to_lower()
	if phase not in ["victory", "defeat"]:
		return

	var is_victory := phase == "victory"
	var s := _ui_scale
	var accent_color := COLOR_CYAN if is_victory else COLOR_DANGER
	var title := "航道已肃清" if is_victory else "回声号失联"
	var subtitle := "回声号仍在航行，所有来袭目标均已清除" if is_victory else "船体耐久耗尽，本次航行在此终止"

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.004, 0.012, 0.025, 0.58))
	var panel_width := minf(560.0 * s, size.x - 56.0 * s)
	var panel_height := 278.0 * s
	var rect := Rect2(
		(size.x - panel_width) * 0.5,
		(size.y - panel_height) * 0.5,
		panel_width,
		panel_height
	)
	draw_rect(rect, Color(0.025, 0.055, 0.09, 0.97))
	draw_rect(Rect2(rect.position, Vector2(4.0 * s, rect.size.y)), accent_color)
	draw_rect(rect, accent_color, false, maxf(2.0, 2.0 * s))

	_draw_text(
		font,
		Vector2(rect.position.x + 24.0 * s, rect.position.y + 28.0 * s),
		title,
		roundi(32.0 * s),
		accent_color,
		rect.size.x - 48.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_draw_text(
		font,
		Vector2(rect.position.x + 24.0 * s, rect.position.y + 77.0 * s),
		subtitle,
		roundi(13.0 * s),
		COLOR_MUTED,
		rect.size.x - 48.0 * s,
		HORIZONTAL_ALIGNMENT_CENTER
	)

	var stats_y := rect.position.y + 114.0 * s
	var column_width := (rect.size.x - 48.0 * s) / 3.0
	var labels := ["最终得分", "航行用时", "抵达波次"]
	var values := [
		_format_integer(int(_state_number("score", 0.0))),
		_format_clock(maxf(0.0, _state_number("elapsed", 0.0))),
		"%02d / %02d" % [
			int(_state_number("wave", 0.0)),
			int(_state_number("total_waves", 0.0)),
		],
	]

	for index in range(3):
		var column_x := rect.position.x + 24.0 * s + column_width * float(index)
		_draw_text(
			font,
			Vector2(column_x, stats_y),
			labels[index],
			roundi(11.0 * s),
			COLOR_MUTED,
			column_width,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_draw_text(
			font,
			Vector2(column_x, stats_y + 22.0 * s),
			values[index],
			roundi(21.0 * s),
			COLOR_TEXT,
			column_width,
			HORIZONTAL_ALIGNMENT_CENTER
		)

	var prompt_rect := Rect2(
		rect.position.x + 24.0 * s,
		rect.end.y - 60.0 * s,
		rect.size.x - 48.0 * s,
		36.0 * s
	)
	draw_rect(prompt_rect, Color(accent_color, 0.08))
	draw_rect(prompt_rect, Color(accent_color, 0.55), false, maxf(1.0, s))
	_draw_text(
		font,
		Vector2(prompt_rect.position.x, prompt_rect.position.y + 8.0 * s),
		"按 R 重新启航",
		roundi(15.0 * s),
		accent_color,
		prompt_rect.size.x,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_panel(rect: Rect2, accent_color: Color) -> void:
	var s := _ui_scale
	draw_rect(rect, COLOR_PANEL)
	draw_rect(
		Rect2(rect.position, Vector2(3.0 * s, rect.size.y)),
		accent_color
	)
	draw_rect(
		Rect2(
			Vector2(rect.position.x, rect.position.y),
			Vector2(rect.size.x, maxf(1.0, s))
		),
		_with_alpha(COLOR_BORDER, 0.65)
	)
	draw_rect(rect, _with_alpha(COLOR_BORDER, 0.42), false, maxf(1.0, s))


func _draw_text(
	font: Font,
	position: Vector2,
	text: String,
	font_size: int,
	color: Color,
	max_width: float = -1.0,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	if text.is_empty() or color.a <= 0.0:
		return

	var fitted_text := _fit_text(font, text, font_size, max_width)
	var baseline := position + Vector2(0.0, font_size * 0.82)
	if color.a > 0.45:
		draw_string(
			font,
			baseline + Vector2(1.0, 1.0) * _ui_scale,
			fitted_text,
			alignment,
			max_width,
			font_size,
			_with_alpha(Color(0.0, 0.0, 0.0, 0.65), color.a)
		)
	draw_string(font, baseline, fitted_text, alignment, max_width, font_size, color)


func _fit_text(font: Font, text: String, font_size: int, max_width: float) -> String:
	if max_width <= 0.0:
		return text

	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= max_width:
		return text

	var ellipsis := "…"
	var fitted := text
	while not fitted.is_empty():
		fitted = fitted.left(fitted.length() - 1)
		var candidate := fitted + ellipsis
		if font.get_string_size(
			candidate,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		).x <= max_width:
			return candidate
	return ellipsis


func _state_number(key: String, fallback: float) -> float:
	var value: Variant = _state.get(key)
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		TYPE_STRING, TYPE_STRING_NAME:
			var text := str(value).strip_edges()
			if text.is_valid_float():
				return text.to_float()
	return fallback


func _state_bool(key: String, fallback: bool) -> bool:
	var value: Variant = _state.get(key)
	match typeof(value):
		TYPE_BOOL:
			return bool(value)
		TYPE_INT, TYPE_FLOAT:
			return float(value) != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			var text := str(value).strip_edges().to_lower()
			if text in ["true", "1", "yes", "是"]:
				return true
			if text in ["false", "0", "no", "否"]:
				return false
	return fallback


func _state_text(key: String, fallback: String) -> String:
	var value: Variant = _state.get(key)
	if value == null:
		return fallback
	return str(value)


func _format_resources() -> String:
	var value: Variant = _state.get("resources", 0)
	if typeof(value) == TYPE_DICTIONARY:
		var entries := ""
		var count := 0
		for key: Variant in value:
			if count >= 2:
				break
			if not entries.is_empty():
				entries += " · "
			entries += "%s %s" % [str(key), _format_scalar(value[key])]
			count += 1
		return entries if not entries.is_empty() else "0"

	return _format_scalar(value)


func _format_scalar(value: Variant) -> String:
	match typeof(value):
		TYPE_INT:
			return _format_integer(int(value))
		TYPE_FLOAT:
			return _format_integer(int(roundf(float(value))))
		TYPE_BOOL:
			return "是" if bool(value) else "否"
		TYPE_NIL:
			return "0"
	return str(value)


func _format_integer(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	grouped = digits + grouped
	return ("-" if value < 0 else "") + grouped


func _format_clock(seconds: float) -> String:
	var total_seconds := maxi(0, int(ceil(seconds)))
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	var secs := total_seconds % 60
	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, secs]
	return "%02d:%02d" % [minutes, secs]


func _localize_wave_state(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized.is_empty():
		return "待命"
	return WAVE_STATE_LABELS.get(normalized, value.strip_edges())


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(alpha, 0.0, 1.0))
