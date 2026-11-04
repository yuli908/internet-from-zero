extends Node

## 章节流程：实验完成 → 目标达成 → 奖励 → 知识/技能节点 → 自动存档。
## 所有 gate 通过才允许调用 complete_lab()；gate 结果由实验页逐条执行后写入 flags。

func runtime() -> ChapterRuntime:
	return DataDB.chapter

func complete_lab(lab_id: String) -> Dictionary:
	var p := GameState.player
	if p == null:
		return {"ok": false, "error": "玩家状态不存在"}
	var lab := runtime().lab(lab_id)
	if lab.is_empty():
		return {"ok": false, "error": "实验 %s 不存在" % lab_id}
	var obj_id := str(lab.get("objective", ""))
	if p.is_objective_done(obj_id):
		return {"ok": true, "error": "", "newly": false, "already": true}
	# M3 T5：物品奖励整单校验先于任何状态变更，避免"目标已记完成、奖励却发不出"。
	# M5：`grants` 的唯一数据源是实验数据段（`data/labs/*.json`），章节内联字段仅作覆盖。
	var grants: Dictionary = runtime().grants(lab_id, DataDB.labs_doc, p)
	if not grants.is_empty():
		var v := p.grant_items(lab_id, grants, DataDB.catalog, true)
		if not bool(v.get("ok", false)):
			EventBus.toast("奖励未发放：%s" % str(v.get("error", "")), "warn")
			return {"ok": false, "error": str(v.get("error", "")), "newly": false, "grant_rejected": true}
	p.mark_lab_completed(lab_id)
	p.set_flag("lab:%s" % lab_id, true)
	for gid in lab.get("gate_ids", []):
		p.set_flag("gate:%s" % str(gid), true)
	var res := runtime().complete_objective(p, obj_id)
	if bool(res.get("newly", false)):
		var reward: Dictionary = lab.get("reward", {})
		if not p.has_flag("lab_reward:%s" % lab_id):
			p.add_gold(int(reward.get("gold", 0)))
			p.add_xp(int(reward.get("xp", 0)))
			p.set_flag("lab_reward:%s" % lab_id, true)
		if not grants.is_empty():
			var g := p.grant_items(lab_id, grants, DataDB.catalog)
			if bool(g.get("ok", false)) and not bool(g.get("already", false)):
				var granted: Dictionary = g.get("granted", {})
				var total := 0
				for id in granted:
					total += int(granted[id])
				if total > 0:
					EventBus.toast("奖励入库：%d 件物品" % total, "ok")
		var k := str(lab.get("knowledge", ""))
		if not k.is_empty():
			Knowledge.unlock(k)
		var milestone := str(lab.get("milestone", ""))
		if not milestone.is_empty():
			Knowledge.unlock(milestone)
		for card in lab.get("knowledge_cards", []):
			Knowledge.unlock(str(card))
		var skills: Array = lab.get("skill_nodes", [])
		var single := str(lab.get("skill_node", ""))
		if not single.is_empty() and not skills.has(single):
			skills.append(single)
		for s in skills:
			Knowledge.unlock(str(s))
		EventBus.lab_completed.emit(lab_id)
		EventBus.objective_completed.emit(obj_id)
		var title := str(runtime().objective(obj_id).get("title", obj_id))
		EventBus.toast("实验完成：%s（+%d 金币 / +%d XP）" % [title, int(reward.get("gold", 0)), int(reward.get("xp", 0))], "ok")
		EventBus.state_changed.emit()
		if bool(res.get("all_done", false)):
			_finish_chapter()
		SaveManager.autosave()
	return res

func _finish_chapter() -> void:
	var p := GameState.player
	if not runtime().chapter_reward_claimable(p):
		return
	p.set_flag(runtime().chapter_reward_key(), true)
	p.set_flag(runtime().chapter_complete_flag(), true)
	var reward: Dictionary = runtime().data.get("complete_reward", {})
	var payout := runtime().chapter_finish_reward(DataDB.skill_graph)
	p.add_gold(int(payout.get("gold", 0)))
	p.add_xp(int(payout.get("xp", 0)))
	var badge := str(reward.get("badge", ""))
	if not badge.is_empty():
		p.set_flag("badge:%s" % badge, true)
	var node_id := str(payout.get("node_id", ""))
	Knowledge.unlock(node_id if not node_id.is_empty() else runtime().id().to_upper())
	EventBus.chapter_completed.emit(runtime().id())
	EventBus.toast("章节完成！%s" % runtime().title(), "ok")
	EventBus.fire("chapter_completed:%s" % runtime().id())
	SaveManager.autosave()

func progress() -> Dictionary:
	if GameState.player == null:
		return {"done": 0, "total": 0}
	return runtime().progress(GameState.player)

func next_objective() -> Dictionary:
	if GameState.player == null:
		return {}
	return runtime().next_objective(GameState.player)

func is_objective_done(obj_id: String) -> bool:
	return GameState.player != null and GameState.player.is_objective_done(obj_id)

func is_lab_unlocked(lab_id: String) -> bool:
	return GameState.player != null and runtime().lab_unlocked(GameState.player, lab_id)

func lab_lock_reason(lab_id: String) -> String:
	if GameState.player == null:
		return "玩家状态未就绪"
	return runtime().lab_lock_reason(GameState.player, lab_id)

func chapter_complete() -> bool:
	return GameState.player != null and GameState.player.has_flag("chapter_complete:%s" % runtime().id())

func gate_passed(gate_id: String) -> bool:
	return GameState.player != null and GameState.player.has_flag("gate:%s" % gate_id)
