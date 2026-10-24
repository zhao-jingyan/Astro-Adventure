class_name GameAudio
extends Node

## 程序化深空电子音效。
##
## 所有波形均在 _ready() 中生成一次，不依赖外部音频文件。
## 播放方法可安全地在 headless 环境中调用。

const SAMPLE_RATE := 22050
const PLAYER_POOL_SIZE := 12
const MAX_VOICES_PER_FRAME := 3
const DEFAULT_MASTER_LINEAR := 0.78

const EFFECT_VOLUME_DB := {
	&"shoot": -9.5,
	&"turret_shot": -10.5,
	&"enemy_shot": -11.5,
	&"hit": -11.0,
	&"explosion": -8.5,
	&"build": -10.0,
	&"upgrade": -9.5,
	&"wave": -10.0,
	&"victory": -9.0,
	&"defeat": -9.0,
}

const EFFECT_COOLDOWN_MS := {
	&"shoot": 38,
	&"turret_shot": 48,
	&"enemy_shot": 55,
	&"hit": 34,
	&"explosion": 75,
	&"build": 90,
	&"upgrade": 120,
	&"wave": 250,
	&"victory": 500,
	&"defeat": 500,
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player_index := 0
var _last_play_frame := -1
var _voices_this_frame := 0
var _last_played_ms: Dictionary = {}
var _master_linear := DEFAULT_MASTER_LINEAR
var _initialized := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if _initialized:
		return

	# 无窗口测试不需要占用音频驱动；图形运行时再生成完整音色库。
	if DisplayServer.get_name() == "headless":
		return

	# 固定随机种子，让噪声音色在每次启动时保持一致。
	_rng.seed = 0x5A17C0DE
	_build_sound_library()
	_create_player_pool()
	_initialized = true


func _exit_tree() -> void:
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.stream = null
	_players.clear()
	_streams.clear()
	_initialized = false


## 玩家射击：高频快速下滑，短促而干脆。
func play_shoot() -> void:
	_play(&"shoot")


## 炮台射击：更低、更厚的能量脉冲，便于与玩家射击区分。
func play_turret_shot() -> void:
	_play(&"turret_shot")


## 敌方射击：带平滑噪声的偏暗能量束。
func play_enemy_shot() -> void:
	_play(&"enemy_shot")


## 命中：短促点击叠加深空脉冲。
func play_hit() -> void:
	_play(&"hit")


## 爆炸：低频衰减与逐渐变暗的噪声尾音。
func play_explosion() -> void:
	_play(&"explosion")


## 建造：三音上扬和弦。
func play_build() -> void:
	_play(&"build")


## 升级：更明亮、更长的上扬琶音和弦。
func play_upgrade() -> void:
	_play(&"upgrade")


## 波次开始：带颤音的上升警报。
func play_wave() -> void:
	_play(&"wave")


## 胜利：明亮的大调短琶音。
func play_victory() -> void:
	_play(&"victory")


## 失败：低沉的下行短琶音。
func play_defeat() -> void:
	_play(&"defeat")


## 设置本模块的整体线性音量；范围为 0.0 到 1.0，不进行额外放大。
func set_master_volume(linear: float) -> void:
	_master_linear = clampf(linear, 0.0, 1.0)
	_refresh_player_volumes()


## 立即停止所有正在播放的音效，供场景切换和自动化测试清理。
func stop_all() -> void:
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.stream = null


func _create_player_pool() -> void:
	_players.clear()

	for index in range(PLAYER_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "Voice%02d" % (index + 1)
		player.bus = &"Master"
		player.set_meta(&"base_volume_db", -10.0)
		player.volume_db = _combined_volume_db(-10.0)
		add_child(player)
		_players.append(player)


func _build_sound_library() -> void:
	_streams.clear()
	_streams[&"shoot"] = _make_wav(_generate_shoot(), 0.70)
	_streams[&"turret_shot"] = _make_wav(_generate_turret_shot(), 0.76)
	_streams[&"enemy_shot"] = _make_wav(_generate_enemy_shot(), 0.66)
	_streams[&"hit"] = _make_wav(_generate_hit(), 0.62)
	_streams[&"explosion"] = _make_wav(_generate_explosion(), 0.82)
	_streams[&"build"] = _make_wav(_generate_build(), 0.68)
	_streams[&"upgrade"] = _make_wav(_generate_upgrade(), 0.72)
	_streams[&"wave"] = _make_wav(_generate_wave(), 0.64)
	_streams[&"victory"] = _make_wav(_generate_victory(), 0.70)
	_streams[&"defeat"] = _make_wav(_generate_defeat(), 0.66)


func _play(sound_id: StringName) -> void:
	if not _initialized or not _streams.has(sound_id):
		return

	var current_frame := Engine.get_process_frames()
	if current_frame != _last_play_frame:
		_last_play_frame = current_frame
		_voices_this_frame = 0

	if _voices_this_frame >= MAX_VOICES_PER_FRAME:
		return

	var now_ms := Time.get_ticks_msec()
	var cooldown_ms := int(EFFECT_COOLDOWN_MS.get(sound_id, 0))
	var last_ms := int(_last_played_ms.get(sound_id, -cooldown_ms - 1))
	if now_ms - last_ms < cooldown_ms:
		return

	var player := _acquire_player()
	if player == null:
		return

	_last_played_ms[sound_id] = now_ms
	_voices_this_frame += 1

	var base_volume_db := float(EFFECT_VOLUME_DB.get(sound_id, -10.0))
	player.set_meta(&"base_volume_db", base_volume_db)
	player.volume_db = _combined_volume_db(base_volume_db)
	player.stream = _streams[sound_id]
	player.play()


func _acquire_player() -> AudioStreamPlayer:
	if _players.is_empty():
		return null

	# 优先使用空闲播放器；池满时按顺序复用最早轮到的播放器。
	for player in _players:
		if not player.playing:
			return player

	var reused_player := _players[_next_player_index]
	_next_player_index = (_next_player_index + 1) % _players.size()
	reused_player.stop()
	return reused_player


func _refresh_player_volumes() -> void:
	for player in _players:
		var base_volume_db := float(player.get_meta(&"base_volume_db", -10.0))
		player.volume_db = _combined_volume_db(base_volume_db)


func _combined_volume_db(base_volume_db: float) -> float:
	if _master_linear <= 0.0001:
		return -80.0
	return base_volume_db + linear_to_db(_master_linear)


func _generate_shoot() -> PackedFloat32Array:
	const DURATION := 0.085
	var samples := _new_sample_buffer(DURATION)

	for index in range(samples.size()):
		var time := float(index) / float(SAMPLE_RATE)
		var progress := clampf(time / DURATION, 0.0, 1.0)
		var envelope := _edge_envelope(time, DURATION, 0.003, 0.032)
		var crackle := _rng.randf_range(-1.0, 1.0) * pow(1.0 - progress, 5.0)
		samples[index] = envelope * (
			_chirp(time, 1380.0, 690.0, DURATION) * 0.72
			+ _chirp(time, 2760.0, 1380.0, DURATION) * 0.13
			+ crackle * 0.08
		)

	return _seal_buffer(samples)


func _generate_turret_shot() -> PackedFloat32Array:
	const DURATION := 0.16
	var samples := _new_sample_buffer(DURATION)

	for index in range(samples.size()):
		var time := float(index) / float(SAMPLE_RATE)
		var progress := clampf(time / DURATION, 0.0, 1.0)
		var envelope := _edge_envelope(time, DURATION, 0.004, 0.075)
		var weight := pow(1.0 - progress, 1.5)
		samples[index] = envelope * (
			_chirp(time, 305.0, 142.0, DURATION) * 0.68
			+ _chirp(time, 915.0, 426.0, DURATION) * 0.10
			+ _chirp(time, 82.0, 52.0, DURATION) * weight * 0.24
		)

	return _seal_buffer(samples)


func _generate_enemy_shot() -> PackedFloat32Array:
	const DURATION := 0.17
	var samples := _new_sample_buffer(DURATION)
	var filtered_noise := 0.0

	for index in range(samples.size()):
		var time := float(index) / float(SAMPLE_RATE)
		var progress := clampf(time / DURATION, 0.0, 1.0)
		var envelope := _edge_envelope(time, DURATION, 0.005, 0.085)
		var white_noise := _rng.randf_range(-1.0, 1.0)
		filtered_noise = lerpf(filtered_noise, white_noise, 0.30)
		var noise_envelope := pow(1.0 - progress, 2.5)
		samples[index] = envelope * (
			_chirp(time, 480.0, 185.0, DURATION) * 0.52
			+ _chirp(time, 125.0, 78.0, DURATION) * 0.24
			+ filtered_noise * noise_envelope * 0.22
		)

	return _seal_buffer(samples)


func _generate_hit() -> PackedFloat32Array:
	const DURATION := 0.11
	var samples := _new_sample_buffer(DURATION)
	var filtered_noise := 0.0

	for index in range(samples.size()):
		var time := float(index) / float(SAMPLE_RATE)
		var progress := clampf(time / DURATION, 0.0, 1.0)
		var envelope := _edge_envelope(time, DURATION, 0.0015, 0.070)
		var white_noise := _rng.randf_range(-1.0, 1.0)
		filtered_noise = lerpf(filtered_noise, white_noise, 0.55)
		samples[index] = envelope * (
			_chirp(time, 740.0, 250.0, DURATION) * 0.46
			+ _chirp(time, 190.0, 110.0, DURATION) * 0.42
			+ filtered_noise * pow(1.0 - progress, 4.0) * 0.11
		)

	return _seal_buffer(samples)


func _generate_explosion() -> PackedFloat32Array:
	const DURATION := 0.52
	var samples := _new_sample_buffer(DURATION)
	var rumble_noise := 0.0
	var air_noise := 0.0

	for index in range(samples.size()):
		var time := float(index) / float(SAMPLE_RATE)
		var progress := clampf(time / DURATION, 0.0, 1.0)
		var envelope := _edge_envelope(time, DURATION, 0.004, 0.34)
		var white_noise := _rng.randf_range(-1.0, 1.0)
		rumble_noise = lerpf(rumble_noise, white_noise, 0.055)
		air_noise = lerpf(air_noise, white_noise, 0.18)
		var low_decay := pow(1.0 - progress, 2.4)
		var noise_decay := pow(1.0 - progress, 3.8)
		samples[index] = envelope * (
			_chirp(time, 108.0, 34.0, DURATION) * low_decay * 0.64
			+ _chirp(time, 216.0, 68.0, DURATION) * low_decay * 0.18
			+ rumble_noise * noise_decay * 0.26
			+ air_noise * noise_decay * 0.06
		)

	return _seal_buffer(samples)


func _generate_build() -> PackedFloat32Array:
	const DURATION := 0.45
	const NOTE_DURATION := 0.27
	var samples := _new_sample_buffer(DURATION)
	var notes := [220.0, 277.18, 329.63]

	for index in range(samples.size()):
		var time := float(index) / float(SAMPLE_RATE)
		var value := 0.0
		for note_index in range(notes.size()):
			var note_start := float(note_index) * 0.085
			value += _soft_note(time, note_start, NOTE_DURATION, float(notes[note_index]), 0.34)

		var shimmer_envelope := _edge_envelope(time, DURATION, 0.06, 0.20)
		value += _chirp(time, 260.0, 720.0, DURATION) * shimmer_envelope * 0.055
		samples[index] = value

	return _seal_buffer(samples)


func _generate_upgrade() -> PackedFloat32Array:
	const DURATION := 0.62
	const NOTE_DURATION := 0.30
	var samples := _new_sample_buffer(DURATION)
	var notes := [329.63, 415.30, 493.88, 659.25]

	for index in range(samples.size()):
		var time := float(index) / float(SAMPLE_RATE)
		var value := 0.0
		for note_index in range(notes.size()):
			var note_start := float(note_index) * 0.085
			value += _soft_note(time, note_start, NOTE_DURATION, float(notes[note_index]), 0.27)

		value += _soft_note(time, 0.18, 0.40, 164.81, 0.12)
		var sweep_envelope := _edge_envelope(time, DURATION, 0.045, 0.26)
		value += _chirp(time, 380.0, 1280.0, DURATION) * sweep_envelope * 0.07
		samples[index] = value

	return _seal_buffer(samples)


func _generate_wave() -> PackedFloat32Array:
	const DURATION := 0.70
	var samples := _new_sample_buffer(DURATION)

	for index in range(samples.size()):
		var time := float(index) / float(SAMPLE_RATE)
		var progress := clampf(time / DURATION, 0.0, 1.0)
		var envelope := _edge_envelope(time, DURATION, 0.065, 0.23)
		var tremolo := 0.82 + 0.18 * sin(TAU * 9.0 * time)
		var pulse := 0.72 + 0.28 * sin(TAU * 18.0 * time)
		samples[index] = envelope * tremolo * (
			_chirp(time, 155.0, 485.0, DURATION) * 0.46
			+ _chirp(time, 310.0, 970.0, DURATION) * 0.14
			+ sin(TAU * (72.0 * time + 18.0 * time * progress)) * 0.18 * pulse
		)

	return _seal_buffer(samples)


func _generate_victory() -> PackedFloat32Array:
	const DURATION := 0.88
	const NOTE_DURATION := 0.34
	var samples := _new_sample_buffer(DURATION)
	var notes := [261.63, 329.63, 392.00, 523.25, 659.25]

	for index in range(samples.size()):
		var time := float(index) / float(SAMPLE_RATE)
		var value := 0.0
		for note_index in range(notes.size()):
			var note_start := float(note_index) * 0.105
			value += _soft_note(time, note_start, NOTE_DURATION, float(notes[note_index]), 0.24)
			value += _soft_note(
				time,
				note_start,
				NOTE_DURATION,
				float(notes[note_index]) * 2.0,
				0.055
			)

		value += _soft_note(time, 0.44, 0.40, 130.81, 0.12)
		samples[index] = value

	return _seal_buffer(samples)


func _generate_defeat() -> PackedFloat32Array:
	const DURATION := 0.88
	const NOTE_DURATION := 0.38
	var samples := _new_sample_buffer(DURATION)
	var notes := [392.00, 311.13, 246.94, 196.00]

	for index in range(samples.size()):
		var time := float(index) / float(SAMPLE_RATE)
		var value := 0.0
		for note_index in range(notes.size()):
			var note_start := float(note_index) * 0.135
			value += _soft_note(time, note_start, NOTE_DURATION, float(notes[note_index]), 0.28)
			value += _soft_note(
				time,
				note_start + 0.008,
				NOTE_DURATION,
				float(notes[note_index]) * 0.997,
				0.10
			)

		value += _soft_note(time, 0.55, 0.29, 98.00, 0.25)
		samples[index] = value

	return _seal_buffer(samples)


func _new_sample_buffer(duration: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(maxi(1, int(round(duration * float(SAMPLE_RATE)))))
	return samples


func _soft_note(
	time: float,
	start_time: float,
	duration: float,
	frequency: float,
	amplitude: float
) -> float:
	var local_time := time - start_time
	if local_time < 0.0 or local_time >= duration:
		return 0.0

	var envelope := _edge_envelope(local_time, duration, 0.012, duration * 0.70)
	var fundamental := sin(TAU * frequency * local_time)
	var soft_third := sin(TAU * frequency * 3.0 * local_time) * 0.055
	return (fundamental + soft_third) * envelope * amplitude


func _chirp(time: float, start_frequency: float, end_frequency: float, duration: float) -> float:
	var safe_duration := maxf(duration, 0.0001)
	var frequency_slope := (end_frequency - start_frequency) / safe_duration
	var phase := start_frequency * time + 0.5 * frequency_slope * time * time
	return sin(TAU * phase)


func _edge_envelope(
	time: float,
	duration: float,
	attack_time: float,
	release_time: float
) -> float:
	var attack := smoothstep(0.0, maxf(attack_time, 0.0001), time)
	var release := smoothstep(0.0, maxf(release_time, 0.0001), duration - time)
	return attack * release


## 清除缓冲首尾突变，并将峰值归一化到安全范围。
func _seal_buffer(samples: PackedFloat32Array, target_peak: float = 1.0) -> PackedFloat32Array:
	if samples.is_empty():
		return samples

	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value))

	if peak > 0.0001:
		var gain := target_peak / peak
		for index in range(samples.size()):
			samples[index] *= gain

	samples[0] = 0.0
	samples[samples.size() - 1] = 0.0
	return samples


func _make_wav(samples: PackedFloat32Array, target_peak: float) -> AudioStreamWAV:
	# 先按目标峰值归一化，再转换为小端 PCM 16-bit 字节。
	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value))

	var gain := 0.0 if peak <= 0.0001 else target_peak / peak
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)

	for index in range(samples.size()):
		var sample_value := int(round(clampf(samples[index] * gain, -1.0, 1.0) * 32767.0))
		var encoded_sample := sample_value & 0xFFFF
		pcm[index * 2] = encoded_sample & 0xFF
		pcm[index * 2 + 1] = (encoded_sample >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream
