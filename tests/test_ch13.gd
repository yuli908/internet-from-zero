extends RefCounted

## CH13 结构 + 判据校验（15 段）。
## 分母口径：required 且非 pending 的 gate 数，按 Ch13Checks.deferred_gates(cfg) 现算；
## 13.1 源码行映射已按 interface 19 §2.1 落地 → 4 条全进分母，pending=0。
## 负例断言给出精确失败码；断言能红，不是恒真。

const LABS := ["bytecode_vm", "object_ref", "gc_reclaim"]
const TOTAL_SECTIONS := 15
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260
const GATE_IDS := {"bytecode_vm": ["T13.1-1", "T13.1-2", "T13.1-3", "T13.1-4"], "object_ref": ["T13.2-1", "T13.2-2", "T13.2-3", "T13.2-4"], "gc_reclaim": ["T13.3-1", "T13.3-2", "T13.3-3", "T13.3-4"]}
const GATE_KINDS := {"bytecode_vm": ["table", "skip_layer", "derived_number", "quiz"], "object_ref": ["table", "skip_layer", "derived_number", "quiz"], "gc_reclaim": ["table", "skip_layer", "derived_number", "quiz"]}
const ALLOWED_KINDS := ["table", "coverage", "port_map", "page_map", "checksum",
	"derived_number", "handshake_fsm", "timeout_idle", "skip_layer", "quiz"]

const Ch13Checks = preload("res://src/core/ch13_checks.gd")
const ObjectGraph = preload("res://src/core/object_graph.gd")
const BytecodeTrace = preload("res://src/core/bytecode_trace.gd")

const EXPECT := 70
const EXPECT_GROUPS := {"loadable": 1, "sections_present": 3, "section_count": 3, "order": 3, "text_nonempty": 3, "text_cap": 3, "screen_sum": 3, "last_after": 3, "practice": 3, "gate_count": 3, "p1_field": 3, "gate_ids": 3, "gate_kinds": 3, "gate_codes": 3, "denominator": 3, "pending_total": 1, "total_sections": 1, "positive": 3, "t13_1_real": 3, "t13_2_graph": 11, "negative": 8}
const GROUP_DESCRIPTIONS := {"loadable": "ch13_labs 数据文件可读", "sections_present": "每 lab 必有非空 sections", "section_count": "每 lab 段数为 5", "order": "每 lab 内 order 连续 1..5", "text_nonempty": "每段 text 非空", "text_cap": "每段 ≤150 字（去半角空格）", "screen_sum": "同一 after 档同屏合计 ≤260", "last_after": "末段 after=3", "practice": "每节实践表 4 行且字段齐全", "gate_count": "每节 4 条 gate", "p1_field": "每节有 P1 文本与 p1_gates", "gate_ids": "gate id 按 T13.x-n 定稿", "gate_kinds": "只用既有 kind（table/skip_layer/derived_number/quiz）", "gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28", "denominator": "进分母 gate 数按 deferred_gates 现算（13.1 行映射落地后 bytecode_vm 为 4）", "pending_total": "全章 pending 条数=0，且进分母计数=12", "total_sections": "全篇段数 15", "positive": "3 节好答案全绿（含 T13.1-1 实跑作答）", "t13_1_real": "T13.1-1 行映射/覆盖/输出由 bytecode_trace 实跑导出并与数据期望逐项一致", "t13_2_graph": "13.2 对象图：数据图自洽、下游真读 report.actual.graph、端点缺失/kind 错/方向颠倒/节点超限/边超限五条负例实测、合法大图 60/120 不误红、上限余量 ≥20 倍", "negative": "错值/缺件/负例未复现/复算错/quiz 错/缺 rows/行映射改坏/映射项删除 均精确判红"}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch13_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch13_labs 可读", not labs.is_empty(), str(labs.size()))

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
		var d: Dictionary = Ch13Checks.deferred_gates(cfg)
		var pending := _pending_count(cfg)
		ctx.eq("%s 进分母（4 条 gate 去 %d pending）" % [id, pending],
			int(d["counted"]), 4 - pending)
		pending_sum += pending
		counted_sum += int(d["counted"])
		total += secs.size()
	ctx.begin_group("pending_total")
	ctx.check("全章 pending=0、进分母=12", pending_sum == 0 and counted_sum == 12,
		"pending=%d counted=%d" % [pending_sum, counted_sum])

	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var r: Dictionary = Ch13Checks.run(id, cfg, {"answers": _good(cfg)})
		ctx.begin_group("positive")
		ctx.check("%s 好答案全绿（pending=%d）" % [id, (r["pending"] as Array).size()],
			bool(r["ok"]), str(r["report"].first_failure()))

	_t13_1_real(ctx, labs["bytecode_vm"])
	_t13_2_graph(ctx, labs["object_ref"])

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
## derived 抄 expect_values，quiz 取 answer。T13.1-1 例外：由 bytecode_trace 实跑导出，
## 不抄 expect_meta（行映射/覆盖/输出必须是跑出来的）。
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
				if g.has("graph"):
					(out[cid] as Dictionary)["graph"] = (g["graph"] as Dictionary).duplicate(true)
			"skip_layer":
				var st := str(g.get("stage", ""))
				out[cid] = {"stages": [st, "downstream"], "missing": st, "downstream_ok": false}
			"derived_number":
				out[cid] = {"values": (g.get("expect_values", {}) as Dictionary).duplicate(true)}
			"quiz":
				out[cid] = int((g.get("quiz", {}) as Dictionary).get("answer", 0))
	if not cfg.has("program"):
		return out
	var tr: Dictionary = BytecodeTrace.run(cfg.get("program", []))
	out["T13.1-1"] = {
		"rows": tr["rows"],
		"meta": {
			"line_map": tr["line_map"],
			"lines_covered": tr["lines_covered"],
			"unmapped_pc": tr["unmapped_pc"],
			"output": tr["output"],
			"p04_grant": true,
		},
	}
	return out

func _gate(cfg: Dictionary, cid: String) -> Dictionary:
	for raw in (cfg.get("gate_cases", []) as Array):
		if str((raw as Dictionary).get("id", "")) == cid:
			return raw
	return {}

## 真判据：行映射不是抄 expect_meta，而是把 lab 级 program 交给参考执行器跑出来的。
func _t13_1_real(ctx: TestContext, cfg: Dictionary) -> void:
	ctx.begin_group("t13_1_real")
	var tr: Dictionary = BytecodeTrace.run(cfg.get("program", []))
	var g: Dictionary = _gate(cfg, "T13.1-1")
	var want: Dictionary = g.get("expect_meta", {})
	ctx.check("T13.1-1 行映射由 program 实跑导出，逐 pc 一致",
		_deep_eq(tr["line_map"], want.get("line_map", [])) and bool(tr["ok"]),
		"实跑 %s / 期望 %s" % [str(tr["line_map"]), str(want.get("line_map", []))])
	ctx.check("T13.1-1 全 pc 有行号、覆盖 1..3、无 unmapped",
		tr["unmapped_pc"].is_empty() and _deep_eq(tr["lines_covered"], [1, 2, 3])
			and (tr["line_map"] as Array).size() == (cfg.get("program", []) as Array).size(),
		"unmapped=%s covered=%s" % [str(tr["unmapped_pc"]), str(tr["lines_covered"])])
	ctx.check("T13.1-1 输出由栈机实算 [5]",
		_deep_eq(tr["output"], want.get("output", [])), str(tr["output"]))

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
	var a1 := _good(labs["object_ref"])
	var g1: Dictionary = a1["T13.2-1"]
	var rows1: Array = (g1["rows"] as Array).duplicate(true)
	rows1[0]["value"] = 8
	g1["rows"] = rows1
	var r1: Dictionary = Ch13Checks.run("object_ref", labs["object_ref"], {"answers": a1})
	var c1: int = _code(r1["report"], "T13.2-1")
	print("RED-PROBE CH13 T13.2-1 T13.2-1 字段值错 -> code=%d" % c1)
	ctx.eq("T13.2-1 字段值错判红 E_TABLE_CELL(7)", c1, GateResult.E_TABLE_CELL)

	var a2 := _good(labs["bytecode_vm"])
	a2["T13.1-2"] = {"stages": ["vm_exec"], "missing": "vm_exec", "downstream_ok": true}
	var r2: Dictionary = Ch13Checks.run("bytecode_vm", labs["bytecode_vm"], {"answers": a2})
	var c2: int = _code(r2["report"], "T13.1-2")
	print("RED-PROBE CH13 T13.1-2 T13.1-2 负例未复现(VM 未接却输出正常) -> code=%d" % c2)
	ctx.eq("T13.1-2 负例未复现(VM 未接却输出正常)判红 E_OUTPUT_MISMATCH(10)", c2, GateResult.E_OUTPUT_MISMATCH)

	var a3 := _good(labs["object_ref"])
	var g3: Dictionary = a3["T13.2-1"]
	var rows3: Array = (g3["rows"] as Array).duplicate(true)
	g3["rows"] = rows3.slice(0, 3)
	var r3: Dictionary = Ch13Checks.run("object_ref", labs["object_ref"], {"answers": a3})
	var c3: int = _code(r3["report"], "T13.2-1")
	print("RED-PROBE CH13 T13.2-1 T13.2-1 只交 3/4 行 -> code=%d" % c3)
	ctx.eq("T13.2-1 只交 3/4 行判红 E_COVERAGE(13)", c3, GateResult.E_COVERAGE)

	var a4 := _good(labs["bytecode_vm"])
	var g4: Dictionary = a4["T13.1-3"]
	var v4: Dictionary = (g4["values"] as Dictionary).duplicate(true)
	v4["after_add"] = 2
	g4["values"] = v4
	var r4: Dictionary = Ch13Checks.run("bytecode_vm", labs["bytecode_vm"], {"answers": a4})
	var c4: int = _code(r4["report"], "T13.1-3")
	print("RED-PROBE CH13 T13.1-3 T13.1-3 栈深复算错 -> code=%d" % c4)
	ctx.eq("T13.1-3 栈深复算错判红 E_TABLE_CELL(7)", c4, GateResult.E_TABLE_CELL)

	var a5 := _good(labs["bytecode_vm"])
	a5["T13.1-4"] = 1
	var r5: Dictionary = Ch13Checks.run("bytecode_vm", labs["bytecode_vm"], {"answers": a5})
	var c5: int = _code(r5["report"], "T13.1-4")
	print("RED-PROBE CH13 T13.1-4 T13.1-4 选错项 -> code=%d" % c5)
	ctx.eq("T13.1-4 选错项判红 E_QUIZ(14)", c5, GateResult.E_QUIZ)

	var a6 := _good(labs["gc_reclaim"])
	a6["T13.3-1"] = {}
	var r6: Dictionary = Ch13Checks.run("gc_reclaim", labs["gc_reclaim"], {"answers": a6})
	var c6: int = _code(r6["report"], "T13.3-1")
	print("RED-PROBE CH13 T13.3-1 T13.3-1 缺 rows -> code=%d" % c6)
	ctx.eq("T13.3-1 缺 rows 判红 E_UNCONNECTED(3)", c6, GateResult.E_UNCONNECTED)

	# 能红证据①：改坏行映射里一个 src_line（pc2 由 1 改成 9）。
	var a7 := _good(labs["bytecode_vm"])
	var m7: Dictionary = (a7["T13.1-1"]["meta"] as Dictionary).duplicate(true)
	var lm7: Array = (m7["line_map"] as Array).duplicate(true)
	lm7[2]["src_line"] = 9
	m7["line_map"] = lm7
	a7["T13.1-1"]["meta"] = m7
	var r7: Dictionary = Ch13Checks.run("bytecode_vm", labs["bytecode_vm"], {"answers": a7})
	var c7: int = _code(r7["report"], "T13.1-1")
	print("RED-PROBE CH13 T13.1-1 T13.1-1 行映射 pc2 来源行改坏(1→9) -> code=%d" % c7)
	ctx.eq("T13.1-1 行映射改坏判红 E_OUTPUT_MISMATCH(10)", c7, GateResult.E_OUTPUT_MISMATCH)

	# 能红证据②：删掉一条 pc→行映射项（pc2），不是布尔位能盖住的。
	var a8 := _good(labs["bytecode_vm"])
	var m8: Dictionary = (a8["T13.1-1"]["meta"] as Dictionary).duplicate(true)
	var lm8: Array = (m8["line_map"] as Array).duplicate(true)
	lm8.remove_at(2)
	m8["line_map"] = lm8
	a8["T13.1-1"]["meta"] = m8
	var r8: Dictionary = Ch13Checks.run("bytecode_vm", labs["bytecode_vm"], {"answers": a8})
	var c8: int = _code(r8["report"], "T13.1-1")
	print("RED-PROBE CH13 T13.1-1 T13.1-1 删一条 pc2 行映射项 -> code=%d" % c8)
	ctx.eq("T13.1-1 删映射项判红 E_OUTPUT_MISMATCH(10)", c8, GateResult.E_OUTPUT_MISMATCH)

## 13.2 对象图（19 §2.2）：边语义在 ObjectGraph 里定稿；这里验数据自洽、
## 下游真读（report.actual.graph）、以及五条能红的负例（端点/kind/方向/两道规模上限）。
func _t13_2_graph(ctx: TestContext, cfg: Dictionary) -> void:
	ctx.begin_group("t13_2_graph")
	var want := _graph_of(cfg)
	var wn: Array = want.get("nodes", [])
	var we: Array = want.get("edges", [])
	ctx.check("数据对象图 3 节点 / 3 边", wn.size() == 3 and we.size() == 3,
		"nodes=%d edges=%d" % [wn.size(), we.size()])
	var addrs := {}
	for raw in wn:
		addrs[str((raw as Dictionary).get("obj_addr", ""))] = true
	var endpoints_ok := true
	var kinds_ok := true
	for raw in we:
		var e: Dictionary = raw
		if not addrs.has(str(e.get("from", ""))):
			endpoints_ok = false
		if not addrs.has(str(e.get("to", ""))):
			endpoints_ok = false
		if not ["parent", "iface", "field"].has(str(e.get("kind", ""))):
			kinds_ok = false
	ctx.check("数据图边端点全在节点地址集", endpoints_ok, _edge_text(we))
	ctx.check("数据图边 kind 全在枚举", kinds_ok, _edge_text(we))

	# 下游真读：不是只有 ok:true，报告 actual.graph 必须带解析后的节点/边。
	var r: Dictionary = Ch13Checks.run("object_ref", cfg, {"answers": _good(cfg)})
	var c0 := _case(r["report"], "T13.2-1")
	var ag: Dictionary = (c0.get("actual", {}) as Dictionary).get("graph", {})
	ctx.check("T13.2-1 下游真读 report.actual.graph 含 3 节点/3 边",
		(ag.get("nodes", []) as Array).size() == 3
			and (ag.get("edges", []) as Array).size() == 3, str(ag))

	# 负例①：边指向不存在的节点 → 3。
	var g1: Dictionary = want.duplicate(true)
	((g1["edges"] as Array)[0] as Dictionary)["to"] = "0x99"
	var c1 := _graph_code(cfg, g1)
	print("RED-PROBE CH13 T13.2-1 边端点不存在(to=0x99) -> code=%d" % c1)
	ctx.eq("T13.2-1 边指向不存在节点判红 E_UNCONNECTED(3)", c1, GateResult.E_UNCONNECTED)

	# 负例②：kind 写错 → 7。
	var g2: Dictionary = want.duplicate(true)
	((g2["edges"] as Array)[1] as Dictionary)["kind"] = "implement"
	var c2 := _graph_code(cfg, g2)
	print("RED-PROBE CH13 T13.2-1 边 kind 写错(iface→implement) -> code=%d" % c2)
	ctx.eq("T13.2-1 边 kind 写错判红 E_TABLE_CELL(7)", c2, GateResult.E_TABLE_CELL)

	# 负例③：有向边 from/to 颠倒 → 10（端点都在、kind 也对，所以不是 3/7）。
	var g3: Dictionary = want.duplicate(true)
	var e3: Dictionary = (g3["edges"] as Array)[0]
	var tmp := str(e3.get("from", ""))
	e3["from"] = str(e3.get("to", ""))
	e3["to"] = tmp
	var c3 := _graph_code(cfg, g3)
	print("RED-PROBE CH13 T13.2-1 有向边 from/to 颠倒 -> code=%d" % c3)
	ctx.eq("T13.2-1 有向边方向颠倒判红 E_OUTPUT_MISMATCH(10)", c3, GateResult.E_OUTPUT_MISMATCH)

	# 合法大图不误红：60 节点 / 120 边（含 field 边）应通过；上限对当前 3 节点仍有 ≥20 倍余量。
	var big := {"nodes": [], "edges": []}
	for i in 60:
		(big["nodes"] as Array).append({"obj_addr": "0x%02x" % (i + 1), "type": "N",
			"fields": [{"name": "ref", "offset": 2}]})
	for i in 60:
		var nxt := "0x%02x" % (((i + 1) % 60) + 1)
		(big["edges"] as Array).append({"kind": "field", "from": "0x%02x" % (i + 1),
			"to": nxt, "field": "ref"})
		(big["edges"] as Array).append({"kind": "iface", "from": "0x%02x" % (i + 1),
			"to": nxt, "field": ""})
	var gok: Dictionary = ObjectGraph.validate(big, big)
	print("GREEN-PROBE CH13 T13.2-1 合法大图 60 节点/120 边 -> ok=%s code=%d"
		% [str(gok.get("ok", false)), int(gok.get("code", -1))])
	ctx.check("T13.2-1 合法大图 60 节点/120 边通过（不误红）",
		bool(gok.get("ok", false)), str(gok.get("detail", "")))
	ctx.check("T13.2-1 上限余量 ≥20 倍（64/3 与 128/3）",
		ObjectGraph.MAX_NODES >= 3 * 20 and ObjectGraph.MAX_EDGES >= 3 * 20,
		"nodes=%d edges=%d" % [ObjectGraph.MAX_NODES, ObjectGraph.MAX_EDGES])

	# 规模上限：超限判红，不截断（节点 65 > 64、边 129 > 128）。
	var big_nodes := {"nodes": [], "edges": []}
	for i in 65:
		(big_nodes["nodes"] as Array).append(
			{"obj_addr": "0x%02x" % (i + 1), "type": "N", "fields": []})
	var c4 := _graph_code(cfg, big_nodes)
	print("RED-PROBE CH13 T13.2-1 节点 65 > 上限 64 -> code=%d" % c4)
	ctx.eq("T13.2-1 节点超上限判红 E_TABLE_CELL(7)", c4, GateResult.E_TABLE_CELL)

	var big_edges: Dictionary = want.duplicate(true)
	for i in 126:
		(big_edges["edges"] as Array).append(
			{"kind": "parent", "from": "0x48", "to": "0x40", "field": ""})
	var c5 := _graph_code(cfg, big_edges)
	print("RED-PROBE CH13 T13.2-1 边 129 > 上限 128 -> code=%d" % c5)
	ctx.eq("T13.2-1 边超上限判红 E_TABLE_CELL(7)", c5, GateResult.E_TABLE_CELL)

func _graph_of(cfg: Dictionary) -> Dictionary:
	var g: Dictionary = _gate(cfg, "T13.2-1")
	return (g.get("graph", {}) as Dictionary).duplicate(true)

func _graph_code(cfg: Dictionary, graph: Dictionary) -> int:
	var a := _good(cfg)
	(a["T13.2-1"] as Dictionary)["graph"] = graph
	var r: Dictionary = Ch13Checks.run("object_ref", cfg, {"answers": a})
	return _code(r["report"], "T13.2-1")

func _case(report: GateReport, cid: String) -> Dictionary:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return c
	return {}

func _edge_text(edges: Array) -> String:
	var out := []
	for raw in edges:
		var e: Dictionary = raw
		out.append("%s:%s->%s" % [str(e.get("kind", "")), str(e.get("from", "")),
			str(e.get("to", ""))])
	return str(out)
