extends Node

## 存档管理：原子写入 + 备份回退 + 自动存档。

var store := SaveStore.new("user://saves")
var last_message := ""

func has_slot(slot: int = 1) -> bool:
	return FileAccess.file_exists(store.slot_path(slot)) or FileAccess.file_exists(store.backup_path(slot))

func save_game(slot: int = 1, quiet: bool = false) -> Dictionary:
	if GameState.player == null:
		return {"ok": false, "error": "玩家状态不存在"}
	var res := store.save(GameState.player, slot)
	if bool(res.get("ok", false)):
		last_message = "已保存 · 槽位 %d · %s" % [slot, str(GameState.player.updated_at)]
		if not quiet:
			EventBus.toast("已保存到槽位 %d" % slot, "ok")
		EventBus.fire("game_autosaved" if quiet else "game_saved")
		EventBus.state_changed.emit()
	else:
		last_message = "保存失败：%s" % str(res.get("error", "未知错误"))
		EventBus.toast(last_message, "error")
	return res

func load_game(slot: int = 1, quiet: bool = false) -> Dictionary:
	var res := store.load_slot(slot)
	if bool(res.get("ok", false)):
		var st: PlayerState = res["state"]
		GameState.set_player(st)
		last_message = "已读取 · 槽位 %d" % slot
		if bool(res.get("used_backup", false)):
			last_message += "（主文件损坏，已回退备份）"
			EventBus.toast(last_message, "warn")
		elif not quiet:
			EventBus.toast(last_message, "ok")
		EventBus.state_changed.emit()
		EventBus.fire("game_loaded")
	else:
		last_message = "读取失败：%s" % str(res.get("error", "未知错误"))
		if not quiet:
			EventBus.toast(last_message, "error")
	return res

func autosave() -> void:
	if GameState.player == null:
		return
	var res := save_game(1, true)
	if bool(res.get("ok", false)):
		last_message = "自动保存 · %s" % str(GameState.player.updated_at)

func slot_info(slot: int = 1) -> Dictionary:
	return store.slot_info(slot)

func delete_slot(slot: int = 1) -> void:
	store.delete_slot(slot)
	EventBus.toast("槽位 %d 已删除" % slot, "warn")

func export_backup(slot: int = 1) -> Dictionary:
	var target := "user://backups"
	var res := store.copy_slot_to_dir(slot, target)
	if bool(res.get("ok", false)):
		EventBus.toast("已导出备份：%s" % str(res.get("path", "")), "ok")
	else:
		EventBus.toast("导出失败：%s" % str(res.get("error", "")), "error")
	return res
