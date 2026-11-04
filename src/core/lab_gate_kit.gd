class_name LabGateKit
extends RefCounted

## CH05 / CH06 判据公共工具：只做「取玩家作答 / 发射用例 / 解析分母」三件事，
## 不含任何 kind 语义（各章语义在 `ch05_checks.gd` / `ch06_checks.gd`）。
##
## 分母口径沿用 `Ch02Checks.deferred_gates`：
##   1) 整节 `content_status` 非 ready → required 全部不进分母；
##   2) 单条 gate 的 `content_status` / `status` 非 ready → 该条不进分母；
##   3) 缺省 ready，ready 后自动回到分母，无需迁移存档。

## 失败 code 白名单（17 号 §0）：只允许这些已存在码，28 已撤销、26 只属 3.4。
const ALLOWED_CODES := [3, 5, 7, 8, 9, 10, 13, 14, 15, 27]

static var _status_cache := {}

static func answer(answers: Dictionary, cid: String) -> Variant:
	if answers.has(cid):
		return answers[cid]
	return answers.get("default", null)

static func answer_dict(answers: Dictionary, cid: String) -> Dictionary:
	var v: Variant = answer(answers, cid)
	return v if v is Dictionary else {}

static func answer_list(answers: Dictionary, cid: String) -> Array:
	var v: Variant = answer(answers, cid)
	return v if v is Array else []

static func emit(rep: GateReport, tracker: GateAttemptTracker, code: int, c: Dictionary, ok: bool,
		input: Variant, expected: Variant, actual: Variant, detail: String) -> void:
	var cid := str(c.get("id", ""))
	var title := str(c.get("title", ""))
	var required := bool(c.get("required", true))
	var attempt := tracker.record(cid, ok) if tracker != null else 0
	var use_code := GateResult.OK if ok else code
	rep.add_case(use_code, cid, title, input, expected, actual, [], detail, required, attempt)

static func judge_quiz(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var quiz: Dictionary = c.get("quiz", {})
	var want := int(quiz.get("answer", -1))
	var got := -1
	var raw: Variant = answer(answers, str(c.get("id", "")))
	if raw != null and (typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT):
		got = int(raw)
	var ok := want >= 0 and got == want
	emit(rep, tracker, GateResult.E_QUIZ, c, ok, {"answer": got}, want, got,
		"作答 %d，期望 %d" % [got, want])

static func add_pending(rep: GateReport, c: Dictionary, reason: String) -> void:
	rep.add_case(GateResult.E_PENDING, str(c.get("id", "")), str(c.get("title", "")),
		{"kind": str(c.get("kind", ""))}, "仿真层支持", "pending", [], "pending：" + reason, false, 0)

static func deferred_gates(cfg: Dictionary, levels_path: String) -> Dictionary:
	var ids := []
	var all_ids := []
	var total := 0
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		if not bool(c.get("required", true)):
			continue
		total += 1
		var cid := str(c.get("id", ""))
		all_ids.append(cid)
		if _gate_status(c) != "ready":
			ids.append(cid)
	if _lab_status(cfg, levels_path) != "ready":
		return {"total": total, "counted": 0, "deferred": total,
			"ids": all_ids, "section_deferred": true}
	return {"total": total, "counted": total - ids.size(), "deferred": ids.size(),
		"ids": ids, "section_deferred": false}

static func _gate_status(c: Dictionary) -> String:
	if c.has("content_status"):
		return str(c["content_status"])
	if c.has("status"):
		return "ready" if str(c["status"]) == "ready" else str(c["status"])
	return "ready"

static func _lab_status(cfg: Dictionary, levels_path: String) -> String:
	if cfg.has("content_status"):
		return str(cfg["content_status"])
	var lid := str(cfg.get("id", ""))
	if lid.is_empty():
		return "ready"
	if not _status_cache.has(levels_path):
		_status_cache[levels_path] = _load_statuses(levels_path)
	return str((_status_cache[levels_path] as Dictionary).get(lid, "ready"))

static func _load_statuses(levels_path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(levels_path):
		return out
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(levels_path))
	if doc is Dictionary:
		for raw in (doc.get("labs", []) as Array):
			if raw is Dictionary:
				out[str(raw.get("id", ""))] = str(raw.get("content_status", "ready"))
	return out
