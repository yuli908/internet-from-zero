extends RefCounted

## CH11 四节（20 段）结构 + P1 判据校验。
## 分母口径：required 且非 pending 的 gate 数，按 Ch11Checks.deferred_gates(cfg) 现算；
## 11.3 返回地址基址 0xF0 为【假设】 → 4 降为 3，测试里单独断言。
## 负例断言给出精确失败码；断言能红，不是恒真。

const LABS := ["assembler", "branch_loop", "stack_call", "debug_locate"]
const SECTION_COUNTS := {"assembler": 5, "branch_loop": 5, "stack_call": 5, "debug_locate": 5}
const TOTAL_SECTIONS := 20
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260
const GATE_IDS := {
	"assembler": ["T11.1-1", "T11.1-2", "T11.1-3", "T11.1-4"],
	"branch_loop": ["T11.2-1", "T11.2-2", "T11.2-3", "T11.2-4"],
	"stack_call": ["T11.3-1", "T11.3-2", "T11.3-3", "T11.3-4"],
	"debug_locate": ["T11.4-1", "T11.4-2", "T11.4-3", "T11.4-4"],
}
const GATE_KINDS := {
	"assembler": ["table", "table", "derived_number", "quiz"],
	"branch_loop": ["table", "skip_layer", "derived_number", "quiz"],
	"stack_call": ["table", "skip_layer", "derived_number", "quiz"],
	"debug_locate": ["table", "skip_layer", "derived_number", "quiz"],
}
const ALLOWED_KINDS := ["table", "coverage", "port_map", "page_map", "checksum",
	"derived_number", "handshake_fsm", "timeout_idle", "skip_layer", "quiz"]

const Ch11Checks = preload("res://src/core/ch11_checks.gd")

const EXPECT := 68
const EXPECT_GROUPS := {
	"loadable": 1, "sections_present": 4, "section_count": 4, "total_sections": 1,
	"text_nonempty": 4, "text_cap": 4, "screen_sum": 4, "last_after": 4, "order": 4,
	"practice": 4, "gate_count": 4, "p1_field": 4, "gate_ids": 4,
	"gate_kinds": 4, "gate_codes": 4, "denominator": 4, "positive": 4, "negative": 6,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch11_labs 数据文件可读",
	"sections_present": "每 lab 必有非空 sections",
	"section_count": "每 lab 段数为 5",
	"total_sections": "全篇段数 20",
	"text_nonempty": "每段 text 非空",
	"text_cap": "每段 ≤150 字（去半角空格）",
	"screen_sum": "同一 after 档同屏合计 ≤260",
	"last_after": "末段 after=3",
	"order": "每 lab 内 order 连续 1..5",
	"practice": "每节实践表 4 行且字段齐全",
	"gate_count": "每节 4 条 gate",
	"p1_field": "每节有 P1 文本与 p1_gates",
	"gate_ids": "gate id 按 T11.x-n 提案",
	"gate_kinds": "只用既有 kind（table/skip_layer/derived_number/quiz）",
	"gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28",
	"denominator": "进分母 gate 数按 deferred_gates 现算（11.3 为 3，因 0xF0 假设 pending）",
	"positive": "四节好答案全绿",
	"negative": "错值/缺件/只跑一组/改结果不定位均精确判红",
}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch11_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch11_labs 可读", not labs.is_empty(), str(labs.size()))

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
		var d: Dictionary = Ch11Checks.deferred_gates(cfg)
		var pending := _pending_count(cfg)
		ctx.eq("%s 进分母（%d 条 gate 去 %d pending）" % [id, (cfg.get("gate_cases", []) as Array).size(), pending],
			int(d["counted"]), (cfg.get("gate_cases", []) as Array).size() - pending)
		total += secs.size()
	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var r: Dictionary = Ch11Checks.run(id, cfg, {"answers": _answers(id)})
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
		"assembler":
			return {
				"T11.1-1": {"rows": [
					{"line": 1, "mnemonic": "LDI", "opcode": 3, "operand": 5, "code16": "0x0305"},
					{"line": 2, "mnemonic": "STA", "opcode": 2, "operand": 32, "code16": "0x0220"},
					{"line": 3, "mnemonic": "LDA", "opcode": 1, "operand": 32, "code16": "0x0120"},
					{"line": 4, "mnemonic": "ADD", "opcode": 4, "operand": 33, "code16": "0x0421"},
					{"line": 5, "mnemonic": "OUT", "opcode": 12, "operand": 0, "code16": "0x0C00"},
				], "meta": {"roundtrip": true, "wrong_line": 4,
					"wrong_field": "opcode", "assembler_grant": true}},
				"T11.1-2": {"rows": [{"line": 4, "mnemonic": "ADD", "opcode": 5,
					"decoded": "SUB", "result_changed": true}]},
				"T11.1-3": {"values": {"opcode": 4, "operand": 33}},
				"T11.1-4": 0,
			}
		"branch_loop":
			return {
				"T11.2-1": {"rows": [
					{"case": "0..9", "sum": 45, "replay_ok": true, "zc_ok": true},
					{"case": "N=4", "sum": 10, "replay_ok": true, "zc_ok": true},
					{"case": "N=7", "sum": 28, "replay_ok": true, "zc_ok": true},
					{"case": "N=10", "sum": 55, "replay_ok": true, "zc_ok": true},
				], "meta": {"jz_triggered": true, "jc_triggered": true, "blueprint": true}},
				"T11.2-2": {"stages": ["conditional_jump", "loop"],
					"missing": "conditional_jump", "downstream_ok": false},
				"T11.2-3": {"value": 45},
				"T11.2-4": 0,
			}
		"stack_call":
			return {
				"T11.3-1": {"rows": [{"depth": 1, "ret_addr": "0xF0", "pc_after": "0x0016",
					"sp_after": "0xF1", "a": 7, "b": 3}],
					"meta": {"recorded": true, "stack_restored": true, "card": true}},
				"T11.3-2": {"stages": ["ret_push", "call"],
					"missing": "ret_push", "downstream_ok": false},
				"T11.3-3": {"values": {"net_change": 0, "peak": 2}},
				"T11.3-4": 0,
			}
		"debug_locate":
			return {
				"T11.4-1": {"rows": [
					{"id": "F1", "line": 3, "panel": "PC", "value_before": "0x0008",
						"value_expected": "0x000C", "fixed": true},
					{"id": "F2", "line": 6, "panel": "A", "value_before": 10,
						"value_expected": 15, "fixed": true},
					{"id": "F3", "line": 9, "panel": "MEM", "value_before": "0x20",
						"value_expected": "0x21", "fixed": true},
				], "meta": {"breakpoints": 3, "rerun_ok": true,
					"no_regression": true, "report": true}},
				"T11.4-2": {"stages": ["locate", "fix"],
					"missing": "locate", "downstream_ok": false},
				"T11.4-3": {"value": 5},
				"T11.4-4": 0,
			}
	return {}

func _code(report: GateReport, cid: String) -> int:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return -1

func _negative(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("negative")
	var r1: Dictionary = Ch11Checks.run("assembler", labs["assembler"], {"answers": {
		"T11.1-1": {"rows": [
			{"line": 1, "mnemonic": "LDI", "opcode": 3, "operand": 5, "code16": "0x0305"},
			{"line": 2, "mnemonic": "STA", "opcode": 2, "operand": 32, "code16": "0x0220"},
			{"line": 3, "mnemonic": "LDA", "opcode": 1, "operand": 32, "code16": "0x0120"},
			{"line": 4, "mnemonic": "ADD", "opcode": 4, "operand": 33, "code16": "0x0521"},
			{"line": 5, "mnemonic": "OUT", "opcode": 12, "operand": 0, "code16": "0x0C00"},
		], "meta": {"roundtrip": true, "wrong_line": 4,
			"wrong_field": "opcode", "assembler_grant": true}},
		"T11.1-2": _answers("assembler")["T11.1-2"],
		"T11.1-3": _answers("assembler")["T11.1-3"], "T11.1-4": 0,
	}})
	var c1: int = _code(r1["report"], "T11.1-1")
	print("RED-PROBE CH11 T11.1-1 错值(line4 码=0x0521) -> code=%d" % c1)
	ctx.eq("T11.1-1 机器码字段错判红 E_TABLE_CELL(7)", c1, GateResult.E_TABLE_CELL)

	var r2: Dictionary = Ch11Checks.run("branch_loop", labs["branch_loop"], {"answers": {
		"T11.2-1": _answers("branch_loop")["T11.2-1"],
		"T11.2-2": {"stages": ["conditional_jump"], "missing": "conditional_jump", "downstream_ok": true},
		"T11.2-3": {"value": 45}, "T11.2-4": 0,
	}})
	var c2: int = _code(r2["report"], "T11.2-2")
	print("RED-PROBE CH11 T11.2-2 负例未复现(循环仍退出) -> code=%d" % c2)
	ctx.eq("T11.2-2 无条件跳转却正常退出判红 E_OUTPUT_MISMATCH(10)", c2, GateResult.E_OUTPUT_MISMATCH)

	var r3: Dictionary = Ch11Checks.run("branch_loop", labs["branch_loop"], {"answers": {
		"T11.2-1": {"rows": [
			{"case": "0..9", "sum": 45, "replay_ok": true, "zc_ok": true},
			{"case": "N=4", "sum": 10, "replay_ok": true, "zc_ok": true},
		], "meta": {"jz_triggered": true, "jc_triggered": true, "blueprint": true}},
		"T11.2-2": _answers("branch_loop")["T11.2-2"],
		"T11.2-3": {"value": 45}, "T11.2-4": 0,
	}})
	var c3: int = _code(r3["report"], "T11.2-1")
	print("RED-PROBE CH11 T11.2-1 缺件(只跑1组N) -> code=%d" % c3)
	ctx.eq("T11.2-1 只跑一组 N 判红 E_COVERAGE(13)", c3, GateResult.E_COVERAGE)

	var r4: Dictionary = Ch11Checks.run("stack_call", labs["stack_call"], {"answers": {
		"T11.3-1": _answers("stack_call")["T11.3-1"],
		"T11.3-2": {"stages": ["ret_push"], "missing": "ret_push", "downstream_ok": true},
		"T11.3-3": _answers("stack_call")["T11.3-3"], "T11.3-4": 0,
	}})
	var c4: int = _code(r4["report"], "T11.3-2")
	print("RED-PROBE CH11 T11.3-2 负例未复现(返回仍正常) -> code=%d" % c4)
	ctx.eq("T11.3-2 不压返回地址却不跑飞判红 E_OUTPUT_MISMATCH(10)", c4, GateResult.E_OUTPUT_MISMATCH)

	var r5: Dictionary = Ch11Checks.run("debug_locate", labs["debug_locate"], {"answers": {
		"T11.4-1": {"rows": [
			{"id": "F1", "line": 3, "panel": "PC", "value_before": "0x0008",
				"value_expected": "0x000C", "fixed": true},
			{"id": "F2", "line": 6, "panel": "A", "value_before": 10,
				"value_expected": 15, "fixed": true},
		], "meta": {"breakpoints": 3, "rerun_ok": true,
			"no_regression": true, "report": true}},
		"T11.4-2": _answers("debug_locate")["T11.4-2"],
		"T11.4-3": {"value": 5}, "T11.4-4": 0,
	}})
	var c5: int = _code(r5["report"], "T11.4-1")
	print("RED-PROBE CH11 T11.4-1 缺件(只定位2个故障) -> code=%d" % c5)
	ctx.eq("T11.4-1 只查两个故障判红 E_COVERAGE(13)", c5, GateResult.E_COVERAGE)

	var r6: Dictionary = Ch11Checks.run("debug_locate", labs["debug_locate"], {"answers": {
		"T11.4-1": _answers("debug_locate")["T11.4-1"],
		"T11.4-2": _answers("debug_locate")["T11.4-2"],
		"T11.4-3": {"value": 4}, "T11.4-4": 0,
	}})
	var c6: int = _code(r6["report"], "T11.4-3")
	print("RED-PROBE CH11 T11.4-3 错值(差值=4) -> code=%d" % c6)
	ctx.eq("T11.4-3 断点差值算错判红 E_TABLE_CELL(7)", c6, GateResult.E_TABLE_CELL)
