class_name SaveStore
extends RefCounted

## 按命名空间隔离的 JSON 存档。
##
## 每个命名空间对应一个文件。写入时先落盘到临时文件，再替换正式文件，
## 避免进程中断留下半截 JSON。损坏或不兼容的存档会回退为空档。

const SCHEMA_VERSION := 1
const DEFAULT_BASE_DIR := "user://saves"
const DEFAULT_NAMESPACE := "default"

var last_error := ""
var is_loaded := false

var _base_dir := DEFAULT_BASE_DIR
var _namespace := DEFAULT_NAMESPACE
var _data: Dictionary = {}
var _dirty := false


func _init(start_base_dir: String = DEFAULT_BASE_DIR, start_namespace: String = DEFAULT_NAMESPACE) -> void:
	_base_dir = _normalize_base_dir(start_base_dir)
	_namespace = _normalize_namespace(start_namespace)


## 可切换存档目录，供测试或不同账号配置使用。
var base_dir: String:
	get:
		return _base_dir
	set(value):
		_base_dir = _normalize_base_dir(value)
		_data.clear()
		_dirty = false
		is_loaded = false


## 可切换命名空间，例如 achievements、settings、meta。
## namespace 是 GDScript 保留字，因此公开属性命名为 save_namespace。
var save_namespace: String:
	get:
		return _namespace
	set(value):
		_namespace = _normalize_namespace(value)
		_data.clear()
		_dirty = false
		is_loaded = false


func get_save_path() -> String:
	return _base_dir.path_join(_namespace + ".json")


## 一次性配置目录与命名空间；调用后仍需 load 或 flush。
func configure(next_base_dir: String, next_namespace: String = DEFAULT_NAMESPACE) -> void:
	base_dir = next_base_dir
	save_namespace = next_namespace


func get_base_dir() -> String:
	return _base_dir


func get_namespace() -> String:
	return _namespace


func set_namespace(next_namespace: String) -> void:
	save_namespace = next_namespace


## 显式切换到另一个命名空间并立即加载。
func use_namespace(next_namespace: String) -> bool:
	save_namespace = next_namespace
	return self.load()


## 从磁盘读取当前命名空间；文件不存在时得到空档。
func load() -> bool:
	last_error = ""
	_data.clear()
	_dirty = false

	var path := get_save_path()
	if not FileAccess.file_exists(path):
		is_loaded = true
		return true

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "无法读取存档：%s（错误码 %d）" % [path, FileAccess.get_open_error()]
		is_loaded = true
		return false

	var raw_text := file.get_as_text()
	var json := JSON.new()
	var parse_error := json.parse(raw_text)
	if parse_error != OK or not (json.data is Dictionary):
		last_error = "存档 JSON 无效：%s（第 %d 行）" % [path, json.get_error_line()]
		is_loaded = true
		return false

	var root: Dictionary = json.data
	var version := int(root.get("schema_version", -1))
	if version != SCHEMA_VERSION:
		last_error = "存档版本不兼容：%s（期望 %d，实际 %d）" % [path, SCHEMA_VERSION, version]
		is_loaded = true
		return false

	var payload: Variant = root.get("data", {})
	if not (payload is Dictionary):
		last_error = "存档 data 字段无效：%s" % path
		is_loaded = true
		return false

	_data = (payload as Dictionary).duplicate(true)
	is_loaded = true
	return true


## 原子写入当前命名空间。返回值表示正式文件是否成功替换。
func flush() -> bool:
	last_error = ""
	var path := get_save_path()
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK:
		last_error = "无法创建存档目录：%s（错误码 %d）" % [path.get_base_dir(), directory_error]
		return false

	var temporary_path := path + ".tmp"
	var root := {
		"schema_version": SCHEMA_VERSION,
		"namespace": _namespace,
		"data": _data,
	}

	var temporary_file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		last_error = "无法创建临时存档：%s（错误码 %d）" % [
			temporary_path,
			FileAccess.get_open_error(),
		]
		return false

	temporary_file.store_string(JSON.stringify(root, "\t", false))
	temporary_file.flush()
	temporary_file.close()

	# 同一目录内 rename 在常见平台上可原子替换已有存档。
	var rename_error := DirAccess.rename_absolute(temporary_path, path)
	if rename_error != OK:
		# 少数平台不允许 rename 覆盖；只在替换阶段做一次兼容回退。
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		rename_error = DirAccess.rename_absolute(temporary_path, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary_path)
		last_error = "无法替换存档：%s（错误码 %d）" % [path, rename_error]
		return false

	_dirty = false
	is_loaded = true
	return true


func set_value(key: String, value: Variant) -> bool:
	var parts := _key_parts(key)
	if parts.is_empty():
		last_error = "存档 key 不能为空"
		return false

	var node: Dictionary = _data
	for index in range(parts.size() - 1):
		var part := parts[index]
		var child: Variant = node.get(part, {})
		if not (child is Dictionary):
			last_error = "存档 key 路径冲突：%s" % key
			return false
		node[part] = child
		node = child

	node[parts[-1]] = value
	_dirty = true
	last_error = ""
	return true


func get_or(key: String, default_value: Variant = null) -> Variant:
	var parts := _key_parts(key)
	if parts.is_empty():
		return default_value

	var node: Variant = _data
	for part in parts:
		if not (node is Dictionary) or not (node as Dictionary).has(part):
			return default_value
		node = (node as Dictionary)[part]
	return node


## 对已有数值累加；没有值时从 0 开始。非数值目标会返回 null。
func add(key: String, amount: Variant = 1) -> Variant:
	var current: Variant = get_or(key, 0)
	var result: Variant
	if current is int and amount is int:
		result = current + amount
	elif (current is int or current is float) and (amount is int or amount is float):
		result = float(current) + float(amount)
	else:
		last_error = "存档字段不是数值：%s" % key
		return null

	if not set_value(key, result):
		return null
	return result


## 删除指定 key，返回是否存在并成功删除。
func remove(key: String) -> bool:
	var parts := _key_parts(key)
	if parts.is_empty():
		last_error = "存档 key 不能为空"
		return false

	var node: Variant = _data
	for index in range(parts.size() - 1):
		if not (node is Dictionary):
			return false
		var child: Variant = (node as Dictionary).get(parts[index])
		if not (child is Dictionary):
			return false
		node = child

	if not (node is Dictionary) or not (node as Dictionary).has(parts[-1]):
		return false
	(node as Dictionary).erase(parts[-1])
	_dirty = true
	last_error = ""
	return true


func has(key: String) -> bool:
	var sentinel := &"__save_store_missing__"
	return get_or(key, sentinel) != sentinel


# 承接 Object.set/get 对未知属性的访问，使 store.set("key", value)
# 与 store.get("key") 也能直接读写存档；需要默认值时使用 get_or。
func _set(property: StringName, value: Variant) -> bool:
	return set_value(str(property), value)


func _get(property: StringName) -> Variant:
	return get_or(str(property))


func get_schema_version() -> int:
	return SCHEMA_VERSION


func snapshot() -> Dictionary:
	return _data.duplicate(true)


func clear() -> void:
	_data.clear()
	_dirty = true


func is_dirty() -> bool:
	return _dirty


func _normalize_base_dir(value: String) -> String:
	var normalized := value.strip_edges()
	return DEFAULT_BASE_DIR if normalized.is_empty() else normalized.trim_suffix("/")


func _normalize_namespace(value: String) -> String:
	var normalized := value.strip_edges().trim_prefix("/").trim_suffix("/")
	if normalized.is_empty() or normalized.contains(".."):
		return DEFAULT_NAMESPACE
	for segment in normalized.split("/", false):
		if segment.is_empty() or segment.contains("\\") or segment.contains(":"):
			return DEFAULT_NAMESPACE
	return normalized


func _key_parts(key: String) -> PackedStringArray:
	var normalized := key.strip_edges()
	if normalized.is_empty():
		return PackedStringArray()
	return normalized.split(".", false)
