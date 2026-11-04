class_name ChapterRuntime
extends RefCounted

## 章节运行时：目标、实验解锁关系、进度。

var data: Dictionary = {}
var objectives: Dictionary = {}
var objective_order: Array = []
var labs: Dictionary = {}
var lab_order: Array = []

static func from_doc(doc: Dictionary) -> ChapterRuntime:
	var c := ChapterRuntime.new()
	c.data = doc.duplicate(true)
	for raw in doc.get("objectives", []):
		if raw is Dictionary:
			var o: Dictionary = raw
			var id := str(o.get("id", ""))
			if not id.is_empty():
				c.objectives[id] = o
				c.objective_order.append(id)
	for raw in doc.get("labs", []):
		if raw is Dictionary:
			var lab: Dictionary = raw
			var id := str(lab.get("id", ""))
			if not id.is_empty():
				c.labs[id] = lab
				c.lab_order.append(id)
	return c

func id() -> String:
	return str(data.get("id", ""))

func title() -> String:
	return str(data.get("title", ""))

func subtitle() -> String:
	return str(data.get("subtitle", ""))

func lab(id_in: String) -> Dictionary:
	return labs.get(id_in, {})

func objective(id_in: String) -> Dictionary:
	return objectives.get(id_in, {})

func objective_for_lab(lab_id: String) -> String:
	return str(lab(lab_id).get("objective", ""))

func grants(lab_id: String, labs_doc: Dictionary = {}, state: PlayerState = null) -> Dictionary:
	## 物品奖励解析：优先章节内联 `grants`，否则回落到实验数据段（`ch01_labs.json` 等）。
	## 单一数据源仍是 labs 段；章节内联只作覆盖入口，避免两份奖励表打架。
	## 传入 state 时真正执行 `bound_first`：该 lab 已发过（`granted:<lab>`）就返回空单，
	## 重复刷同一关不会再拿第二件；不传 state 只做数据校验用。
	var g := _raw_grants(lab_id, labs_doc)
	if g.is_empty():
		return {}
	if state != null and bool(g.get("bound_first", false)):
		if state.has_flag("granted:%s" % lab_id):
			return {}
	return g

func _raw_grants(lab_id: String, labs_doc: Dictionary) -> Dictionary:
	var lab_data := lab(lab_id)
	if lab_data.is_empty():
		return {}
	var inline: Variant = lab_data.get("grants", {})
	if inline is Dictionary and not (inline as Dictionary).is_empty():
		return inline
	if labs_doc.is_empty():
		return {}
	var key := str(lab_data.get("data_key", ""))
	var all: Variant = labs_doc.get("labs", {})
	if not (all is Dictionary):
		return {}
	var seg: Variant = (all as Dictionary).get(key, {})
	if not (seg is Dictionary):
		return {}
	var g: Variant = (seg as Dictionary).get("grants", {})
	return g if g is Dictionary else {}

func requires(lab_id: String) -> Array:
	var v: Variant = lab(lab_id).get("requires", [])
	if v == null:
		return []
	if v is Array:
		return v
	if str(v).is_empty():
		return []
	return [str(v)]

func content_status(lab_id: String) -> String:
	## 内容状态：`ready` / `deferred`；旧数据不写该字段即视为 ready，不破坏现有存档。
	return str(lab(lab_id).get("content_status", "ready"))

func requirement(lab_id: String) -> String:
	## 必修属性：`MUST` / `OPT` / `CHAL`；旧数据不写即视为 MUST。
	## 与 `content_status` 是两个独立维度，不允许互相推导。
	return str(lab(lab_id).get("requirement", "MUST"))

func lab_content_available(lab_id: String) -> Dictionary:
	## 内容级可用性（先于前置 lab 判定）：deferred 的节整节禁入，不是让 gate 显示 pending。
	var lab_data := lab(lab_id)
	if lab_data.is_empty():
		return {"available": false, "reason": "实验不存在"}
	if content_status(lab_id) != "ready":
		var reason := str(lab_data.get("deferred_reason", ""))
		return {"available": false, "reason": reason if not reason.is_empty() else "这一节暂未开放"}
	return {"available": true, "reason": ""}

func start_gold() -> int:
	return int(data.get("start_gold", 0))

func start_items() -> Dictionary:
	return data.get("start_items", {})

func next_chapter() -> String:
	return str(data.get("next_chapter", ""))

func lab_unlocked(state: PlayerState, lab_id: String) -> bool:
	var lab_data := lab(lab_id)
	if lab_data.is_empty():
		return false
	if not bool(lab_content_available(lab_id).get("available", false)):
		return false
	for req in requires(lab_id):
		if not state.is_lab_completed(str(req)):
			return false
	return true

func lab_lock_reason(state: PlayerState, lab_id: String) -> String:
	var lab_data := lab(lab_id)
	var avail := lab_content_available(lab_id)
	if not bool(avail.get("available", false)):
		return str(avail.get("reason", ""))
	var missing := []
	for req in requires(lab_id):
		if not state.is_lab_completed(str(req)):
			missing.append("「%s」" % str(lab(req).get("title", req)))
	if missing.is_empty():
		return ""
	return "需要先完成 %s" % "、".join(missing)

static func _opt_string(d: Dictionary, key: String) -> String:
	var v: Variant = d.get(key, "")
	if v == null:
		return ""
	return str(v)

func is_objective_done(state: PlayerState, obj_id: String) -> bool:
	return state.is_objective_done(obj_id)

func objective_ready(obj_id: String) -> bool:
	## 内容可玩：`content_status == "ready"`。
	var lab_id := str(objective(obj_id).get("lab", ""))
	if lab_id.is_empty():
		return true
	return content_status(lab_id) == "ready"

func objective_active(obj_id: String) -> bool:
	## 计入完成度分母：`requirement == "MUST"` **且** `content_status == "ready"`。
	## OPT / CHAL 只给奖励、不进分母；deferred 也不进。
	if not objective_ready(obj_id):
		return false
	var lab_id := str(objective(obj_id).get("lab", ""))
	if lab_id.is_empty():
		return true
	return requirement(lab_id) == "MUST"

func active_objective_ids() -> Array:
	var out := []
	for id in objective_order:
		if objective_active(str(id)):
			out.append(id)
	return out

func complete_objective(state: PlayerState, obj_id: String) -> Dictionary:
	if not objectives.has(obj_id):
		return {"ok": false, "error": "目标不存在", "newly": false}
	if state.is_objective_done(obj_id):
		return {"ok": true, "error": "", "newly": false, "all_done": all_done(state)}
	# 延后节不产生任何完成记录：不是让 gate 显示 pending，而是根本不给记 pass。
	if not objective_ready(obj_id):
		return {"ok": false, "error": "该实验内容暂未开放", "newly": false, "all_done": all_done(state)}
	var newly := state.complete_objective(obj_id)
	return {"ok": true, "error": "", "newly": newly, "all_done": all_done(state)}

func all_done(state: PlayerState) -> bool:
	for id in active_objective_ids():
		if not state.is_objective_done(str(id)):
			return false
	return true

func next_objective(state: PlayerState) -> Dictionary:
	for id in active_objective_ids():
		if not state.is_objective_done(str(id)):
			return objectives[str(id)]
	return {}

func progress(state: PlayerState) -> Dictionary:
	var ids := active_objective_ids()
	var done := 0
	for id in ids:
		if state.is_objective_done(str(id)):
			done += 1
	return {"done": done, "total": ids.size()}

func chapter_reward_key() -> String:
	return "chapter_reward:%s" % id()

func chapter_complete_flag() -> String:
	return "chapter_complete:%s" % id()

func chapter_reward_claimable(state: PlayerState) -> bool:
	## 章末奖励一次性：全部可完成节做完，且未领过。
	return all_done(state) and not state.has_flag(chapter_reward_key())

func dsl_errors() -> Array:
	var errs := []
	for lab_id in lab_order:
		var lab_data := lab(lab_id)
		var obj := str(lab_data.get("objective", ""))
		if obj.is_empty() or not objectives.has(obj):
			errs.append("实验 %s 指向不存在的目标 %s" % [lab_id, obj])
		for req in requires(lab_id):
			if not labs.has(str(req)):
				errs.append("实验 %s 的前置实验 %s 不存在" % [lab_id, str(req)])
		if str(lab_data.get("knowledge", "")).is_empty():
			errs.append("实验 %s 缺少知识节点" % lab_id)
	return errs
