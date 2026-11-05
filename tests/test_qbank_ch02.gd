extends RefCounted

## ch02 练习题库：数据可加载、三件引用不悬空、excerpt 逐字命中课件、选择题唯一答案与
## 干扰项来源、pending gate 零命中、`QuestionBank.score(choice)` 真判分。
## 数据：data/questions/ch02_exercises.json；出处：res://docs/curriculum/13-ch02-lecture-copy.md。

const CHAPTER := "ch02"
const LABS_PATH := "res://data/labs/ch02_labs.json"
const BANK_PATH := "res://data/questions/ch02_exercises.json"
const CURRICULUM := "res://docs/curriculum/13-ch02-lecture-copy.md"
const SECTIONS := ["2.1", "2.2", "2.3", "2.4", "2.5"]
const PENDING_GATES := ["T2.2-3", "T2.4-4"]
const N_ITEMS := 35
const N_CHOICE := 8

const EXPECT := 402
const EXPECT_GROUPS := {
	"loadable": 2, "meta": 4, "section_count": 5, "item_refs": 175,
	"item_shape": 175, "choice": 32, "pending": 3, "scoring": 5, "manifest": 1,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "题库文件可读，QuestionBank 校验零错误",
	"meta": "format/chapter/bank/题量与声明一致",
	"section_count": "每节 7 题（7 × 节数 = 总题量）",
	"item_refs": "逐题 5 项：字段齐全 / lab / gate / order / excerpt 命中课件",
	"item_shape": "逐题 5 项：type / rubric 100 / solutions 3 条 / 题干 ≤100 / common_errors",
	"choice": "选择题 4 项：options 合法、无重复、answer 下标、干扰项来源覆盖",
	"pending": "pending gate 零命中（全库 + 逐条）",
	"scoring": "自动判分：对=100、错=0、形状错=E_RESPONSE、多解题交人工、options_of 一致",
	"manifest": "题库已登记进 data/manifest.json",
}

func run(ctx: TestContext) -> void:
	var bank: Dictionary = TestUtil.read_json(BANK_PATH)
	var qb := QuestionBank.from_doc(bank)
	var labs: Dictionary = TestUtil.read_json(LABS_PATH).get("labs", {}) as Dictionary
	var cur := FileAccess.get_file_as_string(CURRICULUM)

	ctx.begin_group("loadable")
	ctx.check("%s 题库可读" % CHAPTER, not qb.items.is_empty(), BANK_PATH)
	ctx.check("QuestionBank 校验零错误", qb.load_errors.is_empty(), str(qb.load_errors))

	ctx.begin_group("meta")
	ctx.check("format = ifz-questions/1", str(bank.get("format", "")) == QuestionBank.FORMAT)
	ctx.check("chapter 一致", str(bank.get("chapter", "")) == CHAPTER)
	ctx.check("bank = exercises", str(bank.get("bank", "")) == "exercises")
	ctx.check("题量 %d" % N_ITEMS, qb.items.size() == N_ITEMS, str(qb.items.size()))

	ctx.begin_group("section_count")
	for s in SECTIONS:
		var n := 0
		for raw_it in qb.items:
			if str((raw_it as Dictionary).get("section", "")) == s:
				n += 1
		ctx.check("节 %s 题量 = 7" % s, n == 7, str(n))

	ctx.begin_group("item_refs")
	for raw_it in qb.items:
		_check_item_refs(ctx, raw_it as Dictionary, labs, cur)

	ctx.begin_group("item_shape")
	for raw_it in qb.items:
		_check_item_shape(ctx, raw_it as Dictionary)

	ctx.begin_group("choice")
	for raw_it in qb.items:
		var it: Dictionary = raw_it as Dictionary
		if it.has("options"):
			_check_choice(ctx, it)

	ctx.begin_group("pending")
	var used := []
	for raw_it in qb.items:
		if PENDING_GATES.has(str((raw_it as Dictionary).get("gate", ""))):
			used.append(str((raw_it as Dictionary).get("id", "")))
	ctx.check("无题挂 pending gate", used.is_empty(), str(used))
	for pid in PENDING_GATES:
		var hits := 0
		for raw_it in qb.items:
			if str((raw_it as Dictionary).get("gate", "")) == pid:
				hits += 1
		ctx.check("%s 零命中" % pid, hits == 0, str(hits))

	ctx.begin_group("scoring")
	var cq: Dictionary = _first_choice(qb)
	var ans := int(cq.get("answer", -1))
	var wrong := -1
	if not cq.is_empty():
		var opts: Array = (cq.get("options", []) as Array)
		for i in opts.size():
			if i != ans:
				wrong = i
				break
	var r_ok: Dictionary = qb.score(str(cq.get("id", "")), {"choice": ans}) if not cq.is_empty() else {}
	var r_bad: Dictionary = qb.score(str(cq.get("id", "")), {"choice": wrong}) if not cq.is_empty() else {}
	var r_shape: Dictionary = qb.score(str(cq.get("id", "")), {"choice": "x"}) if not cq.is_empty() else {}
	var manual_id := _first_manual(qb)
	var r_manual: Dictionary = qb.score(manual_id, {"text": "手写答案"})
	ctx.check("选择题正确项判 100", int(r_ok.get("score", -1)) == 100, str(r_ok))
	ctx.check("选择题错误项判 0", bool(r_bad.get("ok", false)) and int(r_bad.get("score", -1)) == 0, str(r_bad))
	ctx.check("choice 形状错 -> E_RESPONSE", str(r_shape.get("error_code", "")) == "E_RESPONSE", str(r_shape))
	ctx.check("多解题不回自动分", bool(r_manual.get("manual", false)) and int(r_manual.get("score", -1)) == 0, str(r_manual))
	var opts_same: Array = qb.options_of(str(cq.get("id", "")))
	ctx.check("options_of 与数据一致", not cq.is_empty() and opts_same == (cq.get("options", []) as Array), str(opts_same.size()))

	ctx.begin_group("manifest")
	var files: Array = TestUtil.read_json("res://data/manifest.json").get("files", []) as Array
	ctx.check("manifest 已登记题库", files.has(BANK_PATH), BANK_PATH)


func _check_item_refs(ctx: TestContext, it: Dictionary, labs: Dictionary, cur: String) -> void:
	var tag := str(it.get("id", "?"))
	var need := ["id", "section", "lab", "gate", "order", "concept", "source_excerpt",
		"type", "stem", "solutions", "rubric", "common_errors", "hints"]
	var missing := []
	for k in need:
		if not it.has(k):
			missing.append(k)
	ctx.check("%s 字段齐全" % tag, missing.is_empty(), str(missing))

	var lid := str(it.get("lab", ""))
	var lab: Dictionary = labs.get(lid, {}) as Dictionary
	ctx.check("%s lab 非悬空" % tag, not lab.is_empty(), lid)

	var gate := str(it.get("gate", ""))
	var gate_ok := false
	for raw_g in (lab.get("gate_cases", []) as Array):
		var g: Dictionary = raw_g as Dictionary
		if str(g.get("id", "")) == gate:
			gate_ok = not (str(g.get("status", "")) == "pending" or g.has("pending_reason"))
	ctx.check("%s gate 非悬空且非 pending" % tag, gate_ok, gate)

	var order_v: Variant = it.get("order", null)
	var order_ok := false
	if not lab.is_empty() and (order_v is int or order_v is float):
		var n_seg := (lab.get("sections", []) as Array).size()
		order_ok = int(order_v) >= 1 and int(order_v) <= n_seg
	ctx.check("%s order 在 1..段数" % tag, order_ok, str(order_v))

	var exc := str(it.get("source_excerpt", ""))
	ctx.check("%s excerpt 逐字命中课件" % tag, not exc.is_empty() and cur.contains(exc), exc)


func _check_item_shape(ctx: TestContext, it: Dictionary) -> void:
	var tag := str(it.get("id", "?"))
	ctx.check("%s type 合法" % tag, QuestionBank.TYPES.has(str(it.get("type", ""))), str(it.get("type", "")))

	var total := 0
	var dim_ok := true
	for raw_r in (it.get("rubric", []) as Array):
		var r: Dictionary = raw_r as Dictionary
		total += int(r.get("weight", 0))
		if str(r.get("dim", "")).strip_edges().is_empty():
			dim_ok = false
	ctx.check("%s rubric 权重和 100" % tag, total == 100 and dim_ok, str(total))

	var sols: Array = (it.get("solutions", []) as Array)
	var sol_ok := sols.size() == 3
	for raw_s in sols:
		var s: Dictionary = raw_s as Dictionary
		if str(s.get("label", "")).strip_edges().is_empty() or str(s.get("approach", "")).strip_edges().is_empty():
			sol_ok = false
	ctx.check("%s solutions 恰 3 条且完整" % tag, sol_ok, str(sols.size()))

	var stem := str(it.get("stem", ""))
	var stem_len := stem.replace(" ", "").length()
	ctx.check("%s 题干 ≤100 字" % tag, not stem.strip_edges().is_empty() and stem_len <= 100, str(stem_len))

	var ce: Array = (it.get("common_errors", []) as Array)
	ctx.check("%s common_errors 非空" % tag, ce.size() >= 1, str(ce.size()))


func _check_choice(ctx: TestContext, it: Dictionary) -> void:
	var tag := str(it.get("id", "?"))
	var opts: Array = (it.get("options", []) as Array)
	var texts := {}
	var opt_ok := opts.size() >= 3
	for raw_o in opts:
		var t := str(raw_o).strip_edges()
		if t.is_empty() or texts.has(t):
			opt_ok = false
		texts[t] = true
	ctx.check("%s options ≥3 且无空项" % tag, opt_ok, str(opts.size()))

	ctx.check("%s options 无重复项" % tag, texts.size() == opts.size(), str(texts.size()))

	var ans_v: Variant = it.get("answer", null)
	var ans_ok := false
	if ans_v is int or ans_v is float:
		ans_ok = int(ans_v) >= 0 and int(ans_v) < opts.size()
	ctx.check("%s answer 下标合法" % tag, ans_ok, str(ans_v))

	var ans := int(ans_v) if (ans_v is int or ans_v is float) else -1
	var covered := {}
	var notes_ok := true
	for raw_n in (it.get("distractor_notes", []) as Array):
		var n: Dictionary = raw_n as Dictionary
		var idx_v: Variant = n.get("index", null)
		if not (idx_v is int or idx_v is float):
			notes_ok = false
			continue
		var idx := int(idx_v)
		if idx == ans or idx < 0 or idx >= opts.size() or covered.has(idx):
			notes_ok = false
		covered[idx] = true
		if not QuestionBank.DISTRACTOR_KINDS.has(str(n.get("kind", ""))):
			notes_ok = false
		if str(n.get("why", "")).strip_edges().is_empty():
			notes_ok = false
	for i in opts.size():
		if i != ans and not covered.has(i):
			notes_ok = false
	ctx.check("%s 干扰项来源覆盖全部错误项" % tag, notes_ok, str(covered.size()))


func _first_choice(qb: QuestionBank) -> Dictionary:
	for raw_it in qb.items:
		var it: Dictionary = raw_it as Dictionary
		if it.has("options") and it.has("answer"):
			return it
	return {}


func _first_manual(qb: QuestionBank) -> String:
	for raw_it in qb.items:
		var it: Dictionary = raw_it as Dictionary
		if not it.has("answer") and not it.has("answer_value"):
			return str(it.get("id", ""))
	return ""
