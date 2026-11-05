extends RefCounted

## Ch19 结构 + 判据校验（25 段）。
## 分母口径：required 且非 pending 的 gate 数，按 Ch19Checks.deferred_gates(cfg) 现算；
## 19.2 ADC 位数/量程与功耗阈值未定 → T19.2-1 挂 pending，4 降为 3。
## 负例断言给出精确失败码；断言能红，不是恒真。

const LABS := ["shared_medium", "embedded_budget", "sensor_loop", "firmware_rollback", "multi_terminal_alarm"]
const TOTAL_SECTIONS := 25
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260
const GATE_IDS := {"shared_medium": ["T19.1-1", "T19.1-2", "T19.1-3", "T19.1-4"], "embedded_budget": ["T19.2-1", "T19.2-2", "T19.2-3", "T19.2-4"], "sensor_loop": ["T19.3-1", "T19.3-2", "T19.3-3", "T19.3-4"], "firmware_rollback": ["T19.4-1", "T19.4-2", "T19.4-3", "T19.4-4"], "multi_terminal_alarm": ["T19.5-1", "T19.5-2", "T19.5-3", "T19.5-4"]}
const GATE_KINDS := {"shared_medium": ["table", "skip_layer", "derived_number", "quiz"], "embedded_budget": ["table", "skip_layer", "derived_number", "quiz"], "sensor_loop": ["table", "skip_layer", "derived_number", "quiz"], "firmware_rollback": ["table", "skip_layer", "derived_number", "quiz"], "multi_terminal_alarm": ["table", "skip_layer", "derived_number", "quiz"]}
const ALLOWED_KINDS := ["table", "coverage", "port_map", "page_map", "checksum",
	"derived_number", "handshake_fsm", "timeout_idle", "skip_layer", "quiz"]

const Ch19Checks = preload("res://src/core/ch19_checks.gd")
const SimSampling = preload("res://src/sim/sim_sampling.gd")
const SamplingLink = preload("res://src/core/sampling_link.gd")

const EXPECT := 92
const EXPECT_GROUPS := {"loadable": 1, "sections_present": 5, "section_count": 5, "order": 5, "text_nonempty": 5, "text_cap": 5, "screen_sum": 5, "last_after": 5, "practice": 5, "gate_count": 5, "p1_field": 5, "gate_ids": 5, "gate_kinds": 5, "gate_codes": 5, "denominator": 5, "pending_total": 1, "total_sections": 1, "positive": 5, "negative": 7, "t19_3_chain": 7}
const GROUP_DESCRIPTIONS := {"loadable": "ch19_labs.json 数据文件可读", "sections_present": "每 lab 必有非空 sections", "section_count": "每 lab 段数为 5", "order": "每 lab 内 order 连续 1..5", "text_nonempty": "每段 text 非空", "text_cap": "每段 ≤150 字（去半角空格）", "screen_sum": "同一 after 档同屏合计 ≤260", "last_after": "末段 after=3", "practice": "每节实践表 4 行且字段齐全", "gate_count": "每节 4 条 gate", "p1_field": "每节有 P1 文本与 p1_gates", "gate_ids": "gate id 按 T19.x-n 定稿", "gate_kinds": "只用既有 kind（table / skip_layer / derived_number / quiz）", "gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28", "denominator": "进分母 gate 数按 deferred_gates 现算（合计 19）", "pending_total": "全章 pending 条数=1，且进分母计数=19", "total_sections": "全篇段数 25", "positive": "5 节好答案全绿（pending 不计）", "negative": "错值/负例未复现/缺行/复算错/quiz 错/缺 answers/时延越限均精确判红", "t19_3_chain": "19.3 五段采样链路：真跑链、逐段可读、顺序/换算截断/缺段/段数声明四条负例、超限与满规模"}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch19_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch19_labs.json 可读", not labs.is_empty(), str(labs.size()))

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
		var d: Dictionary = Ch19Checks.deferred_gates(cfg)
		var pending := _pending_count(cfg)
		ctx.eq("%s 进分母（4 条 gate 去 %d pending）" % [id, pending],
			int(d["counted"]), 4 - pending)
		pending_sum += pending
		counted_sum += int(d["counted"])
		total += secs.size()
	ctx.begin_group("pending_total")
	ctx.check("全章 pending=1、进分母=19", pending_sum == 1 and counted_sum == 19,
		"pending=%d counted=%d" % [pending_sum, counted_sum])

	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var r: Dictionary = Ch19Checks.run(id, cfg, {"answers": _good(cfg)})
		ctx.begin_group("positive")
		ctx.check("%s 好答案全绿（pending=%d）" % [id, (r["pending"] as Array).size()],
			bool(r["ok"]), str(r["report"].first_failure()))

	_negative(ctx, labs)
	_chain(ctx, labs)

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
				if g.has("sampling"):
					# 19.3：好答案不是抄期望表，而是真跑一遍采样链再交原始字节/码值。
					var tr: Dictionary = SimSampling.trace(g["sampling"])
					out[cid] = {"rows": (tr["stages"] as Array).duplicate(true),
						"meta": (tr["meta"] as Dictionary).duplicate(true)}
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

func _code(report: GateReport, cid: String) -> int:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return -1

func _negative(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("negative")
	var a1 := _good(labs["shared_medium"])
	var g1: Dictionary = a1["T19.1-1"]
	var rows1: Array = (g1["rows"] as Array).duplicate(true)
	rows1[0]["collisions"] = 0
	g1["rows"] = rows1
	var r1: Dictionary = Ch19Checks.run("shared_medium", labs["shared_medium"], {"answers": a1})
	var c1: int = _code(r1["report"], "T19.1-1")
	print("RED-PROBE Ch19 T19.1-1 T19.1-1 未退避那轮冲突记成 0 -> code=%d" % c1)
	ctx.eq("T19.1-1 T19.1-1 未退避那轮冲突记成 0判红 E_TABLE_CELL", c1, GateResult.E_TABLE_CELL)

	var a2 := _good(labs["shared_medium"])
	a2["T19.1-2"] = {"stages": ["backoff_random"], "missing": "backoff_random", "downstream_ok": true}
	var r2: Dictionary = Ch19Checks.run("shared_medium", labs["shared_medium"], {"answers": a2})
	var c2: int = _code(r2["report"], "T19.1-2")
	print("RED-PROBE Ch19 T19.1-2 T19.1-2 负例未复现（退避没接却显示冲突降了） -> code=%d" % c2)
	ctx.eq("T19.1-2 T19.1-2 负例未复现（退避没接却显示冲突降了）判红 E_OUTPUT_MISMATCH", c2, GateResult.E_OUTPUT_MISMATCH)

	var a3 := _good(labs["shared_medium"])
	var g3: Dictionary = a3["T19.1-1"]
	var rows3: Array = (g3["rows"] as Array).duplicate(true)
	g3["rows"] = rows3.slice(0, 1)
	var r3: Dictionary = Ch19Checks.run("shared_medium", labs["shared_medium"], {"answers": a3})
	var c3: int = _code(r3["report"], "T19.1-1")
	print("RED-PROBE Ch19 T19.1-1 T19.1-1 只交 1/2 轮 -> code=%d" % c3)
	ctx.eq("T19.1-1 T19.1-1 只交 1/2 轮判红 E_COVERAGE", c3, GateResult.E_COVERAGE)

	var a4 := _good(labs["shared_medium"])
	var g4: Dictionary = a4["T19.1-3"]
	var v4: Dictionary = (g4["values"] as Dictionary).duplicate(true)
	v4["expected_collisions"] = 3
	g4["values"] = v4
	var r4: Dictionary = Ch19Checks.run("shared_medium", labs["shared_medium"], {"answers": a4})
	var c4: int = _code(r4["report"], "T19.1-3")
	print("RED-PROBE Ch19 T19.1-3 T19.1-3 期望冲突数算错 -> code=%d" % c4)
	ctx.eq("T19.1-3 T19.1-3 期望冲突数算错判红 E_TABLE_CELL", c4, GateResult.E_TABLE_CELL)

	var a5 := _good(labs["shared_medium"])
	a5["T19.1-4"] = 3
	var r5: Dictionary = Ch19Checks.run("shared_medium", labs["shared_medium"], {"answers": a5})
	var c5: int = _code(r5["report"], "T19.1-4")
	print("RED-PROBE Ch19 T19.1-4 T19.1-4 选错项 -> code=%d" % c5)
	ctx.eq("T19.1-4 T19.1-4 选错项判红 E_QUIZ", c5, GateResult.E_QUIZ)

	var a6 := _good(labs["multi_terminal_alarm"])
	a6["T19.5-1"] = {}
	var r6: Dictionary = Ch19Checks.run("multi_terminal_alarm", labs["multi_terminal_alarm"], {"answers": a6})
	var c6: int = _code(r6["report"], "T19.5-1")
	print("RED-PROBE Ch19 T19.5-1 T19.5-1 缺 rows -> code=%d" % c6)
	ctx.eq("T19.5-1 T19.5-1 缺 rows判红 E_UNCONNECTED", c6, GateResult.E_UNCONNECTED)

	var a7 := _good(labs["multi_terminal_alarm"])
	var g7: Dictionary = a7["T19.5-1"]
	var rows7: Array = (g7["rows"] as Array).duplicate(true)
	rows7[0]["sched_ms"] = 90
	g7["rows"] = rows7
	var r7: Dictionary = Ch19Checks.run("multi_terminal_alarm", labs["multi_terminal_alarm"], {"answers": a7})
	var c7: int = _code(r7["report"], "T19.5-1")
	print("RED-PROBE Ch19 T19.5-1 T19.5-1 第 1 台调度 90 超过上限 50 -> code=%d" % c7)
	ctx.eq("T19.5-1 T19.5-1 第 1 台调度 90 超过上限 50判红 E_DELAY_MISMATCH", c7, GateResult.E_DELAY_MISMATCH)

func _case_actual(report: GateReport, cid: String) -> Dictionary:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			var a: Variant = c.get("actual", {})
			return a if a is Dictionary else {}
	return {}

## 合法 N 段链：sample → receive → quantize → (N-4 段 pass) → store。
## 与 data 里的五段链同一种 op 语义，只是段数可变，用来验上限与满规模。
func _chain_cfg(stages: int) -> Dictionary:
	var arr := []
	arr.append({"stage": "send", "node": "sensor", "op": "sample", "ms": 20})
	arr.append({"stage": "recv", "node": "adc", "op": "receive", "ms": 20})
	arr.append({"stage": "parse", "node": "adc", "op": "quantize", "ms": 20})
	for i in range(stages - 4):
		arr.append({"stage": "hop%d" % (i + 1), "node": "mcu", "op": "pass", "ms": 20})
	arr.append({"stage": "store", "node": "server", "op": "store", "ms": 20})
	return {"sensor_v": 0.5, "vref": 2.0, "bits": 8,
		"stage_count": stages, "stages": arr}

## 19.3 五段采样链路：真跑链、逐段可读、四条负例、超限与满规模。
func _chain(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("t19_3_chain")
	var cfg: Dictionary = labs["sensor_loop"]
	var gr: Dictionary = Ch19Checks.run("sensor_loop", cfg, {"answers": _good(cfg)})
	var act := _case_actual(gr["report"], "T19.3-1")
	var chain: Array = act.get("chain", [])
	var rows: Array = act.get("rows", [])
	var read_ok := bool(gr["ok"]) and chain.size() == 5 and rows.size() == 5
	for raw in chain:
		if not (raw is Dictionary):
			read_ok = false
			continue
		var s: Dictionary = raw
		read_ok = read_ok and s.has("stage") and s.has("node") and s.has("in_raw") \
			and s.has("out_raw") and s.has("code") and s.has("sample_ms")
	ctx.check("T19.3-1 好答案全绿且五段逐段可读（actual.chain 带 stage/node/in_raw/out_raw/code/sample_ms）",
		read_ok, "chain=%d rows=%d" % [chain.size(), rows.size()])

	# ① 五段顺序错位：parse 与 apply 对调 → 10（语义错，不能被普通填错 7 吞掉）。
	var a1 := _good(cfg)
	var g1: Dictionary = a1["T19.3-1"]
	var r1: Array = (g1["rows"] as Array).duplicate(true)
	var tmp: Variant = r1[2]
	r1[2] = r1[3]
	r1[3] = tmp
	g1["rows"] = r1
	a1["T19.3-1"] = g1
	var n1: Dictionary = Ch19Checks.run("sensor_loop", cfg, {"answers": a1})
	var c1: int = _code(n1["report"], "T19.3-1")
	print("RED-PROBE Ch19 T19.3-1 五段顺序错位（parse/apply 对调） -> code=%d" % c1)
	ctx.eq("T19.3-1 五段顺序错位判红 E_OUTPUT_MISMATCH", c1, GateResult.E_OUTPUT_MISMATCH)

	# ② 某段原始码值被换算成人话：parse 的 out_raw 40 → "0.5 v" → 7。
	var a2 := _good(cfg)
	var g2: Dictionary = a2["T19.3-1"]
	var r2: Array = (g2["rows"] as Array).duplicate(true)
	var p2: Dictionary = r2[2]
	p2["out_raw"] = "0.5 v"
	r2[2] = p2
	g2["rows"] = r2
	a2["T19.3-1"] = g2
	var n2: Dictionary = Ch19Checks.run("sensor_loop", cfg, {"answers": a2})
	var c2: int = _code(n2["report"], "T19.3-1")
	print("RED-PROBE Ch19 T19.3-1 第 3 段 parse 的 out_raw 由 40 换算成 0.5 v -> code=%d" % c2)
	ctx.eq("T19.3-1 某段原始码值被换算判红 E_TABLE_CELL", c2, GateResult.E_TABLE_CELL)

	# ③ 缺一段：删掉 apply → 行数 4 ≠ 链路 5 → 13。
	var a3 := _good(cfg)
	var g3: Dictionary = a3["T19.3-1"]
	var r3: Array = (g3["rows"] as Array).duplicate(true)
	r3.remove_at(3)
	g3["rows"] = r3
	a3["T19.3-1"] = g3
	var n3: Dictionary = Ch19Checks.run("sensor_loop", cfg, {"answers": a3})
	var c3: int = _code(n3["report"], "T19.3-1")
	print("RED-PROBE Ch19 T19.3-1 删掉 apply 只剩 4 段 -> code=%d" % c3)
	ctx.eq("T19.3-1 缺一段判红 E_COVERAGE", c3, GateResult.E_COVERAGE)

	# ④ 段数与网关声明不符：五段齐全但 meta.stage_count=4 → 10。
	var a4 := _good(cfg)
	var g4: Dictionary = a4["T19.3-1"]
	var m4: Dictionary = (g4["meta"] as Dictionary).duplicate(true)
	m4["stage_count"] = 4
	g4["meta"] = m4
	a4["T19.3-1"] = g4
	var n4: Dictionary = Ch19Checks.run("sensor_loop", cfg, {"answers": a4})
	var c4: int = _code(n4["report"], "T19.3-1")
	print("RED-PROBE Ch19 T19.3-1 meta.stage_count 交 4、网关声明 5 -> code=%d" % c4)
	ctx.eq("T19.3-1 段数与网关声明不符判红 E_OUTPUT_MISMATCH", c4, GateResult.E_OUTPUT_MISMATCH)

	# 上限：33 段超 MAX_STAGES=32 → 7，且不返回任何截断后的段。
	var over_cfg := _chain_cfg(SimSampling.MAX_STAGES + 1)
	var over: Dictionary = SimSampling.trace(over_cfg)
	var over_ok := int(over.get("code", -1)) == GateResult.E_TABLE_CELL \
		and (over.get("stages", []) as Array).is_empty()
	print("RED-PROBE Ch19 T19.3-1 段数 %d 超过上限 %d（不截断） -> code=%d stages=%d"
		% [SimSampling.MAX_STAGES + 1, SimSampling.MAX_STAGES,
			int(over.get("code", -1)), (over.get("stages", []) as Array).size()])
	ctx.check("段数超上限判红 E_TABLE_CELL 且不静默截断", over_ok, str(over))

	# 合法满规模：正好 32 段（= 上限）也要绿；当前真实链 5 段，余量 6.4×。
	var full_cfg := _chain_cfg(SimSampling.MAX_STAGES)
	var full: Dictionary = SimSampling.trace(full_cfg)
	var fres: Dictionary = SamplingLink.validate_gate(
		{"rows": full["stages"], "meta": full["meta"]}, full_cfg)
	var margin := float(SimSampling.MAX_STAGES) / 5.0
	var full_ok := bool(full.get("ok", false)) and bool(fres.get("ok", false)) and margin >= 6.0
	print("GREEN-PROBE Ch19 T19.3-1 合法满规模 %d/%d 段（余量 %.1fx） -> ok=%s"
		% [(full["stages"] as Array).size(), SimSampling.MAX_STAGES, margin, str(full_ok)])
	ctx.check("合法满规模 32 段通过且余量 ≥6x", full_ok,
		"stages=%d ok=%s" % [(full["stages"] as Array).size(), str(full_ok)])

