extends RefCounted

## CH14 结构 + 判据校验（15 段）。
## 分母口径：required 且非 pending 的 gate 数，按 Ch14Checks.deferred_gates(cfg) 现算；
## 14.2 类型标签存放位置未定 → 4 降为 3，测试里单独断言 pending 条数与分母。
## 负例断言给出精确失败码；断言能红，不是恒真。

const LABS := ["interpreter_eval", "dynamic_type", "script_automation"]
const TOTAL_SECTIONS := 15
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260
const GATE_IDS := {"interpreter_eval": ["T14.1-1", "T14.1-2", "T14.1-3", "T14.1-4"], "dynamic_type": ["T14.2-1", "T14.2-2", "T14.2-3", "T14.2-4"], "script_automation": ["T14.3-1", "T14.3-2", "T14.3-3", "T14.3-4"]}
const GATE_KINDS := {"interpreter_eval": ["table", "skip_layer", "derived_number", "quiz"], "dynamic_type": ["table", "skip_layer", "derived_number", "quiz"], "script_automation": ["table", "skip_layer", "derived_number", "quiz"]}
const ALLOWED_KINDS := ["table", "coverage", "port_map", "page_map", "checksum",
	"derived_number", "handshake_fsm", "timeout_idle", "skip_layer", "quiz"]

const Ch14Checks = preload("res://src/core/ch14_checks.gd")
const MiniInterp = preload("res://src/core/mini_interp.gd")

const EXPECT := 59
const EXPECT_GROUPS := {"loadable": 1, "sections_present": 3, "section_count": 3, "order": 3, "text_nonempty": 3, "text_cap": 3, "screen_sum": 3, "last_after": 3, "practice": 3, "gate_count": 3, "p1_field": 3, "gate_ids": 3, "gate_kinds": 3, "gate_codes": 3, "denominator": 3, "pending_total": 1, "total_sections": 1, "positive": 3, "t14_1_real": 3, "negative": 8}
const GROUP_DESCRIPTIONS := {"loadable": "ch14_labs 数据文件可读", "sections_present": "每 lab 必有非空 sections", "section_count": "每 lab 段数为 5", "order": "每 lab 内 order 连续 1..5", "text_nonempty": "每段 text 非空", "text_cap": "每段 ≤150 字（去半角空格）", "screen_sum": "同一 after 档同屏合计 ≤260", "last_after": "末段 after=3", "practice": "每节实践表 4 行且字段齐全", "gate_count": "每节 4 条 gate", "p1_field": "每节有 P1 文本与 p1_gates", "gate_ids": "gate id 按 T14.x-n 定稿", "gate_kinds": "只用既有 kind（table/skip_layer/derived_number/quiz）", "gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28", "denominator": "进分母 gate 数按 deferred_gates 现算（dynamic_type 为 3，因 T14.2-1 pending）", "pending_total": "全章 pending 条数=1，且进分母计数=11", "total_sections": "全篇段数 15", "positive": "3 节好答案全绿（pending 不计，T14.1-1 由真解释器作答）", "t14_1_real": "T14.1-1 tokens/AST/value 由 mini_interp 实跑导出，逐段与数据期望一致", "negative": "错值/缺件/负例未复现/复算错/quiz 错/缺 rows/token 改坏/token 删除 均精确判红"}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch14_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch14_labs 可读", not labs.is_empty(), str(labs.size()))

	var total := 0
	var pending_sum := 0
	var counted_sum := 0
	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var secs: Array = cfg.get("sections", [])
		ctx.begin_group("sections_present")
		ctx.check("%s 有 sections" % id, not secs.is_empty(), str(secs.size()))
		ctx.begin_group("section_count")
		ctx.eq("%s 段数" % id, secs.size(), 5)
		ctx.begin_group("order")
		ctx.check("%s order 连续" % id, _orders_ok(secs), _orders(secs))
		ctx.begin_group("text_nonempty")
		ctx.check("%s 每段非空" % id, _all_nonempty(secs), "")
		ctx.begin_group("text_cap")
		ctx.check("%s 单段 ≤150" % id, _max_len(secs) <= LEFT_LIMIT, str(_max_len(secs)))
		ctx.begin_group("screen_sum")
		ctx.check("%s 同屏 ≤260" % id, _max_screen(secs) <= SCREEN_LIMIT, str(_max_screen(secs)))
		ctx.begin_group("last_after")
		ctx.eq("%s 末段 after" % id, int((secs[secs.size() - 1] as Dictionary).get("after", -1)), 3)
		ctx.begin_group("practice")
		ctx.check("%s 实践表 4 行齐全" % id, _practice_ok(cfg), str((cfg.get("practice", []) as Array).size()))
		ctx.begin_group("gate_count")
		ctx.eq("%s gate 条数" % id, (cfg.get("gate_cases", []) as Array).size(), 4)
		ctx.begin_group("p1_field")
		ctx.check("%s 有 P1 文本与 p1_gates" % id,
			not str(cfg.get("p1", "")).strip_edges().is_empty() and not (cfg.get("p1_gates", []) as Array).is_empty(),
			str(cfg.get("p1_gates", [])))
		ctx.begin_group("gate_ids")
		ctx.check("%s gate id 与提案一致" % id, _gate_ids(cfg) == str(GATE_IDS[id]), _gate_ids(cfg))
		ctx.begin_group("gate_kinds")
		ctx.check("%s kind 全是既有 kind" % id, _kinds_ok(cfg, id), _gate_kinds(cfg))
		ctx.begin_group("gate_codes")
		ctx.check("%s 失败码在白名单" % id, _codes_ok(cfg), "")
		ctx.begin_group("denominator")
		var d: Dictionary = Ch14Checks.deferred_gates(cfg)
		var pending := _pending_count(cfg)
		ctx.eq("%s 进分母（4 条 gate 去 %d pending）" % [id, pending],
			int(d["counted"]), 4 - pending)
		pending_sum += pending
		counted_sum += int(d["counted"])
		total += secs.size()
	ctx.begin_group("pending_total")
	ctx.check("全章 pending=1、进分母=11", pending_sum == 1 and counted_sum == 11,
		"pending=%d counted=%d" % [pending_sum, counted_sum])

	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var r: Dictionary = Ch14Checks.run(id, cfg, {"answers": _good(cfg)})
		ctx.begin_group("positive")
		ctx.check("%s 好答案全绿（pending=%d）" % [id, (r["pending"] as Array).size()],
			bool(r["ok"]), str(r["report"].first_failure()))

	_t14_1_real(ctx, labs["interpreter_eval"])

	_negative(ctx, labs)

func _orders(secs: Array) -> String:
	var out := []
	for s in secs:
		out.append(int((s as Dictionary).get("order", -1)))
	return str(out)

func _orders_ok(secs: Array) -> bool:
	for i in secs.size():
		if int((secs[i] as Dictionary).get("order", -1)) != i + 1:
			return false
	return true

func _all_nonempty(secs: Array) -> bool:
	for s in secs:
		if str((s as Dictionary).get("text", "")).strip_edges().is_empty():
			return false
	return true

func _max_len(secs: Array) -> int:
	var m := 0
	for s in secs:
		m = maxi(m, str((s as Dictionary).get("text", "")).replace(" ", "").length())
	return m

func _max_screen(secs: Array) -> int:
	var screen := {}
	for s in secs:
		var after := int((s as Dictionary).get("after", -1))
		screen[after] = int(screen.get(after, 0)) \
			+ str((s as Dictionary).get("text", "")).replace(" ", "").length()
	var m := 0
	for k in screen:
		m = maxi(m, int(screen[k]))
	return m

func _practice_ok(cfg: Dictionary) -> bool:
	var p: Array = cfg.get("practice", [])
	if p.size() != 4:
		return false
	for raw in p:
		var row: Dictionary = raw
		for key in ["id", "level", "produce", "judge"]:
			if str(row.get(key, "")).strip_edges().is_empty():
				return false
	return true

func _gate_ids(cfg: Dictionary) -> String:
	var out := []
	for raw in (cfg.get("gate_cases", []) as Array):
		out.append(str((raw as Dictionary).get("id", "")))
	return str(out)

func _gate_kinds(cfg: Dictionary) -> String:
	var out := []
	for raw in (cfg.get("gate_cases", []) as Array):
		out.append(str((raw as Dictionary).get("kind", "")))
	return str(out)

func _kinds_ok(cfg: Dictionary, id: String) -> bool:
	var kinds := []
	for raw in (cfg.get("gate_cases", []) as Array):
		var k := str((raw as Dictionary).get("kind", ""))
		if not ALLOWED_KINDS.has(k):
			return false
		kinds.append(k)
	return kinds == GATE_KINDS[id]

func _codes_ok(cfg: Dictionary) -> bool:
	var codes := []
	for raw in (cfg.get("gate_cases", []) as Array):
		for code in (raw as Dictionary).get("codes", []):
			codes.append(str(code))
	for raw in (cfg.get("practice", []) as Array):
		for code in (raw as Dictionary).get("codes", []):
			codes.append(str(code))
	for s in codes:
		var num := _code_num(s)
		if num < 0 or not LabGateKit.ALLOWED_CODES.has(num):
			return false
	return true

func _code_num(s: String) -> int:
	var a := s.find("(")
	var b := s.find(")")
	if a < 0 or b <= a:
		return -1
	return int(s.substr(a + 1, b - a - 1))

func _pending_count(cfg: Dictionary) -> int:
	var n := 0
	for raw in (cfg.get("gate_cases", []) as Array):
		var g: Dictionary = raw
		if str(g.get("content_status", g.get("status", "ready"))) != "ready":
			n += 1
	return n

## 好答案由数据侧定稿现建：table 抄 expect_rows/meta，skip 复现缺层，
## derived 抄 expect_values，quiz 取 answer。T14.1-1 例外：由 mini_interp 实跑三段，
## 不抄 expect_rows（token 序列/AST/值必须是跑出来的）。
func _good(cfg: Dictionary) -> Dictionary:
	var out := {}
	for raw in (cfg.get("gate_cases", []) as Array):
		var g: Dictionary = raw
		if str(g.get("content_status", g.get("status", "ready"))) != "ready":
			continue
		var cid := str(g.get("id", ""))
		match str(g.get("kind", "")):
			"table":
				out[cid] = {"rows": (g.get("expect_rows", []) as Array).duplicate(true),
					"meta": (g.get("expect_meta", {}) as Dictionary).duplicate(true)}
			"skip_layer":
				var st := str(g.get("stage", ""))
				out[cid] = {"stages": [st, "downstream"], "missing": st, "downstream_ok": false}
			"derived_number":
				out[cid] = {"values": (g.get("expect_values", {}) as Dictionary).duplicate(true)}
			"quiz":
				out[cid] = int((g.get("quiz", {}) as Dictionary).get("answer", 0))
		var sources: Dictionary = cfg.get("case_sources", {})
		if sources.is_empty():
			continue
		var rows: Array = []
		for k in ["fib5", "fib6", "list"]:
			var toks: Array = MiniInterp.lex(str(sources.get(k, "")))
			var ast: Dictionary = MiniInterp.parse(toks)
			rows.append({
				"case": k,
				"tokens": toks,
				"ast": ast,
				"value": int(MiniInterp.eval(ast)),
				"stages_exported": ["tokens", "ast", "value"],
			})
		out["T14.1-1"] = {"rows": rows, "meta": {"p05_grant": true}}
	return out

func _gate(cfg: Dictionary, cid: String) -> Dictionary:
	for raw in (cfg.get("gate_cases", []) as Array):
		if str((raw as Dictionary).get("id", "")) == cid:
			return raw
	return {}

## 真判据：三案源码逐段实跑，tokens 逐条、AST 逐层、value 逐个与数据期望比。
func _t14_1_real(ctx: TestContext, cfg: Dictionary) -> void:
	ctx.begin_group("t14_1_real")
	var sources: Dictionary = cfg.get("case_sources", {})
	var g: Dictionary = _gate(cfg, "T14.1-1")
	var want_rows: Array = g.get("expect_rows", [])
	var tok_ok := true
	var ast_ok := true
	var val_ok := true
	var tok_total := 0
	for i in want_rows.size():
		var src := str(sources.get(str((want_rows[i] as Dictionary).get("case", "")), ""))
		var toks: Array = MiniInterp.lex(src)
		var ast: Dictionary = MiniInterp.parse(toks)
		tok_total += toks.size()
		tok_ok = tok_ok and _deep_eq(toks, (want_rows[i] as Dictionary).get("tokens", []))
		ast_ok = ast_ok and _deep_eq(ast, (want_rows[i] as Dictionary).get("ast", {}))
		val_ok = val_ok and int(MiniInterp.eval(ast)) == int((want_rows[i] as Dictionary).get("value", -1))
	ctx.check("T14.1-1 token 序列实导并逐条一致（%d 条）" % tok_total, tok_ok, str(sources))
	ctx.check("T14.1-1 AST 实建并逐层一致（三案）", ast_ok, "")
	ctx.check("T14.1-1 求值实算 5/8/6", val_ok, "")

func _deep_eq(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _deep_eq((a as Array)[i], (b as Array)[i]):
				return false
		return true
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in (a as Dictionary):
			if not (b as Dictionary).has(k) or not _deep_eq((a as Dictionary)[k], (b as Dictionary)[k]):
				return false
		return true
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) \
			and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return absf(float(a) - float(b)) < 1e-9
	return str(a) == str(b)

func _code(report: GateReport, cid: String) -> int:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return -1

func _negative(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("negative")
	var a1 := _good(labs["interpreter_eval"])
	var g1: Dictionary = a1["T14.1-1"]
	var rows1: Array = (g1["rows"] as Array).duplicate(true)
	rows1[0]["value"] = 6
	g1["rows"] = rows1
	var r1: Dictionary = Ch14Checks.run("interpreter_eval", labs["interpreter_eval"], {"answers": a1})
	var c1: int = _code(r1["report"], "T14.1-1")
	print("RED-PROBE CH14 T14.1-1 T14.1-1 求值结果错 -> code=%d" % c1)
	ctx.eq("T14.1-1 求值结果错判红 E_TABLE_CELL(7)", c1, GateResult.E_TABLE_CELL)

	var a2 := _good(labs["interpreter_eval"])
	a2["T14.1-2"] = {"stages": ["eval"], "missing": "eval", "downstream_ok": true}
	var r2: Dictionary = Ch14Checks.run("interpreter_eval", labs["interpreter_eval"], {"answers": a2})
	var c2: int = _code(r2["report"], "T14.1-2")
	print("RED-PROBE CH14 T14.1-2 T14.1-2 负例未复现(求值未接却结果正常) -> code=%d" % c2)
	ctx.eq("T14.1-2 负例未复现(求值未接却结果正常)判红 E_OUTPUT_MISMATCH(10)", c2, GateResult.E_OUTPUT_MISMATCH)

	var a3 := _good(labs["interpreter_eval"])
	var g3: Dictionary = a3["T14.1-1"]
	var rows3: Array = (g3["rows"] as Array).duplicate(true)
	g3["rows"] = rows3.slice(0, 2)
	var r3: Dictionary = Ch14Checks.run("interpreter_eval", labs["interpreter_eval"], {"answers": a3})
	var c3: int = _code(r3["report"], "T14.1-1")
	print("RED-PROBE CH14 T14.1-1 T14.1-1 只交 2/3 行 -> code=%d" % c3)
	ctx.eq("T14.1-1 只交 2/3 行判红 E_COVERAGE(13)", c3, GateResult.E_COVERAGE)

	var a4 := _good(labs["interpreter_eval"])
	var g4: Dictionary = a4["T14.1-3"]
	var v4: Dictionary = (g4["values"] as Dictionary).duplicate(true)
	v4["fib6"] = 9
	g4["values"] = v4
	var r4: Dictionary = Ch14Checks.run("interpreter_eval", labs["interpreter_eval"], {"answers": a4})
	var c4: int = _code(r4["report"], "T14.1-3")
	print("RED-PROBE CH14 T14.1-3 T14.1-3 fib(6) 复算错 -> code=%d" % c4)
	ctx.eq("T14.1-3 fib(6) 复算错判红 E_TABLE_CELL(7)", c4, GateResult.E_TABLE_CELL)

	var a5 := _good(labs["interpreter_eval"])
	a5["T14.1-4"] = 2
	var r5: Dictionary = Ch14Checks.run("interpreter_eval", labs["interpreter_eval"], {"answers": a5})
	var c5: int = _code(r5["report"], "T14.1-4")
	print("RED-PROBE CH14 T14.1-4 T14.1-4 选错项 -> code=%d" % c5)
	ctx.eq("T14.1-4 选错项判红 E_QUIZ(14)", c5, GateResult.E_QUIZ)

	var a6 := _good(labs["script_automation"])
	a6["T14.3-1"] = {}
	var r6: Dictionary = Ch14Checks.run("script_automation", labs["script_automation"], {"answers": a6})
	var c6: int = _code(r6["report"], "T14.3-1")
	print("RED-PROBE CH14 T14.3-1 T14.3-1 缺 rows -> code=%d" % c6)
	ctx.eq("T14.3-1 缺 rows 判红 E_UNCONNECTED(3)", c6, GateResult.E_UNCONNECTED)

	# 能红证据①：改坏 fib5 第 3 个 token 的字面量（5→9）。
	var a7 := _good(labs["interpreter_eval"])
	var rows7: Array = (a7["T14.1-1"]["rows"] as Array)
	(rows7[0]["tokens"] as Array)[2]["text"] = "9"
	var r7: Dictionary = Ch14Checks.run("interpreter_eval", labs["interpreter_eval"], {"answers": a7})
	var c7: int = _code(r7["report"], "T14.1-1")
	print("RED-PROBE CH14 T14.1-1 T14.1-1 token 字面量改坏(5→9) -> code=%d" % c7)
	ctx.eq("T14.1-1 token 改坏判红 E_TABLE_CELL(7)", c7, GateResult.E_TABLE_CELL)

	# 能红证据②：删掉一个 token（i=1 的左括号），序列不再逐条对齐。
	var a8 := _good(labs["interpreter_eval"])
	((a8["T14.1-1"]["rows"] as Array)[0]["tokens"] as Array).remove_at(1)
	var r8: Dictionary = Ch14Checks.run("interpreter_eval", labs["interpreter_eval"], {"answers": a8})
	var c8: int = _code(r8["report"], "T14.1-1")
	print("RED-PROBE CH14 T14.1-1 T14.1-1 删一个 token(i=1) -> code=%d" % c8)
	ctx.eq("T14.1-1 删 token 判红 E_TABLE_CELL(7)", c8, GateResult.E_TABLE_CELL)
