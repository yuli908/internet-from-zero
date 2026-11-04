extends RefCounted

## CH07 四节（20 段）结构 + 判据校验。
## 分母口径：required 且非 pending 的 gate 数，按数据现算。
## 7.1 P1 的采样相位阈值是课文 §6-4 初值，未校准 → pending 不进分母；其余 gate 一律给正解与反例。
## 所有判据断言都给反例：断言必须能红，不是恒真。

const LABS := ["serial_basics", "frame4", "uart", "two_machine"]
const SECTION_COUNTS := {"serial_basics": 5, "frame4": 5, "uart": 5, "two_machine": 5}
const TOTAL_SECTIONS := 20
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260

const Ch07 = preload("res://src/core/ch07_checks.gd")
const Teach = preload("res://src/ui/teaching.gd")

const EXPECT := 208
const EXPECT_GROUPS := {
	"loadable": 1, "sections_present": 4, "section_count": 4, "total_sections": 1,
	"order": 20, "after_unlock": 20, "after_bound": 20, "text_nonempty": 20, "text_cap": 20,
	"screen_sum": 16, "last_after": 4, "after_required": 4, "fallback": 8,
	"denominator": 4, "gate_ids": 4, "gate_count": 4, "required_count": 4, "gate_codes": 4,
	"practice": 8, "p1_field": 4, "pending_declared": 2,
	"judge_serial": 8, "judge_frame": 8, "judge_uart": 8, "judge_two": 8,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch07_labs 数据文件可读",
	"sections_present": "每 lab 必有非空 sections",
	"section_count": "每 lab 段数与课文一致（各 5 段）",
	"total_sections": "全篇 20 段",
	"order": "每 lab 内 order 连续",
	"after_unlock": "首段 after=0、其余单调不减",
	"after_bound": "每段 after ≤ required−1",
	"text_nonempty": "每段 text 非空",
	"text_cap": "每段 ≤150 字（左栏口径，去半角空格）",
	"screen_sum": "同一 after 档同屏合计 ≤260",
	"last_after": "末段 after = required−1",
	"after_required": "最大 after 落在 required−1",
	"fallback": "删掉 sections 的副本退回 body",
	"denominator": "进分母 gate 数按 required 去 pending 现算",
	"gate_ids": "gate id 按 T7.x-n 顺序且与课文提案一致",
	"gate_count": "每节 gate 条数 4",
	"required_count": "每节 required gate 数为 4",
	"gate_codes": "gate 失败码只用白名单 3/5/7/8/9/10/13/14/15/27",
	"practice": "每节有实践表且每行 id/level/produce/judge 齐全",
	"p1_field": "每节有 P1 文本与 p1_gates",
	"pending_declared": "7.1 采样相位阈值未校准，T7.1-1 挂 pending 且不进分母",
	"judge_serial": "7.1 可判三项正解判绿；稳定读数/周期错/选择题错/未接线给反例",
	"judge_frame": "7.2 字段表与三向量正解判绿；位宽/该过未过/漏向量/停止位/校验/选择题给反例",
	"judge_uart": "7.3 同频/1.3×/定位/修正正解判绿；比例/位号/字节/只挪点/累计/选择题给反例",
	"judge_two": "7.4 双机正解判绿；分频不一致/不校验/单向/字节错/未拒收/选择题给反例",
}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch07_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch07_labs 可读", not labs.is_empty(), str(labs.size()))

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

	_judge_serial(ctx, labs.get("serial_basics", {}))
	_judge_frame(ctx, labs.get("frame4", {}))
	_judge_uart(ctx, labs.get("uart", {}))
	_judge_two(ctx, labs.get("two_machine", {}))

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
	var d: Dictionary = Ch07.deferred_gates(cfg)
	var want := 3 if id == "serial_basics" else 4
	ctx.begin_group("denominator")
	ctx.eq("%s 进分母 gate 数" % id, int(d["counted"]), want)
	ctx.begin_group("gate_count")
	ctx.eq("%s gate 条数" % id, cases.size(), 4)
	ctx.begin_group("required_count")
	ctx.eq("%s required 数" % id, req, 4)
	ctx.begin_group("gate_ids")
	var ids := []
	for raw in cases:
		ids.append(str((raw as Dictionary).get("id", "")))
	ctx.check("%s gate id 顺序与课文提案一致" % id, _ids_ok(id, ids), str(ids))
	ctx.begin_group("gate_codes")
	var bad := []
	var codes := []
	for raw in cases:
		for code in (raw as Dictionary).get("codes", []):
			codes.append(str(code))
	for raw in (cfg.get("practice", []) as Array):
		for code in (raw as Dictionary).get("codes", []):
			codes.append(str(code))
	for s in codes:
		var num := _code_num(str(s))
		if num < 0 or not LabGateKit.ALLOWED_CODES.has(num):
			bad.append(str(s))
	ctx.check("%s 失败码形如 E_NAME(n) 且在白名单（无 26/28）" % id, bad.is_empty(), str(bad))
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

func _judge_serial(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T7.1-2": {"readings": [0, 1, 0, 1], "inverted": false},
		"T7.1-3": {"bit_us": 104.2, "half_us": 52.1},
		"T7.1-4": 0,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	var pend: Array = result.get("pending", [])
	ctx.begin_group("judge_serial")
	ctx.check("7.1 可判项全过（相位项 pending）", rep.all_required_passed(), str(rep.failure_codes()))
	ctx.check("7.1 T7.1-2 沿上重复读数判绿", _case_ok(result, "T7.1-2"))
	ctx.check("7.1 T7.1-3 周期换算判绿", _case_ok(result, "T7.1-3"))
	ctx.check("7.1 T7.1-4 选择题判绿", _case_ok(result, "T7.1-4"))
	ctx.check("7.1 多次读数一致 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.1-2", {"readings": [1, 1, 1], "inverted": false})),
			"T7.1-2") == 10)
	ctx.check("7.1 位宽算成半位 → 红 E_DELAY_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.1-3", {"bit_us": 52.1, "half_us": 26.0})),
			"T7.1-3") == 9)
	ctx.check("7.1 选择题错 → 红 E_QUIZ",
		_case_code(_run(cfg, _with(good, "T7.1-4", 1)), "T7.1-4") == 14)
	ctx.check("7.1 未接探针 → 红 E_UNCONNECTED",
		_case_code(_run(cfg, _with(good, "T7.1-2", {})), "T7.1-2") == 3)
	ctx.begin_group("pending_declared")
	ctx.check("7.1 仅 T7.1-1 挂 pending（相位阈值未校准）",
		pend.size() == 1 and str((pend[0] as Dictionary).get("id", "")) == "T7.1-1", str(pend))
	var g := _gate(cfg, "T7.1-1")
	var phase: Dictionary = (g.get("thresholds", {}) as Dictionary).get("phase_tolerance", {})
	ctx.check("7.1 相位容差标 pending，不以 10% 冒充定稿",
		str(phase.get("status", "")) == "pending", str(phase))

func _judge_frame(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T7.2-1": {
			"fields": [
				{"name": "start", "start": 0, "width": 1},
				{"name": "data", "start": 1, "width": 4},
				{"name": "parity", "start": 5, "width": 1},
				{"name": "stop", "start": 6, "width": 1},
			],
			"vectors": [
				{"id": "normal", "passed": true, "rejected": false},
				{"id": "parity", "passed": false, "rejected": true, "field": "parity"},
				{"id": "stop", "passed": false, "rejected": true, "field": "stop"},
			],
		},
		"T7.2-2": {"stop_level": 0, "single_frame_ok": true, "frames_merged": true},
		"T7.2-3": {"results": [{"id": "v1", "parity": 0}, {"id": "v2", "parity": 1},
			{"id": "v3", "parity": 0}]},
		"T7.2-4": 0,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	ctx.begin_group("judge_frame")
	ctx.check("7.2 四条全过", rep.all_required_passed(), str(rep.failure_codes()))
	var bad_fields: Array = (good["T7.2-1"] as Dictionary)["fields"].duplicate(true)
	bad_fields[1]["width"] = 3
	ctx.check("7.2 数据位宽写成 3 → 红 E_TABLE_CELL",
		_case_code(_run(cfg, _with(good, "T7.2-1",
			{"fields": bad_fields, "vectors": (good["T7.2-1"] as Dictionary)["vectors"]})), "T7.2-1") == 7)
	var normal_bad: Array = (good["T7.2-1"] as Dictionary)["vectors"].duplicate(true)
	normal_bad[0] = {"id": "normal", "passed": false, "rejected": true, "field": "stop"}
	ctx.check("7.2 正常帧被拒 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.2-1",
			{"fields": (good["T7.2-1"] as Dictionary)["fields"], "vectors": normal_bad})), "T7.2-1") == 10)
	ctx.check("7.2 漏校验向量 → 红 E_COVERAGE",
		_case_code(_run(cfg, _with(good, "T7.2-1",
			{"fields": (good["T7.2-1"] as Dictionary)["fields"],
			 "vectors": [{"id": "normal", "passed": true, "rejected": false},
				{"id": "stop", "passed": false, "rejected": true, "field": "stop"}]})), "T7.2-1") == 13)
	ctx.check("7.2 停止位没接低 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.2-2",
			{"stop_level": 1, "single_frame_ok": true, "frames_merged": false})), "T7.2-2") == 10)
	ctx.check("7.2 校验位算错 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.2-3",
			{"results": [{"id": "v1", "parity": 0}, {"id": "v2", "parity": 0},
				{"id": "v3", "parity": 0}]})), "T7.2-3") == 10)
	ctx.check("7.2 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T7.2-4", 1)),
		"T7.2-4") == 14)
	ctx.check("7.2 未接帧检查器 → 红 E_UNCONNECTED", _case_code(_run(cfg, _with(good, "T7.2-1", {})),
		"T7.2-1") == 3)

func _judge_uart(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T7.3-1": {"offset_ratio": 1.3, "same_freq_byte": 165, "offset_byte": 49,
			"first_bad_bit": 2, "fixed_byte": 165},
		"T7.3-2": {"last_sample_shifted": true, "byte_before": 165, "byte_after": 165,
			"reproduced": false},
		"T7.3-3": {"bit_us": 104.2, "offset_us": 31.3, "accum_bits": 2.1},
		"T7.3-4": 0,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	ctx.begin_group("judge_uart")
	ctx.check("7.3 四条全过", rep.all_required_passed(), str(rep.failure_codes()))
	ctx.check("7.3 偏移比例报 1.0× → 红 E_DELAY_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.3-1", {"offset_ratio": 1.0,
			"same_freq_byte": 165, "offset_byte": 49, "first_bad_bit": 2, "fixed_byte": 165})),
			"T7.3-1") == 9)
	ctx.check("7.3 首个错位报错 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.3-1", {"offset_ratio": 1.3,
			"same_freq_byte": 165, "offset_byte": 49, "first_bad_bit": 3, "fixed_byte": 165})),
			"T7.3-1") == 10)
	ctx.check("7.3 偏移后字节报错 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.3-1", {"offset_ratio": 1.3,
			"same_freq_byte": 165, "offset_byte": 33, "first_bad_bit": 2, "fixed_byte": 165})),
			"T7.3-1") == 10)
	ctx.check("7.3 自称只挪点位就复现 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.3-2", {"last_sample_shifted": true,
			"byte_before": 165, "byte_after": 164, "reproduced": true})), "T7.3-2") == 10)
	ctx.check("7.3 累计偏移算错 → 红 E_DELAY_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.3-3", {"bit_us": 52.1, "offset_us": 31.3,
			"accum_bits": 2.1})), "T7.3-3") == 9)
	ctx.check("7.3 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T7.3-4", 1)),
		"T7.3-4") == 14)
	ctx.check("7.3 未接发送器 → 红 E_UNCONNECTED", _case_code(_run(cfg, _with(good, "T7.3-1", {})),
		"T7.3-1") == 3)

func _judge_two(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T7.4-1": {"width_tx": 104.0, "width_rx": 104.0, "tx_bytes": [165, 60],
			"rx_bytes": [165, 60], "rejected_frame": 2, "resent_ok": true},
		"T7.4-2": {"width_a": 104.0, "width_b": 135.2,
			"frames": [{"index": 1, "ok": true}, {"index": 2, "ok": false}]},
		"T7.4-3": {"checksum_checked": false, "corrupted_accepted": true,
			"corrupted_byte": 164, "clean_byte": 165},
		"T7.4-4": 0,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	ctx.begin_group("judge_two")
	ctx.check("7.4 四条全过", rep.all_required_passed(), str(rep.failure_codes()))
	ctx.check("7.4 分频不一致却报两帧全对 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.4-2", {"width_a": 104.0, "width_b": 135.2,
			"frames": [{"index": 1, "ok": true}, {"index": 2, "ok": true}]})), "T7.4-2") == 10)
	ctx.check("7.4 校验仍开却报坏帧被收 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.4-3", {"checksum_checked": true,
			"corrupted_accepted": true, "corrupted_byte": 164, "clean_byte": 165})),
			"T7.4-3") == 10)
	ctx.check("7.4 只跑单向 → 红 E_COVERAGE",
		_case_code(_run(cfg, _with(good, "T7.4-1", {"width_tx": 104.0, "width_rx": 104.0,
			"tx_bytes": [165], "rx_bytes": [165, 60], "rejected_frame": 2, "resent_ok": true})),
			"T7.4-1") == 13)
	ctx.check("7.4 双向字节不一致 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.4-1", {"width_tx": 104.0, "width_rx": 104.0,
			"tx_bytes": [165, 61], "rx_bytes": [165, 60], "rejected_frame": 2, "resent_ok": true})),
			"T7.4-1") == 10)
	ctx.check("7.4 坏帧未报号 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T7.4-1", {"width_tx": 104.0, "width_rx": 104.0,
			"tx_bytes": [165, 60], "rx_bytes": [165, 60], "rejected_frame": 0, "resent_ok": true})),
			"T7.4-1") == 10)
	ctx.check("7.4 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T7.4-4", 1)),
		"T7.4-4") == 14)
	ctx.check("7.4 未接三根线 → 红 E_UNCONNECTED", _case_code(_run(cfg, _with(good, "T7.4-1", {})),
		"T7.4-1") == 3)

# ---------------------------------------------------------------- 工具

func _ids_ok(id: String, ids: Array) -> bool:
	var prefix := ""
	match id:
		"serial_basics": prefix = "T7.1-"
		"frame4": prefix = "T7.2-"
		"uart": prefix = "T7.3-"
		"two_machine": prefix = "T7.4-"
	if ids.size() != 4:
		return false
	for i in 4:
		if str(ids[i]) != "%s%d" % [prefix, i + 1]:
			return false
	return true

func _required_count(cfg: Dictionary) -> int:
	var n := 0
	for raw in cfg.get("gate_cases", []):
		if bool((raw as Dictionary).get("required", false)):
			n += 1
	return n

func _gate(cfg: Dictionary, cid: String) -> Dictionary:
	for raw in cfg.get("gate_cases", []):
		if str((raw as Dictionary).get("id", "")) == cid:
			return raw
	return {}

func _code_num(raw: String) -> int:
	var l := raw.find("(")
	var r := raw.find(")")
	if l < 0 or r < 0:
		return -1
	return int(raw.substr(l + 1, r - l - 1))

func _run(cfg: Dictionary, answers: Dictionary) -> Dictionary:
	return Ch07.run(str(cfg.get("id", "")), cfg, {"answers": answers})

func _with(good: Dictionary, cid: String, value: Variant) -> Dictionary:
	var out := good.duplicate(true)
	out[cid] = value
	return out

func _report_of(result: Variant) -> GateReport:
	if result is Dictionary:
		return (result as Dictionary).get("report")
	return result

func _case_ok(result: Variant, cid: String) -> bool:
	var report := _report_of(result)
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return bool(c.get("ok", false))
	return false

func _case_code(result: Variant, cid: String) -> int:
	var report := _report_of(result)
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return GateResult.E_GENERIC
