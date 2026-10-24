extends SceneTree

## 验证生成的三段背景音乐都能被 Godot 导入，并具有可用于循环的长度。

const TRACKS := {
	"main": "res://assets/audio/generated/astral_signal_a_main.wav",
	"discovery": "res://assets/audio/generated/astral_signal_b_discovery.wav",
	"anomaly": "res://assets/audio/generated/astral_signal_c_anomaly.wav",
}


func _init() -> void:
	for track_name: String in TRACKS:
		var stream := load(TRACKS[track_name]) as AudioStreamWAV
		if stream == null:
			push_error("背景音乐导入失败：%s" % track_name)
			quit(1)
			return
		if stream.get_length() < 16.5:
			push_error("背景音乐长度异常：%s" % track_name)
			quit(1)
			return

	print("背景音乐资源测试通过：三段 WAV 均可导入且长度一致。")
	quit(0)
