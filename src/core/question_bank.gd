class_name QuestionBank
extends RefCounted

## M4 · 题库接入接口（只做加载 / 字段校验 / 评分入口；**不含任何题目数据**）。
## 数据格式 `ifz-questions/1`，路径 `data/questions/<chapter>_<bank>.json`。
## 条数不写死：42 = 第一章练习（docs/curriculum/03 §2），12/章 = 小测（06 §2），是两份不同 bank。
## 评分确定性：不引入时间、随机与字典迭代序；浮点比较只用题目自带 `tol`。

const FORMAT := "ifz-questions/1"
const BANKS := ["exercises", "quiz"]
const TYPES := ["understanding", "compute", "build", "debug", "open", "memory"]
## docs/curriculum/06 §3 的错因码（C1–C9），只做常量与校验。
const ERROR_CODES := ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9"]

var doc: Dictionary = {}
var items: Array = []
var by_id: Dictionary = {}
var load_errors: Array = []

static func from_doc(p_doc: Dictionary) -> QuestionBank:
	var q := QuestionBank.new()
	q.doc = p_doc.duplicate(true)
	var raw_items: Variant = p_doc.get("items", [])
	q.items = (raw_items as Array).duplicate(true) if raw_items is Array else []
	for raw in q.items:
		if not (raw is Dictionary):
			continue
		var it: Dictionary = raw
		var id := str(it.get("id", ""))
		if id.is_empty() or q.by_id.has(id):
			continue
		q.by_id[id] = it
	q.load_errors = q.validate()
	return q

func validate() -> Array:
	## 返回错误串数组；空数组 = 通过。顺序固定（按文档顺序），便于日志比对。
	var errs: Array = []
	if str(doc.get("format", "")) != FORMAT:
		errs.append("format 必须是 %s，实际 %s" % [FORMAT, str(doc.get("format", ""))])
	if str(doc.get("chapter", "")).is_empty():
		errs.append("缺少 chapter")
	if not BANKS.has(str(doc.get("bank", ""))):
		errs.append("bank 必须是 exercises/quiz，实际 %s" % str(doc.get("bank", "")))
	if not (doc.get("items", null) is Array):
		errs.append("items 必须是数组")
	var seen := {}
	for i in items.size():
		var raw: Variant = items[i]
		if not (raw is Dictionary):
			errs.append("题目 #%d 不是对象" % i)
			continue
		var it: Dictionary = raw
		var id := str(it.get("id", ""))
		var tag := id if not id.is_empty() else "#%d" % i
		if id.is_empty():
			errs.append("题目 #%d 缺少 id" % i)
		elif seen.has(id):
			errs.append("题目 id 重复：%s" % id)
		else:
			seen[id] = true
		if str(it.get("stem", "")).is_empty():
			errs.append("题目 %s 缺少 stem" % tag)
		var typ := str(it.get("type", ""))
		if not TYPES.has(typ):
			errs.append("题目 %s 的 type 非法：%s" % [tag, typ])
		var sols: Variant = it.get("solutions", [])
		if not (sols is Array) or (sols as Array).size() < 2:
			errs.append("题目 %s 的 solutions < 2" % tag)
		var rubric: Variant = it.get("rubric", [])
		var total := 0
		var has_correct := false
		if rubric is Array:
			for raw_r in (rubric as Array):
				if not (raw_r is Dictionary):
					continue
				var r: Dictionary = raw_r
				total += int(r.get("weight", 0))
				if str(r.get("dim", "")).contains("正确"):
					has_correct = true
		if total != 100:
			errs.append("题目 %s 的 rubric 权重和 = %d ≠ 100" % [tag, total])
		if typ == "build" and not has_correct:
			errs.append("搭建题 %s 的 rubric 缺'正确性'维" % tag)
		if it.has("answer"):
			var ct := typeof(it["answer"])
			if ct != TYPE_INT and ct != TYPE_FLOAT:
				errs.append("题目 %s 的 answer 必须是 int（选项下标）" % tag)
			elif int(it["answer"]) < 0:
				errs.append("题目 %s 的 answer 不能为负" % tag)
		if it.has("answer_value"):
			var at := typeof(it["answer_value"])
			if at != TYPE_INT and at != TYPE_FLOAT:
				errs.append("题目 %s 的 answer_value 必须是数值" % tag)
			if not it.has("tol") or float(it.get("tol", -1.0)) < 0.0:
				errs.append("题目 %s 有 answer_value 时必须带非负 tol" % tag)
	return errs

func item(id: String) -> Dictionary:
	var it: Dictionary = by_id.get(id, {})
	return it.duplicate(true)

func has(id: String) -> bool:
	return by_id.has(id)

func score(id: String, response: Dictionary) -> Dictionary:
	## 统一返回 {ok, score, max, detail, error_code}；主观/搭建题 `manual=true`，不自动编分。
	## `response` 形状：`{"choice": int}` / `{"text": str}` / `{"graph": Variant}` / `{"value": float}`。
	if not by_id.has(id):
		return _res(false, 0, "未知题目 %s" % id, "E_UNKNOWN_ITEM")
	var it: Dictionary = by_id[id]
	if not it.has("answer") and not it.has("answer_value"):
		return {
			"ok": true, "score": 0, "max": 100, "error_code": "", "manual": true,
			"detail": "题目 %s 无自动判分字段，交人工 rubric" % id,
		}
	if it.has("answer"):
		if not response.has("choice") or typeof(response["choice"]) != TYPE_INT:
			return _res(false, 0, "response 需要 choice:int", "E_RESPONSE")
		var correct := int(response["choice"]) == int(it["answer"])
		return {
			"ok": true, "score": 100 if correct else 0, "max": 100, "error_code": "",
			"manual": false, "correct": correct,
			"detail": "选项 %d（期望 %d）" % [int(response["choice"]), int(it["answer"])],
		}
	var v: Variant = response.get("value", null)
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return _res(false, 0, "response 需要 value:number", "E_RESPONSE")
	var tol := float(it.get("tol", 0.0))
	var ok_num := absf(float(v) - float(it["answer_value"])) <= tol
	return {
		"ok": true, "score": 100 if ok_num else 0, "max": 100, "error_code": "",
		"manual": false, "correct": ok_num,
		"detail": "%.6f（期望 %.6f，tol %.6f）" % [float(v), float(it["answer_value"]), tol],
	}

static func error_codes() -> Array:
	return ERROR_CODES.duplicate()

static func _res(ok: bool, score_v: int, detail: String, code: String) -> Dictionary:
	return {"ok": ok, "score": score_v, "max": 100, "detail": detail, "error_code": code}
