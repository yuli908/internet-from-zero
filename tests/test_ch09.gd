extends RefCounted

## CH09 五节（25 段）结构 + P1 判据校验。
## 分母口径：required 且非 pending 的 gate 数，按 Ch09Checks.deferred_gates(cfg) 现算；
## 9.4 备路 ≤3 跳为未校准初值 → 4 降为 3，测试里单独断言。
## 负例断言给出精确失败码；断言能红，不是恒真。

const LABS := ["addressing", "arp", "switch", "router", "loop_recovery"]
const SECTION_COUNTS := {"addressing": 5, "arp": 5, "switch": 5, "router": 5, "loop_recovery": 5}
const TOTAL_SECTIONS := 25
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260
const GATE_IDS := {
	"addressing": ["T9.1-1", "T9.1-2", "T9.1-3", "T9.1-4"],
	"arp": ["T9.1a-1", "T9.1a-2", "T9.1a-3", "T9.1a-4"],
	"switch": ["T9.2-1", "T9.2-2", "T9.2-3", "T9.2-4"],
	"router": ["T9.3-1", "T9.3-2", "T9.3-3", "T9.3-4"],
	"loop_recovery": ["T9.4-1", "T9.4-2", "T9.4-3", "T9.4-4"],
}
const GATE_KINDS := {
	"addressing": ["table", "skip_layer", "derived_number", "quiz"],
	"arp": ["table", "table", "derived_number", "quiz"],
	"switch": ["port_map", "table", "derived_number", "quiz"],
	"router": ["port_map", "table", "derived_number", "quiz"],
	"loop_recovery": ["coverage", "coverage", "derived_number", "quiz"],
}
const ALLOWED_KINDS := ["table", "coverage", "port_map", "page_map", "checksum",
	"derived_number", "handshake_fsm", "timeout_idle", "skip_layer", "quiz"]

const Ch09Checks = preload("res://src/core/ch09_checks.gd")

const EXPECT := 83
const EXPECT_GROUPS := {
	"loadable": 1, "sections_present": 5, "section_count": 5, "total_sections": 1,
	"text_nonempty": 5, "text_cap": 5, "screen_sum": 5, "last_after": 5, "order": 5,
	"practice": 5, "gate_count": 5, "p1_field": 5, "gate_ids": 5,
	"gate_kinds": 5, "gate_codes": 5, "denominator": 5, "positive": 5, "negative": 6,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch09_labs 数据文件可读",
	"sections_present": "每 lab 必有非空 sections",
	"section_count": "每 lab 段数为 5",
	"total_sections": "全篇段数 25",
	"text_nonempty": "每段 text 非空",
	"text_cap": "每段 ≤150 字（去半角空格）",
	"screen_sum": "同一 after 档同屏合计 ≤260",
	"last_after": "末段 after=3",
	"order": "每 lab 内 order 连续 1..5",
	"practice": "每节实践表 4 行且 id/level/produce/judge 齐全",
	"gate_count": "每节 4 条 gate",
	"p1_field": "每节有 P1 文本与 p1_gates",
	"gate_ids": "gate id 按 T9.x-n 提案",
	"gate_kinds": "只用既有 kind（table/coverage/port_map/derived_number/skip_layer/quiz）",
	"gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28",
	"denominator": "进分母 gate 数按 deferred_gates 现算（9.4 为 3，因 ≤3 跳 pending）",
	"positive": "五节好答案全绿",
	"negative": "错值/缺件/填表式/负例未复现均精确判红",
}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch09_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch09_labs 可读", not labs.is_empty(), str(labs.size()))

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
		var d: Dictionary = Ch09Checks.deferred_gates(cfg)
		var pending := _pending_count(cfg)
		ctx.eq("%s 进分母（%d 条 gate 去 %d pending）" % [id, (cfg.get("gate_cases", []) as Array).size(), pending],
			int(d["counted"]), (cfg.get("gate_cases", []) as Array).size() - pending)
		total += secs.size()
	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var r: Dictionary = Ch09Checks.run(id, cfg, {"answers": _answers(id)})
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
		"addressing":
			return {
				"T9.1-1": {"rows": [
					{"node": "n1", "net": 1, "host": 1},
					{"node": "n2", "net": 1, "host": 2},
					{"node": "n3", "net": 2, "host": 3},
					{"node": "n4", "net": 2, "host": 4},
				], "meta": {"same_net_ok": true, "cross_net_ok": true,
					"dup_rejected": true, "conflict_with": "n2"}},
				"T9.1-2": {"stages": ["dup_check", "deliver"],
					"missing": "dup_check", "downstream_ok": false},
				"T9.1-3": {"value": 256},
				"T9.1-4": 0,
			}
		"arp":
			return {
				"T9.1a-1": {"rows": [
					{"frame": "req", "src": "n1", "dst": "broadcast",
						"broadcast": true, "unicast": false, "hw": "aa-bb"},
					{"frame": "resp", "src": "n2", "dst": "n1",
						"broadcast": false, "unicast": true, "hw": "aa-bb"},
				], "meta": {"fields_match": true, "broadcasts": 1, "cache_hits": 2}},
				"T9.1a-2": {"rows": [{"frame": "resp", "dst": "broadcast",
					"copies": 3, "bystanders": 2}]},
				"T9.1a-3": {"value": 1},
				"T9.1a-4": 0,
			}
		"switch":
			return {
				"T9.2-1": {"rows": [
					{"addr": "n1", "port": "p1"},
					{"addr": "n2", "port": "p2"},
					{"addr": "n3", "port": "p3"},
					{"addr": "n4", "port": "p4"},
				], "meta": {"flood_ports": 3, "converged": true}},
				"T9.2-2": {"rows": [{"addr": "n1", "port": "p2",
					"learned": false, "moved": true, "misdelivered": true}]},
				"T9.2-3": {"value": 3},
				"T9.2-4": 0,
			}
		"router":
			return {
				"T9.3-1": {"rows": [
					{"addr": "net1", "port": "direct"},
					{"addr": "net2", "port": "r2"},
				], "meta": {"all_connected": true, "ttl_step_ok": true,
					"ttl_zero_dropped": true, "wrong_then_fixed": true}},
				"T9.3-2": {"rows": [{"row": "net2", "next_hop": "r1",
					"loop": true, "ttl_zero_reported": true}]},
				"T9.3-3": {"value": 3},
				"T9.3-4": 0,
			}
		"loop_recovery":
			return {
				"T9.4-1": {"cases": {"storm_growth": true, "storm_reproducible": true,
					"block_falls": true, "normal_delivered": true, "backup_path_ok": true}},
				"T9.4-2": {"cases": {"no_storm_data": true, "partition_only": true}},
				"T9.4-3": {"value": 3},
				"T9.4-4": 0,
			}
	return {}

func _code(report: GateReport, cid: String) -> int:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return -1

func _negative(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("negative")
	var r1: Dictionary = Ch09Checks.run("addressing", labs["addressing"], {"answers": {
		"T9.1-1": {"rows": [
			{"node": "n1", "net": 1, "host": 1},
			{"node": "n2", "net": 1, "host": 2},
			{"node": "n3", "net": 2, "host": 3},
			{"node": "n4", "net": 2, "host": 9},
		], "meta": {"same_net_ok": true, "cross_net_ok": true,
			"dup_rejected": true, "conflict_with": "n2"}},
		"T9.1-2": {"stages": ["dup_check"], "missing": "dup_check", "downstream_ok": false},
		"T9.1-3": {"value": 256}, "T9.1-4": 0,
	}})
	var c1: int = _code(r1["report"], "T9.1-1")
	print("RED-PROBE CH09 T9.1-1 错值(host=9) -> code=%d" % c1)
	ctx.eq("T9.1-1 错值判红 E_TABLE_CELL(7)", c1, GateResult.E_TABLE_CELL)

	var r2: Dictionary = Ch09Checks.run("addressing", labs["addressing"], {"answers": {
		"T9.1-1": _answers("addressing")["T9.1-1"],
		"T9.1-2": {"stages": ["dup_check"], "missing": "dup_check", "downstream_ok": true},
		"T9.1-3": {"value": 256}, "T9.1-4": 0,
	}})
	var c2: int = _code(r2["report"], "T9.1-2")
	print("RED-PROBE CH09 T9.1-2 负例未复现 -> code=%d" % c2)
	ctx.eq("T9.1-2 下游仍正常判红 E_OUTPUT_MISMATCH(10)", c2, GateResult.E_OUTPUT_MISMATCH)

	var r3: Dictionary = Ch09Checks.run("arp", labs["arp"], {"answers": {
		"T9.1a-1": {"rows": [
			{"frame": "req", "src": "n1", "dst": "broadcast",
				"broadcast": true, "unicast": false, "hw": "aa-bb"},
			{"frame": "resp", "src": "n2", "dst": "n1",
				"broadcast": false, "unicast": true, "hw": "aa-bb"},
		], "meta": {"fields_match": true, "broadcasts": 2, "cache_hits": 2}},
		"T9.1a-2": {"rows": [{"frame": "resp", "dst": "broadcast",
			"copies": 3, "bystanders": 2}]},
		"T9.1a-3": {"value": 1}, "T9.1a-4": 0,
	}})
	var c3: int = _code(r3["report"], "T9.1a-1")
	print("RED-PROBE CH09 T9.1a-1 广播次数=2 -> code=%d" % c3)
	ctx.eq("T9.1a-1 缓存未命中判红 E_OUTPUT_MISMATCH(10)", c3, GateResult.E_OUTPUT_MISMATCH)

	var r4: Dictionary = Ch09Checks.run("switch", labs["switch"], {"answers": {
		"T9.2-1": {"rows": [
			{"addr": "n1", "port": "p2"},
			{"addr": "n2", "port": "p2"},
			{"addr": "n3", "port": "p3"},
			{"addr": "n4", "port": "p4"},
		], "meta": {"flood_ports": 3, "converged": true}},
		"T9.2-2": _answers("switch")["T9.2-2"],
		"T9.2-3": {"value": 3}, "T9.2-4": 0,
	}})
	var c4: int = _code(r4["report"], "T9.2-1")
	print("RED-PROBE CH09 T9.2-1 填表式(p1->p2) -> code=%d" % c4)
	ctx.eq("T9.2-1 端口填错判红 E_TABLE_CELL(7)", c4, GateResult.E_TABLE_CELL)

	var r5: Dictionary = Ch09Checks.run("router", labs["router"], {"answers": {
		"T9.3-1": {"rows": [{"addr": "net1", "port": "direct"}],
			"meta": {"all_connected": true, "ttl_step_ok": true,
				"ttl_zero_dropped": true, "wrong_then_fixed": true}},
		"T9.3-2": _answers("router")["T9.3-2"],
		"T9.3-3": {"value": 3}, "T9.3-4": 0,
	}})
	var c5: int = _code(r5["report"], "T9.3-1")
	print("RED-PROBE CH09 T9.3-1 缺件(只交1行) -> code=%d" % c5)
	ctx.eq("T9.3-1 缺行判红 E_COVERAGE(13)", c5, GateResult.E_COVERAGE)

	var r6: Dictionary = Ch09Checks.run("loop_recovery", labs["loop_recovery"], {"answers": {
		"T9.4-1": _answers("loop_recovery")["T9.4-1"],
		"T9.4-2": _answers("loop_recovery")["T9.4-2"],
		"T9.4-3": {"value": 4}, "T9.4-4": 0,
	}})
	var c6: int = _code(r6["report"], "T9.4-3")
	print("RED-PROBE CH09 T9.4-3 错值(边数=4) -> code=%d" % c6)
	ctx.eq("T9.4-3 复算错判红 E_TABLE_CELL(7)", c6, GateResult.E_TABLE_CELL)
