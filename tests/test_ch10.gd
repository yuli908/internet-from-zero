extends RefCounted

## CH10 四节（20 段）结构 + P1 判据校验。
## 分母口径：required 且非 pending 的 gate 数，按 Ch10Checks.deferred_gates(cfg) 现算；
## 10.3 吞吐 ≥2× 为【假设】初值 → 4 降为 3，测试里单独断言。
## 负例断言给出精确失败码；断言能红，不是恒真。

const LABS := ["seq_reorder", "ack_retransmit", "sliding_window", "reliable_channel"]
const SECTION_COUNTS := {"seq_reorder": 5, "ack_retransmit": 5, "sliding_window": 5, "reliable_channel": 5}
const TOTAL_SECTIONS := 20
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260
const GATE_IDS := {
	"seq_reorder": ["T10.1-1", "T10.1-2", "T10.1-3", "T10.1-4"],
	"ack_retransmit": ["T10.2-1", "T10.2-2", "T10.2-3", "T10.2-4"],
	"sliding_window": ["T10.3-1", "T10.3-2", "T10.3-3", "T10.3-4"],
	"reliable_channel": ["T10.4-1", "T10.4-2", "T10.4-3", "T10.4-4"],
}
const GATE_KINDS := {
	"seq_reorder": ["table", "skip_layer", "derived_number", "quiz"],
	"ack_retransmit": ["handshake_fsm", "timeout_idle", "derived_number", "quiz"],
	"sliding_window": ["table", "coverage", "derived_number", "quiz"],
	"reliable_channel": ["checksum", "skip_layer", "derived_number", "quiz"],
}
const ALLOWED_KINDS := ["table", "coverage", "port_map", "page_map", "checksum",
	"derived_number", "handshake_fsm", "timeout_idle", "skip_layer", "quiz"]

const Ch10Checks = preload("res://src/core/ch10_checks.gd")

const EXPECT := 68
const EXPECT_GROUPS := {
	"loadable": 1, "sections_present": 4, "section_count": 4, "total_sections": 1,
	"text_nonempty": 4, "text_cap": 4, "screen_sum": 4, "last_after": 4, "order": 4,
	"practice": 4, "gate_count": 4, "p1_field": 4, "gate_ids": 4,
	"gate_kinds": 4, "gate_codes": 4, "denominator": 4, "positive": 4, "negative": 6,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch10_labs 数据文件可读",
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
	"gate_ids": "gate id 按 T10.x-n 提案",
	"gate_kinds": "只用既有 kind（table/coverage/checksum/handshake_fsm/timeout_idle/skip_layer/derived_number/quiz）",
	"gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28",
	"denominator": "进分母 gate 数按 deferred_gates 现算（10.3 为 3，因 ≥2× 假设 pending）",
	"positive": "四节好答案全绿",
	"negative": "错值/缺件/填表式/假送达均精确判红",
}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch10_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch10_labs 可读", not labs.is_empty(), str(labs.size()))

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
		var d: Dictionary = Ch10Checks.deferred_gates(cfg)
		var pending := _pending_count(cfg)
		ctx.eq("%s 进分母（%d 条 gate 去 %d pending）" % [id, (cfg.get("gate_cases", []) as Array).size(), pending],
			int(d["counted"]), (cfg.get("gate_cases", []) as Array).size() - pending)
		total += secs.size()
	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var r: Dictionary = Ch10Checks.run(id, cfg, {"answers": _answers(id)})
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
		"seq_reorder":
			return {
				"T10.1-1": {"rows": [
					{"in_seq": 1, "out_seq": 1, "status": "ok"},
					{"in_seq": 3, "out_seq": 2, "status": "buffered"},
					{"in_seq": 2, "out_seq": 3, "status": "reordered"},
					{"in_seq": 4, "out_seq": 4, "status": "ok"},
					{"in_seq": 5, "out_seq": 5, "status": "missing"},
				], "meta": {"monotonic": true, "gap_seq": 5,
					"duplicate_suppressed": true, "loss_rate": 0.3, "mechanisms": 2}},
				"T10.1-2": {"stages": ["reorder_buffer", "deliver"],
					"missing": "reorder_buffer", "downstream_ok": false},
				"T10.1-3": {"value": 3},
				"T10.1-4": 0,
			}
		"ack_retransmit":
			return {
				"T10.2-1": {"transitions": [
					{"from": "idle", "event": "send", "to": "waiting"},
					{"from": "waiting", "event": "ack", "to": "acked"},
					{"from": "waiting", "event": "timeout", "to": "waiting"},
				], "drop_frame": 2, "state_after_drop": "waiting",
					"resend_frame": 2, "delivered": true, "p07_full": true,
					"repeatable": true},
				"T10.2-2": {"resent": true, "state": "waiting", "delivered": true},
				"T10.2-3": {"value": 1},
				"T10.2-4": 0,
			}
		"sliding_window":
			return {
				"T10.3-1": {"rows": [
					{"window": 1, "in_flight": 1, "throughput": 1.0, "retrans": 0.10},
					{"window": 4, "in_flight": 4, "throughput": 2.4, "retrans": 0.12},
				], "meta": {"same_config": true, "retrans_recorded": true, "perf_card": true}},
				"T10.3-2": {"cases": {"buffer_overflow": true,
					"retrans_up": true, "throughput_down": true}},
				"T10.3-3": {"value": 4},
				"T10.3-4": 0,
			}
		"reliable_channel":
			return {
				"T10.4-1": {"bytes": 1024, "checksum": 66560, "result_checksum": 66560,
					"seq_ok": true, "frames_ok": true,
					"meta": {"same_run": true, "perf_card": true, "blueprint_wired": true}},
				"T10.4-2": {"stages": ["send_count", "receiver_check"],
					"missing": "receiver_check", "downstream_ok": false},
				"T10.4-3": {"values": {"bytes": 1024, "bits": 8192}},
				"T10.4-4": 0,
			}
	return {}

func _code(report: GateReport, cid: String) -> int:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return -1

func _negative(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("negative")
	var r1: Dictionary = Ch10Checks.run("seq_reorder", labs["seq_reorder"], {"answers": {
		"T10.1-1": {"rows": _answers("seq_reorder")["T10.1-1"]["rows"],
			"meta": {"monotonic": false, "gap_seq": 5,
				"duplicate_suppressed": true, "loss_rate": 0.3, "mechanisms": 2}},
		"T10.1-2": _answers("seq_reorder")["T10.1-2"],
		"T10.1-3": {"value": 3}, "T10.1-4": 0,
	}})
	var c1: int = _code(r1["report"], "T10.1-1")
	print("RED-PROBE CH10 T10.1-1 输出不递增 -> code=%d" % c1)
	ctx.eq("T10.1-1 非单调判红 E_OUTPUT_MISMATCH(10)", c1, GateResult.E_OUTPUT_MISMATCH)

	var r2: Dictionary = Ch10Checks.run("seq_reorder", labs["seq_reorder"], {"answers": {
		"T10.1-1": _answers("seq_reorder")["T10.1-1"],
		"T10.1-2": {"stages": ["reorder_buffer"], "missing": "reorder_buffer", "downstream_ok": true},
		"T10.1-3": {"value": 3}, "T10.1-4": 0,
	}})
	var c2: int = _code(r2["report"], "T10.1-2")
	print("RED-PROBE CH10 T10.1-2 负例未复现(下游仍好) -> code=%d" % c2)
	ctx.eq("T10.1-2 缓冲未接却下游正常判红 E_OUTPUT_MISMATCH(10)", c2, GateResult.E_OUTPUT_MISMATCH)

	var r3: Dictionary = Ch10Checks.run("ack_retransmit", labs["ack_retransmit"], {"answers": {
		"T10.2-1": {"transitions": _answers("ack_retransmit")["T10.2-1"]["transitions"],
			"drop_frame": 0, "state_after_drop": "waiting", "resend_frame": 0,
			"delivered": true, "p07_full": true, "repeatable": true},
		"T10.2-2": _answers("ack_retransmit")["T10.2-2"],
		"T10.2-3": {"value": 1}, "T10.2-4": 0,
	}})
	var c3: int = _code(r3["report"], "T10.2-1")
	print("RED-PROBE CH10 T10.2-1 没注入丢 ACK -> code=%d" % c3)
	ctx.eq("T10.2-1 只跑无丢包路径判红 E_COVERAGE(13)", c3, GateResult.E_COVERAGE)

	var r4: Dictionary = Ch10Checks.run("ack_retransmit", labs["ack_retransmit"], {"answers": {
		"T10.2-1": _answers("ack_retransmit")["T10.2-1"],
		"T10.2-2": {"resent": false, "state": "idle", "delivered": true},
		"T10.2-3": {"value": 1}, "T10.2-4": 0,
	}})
	var c4: int = _code(r4["report"], "T10.2-2")
	print("RED-PROBE CH10 T10.2-2 超时回空闲假送达 -> code=%d" % c4)
	ctx.eq("T10.2-2 假送达判红 E_OUTPUT_MISMATCH(10)", c4, GateResult.E_OUTPUT_MISMATCH)

	var r5: Dictionary = Ch10Checks.run("reliable_channel", labs["reliable_channel"], {"answers": {
		"T10.4-1": {"bytes": 1024, "checksum": 66560, "result_checksum": 66561,
			"seq_ok": true, "frames_ok": true,
			"meta": {"same_run": true, "perf_card": true, "blueprint_wired": true}},
		"T10.4-2": _answers("reliable_channel")["T10.4-2"],
		"T10.4-3": {"values": {"bytes": 1024, "bits": 8192}}, "T10.4-4": 0,
	}})
	var c5: int = _code(r5["report"], "T10.4-1")
	print("RED-PROBE CH10 T10.4-1 校验差 1 字节 -> code=%d" % c5)
	ctx.eq("T10.4-1 校验不一致判红 E_OUTPUT_MISMATCH(10)", c5, GateResult.E_OUTPUT_MISMATCH)

	var r6: Dictionary = Ch10Checks.run("reliable_channel", labs["reliable_channel"], {"answers": {
		"T10.4-1": _answers("reliable_channel")["T10.4-1"],
		"T10.4-2": _answers("reliable_channel")["T10.4-2"],
		"T10.4-3": {"values": {"bytes": 1000, "bits": 8192}}, "T10.4-4": 0,
	}})
	var c6: int = _code(r6["report"], "T10.4-3")
	print("RED-PROBE CH10 T10.4-3 错值(1 KB=1000B) -> code=%d" % c6)
	ctx.eq("T10.4-3 换算错判红 E_TABLE_CELL(7)", c6, GateResult.E_TABLE_CELL)
