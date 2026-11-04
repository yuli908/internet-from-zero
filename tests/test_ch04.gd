extends RefCounted

## M6 · CH04 数据落地与判定：5 节 20 条 gate（1 条 pending），每条可判 gate 各绿各红。

const Ch04 := preload("res://src/core/ch04_checks.gd")
const SCREEN_LIMIT := 260

const SECTION_COUNTS := {"mux": 5, "alu8": 5, "control_unit": 5, "memory": 5, "io_bus": 5}
const AFTER_SEQS := {
	"mux": [0, 0, 1, 2, 3],
	"alu8": [0, 0, 1, 2, 3],
	"control_unit": [0, 0, 1, 2, 3],
	"memory": [0, 0, 1, 2, 3],
	"io_bus": [0, 0, 1, 2, 3],
}
const CODE_WHITELIST := [3, 6, 7, 8, 10, 12, 14, 17, 22, 26, 27]
const DENOMINATORS := {"mux": 4, "alu8": 3, "control_unit": 4, "memory": 4, "io_bus": 4}

const EXPECT := 265
const EXPECT_GROUPS := {
	"loadable": 1, "pending": 3, "sections_present": 5, "section_count": 5,
	"order": 25, "after_unlock": 25, "after_bound": 25, "text_nonempty": 25,
	"text_cap": 25, "screen_sum": 20, "last_after": 5, "after_required": 5,
	"fallback": 10, "total_sections": 1, "denominator": 5, "gate_ids": 5,
	"gate_count": 5, "required_count": 5, "gate_codes": 5, "practice": 10,
	"p1_field": 5, "judge_mux": 9, "judge_alu": 9, "judge_control": 9,
	"judge_memory": 9, "judge_bus": 9,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch04_labs 可读",
	"pending": "仅 4.2 面积一项 pending，且原因写明预算未定",
	"sections_present": "五节都有 sections",
	"section_count": "五节各五段",
	"order": "order 逐段 1..n",
	"after_unlock": "after 逐段为 0 或小于 order",
	"after_bound": "after 不超过 required 数减一",
	"text_nonempty": "每段有正文",
	"text_cap": "每段 ≤150 字",
	"screen_sum": "同一 after 档同屏 ≤260 字",
	"last_after": "末段 after = required−1",
	"after_required": "after 最大档 = required−1",
	"fallback": "有 sections 用 sections，缺 sections 回退 body",
	"total_sections": "25 段合计",
	"denominator": "4.2 分母 3，其余 4",
	"gate_ids": "gate_ids 按 T4.x-1..4 顺序",
	"gate_count": "每节 4 条 gate",
	"required_count": "每节 required 4 条（4.2 含 pending）",
	"gate_codes": "失败码形如 E_NAME(n) 且在白名单",
	"practice": "实践表非空且字段齐全",
	"p1_field": "每节有 P1 文本与 p1_gates",
	"judge_mux": "4.1 四条 gate 各绿各红",
	"judge_alu": "4.2 三条可判 gate 各绿各红，面积 pending",
	"judge_control": "4.3 四条 gate 各绿各红",
	"judge_memory": "4.4 四条 gate 各绿各红",
	"judge_bus": "4.5 四条 gate 各绿各红",
}

func run(ctx: TestContext) -> void:
	var labs := TestUtil.read_json("res://data/labs/ch04_labs.json")

	ctx.begin_group("loadable")
	ctx.check("ch04_labs 可读", not labs.is_empty())

	ctx.begin_group("pending")
	var pending_kinds: Dictionary = labs.get("pending_kinds", {})
	ctx.check("pending_kinds 仅 area_check", pending_kinds.size() == 1 and pending_kinds.has("area_check"))
	ctx.check("area 原因写明预算未定", str(pending_kinds.get("area_check", "")).contains("预算"))
	ctx.check("pending 无其他 kind", pending_kinds.keys() == ["area_check"], str(pending_kinds.keys()))

	var total := 0
	for raw_lab in labs.get("labs", {}).values():
		var cfg: Dictionary = raw_lab
		var id := str(cfg.get("id", ""))
		ctx.begin_group("sections_present")
		ctx.check("%s 有 sections" % id, not (cfg.get("sections", []) as Array).is_empty())
		ctx.begin_group("section_count")
		ctx.check("%s 段数" % id, (cfg.get("sections", []) as Array).size() == int(SECTION_COUNTS[id]))

		var sections: Array = cfg.get("sections", [])
		var required := _required_count(cfg)
		var screen := {}
		var max_after := 0
		for i in sections.size():
			var s: Dictionary = sections[i]
			ctx.begin_group("order")
			ctx.check("%s 第 %d 段 order" % [id, i + 1], int(s.get("order", 0)) == i + 1)
			ctx.begin_group("after_unlock")
			var after := int(s.get("after", -1))
			ctx.check("%s 第 %d 段 after" % [id, i + 1], after >= 0 and after < i + 1, str(after))
			ctx.begin_group("after_bound")
			ctx.check("%s 第 %d 段 after 上限" % [id, i + 1], after <= required - 1)
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
			ctx.check("%s after=%d 同屏 ≤260" % [id, int(a)], int(screen[a]) <= SCREEN_LIMIT, str(screen[a]))
		ctx.begin_group("last_after")
		ctx.check("%s 末段 after" % id, int(sections[-1].get("after", -1)) == required - 1)
		ctx.begin_group("after_required")
		ctx.check("%s after 最大档 = required−1" % id, max_after == required - 1)

		ctx.begin_group("fallback")
		ctx.check("%s 有 sections 时优先 sections" % id, _effective_segments(cfg)[0] == "sections")
		var stripped := cfg.duplicate(true)
		stripped.erase("sections")
		ctx.check("%s 缺 sections 时回退 body" % id, _effective_segments(stripped)[0] == "body")

		ctx.begin_group("denominator")
		ctx.check("%s required 分母 %d" % [id, int(DENOMINATORS[id])], _counted(cfg) == int(DENOMINATORS[id]))
		ctx.begin_group("gate_ids")
		ctx.check("%s gate_ids 顺序" % id, _ids_ok(id, _case_ids(cfg)))
		ctx.begin_group("gate_count")
		ctx.check("%s gate 数 4" % id, (cfg.get("gate_cases", []) as Array).size() == 4)
		ctx.begin_group("required_count")
		ctx.check("%s required 条数 4" % id, _required_count(cfg) == 4)
		ctx.begin_group("gate_codes")
		ctx.check("%s 失败码白名单" % id, _bad_codes(cfg).is_empty(), str(_bad_codes(cfg)))
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
	ctx.check("CH04 段数合计 25", total == 25, str(total))

	_judge_mux(ctx, _gate(labs, "mux"))
	_judge_alu(ctx, _gate(labs, "alu8"))
	_judge_control(ctx, _gate(labs, "control_unit"))
	_judge_memory(ctx, _gate(labs, "memory"))
	_judge_bus(ctx, _gate(labs, "io_bus"))

# ---------------------------------------------------------------- 判定红绿

func _judge_mux(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T4.1-1": {"rows": _mux_rows()},
		"T4.1-2": {"encapsulated": true, "ports": ["A", "B", "S", "Y"]},
		"T4.1-3": {"outputs": [0, 1, 2, 3, 4, 5, 6, 7], "levels": 3},
		"T4.1-4": 1,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	ctx.begin_group("judge_mux")
	ctx.check("4.1 正确解全过", rep.all_required_passed(), str(rep.failure_codes()))
	for cid in ["T4.1-1", "T4.1-2", "T4.1-3", "T4.1-4"]:
		ctx.check("4.1 %s 绿" % cid, _case_ok(rep, cid))
	var swapped := _mux_rows()
	swapped[0]["y"] = 1
	ctx.check("4.1 S 反接 → 红 E_TRUTH_ROW", _case_code(_run(cfg, _with(good, "T4.1-1",
		{"rows": swapped}), {"T4.1-1": {"rows": swapped}}), "T4.1-1") == 6)
	ctx.check("4.1 端口缺 Y → 红 E_ENCAPSULATION", _case_code(_run(cfg, _with(good, "T4.1-2",
		{"encapsulated": true, "ports": ["A", "B", "S"]}), {"T4.1-2": {"encapsulated": true, "ports": ["A", "B", "S"]}}),
		"T4.1-2") == 12)
	ctx.check("4.1 摊成长链 7 级 → 红", _case_code(_run(cfg, _with(good, "T4.1-3",
		{"outputs": [0, 1, 2, 3, 4, 5, 6, 7], "levels": 7}), {"T4.1-3": {"outputs": [0, 1, 2, 3, 4, 5, 6, 7], "levels": 7}}),
		"T4.1-3") == 6)
	ctx.check("4.1 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T4.1-4", 0)), "T4.1-4") == 14)

func _judge_alu(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T4.2-1": {"results": _alu_results(cfg)},
		"T4.2-2": {"data_ports": ["A", "B"], "opcode_ports": ["OP0", "OP1", "OP2"],
			"opcode_in_data": false},
		"T4.2-4": 1,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	ctx.begin_group("judge_alu")
	ctx.check("4.2 可判 gate 全过", rep.all_required_passed(), str(rep.failure_codes()))
	for cid in ["T4.2-1", "T4.2-2", "T4.2-4"]:
		ctx.check("4.2 %s 绿" % cid, _case_ok(rep, cid))
	var pend: Array = result.get("pending", [])
	var has_area := false
	for p in pend:
		if str((p as Dictionary).get("id", "")) == "T4.2-3":
			has_area = true
	ctx.check("4.2 面积项 pending 不判绿也不判红", has_area and pend.size() == 1, str(pend))
	var bad_results := _alu_results(cfg)
	bad_results[0]["y"] = 255
	ctx.check("4.2 加路算错 → 红 E_TRUTH_ROW", _case_code(_run(cfg, _with(good, "T4.2-1",
		{"results": bad_results}), {"T4.2-1": {"results": bad_results}}), "T4.2-1") == 6)
	ctx.check("4.2 操作码接进数据端 → 红", _case_code(_run(cfg, _with(good, "T4.2-2",
		{"data_ports": ["A", "B", "OP0"], "opcode_ports": ["OP0", "OP1", "OP2"],
		"opcode_in_data": true}), {"T4.2-2": {"data_ports": ["A", "B", "OP0"],
		"opcode_ports": ["OP0", "OP1", "OP2"], "opcode_in_data": true}}), "T4.2-2") == 6)
	ctx.check("4.2 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T4.2-4", 0)), "T4.2-4") == 14)
	ctx.check("4.2 分母排除面积项 = 3", _counted(cfg) == 3, str(_counted(cfg)))

func _judge_control(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T4.3-1": {"cells": _control_cells()},
		"T4.3-2": {"illegal": _illegal_rows()},
		"T4.3-3": {"legal": [{"opcode": 0, "lit": 1}, {"opcode": 1, "lit": 1},
			{"opcode": 2, "lit": 1}, {"opcode": 3, "lit": 1}]},
		"T4.3-4": 1,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	ctx.begin_group("judge_control")
	ctx.check("4.3 正确解全过", rep.all_required_passed(), str(rep.failure_codes()))
	for cid in ["T4.3-1", "T4.3-2", "T4.3-3", "T4.3-4"]:
		ctx.check("4.3 %s 绿" % cid, _case_ok(rep, cid))
	var cells := _control_cells()
	cells["0"]["sel_add"] = 0
	ctx.check("4.3 表一格错 → 红 E_TABLE_CELL", _case_code(_run(cfg, _with(good, "T4.3-1",
		{"cells": cells}), {"T4.3-1": {"cells": cells}}), "T4.3-1") == 7)
	var illegal := _illegal_rows()
	illegal[0]["signals"]["sel_add"] = 1
	ctx.check("4.3 非法码未全 0 → 红 E_OUTPUT_MISMATCH", _case_code(_run(cfg, _with(good, "T4.3-2",
		{"illegal": illegal}), {"T4.3-2": {"illegal": illegal}}), "T4.3-2") == 10)
	ctx.check("4.3 合法码亮两根 → 红", _case_code(_run(cfg, _with(good, "T4.3-3",
		{"legal": [{"opcode": 0, "lit": 2}, {"opcode": 1, "lit": 1},
		{"opcode": 2, "lit": 1}, {"opcode": 3, "lit": 1}]}), {"T4.3-3": {"legal": [{"opcode": 0, "lit": 2},
		{"opcode": 1, "lit": 1}, {"opcode": 2, "lit": 1}, {"opcode": 3, "lit": 1}]}}), "T4.3-3") == 10)
	ctx.check("4.3 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T4.3-4", 0)), "T4.3-4") == 14)

func _judge_memory(ctx: TestContext, cfg: Dictionary) -> void:
	var groups := []
	for i in 16:
		var v := (i * 3) & 255
		groups.append({"addr": i, "value": v, "read": v})
	var good := {
		"T4.4-1": {"groups": groups},
		"T4.4-2": {"low": {"addr": 0, "value": 7}, "high": {"addr": 511, "value": 9}, "decode": "cs"},
		"T4.4-3": {"addr": [{"bits": 8, "slots": 256}, {"bits": 9, "slots": 512},
			{"bits": 10, "slots": 1024}],
			"data": [{"bits": 8, "width": 8}, {"bits": 16, "width": 16}]},
		"T4.4-4": 1,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	ctx.begin_group("judge_memory")
	ctx.check("4.4 正确解全过", rep.all_required_passed(), str(rep.failure_codes()))
	for cid in ["T4.4-1", "T4.4-2", "T4.4-3", "T4.4-4"]:
		ctx.check("4.4 %s 绿" % cid, _case_ok(rep, cid))
	var bad_groups := groups.duplicate(true)
	bad_groups[3]["read"] = 0
	ctx.check("4.4 读回不一致 → 红 E_TRUTH_ROW", _case_code(_run(cfg, _with(good, "T4.4-1",
		{"groups": bad_groups}), {"T4.4-1": {"groups": bad_groups}}), "T4.4-1") == 6)
	ctx.check("4.4 高端地址错 → 红", _case_code(_run(cfg, _with(good, "T4.4-2",
		{"low": {"addr": 0, "value": 7}, "high": {"addr": 510, "value": 9}, "decode": "cs"}),
		{"T4.4-2": {"low": {"addr": 0, "value": 7}, "high": {"addr": 510, "value": 9}, "decode": "cs"}}),
		"T4.4-2") == 6)
	ctx.check("4.4 容量表一格错 → 红 E_TABLE_CELL", _case_code(_run(cfg, _with(good, "T4.4-3",
		{"addr": [{"bits": 8, "slots": 128}, {"bits": 9, "slots": 512}, {"bits": 10, "slots": 1024}],
		"data": [{"bits": 8, "width": 8}, {"bits": 16, "width": 16}]}),
		{"T4.4-3": {"addr": [{"bits": 8, "slots": 128}, {"bits": 9, "slots": 512},
		{"bits": 10, "slots": 1024}], "data": [{"bits": 8, "width": 8}, {"bits": 16, "width": 16}]}}),
		"T4.4-3") == 7)
	ctx.check("4.4 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T4.4-4", 0)), "T4.4-4") == 14)

func _judge_bus(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T4.5-1": {"drivers": [{"en": 1, "v": 1}, {"en": 1, "v": 0}], "line": "X", "reported": true},
		"T4.5-2": {"reads": _bus_reads()},
		"T4.5-3": {"mappings": [
			{"addr": 240, "port": "LED0", "lit": true},
			{"addr": 241, "port": "LED1", "lit": true},
			{"addr": 242, "port": "KBD", "lit": false},
			{"addr": 243, "port": "SND", "lit": false},
		]},
		"T4.5-4": 1,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	ctx.begin_group("judge_bus")
	ctx.check("4.5 正确解全过", rep.all_required_passed(), str(rep.failure_codes()))
	for cid in ["T4.5-1", "T4.5-2", "T4.5-3", "T4.5-4"]:
		ctx.check("4.5 %s 绿" % cid, _case_ok(rep, cid))
	ctx.check("4.5 争用却读回 0 → 红 E_X_ROW", _case_code(_run(cfg, _with(good, "T4.5-1",
		{"drivers": [{"en": 1, "v": 1}, {"en": 1, "v": 0}], "line": "0", "reported": true}),
		{"T4.5-1": {"drivers": [{"en": 1, "v": 1}, {"en": 1, "v": 0}], "line": "0", "reported": true}}),
		"T4.5-1") == 17)
	var bad_reads := _bus_reads()
	bad_reads[2]["value"] = 5
	ctx.check("4.5 器件读回错 → 红 E_TRUTH_ROW", _case_code(_run(cfg, _with(good, "T4.5-2",
		{"reads": bad_reads}), {"T4.5-2": {"reads": bad_reads}}), "T4.5-2") == 6)
	ctx.check("4.5 端口映射错 → 红 E_TABLE_CELL", _case_code(_run(cfg, _with(good, "T4.5-3",
		{"mappings": [{"addr": 240, "port": "LED1", "lit": true},
			{"addr": 241, "port": "LED1", "lit": true},
			{"addr": 242, "port": "KBD", "lit": false},
			{"addr": 243, "port": "SND", "lit": false}]}),
		{"T4.5-3": {"mappings": [{"addr": 240, "port": "LED1", "lit": true},
		{"addr": 241, "port": "LED1", "lit": true}, {"addr": 242, "port": "KBD", "lit": false},
		{"addr": 243, "port": "SND", "lit": false}]}}), "T4.5-3") == 7)
	ctx.check("4.5 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T4.5-4", 0)), "T4.5-4") == 14)

# ---------------------------------------------------------------- 工具

func _effective_segments(cfg: Dictionary) -> Array:
	var sections: Array = cfg.get("sections", [])
	if not sections.is_empty():
		return ["sections", sections]
	var body := str(cfg.get("body", ""))
	if body.is_empty():
		return ["empty", []]
	return ["body", [{"order": 1, "after": 0, "title": str(cfg.get("title", "")), "text": body}]]

func _mux_rows() -> Array:
	return [
		{"s": 0, "a": 0, "b": 0, "y": 0},
		{"s": 0, "a": 1, "b": 1, "y": 1},
		{"s": 1, "a": 0, "b": 0, "y": 0},
		{"s": 1, "a": 1, "b": 1, "y": 1},
	]

func _alu_results(cfg: Dictionary) -> Array:
	var out := []
	var sweep: Dictionary = {}
	for g in cfg.get("gate_cases", []):
		if str((g as Dictionary).get("kind", "")) == "alu_sweep":
			sweep = g
	for op in sweep.get("ops", []):
		for pair in sweep.get("operands", []):
			var a := int(pair[0])
			var b := int(pair[1])
			out.append({"op": str(op), "a": a, "b": b, "y": _alu(str(op), a, b)})
	return out

func _alu(op: String, a: int, b: int) -> int:
	match op:
		"add": return (a + b) & 255
		"sub": return (a - b) & 255
		"and": return a & b
		"or": return a | b
		"xor": return a ^ b
		"not": return (~a) & 255
		"shl": return (a << 1) & 255
		"shr": return a >> 1
	return -1

func _control_cells() -> Dictionary:
	return {
		"0": {"sel_add": 1, "sel_and": 0, "sel_or": 0, "sel_not": 0, "reg_we": 1},
		"1": {"sel_add": 0, "sel_and": 1, "sel_or": 0, "sel_not": 0, "reg_we": 1},
		"2": {"sel_add": 0, "sel_and": 0, "sel_or": 1, "sel_not": 0, "reg_we": 1},
		"3": {"sel_add": 0, "sel_and": 0, "sel_or": 0, "sel_not": 1, "reg_we": 1},
	}

func _illegal_rows() -> Array:
	var rows := []
	for op in [4, 5, 6, 7]:
		rows.append({"opcode": op, "signals": {"sel_add": 0, "sel_and": 0, "sel_or": 0,
			"sel_not": 0, "reg_we": 0}})
	return rows

func _bus_reads() -> Array:
	var rows := []
	for i in 8:
		rows.append({"dev": i, "en": 1, "value": i})
	return rows

func _run(cfg: Dictionary, answers: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var inputs := {"answers": answers}
	for k in extra:
		inputs[k] = extra[k]
	return Ch04.run(str(cfg.get("id", "")), cfg, inputs)

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

func _gate(labs: Dictionary, id: String) -> Dictionary:
	return (labs.get("labs", {}) as Dictionary).get(id, {})

func _required_count(cfg: Dictionary) -> int:
	var n := 0
	for raw in cfg.get("gate_cases", []):
		if bool((raw as Dictionary).get("required", false)):
			n += 1
	return n

func _counted(cfg: Dictionary) -> int:
	var n := 0
	for raw in cfg.get("gate_cases", []):
		var g: Dictionary = raw
		if bool(g.get("required", false)) and str(g.get("kind", "")) != "area_check":
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
		"mux": prefix = "T4.1-"
		"alu8": prefix = "T4.2-"
		"control_unit": prefix = "T4.3-"
		"memory": prefix = "T4.4-"
		"io_bus": prefix = "T4.5-"
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
