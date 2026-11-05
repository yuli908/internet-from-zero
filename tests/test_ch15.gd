extends RefCounted

## CH15 结构 + 判据校验（20 段）。
## 分母口径：required 且非 pending 的 gate 数，按 Ch15Checks.deferred_gates(cfg) 现算；
## 15.2 句柄/帧同编号接口已用本机 loopback 真实捕获（Python socket，fd=332、12 B 原样
## 回环）转正，T15.2-1 不再 pending → 4 条全进分母；接口形状与能红在 t15_2_interface 组验证。
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
const SymbolTable = preload("res://src/core/symbol_table.gd")

const EXPECT := 90
const EXPECT_GROUPS := {"loadable": 1, "sections_present": 4, "section_count": 4, "order": 4, "text_nonempty": 4, "text_cap": 4, "screen_sum": 4, "last_after": 4, "practice": 4, "gate_count": 4, "p1_field": 4, "gate_ids": 4, "gate_kinds": 4, "gate_codes": 4, "denominator": 4, "pending_total": 1, "total_sections": 1, "positive": 4, "t15_1_real": 3, "t15_2_interface": 4, "t15_3_real": 3, "negative": 17}
const GROUP_DESCRIPTIONS := {"loadable": "ch15_labs 数据文件可读", "sections_present": "每 lab 必有非空 sections", "section_count": "每 lab 段数为 5", "order": "每 lab 内 order 连续 1..5", "text_nonempty": "每段 text 非空", "text_cap": "每段 ≤150 字（去半角空格）", "screen_sum": "同一 after 档同屏合计 ≤260", "last_after": "末段 after=3", "practice": "每节实践表 4 行且字段齐全", "gate_count": "每节 4 条 gate", "p1_field": "每节有 P1 文本与 p1_gates", "gate_ids": "gate id 按 T15.x-n 定稿", "gate_kinds": "只用既有 kind（table/skip_layer/derived_number/quiz）", "gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28", "denominator": "进分母 gate 数按 deferred_gates 现算（socket_api 为 4，T15.2-1 已由真实捕获转正）", "pending_total": "全章 pending 条数=0，且进分母计数=16", "total_sections": "全篇段数 20", "positive": "4 节好答案全绿（pending 不计）", "t15_1_real": "T15.1-1 符号签名由 SymbolTable 实导：逐行对数据、签名含有序参数类型、程序声明与库导出跨源一致", "t15_2_interface": "T15.2-1 接口：handles/frames/unmatched_frames 由 socket_trace 实导且同编号逐帧；捕获源客户端字节与 payload 一字节一致", "t15_3_real": "T15.3-1 兼容表由新旧符号对实导：五类 reason 各命中一条，主版本变更按规则拒绝", "negative": "错值/缺件/负例未复现/复算错/quiz 错/缺 rows/frame call_n 改坏/删一帧/符号类型写错/参数顺序颠倒/同符号声明不一致/abi_ok 不符/五类 reason 改错 均精确判红"}

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
	ctx.check("全章 pending=0、进分母=16", pending_sum == 0 and counted_sum == 16,
		"pending=%d counted=%d" % [pending_sum, counted_sum])

	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var r: Dictionary = Ch15Checks.run(id, cfg, {"answers": _good(cfg)})
		ctx.begin_group("positive")
		ctx.check("%s 好答案全绿（pending=%d）" % [id, (r["pending"] as Array).size()],
			bool(r["ok"]), str(r["report"].first_failure()))

	_t15_1_real(ctx, labs["library_abi"])
	_t15_2_interface(ctx, labs["socket_api"])
	_t15_3_real(ctx, labs["version_compat"])

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
	var sym: Dictionary = (cfg.get("case_sources", {}) as Dictionary).get("symbols", {})
	if not sym.is_empty():
		var st: Dictionary = SymbolTable.run(sym)
		out["T15.1-1"] = {"rows": (st["rows"] as Array).duplicate(true),
			"meta": (st["meta"] as Dictionary).duplicate(true)}
	var vp: Dictionary = (cfg.get("case_sources", {}) as Dictionary).get("version_pairs", {})
	if not vp.is_empty():
		var cr: Dictionary = SymbolTable.compat_report(vp)
		out["T15.3-1"] = {"rows": (cr["rows"] as Array).duplicate(true),
			"meta": (cr["meta"] as Dictionary).duplicate(true)}
	if str(cfg.get("id", "")) == "socket_api":
		# T15.2-1 的好答案从真实捕获派生（socket_calls 的 fd/顺序 + capture 的字节），
		# 不是照抄 expect_meta；expect_meta 只作静态对照，防数据漂移。
		out["T15.2-1"] = _answer_15_2(cfg)
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
	# text_roundtrip 不再手写 true：从捕获源的客户端 send/recv 字节算出来。
	var cap: Dictionary = cfg.get("capture", {})
	var sent_hex := ""
	var recv_hex := ""
	for raw in cap.get("calls", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		if str(c.get("who", "")) != "client":
			continue
		if str(c.get("op", "")) == "send":
			sent_hex = str(c.get("bytes_hex", ""))
		if str(c.get("op", "")) == "recv":
			recv_hex = str(c.get("bytes_hex", ""))
	var roundtrip := not sent_hex.is_empty() and sent_hex == recv_hex \
		and sent_hex == str(cap.get("payload_hex", ""))
	return {"rows": rows, "meta": {
		"handles": tr["handles"],
		"frames": tr["frames"],
		"unmatched_frames": tr["unmatched_frames"],
		"text_roundtrip": roundtrip,
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
	# 捕获源真实性：客户端 send/recv 的原始字节必须与 payload 同一串，且 fd 与 socket_calls 一致。
	var cap: Dictionary = cfg.get("capture", {})
	var sent_hex := ""
	var recv_hex := ""
	var cap_fd := -1
	for raw in cap.get("calls", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		if str(c.get("who", "")) != "client":
			continue
		cap_fd = int(c.get("fd", -1))
		if str(c.get("op", "")) == "send":
			sent_hex = str(c.get("bytes_hex", ""))
		if str(c.get("op", "")) == "recv":
			recv_hex = str(c.get("bytes_hex", ""))
	var payload_hex := str(cap.get("payload_hex", ""))
	var socket_fd := int((cfg.get("socket_calls", [])[0] as Dictionary).get("fd", -2))
	ctx.check("T15.2-1 捕获源真实：客户端 send/recv 字节与 payload 同一串，fd 与 socket_calls 一致",
		not sent_hex.is_empty() and sent_hex == recv_hex and sent_hex == payload_hex
			and cap_fd == socket_fd,
		"send=%s recv=%s payload=%s fd=%d socket_fd=%d"
			% [sent_hex, recv_hex, payload_hex, cap_fd, socket_fd])
	ctx.check("T15.2-1 实导 handles/frames/unmatched 与 expect_meta 逐项一致",
		_deep_eq(tr["handles"], want.get("handles", []))
			and _deep_eq(tr["frames"], want.get("frames", []))
			and _deep_eq(tr["unmatched_frames"], want.get("unmatched_frames", [])),
		str(want.get("frames", [])))

func _t15_1_real(ctx: TestContext, cfg: Dictionary) -> void:
	ctx.begin_group("t15_1_real")
	var g: Dictionary = _gate(cfg, "T15.1-1")
	var src: Dictionary = (cfg.get("case_sources", {}) as Dictionary).get("symbols", {})
	var st: Dictionary = SymbolTable.run(src)
	var rows: Array = st["rows"]
	ctx.check("T15.1-1 符号签名由符号表实导且逐行对上数据",
		_deep_eq(rows, g.get("expect_rows", [])), str(rows))
	var sigs_ok := true
	for raw in rows:
		var r: Dictionary = raw
		var want := "%s(%s)->%s" % [str(r.get("symbol", "")),
			str(r.get("param_types", "")), str(r.get("ret", ""))]
		if str(r.get("sig", "")) != want or int(r.get("params", -1)) != _type_count(r):
			sigs_ok = false
	ctx.check("T15.1-1 每行签名含有序参数类型（可逐符号比）", sigs_ok, _sig_list(rows))
	var exports_sig := {}
	for raw in (src.get("symbols", []) as Array):
		var s: Dictionary = raw
		var nm := str(s.get("name", ""))
		exports_sig[nm] = SymbolTable.signature(nm, s.get("params", []), str(s.get("ret", "")))
	var declares_ok := true
	for raw_p in (src.get("programs", []) as Array):
		var p: Dictionary = raw_p
		var seen := {}
		for raw_d in (p.get("declares", []) as Array):
			var d: Dictionary = raw_d
			var nm := str(d.get("name", ""))
			seen[nm] = true
			if not exports_sig.has(nm) \
					or str(exports_sig[nm]) != SymbolTable.signature(nm, d.get("params", []), str(d.get("ret", ""))):
				declares_ok = false
		for nm in exports_sig:
			if not seen.has(str(nm)):
				declares_ok = false
	ctx.check("T15.1-1 程序声明与库导出逐符号一致（跨源核对，非本行自比）",
		declares_ok and bool(st["meta"].get("same_symbol", false)) and bool(st["meta"].get("abi_ok", false)),
		"same_symbol=%s abi_ok=%s" % [str(st["meta"].get("same_symbol")), str(st["meta"].get("abi_ok"))])

func _t15_3_real(ctx: TestContext, cfg: Dictionary) -> void:
	ctx.begin_group("t15_3_real")
	var g: Dictionary = _gate(cfg, "T15.3-1")
	var vp: Dictionary = (cfg.get("case_sources", {}) as Dictionary).get("version_pairs", {})
	var cr: Dictionary = SymbolTable.compat_report(vp)
	var rows: Array = cr["rows"]
	ctx.check("T15.3-1 兼容表由新旧符号对实导且逐行对上数据",
		_deep_eq(rows, g.get("expect_rows", [])), str(rows))
	var want := {"area": "ret_changed", "scale": "order_changed", "sum": "arity_changed",
		"peek": "name_changed", "emit": "type_changed", "tick": ""}
	var dist := {}
	var hit := true
	for raw in rows:
		var r: Dictionary = raw
		var nm := str(r.get("symbol", ""))
		var reason := str(r.get("reason", ""))
		dist[nm] = reason
		if not want.has(nm) or str(want[nm]) != reason:
			hit = false
	ctx.check("T15.3-1 五类 reason 各命中一条（顺序敏感：scale 报 order 不报 type）",
		hit, str(dist))
	var meta: Dictionary = cr["meta"]
	var tick: Dictionary = rows[5]
	ctx.check("T15.3-1 主版本 1.0→2.0：6 条全 rejected，ABI 未变的 tick 也拒绝",
		bool(meta.get("version_major_changed", false)) and int(meta.get("changed", -1)) == 5 \
			and int(meta.get("unchanged", -1)) == 1 \
			and str(tick.get("result", "")) == "rejected" and bool(tick.get("compatible", false)),
		str(meta))

func _type_count(row: Dictionary) -> int:
	var t := str(row.get("param_types", ""))
	return 0 if t.is_empty() else t.split(",").size()

func _sig_list(rows: Array) -> String:
	var out := []
	for raw in rows:
		out.append(str((raw as Dictionary).get("sig", "")))
	return str(out)

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

	# 能红证据：接口判据本身可红（T15.2-1 已由真实捕获转正，直接走 _table）。
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

	var a9 := _good(labs["library_abi"])
	var g9: Dictionary = a9["T15.1-1"]
	var rows9: Array = (g9["rows"] as Array).duplicate(true)
	rows9[1]["param_types"] = "char,char"
	rows9[1]["sig"] = "scale(char,char)->int"
	g9["rows"] = rows9
	var r9: Dictionary = Ch15Checks.run("library_abi", labs["library_abi"], {"answers": a9})
	var c9: int = _code(r9["report"], "T15.1-1")
	print("RED-PROBE CH15 T15.1-1 第 2 行 scale 参数类型写错(char,int→char,char) -> code=%d" % c9)
	ctx.eq("T15.1-1 符号类型写错判红 E_TABLE_CELL(7)", c9, GateResult.E_TABLE_CELL)

	var a10 := _good(labs["library_abi"])
	var g10: Dictionary = a10["T15.1-1"]
	var rows10: Array = (g10["rows"] as Array).duplicate(true)
	rows10[1]["param_types"] = "int,char"
	rows10[1]["sig"] = "scale(int,char)->int"
	g10["rows"] = rows10
	var r10: Dictionary = Ch15Checks.run("library_abi", labs["library_abi"], {"answers": a10})
	var c10: int = _code(r10["report"], "T15.1-1")
	print("RED-PROBE CH15 T15.1-1 第 2 行 scale 参数顺序颠倒(char,int→int,char) -> code=%d" % c10)
	ctx.eq("T15.1-1 参数顺序颠倒判红 E_TABLE_CELL(7)", c10, GateResult.E_TABLE_CELL)

	# same_symbol 不是恒真：库导出与行都不动，只把 P2 的 area 声明改成 (int,char,int) → same_symbol=false。
	var src11: Dictionary = ((labs["library_abi"].get("case_sources", {}) as Dictionary).get("symbols", {}) as Dictionary).duplicate(true)
	var progs11: Array = src11.get("programs", [])
	var area11: Dictionary = ((progs11[1] as Dictionary).get("declares", []) as Array)[0]
	(area11.get("params", []) as Array).append("int")
	var st11: Dictionary = SymbolTable.run(src11)
	print("RED-PROBE CH15 T15.1-1 P2 声明 area(int,char,int)（库导出/行不变）-> same_symbol=%s abi_ok=%s"
		% [str(st11["meta"]["same_symbol"]), str(st11["meta"]["abi_ok"])])
	var r11: Dictionary = Ch15Checks.run("library_abi", labs["library_abi"], {"answers": {
		"T15.1-1": {"rows": (st11["rows"] as Array).duplicate(true), "meta": (st11["meta"] as Dictionary).duplicate(true)}}})
	var c11: int = _code(r11["report"], "T15.1-1")
	print("RED-PROBE CH15 T15.1-1 同符号声明不一致 -> code=%d" % c11)
	ctx.check("T15.1-1 同符号声明不一致（行不变）也判红",
		not bool(st11["meta"]["same_symbol"]) and c11 == GateResult.E_OUTPUT_MISMATCH,
		"same_symbol=%s code=%d" % [str(st11["meta"]["same_symbol"]), c11])

	# abi_ok 也不是恒真：P1/P2 都声明 area 返回 B（彼此一致 → same_symbol=true），但与库导出 A 不符。
	var src12: Dictionary = ((labs["library_abi"].get("case_sources", {}) as Dictionary).get("symbols", {}) as Dictionary).duplicate(true)
	for raw_p in (src12.get("programs", []) as Array):
		for raw_d in ((raw_p as Dictionary).get("declares", []) as Array):
			if str((raw_d as Dictionary).get("name", "")) == "area":
				(raw_d as Dictionary)["ret"] = "B"
	var st12: Dictionary = SymbolTable.run(src12)
	print("RED-PROBE CH15 T15.1-1 P1/P2 都声明 area(...)->B（与库导出 A 不符）-> same_symbol=%s abi_ok=%s"
		% [str(st12["meta"]["same_symbol"]), str(st12["meta"]["abi_ok"])])
	var r12: Dictionary = Ch15Checks.run("library_abi", labs["library_abi"], {"answers": {
		"T15.1-1": {"rows": (st12["rows"] as Array).duplicate(true), "meta": (st12["meta"] as Dictionary).duplicate(true)}}})
	var c12: int = _code(r12["report"], "T15.1-1")
	print("RED-PROBE CH15 T15.1-1 abi_ok 不符 -> code=%d" % c12)
	ctx.check("T15.1-1 abi_ok 不符（同符号仍一致）也判红",
		bool(st12["meta"]["same_symbol"]) and not bool(st12["meta"]["abi_ok"]) and c12 == GateResult.E_OUTPUT_MISMATCH,
		"same_symbol=%s abi_ok=%s code=%d" % [str(st12["meta"]["same_symbol"]), str(st12["meta"]["abi_ok"]), c12])

	# 15.3 五类 reason 各一条负例：把对应行的 reason 改错 → 逐格判红。
	var classes := ["ret_changed", "order_changed", "arity_changed", "name_changed", "type_changed"]
	var wrong_reason := ["type_changed", "type_changed", "type_changed", "type_changed", "ret_changed"]
	for i in 5:
		var av: Dictionary = _good(labs["version_compat"])
		var gv: Dictionary = av["T15.3-1"]
		var rv: Array = (gv["rows"] as Array).duplicate(true)
		var sym_name := str((rv[i] as Dictionary).get("symbol", ""))
		(rv[i] as Dictionary)["reason"] = wrong_reason[i]
		gv["rows"] = rv
		var rr: Dictionary = Ch15Checks.run("version_compat", labs["version_compat"], {"answers": av})
		var cv: int = _code(rr["report"], "T15.3-1")
		print("RED-PROBE CH15 T15.3-1 %s 行 reason 改错(%s→%s) -> code=%d"
			% [sym_name, classes[i], wrong_reason[i], cv])
		ctx.eq("T15.3-1 %s/%s 的 reason 改错判红 E_TABLE_CELL(7)" % [sym_name, classes[i]], cv, GateResult.E_TABLE_CELL)
