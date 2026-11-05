extends RefCounted

## Final 结构 + 判据校验（9 段）。
## 分母口径：required 且非 pending 的 gate 数，按 FinalChecks.deferred_gates(cfg) 现算；
## F1 出口形态已定为本机 loopback 真 TCP（127.0.0.1:7777）→ F1-1 转 ready，3 全进分母。
## 负例断言给出精确失败码；断言能红，不是恒真。

const LABS := ["f1_outbound", "f2_gomoku", "f3_certificate"]
const TOTAL_SECTIONS := 9
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260
const GATE_IDS := {"f1_outbound": ["F1-1", "F1-2", "F1-3"], "f2_gomoku": ["F2-1", "F2-2", "F2-3"], "f3_certificate": ["F3-1", "F3-2", "F3-3"]}
const GATE_KINDS := {"f1_outbound": ["table", "skip_layer", "derived_number"], "f2_gomoku": ["table", "skip_layer", "derived_number"], "f3_certificate": ["table", "skip_layer", "derived_number"]}
const ALLOWED_KINDS := ["table", "coverage", "port_map", "page_map", "checksum",
	"derived_number", "handshake_fsm", "timeout_idle", "skip_layer", "quiz"]

const FinalChecks = preload("res://src/core/final_checks.gd")
const WorldPort = preload("res://src/sim/world_port.gd")

const EXPECT := 63
const EXPECT_GROUPS := {"loadable": 1, "sections_present": 3, "section_count": 3, "order": 3, "text_nonempty": 3, "text_cap": 3, "screen_sum": 3, "last_after": 3, "practice": 3, "gate_count": 3, "p1_field": 3, "gate_ids": 3, "gate_kinds": 3, "gate_codes": 3, "denominator": 3, "pending_total": 1, "total_sections": 1, "positive": 3, "f1_outbound_real": 9, "negative": 6}
const GROUP_DESCRIPTIONS := {"loadable": "final_labs.json 数据文件可读", "sections_present": "每 lab 必有非空 sections", "section_count": "每 lab 段数为 3", "order": "每 lab 内 order 连续 1..3", "text_nonempty": "每段 text 非空", "text_cap": "每段 ≤150 字（去半角空格）", "screen_sum": "同一 after 档同屏合计 ≤260", "last_after": "末段 after=2", "practice": "每节实践表 3 行且字段齐全", "gate_count": "每节 3 条 gate", "p1_field": "每节有 P1 文本与 p1_gates", "gate_ids": "gate id 按 F1-1..F3-3 定稿", "gate_kinds": "只用既有 kind（table / skip_layer / derived_number）", "gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28", "denominator": "进分母 gate 数按 deferred_gates 现算（合计 9）", "pending_total": "全章 pending 条数=0，且进分母计数=9", "total_sections": "全篇段数 9", "positive": "3 节好答案全绿（pending 不计）", "f1_outbound_real": "F1 本机 loopback 真 TCP：同一份字节两个读取点、随输入变、端口真实、两条负例判红", "negative": "错值/负例未复现/缺行/复算错/缺 answers/时延越限均精确判红"}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/final_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("final_labs.json 可读", not labs.is_empty(), str(labs.size()))

	var total := 0
	var pending_sum := 0
	var counted_sum := 0
	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var secs: Array = cfg.get("sections", [])
		ctx.begin_group("sections_present")
		ctx.check("%s 有 sections" % id, not secs.is_empty(), str(secs.size()))
		ctx.begin_group("section_count")
		ctx.eq("%s 段数" % id, secs.size(), 3)
		ctx.begin_group("order")
		ctx.check("%s order 连续" % id, _orders_ok(secs), _orders(secs))
		ctx.begin_group("text_nonempty")
		ctx.check("%s 每段非空" % id, _all_nonempty(secs), "")
		ctx.begin_group("text_cap")
		ctx.check("%s 单段 ≤150" % id, _max_len(secs) <= LEFT_LIMIT, str(_max_len(secs)))
		ctx.begin_group("screen_sum")
		ctx.check("%s 同屏 ≤260" % id, _max_screen(secs) <= SCREEN_LIMIT, str(_max_screen(secs)))
		ctx.begin_group("last_after")
		ctx.eq("%s 末段 after" % id, int((secs[secs.size() - 1] as Dictionary).get("after", -1)), 2)
		ctx.begin_group("practice")
		ctx.check("%s 实践表 3 行齐全" % id, _practice_ok(cfg), str((cfg.get("practice", []) as Array).size()))
		ctx.begin_group("gate_count")
		ctx.eq("%s gate 条数" % id, (cfg.get("gate_cases", []) as Array).size(), 3)
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
		var d: Dictionary = FinalChecks.deferred_gates(cfg)
		var pending := _pending_count(cfg)
		ctx.eq("%s 进分母（3 条 gate 去 %d pending）" % [id, pending],
			int(d["counted"]), 3 - pending)
		pending_sum += pending
		counted_sum += int(d["counted"])
		total += secs.size()
	ctx.begin_group("pending_total")
	ctx.check("全章 pending=0、进分母=9", pending_sum == 0 and counted_sum == 9,
		"pending=%d counted=%d" % [pending_sum, counted_sum])

	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var r: Dictionary = FinalChecks.run(id, cfg, {"answers": _good(cfg)})
		ctx.begin_group("positive")
		ctx.check("%s 好答案全绿（pending=%d）" % [id, (r["pending"] as Array).size()],
			bool(r["ok"]), str(r["report"].first_failure()))

	_f1(ctx, labs)
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
	if p.size() != 3:
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
				if g.has("outbound"):
					var live: Dictionary = WorldPort.deliver(g.get("outbound", {}))
					out[cid] = {"rows": (live.get("rows", []) as Array).duplicate(true),
						"meta": (live.get("meta", {}) as Dictionary).duplicate(true)}
				else:
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

func _gate_case(cfg: Dictionary, cid: String) -> Dictionary:
	for raw in (cfg.get("gate_cases", []) as Array):
		if str((raw as Dictionary).get("id", "")) == cid:
			return raw
	return {}

## F1 不是「打印两行」：现跑本机 loopback 真 TCP，核两个读取点（发出/收到）同一份字节，
## 再拿两条负例（字节被改写、输出顺序颠倒）加一条端口负例证明判据能红。
func _f1(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("f1_outbound_real")
	var cfg: Dictionary = labs.get("f1_outbound", {})
	var g: Dictionary = _gate_case(cfg, "F1-1")
	var live: Dictionary = WorldPort.deliver(g.get("outbound", {}))
	ctx.check("本机 loopback 真 TCP 收发成功", bool(live.get("ok", false)),
		str(live.get("detail", "")))
	var rows: Array = live.get("rows", [])
	ctx.eq("两次改输入各一行", rows.size(), 2)

	var same := true
	var decode_ok := true
	var varies := true
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		if str(r.get("sent_hex", "")).is_empty() \
				or str(r.get("local_bytes", "")) != str(r.get("sent_hex", "")):
			same = false
		if str(r.get("local_bytes", "")).hex_decode().get_string_from_utf8() != str(r.get("input", "")):
			decode_ok = false
		if i > 0 and str(r.get("sent_hex", "")) == str((rows[i - 1] as Dictionary).get("sent_hex", "")):
			varies = false
	var meta: Dictionary = live.get("meta", {})
	ctx.check("同一份字节在两个读取点一致（sent_hex == local_bytes 且非空）", same, str(rows))
	ctx.check("两次输出随输入变，且本机读到的字节解码回原文", varies and decode_ok, str(rows))
	ctx.check("真实回环拓扑与端口", str(meta.get("transport", "")) == "tcp-loopback"
		and str(meta.get("host", "")) == "127.0.0.1" and int(meta.get("port", 0)) > 0, str(meta))
	var slow := 0
	for r in rows:
		slow = maxi(slow, int((r as Dictionary).get("deliver_us", -1)))
	ctx.check("真实往返时延在 1..50000 us", slow >= 1 and slow <= 50000, str(slow))

	# 负例①：本机字节被改写（校验和对不上）→ 10
	var a1 := _good(labs["f1_outbound"])
	var r1: Dictionary = a1["F1-1"]
	var rows1: Array = (r1["rows"] as Array).duplicate(true)
	rows1[0]["local_bytes"] = "68692c2068756d616f"
	r1["rows"] = rows1
	var rb: Dictionary = FinalChecks.run("f1_outbound", labs["f1_outbound"], {"answers": a1})
	var cb: int = _code(rb["report"], "F1-1")
	print("RED-PROBE Final F1-1 F1-1 本机字节被改写 -> code=%d detail=%s"
		% [cb, _detail(rb["report"], "F1-1")])
	ctx.eq("F1-1 本机字节被改写判红 E_OUTPUT_MISMATCH", cb, GateResult.E_OUTPUT_MISMATCH)

	# 负例②：两次输出顺序颠倒 → 10
	var a2 := _good(labs["f1_outbound"])
	var r2: Dictionary = a2["F1-1"]
	var rows2: Array = (r2["rows"] as Array).duplicate(true)
	rows2.reverse()
	r2["rows"] = rows2
	var ro: Dictionary = FinalChecks.run("f1_outbound", labs["f1_outbound"], {"answers": a2})
	var co: int = _code(ro["report"], "F1-1")
	print("RED-PROBE Final F1-1 F1-1 输出顺序颠倒 -> code=%d detail=%s"
		% [co, _detail(ro["report"], "F1-1")])
	ctx.eq("F1-1 输出顺序颠倒判红 E_OUTPUT_MISMATCH", co, GateResult.E_OUTPUT_MISMATCH)

	# 端口写错：不是任何真实监听端口 → 7（拓扑先于语义）
	var a3 := _good(labs["f1_outbound"])
	var meta3: Dictionary = (a3["F1-1"]["meta"] as Dictionary).duplicate(true)
	meta3["port"] = int(meta3.get("port", 0)) + 1
	a3["F1-1"]["meta"] = meta3
	var rp: Dictionary = FinalChecks.run("f1_outbound", labs["f1_outbound"], {"answers": a3})
	var cp: int = _code(rp["report"], "F1-1")
	print("RED-PROBE Final F1-1 F1-1 端口写错 -> code=%d detail=%s"
		% [cp, _detail(rp["report"], "F1-1")])
	ctx.eq("F1-1 端口写错判红 E_TABLE_CELL", cp, GateResult.E_TABLE_CELL)

func _detail(report: GateReport, cid: String) -> String:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return str(c.get("detail", ""))
	return ""

func _code(report: GateReport, cid: String) -> int:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return -1

func _negative(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("negative")
	var a1 := _good(labs["f2_gomoku"])
	var g1: Dictionary = a1["F2-1"]
	var rows1: Array = (g1["rows"] as Array).duplicate(true)
	rows1[0]["x"] = 9
	g1["rows"] = rows1
	var r1: Dictionary = FinalChecks.run("f2_gomoku", labs["f2_gomoku"], {"answers": a1})
	var c1: int = _code(r1["report"], "F2-1")
	print("RED-PROBE Final F2-1 F2-1 第 1 手落点对不上 -> code=%d" % c1)
	ctx.eq("F2-1 F2-1 第 1 手落点对不上判红 E_TABLE_CELL", c1, GateResult.E_TABLE_CELL)

	var a2 := _good(labs["f1_outbound"])
	a2["F1-2"] = {"stages": ["world_bridge"], "missing": "world_bridge", "downstream_ok": true}
	var r2: Dictionary = FinalChecks.run("f1_outbound", labs["f1_outbound"], {"answers": a2})
	var c2: int = _code(r2["report"], "F1-2")
	print("RED-PROBE Final F1-2 F1-2 负例未复现（假打印却显示本机收到） -> code=%d" % c2)
	ctx.eq("F1-2 F1-2 负例未复现（假打印却显示本机收到）判红 E_OUTPUT_MISMATCH", c2, GateResult.E_OUTPUT_MISMATCH)

	var a3 := _good(labs["f2_gomoku"])
	var g3: Dictionary = a3["F2-1"]
	var rows3: Array = (g3["rows"] as Array).duplicate(true)
	g3["rows"] = rows3.slice(0, 1)
	var r3: Dictionary = FinalChecks.run("f2_gomoku", labs["f2_gomoku"], {"answers": a3})
	var c3: int = _code(r3["report"], "F2-1")
	print("RED-PROBE Final F2-1 F2-1 只交 1/5 手 -> code=%d" % c3)
	ctx.eq("F2-1 F2-1 只交 1/5 手判红 E_COVERAGE", c3, GateResult.E_COVERAGE)

	var a4 := _good(labs["f3_certificate"])
	var g4: Dictionary = a4["F3-3"]
	var v4: Dictionary = (g4["values"] as Dictionary).duplicate(true)
	v4["field_count"] = 2
	g4["values"] = v4
	var r4: Dictionary = FinalChecks.run("f3_certificate", labs["f3_certificate"], {"answers": a4})
	var c4: int = _code(r4["report"], "F3-3")
	print("RED-PROBE Final F3-3 F3-3 凭证字段数算错 -> code=%d" % c4)
	ctx.eq("F3-3 F3-3 凭证字段数算错判红 E_TABLE_CELL", c4, GateResult.E_TABLE_CELL)

	var a5 := _good(labs["f2_gomoku"])
	a5["F2-1"] = {}
	var r5: Dictionary = FinalChecks.run("f2_gomoku", labs["f2_gomoku"], {"answers": a5})
	var c5: int = _code(r5["report"], "F2-1")
	print("RED-PROBE Final F2-1 F2-1 缺 rows -> code=%d" % c5)
	ctx.eq("F2-1 F2-1 缺 rows判红 E_UNCONNECTED", c5, GateResult.E_UNCONNECTED)

	var a6 := _good(labs["f2_gomoku"])
	var g6: Dictionary = a6["F2-1"]
	var rows6: Array = (g6["rows"] as Array).duplicate(true)
	rows6[0]["turn_ms"] = 90
	g6["rows"] = rows6
	var r6: Dictionary = FinalChecks.run("f2_gomoku", labs["f2_gomoku"], {"answers": a6})
	var c6: int = _code(r6["report"], "F2-1")
	print("RED-PROBE Final F2-1 F2-1 第 1 回合 90 超过上限 50 -> code=%d" % c6)
	ctx.eq("F2-1 F2-1 第 1 回合 90 超过上限 50判红 E_DELAY_MISMATCH", c6, GateResult.E_DELAY_MISMATCH)
