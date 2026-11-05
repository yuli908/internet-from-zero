extends RefCounted

## Ch18 结构 + 判据校验（20 段）。
## 分母口径：required 且非 pending 的 gate 数，按 Ch18Checks.deferred_gates(cfg) 现算；
## 18.1 密钥流生成与逐字节导出未批 → T18.1-1 挂 pending，4 降为 3。
## 负例断言给出精确失败码；断言能红，不是恒真。

const LABS := ["xor_cipher", "key_exchange", "hash_cert", "mitm_lab"]
const TOTAL_SECTIONS := 20
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260
const GATE_IDS := {"xor_cipher": ["T18.1-1", "T18.1-2", "T18.1-3", "T18.1-4"], "key_exchange": ["T18.2-1", "T18.2-2", "T18.2-3", "T18.2-4"], "hash_cert": ["T18.3-1", "T18.3-2", "T18.3-3", "T18.3-4"], "mitm_lab": ["T18.4-1", "T18.4-2", "T18.4-3", "T18.4-4"]}
const GATE_KINDS := {"xor_cipher": ["table", "skip_layer", "derived_number", "quiz"], "key_exchange": ["table", "skip_layer", "derived_number", "quiz"], "hash_cert": ["table", "skip_layer", "derived_number", "quiz"], "mitm_lab": ["table", "skip_layer", "derived_number", "quiz"]}
const ALLOWED_KINDS := ["table", "coverage", "port_map", "page_map", "checksum",
	"derived_number", "handshake_fsm", "timeout_idle", "skip_layer", "quiz"]

const Ch18Checks = preload("res://src/core/ch18_checks.gd")

const EXPECT := 77
const EXPECT_GROUPS := {"loadable": 1, "sections_present": 4, "section_count": 4, "order": 4, "text_nonempty": 4, "text_cap": 4, "screen_sum": 4, "last_after": 4, "practice": 4, "gate_count": 4, "p1_field": 4, "gate_ids": 4, "gate_kinds": 4, "gate_codes": 4, "denominator": 4, "pending_total": 1, "total_sections": 1, "positive": 4, "negative": 7, "t18_4_script": 7}
const GROUP_DESCRIPTIONS := {"loadable": "ch18_labs.json 数据文件可读", "sections_present": "每 lab 必有非空 sections", "section_count": "每 lab 段数为 5", "order": "每 lab 内 order 连续 1..5", "text_nonempty": "每段 text 非空", "text_cap": "每段 ≤150 字（去半角空格）", "screen_sum": "同一 after 档同屏合计 ≤260", "last_after": "末段 after=3", "practice": "每节实践表 4 行且字段齐全", "gate_count": "每节 4 条 gate", "p1_field": "每节有 P1 文本与 p1_gates", "gate_ids": "gate id 按 T18.x-n 定稿", "gate_kinds": "只用既有 kind（table / skip_layer / derived_number / quiz）", "gate_codes": "失败码在白名单 3/5/7/8/9/10/13/14/15/27，且无 26/28", "denominator": "进分母 gate 数按 deferred_gates 现算（合计 15）", "pending_total": "全章 pending 条数=1，且进分母计数=15", "total_sections": "全篇段数 20", "positive": "4 节好答案全绿（pending 不计）", "negative": "错值/负例未复现/缺行/复算错/quiz 错/缺 answers/时延越限均精确判红", "t18_4_script": "剧本开关与证书结果可指认：两遍相反、下游可读、开关开启写通过(10)、证书校验不符(10)、关开关结果缺失(7)、链上 sig_ok 错(10)"}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch18_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch18_labs.json 可读", not labs.is_empty(), str(labs.size()))

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
		var d: Dictionary = Ch18Checks.deferred_gates(cfg)
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
		var r: Dictionary = Ch18Checks.run(id, cfg, {"answers": _good(cfg)})
		ctx.begin_group("positive")
		ctx.check("%s 好答案全绿（pending=%d）" % [id, (r["pending"] as Array).size()],
			bool(r["ok"]), str(r["report"].first_failure()))

	_negative(ctx, labs)
	_t18_4_script(ctx, labs)

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
				var rows_good: Array = (g.get("expect_rows", []) as Array).duplicate(true)
				if g.has("script"):
					_merge_script(rows_good, g.get("script", {}))
				out[cid] = {"rows": rows_good,
					"meta": (g.get("expect_meta", {}) as Dictionary).duplicate(true)}
			"skip_layer":
				var st := str(g.get("stage", ""))
				out[cid] = {"stages": [st, "downstream"], "missing": st, "downstream_ok": false}
			"derived_number":
				out[cid] = {"values": (g.get("expect_values", {}) as Dictionary).duplicate(true)}
			"quiz":
				out[cid] = int((g.get("quiz", {}) as Dictionary).get("answer", 0))
	return out

## 剧本字段（19 §2.8）合进表行：好答案必须交 switch/cert_verify/result/reason/chain，
## 不能只交 intercepted/rejected 两个布尔位，否则下游读不出"开关是哪档、拒在哪一级"。
func _merge_script(rows: Array, script: Dictionary) -> void:
	var key := str(script.get("row_key", "phase"))
	var phases: Dictionary = script.get("phases", {})
	for phase in phases:
		var wp: Dictionary = phases[phase]
		for raw in rows:
			if not (raw is Dictionary):
				continue
			var row: Dictionary = raw
			if str(row.get(key, "")) != phase:
				continue
			row["switch"] = str(wp.get("switch", ""))
			row["cert_verify"] = bool(wp.get("cert_verify", false))
			row["result"] = str(wp.get("expect", ""))
			row["reason"] = str(wp.get("reason", ""))
			row["chain"] = (wp.get("chain", []) as Array).duplicate(true)

func _gate(cfg: Dictionary, id: String) -> Dictionary:
	for raw in (cfg.get("gate_cases", []) as Array):
		if str((raw as Dictionary).get("id", "")) == id:
			return raw
	return {}

func _case(report: GateReport, cid: String) -> Dictionary:
	for raw in report.cases:
		var c: Dictionary = raw
		if str(c.get("id", "")) == cid:
			return c
	return {}

## 下游读取点：成功 case 的 actual.rows 必须逐行带开关/证书结论/理由/链，且类型可读。
func _downstream_ok(rows: Array) -> bool:
	if rows.is_empty():
		return false
	for raw in rows:
		if not (raw is Dictionary):
			return false
		var row: Dictionary = raw
		if not ["on", "off"].has(str(row.get("switch", ""))):
			return false
		if typeof(row.get("cert_verify", null)) != TYPE_BOOL:
			return false
		if not ["intercepted", "rejected", "pass"].has(str(row.get("result", ""))):
			return false
		if typeof(row.get("reason", null)) != TYPE_STRING:
			return false
		var chain_v: Variant = row.get("chain", null)
		if not (chain_v is Array) or (chain_v as Array).is_empty():
			return false
		for cn in chain_v:
			if not (cn is Dictionary):
				return false
			if typeof((cn as Dictionary).get("sig_ok", null)) != TYPE_BOOL:
				return false
	return true

## 18.4 剧本开关与证书结果（提案 19 §2.8）：两遍剧本相反 → 下游可读 → 三条负例精确判红。
func _t18_4_script(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("t18_4_script")
	var cfg: Dictionary = labs.get("mitm_lab", {})
	var gate: Dictionary = _gate(cfg, "T18.4-1")
	var phases: Dictionary = (gate.get("script", {}) as Dictionary).get("phases", {})
	var off: Dictionary = phases.get("verify_off", {})
	var on: Dictionary = phases.get("verify_on", {})
	ctx.check("T18.4-1 两遍剧本开关相反、要求结果相反",
		str(off.get("switch", "")) == "off" and str(on.get("switch", "")) == "on" \
			and str(off.get("expect", "")) == "intercepted" \
			and str(on.get("expect", "")) == "rejected" \
			and bool(off.get("cert_verify", true)) == false \
			and bool(on.get("cert_verify", false)) == true,
		"off=%s/%s cv=%s；on=%s/%s cv=%s" % [str(off.get("switch", "")),
			str(off.get("expect", "")), str(off.get("cert_verify", null)),
			str(on.get("switch", "")), str(on.get("expect", "")),
			str(on.get("cert_verify", null))])

	var good := _good(cfg)
	var r0: Dictionary = Ch18Checks.run("mitm_lab", cfg, {"answers": good})
	var c0: Dictionary = _case(r0["report"], "T18.4-1")
	ctx.check("T18.4-1 剧本齐全的好答案全绿", bool(r0["ok"]),
		str((r0["report"] as GateReport).first_failure()))
	var rows0: Array = ((c0.get("actual", {}) as Dictionary).get("rows", []) as Array)
	if rows0.size() >= 2:
		print("GREEN-PROBE Ch18 T18.4-1 下游读取 actual.rows 行数=%d switch=%s/%s result=%s/%s"
			% [rows0.size(),
				str((rows0[0] as Dictionary).get("switch", "?")),
				str((rows0[1] as Dictionary).get("switch", "?")),
				str((rows0[0] as Dictionary).get("result", "?")),
				str((rows0[1] as Dictionary).get("result", "?"))])
	else:
		print("GREEN-PROBE Ch18 T18.4-1 下游读取 actual.rows 行数=%d（不足以展示）"
			% rows0.size())
	ctx.check("下游可逐行读 switch/cert_verify/result/reason/chain（非单一布尔位）",
		_downstream_ok(rows0), "rows=%d" % rows0.size())

	# ① 开关开着，却把结果写成通过（剧本要求拒绝）→ 10。
	var a1 := _good(cfg)
	var g1: Dictionary = a1["T18.4-1"]
	var rows1: Array = (g1["rows"] as Array).duplicate(true)
	for raw in rows1:
		if str((raw as Dictionary).get("phase", "")) == "verify_on":
			raw["intercepted"] = false
			raw["rejected"] = false
			raw["result"] = "pass"
	g1["rows"] = rows1
	var r1: Dictionary = Ch18Checks.run("mitm_lab", cfg, {"answers": a1})
	var c1: int = _code(r1["report"], "T18.4-1")
	print("RED-PROBE Ch18 T18.4-1 开关开着却写通过（剧本要拒绝） -> code=%d" % c1)
	ctx.eq("T18.4-1 开关开启时结果写成通过判红 E_OUTPUT_MISMATCH",
		c1, GateResult.E_OUTPUT_MISMATCH)

	# ② 证书校验结果与剧本不符（开验证那遍交 cert_verify=false）→ 10。
	var a2 := _good(cfg)
	var g2: Dictionary = a2["T18.4-1"]
	var rows2: Array = (g2["rows"] as Array).duplicate(true)
	for raw in rows2:
		if str((raw as Dictionary).get("phase", "")) == "verify_on":
			raw["cert_verify"] = false
	g2["rows"] = rows2
	var r2: Dictionary = Ch18Checks.run("mitm_lab", cfg, {"answers": a2})
	var c2: int = _code(r2["report"], "T18.4-1")
	print("RED-PROBE Ch18 T18.4-1 证书校验结果与剧本不符 -> code=%d" % c2)
	ctx.eq("T18.4-1 证书校验结果与剧本不符判红 E_OUTPUT_MISMATCH",
		c2, GateResult.E_OUTPUT_MISMATCH)

	# ③ 开关关闭那遍结果字段缺失（只交开关不交结果）→ 7。
	var a3 := _good(cfg)
	var g3: Dictionary = a3["T18.4-1"]
	var rows3: Array = (g3["rows"] as Array).duplicate(true)
	for raw in rows3:
		if str((raw as Dictionary).get("phase", "")) == "verify_off":
			raw.erase("intercepted")
	g3["rows"] = rows3
	var r3: Dictionary = Ch18Checks.run("mitm_lab", cfg, {"answers": a3})
	var c3: int = _code(r3["report"], "T18.4-1")
	print("RED-PROBE Ch18 T18.4-1 开关关闭时结果字段缺失 -> code=%d" % c3)
	ctx.eq("T18.4-1 开关关闭时结果字段缺失判红 E_TABLE_CELL", c3, GateResult.E_TABLE_CELL)

	# ④ 拒因落到具体一级：链上第 1 级 sig_ok 与剧本不符 → 10，detail 点名该级。
	var a4 := _good(cfg)
	var g4: Dictionary = a4["T18.4-1"]
	var rows4: Array = (g4["rows"] as Array).duplicate(true)
	for raw in rows4:
		if str((raw as Dictionary).get("phase", "")) == "verify_on":
			var chain4: Array = (raw as Dictionary)["chain"]
			(chain4[0] as Dictionary)["sig_ok"] = true
	g4["rows"] = rows4
	var r4: Dictionary = Ch18Checks.run("mitm_lab", cfg, {"answers": a4})
	var c4: int = _code(r4["report"], "T18.4-1")
	print("RED-PROBE Ch18 T18.4-1 证书链第 1 级 sig_ok 与剧本不符 -> code=%d" % c4)
	ctx.eq("T18.4-1 证书链逐级结论与剧本不符判红 E_OUTPUT_MISMATCH",
		c4, GateResult.E_OUTPUT_MISMATCH)

func _code(report: GateReport, cid: String) -> int:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return -1

func _negative(ctx: TestContext, labs: Dictionary) -> void:
	ctx.begin_group("negative")
	var a1 := _good(labs["key_exchange"])
	var g1: Dictionary = a1["T18.2-1"]
	var rows1: Array = (g1["rows"] as Array).duplicate(true)
	rows1[0]["session_fp"] = "0000"
	g1["rows"] = rows1
	var r1: Dictionary = Ch18Checks.run("key_exchange", labs["key_exchange"], {"answers": a1})
	var c1: int = _code(r1["report"], "T18.2-1")
	print("RED-PROBE Ch18 T18.2-1 T18.2-1 两端指纹对不上 -> code=%d" % c1)
	ctx.eq("T18.2-1 T18.2-1 两端指纹对不上判红 E_TABLE_CELL", c1, GateResult.E_TABLE_CELL)

	var a2 := _good(labs["key_exchange"])
	a2["T18.2-2"] = {"stages": ["key_exchange"], "missing": "key_exchange", "downstream_ok": true}
	var r2: Dictionary = Ch18Checks.run("key_exchange", labs["key_exchange"], {"answers": a2})
	var c2: int = _code(r2["report"], "T18.2-2")
	print("RED-PROBE Ch18 T18.2-2 T18.2-2 负例未复现（公钥没参与仍显示一致） -> code=%d" % c2)
	ctx.eq("T18.2-2 T18.2-2 负例未复现（公钥没参与仍显示一致）判红 E_OUTPUT_MISMATCH", c2, GateResult.E_OUTPUT_MISMATCH)

	var a3 := _good(labs["key_exchange"])
	var g3: Dictionary = a3["T18.2-1"]
	var rows3: Array = (g3["rows"] as Array).duplicate(true)
	g3["rows"] = rows3.slice(0, 1)
	var r3: Dictionary = Ch18Checks.run("key_exchange", labs["key_exchange"], {"answers": a3})
	var c3: int = _code(r3["report"], "T18.2-1")
	print("RED-PROBE Ch18 T18.2-1 T18.2-1 只交 1/2 端 -> code=%d" % c3)
	ctx.eq("T18.2-1 T18.2-1 只交 1/2 端判红 E_COVERAGE", c3, GateResult.E_COVERAGE)

	var a4 := _good(labs["key_exchange"])
	var g4: Dictionary = a4["T18.2-3"]
	var v4: Dictionary = (g4["values"] as Dictionary).duplicate(true)
	v4["mod_value"] = 242
	g4["values"] = v4
	var r4: Dictionary = Ch18Checks.run("key_exchange", labs["key_exchange"], {"answers": a4})
	var c4: int = _code(r4["report"], "T18.2-3")
	print("RED-PROBE Ch18 T18.2-3 T18.2-3 模幂算错 -> code=%d" % c4)
	ctx.eq("T18.2-3 T18.2-3 模幂算错判红 E_TABLE_CELL", c4, GateResult.E_TABLE_CELL)

	var a5 := _good(labs["key_exchange"])
	a5["T18.2-4"] = 3
	var r5: Dictionary = Ch18Checks.run("key_exchange", labs["key_exchange"], {"answers": a5})
	var c5: int = _code(r5["report"], "T18.2-4")
	print("RED-PROBE Ch18 T18.2-4 T18.2-4 选错项 -> code=%d" % c5)
	ctx.eq("T18.2-4 T18.2-4 选错项判红 E_QUIZ", c5, GateResult.E_QUIZ)

	var a6 := _good(labs["mitm_lab"])
	a6["T18.4-1"] = {}
	var r6: Dictionary = Ch18Checks.run("mitm_lab", labs["mitm_lab"], {"answers": a6})
	var c6: int = _code(r6["report"], "T18.4-1")
	print("RED-PROBE Ch18 T18.4-1 T18.4-1 缺 rows -> code=%d" % c6)
	ctx.eq("T18.4-1 T18.4-1 缺 rows判红 E_UNCONNECTED", c6, GateResult.E_UNCONNECTED)

	var a7 := _good(labs["mitm_lab"])
	var g7: Dictionary = a7["T18.4-1"]
	var rows7: Array = (g7["rows"] as Array).duplicate(true)
	rows7[0]["handshake_ms"] = 90
	g7["rows"] = rows7
	var r7: Dictionary = Ch18Checks.run("mitm_lab", labs["mitm_lab"], {"answers": a7})
	var c7: int = _code(r7["report"], "T18.4-1")
	print("RED-PROBE Ch18 T18.4-1 T18.4-1 关验证那遍握手 90 超过上限 50 -> code=%d" % c7)
	ctx.eq("T18.4-1 T18.4-1 关验证那遍握手 90 超过上限 50判红 E_DELAY_MISMATCH", c7, GateResult.E_DELAY_MISMATCH)
