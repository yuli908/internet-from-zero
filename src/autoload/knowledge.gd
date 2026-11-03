extends Node

## 知识树服务：解锁节点、发放奖励、广播事件。

func unlock(id: String) -> Dictionary:
	if GameState.player == null:
		return {"ok": false, "error": "玩家状态不存在"}
	var res := DataDB.skill_graph.unlock(GameState.player, id)
	if bool(res.get("ok", false)):
		var n: Dictionary = res.get("node", {})
		EventBus.knowledge_unlocked.emit(id)
		EventBus.state_changed.emit()
		if str(res.get("kind", "knowledge")) == "skill":
			EventBus.toast("技能解锁：%s（消耗 %d XP）" % [str(n.get("title", id)), int(res.get("cost_xp", 0))], "ok")
		else:
			EventBus.toast("知识解锁：%s（+%d XP / +%d 废铁）" % [str(n.get("title", id)), int(res.get("awarded_xp", 0)), int(res.get("awarded_scrap", 0))], "ok")
		EventBus.fire("knowledge_unlocked:%s" % id)
	return res

func is_unlocked(id: String) -> bool:
	return GameState.player != null and GameState.player.has_knowledge(id)

func can_unlock(id: String) -> Dictionary:
	return DataDB.skill_graph.can_unlock(GameState.player, id)

func progress() -> Dictionary:
	return DataDB.skill_graph.progress(GameState.player)
