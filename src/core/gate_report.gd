class_name GateReport
extends RefCounted

## 单次 gate 验收报告。每条用例都要有 id/标题/通过与否/证据，UI 原样展示。
## required 用例全过才算通过；optional 只记录。
##
## M5：每条用例额外携带结构化失败回传
## `{code, gate_id, input, expected, actual, error_tags[], attempt}`（见 `GateResult`）。
## 旧字段 `id/title/ok/detail/required` 全部保留，UI 不改也能继续用。

var cases: Array = []
var ran_at := 0

func add(id: String, title: String, ok: bool, detail: String = "", required: bool = true) -> void:
	## 兼容入口：没有精确 code 时，失败按 `E_GENERIC`（兜底 R 标签）记录。
	add_case(GateResult.OK if ok else GateResult.E_GENERIC, id, title, null, null, null, [], detail, required, 0)

func add_case(code: int, gate_id: String, title: String, input: Variant, expected: Variant,
		actual: Variant, tags: Array = [], detail: String = "", required: bool = true, attempt: int = 0) -> void:
	var c := GateResult.normalize(code)
	if GateResult.is_ok(c):
		c = GateResult.OK
	var use_tags: Array = tags.duplicate() if not tags.is_empty() else GateResult.tags_for(c)
	cases.append({
		"id": gate_id,
		"title": title,
		"ok": GateResult.is_ok(c),
		"detail": detail,
		"required": required,
		"code": c,
		"code_name": GateResult.name_of(c),
		"gate_id": gate_id,
		"input": input,
		"expected": expected,
		"actual": actual,
		"error_tags": use_tags,
		"attempt": maxi(0, attempt),
	})

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

func first_failure() -> Dictionary:
	## 提示阶梯读取的第一条失败：已展开成结构化形状；全过时返回 {}。
	for c in cases:
		if not bool(c.get("ok", false)):
			return {
				"code": int(c.get("code", GateResult.E_GENERIC)),
				"code_name": str(c.get("code_name", "E_GENERIC")),
				"gate_id": str(c.get("gate_id", "")),
				"input": c.get("input", null),
				"expected": c.get("expected", null),
				"actual": c.get("actual", null),
				"error_tags": (c.get("error_tags", []) as Array).duplicate(),
				"attempt": int(c.get("attempt", 0)),
			}
	return {}

func failure_codes() -> Array:
	## 机器可判定：失败用例的 code 列表（按出现顺序，可重复）。
	var out := []
	for c in cases:
		if not bool(c.get("ok", false)):
			out.append(int(c.get("code", GateResult.E_GENERIC)))
	return out

func summary() -> String:
	return "gate %d/%d" % [passed_count(), cases.size()]

func to_dict() -> Dictionary:
	return {"ran_at": ran_at, "passed": all_required_passed(), "cases": cases}
