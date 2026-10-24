extends Node2D

## 灰盒环境验证场景：确认移动、绘制和项目启动链路。

const WORLD_SIZE := Vector2(1280.0, 720.0)
const SHIP_POSITION := Vector2(640.0, 360.0)
const INPUT_KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
}

@export var player_speed: float = 240.0

var player_position := Vector2(760.0, 360.0)
var has_received_keyboard_input := false


func _ready() -> void:
	_ensure_input_actions()
	queue_redraw()


func _process(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.is_zero_approx():
		return

	player_position += direction.normalized() * player_speed * delta
	player_position = player_position.clamp(Vector2(24.0, 24.0), WORLD_SIZE - Vector2(24.0, 24.0))
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		has_received_keyboard_input = true
		queue_redraw()

	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _ensure_input_actions() -> void:
	for action_name: String in INPUT_KEYS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

		for keycode: Key in INPUT_KEYS[action_name]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keycode
			if not InputMap.action_has_event(action_name, key_event):
				InputMap.action_add_event(action_name, key_event)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("#08111f"))

	for x in range(0, int(WORLD_SIZE.x) + 1, 64):
		draw_line(Vector2(x, 0), Vector2(x, WORLD_SIZE.y), Color("#15243a"), 1.0)
	for y in range(0, int(WORLD_SIZE.y) + 1, 64):
		draw_line(Vector2(0, y), Vector2(WORLD_SIZE.x, y), Color("#15243a"), 1.0)

	# 飞船安全区与炮台占位。
	draw_circle(SHIP_POSITION, 112.0, Color(0.12, 0.32, 0.48, 0.18))
	draw_arc(SHIP_POSITION, 112.0, 0.0, TAU, 96, Color("#2d6f91"), 2.0)
	draw_circle(SHIP_POSITION, 58.0, Color("#d9e8ef"))
	draw_circle(SHIP_POSITION, 42.0, Color("#4587aa"))

	for index in range(4):
		var angle := TAU * float(index) / 4.0
		var mount_position := SHIP_POSITION + Vector2.from_angle(angle) * 86.0
		draw_circle(mount_position, 12.0, Color("#f2be5c"))
		draw_circle(mount_position, 6.0, Color("#3a2b16"))

	# 当前玩家。
	draw_circle(player_position, 15.0, Color("#74e0c5"))
	draw_circle(player_position, 7.0, Color("#e6fff8"))

	var font := ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(32.0, 48.0),
		"ASTRO ADVENTURE / 环境验证场景",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		24,
		Color("#e6fff8")
	)
	draw_string(
		font,
		Vector2(32.0, 82.0),
		"WASD / 方向键移动 · Esc 退出 · 黄色圆点为炮台占位",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		Color("#8eabc0")
	)
	draw_string(
		font,
		Vector2(32.0, 108.0),
		"键盘输入：已收到" if has_received_keyboard_input else "键盘输入：等待按键，请先点击游戏窗口",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		Color("#74e0c5") if has_received_keyboard_input else Color("#f2be5c")
	)
