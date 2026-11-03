class_name KnowledgeGraph
extends RefCounted

## 知识/技能树。知识节点由实验自动解锁，技能节点消耗 XP 手动解锁。

var nodes: Dictionary = {}
var order: Array = []

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
	return str(node(id).get("title", id))

func kind(id: String) -> String:
	return str(node(id).get("kind", "knowledge"))

func prereqs(id: String) -> Array:
	return node(id).get("prereq", [])

func is_unlocked(state: PlayerState, id: String) -> bool:
	return state.has_knowledge(id)

func can_unlock(state: PlayerState, id: String) -> Dictionary:
	if not nodes.has(id):
		return {"ok": false, "error": "节点不存在", "already": false}
	if is_unlocked(state, id):
		return {"ok": false, "error": "已经解锁", "already": true}
	for p in prereqs(id):
		if not state.has_knowledge(str(p)):
			return {"ok": false, "error": "前置知识「%s」尚未掌握" % title(str(p)), "already": false}
	if kind(id) == "skill":
		var cost := int(node(id).get("xp_cost", 0))
		if state.xp < cost:
			return {"ok": false, "error": "经验不足：需要 %d，现有 %d" % [cost, state.xp], "already": false}
	return {"ok": true, "error": "", "already": false}

func unlock(state: PlayerState, id: String) -> Dictionary:
	var check := can_unlock(state, id)
	if not bool(check.ok):
		return check
	var n := node(id)
	var awarded_scrap := 0
	var awarded_xp := 0
	var cost_xp := 0
	if kind(id) == "skill":
		cost_xp = int(n.get("xp_cost", 0))
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

func available(state: PlayerState) -> Array:
	var out := []
	for id in order:
		if state.has_knowledge(str(id)):
			continue
		var check := can_unlock(state, str(id))
		out.append({"id": str(id), "ok": bool(check.ok), "error": str(check.error)})
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
