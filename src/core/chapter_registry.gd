extends RefCounted

## 章节注册表：启动时扫 `data/chapters/*_levels.json`，按章节 `number` 排序。
## 顺序来自章节数据本身，**不依赖文件名字典序**；实验数据按章节 ID 配对 `data/labs/<id>_labs.json`。
## 纯静态、无 autoload 依赖，`-s` 模式与运行时都可直接用。

const CHAPTER_DIR := "res://data/chapters"
const LABS_DIR := "res://data/labs"

static var _entries: Array = []
static var _by_id: Dictionary = {}
static var _levels: Dictionary = {}
static var _labs_docs: Dictionary = {}
static var _loaded := false

static func entries() -> Array:
	_ensure()
	return _entries.duplicate()

static func ids() -> Array:
	_ensure()
	var out := []
	for e in _entries:
		out.append(str((e as Dictionary).get("id", "")))
	return out

static func default_id() -> String:
	## 注册表的首个章节（按 `number` 升序），旧档/旧调用点回落到这里。
	_ensure()
	if _entries.is_empty():
		return ""
	return str((_entries[0] as Dictionary).get("id", ""))

static func has(cid: String) -> bool:
	_ensure()
	return _by_id.has(cid)

static func entry(cid: String) -> Dictionary:
	_ensure()
	return _by_id.get(cid, {})

static func levels_doc(cid: String) -> Dictionary:
	_ensure()
	return _levels.get(cid, {})

static func labs_doc(cid: String) -> Dictionary:
	_ensure()
	return _labs_docs.get(cid, {})

static func labs(cid: String) -> Dictionary:
	var doc := labs_doc(cid)
	var seg: Variant = doc.get("labs", {})
	return seg if seg is Dictionary else {}

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(CHAPTER_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not str(file).ends_with("_levels.json"):
			continue
		var path := "%s/%s" % [CHAPTER_DIR, str(file)]
		var doc := _read(path)
		var cid := str(doc.get("id", ""))
		if cid.is_empty() or _by_id.has(cid):
			continue
		var labs_path := "%s/%s_labs.json" % [LABS_DIR, cid]
		var has_labs := FileAccess.file_exists(labs_path)
		_levels[cid] = doc
		if has_labs:
			_labs_docs[cid] = _read(labs_path)
		var meta := {
			"id": cid,
			"number": int(doc.get("number", 0)),
			"title": str(doc.get("title", "")),
			"levels_path": path,
			"labs_path": labs_path if has_labs else "",
			"has_labs": has_labs,
			"next_chapter": str(doc.get("next_chapter", "")),
		}
		_by_id[cid] = meta
		_entries.append(meta)
	_entries.sort_custom(_compare)

static func _compare(a: Dictionary, b: Dictionary) -> bool:
	## 主键章节号；缺号排末尾；同号按 ID 保证确定性。
	var na := int(a.get("number", 0))
	var nb := int(b.get("number", 0))
	if na <= 0 and nb > 0:
		return false
	if nb <= 0 and na > 0:
		return true
	if na == nb:
		return str(a.get("id", "")) < str(b.get("id", ""))
	return na < nb

static func _read(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
