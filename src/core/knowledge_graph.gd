class_name KnowledgeGraph
extends RefCounted

## 知识/技能双树。知识节点由实验/里程碑授予，技能节点消耗 XP（标 auto 的除外）。
## 四态：completed / available / challenge / locked，见 docs/design/07-skill-knowledge-tree.md。
## requires 条件全部数据驱动，支持 all / any / count 组合与 gate/lab/node/item/flag 条件。

var nodes: Dictionary = {}
var order: Array = []
var trees: Array = ["knowledge", "skill"]

static func from_doc(doc: Dictionary) -> KnowledgeGraph:
	var g := KnowledgeGraph.new()
	for raw in doc.get("nodes", []):
		if raw is Dictionary:
			var n: Dictionary = raw
			var id := str(n.get("id", ""))
			if id.is_empty():
				continue
			g.nodes[id] = n
			g.order.append(id)
	return g

func has_node(id: String) -> bool:
	return nodes.has(id)

func node(id: String) -> Dictionary:
	return nodes.get(id, {})

func title(id: String) -> String:
	var n := node(id)
	return str(n.get("title", n.get("name", id)))

func kind(id: String) -> String:
	return str(node(id).get("kind", "knowledge"))

func tree(id: String) -> String:
	return str(node(id).get("tree", "knowledge" if kind(id) == "knowledge" else "skill"))

func prereqs(id: String) -> Array:
	return node(id).get("prereq", [])

func is_unlocked(state: PlayerState, id: String) -> bool:
	return state.has_knowledge(id)

func can_unlock(state: PlayerState, id: String) -> Dictionary:
	if not nodes.has(id):
		return {"ok": false, "error": "节点不存在", "already": false, "state": "locked"}
	if is_unlocked(state, id):
		return {"ok": false, "error": "已经解锁", "already": true, "state": "completed"}
	var req := requirements_met(state, id)
	if not bool(req.get("ok", false)):
		return {"ok": false, "error": str(req.get("error", "条件未满足")), "already": false, "state": "locked"}
	if kind(id) == "skill" and not bool(node(id).get("auto", false)):
		var cost := int(node(id).get("xp_cost", node(id).get("cost", 0)))
		if state.xp < cost:
			return {"ok": false, "error": "经验不足：需要 %d，现有 %d" % [cost, state.xp], "already": false, "state": "challenge"}
	return {"ok": true, "error": "", "already": false, "state": "available"}

func unlock(state: PlayerState, id: String) -> Dictionary:
	var check := can_unlock(state, id)
	if not bool(check.ok):
		return check
	var n := node(id)
	var awarded_scrap := 0
	var awarded_xp := 0
	var cost_xp := 0
	if kind(id) == "skill" and not bool(n.get("auto", false)):
		cost_xp = int(n.get("xp_cost", n.get("cost", 0)))
		state.spend_xp(cost_xp)
	else:
		awarded_scrap = int(n.get("scrap_award", 0))
		awarded_xp = int(n.get("xp_award", 0))
		state.add_scrap(awarded_scrap)
		state.add_xp(awarded_xp)
	state.grant_knowledge(id)
	return {
		"ok": true, "error": "", "already": false, "id": id, "kind": kind(id), "node": n,
		"awarded_scrap": awarded_scrap, "awarded_xp": awarded_xp, "cost_xp": cost_xp,
	}

func node_state(state: PlayerState, id: String) -> String:
	if is_unlocked(state, id):
		return "completed"
	return str(can_unlock(state, id).get("state", "locked"))

func requirements_met(state: PlayerState, id: String) -> Dictionary:
	var n := node(id)
	for p in prereqs(id):
		if not state.has_knowledge(str(p)):
			return {"ok": false, "error": "前置知识「%s」尚未掌握" % title(str(p))}
	var req: Dictionary = n.get("requires", {})
	if req.is_empty():
		return {"ok": true, "error": ""}
	var all: Array = req.get("all", [])
	for cond in all:
		var r := _condition_met(state, cond)
		if not bool(r.get("ok", false)):
			return r
	var any: Array = req.get("any", [])
	if not any.is_empty():
		var any_ok := false
		for cond in any:
			if bool(_condition_met(state, cond).get("ok", false)):
				any_ok = true
				break
		if not any_ok:
			return {"ok": false, "error": "任一条件未满足：%s" % str(req.get("any_label", "any"))}
	var count: Dictionary = req.get("count", {})
	if not count.is_empty():
		var need := int(count.get("n", 0))
		var have := _count_scope(state, str(count.get("scope", "gate")))
		if have < need:
			return {"ok": false, "error": "进度不足：%d/%d" % [have, need]}
	return {"ok": true, "error": ""}

func _condition_met(state: PlayerState, raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {"ok": true, "error": ""}
	var cond: Dictionary = raw
	var typ := str(cond.get("type", ""))
	var id := str(cond.get("id", ""))
	match typ:
		"node":
			# 当前节点处于解锁/评估过程中，视为不可自满足；由调用方保证顺序
			if state.has_knowledge(id):
				return {"ok": true, "error": ""}
			return {"ok": false, "error": "需要「%s」" % title(id)}
		"gate":
			if state.has_flag("gate:%s" % id) or state.has_flag("gate_%s" % id):
				return {"ok": true, "error": ""}
			return {"ok": false, "error": "需要验收通过 %s" % id}
		"lab":
			if state.has_flag("lab:%s" % id) or state.is_lab_completed(id):
				return {"ok": true, "error": ""}
			return {"ok": false, "error": "需要完成实验 %s" % id}
		"flag":
			if state.has_flag(id):
				return {"ok": true, "error": ""}
			return {"ok": false, "error": "需要标记 %s" % id}
		"item":
			var need := int(cond.get("qty", 1))
			if state.item_count(id) >= need:
				return {"ok": true, "error": ""}
			return {"ok": false, "error": "需要物品 %s ×%d" % [id, need]}
		_:
			return {"ok": true, "error": ""}

func _count_scope(state: PlayerState, scope: String) -> int:
	var n := 0
	if scope == "gate":
		for k in state.flags.keys():
			if str(k).begins_with("gate:"):
				n += 1
	elif scope == "lab":
		n = state.labs_completed.size()
	elif scope == "objective":
		for k in state.objectives.keys():
			if bool(state.objectives[k]):
				n += 1
	return n

func available(state: PlayerState) -> Array:
	var out := []
	for id in order:
		if state.has_knowledge(str(id)):
			continue
		var check := can_unlock(state, str(id))
		out.append({"id": str(id), "ok": bool(check.ok), "error": str(check.error), "state": str(check.get("state", ""))})
	return out

func progress(state: PlayerState) -> Dictionary:
	var done := 0
	for id in order:
		if state.has_knowledge(str(id)):
			done += 1
	return {"done": done, "total": order.size()}

func knowledge_nodes() -> Array:
	var out := []
	for id in order:
		if kind(str(id)) == "knowledge":
			out.append(str(id))
	return out

func nodes_of_tree(which: String) -> Array:
	var out := []
	for id in order:
		if tree(str(id)) == which or (which == "skill" and kind(str(id)) == "skill"):
			out.append(str(id))
	return out

func node_map() -> Dictionary:
	return nodes
