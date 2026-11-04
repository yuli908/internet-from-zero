extends RefCounted

## CH05 四节（21 段）结构 + P1 判据校验。
## 分母口径：required 且非 pending 的 gate 数，按数据现算，不写死。
## 5.1 的 waveform_align 由 `WaveformAlign` 实现（另一会话），本套件按契约验证数据可被它判绿/判红。
## 所有判据断言都给反例：断言必须能红，不是恒真。

const LABS := ["datapath", "isa8", "first_program", "clock_limit"]
const SECTION_COUNTS := {"datapath": 5, "isa8": 5, "first_program": 5, "clock_limit": 6}
const TOTAL_SECTIONS := 21
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260

const Ch05 = preload("res://src/core/ch05_checks.gd")
const Teach = preload("res://src/ui/teaching.gd")

const EXPECT := 210
const EXPECT_GROUPS := {
	"loadable": 1, "sections_present": 4, "section_count": 4, "total_sections": 1,
	"order": 21, "after_unlock": 21, "after_bound": 21, "text_nonempty": 21, "text_cap": 21,
	"screen_sum": 16, "last_after": 4, "after_required": 4, "fallback": 8,
	"denominator": 4, "gate_ids": 4, "gate_count": 4, "required_count": 4, "gate_codes": 4,
	"practice": 8, "p1_field": 4, "no_pending": 1, "waveform_ready": 1,
	"judge_datapath": 7, "judge_isa": 7, "judge_program": 6, "judge_clock": 9,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch05_labs 数据文件可读",
	"sections_present": "每 lab 必有非空 sections",
	"section_count": "每 lab 段数与课文一致（5/5/5/6）",
	"total_sections": "全篇段数 21",
	"order": "每 lab 内 order 连续",
	"after_unlock": "首段 after=0、其余单调不减",
	"after_bound": "每段 after ≤ required−1",
	"text_nonempty": "每段 text 非空",
	"text_cap": "每段 ≤150 字（左栏口径，去半角空格）",
	"screen_sum": "同一 after 档同屏合计 ≤260",
	"last_after": "末段 after = required−1",
	"after_required": "最大 after 落在 required−1（不按分母缩）",
	"fallback": "删掉 sections 的副本退回 body",
	"denominator": "进分母 gate 数按 required 去 pending 现算",
	"gate_ids": "gate id 按 T5.x-n 顺序且与课文提案一致",
	"gate_count": "每节 gate 条数（5.4 含一条非 required quiz）",
	"required_count": "每节 required gate 数为 4",
	"gate_codes": "gate 失败码只用白名单 3/5/7/8/9/10/13/14/15/27",
	"practice": "每节有实践表且每行 id/level/produce/judge 齐全",
	"p1_field": "每节有 P1 文本与 p1_gates",
	"no_pending": "CH05 无 pending kind（waveform_align 已接入）",
	"waveform_ready": "5.1 waveform_align 带契约字段（waveform/stage_signals/final_signal）",
	"judge_datapath": "5.1 P1：终值/波形/控制线三个 gate 判绿与各自反例",
	"judge_isa": "5.2 P1：控制表行与 16 条单步判绿、错行/漏条/空码未拒的反例",
	"judge_program": "5.3 P1：两条程序判绿，输出错、不停机、边界未测的反例",
	"judge_clock": "5.4 P1：首坏拍/同频复测/手填/算式判绿与反例",
}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch05_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch05_labs 可读", not labs.is_empty(), str(labs.size()))
	ctx.begin_group("no_pending")
	ctx.check("CH05 pending_kinds 为空（waveform_align 已接入）",
		(cfg_all.get("pending_kinds", {}) as Dictionary).is_empty(),
		str(cfg_all.get("pending_kinds", {})))

	var total := 0
	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var secs: Array = cfg.get("sections", [])
		ctx.begin_group("sections_present")
		ctx.check("%s 有 sections" % id, not secs.is_empty(), str(secs.size()))
		ctx.begin_group("section_count")
		ctx.eq("%s 段数" % id, secs.size(), int(SECTION_COUNTS[id]))
		_structural(ctx, id, cfg, secs)
		total += secs.size()
		_contract(ctx, id, cfg, labs)
	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	_judge_datapath(ctx, labs.get("datapath", {}))
	_judge_isa(ctx, labs.get("isa8", {}))
	_judge_program(ctx, labs.get("first_program", {}))
	_judge_clock(ctx, labs.get("clock_limit", {}))
	print("DEBUG_GROUPS ", ctx.group_counts)

func _structural(ctx: TestContext, id: String, cfg: Dictionary, secs: Array) -> void:
	var req := _required_count(cfg)
	var prev_after := -1
	var max_after := -1
	var screen := {}
	for i in secs.size():
		var s: Dictionary = secs[i]
		var order := int(s.get("order", -1))
		var after := int(s.get("after", -1))
		var text := str(s.get("text", ""))
		var text_len := text.replace(" ", "").length()
		ctx.begin_group("order")
		ctx.eq("%s[%d] order 连续" % [id, i + 1], order, i + 1)
		ctx.begin_group("after_unlock")
		if i == 0:
			ctx.eq("%s 首段 after=0" % id, after, 0)
		else:
			ctx.check("%s[%d] after 单调不减" % [id, i + 1], after >= prev_after,
				"%d < %d" % [after, prev_after])
		ctx.begin_group("after_bound")
		ctx.check("%s[%d] after ≤ required−1" % [id, i + 1], after <= req - 1,
			"after=%d required=%d" % [after, req])
		ctx.begin_group("text_nonempty")
		ctx.check("%s[%d] text 非空" % [id, i + 1], not text.strip_edges().is_empty())
		ctx.begin_group("text_cap")
		ctx.check("%s[%d] text ≤150 字" % [id, i + 1], text_len <= LEFT_LIMIT, str(text_len))
		screen[after] = int(screen.get(after, 0)) + text_len
		max_after = maxi(max_after, after)
		prev_after = after
	var last_after := int((secs[secs.size() - 1] as Dictionary).get("after", -1))
	ctx.begin_group("last_after")
	ctx.check("%s 末段 after = required−1" % id, last_after == req - 1,
		"last=%d required=%d" % [last_after, req])
	ctx.begin_group("after_required")
	ctx.check("%s 最大 after = required−1" % id, max_after == req - 1,
		"max=%d required=%d" % [max_after, req])
	ctx.begin_group("screen_sum")
	for after in screen.keys():
		ctx.check("%s after=%d 同屏合计 ≤260" % [id, int(after)], int(screen[after]) <= SCREEN_LIMIT,
			str(screen[after]))
	ctx.begin_group("fallback")
	var copy: Dictionary = JSON.parse_string(JSON.stringify(cfg))
	copy.erase("sections")
	ctx.check("%s 无 sections 时 body 非空" % id, not str(copy.get("body", "")).strip_edges().is_empty())
	ctx.check("%s 无 sections 时退回 body" % id, Teach.has_teaching(copy), Teach.teaching_text(copy))

func _contract(ctx: TestContext, id: String, cfg: Dictionary, labs: Dictionary) -> void:
	var req := _required_count(cfg)
	var cases: Array = cfg.get("gate_cases", [])
	var d: Dictionary = Ch05.deferred_gates(cfg)
	ctx.begin_group("denominator")
	ctx.eq("%s 进分母 gate 数" % id, int(d["counted"]), req)
	ctx.begin_group("gate_count")
	ctx.eq("%s gate 条数" % id, cases.size(), 4 + (1 if id == "clock_limit" else 0))
	ctx.begin_group("required_count")
	ctx.eq("%s required 数" % id, req, 4)
	ctx.begin_group("gate_ids")
	var ids := []
	for raw in cases:
		ids.append(str((raw as Dictionary).get("id", "")))
	ctx.check("%s gate id 顺序与课文提案一致" % id, _ids_ok(id, ids), str(ids))
	ctx.begin_group("gate_codes")
	var bad := []
	var re := RegEx.new()
	re.compile("(\\d+)")
	for raw in cases:
		for code in (raw as Dictionary).get("codes", []):
			var m := re.search(str(code))
			if m == null or not LabGateKit.ALLOWED_CODES.has(int(m.get_string(1))):
				bad.append(str(code))
	ctx.check("%s 失败码在白名单内（无 26/28）" % id, bad.is_empty(), str(bad))
	ctx.begin_group("practice")
	var practice: Array = cfg.get("practice", [])
	ctx.check("%s 有实践表" % id, not practice.is_empty(), str(practice.size()))
	var incomplete := []
	for raw in practice:
		var row: Dictionary = raw
		for key in ["id", "level", "produce", "judge"]:
			if str(row.get(key, "")).strip_edges().is_empty():
				incomplete.append("%s.%s" % [str(row.get("id", "?")), key])
	ctx.check("%s 实践表字段齐全" % id, incomplete.is_empty(), str(incomplete))
	ctx.begin_group("p1_field")
	var p1 := str(cfg.get("p1", ""))
	var p1_gates: Array = cfg.get("p1_gates", [])
	ctx.check("%s 有 P1 文本与 p1_gates" % id, not p1.strip_edges().is_empty() and not p1_gates.is_empty(), p1)
	ctx.begin_group("waveform_ready")
	if id == "datapath":
		var wc := _gate(cfg, "T5.1-2")
		ctx.check("5.1 waveform_align 契约字段齐全且 status=ready",
			wc.has("waveform") and wc.has("stage_signals") and wc.has("final_signal")
			and str(wc.get("status", "ready")) == "ready", str(wc.keys()))

func _ids_ok(id: String, ids: Array) -> bool:
	var prefix := ""
	var n := 0
	match id:
		"datapath": prefix = "T5.1-"; n = 4
		"isa8": prefix = "T5.2-"; n = 4
		"first_program": prefix = "T5.3-"; n = 4
		"clock_limit": prefix = "T5.4-"; n = 5
	if ids.size() != n:
		return false
	for i in n:
		if str(ids[i]) != "%s%d" % [prefix, i + 1]:
			return false
	return true

func _required_count(cfg: Dictionary) -> int:
	var req := 0
	for raw in cfg.get("gate_cases", []):
		if bool((raw as Dictionary).get("required", false)):
			req += 1
	return req

func _gate(cfg: Dictionary, cid: String) -> Dictionary:
	for raw in cfg.get("gate_cases", []):
		if str((raw as Dictionary).get("id", "")) == cid:
			return raw
	return {}

func _run(cfg: Dictionary, answers: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var inputs := {"answers": answers}
	for k in extra:
		inputs[k] = extra[k]
	return Ch05.run(str(cfg.get("id", "")), cfg, inputs)

func _codes(rep: GateReport) -> Array:
	return rep.failure_codes()

# ---------------------------------------------------------------- 5.1

func _judge_datapath(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T5.1-1": {"regs": {"R1": 3, "R2": 5, "R3": 8}, "ticks": 4},
		"T5.1-2": {"final_value": 8,
			"spans": {"fetch": {"start": 0, "end": 1}, "decode": {"start": 2, "end": 2},
				"execute": {"start": -1, "end": -1}, "writeback": {"start": 3, "end": 3}},
			"beats": {0: "fetch", 1: "fetch", 2: "decode", 3: "writeback"}},
		"T5.1-3": {"lines": ["PC_WR", "MEM_RD", "IR_WR", "RF_WR"]},
		"T5.1-4": 0,
	}
	ctx.begin_group("judge_datapath")
	ctx.check("5.1 全对判绿", bool(_run(cfg, good)["ok"]))
	var bad_val: Dictionary = good.duplicate(true)
	bad_val["T5.1-1"] = {"regs": {"R1": 3, "R2": 5, "R3": 7}, "ticks": 4}
	var r1 := _run(cfg, bad_val)
	ctx.check("5.1 终值错判红", not bool(r1["ok"]))
	ctx.eq("5.1 终值错落 10", _codes(r1["report"])[0], GateResult.E_OUTPUT_MISMATCH)
	var table: Dictionary = good.duplicate(true)
	table["T5.1-2"] = {"order": ["fetch", "decode", "execute", "writeback"]}
	var r2 := _run(cfg, table)
	ctx.check("5.1 填表式波形被判红", not bool(r2["ok"]))
	ctx.eq("5.1 填表式波形落 10", _codes(r2["report"])[0], GateResult.E_OUTPUT_MISMATCH)
	var extra: Dictionary = good.duplicate(true)
	extra["T5.1-3"] = {"lines": ["PC_WR", "MEM_RD", "IR_WR", "RF_WR", "ALU_ADD"]}
	ctx.check("5.1 多翻一根线判红", not bool(_run(cfg, extra)["ok"]))
	var quiz: Dictionary = good.duplicate(true)
	quiz["T5.1-4"] = 1
	ctx.eq("5.1 quiz 错落 14", _codes(_run(cfg, quiz)["report"])[0], GateResult.E_QUIZ)

# ---------------------------------------------------------------- 5.2

func _judge_isa(ctx: TestContext, cfg: Dictionary) -> void:
	var isa: Array = ((_gate(cfg, "T5.2-2").get("isa", [])) as Array)
	var steps := []
	for raw in isa:
		steps.append({"opcode": int((raw as Dictionary)["opcode"]),
			"mnemonic": str((raw as Dictionary)["mnemonic"]), "ticks": 4})
	var good := {
		"T5.2-1": {"opcode": 4, "mnemonic": "ADD",
			"lines": ["RF_RD", "ALU_ADD", "RF_WR", "PC_WR", "MEM_RD", "IR_WR"],
			"final": {"A": 8}, "ticks": 5},
		"T5.2-2": steps,
		"T5.2-3": {"tested": [16, 17, 18, 19], "rejected": [16, 17, 18, 19],
			"reported": [16, 17, 18, 19]},
		"T5.2-4": 0,
	}
	ctx.begin_group("judge_isa")
	ctx.check("5.2 全对判绿", bool(_run(cfg, good, {"waveform": {"ticks": 5}})["ok"]))
	var missing: Dictionary = good.duplicate(true)
	(missing["T5.2-2"] as Array).pop_back()
	var r1 := _run(cfg, missing, {"waveform": {"ticks": 5}})
	ctx.check("5.2 漏单步一条判红", not bool(r1["ok"]))
	ctx.eq("5.2 漏条落 10", _codes(r1["report"])[0], GateResult.E_OUTPUT_MISMATCH)
	var row: Dictionary = good.duplicate(true)
	row["T5.2-1"] = {"opcode": 5, "mnemonic": "SUB", "lines": ["RF_RD", "ALU_ADD"],
		"final": {"A": 8}, "ticks": 5}
	ctx.eq("5.2 控制表行错落 7", _codes(_run(cfg, row)["report"])[0], GateResult.E_TABLE_CELL)
	var notest: Dictionary = good.duplicate(true)
	notest["T5.2-3"] = {"tested": [16], "rejected": [16], "reported": [16]}
	ctx.eq("5.2 空码只测一个落 13", _codes(_run(cfg, notest)["report"])[0], GateResult.E_COVERAGE)
	var unreg: Dictionary = good.duplicate(true)
	unreg["T5.2-3"] = {"tested": [16, 17, 18, 19], "rejected": [16, 18, 19], "reported": [16, 18, 19]}
	ctx.check("5.2 空码未拒判红", not bool(_run(cfg, unreg)["ok"]))
	ctx.eq("5.2 空码未拒落 10", _codes(_run(cfg, unreg)["report"])[0], GateResult.E_OUTPUT_MISMATCH)

# ---------------------------------------------------------------- 5.3

func _judge_program(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T5.3-1": {"out": 8, "regs": {"R1": 3, "R2": 5, "R3": 8}, "ticks": 8},
		"T5.3-2": {"out": 15, "back_jumps": 5, "halted": true},
		"T5.3-3": {"out": 0, "back_jumps": 0},
		"T5.3-4": 0,
	}
	ctx.begin_group("judge_program")
	ctx.check("5.3 两条程序判绿", bool(_run(cfg, good)["ok"]))
	var wrong: Dictionary = good.duplicate(true)
	wrong["T5.3-1"] = {"out": 7, "regs": {"R1": 3, "R2": 5, "R3": 8}, "ticks": 8}
	var r1 := _run(cfg, wrong)
	ctx.check("5.3 输出错判红", not bool(r1["ok"]))
	ctx.eq("5.3 输出错落 10", _codes(r1["report"])[0], GateResult.E_OUTPUT_MISMATCH)
	var hang: Dictionary = good.duplicate(true)
	hang["T5.3-2"] = {"out": 15, "back_jumps": 5, "halted": false}
	ctx.eq("5.3 不停机落 15", _codes(_run(cfg, hang)["report"])[0], GateResult.E_TARGET_UNREACHED)
	var edge: Dictionary = good.duplicate(true)
	edge["T5.3-3"] = {"out": 1, "back_jumps": 1}
	ctx.check("5.3 边界未测判红", not bool(_run(cfg, edge)["ok"]))
	ctx.eq("5.3 边界未测落 10", _codes(_run(cfg, edge)["report"])[0], GateResult.E_OUTPUT_MISMATCH)

# ---------------------------------------------------------------- 5.4

func _judge_clock(ctx: TestContext, cfg: Dictionary) -> void:
	var report := {"stages": 9, "stage_delay_ps": 1000.0, "clock_period_ps": 12000.0,
		"fail_tick": 12, "fail_line": "carry", "setup_ps": 200.0, "hold_ps": 100.0}
	var good := {
		"T5.4-1": {"tick": 12, "line": "carry", "margin_ps": 2700.0},
		"T5.4-2": {"stages_after": 4, "same_freq": true, "retest_pass": true, "margin_ps": 2700.0},
		"T5.4-3": {"clock_period_ps": 9000.0},
		"T5.4-4": {"clock_period_ps": 9000.0},
		"T5.4-5": 0,
	}
	ctx.begin_group("judge_clock")
	ctx.check("5.4 全对判绿", bool(_run(cfg, good, {"delay_report": report})["ok"]))
	var tick: Dictionary = good.duplicate(true)
	tick["T5.4-1"] = {"tick": 11, "line": "carry", "margin_ps": 2700.0}
	var r1 := _run(cfg, tick, {"delay_report": report})
	ctx.check("5.4 拍号错判红", not bool(r1["ok"]))
	ctx.eq("5.4 拍号与报告不符落 9", _codes(r1["report"])[0], GateResult.E_DELAY_MISMATCH)
	var no_report := _run(cfg, good, {})
	ctx.eq("5.4 缺报告（手填）落 9", _codes(no_report["report"])[0], GateResult.E_DELAY_MISMATCH)
	var neg := report.duplicate(true)
	neg["clock_period_ps"] = 8000.0
	ctx.eq("5.4 余量为负落 27", _codes(_run(cfg, good, {"delay_report": neg})["report"])[0],
		GateResult.E_TIMING_MARGIN)
	var no_cut: Dictionary = good.duplicate(true)
	no_cut["T5.4-2"] = {"stages_after": 9, "same_freq": true, "retest_pass": true, "margin_ps": 2700.0}
	ctx.eq("5.4 只调频率（级数未降）落 8",
		_codes(_run(cfg, no_cut, {"delay_report": report})["report"])[0], GateResult.E_DELAY_EXCEED)
	var lower: Dictionary = good.duplicate(true)
	lower["T5.4-2"] = {"stages_after": 4, "same_freq": false, "retest_pass": true, "margin_ps": 2700.0}
	ctx.eq("5.4 不同频复测落 8",
		_codes(_run(cfg, lower, {"delay_report": report})["report"])[0], GateResult.E_DELAY_EXCEED)
	var hand: Dictionary = good.duplicate(true)
	hand["T5.4-3"] = {"clock_period_ps": 7000.0}
	ctx.eq("5.4 手填周期落 9",
		_codes(_run(cfg, hand, {"delay_report": report})["report"])[0], GateResult.E_DELAY_MISMATCH)
	var calc: Dictionary = good.duplicate(true)
	calc["T5.4-4"] = {"clock_period_ps": 8000.0}
	ctx.eq("5.4 算式错落 9",
		_codes(_run(cfg, calc, {"delay_report": report})["report"])[0], GateResult.E_DELAY_MISMATCH)
