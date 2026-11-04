extends RefCounted

## M6 · CH03 数据落地与判定：16 条 gate，每节正确解全过 + 每条 gate 的错误解必红。

const Ch03 := preload("res://src/core/ch03_checks.gd")
const SCREEN_LIMIT := 260

const SECTION_COUNTS := {"full_adder": 5, "adder8": 5, "clock_edge": 5, "bistable_reg": 6}
const AFTER_SEQS := {
	"full_adder": [0, 0, 1, 2, 3],
	"adder8": [0, 0, 1, 2, 3],
	"clock_edge": [0, 0, 1, 2, 3],
	"bistable_reg": [0, 0, 1, 2, 3, 3],
}
const CODE_WHITELIST := [3, 6, 7, 8, 9, 10, 12, 14, 22, 26, 27]

const EXPECT := 216
const EXPECT_GROUPS := {
	"loadable": 1, "no_pending": 1, "sections_present": 4, "section_count": 4,
	"order": 21, "after_unlock": 21, "after_bound": 21, "text_nonempty": 21,
	"text_cap": 21, "screen_sum": 16, "last_after": 4, "after_required": 4,
	"fallback": 8, "total_sections": 1, "denominator": 4, "gate_ids": 4,
	"gate_count": 4, "required_count": 4, "gate_codes": 4, "practice": 8,
	"p1_field": 4, "judge_ful": 9, "judge_addr": 9, "judge_clock": 9, "judge_bistable": 9,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch03_labs 可读",
	"no_pending": "pending_kinds 为空，16 条 gate 全部可判",
	"sections_present": "四节都有 sections",
	"section_count": "3.1/3.2/3.3 五段、3.4 六段",
	"order": "order 逐段 1..n",
	"after_unlock": "after 逐段为 0 或小于 order",
	"after_bound": "after 不超过 required 数减一",
	"text_nonempty": "每段有正文",
	"text_cap": "每段 ≤150 字",
	"screen_sum": "同一 after 档同屏 ≤260 字",
	"last_after": "末段 after = required−1",
	"after_required": "after 最大档 = required−1",
	"fallback": "有 sections 用 sections，缺 sections 回退 body",
	"total_sections": "21 段合计",
	"denominator": "每节 required 分母 = 4",
	"gate_ids": "gate_ids 按 T3.x-1..4 顺序",
	"gate_count": "每节 4 条 gate",
	"required_count": "每节 required 4 条",
	"gate_codes": "失败码形如 E_NAME(n) 且在白名单",
	"practice": "实践表非空且字段齐全",
	"p1_field": "每节有 P1 文本与 p1_gates",
	"judge_ful": "3.1 四条 gate 各绿各红",
	"judge_addr": "3.2 四条 gate 各绿各红",
	"judge_clock": "3.3 四条 gate 各绿各红（短 T 必须红）",
	"judge_bistable": "3.4 四条 gate 各绿各红",
}

func run(ctx: TestContext) -> void:
	var labs := TestUtil.read_json("res://data/labs/ch03_labs.json")

	ctx.begin_group("loadable")
	ctx.check("ch03_labs 可读", not labs.is_empty())

	ctx.begin_group("no_pending")
	ctx.check("pending_kinds 为空", (labs.get("pending_kinds", {}) as Dictionary).is_empty())

	var total := 0
	for raw_lab in labs.get("labs", {}).values():
		var cfg: Dictionary = raw_lab
		var id := str(cfg.get("id", ""))
		ctx.begin_group("sections_present")
		ctx.check("%s 有 sections" % id, not (cfg.get("sections", []) as Array).is_empty())
		ctx.begin_group("section_count")
		ctx.check("%s 段数" % id, (cfg.get("sections", []) as Array).size() == int(SECTION_COUNTS[id]),
			"%d" % (cfg.get("sections", []) as Array).size())

		var sections: Array = cfg.get("sections", [])
		var required := _required_count(cfg)
		var screen := {}
		var max_after := 0
		for i in sections.size():
			var s: Dictionary = sections[i]
			ctx.begin_group("order")
			ctx.check("%s 第 %d 段 order" % [id, i + 1], int(s.get("order", 0)) == i + 1,
				str(s.get("order", "?")))
			ctx.begin_group("after_unlock")
			var after := int(s.get("after", -1))
			ctx.check("%s 第 %d 段 after" % [id, i + 1], after >= 0 and after < i + 1,
				str(after))
			ctx.begin_group("after_bound")
			ctx.check("%s 第 %d 段 after 上限" % [id, i + 1], after <= required - 1,
				"%d / required %d" % [after, required])
			ctx.begin_group("text_nonempty")
			ctx.check("%s 第 %d 段有正文" % [id, i + 1], not str(s.get("text", "")).strip_edges().is_empty())
			ctx.begin_group("text_cap")
			var cap := _chars(str(s.get("text", "")))
			ctx.check(str(id) + " 第 " + str(i + 1) + " 段不超 150 字", cap <= 150, str(cap))
			screen[after] = int(screen.get(after, 0)) + _chars(str(s.get("text", "")))
			max_after = maxi(max_after, after)
			total += 1
		for a in screen.keys():
			ctx.begin_group("screen_sum")
			ctx.check("%s after=%d 同屏 ≤260" % [id, int(a)], int(screen[a]) <= SCREEN_LIMIT,
				str(screen[a]))
		ctx.begin_group("last_after")
		ctx.check("%s 末段 after" % id, int(sections[-1].get("after", -1)) == required - 1,
			str(int(sections[-1].get("after", -1))))
		ctx.begin_group("after_required")
		ctx.check("%s after 最大档 = required−1" % id, max_after == required - 1,
			"%d / %d" % [max_after, required])

		ctx.begin_group("fallback")
		ctx.check("%s 有 sections 时优先 sections" % id, _effective_segments(cfg)[0] == "sections")
		var stripped := cfg.duplicate(true)
		stripped.erase("sections")
		ctx.check("%s 缺 sections 时回退 body" % id, _effective_segments(stripped)[0] == "body")

		ctx.begin_group("denominator")
		ctx.check("%s required 分母 4" % id, required == 4, str(required))
		ctx.begin_group("gate_ids")
		ctx.check("%s gate_ids 顺序" % id, _ids_ok(id, _case_ids(cfg)),
			str(cfg.get("gate_ids", [])))
		ctx.begin_group("gate_count")
		ctx.check("%s gate 数 4" % id, (cfg.get("gate_cases", []) as Array).size() == 4,
			str((cfg.get("gate_cases", []) as Array).size()))
		ctx.begin_group("required_count")
		ctx.check("%s required 条数 4" % id, _required_count(cfg) == 4)
		ctx.begin_group("gate_codes")
		var bad := _bad_codes(cfg)
		ctx.check("%s 失败码白名单" % id, bad.is_empty(), str(bad))
		ctx.begin_group("practice")
		var practice: Array = cfg.get("practice", [])
		var incomplete := []
		for row_raw in practice:
			var row: Dictionary = row_raw
			for key in ["id", "level", "produce", "judge"]:
				if str(row.get(key, "")).strip_edges().is_empty():
					incomplete.append("%s.%s" % [str(row.get("id", "?")), key])
		ctx.check("%s 实践表非空" % id, not practice.is_empty())
		ctx.check("%s 实践表字段齐全" % id, incomplete.is_empty(), str(incomplete))
		ctx.begin_group("p1_field")
		ctx.check("%s 有 P1 文本与 p1_gates" % id,
			not str(cfg.get("p1", "")).strip_edges().is_empty()
			and not (cfg.get("p1_gates", []) as Array).is_empty())

	ctx.begin_group("total_sections")
	ctx.check("CH03 段数合计 21", total == 21, str(total))

	var ful := _gate(labs, "full_adder")
	var addr := _gate(labs, "adder8")
	var clk := _gate(labs, "clock_edge")
	var bist := _gate(labs, "bistable_reg")
	_judge_ful(ctx, ful)
	_judge_addr(ctx, addr)
	_judge_clock(ctx, clk)
	_judge_bistable(ctx, bist)

# ---------------------------------------------------------------- 判定红绿

func _judge_ful(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T3.1-1": {"rows": _fa_rows()},
		"T3.1-2": {"parts": {"half_adder": 2, "or": 1}},
		"T3.1-3": {"delay_ticks": 10},
		"T3.1-4": 1,
	}
	var rep: GateReport = _run(cfg, good)
	ctx.begin_group("judge_ful")
	ctx.check("3.1 正确解全过", rep.all_required_passed(), str(rep.failure_codes()))
	for cid in ["T3.1-1", "T3.1-2", "T3.1-3", "T3.1-4"]:
		ctx.check("3.1 %s 绿" % cid, _case_ok(rep, cid))
	ctx.check("3.1 Cin 接死 0 → 红 E_TRUTH_ROW", _case_code(_run(cfg, _with(good, "T3.1-1",
		{"rows": _fa_rows_tied()})), "T3.1-1") == 6)
	ctx.check("3.1 多一只或门 → 红 E_ENCAPSULATION", _case_code(_run(cfg, _with(good, "T3.1-2",
		{"parts": {"half_adder": 2, "or": 2}})), "T3.1-2") == 12)
	ctx.check("3.1 延迟 0 → 红 E_DELAY_EXCEED", _case_code(_run(cfg, _with(good, "T3.1-3",
		{"delay_ticks": 0}), {"T3.1-3": {"delay_ticks": 0}}), "T3.1-3") == 8)
	ctx.check("3.1 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T3.1-4", 0)), "T3.1-4") == 14)

func _judge_addr(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T3.2-1": {"part": "full_adder", "instances": 8, "same_part": true},
		"T3.2-2": {"groups": _adder_groups()},
		"T3.2-3": {"sum": 0, "c8": 1},
		"T3.2-4": {"stages": 8},
	}
	var rep: GateReport = _run(cfg, good)
	ctx.begin_group("judge_addr")
	ctx.check("3.2 正确解全过", rep.all_required_passed(), str(rep.failure_codes()))
	for cid in ["T3.2-1", "T3.2-2", "T3.2-3", "T3.2-4"]:
		ctx.check("3.2 %s 绿" % cid, _case_ok(rep, cid))
	ctx.check("3.2 手画八份 → 红 E_ENCAPSULATION", _case_code(_run(cfg, _with(good, "T3.2-1",
		{"part": "full_adder", "instances": 8, "same_part": false})), "T3.2-1") == 12)
	var bad_groups := _adder_groups()
	bad_groups[0]["sum"] = 0
	ctx.check("3.2 某位和错 → 红 E_TRUTH_ROW", _case_code(_run(cfg, _with(good, "T3.2-2",
		{"groups": bad_groups})), "T3.2-2") == 6)
	ctx.check("3.2 255+1 不进位 → 红 E_TRUTH_ROW", _case_code(_run(cfg, _with(good, "T3.2-3",
		{"sum": 255, "c8": 0})), "T3.2-3") == 6)
	ctx.check("3.2 级数报 7 → 红 E_DELAY_EXCEED", _case_code(_run(cfg, _with(good, "T3.2-4",
		{"stages": 7})), "T3.2-4") == 8)

func _judge_clock(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T3.3-1": {"period_long": 12, "period_short": 3, "long_sample": 8, "short_sample": 5},
		"T3.3-2": 1,
		"T3.3-3": {"stages_used": 9, "period_ticks": 9},
		"T3.3-4": {"mode": "edge"},
	}
	var inputs := {"delay_report": {"stages": 8, "stage_delay_ticks": 1}}
	var rep: GateReport = _run(cfg, good, inputs)
	ctx.begin_group("judge_clock")
	ctx.check("3.3 正确解全过", rep.all_required_passed(), str(rep.failure_codes()))
	for cid in ["T3.3-1", "T3.3-2", "T3.3-3", "T3.3-4"]:
		ctx.check("3.3 %s 绿" % cid, _case_ok(rep, cid))
	ctx.check("3.3 短 T 仍采到期望值 → 红（必须能红）", _case_code(_run(cfg, _with(good, "T3.3-1",
		{"period_long": 12, "period_short": 3, "long_sample": 8, "short_sample": 8}), inputs),
		"T3.3-1") == 6)
	ctx.check("3.3 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T3.3-2", 0), inputs),
		"T3.3-2") == 14)
	ctx.check("3.3 T 小于 9 级 → 红 E_TIMING_MARGIN", _case_code(_run(cfg, _with(good, "T3.3-3",
		{"stages_used": 9, "period_ticks": 8}), inputs), "T3.3-3") == 27)
	ctx.check("3.3 用电平采样 → 红 E_TRUTH_ROW", _case_code(_run(cfg, _with(good, "T3.3-4",
		{"mode": "level"}), inputs), "T3.3-4") == 6)

func _judge_bistable(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T3.4-1": {"inverters": 2, "cross_coupled": true},
		"T3.4-2": {"runs": [
			{"state": 0, "readings": _repeat(0, 10)},
			{"state": 1, "readings": _repeat(1, 10)},
		]},
		"T3.4-3": {"width": 8, "write": [1, 0, 1, 1, 0, 0, 1, 0],
			"read_back": [1, 0, 1, 1, 0, 0, 1, 0],
			"read_before": [0, 1, 0, 0, 1, 1, 0, 1]},
		"T3.4-4": {"setup": 1, "hold": 1},
	}
	var rep: GateReport = _run(cfg, good)
	ctx.begin_group("judge_bistable")
	ctx.check("3.4 正确解全过", rep.all_required_passed(), str(rep.failure_codes()))
	for cid in ["T3.4-1", "T3.4-2", "T3.4-3", "T3.4-4"]:
		ctx.check("3.4 %s 绿" % cid, _case_ok(rep, cid))
	ctx.check("3.4 不交叉耦合 → 红 E_HOLD_TICKS", _case_code(_run(cfg, _with(good, "T3.4-1",
		{"inverters": 2, "cross_coupled": false})), "T3.4-1") == 26)
	var flipped := _repeat(0, 10)
	flipped[5] = 1
	ctx.check("3.4 保持中途翻转 → 红 E_HOLD_TICKS", _case_code(_run(cfg, _with(good, "T3.4-2",
		{"runs": [{"state": 0, "readings": flipped},
			{"state": 1, "readings": _repeat(1, 10)}]})), "T3.4-2") == 26)
	ctx.check("3.4 WE=0 后读回变了 → 红", _case_code(_run(cfg, _with(good, "T3.4-3",
		{"width": 8, "write": [1, 0, 1, 1, 0, 0, 1, 0],
		"read_back": [1, 0, 1, 1, 0, 1, 1, 0],
		"read_before": [0, 1, 0, 0, 1, 1, 0, 1]})), "T3.4-3") == 26)
	ctx.check("3.4 建立/保持为 0 → 红 E_TIMING_MARGIN", _case_code(_run(cfg, _with(good,
		"T3.4-4", {"setup": 0, "hold": 0}), {"T3.4-4": {"setup": 0, "hold": 0}}),
		"T3.4-4") == 27)

# ---------------------------------------------------------------- 工具

func _effective_segments(cfg: Dictionary) -> Array:
	var sections: Array = cfg.get("sections", [])
	if not sections.is_empty():
		return ["sections", sections]
	var body := str(cfg.get("body", ""))
	if body.is_empty():
		return ["empty", []]
	return ["body", [{"order": 1, "after": 0, "title": str(cfg.get("title", "")), "text": body}]]

func _fa_rows() -> Array:
	var rows := []
	for a in 2:
		for b in 2:
			for cin in 2:
				rows.append({"a": a, "b": b, "cin": cin, "sum": a ^ b ^ cin,
					"cout": int(((a & b) | (a & cin) | (b & cin)) > 0)})
	return rows

func _fa_rows_tied() -> Array:
	var rows := []
	for a in 2:
		for b in 2:
			for cin in 2:
				rows.append({"a": a, "b": b, "cin": cin, "sum": a ^ b,
					"cout": a & b})
	return rows

func _adder_groups() -> Array:
	var pairs := [[1, 2], [3, 4], [5, 6], [7, 8], [9, 10], [11, 12], [13, 14], [15, 16],
		[17, 18], [19, 20], [21, 22], [23, 24], [25, 26], [27, 28], [29, 30], [31, 32],
		[0, 0], [255, 0], [128, 127], [255, 1]]
	var groups := []
	for p in pairs:
		var a := int(p[0])
		var b := int(p[1])
		var total := a + b
		groups.append({"a": a, "b": b, "sum": total % 256, "c8": int(total > 255)})
	return groups

func _repeat(v: int, n: int) -> Array:
	var out := []
	for i in n:
		out.append(v)
	return out

func _run(cfg: Dictionary, answers: Dictionary, extra: Dictionary = {}) -> GateReport:
	var inputs := {"answers": answers}
	for k in extra:
		inputs[k] = extra[k]
	return Ch03.run(str(cfg.get("id", "")), cfg, inputs).get("report")

func _with(good: Dictionary, cid: String, value: Variant) -> Dictionary:
	var out := good.duplicate(true)
	out[cid] = value
	return out

func _case_ok(report: GateReport, cid: String) -> bool:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return bool(c.get("ok", false))
	return false

func _case_code(report: GateReport, cid: String) -> int:
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return GateResult.E_GENERIC

func _gate(labs: Dictionary, id: String) -> Dictionary:
	return (labs.get("labs", {}) as Dictionary).get(id, {})

func _required_count(cfg: Dictionary) -> int:
	var n := 0
	for raw in cfg.get("gate_cases", []):
		if bool((raw as Dictionary).get("required", false)):
			n += 1
	return n

func _case_ids(cfg: Dictionary) -> Array:
	var out := []
	for raw in cfg.get("gate_cases", []):
		out.append(str((raw as Dictionary).get("id", "")))
	return out

func _ids_ok(id: String, ids: Array) -> bool:
	var prefix := ""
	match id:
		"full_adder": prefix = "T3.1-"
		"adder8": prefix = "T3.2-"
		"clock_edge": prefix = "T3.3-"
		"bistable_reg": prefix = "T3.4-"
	if ids.size() != 4:
		return false
	for i in 4:
		if str(ids[i]) != "%s%d" % [prefix, i + 1]:
			return false
	return true

func _bad_codes(cfg: Dictionary) -> Array:
	var bad := []
	var codes := []
	for raw in cfg.get("gate_cases", []):
		for code in (raw as Dictionary).get("codes", []):
			codes.append(str(code))
	for raw in cfg.get("practice", []):
		for code in (raw as Dictionary).get("codes", []):
			codes.append(str(code))
	for s in codes:
		var num := _code_num(s)
		if num < 0 or not CODE_WHITELIST.has(num):
			bad.append(str(s))
	return bad

func _code_num(s: String) -> int:
	var re := RegEx.new()
	re.compile(r"^E_[A-Z_]+\((\d+)\)$")
	var m := re.search(s)
	if m == null:
		return -1
	var num := int(m.get_string(1))
	if s.get_slice("(", 0) != GateResult.name_of(num):
		return -1
	return num

func _chars(s: String) -> int:
	return s.replace(" ", "").length()
