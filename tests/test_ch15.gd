extends RefCounted

## CH15 结构 + 判据校验（20 段）。
## 分母口径：required 且非 pending 的 gate 数，按 Ch15Checks.deferred_gates(cfg) 现算；
## 15.2 句柄/帧同编号接口已具备（handles/frames/unmatched_frames），但缺真实抓包数据源，
## T15.2-1 仍 pending → 4 降为 3；接口形状与能红单独在 t15_2_interface 组验证。
## 负例断言给出精确失败码；断言能红，不是恒真。

const LABS := ["library_abi", "socket_api", "version_compat", "dns_resolve"]
const TOTAL_SECTIONS := 20
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260
const GATE_IDS := {"library_abi": ["T15.1-1", "T15.1-2", "T15.1-3", "T15.1-4"], "socket_api": ["T15.2-1", "T15.2-2", "T15.2-3", "T15.2-4"], "version_compat": ["T15.3-1", "T15.3-2", "T15.3-3", "T15.3-4"], "dns_resolve": ["T15.4-1", "T15.4-2", "T15.4-3", "T15.4-4"]}
const GATE_KINDS := {"library_abi": ["table", "skip_layer", "derived_number", "quiz"], "socket_api": ["table", "skip_layer", "derived_number", "quiz"], "version_compat": ["table", "skip_layer", "derived_number", "quiz"], "dns_resolve": ["table", "skip_layer", "derived_number", "quiz"]}
const ALLOWED_KINDS := ["table", "coverage", "port_map", "page_map", "checksum",
	"derived_number", "handshake_fsm", "timeout_idle", "skip_layer", "quiz"]

const Ch15Checks = preload("res://src/core/ch15_checks.gd")
const SocketTrace = preload("res://src/core/socket_trace.gd")
const NetLibKit = preload("res://src/core/net_lab_kit.gd")

const EXPECT := 74
const EXPECT_GROUPS := {"loadable": 1, "sections_present": 4, "section_count": 4, "order": 4, "text_nonempty": 4, "text_cap": 4, "screen_sum": 4, "last_after": 4, "practice": 4, "gate_count": 4, "p1_field": 4, "gate_ids": 4, "gate_kinds": 4, "gate_codes": 4, "denominator": 4, "pending_total": 1, "total_sections": 1, "positive": 4, "t15_2_interface": 3, "negative": 8}
const GROUP_DESCRIPTIONS := {"loadable": "ch15_labs 数据文件可读", "sections_present": "每 lab 必有非空 sections", "section_count": "每 lab 段数为 5", "order": "每 lab 内 order 连续 1..5", "text_nonempty": "每段 text 非空", "text_cap": "每段 ≤150 字（去半角空格）", "screen_sum": "同一 after 档同屏合计 ≤260", "last_after": "末段 after=3", "practice": "每节实践表 4 行且字段齐全", "gate_count": "每节 4 条 gate", "p1_field": "每节有 P1 文本与 p1_gates", "gate_ids": "gate id 按 T15.x-n 定稿", "gate_kinds": "只用既有 kind（table/skip_layer/derived_number/quiz）", "gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28", "denominator": "进分母 gate 数按 deferred_gates 现算（socket_api 为 3，因 T15.2-1 仍 pending）", "pending_total": "全章 pending 条数=1，且进分母计数=15", "total_sections": "全篇段数 20", "positive": "4 节好答案全绿（pending 不计）", "t15_2_interface": "T15.2-1 接口：handles/frames/unmatched_frames 由 socket_trace 实导且同编号逐帧", "negative": "错值/缺件/负例未复现/复算错/quiz 错/缺 rows/frame call_n 改坏/删一帧 均精确判红"}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch15_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch15_labs 可读", not labs.is_empty(), str(labs.size()))

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
		var d: Dictionary = Ch15Checks.deferred_gates(cfg)
		var pending := _pending_count(cfg)
		ctx.eq("%s 进分母（4 条 gate 去 %d pending）" % [id, pending],
			int(d["counted"]), 4 - pending)
		pending_sum += pending
		counted_sum += int(d["counted"])
		total += secs.size()
	ctx.begin_group("pending_total")
	ctx.check("全章 pending=1、进分母=15", pending_sum == 1 and counted_sum == 15,
		"pending=%d counted=%d" % [pending_sum, counted_sum])

	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var r: Dictionary = Ch15Checks.run(id, cfg, {"answers": _good(cfg)})
		ctx.begin_group("positive")
		ctx.check("%s 好答案全绿（pending=%d）" % [id, (r["pending"] as Array).size()],
			bool(r["ok"]), str(r["report"].first_failure()))

	_t15_2_interface(ctx, labs["socket_api"])

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
## derived 抄 expect_values，quiz 取 answer。pending 不参与。
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
	return out

func _gate(cfg: Dictionary, cid: String) -> Dictionary:
	for raw in (cfg.get("gate_cases", []) as Array):
		if str((raw as Dictionary).get("id", "")) == cid:
			return raw
	return {}

## T15.2-1 的作答由 socket_trace 实导：rows 照四调用，meta 的 handles/frames 是跑出来的。
func _answer_15_2(cfg: Dictionary) -> Dictionary:
	var calls: Array = cfg.get("socket_calls", [])
	var tr: Dictionary = SocketTrace.run(calls)
	var rows: Array = []
	for raw in calls:
		var c: Dictionary = raw
		rows.append({"call": str(c.get("op", "")), "stack_layer": str(c.get("stack_layer", "")),
			"frame": str(c.get("frame", ""))})
	return {"rows": rows, "meta": {
		"handles": tr["handles"],
		"frames": tr["frames"],
		"unmatched_frames": tr["unmatched_frames"],
		"text_roundtrip": true,
		"blueprint": true,
	}}

func _t15_2_interface(ctx: TestContext, cfg: Dictionary) -> void:
	ctx.begin_group("t15_2_interface")
	var tr: Dictionary = SocketTrace.run(cfg.get("socket_calls", []))
	var g: Dictionary = _gate(cfg, "T15.2-1")
	var want: Dictionary = g.get("expect_meta", {})
	ctx.check("T15.2-1 接口三字段齐备且实导成功",
		bool(tr["ok"]) and want.has("handles") and want.has("frames") and want.has("unmatched_frames"),
		"ok=%s keys=%s" % [str(tr["ok"]), str(want.keys())])
	var calls: Array = cfg.get("socket_calls", [])
	var numbered := (tr["frames"] as Array).size() == calls.size()
	for i in (tr["frames"] as Array).size():
		var f: Dictionary = (tr["frames"] as Array)[i]
		var c: Dictionary = calls[i]
		if int(f.get("frame_id", -1)) != i + 1 or int(f.get("call_n", -2)) != int(c.get("n", -3)) \
				or int(f.get("fd", -2)) != int(c.get("fd", -3)):
			numbered = false
		if str(f.get("dir", "")) != ("in" if str(c.get("op", "")) == "recv" else "out"):
			numbered = false
	ctx.check("T15.2-1 抓包与 socket 帧同编号：frame_id/call_n/fd 逐帧对上",
		numbered and (tr["unmatched_frames"] as Array).is_empty(),
		"frames=%s unmatched=%s" % [str(tr["frames"]), str(tr["unmatched_frames"])])
	ctx.check("T15.2-1 实导 handles/frames/unmatched 与 expect_meta 逐项一致",
		_deep_eq(tr["handles"], want.get("handles", []))
			and _deep_eq(tr["frames"], want.get("frames", []))
			and _deep_eq(tr["unmatched_frames"], want.get("unmatched_frames", [])),
		str(want.get("frames", [])))

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
	var a1 := _good(labs["library_abi"])
	var g1: Dictionary = a1["T15.1-1"]
	var rows1: Array = (g1["rows"] as Array).duplicate(true)
	rows1[0]["params"] = 3
	g1["rows"] = rows1
	var r1: Dictionary = Ch15Checks.run("library_abi", labs["library_abi"], {"answers": a1})
	var c1: int = _code(r1["report"], "T15.1-1")
	print("RED-PROBE CH15 T15.1-1 T15.1-1 参数个数错 -> code=%d" % c1)
	ctx.eq("T15.1-1 参数个数错判红 E_TABLE_CELL(7)", c1, GateResult.E_TABLE_CELL)

	var a2 := _good(labs["library_abi"])
	a2["T15.1-2"] = {"stages": ["link"], "missing": "link", "downstream_ok": true}
	var r2: Dictionary = Ch15Checks.run("library_abi", labs["library_abi"], {"answers": a2})
	var c2: int = _code(r2["report"], "T15.1-2")
	print("RED-PROBE CH15 T15.1-2 T15.1-2 负例未复现(链接未读符号表却正常) -> code=%d" % c2)
	ctx.eq("T15.1-2 负例未复现(链接未读符号表却正常)判红 E_OUTPUT_MISMATCH(10)", c2, GateResult.E_OUTPUT_MISMATCH)

	var a3 := _good(labs["library_abi"])
	var g3: Dictionary = a3["T15.1-1"]
	var rows3: Array = (g3["rows"] as Array).duplicate(true)
	g3["rows"] = rows3.slice(0, 1)
	var r3: Dictionary = Ch15Checks.run("library_abi", labs["library_abi"], {"answers": a3})
	var c3: int = _code(r3["report"], "T15.1-1")
	print("RED-PROBE CH15 T15.1-1 T15.1-1 只交 1/2 行 -> code=%d" % c3)
	ctx.eq("T15.1-1 只交 1/2 行判红 E_COVERAGE(13)", c3, GateResult.E_COVERAGE)

	var a4 := _good(labs["socket_api"])
	var g4: Dictionary = a4["T15.2-3"]
	var v4: Dictionary = (g4["values"] as Dictionary).duplicate(true)
	v4["frames"] = 3
	g4["values"] = v4
	var r4: Dictionary = Ch15Checks.run("socket_api", labs["socket_api"], {"answers": a4})
	var c4: int = _code(r4["report"], "T15.2-3")
	print("RED-PROBE CH15 T15.2-3 T15.2-3 帧数复算错 -> code=%d" % c4)
	ctx.eq("T15.2-3 帧数复算错判红 E_TABLE_CELL(7)", c4, GateResult.E_TABLE_CELL)

	var a5 := _good(labs["socket_api"])
	a5["T15.2-4"] = 1
	var r5: Dictionary = Ch15Checks.run("socket_api", labs["socket_api"], {"answers": a5})
	var c5: int = _code(r5["report"], "T15.2-4")
	print("RED-PROBE CH15 T15.2-4 T15.2-4 选错项 -> code=%d" % c5)
	ctx.eq("T15.2-4 选错项判红 E_QUIZ(14)", c5, GateResult.E_QUIZ)

	var a6 := _good(labs["dns_resolve"])
	a6["T15.4-1"] = {}
	var r6: Dictionary = Ch15Checks.run("dns_resolve", labs["dns_resolve"], {"answers": a6})
	var c6: int = _code(r6["report"], "T15.4-1")
	print("RED-PROBE CH15 T15.4-1 T15.4-1 缺 rows -> code=%d" % c6)
	ctx.eq("T15.4-1 缺 rows 判红 E_UNCONNECTED(3)", c6, GateResult.E_UNCONNECTED)

	# 能红证据：T15.2-1 虽 pending，接口判据本身可红。直接走 _table（绕过 pending 跳过）。
	var g7: Dictionary = _gate(labs["socket_api"], "T15.2-1")
	var ans7: Dictionary = _answer_15_2(labs["socket_api"])
	(ans7["meta"]["frames"] as Array)[1]["call_n"] = 9
	var rep7 := GateReport.new()
	NetLibKit._table(rep7, null, g7, {"T15.2-1": ans7})
	var c7: int = _code(rep7, "T15.2-1")
	print("RED-PROBE CH15 T15.2-1 T15.2-1 frame2 的 call_n 改坏(2→9) -> code=%d" % c7)
	ctx.eq("T15.2-1 frame call_n 改坏判红 E_OUTPUT_MISMATCH(10)", c7, GateResult.E_OUTPUT_MISMATCH)

	var ans8: Dictionary = _answer_15_2(labs["socket_api"])
	(ans8["meta"]["frames"] as Array).remove_at(1)
	var rep8 := GateReport.new()
	NetLibKit._table(rep8, null, g7, {"T15.2-1": ans8})
	var c8: int = _code(rep8, "T15.2-1")
	print("RED-PROBE CH15 T15.2-1 T15.2-1 删一帧(frame2) -> code=%d" % c8)
	ctx.eq("T15.2-1 删一帧判红 E_OUTPUT_MISMATCH(10)", c8, GateResult.E_OUTPUT_MISMATCH)
