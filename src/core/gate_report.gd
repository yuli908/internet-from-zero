class_name GateReport
extends RefCounted

## 单次 gate 验收报告。每条用例都要有 id/标题/通过与否/证据，UI 原样展示。
## required 用例全过才算通过；optional 只记录。

var cases: Array = []
var ran_at := 0

func add(id: String, title: String, ok: bool, detail: String = "", required: bool = true) -> void:
	cases.append({"id": id, "title": title, "ok": ok, "detail": detail, "required": required})

func all_required_passed() -> bool:
	for c in cases:
		if bool(c.get("required", true)) and not bool(c.get("ok", false)):
			return false
	return true

func passed_count() -> int:
	var n := 0
	for c in cases:
		if bool(c.get("ok", false)):
			n += 1
	return n

func required_count() -> int:
	var n := 0
	for c in cases:
		if bool(c.get("required", true)):
			n += 1
	return n

func summary() -> String:
	return "gate %d/%d" % [passed_count(), cases.size()]

func to_dict() -> Dictionary:
	return {"ran_at": ran_at, "passed": all_required_passed(), "cases": cases}
