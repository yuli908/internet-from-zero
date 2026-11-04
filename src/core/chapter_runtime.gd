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
	for req in requires(lab_id):
		if not state.is_lab_completed(str(req)):
			return false
	return true

func lab_lock_reason(state: PlayerState, lab_id: String) -> String:
	var lab_data := lab(lab_id)
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

func complete_objective(state: PlayerState, obj_id: String) -> Dictionary:
	if not objectives.has(obj_id):
		return {"ok": false, "error": "目标不存在", "newly": false}
	if state.is_objective_done(obj_id):
		return {"ok": true, "error": "", "newly": false, "all_done": all_done(state)}
	var newly := state.complete_objective(obj_id)
	return {"ok": true, "error": "", "newly": newly, "all_done": all_done(state)}

func all_done(state: PlayerState) -> bool:
	for id in objective_order:
		if not state.is_objective_done(str(id)):
			return false
	return true

func next_objective(state: PlayerState) -> Dictionary:
	for id in objective_order:
		if not state.is_objective_done(str(id)):
			return objectives[str(id)]
	return {}

func progress(state: PlayerState) -> Dictionary:
	var done := 0
	for id in objective_order:
		if state.is_objective_done(str(id)):
			done += 1
	return {"done": done, "total": objective_order.size()}

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
