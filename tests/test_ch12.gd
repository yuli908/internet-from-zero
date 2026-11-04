extends RefCounted

## CH12 五节（25 段）结构 + P1 判据校验。
## 分母口径：required 且非 pending 的 gate 数，按 Ch12Checks.deferred_gates(cfg) 现算；
## 12.3 栈帧布局未定稿（仅返回地址 0xF0 为【假设】）→ 4 降为 3，测试里单独断言。
## 负例断言给出精确失败码；断言能红，不是恒真。

const LABS := ["expr_compile", "pointer_array", "stack_frame", "recursion_baseline",
	"string_reverse"]
const SECTION_COUNTS := {"expr_compile": 5, "pointer_array": 5, "stack_frame": 5,
	"recursion_baseline": 5, "string_reverse": 5}
const TOTAL_SECTIONS := 25
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260
const GATE_IDS := {
	"expr_compile": ["T12.1-1", "T12.1-2", "T12.1-3", "T12.1-4"],
	"pointer_array": ["T12.2-1", "T12.2-2", "T12.2-3", "T12.2-4"],
	"stack_frame": ["T12.3-1", "T12.3-2", "T12.3-3", "T12.3-4"],
	"recursion_baseline": ["T12.4-1", "T12.4-2", "T12.4-3", "T12.4-4"],
	"string_reverse": ["T12.5-1", "T12.5-2", "T12.5-3", "T12.5-4"],
}
const GATE_KINDS := {
	"expr_compile": ["table", "skip_layer", "derived_number", "quiz"],
	"pointer_array": ["table", "skip_layer", "derived_number", "quiz"],
	"stack_frame": ["table", "skip_layer", "derived_number", "quiz"],
	"recursion_baseline": ["table", "skip_layer", "derived_number", "quiz"],
	"string_reverse": ["table", "skip_layer", "derived_number", "quiz"],
}
const ALLOWED_KINDS := ["table", "coverage", "port_map", "page_map", "checksum",
	"derived_number", "handshake_fsm", "timeout_idle", "skip_layer", "quiz"]

const Ch12Checks = preload("res://src/core/ch12_checks.gd")

const EXPECT := 83
const EXPECT_GROUPS := {
	"loadable": 1, "sections_present": 5, "section_count": 5, "total_sections": 1,
	"text_nonempty": 5, "text_cap": 5, "screen_sum": 5, "last_after": 5, "order": 5,
	"practice": 5, "gate_count": 5, "p1_field": 5, "gate_ids": 5,
	"gate_kinds": 5, "gate_codes": 5, "denominator": 5, "positive": 5, "negative": 6,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch12_labs 数据文件可读",
	"sections_present": "每 lab 必有非空 sections",
	"section_count": "每 lab 段数为 5",
	"total_sections": "全篇段数 25",
	"text_nonempty": "每段 text 非空",
	"text_cap": "每段 ≤150 字（去半角空格）",
	"screen_sum": "同一 after 档同屏合计 ≤260",
	"last_after": "末段 after=3",
	"order": "每 lab 内 order 连续 1..5",
	"practice": "每节实践表 4 行且字段齐全",
	"gate_count": "每节 4 条 gate",
	"p1_field": "每节有 P1 文本与 p1_gates",
	"gate_ids": "gate id 按 T12.x-n 提案",
	"gate_kinds": "只用既有 kind（table/skip_layer/derived_number/quiz）",
	"gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28",
	"denominator": "进分母 gate 数按 deferred_gates 现算（12.3 为 3，因栈帧布局 pending）",
	"positive": "五节好答案全绿",
	"negative": "错值/缺件/负例未复现/字节截断均精确判红",
}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch12_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch12_labs 可读", not labs.is_empty(), str(labs.size()))

	var total := 0
	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var secs: Array = cfg.get("sections", [])
		ctx.begin_group("sections_present")
		ctx.check("%s 有 sections" % id, not secs.is_empty(), str(secs.size()))
		ctx.begin_group("section_count")
		ctx.eq("%s 段数" % id, secs.size(), int(SECTION_COUNTS[id]))
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
		ctx.check("%s gate id 与提案一致" % id, _gate_ids_ok(cfg, id), _gate_ids(cfg))
		ctx.begin_group("gate_kinds")
		ctx.check("%s kind 全是既有 kind" % id, _kinds_ok(cfg, id), _gate_kinds(cfg))
		ctx.begin_group("gate_codes")
		ctx.check("%s 失败码在白名单" % id, _codes_ok(cfg), "")
		ctx.begin_group("denominator")
		var d: Dictionary = Ch12Checks.deferred_gates(cfg)
		var pending := _pending_count(cfg)
		ctx.eq("%s 进分母（%d 条 gate 去 %d pending）" % [id, (cfg.get("gate_cases", []) as Array).size(), pending],
			int(d["counted"]), (cfg.get("gate_cases", []) as Array).size() - pending)
		total += secs.size()
	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var r: Dictionary = Ch12Checks.run(id, cfg, {"answers": _answers(id)})
		ctx.begin_group("positive")
		ctx.check("%s 好答案全绿（pending=%d）" % [id, (r["pending"] as Array).size()],
			bool(r["ok"]), str(r["report"].first_failure()))

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

func _gate_ids_ok(cfg: Dictionary, id: String) -> bool:
	return _gate_ids(cfg) == str(GATE_IDS[id])

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

func _answers(id: String) -> Dictionary:
	match id:
		"expr_compile":
			return {
				"T12.1-1": {"rows": [
					{"expr": "a*b+c", "ast_nodes": 5, "instructions": 5, "run": 17,
						"span_ok": true, "trace_ok": true},
					{"expr": "(a+b)*c", "ast_nodes": 5, "instructions": 5, "run": 35,
						"span_ok": true, "trace_ok": true},
					{"expr": "a+b*c", "ast_nodes": 5, "instructions": 5, "run": 23,
						"span_ok": true, "trace_ok": true},
				], "meta": {"ast_linked": true, "instructions_traceable": true,
					"p03_grant": true}},
				"T12.1-2": {"stages": ["ast", "codegen", "run"],
					"missing": "ast", "downstream_ok": false},
				"T12.1-3": {"values": {"mul_add": 17, "paren": 35, "prec": 23}},
				"T12.1-4": 0,
			}
		"pointer_array":
			return {
				"T12.2-1": {"rows": [
					{"case": "x", "addr": "0x20", "value": 9, "error": ""},
					{"case": "y", "addr": "0x21", "value": 7, "error": ""},
					{"case": "a[2]", "addr": "0x12", "value": 42, "error": ""},
					{"case": "*(a+2)", "addr": "0x12", "value": 42, "error": ""},
					{"case": "a[4]", "addr": "0x14", "value": 0, "error": "OUT_OF_RANGE"},
				], "meta": {"ptr_addr_stable": true, "forms_equal": true,
					"oob_reported": true, "card": true}},
				"T12.2-2": {"stages": ["bounds_check", "load"],
					"missing": "bounds_check", "downstream_ok": false},
				"T12.2-3": {"values": {"a2_addr": 18, "a4_addr": 20}},
				"T12.2-4": 0,
			}
		"stack_frame":
			return {
				"T12.3-1": {"rows": [
					{"field": "ret_addr", "addr": "0xF0", "value": "0x0016"},
					{"field": "old_fp", "addr": "0xEF", "value": "0xF1"},
					{"field": "param_a", "addr": "0xEE", "value": 7},
					{"field": "param_b", "addr": "0xED", "value": 3},
					{"field": "local_t", "addr": "0xEC", "value": 0},
				], "meta": {"ret_matches": true, "fields_identified": true,
					"stack_restored": true, "card": true}},
				"T12.3-2": {"stages": ["frame_push", "call"],
					"missing": "frame_push", "downstream_ok": false},
				"T12.3-3": {"values": {"net_change": 0, "pushed_fields": 5}},
				"T12.3-4": 0,
			}
		"recursion_baseline":
			return {
				"T12.4-1": {"rows": [
					{"case": "fact3", "prog": "fact", "n": 3, "result": 6,
						"max_depth": 3, "frames_match": true},
					{"case": "fact5", "prog": "fact", "n": 5, "result": 120,
						"max_depth": 5, "frames_match": true},
					{"case": "fib5", "prog": "fib", "n": 5, "result": 5,
						"max_depth": 5, "frames_match": true},
					{"case": "fib6", "prog": "fib", "n": 6, "result": 8,
						"max_depth": 6, "frames_match": true},
				], "meta": {"depth_grows": true, "repeatable": true, "blueprint": true}},
				"T12.4-2": {"stages": ["recursion", "return"],
					"missing": "recursion", "downstream_ok": false},
				"T12.4-3": {"values": {"fact5": 120, "fib5": 5, "fib6": 8}},
				"T12.4-4": 0,
			}
		"string_reverse":
			return {
				"T12.5-1": {"rows": [
					{"case": "ascii", "input": "abcd", "in_bytes": 4,
						"out_hex": "64636261", "len_ok": true},
					{"case": "zh", "input": "你好", "in_bytes": 6,
						"out_hex": "BDA5E5A0BDE4", "len_ok": true},
					{"case": "empty", "input": "", "in_bytes": 0,
						"out_hex": "", "len_ok": true},
				], "meta": {"ascii_ok": true, "zh_bytes_ok": true,
					"empty_safe": true, "blueprint": true}},
				"T12.5-2": {"stages": ["length", "swap"],
					"missing": "length", "downstream_ok": false},
				"T12.5-3": {"values": {"ascii_len": 4, "zh_len": 6, "empty_len": 0}},
				"T12.5-4": 0,
			}
	return {}

func _code(report: GateReport, cid: String) -> int:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return -1

func _negative(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("negative")
	var r1: Dictionary = Ch12Checks.run("expr_compile", labs["expr_compile"], {"answers": {
		"T12.1-1": {"rows": [
			{"expr": "a*b+c", "ast_nodes": 5, "instructions": 5, "run": 18,
				"span_ok": true, "trace_ok": true},
			{"expr": "(a+b)*c", "ast_nodes": 5, "instructions": 5, "run": 35,
				"span_ok": true, "trace_ok": true},
			{"expr": "a+b*c", "ast_nodes": 5, "instructions": 5, "run": 23,
				"span_ok": true, "trace_ok": true},
		], "meta": {"ast_linked": true, "instructions_traceable": true,
			"p03_grant": true}},
		"T12.1-2": _answers("expr_compile")["T12.1-2"],
		"T12.1-3": _answers("expr_compile")["T12.1-3"], "T12.1-4": 0,
	}})
	var c1: int = _code(r1["report"], "T12.1-1")
	print("RED-PROBE CH12 T12.1-1 错值(a*b+c 运行=18) -> code=%d" % c1)
	ctx.eq("T12.1-1 运行结果错判红 E_TABLE_CELL(7)", c1, GateResult.E_TABLE_CELL)

	var r2: Dictionary = Ch12Checks.run("expr_compile", labs["expr_compile"], {"answers": {
		"T12.1-1": _answers("expr_compile")["T12.1-1"],
		"T12.1-2": {"stages": ["ast"], "missing": "ast", "downstream_ok": true},
		"T12.1-3": _answers("expr_compile")["T12.1-3"], "T12.1-4": 0,
	}})
	var c2: int = _code(r2["report"], "T12.1-2")
	print("RED-PROBE CH12 T12.1-2 负例未复现(AST 未接却输出正常) -> code=%d" % c2)
	ctx.eq("T12.1-2 AST 未接却输出正常判红 E_OUTPUT_MISMATCH(10)", c2, GateResult.E_OUTPUT_MISMATCH)

	var r3: Dictionary = Ch12Checks.run("pointer_array", labs["pointer_array"], {"answers": {
		"T12.2-1": {"rows": [
			{"case": "x", "addr": "0x20", "value": 9, "error": ""},
			{"case": "y", "addr": "0x21", "value": 7, "error": ""},
			{"case": "a[2]", "addr": "0x12", "value": 42, "error": ""},
		], "meta": {"ptr_addr_stable": true, "forms_equal": true,
			"oob_reported": true, "card": true}},
		"T12.2-2": _answers("pointer_array")["T12.2-2"],
		"T12.2-3": _answers("pointer_array")["T12.2-3"], "T12.2-4": 0,
	}})
	var c3: int = _code(r3["report"], "T12.2-1")
	print("RED-PROBE CH12 T12.2-1 缺件(只做交换、未做越界) -> code=%d" % c3)
	ctx.eq("T12.2-1 只做交换未做越界判红 E_COVERAGE(13)", c3, GateResult.E_COVERAGE)

	var r4: Dictionary = Ch12Checks.run("pointer_array", labs["pointer_array"], {"answers": {
		"T12.2-1": _answers("pointer_array")["T12.2-1"],
		"T12.2-2": {"stages": ["bounds_check"], "missing": "bounds_check", "downstream_ok": true},
		"T12.2-3": _answers("pointer_array")["T12.2-3"], "T12.2-4": 0,
	}})
	var c4: int = _code(r4["report"], "T12.2-2")
	print("RED-PROBE CH12 T12.2-2 负例未复现(只提示仍继续跑) -> code=%d" % c4)
	ctx.eq("T12.2-2 越界只提示未拦截判红 E_OUTPUT_MISMATCH(10)", c4, GateResult.E_OUTPUT_MISMATCH)

	var r5: Dictionary = Ch12Checks.run("stack_frame", labs["stack_frame"], {"answers": {
		"T12.3-1": _answers("stack_frame")["T12.3-1"],
		"T12.3-2": {"stages": ["frame_push"], "missing": "frame_push", "downstream_ok": true},
		"T12.3-3": _answers("stack_frame")["T12.3-3"], "T12.3-4": 0,
	}})
	var c5: int = _code(r5["report"], "T12.3-2")
	print("RED-PROBE CH12 T12.3-2 负例未复现(不压帧却没坏) -> code=%d" % c5)
	ctx.eq("T12.3-2 不压帧却正常返回判红 E_OUTPUT_MISMATCH(10)", c5, GateResult.E_OUTPUT_MISMATCH)

	var r6: Dictionary = Ch12Checks.run("string_reverse", labs["string_reverse"], {"answers": {
		"T12.5-1": {"rows": [
			{"case": "ascii", "input": "abcd", "in_bytes": 4,
				"out_hex": "646362", "len_ok": true},
			{"case": "zh", "input": "你好", "in_bytes": 6,
				"out_hex": "BDA5E5A0BDE4", "len_ok": true},
			{"case": "empty", "input": "", "in_bytes": 0,
				"out_hex": "", "len_ok": true},
		], "meta": {"ascii_ok": true, "zh_bytes_ok": true,
			"empty_safe": true, "blueprint": true}},
		"T12.5-2": _answers("string_reverse")["T12.5-2"],
		"T12.5-3": _answers("string_reverse")["T12.5-3"], "T12.5-4": 0,
	}})
	var c6: int = _code(r6["report"], "T12.5-1")
	print("RED-PROBE CH12 T12.5-1 错值(ASCII 只翻 6 字节) -> code=%d" % c6)
	ctx.eq("T12.5-1 输出字节被截断判红 E_TABLE_CELL(7)", c6, GateResult.E_TABLE_CELL)
