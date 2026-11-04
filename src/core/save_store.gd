class_name SaveStore
extends RefCounted

## 存档文件读写：临时文件 + 备份 + 原子替换。
## 损坏时自动回退到 .bak。

var dir_path := "user://saves"

func _init(dir_path_in: String = "user://saves") -> void:
	dir_path = dir_path_in

func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [dir_path, slot]

func backup_path(slot: int) -> String:
	return "%s/slot_%d.bak" % [dir_path, slot]

func ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(dir_path):
		return true
	return DirAccess.make_dir_recursive_absolute(dir_path) == OK

func save(state: PlayerState, slot: int) -> Dictionary:
	if not ensure_dir():
		return {"ok": false, "error": "无法创建存档目录 %s" % dir_path}
	state.slot = slot
	state.stats["saves"] = int(state.stats.get("saves", 0)) + 1
	var text := SaveCodec.encode(state)
	var final_path := slot_path(slot)
	var tmp_path := final_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "无法写入临时文件（错误码 %d）" % FileAccess.get_open_error()}
	f.store_string(text)
	f.close()
	var check := _read(tmp_path)
	if check != text:
		return {"ok": false, "error": "写入校验失败：回读内容不一致"}
	if FileAccess.file_exists(final_path):
		var old := _read(final_path)
		if not old.is_empty():
			_write(backup_path(slot), old)
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var err := DirAccess.rename_absolute(tmp_path, final_path)
	if err != OK:
		_write(final_path, text)
		DirAccess.remove_absolute(tmp_path)
	return {"ok": true, "error": "", "path": final_path, "bytes": text.length()}

func load_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		var bak_missing := backup_path(slot)
		if not FileAccess.file_exists(bak_missing):
			return {"ok": false, "error": "槽位 %d 没有存档" % slot, "used_backup": false}
		return _load_from(bak_missing, true, slot)
	var res := _load_from(path, false, slot)
	if bool(res.ok):
		return res
	var bak := backup_path(slot)
	if FileAccess.file_exists(bak):
		var fallback := _load_from(bak, true, slot)
		if bool(fallback.ok):
			fallback["primary_error"] = res.error
			return fallback
	return res

func _load_from(path: String, used_backup: bool, slot: int) -> Dictionary:
	var text := _read(path)
	var decoded := SaveCodec.decode(text)
	if not bool(decoded.ok):
		return {"ok": false, "error": "读取 %s 失败：%s" % [path, decoded.error], "used_backup": used_backup, "path": path}
	var state := PlayerState.from_dict(decoded.payload)
	state.slot = slot
	return {
		"ok": true, "error": "", "state": state, "path": path,
		"used_backup": used_backup, "migrated_from": int(decoded.migrated_from),
		"version": int(decoded.version),
	}

func slot_info(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "空槽位", "path": path}
	var decoded := SaveCodec.decode(_read(path))
	if not bool(decoded.ok):
		return {"ok": false, "error": str(decoded.error), "path": path}
	var p: Dictionary = decoded.payload
	return {
		"ok": true, "error": "", "path": path,
		"updated_at": str(p.get("updated_at", "")),
		"chapter_id": str(p.get("chapter_id", "")),
		"gold": int(p.get("gold", 0)),
		"xp": int(p.get("xp", 0)),
		"knowledge": int((p.get("knowledge", {}) as Dictionary).size()),
		"objectives": int((p.get("objectives", {}) as Dictionary).size()),
	}

func delete_slot(slot: int) -> bool:
	var removed := false
	for path in [slot_path(slot), backup_path(slot), slot_path(slot) + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
			removed = true
	return removed

func copy_slot_to_dir(slot: int, target_dir: String) -> Dictionary:
	var src := slot_path(slot)
	if not FileAccess.file_exists(src):
		return {"ok": false, "error": "没有可备份的存档"}
	if not DirAccess.dir_exists_absolute(target_dir):
		DirAccess.make_dir_recursive_absolute(target_dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var dst := "%s/slot_%d_%s.json" % [target_dir, slot, stamp]
	var text := _read(src)
	if not _write(dst, text):
		return {"ok": false, "error": "备份写入失败"}
	return {"ok": true, "error": "", "path": dst}

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text

func _write(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true
