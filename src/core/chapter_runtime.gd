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

func lab_unlocked(state: PlayerState, lab_id: String) -> bool:
	var lab_data := lab(lab_id)
	if lab_data.is_empty():
		return false
	var req := _opt_string(lab_data, "requires")
	if req.is_empty():
		return true
	return state.is_lab_completed(req)

func lab_lock_reason(state: PlayerState, lab_id: String) -> String:
	var lab_data := lab(lab_id)
	var req := _opt_string(lab_data, "requires")
	if req.is_empty() or state.is_lab_completed(req):
		return ""
	return "需要先完成「%s」" % str(lab(req).get("title", req))

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
		var req := _opt_string(lab_data, "requires")
		if not req.is_empty() and not labs.has(req):
			errs.append("实验 %s 的前置实验 %s 不存在" % [lab_id, req])
		if not str(lab_data.get("knowledge", "")).is_empty() and not lab_data.has("knowledge"):
			errs.append("实验 %s 缺少知识节点" % lab_id)
	return errs
